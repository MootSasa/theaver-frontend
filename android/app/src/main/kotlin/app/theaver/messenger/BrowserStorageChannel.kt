package app.theaver.messenger

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.View
import android.webkit.CookieManager
import android.webkit.WebSettings
import android.webkit.WebStorage
import android.webkit.WebView
import android.webkit.WebViewDatabase
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.concurrent.Executors

/**
 * Native Android WebView cookie jar, WebStorage, HTTP auth cache, and OS Autofill
 * bridge for `app.theaver.messenger/browser_storage`.
 */
object BrowserStorageChannel {
    private const val CHANNEL_NAME = "app.theaver.messenger/browser_storage"
    private const val CHROMIUM_EPOCH_OFFSET_MICROS = 11644473600000000L

    private val mainHandler = Handler(Looper.getMainLooper())
    private val ioExecutor = Executors.newSingleThreadExecutor()

    fun register(
        flutterEngine: FlutterEngine,
        context: Context,
        webViewFinder: (String?) -> WebView?,
    ) {
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL_NAME,
        ).setMethodCallHandler { call: MethodCall, result: MethodChannel.Result ->
            when (call.method) {
                "flushCookies" -> {
                    mainHandler.post {
                        try {
                            CookieManager.getInstance().flush()
                            result.success(true)
                        } catch (_: Throwable) {
                            result.success(false)
                        }
                    }
                }

                "configureWebViewPolicies" -> {
                    val url = call.argument<String>("url")
                    val acceptThirdParty = call.argument<Boolean>("acceptThirdPartyCookies") ?: true
                    val enableOsAutofill = call.argument<Boolean>("enableOsAutofill") ?: true
                    val blockAllCookies = call.argument<Boolean>("blockAllCookies") ?: false
                    mainHandler.post {
                        try {
                            val cm = CookieManager.getInstance()
                            cm.setAcceptCookie(!blockAllCookies)
                            val wv = webViewFinder(url)
                            if (wv != null) {
                                cm.setAcceptThirdPartyCookies(wv, acceptThirdParty && !blockAllCookies)
                                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                    wv.importantForAutofill = if (enableOsAutofill) {
                                        View.IMPORTANT_FOR_AUTOFILL_YES
                                    } else {
                                        View.IMPORTANT_FOR_AUTOFILL_NO_EXCLUDE_DESCENDANTS
                                    }
                                }
                                wv.settings.cacheMode = WebSettings.LOAD_DEFAULT
                            }
                            result.success(true)
                        } catch (_: Throwable) {
                            result.success(false)
                        }
                    }
                }

                "exportAllCookies" -> {
                    val knownOrigins = call.argument<List<String>>("knownOrigins") ?: emptyList()
                    mainHandler.post {
                        try {
                            CookieManager.getInstance().flush()
                        } catch (_: Throwable) {}
                        ioExecutor.execute {
                            val exported = exportCookiesInternal(context, knownOrigins)
                            mainHandler.post { result.success(exported) }
                        }
                    }
                }

                "importCookies" -> {
                    @Suppress("UNCHECKED_CAST")
                    val rawList = call.argument<List<Map<String, Any?>>>("cookies") ?: emptyList()
                    mainHandler.post {
                        try {
                            importCookiesInternal(rawList)
                            result.success(true)
                        } catch (_: Throwable) {
                            result.success(false)
                        }
                    }
                }

                "clearSiteData" -> {
                    val originUrl = call.argument<String>("originUrl").orEmpty()
                    mainHandler.post {
                        try {
                            clearSiteDataInternal(context, originUrl)
                            result.success(true)
                        } catch (_: Throwable) {
                            result.success(false)
                        }
                    }
                }

                "clearAllWebData" -> {
                    mainHandler.post {
                        try {
                            webViewFinder(null)?.clearCache(true)
                        } catch (_: Throwable) {}
                        try {
                            WebStorage.getInstance().deleteAllData()
                        } catch (_: Throwable) {}
                        try {
                            WebViewDatabase.getInstance(context).clearHttpAuthUsernamePassword()
                        } catch (_: Throwable) {}
                        try {
                            val cm = CookieManager.getInstance()
                            cm.removeAllCookies {
                                try {
                                    cm.flush()
                                } catch (_: Throwable) {}
                                result.success(true)
                            }
                        } catch (_: Throwable) {
                            result.success(false)
                        }
                    }
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun resolveCookieDbFile(context: Context): File? {
        val dataDir = File(context.applicationInfo.dataDir)
        val candidates = listOf(
            File(dataDir, "app_webview/Default/Cookies"),
            File(dataDir, "app_webview/Cookies"),
        )
        return candidates.firstOrNull { it.exists() && it.isFile && it.length() > 0 }
    }

    private fun parseCookieHeaderPairs(header: String?): Map<String, String> {
        if (header.isNullOrBlank()) return emptyMap()
        val out = LinkedHashMap<String, String>()
        for (part in header.split(";")) {
            val idx = part.indexOf('=')
            if (idx <= 0) continue
            val name = part.substring(0, idx).trim()
            val value = part.substring(idx + 1).trim()
            if (name.isNotEmpty()) {
                out[name] = value
            }
        }
        return out
    }

    private fun exportCookiesInternal(
        context: Context,
        knownOrigins: List<String>,
    ): List<Map<String, Any?>> {
        val cm = CookieManager.getInstance()
        val dedup = LinkedHashMap<String, Map<String, Any?>>()
        val valueLookup = HashMap<String, String>()

        val dbFile = resolveCookieDbFile(context)
        if (dbFile != null) {
            var db: SQLiteDatabase? = null
            try {
                db = SQLiteDatabase.openDatabase(
                    dbFile.absolutePath,
                    null,
                    SQLiteDatabase.OPEN_READONLY,
                )
                val cursor = db.rawQuery(
                    "SELECT host_key, name, value, path, expires_utc, is_secure, is_httponly, samesite FROM cookies",
                    null,
                )
                cursor.use { c ->
                    val probeUrls = HashSet<String>()
                    val rawRows = ArrayList<Map<String, Any?>>()
                    while (c.moveToNext()) {
                        val hostKey = c.getString(0)?.trim().orEmpty()
                        val name = c.getString(1)?.trim().orEmpty()
                        val value = c.getString(2).orEmpty()
                        val path = c.getString(3)?.trim().orEmpty().ifEmpty { "/" }
                        val expiresUtc = c.getLong(4)
                        val isSecure = c.getInt(5) != 0
                        val isHttpOnly = c.getInt(6) != 0
                        val sameSite = c.getInt(7)
                        if (hostKey.isEmpty() || name.isEmpty()) continue

                        val expiresEpochMs = if (expiresUtc <= 0L) {
                            0L
                        } else {
                            ((expiresUtc - CHROMIUM_EPOCH_OFFSET_MICROS) / 1000L).coerceAtLeast(0L)
                        }

                        val cleanHost = hostKey.trimStart('.')
                        if (cleanHost.isNotEmpty()) {
                            val scheme = if (isSecure) "https" else "http"
                            probeUrls.add("$scheme://$cleanHost$path")
                            probeUrls.add("https://$cleanHost/")
                        }

                        rawRows.add(
                            hashMapOf(
                                "hostKey" to hostKey,
                                "name" to name,
                                "value" to value,
                                "path" to path,
                                "expiresEpochMs" to expiresEpochMs,
                                "isSecure" to isSecure,
                                "isHttpOnly" to isHttpOnly,
                                "sameSite" to sameSite,
                            ),
                        )
                    }

                    for (probe in probeUrls) {
                        val uri = try {
                            Uri.parse(probe)
                        } catch (_: Exception) {
                            null
                        } ?: continue
                        val h = uri.host?.lowercase(Locale.ROOT).orEmpty()
                        if (h.isEmpty()) continue
                        val header = try {
                            cm.getCookie(probe)
                        } catch (_: Throwable) {
                            null
                        }
                        for ((n, v) in parseCookieHeaderPairs(header)) {
                            valueLookup["$h|$n"] = v
                        }
                    }

                    for (row in rawRows) {
                        val hostKey = row["hostKey"] as String
                        val name = row["name"] as String
                        val path = row["path"] as String
                        val cleanHost = hostKey.trimStart('.').lowercase(Locale.ROOT)
                        val existingVal = row["value"] as String
                        val resolvedVal = existingVal.ifEmpty {
                            valueLookup["$cleanHost|$name"].orEmpty()
                        }
                        if (resolvedVal.isEmpty()) continue
                        val key = "${hostKey.lowercase(Locale.ROOT)}|$path|$name"
                        dedup[key] = hashMapOf(
                            "hostKey" to hostKey,
                            "name" to name,
                            "value" to resolvedVal,
                            "path" to path,
                            "expiresEpochMs" to row["expiresEpochMs"],
                            "isSecure" to row["isSecure"],
                            "isHttpOnly" to row["isHttpOnly"],
                            "sameSite" to row["sameSite"],
                        )
                    }
                }
            } catch (_: Throwable) {
                // Fall back to CookieManager API across knownOrigins below.
            } finally {
                try {
                    db?.close()
                } catch (_: Throwable) {}
            }
        }

        // Supplement with CookieManager values for any known origins (captures recent
        // or session cookies even when SQLite cannot be opened directly).
        for (origin in knownOrigins) {
            val uri = try {
                Uri.parse(origin.trim())
            } catch (_: Exception) {
                null
            } ?: continue
            val host = uri.host?.lowercase(Locale.ROOT).orEmpty()
            if (host.isEmpty()) continue
            val header = try {
                cm.getCookie(origin)
            } catch (_: Throwable) {
                null
            }
            val isSecure = uri.scheme.equals("https", ignoreCase = true)
            for ((name, value) in parseCookieHeaderPairs(header)) {
                val alreadyExists = dedup.keys.any { k ->
                    k.endsWith("|$name") && (k.startsWith("$host|") || k.startsWith(".$host|"))
                }
                if (!alreadyExists && value.isNotEmpty()) {
                    dedup["$host|/|$name"] = hashMapOf(
                        "hostKey" to host,
                        "name" to name,
                        "value" to value,
                        "path" to "/",
                        "expiresEpochMs" to 0L,
                        "isSecure" to isSecure,
                        "isHttpOnly" to false,
                        "sameSite" to -1,
                    )
                }
            }
        }

        return dedup.values.toList()
    }

    private fun formatHttpDate(epochMs: Long): String {
        val fmt = SimpleDateFormat("EEE, dd MMM yyyy HH:mm:ss 'GMT'", Locale.US)
        fmt.timeZone = TimeZone.getTimeZone("GMT")
        return fmt.format(Date(epochMs))
    }

    private fun importCookiesInternal(rawList: List<Map<String, Any?>>) {
        val cm = CookieManager.getInstance()
        val nowMs = System.currentTimeMillis()
        for (item in rawList) {
            val hostKey = (item["hostKey"] as? String)?.trim().orEmpty()
            val name = (item["name"] as? String)?.trim().orEmpty()
            val value = (item["value"] as? String).orEmpty()
            if (hostKey.isEmpty() || name.isEmpty()) continue

            val path = (item["path"] as? String)?.trim().orEmpty().ifEmpty { "/" }
            val expiresEpochMs = (item["expiresEpochMs"] as? Number)?.toLong() ?: 0L
            if (expiresEpochMs in 1 until nowMs) continue

            val isSecure = (item["isSecure"] as? Boolean) ?: false
            val isHttpOnly = (item["isHttpOnly"] as? Boolean) ?: false
            val sameSite = (item["sameSite"] as? Number)?.toInt() ?: -1

            val sb = StringBuilder()
            sb.append(name).append('=').append(value)
            val cleanHost = hostKey.trimStart('.')
            if (cleanHost.isEmpty()) continue
            if (hostKey.startsWith(".")) {
                sb.append("; Domain=").append(cleanHost)
            }
            sb.append("; Path=").append(path)
            if (expiresEpochMs > 0L) {
                sb.append("; Expires=").append(formatHttpDate(expiresEpochMs))
            }
            if (isSecure) {
                sb.append("; Secure")
            }
            if (isHttpOnly) {
                sb.append("; HttpOnly")
            }
            when (sameSite) {
                0 -> sb.append("; SameSite=None")
                1 -> sb.append("; SameSite=Lax")
                2 -> sb.append("; SameSite=Strict")
            }
            val targetUrl = "${if (isSecure) "https" else "http"}://$cleanHost$path"
            cm.setCookie(targetUrl, sb.toString())
        }
        cm.flush()
    }

    private fun clearSiteDataInternal(context: Context, originUrl: String) {
        val uri = try {
            Uri.parse(originUrl.trim())
        } catch (_: Exception) {
            null
        } ?: return
        val cleanHost = uri.host?.lowercase(Locale.ROOT)?.trimStart('.').orEmpty()
        if (cleanHost.isEmpty()) return

        val cm = CookieManager.getInstance()
        val targets = ArrayList<Triple<String, String, String>>() // hostKey, name, path

        // 1. Collect from SQLite (includes exact paths, HttpOnly, and subdomain cookies).
        val dbFile = resolveCookieDbFile(context)
        if (dbFile != null) {
            var db: SQLiteDatabase? = null
            try {
                db = SQLiteDatabase.openDatabase(
                    dbFile.absolutePath,
                    null,
                    SQLiteDatabase.OPEN_READONLY,
                )
                val cursor = db.rawQuery(
                    "SELECT host_key, name, path FROM cookies",
                    null,
                )
                cursor.use { c ->
                    while (c.moveToNext()) {
                        val hk = c.getString(0)?.trim().orEmpty()
                        val name = c.getString(1)?.trim().orEmpty()
                        val path = c.getString(2)?.trim().orEmpty().ifEmpty { "/" }
                        if (hk.isEmpty() || name.isEmpty()) continue
                        val hkNoDot = hk.trimStart('.').lowercase(Locale.ROOT)
                        val matches = hkNoDot == cleanHost ||
                            hkNoDot.endsWith(".$cleanHost") ||
                            (hk.startsWith(".") && cleanHost.endsWith(hk.lowercase(Locale.ROOT)))
                        if (matches) {
                            targets.add(Triple(hk, name, path))
                        }
                    }
                }
            } catch (_: Throwable) {
                // Ignore SQLite read error and rely on CookieManager fallback.
            } finally {
                try {
                    db?.close()
                } catch (_: Throwable) {}
            }
        }

        // 2. Supplement with CookieManager for host & www/bare variants.
        val hostVariants = linkedSetOf(cleanHost)
        if (cleanHost.startsWith("www.")) {
            hostVariants.add(cleanHost.removePrefix("www."))
        } else {
            hostVariants.add("www.$cleanHost")
        }
        for (hv in hostVariants) {
            for (scheme in listOf("https", "http")) {
                val hdr = try {
                    cm.getCookie("$scheme://$hv/")
                } catch (_: Throwable) {
                    null
                }
                for (name in parseCookieHeaderPairs(hdr).keys) {
                    targets.add(Triple(hv, name, "/"))
                    targets.add(Triple(".$hv", name, "/"))
                }
            }
        }

        for ((hk, name, path) in targets) {
            val hNoDot = hk.trimStart('.')
            val effectivePaths = linkedSetOf(path, "/")
            for (p in effectivePaths) {
                for (scheme in listOf("https", "http")) {
                    val url = "$scheme://$hNoDot$p"
                    cm.setCookie(
                        url,
                        "$name=; Max-Age=0; Expires=Thu, 01 Jan 1970 00:00:00 GMT; Path=$p",
                    )
                    cm.setCookie(
                        url,
                        "$name=; Max-Age=0; Expires=Thu, 01 Jan 1970 00:00:00 GMT; Domain=$hNoDot; Path=$p",
                    )
                    if (scheme == "https") {
                        cm.setCookie(
                            url,
                            "$name=; Max-Age=0; Expires=Thu, 01 Jan 1970 00:00:00 GMT; Path=$p; Secure; HttpOnly",
                        )
                    }
                }
            }
        }

        // 3. Delete WebStorage (localStorage, IndexedDB, CacheStorage) for matching origins.
        val storage = WebStorage.getInstance()
        val originsToWipe = linkedSetOf(
            if (uri.scheme != null && uri.authority != null) "${uri.scheme}://${uri.authority}" else "",
            "https://$cleanHost",
            "http://$cleanHost",
        ).filter { it.isNotEmpty() }
        for (o in originsToWipe) {
            try {
                storage.deleteOrigin(o)
            } catch (_: Throwable) {}
        }

        cm.flush()
    }
}
