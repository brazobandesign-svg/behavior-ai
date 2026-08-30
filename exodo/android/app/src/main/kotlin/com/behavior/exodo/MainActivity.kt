package com.behavior.exodo

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        private const val TAG = "MainActivity"
        private const val CHANNEL = "com.behavior.exodo/widgets"
        private const val APP_INFO_CHANNEL = "exodo/app_info"
        private const val EXTRA_WIDGET_PROMPT = "widget_prompt"
        private const val MAX_DELIVERY_RETRIES = 3
        private const val RETRY_DELAY_MS = 1500L
    }

    private val mainHandler = Handler(Looper.getMainLooper())

    /**
     * Buffer único del prompt recibido del widget. Es la única fuente de
     * verdad para evitar entregas duplicadas entre el arranque en frío
     * (getInitialPrompt, cuando ChatScreen levanta) y la app ya en memoria
     * (onWidgetPrompt, vía onNewIntent). Solo se limpia cuando Dart confirma
     * la recepción o cuando ChatScreen lo consume.
     */
    private var pendingPrompt: String? = null
    private var deliveryAttempts = 0

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        extractWidgetPrompt(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        extractWidgetPrompt(intent)
        // La actividad ya existía y el engine debería estar vivo:
        // intentar la entrega inmediata a Dart.
        deliverPendingPrompt()
    }

    private fun extractWidgetPrompt(intent: Intent?) {
        val prompt = intent?.getStringExtra(EXTRA_WIDGET_PROMPT)?.trim()
        if (prompt.isNullOrEmpty()) return
        Log.d(TAG, "Prompt recibido del widget (${prompt.length} caracteres)")
        pendingPrompt = prompt
        deliveryAttempts = 0
    }

    /**
     * Envía el prompt pendiente a Flutter. Si Dart aún no registró el handler
     * (engine calentando tras la muerte del proceso), el invokeMethod responde
     * notImplemented: se reintenta con retardo y el prompt permanece en el
     * buffer, disponible también para getInitialPrompt cuando ChatScreen
     * inicialice su listener. Así ningún prompt se pierde en la transición.
     */
    private fun deliverPendingPrompt() {
        val prompt = pendingPrompt ?: return
        val engine = flutterEngine
        if (engine == null) {
            Log.w(TAG, "deliverPendingPrompt: FlutterEngine no disponible; entrega diferida")
            scheduleDeliveryRetry()
            return
        }
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            .invokeMethod("onWidgetPrompt", prompt, object : MethodChannel.Result {
                override fun success(result: Any?) {
                    Log.d(TAG, "onWidgetPrompt entregado a Flutter")
                    pendingPrompt = null
                }

                override fun error(code: String, message: String?, details: Any?) {
                    Log.w(TAG, "onWidgetPrompt rechazado por Dart ($code); se reintentará")
                    scheduleDeliveryRetry()
                }

                override fun notImplemented() {
                    Log.w(TAG, "onWidgetPrompt sin handler en Dart todavía; se reintentará")
                    scheduleDeliveryRetry()
                }
            })
    }

    private fun scheduleDeliveryRetry() {
        if (pendingPrompt == null) return
        if (deliveryAttempts >= MAX_DELIVERY_RETRIES) {
            Log.w(TAG, "scheduleDeliveryRetry: reintentos agotados; queda disponible vía getInitialPrompt")
            return
        }
        deliveryAttempts++
        mainHandler.postDelayed({ deliverPendingPrompt() }, RETRY_DELAY_MS)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Auto-actualización: exponer el versionCode instalado a Dart
        // (UpdateService compara contra version.json de GitHub Releases).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, APP_INFO_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "versionCode" -> {
                    try {
                        val pm = packageManager
                        val info = pm.getPackageInfo(packageName, 0)
                        val code = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                            info.longVersionCode.toInt()
                        } else {
                            @Suppress("DEPRECATION")
                            info.versionCode
                        }
                        result.success(code)
                    } catch (e: Exception) {
                        result.error("VERSION_ERROR", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialPrompt" -> {
                    result.success(pendingPrompt)
                    pendingPrompt = null
                    deliveryAttempts = 0
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

    override fun onDestroy() {
        mainHandler.removeCallbacksAndMessages(null)
        super.onDestroy()
    }
}
