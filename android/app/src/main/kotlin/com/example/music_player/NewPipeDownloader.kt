package com.example.music_player

import android.os.Build
import org.schabi.newpipe.extractor.downloader.Downloader
import org.schabi.newpipe.extractor.downloader.Request
import org.schabi.newpipe.extractor.downloader.Response
import java.net.HttpURLConnection
import java.net.URL

class NewPipeDownloader : Downloader() {

    companion object {
        private const val CONNECT_TIMEOUT = 15_000
        private const val READ_TIMEOUT = 30_000

        private const val USER_AGENT =
            "Mozilla/5.0 (Linux; Android %s) " +
            "AppleWebKit/537.36 (KHTML, like Gecko) " +
            "Chrome/140.0 Mobile Safari/537.36"
    }

    override fun execute(request: Request): Response {

        val url = URL(request.url())

        val connection =
            url.openConnection() as HttpURLConnection

        try {
            connection.requestMethod = request.httpMethod()

            connection.instanceFollowRedirects = true
            connection.useCaches = false
            connection.doInput = true

            connection.connectTimeout = CONNECT_TIMEOUT
            connection.readTimeout = READ_TIMEOUT

            connection.setRequestProperty(
                "User-Agent",
                USER_AGENT.format(Build.VERSION.RELEASE)
            )

            connection.setRequestProperty(
                "Accept",
                "*/*"
            )

            connection.setRequestProperty(
                "Accept-Encoding",
                "identity"
            )

            for ((name, values) in request.headers()) {
                for (value in values) {
                    connection.setRequestProperty(name, value)
                }
            }

            val body = request.dataToSend()

            if (body != null && body.isNotEmpty()) {
                connection.doOutput = true

                connection.outputStream.use { output ->
                    output.write(body)
                    output.flush()
                }
            }

            val responseCode = connection.responseCode

            val responseMessage =
                connection.responseMessage ?: ""

            val headers =
                connection.headerFields
                    .filterKeys { it != null }
                    .mapKeys { it.key!! }
                    .mapValues { it.value ?: emptyList() }

            val inputStream =
                if (responseCode >= 400) {
                    connection.errorStream
                } else {
                    connection.inputStream
                }

            val responseBody =
                inputStream
                    ?.bufferedReader(Charsets.UTF_8)
                    ?.use { it.readText() }
                    ?: ""

            return Response(
                responseCode,
                responseMessage,
                headers,
                responseBody,
                connection.url.toString()
            )

        } finally {
            connection.disconnect()
        }
    }
}
