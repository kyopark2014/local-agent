import Foundation

/// Locates the local-agent repo and runs uvicorn for the FastAPI backend.
@MainActor
final class PythonProcessManager: ObservableObject {
    @Published private(set) var status: ServerStatus = .offline
    @Published private(set) var lastLog: String = ""

    private var process: Process?
    private let port: Int
    private let api = APIClient.shared

    init(port: Int = 8501) {
        self.port = port
        api.baseURL = URL(string: "http://127.0.0.1:\(port)")!
    }

    var repoRoot: URL {
        if let stored = UserDefaults.standard.string(forKey: "repoRoot"), !stored.isEmpty {
            return URL(fileURLWithPath: stored)
        }
        // MacApp/ is inside local-agent/; Bundle is .../Seyeon.app/Contents/MacOS
        let appDir = Bundle.main.bundleURL.deletingLastPathComponent()
        let candidates: [URL] = [
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent() // Services
                .deletingLastPathComponent() // LocalAgent
                .deletingLastPathComponent() // MacApp
                .deletingLastPathComponent(), // local-agent
            appDir.appendingPathComponent("local-agent"),
            appDir,
            Bundle.main.bundleURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent(),
            URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents/src/local-agent"),
        ]
        for url in candidates {
            let marker = url.appendingPathComponent("application/server.py")
            if FileManager.default.fileExists(atPath: marker.path) {
                return url
            }
        }
        return URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents/src/local-agent")
    }

    func ensureServerRunning() async {
        if status == .ready {
            if (try? await api.health()) == true { return }
        }

        if (try? await api.health()) == true {
            status = .ready
            return
        }

        status = .starting
        do {
            try startProcess()
            let ok = await waitForHealth(timeoutSeconds: 45)
            if ok {
                status = .ready
            } else {
                status = .error("Server did not become healthy in time")
            }
        } catch {
            status = .error(error.localizedDescription)
        }
    }

    func stop() {
        process?.terminate()
        process = nil
        status = .offline
    }

    private func startProcess() throws {
        if let existing = process, existing.isRunning { return }

        let root = repoRoot
        let script = root.appendingPathComponent("scripts/run_api.sh")
        let proc = Process()
        proc.currentDirectoryURL = root

        var env = ProcessInfo.processInfo.environment
        env["PYTHONUNBUFFERED"] = "1"
        env["PORT"] = String(port)

        if FileManager.default.isExecutableFile(atPath: script.path) {
            proc.executableURL = script
            proc.arguments = []
        } else {
            let python = resolvePython(root: root)
            proc.executableURL = URL(fileURLWithPath: python)
            proc.arguments = [
                "-m", "uvicorn",
                "application.server:app",
                "--host", "127.0.0.1",
                "--port", String(port),
            ]
        }
        proc.environment = env

        let out = Pipe()
        let err = Pipe()
        proc.standardOutput = out
        proc.standardError = err
        out.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in self?.lastLog = String(text.suffix(400)) }
        }
        err.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in self?.lastLog = String(text.suffix(400)) }
        }

        try proc.run()
        process = proc
    }

    private func resolvePython(root: URL) -> String {
        if let custom = UserDefaults.standard.string(forKey: "pythonPath"), !custom.isEmpty {
            return custom
        }
        let candidates = [
            root.appendingPathComponent(".venv/bin/python3").path,
            root.deletingLastPathComponent().appendingPathComponent("agent-skills/.venv/bin/python3").path,
            "/usr/bin/python3",
            "/opt/homebrew/bin/python3",
        ]
        for path in candidates {
            guard FileManager.default.isExecutableFile(atPath: path) else { continue }
            let check = Process()
            check.executableURL = URL(fileURLWithPath: path)
            check.arguments = ["-c", "import uvicorn"]
            check.standardOutput = FileHandle.nullDevice
            check.standardError = FileHandle.nullDevice
            do {
                try check.run()
                check.waitUntilExit()
                if check.terminationStatus == 0 { return path }
            } catch {
                continue
            }
        }
        return "/usr/bin/python3"
    }

    private func waitForHealth(timeoutSeconds: Double) async -> Bool {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if (try? await api.health()) == true { return true }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        return false
    }
}
