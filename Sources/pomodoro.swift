#!/usr/bin/env swift
// ぽてぽてポモドーロ — かわいいポモドーロタイマー

import Cocoa
import AVFoundation

// ── パス解決 ──────────────────────────────────────────────────────────────────
let ASSETS: URL = {
    // 1. .app バンドルの Resources を優先
    if let rp = Bundle.main.resourcePath {
        let u = URL(fileURLWithPath: rp)
        if FileManager.default.fileExists(atPath: u.appendingPathComponent("work_normal.png").path) { return u }
    }
    let bin = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
    // 2. 開発時: バイナリと同階層の Resources/
    let sibling = bin.deletingLastPathComponent().appendingPathComponent("Resources")
    if FileManager.default.fileExists(atPath: sibling.appendingPathComponent("work_normal.png").path) { return sibling }
    // 3. リポジトリルートからの相対 (../Resources/)
    return bin.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources")
}()

let WIN_W: CGFloat = 300
let WIN_H: CGFloat = 520

// ── まばたき設定（画像内での目の位置・左上原点で 0〜1 正規化）────────────────
// キャラの実際の目の位置に合うよう、left/right/size を微調整してください
struct EyeConfig {
    let left: CGPoint
    let right: CGPoint
    let size: CGSize   // 画像幅/高さに対する比率
    let color: NSColor // まぶた色（肌色）
}
let EYE_WORK_NORMAL = EyeConfig(
    left:  CGPoint(x: 0.40, y: 0.40),
    right: CGPoint(x: 0.60, y: 0.40),
    size:  CGSize(width: 0.075, height: 0.028),
    color: NSColor(red: 0.99, green: 0.88, blue: 0.78, alpha: 1.0)
)
let EYE_WORK_GLASSES = EyeConfig(
    left:  CGPoint(x: 0.40, y: 0.40),
    right: CGPoint(x: 0.60, y: 0.40),
    size:  CGSize(width: 0.070, height: 0.026),
    color: NSColor(red: 0.99, green: 0.88, blue: 0.78, alpha: 1.0)
)
let EYE_BREAK = EyeConfig(
    left:  CGPoint(x: 0.40, y: 0.43),
    right: CGPoint(x: 0.60, y: 0.43),
    size:  CGSize(width: 0.075, height: 0.025),
    color: NSColor(red: 0.99, green: 0.88, blue: 0.78, alpha: 1.0)
)

// ── パステルカラー ────────────────────────────────────────────────────────────
extension NSColor {
    static let cream       = NSColor(red: 1.00, green: 0.98, blue: 0.94, alpha: 1.0)
    static let cozy        = NSColor(red: 0.35, green: 0.30, blue: 0.28, alpha: 1.0)
    static let cozySub     = NSColor(red: 0.60, green: 0.55, blue: 0.50, alpha: 1.0)
    static let barGreen    = NSColor(red: 0.60, green: 0.82, blue: 0.55, alpha: 1.0)
    static let barBlue     = NSColor(red: 0.55, green: 0.80, blue: 0.92, alpha: 1.0)
    static let btnMint     = NSColor(red: 0.55, green: 0.80, blue: 0.65, alpha: 1.0)
    static let btnOrange   = NSColor(red: 0.92, green: 0.70, blue: 0.45, alpha: 1.0)
    static let btnLavender = NSColor(red: 0.75, green: 0.70, blue: 0.85, alpha: 1.0)
    static let btnPink     = NSColor(red: 0.90, green: 0.72, blue: 0.75, alpha: 1.0)
    static let softShadow  = NSColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.06)
    static let trackBg     = NSColor(red: 0.92, green: 0.90, blue: 0.86, alpha: 1.0)
}

// ── かわいい丸角ボタン ────────────────────────────────────────────────────────
class CuteBtn: NSButton {
    var bg: NSColor = .btnMint { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        let shadowRect = bounds.insetBy(dx: 2, dy: 0).offsetBy(dx: 0, dy: -2)
        NSBezierPath(roundedRect: shadowRect, xRadius: 14, yRadius: 14).fill(using: .softShadow)
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 14, yRadius: 14)
        bg.setFill(); path.fill()
        let s = NSMutableParagraphStyle(); s.alignment = .center
        let a: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .bold),
            .foregroundColor: NSColor.white, .paragraphStyle: s,
        ]
        let sz = (title as NSString).size(withAttributes: a)
        (title as NSString).draw(in: NSRect(
            x: (bounds.width - sz.width) / 2, y: (bounds.height - sz.height) / 2 + 1,
            width: sz.width, height: sz.height), withAttributes: a)
    }
}

extension NSBezierPath {
    func fill(using color: NSColor) { color.setFill(); fill() }
}

// ── 足跡プログレスバー ────────────────────────────────────────────────────────
class PawProgressView: NSView {
    var progress: CGFloat = 0.0 { didSet { needsDisplay = true } }
    var barColor: NSColor = .barGreen { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        // トラック背景
        let trackPath = NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2)
        NSColor.trackBg.setFill(); trackPath.fill()

        // 進捗バー
        let barW = max(bounds.height, bounds.width * progress)
        let barRect = NSRect(x: 0, y: 0, width: barW, height: bounds.height)
        let barPath = NSBezierPath(roundedRect: barRect, xRadius: bounds.height / 2, yRadius: bounds.height / 2)
        barColor.setFill(); barPath.fill()

        // 足跡を等間隔に描画（進捗範囲内のみ）
        let pawSpacing: CGFloat = 28
        let pawSize: CGFloat = 10
        var x: CGFloat = 14
        let midY = bounds.height / 2
        var stepIndex = 0

        while x < barW - 6 {
            let isLeft = (stepIndex % 2 == 0)
            let offsetY: CGFloat = isLeft ? 2.0 : -2.0
            drawPaw(at: NSPoint(x: x, y: midY + offsetY), size: pawSize)
            x += pawSpacing
            stepIndex += 1
        }

        // 先頭の足跡（少し大きく）
        if progress > 0.01 {
            let headX = min(barW - 8, bounds.width - 8)
            drawPaw(at: NSPoint(x: headX, y: midY), size: pawSize * 1.3)
        }
    }

    private func drawPaw(at center: NSPoint, size: CGFloat) {
        let alpha: CGFloat = 0.5
        let color = NSColor(white: 1.0, alpha: alpha)
        color.setFill()

        // メインパッド（楕円）
        let mainW = size * 0.7
        let mainH = size * 0.5
        let mainRect = NSRect(x: center.x - mainW / 2, y: center.y - mainH / 2 - size * 0.1,
                              width: mainW, height: mainH)
        NSBezierPath(ovalIn: mainRect).fill()

        // 3つの指パッド
        let toeSize = size * 0.25
        let toeY = center.y + mainH / 2 + toeSize * 0.2
        let positions: [CGFloat] = [-size * 0.28, 0, size * 0.28]
        for dx in positions {
            let toeRect = NSRect(x: center.x + dx - toeSize / 2, y: toeY,
                                 width: toeSize, height: toeSize)
            NSBezierPath(ovalIn: toeRect).fill()
        }
    }
}

// ── まばたきオーバーレイ ──────────────────────────────────────────────────────
class BlinkOverlay: NSView {
    var isBlinking: Bool = false { didSet { needsDisplay = true } }
    var config: EyeConfig? = nil { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        guard isBlinking, let cfg = config else { return }
        cfg.color.setFill()
        let w = cfg.size.width * bounds.width
        let h = cfg.size.height * bounds.height
        for ec in [cfg.left, cfg.right] {
            let cx = ec.x * bounds.width
            let cy = (1 - ec.y) * bounds.height
            NSBezierPath(ovalIn: NSRect(x: cx - w/2, y: cy - h/2, width: w, height: h)).fill()
        }
    }
}

// ── 呼吸＋まばたきアニメーター ────────────────────────────────────────────────
class CharacterAnimator {
    weak var imageView: NSImageView?
    weak var blinkOverlay: BlinkOverlay?
    private var breathTimer: Timer?
    private var blinkTimer: Timer?
    private var phaseT: TimeInterval = 0
    private let period: TimeInterval = 3.2
    private let amp: CGFloat = 4.0
    private var base: NSRect = .zero

    func start(baseFrame: NSRect) {
        base = baseFrame
        imageView?.frame = base
        blinkOverlay?.frame = base
        breathTimer?.invalidate()
        breathTimer = Timer.scheduledTimer(withTimeInterval: 1.0/30.0, repeats: true) { [weak self] _ in
            self?.tickBreath()
        }
        scheduleBlink()
    }
    func stop() {
        breathTimer?.invalidate(); breathTimer = nil
        blinkTimer?.invalidate(); blinkTimer = nil
        blinkOverlay?.isBlinking = false
    }
    private func tickBreath() {
        phaseT += 1.0/30.0
        let dy = sin(phaseT * .pi * 2 / period) * amp
        var f = base
        f.origin.y += dy
        imageView?.frame = f
        blinkOverlay?.frame = f
    }
    private func scheduleBlink() {
        blinkTimer?.invalidate()
        let next = TimeInterval.random(in: 3.0...5.5)
        blinkTimer = Timer.scheduledTimer(withTimeInterval: next, repeats: false) { [weak self] _ in
            self?.fireBlink()
        }
    }
    private func fireBlink() {
        blinkOverlay?.isBlinking = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.13) { [weak self] in
            self?.blinkOverlay?.isBlinking = false
            // たまに二回まばたき
            if Bool.random() && Int.random(in: 0..<4) == 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.13) { [weak self] in
                    self?.blinkOverlay?.isBlinking = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.11) { [weak self] in
                        self?.blinkOverlay?.isBlinking = false
                        self?.scheduleBlink()
                    }
                }
            } else {
                self?.scheduleBlink()
            }
        }
    }
}

// ── ステッパー付き時間設定 ────────────────────────────────────────────────────
class TimeSettingRow: NSView {
    let label = NSTextField(labelWithString: "")
    let valueLabel = NSTextField(labelWithString: "")
    let stepper = NSStepper()
    var minutes: Int { didSet { valueLabel.stringValue = "\(minutes)分"; stepper.integerValue = minutes } }
    var onChange: ((Int) -> Void)?
    init(title: String, initial: Int, min: Int, max: Int) {
        self.minutes = initial; super.init(frame: .zero)
        label.stringValue = title
        label.font = NSFont.systemFont(ofSize: 13, weight: .medium); label.textColor = .cozy
        label.isBezeled = false; label.drawsBackground = false; label.isEditable = false
        valueLabel.stringValue = "\(initial)分"
        valueLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 15, weight: .bold)
        valueLabel.textColor = .cozy; valueLabel.alignment = .center
        valueLabel.isBezeled = false; valueLabel.drawsBackground = false; valueLabel.isEditable = false
        stepper.minValue = Double(min); stepper.maxValue = Double(max)
        stepper.increment = 5; stepper.integerValue = initial
        stepper.target = self; stepper.action = #selector(stepped)
        addSubview(label); addSubview(valueLabel); addSubview(stepper)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() {
        super.layout()
        label.frame = NSRect(x: 0, y: 0, width: 70, height: bounds.height)
        valueLabel.frame = NSRect(x: 70, y: 0, width: 50, height: bounds.height)
        stepper.frame = NSRect(x: 130, y: 2, width: 20, height: bounds.height - 4)
    }
    @objc func stepped() { minutes = stepper.integerValue; onChange?(minutes) }
}

// ── サウンド ──────────────────────────────────────────────────────────────────
class SoundPlayer {
    private var footTimer: Timer?
    private var footCount = 0
    func playFootsteps(completion: @escaping () -> Void) {
        footCount = 0; footTimer?.invalidate()
        footTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] t in
            guard let s = self else { t.invalidate(); return }
            s.footCount += 1; NSSound(named: "Tink")?.play()
            if s.footCount >= 10 { t.invalidate(); completion() }
        }
    }
    func playAlarm() {
        NSSound(named: "Hero")?.play()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { NSSound(named: "Glass")?.play() }
    }
    func stop() { footTimer?.invalidate(); footTimer = nil }
}

// ── メインコントローラー ──────────────────────────────────────────────────────
class PomodoroController: NSObject {
    enum Phase { case work, breakTime }
    enum State { case stopped, running, paused }

    var workMin = 50, breakMin = 10
    var phase: Phase = .work
    var state: State = .stopped
    var remaining: Int = 50 * 60
    var sessions = 0, turn = 1
    var timer: Timer?
    var countdownStarted = false
    let sound = SoundPlayer()

    let imgWork1: NSImage?
    let imgWork2: NSImage?
    let imgBreak: NSImage?

    let window: NSWindow
    let imageView    = NSImageView()
    let blinkOverlay = BlinkOverlay()
    let animator     = CharacterAnimator()
    let phaseLabel   = NSTextField(labelWithString: "")
    let timerLabel   = NSTextField(labelWithString: "50:00")
    let sessionLabel = NSTextField(labelWithString: "")
    let pawProgress  = PawProgressView()
    let startBtn     = CuteBtn()
    let resetBtn     = CuteBtn()
    let settingsBtn  = CuteBtn()

    var settingsPanel: NSPanel?

    override init() {
        imgWork1 = NSImage(contentsOf: ASSETS.appendingPathComponent("work_normal.png"))
        imgWork2 = NSImage(contentsOf: ASSETS.appendingPathComponent("work_glasses.png"))
        imgBreak = NSImage(contentsOf: ASSETS.appendingPathComponent("break_relax.png"))

        let scr = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        window = NSWindow(
            contentRect: NSRect(x: scr.maxX - WIN_W - 24, y: scr.maxY - WIN_H - 24, width: WIN_W, height: WIN_H),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered, defer: false)
        super.init()

        window.title = "ぽてぽてポモドーロ"
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        window.backgroundColor = .cream
        buildUI(); refresh()
    }

    func buildUI() {
        guard let c = window.contentView else { return }

        // キャラ画像（背景なし、ウィンドウ幅いっぱい）
        let imgW: CGFloat = WIN_W - 32
        let imgH: CGFloat = 260
        let imgFrame = NSRect(x: 16, y: WIN_H - imgH - 12, width: imgW, height: imgH)
        imageView.frame = imgFrame
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 16
        imageView.layer?.masksToBounds = true
        c.addSubview(imageView)

        // 瞬きオーバーレイ（imageViewの上に重ねる）
        blinkOverlay.frame = imgFrame
        c.addSubview(blinkOverlay)

        // 呼吸＋瞬き 開始
        animator.imageView = imageView
        animator.blinkOverlay = blinkOverlay
        animator.start(baseFrame: imgFrame)

        // フェーズラベル
        let baseY = WIN_H - imgH - 12  // 画像の下端
        phaseLabel.frame = NSRect(x: 0, y: baseY - 30, width: WIN_W, height: 24)
        phaseLabel.alignment = .center
        phaseLabel.font = NSFont.systemFont(ofSize: 15, weight: .medium)
        phaseLabel.textColor = .cozy
        phaseLabel.isBezeled = false; phaseLabel.drawsBackground = false; phaseLabel.isEditable = false
        c.addSubview(phaseLabel)

        // タイマー（下寄り配置）
        timerLabel.frame = NSRect(x: 0, y: baseY - 86, width: WIN_W, height: 56)
        timerLabel.alignment = .center
        timerLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 52, weight: .heavy)
        timerLabel.textColor = .cozy
        timerLabel.isBezeled = false; timerLabel.drawsBackground = false; timerLabel.isEditable = false
        c.addSubview(timerLabel)

        // 足跡プログレスバー
        let barY = baseY - 106
        pawProgress.frame = NSRect(x: 24, y: barY, width: WIN_W - 48, height: 14)
        c.addSubview(pawProgress)

        // セッション表示（大きめ）
        sessionLabel.frame = NSRect(x: 0, y: barY - 28, width: WIN_W, height: 22)
        sessionLabel.alignment = .center
        sessionLabel.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        sessionLabel.textColor = .cozySub
        sessionLabel.isBezeled = false; sessionLabel.drawsBackground = false; sessionLabel.isEditable = false
        c.addSubview(sessionLabel)

        // ボタン（大きめ文字）
        let bw: CGFloat = 82, bh: CGFloat = 40, by: CGFloat = 16
        let gap: CGFloat = 10
        let sx = (WIN_W - (bw * 3 + gap * 2)) / 2

        startBtn.frame = NSRect(x: sx, y: by, width: bw, height: bh)
        startBtn.title = "はじめ"; startBtn.bg = .btnMint
        startBtn.isBordered = false; startBtn.target = self; startBtn.action = #selector(toggleTimer)
        c.addSubview(startBtn)

        resetBtn.frame = NSRect(x: sx + bw + gap, y: by, width: bw, height: bh)
        resetBtn.title = "もどる"; resetBtn.bg = .btnPink
        resetBtn.isBordered = false; resetBtn.target = self; resetBtn.action = #selector(resetTimer)
        c.addSubview(resetBtn)

        settingsBtn.frame = NSRect(x: sx + (bw + gap) * 2, y: by, width: bw, height: bh)
        settingsBtn.title = "じかん"; settingsBtn.bg = .btnLavender
        settingsBtn.isBordered = false; settingsBtn.target = self; settingsBtn.action = #selector(openSettings)
        c.addSubview(settingsBtn)
    }

    // ── 設定パネル ────────────────────────────────────────────────────────────
    @objc func openSettings() {
        if let p = settingsPanel { p.makeKeyAndOrderFront(nil); return }
        let pw: CGFloat = 230, ph: CGFloat = 170
        let wf = window.frame
        let panel = NSPanel(
            contentRect: NSRect(x: wf.minX - pw - 8, y: wf.maxY - ph, width: pw, height: ph),
            styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: false)
        panel.title = "じかんのせってい"
        panel.isFloatingPanel = true; panel.level = .floating
        panel.backgroundColor = .cream; panel.isReleasedWhenClosed = false
        guard let pc = panel.contentView else { return }

        let ws = TimeSettingRow(title: "さぎょう", initial: workMin, min: 5, max: 120)
        ws.frame = NSRect(x: 24, y: 100, width: 180, height: 30)
        ws.onChange = { [weak self] v in
            self?.workMin = v
            if self?.state == .stopped && self?.phase == .work { self?.remaining = v * 60; self?.refresh() }
        }
        pc.addSubview(ws)

        let bs = TimeSettingRow(title: "きゅうけい", initial: breakMin, min: 1, max: 30)
        bs.frame = NSRect(x: 24, y: 60, width: 180, height: 30)
        bs.onChange = { [weak self] v in
            self?.breakMin = v
            if self?.state == .stopped && self?.phase == .breakTime { self?.remaining = v * 60; self?.refresh() }
        }
        pc.addSubview(bs)

        let hint = NSTextField(labelWithString: "5ふんきざみで ちょうせつできるよ")
        hint.frame = NSRect(x: 24, y: 22, width: 180, height: 18)
        hint.font = NSFont.systemFont(ofSize: 11); hint.textColor = .cozySub
        hint.isBezeled = false; hint.drawsBackground = false; hint.isEditable = false
        pc.addSubview(hint)

        settingsPanel = panel; panel.makeKeyAndOrderFront(nil)
    }

    // ── タイマー ──────────────────────────────────────────────────────────────
    @objc func toggleTimer() {
        switch state {
        case .stopped, .paused: startRun()
        case .running: pauseRun()
        }
    }

    func startRun() {
        state = .running; countdownStarted = false
        startBtn.title = "つづける"; startBtn.bg = .btnOrange; startBtn.needsDisplay = true
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in self?.tick() }
    }

    func pauseRun() {
        state = .paused; timer?.invalidate(); timer = nil; sound.stop()
        startBtn.title = "つづける"; startBtn.bg = .btnMint; startBtn.needsDisplay = true
    }

    @objc func resetTimer() {
        timer?.invalidate(); timer = nil; sound.stop()
        state = .stopped; phase = .work; remaining = workMin * 60; countdownStarted = false
        startBtn.title = "はじめ"; startBtn.bg = .btnMint; startBtn.needsDisplay = true
        refresh()
    }

    func tick() {
        remaining -= 1
        if remaining == 5 && !countdownStarted {
            countdownStarted = true
            sound.playFootsteps { [weak self] in self?.sound.playAlarm() }
        }
        if remaining <= 0 { switchPhase() }
        refresh()
    }

    func switchPhase() {
        timer?.invalidate(); timer = nil
        let n = NSUserNotification()
        switch phase {
        case .work:
            sessions += 1; phase = .breakTime; remaining = breakMin * 60
            n.title = "おつかれさま"; n.informativeText = "\(breakMin)ふんの きゅうけいタイムだよ"
        case .breakTime:
            turn = (turn == 1) ? 2 : 1; phase = .work; remaining = workMin * 60
            n.title = "きゅうけい おわり"; n.informativeText = "つぎの さぎょうタイム、がんばろう"
        }
        NSUserNotificationCenter.default.deliver(n)
        countdownStarted = false; refresh(); startRun()
    }

    // ── 表示更新 ──────────────────────────────────────────────────────────────
    func refresh() {
        timerLabel.stringValue = String(format: "%02d:%02d", remaining / 60, remaining % 60)

        switch phase {
        case .work:
            phaseLabel.stringValue = "さぎょうタイム"
            pawProgress.barColor = .barGreen
            imageView.image = (turn == 1) ? imgWork1 : imgWork2
            blinkOverlay.config = (turn == 1) ? EYE_WORK_NORMAL : EYE_WORK_GLASSES
        case .breakTime:
            phaseLabel.stringValue = "きゅうけいタイム"
            pawProgress.barColor = .barBlue
            imageView.image = imgBreak
            blinkOverlay.config = EYE_BREAK
        }

        let total = (phase == .work) ? workMin * 60 : breakMin * 60
        pawProgress.progress = CGFloat(total - remaining) / CGFloat(max(total, 1))

        let t = (turn == 1) ? "ターン1" : "ターン2"
        sessionLabel.stringValue = sessions > 0 ? "\(t)  |  \(sessions)かい がんばった" : t
    }

    func show() { window.makeKeyAndOrderFront(nil) }
}

// ── 起動 ──────────────────────────────────────────────────────────────────────
let app = NSApplication.shared
app.setActivationPolicy(.regular)
let lockPath = FileManager.default.temporaryDirectory.appendingPathComponent("potepote_pomodoro.lock")
let fd = open(lockPath.path, O_CREAT | O_RDWR, 0o600)
if fd == -1 || flock(fd, LOCK_EX | LOCK_NB) != 0 {
    let a = NSAlert(); a.messageText = "ぽてぽてポモドーロは もう うごいてるよ"; a.runModal(); exit(0)
}
let ctrl = PomodoroController()
ctrl.show()
app.activate(ignoringOtherApps: true)
app.run()
