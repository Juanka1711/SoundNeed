package com.example.music_player

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RadialGradient
import android.graphics.RectF
import android.graphics.Shader
import android.net.Uri
import android.view.KeyEvent
import android.view.View
import android.widget.RemoteViews
import com.ryanheise.audioservice.MediaButtonReceiver
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

class SoundNeedWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        appWidgetIds.forEach {
            render(
                context,
                appWidgetManager,
                it,
                refreshArtwork = true
            )
        }
    }

    companion object {

        private const val PREFS = "soundneed_home_widget"

        private const val KEY_TITLE = "title"
        private const val KEY_ARTIST = "artist"
        private const val KEY_ART_URI = "art_uri"
        private const val KEY_PLAYING = "playing"
        private const val KEY_POSITION = "position"
        private const val KEY_DURATION = "duration"

        private val artworkExecutor = Executors.newSingleThreadExecutor()

        // ============================================================
        // ACTUALIZAR CANCIÓN
        // ============================================================

        fun updatePlayback(
            context: Context,
            title: String,
            artist: String,
            artUri: String,
            playing: Boolean
        ) {

            val preferences =
                context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

            val previousArtUri =
                preferences.getString(KEY_ART_URI, "")

            val artworkCacheMissing =
                cachedArtworkFile(context, artUri)?.exists() != true

            preferences.edit()
                .putString(KEY_TITLE, title)
                .putString(KEY_ARTIST, artist)
                .putString(KEY_ART_URI, artUri)
                .putBoolean(KEY_PLAYING, playing)
                .apply()

            val manager =
                AppWidgetManager.getInstance(context)

            val ids = manager.getAppWidgetIds(
                ComponentName(
                    context,
                    SoundNeedWidgetProvider::class.java
                )
            )

            ids.forEach { widgetId ->

                render(
                    context,
                    manager,
                    widgetId,
                    refreshArtwork = previousArtUri != artUri || artworkCacheMissing
                )
            }
        }

        // ============================================================
        // ACTUALIZAR PROGRESO
        // ============================================================

        fun updateProgress(
            context: Context,
            position: Long,
            duration: Long
        ) {

            val preferences =
                context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

            preferences.edit()
                .putLong(KEY_POSITION, position)
                .putLong(KEY_DURATION, duration)
                .apply()

            val manager =
                AppWidgetManager.getInstance(context)

            val ids = manager.getAppWidgetIds(
                ComponentName(
                    context,
                    SoundNeedWidgetProvider::class.java
                )
            )

            ids.forEach { widgetId ->

                val views =
                    RemoteViews(
                        context.packageName,
                        R.layout.soundneed_widget
                    )

                val progress =
                    if (duration > 0) {
                        (position.toFloat() / duration.toFloat())
                            .coerceIn(0f, 1f)
                    } else {
                        0f
                    }

                val artUri =
                    preferences.getString(KEY_ART_URI, "") ?: ""

                val cached =
                    cachedArtworkFile(context, artUri)

                if (cached?.exists() == true) {

                    BitmapFactory.decodeFile(
                        cached.absolutePath
                    )?.let {

                        applyArtwork(
                            views,
                            it,
                            progress
                        )
                    }
                } else {

                    views.setImageViewBitmap(
                        R.id.widget_progress_ring,
                        createProgressRing(
                            Color.WHITE,
                            Color.WHITE,
                            progress
                        )
                    )
                }

                configureControls(
                    context,
                    views,
                    preferences
                )

                manager.updateAppWidget(
                    widgetId,
                    views
                )
            }
        }

        // ============================================================
        // RENDER
        // ============================================================

        private fun render(
            context: Context,
            manager: AppWidgetManager,
            widgetId: Int,
            refreshArtwork: Boolean
        ) {

            val preferences =
                context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

            val title =
                preferences.getString(KEY_TITLE, "") ?: ""

            val artist =
                preferences.getString(KEY_ARTIST, "") ?: ""

            val artUri =
                preferences.getString(KEY_ART_URI, "") ?: ""

            val isPlaying =
                preferences.getBoolean(KEY_PLAYING, false)

            val position =
                preferences.getLong(KEY_POSITION, 0L)

            val duration =
                preferences.getLong(KEY_DURATION, 0L)

            val hasSong =
                title.isNotBlank() || artUri.isNotBlank()

            val views =
                RemoteViews(
                    context.packageName,
                    R.layout.soundneed_widget
                )

            // ========================================================
            // SIN CANCIÓN
            // ========================================================

            if (!hasSong) {

                // Mantener el widget como mini player aunque todavía no haya
                // una canción activa: así conserva su tamaño y ofrece una
                // entrada clara para abrir SoundNeed.
                views.setViewVisibility(R.id.widget_root, View.VISIBLE)

                views.setTextViewText(
                    R.id.widget_title,
                    "SoundNeed"
                )

                views.setTextViewText(
                    R.id.widget_artist,
                    "Toca para reproducir música"
                )

                views.setImageViewResource(
                    R.id.widget_artwork,
                    R.drawable.soundneed_widget_placeholder
                )

                views.setImageViewResource(
                    R.id.widget_play_pause,
                    R.drawable.soundneed_widget_play
                )

                views.setImageViewBitmap(
                    R.id.widget_background_image,
                    createDefaultBackground()
                )

                views.setImageViewBitmap(
                    R.id.widget_progress_ring,
                    createProgressRing(
                        Color.WHITE,
                        Color.WHITE,
                        0f
                    )
                )

                configureControls(
                    context,
                    views,
                    preferences
                )

                // Abrir la app al tocar el widget
                views.setOnClickPendingIntent(
                    R.id.widget_content,
                    launchAppPendingIntent(context)
                )
                views.setOnClickPendingIntent(
                    R.id.widget_play_pause,
                    launchAppPendingIntent(context)
                )

                manager.updateAppWidget(
                    widgetId,
                    views
                )

                return
            }

            // ========================================================
            // CON CANCIÓN
            // ========================================================

            views.setViewVisibility(R.id.widget_root, View.VISIBLE)

            views.setTextViewText(
                R.id.widget_title,
                title
            )

            views.setTextViewText(
                R.id.widget_artist,
                artist
            )

            val progress =
                if (duration > 0) {
                    (position.toFloat() / duration.toFloat())
                        .coerceIn(0f, 1f)
                } else {
                    0f
                }

            val cachedArtwork =
                cachedArtworkFile(
                    context,
                    artUri
                )

            if (cachedArtwork?.exists() == true) {

                BitmapFactory.decodeFile(
                    cachedArtwork.absolutePath
                )?.let {

                    applyArtwork(
                        views,
                        it,
                        progress
                    )
                }

            } else {

                views.setImageViewResource(
                    R.id.widget_artwork,
                    R.drawable.soundneed_widget_placeholder
                )

                views.setImageViewBitmap(
                    R.id.widget_background_image,
                    createDefaultBackground()
                )

                views.setImageViewBitmap(
                    R.id.widget_progress_ring,
                    createProgressRing(
                        Color.WHITE,
                        Color.WHITE,
                        progress
                    )
                )
            }

            configureControls(
                context,
                views,
                preferences
            )

            // Abrir la app al tocar el widget
            views.setOnClickPendingIntent(
                R.id.widget_content,
                launchAppPendingIntent(context)
            )

            manager.updateAppWidget(
                widgetId,
                views
            )

            // ========================================================
            // CARGAR PORTADA
            // ========================================================

            if (
                refreshArtwork &&
                artUri.isNotBlank()
            ) {

                loadArtwork(
                    context.applicationContext,
                    manager,
                    widgetId,
                    artUri
                )
            }
        }

        // ============================================================
        // CONTROLES
        // ============================================================

        private fun configureControls(
            context: Context,
            views: RemoteViews,
            preferences: android.content.SharedPreferences
        ) {

            val playing =
                preferences.getBoolean(
                    KEY_PLAYING,
                    false
                )

            views.setImageViewResource(
                R.id.widget_play_pause,
                if (playing) {
                    R.drawable.soundneed_widget_pause
                } else {
                    R.drawable.soundneed_widget_play
                }
            )

            views.setOnClickPendingIntent(
                R.id.widget_previous,
                mediaButtonPendingIntent(
                    context,
                    KeyEvent.KEYCODE_MEDIA_PREVIOUS,
                    100
                )
            )

            views.setOnClickPendingIntent(
                R.id.widget_play_pause,
                mediaButtonPendingIntent(
                    context,
                    if (playing) KeyEvent.KEYCODE_MEDIA_PAUSE else KeyEvent.KEYCODE_MEDIA_PLAY,
                    101
                )
            )

            views.setOnClickPendingIntent(
                R.id.widget_next,
                mediaButtonPendingIntent(
                    context,
                    KeyEvent.KEYCODE_MEDIA_NEXT,
                    102
                )
            )
        }

        // ============================================================
        // MEDIA BUTTON
        // ============================================================

        private fun mediaButtonPendingIntent(
            context: Context,
            keyCode: Int,
            requestCode: Int
        ): PendingIntent {

            val intent =
                Intent(Intent.ACTION_MEDIA_BUTTON)
                    .setClass(
                        context,
                        MediaButtonReceiver::class.java
                    )
                    .putExtra(
                        Intent.EXTRA_KEY_EVENT,
                        KeyEvent(
                            KeyEvent.ACTION_DOWN,
                            keyCode
                        )
                    )

            return PendingIntent.getBroadcast(
                context,
                requestCode,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or
                    PendingIntent.FLAG_IMMUTABLE
            )
        }

        // ============================================================
        // LAUNCH APP
        // ============================================================

        private fun launchAppPendingIntent(
            context: Context
        ): PendingIntent {

            val intent =
                context.packageManager.getLaunchIntentForPackage(
                    context.packageName
                )

            return PendingIntent.getActivity(
                context,
                0,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or
                    PendingIntent.FLAG_IMMUTABLE
            )
        }

        // ============================================================
        // ARTWORK
        // ============================================================

        private fun loadArtwork(
            context: Context,
            manager: AppWidgetManager,
            widgetId: Int,
            artUri: String
        ) {

            artworkExecutor.execute {

                try {

                    val uri =
                        Uri.parse(artUri)

                    val bounds =
                        BitmapFactory.Options().apply {
                            inJustDecodeBounds = true
                        }

                    openArtwork(
                        context,
                        uri
                    )?.use {

                        BitmapFactory.decodeStream(
                            it,
                            null,
                            bounds
                        )
                    }

                    if (
                        bounds.outWidth <= 0 ||
                        bounds.outHeight <= 0
                    ) {
                        return@execute
                    }

                    val sampleSize =
                        max(
                            1,
                            max(
                                bounds.outWidth,
                                bounds.outHeight
                            ) / 256
                        )

                    val options =
                        BitmapFactory.Options().apply {
                            inSampleSize = sampleSize
                        }

                    val bitmap =
                        openArtwork(
                            context,
                            uri
                        )?.use {

                            BitmapFactory.decodeStream(
                                it,
                                null,
                                options
                            )
                        }
                            ?: return@execute

                    val artworkBitmap = if (
                        uri.host?.contains("ytimg.com", ignoreCase = true) == true &&
                        bitmap.height > bitmap.width / 2
                    ) {
                        cropLetterbox(bitmap)
                    } else {
                        bitmap
                    }

                    val file =
                        cachedArtworkFile(
                            context,
                            artUri
                        )
                            ?: return@execute

                    file.outputStream().use {

                        artworkBitmap.compress(
                            Bitmap.CompressFormat.PNG,
                            100,
                            it
                        )
                    }

                    val preferences =
                        context.getSharedPreferences(
                            PREFS,
                            Context.MODE_PRIVATE
                        )

                    if (
                        preferences.getString(
                            KEY_ART_URI,
                            ""
                        ) != artUri
                    ) {
                        return@execute
                    }

                    val position =
                        preferences.getLong(
                            KEY_POSITION,
                            0L
                        )

                    val duration =
                        preferences.getLong(
                            KEY_DURATION,
                            0L
                        )

                    val progress =
                        if (duration > 0) {
                            (
                                position.toFloat() /
                                    duration.toFloat()
                                ).coerceIn(0f, 1f)
                        } else {
                            0f
                        }

                    val views =
                        RemoteViews(
                            context.packageName,
                            R.layout.soundneed_widget
                        )

                    views.setTextViewText(
                        R.id.widget_title,
                        preferences.getString(
                            KEY_TITLE,
                            ""
                        )
                    )

                    views.setTextViewText(
                        R.id.widget_artist,
                        preferences.getString(
                            KEY_ARTIST,
                            ""
                        )
                    )

                    applyArtwork(
                        views,
                        bitmap,
                        progress
                    )

                    configureControls(
                        context,
                        views,
                        preferences
                    )

                    manager.updateAppWidget(
                        widgetId,
                        views
                    )

                    bitmap.recycle()

                } catch (_: Exception) {
                    // La portada no debe romper el widget.
                }
            }
        }

        // ============================================================
        // ABRIR ARTWORK
        // ============================================================

        private fun openArtwork(
            context: Context,
            uri: Uri
        ) =
            when (uri.scheme) {

                "content",
                "file",
                "android.resource" ->

                    context.contentResolver
                        .openInputStream(uri)

                "http",
                "https" ->

                    (
                        URL(uri.toString())
                            .openConnection()
                            as HttpURLConnection
                    ).run {

                        connectTimeout = 8_000
                        readTimeout = 8_000
                        inputStream
                    }

                else -> null
            }

        // ============================================================
        // CACHE
        // ============================================================

        private fun cachedArtworkFile(
            context: Context,
            artUri: String
        ): File? {

            if (artUri.isBlank()) {
                return null
            }

            return File(
                context.cacheDir,
                "soundneed_widget_v2_${artUri.hashCode()}.png"
            )
        }

        private fun cropLetterbox(bitmap: Bitmap): Bitmap {
            val maxCrop = (bitmap.height * 0.30f).toInt()
            val sampleCount = 32

            fun isDarkRow(y: Int): Boolean {
                var darkPixels = 0
                for (sample in 0 until sampleCount) {
                    val x = sample * (bitmap.width - 1) / (sampleCount - 1)
                    val color = bitmap.getPixel(x, y)
                    if (
                        Color.red(color) <= 20 &&
                        Color.green(color) <= 20 &&
                        Color.blue(color) <= 20
                    ) {
                        darkPixels++
                    }
                }
                return darkPixels >= sampleCount * 0.94f
            }

            var top = 0
            while (top < maxCrop && isDarkRow(top)) top++

            var bottom = 0
            while (bottom < maxCrop && isDarkRow(bitmap.height - bottom - 1)) bottom++

            if (top + bottom < bitmap.height * 0.04f) return bitmap
            return Bitmap.createBitmap(
                bitmap,
                0,
                top,
                bitmap.width,
                bitmap.height - top - bottom
            )
        }

        // ============================================================
        // APLICAR PORTADA
        // ============================================================

        private fun applyArtwork(
            views: RemoteViews,
            artwork: Bitmap,
            progress: Float
        ) {

            views.setImageViewBitmap(
                R.id.widget_artwork,
                artwork
            )

            val theme =
                extractArtworkTheme(artwork)

            views.setImageViewBitmap(
                R.id.widget_background_image,
                createArtworkBackground(
                    theme.primary,
                    theme.secondary,
                    theme.dark
                )
            )

            views.setImageViewBitmap(
                R.id.widget_progress_ring,
                createProgressRing(
                    theme.primary,
                    Color.argb(
                        35,
                        255,
                        255,
                        255
                    ),
                    progress
                )
            )
        }

        // ============================================================
        // TEMA DE LA PORTADA
        // ============================================================

        private fun extractArtworkTheme(
            artwork: Bitmap
        ): ArtworkTheme {

            val sample =
                Bitmap.createScaledBitmap(
                    artwork,
                    24,
                    24,
                    true
                )

            val pixels =
                IntArray(24 * 24)

            sample.getPixels(
                pixels,
                0,
                24,
                0,
                0,
                24,
                24
            )

            if (sample !== artwork) {
                sample.recycle()
            }

            var bestColor =
                Color.WHITE

            var bestScore =
                -Float.MAX_VALUE

            pixels.forEach { color ->

                val hsv =
                    FloatArray(3)

                Color.colorToHSV(
                    color,
                    hsv
                )

                val alpha =
                    Color.alpha(color)

                if (alpha < 180) {
                    return@forEach
                }

                val saturation =
                    hsv[1]

                val value =
                    hsv[2]

                if (value < 0.08f) {
                    return@forEach
                }

                // Evita grises/blancos.
                if (
                    saturation < 0.10f &&
                    value > 0.20f &&
                    value < 0.85f
                ) {
                    return@forEach
                }

                val lightnessScore =
                    1f -
                        abs(
                            value - 0.52f
                        )

                val score =
                    saturation * 0.65f +
                        lightnessScore * 0.35f

                if (score > bestScore) {

                    bestScore = score
                    bestColor = color
                }
            }

            val primary =
                prepareThemeColor(
                    bestColor
                )

            val secondary =
                createSecondaryColor(
                    primary
                )

            val dark =
                darken(
                    primary
                )

            return ArtworkTheme(
                primary,
                secondary,
                dark
            )
        }

        // ============================================================
        // COLOR PRINCIPAL
        // ============================================================

        private fun prepareThemeColor(
            color: Int
        ): Int {

            val hsv =
                FloatArray(3)

            Color.colorToHSV(
                color,
                hsv
            )

            hsv[1] =
                hsv[1].coerceIn(
                    0.35f,
                    0.90f
                )

            hsv[2] =
                hsv[2].coerceIn(
                    0.30f,
                    0.78f
                )

            if (hsv[2] < 0.30f) {
                hsv[2] = 0.48f
            }

            if (hsv[2] > 0.78f) {
                hsv[2] = 0.62f
            }

            return Color.HSVToColor(
                hsv
            )
        }

        // ============================================================
        // COLOR SECUNDARIO
        // ============================================================

        private fun createSecondaryColor(
            primary: Int
        ): Int {

            val hsv =
                FloatArray(3)

            Color.colorToHSV(
                primary,
                hsv
            )

            hsv[0] =
                (hsv[0] + 35f) % 360f

            hsv[1] =
                (hsv[1] * 0.85f)
                    .coerceIn(
                        0.30f,
                        0.90f
                    )

            hsv[2] =
                (hsv[2] * 0.90f)
                    .coerceIn(
                        0.25f,
                        0.72f
                    )

            return Color.HSVToColor(
                hsv
            )
        }

        // ============================================================
        // COLOR OSCURO
        // ============================================================

        private fun darken(
            color: Int
        ): Int {

            val hsv =
                FloatArray(3)

            Color.colorToHSV(
                color,
                hsv
            )

            hsv[1] =
                (hsv[1] * 0.75f)
                    .coerceIn(
                        0.25f,
                        0.90f
                    )

            hsv[2] = 0.07f

            return Color.HSVToColor(
                hsv
            )
        }

        // ============================================================
        // FONDO DINÁMICO
        // ============================================================

        private fun createArtworkBackground(
            primary: Int,
            secondary: Int,
            dark: Int
        ): Bitmap {

            val width = 640
            val height = 160

            val background =
                Bitmap.createBitmap(
                    width,
                    height,
                    Bitmap.Config.ARGB_8888
                )

            val canvas =
                Canvas(background)

            val bounds =
                RectF(
                    0f,
                    0f,
                    width.toFloat(),
                    height.toFloat()
                )

            val clip =
                Path().apply {

                    addRoundRect(
                        bounds,
                        48f,
                        48f,
                        Path.Direction.CW
                    )
                }

            canvas.save()

            canvas.clipPath(
                clip
            )

            // Gradiente equivalente al MiniPlayer.
            val gradient =
                LinearGradient(
                    0f,
                    0f,
                    width.toFloat(),
                    0f,
                    intArrayOf(
                        dark,
                        blend(
                            dark,
                            primary,
                            0.20f
                        ),
                        blend(
                            dark,
                            secondary,
                            0.12f
                        )
                    ),
                    floatArrayOf(
                        0f,
                        0.55f,
                        1f
                    ),
                    Shader.TileMode.CLAMP
                )

            val paint =
                Paint(
                    Paint.ANTI_ALIAS_FLAG
                ).apply {
                    shader = gradient
                }

            canvas.drawRect(
                bounds,
                paint
            )

            // Glow ambiental.
            val glow =
                RadialGradient(
                    width * 0.10f,
                    height * 0.50f,
                    height * 1.20f,
                    intArrayOf(
                        Color.argb(
                            20,
                            Color.red(primary),
                            Color.green(primary),
                            Color.blue(primary)
                        ),
                        Color.TRANSPARENT
                    ),
                    null,
                    Shader.TileMode.CLAMP
                )

            val glowPaint =
                Paint(
                    Paint.ANTI_ALIAS_FLAG
                ).apply {
                    shader = glow
                }

            canvas.drawRect(
                bounds,
                glowPaint
            )

            canvas.restore()

            return background
        }

        // ============================================================
        // ANILLO CIRCULAR
        // ============================================================

        private fun createProgressRing(
            progressColor: Int,
            backgroundColor: Int,
            progress: Float
        ): Bitmap {

            val size = 92

            val bitmap =
                Bitmap.createBitmap(
                    size,
                    size,
                    Bitmap.Config.ARGB_8888
                )

            val canvas =
                Canvas(bitmap)

            val center =
                size / 2f

            val radius =
                39f

            // Base.
            val backgroundPaint =
                Paint(
                    Paint.ANTI_ALIAS_FLAG
                ).apply {

                    style =
                        Paint.Style.STROKE

                    strokeWidth =
                        5f

                    strokeCap =
                        Paint.Cap.ROUND

                    color =
                        backgroundColor
                }

            canvas.drawCircle(
                center,
                center,
                radius,
                backgroundPaint
            )

            // Progreso.
            if (progress > 0f) {

                val progressPaint =
                    Paint(
                        Paint.ANTI_ALIAS_FLAG
                    ).apply {

                        style =
                            Paint.Style.STROKE

                        strokeWidth =
                            5f

                        strokeCap =
                            Paint.Cap.ROUND

                        color =
                            progressColor
                    }

                val rect =
                    RectF(
                        center - radius,
                        center - radius,
                        center + radius,
                        center + radius
                    )

                canvas.drawArc(
                    rect,
                    -90f,
                    360f * progress,
                    false,
                    progressPaint
                )
            }

            return bitmap
        }

        // ============================================================
        // FONDO SIN CANCIÓN
        // ============================================================

        private fun createDefaultBackground(): Bitmap {

            val width = 640
            val height = 160

            val bitmap =
                Bitmap.createBitmap(
                    width,
                    height,
                    Bitmap.Config.ARGB_8888
                )

            val canvas =
                Canvas(bitmap)

            val paint =
                Paint(
                    Paint.ANTI_ALIAS_FLAG
                ).apply {

                    shader =
                        LinearGradient(
                            0f,
                            0f,
                            width.toFloat(),
                            0f,
                            Color.rgb(
                                10,
                                10,
                                18
                            ),
                            Color.rgb(
                                21,
                                21,
                                34
                            ),
                            Shader.TileMode.CLAMP
                        )
                }

            canvas.drawRect(
                0f,
                0f,
                width.toFloat(),
                height.toFloat(),
                paint
            )

            return bitmap
        }

        // ============================================================
        // BLEND
        // ============================================================

        private fun blend(
            from: Int,
            to: Int,
            amount: Float
        ): Int {

            return Color.rgb(

                (
                    Color.red(from) +
                        (
                            Color.red(to) -
                                Color.red(from)
                            ) * amount
                    ).toInt(),

                (
                    Color.green(from) +
                        (
                            Color.green(to) -
                                Color.green(from)
                            ) * amount
                    ).toInt(),

                (
                    Color.blue(from) +
                        (
                            Color.blue(to) -
                                Color.blue(from)
                            ) * amount
                    ).toInt()
            )
        }

        private data class ArtworkTheme(
            val primary: Int,
            val secondary: Int,
            val dark: Int
        )
    }
}
