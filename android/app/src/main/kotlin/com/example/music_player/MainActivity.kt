package com.example.music_player

import android.Manifest
import android.content.ContentUris
import android.content.pm.PackageManager
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import java.io.ByteArrayOutputStream

import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat

import com.ryanheise.audioservice.AudioServiceActivity

import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {

    companion object {
        private const val CHANNEL = "music_player/media"
        private const val NOTIFICATION_PERMISSION_REQUEST_CODE = 200
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
            MediaStore.Audio.Media.SIZE
        )

        val selection =
            "${MediaStore.Audio.Media.IS_MUSIC} != 0"

        val sortOrder =
            "${MediaStore.Audio.Media.TITLE} COLLATE NOCASE ASC"

        contentResolver.query(
            collection,
            projection,
            selection,
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
                        "artworkUri" to artworkUri
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
}