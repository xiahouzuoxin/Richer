import AudioToolbox
import AVFoundation
import CoreAudio
import Foundation
import Observation
import Speech

enum SpeechRecognitionError: LocalizedError {
    case microphoneDenied
    case speechRecognitionDenied
    case recognizerUnavailable(String)
    case audioEngine(String)

    var errorDescription: String? {
        switch self {
        case .microphoneDenied:
            String(localized: "Microphone permission denied. Enable it in System Settings → Privacy & Security → Microphone.")
        case .speechRecognitionDenied:
            String(localized: "Speech Recognition permission denied. Enable it in System Settings → Privacy & Security → Speech Recognition.")
        case .recognizerUnavailable(let locale):
            String(localized: "On-device speech recognition isn't available for \(locale). Pick a different language.")
        case .audioEngine(let msg):
            "Audio engine error: \(msg)"
        }
    }
}

/// `@Observable @MainActor` wrapper around `SFSpeechRecognizer` + `AVAudioEngine`.
/// Drives live dictation: click to start, click to stop. Partial recognition results
/// stream out via the `onPartial` callback while recording is active.
@Observable
@MainActor
final class SpeechRecognizer {
    private(set) var isRecording: Bool = false
    private(set) var partial: String = ""
    private(set) var lastError: String?

    private var recognizer: SFSpeechRecognizer?
    private var audioEngine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var partialHandler: ((String) -> Void)?
    private var finalHandler: ((String) -> Void)?

    /// Start dictating in `locale`. `onPartial` fires repeatedly while recording with
    /// the latest best-effort transcription; `onFinal` fires once when recording stops
    /// (with the final transcription) or when the recognizer signals `isFinal`.
    ///
    /// If `deviceUID` is non-nil, route audio through that specific input device
    /// (matched via CoreAudio). If nil — or if the requested device is no longer
    /// present — fall back to whatever the OS has set as the default input.
    func start(
        locale: String,
        deviceUID: String? = nil,
        onPartial: @escaping (String) -> Void,
        onFinal: @escaping (String) -> Void
    ) {
        stop() // tear down any prior session
        lastError = nil
        partial = ""

        let nsLocale = Locale(identifier: locale)
        guard let recognizer = SFSpeechRecognizer(locale: nsLocale), recognizer.isAvailable else {
            lastError = SpeechRecognitionError.recognizerUnavailable(locale).errorDescription
            return
        }
        self.recognizer = recognizer

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        self.request = request

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode

        // Pin the engine to a specific input device when the user picked one. Silently
        // falls back to the OS default if the device went away (e.g., USB unplugged).
        if let deviceUID,
           let audioDeviceID = AudioDeviceList.audioDeviceID(for: deviceUID),
           let audioUnit = inputNode.audioUnit {
            var id = audioDeviceID
            let result = AudioUnitSetProperty(
                audioUnit,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &id,
                UInt32(MemoryLayout<AudioDeviceID>.size)
            )
            if result != noErr {
                NSLog("[Richer] failed to pin AVAudioEngine input to device \(deviceUID) (OSStatus \(result)); using default")
            }
        }

        let format = inputNode.outputFormat(forBus: 0)
        // 1024 frames @ 44.1kHz ≈ 23ms per buffer — plenty of granularity for partials.
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak request] buffer, _ in
            request?.append(buffer)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            lastError = SpeechRecognitionError.audioEngine(error.localizedDescription).errorDescription
            inputNode.removeTap(onBus: 0)
            return
        }
        self.audioEngine = engine

        self.partialHandler = onPartial
        self.finalHandler = onFinal
        isRecording = true

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self, self.isRecording else { return } // ignore late callbacks after manual stop()
                if let result {
                    let text = result.bestTranscription.formattedString
                    self.partial = text
                    self.partialHandler?(text)
                    if result.isFinal {
                        self.finalize(with: text)
                    }
                } else if let error {
                    let nsError = error as NSError
                    // SFSpeechRecognizer fires `kAFAssistantErrorDomain 1110` ("no speech detected")
                    // when the user stops without saying anything. Treat as a silent abort, not an error.
                    if nsError.domain != "kAFAssistantErrorDomain" || nsError.code != 1110 {
                        self.lastError = nsError.localizedDescription
                    }
                    self.finalize(with: self.partial)
                }
            }
        }
    }

    /// Stop dictating *synchronously*. Tears the audio engine down and immediately
    /// fires `onFinal` with the last partial seen. Subsequent recognizer callbacks
    /// are dropped via the `isRecording` guard in the task closure. This is what
    /// makes "click mic to stop" predictable — no async final callback later
    /// clobbers the user's input.
    func stop() {
        guard isRecording else { return }
        let lastPartial = partial
        request?.endAudio()
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        task?.cancel()
        finalize(with: lastPartial)
    }

    /// Internal: tear down recording state and notify the consumer once.
    /// `isRecording` is set to false FIRST so any in-flight task callback exits early.
    private func finalize(with text: String) {
        isRecording = false
        task = nil
        request = nil
        audioEngine = nil
        finalHandler?(text)
        partialHandler = nil
        finalHandler = nil
        partial = ""
    }
}
