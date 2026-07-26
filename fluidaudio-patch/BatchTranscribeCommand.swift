#if os(macOS)
import FluidAudio
import Foundation

/// `batch-transcribe <audio> --output <json> [--max-speech-s 22]`
/// 长音频中文转写：VAD 按静音切成 ≤max-speech 秒的片段 → Paraformer(模型只加载一次)逐段转写
/// → 输出带时间戳的 JSON {"segments":[{"start":s,"end":s,"text":"…"}]}，供上层按时间与说话人分离对齐。
enum BatchTranscribeCommand {
    private static let logger = AppLogger(category: "BatchTranscribe")
    private static let hardMaxSamples = 470_000  // Paraformer 单次上限约 30s(480000)，留余量

    static func run(arguments: [String]) async {
        var audioPath: String?
        var outputPath: String?
        var maxSpeech: Double = 22.0
        var i = 0
        while i < arguments.count {
            switch arguments[i] {
            case "--output", "-o":
                if i + 1 < arguments.count { outputPath = arguments[i + 1]; i += 1 }
            case "--max-speech-s":
                if i + 1 < arguments.count { maxSpeech = Double(arguments[i + 1]) ?? 22.0; i += 1 }
            case "--help", "-h":
                print("Usage: fluidaudio batch-transcribe <audio> --output <json> [--max-speech-s 22]")
                return
            default:
                if audioPath == nil { audioPath = arguments[i] }
            }
            i += 1
        }
        guard let audioPath else { logger.error("No audio file specified"); exit(1) }

        do {
            let sr = VadManager.sampleRate  // 16000，与 Paraformer 一致
            let samples = try AudioConverter(sampleRate: Double(sr)).resampleAudioFile(path: audioPath)

            // 1) VAD 切段
            let vad = try await VadManager(
                config: VadConfig(
                    defaultThreshold: VadConfig.default.defaultThreshold,
                    debugMode: false,
                    computeUnits: .cpuAndNeuralEngine))
            let vadResults = try await vad.process(samples)
            let segConfig = VadSegmentationConfig(maxSpeechDuration: maxSpeech)
            let segments = await vad.segmentSpeech(
                from: vadResults, totalSamples: samples.count, config: segConfig)
            logger.info("VAD 切出 \(segments.count) 段语音")

            // 2) Paraformer 逐段转写（模型只加载一次）
            let asr = try await ParaformerManager.load()
            var out: [[String: Any]] = []
            for (idx, seg) in segments.enumerated() {
                var s = max(0, seg.startSample(sampleRate: sr))
                var e = min(samples.count, seg.endSample(sampleRate: sr))
                if e <= s { continue }
                if e - s > hardMaxSamples { e = s + hardMaxSamples }  // 安全兜底
                let text = (try? await asr.transcribe(audio: Array(samples[s..<e]))) ?? ""
                let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty {
                    out.append(["start": seg.startTime, "end": seg.endTime, "text": t])
                }
                // 逐段进度输出到 stderr，供上层驱动进度条
                FileHandle.standardError.write(Data("PROGRESS \(idx + 1)/\(segments.count)\n".utf8))
            }

            let payload: [String: Any] = ["segments": out]
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted])
            if let outputPath {
                try data.write(to: URL(fileURLWithPath: outputPath))
                logger.info("已写出 \(out.count) 段转写 → \(outputPath)")
            } else {
                print(String(data: data, encoding: .utf8) ?? "")
            }
        } catch {
            logger.error("batch-transcribe failed: \(error)")
            exit(1)
        }
    }
}
#endif
