package app.inf.flutter

import android.app.PictureInPictureParams
import android.content.ContentValues
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.MediaStore
import android.util.Rational
import android.view.HapticFeedbackConstants
import android.webkit.CookieManager
import android.webkit.WebSettings
import android.webkit.WebView
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * The only native piece the rewrite needs: the WebView cookie store is shared between the login
 * page and the Dart HTTP client, exactly like the Compose app's WebViewCookieJar.
 */
class MainActivity : FlutterActivity() {

    private val channelName = "app.inf.flutter/native"

    override fun onCreate(savedInstanceState: Bundle?) {
        // Run before the engine so Dart's first cookie read sees a seeded session.
        if (BuildConfig.DEBUG) seedCookies()
        super.onCreate(savedInstanceState)
    }

    private fun seedCookies() {
        intent?.getStringExtra("seedCookie")?.takeIf { it.isNotBlank() }?.let { raw ->
            val manager = CookieManager.getInstance()
            raw.split(';').map { it.trim() }.filter { it.contains('=') }.forEach {
                manager.setCookie("https://m.weibo.cn/", it)
            }
            manager.flush()
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        if (BuildConfig.DEBUG) WebView.setWebContentsDebuggingEnabled(true)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "getCookies" -> {
                            val url = call.argument<String>("url") ?: "https://m.weibo.cn/"
                            val manager = CookieManager.getInstance()
                            manager.flush()
                            result.success(manager.getCookie(url) ?: "")
                        }
                        "setCookie" -> {
                            val url = call.argument<String>("url") ?: "https://m.weibo.cn/"
                            val value = call.argument<String>("value") ?: ""
                            val manager = CookieManager.getInstance()
                            manager.setCookie(url, value)
                            manager.flush()
                            result.success(true)
                        }
                        "clearCookies" -> {
                            val manager = CookieManager.getInstance()
                            manager.removeAllCookies(null)
                            manager.flush()
                            result.success(true)
                        }
                        "clearAuthCookies" -> {
                            val manager = CookieManager.getInstance()
                            // getCookie() does not report a cookie's Domain, and an expiring
                            // Set-Cookie only replaces a cookie with the same domain, so
                            // expire each name both as host-only and on its parent domain.
                            val hosts = mapOf(
                                "m.weibo.cn" to ".weibo.cn",
                                "weibo.com" to ".weibo.com",
                                "passport.weibo.com" to ".weibo.com",
                                "login.sina.com.cn" to ".sina.com.cn",
                                "passport.sina.cn" to ".sina.cn",
                            )
                            val names = listOf("SUB", "SUBP", "ALF", "SSOLoginState", "MLOGIN", "SCF")
                            for ((host, domain) in hosts) {
                                val url = "https://$host/"
                                for (name in names) {
                                    manager.setCookie(url, "$name=; Max-Age=0; Path=/; Secure")
                                    manager.setCookie(url, "$name=; Max-Age=0; Path=/; Domain=$domain; Secure")
                                }
                            }
                            manager.flush()
                            result.success(true)
                        }
                        "userAgent" -> result.success(WebSettings.getDefaultUserAgent(this))
                        "isMetered" -> {
                            val manager = getSystemService(ConnectivityManager::class.java)
                            result.success(manager?.isActiveNetworkMetered ?: true)
                        }
                        "isPipAvailable" -> result.success(
                            Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                                packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)
                        )
                        "enterPip" -> {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                                packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)
                            ) {
                                val ratio = (call.argument<Double>("aspectRatio") ?: (16.0 / 9.0))
                                    .coerceIn(0.42, 2.39)
                                val params = PictureInPictureParams.Builder()
                                    .setAspectRatio(Rational((ratio * 1000).toInt(), 1000))
                                    .build()
                                result.success(enterPictureInPictureMode(params))
                            } else {
                                result.success(false)
                            }
                        }
                        "saveImage" -> {
                            val path = call.argument<String>("path")
                            val name = call.argument<String>("name") ?: "INF-image.jpg"
                            val mime = call.argument<String>("mime") ?: "image/jpeg"
                            if (path.isNullOrBlank()) {
                                result.error("save_image", "missing path", null)
                            } else {
                                Thread {
                                    try {
                                        val saved = saveImageToGallery(File(path), name, mime)
                                        runOnUiThread { result.success(saved) }
                                    } catch (error: Throwable) {
                                        runOnUiThread { result.error("save_image", error.message, null) }
                                    }
                                }.start()
                            }
                        }
                        "saveVideo" -> {
                            val path = call.argument<String>("path")
                            val name = call.argument<String>("name") ?: "INF-video.mp4"
                            if (path.isNullOrBlank()) {
                                result.error("save_video", "missing path", null)
                            } else {
                                Thread {
                                    try {
                                        val saved = saveVideoToGallery(File(path), name)
                                        runOnUiThread { result.success(saved) }
                                    } catch (error: Throwable) {
                                        runOnUiThread { result.error("save_video", error.message, null) }
                                    }
                                }.start()
                            }
                        }
                        "peakRefreshRate" -> {
                            val peak = display?.supportedModes?.maxByOrNull { it.refreshRate }
                            if (peak != null) {
                                runOnUiThread {
                                    window.attributes = window.attributes.apply {
                                        preferredRefreshRate = peak.refreshRate
                                    }
                                }
                                result.success(peak.refreshRate.toDouble())
                            } else {
                                result.success(null)
                            }
                        }
                        "haptic" -> result.success(
                            window.decorView.performHapticFeedback(hapticConstant(call.argument<String>("kind")))
                        )
                        else -> result.notImplemented()
                    }
                } catch (error: Throwable) {
                    result.error("native_error", error.message, null)
                }
            }
    }

    /**
     * System constants instead of raw vibrator timings: each vendor tunes these waveforms for its
     * motor, and performHapticFeedback honours the system touch-feedback switch without VIBRATE.
     */
    private fun hapticConstant(kind: String?): Int {
        val sdk = Build.VERSION.SDK_INT
        return when (kind) {
            "toggleOn" -> if (sdk >= 34) HapticFeedbackConstants.TOGGLE_ON else HapticFeedbackConstants.CONTEXT_CLICK
            "toggleOff" -> if (sdk >= 34) HapticFeedbackConstants.TOGGLE_OFF else HapticFeedbackConstants.CLOCK_TICK
            "longPress" -> HapticFeedbackConstants.LONG_PRESS
            "threshold" -> if (sdk >= 34) {
                HapticFeedbackConstants.GESTURE_THRESHOLD_ACTIVATE
            } else {
                HapticFeedbackConstants.CONTEXT_CLICK
            }
            "thresholdRelease" -> if (sdk >= 34) {
                HapticFeedbackConstants.GESTURE_THRESHOLD_DEACTIVATE
            } else {
                HapticFeedbackConstants.CLOCK_TICK
            }
            "success" -> if (sdk >= 30) HapticFeedbackConstants.CONFIRM else HapticFeedbackConstants.VIRTUAL_KEY
            "error" -> if (sdk >= 30) HapticFeedbackConstants.REJECT else HapticFeedbackConstants.LONG_PRESS
            else -> HapticFeedbackConstants.CLOCK_TICK
        }
    }

    private fun saveImageToGallery(source: File, name: String, mime: String): String? {
        if (!source.exists() || Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return null
        val resolver = contentResolver
        val values = ContentValues().apply {
            put(MediaStore.Images.Media.DISPLAY_NAME, name)
            put(MediaStore.Images.Media.MIME_TYPE, mime)
            put(MediaStore.Images.Media.RELATIVE_PATH, Environment.DIRECTORY_PICTURES + "/INF")
            put(MediaStore.Images.Media.IS_PENDING, 1)
        }
        val uri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
            ?: return null
        resolver.openOutputStream(uri)?.use { out -> source.inputStream().use { it.copyTo(out) } }
        values.clear()
        values.put(MediaStore.Images.Media.IS_PENDING, 0)
        resolver.update(uri, values, null, null)
        return "Pictures/INF/$name"
    }

    private fun saveVideoToGallery(source: File, name: String): String? {
        if (!source.exists() || Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return null
        val resolver = contentResolver
        val values = ContentValues().apply {
            put(MediaStore.Video.Media.DISPLAY_NAME, name)
            put(MediaStore.Video.Media.MIME_TYPE, "video/mp4")
            put(MediaStore.Video.Media.RELATIVE_PATH, Environment.DIRECTORY_MOVIES + "/INF")
            put(MediaStore.Video.Media.IS_PENDING, 1)
        }
        val uri = resolver.insert(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, values)
            ?: return null
        resolver.openOutputStream(uri)?.use { out -> source.inputStream().use { it.copyTo(out) } }
        values.clear()
        values.put(MediaStore.Video.Media.IS_PENDING, 0)
        resolver.update(uri, values, null, null)
        return "Movies/INF/$name"
    }
}