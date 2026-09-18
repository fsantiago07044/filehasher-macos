import XCTest
@testable import FileHasher

/// Preferences that survive between runs, and more importantly the ones that
/// must NOT.
///
/// Every case runs against its own UserDefaults suite rather than `.standard`,
/// so the suite never reads or overwrites the real user's preferences. That
/// matters more here than it looks: the test target is app-hosted, so these run
/// inside the real app.
@MainActor
final class PreferencesTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        suiteName = "FileHasherTests-\(UUID().uuidString)"
        defaults  = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testDefaultsWhenNothingHasBeenStored() {
        let model = AppModel(defaults: defaults)

        XCTAssertEqual(model.algorithm, .sha256)
        XCTAssertFalse(model.includeMetadata)
    }

    func testAlgorithmAndMetadataSurviveARestart() {
        let first = AppModel(defaults: defaults)
        first.algorithm       = .sha512
        first.includeMetadata = true

        let second = AppModel(defaults: defaults)

        XCTAssertEqual(second.algorithm, .sha512)
        XCTAssertTrue(second.includeMetadata)
    }

    /// The sidecar extension is deliberately not persisted, so it has to be
    /// re-derived from the restored algorithm. Property observers do not fire
    /// during initialisation, so without an explicit call this would restore
    /// SHA512 alongside a stale ".sha256" extension, a combination the UI can
    /// never produce by hand.
    func testRestoringAnAlgorithmReDerivesTheSidecarExtension() {
        let first = AppModel(defaults: defaults)
        first.algorithm = .sha512
        XCTAssertEqual(first.sidecarExtension, ".sha512")

        let second = AppModel(defaults: defaults)

        XCTAssertEqual(second.algorithm, .sha512)
        XCTAssertEqual(second.sidecarExtension, ".sha512")
    }

    /// A hand-edited or future-written value must not leave the app with no
    /// algorithm selected.
    func testUnknownStoredAlgorithmFallsBackToTheDefault() {
        defaults.set("ROT13", forKey: "algorithm")

        XCTAssertEqual(AppModel(defaults: defaults).algorithm, .sha256)
    }

    /// The rule: if a control's enabled state depends on the target, its value
    /// describes that target rather than a standing preference, so it resets.
    /// Anything that writes files resets too. Adding persistence for one of
    /// these should fail here rather than ship.
    func testTargetDependentAndFileWritingOptionsAreNotRemembered() {
        let first = AppModel(defaults: defaults)
        first.targetPath       = "/tmp"
        first.depthMode        = .allSubfolders
        first.depthLevels      = 9
        first.limitFileTypes   = true
        first.fileTypesText    = "pkg, dmg"
        first.writeSidecars    = true
        first.sidecarExtension = ".custom"
        first.sidecarFormat    = .extended
        first.exportCsv        = true
        first.csvPath          = "/tmp/out.csv"

        let second = AppModel(defaults: defaults)

        XCTAssertEqual(second.targetPath, "")
        XCTAssertEqual(second.depthMode, .thisFolderOnly)
        XCTAssertEqual(second.depthLevels, 1)
        XCTAssertFalse(second.limitFileTypes)
        XCTAssertEqual(second.fileTypesText, "")
        XCTAssertFalse(second.writeSidecars)
        XCTAssertEqual(second.sidecarExtension, ".sha256")
        XCTAssertEqual(second.sidecarFormat, .algoSum)
        XCTAssertFalse(second.exportCsv)
        XCTAssertEqual(second.csvPath, "")
    }

    func testPreferencesAreWrittenToTheInjectedSuiteOnly() {
        let model = AppModel(defaults: defaults)
        model.algorithm = .md5

        XCTAssertEqual(defaults.string(forKey: "algorithm"), "MD5")
    }
}
