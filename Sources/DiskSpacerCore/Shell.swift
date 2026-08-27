import Foundation

/// Minimal process runner for the few cleaners that must ask a tool (docker,
/// brew) what it's holding.
///
/// A GUI app launched from Finder inherits a bare `PATH` that contains none of
/// the usual install locations, so tools are located by explicit search rather
/// than trusted to be on `PATH`.
public enum Shell {

    private static let searchPaths = [
        "/opt/homebrew/bin",            // Apple silicon Homebrew
        "/usr/local/bin",               // Intel Homebrew, Docker Desktop
        "/usr/bin", "/bin", "/usr/sbin", "/sbin",
        NSHomeDirectory() + "/.docker/bin",
        "/Applications/Docker.app/Contents/Resources/bin",
    ]

    /// Absolute path to `tool`, or nil if it isn't installed.
    public static func which(_ tool: String) -> String? {
        for dir in searchPaths {
            let p = dir + "/" + tool
            if FileManager.default.isExecutableFile(atPath: p) { return p }
        }
        return nil
    }

    public struct Output: Sendable {
        public let stdout: String
        public let stderr: String
        public let exitCode: Int32
        public var ok: Bool { exitCode == 0 }
    }

    /// Runs `tool` with `args`, capturing output. Returns nil if not installed.
    /// `timeout` guards against a hung daemon wedging the whole scan.
    public static func run(
        _ tool: String, _ args: [String], timeout: TimeInterval = 30
    ) -> Output? {
        guard let exe = which(tool) else { return nil }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: exe)
        proc.arguments = args
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = searchPaths.joined(separator: ":")
        proc.environment = env

        let out = Pipe(), err = Pipe()
        proc.standardOutput = out
        proc.standardError = err

        do { try proc.run() } catch { return nil }

        // Read concurrently with waiting, so a large output can't fill the pipe
        // buffer and deadlock the child.
        let outData = UnsafeSendableBox<Data>(Data())
        let errData = UnsafeSendableBox<Data>(Data())
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            outData.value = out.fileHandleForReading.readDataToEndOfFile(); group.leave()
        }
        group.enter()
        DispatchQueue.global().async {
            errData.value = err.fileHandleForReading.readDataToEndOfFile(); group.leave()
        }

        let deadline = Date().addingTimeInterval(timeout)
        while proc.isRunning && Date() < deadline {
            usleep(50_000)
        }
        if proc.isRunning {
            proc.terminate()
            _ = group.wait(timeout: .now() + 2)
            return Output(stdout: "", stderr: "timed out", exitCode: -1)
        }
        _ = group.wait(timeout: .now() + 5)

        return Output(
            stdout: String(data: outData.value, encoding: .utf8) ?? "",
            stderr: String(data: errData.value, encoding: .utf8) ?? "",
            exitCode: proc.terminationStatus
        )
    }
}

/// Small mutable box for handing data back from a dispatch queue.
final class UnsafeSendableBox<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}
