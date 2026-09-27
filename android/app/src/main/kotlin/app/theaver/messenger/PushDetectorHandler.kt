package app.theaver.messenger

import android.content.Context
import android.content.pm.PackageManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * MethodChannel handler for push service detection.
 * 
 * Detects availability of:
 * - Google Play Services (GMS) → FCM
 * - HMS Core → Huawei Push Kit
 * 
 * Uses PackageManager instead of SDK classes to avoid
 * compile-time dependencies on GMS/HMS libraries.
 */
class PushDetectorHandler(private val context: Context) {

    companion object {
        private const val PUSH_DETECTOR_CHANNEL = "app.theaver.messenger/push_detector"
        private const val HMS_PUSH_CHANNEL = "app.theaver.messenger/hms_push"
    }

    fun setup(flutterEngine: FlutterEngine) {
        // Push detector channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PUSH_DETECTOR_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isGmsAvailable" -> {
                        result.success(isGmsAvailable())
                    }
                    "isHmsAvailable" -> {
                        result.success(isHmsAvailable())
                    }
                    "isHuaweiDevice" -> {
                        result.success(isHuaweiDevice())
                    }
                    "cancelChatNotifications" -> {
                        val chatId = call.argument<String>("chat_id") ?: ""
                        cancelChatNotifications(chatId)
                        result.success(true)
                    }
                    "cancelAllNotifications" -> {
                        cancelAllNotifications()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }

        // HMS Push channel (placeholder — actual HMS Push handled by Flutter plugin)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, HMS_PUSH_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestPermission" -> result.success(true)
                    "getToken" -> result.success(null)
                    "deleteToken" -> result.success(true)
                    "subscribeToTopic" -> result.success(true)
                    "unsubscribeFromTopic" -> result.success(true)
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Check if Google Play Services are available on this device.
     * Uses GoogleApiAvailability via reflection, and blocks false positives on Huawei devices.
     */
    private fun isGmsAvailable(): Boolean {
        val isHuawei = isHuaweiDevice()

        // 1. Check via GoogleApiAvailability (ConnectionResult.SUCCESS = 0)
        try {
            val clazz = Class.forName("com.google.android.gms.common.GoogleApiAvailability")
            val getInstanceMethod = clazz.getMethod("getInstance")
            val instance = getInstanceMethod.invoke(null)
            val isAvailableMethod = clazz.getMethod("isGooglePlayServicesAvailable", Context::class.java)
            val statusCode = isAvailableMethod.invoke(instance, context) as? Int ?: -1
            if (statusCode == 0) {
                // If Google Play Services is actually functional, allow GMS
                // UNLESS it's a Huawei device where HMS Core is installed and should take priority
                if (isHuawei && isHmsAvailable()) {
                    return false
                }
                return true
            }
            return false
        } catch (_: Throwable) {
            // GoogleApiAvailability class not found or reflection failed
        }

        // 2. Fallback check for non-Huawei devices
        if (isHuawei) return false
        return try {
            val pm = context.packageManager
            val info = pm.getPackageInfo("com.google.android.gms", 0)
            info.applicationInfo?.enabled == true
        } catch (_: Throwable) {
            false
        }
    }

    /**
     * Check if HMS Core is available on this device.
     * Uses HuaweiApiAvailability via reflection, with fallbacks to package check.
     */
    private fun isHmsAvailable(): Boolean {
        // 1. Check via HuaweiApiAvailability (ConnectionResult.SUCCESS = 0)
        try {
            val clazz = Class.forName("com.huawei.hms.api.HuaweiApiAvailability")
            val getInstanceMethod = clazz.getMethod("getInstance")
            val instance = getInstanceMethod.invoke(null)
            val isAvailableMethod = clazz.getMethod("isHuaweiMobileServicesAvailable", Context::class.java)
            val statusCode = isAvailableMethod.invoke(instance, context) as? Int ?: -1
            if (statusCode == 0) {
                return true
            }
        } catch (_: Throwable) {
            // HuaweiApiAvailability class not found or reflection failed
        }

        // 2. Fallback: check PackageManager for com.huawei.hwid
        try {
            val pm = context.packageManager
            val info = pm.getPackageInfo("com.huawei.hwid", 0)
            if (info.applicationInfo?.enabled == true) {
                return true
            }
        } catch (_: Throwable) {}

        // 3. Fallback: if it's a Huawei/Honor device, assume HMS capability
        return isHuaweiDevice()
    }

    /**
     * Check if the device is manufactured by Huawei or Honor.
     */
    private fun isHuaweiDevice(): Boolean {
        val manufacturer = android.os.Build.MANUFACTURER.lowercase()
        val brand = android.os.Build.BRAND.lowercase()
        return manufacturer.contains("huawei") || brand.contains("huawei") || brand.contains("honor")
    }

    private fun cancelChatNotifications(chatId: String) {
        if (chatId.isEmpty()) return
        try {
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as? android.app.NotificationManager ?: return
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
                val active = nm.activeNotifications ?: return
                for (sbn in active) {
                    val tag = sbn.tag ?: ""
                    val id = sbn.id
                    if (tag == "chat_$chatId" || tag.startsWith("chat_${chatId}_") || tag == chatId) {
                        nm.cancel(tag, id)
                    }
                }
            } else {
                nm.cancel("chat_$chatId", 0)
            }
        } catch (_: Throwable) {}
    }

    private fun cancelAllNotifications() {
        try {
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as? android.app.NotificationManager ?: return
            nm.cancelAll()
        } catch (_: Throwable) {}
    }
}
