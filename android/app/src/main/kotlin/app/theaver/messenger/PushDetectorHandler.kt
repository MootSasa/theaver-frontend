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
                        val chatTitle = call.argument<String>("chat_title")
                        cancelChatNotifications(chatId, chatTitle)
                        result.success(true)
                    }
                    "cancelAllNotifications" -> {
                        cancelAllNotifications()
                        result.success(true)
                    }
                    "startKeepAliveService" -> {
                        KeepAliveService.start(context)
                        result.success(true)
                    }
                    "stopKeepAliveService" -> {
                        KeepAliveService.stop(context)
                        result.success(true)
                    }
                    "isKeepAliveServiceRunning" -> {
                        result.success(KeepAliveService.isServiceRunning())
                    }
                    "requestIgnoreBatteryOptimizations" -> {
                        requestIgnoreBatteryOptimizations()
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

    private fun cancelChatNotifications(chatId: String, chatTitle: String? = null) {
        if (chatId.isEmpty()) return
        try {
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as? android.app.NotificationManager ?: return
            val targetChatId = chatId.trim()
            val targetTitle = chatTitle?.trim()?.lowercase()

            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
                val active = nm.activeNotifications ?: return
                for (sbn in active) {
                    val rawTag = sbn.tag
                    val id = sbn.id
                    val notif = sbn.notification
                    val extras = notif?.extras

                    var match = false

                    // 1. Tag matching
                    if (rawTag != null) {
                        if (rawTag == "chat_$targetChatId" ||
                            rawTag.startsWith("chat_${targetChatId}_") ||
                            rawTag == targetChatId ||
                            rawTag.contains("chat_$targetChatId")) {
                            match = true
                        }
                    }

                    // 2. Extras matching (chat_id, data JSON, key search)
                    if (!match && extras != null) {
                        val extraChatId = extras.getString("chat_id") ?: extras.getString("chatId")
                        if (extraChatId != null && extraChatId == targetChatId) {
                            match = true
                        } else {
                            for (key in extras.keySet()) {
                                val value = extras.get(key)?.toString() ?: ""
                                if (value == targetChatId ||
                                    value.contains("\"chat_id\":\"$targetChatId\"") ||
                                    value.contains("\"chat_id\":$targetChatId")) {
                                    match = true
                                    break
                                }
                            }
                        }

                        // 3. Title matching (if chatTitle is supplied)
                        if (!match && !targetTitle.isNullOrEmpty()) {
                            val notifTitle = extras.getCharSequence(android.app.Notification.EXTRA_TITLE)?.toString()?.trim()?.lowercase()
                            if (notifTitle != null && (notifTitle == targetTitle || notifTitle.contains(targetTitle))) {
                                match = true
                            }
                        }
                    }

                    // 4. Fallback ID match (numeric ID == chatId)
                    if (!match) {
                        val numChatId = targetChatId.toIntOrNull()
                        if (numChatId != null && id == numChatId) {
                            match = true
                        }
                    }

                    if (match) {
                        if (rawTag != null) {
                            nm.cancel(rawTag, id)
                        } else {
                            nm.cancel(null, id)
                            nm.cancel(id)
                        }
                    }
                }
            } else {
                nm.cancel("chat_$targetChatId", 0)
                val num = targetChatId.toIntOrNull()
                if (num != null) nm.cancel(num)
            }
        } catch (_: Throwable) {}
    }

    private fun cancelAllNotifications() {
        try {
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as? android.app.NotificationManager ?: return
            nm.cancelAll()
        } catch (_: Throwable) {}
    }

    private fun requestIgnoreBatteryOptimizations() {
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
            try {
                val pm = context.getSystemService(Context.POWER_SERVICE) as? android.os.PowerManager
                val pkgName = context.packageName
                if (pm != null && !pm.isIgnoringBatteryOptimizations(pkgName)) {
                    val intent = android.content.Intent(android.provider.Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                        data = android.net.Uri.parse("package:$pkgName")
                        addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    context.startActivity(intent)
                }
            } catch (_: Throwable) {}
        }
    }
}
