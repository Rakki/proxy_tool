package org.roboratory.proxy_tool

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.widget.RemoteViews
import androidx.core.content.ContextCompat

class ProxyWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        appWidgetIds.forEach { widgetId ->
            appWidgetManager.updateAppWidget(widgetId, buildViews(context))
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        when (intent.action) {
            actionToggle -> handleToggle(context)
            actionPrevious -> {
                WidgetStateStore.moveSelection(context, -1)
                refreshAll(context)
            }
            actionNext -> {
                WidgetStateStore.moveSelection(context, 1)
                refreshAll(context)
            }
            actionOpenApp -> openApp(context)
            AppWidgetManager.ACTION_APPWIDGET_UPDATE -> refreshAll(context)
        }
    }

    private fun handleToggle(context: Context) {
        val profile = WidgetStateStore.selectedProfile(context)
        if (profile == null) {
            openApp(context)
            return
        }

        val profileId = profile["id"] as? String
        if (profileId != null && WidgetStateStore.activeProfileId(context) == profileId) {
            context.startService(ProxyVpnService.createStopIntent(context))
            WidgetStateStore.setActiveProfileId(context, null)
            refreshAll(context)
            return
        }

        val prepareIntent = VpnService.prepare(context)
        if (prepareIntent != null) {
            openApp(context)
            return
        }

        val startIntent = ProxyVpnService.createStartIntent(context, profile)
        ContextCompat.startForegroundService(context, startIntent)
        WidgetStateStore.setActiveProfileId(context, profileId)
        refreshAll(context)
    }

    private fun openApp(context: Context) {
        context.startActivity(
            Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
        )
    }

    private fun buildViews(context: Context): RemoteViews {
        val selectedProfile = WidgetStateStore.selectedProfile(context)
        val profileName = selectedProfile?.get("name") as? String
        val profileId = selectedProfile?.get("id") as? String
        val activeProfileId = WidgetStateStore.activeProfileId(context)
        val isActive = profileId != null && profileId == activeProfileId
        val hasProfile = selectedProfile != null

        val rootIntent = pendingBroadcast(context, actionOpenApp, 1)
        val toggleIntent = pendingBroadcast(context, if (hasProfile) actionToggle else actionOpenApp, 2)
        val previousIntent = pendingBroadcast(context, actionPrevious, 3)
        val nextIntent = pendingBroadcast(context, actionNext, 4)

        return RemoteViews(context.packageName, R.layout.proxy_widget).apply {
            setTextViewText(
                R.id.widget_title,
                profileName ?: context.getString(R.string.widget_title),
            )
            setTextViewText(
                R.id.widget_subtitle,
                when {
                    !hasProfile -> context.getString(R.string.widget_subtitle_empty)
                    isActive -> context.getString(R.string.widget_subtitle_active)
                    else -> context.getString(R.string.widget_subtitle_ready)
                },
            )
            setTextViewText(
                R.id.widget_action_button,
                when {
                    !hasProfile -> context.getString(R.string.widget_button_open)
                    isActive -> context.getString(R.string.widget_button_stop)
                    else -> context.getString(R.string.widget_button_start)
                },
            )
            setOnClickPendingIntent(R.id.widget_root, rootIntent)
            setOnClickPendingIntent(R.id.widget_action_button, toggleIntent)
            setOnClickPendingIntent(R.id.widget_prev_button, previousIntent)
            setOnClickPendingIntent(R.id.widget_next_button, nextIntent)
        }
    }

    private fun pendingBroadcast(
        context: Context,
        action: String,
        requestCode: Int,
    ): PendingIntent {
        val intent = Intent(context, ProxyWidgetProvider::class.java).apply {
            this.action = action
        }
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        return PendingIntent.getBroadcast(context, requestCode, intent, flags)
    }

    companion object {
        const val actionToggle = "org.roboratory.proxy_tool.WIDGET_TOGGLE"
        const val actionPrevious = "org.roboratory.proxy_tool.WIDGET_PREVIOUS"
        const val actionNext = "org.roboratory.proxy_tool.WIDGET_NEXT"
        const val actionOpenApp = "org.roboratory.proxy_tool.WIDGET_OPEN_APP"

        fun refreshAll(context: Context) {
            val appWidgetManager = AppWidgetManager.getInstance(context)
            val componentName = ComponentName(context, ProxyWidgetProvider::class.java)
            val ids = appWidgetManager.getAppWidgetIds(componentName)
            if (ids.isEmpty()) {
                return
            }

            val provider = ProxyWidgetProvider()
            ids.forEach { id ->
                appWidgetManager.updateAppWidget(id, provider.buildViews(context))
            }
        }
    }
}
