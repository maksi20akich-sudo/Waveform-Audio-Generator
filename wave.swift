// wave.swift
import Foundation

class Envelope {
    var attack, decay, sustain, release: Double
    init(attack: Double, decay: Double, sustain: Double, release: Double) {
        self.attack = attack; self.decay = decay; self.sustain = sustain; self.release = release
    }
}

class WaveGenerator {
    var freq = 440.0
    var amp = 0.8
    var duration = 2.0
    var sampleRate = 44100
    var waveType = "sine"
    var stereo = false
    var envelope: Envelope?
    var sweepStart: Double?
    var sweepEnd: Double?
    private var samples: [[Int16]] = []

    private func valueAt(_ t: Double) -> Double {
        var f = freq
        if let start = sweepStart, let end = sweepEnd {
            f = start + (end - start) * (t / duration)
        }
        let phase = 2 * Double.pi * f * t
        var val: Double
        switch waveType {
        case "sine": val = sin(phase)
        case "square": val = sin(phase) >= 0 ? 1 : -1
        case "sawtooth": val = 2 * (phase / (2 * Double.pi) - floor(phase / (2 * Double.pi) + 0.5))
        case "triangle": val = 2 * abs(2 * (phase / (2 * Double.pi) - floor(phase / (2 * Double.pi) + 0.5))) - 1
        case "noise": val = Double.random(in: -1...1)
        default: val = 0
        }
        if let env = envelope {
            val *= envelopeValue(t)
        }
        return val
    }

    private func envelopeValue(_ t: Double) -> Double {
        guard let e = envelope else { return 1 }
        if t < e.attack { return t / (e.attack > 0 ? e.attack : 1) }
        var t2 = t - e.attack
        if t2 < e.decay { return 1 - (1 - e.sustain) * (t2 / (e.decay > 0 ? e.decay : 1)) }
        t2 -= e.decay
        let sustainDur = duration - e.attack - e.decay - e.release
        if sustainDur > 0 && t2 < sustainDur { return e.sustain }
        t2 -= sustainDur
        if t2 < e.release { return e.sustain * (1 - t2 / (e.release > 0 ? e.release : 1)) }
        return 0
    }

    func generate() {
        let numSamples = Int(duration * Double(sampleRate))
        let channels = stereo ? 2 : 1
        samples = Array(repeating: [], count: channels)
        for i in 0..<numSamples {
            let t = Double(i) / Double(sampleRate)
            let val = valueAt(t)
            let sample = Int16(amp * val * 32767)
            for ch in 0..<channels {
                samples[ch].append(sample)
            }
        }
    }

    func saveWAV(_ filename: String) throws {
        let channels = samples.count
        let numSamples = samples[0].count
        let dataSize = numSamples * 2 * channels
        let byteRate = sampleRate * 2 * channels
        var header = Data()
        // RIFF
        header.append("RIFF".data(using: .utf8)!)
        header.append(withUnsafeBytes(of: UInt32(36 + dataSize).littleEndian) { Data($0) })
        header.append("WAVE".data(using: .utf8)!)
        header.append("fmt ".data(using: .utf8)!)
        header.append(withUnsafeBytes(of: UInt32(16).littleEndian) { Data($0) })
        header.append(withUnsafeBytes(of: UInt16(1).littleEndian) { Data($0) })
        header.append(withUnsafeBytes(of: UInt16(channels).littleEndian) { Data($0) })
        header.append(withUnsafeBytes(of: UInt32(sampleRate).littleEndian) { Data($0) })
        header.append(withUnsafeBytes(of: UInt32(byteRate).littleEndian) { Data($0) })
        header.append(withUnsafeBytes(of: UInt16(2 * channels).littleEndian) { Data($0) })
        header.append(withUnsafeBytes(of: UInt16(16).littleEndian) { Data($0) })
        header.append("data".data(using: .utf8)!)
        header.append(withUnsafeBytes(of: UInt32(dataSize).littleEndian) { Data($0) })
        // samples
        var samplesData = Data()
        for i in 0..<numSamples {
            for ch in 0..<channels {
                samplesData.append(withUnsafeBytes(of: samples[ch][i].littleEndian) { Data($0) })
            }
        }
        let combined = header + samplesData
        try combined.write(to: URL(fileURLWithPath: filename))
    }

    func play(_ filename: String) {
        #if os(macOS)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
        process.arguments = [filename]
        try? process.run()
        #elseif os(Linux)
        let players = ["ffplay", "aplay", "mpg123"]
        for p in players {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/which")
            proc.arguments = [p]
            let pipe = Pipe()
            proc.standardOutput = pipe
            try? proc.run()
            proc.waitUntilExit()
            if proc.terminationStatus == 0 {
                let play = Process()
                play.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                play.arguments = [p, filename]
                try? play.run()
                return
            }
        }
        print("No audio player found.")
        #elseif os(Windows)
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "C:/Windows/System32/cmd.exe")
        proc.arguments = ["/c", "start", filename]
        try? proc.run()
        #endif
    }
}

func interactive() {
    print("=== Waveform Audio Generator ===")
    let types = ["sine", "square", "sawtooth", "triangle", "noise"]
    print("Type (\(types.joined(separator: "/"))) [sine]: ", terminator: "")
    var wtype = readLine() ?? "sine"
    if !types.contains(wtype) { wtype = "sine" }
    print("Frequency (Hz) [440]: ", terminator: "")
    let freq = Double(readLine() ?? "") ?? 440
    print("Amplitude (0.0-1.0) [0.8]: ", terminator: "")
    let amp = Double(readLine() ?? "") ?? 0.8
    print("Duration (s) [2.0]: ", terminator: "")
    let dur = Double(readLine() ?? "") ?? 2.0
    print("Sample rate [44100]: ", terminator: "")
    let rate = Int(readLine() ?? "") ?? 44100
    print("Stereo? (y/n) [n]: ", terminator: "")
    let stereo = (readLine() ?? "").lowercased() == "y"
    print("ADSR? (Attack Decay Sustain Release) [none]: ", terminator: "")
    let adsrStr = readLine() ?? ""
    var env: Envelope? = nil
    if adsrStr != "" && adsrStr != "none" {
        let parts = adsrStr.split(separator: " ").compactMap { Double($0) }
        if parts.count == 4 { env = Envelope(attack: parts[0], decay: parts[1], sustain: parts[2], release: parts[3]) }
    }
    print("Output file [output.wav]: ", terminator: "")
    var fname = readLine() ?? "output.wav"
    if !fname.hasSuffix(".wav") { fname += ".wav" }
    let gen = WaveGenerator()
    gen.freq = freq; gen.amp = amp; gen.duration = dur; gen.sampleRate = rate
    gen.waveType = wtype; gen.stereo = stereo; gen.envelope = env
    gen.generate()
    do { try gen.saveWAV(fname); print("Saved to \(fname)") }
    catch { print("Error saving: \(error)") }
    print("Play? (y/n) [y]: ", terminator: "")
    if (readLine() ?? "").lowercased() != "n" { gen.play(fname) }
}

func cli() {
    let args = CommandLine.arguments.dropFirst()
    var params: [String: String] = [:]
    var i = 0
    while i < args.count {
        let arg = args[i]
        if arg.hasPrefix("-") || arg.hasPrefix("--") {
            let key = arg.replacingOccurrences(of: "-", with: "")
            if i+1 < args.count && !args[i+1].hasPrefix("-") {
                params[key] = args[i+1]
                i += 2
            } else {
                params[key] = "true"
                i += 1
            }
        } else { i += 1 }
    }
    let gen = WaveGenerator()
    if let f = params["f"] ?? params["freq"] { gen.freq = Double(f) ?? 440 }
    if let t = params["t"] ?? params["type"] { gen.waveType = t }
    if let a = params["a"] ?? params["amp"] { gen.amp = Double(a) ?? 0.8 }
    if let d = params["d"] ?? params["dur"] { gen.duration = Double(d) ?? 2.0 }
    if let r = params["r"] ?? params["rate"] { gen.sampleRate = Int(r) ?? 44100 }
    if params["stereo"] != nil { gen.stereo = true }
    if let adsr = params["adsr"] {
        let parts = adsr.split(separator: " ").compactMap { Double($0) }
        if parts.count == 4 { gen.envelope = Envelope(attack: parts[0], decay: parts[1], sustain: parts[2], release: parts[3]) }
    }
    if let sweep = params["sweep"] {
        let parts = sweep.split(separator: " ").compactMap { Double($0) }
        if parts.count == 2 { gen.sweepStart = parts[0]; gen.sweepEnd = parts[1] }
    }
    let output = params["o"] ?? params["output"] ?? "output.wav"
    gen.generate()
    do { try gen.saveWAV(output); print("Saved to \(output)") }
    catch { print("Error saving: \(error)") }
    if params["no-play"] == nil { gen.play(output) }
}

if CommandLine.arguments.count > 1 { cli() } else { interactive() }
