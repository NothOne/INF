package app.inf.flutter

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import java.io.ByteArrayOutputStream
import java.io.File
import java.nio.ByteBuffer

/**
 * Writes a Weibo live photo as a Motion Photo (Google's format, also read by most Android
 * galleries): the still as a JPEG whose XMP points at an MP4 appended after its end.
 */
object MotionPhoto {
    private val xmpHeader = "http://ns.adobe.com/xap/1.0/\u0000".toByteArray(Charsets.US_ASCII)

    /** Writes [target] from [image] and the motion clip [video]. */
    fun compose(image: File, video: File, target: File, scratch: File) {
        val remuxed = File(scratch, "motion-" + System.nanoTime() + ".mp4")
        try {
            val clip = if (remuxToMp4(video, remuxed)) remuxed else video
            val mime = if (clip === remuxed) "video/mp4" else "video/quicktime"
            val length = clip.length()
            val jpeg = withXmp(jpegOf(image), xmp(mime, length))
            target.outputStream().use { out ->
                out.write(jpeg)
                clip.inputStream().use { it.copyTo(out) }
            }
        } finally {
            remuxed.delete()
        }
    }

    /**
     * Weibo serves the clip as QuickTime; galleries expect MP4. Copies the samples into an MP4
     * container without re-encoding. False when the platform cannot read or write the tracks.
     */
    fun remuxToMp4(source: File, target: File): Boolean {
        val extractor = MediaExtractor()
        var muxer: MediaMuxer? = null
        return try {
            extractor.setDataSource(source.path)
            val output = MediaMuxer(target.path, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            muxer = output
            val tracks = HashMap<Int, Int>()
            var bufferSize = 1 shl 20
            for (index in 0 until extractor.trackCount) {
                val format = extractor.getTrackFormat(index)
                val mime = format.getString(MediaFormat.KEY_MIME) ?: continue
                if (!mime.startsWith("video/") && !mime.startsWith("audio/")) continue
                extractor.selectTrack(index)
                tracks[index] = output.addTrack(format)
                if (format.containsKey(MediaFormat.KEY_MAX_INPUT_SIZE)) {
                    bufferSize = maxOf(bufferSize, format.getInteger(MediaFormat.KEY_MAX_INPUT_SIZE))
                }
                if (mime.startsWith("video/") && format.containsKey(MediaFormat.KEY_ROTATION)) {
                    output.setOrientationHint(format.getInteger(MediaFormat.KEY_ROTATION))
                }
            }
            if (tracks.isEmpty()) {
                target.delete()
                return false
            }
            output.start()
            val buffer = ByteBuffer.allocate(bufferSize)
            val info = MediaCodec.BufferInfo()
            while (true) {
                val size = extractor.readSampleData(buffer, 0)
                if (size < 0) break
                val track = tracks[extractor.sampleTrackIndex]
                if (track != null) {
                    info.set(
                        0,
                        size,
                        extractor.sampleTime,
                        if (extractor.sampleFlags and MediaExtractor.SAMPLE_FLAG_SYNC != 0) {
                            MediaCodec.BUFFER_FLAG_KEY_FRAME
                        } else {
                            0
                        },
                    )
                    output.writeSampleData(track, buffer, info)
                }
                extractor.advance()
            }
            output.stop()
            true
        } catch (_: Throwable) {
            target.delete()
            false
        } finally {
            try {
                muxer?.release()
            } catch (_: Throwable) {
            }
            extractor.release()
        }
    }

    /** The still as JPEG bytes; sinaimg sometimes serves WebP or PNG under a `.jpg` name. */
    private fun jpegOf(image: File): ByteArray {
        val bytes = image.readBytes()
        if (bytes.size > 2 && bytes[0] == 0xFF.toByte() && bytes[1] == 0xD8.toByte()) return bytes
        val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
            ?: throw IllegalArgumentException("unreadable image")
        return ByteArrayOutputStream().use { out ->
            bitmap.compress(Bitmap.CompressFormat.JPEG, 95, out)
            bitmap.recycle()
            out.toByteArray()
        }
    }

    /**
     * Motion Photo 1.0 plus the older MicroVideo fields, which some galleries still read instead.
     * A presentation timestamp of -1 leaves the cover frame to the gallery.
     */
    private fun xmp(videoMime: String, videoLength: Long): ByteArray = """
        <x:xmpmeta xmlns:x="adobe:ns:meta/" x:xmptk="INF">
          <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
            <rdf:Description rdf:about=""
                xmlns:GCamera="http://ns.google.com/photos/1.0/camera/"
                xmlns:Container="http://ns.google.com/photos/1.0/container/"
                xmlns:Item="http://ns.google.com/photos/1.0/container/item/"
              GCamera:MotionPhoto="1"
              GCamera:MotionPhotoVersion="1"
              GCamera:MotionPhotoPresentationTimestampUs="-1"
              GCamera:MicroVideo="1"
              GCamera:MicroVideoVersion="1"
              GCamera:MicroVideoOffset="$videoLength"
              GCamera:MicroVideoPresentationTimestampUs="-1">
              <Container:Directory>
                <rdf:Seq>
                  <rdf:li rdf:parseType="Resource">
                    <Container:Item Item:Mime="image/jpeg" Item:Semantic="Primary" Item:Length="0" Item:Padding="0"/>
                  </rdf:li>
                  <rdf:li rdf:parseType="Resource">
                    <Container:Item Item:Mime="$videoMime" Item:Semantic="MotionPhoto" Item:Length="$videoLength" Item:Padding="0"/>
                  </rdf:li>
                </rdf:Seq>
              </Container:Directory>
            </rdf:Description>
          </rdf:RDF>
        </x:xmpmeta>
    """.trimIndent().toByteArray(Charsets.UTF_8)

    /**
     * Puts [xmp] in an APP1 segment after the leading APPn segments (JFIF and Exif stay first),
     * dropping any XMP the picture already had so readers see only ours.
     */
    private fun withXmp(jpeg: ByteArray, xmp: ByteArray): ByteArray {
        val out = ByteArrayOutputStream(jpeg.size + xmp.size + 64)
        out.write(jpeg, 0, 2)
        var position = 2
        while (position + 4 <= jpeg.size && jpeg[position] == 0xFF.toByte()) {
            val marker = jpeg[position + 1].toInt() and 0xFF
            if (marker !in 0xE0..0xEF) break
            val length = ((jpeg[position + 2].toInt() and 0xFF) shl 8) or (jpeg[position + 3].toInt() and 0xFF)
            if (length < 2 || position + 2 + length > jpeg.size) break
            val isXmp = marker == 0xE1 && startsWith(jpeg, position + 4, xmpHeader)
            if (!isXmp) out.write(jpeg, position, length + 2)
            position += length + 2
        }
        val payload = xmpHeader.size + xmp.size
        out.write(0xFF)
        out.write(0xE1)
        out.write((payload + 2) shr 8)
        out.write((payload + 2) and 0xFF)
        out.write(xmpHeader)
        out.write(xmp)
        out.write(jpeg, position, jpeg.size - position)
        return out.toByteArray()
    }

    private fun startsWith(bytes: ByteArray, at: Int, prefix: ByteArray): Boolean {
        if (at + prefix.size > bytes.size) return false
        for (i in prefix.indices) if (bytes[at + i] != prefix[i]) return false
        return true
    }
}
