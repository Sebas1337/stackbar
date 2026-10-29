import Darwin

/// The private SkyLight framework, opened with `dlopen` so Stackbar doesn't link against it.
/// Private APIs need the user's approval (docs/PLAN.md, Decisions → Private APIs); the approved
/// ones are `PrivateWindowCapture` and `CursorHider`.
enum SkyLight {
    nonisolated(unsafe) private static let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)

    /// The first of `names` that exists, nil when SkyLight or every name is missing.
    static func symbol(_ names: String...) -> UnsafeMutableRawPointer? {
        guard let handle else { return nil }
        return names.lazy.compactMap { dlsym(handle, $0) }.first
    }
}
