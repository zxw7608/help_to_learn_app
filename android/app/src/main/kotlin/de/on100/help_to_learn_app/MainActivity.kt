package de.on100.help_to_learn_app

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import com.ryanheise.audioservice.AudioServiceActivity

class MainActivity : AudioServiceActivity() {
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        val fixedData = data ?: Intent()
        if (fixedData.action == null) {
            fixedData.action = ""
        }
        super.onActivityResult(requestCode, resultCode, fixedData)
    }
}
