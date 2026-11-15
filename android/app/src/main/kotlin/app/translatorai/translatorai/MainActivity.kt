package app.translatorai.translatorai

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.view.WindowManager
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/// Hands a downloaded update to Android's own installer. Only a file inside
/// the app's cache "updates" folder is ever offered (see res/xml/update_paths.xml).
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // small system services the app needs: keep the screen on while listening,
        // and the app's own settings page (to grant the microphone after a refusal)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "translatorai/system").setMethodCallHandler { call, result ->
            when (call.method) {
                "keepScreenOn" -> {
                    if (call.argument<Boolean>("on") == true) {
                        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    } else {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    }
                    result.success(null)
                }
                "openAppSettings" -> {
                    startActivity(
                        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName"))
                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    )
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "translatorai/installer").setMethodCallHandler { call, result ->
            when (call.method) {
                "canInstall" -> result.success(
                    Build.VERSION.SDK_INT < Build.VERSION_CODES.O || packageManager.canRequestPackageInstalls()
                )
                "openInstallSettings" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startActivity(
                            Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName"))
                                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        )
                    }
                    result.success(null)
                }
                "install" -> {
                    val path = call.argument<String>("path")
                    val updates = File(cacheDir, "updates").canonicalFile
                    val apk = path?.let { File(it).canonicalFile }
                    if (apk == null || apk.parentFile != updates || !apk.name.endsWith(".apk") || !apk.isFile) {
                        result.error("bad_path", "not a downloaded update", null)
                    } else {
                        val uri = FileProvider.getUriForFile(this, "$packageName.updates", apk)
                        startActivity(
                            Intent(Intent.ACTION_VIEW)
                                .setDataAndType(uri, "application/vnd.android.package-archive")
                                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
                        )
                        result.success(null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
