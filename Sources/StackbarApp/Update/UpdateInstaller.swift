import AppKit
import CryptoKit
import Security
import StackbarCore

/// Installs an update in place (docs/PLAN.md M5, Updates): downloads the release's zip, checks
/// its SHA-256 and that the app inside is signed with the **same certificate** as the running
/// Stackbar (its designated requirement), so macOS keeps the permissions; then swaps the bundle
/// and relaunches. Downloads made here get no quarantine flag, so Gatekeeper doesn't stop the
/// new version.
@MainActor
enum UpdateInstaller {
    enum Failure: LocalizedError {
        case notReplaceable(String)
        case download(String)
        case checksum
        case archive
        case signature(OSStatus)
        case wrongApp(String)
        case relaunch(String)
        case cancelled
        case administrator(String)

        var errorDescription: String? {
            switch self {
            case .notReplaceable(let reason): reason
            case .download(let reason): "The download failed: \(reason)"
            case .checksum: "The download is damaged (checksum mismatch)."
            case .archive: "The download doesn't contain Stackbar.app."
            case .signature(let status):
                "The new version isn't signed like this one (\(status)). Development builds can't install releases; "
                    + "download it from GitHub instead."
            case .wrongApp(let reason): reason
            case .relaunch(let reason): "Stackbar was updated but couldn't restart itself (\(reason)). Quit it and open it again."
            case .cancelled: "The update was cancelled."
            case .administrator(let reason): "Replacing Stackbar as administrator failed: \(reason)"
            }
        }
    }

    /// Why this copy can't replace itself, nil when it can.
    static func blocker() -> String? {
        let bundle = Bundle.main.bundleURL
        if bundle.path.contains("/AppTranslocation/") {
            return "macOS runs this copy from a temporary location. Move Stackbar to Applications and open it from there."
        }
        // A disk image or another read-only volume: not even an administrator can swap it.
        if (try? bundle.resourceValues(forKeys: [.volumeIsReadOnlyKey]))?.volumeIsReadOnly == true {
            return "Stackbar runs from a read-only disk. Move it to Applications and open it from there."
        }
        return nil
    }

    /// The swap removes the old bundle from its folder and replaces its contents. Not writable: the
    /// copy belongs to another user (installed from their account; rc.1 test, 2026-10-31), so the
    /// swap asks for an administrator's password instead.
    private static func canReplaceAsUser(_ bundle: URL) -> Bool {
        [bundle.deletingLastPathComponent().path, bundle.path, bundle.appendingPathComponent("Contents").path]
            .allSatisfy { FileManager.default.isWritableFile(atPath: $0) }
    }

    static func install(_ update: ReleaseFeed.Update) async throws {
        if let reason = blocker() { throw Failure.notReplaceable(reason) }
        let bundle = Bundle.main.bundleURL
        // On the app's volume, so the swap is a rename.
        let folder = try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: bundle, create: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let expected = try await download(update.checksum).flatMap { ReleaseFeed.digest(fromChecksumFile: String(decoding: $0, as: UTF8.self)) }
        guard let expected else { throw Failure.checksum }
        guard let data = try await download(update.archive) else { throw Failure.download("empty response") }
        // Hashing, unzipping and checking the signature of a universal app take a moment: not on
        // the main thread, where the menu bar icon and the panel live.
        let app = try await Task.detached { try unpack(data, expected: expected, into: folder) }.value
        try checkBundle(app, version: update.version)

        if canReplaceAsUser(bundle) {
            _ = try FileManager.default.replaceItemAt(bundle, withItemAt: app)
        } else {
            try await replaceAsAdministrator(bundle, with: app, version: update.version)
        }
        SpikeLog.shared.add("Update: installed \(update.version), relaunching")
        try relaunch(bundle)
    }

    /// Checks the zip against its checksum, unzips it into `folder` and checks the app's signature.
    private nonisolated static func unpack(_ data: Data, expected: String, into folder: URL) throws -> URL {
        guard SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == expected else { throw Failure.checksum }
        let archive = folder.appendingPathComponent("Stackbar.zip")
        try data.write(to: archive)
        let extracted = folder.appendingPathComponent("extracted", isDirectory: true)
        try run("/usr/bin/ditto", ["-x", "-k", archive.path, extracted.path])
        let app = extracted.appendingPathComponent("Stackbar.app")
        guard FileManager.default.fileExists(atPath: app.path) else { throw Failure.archive }
        _ = try? run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", app.path])
        try checkSignature(of: app)
        return app
    }

    private static func download(_ url: URL) async throws -> Data? {
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw Failure.download("HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
            }
            return data.isEmpty ? nil : data
        } catch let failure as Failure {
            throw failure
        } catch {
            throw Failure.download(error.localizedDescription)
        }
    }

    /// The new app must satisfy the running app's designated requirement: same bundle id, same
    /// signing certificate. That is what TCC checks, so the permissions carry over.
    private nonisolated static func checkSignature(of app: URL) throws {
        var running: SecCode?
        var runningStatic: SecStaticCode?
        var requirement: SecRequirement?
        var candidate: SecStaticCode?
        var status = SecCodeCopySelf([], &running)
        if status == errSecSuccess, let running { status = SecCodeCopyStaticCode(running, [], &runningStatic) }
        if status == errSecSuccess, let runningStatic { status = SecCodeCopyDesignatedRequirement(runningStatic, [], &requirement) }
        if status == errSecSuccess { status = SecStaticCodeCreateWithPath(app as CFURL, [], &candidate) }
        if status == errSecSuccess, let candidate {
            let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
            status = SecStaticCodeCheckValidity(candidate, flags, requirement)
        }
        guard status == errSecSuccess else { throw Failure.signature(status) }
    }

    private static func checkBundle(_ app: URL, version: SemanticVersion) throws {
        let info = Bundle(url: app)?.infoDictionary ?? [:]
        guard info["CFBundleIdentifier"] as? String == Bundle.main.bundleIdentifier else {
            throw Failure.wrongApp("The download isn't Stackbar.")
        }
        guard (info["CFBundleShortVersionString"] as? String).flatMap(SemanticVersion.init) == version else {
            throw Failure.wrongApp("The download isn't version \(version).")
        }
    }

    /// Swaps the bundle with an administrator's password (macOS's own dialog, through `osascript`):
    /// the old copy is moved aside first (to a new name, so nothing that exists is removed) and put
    /// back when the new one can't be moved in. Paths go
    /// in as arguments and through `quoted form of`, never into the script text.
    private static func replaceAsAdministrator(_ bundle: URL, with app: URL, version: SemanticVersion) async throws {
        let script = """
            on run argv
              set bundlePath to quoted form of item 1 of argv
              set asidePath to quoted form of item 2 of argv
              set newPath to quoted form of item 3 of argv
              do shell script "/bin/mv " & bundlePath & " " & asidePath & " && { /bin/mv " & newPath & " " & bundlePath & " || { /bin/mv " & asidePath & " " & bundlePath & "; exit 1; }; } && /bin/rm -rf " & asidePath with prompt (item 4 of argv) with administrator privileges
            end run
            """
        let prompt = "Stackbar \(version) replaces \(bundle.path), which belongs to another user on this Mac."
        let aside = bundle.deletingLastPathComponent().appendingPathComponent(".Stackbar-\(UUID().uuidString).app").path
        let arguments = ["-e", script, bundle.path, aside, app.path, prompt]
        let (status, output) = try await Task.detached { try runCapturing("/usr/bin/osascript", arguments) }.value
        guard status == 0 else {
            // -128: the user clicked Cancel in the password dialog.
            if output.contains("(-128)") { throw Failure.cancelled }
            throw Failure.administrator(output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private nonisolated static func runCapturing(_ tool: String, _ arguments: [String]) throws -> (Int32, String) {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardError = pipe
        process.standardOutput = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    private nonisolated static func run(_ tool: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw Failure.archive }
    }

    /// Opens the new version once this process has exited. Doesn't quit when that can't be arranged.
    /// LaunchServices notices the exit some milliseconds after the process is gone: an `open` right
    /// away only activated the dying instance and nothing started (M5 update test, `open` 12 ms
    /// after the exit, LaunchServices' QUITTING 24 ms later). So wait a moment, and `-n` starts a
    /// new instance whatever LaunchServices still thinks.
    private static func relaunch(_ bundle: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c", "while /bin/kill -0 \"$1\" 2>/dev/null; do /bin/sleep 0.2; done; /bin/sleep 1; /usr/bin/open -n \"$0\"",
            bundle.path, String(ProcessInfo.processInfo.processIdentifier),
        ]
        do {
            try process.run()
        } catch {
            throw Failure.relaunch(error.localizedDescription)
        }
        NSApp.terminate(nil)
    }
}
