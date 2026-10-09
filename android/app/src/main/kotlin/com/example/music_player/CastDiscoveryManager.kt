package com.example.music_player

import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import java.net.HttpURLConnection
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.net.DatagramPacket
import java.net.InetAddress
import java.net.MulticastSocket
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors

/** Finds local services; it does not claim that a found device can receive a cast. */
class CastDiscoveryManager(context: Context, messenger: io.flutter.plugin.common.BinaryMessenger) {
    private val appContext = context.applicationContext
    private val activity = context as? Activity
    private val nsd = appContext.getSystemService(Context.NSD_SERVICE) as NsdManager
    private val wifi = appContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
    private val mainHandler = Handler(Looper.getMainLooper())
    private val executor = Executors.newSingleThreadExecutor()
    private val devices = ConcurrentHashMap<String, Map<String, Any>>()
    private val listeners = mutableListOf<Pair<String, NsdManager.DiscoveryListener>>()
    private var sink: EventChannel.EventSink? = null
    private var multicastLock: WifiManager.MulticastLock? = null
    @Volatile private var ssdpSocket: MulticastSocket? = null
    @Volatile private var scanning = false
    @Volatile private var permissionRequired = false

    init {
        MethodChannel(messenger, "soundneed/cast").setMethodCallHandler { call, result ->
            when (call.method) {
                "startDiscovery" -> {
                    startDiscovery()
                    result.success(null)
                }
                "stopDiscovery" -> {
                    stopDiscovery()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        EventChannel(messenger, "soundneed/cast/events").setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    sink = events
                    publish()
                }

                override fun onCancel(arguments: Any?) {
                    sink = null
                    stopDiscovery()
                }
            }
        )
    }

    @Synchronized
    private fun startDiscovery() {
        stopDiscovery()
        devices.clear()
        permissionRequired = false
        if (Build.VERSION.SDK_INT >= 37 && appContext.applicationInfo.targetSdkVersion >= 37 &&
            appContext.checkSelfPermission("android.permission.ACCESS_LOCAL_NETWORK") != PackageManager.PERMISSION_GRANTED
        ) {
            permissionRequired = true
            activity?.requestPermissions(
                arrayOf("android.permission.ACCESS_LOCAL_NETWORK"),
                LOCAL_NETWORK_PERMISSION_REQUEST
            )
            publish()
            return
        }
        scanning = true
        publish()
        try {
            multicastLock = wifi.createMulticastLock("SoundNeedCastDiscovery").apply {
                setReferenceCounted(false)
                acquire()
            }
        } catch (error: Exception) {
            Log.w(TAG, "No se pudo adquirir el bloqueo multicast", error)
        }

        listOf("_googlecast._tcp.", "_airplay._tcp.", "_raop._tcp.", "_soundneed._tcp.", "_workstation._tcp.")
            .forEach(::startNsdDiscovery)
        executor.execute(::runSsdpDiscovery)
        mainHandler.postDelayed({ stopDiscovery() }, SCAN_WINDOW_MS)
    }

    private fun startNsdDiscovery(type: String) {
        val listener = object : NsdManager.DiscoveryListener {
            override fun onDiscoveryStarted(serviceType: String) = Unit
            override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) {
                try { nsd.stopServiceDiscovery(this) } catch (_: Exception) { }
            }
            override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) {
                try { nsd.stopServiceDiscovery(this) } catch (_: Exception) { }
            }
            override fun onDiscoveryStopped(serviceType: String) = Unit
            override fun onServiceLost(serviceInfo: NsdServiceInfo) = Unit
            override fun onServiceFound(serviceInfo: NsdServiceInfo) {
                try {
                    nsd.resolveService(serviceInfo, object : NsdManager.ResolveListener {
                        override fun onResolveFailed(info: NsdServiceInfo, errorCode: Int) = Unit
                        override fun onServiceResolved(info: NsdServiceInfo) {
                            val host = info.host?.hostAddress ?: return
                            val protocol = type.removePrefix("_").removeSuffix("._tcp.")
                            val soundNeed = protocol.equals("soundneed", true)
                            val attributes = info.attributes
                            val advertisedName = attributes["fn"]?.toString(Charsets.UTF_8)
                                ?.trim()?.takeIf { it.isNotEmpty() }
                            val model = attributes["md"]?.toString(Charsets.UTF_8)
                                ?.trim().orEmpty()
                            val googleCast = protocol.equals("googlecast", true)
                            val device = mapOf(
                                "id" to host,
                                "name" to (advertisedName ?: info.serviceName),
                                "host" to host,
                                "kind" to kindFor(protocol, advertisedName ?: info.serviceName, model),
                                "protocol" to protocol.uppercase(),
                                "model" to model,
                                "compatible" to googleCast,
                                "permissionRequired" to permissionRequired,
                                "status" to when {
                                    googleCast -> "Google Cast detectado; disponible para conectar"
                                    soundNeed -> "Receptor SoundNeed detectado; conexión aún no configurada"
                                    else -> "Protocolo detectado; compatibilidad por comprobar"
                                },
                            )
                            upsertDevice(device)
                        }
                    })
                } catch (_: Exception) { }
            }
        }
        synchronized(listeners) { listeners.add(type to listener) }
        try {
            nsd.discoverServices(type, NsdManager.PROTOCOL_DNS_SD, listener)
        } catch (error: Exception) {
            Log.d(TAG, "No se pudo iniciar mDNS para $type", error)
        }
    }

    private fun runSsdpDiscovery() {
        var socket: MulticastSocket? = null
        try {
            socket = MulticastSocket(0)
            socket.soTimeout = 500
            socket.joinGroup(InetAddress.getByName(SSDP_ADDRESS))
            ssdpSocket = socket
            val targets = listOf("ssdp:all", "urn:schemas-upnp-org:device:MediaRenderer:1")
            for (target in targets) {
                val request = ("M-SEARCH * HTTP/1.1\r\n" +
                    "HOST: $SSDP_ADDRESS:1900\r\n" +
                    "MAN: \"ssdp:discover\"\r\n" +
                    "MX: 2\r\nST: $target\r\n\r\n").toByteArray()
                socket.send(DatagramPacket(request, request.size, InetAddress.getByName(SSDP_ADDRESS), 1900))
            }

            val endAt = System.currentTimeMillis() + SCAN_WINDOW_MS
            val buffer = ByteArray(8192)
            while (scanning && System.currentTimeMillis() < endAt) {
                try {
                    val packet = DatagramPacket(buffer, buffer.size)
                    socket.receive(packet)
                    val headers = String(packet.data, packet.offset, packet.length)
                    val st = header(headers, "ST") ?: header(headers, "NT") ?: "UPnP"
                    val host = packet.address.hostAddress ?: continue
                    val location = header(headers, "LOCATION")
                    val description = location?.let { resolveUpnpDescription(it) }
                    val name = description?.first ?: "Dispositivo UPnP · $host"
                    val deviceType = description?.second.orEmpty()
                    val device = mapOf(
                        "id" to host,
                        "name" to name,
                        "host" to host,
                        "kind" to kindFor("upnp", name, deviceType),
                        "protocol" to "UPnP / SSDP",
                        "model" to deviceType,
                        "compatible" to false,
                        "permissionRequired" to permissionRequired,
                        "status" to "Detectado; compatibilidad de reproducción por comprobar",
                    )
                    upsertDevice(device)
                } catch (_: java.net.SocketTimeoutException) { }
            }
        } catch (error: Exception) {
            Log.d(TAG, "SSDP no disponible en esta red", error)
        } finally {
            try { socket?.leaveGroup(InetAddress.getByName(SSDP_ADDRESS)) } catch (_: Exception) { }
            socket?.close()
            if (ssdpSocket === socket) ssdpSocket = null
        }
    }

    private fun header(response: String, name: String): String? = response.lineSequence()
        .firstOrNull { it.substringBefore(':').trim().equals(name, true) }
        ?.substringAfter(':')?.trim()

    private fun resolveUpnpDescription(location: String): Pair<String, String>? {
        var connection: HttpURLConnection? = null
        return try {
            val url = java.net.URL(location)
            if (!InetAddress.getByName(url.host).isSiteLocalAddress) return null
            connection = url.openConnection() as? HttpURLConnection ?: return null
            connection.instanceFollowRedirects = false
            connection.connectTimeout = 900
            connection.readTimeout = 900
            connection.setRequestProperty("Connection", "close")
            val xml = connection.inputStream.bufferedReader().use { it.readText() }
            val name = Regex("<friendlyName>(.*?)</friendlyName>", RegexOption.IGNORE_CASE)
                .find(xml)?.groupValues?.getOrNull(1)?.let(::decodeXmlText)?.takeIf { it.isNotBlank() }
                ?: return null
            val type = Regex("<deviceType>(.*?)</deviceType>", RegexOption.IGNORE_CASE)
                .find(xml)?.groupValues?.getOrNull(1)?.let(::decodeXmlText).orEmpty()
            name to type
        } catch (_: Exception) {
            null
        } finally {
            connection?.disconnect()
        }
    }

    private fun decodeXmlText(value: String): String = value
        .replace("&amp;", "&")
        .replace("&lt;", "<")
        .replace("&gt;", ">")
        .replace("&quot;", "\"")
        .replace("&apos;", "'")

    private fun kindFor(protocol: String, name: String, model: String = ""): String {
        val clues = "$protocol $name $model"
        if (Regex("\\b(speaker|altavoz|soundbar|sound.?bar|audio|sonos|home.?pod|nest.?mini)\\b", RegexOption.IGNORE_CASE).containsMatchIn(clues) || protocol.equals("raop", true)) {
            return if (protocol.equals("googlecast", true)) "Altavoz Google Cast" else "Altavoz / audio"
        }
        if (Regex("\\b(tv|television|televisor|smart.?tv|tizen|webos|bravia|qled|oled|android.?tv|roku.?tv)\\b", RegexOption.IGNORE_CASE).containsMatchIn(clues) ||
            (protocol.startsWith("upnp", true) && Regex("\\b(samsung|lg|sony|tcl|hisense|philips|panasonic|sharp)\\b", RegexOption.IGNORE_CASE).containsMatchIn(name))) {
            return "Televisor"
        }
        if (protocol.equals("googlecast", true)) return "TV / Google Cast"
        if (protocol.equals("airplay", true)) return "Pantalla AirPlay"
        if (protocol.equals("soundneed", true)) return "Receptor SoundNeed"
        if (protocol.equals("workstation", true) || Regex("\\b(pc|computer|desktop|ordenador)\\b", RegexOption.IGNORE_CASE).containsMatchIn(clues)) {
            return "Ordenador"
        }
        return "Dispositivo de red"
    }

    @Synchronized
    private fun upsertDevice(incoming: Map<String, Any>) {
        val host = incoming["host"]?.toString().orEmpty()
        if (host.isBlank()) return
        val incomingName = incoming["name"].toString()
        val duplicate = devices.entries.firstOrNull { (key, value) ->
            key == host || (!isGenericName(incomingName) &&
                normalizeDeviceName(value["name"].toString()) == normalizeDeviceName(incomingName))
        }
        val deviceKey = duplicate?.key ?: host
        val existing = duplicate?.value
        val updated = if (existing == null) {
            incoming
        } else {
                val protocols = (existing["protocol"].toString().split(" · ") +
                    incoming["protocol"].toString().split(" · "))
                    .map { it.trim() }
                    .filter { it.isNotEmpty() }
                    .distinct()
                val oldName = existing["name"].toString()
                val newName = incomingName
                val name = when {
                    hasTvMarker(newName) && !hasTvMarker(oldName) -> newName
                    isGenericName(oldName) && !isGenericName(newName) -> newName
                    else -> oldName
                }
                val oldModel = existing["model"].toString()
                val newModel = incoming["model"].toString()
                val model = listOf(oldModel, newModel).filter { it.isNotBlank() }.distinct().joinToString(" · ")
                val kind = listOf(existing["kind"].toString(), incoming["kind"].toString())
                    .firstOrNull { it == "Televisor" }
                    ?: listOf(existing["kind"].toString(), incoming["kind"].toString())
                        .firstOrNull { it.startsWith("Altavoz") }
                    ?: listOf(existing["kind"].toString(), incoming["kind"].toString())
                        .firstOrNull { it == "Ordenador" }
                    ?: incoming["kind"].toString()
                mapOf(
                    "id" to deviceKey,
                    "name" to name,
                    "host" to (existing["host"]?.toString()?.ifBlank { host } ?: host),
                    "kind" to kind,
                    "protocol" to protocols.joinToString(" · "),
                    "model" to model,
                    "compatible" to (existing["compatible"] == true || incoming["compatible"] == true),
                    "permissionRequired" to permissionRequired,
                    "status" to if (existing["compatible"] == true || incoming["compatible"] == true) {
                        "Google Cast detectado; disponible para conectar"
                    } else {
                        "Protocolos detectados: ${protocols.joinToString(", ")}; compatibilidad por comprobar"
                    },
                )
        }
        devices[deviceKey] = updated
        publish()
    }

    private fun normalizeDeviceName(name: String): String =
        name.lowercase().replace(Regex("[^a-z0-9]"), "")

    private fun hasTvMarker(name: String): Boolean =
        Regex("\\b(tv|television|televisor|smart.?tv|tizen|webos|bravia|qled|oled|roku.?tv)\\b", RegexOption.IGNORE_CASE)
            .containsMatchIn(name)

    private fun isGenericName(name: String): Boolean =
        name.startsWith("Dispositivo UPnP", true) ||
            name.startsWith("Dispositivo de red", true) ||
            name.matches(Regex("[0-9a-fA-F:.]+"))

    fun dispose() {
        stopDiscovery()
        executor.shutdownNow()
    }

    @Synchronized
    private fun stopDiscovery() {
        if (!scanning && listeners.isEmpty()) return
        scanning = false
        mainHandler.removeCallbacksAndMessages(null)
        synchronized(listeners) {
            listeners.forEach { (_, listener) ->
                try { nsd.stopServiceDiscovery(listener) } catch (_: Exception) { }
            }
            listeners.clear()
        }
        ssdpSocket?.close()
        ssdpSocket = null
        try { multicastLock?.takeIf { it.isHeld }?.release() } catch (_: Exception) { }
        multicastLock = null
        publish()
    }

    private fun publish() {
        val snapshot = mapOf(
            "scanning" to scanning,
            "permissionRequired" to permissionRequired,
            "devices" to devices.values.sortedBy { it["name"].toString().lowercase() },
        )
        mainHandler.post { sink?.success(snapshot) }
    }

    companion object {
        private const val TAG = "SoundNeedCast"
        private const val SSDP_ADDRESS = "239.255.255.250"
        private const val SCAN_WINDOW_MS = 12_000L
        private const val LOCAL_NETWORK_PERMISSION_REQUEST = 309
    }
}
