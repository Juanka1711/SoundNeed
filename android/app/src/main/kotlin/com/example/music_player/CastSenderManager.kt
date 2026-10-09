package com.example.music_player

import android.app.Activity
import android.view.View
import android.view.ViewGroup
import android.view.KeyEvent
import android.net.Uri
import androidx.appcompat.view.ContextThemeWrapper
import androidx.mediarouter.app.MediaRouteButton
import com.google.android.gms.common.images.WebImage
import com.google.android.gms.cast.MediaInfo
import com.google.android.gms.cast.MediaMetadata
import com.google.android.gms.cast.MediaStatus
import com.google.android.gms.cast.framework.media.RemoteMediaClient
import com.google.android.gms.cast.framework.CastButtonFactory
import com.google.android.gms.cast.framework.CastContext
import com.google.android.gms.cast.framework.CastSession
import com.google.android.gms.cast.framework.SessionManagerListener
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/** Google Cast sender integration using Google's standard media receiver. */
class CastSenderManager(private val activity: Activity, messenger: io.flutter.plugin.common.BinaryMessenger) {
    private val methods = MethodChannel(messenger, "soundneed/cast_sender")
    private var sessionSink: EventChannel.EventSink? = null
    private var castContext: CastContext? = null
    private var routeButton: MediaRouteButton? = null
    private var observedClient: RemoteMediaClient? = null
    @Volatile private var localMediaServer: CastLocalMediaServer? = null
    private val localMediaExecutor = Executors.newSingleThreadExecutor()

    private val remoteMediaCallback = object : RemoteMediaClient.Callback() {
        override fun onStatusUpdated() = publishSession()
        override fun onMetadataUpdated() = publishSession()
    }
    private val remoteProgressListener = RemoteMediaClient.ProgressListener { _, _ ->
        publishSession()
    }

    private val sessionListener = object : SessionManagerListener<CastSession> {
        override fun onSessionStarting(session: CastSession) = Unit
        override fun onSessionStarted(session: CastSession, sessionId: String) {
            observeRemoteClient(session)
            publishSession()
        }
        override fun onSessionStartFailed(session: CastSession, error: Int) = publishSession()
        override fun onSessionEnding(session: CastSession) = Unit
        override fun onSessionEnded(session: CastSession, error: Int) {
            stopObservingRemoteClient()
            localMediaServer?.close()
            localMediaServer = null
            publishSession()
        }
        override fun onSessionResuming(session: CastSession, sessionId: String) = Unit
        override fun onSessionResumed(session: CastSession, wasSuspended: Boolean) {
            observeRemoteClient(session)
            publishSession()
        }
        override fun onSessionResumeFailed(session: CastSession, error: Int) = publishSession()
        override fun onSessionSuspended(session: CastSession, reason: Int) = publishSession()
    }

    init {
        EventChannel(messenger, "soundneed/cast/session").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                sessionSink = events
                castContext?.sessionManager?.currentCastSession?.let(::observeRemoteClient)
                publishSession()
            }
            override fun onCancel(arguments: Any?) { sessionSink = null }
        })

        methods.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "prepareLocalMedia" -> {
                        val source = call.argument<String>("uri").orEmpty()
                        val mimeType = call.argument<String>("contentType").orEmpty()
                        val artwork = call.argument<ByteArray>("artwork")
                        if (source.isBlank()) {
                            result.error("LOCAL_MEDIA_UNAVAILABLE", "La ruta de la canción está vacía.", null)
                            return@setMethodCallHandler
                        }
                        localMediaServer?.close()
                        localMediaServer = null
                        localMediaExecutor.execute {
                            val server = CastLocalMediaServer(activity)
                            try {
                                val media = server.start(source, mimeType, artwork)
                                localMediaServer = server
                                activity.runOnUiThread { result.success(media) }
                            } catch (error: Exception) {
                                server.close()
                                android.util.Log.e(TAG, "No se pudo compartir la canción local con Cast", error)
                                activity.runOnUiThread {
                                    result.error(
                                        "LOCAL_MEDIA_UNAVAILABLE",
                                        error.message ?: "No se pudo preparar la canción local para Cast.",
                                        null,
                                    )
                                }
                            }
                        }
                    }
                    "showPicker" -> {
                        initializeCast()
                        castContext?.sessionManager?.currentCastSession?.let(::observeRemoteClient)
                        publishSession()
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
                        require(url.startsWith("https://") || url.startsWith("http://")) { "La URL de medios no es accesible para Cast" }
                        val isVideo = call.argument<Boolean>("isVideo") == true
                        val metadata = MediaMetadata(
                            if (isVideo) MediaMetadata.MEDIA_TYPE_MOVIE else MediaMetadata.MEDIA_TYPE_MUSIC_TRACK
                        ).apply {
                            putString(MediaMetadata.KEY_TITLE, call.argument<String>("title").orEmpty())
                            putString(MediaMetadata.KEY_ARTIST, call.argument<String>("artist").orEmpty())
                            call.argument<String>("artwork")?.takeIf { it.startsWith("https://") || it.startsWith("http://") }
                                ?.let { addImage(WebImage(Uri.parse(it))) }
                        }
                        val contentType = call.argument<String>("contentType")
                            ?: if (isVideo) "video/mp4" else "audio/mpeg"
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

    /** Routes hardware volume keys to the active Cast receiver while it is connected. */
    fun adjustCastVolumeForKey(keyCode: Int, action: Int, repeatCount: Int): Boolean {
        val delta = when (keyCode) {
            KeyEvent.KEYCODE_VOLUME_UP -> 0.05
            KeyEvent.KEYCODE_VOLUME_DOWN -> -0.05
            else -> return false
        }
        val session = castContext?.sessionManager?.currentCastSession
            ?.takeIf { it.isConnected } ?: return false
        if (action != KeyEvent.ACTION_DOWN) return true

        return try {
            val nextVolume = (session.volume + delta).coerceIn(0.0, 1.0)
            session.setVolume(nextVolume)
            if (keyCode == KeyEvent.KEYCODE_VOLUME_UP) session.setMute(false)
            android.util.Log.d(TAG, "Volumen Cast actualizado a $nextVolume (repetición $repeatCount)")
            true
        } catch (error: Exception) {
            android.util.Log.w(TAG, "No se pudo ajustar el volumen Cast desde las teclas físicas", error)
            false
        }
    }

    private fun observeRemoteClient(session: CastSession) {
        val client = session.remoteMediaClient ?: return
        if (observedClient === client) return
        stopObservingRemoteClient()
        observedClient = client
        client.registerCallback(remoteMediaCallback)
        client.addProgressListener(remoteProgressListener, 1000L)
    }

    private fun stopObservingRemoteClient() {
        observedClient?.let { client ->
            client.unregisterCallback(remoteMediaCallback)
            client.removeProgressListener(remoteProgressListener)
        }
        observedClient = null
    }

    private fun publishSession() {
        activity.runOnUiThread {
            val session = castContext?.sessionManager?.currentCastSession
            val remote = session?.remoteMediaClient
            val media = remote?.mediaInfo
            val metadata = media?.metadata
            val artworkUrl = metadata?.images?.firstOrNull()?.url?.toString().orEmpty()
            val positionMs = try { remote?.approximateStreamPosition ?: 0L } catch (_: Exception) { 0L }
            val durationMs = try { remote?.streamDuration ?: 0L } catch (_: Exception) { 0L }
            sessionSink?.success(
                mapOf(
                    "connected" to (session?.isConnected == true),
                    "deviceName" to session?.castDevice?.friendlyName.orEmpty(),
                    "playing" to (remote?.isPlaying == true),
                    "ended" to (
                        remote?.playerState == MediaStatus.PLAYER_STATE_IDLE &&
                            remote.idleReason == MediaStatus.IDLE_REASON_FINISHED
                        ),
                    "title" to metadata?.getString(MediaMetadata.KEY_TITLE).orEmpty(),
                    "artist" to metadata?.getString(MediaMetadata.KEY_ARTIST).orEmpty(),
                    "artworkUrl" to artworkUrl,
                    "contentId" to media?.contentId.orEmpty(),
                    "positionMs" to positionMs,
                    "durationMs" to durationMs,
                )
            )
        }
    }

    fun dispose() {
        stopObservingRemoteClient()
        localMediaServer?.close()
        localMediaServer = null
        localMediaExecutor.shutdownNow()
        try { castContext?.sessionManager?.removeSessionManagerListener(sessionListener, CastSession::class.java) } catch (_: Exception) { }
        methods.setMethodCallHandler(null)
        sessionSink = null
    }

    companion object { private const val TAG = "SoundNeedCast" }
}
