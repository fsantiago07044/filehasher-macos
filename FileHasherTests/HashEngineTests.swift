import XCTest
@testable import FileHasher

final class HashEngineTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileHasherTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    @discardableResult
    private func makeFile(_ name: String, _ contents: String) throws -> String {
        let url = tempDir.appendingPathComponent(name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url.path
    }

    // ── Hash correctness (known vectors for "abc") ───────────────────────────

    func testKnownHashVectors() throws {
        let path = try makeFile("abc.txt", "abc")
        let cancel = CancelFlag()

        XCTAssertEqual(
            try HashAlgorithmKind.hashFile(atPath: path, using: .md5, cancel: cancel),
            "900150983CD24FB0D6963F7D28E17F72")
        XCTAssertEqual(
            try HashAlgorithmKind.hashFile(atPath: path, using: .sha1, cancel: cancel),
            "A9993E364706816ABA3E25717850C26C9CD0D89D")
        XCTAssertEqual(
            try HashAlgorithmKind.hashFile(atPath: path, using: .sha256, cancel: cancel),
            "BA7816BF8F01CFEA414140DE5DAE2223B00361A396177A9CB410FF61F20015AD")
        XCTAssertEqual(
            try HashAlgorithmKind.hashFile(atPath: path, using: .sha512, cancel: cancel),
            "DDAF35A193617ABACC417349AE20413112E6FA4E89A97EA20A9EEEE64B55D39A"
            + "2192992A274FC1A836BA3C23A3FEEBBD454D4423643CE80E2A9AC94FA54CA49F")
    }

    func testCancelledHashThrows() throws {
        let path = try makeFile("big.bin", String(repeating: "x", count: 1_000_000))
        let cancel = CancelFlag()
        cancel.cancel()
        XCTAssertThrowsError(
            try HashAlgorithmKind.hashFile(atPath: path, using: .sha256, cancel: cancel)
        ) { XCTAssertTrue($0 is CancellationError) }
    }

    func testAlgorithmFromHexLength() {
        XCTAssertEqual(HashAlgorithmKind.from(hexLength: 32),  .md5)
        XCTAssertEqual(HashAlgorithmKind.from(hexLength: 40),  .sha1)
        XCTAssertEqual(HashAlgorithmKind.from(hexLength: 64),  .sha256)
        XCTAssertEqual(HashAlgorithmKind.from(hexLength: 128), .sha512)
        XCTAssertNil(HashAlgorithmKind.from(hexLength: 63))
    }

    // ── Sidecar content formats ──────────────────────────────────────────────

    func testSidecarContentFormats() {
        let modified = HashTimestamp.iso.date(from: "2026-08-09T14:33:05Z")!

        XCTAssertEqual(
            HashWorker.sidecarContent(format: .hashOnly, hash: "ABCD",
                                      fileName: "setup.exe", modified: modified, size: 42),
            "ABCD")
        XCTAssertEqual(
            HashWorker.sidecarContent(format: .algoSum, hash: "ABCD",
                                      fileName: "setup.exe", modified: modified, size: 42),
            "ABCD *setup.exe")
        XCTAssertEqual(
            HashWorker.sidecarContent(format: .extended, hash: "ABCD",
                                      fileName: "setup.exe", modified: modified, size: 42),
            "ABCD *setup.exe *2026-08-09T14:33:05Z *42")
    }

    // ── File-type parsing ────────────────────────────────────────────────────

    func testParseFileTypes() {
        XCTAssertEqual(HashOptions.parseFileTypes("pkg, .DMG, zip,, dmg"),
                       ["pkg", "dmg", "zip"])
        XCTAssertEqual(HashOptions.parseFileTypes("  "), [])
        XCTAssertEqual(HashOptions.parseFileTypes("..pkg"), ["pkg"])
        XCTAssertEqual(HashOptions.parseFileTypes("exe msi"), ["exe", "msi"])
    }

    // ── Enumeration: defaults, recursion, filter, sidecar exclusion ──────────

    private func enumOptions(recursive: Bool = false, filter: [String] = [],
                             writeSidecars: Bool = false) -> HashOptions {
        HashOptions(targetPath: tempDir.path, isFile: false,
                    algorithm: .sha256, includeMetadata: false,
                    writeSidecarHashes: writeSidecars, sidecarExtension: ".sha256",
                    sidecarFormat: .algoSum, recursive: recursive, fileTypeFilter: filter)
    }

    private func enumerate(_ opts: HashOptions) throws -> Set<String> {
        let (files, warnings) = try HashWorker(options: opts, cancel: CancelFlag())
            .enumerateFiles()
        XCTAssertTrue(warnings.isEmpty)
        return Set(files.map { ($0 as NSString).lastPathComponent })
    }

    func testEnumerationDefaultsToAllFilesNonRecursive() throws {
        try makeFile("a.exe", "1")
        try makeFile("c.txt", "3")
        try FileManager.default.createDirectory(
            at: tempDir.appendingPathComponent("sub"), withIntermediateDirectories: true)
        try makeFile("sub/nested.pkg", "4")

        // Default: every top-level file, no recursion into sub/.
        XCTAssertEqual(try enumerate(enumOptions()), ["a.exe", "c.txt"])

        // Recursive: sub/ is included.
        XCTAssertEqual(try enumerate(enumOptions(recursive: true)),
                       ["a.exe", "c.txt", "nested.pkg"])
    }

    func testEnumerationFileTypeFilter() throws {
        try makeFile("installer.pkg", "1")
        try makeFile("image.dmg", "2")
        try makeFile("readme.txt", "3")
        try FileManager.default.createDirectory(
            at: tempDir.appendingPathComponent("sub"), withIntermediateDirectories: true)
        try makeFile("sub/other.pkg", "4")

        XCTAssertEqual(try enumerate(enumOptions(filter: ["pkg", "dmg"])),
                       ["installer.pkg", "image.dmg"])
        XCTAssertEqual(try enumerate(enumOptions(recursive: true, filter: ["pkg"])),
                       ["installer.pkg", "other.pkg"])
    }

    func testEnumerationSidecarExclusion() throws {
        try makeFile("a.exe", "1")
        try makeFile("a.exe.sha256", "already-there")

        // Sidecars are excluded only while WRITING sidecars, matching Windows.
        XCTAssertEqual(try enumerate(enumOptions(writeSidecars: true)), ["a.exe"])
        XCTAssertEqual(try enumerate(enumOptions()), ["a.exe", "a.exe.sha256"])
    }

    // ── End-to-end hash run with sidecar writing ─────────────────────────────

    func testHashAllWritesAlgoSumSidecar() throws {
        let path = try makeFile("thing.exe", "abc")
        let opts = HashOptions(targetPath: path, isFile: true,
                               algorithm: .sha256, includeMetadata: true,
                               writeSidecarHashes: true, sidecarExtension: ".sha256",
                               sidecarFormat: .algoSum, recursive: false, fileTypeFilter: [])
        let worker = HashWorker(options: opts, cancel: CancelFlag())
        let logger = try Logger()

        var results: [HashResult] = []
        try worker.hashAll(files: [path], logger: logger) { message in
            if case .hashed(let r) = message { results.append(r) }
        }

        XCTAssertEqual(results.count, 1)
        XCTAssertTrue(results[0].success)
        XCTAssertEqual(results[0].hash,
            "BA7816BF8F01CFEA414140DE5DAE2223B00361A396177A9CB410FF61F20015AD")
        XCTAssertEqual(results[0].length, 3)

        let sidecar = try String(contentsOfFile: path + ".sha256", encoding: .utf8)
        XCTAssertEqual(sidecar,
            "BA7816BF8F01CFEA414140DE5DAE2223B00361A396177A9CB410FF61F20015AD *thing.exe\n")
    }

    // ── Verifier ─────────────────────────────────────────────────────────────

    private func verify(target: String, isFile: Bool, ext: String = ".sha256",
                        recursive: Bool = false,
                        filter: [String] = []) throws -> [VerifyResult] {
        let verifier = SidecarVerifier(targetPath: target, isFile: isFile,
                                       sidecarExtension: ext, recursive: recursive,
                                       fileTypeFilter: filter, cancel: CancelFlag())
        let (items, _) = try verifier.enumerateWork()
        var results: [VerifyResult] = []
        _ = try verifier.verifyAll(items: items, logger: try Logger()) { message in
            if case .verified(let v) = message { results.append(v) }
        }
        return results
    }

    func testVerifyOkAllThreeFormatsAndCaseInsensitivity() throws {
        let hash = "BA7816BF8F01CFEA414140DE5DAE2223B00361A396177A9CB410FF61F20015AD"
        let p1 = try makeFile("bare.exe", "abc")
        try makeFile("bare.exe.sha256", hash.lowercased())          // bare, lowercase
        let p2 = try makeFile("sum.exe", "abc")
        try makeFile("sum.exe.sha256", "\(hash) *sum.exe")           // {algo}sum
        let p3 = try makeFile("ext.exe", "abc")
        try makeFile("ext.exe.sha256",
                     "\(hash) *ext.exe *2026-08-09T14:33:05Z *3")    // extended

        for p in [p1, p2, p3] {
            let results = try verify(target: p, isFile: true)
            XCTAssertEqual(results.count, 1, p)
            XCTAssertEqual(results[0].status, .ok, p)
            XCTAssertEqual(results[0].algorithm, .sha256, p)
        }
    }

    func testVerifyMismatchMissingParseAndAudit() throws {
        // Mismatch
        let bad = try makeFile("bad.exe", "abc")
        try makeFile("bad.exe.sha256", String(repeating: "0", count: 64))
        // Missing file
        try makeFile("gone.exe.sha256", String(repeating: "1", count: 64))
        // Parse error
        let junk = try makeFile("junk.exe", "abc")
        try makeFile("junk.exe.sha256", "not a hash at all")
        // Audit row: matches filter, no sidecar
        try makeFile("naked.exe", "abc")

        let results = try verify(target: tempDir.path, isFile: false)
        let byName = Dictionary(uniqueKeysWithValues: results.map {
            (($0.filePath as NSString).lastPathComponent, $0)
        })

        XCTAssertEqual(byName["bad.exe"]?.status, .mismatch)
        XCTAssertEqual(byName["gone.exe"]?.status, .missingFile)
        XCTAssertEqual(byName["junk.exe"]?.status, .parseError)
        XCTAssertEqual(byName["naked.exe"]?.status, .noSidecar)
        XCTAssertEqual(byName["bad.exe"]?.algorithm, .sha256)
        _ = bad; _ = junk
    }

    func testVerifyMixedAlgorithmsInOnePass() throws {
        let pMd5 = try makeFile("m.exe", "abc")
        try makeFile("m.exe.sha256", "900150983CD24FB0D6963F7D28E17F72")   // MD5 in .sha256
        let pSha1 = try makeFile("s.exe", "abc")
        try makeFile("s.exe.sha256", "A9993E364706816ABA3E25717850C26C9CD0D89D")

        let r1 = try verify(target: pMd5, isFile: true)
        XCTAssertEqual(r1[0].status, .ok)
        XCTAssertEqual(r1[0].algorithm, .md5)

        let r2 = try verify(target: pSha1, isFile: true)
        XCTAssertEqual(r2[0].status, .ok)
        XCTAssertEqual(r2[0].algorithm, .sha1)
    }

    func testVerifySidecarTargetedDirectly() throws {
        try makeFile("direct.exe", "abc")
        let sidecar = try makeFile("direct.exe.sha256",
            "BA7816BF8F01CFEA414140DE5DAE2223B00361A396177A9CB410FF61F20015AD *direct.exe")

        let results = try verify(target: sidecar, isFile: true)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].status, .ok)
        XCTAssertEqual((results[0].filePath as NSString).lastPathComponent, "direct.exe")
    }

    func testVerifyExtendedMetadataNotesDoNotFail() throws {
        let hash = "BA7816BF8F01CFEA414140DE5DAE2223B00361A396177A9CB410FF61F20015AD"
        let p = try makeFile("noted.exe", "abc")
        // Wrong embedded filename, ancient date, wrong size; hash still decides.
        try makeFile("noted.exe.sha256",
                     "\(hash) *other-name.exe *2000-01-01T00:00:00Z *999")

        let results = try verify(target: p, isFile: true)
        XCTAssertEqual(results[0].status, .ok)
        let detail = try XCTUnwrap(results[0].detail)
        XCTAssertTrue(detail.contains("differs"))
    }

    // ── CSV ──────────────────────────────────────────────────────────────────

    func testCsvEscape() {
        XCTAssertEqual(CsvExporter.escape("plain"), "plain")
        XCTAssertEqual(CsvExporter.escape("has,comma"), "\"has,comma\"")
        XCTAssertEqual(CsvExporter.escape("has\"quote"), "\"has\"\"quote\"")
    }

    func testCsvExportContentSortedSuccessOnlyWithBom() throws {
        let date = HashTimestamp.iso.date(from: "2026-08-09T14:33:05Z")
        let results = [
            HashResult(filePath: "/z/last.exe", hash: "BBBB", length: 2,
                       lastWriteUtc: date, success: true, errorMessage: nil),
            HashResult(filePath: "/a/first.exe", hash: "AAAA", length: 1,
                       lastWriteUtc: date, success: true, errorMessage: nil),
            HashResult(filePath: "/b/broken.exe", hash: "", length: nil,
                       lastWriteUtc: nil, success: false, errorMessage: "nope"),
        ]
        let out = tempDir.appendingPathComponent("out.csv").path
        try CsvExporter.export(results: results, algorithm: "SHA256",
                               includeMetadata: true, toPath: out)

        let data = try Data(contentsOf: URL(fileURLWithPath: out))
        XCTAssertEqual(Array(data.prefix(3)), [0xEF, 0xBB, 0xBF])

        let text = String(data: data.dropFirst(3), encoding: .utf8)!
        let lines = text.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines, [
            "Path,SHA256,LengthBytes,LastWriteUtc",
            "/a/first.exe,AAAA,1,2026-08-09T14:33:05Z",
            "/z/last.exe,BBBB,2,2026-08-09T14:33:05Z",
        ])
    }
}
