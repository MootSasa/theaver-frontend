package app.theaver.messenger

import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.content.ContextCompat
import com.google.android.gms.auth.api.phone.SmsRetriever
import com.google.android.gms.common.api.CommonStatusCodes
import com.google.android.gms.common.api.Status
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.lang.ref.WeakReference

/**
 * Native Android bridge for one-tap SMS OTP retrieval via Google Play Services
 * SMS User Consent API (`app.theaver.messenger/browser_otp`).
 *
 * Gracefully no-ops on devices without GMS (e.g., Huawei / AOSP) so OTP
 * fields never crash.
 */
object BrowserOtpChannel {
    private const val CHANNEL_NAME = "app.theaver.messenger/browser_otp"
    const val REQUEST_SMS_CONSENT = 47022

    private val mainHandler = Handler(Looper.getMainLooper())
    private var channel: MethodChannel? = null
    private var activityRef: WeakReference<Activity>? = null
    private var receiverContextRef: WeakReference<Context>? = null
    private var smsReceiver: BroadcastReceiver? = null

    fun register(flutterEngine: FlutterEngine, activity: Activity) {
        if (activityRef?.get() !== activity) {
            unregisterReceiver()
        }
        activityRef = WeakReference(activity)
        channel?.setMethodCallHandler(null)
        val mc = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
        channel = mc
        mc.setMethodCallHandler { call: MethodCall, result: MethodChannel.Result ->
            when (call.method) {
                "startSmsConsent" -> {
                    val act = activityRef?.get()
                    if (act == null || act.isFinishing || act.isDestroyed) {
                        result.success(false)
                    } else {
                        result.success(startSmsConsent(act))
                    }
                }

                "stopSmsConsent" -> {
                    unregisterReceiver()
                    result.success(true)
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun startSmsConsent(activity: Activity): Boolean {
        return try {
            ensureReceiverRegistered(activity)
            val task = SmsRetriever.getClient(activity).startSmsUserConsent(null)
            task.addOnFailureListener {
                unregisterReceiver()
            }
            true
        } catch (_: Throwable) {
            unregisterReceiver()
            false
        }
    }

    private fun ensureReceiverRegistered(activity: Activity) {
        if (smsReceiver != null) return
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (intent?.action != SmsRetriever.SMS_RETRIEVED_ACTION) return
                val extras = intent.extras ?: return
                val status: Status = try {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        extras.getParcelable(SmsRetriever.EXTRA_STATUS, Status::class.java)
                    } else {
                        @Suppress("DEPRECATION")
                        extras.get(SmsRetriever.EXTRA_STATUS) as? Status
                    }
                } catch (_: Throwable) {
                    null
                } ?: return

                when (status.statusCode) {
                    CommonStatusCodes.SUCCESS -> {
                        val consentIntent: Intent = try {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                                extras.getParcelable(
                                    SmsRetriever.EXTRA_CONSENT_INTENT,
                                    Intent::class.java,
                                )
                            } else {
                                @Suppress("DEPRECATION")
                                extras.getParcelable(SmsRetriever.EXTRA_CONSENT_INTENT)
                            }
                        } catch (_: Throwable) {
                            null
                        } ?: run {
                            unregisterReceiver()
                            return
                        }

                        val act = activityRef?.get()
                        if (act == null || act.isFinishing || act.isDestroyed) {
                            unregisterReceiver()
                            return
                        }

                        val resolvedPkg = try {
                            consentIntent.resolveActivity(act.packageManager)?.packageName
                        } catch (_: Throwable) {
                            null
                        }
                        if (resolvedPkg == "com.google.android.gms") {
                            try {
                                act.startActivityForResult(consentIntent, REQUEST_SMS_CONSENT)
                            } catch (_: Throwable) {
                                unregisterReceiver()
                            }
                        } else {
                            unregisterReceiver()
                        }
                    }

                    CommonStatusCodes.TIMEOUT -> {
                        unregisterReceiver()
                    }
                }
            }
        }

        try {
            val filter = IntentFilter(SmsRetriever.SMS_RETRIEVED_ACTION)
            ContextCompat.registerReceiver(
                activity,
                receiver,
                filter,
                SmsRetriever.SEND_PERMISSION,
                null,
                ContextCompat.RECEIVER_EXPORTED,
            )
            smsReceiver = receiver
            receiverContextRef = WeakReference(activity)
        } catch (_: Throwable) {
            smsReceiver = null
            receiverContextRef = null
        }
    }

    private fun unregisterReceiver() {
        val receiver = smsReceiver ?: return
        smsReceiver = null
        val ctx = receiverContextRef?.get()
        receiverContextRef = null
        if (ctx != null) {
            try {
                ctx.unregisterReceiver(receiver)
            } catch (_: Throwable) {}
        }
    }

    fun handleActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_SMS_CONSENT) return false
        unregisterReceiver()
        if (resultCode == Activity.RESULT_OK && data != null) {
            val message = try {
                data.getStringExtra(SmsRetriever.EXTRA_SMS_MESSAGE)
            } catch (_: Throwable) {
                null
            }
            if (!message.isNullOrBlank()) {
                mainHandler.post {
                    channel?.invokeMethod("onSmsReceived", mapOf("message" to message))
                }
            }
        }
        return true
    }

    fun dispose() {
        unregisterReceiver()
        channel?.setMethodCallHandler(null)
        channel = null
        activityRef = null
    }
}
