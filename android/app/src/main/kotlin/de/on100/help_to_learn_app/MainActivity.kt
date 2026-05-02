package de.on100.help_to_learn_app

import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var lifecycleChannel: MethodChannel? = null

    companion object {
        var audioChannel: MethodChannel? = null
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        lifecycleChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "app_lifecycle"
        )

        val audioCh = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "help_to_learn/audio"
        )
        audioChannel = audioCh
        AudioForegroundService.channel = audioCh

        audioCh.setMethodCallHandler { call, result ->
            when (call.method) {
                "startForegroundNotification" -> {
                    val intent = Intent(this@MainActivity, AudioForegroundService::class.java)
                    if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                        startForegroundService(intent)
                    } else {
                        startService(intent)
                    }
                    val args = call.arguments as? Map<*, *> ?: emptyMap<String, Any>()
                    android.os.Handler(mainLooper).postDelayed({
                        AudioForegroundService.instance?.startForegroundNotification(args)
                    }, 100)
                    result.success(null)
                }
                "stopForeground" -> {
                    AudioForegroundService.instance?.stopServiceAndNotification()
                    result.success(null)
                }
                "updateNotification" -> {
                    val args = call.arguments as? Map<*, *>
                    if (args != null) {
                        AudioForegroundService.instance?.updateNotification(args)
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        Log.i("MainActivity", "onDestroy: requesting Dart audio cleanup")
        var destroyed = false
        val handler = Handler(Looper.getMainLooper())
        val parentOnDestroy = { super.onDestroy() }

        val timeout = Runnable {
            if (!destroyed) {
                destroyed = true
                Log.w("MainActivity", "onDestroy: Dart response timed out, forcing destroy")
                parentOnDestroy()
            }
        }
        handler.postDelayed(timeout, 2000)

        try {
            lifecycleChannel?.invokeMethod("onDestroy", null, object : MethodChannel.Result {
                override fun success(result: Any?) {
                    if (!destroyed) {
                        destroyed = true
                        handler.removeCallbacks(timeout)
                        Log.i("MainActivity", "onDestroy: Dart cleanup completed, proceeding to super.onDestroy")
                        parentOnDestroy()
                    }
                }
                override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                    if (!destroyed) {
                        destroyed = true
                        handler.removeCallbacks(timeout)
                        Log.w("MainActivity", "onDestroy: Dart cleanup error: $errorMessage")
                        parentOnDestroy()
                    }
                }
                override fun notImplemented() {
                    if (!destroyed) {
                        destroyed = true
                        handler.removeCallbacks(timeout)
                        Log.w("MainActivity", "onDestroy: method not implemented in Dart")
                        parentOnDestroy()
                    }
                }
            })
        } catch (e: Exception) {
            if (!destroyed) {
                destroyed = true
                handler.removeCallbacks(timeout)
                Log.e("MainActivity", "onDestroy: failed to send cleanup signal", e)
                parentOnDestroy()
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        val fixedData = data ?: Intent()
        if (fixedData.action == null) {
            fixedData.action = ""
        }
        super.onActivityResult(requestCode, resultCode, fixedData)
    }
}
