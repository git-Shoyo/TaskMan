package com.example.taskman

import android.appwidget.AppWidgetManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            WINDOW_CHANNEL_NAME,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "updateNativeGanttTasks" -> {
                    AndroidGanttWidgetStore.saveTasks(this, call.arguments)
                    GanttWidgetProvider.updateAll(this)
                    result.success(null)
                }

                "requestPinAndroidGanttWidget" -> {
                    result.success(requestPinAndroidGanttWidget())
                }

                "getAndroidGanttWidgetSize" -> {
                    result.success(AndroidGanttWidgetStore.loadSize(this).toMethodChannelMap())
                }

                "setAndroidGanttWidgetSize" -> {
                    val size = AndroidGanttWidgetStore.saveSize(this, call.arguments)
                    GanttWidgetProvider.updateAll(this)
                    result.success(size.toMethodChannelMap())
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun requestPinAndroidGanttWidget(): String {
        if (GanttWidgetProvider.hasInstalledWidget(this)) {
            return PIN_STATUS_ALREADY_ADDED
        }

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return PIN_STATUS_UNSUPPORTED
        }

        val appWidgetManager = getSystemService(AppWidgetManager::class.java)
            ?: return PIN_STATUS_UNSUPPORTED
        if (!appWidgetManager.isRequestPinAppWidgetSupported) {
            return PIN_STATUS_UNSUPPORTED
        }

        val provider = GanttWidgetProvider.selectedProviderComponent(this)
        return if (appWidgetManager.requestPinAppWidget(provider, null, null)) {
            PIN_STATUS_REQUESTED
        } else {
            PIN_STATUS_UNSUPPORTED
        }
    }

    companion object {
        private const val WINDOW_CHANNEL_NAME = "taskman/window"
        private const val PIN_STATUS_REQUESTED = "requested"
        private const val PIN_STATUS_ALREADY_ADDED = "alreadyAdded"
        private const val PIN_STATUS_UNSUPPORTED = "unsupported"
    }
}
