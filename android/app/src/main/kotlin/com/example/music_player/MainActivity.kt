package com.example.music_player

import android.Manifest
import android.content.ContentUris
import android.content.pm.PackageManager
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.util.Log
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat

import com.ryanheise.audioservice.AudioServiceActivity

import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

import org.schabi.newpipe.extractor.NewPipe
import org.schabi.newpipe.extractor.stream.AudioStream

class MainActivity : AudioServiceActivity() {

    private var newPipeInitialized = false

    companion object {
        private const val CHANNEL = "music_player/media"
        private const val YOUTUBE_CHANNEL = "youtube/extractor"
        private const val WIDGET_CHANNEL = "soundneed/widget"
        private const val NOTIFICATION_PERMISSION_REQUEST_CODE = 200
        private val extractorExecutor =
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

        // ============================================================
        // CANAL YOUTUBE EXTRACTOR
        // ============================================================

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            YOUTUBE_CHANNEL
        ).setMethodCallHandler { call, result ->

            when (call.method) {

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

            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.READ_EXTERNAL_STORAGE
            ) == PackageManager.PERMISSION_GRANTED
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

            if (
                ContextCompat.checkSelfPermission(
                    this,
                    Manifest.permission.READ_EXTERNAL_STORAGE
                ) != PackageManager.PERMISSION_GRANTED
            ) {

                ActivityCompat.requestPermissions(
                    this,
                    arrayOf(
                        Manifest.permission.READ_EXTERNAL_STORAGE
                    ),
                    100
                )
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

                if (isInExcludedFolder) {
                    continue
                }

                val contentUri =
                    ContentUris.withAppendedId(
                        collection,
                        id
                    )

                val artworkUri =
                    if (albumId != null && albumId > 0) {
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
                        "artworkUri" to artworkUri,
                        "isMusic" to isMusic
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
