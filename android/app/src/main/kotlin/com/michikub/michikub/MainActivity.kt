package com.michikub.michikub

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Online games: keep the connection alive in the background (see GameLinkService).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "michikub/keepalive").setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    if (Build.VERSION.SDK_INT >= 33 &&
                        checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
                    ) {
                        // Without it the service still runs, just without a visible notification.
                        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 7)
                    }
                    val i = Intent(this, GameLinkService::class.java).putExtra(GameLinkService.EXTRA_TEXT, call.argument<String>("text"))
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(i) else startService(i)
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "stop" -> {
                    stopService(Intent(this, GameLinkService::class.java))
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        if (isFinishing) stopService(Intent(this, GameLinkService::class.java))
        super.onDestroy()
    }
}
