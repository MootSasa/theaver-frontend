package app.theaver.messenger

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat

/**
 * Foreground-сервис для удержания активного звонка (аудио/видео) и демонстрации экрана (MediaProjection).
 *
 * На Android 10+ (API 29+) и особенно Android 14+ (API 34+) вызов
 * MediaProjectionManager.getMediaProjection() без запущенного ForegroundService
 * с типом FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION вызывает фатальный SecurityException.
 */
class CallForegroundService : Service() {

    companion object {
        private const val TAG = "CallForegroundService"
        private const val CHANNEL_ID = "theaver_active_call"
        private const val NOTIFICATION_ID = 77702

        const val ACTION_START_CALL = "app.theaver.messenger.START_CALL_SERVICE"
        const val ACTION_PROMOTE_MEDIA_PROJECTION = "app.theaver.messenger.PROMOTE_MEDIA_PROJECTION"
        const val ACTION_STOP_CALL = "app.theaver.messenger.STOP_CALL_SERVICE"

        const val EXTRA_CALL_TITLE = "call_title"
        const val EXTRA_IS_VIDEO = "is_video"
        const val EXTRA_IS_SCREEN_SHARE = "is_screen_share"

        @Volatile
        var isRunning: Boolean = false
            private set

        @Volatile
        var isMediaProjectionActive: Boolean = false
            private set

        @Volatile
        private var instance: CallForegroundService? = null

        private var currentTitle: String = "Активный звонок"
        private var currentIsVideo: Boolean = false

        fun startCallService(
            context: Context,
            title: String = "Активный звонок",
            isVideo: Boolean = false,
            isScreenShare: Boolean = false
        ) {
            currentTitle = title.ifEmpty { "Активный звонок" }
            currentIsVideo = isVideo
            val activeInstance = instance
            if (activeInstance != null && isRunning) {
                activeInstance.updateForegroundImmediate(currentTitle, isVideo, isScreenShare)
                return
            }
            val intent = Intent(context, CallForegroundService::class.java).apply {
                action = ACTION_START_CALL
                putExtra(EXTRA_CALL_TITLE, currentTitle)
                putExtra(EXTRA_IS_VIDEO, isVideo)
                putExtra(EXTRA_IS_SCREEN_SHARE, isScreenShare)
            }
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
            } catch (e: Exception) {
                Log.w(TAG, "Failed to start CallForegroundService: ${e.message}")
            }
        }

        fun promoteToMediaProjection(context: Context) {
            // If service is already running, promote synchronously via Binder before super.onActivityResult!
            val activeInstance = instance
            if (activeInstance != null && isRunning) {
                activeInstance.updateForegroundImmediate(currentTitle, currentIsVideo, true)
                return
            }
            val intent = Intent(context, CallForegroundService::class.java).apply {
                action = ACTION_PROMOTE_MEDIA_PROJECTION
                putExtra(EXTRA_CALL_TITLE, currentTitle)
                putExtra(EXTRA_IS_VIDEO, currentIsVideo)
                putExtra(EXTRA_IS_SCREEN_SHARE, true)
            }
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
            } catch (e: Exception) {
                Log.w(TAG, "Failed to promote CallForegroundService to mediaProjection: ${e.message}")
            }
        }

        fun stopCallService(context: Context) {
            isMediaProjectionActive = false
            val intent = Intent(context, CallForegroundService::class.java).apply {
                action = ACTION_STOP_CALL
            }
            try {
                context.stopService(intent)
            } catch (e: Exception) {
                Log.w(TAG, "Failed to stop CallForegroundService: ${e.message}")
            }
        }
    }

    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
        createNotificationChannel()
    }

    fun updateForegroundImmediate(
        title: String,
        isVideo: Boolean,
        includeMediaProjection: Boolean
    ) {
        currentTitle = title
        currentIsVideo = isVideo
        val notification = buildNotification(title, isVideo, includeMediaProjection)
        startOrUpdateForeground(notification, isVideo, includeMediaProjection)
        acquireLocks()
        isRunning = true
        if (includeMediaProjection) {
            isMediaProjectionActive = true
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        instance = this
        val action = intent?.action ?: ACTION_START_CALL
        if (action == ACTION_STOP_CALL) {
            stopCallForeground()
            return START_NOT_STICKY
        }

        val title = intent?.getStringExtra(EXTRA_CALL_TITLE) ?: currentTitle
        val isVideo = intent?.getBooleanExtra(EXTRA_IS_VIDEO, currentIsVideo) ?: currentIsVideo
        val includeMediaProjection = action == ACTION_PROMOTE_MEDIA_PROJECTION ||
                (intent?.getBooleanExtra(EXTRA_IS_SCREEN_SHARE, false) == true)

        updateForegroundImmediate(title, isVideo, includeMediaProjection)

        return START_STICKY
    }

    private fun startOrUpdateForeground(
        notification: Notification,
        isVideo: Boolean,
        includeMediaProjection: Boolean
    ) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                var fgType = 0
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    val hasMic = ContextCompat.checkSelfPermission(
                        this,
                        Manifest.permission.RECORD_AUDIO
                    ) == PackageManager.PERMISSION_GRANTED
                    if (hasMic) {
                        fgType = fgType or ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
                    }
                    val hasCamera = ContextCompat.checkSelfPermission(
                        this,
                        Manifest.permission.CAMERA
                    ) == PackageManager.PERMISSION_GRANTED
                    if (isVideo && hasCamera) {
                        fgType = fgType or ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA
                    }
                }
                if (includeMediaProjection) {
                    fgType = fgType or ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE && fgType == 0) {
                    fgType = ServiceInfo.FOREGROUND_SERVICE_TYPE_PHONE_CALL
                }

                if (fgType != 0) {
                    try {
                        startForeground(NOTIFICATION_ID, notification, fgType)
                        Log.d(TAG, "CallForegroundService started with fgType=$fgType (mediaProjection=$includeMediaProjection)")
                        return
                    } catch (se: SecurityException) {
                        Log.w(TAG, "startForeground with fgType=$fgType threw SecurityException, trying fallback: ${se.message}")
                        // Fallback if mediaProjection or camera was not allowed yet
                        if (includeMediaProjection) {
                            try {
                                startForeground(
                                    NOTIFICATION_ID,
                                    notification,
                                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION
                                )
                                return
                            } catch (e2: Exception) {
                                Log.w(TAG, "Fallback mediaProjection failed: ${e2.message}")
                            }
                        }
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                            val hasMic = ContextCompat.checkSelfPermission(
                                this,
                                Manifest.permission.RECORD_AUDIO
                            ) == PackageManager.PERMISSION_GRANTED
                            if (hasMic) {
                                try {
                                    startForeground(
                                        NOTIFICATION_ID,
                                        notification,
                                        ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
                                    )
                                    return
                                } catch (_: Exception) {}
                            }
                        }
                    }
                }
            }
            startForeground(NOTIFICATION_ID, notification)
        } catch (e: Exception) {
            Log.e(TAG, "Error in startOrUpdateForeground: ${e.message}")
        }
    }

    private fun acquireLocks() {
        try {
            if (wakeLock == null) {
                val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                wakeLock = pm.newWakeLock(
                    PowerManager.PARTIAL_WAKE_LOCK,
                    "Theaver::CallWakeLock"
                ).apply {
                    setReferenceCounted(false)
                }
            }
            if (wakeLock?.isHeld == false) {
                wakeLock?.acquire(4 * 60 * 60 * 1000L) // max 4 hours
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to acquire WakeLock: ${e.message}")
        }

        try {
            if (wifiLock == null) {
                val wm = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                @Suppress("DEPRECATION")
                val lockMode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    WifiManager.WIFI_MODE_FULL_LOW_LATENCY
                } else {
                    WifiManager.WIFI_MODE_FULL_HIGH_PERF
                }
                wifiLock = wm.createWifiLock(lockMode, "Theaver::CallWifiLock").apply {
                    setReferenceCounted(false)
                }
            }
            if (wifiLock?.isHeld == false) {
                wifiLock?.acquire()
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to acquire WifiLock: ${e.message}")
        }
    }

    private fun releaseLocks() {
        try {
            if (wakeLock?.isHeld == true) {
                wakeLock?.release()
            }
            wakeLock = null
        } catch (_: Exception) {}

        try {
            if (wifiLock?.isHeld == true) {
                wifiLock?.release()
            }
            wifiLock = null
        } catch (_: Exception) {}
    }

    private fun stopCallForeground() {
        isRunning = false
        isMediaProjectionActive = false
        instance = null
        releaseLocks()
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
        } catch (_: Exception) {}
        stopSelf()
    }

    override fun onDestroy() {
        isRunning = false
        isMediaProjectionActive = false
        instance = null
        releaseLocks()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Активный звонок",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Отображается во время активного звонка или трансляции экрана"
                setShowBadge(false)
                enableVibration(false)
                setSound(null, null)
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager?.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(
        title: String,
        isVideo: Boolean,
        isScreenShare: Boolean
    ): Notification {
        val launchIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        val pendingIntent = PendingIntent.getActivity(this, 0, launchIntent, pendingFlags)

        val subtitle = when {
            isScreenShare -> "Идёт демонстрация экрана — нажмите, чтобы вернуться"
            isVideo -> "Идёт видеозвонок — нажмите, чтобы вернуться"
            else -> "Идёт аудиозвонок — нажмите, чтобы вернуться"
        }

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(subtitle)
            .setSmallIcon(R.drawable.ic_notification)
            .setOngoing(true)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setContentIntent(pendingIntent)
            .setUsesChronometer(true)
            .build()
    }
}
