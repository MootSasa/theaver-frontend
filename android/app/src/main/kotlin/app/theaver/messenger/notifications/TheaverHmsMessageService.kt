package app.theaver.messenger.notifications

import com.huawei.hms.flutter.push.hms.FlutterHmsMessageService
import com.huawei.hms.push.RemoteMessage

/**
 * Replaces the huawei_push plugin service (see AndroidManifest `tools:node="remove"`).
 * Chat-message data pushes are rendered natively by [ChatNotificationRenderer] —
 * this avoids the plugin's background-isolate path, which drops data messages once
 * the process is alive but no Dart listener is attached. Other messages (calls,
 * sync) and token callbacks are handled by the plugin as before.
 */
class TheaverHmsMessageService : FlutterHmsMessageService() {
    override fun onMessageReceived(remoteMessage: RemoteMessage?) {
        val data: Map<String, String> = try {
            remoteMessage?.dataOfMap ?: emptyMap()
        } catch (_: Throwable) {
            emptyMap()
        }
        if (data.isNotEmpty() && ChatNotificationRenderer.handlePush(applicationContext, data)) {
            return
        }
        super.onMessageReceived(remoteMessage)
    }
}
