import AppKit
// Explicitly launched design review only. This executable has no rendering,
// installer, login-item, weather-provider or wallpaper-store implementation.
final class Review:NSObject,NSApplicationDelegate {
    let ui=OceanControlWindow()
    var state=OceanControlWindow.State(status:"Preview · no settings are being changed")
    func applicationDidFinishLaunching(_ notification:Notification) {
        ui.closeOnStart=false
        ui.onStart={ [weak self] _ in if let self { self.ui.show(welcome:false,state:self.state) } }
        ui.onPause={ [weak self] in guard let self else { return };state.paused.toggle();ui.update(state) }
        ui.onDaylight={ [weak self] value in guard let self else { return };state.daylight=value;ui.update(state) }
        ui.onWeather={ [weak self] value in guard let self else { return };state.weather=value;ui.update(state) }
        ui.onQuality={ [weak self] value in guard let self else { return };state.quality=value;ui.update(state) }
        ui.onLogin={ [weak self] value in guard let self else { return };state.login=value;ui.update(state) }
        ui.onCancel={ NSApp.terminate(nil) }
        ui.onRepair={ [weak self] in guard let self else { return };state.status="Preview · setup would be repaired";ui.update(state) }
        ui.onRestore={ [weak self] in guard let self else { return };state.status="Preview · previous wallpaper would be restored";ui.update(state) }
        ui.show(welcome:true,state:state)
    }
    func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows flag:Bool)->Bool {
        ui.window?.deminiaturize(nil);ui.showWindow(nil);ui.window?.makeKeyAndOrderFront(nil);return true
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool { true }
}
@main struct ProductUIReview {
    static func main() {
        let app=NSApplication.shared;let delegate=Review();app.delegate=delegate;app.setActivationPolicy(.regular);app.run()
    }
}
