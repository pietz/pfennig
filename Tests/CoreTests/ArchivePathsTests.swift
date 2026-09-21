import Core
import Foundation
import Testing

struct ArchivePathsTests {
    @Test func standardFolderMatchesBuild() {
        #if DEBUG
            let name = "Pfennig-Dev"
        #else
            let name = "Pfennig"
        #endif
        #expect(ArchivePaths.standard.folder == URL.applicationSupportDirectory.appending(
            path: name, directoryHint: .isDirectory
        ))
    }

    @Test func archiveContentsStayUnderSelectedFolder() {
        let folder = URL.temporaryDirectory.appending(path: "pfennig-path-test", directoryHint: .isDirectory)
        let paths = ArchivePaths(folder: folder)
        #expect(paths.databaseFile == folder.appending(path: "pfennig.sqlite"))
        #expect(paths.archive == folder.appending(path: "Archiv", directoryHint: .isDirectory))
        #expect(paths.inbox == folder.appending(path: "Inbox", directoryHint: .isDirectory))
    }
}
