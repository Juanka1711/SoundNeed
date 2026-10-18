<<<<<<< HEAD
package sound_need.music_player
=======
package com.example.music_player
>>>>>>> 1f6e8dce69bd1be9392142d64d1fcaf6d7107d52

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.Rect
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.Typeface
import android.net.Uri
import androidx.core.content.FileProvider
import java.io.File
import java.io.FileOutputStream
import kotlin.math.max
import kotlin.math.min

internal object SongStoryCardRenderer {

    private const val WIDTH = 1080
    private const val HEIGHT = 1920

    private const val BG = 0xFF080910.toInt()
    private const val WHITE = 0xFFF8F9FC.toInt()
    private const val MUTED = 0xFFB7BBC8.toInt()
    private const val ACCENT = 0xFF83E8FF.toInt()

    // Imagen pequeña: mejora el rendimiento del desenfoque.
    private const val BLUR_WIDTH = 120
    private const val BLUR_HEIGHT = 213
    private const val BLUR_RADIUS = 8

    private val paint = Paint(
        Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG
    )

    fun create(
        context: Context,
        title: String,
        artist: String,
        artworkBytes: ByteArray?
    ): Uri {
        val output = Bitmap.createBitmap(
            WIDTH,
            HEIGHT,
            Bitmap.Config.ARGB_8888
        )

        var artwork: Bitmap? = null

        try {
            val canvas = Canvas(output)
            canvas.drawColor(BG)

            artwork = decodeArtwork(artworkBytes)

            // 1. Fondo inmersivo basado en la portada.
            if (artwork != null) {
                drawImmersiveBackground(canvas, artwork)
            } else {
                drawFallbackBackground(canvas)
            }

            // 2. Contraste cinematográfico.
            drawCinematicOverlay(canvas)

            // 3. Identidad visual.
            drawBrand(canvas)

            // 4. Portada central nítida.
            val cover = RectF(
                100f,
                300f,
                980f,
                1180f
            )

            if (artwork != null) {
                drawHeroArtwork(canvas, artwork, cover)
            } else {
                drawPlaceholder(canvas, cover)
            }

            // 5. Información musical.
            drawText(
                canvas = canvas,
                text = "AHORA EN SOUNDNEED",
                x = 104f,
                y = 1280f,
                size = 23f,
                color = ACCENT,
                typeface = Typeface.create(
                    "sans-serif-medium",
                    Typeface.NORMAL
                )
            )

            drawWrappedText(
                canvas = canvas,
                text = title.ifBlank { "Canción desconocida" },
                x = 100f,
                y = 1360f,
                maxWidth = 880f,
                size = 66f,
                color = WHITE,
                typeface = Typeface.create(
                    "sans-serif",
                    Typeface.BOLD
                ),
                maxLines = 2,
                lineHeight = 80f
            )

            drawWrappedText(
                canvas = canvas,
                text = artist.ifBlank { "Artista desconocido" },
                x = 104f,
                y = 1535f,
                maxWidth = 870f,
                size = 35f,
                color = MUTED,
                typeface = Typeface.create(
                    "sans-serif",
                    Typeface.NORMAL
                ),
                maxLines = 1,
                lineHeight = 44f
            )

            // 6. Firma minimalista, sin ecualizadores ni líneas.
            drawFooter(canvas)

            // 7. Exportar la tarjeta.
            val directory = File(context.cacheDir, "shared")

            if (!directory.exists() && !directory.mkdirs()) {
                throw IllegalStateException(
                    "No se pudo crear el directorio de imágenes."
                )
            }

            val file = File(
                directory,
                "soundneed-story-${System.currentTimeMillis()}.jpg"
            )

            FileOutputStream(file).use { stream ->
                val success = output.compress(
                    Bitmap.CompressFormat.JPEG,
                    95,
                    stream
                )

                check(success) {
                    "No se pudo guardar la imagen."
                }

                stream.flush()
            }

            return FileProvider.getUriForFile(
                context,
                "${context.packageName}.fileprovider",
                file
            )
        } finally {
            artwork?.recycle()
            output.recycle()
        }
    }

    private fun decodeArtwork(bytes: ByteArray?): Bitmap? {
        if (bytes == null || bytes.isEmpty()) return null

        return try {
            val bounds = BitmapFactory.Options().apply {
                inJustDecodeBounds = true
            }

            BitmapFactory.decodeByteArray(
                bytes,
                0,
                bytes.size,
                bounds
            )

            if (bounds.outWidth <= 0 || bounds.outHeight <= 0) {
                return null
            }

            // Evita cargar portadas gigantes a resolución completa.
            var sampleSize = 1
            val maxDimension = 1600

            while (
                bounds.outWidth / sampleSize > maxDimension ||
                bounds.outHeight / sampleSize > maxDimension
            ) {
                sampleSize *= 2
            }

            val options = BitmapFactory.Options().apply {
                inSampleSize = sampleSize
                inPreferredConfig = Bitmap.Config.ARGB_8888
            }

            BitmapFactory.decodeByteArray(
                bytes,
                0,
                bytes.size,
                options
            )
        } catch (_: Exception) {
            null
        }
    }

    /**
     * Genera un fondo vertical a partir de la portada.
     * El desenfoque se calcula en una imagen pequeña para
     * reducir el uso de memoria y tiempo de procesamiento.
     */
    private fun drawImmersiveBackground(
        canvas: Canvas,
        artwork: Bitmap
    ) {
        val small = Bitmap.createBitmap(
            BLUR_WIDTH,
            BLUR_HEIGHT,
            Bitmap.Config.ARGB_8888
        )

        var blurred: Bitmap? = null

        try {
            val smallCanvas = Canvas(small)
            smallCanvas.drawColor(BG)

            // Recorte central para conservar la proporción vertical.
            val sourceWidth = artwork.width.toFloat()
            val sourceHeight = artwork.height.toFloat()
            val targetRatio = BLUR_WIDTH.toFloat() / BLUR_HEIGHT
            val sourceRatio = sourceWidth / sourceHeight

            val sourceRect = if (sourceRatio > targetRatio) {
                val cropWidth = sourceHeight * targetRatio
                val left = (sourceWidth - cropWidth) / 2f

                Rect(
                    left.toInt(),
                    0,
                    (left + cropWidth).toInt(),
                    artwork.height
                )
            } else {
                val cropHeight = sourceWidth / targetRatio
                val top = (sourceHeight - cropHeight) / 2f

                Rect(
                    0,
                    top.toInt(),
                    artwork.width,
                    (top + cropHeight).toInt()
                )
            }

            paint.shader = null
            paint.alpha = 255

            smallCanvas.drawBitmap(
                artwork,
                sourceRect,
                Rect(0, 0, BLUR_WIDTH, BLUR_HEIGHT),
                paint
            )

            blurred = boxBlur(small, BLUR_RADIUS)

            // Se amplía el fondo difuminado hasta cubrir el lienzo.
            paint.shader = null
            paint.alpha = 255

            canvas.drawBitmap(
                blurred,
                null,
                RectF(
                    -12f,
                    -12f,
                    WIDTH + 12f,
                    HEIGHT + 12f
                ),
                paint
            )
        } finally {
            blurred?.recycle()
            small.recycle()
        }
    }

    /**
     * Desenfoque de caja separable.
     * No utiliza RenderScript ni dependencias externas.
     */
    private fun boxBlur(
        source: Bitmap,
        radius: Int
    ): Bitmap {
        val width = source.width
        val height = source.height
        val count = width * height

        val input = IntArray(count)
        val horizontal = IntArray(count)
        val resultPixels = IntArray(count)

        source.getPixels(
            input,
            0,
            width,
            0,
            0,
            width,
            height
        )

        // Pasada horizontal.
        for (y in 0 until height) {
            for (x in 0 until width) {
                var alpha = 0
                var red = 0
                var green = 0
                var blue = 0
                var samples = 0

                val start = max(0, x - radius)
                val end = min(width - 1, x + radius)

                for (sampleX in start..end) {
                    val color = input[y * width + sampleX]

                    alpha += Color.alpha(color)
                    red += Color.red(color)
                    green += Color.green(color)
                    blue += Color.blue(color)
                    samples++
                }

                horizontal[y * width + x] = Color.argb(
                    alpha / samples,
                    red / samples,
                    green / samples,
                    blue / samples
                )
            }
        }

        // Pasada vertical.
        for (y in 0 until height) {
            for (x in 0 until width) {
                var alpha = 0
                var red = 0
                var green = 0
                var blue = 0
                var samples = 0

                val start = max(0, y - radius)
                val end = min(height - 1, y + radius)

                for (sampleY in start..end) {
                    val color = horizontal[sampleY * width + x]

                    alpha += Color.alpha(color)
                    red += Color.red(color)
                    green += Color.green(color)
                    blue += Color.blue(color)
                    samples++
                }

                resultPixels[y * width + x] = Color.argb(
                    alpha / samples,
                    red / samples,
                    green / samples,
                    blue / samples
                )
            }
        }

        return Bitmap.createBitmap(
            resultPixels,
            width,
            height,
            Bitmap.Config.ARGB_8888
        )
    }

    private fun drawCinematicOverlay(canvas: Canvas) {
        paint.shader = LinearGradient(
            0f,
            0f,
            0f,
            HEIGHT.toFloat(),
            intArrayOf(
                0xAA070910.toInt(),
                0x66070910,
                0x77070910,
                0xF2070910.toInt()
            ),
            floatArrayOf(0f, 0.30f, 0.62f, 1f),
            Shader.TileMode.CLAMP
        )

        canvas.drawRect(
            0f,
            0f,
            WIDTH.toFloat(),
            HEIGHT.toFloat(),
            paint
        )

        paint.shader = LinearGradient(
            0f,
            0f,
            WIDTH.toFloat(),
            0f,
            intArrayOf(
                0x55000000,
                Color.TRANSPARENT,
                0x55000000
            ),
            null,
            Shader.TileMode.CLAMP
        )

        canvas.drawRect(
            0f,
            0f,
            WIDTH.toFloat(),
            HEIGHT.toFloat(),
            paint
        )

        paint.shader = null
    }

    private fun drawFallbackBackground(canvas: Canvas) {
        paint.shader = LinearGradient(
            0f,
            0f,
            WIDTH.toFloat(),
            HEIGHT.toFloat(),
            intArrayOf(
                0xFF102D43.toInt(),
                0xFF141322.toInt(),
                BG
            ),
            null,
            Shader.TileMode.CLAMP
        )

        canvas.drawRect(
            0f,
            0f,
            WIDTH.toFloat(),
            HEIGHT.toFloat(),
            paint
        )

        paint.shader = null
    }

    private fun drawBrand(canvas: Canvas) {
        drawText(
            canvas = canvas,
            text = "SOUNDNEED",
            x = 100f,
            y = 150f,
            size = 29f,
            color = WHITE,
            typeface = Typeface.create(
                "sans-serif-medium",
                Typeface.NORMAL
            )
        )

        paint.shader = null
        paint.color = ACCENT
        canvas.drawCircle(320f, 140f, 5f, paint)

        drawText(
            canvas = canvas,
            text = "MUSIC, YOUR WAY",
            x = 980f,
            y = 150f,
            size = 19f,
            color = 0xFFDFE4EF.toInt(),
            typeface = Typeface.create(
                "sans-serif",
                Typeface.NORMAL
            ),
            alignRight = true
        )
    }

    private fun drawHeroArtwork(
        canvas: Canvas,
        artwork: Bitmap,
        rect: RectF
    ) {
        // Sombra detrás de la portada.
        paint.shader = null
        paint.color = Color.BLACK
        paint.style = Paint.Style.FILL
        paint.setShadowLayer(
            45f,
            0f,
            24f,
            0xCC000000.toInt()
        )

        canvas.drawRoundRect(
            rect,
            32f,
            32f,
            paint
        )

        paint.clearShadowLayer()

        val save = canvas.save()

        val path = Path().apply {
            addRoundRect(
                rect,
                32f,
                32f,
                Path.Direction.CW
            )
        }

        canvas.clipPath(path)

        val sourceWidth = artwork.width.toFloat()
        val sourceHeight = artwork.height.toFloat()
        val targetRatio = rect.width() / rect.height()
        val sourceRatio = sourceWidth / sourceHeight

        val src = if (sourceRatio > targetRatio) {
            val cropWidth = sourceHeight * targetRatio
            val left = (sourceWidth - cropWidth) / 2f

            Rect(
                left.toInt(),
                0,
                (left + cropWidth).toInt(),
                artwork.height
            )
        } else {
            val cropHeight = sourceWidth / targetRatio
            val top = (sourceHeight - cropHeight) / 2f

            Rect(
                0,
                top.toInt(),
                artwork.width,
                (top + cropHeight).toInt()
            )
        }

        paint.shader = null
        paint.alpha = 255
        paint.color = Color.WHITE
        paint.style = Paint.Style.FILL

        canvas.drawBitmap(
            artwork,
            src,
            rect,
            paint
        )

        canvas.restoreToCount(save)

        // Contorno sutil.
        paint.shader = null
        paint.style = Paint.Style.STROKE
        paint.strokeWidth = 2f
        paint.color = 0x35FFFFFF

        canvas.drawRoundRect(
            rect,
            32f,
            32f,
            paint
        )

        paint.style = Paint.Style.FILL
    }

    private fun drawPlaceholder(
        canvas: Canvas,
        rect: RectF
    ) {
        paint.shader = LinearGradient(
            rect.left,
            rect.top,
            rect.right,
            rect.bottom,
            intArrayOf(
                0xFF123C52.toInt(),
                0xFF22203B.toInt()
            ),
            null,
            Shader.TileMode.CLAMP
        )

        canvas.drawRoundRect(
            rect,
            32f,
            32f,
            paint
        )

        paint.shader = null

        drawText(
            canvas = canvas,
            text = "SN",
            x = rect.centerX(),
            y = rect.centerY() + 35f,
            size = 110f,
            color = WHITE,
            typeface = Typeface.create(
                "sans-serif",
                Typeface.BOLD
            ),
            alignCenter = true
        )
    }

    private fun drawFooter(canvas: Canvas) {
        drawText(
            canvas = canvas,
            text = "DESCÚBRELA. COMPÁRTELA.",
            x = 100f,
            y = 1805f,
            size = 22f,
            color = 0xFFD0D4DF.toInt(),
            typeface = Typeface.create(
                "sans-serif-medium",
                Typeface.NORMAL
            )
        )

        drawText(
            canvas = canvas,
            text = "SOUNDNEED",
            x = 980f,
            y = 1805f,
            size = 24f,
            color = ACCENT,
            typeface = Typeface.create(
                "sans-serif-medium",
                Typeface.NORMAL
            ),
            alignRight = true
        )
    }

    private fun drawWrappedText(
        canvas: Canvas,
        text: String,
        x: Float,
        y: Float,
        maxWidth: Float,
        size: Float,
        color: Int,
        typeface: Typeface,
        maxLines: Int,
        lineHeight: Float
    ) {
        paint.shader = null
        paint.color = color
        paint.textSize = size
        paint.typeface = typeface
        paint.textAlign = Paint.Align.LEFT
        paint.style = Paint.Style.FILL
        paint.alpha = 255
        paint.clearShadowLayer()

        val words = text.trim().split(Regex("\\s+"))
        val lines = mutableListOf<String>()
        var current = ""

        for (word in words) {
            val candidate = if (current.isEmpty()) {
                word
            } else {
                "$current $word"
            }

            if (paint.measureText(candidate) <= maxWidth) {
                current = candidate
            } else {
                if (current.isNotEmpty()) {
                    lines.add(current)
                }

                // Evita perder una palabra muy larga.
                current = word
            }
        }

        if (current.isNotEmpty()) {
            lines.add(current)
        }

        val visible = lines.take(maxLines).toMutableList()

        if (lines.size > maxLines && visible.isNotEmpty()) {
            var last = visible.last()

            while (
                last.isNotEmpty() &&
                paint.measureText("$last…") > maxWidth
            ) {
                last = last.dropLast(1)
            }

            visible[visible.lastIndex] = "$last…"
        }

        visible.forEachIndexed { index, line ->
            canvas.drawText(
                line,
                x,
                y + index * lineHeight,
                paint
            )
        }
    }

    private fun drawText(
        canvas: Canvas,
        text: String,
        x: Float,
        y: Float,
        size: Float,
        color: Int,
        typeface: Typeface,
        alignRight: Boolean = false,
        alignCenter: Boolean = false
    ) {
        paint.shader = null
        paint.clearShadowLayer()
        paint.color = color
        paint.textSize = size
        paint.typeface = typeface
        paint.alpha = 255
        paint.style = Paint.Style.FILL

        paint.textAlign = when {
            alignRight -> Paint.Align.RIGHT
            alignCenter -> Paint.Align.CENTER
            else -> Paint.Align.LEFT
        }

        canvas.drawText(
            text,
            x,
            y,
            paint
        )
    }
}
