import AppKit
import SpriteKit

/// Hält das Spielfeld im Seitenverhältnis 3:2. Der übrige Fenstergrund ist das Blau der Leiste, nicht Schwarz.
final class StageView: NSView {
    let game = SKView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = Palette.chrome.cgColor
        addSubview(game)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        let aspect: CGFloat = 1.5
        var width = bounds.width
        var height = width / aspect
        if height > bounds.height {
            height = bounds.height
            width = height * aspect
        }
        let fitted = NSRect(
            x: floor((bounds.width - width) / 2),
            y: floor((bounds.height - height) / 2),
            width: max(1, floor(width)),
            height: max(1, floor(height)))
        game.frame = fitted
    }
}

@main
enum AppMain {
    static func main() {
        if CommandLine.arguments.contains("--self-test") {
            Sim.runTests()
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow!
    private var scene: GameScene!
    private var activity: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .latencyCritical],
            reason: "Klinker läuft")
        buildMenu()
        buildWindow()
        if #available(macOS 14, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationDidResignActive(_ notification: Notification) {
        scene?.suspend()
    }

    func applicationWillTerminate(_ notification: Notification) {
        scene?.persist()
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        scene?.persist()
        return true
    }

    func windowDidBecomeKey(_ notification: Notification) {
        if let view = window.contentView { window.makeFirstResponder(view) }
    }

    private func buildWindow() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1080, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false)
        window.title = "Klinker"
        window.delegate = self
        window.isRestorable = false
        window.tabbingMode = .disallowed
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.contentMinSize = NSSize(width: 900, height: 600)
        window.setContentSize(NSSize(width: 1080, height: 720))
        window.backgroundColor = Palette.chrome
        window.acceptsMouseMovedEvents = true

        let stage = StageView(frame: window.contentRect(forFrameRect: window.frame))
        let view = stage.game
        view.ignoresSiblingOrder = true
        view.allowsTransparency = false
        // Sonst zeichnet SpriteKit am Fenster vorbei. Ein bewegter Ball bleibt dann
        // zwei-, dreimal sichtbar, obwohl im einzelnen Bild nur eine Kugel liegt.
        view.isAsynchronous = false
        view.wantsLayer = true
        view.layer?.backgroundColor = Palette.chrome.cgColor

        let game = GameScene(size: CGSize(width: 1200, height: 800))
        game.scaleMode = .aspectFit
        game.backgroundColor = Palette.chrome
        view.presentScene(game)
        window.contentView = stage
        stage.layoutSubtreeIfNeeded()
        let refresh = window.screen?.maximumFramesPerSecond ?? 60
        view.preferredFramesPerSecond = max(60, refresh)
        scene = game
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)
    }

    private func buildMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu
        appMenu.addItem(item("Über Klinker", #selector(showAbout(_:)), "", self))
        appMenu.addItem(.separator())
        appMenu.addItem(item("Klinker ausblenden", #selector(NSApplication.hide(_:)), "h", NSApp))
        appMenu.addItem(.separator())
        appMenu.addItem(item("Klinker beenden", #selector(NSApplication.terminate(_:)), "q", NSApp))

        let gameItem = NSMenuItem()
        main.addItem(gameItem)
        let gameMenu = NSMenu(title: "Spiel")
        gameItem.submenu = gameMenu
        gameMenu.addItem(item("Menü", #selector(showMenu(_:)), "e", self))
        gameMenu.addItem(item("Neues Spiel", #selector(newGame(_:)), "n", self))
        gameMenu.addItem(item("Pause", #selector(pauseGame(_:)), "p", self))
        gameMenu.addItem(item("Ton an oder aus", #selector(muteGame(_:)), "t", self))
        gameMenu.addItem(item("Vollbild", #selector(fullScreen(_:)), "f", self))

        let windowItem = NSMenuItem()
        main.addItem(windowItem)
        let windowMenu = NSMenu(title: "Fenster")
        windowItem.submenu = windowMenu
        windowMenu.addItem(item("Schließen", #selector(NSWindow.performClose(_:)), "w", nil))
        windowMenu.addItem(item("Minimieren", #selector(NSWindow.performMiniaturize(_:)), "m", nil))
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = main
    }

    private func item(_ title: String, _ action: Selector, _ key: String, _ target: AnyObject?) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: key)
        entry.target = target
        return entry
    }

    @objc private func showMenu(_ sender: Any?) { scene?.openMenu() }
    @objc private func newGame(_ sender: Any?) { scene?.resetGame() }
    @objc private func pauseGame(_ sender: Any?) { scene?.togglePause() }
    @objc private func muteGame(_ sender: Any?) { scene?.toggleMute() }
    @objc private func fullScreen(_ sender: Any?) { window.toggleFullScreen(nil) }

    @objc private func showAbout(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "Klinker"
        alert.informativeText = """
        Ein nativer Mauerbrecher für den Mac, angelehnt an LBreakout2.

        Bunte Steinreihen, ein Schläger, Bälle, Punkte, Leben und Runden. Bild und Ton sind eigen.

        Beim Start wählst du einen Spieler. Jeder behält seinen Rekord und den letzten Stand. Wechselst du den Spieler, liegt dort wieder die Runde, in der er aufgehört hat. Beim Schließen wird der Stand gespeichert.

        Unter Steuerung stellst du Maus oder Tasten ein. Leertaste oder Klick wirft den Ball. P pausiert, M schaltet den Ton, F schaltet auf Vollbild.

        Manche Steine lassen eine Bildkapsel fallen. Jede Runde mischt neu, und es ist immer ein Malus dabei. Boni: breiterer Schläger, Extra-Ball, Kleber, Energieball, Boden, Explosiv, langsamer Ball, Extra-Leben, 1000 Punkte. Mali: schmaler Schläger, schneller Ball, Chaos, schwacher Ball, eingefrorener Schläger, Dunkelheit.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Gut")
        alert.runModal()
    }
}
