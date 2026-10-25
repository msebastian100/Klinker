import AppKit
import GameController
import SpriteKit

enum Palette {
    static let chrome = NSColor(hex: 0x1D76F9)
    static let field = NSColor(hex: 0x0D1753)
    static let brickHex: [UInt32] = [
        0xF0714A, 0xF0A04A, 0xF0D15A, 0x7ED0A0, 0x7EC8F0, 0x5A88E8, 0xB48AF0,
    ]
    static let steel = NSColor(hex: 0xD5DEEA)
    static let gold = NSColor(hex: 0xF0D15A)
}

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255,
            alpha: alpha)
    }

    func mixed(with other: NSColor, amount: CGFloat) -> NSColor {
        guard let a = usingColorSpace(.sRGB), let b = other.usingColorSpace(.sRGB) else { return self }
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        a.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        b.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return NSColor(
            srgbRed: r1 + (r2 - r1) * amount,
            green: g1 + (g2 - g1) * amount,
            blue: b1 + (b2 - b1) * amount,
            alpha: 1)
    }
}

private struct Metrics {
    var field = CGRect(x: 26, y: 22, width: 980, height: 692)
    var sidebar = CGRect(x: 1022, y: 22, width: 156, height: 692)
    var headerY: CGFloat = 755
    var brick = CGSize(width: 64, height: 22)

    static func designed() -> Metrics {
        var m = Metrics()
        let cols: CGFloat = 13
        let gap: CGFloat = 9
        let side: CGFloat = 18
        let width = (m.field.width - side * 2 - gap * (cols - 1)) / cols
        m.brick = CGSize(width: width, height: 22)
        return m
    }
}

private final class Art {
    let colors: [SKTexture]
    let steel: SKTexture
    let steelCrack: SKTexture
    let ball: SKTexture
    let glow: SKTexture
    let spark: SKTexture
    let gifts: [SKTexture]
    private var paddles: [Int: SKTexture] = [:]
    private var blocks: [UInt32: SKTexture] = [:]
    private let brickSize: CGSize

    init(brick: CGSize) {
        brickSize = brick
        colors = Palette.brickHex.map { Art.brickTexture(NSColor(hex: $0), size: brick, cracked: false) }
        steel = Art.brickTexture(Palette.steel, size: brick, cracked: false)
        steelCrack = Art.brickTexture(Palette.steel.mixed(with: .white, amount: 0.2), size: brick, cracked: true)
        ball = Art.ballTexture()
        glow = Art.glowTexture()
        spark = Art.sparkTexture()
        gifts = Sim.Power.allCases.map { Art.giftTexture($0) }
    }

    func gift(_ kind: Sim.Power) -> SKTexture {
        gifts[kind.rawValue]
    }

    func paddle(width: CGFloat, height: CGFloat) -> SKTexture {
        let key = Int(width.rounded())
        if let cached = paddles[key] { return cached }
        let made = Art.paddleTexture(CGSize(width: width, height: height))
        paddles[key] = made
        return made
    }

    func color(style: Int) -> NSColor {
        if style >= 0 && style < Palette.brickHex.count { return NSColor(hex: Palette.brickHex[style]) }
        return Palette.steel
    }

    func block(_ hex: UInt32, cracked: Bool) -> SKTexture {
        let key = cracked ? hex | 0x0100_0000 : hex
        if let cached = blocks[key] { return cached }
        let made = Art.brickTexture(NSColor(hex: hex), size: brickSize, cracked: cracked)
        blocks[key] = made
        return made
    }

    private static func texture(_ size: CGSize, _ draw: (CGContext, CGSize) -> Void) -> SKTexture {
        let scale: CGFloat = 2
        let w = max(1, Int((size.width * scale).rounded()))
        let h = max(1, Int((size.height * scale).rounded()))
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: info),
              let image = ({
                  ctx.scaleBy(x: scale, y: scale)
                  ctx.setAllowsAntialiasing(true)
                  ctx.interpolationQuality = .high
                  draw(ctx, size)
                  return ctx.makeImage()
              })()
        else {
            return SKTexture()
        }
        let tex = SKTexture(cgImage: image)
        tex.filteringMode = .linear
        return tex
    }

    private static func brickTexture(_ color: NSColor, size: CGSize, cracked: Bool) -> SKTexture {
        texture(size) { ctx, size in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 0.35, dy: 0.35)
            ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 4, cornerHeight: 4, transform: nil))
            ctx.clip()
            let hi = color.mixed(with: .white, amount: 0.4)
            let lo = color.mixed(with: .black, amount: 0.2)
            let colors = [lo.cgColor, color.cgColor, hi.cgColor] as CFArray
            let spots: [CGFloat] = [0, 0.4, 1]
            if let gradient = CGGradient(
                colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: spots) {
                ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
            }
            ctx.setFillColor(NSColor.white.withAlphaComponent(0.34).cgColor)
            ctx.fill(CGRect(x: 2, y: size.height * 0.6, width: size.width - 4, height: size.height * 0.26))
            if cracked {
                ctx.setStrokeColor(NSColor(hex: 0x1B2744, alpha: 0.6).cgColor)
                ctx.setLineWidth(1.3)
                ctx.setLineCap(.round)
                ctx.move(to: CGPoint(x: 8, y: 4))
                ctx.addLine(to: CGPoint(x: size.width - 10, y: size.height - 4))
                ctx.move(to: CGPoint(x: size.width * 0.42, y: 3))
                ctx.addLine(to: CGPoint(x: size.width * 0.7, y: size.height - 3))
                ctx.strokePath()
            }
        }
    }

    private static func paddleTexture(_ size: CGSize) -> SKTexture {
        texture(size) { ctx, size in
            let rect = CGRect(origin: .zero, size: size)
            let radius = size.height * 0.5
            ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
            ctx.clip()
            let colors = [
                NSColor(hex: 0xF07A4A).cgColor,
                NSColor(hex: 0xF7FBFF).cgColor,
                NSColor(hex: 0xF7FBFF).cgColor,
                NSColor(hex: 0xF07A4A).cgColor,
            ] as CFArray
            let spots: [CGFloat] = [0, 0.16, 0.84, 1]
            if let gradient = CGGradient(
                colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: spots) {
                ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: 0), options: [])
            }
        }
    }

    private static func ballTexture() -> SKTexture {
        let size = CGSize(width: 18, height: 18)
        return texture(size) { ctx, size in
            ctx.addEllipse(in: CGRect(origin: .zero, size: size))
            ctx.clip()
            let colors = [
                NSColor.white.cgColor,
                NSColor(hex: 0xFFF4E8).cgColor,
                NSColor(hex: 0xF07A4A).cgColor,
            ] as CFArray
            let spots: [CGFloat] = [0, 0.42, 1]
            let center = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
            if let gradient = CGGradient(
                colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: spots) {
                ctx.drawRadialGradient(
                    gradient,
                    startCenter: CGPoint(x: center.x - 2, y: center.y + 2), startRadius: 0,
                    endCenter: center, endRadius: size.width * 0.5, options: [])
            }
        }
    }

    private static func glowTexture() -> SKTexture {
        let size = CGSize(width: 32, height: 32)
        return texture(size) { ctx, size in
            let colors = [NSColor.white.cgColor, NSColor.white.withAlphaComponent(0).cgColor] as CFArray
            let spots: [CGFloat] = [0, 1]
            let center = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
            if let gradient = CGGradient(
                colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: spots) {
                ctx.drawRadialGradient(
                    gradient, startCenter: center, startRadius: 0,
                    endCenter: center, endRadius: size.width * 0.5, options: [])
            }
        }
    }

    private static func sparkTexture() -> SKTexture {
        let size = CGSize(width: 8, height: 8)
        return texture(size) { ctx, size in
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fillEllipse(in: CGRect(origin: .zero, size: size).insetBy(dx: 0.4, dy: 0.4))
        }
    }

    static let giftSize = CGSize(width: 64, height: 28)

    private static func giftTexture(_ kind: Sim.Power) -> SKTexture {
        texture(giftSize) { ctx, size in
            let frame = frameColor(kind)
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1)
            let radius = rect.height * 0.42
            let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
            ctx.addPath(path)
            ctx.setFillColor(NSColor(hex: 0x1A1E28).cgColor)
            ctx.fillPath()
            ctx.saveGState()
            ctx.addPath(path)
            ctx.clip()
            ctx.setFillColor(NSColor.white.withAlphaComponent(0.08).cgColor)
            ctx.fill(CGRect(x: 0, y: size.height * 0.55, width: size.width, height: size.height * 0.45))
            ctx.restoreGState()
            ctx.addPath(path)
            ctx.setStrokeColor(frame.cgColor)
            ctx.setLineWidth(2.4)
            ctx.strokePath()
            glyph(kind, ctx, size, frame)
        }
    }

    private static func frameColor(_ kind: Sim.Power) -> NSColor {
        switch kind {
        case .bonus, .slow: return NSColor(hex: 0xF0B429)
        case .through: return NSColor(hex: 0x4C8DFF)
        case .dark: return NSColor(hex: 0x8A93A8)
        default: return kind.bad ? NSColor(hex: 0xE23B3B) : NSColor(hex: 0x3DDC67)
        }
    }

    private static func glyph(_ kind: Sim.Power, _ ctx: CGContext, _ size: CGSize, _ frame: NSColor) {
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        let mid = size.height * 0.5
        let gold = NSColor(hex: 0xF0C14A)
        switch kind {
        case .wide:
            paddleBar(ctx, CGRect(x: 16, y: mid - 3, width: 32, height: 6), gold)
            arrowHead(ctx, tip: CGPoint(x: 8, y: mid), pointing: -1, span: 5.5, color: frame)
            arrowHead(ctx, tip: CGPoint(x: size.width - 8, y: mid), pointing: 1, span: 5.5, color: frame)
        case .narrow:
            paddleBar(ctx, CGRect(x: 24, y: mid - 3, width: 16, height: 6), gold)
            arrowHead(ctx, tip: CGPoint(x: 20, y: mid), pointing: 1, span: 5.5, color: frame)
            arrowHead(ctx, tip: CGPoint(x: size.width - 20, y: mid), pointing: -1, span: 5.5, color: frame)
        case .life:
            paddleBar(ctx, CGRect(x: 14, y: mid - 3, width: 22, height: 6), gold)
            plus(ctx, CGPoint(x: size.width - 16, y: mid), frame)
        case .sticky:
            paddleBar(ctx, CGRect(x: 16, y: mid - 6, width: 32, height: 6), gold)
            ball(ctx, CGPoint(x: size.width * 0.5, y: mid + 4), 4.2, NSColor(hex: 0xF4F7FF))
        case .multi:
            ball(ctx, CGPoint(x: size.width * 0.5, y: mid), 6, NSColor(hex: 0x7DFF9A))
        case .through:
            ball(ctx, CGPoint(x: size.width * 0.5, y: mid), 5, NSColor(hex: 0x8EBAFF))
            ctx.setStrokeColor(NSColor(hex: 0xD6E6FF).cgColor)
            ctx.setLineWidth(1.6)
            ctx.strokeEllipse(in: CGRect(x: size.width * 0.5 - 8, y: mid - 8, width: 16, height: 16))
        case .floor:
            for i in 0..<5 {
                let brick = CGRect(x: 10 + CGFloat(i) * 9, y: mid - 3.2, width: 7, height: 6.4)
                ctx.setFillColor(NSColor(hex: 0xD5DEEA).cgColor)
                ctx.addPath(CGPath(roundedRect: brick, cornerWidth: 1.2, cornerHeight: 1.2, transform: nil))
                ctx.fillPath()
            }
        case .slow:
            word(ctx, "Slow", size, NSColor(hex: 0xF0B429), 13)
        case .bonus:
            word(ctx, "1000", size, gold, 13)
        case .fast:
            ball(ctx, CGPoint(x: 18, y: mid), 5, NSColor(hex: 0xF4F7FF))
            ctx.setStrokeColor(frame.cgColor)
            ctx.setLineWidth(1.8)
            for i in 0..<3 {
                let x = 30 + CGFloat(i) * 7
                ctx.move(to: CGPoint(x: x, y: mid - 4))
                ctx.addLine(to: CGPoint(x: x + 4, y: mid + 4))
            }
            ctx.strokePath()
        case .blast:
            burst(ctx, CGPoint(x: size.width * 0.5, y: mid), NSColor(hex: 0xFF5A3C))
        case .freeze:
            ctx.setStrokeColor(NSColor(hex: 0xB9E7FF).cgColor)
            ctx.setLineWidth(1.6)
            let cx = size.width * 0.5
            for i in 0..<3 {
                let aim = CGFloat(i) * .pi / 3
                ctx.move(to: CGPoint(x: cx + cos(aim) * 9, y: mid + sin(aim) * 8))
                ctx.addLine(to: CGPoint(x: cx - cos(aim) * 9, y: mid - sin(aim) * 8))
            }
            ctx.strokePath()
        case .chaos:
            ctx.setStrokeColor(frame.cgColor)
            ctx.setLineWidth(2)
            ctx.move(to: CGPoint(x: 14, y: mid - 5))
            ctx.addLine(to: CGPoint(x: 22, y: mid + 5))
            ctx.addLine(to: CGPoint(x: 32, y: mid - 5))
            ctx.addLine(to: CGPoint(x: 40, y: mid + 5))
            ctx.addLine(to: CGPoint(x: 50, y: mid - 5))
            ctx.strokePath()
        case .weak:
            ball(ctx, CGPoint(x: size.width * 0.5, y: mid), 6, NSColor(hex: 0xC5CDD8))
            ctx.setStrokeColor(frame.cgColor)
            ctx.setLineWidth(1.4)
            ctx.move(to: CGPoint(x: size.width * 0.5 - 2, y: mid + 3))
            ctx.addLine(to: CGPoint(x: size.width * 0.5 + 2, y: mid))
            ctx.addLine(to: CGPoint(x: size.width * 0.5 - 1, y: mid - 4))
            ctx.strokePath()
        case .dark:
            ctx.setFillColor(NSColor.black.cgColor)
            let hole = CGRect(x: 18, y: 6, width: size.width - 36, height: size.height - 12)
            ctx.addPath(CGPath(roundedRect: hole, cornerWidth: 6, cornerHeight: 6, transform: nil))
            ctx.fillPath()
        case .weapon:
            word(ctx, "Waffe", size, gold, 13)
        case .gold:
            word(ctx, "Gold", size, gold, 13)
        case .joker:
            word(ctx, "Joker", size, frame, 13)
        case .attract:
            word(ctx, "Magnet", size, frame, 12)
        case .repel:
            word(ctx, "Stoß", size, frame, 13)
        case .ghost:
            word(ctx, "Geist", size, frame, 13)
        case .reset:
            word(ctx, "Reset", size, frame, 13)
        case .clock:
            word(ctx, "+7s", size, frame, 14)
        case .mystery:
            word(ctx, "?", size, frame, 16)
        }
    }

    private static func paddleBar(_ ctx: CGContext, _ rect: CGRect, _ color: NSColor) {
        ctx.setFillColor(color.cgColor)
        let radius = rect.height * 0.5
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        ctx.fillPath()
    }

    private static func ball(_ ctx: CGContext, _ center: CGPoint, _ radius: CGFloat, _ color: NSColor) {
        ctx.setFillColor(color.cgColor)
        ctx.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    }

    private static func plus(_ ctx: CGContext, _ center: CGPoint, _ color: NSColor) {
        ctx.setFillColor(color.cgColor)
        ctx.fill(CGRect(x: center.x - 1.2, y: center.y - 4.5, width: 2.4, height: 9))
        ctx.fill(CGRect(x: center.x - 4.5, y: center.y - 1.2, width: 9, height: 2.4))
    }

    private static func burst(_ ctx: CGContext, _ center: CGPoint, _ color: NSColor) {
        ctx.setFillColor(color.cgColor)
        for i in 0..<8 {
            let aim = CGFloat(i) * .pi / 4
            ctx.move(to: CGPoint(x: center.x + cos(aim) * 10, y: center.y + sin(aim) * 8))
            ctx.addLine(to: CGPoint(x: center.x + cos(aim + 0.4) * 3, y: center.y + sin(aim + 0.4) * 3))
            ctx.addLine(to: CGPoint(x: center.x + cos(aim - 0.4) * 3, y: center.y + sin(aim - 0.4) * 3))
            ctx.closePath()
            ctx.fillPath()
        }
    }

    private static func word(_ ctx: CGContext, _ text: String, _ size: CGSize, _ color: NSColor, _ fontSize: CGFloat) {
        let font = CTFontCreateWithName("AvenirNextCondensed-Bold" as CFString, fontSize, nil)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: color,
        ]))
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, nil))
        ctx.textPosition = CGPoint(x: (size.width - width) * 0.5, y: (size.height - ascent + descent) * 0.5)
        CTLineDraw(line, ctx)
    }

    private static func arrowHead(_ ctx: CGContext, tip: CGPoint, pointing: CGFloat, span: CGFloat, color: NSColor) {
        ctx.setFillColor(color.cgColor)
        let base = tip.x - pointing * span
        ctx.move(to: tip)
        ctx.addLine(to: CGPoint(x: base, y: tip.y - span * 0.72))
        ctx.addLine(to: CGPoint(x: base, y: tip.y + span * 0.72))
        ctx.closePath()
        ctx.fillPath()
    }
}

private final class GButton {
    let name: String
    let frame: CGRect
    let shape: SKShapeNode
    let label: SKLabelNode
    init(name: String, title: String, frame: CGRect, font: String) {
        self.name = name
        self.frame = frame
        shape = SKShapeNode(rect: frame, cornerRadius: 9)
        shape.fillColor = NSColor.white.withAlphaComponent(0.08)
        shape.strokeColor = NSColor.white.withAlphaComponent(0.9)
        shape.lineWidth = 1.5
        shape.zPosition = 60
        label = SKLabelNode(fontNamed: font)
        label.text = title
        label.fontSize = name == "start" ? 16 : 13
        label.fontColor = .white
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        label.position = CGPoint(x: frame.midX, y: frame.midY - 1)
        label.zPosition = 61
    }
}

private struct Spark {
    let node: SKSpriteNode
    var vx: CGFloat = 0
    var vy: CGFloat = 0
    var life: CGFloat = 0
    var maxLife: CGFloat = 0
}

final class GameScene: SKScene {
    private let metrics = Metrics.designed()
    private var art: Art!
    private var audio: Audio!
    private var sim = Sim()
    private var world = SKNode()
    private var brickLayer = SKNode()
    private var brickNodes: [SKSpriteNode] = []
    private var shownHP: [Int] = []
    private var paddleNode = SKSpriteNode()
    private var shotNodes: [SKSpriteNode] = []
    private var hallNoted = false
    private var ballNodes: [SKSpriteNode] = []
    private var dropNodes: [SKSpriteNode] = []
    private var dropShown: [Int] = []
    private var buttons: [GButton] = []
    private var sparks: [Spark] = []
    private var helpA = SKLabelNode()
    private var helpB = SKLabelNode()
    private var roster = Roster(lastID: nil, lastPlayedID: nil, players: [])
    private var boundID: UUID?
    private var sessionLive = false
    private var menuOpen = true
    private var menuRoot = SKNode()
    private var menuHits: [(name: String, frame: CGRect)] = []
    private var menuShapes: [String: SKShapeNode] = [:]
    private var menuHover: String?
    private var nameLabel = SKLabelNode()
    private var naming = false
    private var namingRename = false
    private var nameBuffer = ""
    private var listScroll = 0
    private var saveClock: CGFloat = 0
    private var shade = SKShapeNode()
    private var floorBar = SKShapeNode()
    private var cheatOpen = false
    private var cheatRoot = SKNode()
    private var cheatHits: [(name: String, frame: CGRect)] = []
    private var shieldLabel = SKLabelNode()
    private var floorBox = SKShapeNode()
    private var floorTick = SKLabelNode()
    private var statusLabel = SKLabelNode()
    private var mouseMode = true

    private var scoreLabel = SKLabelNode()
    private var livesLabel = SKLabelNode()
    private var roundLabel = SKLabelNode()
    private var recordValue = SKLabelNode()
    private var banner = SKLabelNode()
    private var hint = SKLabelNode()
    private var comboLabel = SKLabelNode()
    private var gainLabel = SKLabelNode()
    private var veil = SKNode()
    private var veilTitle = SKLabelNode()
    private var veilDetail = SKLabelNode()
    private var veilHint = SKLabelNode()

    private var keys = Set<UInt16>()
    private var hover: String?
    private var lastMouseX = CGFloat.nan
    private var liveMouseX: CGFloat = 0
    private var mouseUntil: TimeInterval = 0
    private var lastTime: TimeInterval = 0
    private var acc: CGFloat = 0
    private let tick: CGFloat = 1 / 240
    private var userPaused = false
    private var shownLevel = -1
    private var best = 0
    private var bestAtStart = 0
    private var shownScore = -1
    private var shownLives = -1
    private var shownRound = -1
    private var shownCombo = -1
    private var padWasA = false
    private var padWasMenu = false
    private var shake: CGFloat = 0
    private var ready = false
    private var displayFont = "AvenirNextCondensed-Bold"
    private var numberFont = "Menlo-Bold"
    private let logFPS = ProcessInfo.processInfo.environment["KLINKER_FPS"] == "1"
    private var fpsTime: TimeInterval = 0
    private var fpsFrames = 0
    private let numbers: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "de_DE")
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    override init(size: CGSize) {
        super.init(size: size)
    }

    required init?(coder: NSCoder) { nil }

    func resetGame() {
        userPaused = false
        naming = false
        let id = boundID ?? roster.lastID ?? roster.players.first?.id
        if let id {
            boundID = id
            roster.lastID = id
            roster.lastPlayedID = id
            sessionLive = true
            if let player = roster.players.first(where: { $0.id == id }) {
                best = player.best
                mouseMode = player.mouse
            }
        }
        bestAtStart = best
        hallNoted = false
        sim.newGame()
        menuOpen = false
        menuRoot.isHidden = true
        cheatOpen = false
        cheatRoot.isHidden = true
        shieldLabel.text = shieldTitle(sim.shield)
        syncFloorBox()
        rebuild()
        refreshHUD(force: true)
        storeProgress()
        audio?.tick()
        retitle()
    }

    func openMenu() {
        if sessionLive { storeProgress() }
        if let boundID { roster.lastID = boundID }
        naming = false
        menuOpen = true
        userPaused = false
        cheatOpen = false
        cheatRoot.isHidden = true
        keys.removeAll()
        menuRoot.isHidden = false
        rebuildMenu()
        retitle()
    }

    func persist() {
        storeProgress()
    }

    func togglePause() {
        if sim.phase == .over { return }
        userPaused.toggle()
    }

    func toggleMute() {
        guard audio != nil else { return }
        audio.muted.toggle()
        UserDefaults.standard.set(audio.muted, forKey: "klinker.muted")
    }

    func suspend() {
        keys.removeAll()
        if sim.phase == .playing { userPaused = true }
    }

    override func didMove(to view: SKView) {
        if ready { return }
        ready = true
        backgroundColor = Palette.chrome
        displayFont = resolveFont("AvenirNextCondensed-Bold", "AvenirNextCondensed-DemiBold")
        numberFont = resolveFont("Menlo-Bold", "Menlo")
        art = Art(brick: metrics.brick)
        audio = Audio()
        audio.muted = UserDefaults.standard.bool(forKey: "klinker.muted")
        roster = Roster.load(defaultName: defaultPlayerName())
        if let player = roster.selected {
            roster.lastID = player.id
            mouseMode = player.mouse
            best = player.best
        }
        bestAtStart = best
        menuOpen = true

        world.zPosition = 0
        addChild(world)
        let field = SKShapeNode(rect: metrics.field, cornerRadius: 8)
        field.fillColor = Palette.field
        field.strokeColor = NSColor.white.withAlphaComponent(0.45)
        field.lineWidth = 2
        field.zPosition = 1
        world.addChild(field)

        brickLayer.zPosition = 3
        world.addChild(brickLayer)

        shade.path = CGPath(roundedRect: metrics.field, cornerWidth: 8, cornerHeight: 8, transform: nil)
        shade.fillColor = NSColor.black.withAlphaComponent(0.86)
        shade.strokeColor = .clear
        shade.zPosition = 4
        shade.isHidden = true
        world.addChild(shade)

        let sill = CGRect(x: metrics.field.minX + 6, y: metrics.field.minY + 4, width: metrics.field.width - 12, height: 7)
        floorBar.path = CGPath(roundedRect: sill, cornerWidth: 3, cornerHeight: 3, transform: nil)
        floorBar.fillColor = NSColor(hex: 0x7EE0C8)
        floorBar.strokeColor = NSColor.white.withAlphaComponent(0.85)
        floorBar.lineWidth = 1
        floorBar.zPosition = 4.5
        floorBar.isHidden = true
        world.addChild(floorBar)

        paddleNode.zPosition = 5
        world.addChild(paddleNode)
        for _ in 0..<6 {
            let node = SKSpriteNode(texture: art.ball)
            node.size = CGSize(width: sim.ballR * 2, height: sim.ballR * 2)
            node.zPosition = 8
            node.isHidden = true
            world.addChild(node)
            ballNodes.append(node)
        }
        for _ in 0..<8 {
            let body = SKSpriteNode(texture: art.gift(.wide))
            body.size = Art.giftSize
            body.zPosition = 6
            body.isHidden = true
            world.addChild(body)
            dropNodes.append(body)
            dropShown.append(-1)
        }
        for _ in 0..<6 {
            let shot = SKSpriteNode(color: NSColor(hex: 0xF2E27A), size: CGSize(width: 4, height: 12))
            shot.zPosition = 7
            shot.isHidden = true
            world.addChild(shot)
            shotNodes.append(shot)
        }
        for _ in 0..<72 {
            let node = SKSpriteNode(texture: art.spark)
            node.size = CGSize(width: 6, height: 6)
            node.colorBlendFactor = 1
            node.isHidden = true
            node.zPosition = 4
            world.addChild(node)
            sparks.append(Spark(node: node))
        }

        banner = makeLabel("", size: 28, font: displayFont)
        banner.position = CGPoint(x: metrics.field.midX, y: metrics.field.midY + 8)
        banner.zPosition = 9
        banner.alpha = 0
        world.addChild(banner)

        hint = makeLabel("Leertaste oder Klick", size: 16, font: displayFont)
        hint.position = CGPoint(x: metrics.field.midX, y: metrics.field.minY + 118)
        hint.alpha = 0.8
        hint.zPosition = 9
        world.addChild(hint)

        comboLabel = makeLabel("", size: 20, font: numberFont, color: Palette.gold)
        comboLabel.position = CGPoint(x: metrics.field.midX, y: metrics.field.minY + 86)
        comboLabel.zPosition = 9
        world.addChild(comboLabel)

        gainLabel = makeLabel("", size: 14, font: numberFont, color: Palette.gold)
        gainLabel.zPosition = 9
        gainLabel.alpha = 0
        world.addChild(gainLabel)

        statusLabel = makeLabel("", size: 18, font: displayFont)
        statusLabel.position = CGPoint(x: metrics.field.midX, y: metrics.field.minY + 156)
        statusLabel.zPosition = 9
        statusLabel.alpha = 0
        world.addChild(statusLabel)

        buildChrome()
        buildOverlay()
        buildCheat()
        buildMenu()

        sim.layout(field: metrics.field)
        sim.newGame()
        rebuild()
        refreshHUD(force: true)
        retitle()
    }

    override func update(_ currentTime: TimeInterval) {
        let uptime = ProcessInfo.processInfo.systemUptime
        var dt: CGFloat = 0
        if lastTime > 0 {
            dt = CGFloat(min(1.0 / 20, max(0, currentTime - lastTime)))
        }
        lastTime = currentTime
        if logFPS {
            if fpsTime == 0 { fpsTime = currentTime }
            fpsFrames += 1
            if currentTime - fpsTime >= 2 {
                print(String(format: "fps %.1f", Double(fpsFrames) / (currentTime - fpsTime)))
                fpsFrames = 0
                fpsTime = currentTime
            }
        }

        if menuOpen {
            styleMenu(uptime)
            return
        }

        readPointer(uptime)
        pollPad()
        sim.steer = steer(uptime)

        if userPaused || dt == 0 {
            acc = 0
        } else {
            sim.clearFlags()
            acc += dt
            var steps = 0
            while acc >= tick && steps < 24 {
                sim.step(tick)
                acc -= tick
                steps += 1
            }
            if steps == 24 { acc = 0 }
            react()
        }

        if !sim.cheatScore && sim.score > best {
            best = sim.score
            if let boundID, let index = roster.players.firstIndex(where: { $0.id == boundID }) {
                roster.players[index].best = best
            }
        }
        if sessionLive {
            saveClock += dt
            if saveClock >= 3 {
                saveClock = 0
                storeProgress()
            }
        }

        let alpha: CGFloat = sim.phase == .playing ? min(1, acc / tick) : 0
        present(alpha: alpha)
        styleButtons(uptime)
        refreshHUD(force: false)
        syncOverlay()
        stepSparks(dt == 0 ? 1 / 120 : dt)
        stepShake()
    }

    override func keyDown(with event: NSEvent) {
        if menuOpen {
            if event.modifierFlags.contains(.command) { return }
            handleMenuKey(event)
            return
        }
        if event.modifierFlags.contains(.option), event.modifierFlags.contains(.shift), event.keyCode == 40 {
            toggleCheat()
            return
        }
        if event.modifierFlags.contains(.command) { return }
        keys.insert(event.keyCode)
        if event.isARepeat { return }
        switch event.keyCode {
        case 49, 36: pressSpace()
        case 35, 53: togglePause()
        case 46: toggleMute()
        case 3: view?.window?.toggleFullScreen(nil)
        case 15: resetGame()
        default: break
        }
    }

    override func keyUp(with event: NSEvent) {
        keys.remove(event.keyCode)
    }

    override func mouseDown(with event: NSEvent) {
        let point = event.location(in: self)
        if menuOpen {
            if let name = menuHits.first(where: { $0.frame.contains(point) })?.name {
                audio.tick()
                runMenu(name)
            }
            return
        }
        if cheatOpen, let name = cheatHits.first(where: { $0.frame.contains(point) })?.name {
            audio.tick()
            runCheat(name)
            return
        }
        if let name = buttons.first(where: { $0.frame.contains(point) })?.name {
            audio.tick()
            switch name {
            case "menu": openMenu()
            case "mute": toggleMute()
            case "control": toggleControl()
            case "start": pressStart()
            default: break
            }
            return
        }
        guard metrics.field.contains(point) else { return }
        if mouseMode {
            sim.placePaddle(point.x)
            liveMouseX = point.x
            mouseUntil = ProcessInfo.processInfo.systemUptime + 0.4
        }
        if sim.phase == .over { return }
        if userPaused {
            userPaused = false
            return
        }
        if sim.phase == .serving || sim.hasStuckBall { launchBall() }
    }

    override func mouseMoved(with event: NSEvent) {
        let point = event.location(in: self)
        if menuOpen {
            menuHover = menuHits.first { $0.frame.contains(point) }?.name
            return
        }
        hover = buttons.first { $0.frame.contains(point) }?.name
    }

    private func launchBall() {
        guard !userPaused else { return }
        guard sim.phase == .serving || sim.hasStuckBall else { return }
        sim.launch()
        audio.launch()
    }

    private func toggleControl() {
        mouseMode.toggle()
        UserDefaults.standard.set(mouseMode, forKey: "klinker.mouse")
        if sessionLive { storeProgress() }
        mouseUntil = 0
        keys.removeAll()
    }

    private func pressSpace() {
        if sim.phase == .over {
            resetGame()
            return
        }
        if userPaused {
            userPaused = false
            return
        }
        launchBall()
    }

    private func pressStart() {
        if sim.phase == .over {
            resetGame()
            return
        }
        if userPaused {
            userPaused = false
            return
        }
        if sim.phase == .serving || sim.hasStuckBall {
            launchBall()
            return
        }
        if sim.phase == .playing { userPaused = true }
    }

    private func steer(_ uptime: TimeInterval) -> Sim.Steer {
        if let driven = controllerSteer() { return driven }
        if mouseMode {
            if uptime < mouseUntil && hover == nil { return .absolute(liveMouseX) }
            return .idle
        }
        var speed: CGFloat = 0
        if keys.contains(123) || keys.contains(0) { speed -= 1080 }
        if keys.contains(124) || keys.contains(2) { speed += 1080 }
        if speed != 0 { return .velocity(speed) }
        return .idle
    }

    private func readPointer(_ uptime: TimeInterval) {
        guard let point = mouseInScene() else {
            lastMouseX = .nan
            if hover != nil { hover = nil }
            return
        }
        let overButton = buttons.first { $0.frame.contains(point) }?.name
        hover = overButton
        let overFieldX = point.x >= metrics.field.minX && point.x <= metrics.field.maxX
        if overButton == nil && overFieldX {
            if lastMouseX.isNaN {
                lastMouseX = point.x
            } else if abs(point.x - lastMouseX) > 0.35 {
                mouseUntil = uptime + 0.35
                lastMouseX = point.x
            } else {
                lastMouseX = point.x
            }
            liveMouseX = point.x
        } else {
            lastMouseX = .nan
        }
    }

    private func mouseInScene() -> CGPoint? {
        guard let view, let window = view.window, window.isKeyWindow else { return nil }
        let inWindow = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        let inView = view.convert(inWindow, from: nil)
        if !view.bounds.contains(inView) { return nil }
        return convertPoint(fromView: inView)
    }

    private func pollPad() {
        guard let pad = GCController.current?.extendedGamepad ?? GCController.controllers().first?.extendedGamepad else {
            padWasA = false
            padWasMenu = false
            return
        }
        let a = pad.buttonA.isPressed || pad.buttonB.isPressed
        let menu = pad.buttonMenu.isPressed
        if a && !padWasA { pressStart() }
        if menu && !padWasMenu { togglePause() }
        padWasA = a
        padWasMenu = menu
    }

    private func controllerSteer() -> Sim.Steer? {
        guard let pad = GCController.current?.extendedGamepad ?? GCController.controllers().first?.extendedGamepad else {
            return nil
        }
        let stick = CGFloat(pad.leftThumbstick.xAxis.value)
        let dpad = CGFloat(pad.dpad.xAxis.value)
        if abs(dpad) > abs(stick) && abs(dpad) > 0.5 {
            return .velocity(dpad > 0 ? 1500 : -1500)
        }
        if abs(stick) > 0.16 {
            let sign: CGFloat = stick > 0 ? 1 : -1
            let amount = (abs(stick) - 0.16) / 0.84
            return .velocity(sign * amount * amount * 1700)
        }
        return nil
    }

    private func react() {
        if sim.hitPaddle { audio.paddle() }
        if sim.hitWall { audio.wall() }
        if sim.destroyedPitch >= 0 {
            audio.brick(sim.destroyedPitch)
            shake = min(6.5, shake + 2.1)
        } else if sim.cracked {
            audio.crack()
            shake = min(5, shake + 1.2)
        }
        if sim.lostLife {
            audio.hurt()
            shake = 9
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
            if sim.lives <= 0 {
                audio.over()
                storeProgress()
            }
        }
        if sim.justCleared {
            audio.clear()
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .default)
        }
        if sim.justFinished {
            storeProgress()
        }
        if sim.phase == .over && !hallNoted {
            hallNoted = true
            rememberScore()
        }
        if sim.extraLife {
            audio.extra()
            pulse(livesLabel)
        }
        if !sim.notice.isEmpty {
            let bad = sim.noticeBad
            if bad { audio.crack() } else if !sim.extraLife { audio.extra() }
            statusLabel.removeAllActions()
            statusLabel.text = sim.notice
            statusLabel.alpha = 1
            statusLabel.run(.sequence([
                .wait(forDuration: 1.15),
                .fadeOut(withDuration: 0.3),
            ]))
        }
        if sim.gain > 0 {
            gainLabel.removeAllActions()
            gainLabel.text = "+\(sim.gain)"
            gainLabel.position = sim.gainAt
            gainLabel.alpha = 1
            gainLabel.run(.sequence([
                .group([
                    .moveBy(x: 0, y: 16, duration: 0.32),
                    .fadeOut(withDuration: 0.32),
                ]),
            ]))
        }
        if brickNodes.count != sim.bricks.count || shownLevel != sim.level {
            rebuild()
        } else {
            syncBrickHits()
        }
    }

    private func present(alpha: CGFloat) {
        for i in ballNodes.indices {
            if i < sim.balls.count {
                let ball = sim.balls[i]
                ballNodes[i].position = CGPoint(x: ball.x, y: ball.y)
                ballNodes[i].isHidden = false
            } else {
                ballNodes[i].isHidden = true
            }
        }
        for i in dropNodes.indices {
            if i < sim.drops.count {
                let drop = sim.drops[i]
                dropNodes[i].position = CGPoint(x: drop.x, y: drop.y)
                dropNodes[i].isHidden = false
                let raw = drop.kind.rawValue
                if dropShown[i] != raw {
                    dropShown[i] = raw
                    dropNodes[i].texture = art.gift(drop.kind)
                }
            } else {
                dropNodes[i].isHidden = true
                dropShown[i] = -1
            }
        }
        shade.isHidden = !sim.darkOn
        floorBar.isHidden = !sim.floorUp
        paddleNode.position = CGPoint(x: sim.paddle.x, y: sim.paddle.y)
        paddleNode.alpha = sim.ghostOn ? 0.18 : 1
        if brickNodes.count == sim.bricks.count {
            for index in sim.bricks.indices {
                brickNodes[index].position = sim.bricks[index].center
            }
        }
        for index in shotNodes.indices {
            if index < sim.shots.count {
                shotNodes[index].position = CGPoint(x: sim.shots[index].x, y: sim.shots[index].y)
                shotNodes[index].isHidden = false
            } else {
                shotNodes[index].isHidden = true
            }
        }
        if abs(paddleNode.size.width - sim.paddleW) > 0.5 {
            paddleNode.size = CGSize(width: sim.paddleW, height: sim.paddleH)
            paddleNode.texture = art.paddle(width: sim.paddleW, height: sim.paddleH)
        }
        let combo = sim.phase == .playing ? sim.combo : 0
        if combo != shownCombo {
            shownCombo = combo
            comboLabel.text = combo >= 2 ? "×\(min(combo, 8))" : ""
            if combo >= 2 { pulse(comboLabel) }
        }
        let showHint = !userPaused && (sim.phase == .serving || sim.hasStuckBall)
        hint.isHidden = !showHint
        if showHint {
            setText(hint, sim.hasStuckBall ? "Leertaste löst den Ball" : "Leertaste oder Klick")
        }
    }

    private func syncBrickHits() {
        for i in sim.bricks.indices {
            let hp = sim.bricks[i].hp
            let old = shownHP[i]
            if hp == old { continue }
            shownHP[i] = hp
            let node = brickNodes[i]
            if hp <= 0 {
                node.color = .white
                node.colorBlendFactor = 0.9
                node.run(.sequence([
                    .group([
                        .fadeOut(withDuration: 0.12),
                        .scale(to: 0.2, duration: 0.12),
                    ]),
                    .hide(),
                ]), withKey: "pop")
                burst(at: sim.bricks[i].center, color: tint(of: sim.bricks[i]))
            } else {
                node.removeAction(forKey: "pop")
                node.isHidden = false
                node.alpha = 1
                node.setScale(1)
                node.colorBlendFactor = 0
                node.texture = texture(for: sim.bricks[i])
                if hp < old {
                    node.run(.sequence([
                        .scale(to: 1.08, duration: 0.04),
                        .scale(to: 1, duration: 0.08),
                    ]), withKey: "pop")
                }
            }
        }
    }

    private func rebuild() {
        brickLayer.removeAllChildren()
        brickNodes.removeAll(keepingCapacity: true)
        shownHP = sim.bricks.map(\.hp)
        shownLevel = sim.level
        for brick in sim.bricks {
            let node = SKSpriteNode(texture: texture(for: brick))
            node.size = CGSize(width: brick.w, height: brick.h)
            node.position = brick.center
            node.zPosition = 1
            if brick.hp <= 0 { node.isHidden = true }
            brickLayer.addChild(node)
            brickNodes.append(node)
        }
        paddleNode.size = CGSize(width: sim.paddleW, height: sim.paddleH)
        paddleNode.texture = art.paddle(width: sim.paddleW, height: sim.paddleH)
        showBanner()
    }

    private func texture(for brick: Sim.Brick) -> SKTexture {
        let cracked = brick.hp > 0 && brick.hp < brick.maxHP
        switch brick.kind {
        case .plain, .seed:
            return art.colors[min(brick.style, art.colors.count - 1)]
        case .steel:
            return cracked ? art.steelCrack : art.steel
        case .wall:
            return art.block(0x2A3148, cracked: false)
        case .energy:
            return art.block(0xE8F4FF, cracked: cracked)
        case .chaos:
            return art.block(0xC06ADF, cracked: cracked)
        case .tough:
            return art.block(0xE6C15A, cracked: cracked)
        case .heal:
            return art.block(0x3DDC97, cracked: cracked)
        case .tnt:
            return art.block(0xE25B4A, cracked: false)
        case .grow:
            return art.block(0x7EE0C8, cracked: false)
        }
    }

    private func tint(of brick: Sim.Brick) -> NSColor {
        switch brick.kind {
        case .plain, .seed, .steel: return art.color(style: brick.style)
        case .wall: return NSColor(hex: 0x2A3148)
        case .energy: return NSColor(hex: 0xE8F4FF)
        case .chaos: return NSColor(hex: 0xC06ADF)
        case .tough: return NSColor(hex: 0xE6C15A)
        case .heal: return NSColor(hex: 0x3DDC97)
        case .tnt: return NSColor(hex: 0xE25B4A)
        case .grow: return NSColor(hex: 0x7EE0C8)
        }
    }

    private func burst(at point: CGPoint, color: NSColor) {
        var spawned = 0
        for i in sparks.indices {
            if sparks[i].life > 0 { continue }
            sparks[i].life = CGFloat.random(in: 0.16...0.36)
            sparks[i].maxLife = sparks[i].life
            sparks[i].vx = CGFloat.random(in: -220...220)
            sparks[i].vy = CGFloat.random(in: -30...240)
            sparks[i].node.position = point
            sparks[i].node.color = color
            sparks[i].node.alpha = 1
            sparks[i].node.setScale(CGFloat.random(in: 0.55...1.25))
            sparks[i].node.isHidden = false
            spawned += 1
            if spawned == 8 { break }
        }
    }

    private func stepSparks(_ dt: CGFloat) {
        for i in sparks.indices {
            if sparks[i].life <= 0 { continue }
            sparks[i].life -= dt
            sparks[i].vy -= 520 * dt
            sparks[i].node.position.x += sparks[i].vx * dt
            sparks[i].node.position.y += sparks[i].vy * dt
            sparks[i].node.alpha = max(0, sparks[i].life / sparks[i].maxLife)
            if sparks[i].life <= 0 { sparks[i].node.isHidden = true }
        }
    }

    private func stepShake() {
        if shake > 0.2 {
            world.position = CGPoint(
                x: CGFloat.random(in: -shake...shake),
                y: CGFloat.random(in: -shake...shake))
            shake *= 0.84
        } else {
            shake = 0
            world.position = .zero
        }
    }

    private func showBanner() {
        if menuOpen { return }
        banner.removeAllActions()
        banner.text = "Runde \(sim.level + 1)  ·  \(sim.levelName)  ·  \(sim.rank.title)"
        banner.alpha = 0
        banner.setScale(1)
        banner.run(.sequence([
            .fadeIn(withDuration: 0.12),
            .wait(forDuration: 0.85),
            .fadeOut(withDuration: 0.35),
        ]))
    }

    private func refreshHUD(force: Bool) {
        if force || sim.score != shownScore {
            shownScore = sim.score
            setText(scoreLabel, "PUNKTE  \(fmt(sim.score))")
            if !force { pulse(scoreLabel) }
        }
        if force || sim.lives != shownLives {
            shownLives = sim.lives
            setText(livesLabel, "LEBEN  \(sim.lives)")
        }
        let round = sim.level + 1
        if force || round != shownRound {
            shownRound = round
            setText(roundLabel, "RUNDE  \(round)")
        }
        setText(recordValue, fmt(best))
        recordValue.fontColor = sim.score > bestAtStart && sim.score > 0 ? Palette.gold : .white
        guard let start = buttons.first(where: { $0.name == "start" }),
              let tone = buttons.first(where: { $0.name == "mute" }) else { return }
        let title: String
        if sim.phase == .over { title = "NEU" }
        else if userPaused { title = "WEITER" }
        else if sim.phase == .serving || sim.hasStuckBall { title = "START" }
        else { title = "PAUSE" }
        setText(start.label, title)
        setText(tone.label, audio.muted ? "TON AUS" : "TON AN")
        if let control = buttons.first(where: { $0.name == "control" }) {
            setText(control.label, mouseMode ? "MAUS" : "TASTEN")
        }
        setText(helpA, mouseMode ? "Maus bewegt" : "Pfeile oder A D")
        setText(helpB, "Leertaste startet")
    }

    private func styleButtons(_ uptime: TimeInterval) {
        let pulse = 0.62 + 0.38 * (0.5 + 0.5 * sin(uptime * 5))
        for button in buttons {
            let hot = button.name == hover
            var fill: CGFloat = button.name == "start" ? 0.14 : 0.07
            if hot { fill += 0.12 }
            button.shape.fillColor = NSColor.white.withAlphaComponent(fill)
            var stroke: CGFloat = hot ? 1 : 0.72
            if button.name == "start" && sim.phase == .serving && !userPaused { stroke = pulse }
            button.shape.strokeColor = NSColor.white.withAlphaComponent(stroke)
            button.shape.lineWidth = hot ? 2.2 : 1.5
        }
    }

    private func syncOverlay() {
        let show = userPaused || sim.phase == .over
        veil.isHidden = !show
        if !show { return }
        if sim.campaignDone {
            setText(veilTitle, "SATZ GESCHAFFT")
            setText(veilDetail, "\(Sim.authoredCount) Runden  ·  \(fmt(sim.score)) Punkte")
            setText(veilHint, "Leertaste für ein neues Spiel")
        } else if sim.phase == .over {
            setText(veilTitle, "SPIEL VORBEI")
            if sim.score > bestAtStart {
                setText(veilDetail, "Neue Bestleistung  \(fmt(sim.score))")
            } else {
                setText(veilDetail, "\(fmt(sim.score)) Punkte   ·   Rekord \(fmt(best))")
            }
            setText(veilHint, "Leertaste für ein neues Spiel")
        } else {
            setText(veilTitle, "PAUSE")
            setText(veilDetail, "P oder Klick zum Weiterspielen")
            setText(veilHint, "")
        }
    }

    private func buildChrome() {
        let title = makeLabel("KLINKER", size: 30, font: displayFont)
        title.horizontalAlignmentMode = .left
        title.position = CGPoint(x: 28, y: metrics.headerY)
        title.zPosition = 20
        addChild(title)

        scoreLabel = makeLabel("PUNKTE  0", size: 15, font: numberFont)
        scoreLabel.horizontalAlignmentMode = .left
        scoreLabel.position = CGPoint(x: 250, y: metrics.headerY)
        livesLabel = makeLabel("LEBEN  3", size: 15, font: numberFont)
        livesLabel.horizontalAlignmentMode = .left
        livesLabel.position = CGPoint(x: 560, y: metrics.headerY)
        roundLabel = makeLabel("RUNDE  1", size: 15, font: numberFont)
        roundLabel.horizontalAlignmentMode = .left
        roundLabel.position = CGPoint(x: 780, y: metrics.headerY)
        for label in [scoreLabel, livesLabel, roundLabel] {
            label.zPosition = 20
            addChild(label)
        }

        let hair = SKSpriteNode(color: NSColor.white.withAlphaComponent(0.22), size: CGSize(width: 1148, height: 1))
        hair.anchorPoint = CGPoint(x: 0, y: 0.5)
        hair.position = CGPoint(x: 26, y: 728)
        hair.zPosition = 20
        addChild(hair)

        let split = SKSpriteNode(color: NSColor.white.withAlphaComponent(0.22), size: CGSize(width: 1, height: metrics.field.height))
        split.anchorPoint = CGPoint(x: 0.5, y: 0)
        split.position = CGPoint(x: metrics.field.maxX + 8, y: metrics.field.minY)
        split.zPosition = 20
        addChild(split)

        let side = metrics.sidebar
        let width = side.width - 28
        let neu = GButton(
            name: "menu", title: "MENÜ",
            frame: CGRect(x: side.minX + 14, y: side.maxY - 54, width: width, height: 40),
            font: displayFont)
        let tone = GButton(
            name: "mute", title: "TON AN",
            frame: CGRect(x: side.minX + 14, y: side.maxY - 104, width: width, height: 40),
            font: displayFont)
        let control = GButton(
            name: "control", title: "MAUS",
            frame: CGRect(x: side.minX + 14, y: side.maxY - 154, width: width, height: 40),
            font: displayFont)
        let start = GButton(
            name: "start", title: "START",
            frame: CGRect(x: side.minX + 14, y: side.minY + 16, width: width, height: 50),
            font: displayFont)
        buttons = [neu, tone, control, start]
        for button in buttons {
            addChild(button.shape)
            addChild(button.label)
        }

        let record = makeLabel("REKORD", size: 12, font: displayFont)
        record.alpha = 0.7
        record.position = CGPoint(x: side.midX, y: 430)
        record.zPosition = 20
        addChild(record)
        recordValue = makeLabel("0", size: 22, font: numberFont)
        recordValue.position = CGPoint(x: side.midX, y: 398)
        recordValue.zPosition = 20
        addChild(recordValue)

        helpA = makeLabel("Maus bewegt", size: 11, font: displayFont)
        helpA.alpha = 0.65
        helpA.position = CGPoint(x: side.midX, y: 132)
        helpA.zPosition = 20
        helpB = makeLabel("Leertaste startet", size: 11, font: displayFont)
        helpB.alpha = 0.65
        helpB.position = CGPoint(x: side.midX, y: 114)
        helpB.zPosition = 20
        addChild(helpA)
        addChild(helpB)
    }

    private func toggleCheat() {
        cheatOpen.toggle()
        cheatRoot.isHidden = !cheatOpen
    }

    private func runCheat(_ name: String) {
        switch name {
        case "million": sim.cheatMillion()
        case "lives": sim.cheatManyLives()
        case "full": sim.cheatFullPaddle()
        case "normal": sim.cheatNormalPaddle()
        case "ball": sim.cheat(.multi)
        case "slow": sim.cheat(.slow)
        case "energy": sim.cheat(.through)
        case "floor": sim.cheat(.floor)
        case "floorhold":
            _ = sim.cheatHoldFloor()
            syncFloorBox()
        case "skip": sim.cheatSkip()
        case "shield":
            _ = sim.cheatShield()
            shieldLabel.text = shieldTitle(sim.shield)
        default: break
        }
        refreshHUD(force: true)
    }

    private func shieldTitle(_ on: Bool) -> String {
        on ? "Schutz an · Leben bleibt" : "Schutz aus · Leben fällt"
    }

    private func syncFloorBox() {
        let on = sim.floorHeld
        floorTick.isHidden = !on
        floorBox.fillColor = on ? Palette.gold : NSColor.white.withAlphaComponent(0.06)
        floorBox.strokeColor = on ? Palette.gold : NSColor.white.withAlphaComponent(0.75)
    }

    private func buildCheat() {
        cheatRoot.zPosition = 80
        cheatRoot.isHidden = true
        let panel = CGRect(x: 40, y: 214, width: 248, height: 428)
        let plate = SKShapeNode(rect: panel, cornerRadius: 12)
        plate.fillColor = NSColor(hex: 0x102044, alpha: 0.94)
        plate.strokeColor = NSColor.white.withAlphaComponent(0.75)
        plate.lineWidth = 1.5
        cheatRoot.addChild(plate)
        let heading = makeLabel("ADMIN", size: 16, font: displayFont, color: Palette.gold)
        heading.position = CGPoint(x: panel.midX, y: panel.maxY - 24)
        cheatRoot.addChild(heading)
        let rows: [(String, String)] = [
            ("million", "1 Mio Punkte"),
            ("lives", "99 Leben"),
            ("full", "Volle Breite"),
            ("normal", "Normale Breite"),
            ("ball", "Extra-Ball"),
            ("slow", "Slow"),
            ("energy", "Energieball"),
            ("floor", "Boden"),
            ("skip", "Nächste Runde"),
            ("shield", shieldTitle(false)),
        ]
        cheatHits = []
        for (index, row) in rows.enumerated() {
            let box: CGFloat = row.0 == "floor" ? 34 : 0
            let frame = CGRect(x: panel.minX + 14, y: panel.maxY - 52 - CGFloat(index) * 31, width: panel.width - 28 - box, height: 26)
            let chip = SKShapeNode(rect: frame, cornerRadius: 7)
            chip.fillColor = NSColor.white.withAlphaComponent(0.08)
            chip.strokeColor = NSColor.white.withAlphaComponent(0.35)
            cheatRoot.addChild(chip)
            let label = makeLabel(row.1, size: row.0 == "shield" ? 11 : 13, font: displayFont)
            label.position = CGPoint(x: frame.midX, y: frame.midY)
            if row.0 == "shield" { shieldLabel = label }
            cheatRoot.addChild(label)
            cheatHits.append((row.0, frame))
            if row.0 == "floor" {
                let square = CGRect(x: frame.maxX + 8, y: frame.minY + 1, width: 26, height: 26)
                floorBox = SKShapeNode(rect: square, cornerRadius: 5)
                floorBox.lineWidth = 1.6
                floorBox.zPosition = 1
                cheatRoot.addChild(floorBox)
                floorTick = makeLabel("✓", size: 16, font: displayFont, color: Palette.field)
                floorTick.position = CGPoint(x: square.midX, y: square.midY - 1)
                floorTick.zPosition = 2
                cheatRoot.addChild(floorTick)
                cheatHits.append(("floorhold", square))
                syncFloorBox()
            }
        }
        let hold = makeLabel("Kästchen: Boden bleibt liegen", size: 11, font: displayFont)
        hold.alpha = 0.85
        hold.position = CGPoint(x: panel.midX, y: panel.minY + 46)
        cheatRoot.addChild(hold)
        let guardLine = makeLabel("Schutz an: Ball nimmt kein Leben", size: 11, font: displayFont)
        guardLine.alpha = 0.85
        guardLine.position = CGPoint(x: panel.midX, y: panel.minY + 22)
        cheatRoot.addChild(guardLine)
        addChild(cheatRoot)
    }

    private func defaultPlayerName() -> String {
        let given = NSFullUserName().split(separator: " ").first.map(String.init) ?? ""
        let clean = given.filter { $0.isLetter || $0.isNumber }
        if clean.count >= 2 && clean.count <= 18 { return clean }
        return "Spieler"
    }

    private func retitle() {
        let name = roster.selected?.name ?? roster.players.first?.name
        if menuOpen || name == nil {
            view?.window?.title = "Klinker"
        } else if let name {
            view?.window?.title = "Klinker – \(name)"
        }
    }

    private func rememberScore() {
        guard !sim.cheatScore, sim.score > 0 else { return }
        let name = roster.players.first { $0.id == boundID }?.name ?? roster.selected?.name ?? "Spieler"
        roster.note(name: name, score: sim.score, round: sim.level + 1, rank: sim.rank.rawValue)
        roster.write()
    }

    private func storeProgress() {
        guard sessionLive, let boundID, let index = roster.players.firstIndex(where: { $0.id == boundID }) else {
            roster.write()
            return
        }
        if sim.cheatScore {
            roster.players[index].best = max(roster.players[index].best, best)
        } else {
            roster.players[index].best = max(roster.players[index].best, best, sim.score)
        }
        roster.players[index].mouse = mouseMode
        roster.players[index].save = sim.snapshot()
        roster.lastPlayedID = boundID
        roster.write()
    }

    private func enterGame(fresh: Bool) {
        guard let player = roster.selected else { return }
        let id = player.id
        boundID = id
        hallNoted = false
        roster.lastID = id
        roster.lastPlayedID = id
        if let index = roster.players.firstIndex(where: { $0.id == id }) {
            best = roster.players[index].best
            mouseMode = roster.players[index].mouse
            UserDefaults.standard.set(mouseMode, forKey: "klinker.mouse")
            sim.rank = roster.players[index].rank
            if fresh || roster.players[index].save == nil {
                sim.newGame()
            } else if let save = roster.players[index].save {
                sim.layout(field: metrics.field)
                sim.restore(save)
                sim.rank = roster.players[index].rank
                sim.retune()
            }
        }
        bestAtStart = best
        sessionLive = true
        naming = false
        menuOpen = false
        menuRoot.isHidden = true
        userPaused = false
        acc = 0
        keys.removeAll()
        cheatOpen = false
        cheatRoot.isHidden = true
        shieldLabel.text = shieldTitle(sim.shield)
        syncFloorBox()
        rebuild()
        refreshHUD(force: true)
        storeProgress()
        audio?.tick()
        retitle()
    }

    private func handleMenuKey(_ event: NSEvent) {
        if naming {
            if event.keyCode == 53 {
                naming = false
                rebuildMenu()
                return
            }
            if event.keyCode == 36 {
                commitName()
                return
            }
            if event.keyCode == 51 {
                if !nameBuffer.isEmpty { nameBuffer.removeLast() }
                return
            }
            guard !event.isARepeat, let text = event.characters else { return }
            for character in text {
                guard character.isLetter || character.isNumber || character == " " || character == "-" else { continue }
                if nameBuffer.count >= 18 { break }
                nameBuffer.append(character)
            }
            return
        }
        if event.isARepeat && event.keyCode != 126 && event.keyCode != 125 { return }
        switch event.keyCode {
        case 126: moveSelection(-1)
        case 125: moveSelection(1)
        case 36, 49: enterGame(fresh: roster.selected?.save == nil)
        case 53: closeMenu()
        case 45: enterGame(fresh: true)
        default: break
        }
    }

    private func runMenu(_ name: String) {
        if name == "ok" {
            commitName()
            return
        }
        if name == "cancel" {
            naming = false
            rebuildMenu()
            return
        }
        if name == "add" {
            naming = true
            namingRename = false
            nameBuffer = ""
            rebuildMenu()
            return
        }
        if name == "rename" {
            naming = true
            namingRename = true
            nameBuffer = roster.selected?.name ?? ""
            rebuildMenu()
            return
        }
        if name.hasPrefix("rank:"), let raw = Int(name.dropFirst(5)), let rank = Sim.Rank(rawValue: raw),
           let index = roster.players.firstIndex(where: { $0.id == roster.lastID }) {
            roster.players[index].difficulty = rank.rawValue
            roster.write()
            rebuildMenu()
            return
        }
        if name == "delete" {
            deleteSelected()
            return
        }
        if name == "up" {
            listScroll = max(0, listScroll - 1)
            rebuildMenu()
            return
        }
        if name == "down" {
            listScroll += 1
            rebuildMenu()
            return
        }
        if name == "go" {
            enterGame(fresh: false)
            return
        }
        if name == "fresh" {
            enterGame(fresh: true)
            return
        }
        if name.hasPrefix("player:") {
            let raw = String(name.dropFirst("player:".count))
            guard let id = UUID(uuidString: raw) else { return }
            if roster.lastID == id {
                enterGame(fresh: roster.selected?.save == nil)
            } else {
                roster.lastID = id
                roster.write()
                keepSelectionVisible()
                rebuildMenu()
            }
        }
    }

    private func moveSelection(_ delta: Int) {
        guard !roster.players.isEmpty else { return }
        let ids = roster.players.map(\.id)
        let current = ids.firstIndex(of: roster.lastID ?? ids[0]) ?? 0
        let next = min(ids.count - 1, max(0, current + delta))
        roster.lastID = ids[next]
        keepSelectionVisible()
        roster.write()
        rebuildMenu()
    }

    private func keepSelectionVisible() {
        let ids = roster.players.map(\.id)
        let index = ids.firstIndex(of: roster.lastID ?? UUID()) ?? 0
        if index < listScroll { listScroll = index }
        if index >= listScroll + 5 { listScroll = index - 4 }
        listScroll = max(0, min(listScroll, max(0, roster.players.count - 5)))
    }

    private func closeMenu() {
        guard sessionLive, let boundID else { return }
        roster.lastID = boundID
        naming = false
        menuOpen = false
        menuRoot.isHidden = true
        keys.removeAll()
        retitle()
    }

    private func commitName() {
        let name = nameBuffer.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        if namingRename, let index = roster.players.firstIndex(where: { $0.id == roster.lastID }) {
            roster.players[index].name = name
        } else {
            let player = Roster.Player(
                id: UUID(), name: name, best: 0, mouse: mouseMode, save: nil,
                difficulty: roster.selected?.difficulty)
            roster.players.append(player)
            roster.lastID = player.id
            listScroll = max(0, roster.players.count - 5)
        }
        naming = false
        roster.write()
        rebuildMenu()
    }

    private func deleteSelected() {
        guard roster.players.count > 1, let id = roster.lastID,
              let index = roster.players.firstIndex(where: { $0.id == id }) else { return }
        roster.players.remove(at: index)
        if roster.lastPlayedID == id { roster.lastPlayedID = roster.players.first?.id }
        let next = min(index, roster.players.count - 1)
        roster.lastID = roster.players[next].id
        if boundID == id {
            boundID = nil
            sessionLive = false
        }
        keepSelectionVisible()
        roster.write()
        rebuildMenu()
    }

    private func buildMenu() {
        menuRoot.zPosition = 100
        menuRoot.isHidden = !menuOpen
        addChild(menuRoot)
        rebuildMenu()
    }

    private func styleMenu(_ uptime: TimeInterval) {
        let picked = roster.lastID?.uuidString ?? ""
        for (name, shape) in menuShapes {
            let hot = name == menuHover
            let chosen = name == "player:\(picked)" || name == "rank:\(roster.selected?.rank.rawValue ?? 2)"
            shape.lineWidth = hot || chosen ? 2.4 : 1.4
            shape.strokeColor = chosen ? Palette.gold : NSColor.white.withAlphaComponent(hot ? 0.95 : 0.4)
            let fill: CGFloat = chosen ? 0.16 : (hot ? 0.1 : 0.05)
            shape.fillColor = NSColor.white.withAlphaComponent(fill)
        }
        if naming {
            let blink = Int(uptime * 2) % 2 == 0
            let shown = nameBuffer.isEmpty ? "Name" : nameBuffer
            nameLabel.text = blink ? shown + "|" : shown
            nameLabel.alpha = nameBuffer.isEmpty ? 0.45 : 1
        }
    }

    private func rebuildMenu() {
        menuRoot.removeAllChildren()
        menuHits = []
        menuShapes = [:]
        let backdrop = SKSpriteNode(color: Palette.chrome, size: size)
        backdrop.position = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
        backdrop.zPosition = 0
        menuRoot.addChild(backdrop)

        let title = makeLabel("KLINKER", size: 52, font: displayFont)
        title.position = CGPoint(x: size.width * 0.5, y: size.height - 62)
        title.zPosition = 2
        menuRoot.addChild(title)
        let sub = makeLabel("Wer spielt?", size: 18, font: displayFont)
        sub.alpha = 0.88
        sub.position = CGPoint(x: size.width * 0.5, y: size.height - 104)
        sub.zPosition = 2
        menuRoot.addChild(sub)
        let rule = SKSpriteNode(color: Palette.gold.withAlphaComponent(0.85), size: CGSize(width: 120, height: 2))
        rule.position = CGPoint(x: size.width * 0.5, y: size.height - 124)
        rule.zPosition = 2
        menuRoot.addChild(rule)

        let left = CGRect(x: 64, y: 86, width: 470, height: 540)
        let right = CGRect(x: 558, y: 86, width: 578, height: 540)
        menuRoot.addChild(menuCard(left))
        menuRoot.addChild(menuCard(right))

        let playersHead = makeLabel("SPIELER", size: 13, font: displayFont, color: Palette.gold)
        playersHead.position = CGPoint(x: left.midX, y: left.maxY - 28)
        playersHead.zPosition = 3
        menuRoot.addChild(playersHead)

        let rowH: CGFloat = 62
        let gap: CGFloat = 8
        let visible = 5
        listScroll = max(0, min(listScroll, max(0, roster.players.count - visible)))
        let listTop = left.maxY - 52
        for slot in 0..<visible {
            let index = listScroll + slot
            guard index < roster.players.count else { break }
            let player = roster.players[index]
            let frame = CGRect(
                x: left.minX + 16,
                y: listTop - CGFloat(slot + 1) * (rowH + gap) + gap,
                width: left.width - 32,
                height: rowH)
            let key = "player:\(player.id.uuidString)"
            addMenuButton(key, frame: frame, title: nil)
            let name = makeLabel(player.name, size: 20, font: displayFont)
            name.position = CGPoint(x: frame.midX, y: frame.midY + 10)
            name.zPosition = 5
            menuRoot.addChild(name)
            let detail = makeLabel(playerLine(player), size: 12, font: displayFont)
            detail.alpha = 0.78
            detail.position = CGPoint(x: frame.midX, y: frame.midY - 12)
            detail.zPosition = 5
            menuRoot.addChild(detail)
            if player.id == roster.lastPlayedID {
                let mark = makeLabel("zuletzt", size: 11, font: displayFont, color: Palette.gold)
                mark.horizontalAlignmentMode = .right
                mark.position = CGPoint(x: frame.maxX - 12, y: frame.maxY - 14)
                mark.zPosition = 5
                menuRoot.addChild(mark)
            }
        }
        if listScroll > 0 {
            addMenuButton("up", frame: CGRect(x: left.maxX - 42, y: left.maxY - 46, width: 28, height: 22), title: "▲")
        }
        if listScroll + visible < roster.players.count {
            addMenuButton("down", frame: CGRect(x: left.minX + 16, y: left.minY + 64, width: 28, height: 22), title: "▼")
        }
        let tip = makeLabel("Klick wählt, noch einmal startet", size: 12, font: displayFont)
        tip.alpha = 0.7
        tip.position = CGPoint(x: left.midX, y: left.minY + 76)
        tip.zPosition = 3
        menuRoot.addChild(tip)
        addMenuButton("add", frame: CGRect(x: left.minX + 16, y: left.minY + 16, width: left.width - 32, height: 40), title: "+ Neuer Spieler")

        if naming {
            buildNameCard(right)
        } else if let player = roster.selected {
            buildDetailCard(right, player)
        }

        let board = roster.board.prefix(3).map { "\($0.name) \(fmt($0.score))" }.joined(separator: "   ·   ")
        let hall = makeLabel(
            board.isEmpty ? "Bestenliste füllt sich nach dem ersten Spiel" : "Bestenliste   \(board)",
            size: 13,
            font: displayFont)
        hall.alpha = 0.85
        hall.position = CGPoint(x: size.width * 0.5, y: 36)
        hall.zPosition = 2
        menuRoot.addChild(hall)
    }

    private func menuCard(_ frame: CGRect) -> SKShapeNode {
        let card = SKShapeNode(rect: frame, cornerRadius: 16)
        card.fillColor = Palette.field.withAlphaComponent(0.94)
        card.strokeColor = NSColor.white.withAlphaComponent(0.35)
        card.lineWidth = 1.5
        card.zPosition = 1
        return card
    }

    private func addMenuButton(_ name: String, frame: CGRect, title: String?) {
        let shape = SKShapeNode(rect: frame, cornerRadius: 10)
        shape.fillColor = NSColor.white.withAlphaComponent(0.06)
        shape.strokeColor = NSColor.white.withAlphaComponent(0.45)
        shape.lineWidth = 1.4
        shape.zPosition = 4
        menuRoot.addChild(shape)
        menuShapes[name] = shape
        menuHits.append((name, frame))
        if let title {
            let label = makeLabel(title, size: name == "go" ? 18 : 14, font: displayFont)
            label.position = CGPoint(x: frame.midX, y: frame.midY)
            label.zPosition = 5
            menuRoot.addChild(label)
        }
    }

    private func playerLine(_ player: Roster.Player) -> String {
        if let save = player.save {
            return "Runde \(save.level + 1)  ·  \(fmt(save.score)) Punkte"
        }
        if player.best > 0 { return "Rekord \(fmt(player.best))" }
        return "Noch kein Spiel"
    }

    private func buildDetailCard(_ card: CGRect, _ player: Roster.Player) {
        let name = makeLabel(player.name, size: 34, font: displayFont)
        name.position = CGPoint(x: card.midX, y: card.maxY - 58)
        name.zPosition = 3
        menuRoot.addChild(name)
        if player.id == roster.lastPlayedID {
            let mark = makeLabel("hat zuletzt gespielt", size: 14, font: displayFont, color: Palette.gold)
            mark.position = CGPoint(x: card.midX, y: card.maxY - 96)
            mark.zPosition = 3
            menuRoot.addChild(mark)
        }
        let lines = detailLines(player)
        for (index, line) in lines.enumerated() {
            let label = makeLabel(line, size: 16, font: numberFont)
            label.position = CGPoint(x: card.midX, y: card.maxY - 160 - CGFloat(index) * 32)
            label.zPosition = 3
            menuRoot.addChild(label)
        }
        let rankLabel = makeLabel("Schwierigkeit", size: 13, font: displayFont, color: Palette.gold)
        rankLabel.position = CGPoint(x: card.midX, y: card.minY + 246)
        rankLabel.zPosition = 3
        menuRoot.addChild(rankLabel)
        let ranks = Sim.Rank.allCases
        let gap: CGFloat = 8
        let buttonW = (card.width - 56 - gap * CGFloat(ranks.count - 1)) / CGFloat(ranks.count)
        for (index, rank) in ranks.enumerated() {
            let frame = CGRect(
                x: card.minX + 28 + CGFloat(index) * (buttonW + gap),
                y: card.minY + 198,
                width: buttonW,
                height: 36)
            addMenuButton("rank:\(rank.rawValue)", frame: frame, title: rank.title)
        }
        let hasSave = player.save != nil
        addMenuButton(
            "go",
            frame: CGRect(x: card.minX + 28, y: card.minY + 132, width: card.width - 56, height: 52),
            title: hasSave ? "Weiterspielen" : "Neues Spiel")
        if hasSave {
            addMenuButton(
                "fresh",
                frame: CGRect(x: card.minX + 28, y: card.minY + 74, width: card.width - 56, height: 44),
                title: "Neues Spiel")
        }
        let half = (card.width - 68) * 0.5
        addMenuButton("rename", frame: CGRect(x: card.minX + 28, y: card.minY + 18, width: half, height: 40), title: "Name ändern")
        if roster.players.count > 1 {
            addMenuButton(
                "delete",
                frame: CGRect(x: card.minX + 40 + half, y: card.minY + 18, width: half, height: 40),
                title: "Löschen")
        }
    }

    private func detailLines(_ player: Roster.Player) -> [String] {
        var lines = ["Rekord   \(fmt(player.best))", "Stufe   \(player.rank.title)"]
        if let save = player.save {
            let ball = save.phase == Sim.Phase.playing.rawValue ? "Ball ist unterwegs" : "Ball liegt auf"
            lines.append("Runde \(save.level + 1)   ·   \(ball)")
            lines.append("\(fmt(save.score)) Punkte   ·   \(save.lives) Leben")
        } else if player.best > 0 {
            lines.append("Bereit für ein neues Spiel")
        } else {
            lines.append("Bereit für die erste Runde")
        }
        return lines
    }

    private func buildNameCard(_ card: CGRect) {
        let heading = makeLabel(namingRename ? "Neuer Name" : "Neuer Spieler", size: 28, font: displayFont)
        heading.position = CGPoint(x: card.midX, y: card.maxY - 80)
        heading.zPosition = 3
        menuRoot.addChild(heading)
        let hint = makeLabel("Tippen, dann Enter", size: 15, font: displayFont)
        hint.alpha = 0.8
        hint.position = CGPoint(x: card.midX, y: card.maxY - 122)
        hint.zPosition = 3
        menuRoot.addChild(hint)
        let field = CGRect(x: card.minX + 48, y: card.midY - 10, width: card.width - 96, height: 56)
        let plate = SKShapeNode(rect: field, cornerRadius: 10)
        plate.fillColor = NSColor.black.withAlphaComponent(0.25)
        plate.strokeColor = Palette.gold
        plate.lineWidth = 2
        plate.zPosition = 3
        menuRoot.addChild(plate)
        nameLabel = makeLabel(nameBuffer.isEmpty ? "Name" : nameBuffer, size: 26, font: displayFont)
        nameLabel.position = CGPoint(x: field.midX, y: field.midY)
        nameLabel.zPosition = 4
        nameLabel.alpha = nameBuffer.isEmpty ? 0.45 : 1
        menuRoot.addChild(nameLabel)
        addMenuButton(
            "ok",
            frame: CGRect(x: card.minX + 48, y: card.minY + 78, width: card.width - 96, height: 48),
            title: namingRename ? "Speichern" : "Anlegen")
        addMenuButton(
            "cancel",
            frame: CGRect(x: card.minX + 48, y: card.minY + 22, width: card.width - 96, height: 40),
            title: "Abbrechen")
    }

    private func buildOverlay() {
        veil.zPosition = 40
        veil.isHidden = true
        let dim = SKSpriteNode(color: NSColor.black.withAlphaComponent(0.52), size: metrics.field.size)
        dim.position = CGPoint(x: metrics.field.midX, y: metrics.field.midY)
        veil.addChild(dim)
        veilTitle = makeLabel("", size: 40, font: displayFont)
        veilTitle.position = CGPoint(x: metrics.field.midX, y: metrics.field.midY + 28)
        veilDetail = makeLabel("", size: 18, font: numberFont)
        veilDetail.position = CGPoint(x: metrics.field.midX, y: metrics.field.midY - 16)
        veilHint = makeLabel("", size: 15, font: displayFont)
        veilHint.alpha = 0.85
        veilHint.position = CGPoint(x: metrics.field.midX, y: metrics.field.midY - 52)
        veil.addChild(veilTitle)
        veil.addChild(veilDetail)
        veil.addChild(veilHint)
        addChild(veil)
    }

    private func makeLabel(_ text: String, size: CGFloat, font: String, color: NSColor = .white) -> SKLabelNode {
        let node = SKLabelNode(fontNamed: font)
        node.text = text
        node.fontSize = size
        node.fontColor = color
        node.verticalAlignmentMode = .center
        node.horizontalAlignmentMode = .center
        return node
    }

    private func setText(_ label: SKLabelNode, _ text: String) {
        if label.text != text { label.text = text }
    }

    private func pulse(_ node: SKNode) {
        node.removeAction(forKey: "pulse")
        node.setScale(1)
        node.run(.sequence([
            .scale(to: 1.12, duration: 0.05),
            .scale(to: 1, duration: 0.12),
        ]), withKey: "pulse")
    }

    private func fmt(_ value: Int) -> String {
        numbers.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private func resolveFont(_ names: String...) -> String {
        for name in names {
            if NSFont(name: name, size: 12) != nil { return name }
        }
        return NSFont.boldSystemFont(ofSize: 12).fontName
    }
}
