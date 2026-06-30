package com.behavior.exodo

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Intent
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.behavior.exodo/widgets"
    private var initialPrompt: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        initialPrompt = intent.getStringExtra("widget_prompt")
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val prompt = intent.getStringExtra("widget_prompt")
        if (!prompt.isNullOrBlank()) {
            flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
                MethodChannel(messenger, CHANNEL).invokeMethod("onWidgetPrompt", prompt)
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialPrompt" -> {
                    result.success(initialPrompt)
                    initialPrompt = null
                }
                "pinWidget" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        val type = call.argument<String>("type") ?: "grok"
                        val appWidgetManager = AppWidgetManager.getInstance(this)
                        val providerClass = if (type == "grok_light") {
                            ExodoLightWidgetProvider::class.java
                        } else {
                            ExodoWidgetProvider::class.java
                        }
                        val provider = ComponentName(this, providerClass)
                        if (appWidgetManager.isRequestPinAppWidgetSupported) {
                            appWidgetManager.requestPinAppWidget(provider, null, null)
                            result.success(true)
                        } else {
                            result.success(false)
                        }
                    } else {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
