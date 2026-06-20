package com.ryanheise.just_audio

import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.audio.AudioProcessor.AudioFormat
import androidx.media3.common.audio.AudioProcessor.UnhandledAudioFormatException
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.PI

class AdvancedVocalRemoverProcessor : AudioProcessor {
    companion object {
        val instance = AdvancedVocalRemoverProcessor()
    }

    private var isActive = false
    
    // Thread safety constraint for cross-thread volume adjustments
    @Volatile private var vocalReductionFactor = 0.0f
    private var outputBuffer: ByteBuffer = AudioProcessor.EMPTY_BUFFER
    
    var onMonoTrackEncountered: (() -> Unit)? = null

    // Biquad High-Pass Filter coefficients (Cutoff: ~250Hz, Q: 0.7071)
    private var b0 = 0.0; private var b1 = 0.0; private var b2 = 0.0
    private var a1 = 0.0; private var a2 = 0.0

    // High-pass filter memory buffers for delay tracking
    private var x1L = 0.0; private var x2L = 0.0; private var y1L = 0.0; private var y2L = 0.0
    private var x1R = 0.0; private var x2R = 0.0; private var y1R = 0.0; private var y2R = 0.0

    fun setVocalReduction(factor: Float) {
        this.vocalReductionFactor = factor.coerceIn(0.0f, 1.0f)
    }

    override fun configure(inputAudioFormat: AudioFormat): AudioFormat {
        // Media3 Lifecycle Constraint: Explicitly throw contract exception on non-stereo files
        if (inputAudioFormat.channelCount != 2) {
            isActive = false
            onMonoTrackEncountered?.invoke()
            throw UnhandledAudioFormatException(inputAudioFormat)
        }
        
        isActive = true
        setupHighPassFilter(cutoffFreq = 250.0, sampleRate = inputAudioFormat.sampleRate.toDouble())
        return inputAudioFormat
    }

    private fun setupHighPassFilter(cutoffFreq: Double, sampleRate: Double) {
        val w0 = 2.0 * PI * cutoffFreq / sampleRate
        val sinW0 = Math.sin(w0)
        val cosW0 = Math.cos(w0)
        
        // Exact Q factor for a flat passband Butterworth filter response
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
        // Constraint: Prevent allocation thrashing; safely resize buffer only when expanding capacity
        if (outputBuffer.capacity() < remaining) {
            outputBuffer = ByteBuffer.allocateDirect(remaining).order(ByteOrder.nativeOrder())
        } else {
            outputBuffer.clear()
        }

        // Processing Loop: Raw 16-bit PCM Linear Data Interleaved
        while (inputBuffer.hasRemaining()) {
            val leftSample = inputBuffer.short.toDouble()
            val rightSample = inputBuffer.short.toDouble()

            // Step 1: Run through High-Pass Filter to isolate vocal bands
            val hpLeft = b0 * leftSample + b1 * x1L + b2 * x2L - a1 * y1L - a2 * y2L
            x2L = x1L; x1L = leftSample; y2L = y1L; y1L = hpLeft

            val hpRight = b0 * rightSample + b1 * x1R + b2 * x2R - a1 * y1R - a2 * y2R
            x2R = x1R; x1R = rightSample; y2R = y1R; y1R = hpRight

            // Step 2: Capture lower bass frequencies
            val bassLeft = leftSample - hpLeft
            val bassRight = rightSample - hpRight

            // Step 3: Compute Mid-Side differences on high-pass frequencies
            val midHP = (hpLeft + hpRight) / 2.0
            val sideHP = (hpLeft - hpRight) / 2.0

            val reduction = 1.0f - vocalReductionFactor
            val newHpLeft = sideHP + (midHP * reduction)
            val newHpRight = -sideHP + (midHP * reduction)

            // Step 4: Re-integrate Bass
            val finalLeftFloat = newHpLeft + bassLeft
            val finalRightFloat = newHpRight + bassRight

            // Step 5: Process through a mathematically perfect Cubic Soft-Knee Limiter
            fun softLimit(sample: Double): Double {
                val maxVal = 32768.0
                val threshold = 27852.8 // 85% of full 16-bit scale (Unity gain below this point)
                val absSample = Math.abs(sample)
                
                if (absSample <= threshold) {
                    return sample // Pass through at absolute 1:1 unity gain
                }
                
                // Bounded normalized remainder to guarantee stability against extreme overshoots
                val r = ((absSample - threshold) / (maxVal - threshold)).coerceIn(0.0, 1.0)
                
                // Cubic Hermite spline curve: f'(0)=1 (smooth knee), f'(1)=0 (flat ceiling), f(1)=1 (full headroom)
                val compressedAbs = threshold + (maxVal - threshold) * (r + (r * r) - (r * r * r))
                return if (sample < 0) -compressedAbs else compressedAbs
            }

            // Polish Constraint: Use Math.round() to eliminate raw .toInt() truncation noise bias
            var finalLeft = Math.round(softLimit(finalLeftFloat)).toInt()
            var finalRight = Math.round(softLimit(finalRightFloat)).toInt()

            // Final defensive guardrail
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

    override fun queueEndOfStream() {}
    override fun isEnded(): Boolean = !isActive && outputBuffer == AudioProcessor.EMPTY_BUFFER
    
    // Lifecycle Constraint: Delay-lines must be flushed to prevent audio pops on track skips/seeks
    override fun flush() {
        outputBuffer = AudioProcessor.EMPTY_BUFFER
        x1L = 0.0; x2L = 0.0; y1L = 0.0; y2L = 0.0
        x1R = 0.0; x2R = 0.0; y1R = 0.0; y2R = 0.0
    }

    override fun reset() {
        flush()
        isActive = false
    }
}
