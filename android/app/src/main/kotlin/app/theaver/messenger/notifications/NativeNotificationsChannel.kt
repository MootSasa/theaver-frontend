package app.theaver.messenger.notifications

import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Flutter <-> native bridge for chat notifications
 * (channel "app.theaver.messenger/native_notifications").
 *
 * Dart -> native:
 *  - configure {base_url, storage_url, token, user_id}
 *  - setState {foreground, active_chat_ids, foreground_enabled}
 *  - showChatNotification {…push-style payload…}
 *  - cancelChat {chat_id}, cancelAll
 *  - getInitialTap -> JSON payload of the notification that launched the app (or null)
 *  - openAutoStartSettings -> opens Huawei/Honor "App launch" settings
 * Native -> Dart:
 *  - onNotificationTap {payload}
 */
object NativeNotificationsChannel {
    private const val CHANNEL = "app.theaver.messenger/native_notifications"

    private var channel: MethodChannel? = null
    private var pendingTapPayload: String? = null
    private val main = Handler(Looper.getMainLooper())

    fun register(engine: FlutterEngine, context: Context) {
        val appContext = context.applicationContext
        val ch = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
        channel = ch
        ch.setMethodCallHandler { call, result ->
            val store = NotificationStore(appContext)
            when (call.method) {
                "configure" -> {
                    call.argument<String>("base_url")?.let { store.baseUrl = it }
                    call.argument<String>("storage_url")?.let { store.storageUrl = it }
                    store.authToken = call.argument<String>("token") ?: ""
                    store.userId = call.argument<String>("user_id") ?: ""
                    result.success(null)
                }
                "setState" -> {
                    store.appInForeground = call.argument<Boolean>("foreground") ?: false
                    store.foregroundNotificationsEnabled = call.argument<Boolean>("foreground_enabled") ?: true
                    store.activeChatIds = (call.argument<List<String>>("active_chat_ids") ?: emptyList()).toSet()
                    result.success(null)
                }
                "showChatNotification" -> {
                    val args = call.arguments as? Map<*, *>
                    if (args == null) {
                        result.success(false)
                    } else {
                        val data = HashMap<String, String>()
                        args.forEach { (k, v) -> if (k != null && v != null) data[k.toString()] = v.toString() }
                        ChatNotificationRenderer.showFromApp(appContext, data)
                        result.success(true)
                    }
                }
                "cancelChat" -> {
                    val chatId = call.argument<String>("chat_id").orEmpty()
                    if (chatId.isNotEmpty()) ChatNotificationRenderer.cancelChat(appContext, chatId)
                    result.success(null)
                }
                "cancelAll" -> {
                    ChatNotificationRenderer.cancelAll(appContext)
                    result.success(null)
                }
                "getInitialTap" -> {
                    result.success(pendingTapPayload)
                    pendingTapPayload = null
                }
                "openAutoStartSettings" -> result.success(AutoStartSettings.open(appContext))
                else -> result.notImplemented()
            }
        }
    }

    /** Called by MainActivity for launch / new intents. */
    fun handleIntent(intent: Intent?) {
        val payload = intent?.getStringExtra(ChatNotificationRenderer.EXTRA_TAP_PAYLOAD) ?: return
        intent.removeExtra(ChatNotificationRenderer.EXTRA_TAP_PAYLOAD)
        val ch = channel
        if (ch == null) {
            pendingTapPayload = payload
            return
        }
        // Keep it for getInitialTap too (cold start: Dart may not be listening yet).
        pendingTapPayload = payload
        main.post {
            ch.invokeMethod("onNotificationTap", mapOf("payload" to payload), object : MethodChannel.Result {
                override fun success(result: Any?) {
                    if (result == true) pendingTapPayload = null
                }
                override fun error(code: String, msg: String?, details: Any?) {}
                override fun notImplemented() {}
            })
        }
    }
}
