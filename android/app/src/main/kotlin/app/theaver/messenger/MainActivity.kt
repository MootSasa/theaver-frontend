package app.theaver.messenger

import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.RectF
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.media.MediaMuxer
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Build
import android.net.Uri
import android.os.Environment
import android.provider.CalendarContract
import android.provider.MediaStore
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.nio.ByteBuffer

class MainActivity : FlutterFragmentActivity() {
    private val CHANNEL = "com.example.app/cutout"
    private val MUXER_CHANNEL = "com.example.app/media_muxer"
    private val CALENDAR_CHANNEL = "app.theaver.messenger/calendar"
    private val INSTALLER_CHANNEL = "app.theaver.messenger/installer"
    private val NETWORK_CHANNEL = "app.theaver.messenger/network"
    private var pendingApkPath: String? = null

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        enableHighRefreshRate()
    }

    override fun onResume() {
        super.onResume()
        enableHighRefreshRate()
        val path = pendingApkPath
        if (path != null) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O || packageManager.canRequestPackageInstalls()) {
                pendingApkPath = null
                try {
                    launchApkInstaller(File(path))
                } catch (_: Exception) {}
            }
        }
    }

    private fun enableHighRefreshRate() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            try {
                val display = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    this.display
                } else {
                    @Suppress("DEPRECATION")
                    windowManager.defaultDisplay
                } ?: return
                val modes = display.supportedModes
                val currentMode = display.mode
                val highestMode = modes
                    .filter {
                        it.physicalWidth == currentMode.physicalWidth &&
                            it.physicalHeight == currentMode.physicalHeight
                    }
                    .maxByOrNull { it.refreshRate }
                if (highestMode != null && highestMode.modeId != currentMode.modeId) {
                    val params = window.attributes
                    params.preferredDisplayModeId = highestMode.modeId
                    window.attributes = params
                }
            } catch (_: Exception) {}
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Register push detector MethodChannel handler
        val pushDetector = PushDetectorHandler(this)
        pushDetector.setup(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NETWORK_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "getNetworkType") {
                try {
                    val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
                    val activeNet = cm?.activeNetwork
                    val caps = if (activeNet != null) cm?.getNetworkCapabilities(activeNet) else null
                    val netType = when {
                        caps == null -> "none"
                        caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) ||
                            caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "wifi"
                        caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> {
                            val notRoaming = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                                caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_ROAMING)
                            } else {
                                @Suppress("DEPRECATION")
                                (cm?.activeNetworkInfo?.isRoaming != true)
                            }
                            if (!notRoaming) "roaming" else "cellular"
                        }
                        else -> "wifi"
                    }
                    result.success(netType)
                } catch (_: Exception) {
                    result.success("wifi")
                }
            } else {
                result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, INSTALLER_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "installApk" -> {
                    val filePath = call.argument<String>("filePath")
                    if (filePath.isNullOrEmpty()) {
                        result.error("INVALID_ARGS", "Missing filePath", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val file = File(filePath)
                        if (!file.exists() || file.length() <= 0L) {
                            result.error("FILE_NOT_FOUND", "APK file does not exist or is empty: $filePath", null)
                            return@setMethodCallHandler
                        }
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !packageManager.canRequestPackageInstalls()) {
                            pendingApkPath = filePath
                            val intent = Intent(
                                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                Uri.parse("package:$packageName")
                            ).apply {
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(intent)
                            result.success("permission_requested")
                        } else {
                            pendingApkPath = null
                            launchApkInstaller(file)
                            result.success("started")
                        }
                    } catch (e: Exception) {
                        result.error("INSTALL_ERROR", e.message, null)
                    }
                }
                "saveToDownloads" -> {
                    val sourcePath = call.argument<String>("sourcePath")
                    val fileName = call.argument<String>("fileName") ?: "file"
                    val mimeType = call.argument<String>("mimeType") ?: "application/octet-stream"
                    if (sourcePath.isNullOrEmpty()) {
                        result.error("INVALID_ARGS", "Missing sourcePath", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val srcFile = File(sourcePath)
                        if (!srcFile.exists()) {
                            result.error("FILE_NOT_FOUND", "Source file not found", null)
                            return@setMethodCallHandler
                        }
                        val savedLocation = saveFileToPublicDownloads(srcFile, fileName, mimeType)
                        result.success(savedLocation)
                    } catch (e: Exception) {
                        result.error("SAVE_ERROR", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CALENDAR_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "addBirthdayEvent") {
                try {
                    val title = call.argument<String>("title") ?: "Birthday"
                    val description = call.argument<String>("description") ?: ""
                    val chooserTitle = call.argument<String>("chooserTitle") ?: title
                    val beginTime = (call.argument<Number>("beginTimeMillis")
                        ?: call.argument<Number>("beginTime"))?.toLong()
                        ?: System.currentTimeMillis()
                    val endTime = (call.argument<Number>("endTimeMillis")
                        ?: call.argument<Number>("endTime"))?.toLong()
                        ?: (beginTime + 86400000L)

                    val intent = Intent(Intent.ACTION_INSERT).apply {
                        setDataAndType(
                            CalendarContract.Events.CONTENT_URI,
                            "vnd.android.cursor.dir/event"
                        )
                        putExtra(CalendarContract.Events.TITLE, title)
                        putExtra(CalendarContract.Events.DESCRIPTION, description)
                        putExtra(CalendarContract.EXTRA_EVENT_ALL_DAY, true)
                        putExtra(CalendarContract.EXTRA_EVENT_BEGIN_TIME, beginTime)
                        putExtra(CalendarContract.EXTRA_EVENT_END_TIME, endTime)
                        putExtra(CalendarContract.Events.RRULE, "FREQ=YEARLY")
                    }
                    startActivity(Intent.createChooser(intent, chooserTitle))
                    result.success(true)
                } catch (e: Exception) {
                    result.success(false)
                }
            } else {
                result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "getCutoutInfo") {
                val cutoutInfo = getDisplayCutout()
                result.success(cutoutInfo)
            } else {
                result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, MUXER_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "mux") {
                val videoPath = call.argument<String>("videoPath")
                val audioPath = call.argument<String>("audioPath")
                val outputPath = call.argument<String>("outputPath")
                if (videoPath != null && audioPath != null && outputPath != null) {
                    try {
                        val ok = muxVideoAndAudio(videoPath, audioPath, outputPath)
                        result.success(ok)
                    } catch (e: Exception) {
                        result.error("MUX_ERROR", e.message, null)
                    }
                } else {
                    result.error("INVALID_ARGS", "Missing paths", null)
                }
            } else if (call.method == "getVideoThumbnail") {
                val videoPath = call.argument<String>("videoPath")
                if (videoPath != null) {
                    try {
                        val retriever = MediaMetadataRetriever()
                        retriever.setDataSource(videoPath)
                        val bitmap = retriever.getFrameAtTime(0, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                        val widthStr = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)
                        val heightStr = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)
                        val durStr = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                        val rotationStr = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)
                        
                        var w = widthStr?.toIntOrNull() ?: 0
                        var h = heightStr?.toIntOrNull() ?: 0
                        val rot = rotationStr?.toIntOrNull() ?: 0
                        if (rot == 90 || rot == 270) {
                            val tmp = w
                            w = h
                            h = tmp
                        }
                        val durMs = durStr?.toLongOrNull() ?: 0L
                        val durSec = (durMs / 1000L).toInt()

                        var thumbBytes: ByteArray? = null
                        if (bitmap != null) {
                            val stream = ByteArrayOutputStream()
                            bitmap.compress(Bitmap.CompressFormat.JPEG, 60, stream)
                            thumbBytes = stream.toByteArray()
                        }
                        retriever.release()

                        result.success(mapOf(
                            "thumbnail" to thumbBytes,
                            "width" to w,
                            "height" to h,
                            "duration" to durSec
                        ))
                    } catch (e: Exception) {
                        result.success(null)
                    }
                } else {
                    result.error("INVALID_ARGS", "Missing videoPath", null)
                }
            } else {
                result.notImplemented()
            }
        }
    }

    private fun muxVideoAndAudio(videoPath: String, audioPath: String, outputPath: String): Boolean {
        var videoExtractor: MediaExtractor? = null
        var audioExtractor: MediaExtractor? = null
        var muxer: MediaMuxer? = null

        try {
            videoExtractor = MediaExtractor()
            videoExtractor.setDataSource(videoPath)
            var videoTrackIndex = -1
            for (i in 0 until videoExtractor.trackCount) {
                val format = videoExtractor.getTrackFormat(i)
                val mime = format.getString(MediaFormat.KEY_MIME) ?: ""
                if (mime.startsWith("video/")) {
                    videoExtractor.selectTrack(i)
                    videoTrackIndex = i
                    break
                }
            }

            audioExtractor = MediaExtractor()
            audioExtractor.setDataSource(audioPath)
            var audioTrackIndex = -1
            for (i in 0 until audioExtractor.trackCount) {
                val format = audioExtractor.getTrackFormat(i)
                val mime = format.getString(MediaFormat.KEY_MIME) ?: ""
                if (mime.startsWith("audio/")) {
                    audioExtractor.selectTrack(i)
                    audioTrackIndex = i
                    break
                }
            }

            if (videoTrackIndex == -1 || audioTrackIndex == -1) {
                return false
            }

            muxer = MediaMuxer(outputPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            val muxerVideoTrack = muxer.addTrack(videoExtractor.getTrackFormat(videoTrackIndex))
            val muxerAudioTrack = muxer.addTrack(audioExtractor.getTrackFormat(audioTrackIndex))
            muxer.start()

            val buffer = ByteBuffer.allocate(1024 * 1024)
            val bufferInfo = MediaCodec.BufferInfo()

            var videoDone = false
            var audioDone = false

            while (!videoDone || !audioDone) {
                val videoTime = if (!videoDone) videoExtractor.sampleTime else Long.MAX_VALUE
                val audioTime = if (!audioDone) audioExtractor.sampleTime else Long.MAX_VALUE

                if (!videoDone && (audioDone || videoTime <= audioTime)) {
                    bufferInfo.size = videoExtractor.readSampleData(buffer, 0)
                    if (bufferInfo.size >= 0) {
                        bufferInfo.presentationTimeUs = videoExtractor.sampleTime
                        bufferInfo.flags = videoExtractor.sampleFlags
                        muxer.writeSampleData(muxerVideoTrack, buffer, bufferInfo)
                        videoExtractor.advance()
                    } else {
                        videoDone = true
                    }
                } else if (!audioDone) {
                    bufferInfo.size = audioExtractor.readSampleData(buffer, 0)
                    if (bufferInfo.size >= 0) {
                        bufferInfo.presentationTimeUs = audioExtractor.sampleTime
                        bufferInfo.flags = audioExtractor.sampleFlags
                        muxer.writeSampleData(muxerAudioTrack, buffer, bufferInfo)
                        audioExtractor.advance()
                    } else {
                        audioDone = true
                    }
                }
            }

            return true
        } catch (e: Exception) {
            return false
        } finally {
            try { muxer?.stop() } catch (e: Exception) {}
            try { muxer?.release() } catch (e: Exception) {}
            try { videoExtractor?.release() } catch (e: Exception) {}
            try { audioExtractor?.release() } catch (e: Exception) {}
        }
    }

    private fun getDisplayCutout(): List<Map<String, Float>> {
        val cutoutList = mutableListOf<Map<String, Float>>()
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            val windowInsets = window.decorView.rootWindowInsets
            val displayCutout = windowInsets?.displayCutout
            
            if (displayCutout != null) {
                val density = resources.displayMetrics.density

                // Пытаемся получить точный контур (только для Android 11+)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    val path = displayCutout.cutoutPath
                    if (path != null) {
                        val pathBounds = RectF()
                        // Вычисляем реальный прямоугольник вокруг самого векторного выреза
                        path.computeBounds(pathBounds, true)
                        
                        if (!pathBounds.isEmpty) {
                            cutoutList.add(mapOf(
                                "left" to pathBounds.left / density,
                                "top" to pathBounds.top / density,
                                "right" to pathBounds.right / density,
                                "bottom" to pathBounds.bottom / density,
                                "width" to pathBounds.width() / density,
                                "height" to pathBounds.height() / density
                            ))
                            return cutoutList
                        }
                    }
                }

                // Фоллбэк для старых версий (Android 9 и 10) или если Path не задан
                for (rect in displayCutout.boundingRects) {
                    cutoutList.add(mapOf(
                        "left" to rect.left / density,
                        "top" to rect.top / density,
                        "right" to rect.right / density,
                        "bottom" to rect.bottom / density,
                        "width" to rect.width().toFloat() / density,
                        "height" to rect.height().toFloat() / density
                    ))
                }
            }
        }
        return cutoutList
    }

    private fun launchApkInstaller(file: File) {
        val apkUri: Uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
        } else {
            Uri.fromFile(file)
        }

        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(apkUri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        startActivity(intent)
    }

    private fun saveFileToPublicDownloads(srcFile: File, fileName: String, mimeType: String): String {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = android.content.ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, fileName)
                put(MediaStore.Downloads.MIME_TYPE, mimeType)
                put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
                put(MediaStore.Downloads.IS_PENDING, 1)
            }
            val resolver = applicationContext.contentResolver
            val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: throw IllegalStateException("Failed to create MediaStore Downloads entry")
            resolver.openOutputStream(uri)?.use { out ->
                srcFile.inputStream().use { input ->
                    input.copyTo(out)
                }
            } ?: throw IllegalStateException("Failed to open MediaStore output stream")
            values.clear()
            values.put(MediaStore.Downloads.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
            return "/storage/emulated/0/Download/$fileName"
        } else {
            val downloadsDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
            if (!downloadsDir.exists()) {
                downloadsDir.mkdirs()
            }
            var destFile = File(downloadsDir, fileName)
            val dotIdx = fileName.lastIndexOf('.')
            val baseName = if (dotIdx != -1) fileName.substring(0, dotIdx) else fileName
            val ext = if (dotIdx != -1) fileName.substring(dotIdx) else ""
            var counter = 1
            while (destFile.exists()) {
                destFile = File(downloadsDir, "${baseName}_$counter$ext")
                counter++
            }
            srcFile.copyTo(destFile, overwrite = true)
            return destFile.absolutePath
        }
    }
}
