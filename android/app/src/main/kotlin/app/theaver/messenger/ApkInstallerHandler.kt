package app.theaver.messenger

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Handles in-app APK installation on Android via FileProvider, including requesting
 * REQUEST_INSTALL_PACKAGES permission on Android 8+ and resuming once granted.
 */
object ApkInstallerHandler {
    private const val CHANNEL = "app.theaver.messenger/installer"

    @Volatile
    private var pendingApkPath: String? = null

    fun register(flutterEngine: FlutterEngine, context: Context) {
        val appContext = context.applicationContext
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method != "installApk") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val filePath = call.argument<String>("filePath")?.trim().orEmpty()
                if (filePath.isEmpty()) {
                    result.error("INVALID_ARGS", "filePath is required", null)
                    return@setMethodCallHandler
                }
                val file = File(filePath)
                if (!file.exists()) {
                    result.error("FILE_NOT_FOUND", "APK file not found: $filePath", null)
                    return@setMethodCallHandler
                }

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                    !appContext.packageManager.canRequestPackageInstalls()
                ) {
                    pendingApkPath = filePath
                    try {
                        val settingsIntent = Intent(
                            Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                            Uri.parse("package:${appContext.packageName}"),
                        ).apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        appContext.startActivity(settingsIntent)
                        result.success("PERMISSION_REQUESTED")
                    } catch (e: Throwable) {
                        pendingApkPath = null
                        result.error("PERMISSION_INTENT_FAILED", e.message, null)
                    }
                    return@setMethodCallHandler
                }

                try {
                    launchInstaller(appContext, file)
                    pendingApkPath = null
                    result.success("LAUNCHED")
                } catch (e: Throwable) {
                    result.error("INSTALL_LAUNCH_FAILED", e.message, null)
                }
            }
    }

    fun onActivityResume(context: Context) {
        val path = pendingApkPath ?: return
        val appContext = context.applicationContext
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !appContext.packageManager.canRequestPackageInstalls()
        ) {
            return
        }
        pendingApkPath = null
        val file = File(path)
        if (!file.exists()) return
        try {
            launchInstaller(appContext, file)
        } catch (_: Throwable) {
        }
    }

    private fun launchInstaller(context: Context, file: File) {
        val authority = "${context.packageName}.fileprovider"
        val apkUri = FileProvider.getUriForFile(context, authority, file)
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(apkUri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        context.startActivity(intent)
    }
}
