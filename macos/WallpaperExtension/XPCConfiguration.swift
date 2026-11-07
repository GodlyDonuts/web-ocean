// Adapted from Aerial (MIT); see Aerial-LICENSE.
// XPC connection configuration for the wallpaper extension.
//
// Accepts incoming connections from WallpaperAgent, sets up class whitelists
// for all XPC type parameters, and wires up the handler.

import ExtensionFoundation
import Foundation

struct OceanWallpaperConfiguration: AppExtensionConfiguration {
    func accept(connection: NSXPCConnection) -> Bool {
        debugLog("XPC accept from PID=\(connection.processIdentifier)")

        let exported = NSXPCInterface(with: (any WallpaperExtensionXPCProtocol).self)

        let typeNames = [
            "WallpaperIDXPC",
            "WallpaperCreationRequestXPC",
            "WallpaperUpdateRequestXPC",
            "WallpaperRemoteContextXPC",
            "WallpaperSnapshotXPC",
            "WallpaperContentTypeSetXPC",
            "WallpaperChoiceIDXPC",
            "WallpaperChoiceIDsXPC",
            "WallpaperExtensionChoiceRequestXPC",
            "WallpaperChoiceRequestAdditionResultXPC",
            "WallpaperDebugRequestXPC",
            "WallpaperDebugResponseXPC",
            "WallpaperMigrationVersionXPC",
            "WallpaperSettingsViewModelsXPC",
            "AuditTokenXPC",
        ]

        let allTypes = NSMutableSet()
        var missing: [String] = []
        for name in typeNames {
            if let cls = objc_getClass(name) {
                allTypes.add(cls)
            } else {
                missing.append(name)
            }
        }
        if !missing.isEmpty {
            debugLog("  MISSING runtime types: \(missing.joined(separator: ", "))")
        }
        allTypes.add(NSString.self)
        allTypes.add(NSNumber.self)
        allTypes.add(NSData.self)
        allTypes.add(NSArray.self)
        allTypes.add(NSDictionary.self)
        allTypes.add(NSURL.self)
        allTypes.add(NSError.self)

        // Element-wise bridge (verified identical to the NSSet force-bridge
        // for ObjC class objects); an `as!` here would abort the extension
        // on the very first XPC accept.
        let classes = Set(allTypes.compactMap { $0 as? AnyHashable })
        if classes.count != allTypes.count {
            debugLog("  WARNING: class whitelist bridge dropped \(allTypes.count - classes.count) entries")
        }

        let selectors: [(Selector, Int, Bool)] = [
            (#selector(OceanWallpaperHandler.acquire(withId:request:reply:)), 0, false),
            (#selector(OceanWallpaperHandler.acquire(withId:request:reply:)), 1, false),
            (#selector(OceanWallpaperHandler.acquire(withId:request:reply:)), 0, true),
            (#selector(OceanWallpaperHandler.update(withId:request:reply:)), 0, false),
            (#selector(OceanWallpaperHandler.update(withId:request:reply:)), 1, false),
            (#selector(OceanWallpaperHandler.invalidate(withId:reply:)), 0, false),
            (#selector(OceanWallpaperHandler.snapshot(withId:reply:)), 0, false),
            (#selector(OceanWallpaperHandler.snapshot(withId:reply:)), 0, true),
            (#selector(OceanWallpaperHandler.provideSettingsViewModels(withContentTypes:reply:)), 0, false),
            (#selector(OceanWallpaperHandler.provideSettingsViewModels(withContentTypes:reply:)), 0, true),
            (#selector(OceanWallpaperHandler.addChoiceRequest(withChoiceRequest:onBehalfOfProcess:reply:)), 0, false),
            (#selector(OceanWallpaperHandler.addChoiceRequest(withChoiceRequest:onBehalfOfProcess:reply:)), 1, false),
            (#selector(OceanWallpaperHandler.addChoiceRequest(withChoiceRequest:onBehalfOfProcess:reply:)), 0, true),
            (#selector(OceanWallpaperHandler.removeChoiceRequest(withChoiceRequest:reply:)), 0, false),
            (#selector(OceanWallpaperHandler.selectedChoicesDidChange(for:reply:)), 0, false),
            (#selector(OceanWallpaperHandler.invokeContextMenuAction(withMenuItemID:groupItemID:reply:)), 0, false),
            (#selector(OceanWallpaperHandler.invokeContextMenuAction(withMenuItemID:groupItemID:reply:)), 1, false),
            (#selector(OceanWallpaperHandler.isChoiceDownloaded(with:reply:)), 0, false),
            (#selector(OceanWallpaperHandler.download(withChoiceID:reply:)), 0, false),
            (#selector(OceanWallpaperHandler.pauseDownload(for:reply:)), 0, false),
            (#selector(OceanWallpaperHandler.cancelDownload(for:reply:)), 0, false),
            (#selector(OceanWallpaperHandler.resumeDownload(for:reply:)), 0, false),
            (#selector(OceanWallpaperHandler.removeDownload(for:reply:)), 0, false),
            (#selector(OceanWallpaperHandler.migrateSelectedChoice(for:reply:)), 0, false),
            (#selector(OceanWallpaperHandler.migrateSelectedChoice(for:reply:)), 0, true),
            (#selector(OceanWallpaperHandler.migrate(from:to:reply:)), 0, false),
            (#selector(OceanWallpaperHandler.migrate(from:to:reply:)), 1, false),
            (#selector(OceanWallpaperHandler.skipShuffledContent(withId:reply:)), 0, false),
            (#selector(OceanWallpaperHandler.canSkipShuffledContent(withId:reply:)), 0, false),
            (#selector(OceanWallpaperHandler.handleDebugRequest(for:reply:)), 0, false),
            (#selector(OceanWallpaperHandler.handleDebugRequest(for:reply:)), 0, true),
            (#selector(OceanWallpaperHandler.handleNotification(withNamed:reply:)), 0, false),
        ]

        for (sel, idx, isReply) in selectors {
            exported.setClasses(classes, for: sel, argumentIndex: idx, ofReply: isReply)
        }

        connection.exportedInterface = exported
        connection.remoteObjectInterface = NSXPCInterface(with: (any WallpaperExtensionProxyXPCProtocol).self)

        let handler = OceanWallpaperHandler()
        connection.exportedObject = handler

        connection.interruptionHandler = { debugLog("XPC interrupted") }
        connection.invalidationHandler = {
            debugLog("XPC invalidated")
            // The agent dropped us (its 5-min idle disconnect); RunningBoard
            // suspends ~100 ms later and kills a process holding Metal's
            // file lock (0xDEAD10CC). When nothing is hosted, leave now —
            // the ONLY place a voluntary exit is safe: the agent has already
            // invalidated its proxy, so its next acquire launches a fresh
            // process. Exiting anywhere else leaves it with an interrupted
            // proxy and every acquire failing with 4099 (default saver).
            // May not return; the async line above can be lost and the
            // synchronous "🚪 idle exit" line is the record.
            DispatchQueue.main.async { OceanWallpaperWorld.releaseIfUnused() }
        }

        connection.resume()

        debugLog("XPC accepted")
        return true
    }
}
