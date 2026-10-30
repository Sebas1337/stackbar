import Testing
@testable import StackbarCore

struct SemanticVersionTests {
    static func version(_ text: String) -> SemanticVersion {
        SemanticVersion(text)!
    }

    @Test func parsesReleasesPrereleasesAndTags() {
        #expect(Self.version("1.2.3").description == "1.2.3")
        #expect(Self.version("v1.0.0-beta.2").description == "1.0.0-beta.2")
        #expect(Self.version("1.0.0+42").description == "1.0.0")
        #expect(Self.version("1.0.0-rc.1").isPrerelease)
        for bad in ["1.0", "1.0.0.0", "a.b.c", "1.0.0-", "1.0.0-beta..1", "", "-1.0.0"] {
            #expect(SemanticVersion(bad) == nil, "\(bad)")
        }
    }

    @Test func ordersLikeSemVer() {
        // The SemVer 2.0.0 example, in ascending order.
        let ordered = ["1.0.0-alpha", "1.0.0-alpha.1", "1.0.0-alpha.beta", "1.0.0-beta", "1.0.0-beta.2",
                       "1.0.0-beta.11", "1.0.0-rc.1", "1.0.0", "1.0.1", "1.1.0", "2.0.0", "10.0.0"].map(Self.version)
        for (lower, higher) in zip(ordered, ordered.dropFirst()) {
            #expect(lower < higher, "\(lower) < \(higher)")
            #expect(!(higher < lower), "\(higher) < \(lower)")
        }
        #expect(Self.version("0.6.1") < Self.version("1.0.0-beta.1"))
        #expect(Self.version("1.0.0") == Self.version("v1.0.0"))
    }
}
