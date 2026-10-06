package app.theaver.messenger

import android.graphics.Bitmap
import android.graphics.RectF
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.media.MediaMuxer
import android.os.Build
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer

class MainActivity : FlutterFragmentActivity() {
    private val CHANNEL = "com.example.app/cutout"
    private val MUXER_CHANNEL = "com.example.app/media_muxer"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Register push detector MethodChannel handler
        val pushDetector = PushDetectorHandler(this)
        pushDetector.setup(flutterEngine)

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
}
