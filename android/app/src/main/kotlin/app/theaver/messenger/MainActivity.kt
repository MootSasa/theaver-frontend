package app.theaver.messenger

import android.app.Activity
import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import android.hardware.display.DisplayManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.Display
import android.view.MotionEvent
import android.view.Surface
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import java.lang.ref.WeakReference
import java.util.Collections
import java.util.WeakHashMap
import kotlin.math.abs

class MainActivity : FlutterFragmentActivity() {

    companion object {
        private var currentActivityRef: WeakReference<MainActivity>? = null

        fun getCurrentActivity(): MainActivity? = currentActivityRef?.get()
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private val hookedSurfaceHolders: MutableSet<SurfaceHolder> =
        Collections.newSetFromMap(WeakHashMap())
    private var cachedFlutterSurfaceViewRef: WeakReference<SurfaceView>? = null
    private var targetRefreshRateHz: Float = 0f
    private var targetDisplayModeId: Int = 0

    private val displayListener = object : DisplayManager.DisplayListener {
        override fun onDisplayAdded(displayId: Int) {}
        override fun onDisplayRemoved(displayId: Int) {}
        override fun onDisplayChanged(displayId: Int) {
            applyHighRefreshRate()
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        currentActivityRef = WeakReference(this)
        applyLockScreenFlagsIfNeeded(intent)
        applyHighRefreshRate()
        window?.decorView?.post { applyHighRefreshRate() }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        applyLockScreenFlagsIfNeeded(intent)
    }

    override fun onResume() {
        super.onResume()
        currentActivityRef = WeakReference(this)
        val dm = getSystemService(Context.DISPLAY_SERVICE) as? DisplayManager
        dm?.registerDisplayListener(displayListener, mainHandler)
        applyHighRefreshRate()
        window?.decorView?.post { applyHighRefreshRate() }
    }

    override fun onPause() {
        val dm = getSystemService(Context.DISPLAY_SERVICE) as? DisplayManager
        dm?.unregisterDisplayListener(displayListener)
        super.onPause()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) {
            applyHighRefreshRate()
        }
    }

    override fun dispatchTouchEvent(ev: MotionEvent?): Boolean {
        val handled = super.dispatchTouchEvent(ev)
        val action = ev?.actionMasked
        if (action == MotionEvent.ACTION_UP || action == MotionEvent.ACTION_CANCEL) {
            // Prevent LTPO / OEM Touch-Boost governors from dropping VSYNC to 60Hz/30Hz
            // when the finger is lifted off the screen.
            ensureHighRefreshRateOnTouchEnd()
        }
        return handled
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
     * Locks the highest supported display refresh rate (90Hz / 120Hz / 144Hz) on both
     * the Window (preferredDisplayModeId / preferredRefreshRate) and the FlutterSurfaceView's
     * Surface (Surface.setFrameRate), preventing Android's Touch-Boost / LTPO governor from
     * throttling the app down to 60Hz/30Hz as soon as the user lifts their finger (ACTION_UP).
     */
    private fun applyHighRefreshRate() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        try {
            val currentDisplay: Display = (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                try {
                    display
                } catch (_: Exception) {
                    null
                }
            } else {
                null
            }) ?: @Suppress("DEPRECATION") windowManager.defaultDisplay ?: return

            val supportedModes = currentDisplay.supportedModes
            if (supportedModes.isNullOrEmpty()) return

            val activeMode = currentDisplay.mode
            val sameResolutionModes = if (activeMode != null) {
                supportedModes.filter {
                    it.physicalWidth == activeMode.physicalWidth &&
                            it.physicalHeight == activeMode.physicalHeight
                }
            } else {
                emptyList()
            }

            val candidateModes = if (sameResolutionModes.isNotEmpty()) {
                sameResolutionModes
            } else {
                supportedModes.toList()
            }

            val bestMode = candidateModes.maxWithOrNull(
                compareBy<Display.Mode> { it.refreshRate }
                    .thenBy { it.physicalWidth.toLong() * it.physicalHeight.toLong() }
            ) ?: return

            targetRefreshRateHz = bestMode.refreshRate
            targetDisplayModeId = bestMode.modeId

            val win = window ?: return
            val params = win.attributes
            if (params.preferredDisplayModeId != bestMode.modeId ||
                abs(params.preferredRefreshRate - bestMode.refreshRate) > 0.01f
            ) {
                params.preferredDisplayModeId = bestMode.modeId
                params.preferredRefreshRate = bestMode.refreshRate
                win.attributes = params
            }

            val decorView = win.decorView
            bindSurfaceViewsForHighRefreshRate(decorView, bestMode.refreshRate)
        } catch (_: Exception) {}
    }

    private fun ensureHighRefreshRateOnTouchEnd() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        try {
            if (targetDisplayModeId == 0 || targetRefreshRateHz <= 60f) {
                applyHighRefreshRate()
                return
            }
            val win = window ?: return
            val params = win.attributes
            if (params.preferredDisplayModeId != targetDisplayModeId ||
                abs(params.preferredRefreshRate - targetRefreshRateHz) > 0.01f
            ) {
                params.preferredDisplayModeId = targetDisplayModeId
                params.preferredRefreshRate = targetRefreshRateHz
                win.attributes = params
            }

            val sv = cachedFlutterSurfaceViewRef?.get()
            if (sv != null && sv.isAttachedToWindow) {
                applySurfaceFrameRate(sv.holder.surface, targetRefreshRateHz)
            } else {
                bindSurfaceViewsForHighRefreshRate(win.decorView, targetRefreshRateHz)
            }
        } catch (_: Exception) {}
    }

    private fun bindSurfaceViewsForHighRefreshRate(root: View?, refreshRate: Float) {
        if (root == null || refreshRate <= 0f) return
        if (root is SurfaceView) {
            cachedFlutterSurfaceViewRef = WeakReference(root)
            val holder = root.holder
            if (holder != null) {
                applySurfaceFrameRate(holder.surface, refreshRate)
                if (hookedSurfaceHolders.add(holder)) {
                    holder.addCallback(object : SurfaceHolder.Callback {
                        override fun surfaceCreated(h: SurfaceHolder) {
                            val hz = if (targetRefreshRateHz > 0f) targetRefreshRateHz else refreshRate
                            applySurfaceFrameRate(h.surface, hz)
                        }

                        override fun surfaceChanged(
                            h: SurfaceHolder,
                            format: Int,
                            width: Int,
                            height: Int
                        ) {
                            val hz = if (targetRefreshRateHz > 0f) targetRefreshRateHz else refreshRate
                            applySurfaceFrameRate(h.surface, hz)
                        }

                        override fun surfaceDestroyed(h: SurfaceHolder) {}
                    })
                }
            }
        } else if (root is ViewGroup) {
            for (i in 0 until root.childCount) {
                bindSurfaceViewsForHighRefreshRate(root.getChildAt(i), refreshRate)
            }
        }
    }

    private fun applySurfaceFrameRate(surface: Surface?, refreshRate: Float) {
        if (surface == null || !surface.isValid || refreshRate <= 0f) return
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                surface.setFrameRate(
                    refreshRate,
                    Surface.FRAME_RATE_COMPATIBILITY_DEFAULT,
                    Surface.CHANGE_FRAME_RATE_ALWAYS
                )
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                surface.setFrameRate(
                    refreshRate,
                    Surface.FRAME_RATE_COMPATIBILITY_DEFAULT
                )
            }
        } catch (_: Exception) {}
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
