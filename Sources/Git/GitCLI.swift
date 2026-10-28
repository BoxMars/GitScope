import Foundation

struct GitOutput {
    var status: Int32
    var stdout: String
    var stderr: String
    var ok: Bool { status == 0 }
    var trimmed: String { stdout.trimmingCharacters(in: .whitespacesAndNewlines) }
    var errorText: String { stderr.trimmingCharacters(in: .whitespacesAndNewlines) }
}

enum GitError: LocalizedError {
    case commandFailed(String)
    case notARepository(String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let message): return message
        case .notARepository(let path): return "Not a git repository: \(path)"
        }
    }
}

/// Runs the `git` binary as a child process.
enum GitCLI {
    static let executable: String = {
        for candidate in ["/opt/homebrew/bin/git", "/usr/local/bin/git", "/usr/bin/git"] {
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return "/usr/bin/git"
    }()

    static let baseEnvironment: [String: String] = {
        var env = ProcessInfo.processInfo.environment
        let path = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        env["PATH"] = path
        env["GIT_TERMINAL_PROMPT"] = "0"
        env["GIT_OPTIONAL_LOCKS"] = "0"
        env["LC_ALL"] = "en_US.UTF-8"
        env["LANG"] = "en_US.UTF-8"
        return env
    }()

    static func run(
        _ arguments: [String],
        in directory: String,
        environment: [String: String] = [:],
        input: String? = nil
    ) async throws -> GitOutput {
        var env = baseEnvironment
        for (key, value) in environment { env[key] = value }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.currentDirectoryURL = URL(fileURLWithPath: directory)
        process.arguments = arguments
        process.environment = env
        process.standardInput = Pipe()
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<GitOutput, Error>) in
                let stdoutPipe = process.standardOutput as! Pipe
                let stderrPipe = process.standardError as! Pipe
                let stdinPipe = process.standardInput as! Pipe

                var outData = Data()
                var errData = Data()
                let group = DispatchGroup()
                group.enter()
                DispatchQueue.global().async {
                    outData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }
                group.enter()
                DispatchQueue.global().async {
                    errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }

                if let input {
                    stdinPipe.fileHandleForWriting.write(input.data(using: .utf8) ?? Data())
                }
                try? stdinPipe.fileHandleForWriting.close()

                process.terminationHandler = { proc in
                    group.wait()
                    let out = String(data: outData, encoding: .utf8) ?? ""
                    let err = String(data: errData, encoding: .utf8) ?? ""
                    continuation.resume(returning: GitOutput(status: proc.terminationStatus, stdout: out, stderr: err))
                }

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
    }

    /// Run and throw on non-zero exit.
    @discardableResult
    static func runChecked(
        _ arguments: [String],
        in directory: String,
        environment: [String: String] = [:],
        input: String? = nil
    ) async throws -> String {
        let result = try await run(arguments, in: directory, environment: environment, input: input)
        guard result.ok else {
            let message = result.errorText.isEmpty ? "git \(arguments.prefix(2).joined(separator: " ")) failed" : result.errorText
            throw GitError.commandFailed(message)
        }
        return result.stdout
    }
}
