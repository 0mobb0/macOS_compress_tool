import XCTest
@testable import ZipCore

final class ZipCoreTests: XCTestCase {
    var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    func file(_ name: String, text: String = "hello 中文 🌏") throws -> URL {
        let url = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        return url
    }
    var output: URL { root.appendingPathComponent("output.zip") }
    func assertClean() throws {
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: root.path).contains { $0.hasPrefix(".cleanzip-") })
    }
    func testUnicodeHeadersAndMetadata() throws {
        _ = try file("资料/你好🌏.txt")
        _ = try file("资料/.DS_Store"); _ = try file("资料/._你好.txt")
        _ = try file("资料/__MACOSX/junk")
        try ZipWriter.create(sources: [root.appendingPathComponent("资料")], destination: output)
        let data = try Data(contentsOf: output)
        XCTAssertEqual(Array(data[6..<8]), [0, 8])
        XCTAssertNotNil(data.range(of: Data("资料/你好🌏.txt".utf8)))
        XCTAssertNil(data.range(of: Data(".DS_Store".utf8)))
        XCTAssertNil(data.range(of: Data("__MACOSX".utf8)))
        XCTAssertNotNil(data.range(of: Data([0x75, 0x70])))
    }
    func testExistingDestinationPreserved() throws {
        let source = try file("输入.txt")
        let old = Data("keep me".utf8); try old.write(to: output)
        XCTAssertThrowsError(try ZipWriter.create(sources: [source], destination: output))
        XCTAssertEqual(try Data(contentsOf: output), old)
    }
    func testInvalidWindowsNames() throws {
        for name in ["CON.txt", "a:b.txt", "尾部.", "尾部 ", "LPT1", "COM¹.txt"] {
            let source = try file(name)
            XCTAssertThrowsError(try ZipWriter.create(sources: [source], destination: output), name)
        }
        try assertClean()
    }
    func testDuplicateBasenames() throws {
        let a = try file("a/报告.txt"), b = try file("b/报告.txt")
        XCTAssertThrowsError(try ZipWriter.create(sources: [a, b], destination: output))
        try assertClean()
    }
    func testCaseInsensitiveNames() throws {
        let a = try file("a/Report.txt"), b = try file("b/report.txt")
        XCTAssertThrowsError(try ZipWriter.create(sources: [a, b], destination: output))
        try assertClean()
    }
    func testCanonicalNormalizationCollision() throws {
        let a = try file("a/café.txt"), b = try file("b/cafe\u{301}.txt")
        XCTAssertThrowsError(try ZipWriter.create(sources: [a, b], destination: output))
    }
    func testEmptyFolderAndEmptyFile() throws {
        _ = try file("folder/empty.txt", text: "")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("folder/空目录"), withIntermediateDirectories: true)
        try ZipWriter.create(sources: [root.appendingPathComponent("folder")], destination: output)
        XCTAssertNotNil(try Data(contentsOf: output).range(of: Data("folder/空目录/".utf8)))
    }
    func testSymbolicLinkRejected() throws {
        let target = try file("target")
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        XCTAssertThrowsError(try ZipWriter.create(sources: [link], destination: output))
        try assertClean()
    }
    func testOutputInsideSourceRejected() throws {
        _ = try file("folder/a.txt")
        XCTAssertThrowsError(try ZipWriter.create(sources: [root.appendingPathComponent("folder")], destination: root.appendingPathComponent("folder/archive.zip")))
    }
    func testCancellationCleansPartialArchive() throws {
        let source = try file("test.txt")
        let token = Cancellation()
        XCTAssertThrowsError(try ZipWriter.create(sources: [source], destination: output, cancellation: token) { _ in token.cancel() })
        try assertClean()
    }
    func testEmptyInputAndOnlyMetadata() throws {
        XCTAssertThrowsError(try ZipWriter.create(sources: [], destination: output))
        XCTAssertThrowsError(try ZipWriter.create(sources: [try file(".DS_Store")], destination: output))
        try assertClean()
    }
    func testLargeFileRejectedWithoutReading() throws {
        let source = try file("large.bin", text: "")
        let handle = try FileHandle(forWritingTo: source)
        try handle.truncate(atOffset: UInt64(UInt32.max)); try handle.close()
        XCTAssertThrowsError(try ZipWriter.create(sources: [source], destination: output))
        try assertClean()
    }
    func testDestinationAppearingDuringCompressionIsPreserved() throws {
        let source = try file("source.txt")
        let old = Data("someone else's file".utf8)
        XCTAssertThrowsError(try ZipWriter.create(sources: [source], destination: output) { p in
            if p.completed == 0 { try! old.write(to: self.output) }
        })
        XCTAssertEqual(try Data(contentsOf: output), old)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: root.path).contains { $0.hasPrefix(".cleanzip-") })
    }
}
