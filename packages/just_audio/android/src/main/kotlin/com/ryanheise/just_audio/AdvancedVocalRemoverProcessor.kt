package com.ryanheise.just_audio

import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.audio.AudioProcessor.AudioFormat
import androidx.media3.common.audio.AudioProcessor.UnhandledAudioFormatException
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.PI

class AdvancedVocalRemoverProcessor : AudioProcessor {
    companion object {
        private val activeProcessors = java.util.concurrent.CopyOnWriteArrayList<AdvancedVocalRemoverProcessor>()

        var onMonoTrackEncountered: (() -> Unit)? = null

        fun broadcastVocalReduction(factor: Float) {
            for (proc in activeProcessors) {
                proc.setVocalReduction(factor)
            }
        }
    }

    private var isActive = false
    @Volatile private var inputEnded = false
    private var outputBuffer: ByteBuffer = AudioProcessor.EMPTY_BUFFER

    @Volatile var vocalReductionFactor = 0.0f
    var onMonoTrackEncountered: (() -> Unit)? = null

    private var b0 = 0.0; private var b1 = 0.0; private var b2 = 0.0
    private var a1 = 0.0; private var a2 = 0.0

    private var x1L = 0.0; private var x2L = 0.0; private var y1L = 0.0; private var y2L = 0.0
    private var x1R = 0.0; private var x2R = 0.0; private var y1R = 0.0; private var y2R = 0.0

    private var currentReductionFactor = 0.0
    private val RAMP_TIME_SECONDS = 0.02
    private var rampStepPerSample = 0.0

    fun setVocalReduction(factor: Float) {
        this.vocalReductionFactor = factor.coerceIn(0.0f, 1.0f)
    }

    override fun configure(inputAudioFormat: AudioFormat): AudioFormat {
        if (inputAudioFormat.channelCount != 2) {
            isActive = false
            onMonoTrackEncountered?.invoke()
            throw UnhandledAudioFormatException(inputAudioFormat)
        }

        isActive = true
        inputEnded = false
        val sampleRateDouble = inputAudioFormat.sampleRate.toDouble()
        setupHighPassFilter(cutoffFreq = 90.0, sampleRate = sampleRateDouble)
        rampStepPerSample = 1.0 / (RAMP_TIME_SECONDS * sampleRateDouble)
        this.onMonoTrackEncountered = Companion.onMonoTrackEncountered
        activeProcessors.addIfAbsent(this)
        return inputAudioFormat
    }

    private fun setupHighPassFilter(cutoffFreq: Double, sampleRate: Double) {
        val w0 = 2.0 * PI * cutoffFreq / sampleRate
        val sinW0 = Math.sin(w0)
        val cosW0 = Math.cos(w0)

        val q = 0.70710678118
        val alpha = sinW0 / (2.0 * q)
        val a0 = 1.0 + alpha

        b0 = ((1.0 + cosW0) / 2.0) / a0
        b1 = -(1.0 + cosW0) / a0
        b2 = ((1.0 + cosW0) / 2.0) / a0
        a1 = (-2.0 * cosW0) / a0
        a2 = (1.0 - alpha) / a0
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

        while (inputBuffer.hasRemaining()) {
            val target = vocalReductionFactor.toDouble()
            if (currentReductionFactor < target) {
                currentReductionFactor = (currentReductionFactor + rampStepPerSample).coerceAtMost(target)
            } else if (currentReductionFactor > target) {
                currentReductionFactor = (currentReductionFactor - rampStepPerSample).coerceAtLeast(target)
            }

            val leftSample = inputBuffer.short.toDouble()
            val rightSample = inputBuffer.short.toDouble()

            val hpLeft = b0 * leftSample + b1 * x1L + b2 * x2L - a1 * y1L - a2 * y2L
            x2L = x1L; x1L = leftSample; y2L = y1L; y1L = hpLeft

            val hpRight = b0 * rightSample + b1 * x1R + b2 * x2R - a1 * y1R - a2 * y2R
            x2R = x1R; x1R = rightSample; y2R = y1R; y1R = hpRight

            val bassLeft = leftSample - hpLeft
            val bassRight = rightSample - hpRight

            val midHP = (hpLeft + hpRight) / 2.0
            val sideHP = (hpLeft - hpRight) / 2.0

            val reduction = 1.0 - currentReductionFactor
            val sideReduction = 1.0 - (currentReductionFactor * 0.5)

            val newHpLeft = (sideHP * sideReduction) + (midHP * reduction)
            val newHpRight = -(sideHP * sideReduction) + (midHP * reduction)

            val finalLeftFloat = newHpLeft + bassLeft
            val finalRightFloat = newHpRight + bassRight

            fun softLimit(sample: Double): Double {
                val maxVal = 32768.0
                val threshold = 27852.8
                val absSample = Math.abs(sample)

                if (absSample <= threshold) return sample

                val r = ((absSample - threshold) / (maxVal - threshold)).coerceIn(0.0, 1.0)
                val compressedAbs = threshold + (maxVal - threshold) * (r + (r * r) - (r * r * r))
                return if (sample < 0) -compressedAbs else compressedAbs
            }

            var finalLeft = Math.round(softLimit(finalLeftFloat)).toInt()
            var finalRight = Math.round(softLimit(finalRightFloat)).toInt()

            finalLeft = finalLeft.coerceIn(-32768, 32767)
            finalRight = finalRight.coerceIn(-32768, 32767)

            outputBuffer.putShort(finalLeft.toShort())
            outputBuffer.putShort(finalRight.toShort())
        }

        outputBuffer.flip()
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
        x1L = 0.0; x2L = 0.0; y1L = 0.0; y2L = 0.0
        x1R = 0.0; x2R = 0.0; y1R = 0.0; y2R = 0.0
        currentReductionFactor = 0.0
        inputEnded = false
    }

    override fun reset() {
        flush()
        isActive = false
        activeProcessors.remove(this)
    }
}
