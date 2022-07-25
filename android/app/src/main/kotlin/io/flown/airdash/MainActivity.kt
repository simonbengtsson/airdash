package io.flown.airdash

import android.content.ActivityNotFoundException
import android.content.Intent
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity: FlutterActivity() {
    private val communicatorChannel = "io.flown.airdash/communicator"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        MethodChannel(messenger, communicatorChannel).setMethodCallHandler {
                call, result ->
            if (call.method == "openFile") {
                val url: String = call.argument("url")!!
                val file = File(url)
                val providerName = activity.applicationContext.packageName + ".provider"
                val uri = FileProvider.getUriForFile(activity, providerName, file)
                val launchIntent = Intent(Intent.ACTION_VIEW)
                    .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    .setData(uri)
                try {
                    activity.startActivity(launchIntent)
                    result.success(true)
                } catch (e: ActivityNotFoundException) {
                    result.error("ACTIVITY_NOT_FOUND", "No activity", null)
                }
            }

        }
    }
}
