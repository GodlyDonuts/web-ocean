import AppKit

// Native controls retain keyboard navigation, VoiceOver and system appearance.
// Rendering/settings remain owned by the existing app, never by this window.
final class OceanControlWindow:NSWindowController {
    struct State {
        var paused=false
        var daylight="automatic"
        var weather:Int=0
        var quality:Int=1
        var login=false
        var status="Preparing Ocean…"
    }
    var closeOnStart=true
    var onStart:((Bool)->Void)?
    var onPause:(()->Void)?
    var onDaylight:((String)->Void)?
    var onWeather:((Int)->Void)?
    var onQuality:((Int)->Void)?
    var onLogin:((Bool)->Void)?
    var onRestore:(()->Void)?
    var onRepair:(()->Void)?
    var onSupport:(()->Void)?
    var onCancel:(()->Void)?
    private var statusLabel:NSTextField?
    private var pauseButton:NSButton?
    private var loginButton:NSButton?
    private var daylightPopup:NSPopUpButton?
    private var weatherPopup:NSPopUpButton?
    private var qualityPopup:NSPopUpButton?
    private var startButton:NSButton?
    private var welcome=false
    private let daylightValues=["automatic","sunrise","midday","goldenHour","sunset","midnight","custom"]

    init() {
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:580,height:570),styleMask:[.titled,.closable,.miniaturizable],backing:.buffered,defer:false)
        window.title="Ocean";window.isReleasedWhenClosed=false
        super.init(window:window)
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not supported") }
    private func text(_ value:String,size:CGFloat=13,weight:NSFont.Weight = .regular,secondary:Bool=false)->NSTextField {
        let label=NSTextField(wrappingLabelWithString:value)
        label.font = .systemFont(ofSize:size,weight:weight)
        label.textColor=secondary ? .secondaryLabelColor : .labelColor
        label.setContentCompressionResistancePriority(.required,for:.vertical)
        return label
    }
    private func button(_ title:String,_ action:Selector)->NSButton {
        let b=NSButton(title:title,target:self,action:action);b.bezelStyle = .rounded;return b
    }
    private func line()->NSBox { let box=NSBox();box.boxType = .separator;return box }
    private func row(_ title:String,_ control:NSView)->NSStackView {
        control.setAccessibilityLabel(title)
        let label=text(title,weight:.medium);label.widthAnchor.constraint(equalToConstant:136).isActive=true
        control.widthAnchor.constraint(equalToConstant:300).isActive=true
        let row=NSStackView(views:[label,control]);row.orientation = .horizontal;row.spacing=18;row.alignment = .centerY
        return row
    }
    private func feature(_ symbol:String,_ title:String,_ detail:String)->NSStackView {
        let image=NSImageView(image:NSImage(systemSymbolName:symbol,accessibilityDescription:nil) ?? NSImage())
        image.contentTintColor = .systemTeal;image.widthAnchor.constraint(equalToConstant:28).isActive=true
        let copy=NSStackView(views:[text(title,weight:.semibold),text(detail,size:12,secondary:true)])
        copy.orientation = .vertical;copy.alignment = .leading;copy.spacing=3
        let row=NSStackView(views:[image,copy]);row.orientation = .horizontal;row.spacing=14;return row
    }
    func show(welcome:Bool,state:State) {
        self.welcome=welcome
        let content=NSView();window?.contentView=content
        let stack=NSStackView();stack.orientation = .vertical;stack.alignment = .leading;stack.spacing=18
        stack.translatesAutoresizingMaskIntoConstraints=false;content.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo:content.leadingAnchor,constant:30),stack.trailingAnchor.constraint(equalTo:content.trailingAnchor,constant:-30),stack.topAnchor.constraint(equalTo:content.topAnchor,constant:28),stack.bottomAnchor.constraint(lessThanOrEqualTo:content.bottomAnchor,constant:-28)])
        let icon=NSImageView(image:Bundle.main.url(forResource:"Ocean",withExtension:"icns").flatMap(NSImage.init(contentsOf:)) ?? NSImage(systemSymbolName:"water.waves",accessibilityDescription:"Ocean")!)
        icon.widthAnchor.constraint(equalToConstant:64).isActive=true;icon.heightAnchor.constraint(equalToConstant:64).isActive=true
        let headings=NSStackView(views:[text(welcome ? "Your ocean, all day." : "Ocean",size:27,weight:.semibold),text(welcome ? "Live waves. Changing skies. Your own horizon." : "A little room to breathe on your Mac.",secondary:true)])
        headings.orientation = .vertical;headings.alignment = .leading;headings.spacing=4
        let header=NSStackView(views:[icon,headings]);header.orientation = .horizontal;header.spacing=16;stack.addArrangedSubview(header)
        if welcome {
            stack.addArrangedSubview(text("Ocean runs from the wave icon in your menu bar and sets up your wallpaper and screen saver. Restore your previous look anytime."))
            stack.addArrangedSubview(feature("sparkles","Set it once","Ocean handles setup for you, including the live lock screen on macOS 26."))
            stack.addArrangedSubview(feature("sun.horizon","Follows your day","Sunrise, sunset and weather follow your general area."))
            stack.addArrangedSubview(feature("leaf","Starts with balance","Power-saving defaults adapt to your battery and visible desktop."))
            let login=NSButton(checkboxWithTitle:"Start Ocean when I log in",target:nil,action:nil);login.state = .on;loginButton=login;stack.addArrangedSubview(login)
            stack.addArrangedSubview(text("Ocean uses your IP address’s general area for daylight and weather. No GPS or location permission is needed.",size:12,secondary:true))
            let start=button("Use Ocean",#selector(start));start.keyEquivalent="\r";startButton=start
            let actions=NSStackView(views:[button("Help & Privacy",#selector(help)),button("Not Now",#selector(cancel)),start]);actions.orientation = .horizontal;actions.spacing=12;stack.addArrangedSubview(actions)
        } else {
            let status=text(state.status,size:12,secondary:true);statusLabel=status;stack.addArrangedSubview(status)
            let daylight=NSPopUpButton();daylight.addItems(withTitles:["Follow Local Time","Sunrise","Midday","Golden Hour","Sunset","Midnight","Custom Time…"]);daylight.target=self;daylight.action=#selector(daylightChanged);daylightPopup=daylight
            stack.addArrangedSubview(row("Daylight",daylight))
            let weather=NSPopUpButton();weather.addItems(withTitles:["Follow Local Weather","Fair","Light Drizzle","Steady Rain","Thunderstorm","Hurricane"]);weather.target=self;weather.action=#selector(weatherChanged);weatherPopup=weather
            stack.addArrangedSubview(row("Weather",weather))
            let quality=NSPopUpButton();quality.addItems(withTitles:OceanProduct.qualities.map(\.title)+["Custom (Advanced)"]);quality.lastItem?.isEnabled=false;quality.target=self;quality.action=#selector(qualityChanged);qualityPopup=quality
            stack.addArrangedSubview(row("Performance",quality))
            stack.addArrangedSubview(text("Balanced adapts to battery, heat and covered windows. Save Energy uses less power; Sharper adds detail.",size:12,secondary:true))
            let login=NSButton(checkboxWithTitle:"Start Ocean when I log in",target:self,action:#selector(loginChanged));loginButton=login;stack.addArrangedSubview(login)
            stack.addArrangedSubview(line())
            let pause=button("Pause Animation",#selector(pause));pauseButton=pause
            let actions=NSStackView(views:[pause,button("Repair Setup",#selector(repair)),button("Turn Off Ocean…",#selector(restore))]);actions.orientation = .horizontal;actions.spacing=10;stack.addArrangedSubview(actions)
            let helpRow=NSStackView(views:[button("Help & Privacy",#selector(help)),button("Updates on GitHub",#selector(updates)),button("Copy Support Info",#selector(support))]);helpRow.orientation = .horizontal;helpRow.spacing=10;stack.addArrangedSubview(helpRow)
            let version=Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "development"
            stack.addArrangedSubview(text("Ocean \(version) · GitHub beta",size:11,secondary:true))
            update(state)
        }
        for view in stack.arrangedSubviews { view.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive=true }
        window?.setContentSize(NSSize(width:580,height:welcome ? 575 : 535))
        window?.center();showWindow(nil);window?.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
    }
    func update(_ state:State) {
        guard !welcome else { return }
        statusLabel?.stringValue=state.status
        daylightPopup?.selectItem(at:daylightValues.firstIndex(of:state.daylight) ?? 6)
        weatherPopup?.selectItem(at:max(0,min(5,state.weather)))
        qualityPopup?.selectItem(at:max(0,min(3,state.quality)))
        loginButton?.state=state.login ? .on : .off
        pauseButton?.title=state.paused ? "Resume Animation" : "Pause Animation"
    }
    @objc private func start() { startButton?.isEnabled=false;startButton?.title="Starting…";onStart?(loginButton?.state == .on);if closeOnStart { close() } }
    @objc private func cancel() { close();onCancel?() }
    @objc private func pause() { onPause?() }
    @objc private func daylightChanged() { if let i=daylightPopup?.indexOfSelectedItem { onDaylight?(daylightValues[i]) } }
    @objc private func weatherChanged() { onWeather?(weatherPopup?.indexOfSelectedItem ?? 0) }
    @objc private func qualityChanged() { onQuality?(qualityPopup?.indexOfSelectedItem ?? 1) }
    @objc private func loginChanged() { onLogin?(loginButton?.state == .on) }
    @objc private func restore() { onRestore?() }
    @objc private func repair() { onRepair?() }
    @objc private func support() { onSupport?() }
    @objc private func updates() { NSWorkspace.shared.open(OceanProduct.releases) }
    @objc private func help() { if let url=Bundle.main.url(forResource:"Help",withExtension:"html") { NSWorkspace.shared.open(url) } }
}
