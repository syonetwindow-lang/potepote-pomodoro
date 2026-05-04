#!/usr/bin/env swift
// ぽてぽてポモドーロ — 50分作業 / 10分休憩
// ターン1: メガネなし、ターン2: メガネあり（交互）

import Cocoa
import AVFoundation

// ── パス解決 ──────────────────────────────────────────────────────────────────
// .app バンドル内の Resources を優先、なければバイナリ相対パスにフォールバック
let ASSETS: URL = {
    if let resourcePath = Bundle.main.resourcePath {
        let bundleRes = URL(fileURLWithPath: resourcePath)
        if FileManager.default.fileExists(atPath: bundleRes.appendingPathComponent("work_normal.png").path) {
            return bundleRes
        }
    }
    let bin = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
    return bin.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("assets/pomodoro")
}()

// ── ウィンドウサイズ ──────────────────────────────────────────────────────────
let WIN_W: CGFloat = 320
let WIN_H: CGFloat = 500

// ── カラー ────────────────────────────────────────────────────────────────────
extension NSColor {
    static let bg         = NSColor(red: 0.96, green: 0.95, blue: 0.92, alpha: 1.0)
    static let textMain   = NSColor(red: 0.25, green: 0.25, blue: 0.25, alpha: 1.0)
    static let textSub    = NSColor(red: 0.55, green: 0.55, blue: 0.55, alpha: 1.0)
    static let barWork    = NSColor(red: 0.55, green: 0.78, blue: 0.45, alpha: 1.0)
    static let barBreak   = NSColor(red: 0.60, green: 0.85, blue: 0.92, alpha: 1.0)
    static let btnGo      = NSColor(red: 0.40, green: 0.70, blue: 0.40, alpha: 1.0)
    static let btnPause   = NSColor(red: 0.85, green: 0.60, blue: 0.30, alpha: 1.0)
    static let btnGray    = NSColor(red: 0.70, green: 0.70, blue: 0.70, alpha: 1.0)
}

// ── 丸角ボタン ────────────────────────────────────────────────────────────────
class Btn: NSButton {
    var bg: NSColor = .btnGo { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        let p = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 12, yRadius: 12)
        bg.setFill(); p.fill()
        let s = NSMutableParagraphStyle(); s.alignment = .center
        let a: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.white, .paragraphStyle: s,
        ]
        let sz = (title as NSString).size(withAttributes: a)
        (title as NSString).draw(in: NSRect(
            x: (bounds.width - sz.width) / 2, y: (bounds.height - sz.height) / 2,
            width: sz.width, height: sz.height), withAttributes: a)
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
        self.minutes = initial
        super.init(frame: .zero)

        label.stringValue = title
        label.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        label.textColor = .textSub
        label.isBezeled = false; label.drawsBackground = false; label.isEditable = false

        valueLabel.stringValue = "\(initial)分"
        valueLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .bold)
        valueLabel.textColor = .textMain
        valueLabel.alignment = .center
        valueLabel.isBezeled = false; valueLabel.drawsBackground = false; valueLabel.isEditable = false

        stepper.minValue = Double(min)
        stepper.maxValue = Double(max)
        stepper.increment = 5
        stepper.integerValue = initial
        stepper.target = self
        stepper.action = #selector(stepped)

        addSubview(label); addSubview(valueLabel); addSubview(stepper)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        label.frame = NSRect(x: 0, y: 0, width: 70, height: bounds.height)
        valueLabel.frame = NSRect(x: 70, y: 0, width: 50, height: bounds.height)
        stepper.frame = NSRect(x: 125, y: 2, width: 20, height: bounds.height - 4)
    }

    @objc func stepped() {
        minutes = stepper.integerValue
        onChange?(minutes)
    }
}

// ── サウンドプレイヤー ────────────────────────────────────────────────────────
class SoundPlayer {
    private var footstepTimer: Timer?
    private var footstepCount = 0

    func playFootsteps(completion: @escaping () -> Void) {
        footstepCount = 0
        footstepTimer?.invalidate()
        // 5秒間、0.5秒間隔で「ぽて…ぽて…」と足音
        footstepTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] t in
            guard let self = self else { t.invalidate(); return }
            self.footstepCount += 1
            // Tink = 軽い足音っぽい音
            NSSound(named: "Tink")?.play()
            if self.footstepCount >= 10 { // 5秒 = 10回
                t.invalidate()
                completion()
            }
        }
    }

    func playAlarm() {
        // Hero = 明るい完了音
        NSSound(named: "Hero")?.play()
        // 少し間を空けてもう一度（気づきやすく）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            NSSound(named: "Glass")?.play()
        }
    }

    func stop() {
        footstepTimer?.invalidate()
        footstepTimer = nil
    }
}

// ── メインコントローラー ──────────────────────────────────────────────────────
class PomodoroController: NSObject {
    enum Phase { case work, breakTime }
    enum State { case stopped, running, paused }

    var workMinutes  = 50
    var breakMinutes = 10
    var phase: Phase = .work
    var state: State = .stopped
    var remaining: Int = 50 * 60
    var sessionCount = 0
    var currentTurn  = 1
    var timer: Timer?
    var countdownStarted = false  // 5秒前カウントダウン開始済みフラグ
    let sound = SoundPlayer()

    // 画像
    let imgWork1: NSImage?
    let imgWork2: NSImage?
    let imgBreak: NSImage?

    // UI部品
    let window: NSWindow
    let imageView    = NSImageView()
    let timerLabel   = NSTextField(labelWithString: "50:00")
    let phaseLabel   = NSTextField(labelWithString: "作業タイム")
    let sessionLabel = NSTextField(labelWithString: "")
    let startBtn     = Btn()
    let resetBtn     = Btn()
    let settingsBtn  = Btn()
    let progressTrack = NSView()
    let progressBar   = NSView()

    // 設定パネル
    var settingsPanel: NSPanel?
    var workSetting:  TimeSettingRow?
    var breakSetting: TimeSettingRow?

    override init() {
        imgWork1 = NSImage(contentsOf: ASSETS.appendingPathComponent("work_normal.png"))
        imgWork2 = NSImage(contentsOf: ASSETS.appendingPathComponent("work_glasses.png"))
        imgBreak = NSImage(contentsOf: ASSETS.appendingPathComponent("break_relax.png"))

        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        window = NSWindow(
            contentRect: NSRect(
                x: screen.maxX - WIN_W - 20,
                y: screen.maxY - WIN_H - 20,
                width: WIN_W, height: WIN_H),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered, defer: false)

        super.init()

        window.title = "ぽてぽてポモドーロ"
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        window.backgroundColor = .bg

        buildUI()
        refresh()
    }

    func buildUI() {
        guard let c = window.contentView else { return }

        // キャラ画像（背景なし、直接表示）
        let imgSize: CGFloat = 240
        imageView.frame = NSRect(x: (WIN_W - imgSize) / 2, y: WIN_H - imgSize - 16, width: imgSize, height: imgSize)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 16
        imageView.layer?.masksToBounds = true
        c.addSubview(imageView)

        // フェーズラベル
        phaseLabel.frame = NSRect(x: 0, y: WIN_H - imgSize - 42, width: WIN_W, height: 20)
        phaseLabel.alignment = .center
        phaseLabel.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        phaseLabel.textColor = .textMain
        phaseLabel.isBezeled = false; phaseLabel.drawsBackground = false; phaseLabel.isEditable = false
        c.addSubview(phaseLabel)

        // タイマー
        timerLabel.frame = NSRect(x: 0, y: WIN_H - imgSize - 90, width: WIN_W, height: 48)
        timerLabel.alignment = .center
        timerLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 48, weight: .bold)
        timerLabel.textColor = .textMain
        timerLabel.isBezeled = false; timerLabel.drawsBackground = false; timerLabel.isEditable = false
        c.addSubview(timerLabel)

        // プログレストラック
        let barY = WIN_H - imgSize - 104
        progressTrack.wantsLayer = true
        progressTrack.layer?.backgroundColor = NSColor(white: 0.88, alpha: 1.0).cgColor
        progressTrack.layer?.cornerRadius = 4
        progressTrack.frame = NSRect(x: 40, y: barY, width: WIN_W - 80, height: 8)
        c.addSubview(progressTrack)

        progressBar.wantsLayer = true
        progressBar.layer?.backgroundColor = NSColor.barWork.cgColor
        progressBar.layer?.cornerRadius = 4
        progressBar.frame = NSRect(x: 40, y: barY, width: 0, height: 8)
        c.addSubview(progressBar)

        // セッション数
        sessionLabel.frame = NSRect(x: 0, y: barY - 22, width: WIN_W, height: 18)
        sessionLabel.alignment = .center
        sessionLabel.font = NSFont.systemFont(ofSize: 12)
        sessionLabel.textColor = .textSub
        sessionLabel.isBezeled = false; sessionLabel.drawsBackground = false; sessionLabel.isEditable = false
        c.addSubview(sessionLabel)

        // ボタン（3つ横並び）
        let bw: CGFloat = 90
        let bh: CGFloat = 36
        let by: CGFloat = 16
        let totalW = bw * 3 + 12 * 2
        let startX = (WIN_W - totalW) / 2

        startBtn.frame = NSRect(x: startX, y: by, width: bw, height: bh)
        startBtn.title = "スタート"
        startBtn.bg = .btnGo
        startBtn.isBordered = false; startBtn.target = self; startBtn.action = #selector(toggleTimer)
        c.addSubview(startBtn)

        resetBtn.frame = NSRect(x: startX + bw + 12, y: by, width: bw, height: bh)
        resetBtn.title = "リセット"
        resetBtn.bg = .btnGray
        resetBtn.isBordered = false; resetBtn.target = self; resetBtn.action = #selector(resetTimer)
        c.addSubview(resetBtn)

        settingsBtn.frame = NSRect(x: startX + (bw + 12) * 2, y: by, width: bw, height: bh)
        settingsBtn.title = "設定"
        settingsBtn.bg = .btnGray
        settingsBtn.isBordered = false; settingsBtn.target = self; settingsBtn.action = #selector(openSettings)
        c.addSubview(settingsBtn)
    }

    // ── 設定パネル ────────────────────────────────────────────────────────────
    @objc func openSettings() {
        if let panel = settingsPanel {
            panel.makeKeyAndOrderFront(nil)
            return
        }

        let pw: CGFloat = 220
        let ph: CGFloat = 160
        let wf = window.frame
        let panel = NSPanel(
            contentRect: NSRect(x: wf.minX - pw - 8, y: wf.maxY - ph, width: pw, height: ph),
            styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: false)
        panel.title = "時間の設定"
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .bg
        panel.isReleasedWhenClosed = false

        guard let pc = panel.contentView else { return }

        let ws = TimeSettingRow(title: "作業", initial: workMinutes, min: 5, max: 120)
        ws.frame = NSRect(x: 20, y: 95, width: 180, height: 30)
        ws.onChange = { [weak self] val in
            self?.workMinutes = val
            if self?.state == .stopped && self?.phase == .work {
                self?.remaining = val * 60
                self?.refresh()
            }
        }
        pc.addSubview(ws)
        workSetting = ws

        let bs = TimeSettingRow(title: "休憩", initial: breakMinutes, min: 1, max: 30)
        bs.frame = NSRect(x: 20, y: 55, width: 180, height: 30)
        bs.onChange = { [weak self] val in
            self?.breakMinutes = val
            if self?.state == .stopped && self?.phase == .breakTime {
                self?.remaining = val * 60
                self?.refresh()
            }
        }
        pc.addSubview(bs)
        breakSetting = bs

        // 説明テキスト
        let hint = NSTextField(labelWithString: "5分刻みで調整できるよ")
        hint.frame = NSRect(x: 20, y: 18, width: 180, height: 18)
        hint.font = NSFont.systemFont(ofSize: 11)
        hint.textColor = .textSub
        hint.isBezeled = false; hint.drawsBackground = false; hint.isEditable = false
        pc.addSubview(hint)

        settingsPanel = panel
        panel.makeKeyAndOrderFront(nil)
    }

    // ── タイマー制御 ──────────────────────────────────────────────────────────
    @objc func toggleTimer() {
        switch state {
        case .stopped, .paused: startTimer()
        case .running: pauseTimer()
        }
    }

    func startTimer() {
        state = .running
        countdownStarted = false
        startBtn.title = "一時停止"; startBtn.bg = .btnPause; startBtn.needsDisplay = true
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in self?.tick() }
    }

    func pauseTimer() {
        state = .paused
        timer?.invalidate(); timer = nil
        sound.stop()
        startBtn.title = "再開"; startBtn.bg = .btnGo; startBtn.needsDisplay = true
    }

    @objc func resetTimer() {
        timer?.invalidate(); timer = nil
        sound.stop()
        state = .stopped; phase = .work
        remaining = workMinutes * 60
        countdownStarted = false
        startBtn.title = "スタート"; startBtn.bg = .btnGo; startBtn.needsDisplay = true
        refresh()
    }

    func tick() {
        remaining -= 1

        // 残り5秒で足音開始
        if remaining == 5 && !countdownStarted {
            countdownStarted = true
            sound.playFootsteps { [weak self] in
                // 足音完了（0秒到達）→ アラーム & フェーズ切り替え
                self?.sound.playAlarm()
            }
        }

        if remaining <= 0 {
            switchPhase()
        }
        refresh()
    }

    func switchPhase() {
        timer?.invalidate(); timer = nil

        let notification = NSUserNotification()

        switch phase {
        case .work:
            sessionCount += 1
            phase = .breakTime
            remaining = breakMinutes * 60
            notification.title = "おつかれさま"
            notification.informativeText = "\(breakMinutes)分の休憩タイムだよ"
        case .breakTime:
            currentTurn = (currentTurn == 1) ? 2 : 1
            phase = .work
            remaining = workMinutes * 60
            notification.title = "休憩おわり"
            notification.informativeText = "次の作業タイム、がんばろう"
        }

        NSUserNotificationCenter.default.deliver(notification)
        countdownStarted = false
        refresh()
        startTimer()
    }

    // ── 表示更新 ──────────────────────────────────────────────────────────────
    func refresh() {
        timerLabel.stringValue = String(format: "%02d:%02d", remaining / 60, remaining % 60)

        switch phase {
        case .work:
            phaseLabel.stringValue = "作業タイム"
            progressBar.layer?.backgroundColor = NSColor.barWork.cgColor
            imageView.image = (currentTurn == 1) ? imgWork1 : imgWork2
        case .breakTime:
            phaseLabel.stringValue = "休憩タイム"
            progressBar.layer?.backgroundColor = NSColor.barBreak.cgColor
            imageView.image = imgBreak
        }

        let total = (phase == .work) ? workMinutes * 60 : breakMinutes * 60
        let pct = CGFloat(total - remaining) / CGFloat(max(total, 1))
        progressBar.frame.size.width = max((WIN_W - 80) * pct, 0)

        let turn = (currentTurn == 1) ? "ターン1" : "ターン2"
        sessionLabel.stringValue = sessionCount > 0
            ? "\(turn)  |  \(sessionCount)セッション完了"
            : turn
    }

    func show() { window.makeKeyAndOrderFront(nil) }
}

// ── 起動 ──────────────────────────────────────────────────────────────────────
let app = NSApplication.shared
app.setActivationPolicy(.regular)

let lockPath = FileManager.default.temporaryDirectory.appendingPathComponent("potepote_pomodoro.lock")
let fd = open(lockPath.path, O_CREAT | O_RDWR, 0o600)
if fd == -1 || flock(fd, LOCK_EX | LOCK_NB) != 0 {
    let a = NSAlert(); a.messageText = "ぽてぽてポモドーロは既に起動中です"; a.runModal(); exit(0)
}

let ctrl = PomodoroController()
ctrl.show()
app.activate(ignoringOtherApps: true)
app.run()
