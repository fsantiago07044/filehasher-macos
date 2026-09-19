import XCTest
@testable import FileHasher

/// `AppModel.seedFromPath`, which decides where a browse panel opens.
///
/// The panels themselves are shell windows a test cannot drive, so the decision
/// lives in one pure function and is tested here directly. Same approach as
/// MainFormPathSeedTests in the Windows app.
@MainActor
final class PathSeedTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileHasherSeed-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func makeFile(_ name: String) throws -> URL {
        let url = tempDir.appendingPathComponent(name)
        try Data("x".utf8).write(to: url)
        return url
    }

    func testEmptyOrBlankPathSeedsNothing() {
        for raw in ["", "   ", "\t"] {
            let seed = AppModel.seedFromPath(raw)
            XCTAssertNil(seed.folder, "raw: \(raw.debugDescription)")
            XCTAssertNil(seed.fileName)
        }
    }

    func testExistingFolderOpensInsideItself() {
        let seed = AppModel.seedFromPath(tempDir.path)

        XCTAssertEqual(seed.folder?.path, tempDir.path)
        XCTAssertNil(seed.fileName, "A folder target has no file to pre-select.")
    }

    func testTrailingSeparatorIsHandled() {
        let seed = AppModel.seedFromPath(tempDir.path + "/")

        XCTAssertEqual(seed.folder?.path, tempDir.path)
        XCTAssertNil(seed.fileName)
    }

    func testExistingFileOpensAtItsParentAndNamesTheFile() throws {
        let file = try makeFile("installer.pkg")

        let seed = AppModel.seedFromPath(file.path)

        XCTAssertEqual(seed.folder?.path, tempDir.path)
        XCTAssertEqual(seed.fileName, "installer.pkg")
    }

    /// A name that does not exist yet, in a folder that does: keep the name, so
    /// a save panel reuses it instead of inventing a new one.
    func testMissingLeafInAnExistingFolderKeepsTheName() {
        let seed = AppModel.seedFromPath(tempDir.appendingPathComponent("not-yet.csv").path)

        XCTAssertEqual(seed.folder?.path, tempDir.path)
        XCTAssertEqual(seed.fileName, "not-yet.csv")
    }

    /// Once a directory level has to be walked past, the leaf is dropped:
    /// naming a file inside a folder it never came from is worse than naming
    /// nothing.
    func testWalkingPastAMissingDirectoryDropsTheName() {
        let stale = tempDir
            .appendingPathComponent("gone", isDirectory: true)
            .appendingPathComponent("deeper", isDirectory: true)
            .appendingPathComponent("file.txt")

        let seed = AppModel.seedFromPath(stale.path)

        XCTAssertEqual(seed.folder?.path, tempDir.path,
                       "Should climb to the deepest surviving ancestor.")
        XCTAssertNil(seed.fileName)
    }

    /// A path on a volume that is no longer mounted still resolves to the
    /// deepest ancestor that exists, rather than failing or throwing.
    func testPathOnAVanishedVolumeDegradesToAnExistingAncestor() {
        let seed = AppModel.seedFromPath("/Volumes/NoSuchVolume-\(UUID().uuidString)/x/y.dmg")

        XCTAssertEqual(seed.folder?.path, "/Volumes")
        XCTAssertNil(seed.fileName)
    }
}
