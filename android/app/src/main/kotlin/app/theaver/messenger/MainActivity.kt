package app.theaver.messenger

import android.app.Activity
import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import java.lang.ref.WeakReference

class MainActivity : FlutterFragmentActivity() {

    companion object {
        private var currentActivityRef: WeakReference<MainActivity>? = null

        fun getCurrentActivity(): MainActivity? = currentActivityRef?.get()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        currentActivityRef = WeakReference(this)
        applyLockScreenFlagsIfNeeded(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        applyLockScreenFlagsIfNeeded(intent)
    }

    override fun onResume() {
        super.onResume()
        currentActivityRef = WeakReference(this)
    }

    override fun onDestroy() {
        if (currentActivityRef?.get() === this) {
            currentActivityRef = null
        }
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        PushDetectorHandler.register(flutterEngine, applicationContext)
    }

    /**
     * Перехватываем результат системного диалога записи экрана (MediaProjection) ДО того,
     * как super.onActivityResult передаст его во фрагмент flutter_webrtc.
     * На Android 10–15 вызов getMediaProjection() требует активного ForegroundService
     * с типом FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION.
     */
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (resultCode == Activity.RESULT_OK && data != null) {
            CallForegroundService.promoteToMediaProjection(applicationContext)
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    fun enableCallLockScreenWakeup(enable: Boolean) {
        runOnUiThread {
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                    setShowWhenLocked(enable)
                    setTurnScreenOn(enable)
                    if (enable) {
                        val km = getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
                        km?.requestDismissKeyguard(this, null)
                    }
                } else {
                    @Suppress("DEPRECATION")
                    if (enable) {
                        window.addFlags(
                            WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                                    WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
                                    WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD
                        )
                    } else {
                        window.clearFlags(
                            WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                                    WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
                                    WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD
                        )
                    }
                }
                if (enable) {
                    window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                } else {
                    window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                }
            } catch (_: Exception) {}
        }
    }

    private fun applyLockScreenFlagsIfNeeded(intent: Intent?) {
        val payload = intent?.getStringExtra("payload") ?: ""
        val isCallIntent = payload.contains("incoming_call") ||
                payload.startsWith("call_") ||
                intent?.getBooleanExtra("is_incoming_call", false) == true
        if (isCallIntent) {
            enableCallLockScreenWakeup(true)
        }
    }
}
