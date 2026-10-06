package com.example.music_player

import android.Manifest
import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.app.RecoverableSecurityException
import android.graphics.BitmapFactory
import android.media.MediaScannerConnection
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.Uri
import android.net.NetworkRequest
import android.os.Build
import android.os.Environment
import android.provider.DocumentsContract
import android.provider.MediaStore
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
import androidx.core.content.ContextCompat

import com.ryanheise.audioservice.AudioServiceActivity

import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel

import org.schabi.newpipe.extractor.NewPipe
import org.schabi.newpipe.extractor.stream.AudioStream

class MainActivity : AudioServiceActivity() {

    private var newPipeInitialized = false
    private var networkEventSink: EventChannel.EventSink? = null
    private var downloadProgressSink: EventChannel.EventSink? = null
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

    companion object {
        private const val CHANNEL = "music_player/media"
        private const val YOUTUBE_CHANNEL = "youtube/extractor"
        private const val WIDGET_CHANNEL = "soundneed/widget"
        private const val NOTIFICATION_PERMISSION_REQUEST_CODE = 200
        private const val PICK_MUSIC_FOLDER_REQUEST_CODE = 201
        private const val DELETE_MUSIC_REQUEST_CODE = 202
        private const val MUSIC_FOLDERS_PREFS = "soundneed_music_folders"
        private const val MUSIC_FOLDERS_KEY = "paths"
        private const val DOWNLOAD_ARTWORKS_KEY = "artwork_files"
        private val extractorExecutor =
            Executors.newSingleThreadExecutor()
        private val downloadExecutor =
            Executors.newSingleThreadExecutor()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

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
                    val duration = call.argument<Number>("duration")?.toLong() ?: 0L
                    val artwork = call.argument<ByteArray>("artwork")
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
                                duration,
                                artwork = artwork,
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

                    if (albumId == null) {
                        result.success(null)
                    } else {
                        result.success(getArtwork(albumId))
                    }
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

                else -> {
                    result.notImplemented()
                }
            }
        }
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
        duration: Long,
        artwork: ByteArray?,
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
                val values = ContentValues().apply {
                    put(MediaStore.Audio.Media.DISPLAY_NAME, displayName)
                    put(MediaStore.Audio.Media.TITLE, title)
                    put(MediaStore.Audio.Media.ARTIST, artist.ifBlank { "Artista desconocido" })
                    put(MediaStore.Audio.Media.MIME_TYPE, mimeType)
                    put(MediaStore.Audio.Media.RELATIVE_PATH, "Music/SoundNeed")
                    put(MediaStore.Audio.Media.IS_MUSIC, 1)
                    if (duration > 0) put(MediaStore.Audio.Media.DURATION, duration)
                    put(MediaStore.Audio.Media.IS_PENDING, 1)
                }
                val collection = MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
                val savedUri = contentResolver.insert(collection, values)
                    ?: throw IllegalStateException("No se pudo crear el archivo de audio.")
                try {
                    val output = contentResolver.openOutputStream(savedUri, "w")
                        ?: throw IllegalStateException("No se pudo escribir el archivo.")

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

                    contentResolver.update(
                        savedUri,
                        ContentValues().apply {
                            put(MediaStore.Audio.Media.IS_PENDING, 0)
                        },
                        null,
                        null
                    )
                } catch (error: Exception) {
                    contentResolver.delete(savedUri, null, null)
                    throw error
                }
                registerSoundNeedFolder()
                val artworkUri = saveDownloadedArtwork(savedUri.toString(), artwork)
                return mapOf(
                    "uri" to savedUri.toString(),
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
}
