import Foundation

public enum VoiceActivityObservation: Equatable, Sendable {
    case calibrating
    case silence
    case speechStarted
    case speechContinues
    case speechSilence
    case speechEnded
}

/// Pure RMS speech gate. The device adapter supplies one RMS value per audio frame.
public struct VoiceActivityDetector: Sendable {
    public struct Configuration: Sendable, Equatable {
        public var calibrationSampleCount: Int
        public var minimumSpeechLevel: Float
        public var speechToNoiseRatio: Float
        public var consecutiveSpeechFrames: Int
        public var trailingSilenceFrames: Int
        public var noiseAdaptationRate: Float

        public init(
            calibrationSampleCount: Int = 8,
            minimumSpeechLevel: Float = 0.0025,
            speechToNoiseRatio: Float = 2.2,
            consecutiveSpeechFrames: Int = 2,
            trailingSilenceFrames: Int = 10,
            noiseAdaptationRate: Float = 0.95
        ) {
            self.calibrationSampleCount = max(1, calibrationSampleCount)
            self.minimumSpeechLevel = max(0, minimumSpeechLevel)
            self.speechToNoiseRatio = max(1, speechToNoiseRatio)
            self.consecutiveSpeechFrames = max(1, consecutiveSpeechFrames)
            self.trailingSilenceFrames = max(1, trailingSilenceFrames)
            self.noiseAdaptationRate = min(max(0, noiseAdaptationRate), 1)
        }
    }

    public private(set) var configuration: Configuration
    private var calibrationSamples: [Float] = []
    private var noiseFloor: Float = 0
    private var consecutiveSpeechFrameCount = 0
    private var trailingSilenceFrameCount = 0
    private var speechActive = false

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    /// Compatibility convenience that reports only the beginning of speech.
    public mutating func observe(rmsLevel: Float) -> Bool {
        observeActivity(rmsLevel: rmsLevel) == .speechStarted
    }

    /// Reports whether this frame should open, continue, or close an ASR input gate.
    public mutating func observeActivity(rmsLevel: Float) -> VoiceActivityObservation {
        let level = max(0, rmsLevel)
        if calibrationSamples.count < configuration.calibrationSampleCount {
            calibrationSamples.append(level)
            if calibrationSamples.count == configuration.calibrationSampleCount {
                noiseFloor = max(calibrationSamples.reduce(0, +) / Float(calibrationSamples.count), 0.0001)
            }
            return .calibrating
        }

        let threshold = max(configuration.minimumSpeechLevel, noiseFloor * configuration.speechToNoiseRatio)
        if level >= threshold {
            trailingSilenceFrameCount = 0
            consecutiveSpeechFrameCount += 1
            if speechActive {
                consecutiveSpeechFrameCount = 0
                return .speechContinues
            }
            guard consecutiveSpeechFrameCount >= configuration.consecutiveSpeechFrames else { return .silence }
            speechActive = true
            consecutiveSpeechFrameCount = 0
            return .speechStarted
        }

        consecutiveSpeechFrameCount = 0
        guard speechActive else {
            noiseFloor = (noiseFloor * configuration.noiseAdaptationRate) + (level * (1 - configuration.noiseAdaptationRate))
            return .silence
        }

        trailingSilenceFrameCount += 1
        guard trailingSilenceFrameCount >= configuration.trailingSilenceFrames else { return .speechSilence }
        speechActive = false
        trailingSilenceFrameCount = 0
        return .speechEnded
    }
}
