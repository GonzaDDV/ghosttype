import AVFoundation

class AudioCaptureManager {
    private let engine = AVAudioEngine()
    var onAudioData: ((Data) -> Void)?
    var onError: ((Error) -> Void)?

    private(set) var isCapturing = false

    func startCapturing() throws {
        guard !isCapturing else { return }

        let inputNode = engine.inputNode
        let recordingFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16000,
            channels: 1,
            interleaved: true
        )!

        inputNode.installTap(
            onBus: 0,
            bufferSize: 4096,
            format: recordingFormat
        ) { [weak self] buffer, _ in
            guard let channelData = buffer.int16ChannelData else { return }
            let frameLength = Int(buffer.frameLength)
            let data = Data(bytes: channelData[0], count: frameLength * 2)
            self?.onAudioData?(data)
        }

        engine.prepare()
        try engine.start()
        isCapturing = true
    }

    func stopCapturing() {
        guard isCapturing else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isCapturing = false
    }
}
