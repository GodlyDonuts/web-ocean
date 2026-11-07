import AppKit
@main struct InstallerTests {
    static func main() throws {
        let fm=FileManager.default
        let folder=fm.temporaryDirectory.appendingPathComponent("Ocean-install-test-"+UUID().uuidString)
        defer { try? fm.removeItem(at:folder) }
        let source=folder.appendingPathComponent("Download.app"),destination=folder.appendingPathComponent("Applications/Ocean.app")
        try fm.createDirectory(at:source.appendingPathComponent("Contents/MacOS"),withIntermediateDirectories:true)
        let executable=source.appendingPathComponent("Contents/MacOS/Ocean")
        try Data("test fixture, never executed".utf8).write(to:executable)
        try fm.setAttributes([.posixPermissions:0o755],ofItemAtPath:executable.path)
        try Data("original".utf8).write(to:source.appendingPathComponent("marker"))
        try OceanInstaller.stageCopy(source:source,destination:destination)
        let originalMarker=try Data(contentsOf:destination.appendingPathComponent("marker"))
        precondition(originalMarker==Data("original".utf8))
        let info=destination.appendingPathComponent("Contents/Info.plist")
        try PropertyListSerialization.data(fromPropertyList:["CFBundleIdentifier":"another.app"],format:.xml,options:0).write(to:info)
        do { try OceanInstaller.stageCopy(source:source,destination:destination);preconditionFailure("Cannot replace an unrelated app") } catch {}
        let preservedMarker=try Data(contentsOf:destination.appendingPathComponent("marker"))
        precondition(preservedMarker==Data("original".utf8))
        let broken=folder.appendingPathComponent("Broken.app");try fm.createDirectory(at:broken,withIntermediateDirectories:true)
        do { try OceanInstaller.stageCopy(source:broken,destination:folder.appendingPathComponent("New/Ocean.app"));preconditionFailure("Incomplete copy cannot be installed") } catch {}
        precondition(!fm.fileExists(atPath:folder.appendingPathComponent("New/Ocean.app").path))
        let remaining=try fm.contentsOfDirectory(atPath:destination.deletingLastPathComponent().path)
        precondition(remaining.allSatisfy { !$0.hasPrefix(".Ocean-install-") })
        print("PASS: complete staged installation, preservation of unrelated apps, rejected incomplete downloads and staging cleanup; no app launches or OS writes")
    }
}
