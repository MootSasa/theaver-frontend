package app.theaver.messenger.notifications

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.core.app.RemoteInput
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.util.UUID

/**
 * Handles "Ответить" / "Прочитано" / dismiss of chat notifications natively, so the
 * actions work for every notification (foreground or push) even when Flutter is not
 * running. Uses the API base URL and auth token provided by Flutter via
 * [NativeNotificationsChannel] ("configure").
 */
class NotificationActionReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val chatId = intent.getStringExtra(ChatNotificationRenderer.EXTRA_CHAT_ID).orEmpty()
        if (chatId.isEmpty()) return
        val appContext = context.applicationContext
        when (intent.action) {
            ACTION_DISMISSED -> {
                // User swiped the conversation away: start a fresh history next time.
                NotificationStore(appContext).clearChat(chatId)
                return
            }
            ChatNotificationRenderer.ACTION_REPLY, ChatNotificationRenderer.ACTION_MARK_READ -> Unit
            else -> return
        }

        val replyText = RemoteInput.getResultsFromIntent(intent)
            ?.getCharSequence(ChatNotificationRenderer.KEY_REPLY_TEXT)
            ?.toString()
            ?.trim()
            .orEmpty()
        val action = intent.action
        val pending = goAsync()
        Thread {
            try {
                val store = NotificationStore(appContext)
                val base = store.baseUrl.trimEnd('/')
                val token = store.authToken
                if (base.isEmpty() || token.isEmpty()) {
                    Log.w(TAG, "not configured (no base URL / token)")
                    if (action == ChatNotificationRenderer.ACTION_REPLY && replyText.isNotEmpty()) {
                        ChatNotificationRenderer.appendOwnReply(appContext, chatId, "⚠️ Не отправлено: $replyText")
                    }
                    return@Thread
                }
                if (action == ChatNotificationRenderer.ACTION_REPLY) {
                    if (replyText.isEmpty()) {
                        ChatNotificationRenderer.appendOwnReply(appContext, chatId, "")
                        return@Thread
                    }
                    val body = JSONObject().apply {
                        put("content", replyText)
                        put("message_type", "text")
                        put("local_id", UUID.randomUUID().toString())
                    }
                    val sent = post("$base/api/chats/$chatId/messages", token, body.toString())
                    if (sent) {
                        post("$base/api/chats/$chatId/messages/read", token, null)
                        ChatNotificationRenderer.appendOwnReply(appContext, chatId, replyText)
                    } else {
                        ChatNotificationRenderer.appendOwnReply(appContext, chatId, "⚠️ Не отправлено: $replyText")
                    }
                } else {
                    post("$base/api/chats/$chatId/messages/read", token, null)
                    ChatNotificationRenderer.cancelChat(appContext, chatId)
                }
            } catch (e: Throwable) {
                Log.e(TAG, "action failed", e)
            } finally {
                pending.finish()
            }
        }.start()
    }

    private fun post(url: String, token: String, json: String?): Boolean {
        val conn = (URL(url).openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            connectTimeout = 10_000
            readTimeout = 10_000
            setRequestProperty("Authorization", "Bearer $token")
            setRequestProperty("Content-Type", "application/json")
            doOutput = json != null
        }
        return try {
            if (json != null) conn.outputStream.use { it.write(json.toByteArray(Charsets.UTF_8)) }
            val code = conn.responseCode
            if (code !in 200..299) Log.w(TAG, "POST $url -> $code")
            code in 200..299
        } catch (e: Throwable) {
            Log.w(TAG, "POST $url failed: ${e.message}")
            false
        } finally {
            conn.disconnect()
        }
    }

    companion object {
        private const val TAG = "NotifActionReceiver"
        const val ACTION_DISMISSED = "app.theaver.messenger.notifications.DISMISSED"
    }
}
