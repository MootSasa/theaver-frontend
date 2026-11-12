package app.theaver.messenger.notifications

import android.annotation.SuppressLint
import android.app.ActivityManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.graphics.Rect
import android.graphics.RectF
import android.os.Build
import android.os.Looper
import android.util.Base64
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.Person
import androidx.core.app.RemoteInput
import androidx.core.content.pm.ShortcutInfoCompat
import androidx.core.content.pm.ShortcutManagerCompat
import androidx.core.graphics.drawable.IconCompat
import app.theaver.messenger.MainActivity
import app.theaver.messenger.R
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/**
 * The single renderer of chat-message notifications on Android.
 *
 * Every message notification — from the WebSocket while the app is open, or from an
 * FCM/HMS data push while it is backgrounded/killed — goes through [show], so all of
 * them look the same:
 *  - one conversation notification per chat (tag `chat_<id>`), MessagingStyle with the
 *    recent history (grouped, not only the last message);
 *  - the chat avatar instead of the app icon (conversation shortcut on Android 11+,
 *    large icon / person icons on older versions; initials if there is no avatar);
 *  - "Ответить" (inline reply) and "Прочитано" actions handled natively by
 *    [NotificationActionReceiver], even when Flutter is not running;
 *  - a group summary when several chats have notifications.
 */
object ChatNotificationRenderer {

    private const val TAG = "ChatNotifRenderer"
    const val GROUP_KEY = "app.theaver.messenger.MESSAGES"
    private const val SUMMARY_TAG = "messages_summary"
    private const val SUMMARY_ID = 1
    private const val ACCENT = 0xFF5B7FFF.toInt()

    const val ACTION_REPLY = "app.theaver.messenger.notifications.REPLY"
    const val ACTION_MARK_READ = "app.theaver.messenger.notifications.MARK_READ"
    const val EXTRA_CHAT_ID = "chat_id"
    const val KEY_REPLY_TEXT = "reply_text"
    const val EXTRA_TAP_PAYLOAD = "theaver_notification_payload"

    private val executor = Executors.newSingleThreadExecutor()

    fun tagFor(chatId: String) = "chat_$chatId"

    // ======================= Entry points =======================

    /**
     * Handles an FCM/HMS data push. Returns true if the message type is owned by the
     * native renderer (it must then not be rendered again by Flutter).
     */
    fun handlePush(context: Context, data: Map<String, String>): Boolean {
        return when (data["type"]) {
            "new_message" -> {
                if (data["message_type"] == "call") return true
                runBlockingIfPossible { show(context, data, fromPush = true) }
                true
            }
            "read_status_updated" -> {
                val chatId = data["chat_id"].orEmpty()
                if (chatId.isNotEmpty()) cancelChat(context, chatId)
                true
            }
            else -> false
        }
    }

    /** Called from Flutter for WebSocket messages (decision already made in Dart). */
    fun showFromApp(context: Context, data: Map<String, String>) {
        executor.execute { show(context, data, fromPush = false) }
    }

    /**
     * Runs [block] on the current thread when it is a worker thread (FCM/HMS services
     * deliver on a background thread and the process may die right after return);
     * on the main thread it hands off to the executor and waits briefly.
     */
    private fun runBlockingIfPossible(block: () -> Unit) {
        if (Looper.myLooper() != Looper.getMainLooper()) {
            block()
            return
        }
        val latch = CountDownLatch(1)
        executor.execute {
            try {
                block()
            } finally {
                latch.countDown()
            }
        }
        try {
            latch.await(8, TimeUnit.SECONDS)
        } catch (_: InterruptedException) {
        }
    }

    // ======================= Rendering =======================

    private fun show(context: Context, data: Map<String, String>, fromPush: Boolean) {
        try {
            val store = NotificationStore(context)
            val chatId = data["chat_id"].orEmpty()
            if (chatId.isEmpty()) return

            val senderId = data["sender_id"].orEmpty()
            if (senderId.isNotEmpty() && senderId == store.userId) return

            if (fromPush && store.appInForeground && isProcessForeground()) {
                // The app renders foreground notifications from the WebSocket itself.
                if (!store.foregroundNotificationsEnabled || store.activeChatIds.contains(chatId)) return
            }

            val messageId = data["id"] ?: data["message_id"] ?: ""
            val text = data["message_text"]?.takeIf { it.isNotBlank() } ?: "Новое сообщение"
            if (messageId.isNotEmpty()) {
                if (store.checkAndMarkShown("msg:$chatId:$messageId")) return
            } else if (store.checkAndMarkShown("msg:$chatId:t:${text.hashCode()}")) {
                return
            }

            val chatType = data["chat_type"].orEmpty()
            val isChannel = chatType == "channel" || data["is_channel"] == "true"
            val isGroup = !isChannel && (data["is_group"] == "true" || chatType == "group")
            val chatName = data["chat_name"]?.takeIf { it.isNotBlank() } ?: data["sender_name"] ?: "Theaver"
            val senderName = data["sender_name"].orEmpty()

            // Avatars may be missing in one of the sources (WebSocket / FCM / HMS):
            // remember the last known ones so every notification shows an avatar.
            val senderAvatarFromData = data["sender_avatar_url"].orEmpty()
            val chatAvatarUrl = data["avatar_url"].orEmpty()
                .ifEmpty { if (!isGroup && !isChannel) senderAvatarFromData else "" }
                .ifEmpty { store.knownAvatar("chat:$chatId") }
            if (chatAvatarUrl.isNotEmpty()) store.rememberAvatar("chat:$chatId", chatAvatarUrl)
            val senderAvatarUrl = if (isGroup) {
                senderAvatarFromData.ifEmpty { if (senderId.isNotEmpty()) store.knownAvatar("user:$senderId") else "" }
            } else {
                chatAvatarUrl
            }
            if (senderId.isNotEmpty() && senderAvatarUrl.isNotEmpty()) store.rememberAvatar("user:$senderId", senderAvatarUrl)
            val resolved = if (chatAvatarUrl == data["avatar_url"]) data else HashMap(data).apply { put("avatar_url", chatAvatarUrl) }

            store.saveChatMeta(chatId, resolved)
            val history = store.appendHistory(
                chatId,
                NotificationStore.HistoryEntry(
                    text = text,
                    senderName = if (isGroup) senderName else chatName,
                    senderKey = senderId.ifEmpty { senderName.ifEmpty { chatName } },
                    avatarUrl = senderAvatarUrl,
                    timestamp = System.currentTimeMillis(),
                    isOwn = false,
                    messageId = messageId,
                )
            )
            post(context, store, resolved, chatId, chatName, isGroup, isChannel, history, silentUpdate = false)
        } catch (e: Throwable) {
            Log.e(TAG, "show failed", e)
        }
    }

    /** Re-renders the chat after an inline reply (adds "Вы: …" without alerting). */
    fun appendOwnReply(context: Context, chatId: String, text: String) {
        try {
            val store = NotificationStore(context)
            val meta = store.readChatMeta(chatId) ?: return
            val chatType = meta["chat_type"].orEmpty()
            val isChannel = chatType == "channel" || meta["is_channel"] == "true"
            val isGroup = !isChannel && (meta["is_group"] == "true" || chatType == "group")
            val chatName = meta["chat_name"]?.takeIf { it.isNotBlank() } ?: "Theaver"
            val history = if (text.isEmpty()) {
                // Nothing to add (empty reply): re-render to stop the reply spinner.
                store.readHistory(chatId)
            } else store.appendHistory(
                chatId,
                NotificationStore.HistoryEntry(
                    text = text,
                    senderName = "Вы",
                    senderKey = "me",
                    avatarUrl = "",
                    timestamp = System.currentTimeMillis(),
                    isOwn = true,
                    messageId = "",
                )
            )
            post(context, store, meta, chatId, chatName, isGroup, isChannel, history, silentUpdate = true)
        } catch (e: Throwable) {
            Log.e(TAG, "appendOwnReply failed", e)
        }
    }

    @SuppressLint("MissingPermission")
    private fun post(
        context: Context,
        store: NotificationStore,
        data: Map<String, String>,
        chatId: String,
        chatName: String,
        isGroup: Boolean,
        isChannel: Boolean,
        history: List<NotificationStore.HistoryEntry>,
        silentUpdate: Boolean,
    ) {
        val nm = NotificationManagerCompat.from(context)
        val channelId = resolveChannel(context, data, chatId, isGroup, isChannel)

        val chatAvatar = loadAvatar(context, store, data["avatar_url"].orEmpty(), chatName, chatId)
        val chatIcon = IconCompat.createWithBitmap(chatAvatar)

        val me = Person.Builder().setName("Вы").setKey("me").build()
        val people = HashMap<String, Person>()
        fun personFor(e: NotificationStore.HistoryEntry): Person {
            if (e.isOwn) return me
            val key = e.senderKey.ifEmpty { e.senderName }
            return people.getOrPut(key) {
                val name = e.senderName.ifEmpty { chatName }
                val icon = if (!isGroup && !isChannel) {
                    chatIcon
                } else {
                    IconCompat.createWithBitmap(loadAvatar(context, store, e.avatarUrl, name, key))
                }
                Person.Builder().setName(name).setKey(key).setIcon(icon).build()
            }
        }

        val style = NotificationCompat.MessagingStyle(me)
            .setGroupConversation(isGroup || isChannel)
        if (isGroup || isChannel) style.conversationTitle = chatName
        history.forEach { e -> style.addMessage(e.text, e.timestamp, personFor(e)) }

        // Conversation shortcut: on Android 11+ the notification shows the chat avatar
        // in place of the app icon and lands in the "Conversations" section.
        val shortcutId = tagFor(chatId)
        val tapPayload = tapPayload(data, chatId, chatName, isGroup, isChannel)
        try {
            val shortcutIntent = Intent(context, MainActivity::class.java).apply {
                action = Intent.ACTION_VIEW
                putExtra(EXTRA_TAP_PAYLOAD, tapPayload)
            }
            val builder = ShortcutInfoCompat.Builder(context, shortcutId)
                .setShortLabel(chatName.take(25).ifEmpty { "Чат" })
                .setLongLabel(chatName.ifEmpty { "Чат" })
                .setIcon(chatIcon)
                .setIntent(shortcutIntent)
                .setLongLived(true)
                .setIsConversation()
            if (!isGroup && !isChannel) {
                builder.setPerson(Person.Builder().setName(chatName).setKey(chatId).setIcon(chatIcon).build())
            }
            ShortcutManagerCompat.pushDynamicShortcut(context, builder.build())
        } catch (e: Throwable) {
            Log.w(TAG, "shortcut push failed: ${e.message}")
        }

        val builder = NotificationCompat.Builder(context, channelId)
            .setSmallIcon(R.drawable.ic_notification)
            .setColor(ACCENT)
            .setLargeIcon(chatAvatar)
            .setStyle(style)
            .setShortcutId(shortcutId)
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setGroup(GROUP_KEY)
            .setAutoCancel(true)
            .setOnlyAlertOnce(silentUpdate)
            .setShowWhen(true)
            .setWhen(history.lastOrNull()?.timestamp ?: System.currentTimeMillis())
            .setNumber(history.count { !it.isOwn })
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
            .setContentIntent(tapIntent(context, chatId, tapPayload))
            .setDeleteIntent(actionIntent(context, NotificationActionReceiver.ACTION_DISMISSED, chatId, mutable = false))

        if (!isChannel) {
            val remoteInput = RemoteInput.Builder(KEY_REPLY_TEXT).setLabel("Сообщение").build()
            builder.addAction(
                NotificationCompat.Action.Builder(
                    R.drawable.ic_notification,
                    "Ответить",
                    actionIntent(context, ACTION_REPLY, chatId, mutable = true),
                )
                    .addRemoteInput(remoteInput)
                    .setAllowGeneratedReplies(true)
                    .setSemanticAction(NotificationCompat.Action.SEMANTIC_ACTION_REPLY)
                    .setShowsUserInterface(false)
                    .build()
            )
        }
        builder.addAction(
            NotificationCompat.Action.Builder(
                R.drawable.ic_notification,
                "Прочитано",
                actionIntent(context, ACTION_MARK_READ, chatId, mutable = false),
            )
                .setSemanticAction(NotificationCompat.Action.SEMANTIC_ACTION_MARK_AS_READ)
                .setShowsUserInterface(false)
                .build()
        )

        try {
            nm.notify(tagFor(chatId), 0, builder.build())
        } catch (e: SecurityException) {
            Log.w(TAG, "POST_NOTIFICATIONS not granted: ${e.message}")
            return
        }
        updateSummary(context, store)
    }

    @SuppressLint("MissingPermission")
    private fun updateSummary(context: Context, store: NotificationStore) {
        val nm = NotificationManagerCompat.from(context)
        val chats = store.activeNotificationChats
        if (chats.size < 2) {
            nm.cancel(SUMMARY_TAG, SUMMARY_ID)
            return
        }
        val inbox = NotificationCompat.InboxStyle()
        var total = 0
        chats.take(6).forEach { chatId ->
            val h = store.readHistory(chatId)
            total += h.count { !it.isOwn }
            h.lastOrNull()?.let { e ->
                inbox.addLine(if (e.senderName.isNotEmpty()) "${e.senderName}: ${e.text}" else e.text)
            }
        }
        val summaryText = "Новые сообщения: ${chats.size} чата(ов)"
        inbox.setSummaryText(summaryText)
        ensureBaseChannel(context, CHANNEL_PRIVATE)
        val summary = NotificationCompat.Builder(context, CHANNEL_PRIVATE)
            .setSmallIcon(R.drawable.ic_notification)
            .setColor(ACCENT)
            .setContentTitle("Theaver")
            .setContentText(summaryText)
            .setStyle(inbox)
            .setNumber(total)
            .setGroup(GROUP_KEY)
            .setGroupSummary(true)
            .setGroupAlertBehavior(NotificationCompat.GROUP_ALERT_CHILDREN)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setAutoCancel(true)
            .build()
        try {
            nm.notify(SUMMARY_TAG, SUMMARY_ID, summary)
        } catch (_: SecurityException) {
        }
    }

    /**
     * The "foreground" flag is written by Flutter; verify it against the real process
     * state so a stale flag (app killed while visible) never suppresses pushes.
     */
    private fun isProcessForeground(): Boolean = try {
        val info = ActivityManager.RunningAppProcessInfo()
        ActivityManager.getMyMemoryState(info)
        info.importance <= ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND
    } catch (_: Throwable) {
        false
    }

    // ======================= Cancellation =======================

    fun cancelChat(context: Context, chatId: String) {
        val store = NotificationStore(context)
        store.clearChat(chatId)
        val nm = NotificationManagerCompat.from(context)
        nm.cancel(tagFor(chatId), 0)
        updateSummary(context, store)
    }

    fun cancelAll(context: Context) {
        val store = NotificationStore(context)
        store.activeNotificationChats.forEach { NotificationManagerCompat.from(context).cancel(tagFor(it), 0) }
        store.clearAll()
        NotificationManagerCompat.from(context).cancel(SUMMARY_TAG, SUMMARY_ID)
    }

    // ======================= Intents =======================

    private fun tapPayload(
        data: Map<String, String>,
        chatId: String,
        chatName: String,
        isGroup: Boolean,
        isChannel: Boolean,
    ): String = JSONObject().apply {
        put("type", "new_message")
        put("chat_id", chatId)
        put("chat_name", chatName)
        put("is_group", isGroup)
        put("is_channel", isChannel)
        put("chat_type", if (isChannel) "channel" else if (isGroup) "group" else "private")
        data["avatar_url"]?.takeIf { it.isNotEmpty() }?.let { put("avatar_url", it) }
        (data["id"] ?: data["message_id"])?.takeIf { it.isNotEmpty() }?.let { put("id", it) }
    }.toString()

    private fun tapIntent(context: Context, chatId: String, payload: String): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            action = "app.theaver.messenger.OPEN_CHAT.$chatId"
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(EXTRA_TAP_PAYLOAD, payload)
        }
        return PendingIntent.getActivity(
            context,
            requestCode(chatId, 0),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun actionIntent(context: Context, action: String, chatId: String, mutable: Boolean): PendingIntent {
        val intent = Intent(context, NotificationActionReceiver::class.java).apply {
            this.action = action
            putExtra(EXTRA_CHAT_ID, chatId)
        }
        var flags = PendingIntent.FLAG_UPDATE_CURRENT
        flags = flags or if (mutable && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            PendingIntent.FLAG_MUTABLE
        } else if (!mutable) {
            PendingIntent.FLAG_IMMUTABLE
        } else {
            0
        }
        return PendingIntent.getBroadcast(context, requestCode(chatId, action.hashCode()), intent, flags)
    }

    private fun requestCode(chatId: String, salt: Int): Int = (chatId.hashCode() * 31 + salt) and 0x7fffffff

    // ======================= Channels =======================

    private const val CHANNEL_PRIVATE = "private_chats"
    private const val CHANNEL_GROUP = "group_chats"
    private const val CHANNEL_CHANNELS = "channels"
    private const val CHANNEL_MENTIONS = "mentions"
    private const val CHANNEL_SILENT = "messages_silent"

    private fun resolveChannel(
        context: Context,
        data: Map<String, String>,
        chatId: String,
        isGroup: Boolean,
        isChannel: Boolean,
    ): String {
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        fun exists(id: String) = Build.VERSION.SDK_INT < Build.VERSION_CODES.O || nm.getNotificationChannel(id) != null

        // 1. Server-provided per-device channel, 2. locally created per-chat channel.
        data["channel_id"]?.takeIf { it.startsWith("chat_") && exists(it) }?.let { return it }
        val flutterPrefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val version = try {
            flutterPrefs.getLong("flutter.notif_chat_channel_v_$chatId", -1L)
        } catch (_: ClassCastException) {
            -1L
        }
        if (version > 0) {
            val custom = "chat_${chatId}_v$version"
            if (exists(custom)) return custom
        }
        val base = when {
            data["sound"] == "none" -> CHANNEL_SILENT
            data["is_mention"] == "true" -> CHANNEL_MENTIONS
            isChannel -> CHANNEL_CHANNELS
            isGroup -> CHANNEL_GROUP
            else -> CHANNEL_PRIVATE
        }
        ensureBaseChannel(context, base)
        return base
    }

    /** Creates a base channel if Flutter has not created it yet (cold start from push). */
    private fun ensureBaseChannel(context: Context, id: String) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (nm.getNotificationChannel(id) != null) return
        val (name, importance) = when (id) {
            CHANNEL_GROUP -> "Групповые чаты" to NotificationManager.IMPORTANCE_HIGH
            CHANNEL_CHANNELS -> "Каналы" to NotificationManager.IMPORTANCE_DEFAULT
            CHANNEL_MENTIONS -> "Упоминания" to NotificationManager.IMPORTANCE_HIGH
            CHANNEL_SILENT -> "Беззвучные сообщения" to NotificationManager.IMPORTANCE_HIGH
            else -> "Личные чаты" to NotificationManager.IMPORTANCE_HIGH
        }
        val channel = NotificationChannel(id, name, importance)
        if (id == CHANNEL_SILENT) {
            channel.setSound(null, null)
            channel.enableVibration(false)
        }
        nm.createNotificationChannel(channel)
    }

    // ======================= Avatars =======================

    private const val AVATAR_SIZE = 192

    /** Loads (or generates) a circular avatar bitmap. Never throws. */
    private fun loadAvatar(context: Context, store: NotificationStore, rawUrl: String, name: String, seed: String): Bitmap {
        val url = resolveUrl(store, rawUrl)
        if (url != null) {
            try {
                val bitmap = if (url.startsWith("data:")) {
                    val comma = url.indexOf(',')
                    val bytes = Base64.decode(url.substring(comma + 1), Base64.DEFAULT)
                    BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                } else {
                    loadCached(context, url)
                }
                if (bitmap != null) return circle(bitmap)
            } catch (e: Throwable) {
                Log.w(TAG, "avatar load failed: ${e.message}")
            }
        }
        return initials(name, seed)
    }

    private fun resolveUrl(store: NotificationStore, raw: String): String? {
        val url = raw.trim()
        if (url.isEmpty()) return null
        if (url.startsWith("data:")) return url
        val storage = store.storageUrl.trimEnd('/')
        val base = store.baseUrl.trimEnd('/')
        for (local in listOf("http://localhost:9000", "http://127.0.0.1:9000", "http://minio:9000",
            "https://localhost:9000", "https://127.0.0.1:9000", "https://minio:9000")) {
            if (url.startsWith(local) && storage.isNotEmpty()) return storage + url.removePrefix(local)
        }
        if (url.startsWith("http://") || url.startsWith("https://")) return url
        if (url.startsWith("/")) {
            val prefix = if (url.startsWith("/avatars/")) storage else base
            return if (prefix.isNotEmpty()) prefix + url else null
        }
        return null
    }

    private fun loadCached(context: Context, url: String): Bitmap? {
        val dir = File(context.cacheDir, "notif_avatars").apply { mkdirs() }
        val file = File(dir, sha1(url) + ".img")
        if (file.exists() && file.length() > 0 && System.currentTimeMillis() - file.lastModified() < 7 * 24 * 3600_000L) {
            decodeSampled(file)?.let { return it }
        }
        val conn = (URL(url).openConnection() as HttpURLConnection).apply {
            connectTimeout = 4000
            readTimeout = 4000
            instanceFollowRedirects = true
        }
        try {
            if (conn.responseCode != 200) return null
            conn.inputStream.use { input -> file.outputStream().use { input.copyTo(it) } }
        } finally {
            conn.disconnect()
        }
        return decodeSampled(file)
    }

    private fun decodeSampled(file: File): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(file.path, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
        var sample = 1
        while (bounds.outWidth / (sample * 2) >= AVATAR_SIZE && bounds.outHeight / (sample * 2) >= AVATAR_SIZE) sample *= 2
        return BitmapFactory.decodeFile(file.path, BitmapFactory.Options().apply { inSampleSize = sample })
    }

    private fun circle(src: Bitmap): Bitmap {
        val size = AVATAR_SIZE
        val out = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(out)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
        canvas.drawOval(RectF(0f, 0f, size.toFloat(), size.toFloat()), paint)
        paint.xfermode = PorterDuffXfermode(PorterDuff.Mode.SRC_IN)
        val side = minOf(src.width, src.height)
        val left = (src.width - side) / 2
        val top = (src.height - side) / 2
        canvas.drawBitmap(src, Rect(left, top, left + side, top + side), Rect(0, 0, size, size), paint)
        return out
    }

    private val palette = intArrayOf(
        0xFFE57373.toInt(), 0xFFF06292.toInt(), 0xFFBA68C8.toInt(), 0xFF7986CB.toInt(),
        0xFF4FC3F7.toInt(), 0xFF4DB6AC.toInt(), 0xFF81C784.toInt(), 0xFFFFB74D.toInt(),
    )

    private fun initials(name: String, seed: String): Bitmap {
        val size = AVATAR_SIZE
        val out = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(out)
        val bg = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = palette[(seed.hashCode() and 0x7fffffff) % palette.size] }
        canvas.drawOval(RectF(0f, 0f, size.toFloat(), size.toFloat()), bg)
        val letters = name.trim().split(Regex("\\s+")).filter { it.isNotEmpty() }
            .take(2).joinToString("") { it.substring(0, 1).uppercase() }.ifEmpty { "T" }
        val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE
            textSize = size * if (letters.length > 1) 0.36f else 0.44f
            textAlign = Paint.Align.CENTER
            isFakeBoldText = true
        }
        val y = size / 2f - (textPaint.descent() + textPaint.ascent()) / 2f
        canvas.drawText(letters, size / 2f, y, textPaint)
        return out
    }

    private fun sha1(s: String): String =
        MessageDigest.getInstance("SHA-1").digest(s.toByteArray()).joinToString("") { "%02x".format(it) }
}
