package sound_need.music_player

import android.app.Activity
import android.content.Intent
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.view.Gravity
import android.widget.Button
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import java.io.File

/** Small theme picker opened from Android's native Sharesheet modify action. */
class SongShareThemeActivity : Activity() {
    private val themes = listOf(
        Theme("ocean", "Océano", 0xFF83E8FF.toInt()),
        Theme("sunset", "Atardecer", 0xFFFF6B7D.toInt()),
        Theme("violet", "Violeta", 0xFFB69CFF.toInt()),
    )

    private lateinit var image: ImageView
    private lateinit var chooseButton: Button
    private var selectedTheme = "ocean"
    private var artwork: ByteArray = byteArrayOf()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.statusBarColor = Color.rgb(8, 9, 16)
        window.navigationBarColor = Color.rgb(8, 9, 16)

        val extras = intent.extras
        val artworkPath = extras?.getString(MainActivity.EXTRA_ARTWORK_PATH)
        val artworkFile = artworkPath?.let(::File)
        if (artworkFile == null || !artworkFile.isFile) {
            Toast.makeText(this, "No se encontró la portada.", Toast.LENGTH_SHORT).show()
            finish()
            return
        }
        artwork = artworkFile.readBytes()
        selectedTheme = extras.getString(MainActivity.EXTRA_THEME, "ocean") ?: "ocean"

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(dp(18), dp(14), dp(18), dp(18))
            setBackgroundColor(Color.rgb(8, 9, 16))
        }
        root.addView(TextView(this).apply {
            text = "Cambiar tema"
            setTextColor(Color.WHITE)
            textSize = 22f
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
        }, LinearLayout.LayoutParams(-1, dp(46)))
        root.addView(TextView(this).apply {
            text = "Previsualiza la tarjeta antes de compartirla"
            setTextColor(0xFFB7BBC8.toInt())
            textSize = 14f
            gravity = Gravity.CENTER
        }, LinearLayout.LayoutParams(-1, dp(32)))

        image = ImageView(this).apply {
            scaleType = ImageView.ScaleType.FIT_CENTER
            contentDescription = "Vista previa de la tarjeta"
        }
        root.addView(image, LinearLayout.LayoutParams(-1, 0, 1f).apply {
            setMargins(0, dp(8), 0, dp(8))
        })

        val themeRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
        }
        themes.forEach { theme ->
            val option = TextView(this).apply {
                text = "●  ${theme.label}"
                textSize = 14f
                gravity = Gravity.CENTER
                setTextColor(theme.color)
                setPadding(dp(10), dp(12), dp(10), dp(12))
                background = roundedBackground(
                    if (theme.id == selectedTheme) 0x263A3E4A else 0x14FFFFFF,
                    if (theme.id == selectedTheme) theme.color else 0x33FFFFFF,
                )
                setOnClickListener {
                    selectedTheme = theme.id
                    refreshPreview()
                    refreshThemeOptions(themeRow)
                }
            }
            themeRow.addView(option, LinearLayout.LayoutParams(0, dp(48), 1f).apply {
                setMargins(dp(3), 0, dp(3), 0)
            })
        }
        root.addView(themeRow, LinearLayout.LayoutParams(-1, dp(52)))

        chooseButton = Button(this).apply {
            text = "Usar este tema"
            isAllCaps = false
            textSize = 16f
            setTextColor(Color.WHITE)
            setOnClickListener { applyTheme() }
        }
        root.addView(chooseButton, LinearLayout.LayoutParams(-1, dp(54)).apply {
            setMargins(0, dp(10), 0, 0)
        })

        setContentView(root)
        refreshThemeOptions(themeRow)
        refreshPreview()
    }

    private fun refreshThemeOptions(row: LinearLayout) {
        themes.forEachIndexed { index, theme ->
            (row.getChildAt(index) as? TextView)?.background = roundedBackground(
                if (theme.id == selectedTheme) 0x263A3E4A else 0x14FFFFFF,
                if (theme.id == selectedTheme) theme.color else 0x33FFFFFF,
            )
        }
        chooseButton.background = roundedBackground(
            SongStoryCardRenderer.accentForTheme(selectedTheme),
            SongStoryCardRenderer.accentForTheme(selectedTheme),
        )
    }

    private fun refreshPreview() {
        try {
            val title = intent.getStringExtra("title") ?: "Canción"
            val artist = intent.getStringExtra("artist").orEmpty()
            val uri = SongStoryCardRenderer.create(this, title, artist, artwork, selectedTheme)
            val bitmap = contentResolver.openInputStream(uri)?.use { stream ->
                BitmapFactory.decodeStream(stream)
            }
            if (bitmap != null) image.setImageBitmap(bitmap)
        } catch (_: Exception) {
            Toast.makeText(this, "No se pudo generar la vista previa.", Toast.LENGTH_SHORT).show()
        }
    }

    private fun applyTheme() {
        val shareIntent = Intent(this, MainActivity::class.java).apply {
            action = MainActivity.ACTION_SHARE_WITH_THEME
            flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            intent.extras?.let { putExtras(it) }
            putExtra(MainActivity.EXTRA_THEME, selectedTheme)
        }
        startActivity(shareIntent)
        finish()
    }

    private fun roundedBackground(color: Int, stroke: Int): GradientDrawable =
        GradientDrawable().apply {
            setColor(color)
            cornerRadius = dp(14).toFloat()
            setStroke(dp(1), stroke)
        }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

    private data class Theme(val id: String, val label: String, val color: Int)
}
