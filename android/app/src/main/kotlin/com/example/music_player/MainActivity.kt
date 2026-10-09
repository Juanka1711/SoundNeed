package com.example.music_player

import android.Manifest
import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.app.RecoverableSecurityException
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.graphics.BitmapFactory
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Typeface
import android.graphics.LinearGradient
import android.graphics.Shader
import android.media.MediaScannerConnection
import android.media.MediaMetadataRetriever
import android.media.audiofx.Equalizer
import android.media.audiofx.Visualizer
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.Uri
import android.net.NetworkRequest
import android.os.Build
import android.os.Environment
import android.provider.DocumentsContract
import android.provider.MediaStore
import android.provider.Settings
import android.util.Log
import java.io.ByteArrayOutputStream
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicLong

import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider

import com.ryanheise.audioservice.AudioServiceFragmentActivity
import aman.taglib.TagLib

import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel

import org.schabi.newpipe.extractor.NewPipe
import org.schabi.newpipe.extractor.stream.AudioStream

class MainActivity : AudioServiceFragmentActivity() {

    private var newPipeInitialized = false
    private var networkEventSink: EventChannel.EventSink? = null
    private var downloadProgressSink: EventChannel.EventSink? = null
    private var sharedSongEventSink: EventChannel.EventSink? = null
    private var pendingSharedSongLink: String? = null
    private var connectivityManager: ConnectivityManager? = null
    private val networkCallback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) {
            publishNetworkState()
        }

        override fun onLost(network: Network) {
            publishNetworkState()
        }

        override fun onCapabilitiesChanged(
            network: Network,
            networkCapabilities: NetworkCapabilities
        ) {
            publishNetworkState()
        }
    }
    private var pendingFolderPickerResult: MethodChannel.Result? = null
    private var pendingDeleteResult: MethodChannel.Result? = null
    private var visualizer: Visualizer? = null
    private var visualizerEventSink: EventChannel.EventSink? = null
    private var pendingVisualizerResult: MethodChannel.Result? = null
    private var pendingVisualizerSessionId: Int? = null
    private var equalizer: Equalizer? = null
    private var equalizerSessionId: Int? = null
    private var castDiscoveryManager: CastDiscoveryManager? = null
    private var castSenderManager: CastSenderManager? = null

    companion object {
        private const val CHANNEL = "music_player/media"
        private const val YOUTUBE_CHANNEL = "youtube/extractor"
        private const val WIDGET_CHANNEL = "soundneed/widget"
        private const val NOTIFICATION_PERMISSION_REQUEST_CODE = 200
        private const val NEW_MUSIC_NOTIFICATION_CHANNEL_ID = "soundneed.new.music"
        private const val NEW_MUSIC_NOTIFICATION_ID = 3107
        private const val PICK_MUSIC_FOLDER_REQUEST_CODE = 201
        private const val DELETE_MUSIC_REQUEST_CODE = 202
        private const val VISUALIZER_PERMISSION_REQUEST_CODE = 203
        private const val MUSIC_FOLDERS_PREFS = "soundneed_music_folders"
        private const val MUSIC_FOLDERS_KEY = "paths"
        private const val DOWNLOAD_ARTWORKS_KEY = "artwork_files"
        private val extractorExecutor =
            Executors.newFixedThreadPool(2)
        private val downloadExecutor =
            Executors.newSingleThreadExecutor()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        castDiscoveryManager?.dispose()
        castDiscoveryManager = CastDiscoveryManager(
            this,
            flutterEngine.dartExecutor.binaryMessenger
        )
        castSenderManager?.dispose()
        castSenderManager = CastSenderManager(
            this,
            flutterEngine.dartExecutor.binaryMessenger
        )

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        ).setMethodCallHandler { call, result ->

            when (call.method) {

                // ============================================================
                // COMPROBAR PERMISO DE MÚSICA
                // ============================================================

                "hasPermission" -> {
                    result.success(hasAudioPermission())
                }

                // ============================================================
                // SOLICITAR PERMISO DE MÚSICA
                // ============================================================

                "requestPermission" -> {
                    requestAudioPermission()
                    result.success(true)
                }

                // ============================================================
                // SOLICITAR PERMISO DE NOTIFICACIONES
                // ============================================================

                "requestNotificationPermission" -> {
                    requestNotificationPermission()
                    result.success(true)
                }

                "areNotificationsEnabled" -> {
                    result.success(NotificationManagerCompat.from(this).areNotificationsEnabled())
                }

                "showNewMusicNotification" -> {
                    val count = call.argument<Int>("count") ?: 0
                    result.success(showNewMusicNotification(count))
                }

                "openNotificationSettings" -> {
                    try {
                        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                                putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                            }
                        } else {
                            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                                data = Uri.parse("package:$packageName")
                            }
                        }
                        startActivity(intent)
                        result.success(true)
                    } catch (error: Exception) {
                        result.error("NOTIFICATION_SETTINGS", error.message, null)
                    }
                }

                "getAppVersion" -> {
                    val version = try {
                        packageManager.getPackageInfo(packageName, 0).versionName
                    } catch (_: Exception) {
                        null
                    }
                    result.success(version ?: "No disponible")
                }

                "shareFeedback" -> {
                    try {
                        val version = call.argument<String>("version") ?: "No disponible"
                        val intent = Intent(Intent.ACTION_SEND).apply {
                            type = "text/plain"
                            putExtra(Intent.EXTRA_SUBJECT, "Comentarios sobre SoundNeed")
                            putExtra(
                                Intent.EXTRA_TEXT,
                                "Hola, quiero compartir una idea o reportar un problema de SoundNeed.\n\nVersión: $version\n\n"
                            )
                        }
                        startActivity(Intent.createChooser(intent, "Enviar comentarios"))
                        result.success(true)
                    } catch (error: Exception) {
                        result.error("FEEDBACK_SHARE", error.message, null)
                    }
                }

                "shareSong" -> {
                    try {
                        val title = call.argument<String>("title") ?: "Canción"
                        val artist = call.argument<String>("artist") ?: "SoundNeed"
                        val link = call.argument<String>("link") ?: "soundneed://track"
                        val shareLink = buildSoundNeedShareLink(link, title, artist)
                        val shareText = "🎵 $title\n$artist\n\n$shareLink"
                        val intent = Intent(Intent.ACTION_SEND).apply {
                            type = "text/plain"
                            putExtra(Intent.EXTRA_SUBJECT, "$title · SoundNeed")
                            putExtra(Intent.EXTRA_TEXT, shareText)
                        }
                        startActivity(Intent.createChooser(intent, "Compartir desde SoundNeed"))
                        result.success(true)
                    } catch (error: Exception) {
                        result.error("SONG_SHARE", error.message, null)
                    }
                }

                // ============================================================
                // OBTENER CANCIONES
                // ============================================================

                "getSongs" -> {
                    result.success(getSongs())
                }

                "getMusicFolders" -> {
                    result.success(getSelectedMusicFolders())
                }

                "pickMusicFolder" -> {
                    if (pendingFolderPickerResult != null) {
                        result.error("PICKER_BUSY", "Ya hay un selector abierto", null)
                        return@setMethodCallHandler
                    }
                    pendingFolderPickerResult = result
                    val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
                    }
                    startActivityForResult(intent, PICK_MUSIC_FOLDER_REQUEST_CODE)
                }

                "removeMusicFolder" -> {
                    val path = call.argument<String>("path").orEmpty()
                    val preferences = getSharedPreferences(MUSIC_FOLDERS_PREFS, Context.MODE_PRIVATE)
                    val paths = preferences.getStringSet(MUSIC_FOLDERS_KEY, emptySet())
                        ?.toMutableSet() ?: mutableSetOf()
                    paths.remove(path)
                    preferences.edit().putStringSet(MUSIC_FOLDERS_KEY, paths).apply()
                    result.success(true)
                }

                "deleteSong" -> {
                    val rawUri = call.argument<String>("uri").orEmpty()
                    val uri = runCatching { Uri.parse(rawUri) }.getOrNull()
                    if (uri == null || uri.scheme != "content" ||
                        uri.authority != "media" ||
                        !uri.path.orEmpty().contains("/audio/media/")
                    ) {
                        result.error("INVALID_SONG_URI", "No se reconoce esta canción local.", null)
                        return@setMethodCallHandler
                    }
                    if (pendingDeleteResult != null) {
                        result.error("DELETE_BUSY", "Ya hay una confirmación de eliminación abierta.", null)
                        return@setMethodCallHandler
                    }

                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                        try {
                            val request = MediaStore.createDeleteRequest(
                                contentResolver,
                                listOf(uri),
                            )
                            pendingDeleteResult = result
                            startIntentSenderForResult(
                                request.intentSender,
                                DELETE_MUSIC_REQUEST_CODE,
                                null,
                                0,
                                0,
                                0,
                            )
                        } catch (error: Exception) {
                            pendingDeleteResult = null
                            result.error("DELETE_FAILED", error.message ?: "No se pudo solicitar la eliminación.", null)
                        }
                    } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        try {
                            result.success(contentResolver.delete(uri, null, null) > 0)
                        } catch (error: RecoverableSecurityException) {
                            try {
                                pendingDeleteResult = result
                                startIntentSenderForResult(
                                    error.userAction.actionIntent.intentSender,
                                    DELETE_MUSIC_REQUEST_CODE,
                                    null,
                                    0,
                                    0,
                                    0,
                                )
                            } catch (launchError: Exception) {
                                pendingDeleteResult = null
                                result.error("DELETE_FAILED", launchError.message, null)
                            }
                        } catch (error: Exception) {
                            result.error("DELETE_FAILED", error.message ?: "No se pudo eliminar la canción.", null)
                        }
                    } else {
                        try {
                            result.success(contentResolver.delete(uri, null, null) > 0)
                        } catch (error: Exception) {
                            result.error(
                                "DELETE_FAILED",
                                error.message ?: "No se pudo eliminar la canción.",
                                null,
                            )
                        }
                    }
                }

                "downloadAudio" -> {
                    val audioUrl = call.argument<String>("url").orEmpty()
                    val title = call.argument<String>("title").orEmpty()
                    val artist = call.argument<String>("artist").orEmpty()
                    val album = call.argument<String>("album").orEmpty()
                    val duration = call.argument<Number>("duration")?.toLong() ?: 0L
                    val artwork = call.argument<ByteArray>("artwork")
                    val sourceUrl = call.argument<String>("sourceUrl").orEmpty()
                    if (audioUrl.isBlank() || title.isBlank()) {
                        result.error("INVALID_DOWNLOAD", "Faltan datos de la canción.", null)
                        return@setMethodCallHandler
                    }

                    downloadExecutor.execute {
                        try {
                            val savedAudio = downloadAudioFile(
                                audioUrl,
                                title,
                                artist,
                                album,
                                duration,
                                artwork = artwork,
                                sourceUrl = sourceUrl,
                                onProgress = { received, total ->
                                    val progress = if (total > 0L) {
                                        received.toDouble() / total.toDouble()
                                    } else null
                                    runOnUiThread {
                                        downloadProgressSink?.success(
                                            mapOf("progress" to progress)
                                        )
                                    }
                                }
                            )
                            runOnUiThread { result.success(savedAudio) }
                        } catch (error: Exception) {
                            Log.e("SoundNeedDownload", "Error descargando audio", error)
                            runOnUiThread {
                                result.error(
                                    "DOWNLOAD_FAILED",
                                    error.message ?: "No se pudo descargar el audio.",
                                    null
                                )
                            }
                        }
                    }
                }

                // ============================================================
                // OBTENER PORTADA
                // ============================================================

                "getArtwork" -> {
                    val albumId = call.argument<Number>("albumId")?.toLong()
                    val songUri = call.argument<String>("uri")
                    val embeddedArtwork = songUri
                        ?.takeIf { it.isNotBlank() }
                        ?.let { getEmbeddedArtwork(it) }
                    result.success(embeddedArtwork ?: albumId?.let { getArtwork(it) })
                }

                "cacheOnlineArtwork" -> {
                    val key = call.argument<String>("key").orEmpty()
                    val bytes = call.argument<ByteArray>("bytes")
                    if (key.isBlank() || bytes == null || bytes.isEmpty()) {
                        result.success(null)
                    } else {
                        try {
                            val artworkFile = File(
                                cacheDir,
                                "soundneed_media_art_${key.hashCode()}.png"
                            )
                            artworkFile.outputStream().use { it.write(bytes) }
                            result.success(Uri.fromFile(artworkFile).toString())
                        } catch (error: Exception) {
                            result.error(
                                "ARTWORK_CACHE_FAILED",
                                error.message,
                                null
                            )
                        }

                    }
                }

                else -> {
                    result.notImplemented()
                }
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "soundneed/visualizer"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "hasPermission" -> {
                    result.success(
                        ContextCompat.checkSelfPermission(
                            this,
                            Manifest.permission.RECORD_AUDIO
                        ) == PackageManager.PERMISSION_GRANTED
                    )
                }
                "start" -> {
                    val sessionId = call.argument<Number>("sessionId")?.toInt()
                    if (sessionId == null || sessionId <= 0) {
                        result.success(false)
                    } else if (ContextCompat.checkSelfPermission(
                            this,
                            Manifest.permission.RECORD_AUDIO
                        ) == PackageManager.PERMISSION_GRANTED
                    ) {
                        result.success(startAudioVisualizer(sessionId))
                    } else if (pendingVisualizerResult != null) {
                        result.success(false)
                    } else {
                        pendingVisualizerResult = result
                        pendingVisualizerSessionId = sessionId
                        ActivityCompat.requestPermissions(
                            this,
                            arrayOf(Manifest.permission.RECORD_AUDIO),
                            VISUALIZER_PERMISSION_REQUEST_CODE
                        )
                    }
                }
                "stop" -> {
                    stopAudioVisualizer()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "soundneed/visualizer_data"
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                visualizerEventSink = events
            }

            override fun onCancel(arguments: Any?) {
                visualizerEventSink = null
                stopAudioVisualizer()
                pendingVisualizerResult?.success(false)
                pendingVisualizerResult = null
                pendingVisualizerSessionId = null
            }
        })

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "soundneed/equalizer"
        ).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "open" -> {
                        val sessionId = call.argument<Number>("sessionId")?.toInt()
                        if (sessionId == null || sessionId <= 0) {
                            result.error("INVALID_SESSION", "La sesión de audio no es válida.", null)
                            return@setMethodCallHandler
                        }
                        if (equalizerSessionId != sessionId || equalizer == null) {
                            closeAudioEqualizer()
                            val effect = Equalizer(0, sessionId)
                            equalizer = effect
                            equalizerSessionId = sessionId
                        }

                        val effect = equalizer ?: throw IllegalStateException(
                            "Android no creó el ecualizador."
                        )
                        val range = effect.bandLevelRange
                        val bands = (0 until effect.numberOfBands.toInt()).map { index ->
                            val band = index.toShort()
                            mapOf(
                                "index" to index,
                                "frequencyHz" to (effect.getCenterFreq(band) / 1000),
                                "levelMb" to effect.getBandLevel(band).toInt(),
                            )
                        }
                        val presets = (0 until effect.numberOfPresets.toInt()).map { index ->
                            mapOf(
                                "id" to index,
                                "name" to effect.getPresetName(index.toShort()),
                            )
                        }
                        result.success(
                            mapOf(
                                "supported" to bands.isNotEmpty(),
                                "minimumMb" to range[0].toInt(),
                                "maximumMb" to range[1].toInt(),
                                "bands" to bands,
                                "presets" to presets,
                            )
                        )
                    }
                    "setEnabled" -> {
                        val effect = equalizer ?: throw IllegalStateException(
                            "Abre primero el ecualizador."
                        )
                        effect.enabled = call.argument<Boolean>("enabled") ?: false
                        result.success(effect.enabled)
                    }
                    "setBandLevel" -> {
                        val effect = equalizer ?: throw IllegalStateException(
                            "Abre primero el ecualizador."
                        )
                        val band = call.argument<Number>("band")?.toInt()
                            ?: throw IllegalArgumentException("Falta la banda de audio.")
                        val level = call.argument<Number>("levelMb")?.toInt()
                            ?: throw IllegalArgumentException("Falta el nivel de audio.")
                        effect.setBandLevel(band.toShort(), level.coerceIn(
                            effect.bandLevelRange[0].toInt(),
                            effect.bandLevelRange[1].toInt(),
                        ).toShort())
                        result.success(null)
                    }
                    "setBandLevels" -> {
                        val effect = equalizer ?: throw IllegalStateException(
                            "Abre primero el ecualizador."
                        )
                        val levels = call.argument<List<Number>>("levelsMb")
                            ?: throw IllegalArgumentException("Faltan los niveles de audio.")
                        if (levels.size != effect.numberOfBands.toInt()) {
                            throw IllegalArgumentException("La cantidad de bandas no coincide.")
                        }
                        val range = effect.bandLevelRange
                        levels.forEachIndexed { index, level ->
                            effect.setBandLevel(
                                index.toShort(),
                                level.toInt().coerceIn(
                                    range[0].toInt(),
                                    range[1].toInt(),
                                ).toShort(),
                            )
                        }
                        result.success(
                            (0 until effect.numberOfBands.toInt()).map { index ->
                                effect.getBandLevel(index.toShort()).toInt()
                            }
                        )
                    }
                    "usePreset" -> {
                        val effect = equalizer ?: throw IllegalStateException(
                            "Abre primero el ecualizador."
                        )
                        val preset = call.argument<Number>("presetId")?.toInt()
                            ?: throw IllegalArgumentException("Falta el modo de sonido.")
                        if (preset !in 0 until effect.numberOfPresets.toInt()) {
                            throw IllegalArgumentException("El modo seleccionado no existe.")
                        }
                        effect.usePreset(preset.toShort())
                        result.success(
                            (0 until effect.numberOfBands.toInt()).map { index ->
                                effect.getBandLevel(index.toShort()).toInt()
                            }
                        )
                    }
                    "reset" -> {
                        val effect = equalizer ?: throw IllegalStateException(
                            "Abre primero el ecualizador."
                        )
                        (0 until effect.numberOfBands.toInt()).forEach { index ->
                            effect.setBandLevel(index.toShort(), 0)
                        }
                        result.success(
                            (0 until effect.numberOfBands.toInt()).map { index ->
                                effect.getBandLevel(index.toShort()).toInt()
                            }
                        )
                    }
                    "close" -> {
                        closeAudioEqualizer()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (error: Exception) {
                Log.w("SoundNeedEqualizer", "No se pudo cambiar el ecualizador", error)
                result.error(
                    "EQUALIZER_ERROR",
                    error.message ?: "No se pudo aplicar el ecualizador.",
                    null,
                )
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            WIDGET_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "updatePlayback" -> {
                    SoundNeedWidgetProvider.updatePlayback(
                        this,
                        call.argument<String>("title").orEmpty(),
                        call.argument<String>("artist").orEmpty(),
                        call.argument<String>("artUri").orEmpty(),
                        call.argument<Boolean>("playing") ?: false
                    )
                    result.success(null)
                }
                "updateProgress" -> {
                    SoundNeedWidgetProvider.updateProgress(
                        this,
                        call.argument<Number>("position")?.toLong() ?: 0L,
                        call.argument<Number>("duration")?.toLong() ?: 0L
                    )
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "soundneed/network"
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                networkEventSink = events
                connectivityManager =
                    getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
                try {
                    connectivityManager?.registerNetworkCallback(
                        NetworkRequest.Builder()
                            .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                            .build(),
                        networkCallback
                    )
                } catch (_: Exception) {
                    // Conservamos la reproducción aunque Android rechace el callback.
                }
                publishNetworkState()
            }

            override fun onCancel(arguments: Any?) {
                try {
                    connectivityManager?.unregisterNetworkCallback(networkCallback)
                } catch (_: Exception) {
                    // Puede que el callback ya estuviera cancelado.
                }
                networkEventSink = null
                connectivityManager = null
            }
        })

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "soundneed/download_progress"
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                downloadProgressSink = events
            }

            override fun onCancel(arguments: Any?) {
                downloadProgressSink = null
            }
        })

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "soundneed/shared_song"
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                sharedSongEventSink = events
                val link = pendingSharedSongLink ?: intent?.dataString
                if (isSoundNeedTrackLink(link)) {
                    pendingSharedSongLink = null
                    intent?.data = null
                    events?.success(link)
                }
            }

            override fun onCancel(arguments: Any?) {
                sharedSongEventSink = null
            }
        })

        // ============================================================
        // CANAL YOUTUBE EXTRACTOR
        // ============================================================

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            YOUTUBE_CHANNEL
        ).setMethodCallHandler { call, result ->

            when (call.method) {

                "getVideoMetadata" -> {
                    val videoId = call.argument<String>("videoId").orEmpty()
                    if (videoId.isBlank()) {
                        result.success(null)
                        return@setMethodCallHandler
                    }
                    extractorExecutor.execute {
                        try {
                            initializeNewPipe()
                            val extractor = NewPipe.getService("YouTube")
                                .getStreamExtractor("https://www.youtube.com/watch?v=$videoId")
                            extractor.fetchPage()
                            val metadata = mapOf(
                                "title" to extractor.name,
                                "artist" to extractor.uploaderName,
                                "thumbnail" to extractor.thumbnails.firstOrNull()?.url.orEmpty()
                            )
                            runOnUiThread { result.success(metadata) }
                        } catch (error: Exception) {
                            Log.w("SoundNeedYouTube", "No se pudieron obtener metadatos", error)
                            runOnUiThread { result.success(null) }
                        }
                    }
                }

                "getAudioUrl" -> {

                    val videoId =
                        call.argument<String>("videoId")

                    if (videoId.isNullOrBlank()) {
                        result.error(
                            "INVALID_VIDEO_ID",
                            "El videoId está vacío",
                            null
                        )
                        return@setMethodCallHandler
                    }

                    extractorExecutor.execute {

                        try {

                            val url =
                                getYouTubeAudioUrl(videoId)

                            runOnUiThread {

                                if (url != null) {
                                    result.success(url)
                                } else {
                                    result.error(
                                        "NO_AUDIO",
                                        "No se encontró un stream de audio",
                                        null
                                    )
                                }
                            }

                        } catch (e: Exception) {

                            Log.e(
                                "SoundNeedYouTube",
                                "Error extrayendo audio",
                                e
                            )

                            runOnUiThread {
                                result.error(
                                    "EXTRACTION_ERROR",
                                    e.message ?: "Error desconocido",
                                    null
                                )
                            }
                        }
                    }
                }

                "getVideoUrl" -> {
                    val videoId = call.argument<String>("videoId")
                    if (videoId.isNullOrBlank()) {
                        result.error("INVALID_VIDEO_ID", "El videoId está vacío", null)
                        return@setMethodCallHandler
                    }

                    extractorExecutor.execute {
                        try {
                            val url = getYouTubeVideoUrl(videoId)
                            runOnUiThread {
                                if (url != null) {
                                    result.success(url)
                                } else {
                                    result.error(
                                        "NO_VIDEO",
                                        "No se encontró un stream de video reproducible",
                                        null
                                    )
                                }
                            }
                        } catch (error: Exception) {
                            Log.e("SoundNeedYouTube", "Error extrayendo video", error)
                            runOnUiThread {
                                result.error(
                                    "VIDEO_EXTRACTION_ERROR",
                                    error.message ?: "Error desconocido",
                                    null
                                )
                            }
                        }
                    }
                }

                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    override fun onDestroy() {
        castDiscoveryManager?.dispose()
        castDiscoveryManager = null
        castSenderManager?.dispose()
        castSenderManager = null
        super.onDestroy()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val link = intent.dataString
        if (isSoundNeedTrackLink(link)) {
            if (sharedSongEventSink == null) {
                pendingSharedSongLink = link
            } else {
                sharedSongEventSink?.success(link)
            }
            intent.data = null
        }
    }

    private fun isSoundNeedTrackLink(link: String?): Boolean =
        link?.let {
            val uri = Uri.parse(it)
            uri.scheme.equals("soundneed", ignoreCase = true) &&
                uri.host.equals("track", ignoreCase = true)
        } == true

    private fun buildSoundNeedShareLink(
        deepLink: String,
        title: String,
        artist: String,
    ): String {
        val source = Uri.parse(deepLink)
        val result = Uri.Builder()
            .scheme("https")
            .authority("breinermuleth64-cyber.github.io")
            .appendPath("soundneed-links")
            .appendPath("share.html")
            .appendQueryParameter("preview", "v2")

        source.pathSegments.firstOrNull()?.let {
            result.appendQueryParameter("videoId", it)
        }
        source.queryParameterNames.forEach { name ->
            source.getQueryParameters(name).forEach { value ->
                result.appendQueryParameter(name, value)
            }
        }
        if (!source.queryParameterNames.contains("title")) {
            result.appendQueryParameter("title", title)
        }
        if (!source.queryParameterNames.contains("artist")) {
            result.appendQueryParameter("artist", artist)
        }
        return result.build().toString()
    }

    private fun createSongShareCard(
        title: String,
        artist: String,
        artworkBytes: ByteArray?,
    ): Uri {
        val width = 1080
        val height = 1350
        val coverHeight = 960
        val background = android.graphics.Color.rgb(7, 15, 21)
        val accent = android.graphics.Color.rgb(47, 205, 190)
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val backgroundPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            shader = LinearGradient(
                0f,
                0f,
                0f,
                height.toFloat(),
                intArrayOf(
                    android.graphics.Color.rgb(13, 37, 43),
                    android.graphics.Color.rgb(17, 24, 39),
                    background,
                ),
                null,
                Shader.TileMode.CLAMP,
            )
        }
        canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), backgroundPaint)
        backgroundPaint.shader = null

        val cardBounds = android.graphics.RectF(42f, 42f, 1038f, 1000f)
        val cardPath = android.graphics.Path().apply {
            addRoundRect(cardBounds, 44f, 44f, android.graphics.Path.Direction.CW)
        }
        canvas.save()
        canvas.clipPath(cardPath)
        val cover = artworkBytes?.let {
            BitmapFactory.decodeByteArray(it, 0, it.size)
        }
        if (cover != null) {
            val targetWidth = cardBounds.width().toInt()
            val targetHeight = cardBounds.height().toInt()
            val scale = maxOf(targetWidth.toFloat() / cover.width, targetHeight.toFloat() / cover.height)
            val cropWidth = targetWidth / scale
            val cropHeight = targetHeight / scale
            val source = android.graphics.Rect(
                ((cover.width - cropWidth) / 2).toInt().coerceAtLeast(0),
                ((cover.height - cropHeight) / 2).toInt().coerceAtLeast(0),
                ((cover.width + cropWidth) / 2).toInt().coerceAtMost(cover.width),
                ((cover.height + cropHeight) / 2).toInt().coerceAtMost(cover.height),
            )
            canvas.drawBitmap(
                cover,
                source,
                android.graphics.Rect(
                    cardBounds.left.toInt(), cardBounds.top.toInt(),
                    cardBounds.right.toInt(), cardBounds.bottom.toInt(),
                ),
                Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG),
            )
            cover.recycle()
        } else {
            val notePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = android.graphics.Color.argb(105, 255, 255, 255)
                textSize = 320f
                typeface = Typeface.create("sans-serif", Typeface.BOLD)
                textAlign = Paint.Align.CENTER
            }
            canvas.drawText("♫", width / 2f, 610f, notePaint)
        }

        val imageShade = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            shader = LinearGradient(
                0f,
                560f,
                0f,
                1000f,
                intArrayOf(
                    android.graphics.Color.TRANSPARENT,
                    android.graphics.Color.argb(115, 0, 0, 0),
                    android.graphics.Color.argb(220, 4, 12, 17),
                ),
                floatArrayOf(0f, 0.64f, 1f),
                Shader.TileMode.CLAMP,
            )
        }
        canvas.drawRect(cardBounds.left, 560f, cardBounds.right, cardBounds.bottom, imageShade)
        imageShade.shader = null

        val appIcon = applicationInfo.loadIcon(packageManager)
        val logoPill = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = android.graphics.Color.argb(178, 6, 15, 21)
        }
        canvas.drawRoundRect(70f, 70f, 358f, 154f, 42f, 42f, logoPill)
        appIcon.setBounds(91, 91, 134, 134)
        appIcon.draw(canvas)
        val brandPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = android.graphics.Color.WHITE
            textSize = 29f
            typeface = Typeface.create("sans-serif-medium", Typeface.BOLD)
        }
        canvas.drawText("SoundNeed", 153f, 124f, brandPaint)

        canvas.restore()

        val contentLeft = 68f
        val titlePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = android.graphics.Color.WHITE
            textSize = 59f
            typeface = Typeface.create("sans-serif", Typeface.BOLD)
        }
        val titleLines = wrapText(title, 940f, titlePaint, 2)
        val titleBaseY = if (titleLines.size > 1) 1043f else 1080f
        titleLines.forEachIndexed { index, line ->
            canvas.drawText(line, contentLeft, titleBaseY + index * 64f, titlePaint)
        }

        val artistPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = android.graphics.Color.rgb(196, 204, 213)
            textSize = 37f
            typeface = Typeface.create("sans-serif", Typeface.NORMAL)
        }
        val artistY = if (titleLines.size > 1) 1170f else 1136f
        canvas.drawText(ellipsizeText(artist, 920f, artistPaint), contentLeft, artistY, artistPaint)

        val playerSurface = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = android.graphics.Color.argb(220, 23, 34, 46)
        }
        canvas.drawRoundRect(46f, 1200f, 1034f, 1320f, 60f, 60f, playerSurface)
        val playerOutline = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = android.graphics.Color.argb(60, 115, 231, 223)
            style = Paint.Style.STROKE
            strokeWidth = 2f
        }
        canvas.drawRoundRect(47f, 1201f, 1033f, 1319f, 59f, 59f, playerOutline)

        appIcon.setBounds(75, 1222, 130, 1277)
        appIcon.draw(canvas)
        val eyebrowPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = accent
            textSize = 20f
            letterSpacing = 0.08f
            typeface = Typeface.create("sans-serif-medium", Typeface.BOLD)
        }
        canvas.drawText("COMPARTIDA DESDE", 158f, 1250f, eyebrowPaint)
        val footerPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = android.graphics.Color.WHITE
            textSize = 31f
            typeface = Typeface.create("sans-serif-medium", Typeface.BOLD)
        }
        canvas.drawText("SoundNeed", 158f, 1290f, footerPaint)

        val playPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = accent
        }
        canvas.drawCircle(958f, 1260f, 43f, playPaint)
        playPaint.color = android.graphics.Color.rgb(7, 20, 27)
        val playTriangle = android.graphics.Path().apply {
            moveTo(950f, 1237f)
            lineTo(950f, 1283f)
            lineTo(982f, 1260f)
            close()
        }
        canvas.drawPath(playTriangle, playPaint)

        val directory = File(cacheDir, "shared").apply { mkdirs() }
        val staleBefore = System.currentTimeMillis() - 7L * 24 * 60 * 60 * 1000
        directory.listFiles()
            ?.filter { it.name.startsWith("soundneed-song-") && it.lastModified() < staleBefore }
            ?.forEach { it.delete() }
        val output = File(directory, "soundneed-song-${System.currentTimeMillis()}.jpg")
        output.outputStream().use { stream ->
            bitmap.compress(Bitmap.CompressFormat.JPEG, 92, stream)
        }
        bitmap.recycle()
        return FileProvider.getUriForFile(this, "$packageName.fileprovider", output)
    }

    private fun wrapText(value: String, maxWidth: Float, paint: Paint, maxLines: Int): List<String> {
        val words = value.trim().split(Regex("\\s+")).filter { it.isNotBlank() }
        if (words.isEmpty()) return listOf("")

        val lines = mutableListOf<String>()
        var current = ""
        words.forEach { word ->
            val candidate = if (current.isEmpty()) word else "$current $word"
            if (paint.measureText(candidate) <= maxWidth) {
                current = candidate
            } else {
                if (current.isNotEmpty()) lines += current
                current = word
            }
        }
        if (current.isNotEmpty()) lines += current
        if (lines.size <= maxLines) {
            return lines.map { ellipsizeText(it, maxWidth, paint) }
        }

        val visible = lines.take(maxLines).toMutableList()
        visible[maxLines - 1] = ellipsizeText(visible[maxLines - 1], maxWidth, paint)
        return visible
    }

    private fun ellipsizeText(value: String, maxWidth: Float, paint: Paint): String {
        if (paint.measureText(value) <= maxWidth) return value
        var shortened = value
        while (shortened.isNotEmpty() && paint.measureText("$shortened…") > maxWidth) {
            shortened = shortened.dropLast(1)
        }
        return "$shortened…"
    }

    private fun startAudioVisualizer(sessionId: Int): Boolean {
        stopAudioVisualizer()
        return try {
            val effect = Visualizer(sessionId)
            val captureRange = Visualizer.getCaptureSizeRange()
            effect.captureSize = captureRange[1]
            effect.setDataCaptureListener(
                object : Visualizer.OnDataCaptureListener {
                    override fun onWaveFormDataCapture(
                        visualizer: Visualizer?, waveform: ByteArray?, samplingRate: Int
                    ) = Unit

                    override fun onFftDataCapture(
                        visualizer: Visualizer?, fft: ByteArray?, samplingRate: Int
                    ) {
                        if (fft == null || fft.size < 8) return
                        val bandCount = 36
                        val bands = ArrayList<Double>(bandCount)
                        for (index in 0 until bandCount) {
                            val low = (2.0 * Math.pow(64.0, index.toDouble() / bandCount))
                                .toInt().coerceIn(1, fft.size / 2 - 1)
                            val high = (2.0 * Math.pow(64.0, (index + 1).toDouble() / bandCount))
                                .toInt().coerceIn(low + 1, fft.size / 2)
                            var peak = 0.0
                            for (bin in low until high) {
                                val real = fft[bin * 2].toInt()
                                val imaginary = fft[bin * 2 + 1].toInt()
                                peak = maxOf(peak, Math.hypot(real.toDouble(), imaginary.toDouble()))
                            }
                            bands.add(((peak - 3.0) / 55.0).coerceIn(0.0, 1.0))
                        }
                        runOnUiThread { visualizerEventSink?.success(bands) }
                    }
                },
                Visualizer.getMaxCaptureRate() / 3,
                false,
                true
            )
            effect.enabled = true
            visualizer = effect
            true
        } catch (error: Exception) {
            Log.w("SoundNeedVisualizer", "No se pudo iniciar el FFT de audio", error)
            stopAudioVisualizer()
            false
        }
    }

    private fun stopAudioVisualizer() {
        runCatching { visualizer?.enabled = false }
        runCatching { visualizer?.release() }
        visualizer = null
    }

    private fun closeAudioEqualizer() {
        runCatching { equalizer?.enabled = false }
        runCatching { equalizer?.release() }
        equalizer = null
        equalizerSessionId = null
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != VISUALIZER_PERMISSION_REQUEST_CODE) return
        val result = pendingVisualizerResult ?: return
        val sessionId = pendingVisualizerSessionId
        pendingVisualizerResult = null
        pendingVisualizerSessionId = null
        val granted = grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED
        result.success(granted && sessionId != null && startAudioVisualizer(sessionId))
    }

    @Deprecated("Deprecated in Android")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == DELETE_MUSIC_REQUEST_CODE) {
            val pendingResult = pendingDeleteResult ?: return
            pendingDeleteResult = null
            pendingResult.success(resultCode == RESULT_OK)
            return
        }
        if (requestCode != PICK_MUSIC_FOLDER_REQUEST_CODE) return

        val pendingResult = pendingFolderPickerResult ?: return
        pendingFolderPickerResult = null
        val uri = data?.data
        if (resultCode != RESULT_OK || uri == null) {
            pendingResult.success(null)
            return
        }

        try {
            val readPermission = data.flags and Intent.FLAG_GRANT_READ_URI_PERMISSION
            if (readPermission != 0) {
                contentResolver.takePersistableUriPermission(uri, readPermission)
            }
            val path = folderPathFromTreeUri(uri)
            if (path == null) {
                pendingResult.error(
                    "UNSUPPORTED_FOLDER",
                    "Selecciona una carpeta del almacenamiento del dispositivo.",
                    null
                )
                return
            }

            val preferences = getSharedPreferences(MUSIC_FOLDERS_PREFS, Context.MODE_PRIVATE)
            val paths = preferences.getStringSet(MUSIC_FOLDERS_KEY, emptySet())
                ?.toMutableSet() ?: mutableSetOf()
            paths.add(path)
            preferences.edit().putStringSet(MUSIC_FOLDERS_KEY, paths).apply()
            pendingResult.success(
                mapOf("path" to path, "name" to (File(path).name.ifBlank { path }))
            )
        } catch (error: Exception) {
            pendingResult.error("FOLDER_PICK_FAILED", error.message, null)
        }
    }

    private fun publishNetworkState() {
        val manager =
            getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val connected = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val network = manager.activeNetwork
            val capabilities = manager.getNetworkCapabilities(network)
            capabilities?.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) == true &&
                capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)
        } else {
            @Suppress("DEPRECATION")
            manager.activeNetworkInfo?.isConnected == true
        }
        runOnUiThread { networkEventSink?.success(connected) }
    }

    // ============================================================
    // INICIALIZAR NEWPIPE (UNA SOLA VEZ)
    // ============================================================

    private fun initializeNewPipe() {
        if (newPipeInitialized) return

        synchronized(this) {
            if (newPipeInitialized) return

            NewPipe.init(
                NewPipeDownloader()
            )

            newPipeInitialized = true

            Log.d(
                "SoundNeedYouTube",
                "NewPipe inicializado"
            )
        }
    }

    // ============================================================
    // PERMISO DE AUDIO
    // ============================================================

    private fun hasAudioPermission(): Boolean {

        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {

            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.READ_MEDIA_AUDIO
            ) == PackageManager.PERMISSION_GRANTED

        } else {
            val readGranted = ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.READ_EXTERNAL_STORAGE
            ) == PackageManager.PERMISSION_GRANTED
            val writeGranted = Build.VERSION.SDK_INT > Build.VERSION_CODES.P ||
                ContextCompat.checkSelfPermission(
                    this,
                    Manifest.permission.WRITE_EXTERNAL_STORAGE
                ) == PackageManager.PERMISSION_GRANTED
            readGranted && writeGranted
        }
    }

    private fun requestAudioPermission() {

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {

            if (
                ContextCompat.checkSelfPermission(
                    this,
                    Manifest.permission.READ_MEDIA_AUDIO
                ) != PackageManager.PERMISSION_GRANTED
            ) {

                ActivityCompat.requestPermissions(
                    this,
                    arrayOf(
                        Manifest.permission.READ_MEDIA_AUDIO
                    ),
                    100
                )
            }

        } else {
            val permissions = mutableListOf<String>()
            if (ContextCompat.checkSelfPermission(
                    this,
                    Manifest.permission.READ_EXTERNAL_STORAGE
                ) != PackageManager.PERMISSION_GRANTED
            ) {
                permissions.add(Manifest.permission.READ_EXTERNAL_STORAGE)
            }
            if (Build.VERSION.SDK_INT <= Build.VERSION_CODES.P &&
                ContextCompat.checkSelfPermission(
                    this,
                    Manifest.permission.WRITE_EXTERNAL_STORAGE
                ) != PackageManager.PERMISSION_GRANTED
            ) {
                permissions.add(Manifest.permission.WRITE_EXTERNAL_STORAGE)
            }
            if (permissions.isNotEmpty()) {
                ActivityCompat.requestPermissions(this, permissions.toTypedArray(), 100)
            }
        }
    }

    // ============================================================
    // PERMISO DE NOTIFICACIONES
    // ============================================================

    private fun requestNotificationPermission() {

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {

            if (
                ContextCompat.checkSelfPermission(
                    this,
                    Manifest.permission.POST_NOTIFICATIONS
                ) != PackageManager.PERMISSION_GRANTED
            ) {

                ActivityCompat.requestPermissions(
                    this,
                    arrayOf(
                        Manifest.permission.POST_NOTIFICATIONS
                    ),
                    NOTIFICATION_PERMISSION_REQUEST_CODE
                )
            }
        }
    }

    private fun showNewMusicNotification(count: Int): Boolean {
        if (count <= 0 || !NotificationManagerCompat.from(this).areNotificationsEnabled()) {
            return false
        }

        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                NEW_MUSIC_NOTIFICATION_CHANNEL_ID,
                "Novedades musicales",
                NotificationManager.IMPORTANCE_DEFAULT
            ).apply {
                description = "Avisos cuando se actualizan las tendencias musicales"
            }
            manager.createNotificationChannel(channel)
        }

        val title = if (count == 1) "Hay música nueva para descubrir" else "Las tendencias se actualizaron"
        val message = if (count == 1) {
            "Encontramos una canción nueva en tus tendencias."
        } else {
            "Encontramos $count canciones nuevas en tus tendencias."
        }
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = launchIntent?.let {
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
            PendingIntent.getActivity(this, 3107, it, flags)
        }
        val notification = NotificationCompat.Builder(
            this,
            NEW_MUSIC_NOTIFICATION_CHANNEL_ID
        )
            .setSmallIcon(applicationInfo.icon)
            .setContentTitle(title)
            .setContentText(message)
            .setStyle(NotificationCompat.BigTextStyle().bigText(message))
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setAutoCancel(true)
            .apply { if (pendingIntent != null) setContentIntent(pendingIntent) }
            .build()

        return try {
            NotificationManagerCompat.from(this).notify(
                NEW_MUSIC_NOTIFICATION_ID,
                notification
            )
            true
        } catch (_: SecurityException) {
            false
        }
    }

    // ============================================================
    // OBTENER CANCIONES DESDE MEDIASTORE
    // ============================================================

    private fun folderPathFromTreeUri(uri: Uri): String? {
        if (uri.authority != "com.android.externalstorage.documents") return null
        val documentId = DocumentsContract.getTreeDocumentId(uri)
        val separator = documentId.indexOf(':')
        if (separator <= 0) return null

        val volume = documentId.substring(0, separator)
        val relativePath = documentId.substring(separator + 1).trim('/')
        val root = if (volume.equals("primary", ignoreCase = true)) {
            Environment.getExternalStorageDirectory()
        } else {
            File("/storage", volume)
        }
        return if (relativePath.isEmpty()) root.absolutePath
        else File(root, relativePath).absolutePath
    }

    private fun getSelectedMusicFolders(): List<Map<String, String>> {
        val paths = getSharedPreferences(MUSIC_FOLDERS_PREFS, Context.MODE_PRIVATE)
            .getStringSet(MUSIC_FOLDERS_KEY, emptySet()) ?: emptySet()
        return paths.sorted().map { path ->
            mapOf("path" to path, "name" to (File(path).name.ifBlank { path }))
        }
    }

    private fun registerSoundNeedFolder() {
        val musicDirectory =
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MUSIC)
        val folderPath = File(musicDirectory, "SoundNeed").absolutePath
        val preferences = getSharedPreferences(MUSIC_FOLDERS_PREFS, Context.MODE_PRIVATE)
        val paths = preferences.getStringSet(MUSIC_FOLDERS_KEY, emptySet())
            ?.toMutableSet() ?: mutableSetOf()
        paths.add(folderPath)
        preferences.edit().putStringSet(MUSIC_FOLDERS_KEY, paths).apply()
    }

    private fun saveDownloadedArtwork(audioKey: String, bytes: ByteArray?): String? {
        if (bytes == null || bytes.isEmpty()) return null
        return try {
            val artworkFile = File(filesDir, "soundneed_download_art_${audioKey.hashCode()}.jpg")
            artworkFile.outputStream().use { it.write(bytes) }
            val artworkUri = Uri.fromFile(artworkFile).toString()
            val preferences = getSharedPreferences(MUSIC_FOLDERS_PREFS, Context.MODE_PRIVATE)
            val mappings = preferences.getStringSet(DOWNLOAD_ARTWORKS_KEY, emptySet())
                ?.filterNot { it.startsWith("$audioKey|") }
                ?.toMutableSet() ?: mutableSetOf()
            mappings.add("$audioKey|$artworkUri")
            preferences.edit().putStringSet(DOWNLOAD_ARTWORKS_KEY, mappings).apply()
            artworkUri
        } catch (error: Exception) {
            Log.w("SoundNeedDownload", "No se pudo guardar la portada", error)
            null
        }
    }

    private fun downloadedArtworkFor(vararg keys: String): String? {
        val mappings = getSharedPreferences(MUSIC_FOLDERS_PREFS, Context.MODE_PRIVATE)
            .getStringSet(DOWNLOAD_ARTWORKS_KEY, emptySet()) ?: return null
        for (key in keys) {
            val mapping = mappings.firstOrNull { it.startsWith("$key|") } ?: continue
            return mapping.substringAfter('|')
        }
        return null
    }

    private fun safeDownloadName(value: String): String {
        val sanitized = value
            .replace(Regex("[^\\p{L}\\p{N}._ -]"), "_")
            .trim()
            .trim('.')
        return sanitized.take(100).ifBlank { "SoundNeed audio" }
    }

    private fun downloadAudioFile(
        audioUrl: String,
        title: String,
        artist: String,
        album: String,
        duration: Long,
        artwork: ByteArray?,
        sourceUrl: String,
        onProgress: (Long, Long) -> Unit
    ): Map<String, String> {
        val startTime = System.currentTimeMillis()
        Log.d("SoundNeedDownload", "INICIANDO descarga -> $audioUrl")

        val connection = (URL(audioUrl).openConnection() as HttpURLConnection).apply {
            connectTimeout = 15_000
            readTimeout = 30_000
            instanceFollowRedirects = true
            setRequestProperty("User-Agent", "Mozilla/5.0 (Linux; Android) SoundNeed/1.0")
            setRequestProperty("Accept", "audio/*,application/octet-stream,*/*")
        }

        try {
            val responseCode = connection.responseCode
            val httpTime = System.currentTimeMillis() - startTime
            Log.d("SoundNeedDownload", "Respuesta HTTP=$responseCode en ${httpTime}ms")

            if (responseCode !in 200..299) {
                throw IllegalStateException("HTTP $responseCode: El servidor respondió con error.")
            }
            val contentLength = connection.contentLengthLong
            Log.d("SoundNeedDownload", "Tamaño=$contentLength bytes")

            val acceptRanges = connection.getHeaderField("Accept-Ranges")
            val supportsRange = acceptRanges == "bytes"
            Log.d("SoundNeedDownload", "Accept-Ranges: $acceptRanges (soporta Range: $supportsRange)")

            val mimeType = connection.contentType
                ?.substringBefore(';')
                ?.trim()
                ?.takeIf { it.startsWith("audio/") || it == "video/mp4" }
                ?: "audio/mp4"
            val urlExtension = URL(audioUrl).path.substringAfterLast('.', "")
                .lowercase()
                .takeIf { it.matches(Regex("[a-z0-9]{2,5}")) }
            val extension = when (mimeType.lowercase()) {
                "audio/mpeg" -> "mp3"
                "audio/webm" -> "webm"
                "audio/ogg" -> "ogg"
                "audio/aac" -> "aac"
                "audio/mp4", "video/mp4" -> "m4a"
                else -> urlExtension ?: "m4a"
            }
            val displayName = "${safeDownloadName(title)}.$extension"

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val stagedFile = File.createTempFile("soundneed-download-", ".$extension", cacheDir)
                var savedUri: Uri? = null
                try {
                    java.io.FileOutputStream(stagedFile).use { output ->
                    // Intentar descarga paralela primero si el servidor soporta Range y el archivo es grande
                    var downloadSuccess = false
                    if (supportsRange && contentLength > 2 * 1024 * 1024) {
                        try {
                            Log.d("SoundNeedDownload", "Intentando descarga paralela (4 conexiones)")
                            downloadParallel(audioUrl, output, contentLength, startTime, onProgress)
                            downloadSuccess = true
                        } catch (parallelError: Exception) {
                            Log.w("SoundNeedDownload", "Descarga paralela falló: ${parallelError.message}")
                            Log.d("SoundNeedDownload", "Fallback a descarga normal (1 conexión)")
                            output.channel.truncate(0)
                            output.channel.position(0)
                            // Fallback a descarga normal
                            val bufferedInput = java.io.BufferedInputStream(
                                connection.inputStream,
                                1024 * 1024
                            )
                            val bufferedOutput = java.io.BufferedOutputStream(
                                output,
                                1024 * 1024
                            )

                            bufferedInput.use { input ->
                                bufferedOutput.use { out ->
                                    copyDownload(input, out, contentLength, startTime, onProgress)
                                }
                            }
                            downloadSuccess = true
                        }
                    } else {
                        // Usar streams bufferizados para mejor rendimiento
                        val bufferedInput = java.io.BufferedInputStream(
                            connection.inputStream,
                            1024 * 1024 // 1MB buffer
                        )
                        val bufferedOutput = java.io.BufferedOutputStream(
                            output,
                            1024 * 1024 // 1MB buffer
                        )

                        bufferedInput.use { input ->
                            bufferedOutput.use { out ->
                                copyDownload(input, out, contentLength, startTime, onProgress)
                            }
                        }
                        downloadSuccess = true
                    }

                    if (!downloadSuccess) {
                        throw IllegalStateException("La descarga falló en todos los intentos.")
                    }
                    }

                    writeEmbeddedTags(
                        stagedFile,
                        title,
                        artist,
                        album,
                        duration,
                        artwork,
                        sourceUrl
                    )

                    val values = ContentValues().apply {
                        put(MediaStore.Audio.Media.DISPLAY_NAME, displayName)
                        put(MediaStore.Audio.Media.TITLE, title)
                        put(MediaStore.Audio.Media.ARTIST, artist.ifBlank { "Artista desconocido" })
                        if (album.isNotBlank()) put(MediaStore.Audio.Media.ALBUM, album)
                        put(MediaStore.Audio.Media.MIME_TYPE, mimeType)
                        put(MediaStore.Audio.Media.RELATIVE_PATH, "Music/SoundNeed")
                        put(MediaStore.Audio.Media.IS_MUSIC, 1)
                        if (duration > 0) put(MediaStore.Audio.Media.DURATION, duration)
                        put(MediaStore.Audio.Media.IS_PENDING, 1)
                    }
                    val collection = MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
                    val destinationUri = contentResolver.insert(collection, values)
                        ?: throw IllegalStateException("No se pudo crear el archivo de audio.")
                    savedUri = destinationUri

                    val destination = contentResolver.openOutputStream(destinationUri, "w")
                        ?: throw IllegalStateException("No se pudo escribir el archivo.")
                    destination.use { output ->
                        stagedFile.inputStream().use { input -> input.copyTo(output) }
                    }

                    contentResolver.update(
                        destinationUri,
                        ContentValues().apply {
                            put(MediaStore.Audio.Media.IS_PENDING, 0)
                        },
                        null,
                        null
                    )
                } catch (error: Exception) {
                    savedUri?.let { contentResolver.delete(it, null, null) }
                    throw error
                } finally {
                    stagedFile.delete()
                }
                val publishedUri = savedUri
                    ?: throw IllegalStateException("No se publicó el archivo descargado.")
                registerSoundNeedFolder()
                val artworkUri = saveDownloadedArtwork(publishedUri.toString(), artwork)
                return mapOf(
                    "uri" to publishedUri.toString(),
                    "folderPath" to File(
                        Environment.getExternalStoragePublicDirectory(
                            Environment.DIRECTORY_MUSIC
                        ),
                        "SoundNeed"
                    ).absolutePath,
                    "name" to displayName,
                    "artworkUri" to artworkUri.orEmpty()
                )
            }

            if (ContextCompat.checkSelfPermission(
                    this,
                    Manifest.permission.WRITE_EXTERNAL_STORAGE
                ) != PackageManager.PERMISSION_GRANTED
            ) {
                throw IllegalStateException(
                    "Falta permiso de almacenamiento para guardar canciones en este Android."
                )
            }

            val folder = File(
                Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MUSIC),
                "SoundNeed"
            )
            if (!folder.exists() && !folder.mkdirs()) {
                throw IllegalStateException("No se pudo crear Música/SoundNeed.")
            }
            val file = File(folder, displayName)

            // Usar streams bufferizados
            val bufferedInput = java.io.BufferedInputStream(
                connection.inputStream,
                1024 * 1024
            )
            val bufferedOutput = java.io.BufferedOutputStream(
                file.outputStream(),
                1024 * 1024
            )

            bufferedInput.use { input ->
                bufferedOutput.use { output ->
                    copyDownload(input, output, contentLength, startTime, onProgress)
                }
            }
            writeEmbeddedTags(file, title, artist, album, duration, artwork, sourceUrl)
            registerSoundNeedFolder()

            val scanCompleted = CountDownLatch(1)
            MediaScannerConnection.scanFile(
                this,
                arrayOf(file.absolutePath),
                arrayOf(mimeType)
            ) { _, _ -> scanCompleted.countDown() }
            scanCompleted.await(10, TimeUnit.SECONDS)
            val scannedUri = contentResolver.query(
                MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                arrayOf(MediaStore.Audio.Media._ID),
                "${MediaStore.Audio.Media.DATA} = ?",
                arrayOf(file.absolutePath),
                null
            )?.use { cursor ->
                if (cursor.moveToFirst()) {
                    ContentUris.withAppendedId(
                        MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                        cursor.getLong(0)
                    ).toString()
                } else null
            }
            val artworkUri = saveDownloadedArtwork(
                scannedUri ?: file.absolutePath,
                artwork
            )

            return mapOf(
                "uri" to Uri.fromFile(file).toString(),
                "folderPath" to folder.absolutePath,
                "name" to displayName,
                "artworkUri" to artworkUri.orEmpty()
            )
        } finally {
            connection.disconnect()
        }
    }

    private fun writeEmbeddedTags(
        audioFile: File,
        title: String,
        artist: String,
        album: String,
        duration: Long,
        artwork: ByteArray?,
        sourceUrl: String
    ) {
        val metadata = hashMapOf(
            "TITLE" to title,
            "ARTIST" to artist.ifBlank { "Artista desconocido" },
            "COMMENT" to sourceUrl.takeIf { it.isNotBlank() }
                ?.let { "Source: $it" }.orEmpty()
        )
        if (album.isNotBlank()) metadata["ALBUM"] = album

        val metadataSaved = try {
            TagLib.setMetadata(audioFile.absolutePath, metadata)
        } catch (error: LinkageError) {
            Log.e("SoundNeedDownload", "El etiquetador no está disponible para esta ABI", error)
            return
        }
        if (!metadataSaved) {
            throw IllegalStateException("No se pudieron escribir las etiquetas de audio.")
        }

        if (artwork != null && artwork.isNotEmpty()) {
            val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeByteArray(artwork, 0, artwork.size, options)
            val mimeType = options.outMimeType?.takeIf { it.startsWith("image/") }
                ?: "image/jpeg"
            if (!TagLib.setArtwork(audioFile.absolutePath, artwork, mimeType, "")) {
                Log.w("SoundNeedDownload", "No se pudo incrustar la portada en ${audioFile.name}")
            }
        }

        // La duración se deriva del stream y también se guarda en MediaStore.
        Log.d("SoundNeedDownload", "Etiquetas escritas: ${audioFile.name}, duration=$duration")
    }

    private fun copyDownload(
        input: java.io.InputStream,
        output: java.io.OutputStream,
        totalBytes: Long,
        startTime: Long,
        onProgress: (Long, Long) -> Unit
    ) {
        val buffer = ByteArray(1024 * 1024) // 1MB buffer
        var copied = 0L
        var lastUpdate = System.currentTimeMillis()
        var lastLogUpdate = startTime

        while (true) {
            val count = input.read(buffer)
            if (count < 0) break
            output.write(buffer, 0, count)
            copied += count
            val now = System.currentTimeMillis()

            // Actualizar progreso cada 100ms
            if (now - lastUpdate >= 100L) {
                onProgress(copied, totalBytes)
                lastUpdate = now
            }

            // Loggear velocidad cada 1 segundo
            if (now - lastLogUpdate >= 1000L) {
                val elapsed = (now - startTime).coerceAtLeast(1L)
                val bytesPerSecond = copied * 1000L / elapsed
                Log.d(
                    "SoundNeedDownload",
                    "Descargando: $copied/$totalBytes bytes - ${bytesPerSecond / 1024} KB/s"
                )
                lastLogUpdate = now
            }
        }
        output.flush()
        onProgress(copied, totalBytes)

        val totalTime = System.currentTimeMillis() - startTime
        val avgSpeed = copied * 1000L / totalTime.coerceAtLeast(1L)
        Log.d(
            "SoundNeedDownload",
            "Descarga completada: $copied bytes en ${totalTime}ms - Promedio: ${avgSpeed / 1024} KB/s"
        )
    }

    private fun downloadParallel(
        audioUrl: String,
        output: java.io.OutputStream,
        totalBytes: Long,
        startTime: Long,
        onProgress: (Long, Long) -> Unit
    ) {
        val numConnections = 4
        val chunkSize = totalBytes / numConnections
        val chunks = Array(numConnections) { ByteArray(0) }
        val completed = AtomicInteger(0)
        val totalCopied = AtomicLong(0)
        val executor = Executors.newFixedThreadPool(numConnections)

        try {
            val futures = (0 until numConnections).map { index ->
                executor.submit {
                    val startByte = index * chunkSize
                    val endByte = if (index == numConnections - 1) totalBytes - 1 else (startByte + chunkSize - 1)

                    Log.d("SoundNeedDownload", "Conexión ${index + 1}: bytes $startByte-$endByte")

                    val conn = URL(audioUrl).openConnection() as HttpURLConnection
                    conn.setRequestProperty("Range", "bytes=$startByte-$endByte")
                    conn.connectTimeout = 15_000
                    conn.readTimeout = 30_000
                    conn.setRequestProperty("User-Agent", "Mozilla/5.0 (Linux; Android) SoundNeed/1.0")

                    val responseCode = conn.responseCode
                    if (responseCode !in 200..299 && responseCode != 206) {
                        throw IllegalStateException("Conexión ${index + 1} falló: HTTP $responseCode")
                    }

                    val buffer = ByteArray(256 * 1024) // 256KB buffer por conexión
                    val baos = java.io.ByteArrayOutputStream()
                    var copied = 0L

                    conn.inputStream.use { input ->
                        while (true) {
                            val count = input.read(buffer)
                            if (count < 0) break
                            baos.write(buffer, 0, count)
                            copied += count

                            val newTotal = totalCopied.addAndGet(count.toLong())
                            onProgress(newTotal, totalBytes)
                        }
                    }

                    chunks[index] = baos.toByteArray()
                    completed.incrementAndGet()
                    Log.d("SoundNeedDownload", "Conexión ${index + 1} completada: ${copied} bytes")
                }
            }

            // Esperar a que todas las conexiones terminen
            futures.forEach { it.get() }

            // Escribir en orden
            var lastUpdate = System.currentTimeMillis()
            var written = 0L
            chunks.forEach { chunk ->
                output.write(chunk)
                written += chunk.size
                val now = System.currentTimeMillis()
                if (now - lastUpdate >= 1000L) {
                    val elapsed = (now - startTime).coerceAtLeast(1L)
                    val bytesPerSecond = written * 1000L / elapsed
                    Log.d(
                        "SoundNeedDownload",
                        "Escribiendo: $written/$totalBytes bytes - ${bytesPerSecond / 1024} KB/s"
                    )
                    lastUpdate = now
                }
            }
            output.flush()

            val totalTime = System.currentTimeMillis() - startTime
            val avgSpeed = totalBytes * 1000L / totalTime.coerceAtLeast(1L)
            Log.d(
                "SoundNeedDownload",
                "Descarga paralela completada: $totalBytes bytes en ${totalTime}ms - Promedio: ${avgSpeed / 1024} KB/s"
            )
        } finally {
            executor.shutdown()
        }
    }

    private fun getSongs(): List<Map<String, Any?>> {

        val songs = mutableListOf<Map<String, Any?>>()

        if (!hasAudioPermission()) {
            return songs
        }

        val collection =
            MediaStore.Audio.Media.EXTERNAL_CONTENT_URI

        val projection = arrayOf(
            MediaStore.Audio.Media._ID,
            MediaStore.Audio.Media.TITLE,
            MediaStore.Audio.Media.DISPLAY_NAME,
            MediaStore.Audio.Media.ARTIST,
            MediaStore.Audio.Media.ALBUM,
            MediaStore.Audio.Media.ALBUM_ID,
            MediaStore.Audio.Media.DURATION,
            MediaStore.Audio.Media.MIME_TYPE,
            MediaStore.Audio.Media.SIZE,
            MediaStore.Audio.Media.IS_MUSIC,
            MediaStore.Audio.Media.DATA
        )

        val sortOrder =
            "${MediaStore.Audio.Media.TITLE} COLLATE NOCASE ASC"

        // Carpetas a excluir (audios de aplicaciones)
        val excludedFolders = listOf(
            "WhatsApp",
            "Android/data",
            "Android/media/com.whatsapp",
            "Android/media/com.facebook",
            "Android/media/com.instagram",
            "Android/media/com.snapchat",
            "Android/media/com.discord",
            "Android/media/com.telegram",
            "Recordings",
            "Voice Recorder",
            "Voice Notes",
            "Call Recordings",
            "Sounds",
            "Notifications",
            "Ringtones",
            "Alarms"
        )
        val selectedFolders = getSelectedMusicFolders().map { it.getValue("path") }

        contentResolver.query(
            collection,
            projection,
            null,
            null,
            sortOrder
        )?.use { cursor ->

            val idColumn =
                cursor.getColumnIndexOrThrow(
                    MediaStore.Audio.Media._ID
                )

            val titleColumn =
                cursor.getColumnIndexOrThrow(
                    MediaStore.Audio.Media.TITLE
                )

            val displayNameColumn =
                cursor.getColumnIndexOrThrow(
                    MediaStore.Audio.Media.DISPLAY_NAME
                )

            val artistColumn =
                cursor.getColumnIndexOrThrow(
                    MediaStore.Audio.Media.ARTIST
                )

            val albumColumn =
                cursor.getColumnIndexOrThrow(
                    MediaStore.Audio.Media.ALBUM
                )

            val albumIdColumn =
                cursor.getColumnIndexOrThrow(
                    MediaStore.Audio.Media.ALBUM_ID
                )

            val durationColumn =
                cursor.getColumnIndexOrThrow(
                    MediaStore.Audio.Media.DURATION
                )

            val mimeTypeColumn =
                cursor.getColumnIndexOrThrow(
                    MediaStore.Audio.Media.MIME_TYPE
                )

            val sizeColumn =
                cursor.getColumnIndexOrThrow(
                    MediaStore.Audio.Media.SIZE
                )

            val isMusicColumn =
                cursor.getColumnIndexOrThrow(
                    MediaStore.Audio.Media.IS_MUSIC
                )

            val dataColumn =
                cursor.getColumnIndexOrThrow(
                    MediaStore.Audio.Media.DATA
                )

            while (cursor.moveToNext()) {

                val id =
                    cursor.getLong(idColumn)

                val title =
                    cursor.getString(titleColumn)
                        ?: ""

                val displayName =
                    cursor.getString(displayNameColumn)
                        ?: ""

                val artist =
                    cursor.getString(artistColumn)
                        ?: "Artista desconocido"

                val album =
                    cursor.getString(albumColumn)
                        ?: "Álbum desconocido"

                val albumId =
                    if (!cursor.isNull(albumIdColumn)) {
                        cursor.getLong(albumIdColumn)
                    } else {
                        null
                    }

                val duration =
                    if (!cursor.isNull(durationColumn)) {
                        cursor.getLong(durationColumn)
                    } else {
                        0L
                    }

                val mimeType =
                    cursor.getString(mimeTypeColumn)
                        ?: ""

                val size =
                    if (!cursor.isNull(sizeColumn)) {
                        cursor.getLong(sizeColumn)
                    } else {
                        0L
                    }

                val isMusic =
                    cursor.getInt(isMusicColumn) != 0

                val dataPath =
                    cursor.getString(dataColumn) ?: ""

                // Filtrar por carpetas excluidas
                val isInExcludedFolder = excludedFolders.any { folder ->
                    dataPath.contains(folder, ignoreCase = true)
                }

                val isInSelectedFolder = selectedFolders.any { folder ->
                    dataPath.equals(folder, ignoreCase = true) ||
                        dataPath.startsWith(folder.trimEnd('/') + "/", ignoreCase = true)
                }

                if (isInExcludedFolder && !isInSelectedFolder) {
                    continue
                }

                val contentUri =
                    ContentUris.withAppendedId(
                        collection,
                        id
                    )

                val artworkUri =
                    downloadedArtworkFor(contentUri.toString(), dataPath)
                        ?: if (albumId != null && albumId > 0) {
                        "content://media/external/audio/albumart/$albumId"
                    } else {
                        ""
                    }

                songs.add(
                    mapOf(
                        "id" to id,
                        "title" to title,
                        "displayName" to displayName,
                        "artist" to artist,
                        "album" to album,
                        "albumId" to albumId,
                        "duration" to duration,
                        "mimeType" to mimeType,
                        "size" to size,
                        "uri" to contentUri.toString(),
                        "folderPath" to dataPath.substringBeforeLast('/', ""),
                        "artworkUri" to artworkUri,
                        "isMusic" to (isMusic || isInSelectedFolder)
                    )
                )
            }
        }

        return songs
    }

    // ============================================================
    // OBTENER PORTADA DEL ÁLBUM
    // ============================================================

    private fun getArtwork(albumId: Long): ByteArray? {

        return try {

            val artworkUri = ContentUris.withAppendedId(
                Uri.parse(
                    "content://media/external/audio/albumart"
                ),
                albumId
            )

            contentResolver.openInputStream(
                artworkUri
            )?.use { inputStream ->

                val bitmap =
                    BitmapFactory.decodeStream(inputStream)

                if (bitmap == null) {
                    null
                } else {

                    val outputStream =
                        ByteArrayOutputStream()

                    bitmap.compress(
                        android.graphics.Bitmap.CompressFormat.JPEG,
                        90,
                        outputStream
                    )

                    outputStream.toByteArray()
                }
            }

        } catch (e: Exception) {

            null
        }
    }

    private fun getEmbeddedArtwork(songUri: String): ByteArray? {
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(this, Uri.parse(songUri))
            retriever.embeddedPicture
        } catch (error: Exception) {
            Log.d("SoundNeedArtwork", "No se pudo leer portada incrustada de $songUri", error)
            null
        } finally {
            try {
                retriever.release()
            } catch (_: RuntimeException) {
                // El recurso puede no haberse inicializado correctamente.
            }
        }
    }

    // ============================================================
    // OBTENER URL DE AUDIO DE YOUTUBE (NEWPIPE)
    // ============================================================

    private fun getYouTubeAudioUrl(
        videoId: String
    ): String? {

        initializeNewPipe()

        Log.d(
            "SoundNeedYouTube",
            "Extrayendo audio para videoId=$videoId"
        )

        val service =
            NewPipe.getService("YouTube")

        val extractor =
            service.getStreamExtractor(
                "https://www.youtube.com/watch?v=$videoId"
            )

        extractor.fetchPage()

        val streams =
            extractor.getAudioStreams()

        if (streams.isEmpty()) {

            Log.w(
                "SoundNeedYouTube",
                "YouTube no devolvió streams de audio"
            )

            return null
        }

        // ========================================================
        // FILTRAR STREAMS UTILIZABLES
        // ========================================================

        val validStreams =
            streams.filter { stream ->

                stream.isUrl &&
                    stream.content.isNotBlank()
            }

        if (validStreams.isEmpty()) {

            Log.w(
                "SoundNeedYouTube",
                "Existen streams, pero ninguno tiene una URL directa válida"
            )

            return null
        }

        // ========================================================
        // MOSTRAR INFORMACIÓN DE LOS STREAMS
        // ========================================================

        for (stream in validStreams) {

            val mime =
                stream.codec ?: ""

            val bitrate =
                stream.getBitrate()

            Log.d(
                "SoundNeedYouTube",
                "Stream -> " +
                    "mime=$mime, " +
                    "bitrate=$bitrate, " +
                    "url=${stream.content.take(80)}..."
            )
        }

        // ========================================================
        // FUNCIÓN PARA OBTENER EL MIME COMPLETO
        // ========================================================

        fun mime(stream: AudioStream): String {
            return stream.codec
                ?.lowercase()
                ?.trim()
                ?: ""
        }

        // ========================================================
        // FUNCIÓN DE PRIORIDAD
        // ========================================================
        //
        // Queremos:
        //
        // 1. AAC-LC / mp4a.40.2
        // 2. Otros AAC / mp4a
        // 3. MP4 audio
        // 4. Opus/WebM
        // 5. Otros formatos
        //
        // El número mayor gana.
        // ========================================================

        fun codecPriority(stream: AudioStream): Int {

            val mimeType =
                mime(stream)

            return when {

                // AAC-LC explícito
                mimeType.contains("mp4a.40.2") -> 500

                // Cualquier AAC/mp4a
                mimeType.contains("mp4a") -> 450

                // Audio MP4 aunque el codec no esté indicado
                mimeType.contains("audio/mp4") -> 400

                // Opus
                mimeType.contains("opus") -> 250

                // WebM sin codec explícito
                mimeType.contains("audio/webm") -> 200

                else -> 0
            }
        }

        // ========================================================
        // FUNCIÓN DE PRIORIDAD DE BITRATE
        // ========================================================
        //
        // No buscamos simplemente el bitrate máximo.
        //
        // Preferimos:
        //
        // 128-192 kbps
        // después 192-256
        // después 96-128
        // después el resto
        //
        // Esto reduce la posibilidad de seleccionar un stream
        // innecesariamente pesado.
        // ========================================================

        fun bitrateScore(stream: AudioStream): Int {

            val bitrate =
                stream.getBitrate()

            return when {

                bitrate in 128_000..192_000 -> 400

                bitrate in 192_001..256_000 -> 350

                bitrate in 96_000..127_999 -> 300

                bitrate in 256_001..320_000 -> 250

                bitrate > 320_000 -> 150

                bitrate > 0 -> 100

                else -> 0
            }
        }

        // ========================================================
        // SELECCIÓN FINAL
        // ========================================================

        val selected =
            validStreams
                .sortedWith(
                    compareByDescending<AudioStream> {
                        codecPriority(it)
                    }.thenByDescending {
                        bitrateScore(it)
                    }.thenByDescending {
                        it.getBitrate()
                    }
                )
                .firstOrNull()

        if (selected == null) {

            Log.e(
                "SoundNeedYouTube",
                "No fue posible seleccionar un stream compatible"
            )

            return null
        }

        // ========================================================
        // INFORMACIÓN DEL STREAM SELECCIONADO
        // ========================================================

        val selectedMime =
            selected.codec ?: ""

        val selectedBitrate =
            selected.getBitrate()

        val selectedUrl =
            selected.content

        Log.d(
            "SoundNeedYouTube",
            "STREAM SELECCIONADO -> " +
                "mime=$selectedMime, " +
                "bitrate=$selectedBitrate"
        )

        // ========================================================
        // VALIDACIÓN FINAL DE LA URL
        // ========================================================

        if (selectedUrl.isBlank()) {

            Log.e(
                "SoundNeedYouTube",
                "El stream seleccionado tiene URL vacía"
            )

            return null
        }

        if (
            !selectedUrl.startsWith("https://") &&
            !selectedUrl.startsWith("http://")
        ) {

            Log.e(
                "SoundNeedYouTube",
                "URL de stream inválida"
            )

            return null
        }

        return selectedUrl
    }

    // ============================================================
    // OBTENER URL DIRECTA DE VIDEO DE YOUTUBE (NEWPIPE)
    // ============================================================

    private fun getYouTubeVideoUrl(videoId: String): String? {
        initializeNewPipe()

        val extractor = NewPipe.getService("YouTube")
            .getStreamExtractor("https://www.youtube.com/watch?v=$videoId")
        extractor.fetchPage()

        // Usar un stream combinado de video y audio: en modo video el
        // video_player será la única fuente de reproducción.
        val streams = extractor.videoStreams
            .filter { it.isUrl && !it.isVideoOnly && it.content.isNotBlank() }

        if (streams.isEmpty()) {
            Log.w("SoundNeedYouTube", "YouTube no devolvió streams directos de video con audio")
            return null
        }

        // Preferir una calidad moderada para acelerar la carga en móviles.
        val sortedByQuality = streams.sortedByDescending { stream ->
            stream.getResolution()
                .filter { it.isDigit() }
                .toIntOrNull()
                ?: 0
        }
        val selected = sortedByQuality
            .firstOrNull { stream ->
                stream.getResolution()
                    .filter { it.isDigit() }
                    .toIntOrNull()
                    ?.let { it <= 720 }
                    ?: true
            }
            ?: sortedByQuality.firstOrNull()

        val url = selected?.content?.trim().orEmpty()
        if (!url.startsWith("https://") && !url.startsWith("http://")) {
            Log.w("SoundNeedYouTube", "El stream de video seleccionado tiene URL inválida")
            return null
        }

        return url
    }
}
