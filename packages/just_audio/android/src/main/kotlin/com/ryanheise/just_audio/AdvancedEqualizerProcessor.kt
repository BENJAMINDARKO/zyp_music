package com.ryanheise.just_audio

import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.audio.AudioProcessor.AudioFormat
import androidx.media3.common.audio.AudioProcessor.UnhandledAudioFormatException
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.PI
import kotlin.math.pow
import kotlin.math.sin
import kotlin.math.cos

class AdvancedEqualizerProcessor : AudioProcessor {
    companion object {
        private val BAND_FREQS = doubleArrayOf(
            31.0, 45.0, 63.0, 90.0, 125.0, 180.0, 250.0, 355.0,
            500.0, 710.0, 1000.0, 1400.0, 2000.0, 4000.0, 8000.0, 16000.0
        )

        private const val CASCADE_COMPENSATION_FACTOR = 0.18
        private const val MAX_BAND_GAIN_DB = 15.0

        private val activeProcessors = java.util.concurrent.CopyOnWriteArrayList<AdvancedEqualizerProcessor>()

        fun broadcastConfig(enabled: Boolean, gains: FloatArray, preamp: Float, bass: Float, virtualizer: Float, limiter: Boolean) {
            for (proc in activeProcessors) {
                proc.updateConfig(enabled, gains, preamp, bass, virtualizer, limiter)
            }
        }
    }

    private var isActive = false
    @Volatile private var inputEnded = false
    private var outputBuffer: ByteBuffer = AudioProcessor.EMPTY_BUFFER

    @Volatile var isEnabled = true
    @Volatile var preampDb = 0.0f
    @Volatile var bassBoostFactor = 0.24f
    @Volatile var virtualizerFactor = 0.18f
    @Volatile var limiterEnabled = true
    @Volatile var bandGains = FloatArray(16) { 0.0f }

    private var sampleRate = 44100.0
    private var channelCount = 2

    private class BiquadBand {
        var b0 = 0.0; var b1 = 0.0; var b2 = 0.0
        var a1 = 0.0; var a2 = 0.0

        var x1L = 0.0; var x2L = 0.0; var y1L = 0.0; var y2L = 0.0
        var x1R = 0.0; var x2R = 0.0; var y1R = 0.0; var y2R = 0.0

        fun flush() {
            x1L = 0.0; x2L = 0.0; y1L = 0.0; y2L = 0.0
            x1R = 0.0; x2R = 0.0; y1R = 0.0; y2R = 0.0
        }
    }

    private val bands = Array(16) { BiquadBand() }

    fun updateConfig(enabled: Boolean, gains: FloatArray, preamp: Float, bass: Float, virtualizer: Float, limiter: Boolean) {
        this.isEnabled = enabled
        this.preampDb = preamp
        this.bassBoostFactor = bass / 100.0f
        this.virtualizerFactor = virtualizer / 100.0f
        this.limiterEnabled = limiter
        for (i in 0 until 16) {
            this.bandGains[i] = if (i < gains.size) gains[i] else 0.0f
        }
        recomputeCoefficients()
    }

    override fun configure(inputAudioFormat: AudioFormat): AudioFormat {
        val channels = inputAudioFormat.channelCount
        if (channels < 1 || channels > 2) {
            isActive = false
            throw UnhandledAudioFormatException(inputAudioFormat)
        }
        channelCount = channels
        sampleRate = inputAudioFormat.sampleRate.toDouble()
        isActive = true
        inputEnded = false
        activeProcessors.addIfAbsent(this)
        recomputeCoefficients()
        return inputAudioFormat
    }

    private fun recomputeCoefficients() {
        val rawGains = DoubleArray(16)

        for (i in 0 until 16) {
            val f0 = BAND_FREQS[i]
            var gainDb = bandGains[i].toDouble()

            if (f0 < 150.0 && bassBoostFactor > 0.0f) {
                val boostProportion = (150.0 - f0) / 120.0
                val existingBoost = gainDb.coerceAtLeast(0.0)
                val bassHeadroomFactor = (1.0 - (existingBoost / 12.0)).coerceIn(0.0, 1.0)
                val addedDb = (bassBoostFactor * 8.0) * boostProportion.coerceIn(0.0, 1.0) * bassHeadroomFactor
                gainDb += addedDb
            }
            rawGains[i] = gainDb
        }

        for (i in 0 until 16) {
            val f0 = BAND_FREQS[i]
            var gainDb = rawGains[i]

            if (gainDb > 0.0) {
                var neighborBoost = 0.0
                if (i > 0) neighborBoost += rawGains[i - 1].coerceAtLeast(0.0)
                if (i < 15) neighborBoost += rawGains[i + 1].coerceAtLeast(0.0)
                gainDb -= neighborBoost * CASCADE_COMPENSATION_FACTOR
            }
            gainDb = gainDb.coerceIn(-MAX_BAND_GAIN_DB, MAX_BAND_GAIN_DB)

            val band = bands[i]
            val w0 = 2.0 * PI * f0 / sampleRate
            val cosW0 = cos(w0)
            val sinW0 = sin(w0)
            val q = 1.41421356
            val alpha = sinW0 / (2.0 * q)
            val a = 10.0.pow(gainDb / 40.0)

            val a0Raw = 1.0 + alpha / a
            band.b0 = (1.0 + alpha * a) / a0Raw
            band.b1 = (-2.0 * cosW0) / a0Raw
            band.b2 = (1.0 - alpha * a) / a0Raw
            band.a1 = (-2.0 * cosW0) / a0Raw
            band.a2 = (1.0 - alpha / a) / a0Raw
        }
    }

    override fun isActive(): Boolean = isActive

    override fun queueInput(inputBuffer: ByteBuffer) {
        if (!inputBuffer.hasRemaining()) return
        val remaining = inputBuffer.remaining()

        if (outputBuffer.capacity() < remaining) {
            outputBuffer = ByteBuffer.allocateDirect(remaining).order(ByteOrder.nativeOrder())
        } else {
            outputBuffer.clear()
        }

        if (!isEnabled) {
            outputBuffer.put(inputBuffer)
            outputBuffer.flip()
            return
        }

        val preampFactor = 10.0.pow(preampDb.toDouble() / 20.0)
        val numChannels = channelCount

        while (inputBuffer.hasRemaining()) {
            if (numChannels == 2) {
                var sampleL = inputBuffer.short.toDouble() * preampFactor
                var sampleR = inputBuffer.short.toDouble() * preampFactor

                for (i in 0 until 16) {
                    val b = bands[i]
                    val outL = b.b0 * sampleL + b.b1 * b.x1L + b.b2 * b.x2L - b.a1 * b.y1L - b.a2 * b.y2L
                    b.x2L = b.x1L; b.x1L = sampleL; b.y2L = b.y1L; b.y1L = outL
                    sampleL = outL

                    val outR = b.b0 * sampleR + b.b1 * b.x1R + b.b2 * b.x2R - b.a1 * b.y1R - b.a2 * b.y2R
                    b.x2R = b.x1R; b.x1R = sampleR; b.y2R = b.y1R; b.y1R = outR
                    sampleR = outR
                }

                if (virtualizerFactor > 0.0f) {
                    val mid = (sampleL + sampleR) / 2.0
                    val side = (sampleL - sampleR) / 2.0
                    val widenedSide = side * (1.0 + virtualizerFactor.toDouble() * 1.2)
                    sampleL = mid + widenedSide
                    sampleR = mid - widenedSide
                }

                if (limiterEnabled) {
                    sampleL = softLimit(sampleL)
                    sampleR = softLimit(sampleR)
                }

                val finalL = Math.round(sampleL).toInt().coerceIn(-32768, 32767)
                val finalR = Math.round(sampleR).toInt().coerceIn(-32768, 32767)

                outputBuffer.putShort(finalL.toShort())
                outputBuffer.putShort(finalR.toShort())
            } else {
                var sampleM = inputBuffer.short.toDouble() * preampFactor

                for (i in 0 until 16) {
                    val b = bands[i]
                    val outM = b.b0 * sampleM + b.b1 * b.x1L + b.b2 * b.x2L - b.a1 * b.y1L - b.a2 * b.y2L
                    b.x2L = b.x1L; b.x1L = sampleM; b.y2L = b.y1L; b.y1L = outM
                    sampleM = outM
                }

                if (limiterEnabled) {
                    sampleM = softLimit(sampleM)
                }

                val finalM = Math.round(sampleM).toInt().coerceIn(-32768, 32767)
                outputBuffer.putShort(finalM.toShort())
            }
        }
        outputBuffer.flip()
    }

    private fun softLimit(sample: Double): Double {
        val maxVal = 32768.0
        val threshold = 27852.8
        val absSample = Math.abs(sample)

        if (absSample <= threshold) {
            return sample
        }

        val r = ((absSample - threshold) / (maxVal - threshold)).coerceIn(0.0, 1.0)
        val compressedAbs = threshold + (maxVal - threshold) * (r + (r * r) - (r * r * r))
        return if (sample < 0) -compressedAbs else compressedAbs
    }

    override fun getOutput(): ByteBuffer {
        val output = outputBuffer
        outputBuffer = AudioProcessor.EMPTY_BUFFER
        return output
    }

    override fun queueEndOfStream() {
        inputEnded = true
    }

    override fun isEnded(): Boolean = inputEnded && outputBuffer == AudioProcessor.EMPTY_BUFFER

    override fun flush() {
        outputBuffer = AudioProcessor.EMPTY_BUFFER
        inputEnded = false
        for (i in 0 until 16) {
            bands[i].flush()
        }
    }

    override fun reset() {
        flush()
        isActive = false
        activeProcessors.remove(this)
    }
}
