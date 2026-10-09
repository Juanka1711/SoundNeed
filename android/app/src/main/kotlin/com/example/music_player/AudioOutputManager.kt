package com.example.music_player

import android.app.Activity
import androidx.mediarouter.media.MediaControlIntent
import androidx.mediarouter.media.MediaRouteSelector
import androidx.mediarouter.media.MediaRouter
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/** Reads and selects Android's active media route, including Bluetooth audio. */
class AudioOutputManager(
    private val activity: Activity,
    messenger: io.flutter.plugin.common.BinaryMessenger,
) {
    private val methods = MethodChannel(messenger, "soundneed/audio_output")
    private val events = EventChannel(messenger, "soundneed/audio_output/events")
    private var sink: EventChannel.EventSink? = null
    private val router = MediaRouter.getInstance(activity)
    private val selector = MediaRouteSelector.Builder()
        .addControlCategory(MediaControlIntent.CATEGORY_LIVE_AUDIO)
        .build()

    private val callback = object : MediaRouter.Callback() {
        override fun onRouteAdded(router: MediaRouter, route: MediaRouter.RouteInfo) = publish()
        override fun onRouteChanged(router: MediaRouter, route: MediaRouter.RouteInfo) = publish()
        override fun onRouteRemoved(router: MediaRouter, route: MediaRouter.RouteInfo) = publish()
        override fun onRouteSelected(router: MediaRouter, route: MediaRouter.RouteInfo, reason: Int) = publish()
        override fun onRouteUnselected(router: MediaRouter, route: MediaRouter.RouteInfo, reason: Int) = publish()
    }

    init {
        router.addCallback(
            selector,
            callback,
            MediaRouter.CALLBACK_FLAG_REQUEST_DISCOVERY,
        )
        events.setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    sink = events
                    publish()
                }

                override fun onCancel(arguments: Any?) {
                    sink = null
                }
            })
        methods.setMethodCallHandler { call, result ->
            when (call.method) {
                "getCurrent" -> result.success(snapshot())
                "select" -> {
                    val id = call.argument<String>("routeId")
                    val route = router.routes.firstOrNull { it.id == id && it.isEnabled }
                    if (route == null) {
                        result.error("OUTPUT_UNAVAILABLE", "La salida ya no está disponible.", null)
                    } else {
                        router.selectRoute(route)
                        result.success(null)
                        publish()
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun snapshot(): Map<String, Any> {
        val selected = router.selectedRoute
        val defaultRoute = router.defaultRoute
        val routes = router.routes
            .filter { it.isEnabled && it.supportsControlCategory(MediaControlIntent.CATEGORY_LIVE_AUDIO) }
            .map { route -> routeMap(route, defaultRoute.id) }
            .toMutableList()
        if (routes.none { it["id"] == defaultRoute.id }) {
            routes.add(routeMap(defaultRoute, defaultRoute.id))
        }
        return mapOf(
            "selectedName" to if (selected?.id == defaultRoute.id) "Este teléfono" else (selected?.name?.toString() ?: "Este teléfono"),
            "selectedType" to if (selected?.id == defaultRoute.id) "phone" else (selected?.let { routeType(it.deviceType) } ?: "phone"),
            "routes" to routes,
        )
    }

    private fun routeMap(route: MediaRouter.RouteInfo, defaultRouteId: String): Map<String, Any> =
                mapOf(
                    "id" to route.id,
                    "name" to if (route.id == defaultRouteId) "Este teléfono" else route.name.toString(),
                    "type" to if (route.id == defaultRouteId) "phone" else routeType(route.deviceType),
                    "selected" to route.isSelected,
                )

    private fun routeType(deviceType: Int): String = when (deviceType) {
        MediaRouter.RouteInfo.DEVICE_TYPE_BLUETOOTH_A2DP,
        MediaRouter.RouteInfo.DEVICE_TYPE_BLE_HEADSET -> "bluetooth"
        MediaRouter.RouteInfo.DEVICE_TYPE_BUILTIN_SPEAKER -> "speaker"
        MediaRouter.RouteInfo.DEVICE_TYPE_WIRED_HEADPHONES,
        MediaRouter.RouteInfo.DEVICE_TYPE_WIRED_HEADSET -> "wired"
        MediaRouter.RouteInfo.DEVICE_TYPE_TV,
        MediaRouter.RouteInfo.DEVICE_TYPE_HDMI,
        MediaRouter.RouteInfo.DEVICE_TYPE_REMOTE_SPEAKER -> "remote"
        else -> "other"
    }

    private fun publish() {
        activity.runOnUiThread { sink?.success(snapshot()) }
    }

    fun dispose() {
        router.removeCallback(callback)
        methods.setMethodCallHandler(null)
        events.setStreamHandler(null)
        sink = null
    }
}
