import AVFoundation
import Foundation

/// AVSpeechSynthesizer による音声ナビゲーション案内
@MainActor
final class VoiceGuide {
    private let synthesizer = AVSpeechSynthesizer()
    private let voice = AVSpeechSynthesisVoice(language: "ja-JP")

    /// 音声案内が有効か
    var isEnabled = true

    /// 発話中、または発話直後の待機中かどうか
    var isSpeaking: Bool { synthesizer.isSpeaking || isCoolingDown }

    /// 発話完了後のクールダウン中フラグ
    private var isCoolingDown = false
    /// 発話完了後の待機時間（秒）
    var postSpeechDelay: TimeInterval = 1.0

    /// 発話済みマニューバ＋距離閾値の組み合わせを記録（重複防止）
    private var spokenKeys: Set<String> = []

    private let delegate = VoiceGuideDelegate()

    init() {
        synthesizer.delegate = delegate
        delegate.onFinish = { [weak self] in
            self?.startCooldown()
        }
        configureAudioSession()
    }

    private func startCooldown() {
        isCoolingDown = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(postSpeechDelay))
            isCoolingDown = false
        }
    }

    /// 音声案内をリクエスト（重複防止付き）
    /// - Parameters:
    ///   - text: 発話テキスト
    ///   - key: 重複防止用のユニークキー（例: "maneuver_3_200m"）
    func speak(_ text: String, key: String) {
        guard isEnabled else { return }
        guard !spokenKeys.contains(key) else { return }
        spokenKeys.insert(key)

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.1
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0

        // 前の発話をキャンセルして即座に次を再生
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .word)
        }
        synthesizer.speak(utterance)
    }

    /// ルート変更時にスポーク履歴をリセット
    func reset() {
        spokenKeys.removeAll()
        isCoolingDown = false
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }

    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            // .playback: バックグラウンドでも音声が出る
            // .duckOthers: BGM の音量を一時的に下げる
            try session.setCategory(.playback, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
            try session.setActive(true)
        } catch {
            // 音声セッション設定失敗は致命的ではない
        }
    }
}

// MARK: - Delegate

private class VoiceGuideDelegate: NSObject, AVSpeechSynthesizerDelegate {
    var onFinish: (() -> Void)?

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            onFinish?()
        }
    }
}
