package app.theaver.messenger.notifications

import android.content.Context
import android.content.SharedPreferences
import org.json.JSONArray
import org.json.JSONObject

/**
 * Native notification state shared by the push services, the action receiver and
 * the Flutter MethodChannel. Stored in a private SharedPreferences file so it is
 * available in a cold process started by FCM/HMS.
 */
internal class NotificationStore(context: Context) {

    private val prefs: SharedPreferences =
        context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    // ---------------- configuration (written by Flutter) ----------------

    var baseUrl: String
        get() = prefs.getString(KEY_BASE_URL, "") ?: ""
        set(v) = prefs.edit().putString(KEY_BASE_URL, v).apply()

    var storageUrl: String
        get() = prefs.getString(KEY_STORAGE_URL, "") ?: ""
        set(v) = prefs.edit().putString(KEY_STORAGE_URL, v).apply()

    var authToken: String
        get() = prefs.getString(KEY_TOKEN, "") ?: ""
        set(v) = prefs.edit().putString(KEY_TOKEN, v).apply()

    var userId: String
        get() = prefs.getString(KEY_USER_ID, "") ?: ""
        set(v) = prefs.edit().putString(KEY_USER_ID, v).apply()

    // ---------------- app state (written by Flutter) ----------------

    var appInForeground: Boolean
        get() = prefs.getBoolean(KEY_FOREGROUND, false)
        set(v) = prefs.edit().putBoolean(KEY_FOREGROUND, v).apply()

    var foregroundNotificationsEnabled: Boolean
        get() = prefs.getBoolean(KEY_FOREGROUND_ENABLED, true)
        set(v) = prefs.edit().putBoolean(KEY_FOREGROUND_ENABLED, v).apply()

    var activeChatIds: Set<String>
        get() = prefs.getStringSet(KEY_ACTIVE_CHATS, emptySet()) ?: emptySet()
        set(v) = prefs.edit().putStringSet(KEY_ACTIVE_CHATS, HashSet(v)).apply()

    // ---------------- known avatars ----------------

    /** Last known avatar URL for "chat:<id>" / "user:<id>". */
    fun knownAvatar(key: String): String = prefs.getString(KEY_AVATAR_PREFIX + key, "") ?: ""

    fun rememberAvatar(key: String, url: String) {
        if (url.isEmpty() || url.startsWith("data:")) return
        if (knownAvatar(key) == url) return
        prefs.edit().putString(KEY_AVATAR_PREFIX + key, url).apply()
    }

    // ---------------- de-duplication ----------------

    /** Returns true if [key] was seen in the last [ttlMs]; otherwise records it. */
    @Synchronized
    fun checkAndMarkShown(key: String, ttlMs: Long = 10 * 60 * 1000L): Boolean {
        val now = System.currentTimeMillis()
        val obj = try {
            JSONObject(prefs.getString(KEY_DEDUP, "{}") ?: "{}")
        } catch (_: Exception) {
            JSONObject()
        }
        val fresh = JSONObject()
        val keys = obj.keys()
        while (keys.hasNext()) {
            val k = keys.next()
            val ts = obj.optLong(k, 0)
            if (now - ts < ttlMs) fresh.put(k, ts)
        }
        val seen = fresh.has(key)
        if (!seen) fresh.put(key, now)
        // Bound size.
        if (fresh.length() > 300) {
            val sorted = mutableListOf<Pair<String, Long>>()
            val it = fresh.keys()
            while (it.hasNext()) {
                val k = it.next()
                sorted.add(k to fresh.optLong(k))
            }
            sorted.sortBy { it.second }
            val trimmed = JSONObject()
            sorted.takeLast(200).forEach { trimmed.put(it.first, it.second) }
            prefs.edit().putString(KEY_DEDUP, trimmed.toString()).apply()
        } else {
            prefs.edit().putString(KEY_DEDUP, fresh.toString()).apply()
        }
        return seen
    }

    // ---------------- conversation history ----------------

    data class HistoryEntry(
        val text: String,
        val senderName: String,
        val senderKey: String,
        val avatarUrl: String,
        val timestamp: Long,
        val isOwn: Boolean,
        val messageId: String,
    )

    @Synchronized
    fun readHistory(chatId: String): List<HistoryEntry> {
        val raw = prefs.getString(KEY_HISTORY_PREFIX + chatId, null) ?: return emptyList()
        return try {
            val arr = JSONArray(raw)
            (0 until arr.length()).mapNotNull { i ->
                val o = arr.optJSONObject(i) ?: return@mapNotNull null
                HistoryEntry(
                    text = o.optString("t"),
                    senderName = o.optString("s"),
                    senderKey = o.optString("k"),
                    avatarUrl = o.optString("a"),
                    timestamp = o.optLong("ts"),
                    isOwn = o.optBoolean("o"),
                    messageId = o.optString("id"),
                )
            }
        } catch (_: Exception) {
            emptyList()
        }
    }

    /** Appends an entry (deduplicated by message ID) and returns the updated history. */
    @Synchronized
    fun appendHistory(chatId: String, entry: HistoryEntry): List<HistoryEntry> {
        val list = readHistory(chatId).toMutableList()
        if (entry.messageId.isNotEmpty() && list.any { it.messageId == entry.messageId }) return list
        list.add(entry)
        while (list.size > MAX_HISTORY) list.removeAt(0)
        val arr = JSONArray()
        list.forEach { e ->
            arr.put(JSONObject().apply {
                put("t", e.text)
                put("s", e.senderName)
                put("k", e.senderKey)
                put("a", e.avatarUrl)
                put("ts", e.timestamp)
                put("o", e.isOwn)
                put("id", e.messageId)
            })
        }
        val active = activeNotificationChats.toMutableSet().apply { add(chatId) }
        prefs.edit()
            .putString(KEY_HISTORY_PREFIX + chatId, arr.toString())
            .putStringSet(KEY_ACTIVE_NOTIF_CHATS, active)
            .apply()
        return list
    }

    /** Last rendered chat metadata (used to re-render after an inline reply). */
    @Synchronized
    fun saveChatMeta(chatId: String, payload: Map<String, String>) {
        prefs.edit().putString(KEY_META_PREFIX + chatId, JSONObject(payload as Map<*, *>).toString()).apply()
    }

    @Synchronized
    fun readChatMeta(chatId: String): Map<String, String>? {
        val raw = prefs.getString(KEY_META_PREFIX + chatId, null) ?: return null
        return try {
            val o = JSONObject(raw)
            val map = HashMap<String, String>()
            val it = o.keys()
            while (it.hasNext()) {
                val k = it.next()
                map[k] = o.optString(k)
            }
            map
        } catch (_: Exception) {
            null
        }
    }

    val activeNotificationChats: Set<String>
        get() = prefs.getStringSet(KEY_ACTIVE_NOTIF_CHATS, emptySet()) ?: emptySet()

    @Synchronized
    fun clearChat(chatId: String) {
        val active = activeNotificationChats.toMutableSet().apply { remove(chatId) }
        prefs.edit()
            .remove(KEY_HISTORY_PREFIX + chatId)
            .putStringSet(KEY_ACTIVE_NOTIF_CHATS, active)
            .apply()
    }

    @Synchronized
    fun clearAll() {
        val editor = prefs.edit()
        activeNotificationChats.forEach { editor.remove(KEY_HISTORY_PREFIX + it) }
        editor.putStringSet(KEY_ACTIVE_NOTIF_CHATS, emptySet()).apply()
    }

    companion object {
        private const val PREFS_NAME = "theaver_native_notifications"
        private const val KEY_BASE_URL = "base_url"
        private const val KEY_STORAGE_URL = "storage_url"
        private const val KEY_TOKEN = "auth_token"
        private const val KEY_USER_ID = "user_id"
        private const val KEY_FOREGROUND = "app_foreground"
        private const val KEY_FOREGROUND_ENABLED = "foreground_enabled"
        private const val KEY_ACTIVE_CHATS = "active_chats"
        private const val KEY_DEDUP = "dedup"
        private const val KEY_HISTORY_PREFIX = "history_"
        private const val KEY_META_PREFIX = "meta_"
        private const val KEY_ACTIVE_NOTIF_CHATS = "notif_chats"
        private const val KEY_AVATAR_PREFIX = "avatar_"
        const val MAX_HISTORY = 8
    }
}
