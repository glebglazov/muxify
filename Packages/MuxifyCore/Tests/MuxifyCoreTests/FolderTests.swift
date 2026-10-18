import XCTest
@testable import MuxifyCore

final class FolderTests: XCTestCase {
    func testALocalFolderThatIsGoneComparesThroughItsNearestParent() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        defer { try? FileManager.default.removeItem(atPath: root) }
        try FileManager.default.createDirectory(atPath: root + "/work", withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: root + "/link", withDestinationPath: "work")
        let gone = Folder.local(root + "/link/removed/tree")
        XCTAssertEqual(gone.path, root + "/link/removed/tree", "the spelling stays as given")
        XCTAssertEqual(gone.real, String(cString: realpath(root + "/work", nil)) + "/removed/tree")
        XCTAssertTrue(Folder.local(root + "/link").contains(gone))
    }

    func testAnEmptyPathHoldsNoFolderAndNoFolderHoldsIt() {
        let empty = Folder.local("")
        XCTAssertFalse(empty.contains(Folder.local("/tmp")))
        XCTAssertFalse(Folder.local("/").contains(empty))
    }

    func testARemoteResolverMapsEitherSpellingThroughTheFoldersFoundThere() {
        let resolver = FolderResolver.known([Folder(path: "/h/Dev/app", real: "/h/real/app"), Folder(path: "/", real: "/")])
        let spellings = { (path: String) in [resolver.folder(path).path, resolver.folder(path).real] }
        XCTAssertEqual(spellings("/h/Dev/app/src/../lib"), ["/h/Dev/app/lib", "/h/real/app/lib"], "a Config spelling gets its real path")
        XCTAssertEqual(spellings("/h/real/app/lib"), ["/h/Dev/app/lib", "/h/real/app/lib"], "a real path gets its Config spelling")
        XCTAssertEqual(spellings("/srv/data"), ["/srv/data", "/srv/data"], "a folder under the root is not //srv/data")
    }
}
