import Foundation

struct ProcessResult {
    let command: String
    let arguments: [String]
    let workingDirectory: String
    let exitCode: Int32
    let stdout: String
    let stderr: String
    let startedAt: Date
    let finishedAt: Date

    var commandLine: String {
        ([command] + arguments).joined(separator: " ")
    }

    var duration: TimeInterval {
        finishedAt.timeIntervalSince(startedAt)
    }

    var output: String {
        [stdout, stderr]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}

enum ProcessRunnerError: LocalizedError {
    case commandFailed(command: String, code: Int32, output: String)

    var errorDescription: String? {
        switch self {
        case let .commandFailed(command, code, output):
            return "Command failed (\(code)): \(command)\n\(output)"
        }
    }
}

final class ProcessRunner {
    func run(
        command: String,
        arguments: [String],
        in cwd: URL,
        environment: [String: String] = [:]
    ) throws -> ProcessResult {
        let process = Process()
        process.currentDirectoryURL = cwd
        if !environment.isEmpty {
            var merged = ProcessInfo.processInfo.environment
            for (key, value) in environment {
                merged[key] = value
            }
            process.environment = merged
        }

        if command.contains("/") {
            process.executableURL = URL(fileURLWithPath: command)
            process.arguments = arguments
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [command] + arguments
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let startedAt = Date()
        try process.run()
        process.waitUntilExit()
        let finishedAt = Date()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        let stdout = String(data: stdoutData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let result = ProcessResult(
            command: command,
            arguments: arguments,
            workingDirectory: cwd.path,
            exitCode: process.terminationStatus,
            stdout: stdout,
            stderr: stderr,
            startedAt: startedAt,
            finishedAt: finishedAt
        )

        if process.terminationStatus != 0 {
            throw ProcessRunnerError.commandFailed(
                command: result.commandLine,
                code: process.terminationStatus,
                output: result.output
            )
        }

        return result
    }
}
