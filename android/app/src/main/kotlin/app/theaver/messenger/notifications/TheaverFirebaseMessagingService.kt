package app.theaver.messenger.notifications

import com.google.firebase.messaging.RemoteMessage
import io.flutter.plugins.firebase.messaging.FlutterFirebaseMessagingService

/**
 * Replaces the firebase_messaging service (see AndroidManifest `tools:node="remove"`).
 * Chat-message data pushes are rendered natively by [ChatNotificationRenderer];
 * everything else (calls, tokens) keeps flowing through the Flutter plugin, whose
 * broadcast receiver delivers messages to Dart independently of this service.
 */
class TheaverFirebaseMessagingService : FlutterFirebaseMessagingService() {
    override fun onMessageReceived(remoteMessage: RemoteMessage) {
        if (ChatNotificationRenderer.handlePush(applicationContext, remoteMessage.data)) {
            return
        }
        super.onMessageReceived(remoteMessage)
    }
}
