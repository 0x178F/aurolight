public struct LightFrameRenderer: Sendable {
    public struct Input: Sendable {
        public var layout: LEDLayout
        public var color: ColorSettings
        public var effects: EffectSettings
        public var samples: [RGB]
        public var sceneCut: Bool
        public var time: Double
        public var audio: AudioLevels
        public var whiteBalance: WhiteBalance
        /// Shown on every LED instead of the mode, while the white balance is being matched.
        public var testColor: RGB?

        public init(
            layout: LEDLayout, color: ColorSettings, effects: EffectSettings, samples: [RGB] = [],
            sceneCut: Bool = false, time: Double = 0, audio: AudioLevels = .silent,
            whiteBalance: WhiteBalance = .neutral, testColor: RGB? = nil
        ) {
            self.layout = layout
            self.color = color
            self.effects = effects
            self.samples = samples
            self.sceneCut = sceneCut
            self.time = time
            self.audio = audio
            self.whiteBalance = whiteBalance
            self.testColor = testColor
        }
    }

    public struct Frame: Sendable {
        public let bytes: [UInt8]
        public let preview: [RGB]
    }

    private var processor = ColorProcessor()

    public init() {}

    public mutating func render(_ input: Input) -> Frame? {
        let mode = input.effects.mode
        var settings = input.color
        let placed: [RGB]
        if let testColor = input.testColor {
            placed = Array(repeating: testColor, count: input.layout.placedCount)
            settings.saturation = 1
            settings.blackLevel = 0
        } else if mode == .screen {
            guard input.samples.count == input.layout.placedCount else { return nil }
            placed = input.samples
        } else {
            let effect = EffectRenderer.colors(
                for: input.effects, layout: input.layout, time: input.time, audio: input.audio)
            placed = effect ?? []
            settings.saturation = 1
            settings.blackLevel = 0
        }
        guard !placed.isEmpty else { return nil }
        processor.settings = settings
        processor.gains = input.whiteBalance.gains

        let smooth = input.testColor == nil && ((mode == .screen && !input.sceneCut) || mode == .solid)
        let bytes = processor.process(placed, smooth: smooth)
        return Frame(bytes: bytes, preview: processor.smoothed)
    }
}
