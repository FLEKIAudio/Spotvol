// Spotvol – solange Spotify geöffnet ist, regeln die Lauter/Leiser-Tasten
// (oder selbst gewählte Tasten) die Spotify-Lautstärke in 5-%-Schritten.
// In der Menüleiste: Symbol + Mini-Balken + Prozent in einem dünnen Rahmen.
// Stumm-Taste (F10) schaltet Spotify stumm und wieder zurück.
//
// © 2026 FLEKIAudio

import Cocoa
import ServiceManagement

let spotifyID = "com.spotify.client"
let step = 5

// Sprache: Englisch (Standard) oder Deutsch – im Menü umschaltbar
var lang = UserDefaults.standard.string(forKey: "language") ?? "en"
func tr(_ en: String, _ de: String) -> String { lang == "de" ? de : en }

// Fehlerprotokoll – nur bei Problemen (z. B. Spotify antwortet nicht).
// Liegt lokal unter ~/Library/Logs/Spotvol/spotvol.log, max. ca. 100 KB.
// Spotvol sendet keine Daten ins Internet.
let logURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("Logs/Spotvol/spotvol.log")
func dlog(_ msg: String) {
    let fm = FileManager.default
    try? fm.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    if let size = (try? fm.attributesOfItem(atPath: logURL.path))?[.size] as? Int, size > 100_000 {
        try? fm.removeItem(at: logURL)
    }
    let line = "\(Date().formatted(date: .abbreviated, time: .standard))  \(msg)\n"
    if let h = try? FileHandle(forWritingTo: logURL) { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() }
    else { try? line.write(to: logURL, atomically: true, encoding: .utf8) }
}

// MARK: - Tastenbelegung

struct Hotkey: Equatable {
    var media: Int?          // Medientaste (0 = lauter, 1 = leiser, …)
    var keyCode = 0          // normale Taste
    var mods: UInt64 = 0
    var label = ""

    static let modMask = CGEventFlags.maskCommand.rawValue | CGEventFlags.maskAlternate.rawValue
        | CGEventFlags.maskControl.rawValue | CGEventFlags.maskShift.rawValue
    static let defaultUp = Hotkey(media: 0)
    static let defaultDown = Hotkey(media: 1)

    init(media: Int) { self.media = media }
    init(keyCode: Int, mods: UInt64, label: String) {
        self.keyCode = keyCode; self.mods = mods & Hotkey.modMask; self.label = label
    }
    init?(stored s: String?) {
        guard let p = s?.split(separator: "\t", omittingEmptySubsequences: false) else { return nil }
        if p.count == 2, p[0] == "m", let m = Int(p[1]) { self.init(media: m) }
        else if p.count == 4, p[0] == "k", let k = Int(p[1]), let m = UInt64(p[2]) { self.init(keyCode: k, mods: m, label: String(p[3])) }
        else { return nil }
    }
    var stored: String { media.map { "m\t\($0)" } ?? "k\t\(keyCode)\t\(mods)\t\(label)" }

    var name: String {
        if let m = media {
            return [0: tr("Volume Up key", "Lauter-Taste"), 1: tr("Volume Down key", "Leiser-Taste"),
                    2: tr("Brightness Up key", "Heller-Taste"), 3: tr("Brightness Down key", "Dunkler-Taste"),
                    7: tr("Mute key", "Stumm-Taste"), 16: "Play/Pause", 17: tr("Next key", "Vor-Taste"),
                    18: tr("Previous key", "Zurück-Taste")][m] ?? tr("Media key \(m)", "Medientaste \(m)")
        }
        var s = ""
        if mods & CGEventFlags.maskControl.rawValue != 0 { s += "⌃" }
        if mods & CGEventFlags.maskAlternate.rawValue != 0 { s += "⌥" }
        if mods & CGEventFlags.maskShift.rawValue != 0 { s += "⇧" }
        if mods & CGEventFlags.maskCommand.rawValue != 0 { s += "⌘" }
        let special: [Int: String] = [122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7",
            100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15",
            123: "←", 124: "→", 125: "↓", 126: "↑", 49: tr("Space", "Leertaste"), 36: "↩", 48: "⇥", 51: "⌫",
            116: tr("PgUp", "Bild↑"), 121: tr("PgDn", "Bild↓"), 115: tr("Home", "Pos1"), 119: tr("End", "Ende")]
        return s + (special[keyCode] ?? label)
    }
}

// MARK: - Menüleisten-Symbol (D1: dünner Rahmen um Symbol, Balken, Prozent)

func pillImage(volume: Int?, dashed: Bool, symbol: String) -> NSImage {
    let h: CGFloat = 18, pad: CGFloat = 7, gap: CGFloat = 5, barW: CGFloat = 22
    let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
    let text = volume.map { "\($0) %" as NSString }
    let textSize = text?.size(withAttributes: attrs) ?? .zero
    let boxW = ("100 %" as NSString).size(withAttributes: attrs).width   // feste Breite, damit nichts springt
    let sym = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)!
        .withSymbolConfiguration(.init(pointSize: 10, weight: .semibold))!
    var w = pad + sym.size.width + pad
    if text != nil { w += gap + barW + gap + boxW - 1 }

    let img = NSImage(size: NSSize(width: ceil(w), height: h), flipped: false) { rect in
        NSColor.black.set()
        let border = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: (h - 1) / 2, yRadius: (h - 1) / 2)
        border.lineWidth = 1
        if dashed { border.setLineDash([2.5, 2], count: 2, phase: 0) }
        border.stroke()

        var x = pad
        sym.draw(in: NSRect(x: x, y: (h - sym.size.height) / 2, width: sym.size.width, height: sym.size.height))
        x += sym.size.width
        if let text, let v = volume {
            x += gap
            let bar = NSRect(x: x, y: (h - 4) / 2, width: barW, height: 4)
            NSColor.black.withAlphaComponent(0.3).setFill()
            NSBezierPath(roundedRect: bar, xRadius: 2, yRadius: 2).fill()
            var fill = bar
            fill.size.width = barW * CGFloat(v) / 100
            NSColor.black.setFill()
            if fill.width > 0 { NSBezierPath(roundedRect: fill, xRadius: 2, yRadius: 2).fill() }
            x += barW + gap
            text.draw(at: NSPoint(x: x + boxW - textSize.width, y: (h - textSize.height) / 2), withAttributes: attrs)
        }
        return true
    }
    img.isTemplate = true   // passt sich hell/dunkel automatisch an
    return img
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let d = UserDefaults.standard
    var statusItem: NSStatusItem!
    var tap: CFMachPort?
    var tapSource: CFRunLoopSource?
    var spotifyRunning = false
    var volume: Int?                   // angezeigte Spotify-Lautstärke
    var lastSet = Date.distantPast     // wann wir zuletzt selbst gesetzt haben
    var lastSliderSend = Date.distantPast
    var swallowedKeys = Set<Int>()

    var enabled: Bool {
        get { d.object(forKey: "enabled") as? Bool ?? true }
        set { d.set(newValue, forKey: "enabled"); updateIcon() }
    }
    var upKey: Hotkey {
        get { Hotkey(stored: d.string(forKey: "keyUp")) ?? .defaultUp }
        set { d.set(newValue.stored, forKey: "keyUp") }
    }
    var downKey: Hotkey {
        get { Hotkey(stored: d.string(forKey: "keyDown")) ?? .defaultDown }
        set { d.set(newValue.stored, forKey: "keyDown") }
    }
    // Zwischengespeichert, damit der Tasten-Abfang nicht jedes Mal UserDefaults liest
    var up = Hotkey.defaultUp, down = Hotkey.defaultDown

    // Menü
    let menu = NSMenu()
    var slider: NSSlider!
    var sliderLabel: NSTextField!
    var enabledItem: NSMenuItem!
    var keysItem: NSMenuItem!
    var loginItem: NSMenuItem!
    var warnItem: NSMenuItem!

    // Tasten aufnehmen
    var recording: Int?                // 0 = wartet auf „lauter“, 1 = auf „leiser“
    var pendingUp: Hotkey?
    var recorderPanel: NSPanel?
    var recorderLabel: NSTextField!

    func applicationDidFinishLaunching(_ n: Notification) {
        up = upKey; down = downKey
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        buildMenu()
        statusItem.menu = menu

        spotifyRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: spotifyID).isEmpty
        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let self, (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?
                        .bundleIdentifier == spotifyID else { return }
                self.spotifyRunning = name == NSWorkspace.didLaunchApplicationNotification
                self.volume = nil
                self.updateIcon()
                if self.spotifyRunning {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.pollVolume() }
                }
            }
        }
        // Lautstärke abgleichen, falls sie direkt in Spotify geändert wird (nur wenn Spotify läuft)
        let t = Timer(timeInterval: 3, repeats: true) { [weak self] _ in self?.pollVolume() }
        RunLoop.main.add(t, forMode: .common)

        installTap(prompt: true)
        pollVolume()
        updateIcon()
    }

    // MARK: Symbol

    func updateIcon() {
        guard let button = statusItem.button else { return }
        let image: NSImage
        if tap == nil {
            image = pillImage(volume: nil, dashed: false, symbol: "exclamationmark.triangle")
        } else if !enabled {
            image = pillImage(volume: nil, dashed: false, symbol: "speaker.slash.fill")
        } else if !spotifyRunning {
            image = pillImage(volume: nil, dashed: true, symbol: "speaker.wave.2.fill")
        } else {
            image = pillImage(volume: volume, dashed: false, symbol: volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
        }
        button.image = image
        button.appearsDisabled = !enabled
        button.toolTip = tap == nil ? tr("Spotvol: Accessibility access missing", "Spotvol: Bedienungshilfen-Zugriff fehlt")
            : !enabled ? tr("Spotvol: off", "Spotvol: aus")
            : spotifyRunning ? tr("Spotvol: Spotify volume", "Spotvol: Spotify-Lautstärke")
            : tr("Spotvol: waiting for Spotify", "Spotvol: wartet auf Spotify")
    }

    // MARK: Spotify

    func spotify(_ cmd: String) -> NSAppleEventDescriptor? {
        guard spotifyRunning else { return nil }
        var err: NSDictionary?
        let r = NSAppleScript(source: "tell application id \"\(spotifyID)\" to \(cmd)")?.executeAndReturnError(&err)
        if let err { dlog("\(err)") }
        return err == nil ? r : nil
    }

    func pollVolume() {
        guard spotifyRunning, enabled, recording == nil,
              Date().timeIntervalSince(lastSet) > 2,
              let v = spotify("get sound volume").map({ Int($0.int32Value) }) else { return }
        // Spotify meldet nach dem Setzen manchmal 1 % weniger – das ignorieren wir
        if let cur = volume, abs(cur - v) <= 1 { return }
        volume = v
        updateIcon()
        if menu.highlightedItem == nil { slider?.integerValue = v; sliderLabel?.stringValue = "\(v) %" }
    }

    func setVolume(_ value: Int) {
        let v = max(0, min(100, value))
        _ = spotify("set sound volume to \(v)")
        volume = v
        lastSet = Date()
        updateIcon()
        slider?.integerValue = v
        sliderLabel?.stringValue = "\(v) %"
    }

    func changeVolume(by delta: Int) {
        let base = (Date().timeIntervalSince(lastSet) < 2 ? volume : nil)
            ?? spotify("get sound volume").map { Int($0.int32Value) }
        guard let base else { dlog("Konnte Spotify-Lautstärke nicht lesen"); return }
        setVolume(base + delta)
    }

    var volumeBeforeMute: Int?

    func toggleMute() {
        let cur = (Date().timeIntervalSince(lastSet) < 2 ? volume : nil)
            ?? spotify("get sound volume").map { Int($0.int32Value) }
        guard let cur else { dlog("Konnte Spotify-Lautstärke nicht lesen"); return }
        if cur > 0 {
            volumeBeforeMute = cur
            setVolume(0)
        } else {
            setVolume(volumeBeforeMute ?? 30)
        }
    }

    // MARK: Tasten abfangen

    var needsKeyEvents: Bool { recording != nil || up.media == nil || down.media == nil }

    func installTap(prompt: Bool) {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        if AXIsProcessTrustedWithOptions(opts), createTap() {
            updateIcon(); warnItem?.isHidden = true
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.installTap(prompt: false) }
        }
    }

    @discardableResult
    func createTap() -> Bool {
        if let t = tap { CGEvent.tapEnable(tap: t, enable: false); CFMachPortInvalidate(t) }
        if let s = tapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), s, .commonModes) }
        tap = nil; tapSource = nil
        // Medientasten immer; normale Tasten nur, wenn eigene Tasten gewählt sind
        var mask = CGEventMask(1 << 14)
        if needsKeyEvents { mask |= CGEventMask(1 << CGEventType.keyDown.rawValue) | CGEventMask(1 << CGEventType.keyUp.rawValue) }
        guard let t = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap,
                                        eventsOfInterest: mask, callback: tapCallback,
                                        userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        tap = t
        tapSource = CFMachPortCreateRunLoopSource(nil, t, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), tapSource, .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
        return true
    }

    /// true = Ereignis schlucken
    func handle(type: CGEventType, event: CGEvent) -> Bool {
        var media: Int?
        var keyCode = 0
        let isDown: Bool
        if type.rawValue == 14 {
            guard let ns = NSEvent(cgEvent: event), ns.subtype.rawValue == 8 else { return false }
            media = (ns.data1 & 0xFFFF0000) >> 16
            isDown = (ns.data1 & 0xFF00) >> 8 == 0x0A
        } else if type == .keyDown || type == .keyUp {
            keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
            isDown = type == .keyDown
        } else { return false }

        // Neue Tasten aufnehmen
        if recording != nil {
            guard isDown else { return true }
            if media == nil && keyCode == 53 { DispatchQueue.main.async { self.finishRecording() }; return true } // esc
            let hk = media.map { Hotkey(media: $0) } ?? Hotkey(keyCode: keyCode, mods: event.flags.rawValue,
                label: NSEvent(cgEvent: event)?.charactersIgnoringModifiers?.uppercased() ?? "?")
            DispatchQueue.main.async { self.recorded(hk) }
            return true
        }

        guard enabled, spotifyRunning else { return false }
        // Stumm-Taste (F10): Spotify stumm schalten / wieder herstellen
        if let m = media, m == 7, up.media != 7, down.media != 7 {
            if isDown { DispatchQueue.main.async { self.toggleMute() } }
            return true
        }
        let isUp: Bool
        if let m = media {
            guard up.media == m || down.media == m else { return false }
            isUp = up.media == m
        } else {
            if !isDown { return swallowedKeys.remove(keyCode) != nil }
            let mods = event.flags.rawValue & Hotkey.modMask
            let hit = { (h: Hotkey) in h.media == nil && h.keyCode == keyCode && h.mods == mods }
            guard hit(up) || hit(down) else { return false }
            isUp = hit(up)
            swallowedKeys.insert(keyCode)
        }
        if isDown { DispatchQueue.main.async { self.changeVolume(by: isUp ? step : -step) } }
        return true
    }

    // MARK: Menü

    func buildMenu() {
        menu.delegate = self
        menu.autoenablesItems = false

        warnItem = NSMenuItem(title: tr("⚠️ Allow Accessibility …", "⚠️ Bedienungshilfen erlauben …"), action: #selector(openAccessibility), keyEquivalent: "")
        warnItem.target = self
        menu.addItem(warnItem)

        let view = NSView(frame: NSRect(x: 0, y: 0, width: 250, height: 30))
        slider = NSSlider(value: 50, minValue: 0, maxValue: 100, target: self, action: #selector(sliderMoved))
        slider.frame = NSRect(x: 16, y: 5, width: 180, height: 20)
        slider.isContinuous = true
        sliderLabel = NSTextField(labelWithString: "– %")
        sliderLabel.frame = NSRect(x: 198, y: 7, width: 40, height: 16)
        sliderLabel.alignment = .right
        sliderLabel.textColor = .secondaryLabelColor
        sliderLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        view.addSubview(slider); view.addSubview(sliderLabel)
        let sliderItem = NSMenuItem()
        sliderItem.view = view
        menu.addItem(sliderItem)
        menu.addItem(.separator())

        enabledItem = item(tr("Active", "Aktiv"), #selector(toggleEnabled))
        keysItem = item("", #selector(startRecording))
        loginItem = item(tr("Launch at login", "Beim Anmelden starten"), #selector(toggleLogin))

        // Sprache / Language
        let langItem = NSMenuItem(title: tr("Language", "Sprache"), action: nil, keyEquivalent: "")
        let langMenu = NSMenu()
        for (code, name) in [("en", "English"), ("de", "Deutsch")] {
            let it = NSMenuItem(title: name, action: #selector(setLanguage(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = code
            it.state = lang == code ? .on : .off
            langMenu.addItem(it)
        }
        langItem.submenu = langMenu
        menu.addItem(langItem)
        menu.addItem(.separator())
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let about = NSMenuItem(title: "Spotvol \(version) · © 2026 FLEKIAudio", action: nil, keyEquivalent: "")
        about.isEnabled = false
        menu.addItem(about)
        menu.addItem(NSMenuItem(title: tr("Quit", "Beenden"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    func item(_ title: String, _ sel: Selector) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: sel, keyEquivalent: "")
        it.target = self
        menu.addItem(it)
        return it
    }

    func menuWillOpen(_ menu: NSMenu) {
        warnItem.isHidden = tap != nil
        if spotifyRunning, let v = spotify("get sound volume").map({ Int($0.int32Value) }) {
            if volume == nil || abs(volume! - v) > 1 || Date().timeIntervalSince(lastSet) > 2 { volume = v }
            updateIcon()
        }
        slider.isEnabled = spotifyRunning && volume != nil
        slider.integerValue = volume ?? 0
        sliderLabel.stringValue = slider.isEnabled ? "\(volume!) %" : "– %"
        enabledItem.state = enabled ? .on : .off
        keysItem.title = tr("Keys: \(up.name) / \(down.name)   change …", "Tasten: \(up.name) / \(down.name)   ändern …")
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc func sliderMoved() {
        let v = slider.integerValue
        sliderLabel.stringValue = "\(v) %"
        let mouseUp = NSApp.currentEvent?.type == .leftMouseUp
        // Beim Ziehen höchstens 4× pro Sekunde an Spotify senden, beim Loslassen immer
        if mouseUp || Date().timeIntervalSince(lastSliderSend) > 0.25 {
            lastSliderSend = Date()
            setVolume(v)
        } else {
            volume = v; updateIcon()
        }
    }

    @objc func toggleEnabled() { enabled.toggle() }

    @objc func setLanguage(_ sender: NSMenuItem) {
        guard let code = sender.representedObject as? String, code != lang else { return }
        lang = code
        d.set(code, forKey: "language")
        // Menü und Tasten-Fenster in der neuen Sprache neu aufbauen
        menu.removeAllItems()
        buildMenu()
        recorderPanel?.close()
        recorderPanel = nil
        updateIcon()
    }

    @objc func toggleLogin() {
        let s = SMAppService.mainApp
        try? (s.status == .enabled ? s.unregister() : s.register())
    }

    @objc func openAccessibility() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    // MARK: Tasten ändern

    @objc func startRecording() {
        guard tap != nil else { openAccessibility(); return }
        if recorderPanel == nil { buildRecorder() }
        recording = 0
        pendingUp = nil
        recorderLabel.stringValue = tr("Now press the key for VOLUME UP", "Drücke jetzt die Taste für LAUTER")
        createTap()
        NSApp.activate(ignoringOtherApps: true)
        recorderPanel?.center()
        recorderPanel?.makeKeyAndOrderFront(nil)
    }

    func buildRecorder() {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 130),
                        styleMask: [.titled, .closable], backing: .buffered, defer: false)
        p.title = tr("Spotvol – Set keys", "Spotvol – Tasten festlegen")
        p.isReleasedWhenClosed = false
        p.level = .floating
        let v = p.contentView!
        recorderLabel = NSTextField(labelWithString: "")
        recorderLabel.font = .systemFont(ofSize: 15, weight: .medium)
        recorderLabel.alignment = .center
        recorderLabel.frame = NSRect(x: 10, y: 74, width: 340, height: 24)
        let hint = NSTextField(labelWithString: tr("Combinations like ⌥ + ↑ work too · esc = cancel", "Auch Kombinationen wie ⌥ + ↑ gehen · esc = abbrechen"))
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.alignment = .center
        hint.frame = NSRect(x: 10, y: 52, width: 340, height: 16)
        let reset = NSButton(title: tr("Default (volume keys)", "Standard (Lautstärketasten)"), target: self, action: #selector(resetKeys))
        reset.frame = NSRect(x: 16, y: 12, width: 210, height: 28)
        let cancel = NSButton(title: tr("Cancel", "Abbrechen"), target: self, action: #selector(cancelRecording))
        cancel.frame = NSRect(x: 240, y: 12, width: 104, height: 28)
        [recorderLabel, hint, reset, cancel].forEach { v.addSubview($0) }
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: p, queue: .main) { [weak self] _ in
            if self?.recording != nil { self?.finishRecording() }
        }
        recorderPanel = p
    }

    func recorded(_ hk: Hotkey) {
        guard let r = recording else { return }
        if r == 0 {
            pendingUp = hk
            recording = 1
            recorderLabel.stringValue = tr("Up: \(hk.name) – now the key for VOLUME DOWN", "Lauter: \(hk.name) – jetzt die Taste für LEISER")
        } else if hk == pendingUp {
            recorderLabel.stringValue = tr("Please pick a different key for VOLUME DOWN", "Bitte eine andere Taste für LEISER")
        } else if let u = pendingUp {
            upKey = u; downKey = hk
            up = u; down = hk
            recorderLabel.stringValue = tr("Saved: \(u.name) / \(hk.name)", "Gespeichert: \(u.name) / \(hk.name)")
            recording = nil
            createTap()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in self?.recorderPanel?.orderOut(nil) }
        }
    }

    @objc func resetKeys() {
        upKey = .defaultUp; downKey = .defaultDown
        up = .defaultUp; down = .defaultDown
        finishRecording()
    }

    @objc func cancelRecording() { finishRecording() }

    func finishRecording() {
        recording = nil
        pendingUp = nil
        createTap()
        recorderPanel?.orderOut(nil)
    }
}

let tapCallback: CGEventTapCallBack = { _, type, event, refcon in
    let app = Unmanaged<AppDelegate>.fromOpaque(refcon!).takeUnretainedValue()
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let t = app.tap { CGEvent.tapEnable(tap: t, enable: true) }
        return Unmanaged.passUnretained(event)
    }
    return app.handle(type: type, event: event) ? nil : Unmanaged.passUnretained(event)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
ProcessInfo.processInfo.disableAutomaticTermination("Spotvol läuft im Hintergrund")
ProcessInfo.processInfo.disableSuddenTermination()
app.run()
