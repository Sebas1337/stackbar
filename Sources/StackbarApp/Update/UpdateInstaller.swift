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
            }
        }
    }

    /// Why this copy can't replace itself, nil when it can.
    static func blocker() -> String? {
        let bundle = Bundle.main.bundleURL
        if bundle.path.contains("/AppTranslocation/") {
            return "macOS runs this copy from a temporary location. Move Stackbar to Applications and open it from there."
        }
        if !FileManager.default.isWritableFile(atPath: bundle.deletingLastPathComponent().path) {
            return "Stackbar can't write to \(bundle.deletingLastPathComponent().path)."
        }
        return nil
    }

    static func install(_ update: ReleaseFeed.Update) async throws {
        if let reason = blocker() { throw Failure.notReplaceable(reason) }
        let bundle = Bundle.main.bundleURL
        // On the app's volume, so the swap is a rename.
        let folder = try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: bundle, create: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let archive = folder.appendingPathComponent("Stackbar-\(update.version).zip")
        let expected = try await download(update.checksum).flatMap { ReleaseFeed.digest(fromChecksumFile: String(decoding: $0, as: UTF8.self)) }
        guard let expected else { throw Failure.checksum }
        guard let data = try await download(update.archive) else { throw Failure.download("empty response") }
        guard SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == expected else { throw Failure.checksum }
        try data.write(to: archive)

        let extracted = folder.appendingPathComponent("extracted", isDirectory: true)
        try run("/usr/bin/ditto", ["-x", "-k", archive.path, extracted.path])
        let app = extracted.appendingPathComponent("Stackbar.app")
        guard FileManager.default.fileExists(atPath: app.path) else { throw Failure.archive }
        _ = try? run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", app.path])
        try checkSignature(of: app)
        try checkBundle(app, version: update.version)

        _ = try FileManager.default.replaceItemAt(bundle, withItemAt: app)
        SpikeLog.shared.add("Update: installed \(update.version), relaunching")
        relaunch(bundle)
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
    private static func checkSignature(of app: URL) throws {
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

    private static func run(_ tool: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw Failure.archive }
    }

    /// Opens the new version once this process has exited.
    private static func relaunch(_ bundle: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c", "while /bin/kill -0 \"$1\" 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open \"$0\"",
            bundle.path, String(ProcessInfo.processInfo.processIdentifier),
        ]
        try? process.run()
        NSApp.terminate(nil)
    }
}
