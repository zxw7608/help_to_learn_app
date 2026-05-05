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

        // Store incoming text for later delivery if Flutter isn't ready yet
        @Volatile
        var pendingProcessText: String? = null
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

        // Channel for receiving text from PROCESS_TEXT intent
        val processTextChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "help_to_learn/process_text"
        )

        // Deliver any pending text that arrived before Flutter was ready
        val pending = pendingProcessText
        if (pending != null) {
            pendingProcessText = null
            Handler(Looper.getMainLooper()).post {
                processTextChannel.invokeMethod("onProcessText", pending)
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntent(intent)
    }

    override fun onResume() {
        super.onResume()
        // Check if we were launched via PROCESS_TEXT
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        if (intent?.action == Intent.ACTION_PROCESS_TEXT) {
            val text = intent.getStringExtra(Intent.EXTRA_PROCESS_TEXT)?.trim()
            if (!text.isNullOrEmpty()) {
                Log.i("MainActivity", "Received PROCESS_TEXT: ${text.take(100)}...")
                deliverTextToFlutter(text)
            }
        }
    }

    private fun deliverTextToFlutter(text: String) {
        val channel = MethodChannel(
            flutterEngine?.dartExecutor?.binaryMessenger ?: return,
            "help_to_learn/process_text"
        )
        try {
            channel.invokeMethod("onProcessText", text)
        } catch (e: Exception) {
            // Flutter not ready yet — store for later delivery
            Log.w("MainActivity", "Flutter not ready, storing text for later")
            pendingProcessText = text
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
