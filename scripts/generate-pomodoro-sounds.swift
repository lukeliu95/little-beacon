#!/usr/bin/env swift

import Foundation

private let sampleRate = 44_100

private extension Data {
    mutating func appendUInt16LE(_ value: UInt16) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }

    mutating func appendUInt32LE(_ value: UInt32) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }
}

private struct Tone {
    let frequency: Double
    let duration: Double
    let volume: Double
}

private func makeWAV(_ tones: [Tone]) -> Data {
    var samples: [Int16] = []
    for tone in tones {
        let count = Int(Double(sampleRate) * tone.duration)
        for index in 0..<count {
            let seconds = Double(index) / Double(sampleRate)
            let fade = min(1, Double(index) / 300) * min(1, Double(count - index) / 500)
            let value = tone.frequency == 0
                ? 0
                : sin(2 * .pi * tone.frequency * seconds) * tone.volume * fade
            samples.append(Int16(max(-1, min(1, value)) * Double(Int16.max)))
        }
    }

    let byteCount = UInt32(samples.count * MemoryLayout<Int16>.size)
    var data = Data()
    data.append(Data("RIFF".utf8))
    data.appendUInt32LE(36 + byteCount)
    data.append(Data("WAVEfmt ".utf8))
    data.appendUInt32LE(16)
    data.appendUInt16LE(1)
    data.appendUInt16LE(1)
    data.appendUInt32LE(UInt32(sampleRate))
    data.appendUInt32LE(UInt32(sampleRate * 2))
    data.appendUInt16LE(2)
    data.appendUInt16LE(16)
    data.append(Data("data".utf8))
    data.appendUInt32LE(byteCount)
    for sample in samples {
        data.appendUInt16LE(UInt16(bitPattern: sample))
    }
    return data
}

let repositoryRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let resources = repositoryRoot
    .appendingPathComponent("Sources/LittleBeaconApp/Resources", isDirectory: true)

let alarm = makeWAV([
    Tone(frequency: 784, duration: 0.20, volume: 0.55),
    Tone(frequency: 0, duration: 0.08, volume: 0),
    Tone(frequency: 988, duration: 0.20, volume: 0.55),
    Tone(frequency: 0, duration: 0.08, volume: 0),
    Tone(frequency: 784, duration: 0.28, volume: 0.55),
])
let completion = makeWAV([
    Tone(frequency: 523, duration: 0.18, volume: 0.42),
    Tone(frequency: 659, duration: 0.18, volume: 0.42),
    Tone(frequency: 784, duration: 0.35, volume: 0.42),
])

try alarm.write(to: resources.appendingPathComponent("pomodoro-alarm.wav"), options: .atomic)
try completion.write(to: resources.appendingPathComponent("pomodoro-complete.wav"), options: .atomic)
