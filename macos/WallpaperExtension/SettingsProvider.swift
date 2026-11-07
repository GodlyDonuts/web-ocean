// Adapted from Aerial (MIT); see Aerial-LICENSE.
// Settings view model — single "Aerial" entry in the picker.
//
// One choice in the picker, period. The extension dispatches per
// `directDisplayID` at acquire time, so the user enables this single
// Aerial entry on every screen they want and we render the correct
// content for each screen. (See WallpaperXPCHandler.colorForDisplay.)

import AppKit
import Foundation

private let aerialChoiceID = "ocean"
private let aerialDisplayName = "Ocean"

func buildSettingsViewModelsXPC() async -> AnyObject? {
    let bundleID = Bundle.main.bundleIdentifier ?? "local.wallpaper.ocean.live"
    let groupID = GroupID(id: "ocean-group")

    guard let thumbnailURL = aerialThumbnailURL() else {
        debugLog("  [Settings] Failed to generate thumbnail")
        return makeEmptyGroupsResponse()
    }

    let choiceID = ChoiceID(
        id: aerialChoiceID,
        descriptor: ChoiceIDDescriptor(
            provider: ChoiceProviderID(rawValue: bundleID),
            identifier: aerialChoiceID,
            files: [],
            configuration: Data(aerialChoiceID.utf8),
        ),
    )

    let choiceDescriptor = ChoiceDescriptor(
        id: choiceID,
        provider: ChoiceProviderID(rawValue: bundleID),
        identifier: aerialChoiceID,
        name: aerialDisplayName,
        localizedDescription: "Live Metal ocean",
        thumbnail: .image(url: thumbnailURL),
        isDownloaded: true,
        options: [],
    )

    let item = SettingsItem(
        id: choiceID,
        localizedName: aerialDisplayName,
        thumbnail: .image(url: thumbnailURL),
        choice: choiceDescriptor,
        contentBadge: .none,
        showInTopLevel: true,
        sortOrder: 0,
        disposability: .none,
    )

    let group = SettingsGroup(
        id: groupID,
        items: [item],
        localizedName: "Ocean",
        disposability: .none,
        sortOrder: -50,
        sortID: GroupSortID(id: "com.apple.wallpaper.aerials"),
        allChoiceID: nil,
        shouldHideItemLabels: false,
        contextMenu: nil,
        thumbnail: nil,
    )

    let viewModel = SettingsViewModel(
        groups: [group],
        refreshPolicy: .default,
        isModificationDisabled: false,
    )

    // Same Aerial group/item surfaced in both the Wallpaper picker
    // and the Screen Saver picker. WallpaperAgent's discovery uses the
    // non-nil `screenSaver:` field as the eligibility signal — Apple's
    // own WallpaperAerialsExtension does the same (Phosphene leaves it
    // nil and is wallpaper-only by choice).
    let viewModels = SettingsViewModels(
        desktop: viewModel,
        screenSaver: viewModel,
    )

    return remapToRealXPC(viewModels)
}

/// Fallback: empty groups view model.
func makeEmptyGroupsResponse() -> AnyObject? {
    let emptyViewModel = SettingsViewModel(
        groups: [],
        refreshPolicy: .default,
        isModificationDisabled: false,
    )
    let empty = SettingsViewModels(
        desktop: emptyViewModel,
        screenSaver: emptyViewModel,
    )
    return remapToRealXPC(empty)
}

/// Archive via ShimViewModelsXPC, remap class name on unarchive to WallpaperSettingsViewModelsXPC.
private func remapToRealXPC(_ viewModels: SettingsViewModels) -> AnyObject? {
    let shim = ShimViewModelsXPC(value: viewModels)

    let data: Data
    do {
        data = try NSKeyedArchiver.archivedData(withRootObject: shim, requiringSecureCoding: false)
    } catch {
        debugLog("  [Remap] Archive failed: \(error)")
        return nil
    }

    guard let realClass = objc_getClass("WallpaperSettingsViewModelsXPC") as? AnyClass else {
        debugLog("  [Remap] WallpaperSettingsViewModelsXPC class not found")
        return nil
    }

    guard let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: data) else {
        debugLog("  [Remap] Failed to create unarchiver")
        return nil
    }
    unarchiver.requiresSecureCoding = false
    unarchiver.decodingFailurePolicy = .setErrorAndReturn
    unarchiver.setClass(realClass, forClassName: "ShimViewModelsXPC")

    let result = unarchiver.decodeObject(forKey: NSKeyedArchiveRootObjectKey)
    if let error = unarchiver.error {
        debugLog("  [Remap] Unarchive error: \(error)")
    }
    unarchiver.finishDecoding()

    return result as AnyObject?
}


private func aerialThumbnailURL() -> URL? { Bundle.main.url(forResource:"OceanFallback",withExtension:"png") }
