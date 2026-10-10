package com.example.music_player

import android.Manifest
import android.app.Activity
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothClass
import android.content.Context
import android.content.Intent
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.content.pm.PackageManager
import androidx.mediarouter.media.MediaControlIntent
import androidx.mediarouter.media.MediaRouteSelector
import androidx.mediarouter.media.MediaRouter
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/** Reads and selects Android's active media route, including Bluetooth audio. */
class AudioOutputManager(
    private val activity: Activity,
    messenger: io.flutter.plugin.common.BinaryMessenger,
) {
    companion object {
        private const val BLUETOOTH_CONNECT_PERMISSION_REQUEST = 204
    }

    private val methods = MethodChannel(messenger, "soundneed/audio_output")
    private val events = EventChannel(messenger, "soundneed/audio_output/events")
    private var sink: EventChannel.EventSink? = null
    private var pendingBluetoothDevicesResult: MethodChannel.Result? = null
    private val audioManager = activity.getSystemService(Context.AUDIO_SERVICE) as AudioManager
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

    private val audioDeviceCallback = object : AudioDeviceCallback() {
        override fun onAudioDevicesAdded(addedDevices: Array<out AudioDeviceInfo>) = publish()
        override fun onAudioDevicesRemoved(removedDevices: Array<out AudioDeviceInfo>) = publish()
    }

    init {
        audioManager.registerAudioDeviceCallback(audioDeviceCallback, Handler(Looper.getMainLooper()))
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
                "getBondedBluetoothDevices" -> getBondedBluetoothDevices(result)
                "openBluetoothSettings" -> {
                    try {
                        openBluetoothSettings()
                        result.success(null)
                    } catch (error: Exception) {
                        result.error("BLUETOOTH_SETTINGS_UNAVAILABLE", "No se pudieron abrir los ajustes Bluetooth.", error.message)
                    }
                }
                "select" -> {
                    val id = call.argument<String>("routeId")
                    if (id?.startsWith("bonded-bluetooth-") == true) {
                        try {
                            openBluetoothSettings()
                            result.success(null)
                        } catch (error: Exception) {
                            result.error("BLUETOOTH_SETTINGS_UNAVAILABLE", "No se pudieron abrir los ajustes Bluetooth.", error.message)
                        }
                        return@setMethodCallHandler
                    }
                    val route = router.routes.firstOrNull { it.id == id && it.isEnabled }
                        ?: findRouteForAudioDevice(id)
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

    private fun openBluetoothSettings() {
        activity.startActivity(Intent(Settings.ACTION_BLUETOOTH_SETTINGS))
    }

    private fun getBondedBluetoothDevices(result: MethodChannel.Result) {
        if (android.os.Build.VERSION.SDK_INT >= 31 &&
            ContextCompat.checkSelfPermission(activity, Manifest.permission.BLUETOOTH_CONNECT) != PackageManager.PERMISSION_GRANTED) {
            if (pendingBluetoothDevicesResult != null) {
                result.error("BLUETOOTH_PERMISSION_PENDING", "La solicitud de permiso Bluetooth ya está abierta.", null)
                return
            }
            pendingBluetoothDevicesResult = result
            ActivityCompat.requestPermissions(
                activity,
                arrayOf(Manifest.permission.BLUETOOTH_CONNECT),
                BLUETOOTH_CONNECT_PERMISSION_REQUEST,
            )
            return
        }
        result.success(pairedAudioDevices())
    }

    fun onRequestPermissionsResult(requestCode: Int, grantResults: IntArray): Boolean {
        if (requestCode != BLUETOOTH_CONNECT_PERMISSION_REQUEST) return false
        val result = pendingBluetoothDevicesResult
        pendingBluetoothDevicesResult = null
        if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
            result?.success(pairedAudioDevices())
        } else {
            result?.error("BLUETOOTH_PERMISSION_DENIED", "Se necesita permiso Bluetooth para mostrar los dispositivos emparejados.", null)
        }
        return true
    }

    @Suppress("DEPRECATION")
    private fun pairedAudioDevices(): List<Map<String, Any>> {
        val adapter = BluetoothAdapter.getDefaultAdapter() ?: return emptyList()
        val connectedNames = snapshot()["routes"]
            .let { it as? List<*> ?: emptyList<Any>() }
            .mapNotNull { it as? Map<*, *> }
            .filter { it["type"] == "bluetooth" }
            .mapNotNull { it["name"]?.toString()?.lowercase() }
            .toSet()
        return adapter.bondedDevices
            .filter { device ->
                device.bluetoothClass?.majorDeviceClass == BluetoothClass.Device.Major.AUDIO_VIDEO
            }
            .filterNot { device -> runCatching { device.name?.lowercase() in connectedNames }.getOrDefault(false) }
            .map { device ->
                mapOf(
                    "id" to "bonded-bluetooth-${device.address}",
                    "name" to (runCatching { device.name }.getOrNull()?.takeIf { it.isNotBlank() }
                        ?: "Auriculares Bluetooth"),
                    "type" to "bluetooth",
                    "selected" to false,
                )
            }
    }

    private fun snapshot(): Map<String, Any> {
        val selected = router.selectedRoute
        val defaultRoute = router.defaultRoute
        val wiredOutput = audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
            .firstOrNull { outputType(it.type) == "wired" }
        val selectedType = if (wiredOutput != null) "wired" else selected?.let {
            if (isPhoneRoute(it, defaultRoute.id)) "phone" else routeType(it.deviceType)
        } ?: "phone"
        val physicalWiredName = wiredOutput?.productName?.toString()?.takeIf { it.isNotBlank() }
        val selectedName = if (wiredOutput != null) {
            physicalWiredName?.takeUnless { looksLikeModelCode(it) } ?: "Auriculares con cable"
        } else {
            selected?.name?.toString().orEmpty()
        }
        val routes = router.routes
            .filter { it.isEnabled && it.supportsControlCategory(MediaControlIntent.CATEGORY_LIVE_AUDIO) }
            .map { route -> routeMap(route, defaultRoute.id, selectedType) }
            .toMutableList()
        // MediaRouter misses wired headsets and some Bluetooth devices on some
        // Android builds. AudioManager reports physically connected outputs.
        audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
            .filter { outputType(it.type) != null }
            .forEach { device ->
                val type = outputType(device.type) ?: return@forEach
                val deviceName = device.productName?.toString()?.takeIf { it.isNotBlank() }
                val name = when {
                    type == "phone" -> "Este teléfono"
                    type == "wired" && (deviceName == null || looksLikeModelCode(deviceName)) -> "Auriculares con cable"
                    type == "bluetooth" && (deviceName == null || looksLikeModelCode(deviceName)) -> "Auriculares inalámbricos"
                    else -> deviceName ?: "Salida de audio"
                }
                val matchingRoute = router.routes.firstOrNull {
                    it.isEnabled && routeType(it.deviceType) == type &&
                        (it.name.toString().equals(name, ignoreCase = true) ||
                            type == selectedType && selectedName.isNotBlank() &&
                            it.name.toString().equals(selectedName, ignoreCase = true))
                }
                if (routes.none { it["type"] == type &&
                        (it["name"].toString().equals(name, ignoreCase = true) ||
                            it["id"] == matchingRoute?.id) }) {
                    routes.add(mapOf(
                        "id" to (matchingRoute?.id ?: "audio-device-${device.id}"),
                        "name" to name,
                        "type" to type,
                        "selected" to (matchingRoute?.isSelected == true ||
                            type == selectedType && selectedName.equals(name, ignoreCase = true)),
                    ))
                }
            }
        if (routes.none { it["id"] == defaultRoute.id }) {
            routes.add(routeMap(defaultRoute, defaultRoute.id, selectedType))
        }
        return mapOf(
            "selectedName" to when {
                wiredOutput != null -> selectedName
                selected?.let { isPhoneRoute(it, defaultRoute.id) } == true -> "Este teléfono"
                else -> selected?.name?.toString() ?: "Este teléfono"
            },
            "selectedType" to selectedType,
            "routes" to routes,
        )
    }

    private fun routeMap(
        route: MediaRouter.RouteInfo,
        defaultRouteId: String,
        selectedType: String,
    ): Map<String, Any> {
        val type = if (isPhoneRoute(route, defaultRouteId)) "phone" else routeType(route.deviceType)
        val localOutputType = type == "phone" || type == "wired" || type == "bluetooth"
        return mapOf(
            "id" to route.id,
            "name" to if (type == "phone") "Este teléfono" else route.name.toString(),
            "type" to type,
            "selected" to if (localOutputType) type == selectedType else route.isSelected,
        )
    }

    private fun routeType(deviceType: Int): String = when (deviceType) {
        MediaRouter.RouteInfo.DEVICE_TYPE_BLUETOOTH_A2DP,
        MediaRouter.RouteInfo.DEVICE_TYPE_BLE_HEADSET -> "bluetooth"
        MediaRouter.RouteInfo.DEVICE_TYPE_BUILTIN_SPEAKER -> "phone"
        MediaRouter.RouteInfo.DEVICE_TYPE_WIRED_HEADPHONES,
        MediaRouter.RouteInfo.DEVICE_TYPE_WIRED_HEADSET -> "wired"
        MediaRouter.RouteInfo.DEVICE_TYPE_TV,
        MediaRouter.RouteInfo.DEVICE_TYPE_HDMI,
        MediaRouter.RouteInfo.DEVICE_TYPE_REMOTE_SPEAKER -> "remote"
        else -> "other"
    }

    private fun isPhoneRoute(route: MediaRouter.RouteInfo, defaultRouteId: String): Boolean =
        route.id == defaultRouteId ||
            routeType(route.deviceType) == "phone" ||
            route.name.toString().equals(android.os.Build.MODEL, ignoreCase = true)

    private fun outputType(deviceType: Int): String? = when (deviceType) {
        AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
        AudioDeviceInfo.TYPE_WIRED_HEADSET,
        AudioDeviceInfo.TYPE_USB_HEADSET -> "wired"
        AudioDeviceInfo.TYPE_BLUETOOTH_A2DP,
        AudioDeviceInfo.TYPE_BLUETOOTH_SCO -> "bluetooth"
        AudioDeviceInfo.TYPE_BUILTIN_SPEAKER -> "phone"
        else -> if (android.os.Build.VERSION.SDK_INT >= 31 &&
            deviceType == AudioDeviceInfo.TYPE_BLE_HEADSET) "bluetooth" else null
    }

    private fun looksLikeModelCode(name: String): Boolean =
        Regex("^(?=.*[A-Z])(?=.*\\d)[A-Z0-9_-]{3,12}$", RegexOption.IGNORE_CASE)
            .matches(name.trim())

    private fun findRouteForAudioDevice(id: String?): MediaRouter.RouteInfo? {
        if (id == null || !id.startsWith("audio-device-")) return null
        val deviceId = id.removePrefix("audio-device-").toIntOrNull() ?: return null
        val device = audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
            .firstOrNull { it.id == deviceId } ?: return null
        val type = outputType(device.type) ?: return null
        return router.routes.firstOrNull {
            it.isEnabled && it.supportsControlCategory(MediaControlIntent.CATEGORY_LIVE_AUDIO) &&
                routeType(it.deviceType) == type
        }
    }

    private fun publish() {
        activity.runOnUiThread { sink?.success(snapshot()) }
    }

    fun dispose() {
        audioManager.unregisterAudioDeviceCallback(audioDeviceCallback)
        router.removeCallback(callback)
        methods.setMethodCallHandler(null)
        events.setStreamHandler(null)
        sink = null
    }
}
