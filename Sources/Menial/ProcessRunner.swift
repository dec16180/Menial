// SPDX-FileCopyrightText: 2026 Christopher De Nicolo
//
// SPDX-License-Identifier: MIT

import Foundation

/// Minimal async wrapper around Process that drains both pipes and enforces a timeout.
enum ProcessRunner {
    struct Result {
        var status: Int32
        var stdout: Data
        var stderr: Data
        var timedOut: Bool
    }

    private final class Box: @unchecked Sendable {
        var stdout = Data()
        var stderr = Data()
        var timedOut = false
    }

    static func run(
        _ path: String, args: [String], environment: [String: String],
        directory: URL?, timeout: TimeInterval, input: Data? = nil
    ) async throws -> Result {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = args
            process.environment = environment
            if let directory { process.currentDirectoryURL = directory }

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe
            let inPipe = input.map { _ in Pipe() }
            process.standardInput = inPipe ?? FileHandle.nullDevice

            let box = Box()
            let group = DispatchGroup()
            let queue = DispatchQueue.global(qos: .userInitiated)

            group.enter()
            process.terminationHandler = { _ in group.leave() }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
                return
            }

            if let inPipe, let input {
                queue.async {
                    try? inPipe.fileHandleForWriting.write(contentsOf: input)
                    try? inPipe.fileHandleForWriting.close()
                }
            }
            group.enter()
            queue.async {
                box.stdout = outPipe.fileHandleForReading.readDataToEndOfFile()
                group.leave()
            }
            group.enter()
            queue.async {
                box.stderr = errPipe.fileHandleForReading.readDataToEndOfFile()
                group.leave()
            }

            let killer = DispatchWorkItem {
                if process.isRunning {
                    box.timedOut = true
                    process.terminate()
                }
            }
            queue.asyncAfter(deadline: .now() + timeout, execute: killer)

            group.notify(queue: queue) {
                killer.cancel()
                continuation.resume(returning: Result(
                    status: process.terminationStatus,
                    stdout: box.stdout, stderr: box.stderr, timedOut: box.timedOut
                ))
            }
        }
    }
}
