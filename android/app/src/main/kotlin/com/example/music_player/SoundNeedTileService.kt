package com.example.music_player

import android.content.Intent
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import androidx.annotation.RequiresApi

/**
 * SoundNeed Tile Service
 * 
 * Proporciona un acceso rápido en el panel de ajustes rápidos de Android 16+
 * para controlar la reproducción de música.
 * 
 * Al tocar el tile:
 * - Si la música está pausada → reanuda
 * - Si la música está reproduciendo → pausa
 * - Si no hay música → abre la app
 */
@RequiresApi(Build.VERSION_CODES.N)
class SoundNeedTileService : TileService() {

    companion object {
        private const val ACTION_PLAY_PAUSE = "com.example.music_player.PLAY_PAUSE"
        private const val ACTION_OPEN_APP = "com.example.music_player.OPEN_APP"
    }

    private var isPlaying = false

    override fun onClick() {
        super.onClick()

        // Enviar un intent a la app para controlar la reproducción
        val intent = Intent(ACTION_PLAY_PAUSE).apply {
            setPackage(packageName)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }

        try {
            startActivity(intent)
        } catch (e: Exception) {
            // Si falla, abrir la app directamente
            val appIntent = packageManager.getLaunchIntentForPackage(packageName)
            appIntent?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(appIntent)
        }
    }

    override fun onStartListening() {
        super.onStartListening()

        // Actualizar el estado del tile cuando Android lo solicita
        updateTileState()
    }

    private fun updateTileState() {
        val tile = qsTile ?: return

        tile.state = Tile.STATE_ACTIVE
        tile.label = "SoundNeed"
        tile.contentDescription = if (isPlaying) {
            "Pausar música"
        } else {
            "Reproducir música"
        }

        // Icono básico (puedes personalizarlo más tarde)
        tile.icon = android.graphics.drawable.Icon.createWithResource(
            this,
            R.mipmap.ic_launcher
        )

        tile.updateTile()
    }

    /**
     * Método para actualizar el estado de reproducción desde la app
     * Debe llamarse desde Flutter vía MethodChannel
     */
    fun setPlayingState(playing: Boolean) {
        isPlaying = playing
        updateTileState()
    }
}
