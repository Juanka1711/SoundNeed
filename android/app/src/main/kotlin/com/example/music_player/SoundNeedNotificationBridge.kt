package sound_need.music_player

import android.Manifest
import android.app.Activity
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.BinaryMessenger

/** Android bridge dedicated to non-media SoundNeed notifications. */
internal class SoundNeedNotificationBridge(private val activity: Activity) {
    companion object {
        private const val METHOD_CHANNEL = "soundneed/notifications"
        private const val NAVIGATION_CHANNEL = "soundneed/notification_navigation"
        private const val PERMISSION_REQUEST_CODE = 728
        private const val ACTION_OPEN_NOTIFICATION = "soundneed.action.OPEN_GENERAL_NOTIFICATION"
        private const val PERMISSION_PREFS = "soundneed_general_notification_permission"
        private const val PERMISSION_REQUESTED_KEY = "requested_once"
        private val VALID_CATEGORIES = setOf("downloads", "imports", "library", "news", "errors", "maintenance")
        private val VALID_DESTINATIONS = setOf("home", "songs", "playlists", "notifications", "settings")
        private val CHANNEL_LABELS = mapOf(
            "downloads" to "Descargas",
            "imports" to "Importaciones",
            "library" to "Biblioteca",
            "news" to "Novedades",
            "errors" to "Atención y errores",
            "maintenance" to "Mantenimiento",
        )
    }

    private var navigationSink: EventChannel.EventSink? = null
    private val pendingNavigation = ArrayDeque<Map<String, Any>>()

    fun attach(messenger: BinaryMessenger) {
        MethodChannel(messenger, METHOD_CHANNEL).setMethodCallHandler(::handleMethod)
        EventChannel(messenger, NAVIGATION_CHANNEL).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                navigationSink = events
                consumeIntent(activity.intent)
                while (pendingNavigation.isNotEmpty()) navigationSink?.success(pendingNavigation.removeFirst())
            }

            override fun onCancel(arguments: Any?) {
                navigationSink = null
            }
        })
    }

    /** Called from MainActivity.onNewIntent; returns true when this is ours. */
    fun handleIntent(intent: Intent): Boolean {
        if (intent.action != ACTION_OPEN_NOTIFICATION) return false
        consumeIntent(intent)
        return true
    }

    private fun consumeIntent(intent: Intent?) {
        if (intent?.action != ACTION_OPEN_NOTIFICATION) return
        val destination = intent.getStringExtra("soundneed_notification_destination")
        val recordId = intent.getStringExtra("soundneed_notification_id").orEmpty()
        if (destination != null && destination in VALID_DESTINATIONS) {
            val event = mapOf("destination" to destination, "id" to recordId)
            val sink = navigationSink
            if (sink != null) sink.success(event) else pendingNavigation.addLast(event)
        }
        intent.removeExtra("soundneed_notification_destination")
        intent.removeExtra("soundneed_notification_id")
        if (intent.action == ACTION_OPEN_NOTIFICATION) intent.action = Intent.ACTION_MAIN
    }

    private fun handleMethod(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "initialize" -> {
                    createChannels()
                    result.success(true)
                }
                "areEnabled" -> result.success(areEnabled())
                "requestPermission" -> requestPermission(result)
                "openSettings" -> {
                    openAppNotificationSettings()
                    result.success(true)
                }
                "show" -> result.success(show(call))
                "cancel" -> {
                    val id = call.argument<Int>("id")
                        ?: throw IllegalArgumentException("Falta el identificador")
                    NotificationManagerCompat.from(activity).cancel(id)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        } catch (error: Exception) {
            result.error("GENERAL_NOTIFICATION", error.message, null)
        }
    }

    private fun show(call: MethodCall): Boolean {
        val id = call.argument<Int>("id") ?: return false
        val category = call.argument<String>("category")?.takeIf { it in VALID_CATEGORIES } ?: return false
        createChannels()
        if (!areEnabled(category)) return false
        val title = call.argument<String>("title")?.takeIf { it.isNotBlank() } ?: return false
        val description = call.argument<String>("description").orEmpty()
        val destination = call.argument<String>("destination")
            ?.takeIf { it in VALID_DESTINATIONS }
        val ongoing = call.argument<Boolean>("ongoing") ?: false
        val progress = call.argument<Int>("progress")?.coerceIn(0, 100)
        val priority = when (call.argument<Int>("priority")) {
            0 -> NotificationCompat.PRIORITY_LOW
            2 -> NotificationCompat.PRIORITY_HIGH
            else -> NotificationCompat.PRIORITY_DEFAULT
        }

        val recordId = call.argument<String>("recordId").orEmpty()
        val launchIntent = Intent(activity, MainActivity::class.java).apply {
            action = ACTION_OPEN_NOTIFICATION
            flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra("soundneed_notification_id", recordId)
            putExtra("soundneed_notification_destination", destination ?: "notifications")
        }
        if (launchIntent.resolveActivity(activity.packageManager) == null) return false
        val pendingIntent = PendingIntent.getActivity(
            activity,
            id,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val notification = NotificationCompat.Builder(activity, channelId(category))
            .setSmallIcon(R.drawable.ic_stat_soundneed)
            .setContentTitle(title)
            .setContentText(description)
            .setStyle(NotificationCompat.BigTextStyle().bigText(description))
            .setContentIntent(pendingIntent)
            .setPriority(priority)
            .setCategory(NotificationCompat.CATEGORY_STATUS)
            .setOnlyAlertOnce(true)
            .setOngoing(ongoing)
            .setAutoCancel(!ongoing)
            .apply {
                if (progress != null) setProgress(100, progress, false)
            }
            .build()
        return try {
            NotificationManagerCompat.from(activity).notify(id, notification)
            true
        } catch (_: SecurityException) {
            false
        }
    }

    private fun requestPermission(result: MethodChannel.Result) {
        if (areEnabled()) {
            result.success("granted")
            return
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            openAppNotificationSettings()
            result.success("settings")
            return
        }
        val granted = ContextCompat.checkSelfPermission(
            activity,
            Manifest.permission.POST_NOTIFICATIONS,
        ) == PackageManager.PERMISSION_GRANTED
        if (granted) {
            openAppNotificationSettings()
            result.success("settings")
            return
        }
        val preferences = activity.getSharedPreferences(PERMISSION_PREFS, Context.MODE_PRIVATE)
        if (preferences.getBoolean(PERMISSION_REQUESTED_KEY, false)) {
            openAppNotificationSettings()
            result.success("settings")
            return
        }
        preferences.edit().putBoolean(PERMISSION_REQUESTED_KEY, true).apply()
        ActivityCompat.requestPermissions(
            activity,
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            PERMISSION_REQUEST_CODE,
        )
        result.success("requested")
    }

    private fun openAppNotificationSettings() {
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                .putExtra(Settings.EXTRA_APP_PACKAGE, activity.packageName)
        } else {
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                .setData(Uri.parse("package:${activity.packageName}"))
        }
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        if (intent.resolveActivity(activity.packageManager) != null) activity.startActivity(intent)
    }

    private fun areEnabled(category: String? = null): Boolean {
        if (!NotificationManagerCompat.from(activity).areNotificationsEnabled()) return false
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(activity, Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) return false
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && category != null) {
            val manager = activity.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (manager.getNotificationChannel(channelId(category))?.importance == NotificationManager.IMPORTANCE_NONE) {
                return false
            }
        }
        return true
    }

    private fun createChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = activity.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        VALID_CATEGORIES.forEach { category ->
            if (manager.getNotificationChannel(channelId(category)) != null) return@forEach
            val importance = when (category) {
                "errors" -> NotificationManager.IMPORTANCE_HIGH
                "news" -> NotificationManager.IMPORTANCE_LOW
                else -> NotificationManager.IMPORTANCE_DEFAULT
            }
            manager.createNotificationChannel(
                NotificationChannel(channelId(category), CHANNEL_LABELS.getValue(category), importance).apply {
                    description = "Avisos generales de SoundNeed: ${CHANNEL_LABELS.getValue(category).lowercase()}"
                },
            )
        }
    }

    private fun channelId(category: String) = "soundneed.general.$category"
}
