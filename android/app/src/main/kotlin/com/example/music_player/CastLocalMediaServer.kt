package com.example.music_player

import android.content.Context
import android.net.Uri
import java.io.BufferedInputStream
import java.io.BufferedOutputStream
import java.io.File
import java.net.Inet4Address
import java.net.InetSocketAddress
import java.net.NetworkInterface
import java.net.ServerSocket
import java.net.Socket
import java.util.Collections
import java.util.UUID
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/** Serves one local audio file to a Cast receiver over the phone's LAN address. */
class CastLocalMediaServer(context: Context) {
    private val appContext = context.applicationContext
    private val stopped = AtomicBoolean(false)
    private var serverSocket: ServerSocket? = null
    private var workers: ExecutorService? = null
    private var acceptThread: Thread? = null
    private var mediaFile: File? = null
    private var temporaryFile: File? = null
    private var artworkFile: File? = null
    private var token: String = ""
    private var contentType: String = "audio/mpeg"
    private var artworkContentType: String = "image/jpeg"

    /** Copies content:// sources to cache so Cast can seek and issue byte ranges. */
    fun start(source: String, mimeType: String, artworkBytes: ByteArray?): Map<String, String> {
        close()
        stopped.set(false)
        val uri = Uri.parse(source)
        val file = when (uri.scheme?.lowercase()) {
            "content" -> copyContentUri(uri)
            "file" -> File(requireNotNull(uri.path) { "La ruta local está vacía." })
            else -> File(source)
        }
        require(file.isFile && file.canRead()) { "No se puede leer el archivo de música local." }
        mediaFile = file
        contentType = mimeType.takeIf { it.startsWith("audio/") } ?: "audio/mpeg"
        artworkBytes?.takeIf { it.isNotEmpty() }?.let { bytes ->
            val imageType = when {
                bytes.size >= 8 && bytes[0] == 0x89.toByte() && bytes[1] == 0x50.toByte() -> "image/png"
                bytes.size >= 3 && bytes[0] == 0xff.toByte() && bytes[1] == 0xd8.toByte() -> "image/jpeg"
                bytes.size >= 12 && String(bytes, 8, 4, Charsets.US_ASCII) == "WEBP" -> "image/webp"
                else -> "image/jpeg"
            }
            artworkContentType = imageType
            artworkFile = File.createTempFile("soundneed-cast-art-", ".img", appContext.cacheDir)
                .also { it.writeBytes(bytes) }
        }
        token = UUID.randomUUID().toString().replace("-", "")

        val socket = ServerSocket().apply {
            reuseAddress = true
            bind(InetSocketAddress("0.0.0.0", 0))
        }
        serverSocket = socket
        workers = Executors.newCachedThreadPool()
        acceptThread = Thread({
            while (!stopped.get()) {
                try {
                    val client = socket.accept()
                    workers?.execute { serve(client) }
                } catch (_: Exception) {
                    if (!stopped.get()) android.util.Log.w(TAG, "Falló una conexión de Cast local")
                }
            }
        }, "SoundNeed-Cast-HTTP").apply {
            isDaemon = true
            start()
        }

        val address = findLocalAddress()
        val baseUrl = "http://${address.hostAddress}:${socket.localPort}/$token"
        val result = mutableMapOf("url" to baseUrl)
        if (artworkFile != null) result["artworkUrl"] = "$baseUrl/artwork"
        return result
    }

    private fun copyContentUri(uri: Uri): File {
        val extension = when (contentTypeFromUri(uri)) {
            "audio/mp4", "audio/x-m4a" -> ".m4a"
            "audio/ogg", "audio/opus" -> ".ogg"
            "audio/flac", "audio/x-flac" -> ".flac"
            "audio/wav", "audio/x-wav" -> ".wav"
            else -> ".audio"
        }
        val copy = File.createTempFile("soundneed-cast-", extension, appContext.cacheDir)
        try {
            val input = appContext.contentResolver.openInputStream(uri)
                ?: throw IllegalStateException("Android no pudo abrir el archivo de música.")
            input.use { source ->
                copy.outputStream().use { output -> source.copyTo(output) }
            }
            temporaryFile = copy
            return copy
        } catch (error: Exception) {
            copy.delete()
            throw error
        }
    }

    private fun contentTypeFromUri(uri: Uri): String =
        appContext.contentResolver.getType(uri)?.lowercase().orEmpty()

    private fun findLocalAddress(): Inet4Address {
        val interfaces = Collections.list(NetworkInterface.getNetworkInterfaces())
            .filter { it.isUp && !it.isLoopback }
            .sortedBy { if (it.name.startsWith("wlan") || it.name.startsWith("eth")) 0 else 1 }
        for (networkInterface in interfaces) {
            val address = Collections.list(networkInterface.inetAddresses)
                .filterIsInstance<Inet4Address>()
                .firstOrNull { !it.isLoopbackAddress && !it.isLinkLocalAddress }
            if (address != null) return address
        }
        throw IllegalStateException("Conecta el teléfono a la misma red Wi-Fi que el TV.")
    }

    private fun serve(client: Socket) {
        client.use { socket ->
            try {
                socket.soTimeout = 15_000
                val input = BufferedInputStream(socket.getInputStream())
                val requestLine = input.readAsciiLine() ?: return
                val request = requestLine.split(' ')
                if (request.size < 2) return
                val method = request[0].uppercase()
                val path = request[1].substringBefore('?')
                val headers = mutableMapOf<String, String>()
                while (true) {
                    val line = input.readAsciiLine() ?: break
                    if (line.isEmpty()) break
                    val separator = line.indexOf(':')
                    if (separator > 0) {
                        headers[line.substring(0, separator).trim().lowercase()] =
                            line.substring(separator + 1).trim()
                    }
                }
                if (path != "/$token" && path != "/$token/artwork") {
                    writeResponse(socket, 404, "Not Found", "text/plain", ByteArray(0), false)
                    return
                }
                if (method == "OPTIONS") {
                    val output = BufferedOutputStream(socket.getOutputStream())
                    output.write(
                        ("HTTP/1.1 204 No Content\r\n" +
                                "Access-Control-Allow-Origin: *\r\n" +
                                "Access-Control-Allow-Methods: GET, HEAD, OPTIONS\r\n" +
                                "Access-Control-Allow-Headers: Range, Content-Type\r\n" +
                                "Access-Control-Max-Age: 600\r\n" +
                                "Content-Length: 0\r\nConnection: close\r\n\r\n")
                            .toByteArray(Charsets.ISO_8859_1),
                    )
                    output.flush()
                    return
                }
                if (method != "GET" && method != "HEAD") {
                    writeResponse(socket, 405, "Method Not Allowed", "text/plain", ByteArray(0), false)
                    return
                }

                if (path == "/$token/artwork") {
                    val image = artworkFile ?: run {
                        writeResponse(socket, 404, "Not Found", "text/plain", ByteArray(0), false)
                        return
                    }
                    val bytes = image.readBytes()
                    writeHeader(socket, 200, "OK", artworkContentType, bytes.size.toLong(), bytes.size.toLong(), null)
                    if (method == "GET") socket.getOutputStream().apply { write(bytes); flush() }
                    return
                }

                val file = mediaFile ?: throw IllegalStateException("El audio local ya no está disponible.")
                val length = file.length()
                val rangeHeader = headers["range"]
                val range = parseRange(rangeHeader, length)
                if (rangeHeader != null && range == null) {
                    writeHeader(socket, 416, "Range Not Satisfiable", "text/plain", 0, length, null)
                    return
                }
                val (start, end) = range ?: (0L to (length - 1).coerceAtLeast(0))
                val responseLength = if (length == 0L) 0L else end - start + 1
                val partial = range != null
                writeHeader(
                    socket,
                    if (partial) 206 else 200,
                    if (partial) "Partial Content" else "OK",
                    contentType,
                    responseLength,
                    length,
                    if (partial) "bytes $start-$end/$length" else null,
                )
                if (method == "HEAD" || responseLength == 0L) return

                val output = BufferedOutputStream(socket.getOutputStream())
                java.io.RandomAccessFile(file, "r").use { media ->
                    media.seek(start)
                    val buffer = ByteArray(64 * 1024)
                    var remaining = responseLength
                    while (remaining > 0 && !stopped.get()) {
                        val count = media.read(buffer, 0, minOf(buffer.size.toLong(), remaining).toInt())
                        if (count < 0) break
                        output.write(buffer, 0, count)
                        remaining -= count
                    }
                }
                output.flush()
            } catch (error: Exception) {
                if (!stopped.get()) android.util.Log.w(TAG, "Error entregando audio local a Cast", error)
            }
        }
    }

    private fun parseRange(value: String?, length: Long): Pair<Long, Long>? {
        if (value == null) return null
        if (!value.startsWith("bytes=") || length <= 0) return null
        val parts = value.removePrefix("bytes=").substringBefore(',').split('-', limit = 2)
        if (parts.size != 2) return null
        return try {
            val start: Long
            val end: Long
            if (parts[0].isBlank()) {
                val suffixLength = parts[1].toLong().coerceAtLeast(1)
                start = (length - suffixLength).coerceAtLeast(0)
                end = length - 1
            } else {
                start = parts[0].toLong()
                end = if (parts[1].isBlank()) length - 1 else parts[1].toLong().coerceAtMost(length - 1)
            }
            if (start < 0 || start >= length || end < start) null else start to end
        } catch (_: NumberFormatException) {
            null
        }
    }

    private fun writeHeader(
        socket: Socket,
        code: Int,
        reason: String,
        mime: String,
        length: Long,
        fullLength: Long,
        contentRange: String?,
    ) {
        val output = BufferedOutputStream(socket.getOutputStream())
        val headers = buildString {
            append("HTTP/1.1 $code $reason\r\n")
            append("Content-Type: $mime\r\n")
            append("Content-Length: $length\r\n")
            append("Accept-Ranges: bytes\r\n")
            append("Access-Control-Allow-Origin: *\r\n")
            append("Access-Control-Expose-Headers: Content-Length, Content-Range, Accept-Ranges\r\n")
            append("Connection: close\r\n")
            if (contentRange != null) append("Content-Range: $contentRange\r\n")
            if (code == 416) append("Content-Range: bytes */$fullLength\r\n")
            append("\r\n")
        }
        output.write(headers.toByteArray(Charsets.ISO_8859_1))
        output.flush()
    }

    private fun writeResponse(
        socket: Socket,
        code: Int,
        reason: String,
        mime: String,
        body: ByteArray,
        includeBody: Boolean,
    ) {
        writeHeader(socket, code, reason, mime, body.size.toLong(), body.size.toLong(), null)
        if (includeBody && body.isNotEmpty()) socket.getOutputStream().write(body)
    }

    fun close() {
        if (!stopped.compareAndSet(false, true)) return
        try { serverSocket?.close() } catch (_: Exception) { }
        workers?.shutdownNow()
        temporaryFile?.delete()
        artworkFile?.delete()
        serverSocket = null
        workers = null
        acceptThread = null
        mediaFile = null
        temporaryFile = null
        artworkFile = null
    }

    private fun BufferedInputStream.readAsciiLine(): String? {
        val line = StringBuilder()
        while (true) {
            val value = read()
            if (value < 0) return if (line.isEmpty()) null else line.toString()
            if (value == '\n'.code) return line.toString().removeSuffix("\r")
            line.append(value.toChar())
            if (line.length > 8192) throw IllegalArgumentException("HTTP header demasiado largo")
        }
    }

    companion object { private const val TAG = "SoundNeedCastLocal" }
}
