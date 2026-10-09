package com.example.music_player

import android.app.Activity
import android.view.View
import android.view.ViewGroup
import android.net.Uri
import androidx.appcompat.view.ContextThemeWrapper
import androidx.mediarouter.app.MediaRouteButton
import com.google.android.gms.common.images.WebImage
import com.google.android.gms.cast.MediaInfo
import com.google.android.gms.cast.MediaMetadata
import com.google.android.gms.cast.framework.CastButtonFactory
import com.google.android.gms.cast.framework.CastContext
import com.google.android.gms.cast.framework.CastSession
import com.google.android.gms.cast.framework.SessionManagerListener
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/** Google Cast sender integration using Google's standard media receiver. */
class CastSenderManager(private val activity: Activity, messenger: io.flutter.plugin.common.BinaryMessenger) {
    private val methods = MethodChannel(messenger, "soundneed/cast_sender")
    private var sessionSink: EventChannel.EventSink? = null
    private var castContext: CastContext? = null
    private var routeButton: MediaRouteButton? = null

    private val sessionListener = object : SessionManagerListener<CastSession> {
        override fun onSessionStarting(session: CastSession) = Unit
        override fun onSessionStarted(session: CastSession, sessionId: String) = publishConnection(true)
        override fun onSessionStartFailed(session: CastSession, error: Int) = publishConnection(false)
        override fun onSessionEnding(session: CastSession) = Unit
        override fun onSessionEnded(session: CastSession, error: Int) = publishConnection(false)
        override fun onSessionResuming(session: CastSession, sessionId: String) = Unit
        override fun onSessionResumed(session: CastSession, wasSuspended: Boolean) = publishConnection(true)
        override fun onSessionResumeFailed(session: CastSession, error: Int) = publishConnection(false)
        override fun onSessionSuspended(session: CastSession, reason: Int) = publishConnection(false)
    }

    init {
        EventChannel(messenger, "soundneed/cast/session").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                sessionSink = events
                publishConnection(isConnected())
            }
            override fun onCancel(arguments: Any?) { sessionSink = null }
        })

        methods.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "showPicker" -> {
                        initializeCast()
                        val button = routeButton ?: throw IllegalStateException("El botón de Google Cast no está disponible")
                        if (button.parent == null) {
                            activity.addContentView(button, ViewGroup.LayoutParams(1, 1))
                        }
                        button.visibility = View.VISIBLE
                        button.performClick()
                        button.visibility = View.GONE
                        result.success(null)
                    }
                    "loadMedia" -> {
                        initializeCast()
                        val remote = castContext?.sessionManager?.currentCastSession?.remoteMediaClient
                            ?: throw IllegalStateException("Conecta primero un dispositivo Google Cast")
                        val url = call.argument<String>("url").orEmpty()
                        require(url.startsWith("https://") || url.startsWith("http://")) { "La URL de audio no es accesible para Cast" }
                        val metadata = MediaMetadata(MediaMetadata.MEDIA_TYPE_MUSIC_TRACK).apply {
                            putString(MediaMetadata.KEY_TITLE, call.argument<String>("title").orEmpty())
                            putString(MediaMetadata.KEY_ARTIST, call.argument<String>("artist").orEmpty())
                            call.argument<String>("artwork")?.takeIf { it.startsWith("https://") || it.startsWith("http://") }
                                ?.let { addImage(WebImage(Uri.parse(it))) }
                        }
                        val contentType = call.argument<String>("contentType") ?: "audio/mpeg"
                        val info = MediaInfo.Builder(url)
                            .setContentType(contentType)
                            .setStreamType(MediaInfo.STREAM_TYPE_BUFFERED)
                            .setMetadata(metadata)
                            .build()
                        remote.load(info, true)
                        result.success(null)
                    }
                    "play" -> { castContext?.sessionManager?.currentCastSession?.remoteMediaClient?.play(); result.success(null) }
                    "pause" -> { castContext?.sessionManager?.currentCastSession?.remoteMediaClient?.pause(); result.success(null) }
                    "seek" -> {
                        val ms = call.argument<Number>("positionMs")?.toLong() ?: 0L
                        castContext?.sessionManager?.currentCastSession?.remoteMediaClient?.seek(ms)
                        result.success(null)
                    }
                    "stop" -> { castContext?.sessionManager?.currentCastSession?.remoteMediaClient?.stop(); result.success(null) }
                    else -> result.notImplemented()
                }
            } catch (error: Exception) {
                result.error("CAST_ERROR", error.message ?: "Error de Google Cast", null)
            }
        }
    }

    private fun initializeCast() {
        if (castContext != null) return
        try {
            val context = CastContext.getSharedInstance(activity)
            context.sessionManager.addSessionManagerListener(sessionListener, CastSession::class.java)
            val castButtonContext = ContextThemeWrapper(
                activity,
                R.style.SoundNeedCastButtonTheme,
            )
            val button = MediaRouteButton(castButtonContext)
            CastButtonFactory.setUpMediaRouteButton(activity, button)
            castContext = context
            routeButton = button
        } catch (error: Throwable) {
            android.util.Log.e(TAG, "No se pudo inicializar Google Cast", error)
            throw IllegalStateException("No se pudo iniciar Google Cast: ${error.message}", error)
        }
    }

    private fun isConnected(): Boolean = castContext?.sessionManager?.currentCastSession?.isConnected == true

    private fun publishConnection(connected: Boolean) {
        activity.runOnUiThread { sessionSink?.success(mapOf("connected" to connected)) }
    }

    fun dispose() {
        try { castContext?.sessionManager?.removeSessionManagerListener(sessionListener, CastSession::class.java) } catch (_: Exception) { }
        methods.setMethodCallHandler(null)
        sessionSink = null
    }

    companion object { private const val TAG = "SoundNeedCast" }
}
