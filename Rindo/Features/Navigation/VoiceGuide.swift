import AVFoundation
import Foundation

/// AVSpeechSynthesizer.write() + AVAudioEngine による音声ナビゲーション案内
/// アプリ内オーディオとして再生するため、iOS の画面収録にも音声が含まれる
@MainActor
final class VoiceGuide {
    private let synthesizer = AVSpeechSynthesizer()
    private let audioEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let voice = AVSpeechSynthesisVoice(language: "ja-JP")

    /// 音声案内が有効か
    var isEnabled = true

    /// 再生中、または再生直後の待機中かどうか
    private(set) var isPlaying = false
    var isSpeaking: Bool { isPlaying || isCoolingDown }

    /// 再生完了後のクールダウン中フラグ
    private var isCoolingDown = false
    /// 再生完了後の待機時間（秒）
    var postSpeechDelay: TimeInterval = 1.0

    /// 発話済みマニューバ＋距離閾値の組み合わせを記録（重複防止）
    private var spokenKeys: Set<String> = []

    private var engineConfigured = false

    init() {
        audioEngine.attach(playerNode)
        configureAudioSession()
    }

    private func startCooldown() {
        isCoolingDown = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(postSpeechDelay))
            isCoolingDown = false
        }
    }

    /// 指定キーが発話済みかどうか
    func hasSpoken(key: String) -> Bool {
        spokenKeys.contains(key)
    }

    /// 音声案内をリクエスト（重複防止付き）
    func speak(_ text: String, key: String) {
        speakSegments([(text, 0)], key: key)
    }

    /// 2つのテキストを無音ポーズを挟んで連続再生
    func speakWithPause(_ first: String, pause: TimeInterval, _ second: String, key: String) {
        speakSegments([(first, pause), (second, 0)], key: key)
    }

    /// セグメント配列を順番に合成・再生（各セグメント後に指定秒数の無音を挿入）
    private func speakSegments(_ segments: [(text: String, pauseAfter: TimeInterval)], key: String) {
        guard isEnabled else { return }
        guard !spokenKeys.contains(key) else { return }
        spokenKeys.insert(key)

        stopPlayback()
        isPlaying = true

        let collector = BufferCollector()
        let totalSegments = segments.count
        var completedSegments = 0

        for segment in segments {
            let utterance = AVSpeechUtterance(string: segment.text)
            utterance.voice = voice
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.1
            utterance.pitchMultiplier = 1.0
            utterance.volume = 1.0

            synthesizer.write(utterance) { [weak self] buffer in
                guard let pcmBuffer = buffer as? AVAudioPCMBuffer else { return }

                if pcmBuffer.frameLength == 0 {
                    // このセグメントの合成完了
                    if segment.pauseAfter > 0, let format = collector.lastFormat {
                        collector.appendSilence(duration: segment.pauseAfter, format: format)
                    }
                    completedSegments += 1
                    if completedSegments == totalSegments {
                        let buffers = collector.drain()
                        Task { @MainActor [weak self] in
                            self?.playBuffers(buffers)
                        }
                    }
                    return
                }

                collector.append(pcmBuffer)
            }
        }
    }

    /// ルート変更時にスポーク履歴をリセット
    func reset() {
        spokenKeys.removeAll()
        isCoolingDown = false
        stopPlayback()
    }

    func stop() {
        stopPlayback()
    }

    // MARK: - Private

    private func playBuffers(_ buffers: [AVAudioPCMBuffer]) {
        guard let firstBuffer = buffers.first else {
            isPlaying = false
            return
        }

        let format = firstBuffer.format

        if !engineConfigured {
            audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: format)
            engineConfigured = true
        }

        if !audioEngine.isRunning {
            try? audioEngine.start()
        }

        playerNode.stop()

        for (i, buffer) in buffers.enumerated() {
            if i == buffers.count - 1 {
                // 最後のバッファ再生完了でクールダウン開始
                playerNode.scheduleBuffer(buffer) { [weak self] in
                    Task { @MainActor in
                        self?.isPlaying = false
                        self?.startCooldown()
                    }
                }
            } else {
                playerNode.scheduleBuffer(buffer)
            }
        }

        playerNode.play()
    }

    private func stopPlayback() {
        synthesizer.stopSpeaking(at: .immediate)
        if playerNode.isPlaying {
            playerNode.stop()
        }
        isPlaying = false
    }

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
            try session.setActive(true)
        } catch {
            // 音声セッション設定失敗は致命的ではない
        }
    }
}

// MARK: - Thread-safe buffer collector

/// synthesizer.write() のコールバックはバックグラウンドスレッドから呼ばれるため
/// スレッドセーフなバッファ収集が必要
private final class BufferCollector: @unchecked Sendable {
    private var buffers: [AVAudioPCMBuffer] = []
    private let lock = NSLock()
    private(set) var lastFormat: AVAudioFormat?

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        buffers.append(buffer)
        lastFormat = buffer.format
        lock.unlock()
    }

    func appendSilence(duration: TimeInterval, format: AVAudioFormat) {
        let frameCount = AVAudioFrameCount(format.sampleRate * duration)
        guard let silent = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
        silent.frameLength = frameCount
        // バッファは0初期化されているため無音
        lock.lock()
        buffers.append(silent)
        lock.unlock()
    }

    func drain() -> [AVAudioPCMBuffer] {
        lock.lock()
        let result = buffers
        buffers = []
        lock.unlock()
        return result
    }
}
