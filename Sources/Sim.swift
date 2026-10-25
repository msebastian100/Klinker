import Foundation
import CoreGraphics

/// Arcade-Physik mit festem Zeitschritt. Die Darstellung hängt woanders.
struct Sim {
    enum Phase: Int { case serving, playing, dying, cleared, over }

    enum Steer {
        case idle
        case absolute(CGFloat)
        case velocity(CGFloat)
    }

    enum Kind: Int {
        case plain, steel, wall, energy, chaos, tough, heal, tnt, grow, seed
    }

    struct Brick {
        var minX: CGFloat
        var minY: CGFloat
        var w: CGFloat
        var h: CGFloat
        var hp: Int
        var maxHP: Int
        var points: Int
        var style: Int
        var pitch: Int
        var power: Power?
        var kind: Kind = .plain
        var counts = true
        var mend: CGFloat = 0
        var drift: CGFloat = 0
        var maxX: CGFloat { minX + w }
        var maxY: CGFloat { minY + h }
        var center: CGPoint { CGPoint(x: minX + w * 0.5, y: minY + h * 0.5) }
    }

    enum Power: Int, CaseIterable, Codable {
        case wide, narrow, multi, slow, fast, life, sticky, through, bonus
        case floor, blast, freeze, chaos, weak, dark
        case weapon, gold, joker, attract, repel, ghost, reset, clock, mystery

        var title: String {
            switch self {
            case .wide: return "Breiter Schläger"
            case .narrow: return "Schmaler Schläger"
            case .multi: return "Extra-Ball"
            case .slow: return "Langsamer"
            case .fast: return "Schneller"
            case .life: return "Extra-Leben"
            case .sticky: return "Klebriger Schläger"
            case .through: return "Energieball"
            case .bonus: return "1000 Punkte"
            case .floor: return "Boden"
            case .blast: return "Explosiv"
            case .freeze: return "Eingefroren"
            case .chaos: return "Chaos"
            case .weak: return "Schwacher Ball"
            case .dark: return "Dunkelheit"
            case .weapon: return "Waffe"
            case .gold: return "Goldregen"
            case .joker: return "Joker"
            case .attract: return "Magnet"
            case .repel: return "Gegenmagnet"
            case .ghost: return "Geisterschläger"
            case .reset: return "Reset"
            case .clock: return "Sieben Sekunden"
            case .mystery: return "Zufall"
            }
        }

        var bad: Bool {
            switch self {
            case .narrow, .fast, .freeze, .chaos, .weak, .dark, .repel, .ghost: return true
            default: return false
            }
        }

        var tint: UInt32 {
            switch self {
            case .wide: return 0x3DDC97
            case .narrow: return 0xE25B4A
            case .multi: return 0x7EC8F0
            case .slow: return 0x6AA4F0
            case .fast: return 0xF0A04A
            case .life: return 0xF07AB0
            case .sticky: return 0xF0D15A
            case .through: return 0xF4F7FF
            case .bonus: return 0xE6C15A
            case .floor: return 0x7EE0C8
            case .blast: return 0xF07A4A
            case .freeze: return 0xD7F1FF
            case .chaos: return 0xC06ADF
            case .weak: return 0x8E96A8
            case .dark: return 0x3A4380
            case .weapon: return 0xF2E27A
            case .gold: return 0xE6C15A
            case .joker: return 0xC06ADF
            case .attract: return 0x7EC8F0
            case .repel: return 0xE25B4A
            case .ghost: return 0xB7C0D4
            case .reset: return 0xF4F7FF
            case .clock: return 0x7EE0C8
            case .mystery: return 0xF07AB0
            }
        }
    }

    /// Bonusrunde nach jeder vierten festen Runde. Der Rundenindex bleibt dabei stehen.
    enum Bonus: Int, CaseIterable {
        case barrier, outbreak, jack, ducks, hunter, defender

        var title: String {
            switch self {
            case .barrier: return "Barriere"
            case .outbreak: return "Ausbruch"
            case .jack: return "Hüpfer"
            case .ducks: return "Enten"
            case .hunter: return "Jagd"
            case .defender: return "Wellen"
            }
        }

        var timed: Bool {
            switch self {
            case .jack, .ducks, .hunter: return true
            default: return false
            }
        }

        var limit: CGFloat {
            switch self {
            case .jack: return 22
            case .ducks, .hunter: return 16
            default: return 0
            }
        }
    }

    struct Ball: Codable {
        var x: CGFloat
        var y: CGFloat
        var vx: CGFloat
        var vy: CGFloat
        var stuck = false
        var grip: CGFloat = 0
        var skip = -1
        var alive = true
    }

    struct Drop: Codable {
        var kind: Power
        var x: CGFloat
        var y: CGFloat
        var alive = true
    }

    struct Shot {
        var x: CGFloat
        var y: CGFloat
        var alive = true
    }

    /// Stand einer laufenden Runde, genug um genau dort weiterzumachen.
    struct Save: Codable {
        var score: Int
        var lives: Int
        var level: Int
        var combo: Int
        var lifeBucket: Int
        var speed: Double
        var paddleX: Double
        var paddleW: Double
        var tempo: Double
        var tempoTime: Double
        var sticky: Double
        var through: Double
        var floor: Double
        var blast: Double
        var freeze: Double
        var chaos: Double
        var weak: Double
        var dark: Double
        var shield: Bool
        var cheated: Bool?
        var phase: Int
        var hp: [Int]
        var power: [Int]
        var balls: [Ball]
        var drops: [Drop]
        var rank: Int?
        var weapon: Double?
        var gold: Double?
        var attract: Double?
        var repel: Double?
        var ghost: Double?
        var bonusKind: Int?
        var bonusLeft: Double?
        var bonusWave: Int?
    }

    struct Level {
        var name: String
        var sink: Int = 0
        var rows: [String]
    }

    static let baseSpeed: CGFloat = 300
    static let maxSpeed: CGFloat = 460
    static let paddleStart: CGFloat = 118
    static let paddleStep: CGFloat = 36
    static let paddleMin: CGFloat = 64
    static let paddleMax: CGFloat = 214

    /// Vier Stufen wie im Original: Kinder, Leicht, Mittel, Schwer.
    enum Rank: Int, CaseIterable {
        case kids, easy, medium, hard

        var title: String {
            switch self {
            case .kids: return "Kinder"
            case .easy: return "Leicht"
            case .medium: return "Mittel"
            case .hard: return "Schwer"
            }
        }

        var lives: Int {
            switch self {
            case .kids: return 7
            case .easy: return 5
            case .medium: return 3
            case .hard: return 2
            }
        }

        var maxLives: Int {
            switch self {
            case .kids: return 12
            case .easy: return 9
            case .medium: return 7
            case .hard: return 5
            }
        }

        var paddle: CGFloat {
            switch self {
            case .kids: return 168
            case .easy: return 140
            case .medium: return 118
            case .hard: return 86
            }
        }

        var pace: CGFloat {
            switch self {
            case .kids: return 0.78
            case .easy: return 0.9
            case .medium: return 1
            case .hard: return 1.12
            }
        }

        var cap: CGFloat {
            switch self {
            case .kids: return 390
            case .easy: return 440
            case .medium: return 480
            case .hard: return 540
            }
        }

        var creep: CGFloat {
            switch self {
            case .kids: return 1.5
            case .easy: return 2.5
            case .medium: return 4
            case .hard: return 6
            }
        }

        var ceiling: CGFloat {
            switch self {
            case .kids: return 430
            case .easy: return 500
            case .medium: return 580
            case .hard: return 640
            }
        }

        var time: CGFloat {
            switch self {
            case .kids: return 2
            case .easy: return 1.35
            case .medium: return 1
            case .hard: return 0.7
            }
        }

        var score: CGFloat {
            switch self {
            case .kids: return 0.6
            case .easy: return 0.85
            case .medium: return 1
            case .hard: return 1.3
            }
        }
    }

    var field = CGRect(x: 26, y: 22, width: 980, height: 692)
    var phase: Phase = .serving
    var steer: Steer = .idle
    var bricks: [Brick] = []
    var remaining = 0
    var score = 0
    var lives = 3
    var level = 0
    var combo = 0
    var speed: CGFloat = Sim.baseSpeed
    var paddle = CGPoint(x: 500, y: 64)
    var paddleW: CGFloat = Sim.paddleStart
    let paddleH: CGFloat = 14
    var balls: [Ball] = []
    var drops: [Drop] = []
    let ballR: CGFloat = 6.5

    var hitPaddle = false
    var hitWall = false
    var lostLife = false
    var justCleared = false
    var extraLife = false
    var cracked = false
    var destroyedPitch = -1
    var gain = 0
    var gainAt = CGPoint.zero
    var notice = ""
    var noticeBad = false

    private var time: CGFloat = 0
    private var dieTimer: CGFloat = 0
    private var clearTimer: CGFloat = 0
    private var lifeBucket = 0
    private var tempo: CGFloat = 1
    private var tempoTime: CGFloat = 0
    private var stickyTime: CGFloat = 0
    private var throughTime: CGFloat = 0
    private var floorTime: CGFloat = 0
    private var blastTime: CGFloat = 0
    private var freezeTime: CGFloat = 0
    private var chaosTime: CGFloat = 0
    private var weakTime: CGFloat = 0
    private var darkTime: CGFloat = 0
    private var weaponTime: CGFloat = 0
    private var goldTime: CGFloat = 0
    private var attractTime: CGFloat = 0
    private var repelTime: CGFloat = 0
    private var ghostTime: CGFloat = 0
    private var weaponCooldown: CGFloat = 0
    var shots: [Shot] = []
    var bonus: Bonus?
    private var bonusPlayed = false
    private var bonusClock: CGFloat = 0
    private var bonusLeft: CGFloat = 0
    private var bonusWave = 0

    var floorUp: Bool { floorTime > 0 }
    var darkOn: Bool { darkTime > 0 }
    var ghostOn: Bool { ghostTime > 0 }

    var hasStuckBall: Bool {
        phase == .playing && balls.contains { $0.stuck }
    }

    private var travel: CGFloat { speed * tempo }

    var rank: Rank = .medium

    var levelName: String {
        if let bonus { return bonus.title }
        return Self.layout(for: max(0, level)).name
    }

    static var authoredCount: Int { levels.count }

    mutating func layout(field: CGRect) {
        self.field = field
        paddle.y = field.minY + 46
        paddle.x = field.midX
    }

    mutating func clearFlags() {
        hitPaddle = false
        hitWall = false
        lostLife = false
        justCleared = false
        justFinished = false
        extraLife = false
        cracked = false
        destroyedPitch = -1
        gain = 0
        notice = ""
        noticeBad = false
    }

    mutating func newGame() {
        score = 0
        lives = rank.lives
        level = 0
        combo = 0
        speed = pace(for: 0)
        paddleW = rank.paddle
        paddle.x = field.midX
        lifeBucket = 0
        shield = false
        floorHeld = false
        wideHeld = false
        cheatScore = false
        campaignDone = false
        bonus = nil
        bonusPlayed = false
        bonusClock = 0
        bonusLeft = 0
        bonusWave = 0
        shots.removeAll(keepingCapacity: true)
        time = 0
        buildLevel()
        beginServe()
    }

    mutating func placePaddle(_ x: CGFloat) {
        steer = .absolute(x)
        movePaddle(0)
    }

    mutating func launch() {
        if phase == .playing {
            releaseStuck()
            return
        }
        guard phase == .serving else { return }
        stickBall(bob: false)
        let angle = CGFloat.random(in: -0.42...0.42)
        let mag = travel
        if balls.isEmpty { balls = [Ball(x: paddle.x, y: 0, vx: 0, vy: 0)] }
        balls[0].stuck = false
        balls[0].vx = sin(angle) * mag
        balls[0].vy = cos(angle) * mag
        phase = .playing
    }

    mutating func step(_ dt: CGFloat) {
        time += dt
        switch phase {
        case .playing:
            play(dt)
        case .serving:
            movePaddle(dt)
            stickBall(bob: true)
        case .dying:
            dieTimer -= dt
            if dieTimer <= 0 {
                if lives <= 0 { phase = .over }
                else { beginServe() }
            }
        case .cleared:
            movePaddle(dt)
            stickBall(bob: false)
            clearTimer -= dt
            if clearTimer <= 0 { advance() }
        case .over:
            break
        }
    }

    private mutating func play(_ dt: CGFloat) {
        movePaddle(dt)
        Self.cool(&stickyTime, dt)
        Self.cool(&throughTime, dt)
        if floorHeld { floorTime = 10_000 } else { Self.cool(&floorTime, dt) }
        Self.cool(&blastTime, dt)
        Self.cool(&freezeTime, dt)
        Self.cool(&chaosTime, dt)
        Self.cool(&weakTime, dt)
        Self.cool(&darkTime, dt)
        Self.cool(&weaponTime, dt)
        Self.cool(&goldTime, dt)
        Self.cool(&attractTime, dt)
        Self.cool(&repelTime, dt)
        Self.cool(&ghostTime, dt)
        tickBonus(dt)
        if phase != .playing { return }
        tickWeapon(dt)
        if tempoTime > 0 {
            tempoTime -= dt
            if tempoTime <= 0 {
                tempo = 1
                rescaleBalls()
            }
        }
        mendBricks(dt)
        let piercing = throughTime > 0
        for i in balls.indices {
            if balls[i].stuck {
                balls[i].x = paddle.x + balls[i].grip
                balls[i].y = paddle.y + paddleH * 0.5 + ballR + 2
                balls[i].vx = 0
                balls[i].vy = 0
                continue
            }
            if !balls[i].stuck && balls[i].vy < 0 {
                if attractTime > 0 {
                    balls[i].vx += (paddle.x - balls[i].x) * dt * 1.6
                } else if repelTime > 0 {
                    let away = balls[i].x - paddle.x
                    balls[i].vx += (away == 0 ? 80 : away) * dt * 0.9
                }
            }
            balls[i].x += balls[i].vx * dt
            balls[i].y += balls[i].vy * dt
            if fellOff(i) {
                balls[i].alive = false
                continue
            }
            collidePaddle(i)
            if phase != .playing { return }
            if piercing { pierceBricks(i) } else { collideBricks(i) }
            if phase != .playing { return }
        }
        balls.removeAll { !$0.alive }
        if balls.isEmpty {
            loseLife()
            return
        }
        moveDrops(dt)
    }

    private mutating func beginServe() {
        phase = .serving
        combo = 0
        tempo = 1
        tempoTime = 0
        stickyTime = 0
        throughTime = 0
        floorTime = floorHeld ? 10_000 : 0
        blastTime = 0
        freezeTime = 0
        chaosTime = 0
        weakTime = 0
        darkTime = 0
        weaponTime = 0
        goldTime = 0
        attractTime = 0
        repelTime = 0
        ghostTime = 0
        weaponCooldown = 0
        shots.removeAll(keepingCapacity: true)
        drops.removeAll(keepingCapacity: true)
        balls = [Ball(x: paddle.x, y: 0, vx: 0, vy: 0, stuck: true)]
        stickBall(bob: false)
    }

    private mutating func stickBall(bob: Bool) {
        if balls.isEmpty {
            balls = [Ball(x: paddle.x, y: 0, vx: 0, vy: 0, stuck: true)]
        }
        let bobY: CGFloat = bob ? sin(time * 4.2) * 1.25 : 0
        balls[0].x = paddle.x
        balls[0].y = paddle.y + paddleH * 0.5 + ballR + 2.5 + bobY
        balls[0].vx = 0
        balls[0].vy = 0
        balls[0].stuck = true
        balls[0].grip = 0
    }

    private mutating func releaseStuck() {
        let mag = travel
        for i in balls.indices where balls[i].stuck {
            let hit = balls[i].grip / max(1, paddleW * 0.5)
            let angle = min(1, max(-1, hit)) * 0.9
            balls[i].vx = sin(angle) * mag
            balls[i].vy = abs(cos(angle)) * mag
            if abs(balls[i].vy) < 40 { balls[i].vy = mag }
            balls[i].stuck = false
        }
    }

    private mutating func advance() {
        guard level + 1 < Self.levels.count else {
            finishCampaign()
            return
        }
        if bonus != nil {
            bonus = nil
            bonusClock = 0
            bonusLeft = 0
        } else if !bonusPlayed && (level + 1) % 4 == 0 {
            bonusPlayed = true
            startBonus()
            return
        }
        bonusPlayed = false
        level += 1
        speed = pace(for: level)
        buildLevel()
        clampPaddle()
        beginServe()
    }

    private mutating func finishCampaign() {
        bonus = nil
        campaignDone = true
        justFinished = true
        phase = .over
        notice = "Satz geschafft"
        balls.removeAll(keepingCapacity: true)
        drops.removeAll(keepingCapacity: true)
        shots.removeAll(keepingCapacity: true)
    }

    mutating func retune() {
        speed = pace(for: level)
    }

    private func pace(for level: Int) -> CGFloat {
        let grown = Self.baseSpeed * growth(max(0, level)) * rank.pace
        let cap = min(rank.ceiling, rank.cap + CGFloat(max(0, level - 8)) * rank.creep)
        return min(max(grown, 80), cap)
    }

    private func span(_ seconds: CGFloat) -> CGFloat {
        max(0.4, seconds * rank.time)
    }

    private func growth(_ steps: Int) -> CGFloat {
        var v: CGFloat = 1
        if steps > 0 {
            for _ in 0..<steps { v *= 1.04 }
        }
        return v
    }

    private static func cool(_ timer: inout CGFloat, _ dt: CGFloat) {
        if timer > 0 { timer = max(0, timer - dt) }
    }

    private mutating func movePaddle(_ dt: CGFloat) {
        if phase == .playing && freezeTime > 0 { return }
        switch steer {
        case .idle:
            break
        case .absolute(let x):
            paddle.x = x
        case .velocity(let v):
            paddle.x += v * dt
        }
        clampPaddle()
    }

    private mutating func clampPaddle() {
        let half = paddleW * 0.5
        let lo = field.minX + half + 4
        let hi = field.maxX - half - 4
        if lo >= hi {
            paddle.x = field.midX
            return
        }
        if paddle.x < lo { paddle.x = lo }
        if paddle.x > hi { paddle.x = hi }
    }

    private mutating func fellOff(_ index: Int) -> Bool {
        let left = field.minX + ballR
        let right = field.maxX - ballR
        let top = field.maxY - ballR
        if balls[index].x < left {
            balls[index].x = left
            balls[index].vx = abs(balls[index].vx)
            hitWall = true
            keepAngle(index)
        } else if balls[index].x > right {
            balls[index].x = right
            balls[index].vx = -abs(balls[index].vx)
            hitWall = true
            keepAngle(index)
        }
        if balls[index].y > top {
            balls[index].y = top
            balls[index].vy = -abs(balls[index].vy)
            hitWall = true
            keepAngle(index)
        }
        let sill = field.minY + 11 + ballR
        if floorTime > 0 && balls[index].vy < 0 && balls[index].y <= sill {
            balls[index].y = sill
            balls[index].vy = abs(balls[index].vy)
            hitWall = true
            keepAngle(index)
        }
        return balls[index].y < field.minY - ballR
    }

    private mutating func collidePaddle(_ index: Int) {
        let halfW = paddleW * 0.5
        let halfH = paddleH * 0.5
        let left = paddle.x - halfW
        let right = paddle.x + halfW
        let bottom = paddle.y - halfH
        let top = paddle.y + halfH
        let ball = balls[index]
        let comingDown = ball.vy < 0
        let overX = ball.x >= left - ballR * 0.25 && ball.x <= right + ballR * 0.25
        let onTop = ball.y >= paddle.y && ball.y - ballR <= top + 6
        if comingDown && overX && onTop {
            if stickyTime > 0 {
                balls[index].stuck = true
                balls[index].grip = min(halfW * 0.86, max(-halfW * 0.86, ball.x - paddle.x))
                balls[index].vx = 0
                balls[index].vy = 0
                hitPaddle = true
                lowerBarrier()
                return
            }
            let hit = (ball.x - paddle.x) / halfW
            let angle = min(1, max(-1, hit)) * 1.02
            let mag = travel
            balls[index].vx = sin(angle) * mag
            balls[index].vy = abs(cos(angle)) * mag
            balls[index].y = top + ballR + 0.8
            hitPaddle = true
            combo = 0
            lowerBarrier()
            return
        }

        let beside = ball.y <= top && ball.y >= bottom - ballR
        if beside && ball.x < left && ball.x + ballR >= left {
            balls[index].x = left - ballR - 0.6
            balls[index].vx = -abs(ball.vx)
            hitPaddle = true
        } else if beside && ball.x > right && ball.x - ballR <= right {
            balls[index].x = right + ballR + 0.6
            balls[index].vx = abs(ball.vx)
            hitPaddle = true
        }
    }

    private mutating func collideBricks(_ index: Int) {
        let r = ballR
        var best = -1
        var bestPen = CGFloat.greatestFiniteMagnitude
        var nx: CGFloat = 0
        var ny: CGFloat = 0
        var pushX: CGFloat = 0
        var pushY: CGFloat = 0
        let ball = balls[index]

        for i in bricks.indices {
            let brick = bricks[i]
            if brick.hp <= 0 { continue }
            let cx = min(max(ball.x, brick.minX), brick.maxX)
            let cy = min(max(ball.y, brick.minY), brick.maxY)
            let dx = ball.x - cx
            let dy = ball.y - cy
            let d2 = dx * dx + dy * dy
            if d2 > r * r { continue }

            let pen: CGFloat
            let nnx: CGFloat
            let nny: CGFloat
            let px: CGFloat
            let py: CGFloat
            if d2 > 0.000001 {
                let d = sqrt(d2)
                nnx = dx / d
                nny = dy / d
                pen = r - d
                px = nnx * pen
                py = nny * pen
            } else {
                let left = ball.x - brick.minX
                let right = brick.maxX - ball.x
                let down = ball.y - brick.minY
                let up = brick.maxY - ball.y
                let m = min(left, right, down, up)
                if m == left {
                    nnx = -1; nny = 0; pen = left + r; px = -(left + r); py = 0
                } else if m == right {
                    nnx = 1; nny = 0; pen = right + r; px = right + r; py = 0
                } else if m == down {
                    nnx = 0; nny = -1; pen = down + r; px = 0; py = -(down + r)
                } else {
                    nnx = 0; nny = 1; pen = up + r; px = 0; py = up + r
                }
            }
            if pen < bestPen {
                bestPen = pen
                best = i
                nx = nnx
                ny = nny
                pushX = px
                pushY = py
            }
        }

        if best < 0 { return }
        balls[index].x += pushX
        balls[index].y += pushY
        if chaosTime > 0 || bricks[best].kind == .chaos {
            let mag = max(travel, hypot(balls[index].vx, balls[index].vy))
            let aim = atan2(ny, nx) + CGFloat.random(in: -0.85...0.85)
            balls[index].vx = cos(aim) * mag
            balls[index].vy = sin(aim) * mag
        } else {
            let dot = balls[index].vx * nx + balls[index].vy * ny
            if dot < 0 {
                balls[index].vx -= 2 * dot * nx
                balls[index].vy -= 2 * dot * ny
            }
        }
        keepAngle(index)
        damage(best)
    }

    private mutating func pierceBricks(_ index: Int) {
        let r = ballR
        let ball = balls[index]
        var hit = -1
        for i in bricks.indices {
            let brick = bricks[i]
            if brick.hp <= 0 { continue }
            let cx = min(max(ball.x, brick.minX), brick.maxX)
            let cy = min(max(ball.y, brick.minY), brick.maxY)
            let dx = ball.x - cx
            let dy = ball.y - cy
            if dx * dx + dy * dy <= r * r {
                hit = i
                break
            }
        }
        if hit < 0 {
            balls[index].skip = -1
            return
        }
        if bricks[hit].kind == .wall {
            balls[index].skip = -1
            collideBricks(index)
            return
        }
        if balls[index].skip == hit { return }
        balls[index].skip = hit
        damage(hit)
    }

    private mutating func damage(_ index: Int, fromBlast: Bool = false) {
        if bricks[index].hp <= 0 || bricks[index].kind == .wall || bricks[index].kind == .seed { return }
        if bricks[index].kind == .energy && throughTime <= 0 && !fromBlast {
            notice = "Nur der Energieball"
            noticeBad = false
            return
        }
        if !fromBlast && weakTime > 0 && throughTime <= 0 && CGFloat.random(in: 0..<1) < 0.4 {
            return
        }
        bricks[index].hp -= 1
        if bricks[index].hp > 0 {
            cracked = true
            if bricks[index].kind == .heal { bricks[index].mend = 4 }
            return
        }
        let gift = bricks[index].power
        let origin = bricks[index]
        let spot = origin.center
        bricks[index].hp = 0
        bricks[index].power = nil
        if origin.counts { remaining -= 1 }
        combo = min(combo + 1, 99)
        let shower = goldTime > 0 ? 2 : 1
        let add = Int((CGFloat(origin.points * min(combo, 8) * shower) * rank.score).rounded())
        score += add
        gain += add
        gainAt = spot
        if origin.pitch > destroyedPitch { destroyedPitch = origin.pitch }
        if let gift, drops.count < 8 {
            drops.append(Drop(kind: gift, x: spot.x, y: spot.y))
        }
        awardLife()
        if origin.kind == .tnt {
            for other in bricks.indices where other != index && bricks[other].hp > 0 && near(origin, bricks[other]) {
                guard phase == .playing else { break }
                damage(other, fromBlast: true)
            }
        }
        if origin.kind == .grow {
            for other in bricks.indices where bricks[other].kind == .seed && bricks[other].hp <= 0 && near(origin, bricks[other]) {
                bricks[other].kind = .plain
                bricks[other].counts = true
                bricks[other].hp = 1
                bricks[other].maxHP = 1
                bricks[other].points = 4
                bricks[other].style = 1
                remaining += 1
            }
        }
        if remaining <= 0 && phase == .playing {
            if bonus == .defender && bonusWave < 2 {
                bonusWave += 1
                spawnDefenderWave()
                return
            }
            phase = .cleared
            clearTimer = 1.05
            justCleared = true
            combo = 0
            drops.removeAll(keepingCapacity: true)
            shots.removeAll(keepingCapacity: true)
            return
        }
        guard blastTime > 0, !fromBlast, phase == .playing else { return }
        let targets = bricks.indices.filter { $0 != index && bricks[$0].hp > 0 && near(origin, bricks[$0]) }
        for other in targets where phase == .playing {
            while bricks[other].hp > 0 && phase == .playing {
                damage(other, fromBlast: true)
            }
        }
    }

    private mutating func mendBricks(_ dt: CGFloat) {
        for i in bricks.indices {
            guard bricks[i].kind == .heal, bricks[i].hp > 0, bricks[i].hp < bricks[i].maxHP else { continue }
            if bricks[i].mend <= 0 { bricks[i].mend = 4 }
            bricks[i].mend -= dt
            if bricks[i].mend > 0 { continue }
            bricks[i].hp += 1
            bricks[i].mend = bricks[i].hp < bricks[i].maxHP ? 4 : 0
        }
    }

    private func near(_ a: Brick, _ b: Brick) -> Bool {
        let reach: CGFloat = 14
        return a.minX < b.maxX + reach && b.minX < a.maxX + reach
            && a.minY < b.maxY + reach && b.minY < a.maxY + reach
    }

    private mutating func moveDrops(_ dt: CGFloat) {
        let fall: CGFloat = 150
        var caughtKinds: [Power] = []
        for i in drops.indices {
            drops[i].y -= fall * dt
            if caught(drops[i]) {
                caughtKinds.append(drops[i].kind)
                drops[i].alive = false
            } else if drops[i].y < field.minY - 24 {
                drops[i].alive = false
            }
        }
        drops.removeAll { !$0.alive }
        for kind in caughtKinds where phase == .playing || phase == .serving {
            apply(kind)
        }
    }

    private func caught(_ drop: Drop) -> Bool {
        let half = paddleW * 0.5
        let nearX = abs(drop.x - paddle.x) < half + 26
        let nearY = drop.y <= paddle.y + paddleH && drop.y >= paddle.y - 30
        return nearX && nearY
    }

    private mutating func apply(_ kind: Power) {
        notice = kind.title
        noticeBad = kind.bad
        switch kind {
        case .wide:
            if wideHeld || paddleW > Self.paddleMax {
                paddleW = min(field.width, paddleW + Self.paddleStep)
            } else {
                paddleW = min(Self.paddleMax, paddleW + Self.paddleStep)
            }
        case .narrow:
            if wideHeld || paddleW > Self.paddleMax {
                wideHeld = false
                paddleW = rank.paddle
            } else {
                paddleW = max(Self.paddleMin, paddleW - Self.paddleStep)
            }
        case .multi:
            addBall()
        case .slow:
            let alreadySlow = tempo < 0.99 && tempoTime > 0
            tempo = (Self.baseSpeed * rank.pace) / max(speed, 1)
            tempoTime = alreadySlow ? tempoTime + span(20) : span(20)
            rescaleBalls()
        case .fast:
            let alreadyFast = tempo > 1.01 && tempoTime > 0
            tempo = rank.ceiling / max(speed, 1)
            tempoTime = alreadyFast ? tempoTime + span(20) : span(20)
            rescaleBalls()
        case .life:
            if lives < rank.maxLives {
                lives += 1
                extraLife = true
            }
        case .sticky:
            stickyTime += span(20)
        case .through:
            throughTime += span(5)
        case .bonus:
            let jackpot = Int((1000 * rank.score).rounded())
            score += jackpot
            gain += jackpot
            gainAt = CGPoint(x: paddle.x, y: paddle.y + 36)
        case .floor:
            floorTime = floorHeld ? 10_000 : floorTime + span(10)
        case .blast:
            blastTime += span(10)
        case .freeze:
            freezeTime = span(1)
        case .chaos:
            chaosTime += span(10)
        case .weak:
            weakTime += span(10)
        case .dark:
            darkTime += span(20)
        case .weapon:
            weaponTime += span(15)
        case .gold:
            goldTime += span(15)
        case .joker:
            drops.removeAll(keepingCapacity: true)
            let good = Power.allCases.filter { !$0.bad && $0 != .joker && $0 != .mystery && $0 != .reset }
            if let pick = good.randomElement() {
                apply(pick)
                notice = "Joker: \(pick.title)"
                noticeBad = false
            }
        case .attract:
            repelTime = 0
            attractTime += span(18)
        case .repel:
            attractTime = 0
            repelTime += span(12)
        case .ghost:
            ghostTime += span(12)
        case .reset:
            if tempo > 1 {
                tempo = 1
                tempoTime = 0
                rescaleBalls()
            }
            freezeTime = 0
            chaosTime = 0
            weakTime = 0
            darkTime = 0
            repelTime = 0
            ghostTime = 0
            if !wideHeld && paddleW < rank.paddle { paddleW = rank.paddle }
        case .clock:
            let extra = span(7)
            if stickyTime > 0 { stickyTime += extra }
            if throughTime > 0 { throughTime += extra }
            if !floorHeld && floorTime > 0 { floorTime += extra }
            if blastTime > 0 { blastTime += extra }
            if chaosTime > 0 { chaosTime += extra }
            if weakTime > 0 { weakTime += extra }
            if darkTime > 0 { darkTime += extra }
            if weaponTime > 0 { weaponTime += extra }
            if goldTime > 0 { goldTime += extra }
            if attractTime > 0 { attractTime += extra }
            if repelTime > 0 { repelTime += extra }
            if ghostTime > 0 { ghostTime += extra }
            if tempoTime > 0 { tempoTime += extra }
        case .mystery:
            let pool = Power.allCases.filter { $0 != .mystery && $0 != .joker }
            if let pick = pool.randomElement() { apply(pick) }
        }
        clampPaddle()
    }

    private mutating func addBall() {
        guard balls.count < 6, let source = balls.first else { return }
        var copy = source
        copy.skip = -1
        copy.stuck = false
        let turn: CGFloat = source.stuck ? 0.45 : 0.7
        let vx = source.stuck ? 0 : source.vx
        let vy = source.stuck ? travel : source.vy
        copy.vx = vx * cos(turn) - vy * sin(turn)
        copy.vy = abs(vx * sin(turn) + vy * cos(turn))
        if abs(copy.vy) < 40 { copy.vy = travel }
        balls.append(copy)
        rescaleBalls()
    }

    private mutating func rescaleBalls() {
        let mag = travel
        for i in balls.indices where !balls[i].stuck {
            let now = hypot(balls[i].vx, balls[i].vy)
            if now < 1 { continue }
            let k = mag / now
            balls[i].vx *= k
            balls[i].vy *= k
        }
    }

    private mutating func awardLife() {
        let bucket = score / 10000
        if bucket > lifeBucket && lives < 7 {
            lives += 1
            extraLife = true
        }
        if bucket > lifeBucket { lifeBucket = bucket }
    }

    var shield = false
    var floorHeld = false
    var wideHeld = false
    var cheatScore = false
    var campaignDone = false
    var justFinished = false

    mutating func cheat(_ kind: Power) {
        guard phase == .serving || phase == .playing else { return }
        apply(kind)
    }

    mutating func cheatSkip() {
        guard phase == .serving || phase == .playing else { return }
        advance()
    }

    mutating func cheatShield() -> Bool {
        shield.toggle()
        return shield
    }

    mutating func cheatMillion() {
        cheatScore = true
        score = score >= 1_000_000 ? score + 1_000_000 : 1_000_000
    }

    mutating func cheatManyLives() {
        lives = lives >= 99 ? lives + 100 : 99
    }

    mutating func cheatFullPaddle() {
        wideHeld = true
        paddleW = field.width
        clampPaddle()
    }

    mutating func cheatNormalPaddle() {
        wideHeld = false
        paddleW = rank.paddle
        clampPaddle()
    }

    /// Haken neben Boden: der Boden bleibt, auch nach dem Aufschlag und in der nächsten Runde.
    mutating func cheatHoldFloor() -> Bool {
        floorHeld.toggle()
        floorTime = floorHeld ? 10_000 : 0
        return floorHeld
    }

    private mutating func loseLife() {
        if shield {
            beginServe()
            notice = "Schutz"
            return
        }
        lives -= 1
        combo = 0
        lostLife = true
        phase = .dying
        dieTimer = 0.6
        balls.removeAll(keepingCapacity: true)
        drops.removeAll(keepingCapacity: true)
        shots.removeAll(keepingCapacity: true)
    }

    private mutating func keepAngle(_ index: Int) {
        let mag = hypot(balls[index].vx, balls[index].vy)
        if mag < 1 { return }
        let minY = mag * 0.28
        if abs(balls[index].vy) >= minY { return }
        balls[index].vy = (balls[index].vy >= 0 ? 1 : -1) * minY
        let now = hypot(balls[index].vx, balls[index].vy)
        balls[index].vx *= mag / now
        balls[index].vy *= mag / now
    }

    private mutating func buildLevel() {
        let def = Self.layout(for: level)
        stamp(def.rows, sink: def.sink)
        sprinklePowers()
    }

    private mutating func stamp(_ rows: [String], sink: Int) {
        let cols = rows.map(\.count).max() ?? 1
        let gap: CGFloat = 9
        let side: CGFloat = 18
        let brickH: CGFloat = 22
        let top = 20 + CGFloat(max(0, sink)) * (brickH + gap)
        let avail = field.width - side * 2 - gap * CGFloat(max(0, cols - 1))
        let brickW = avail / CGFloat(max(1, cols))
        let sprouts = rows.contains { $0.contains("+") }
        bricks.removeAll(keepingCapacity: true)
        for (r, row) in rows.enumerated() {
            for (c, ch) in row.enumerated() {
                let spec: Spec?
                if ch == ".", sprouts {
                    spec = Spec(style: 1, points: 4, pitch: 2, hp: 0, kind: .seed, counts: false)
                } else {
                    spec = Self.spec(ch)
                }
                guard let spec else { continue }
                let x = field.minX + side + CGFloat(c) * (brickW + gap)
                let y = field.maxY - top - brickH - CGFloat(r) * (brickH + gap)
                bricks.append(Brick(
                    minX: x, minY: y, w: brickW, h: brickH,
                    hp: spec.hp, maxHP: max(spec.hp, 1), points: spec.points,
                    style: spec.style, pitch: spec.pitch, power: nil,
                    kind: spec.kind, counts: spec.counts))
            }
        }
        remaining = bricks.reduce(0) { $0 + ($1.counts && $1.hp > 0 ? 1 : 0) }
    }

    private mutating func startBonus() {
        let kinds = Bonus.allCases
        let pick = kinds[(level / 4) % kinds.count]
        bonus = pick
        bonusClock = 0
        bonusWave = 0
        bonusLeft = pick.limit
        layBonus(pick)
        sprinklePowers()
        beginServe()
        notice = pick.title
    }

    private mutating func layBonus(_ pick: Bonus) {
        switch pick {
        case .barrier:
            stamp([
                "1111111111111",
                "2222222222222",
                "3333333333333",
                "4444444444444",
            ], sink: 1)
        case .outbreak:
            stamp([
                "......1......",
                ".....222.....",
                "......1......",
            ], sink: 2)
        case .jack:
            stamp(["......8......"], sink: 2)
            if let index = bricks.firstIndex(where: { $0.hp > 0 }) {
                bricks[index].hp = 4
                bricks[index].maxHP = 4
                bricks[index].kind = .tough
            }
        case .ducks:
            stamp([
                "1.1.1.1.1.1.1",
                ".2.2.2.2.2.2.",
                "3.3.3.3.3.3.3",
            ], sink: 1)
        case .hunter:
            stamp(["1.2.3.4.5.6.1"], sink: 2)
            for index in bricks.indices {
                bricks[index].drift = index % 2 == 0 ? 1 : -1
            }
        case .defender:
            spawnDefenderWave()
        }
    }

    private mutating func spawnDefenderWave() {
        stamp(["2222222222222"], sink: 2)
    }

    private mutating func tickBonus(_ dt: CGFloat) {
        guard let bonus else { return }
        bonusClock += dt
        if bonus.timed {
            bonusLeft -= dt
            if bonusLeft <= 0 {
                phase = .cleared
                clearTimer = 0.7
                justCleared = true
                drops.removeAll(keepingCapacity: true)
                shots.removeAll(keepingCapacity: true)
                return
            }
        }
        switch bonus {
        case .barrier:
            breach()
        case .outbreak:
            if bonusClock >= 2.2 && bonusWave < 8 {
                bonusClock = 0
                sprout()
            }
        case .jack:
            if bonusClock >= 1.15 {
                bonusClock = 0
                jumpJack()
            }
        case .hunter:
            let step = 90 * dt
            for index in bricks.indices where bricks[index].hp > 0 && bricks[index].drift != 0 {
                bricks[index].minX += bricks[index].drift * step
                if bricks[index].minX < field.minX + 16 {
                    bricks[index].minX = field.minX + 16
                    bricks[index].drift = 1
                } else if bricks[index].maxX > field.maxX - 16 {
                    bricks[index].minX = field.maxX - 16 - bricks[index].w
                    bricks[index].drift = -1
                }
            }
        case .defender:
            for index in bricks.indices where bricks[index].hp > 0 {
                bricks[index].minY -= 26 * dt
            }
            breach()
        case .ducks:
            break
        }
    }

    /// Eine Reihe tiefer, sobald der Ball wieder auf dem Schläger ankommt.
    private mutating func lowerBarrier() {
        guard bonus == .barrier else { return }
        let drop = (bricks.first?.h ?? 22) + 9
        for index in bricks.indices { bricks[index].minY -= drop }
    }

    private mutating func breach() {
        let line = paddle.y + paddleH + 10
        guard bricks.contains(where: { $0.hp > 0 && $0.counts && $0.minY < line }) else { return }
        let lift = ((bricks.first?.h ?? 22) + 9) * 2
        for index in bricks.indices { bricks[index].minY += lift }
        loseLife()
    }

    private mutating func sprout() {
        guard let hostIndex = bricks.indices.filter({ bricks[$0].hp > 0 }).randomElement() else { return }
        let host = bricks[hostIndex]
        let options: [(CGFloat, CGFloat)] = [
            (host.w + 9, 0), (-(host.w + 9), 0), (0, host.h + 9), (0, -(host.h + 9)),
        ]
        for (dx, dy) in options.shuffled() {
            let x = host.minX + dx
            let y = host.minY + dy
            if x < field.minX + 12 || x + host.w > field.maxX - 12 { continue }
            if y < paddle.y + 90 || y > field.maxY - 36 { continue }
            let occupied = bricks.contains { abs($0.minX - x) < 8 && abs($0.minY - y) < 8 && $0.hp > 0 }
            if occupied { continue }
            bricks.append(Brick(
                minX: x, minY: y, w: host.w, h: host.h,
                hp: 1, maxHP: 1, points: 4, style: bonusWave % 7, pitch: 3,
                power: nil, kind: .plain, counts: true))
            remaining += 1
            bonusWave += 1
            return
        }
    }

    private mutating func jumpJack() {
        guard let index = bricks.firstIndex(where: { $0.hp > 0 }) else { return }
        let cols = 7
        let rows = 4
        let gap: CGFloat = 9
        let span = bricks[index].w + gap
        let left = field.midX - span * CGFloat(cols) * 0.5
        let col = Int.random(in: 0..<cols)
        let row = Int.random(in: 0..<rows)
        bricks[index].minX = left + CGFloat(col) * span
        bricks[index].minY = field.maxY - 70 - CGFloat(row) * (bricks[index].h + gap)
    }

    private mutating func tickWeapon(_ dt: CGFloat) {
        guard weaponTime > 0 else {
            if !shots.isEmpty { shots.removeAll(keepingCapacity: true) }
            return
        }
        weaponCooldown -= dt
        if weaponCooldown <= 0 && shots.count < 6 {
            weaponCooldown = 0.42
            shots.append(Shot(x: paddle.x, y: paddle.y + paddleH))
        }
        var hits: [Int] = []
        for index in shots.indices {
            shots[index].y += 560 * dt
            if shots[index].y > field.maxY {
                shots[index].alive = false
                continue
            }
            let shot = shots[index]
            if let hit = bricks.indices.first(where: {
                bricks[$0].hp > 0
                    && shot.x >= bricks[$0].minX && shot.x <= bricks[$0].maxX
                    && shot.y >= bricks[$0].minY && shot.y <= bricks[$0].maxY
            }) {
                shots[index].alive = false
                hits.append(hit)
            }
        }
        shots.removeAll { !$0.alive }
        for hit in hits {
            guard phase == .playing else { break }
            damage(hit)
        }
    }

    private mutating func sprinklePowers() {
        var rng = SystemRandomNumberGenerator()
        var candidates = bricks.indices.filter { bricks[$0].kind == .plain && bricks[$0].maxHP == 1 }
        guard candidates.count >= 4 else {
            plantEnergy()
            return
        }
        candidates.shuffle(using: &rng)
        var kinds = Power.allCases.shuffled(using: &rng)
        let kindCount = min(kinds.count, Int.random(in: 4...6, using: &rng))
        kinds = Array(kinds.prefix(kindCount))
        let malus: [Power] = [.narrow, .fast, .freeze, .chaos, .weak, .dark, .repel, .ghost]
        if rank != .kids && !kinds.contains(where: \.bad) {
            kinds[0] = malus.randomElement(using: &rng) ?? .narrow
        }
        if rank == .kids {
            kinds = kinds.filter { !$0.bad }
            if kinds.isEmpty { kinds = [.wide, .slow, .multi, .life] }
        } else if rank == .easy {
            var kept = false
            kinds = kinds.compactMap { kind in
                if !kind.bad { return kind }
                if kept { return nil }
                kept = true
                return kind
            }
        } else if rank == .hard {
            var bad = kinds.filter(\.bad).count
            var slot = 0
            while bad < 2 && slot < kinds.count {
                if !kinds[slot].bad {
                    kinds[slot] = malus.randomElement(using: &rng) ?? .fast
                    bad += 1
                }
                slot += 1
            }
        }
        let count = min(candidates.count, Int.random(in: 5...8, using: &rng))
        for i in 0..<count {
            bricks[candidates[i]].power = kinds[i % kinds.count]
        }
        plantEnergy()
    }

    private mutating func plantEnergy() {
        guard bricks.contains(where: { $0.kind == .energy }),
              let host = bricks.indices.first(where: { bricks[$0].kind == .plain && bricks[$0].hp > 0 })
        else { return }
        bricks[host].power = .through
    }

    private struct Spec {
        var style: Int
        var points: Int
        var pitch: Int
        var hp: Int
        var kind: Kind = .plain
        var counts = true
    }

    private static func spec(_ ch: Character) -> Spec? {
        switch ch {
        case "1": return Spec(style: 0, points: 7, pitch: 6, hp: 1)
        case "2": return Spec(style: 1, points: 5, pitch: 5, hp: 1)
        case "3": return Spec(style: 2, points: 4, pitch: 4, hp: 1)
        case "4": return Spec(style: 3, points: 3, pitch: 3, hp: 1)
        case "5": return Spec(style: 4, points: 3, pitch: 2, hp: 1)
        case "6": return Spec(style: 5, points: 2, pitch: 1, hp: 1)
        case "7": return Spec(style: 6, points: 1, pitch: 0, hp: 1)
        case "#": return Spec(style: 7, points: 8, pitch: 3, hp: 2, kind: .steel)
        case "=": return Spec(style: 7, points: 0, pitch: 0, hp: 1, kind: .wall, counts: false)
        case "&": return Spec(style: 0, points: 12, pitch: 6, hp: 1, kind: .energy)
        case "@": return Spec(style: 6, points: 9, pitch: 4, hp: 1, kind: .chaos)
        case "8": return Spec(style: 2, points: 10, pitch: 3, hp: 3, kind: .tough)
        case "%": return Spec(style: 3, points: 8, pitch: 2, hp: 2, kind: .heal)
        case "*": return Spec(style: 0, points: 6, pitch: 5, hp: 1, kind: .tnt)
        case "+": return Spec(style: 3, points: 6, pitch: 2, hp: 1, kind: .grow)
        default: return nil
        }
    }

    private static let opening: [Level] = [
        Level(name: "Klassiker", rows: [
            "1111111111111",
            "2222222222222",
            "3333333333333",
            "4444444444444",
            "5555555555555",
            "6666666666666",
        ]),
        Level(name: "Lücken", rows: [
            "1.1.1.1.1.1.1",
            ".2.2.2.2.2.2.",
            "3.3.3.3.3.3.3",
            ".4.4.4.4.4.4.",
            "5.5.5.5.5.5.5",
            ".6.6.6.6.6.6.",
        ]),
        Level(name: "Pyramide", sink: 2, rows: [
            "......1......",
            ".....222.....",
            "....33333....",
            "...4444444...",
            "..555555555..",
            ".66666666666.",
            "7777777777777",
        ]),
        Level(name: "Festung", rows: [
            "1111111111111",
            "1#####.#####1",
            "1#222222222#1",
            "1#333333333#1",
            "1#444444444#1",
            "1###########1",
        ]),
        Level(name: "Rinne", rows: [
            "1111111111111",
            "2222.....2222",
            "3333333333333",
            "4444.....4444",
            "5555555555555",
            "6666.....6666",
        ]),
        Level(name: "Diamant", sink: 3, rows: [
            "......3......",
            ".....353.....",
            "....35753....",
            "...3575753...",
            "....35753....",
            ".....353.....",
            "......3......",
        ]),
        Level(name: "Doppelwand", rows: [
            "1111111111111",
            "7777777777777",
            "3333333333333",
            "######.######",
            "5555555555555",
            "2222222222222",
            "6666666666666",
        ]),
        Level(name: "Schluss", rows: [
            "#1#1#1#1#1#1#",
            "2222222222222",
            "#3#3#3#3#3#3#",
            "4444444444444",
            "#5#5#5#5#5#5#",
            "6666666666666",
            "#7#7#7#7#7#7#",
        ]),
        Level(name: "Treppe", rows: [
            "11111........",
            ".22222.......",
            "..33333......",
            "...44444.....",
            "....55555....",
            ".....66666...",
            "......77777..",
        ]),
        Level(name: "Ring", rows: [
            "1111111111111",
            "1...........1",
            "1...22222...1",
            "1...2...2...1",
            "1...22222...1",
            "1...........1",
            "1111111111111",
        ]),
        Level(name: "Kreuz", sink: 1, rows: [
            ".....111.....",
            ".....222.....",
            ".....333.....",
            "4444444444444",
            "5555555555555",
            ".....666.....",
            ".....777.....",
            ".....###.....",
        ]),
        Level(name: "Welle", rows: [
            "1122....3344.",
            ".1122....3344",
            "..1122....334",
            "...1122....33",
            "..5566....778",
            ".5566....7788",
            "5566....7788.",
        ]),
        Level(name: "Säulen", rows: [
            "1.1.1.1.1.1.1",
            "#.#.#.#.#.#.#",
            "2.2.2.2.2.2.2",
            "#.#.#.#.#.#.#",
            "3.3.3.3.3.3.3",
            "#.#.#.#.#.#.#",
            "4.4.4.4.4.4.4",
        ]),
        Level(name: "Inseln", rows: [
            "111....222..3",
            "111....222..3",
            "111....222..3",
            ".............",
            "444....555..6",
            "444....555..6",
            "444....555..6",
        ]),
        Level(name: "Trichter", rows: [
            "1...........1",
            ".22.......22.",
            "..333...333..",
            "...444.444...",
            "....55555....",
            ".....666.....",
            "......7......",
        ]),
        Level(name: "Bogen", rows: [
            "..111111111..",
            ".1.........1.",
            "1...........1",
            "1....222....1",
            "1...2...2...1",
            "11112...21111",
            "....22222....",
        ]),
        Level(name: "Schach", rows: [
            "1212121212121",
            "2121212121212",
            "1212121212121",
            "2121212121212",
            "3434343434343",
            "4343434343434",
            "3434343434343",
        ]),
        Level(name: "Pfeil", sink: 2, rows: [
            "......1......",
            ".....222.....",
            "....33333....",
            "...4444444...",
            "..555555555..",
            ".66666666666.",
            "######7######",
        ]),
        Level(name: "Fenster", rows: [
            "1111111111111",
            "1.1.1.1.1.1.1",
            "1111111111111",
            "1.1.1.1.1.1.1",
            "1111111111111",
            "1.1.1.1.1.1.1",
            "1111111111111",
        ]),
        Level(name: "Zange", rows: [
            "11.........11",
            "1.1.......1.1",
            "1..2.....2..1",
            "1...3...3...1",
            "1....4.4....1",
            "1.....5.....1",
            "11....#....11",
        ]),
        Level(name: "Leiter", rows: [
            "1...........1",
            "2222222222222",
            "3...........3",
            "4444444444444",
            "5...........5",
            "6666666666666",
            "7...........7",
        ]),
        Level(name: "Herz", sink: 2, rows: [
            ".22.....22...",
            "2222...2222..",
            "22222222222..",
            ".1111111111..",
            "..11111111...",
            "...111111....",
            "....1111.....",
            ".....11......",
        ]),
        Level(name: "Tor", rows: [
            "#############",
            "##.........11",
            "##.3333333.11",
            "##.3.....3.11",
            "##.3.....3.11",
            "##.3333333.11",
            "##.........11",
            "#############",
        ]),
        Level(name: "Zwillinge", sink: 4, rows: [
            "..111...444..",
            ".1...1.4...4.",
            "1....1.4....4",
            ".1...1.4...4.",
            "..111...444..",
        ]),
        Level(name: "Krone", rows: [
            "1.1.1.1.1.1.1",
            "2222222222222",
            ".###########.",
            "..#########..",
            "...#######...",
            "....#####....",
            ".....444.....",
        ]),
        Level(name: "Brücke", rows: [
            "11111...22222",
            "1...........2",
            "1....777....2",
            "1...7...7...2",
            "1..7777777..2",
            "1...........2",
            "11111...22222",
        ]),
        Level(name: "Gang", rows: [
            "111111111111.",
            "1..........1.",
            "1.22222222.1.",
            "1.2......2.1.",
            "1.2.4444.2.1.",
            "1.2.4..4.2.1.",
            "1.2.4444.2.1.",
            "1.2......2.1.",
            "1.22222222.1.",
            "1..........1.",
            ".11111111111.",
        ]),
        Level(name: "Keil", sink: 3, rows: [
            "11.........11",
            ".22.......22.",
            "..33.....33..",
            "...44...44...",
            "....55.55....",
            ".....666.....",
            "......7......",
        ]),
        Level(name: "Schere", rows: [
            "1...........2",
            ".3.........4.",
            "..5.......6..",
            "...7.....1...",
            "....2...3....",
            "...4.....5...",
            "..6.......7..",
            ".1.........2.",
            "3...........4",
        ]),
        Level(name: "Riesen", rows: [
            "#####",
            "11111",
            "22222",
            "33333",
            "44444",
        ]),
        Level(name: "Turm", sink: 1, rows: [
            "#.#",
            "222",
            "#.#",
            "333",
            "#.#",
            "444",
            "#.#",
        ]),
        Level(name: "Balken", sink: 1, rows: [
            "1111111",
            ".......",
            "2222222",
            ".......",
            "3333333",
            ".......",
            "4444444",
        ]),
        Level(name: "Mond", sink: 2, rows: [
            "..22222..",
            ".2.....2.",
            "2.......2",
            "2...1...2",
            "2.......2",
            ".2.....2.",
            "..22222..",
        ]),
        Level(name: "Konfetti", rows: [
            "1.2.3.4.5.6.7.1.2.3.4",
            ".7.6.5.4.3.2.1.7.6.5.",
            "2.4.6.1.3.5.7.2.4.6.1",
            ".1.3.5.7.2.4.6.1.3.5.",
            "3.6.1.4.7.2.5.3.6.1.4",
            ".5.2.7.4.1.6.3.5.2.7.",
        ]),
        Level(name: "Gitter", sink: 1, rows: [
            "1.1.1.1.1.1.1.1.1",
            ".#.#.#.#.#.#.#.#.",
            "2.2.2.2.2.2.2.2.2",
            ".#.#.#.#.#.#.#.#.",
            "3.3.3.3.3.3.3.3.3",
            ".#.#.#.#.#.#.#.#.",
            "4.4.4.4.4.4.4.4.4",
        ]),
        Level(name: "Tief", sink: 8, rows: [
            "1111111111111",
            "#####...#####",
            "2222222222222",
        ]),
        Level(name: "Rahmen", sink: 2, rows: [
            "###############",
            "#.............#",
            "#.............#",
            "#.....777.....#",
            "#.............#",
            "#.............#",
            "###############",
        ]),
        Level(name: "Pfeiler", rows: [
            "#.#.#.#.#.#",
            "1.1.1.1.1.1",
            "#.#.#.#.#.#",
            "2.2.2.2.2.2",
            "#.#.#.#.#.#",
            "3.3.3.3.3.3",
        ]),
        Level(name: "Wolke", sink: 4, rows: [
            "...1111111...",
            ".11222222211.",
            "1122333322111",
            ".11222222211.",
            "...1111111...",
        ]),
        Level(name: "Schlitz", sink: 1, rows: [
            "1111111111111",
            ".............",
            ".............",
            "......#......",
            ".............",
            ".............",
            "7777777777777",
        ]),
        Level(name: "Keilbreit", sink: 1, rows: [
            ".......1.......",
            "......222......",
            ".....33333.....",
            "....4444444....",
            "...555555555...",
            "..66666666666..",
            ".##############",
        ]),
        Level(name: "Kamm", rows: [
            "1.1.1.1.1.1.1.1.1.1",
            "1111111111111111111",
            "2.2.2.2.2.2.2.2.2.2",
            "2222222222222222222",
            "3.3.3.3.3.3.3.3.3.3",
            "3333333333333333333",
        ]),
        Level(name: "Punkt", sink: 5, rows: [
            "....2....",
            "...222...",
            "..22222..",
            "...222...",
            "....2....",
        ]),
        Level(name: "Mauer", rows: [
            "=============",
            "=11111111111=",
            "=2222...2222=",
            "=33333333333=",
            "=============",
        ]),
        Level(name: "Energie", rows: [
            "1111111111111",
            "&&&&&...&&&&&",
            "2222222222222",
        ]),
        Level(name: "Wirbel", rows: [
            "1@1@1@1@1@1@1",
            "2222222222222",
            "@3@3@3@3@3@3@",
            "4444444444444",
        ]),
        Level(name: "Panzer", rows: [
            "8888888888888",
            "1111111111111",
            "8888888888888",
        ]),
        Level(name: "Heilung", rows: [
            "%%%%%%%%%%%",
            "11111111111",
            "%%%%%%%%%%%",
        ]),
        Level(name: "Zünder", rows: [
            "1*111*111*111",
            "2222222222222",
            "3*333*333*333",
            "4444444444444",
        ]),
        Level(name: "Ranke", rows: [
            "1+.1+.1+.1+.1",
            "2222222222222",
            ".3.3.3.3.3.3.",
        ]),
        Level(name: "Werkstatt", rows: [
            "=111*111*111=",
            "222%222%22222",
            "33&33&33&3333",
            "8@8@8@8@8@8@8",
        ]),
        Level(name: "Tresor", sink: 1, rows: [
            "=============",
            "=88888888888=",
            "=8.........8=",
            "=8..11111..8=",
            "=8.........8=",
            "=============",
        ]),
    ]

    private static let levels: [Level] = opening + extraLevels

    static func layout(for level: Int) -> Level {
        let index = min(max(0, level), levels.count - 1)
        return levels[index]
    }


    func snapshot() -> Save? {
        if phase == .over { return nil }
        var copy = self
        if copy.phase == .dying {
            if copy.lives <= 0 { return nil }
            copy.beginServe()
        } else if copy.phase == .cleared {
            copy.advance()
        }
        return Save(
            score: copy.score,
            lives: copy.lives,
            level: copy.level,
            combo: copy.combo,
            lifeBucket: copy.lifeBucket,
            speed: Double(copy.speed),
            paddleX: Double(copy.paddle.x),
            paddleW: Double(copy.paddleW),
            tempo: Double(copy.tempo),
            tempoTime: Double(copy.tempoTime),
            sticky: Double(copy.stickyTime),
            through: Double(copy.throughTime),
            floor: Double(copy.floorTime),
            blast: Double(copy.blastTime),
            freeze: Double(copy.freezeTime),
            chaos: Double(copy.chaosTime),
            weak: Double(copy.weakTime),
            dark: Double(copy.darkTime),
            shield: copy.shield,
            cheated: copy.cheatScore ? true : nil,
            phase: copy.phase.rawValue,
            hp: copy.bricks.map(\.hp),
            power: copy.bricks.map { $0.power?.rawValue ?? -1 },
            balls: copy.balls,
            drops: copy.drops,
            rank: copy.rank.rawValue,
            weapon: copy.weaponTime > 0 ? Double(copy.weaponTime) : nil,
            gold: copy.goldTime > 0 ? Double(copy.goldTime) : nil,
            attract: copy.attractTime > 0 ? Double(copy.attractTime) : nil,
            repel: copy.repelTime > 0 ? Double(copy.repelTime) : nil,
            ghost: copy.ghostTime > 0 ? Double(copy.ghostTime) : nil,
            bonusKind: copy.bonus?.rawValue,
            bonusLeft: copy.bonusLeft > 0 ? Double(copy.bonusLeft) : nil,
            bonusWave: copy.bonus == nil ? nil : copy.bonusWave)
    }

    mutating func restore(_ save: Save) {
        score = save.score
        lives = max(0, save.lives)
        level = max(0, save.level)
        combo = save.combo
        lifeBucket = save.lifeBucket
        speed = pace(for: max(0, save.level))
        let savedW = CGFloat(save.paddleW)
        wideHeld = false
        paddleW = savedW > Self.paddleMax
            ? rank.paddle
            : min(Self.paddleMax, max(Self.paddleMin, savedW))
        paddle.x = CGFloat(save.paddleX)
        tempo = CGFloat(save.tempo)
        tempoTime = CGFloat(save.tempoTime)
        stickyTime = CGFloat(save.sticky)
        throughTime = CGFloat(save.through)
        floorTime = CGFloat(save.floor)
        floorHeld = false
        if floorTime > 30 { floorTime = 0 }
        blastTime = CGFloat(save.blast)
        freezeTime = CGFloat(save.freeze)
        chaosTime = CGFloat(save.chaos)
        weakTime = CGFloat(save.weak)
        darkTime = CGFloat(save.dark)
        weaponTime = CGFloat(save.weapon ?? 0)
        goldTime = CGFloat(save.gold ?? 0)
        attractTime = CGFloat(save.attract ?? 0)
        repelTime = CGFloat(save.repel ?? 0)
        ghostTime = CGFloat(save.ghost ?? 0)
        bonus = save.bonusKind.flatMap(Bonus.init(rawValue:))
        bonusPlayed = bonus != nil
        bonusLeft = CGFloat(save.bonusLeft ?? 0)
        bonusWave = save.bonusWave ?? 0
        bonusClock = 0
        shield = false
        if lives > 12 {
            lives = rank.lives
        } else if lives > rank.maxLives {
            lives = rank.maxLives
        }
        cheatScore = save.cheated == true
        if let kind = save.bonusKind.flatMap(Bonus.init(rawValue:)) {
            bonus = kind
            bonusPlayed = true
            bonusLeft = CGFloat(save.bonusLeft ?? Double(kind.limit))
            bonusWave = save.bonusWave ?? 0
            layBonus(kind)
        } else {
            bonus = nil
            bonusPlayed = false
            buildLevel()
        }
        if save.hp.count == bricks.count, save.power.count == bricks.count {
            for i in bricks.indices {
                bricks[i].hp = max(0, save.hp[i])
                if bricks[i].hp == 0 {
                    bricks[i].power = nil
                } else if let gift = Power(rawValue: save.power[i]) {
                    bricks[i].power = gift
                } else {
                    bricks[i].power = nil
                }
            }
            for i in bricks.indices where bricks[i].kind == .seed && bricks[i].hp > 0 {
                bricks[i].kind = .plain
                bricks[i].counts = true
                bricks[i].maxHP = 1
            }
            for i in bricks.indices where bricks[i].kind == .wall {
                bricks[i].hp = 1
            }
            remaining = bricks.reduce(0) { $0 + ($1.counts && $1.hp > 0 ? 1 : 0) }
        }
        balls = save.balls
        drops = save.drops
        phase = Phase(rawValue: save.phase) ?? .serving
        if phase != .playing { phase = .serving }
        if balls.isEmpty || phase == .serving {
            phase = .serving
            stickBall(bob: false)
        }
        clampPaddle()
        clearFlags()
    }

    static func runTests() {
        func fail(_ message: String) -> Never {
            fputs("self-test: \(message)\n", stderr)
            exit(1)
        }

        for level in levels {
            let width = level.rows.map(\.count).max() ?? 0
            if width < 3 { fail("leeres Level \(level.name)") }
            for row in level.rows where row.count != width {
                fail("ungleiche Zeile in \(level.name)")
            }
        }

        var sim = Sim()
        sim.layout(field: CGRect(x: 26, y: 22, width: 980, height: 692))
        sim.newGame()
        if sim.bricks.isEmpty { fail("keine Steine") }

        func smack(_ index: Int) {
            let before = sim.bricks[index].hp
            let b = sim.bricks[index]
            sim.phase = .playing
            sim.balls = [Ball(
                x: b.minX + b.w * 0.5,
                y: b.minY - sim.ballR - 0.4,
                vx: 0,
                vy: 420)]
            var hit = false
            for _ in 0..<80 {
                sim.step(1 / 240)
                if sim.bricks[index].hp < before { hit = true; break }
                if sim.balls.contains(where: { $0.x.isNaN || $0.y.isNaN }) { fail("nan") }
            }
            if !hit { fail("kein Treffer") }
        }

        let first = sim.bricks.firstIndex { $0.hp > 0 }!
        let scoreBefore = sim.score
        smack(first)
        if sim.score <= scoreBefore { fail("Punkte fehlen") }
        if sim.bricks.contains(where: { $0.hp < 0 }) { fail("hp negativ") }

        sim.newGame()
        sim.advance()
        sim.advance()
        sim.advance()
        guard let steel = sim.bricks.firstIndex(where: { $0.maxHP == 2 }) else {
            fail("kein fester Stein")
        }
        smack(steel)
        if sim.bricks[steel].hp != 1 { fail("fester Stein sollte angebrochen sein") }
        smack(steel)
        if sim.bricks[steel].hp != 0 { fail("fester Stein sollte weg sein") }

        var layouts: Set<String> = []
        for _ in 0..<10 {
            var sample = Sim()
            sample.layout(field: CGRect(x: 26, y: 22, width: 980, height: 692))
            sample.newGame()
            let signature = sample.bricks.map { $0.power?.rawValue ?? -1 }.map(String.init).joined(separator: ",")
            layouts.insert(signature)
            let gifts = sample.bricks.compactMap(\.power)
            if gifts.count < 4 || gifts.count > 8 { fail("Power-up-Anzahl \(gifts.count)") }
            if Set(gifts).count < 2 { fail("zu wenig verschiedene Power-ups") }
        }
        if layouts.count < 2 { fail("Power-ups wiederholen sich") }

        sim.newGame()
        sim.phase = .playing
        sim.balls = [Ball(x: sim.paddle.x, y: sim.paddle.y + 30, vx: 0, vy: 200)]
        sim.drops = [Drop(kind: .wide, x: sim.paddle.x, y: sim.paddle.y + 8)]
        sim.step(1 / 240)
        if sim.paddleW <= Self.paddleStart { fail("breiter Schläger kam nicht an") }
        if sim.notice != Power.wide.title { fail("Hinweis fehlt") }

        sim.newGame()
        for i in sim.bricks.indices { sim.bricks[i].power = nil }
        sim.launch()
        sim.balls[0].vx = 0
        sim.balls[0].vy = sim.speed
        sim.balls[0].stuck = false
        for _ in 0..<(240 * 12) {
            if sim.phase == .serving {
                sim.launch()
                sim.balls[0].vx = 0
                sim.balls[0].vy = sim.speed
                sim.balls[0].stuck = false
            }
            let tracked = sim.balls.first?.x ?? sim.paddle.x
            sim.steer = .absolute(tracked)
            sim.step(1 / 240)
            if sim.balls.contains(where: { $0.x.isNaN || $0.y.isNaN }) || sim.speed.isNaN {
                fail("nan in der Rallye")
            }
            if sim.speed > Self.maxSpeed + 0.01 { fail("zu schnell") }
        }
        if sim.score < 6 || sim.lives < 3 {
            fail("Rallye score=\(sim.score) lives=\(sim.lives)")
        }
        let rallyScore = sim.score
        let rallyLives = sim.lives
        let rallyRound = sim.level + 1
        sim.newGame()
        sim.score = 40
        sim.lives = 2
        guard let snap = sim.snapshot() else { fail("kein Stand") }
        var back = Sim()
        back.layout(field: CGRect(x: 26, y: 22, width: 980, height: 692))
        back.restore(snap)
        if back.score != 40 || back.lives != 2 || back.level != sim.level { fail("Stand falsch") }
        if back.bricks.map(\.hp) != sim.bricks.map(\.hp) { fail("Steine falsch") }
        let gifts = { (item: Sim) in item.bricks.map { $0.power?.rawValue ?? -1 } }
        if gifts(back) != gifts(sim) { fail("Kapseln falsch") }

        func stage(_ name: String) -> Sim {
            guard let idx = levels.firstIndex(where: { $0.name == name }) else { fail("Level fehlt \(name)") }
            var next = Sim()
            next.layout(field: CGRect(x: 26, y: 22, width: 980, height: 692))
            next.level = idx
            next.buildLevel()
            next.phase = .playing
            return next
        }
        func poke(_ sim: inout Sim, _ index: Int) {
            let before = sim.bricks[index].hp
            let brick = sim.bricks[index]
            sim.phase = .playing
            sim.balls = [Ball(
                x: brick.minX + brick.w * 0.5,
                y: brick.minY - sim.ballR - 0.4,
                vx: 0, vy: 420)]
            for _ in 0..<80 {
                sim.step(1 / 240)
                if sim.bricks[index].hp != before { break }
            }
        }

        var wall = stage("Mauer")
        let wallIndex = wall.bricks.firstIndex { $0.kind == .wall }!
        let wallHP = wall.bricks[wallIndex].hp
        poke(&wall, wallIndex)
        if wall.bricks[wallIndex].hp != wallHP { fail("Mauer ist gebrochen") }
        if wall.remaining == 0 || wall.bricks.contains(where: { $0.kind == .wall && !$0.counts }) == false {
            fail("Mauer zählt falsch")
        }
        if wall.remaining != wall.bricks.filter({ $0.counts && $0.hp > 0 }).count { fail("Mauer im Rest") }

        var energy = stage("Energie")
        let energyIndex = energy.bricks.firstIndex { $0.kind == .energy }!
        poke(&energy, energyIndex)
        if energy.bricks[energyIndex].hp != 1 { fail("Energie ohne Ball kaputt") }
        if !energy.bricks.contains(where: { $0.power == .through }) { fail("Energielevel ohne Energieball") }
        energy.throughTime = 5
        poke(&energy, energyIndex)
        if energy.bricks[energyIndex].hp != 0 { fail("Energieball wirkt nicht") }

        var armor = stage("Panzer")
        let armorIndex = armor.bricks.firstIndex { $0.kind == .tough }!
        poke(&armor, armorIndex)
        if armor.bricks[armorIndex].hp != 2 { fail("Panzer erster Treffer") }
        poke(&armor, armorIndex)
        if armor.bricks[armorIndex].hp != 1 { fail("Panzer zweiter Treffer") }
        poke(&armor, armorIndex)
        if armor.bricks[armorIndex].hp != 0 { fail("Panzer dritter Treffer") }

        var heal = stage("Heilung")
        let healIndex = heal.bricks.firstIndex { $0.kind == .heal }!
        heal.bricks[healIndex].hp = 1
        heal.bricks[healIndex].mend = 0.02
        heal.balls = [Ball(x: 80, y: 40, vx: 0, vy: 0, stuck: true)]
        heal.step(1 / 30)
        if heal.bricks[healIndex].hp != 2 { fail("Heilung kommt nicht zurück") }

        var bomb = stage("Zünder")
        let bombIndex = bomb.bricks.firstIndex { $0.kind == .tnt }!
        let bombCenter = bomb.bricks[bombIndex].center
        let beside = bomb.bricks.indices.first { i in
            i != bombIndex && bomb.bricks[i].kind == .plain
                && hypot(bomb.bricks[i].center.x - bombCenter.x, bomb.bricks[i].center.y - bombCenter.y) < 90
        }!
        poke(&bomb, bombIndex)
        if bomb.bricks[bombIndex].hp != 0 { fail("Zünder bleibt") }
        if bomb.bricks[beside].hp != 0 { fail("Zünder zündet den Nachbarn nicht") }

        var vine = stage("Ranke")
        let vineIndex = vine.bricks.firstIndex { $0.kind == .grow }!
        let seeds = vine.bricks.filter { $0.kind == .seed }.count
        if seeds == 0 { fail("Ranke ohne Lücken") }
        poke(&vine, vineIndex)
        if vine.bricks.filter({ $0.kind == .seed }).count >= seeds { fail("Ranke wächst nicht") }

        if authoredCount != 208 { fail("Satz hat \(authoredCount) Runden") }
        var pictures: Set<String> = []
        var names: Set<String> = []
        for index in 0..<authoredCount {
            let layout = layout(for: index)
            let width = layout.rows.first?.count ?? 0
            if width < 3 { fail("leeres Bild \(layout.name)") }
            for row in layout.rows where row.count != width { fail("ungleiche Zeile in \(layout.name)") }
            if layout.sink + layout.rows.count > 16 { fail("\(layout.name) sitzt im Schläger") }
            let picture = layout.rows.joined(separator: "/")
            if pictures.contains(picture) { fail("Runde \(index + 1) wiederholt ein Bild") }
            if names.contains(layout.name) { fail("Name doppelt: \(layout.name)") }
            pictures.insert(picture)
            names.insert(layout.name)
            if index >= 52 && layout.rows.contains(where: { $0.allSatisfy { $0 == "=" } }) {
                fail("Runde \(index + 1) ist versiegelt")
            }
        }
        func weight(_ index: Int) -> Int {
            let layout = layout(for: index)
            return layout.rows.count + layout.sink
        }
        let earlyWeight = (0..<52).reduce(0) { $0 + weight($1) }
        let lateWeight = (156..<208).reduce(0) { $0 + weight($1) }
        if lateWeight <= earlyWeight { fail("späte Runden werden nicht schwerer") }
        var finale = Sim()
        finale.phase = .serving
        finale.level = authoredCount - 1
        finale.cheatSkip()
        if !finale.campaignDone || finale.level != authoredCount - 1 { fail("der Satz läuft weiter") }

        var kid = Sim()
        kid.layout(field: CGRect(x: 26, y: 22, width: 980, height: 692))
        kid.rank = .kids
        kid.newGame()
        var hard = Sim()
        hard.layout(field: CGRect(x: 26, y: 22, width: 980, height: 692))
        hard.rank = .hard
        hard.newGame()
        if kid.lives != 7 || hard.lives != 2 { fail("Leben der Stufen") }
        if hard.speed <= kid.speed { fail("Schwer ist nicht schneller") }
        if kid.paddleW <= hard.paddleW { fail("Kinder-Schläger ist nicht breiter") }
        if kid.bricks.contains(where: { $0.power?.bad == true }) { fail("Kinder haben einen Malus") }
        let early = hard.speed
        for _ in 0..<12 { hard.cheatSkip() }
        if hard.speed <= early { fail("spätere Runde ist nicht schneller") }

        var clock = Sim()
        clock.layout(field: CGRect(x: 26, y: 22, width: 980, height: 692))
        clock.newGame()
        clock.cheat(.chaos)
        let once = clock.snapshot()?.chaos ?? 0
        if once < 9 || once > 11 { fail("Chaos dauert \(once)") }
        clock.cheat(.chaos)
        let twice = clock.snapshot()?.chaos ?? 0
        if twice < once + 8 { fail("gleiche Kapsel verlängert nicht") }
        clock.cheat(.slow)
        clock.cheat(.fast)
        if (clock.snapshot()?.tempo ?? 0) < 1.2 { fail("Schnell hebt Langsam nicht auf") }
        if (clock.snapshot()?.tempoTime ?? 99) > 22 { fail("Schnell übernimmt die langsame Uhr") }
        clock.cheat(.wide)
        let grown = clock.paddleW
        clock.phase = .playing
        clock.balls = [Ball(x: clock.paddle.x, y: clock.field.minY - 40, vx: 0, vy: -20)]
        clock.step(1 / 60)
        clock.step(0.7)
        if abs(clock.paddleW - grown) > 1 { fail("Breite geht beim Leben verloren") }

        var gate = Sim()
        gate.layout(field: CGRect(x: 26, y: 22, width: 980, height: 692))
        gate.newGame()
        gate.level = 3
        gate.phase = .serving
        gate.cheatSkip()
        if gate.bonus == nil || gate.level != 3 { fail("Bonusrunde fehlt") }
        let before = gate.bricks[0].minY
        gate.phase = .playing
        gate.balls = [Ball(x: gate.paddle.x, y: gate.paddle.y + 20, vx: 0, vy: -400)]
        gate.step(1 / 60)
        if gate.bricks[0].minY > before - 20 { fail("Barriere rückt nicht beim Schläger") }
        let parked = gate.bricks[0].minY
        gate.balls = [Ball(x: gate.paddle.x, y: gate.field.midY, vx: 0, vy: 0)]
        for _ in 0..<240 { gate.step(1 / 60) }
        if abs(gate.bricks[0].minY - parked) > 1 { fail("Barriere rückt von allein") }
        gate.cheatSkip()
        if gate.bonus != nil || gate.level != 4 { fail("nach der Bonusrunde kommt nicht die nächste Runde") }

        var joker = Sim()
        joker.layout(field: CGRect(x: 26, y: 22, width: 980, height: 692))
        joker.newGame()
        joker.phase = .playing
        joker.balls = [Ball(x: joker.field.midX, y: joker.field.midY, vx: 0, vy: 0)]
        joker.drops = [
            Drop(kind: .joker, x: joker.paddle.x, y: joker.paddle.y),
            Drop(kind: .wide, x: joker.paddle.x, y: joker.paddle.y),
        ]
        joker.step(1 / 60)
        if joker.drops.contains(where: { $0.kind == .joker }) { fail("Joker bleibt liegen") }

        var hall = Roster(lastID: nil, lastPlayedID: nil, players: [])
        hall.note(name: "Ada", score: 20, round: 2, rank: 2)
        hall.note(name: "Bea", score: 50, round: 4, rank: 2)
        if hall.board.first?.name != "Bea" || hall.board.count != 2 { fail("Bestenliste sortiert nicht") }

        print("self-test ok score=\(rallyScore) lives=\(rallyLives) round=\(rallyRound) powers=\(layouts.count) bilder=\(authoredCount)")
        exit(0)
    }
}
