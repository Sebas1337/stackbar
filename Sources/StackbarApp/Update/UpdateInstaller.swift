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
            }
        }
    }

    /// Why this copy can't replace itself, nil when it can.
    static func blocker() -> String? {
        let bundle = Bundle.main.bundleURL
        if bundle.path.contains("/AppTranslocation/") {
            return "macOS runs this copy from a temporary location. Move Stackbar to Applications and open it from there."
        }
        // The swap removes the old bundle from its folder and replaces its contents.
        for path in [bundle.deletingLastPathComponent().path, bundle.path, bundle.appendingPathComponent("Contents").path]
        where !FileManager.default.isWritableFile(atPath: path) {
            return "Stackbar can't write to \(path). Download the update instead."
        }
        return nil
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

        _ = try FileManager.default.replaceItemAt(bundle, withItemAt: app)
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

    private nonisolated static func run(_ tool: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw Failure.archive }
    }

    /// Opens the new version once this process has exited. Doesn't quit when that can't be arranged.
    private static func relaunch(_ bundle: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c", "while /bin/kill -0 \"$1\" 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open \"$0\"",
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
