package app.theaver.messenger

import android.annotation.SuppressLint
import android.app.Activity
import android.graphics.Matrix
import android.graphics.Path
import android.graphics.PathMeasure
import android.graphics.Rect
import android.graphics.RectF
import android.os.Build
import android.os.Looper
import android.view.Surface
import androidx.core.graphics.PathParser
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlin.math.abs
import kotlin.math.min

/**
 * Provides accurate physical camera cutout / notch geometry in logical `dp`
 * for the profile avatar metaball effect (supporting centered punch-holes,
 * wide/teardrop notches, left/right corner punch-holes, and unifying dual
 * front cameras into a single stadium oval).
 */
object DisplayCutoutChannel {
    private const val CHANNEL_NAME = "app.theaver.messenger/display_cutout"
    private const val BOTTOM_MARKER = "@bottom"
    private const val DP_MARKER = "@dp"
    private const val RIGHT_MARKER = "@right"
    private const val LEFT_MARKER = "@left"

    fun register(flutterEngine: FlutterEngine, activity: Activity) {
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL_NAME
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getDisplayCutout" -> {
                    val runQuery = Runnable {
                        try {
                            result.success(queryDisplayCutout(activity))
                        } catch (_: Throwable) {
                            result.success(mapOf("hasCutout" to false))
                        }
                    }
                    if (Looper.myLooper() == Looper.getMainLooper()) {
                        runQuery.run()
                    } else {
                        activity.runOnUiThread(runQuery)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun queryDisplayCutout(activity: Activity): Map<String, Any?> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) {
            return mapOf("hasCutout" to false)
        }

        val metrics = activity.resources.displayMetrics
        val density = metrics.density.coerceAtLeast(1f)
        val decorView = activity.window?.decorView
        val screenWidthPx = (decorView?.width?.takeIf { it > 0 } ?: metrics.widthPixels).toFloat()
        val screenHeightPx = (decorView?.height?.takeIf { it > 0 } ?: metrics.heightPixels).toFloat()

        // Only attach avatar metaball to top physical cutouts in portrait layout.
        if (screenWidthPx <= 0f || screenHeightPx <= 0f || screenWidthPx > screenHeightPx) {
            return mapOf("hasCutout" to false)
        }

        val rootInsets = decorView?.rootWindowInsets ?: return mapOf("hasCutout" to false)
        val displayCutout = rootInsets.displayCutout ?: return mapOf("hasCutout" to false)

        val maxTopThresholdPx = 56f * density
        val topRects = displayCutout.boundingRects
            .filter { it.width() > 0 && it.height() > 0 && it.top < maxTopThresholdPx }
            .sortedBy { it.left }

        if (topRects.isEmpty()) {
            return mapOf("hasCutout" to false)
        }

        // Cluster nearby top cutout rects (gap <= 28dp) into one unified oval bounding box.
        val maxClusterGapPx = 28f * density
        val clusters = mutableListOf<RectF>()
        for (r: Rect in topRects) {
            val rf = RectF(r)
            val last = clusters.lastOrNull()
            if (last != null && rf.left - last.right <= maxClusterGapPx) {
                last.union(rf)
            } else {
                clusters.add(rf)
            }
        }
        val windowClusterRect = clusters.minByOrNull { abs(it.centerX() - screenWidthPx * 0.5f) }
            ?: clusters.first()
        var mergedMultipleSensors = topRects.size > 1

        val rotation = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            try {
                activity.display?.rotation ?: Surface.ROTATION_0
            } catch (_: Throwable) {
                Surface.ROTATION_0
            }
        } else {
            @Suppress("DEPRECATION")
            activity.windowManager?.defaultDisplay?.rotation ?: Surface.ROTATION_0
        }

        var exactRectPx: RectF? = null
        var exactPathPx: Path? = null
        var pathHasCurves = false

        // 1. Prefer Android 12+ (API 31+) WindowManager-transformed cutoutPath when available.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val osCutoutPath = displayCutout.cutoutPath
            if (osCutoutPath != null) {
                val parsed = extractTopContoursBoundsAndPath(osCutoutPath, maxTopThresholdPx)
                if (parsed != null && abs(parsed.bounds.centerX() - windowClusterRect.centerX()) <= 28f * density) {
                    exactRectPx = parsed.bounds
                    exactPathPx = parsed.singleContourPath
                    if (parsed.contourCount > 1) {
                        mergedMultipleSensors = true
                    }
                    pathHasCurves = parsed.contourCount == 1
                }
            }
        }

        // 2. Supplement/fallback to AOSP internal SVG resource `config_mainBuiltInDisplayCutout` in ROTATION_0.
        val specInfo = if (rotation == Surface.ROTATION_0) {
            parseBuiltInCutoutResource(activity, screenWidthPx, density)
        } else {
            null
        }
        if (specInfo != null && abs(specInfo.bounds.centerX() - windowClusterRect.centerX()) <= 28f * density) {
            if (exactRectPx == null) {
                exactRectPx = specInfo.bounds
                exactPathPx = if (specInfo.contourCount == 1) specInfo.path else null
            }
            if (specInfo.contourCount > 1) {
                mergedMultipleSensors = true
            }
            pathHasCurves = pathHasCurves || specInfo.hasCurves
        }

        val finalRectPx = exactRectPx ?: windowClusterRect
        val screenWidthDp = screenWidthPx / density
        val leftDp = (finalRectPx.left / density).coerceAtLeast(0f)
        val topDp = (finalRectPx.top / density).coerceAtLeast(0f)
        val widthDp = (finalRectPx.width() / density).coerceAtLeast(8f)
        val heightDp = (finalRectPx.height() / density).coerceAtLeast(8f)
        val centerXDp = leftDp + widthDp * 0.5f

        val gravity = when {
            abs(centerXDp - screenWidthDp * 0.5f) <= 12f -> "center"
            centerXDp < screenWidthDp * 0.5f -> "left"
            else -> "right"
        }

        val isOvalOrPill = mergedMultipleSensors || widthDp > heightDp * 1.15f
        val kind = when {
            gravity != "center" -> "punchHole"
            topDp >= 2.5f || widthDp <= 72f -> "punchHole"
            else -> "topNotch"
        }

        val cornerRadiusDp = if (kind == "punchHole" || isOvalOrPill) {
            min(widthDp, heightDp) * 0.5f
        } else {
            min(widthDp * 0.25f, heightDp * 0.55f)
        }

        // Sample curved single-contour topNotch outline into logical-dp polygon points
        // so custom teardrop/waterdrop notches match the hardware contour accurately.
        val contourPointsDp: List<Double>? = if (
            kind == "topNotch" &&
            !mergedMultipleSensors &&
            pathHasCurves &&
            exactPathPx != null
        ) {
            samplePathPointsDp(exactPathPx, density, maxSamples = 40)
        } else {
            null
        }

        return mapOf(
            "hasCutout" to true,
            "kind" to kind,
            "gravity" to gravity,
            "left" to leftDp.toDouble(),
            "top" to topDp.toDouble(),
            "width" to widthDp.toDouble(),
            "height" to heightDp.toDouble(),
            "cornerRadius" to cornerRadiusDp.toDouble(),
            "isOval" to isOvalOrPill,
            "polygonDp" to contourPointsDp
        )
    }

    private data class ContourScanResult(
        val bounds: RectF,
        val contourCount: Int,
        val singleContourPath: Path?
    )

    private fun extractTopContoursBoundsAndPath(sourcePath: Path, maxTopPx: Float): ContourScanResult? {
        val pm = PathMeasure(sourcePath, false)
        val merged = RectF()
        var topContours = 0
        var singlePath: Path? = null
        val pos = FloatArray(2)

        do {
            val len = pm.length
            if (len > 1f) {
                val contourPath = Path()
                if (pm.getSegment(0f, len, contourPath, true)) {
                    contourPath.close()
                    val cb = RectF()
                    contourPath.computeBounds(cb, true)
                    if (cb.width() > 0f && cb.height() > 0f && cb.top < maxTopPx) {
                        if (topContours == 0) {
                            merged.set(cb)
                            singlePath = contourPath
                        } else {
                            merged.union(cb)
                            singlePath = null
                        }
                        topContours++
                    }
                }
            } else if (pm.getPosTan(0f, pos, null)) {
                // Ignore degenerate zero-length contours
            }
        } while (pm.nextContour())

        if (topContours == 0 || merged.width() <= 0f || merged.height() <= 0f) {
            return null
        }
        return ContourScanResult(
            bounds = merged,
            contourCount = topContours,
            singleContourPath = singlePath
        )
    }

    private data class BuiltInSpecInfo(
        val path: Path,
        val bounds: RectF,
        val contourCount: Int,
        val hasCurves: Boolean
    )

    @SuppressLint("DiscouragedApi")
    private fun parseBuiltInCutoutResource(
        activity: Activity,
        displayWidthPx: Float,
        density: Float
    ): BuiltInSpecInfo? {
        val res = activity.resources
        val resId = res.getIdentifier("config_mainBuiltInDisplayCutout", "string", "android")
        if (resId == 0) return null
        var spec = res.getString(resId).trim()
        if (spec.isEmpty()) return null

        if (spec.contains(BOTTOM_MARKER)) {
            spec = spec.split(BOTTOM_MARKER, limit = 2)[0].trim()
            if (spec.isEmpty()) return null
        }

        val offsetX: Float = when {
            spec.endsWith(RIGHT_MARKER) -> {
                spec = spec.removeSuffix(RIGHT_MARKER).trim()
                displayWidthPx
            }
            spec.endsWith(LEFT_MARKER) -> {
                spec = spec.removeSuffix(LEFT_MARKER).trim()
                0f
            }
            else -> displayWidthPx * 0.5f
        }

        val inDp = spec.endsWith(DP_MARKER)
        if (inDp) {
            spec = spec.removeSuffix(DP_MARKER).trim()
        }
        if (spec.isEmpty()) return null

        val rawPath = try {
            PathParser.createPathFromPathData(spec)
        } catch (_: Throwable) {
            null
        } ?: return null

        val matrix = Matrix()
        if (inDp) {
            matrix.postScale(density, density)
        }
        matrix.postTranslate(offsetX, 0f)
        rawPath.transform(matrix)

        val scan = extractTopContoursBoundsAndPath(rawPath, maxTopPx = 56f * density) ?: return null
        val hasCurves = spec.contains('C', ignoreCase = true) ||
            spec.contains('S', ignoreCase = true) ||
            spec.contains('Q', ignoreCase = true) ||
            spec.contains('A', ignoreCase = true)

        return BuiltInSpecInfo(
            path = scan.singleContourPath ?: rawPath,
            bounds = scan.bounds,
            contourCount = scan.contourCount,
            hasCurves = hasCurves
        )
    }

    private fun samplePathPointsDp(pathPx: Path, density: Float, maxSamples: Int): List<Double>? {
        val pm = PathMeasure(pathPx, false)
        val length = pm.length
        if (length <= 2f || maxSamples < 8) return null
        val out = ArrayList<Double>(maxSamples * 2)
        val pos = FloatArray(2)
        for (i in 0 until maxSamples) {
            val dist = length * i.toFloat() / maxSamples.toFloat()
            if (pm.getPosTan(dist, pos, null)) {
                out.add((pos[0] / density).toDouble())
                out.add((pos[1] / density).toDouble())
            }
        }
        return if (out.size >= 12) out else null
    }
}
