import AppKit
import SwiftUI
import MetalKit
import UniformTypeIdentifiers

// 實驗室黑（承 iOS 版 2026-08-01 定案）：純黑底、髮絲線分層、等寬字標號＝儀器感。
// 深色 UI 不用陰影（排版標準第五節）。編輯器＝資訊密集場景，走髮絲線派。
enum Soft {
    static let base = Color(red: 0.043, green: 0.043, blue: 0.047)   // #0B0B0C
    static let card = Color(red: 0.086, green: 0.086, blue: 0.094)   // #161618
    static let ink = Color(red: 0.937, green: 0.937, blue: 0.945)
    static let ink2 = Color(red: 0.604, green: 0.604, blue: 0.627)
    static let faint = Color(red: 0.353, green: 0.353, blue: 0.376)
    static let hair = Color.white.opacity(0.14)
}

struct MetalCanvas: NSViewRepresentable {
    let renderer: WarpRenderer
    func makeNSView(context: Context) -> MTKView {
        let v = MTKView(frame: .zero, device: renderer.device)
        v.colorPixelFormat = .bgra8Unorm
        v.framebufferOnly = false
        v.preferredFramesPerSecond = 60
        v.delegate = renderer
        return v
    }
    func updateNSView(_ v: MTKView, context: Context) {}
}

struct ContentView: View {
    @StateObject private var r = WarpRenderer()
    @State private var fx = 0
    @State private var amount = 0.45
    @State private var radius = 0.18
    @State private var relax = 40.0
    @State private var waveScale = 0.375     // ＝×1.0（曲線 2^((v-0.375)×4)，上限 ×5.7）
    @State private var last: CGPoint?
    @State private var box = CGSize(width: 1, height: 1)
    @State private var status = ""
    @State private var wasPlaying = false
    @State private var strokeMoved = false

    /// 會往位移場寫筆刷的效果：液化 3-5＋桌面新家族 9-20
    private var paintable: Bool { (fx >= 3 && fx <= 5) || fx >= 9 }

    // 家族分組（索引＝shader mode）。0-8 承 iOS；9-20＝桌面新家族。
    // 2026-08-14 小高定調「全部要像拖曳絲流一樣互動」後，慢快門收成兩顆
    //（橫搖／直拖／前景保留是全域方向的預設，在筆刷範式下沒有存在意義；15/16 編號保留未用）
    private let groups: [(String, [Int])] = [
        ("鏡片", [0, 1, 2]), ("液化", [3, 4, 5]), ("場域", [6, 7, 8]),
        ("玻璃感・抹到哪長到哪", [9, 10, 11, 12]), ("慢快門・跟著筆跡竄", [13, 14, 15]),
        ("拖曳流動", [17, 18, 19, 20]),
    ]
    private let names = ["凸鏡", "黑洞", "放射拉扯", "向前推", "側推", "流體攪動", "噪聲蠕動", "自身位移", "水波鏡面",
                         "細條長虹", "寬條長虹", "水紋玻璃", "長虹色散",
                         "快門拖曳", "光軌拖曳", "移動高光", "－",
                         "漩渦絲綢", "拖曳絲流", "順紋流", "亂流大理石"]
    /// 顯示編號＝清單順位（mode 有跳號，直接印 mode+1 會斷）
    private var displayNo: [Int: Int] {
        var d: [Int: Int] = [:]
        for (i, m) in groups.flatMap(\.1).enumerated() { d[m] = i + 1 }
        return d
    }

    var body: some View {
        HStack(spacing: 0) {
            ZStack {
                Soft.base
                if r.imageSize == .zero { emptyState } else { canvas }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .bottom) { if r.isVideo { transport } }
            Rectangle().fill(Soft.hair).frame(width: 1)
            sidebar
        }
        .background(Soft.base)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in drop(providers) }
        .onAppear {
            r.onVideo = { saveVideo($0) }
            // 測試掛鉤：RHEO_OPEN=路徑 自動開檔；RHEO_TEST=1 再自動抹一筆；
            // RHEO_SAVE=png 存截圖；RHEO_SAVE_MOV=mp4 錄畫布——驗證整條管線不靠螢幕
            let env = ProcessInfo.processInfo.environment
            if let p = env["RHEO_OPEN"] { open(URL(fileURLWithPath: p)) }
            if let s = env["RHEO_FX"], let i = Int(s), i < names.count { fx = i; r.mode = i }
            if let w = env["RHEO_WAVE"], let v = Double(w) { waveScale = v; r.wave = Float(v) }
            if env["RHEO_TEST"] == "1" { autoStroke() }
        }
    }

    // MARK: 畫布（比例跟著照片走，整片都是塗抹區）

    private var canvas: some View {
        MetalCanvas(renderer: r)
            .aspectRatio(r.imageSize.width / max(r.imageSize.height, 1), contentMode: .fit)
            .background(GeometryReader { g in
                Color.clear
                    .onAppear { box = g.size }
                    .onChange(of: g.size) { _, v in box = v }
            })
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { v in
                    let p = CGPoint(x: min(max(v.location.x / box.width, 0), 1),
                                    y: min(max(v.location.y / box.height, 0), 1))
                    r.down = true
                    r.touch = SIMD2(Float(p.x), Float(p.y))
                    // ⌥ 按著＝反向清除（創作軟體的反向筆刷慣例鍵，不撞任何系統手勢）
                    let erasing = NSEvent.modifierFlags.contains(.option)
                    r.erasing = erasing
                    if paintable, let l = last {
                        if erasing { r.erase(at: p) }
                        else { r.stamp(from: l, to: p) } // 液化＋桌面全家族＝同一支筆刷
                        if hypot(p.x - l.x, p.y - l.y) > 0.0015 { strokeMoved = true }
                        r.stroking = strokeMoved
                    }
                    last = p
                }
                .onEnded { _ in
                    // 單點沒拖＝蓋一個圓點（⌥＝擦一個圓）。
                    // 筆長要拉滿 0.06 讓場強到遮罩飽和值——太弱會變成「看不出範圍在調」的小淡點；
                    // 圓的大小＝f_stamp 的高斯半徑 u.r＝範圍滑桿，跟抹的筆刷同一套
                    if paintable, !strokeMoved, let p = last {
                        if NSEvent.modifierFlags.contains(.option) { r.erase(at: p, strength: 0.9) }
                        else { r.stamp(from: CGPoint(x: p.x - 0.06, y: p.y), to: p) }
                    }
                    r.down = false; r.stroking = false; r.erasing = false; last = nil; strokeMoved = false
                })
            .padding(24)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Text("RHEO").font(.system(size: 13, weight: .bold, design: .monospaced))
                .tracking(6).foregroundStyle(Soft.faint)
            Text("把照片或影片拖進視窗，或 ⌘O 開啟").font(.system(size: 13)).foregroundStyle(Soft.ink2)
        }
    }

    // MARK: 傳輸列（浮在畫布下緣，只有影片模式出現）

    private var transport: some View {
        HStack(spacing: 10) {
            Button { r.togglePlay() } label: {
                Image(systemName: r.playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(Soft.ink)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.space, modifiers: [])
            Text(clock(r.currentTime))
                .font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(Soft.ink2)
            TimeSlider(time: r.currentTime, duration: r.duration,
                       onScrub: { r.seek(to: $0) },
                       onScrubState: { began in
                           if began { wasPlaying = r.playing; if r.playing { r.togglePlay() } }
                           else if wasPlaying, !r.playing { r.togglePlay() }
                       })
            Text(clock(r.duration))
                .font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(Soft.faint)
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .frame(maxWidth: 560)
        .background(RoundedRectangle(cornerRadius: 10).fill(Soft.card.opacity(0.92)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Soft.hair, lineWidth: 1))
        .padding(.horizontal, 24)
        .padding(.bottom, 14)
    }

    private func clock(_ s: Double) -> String {
        guard s.isFinite else { return "0:00.0" }
        return String(format: "%d:%04.1f", Int(s) / 60, s.truncatingRemainder(dividingBy: 60))
    }

    // MARK: 側欄

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 內容比視窗高時（小視窗）要能捲，不然 VStack 會上下都裁掉
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    section("效果")
                    ForEach(groups, id: \.0) { g in
                        Text(g.0).font(.system(size: 10, weight: .semibold)).tracking(2.4)
                            .foregroundStyle(Soft.faint).padding(.top, 8).padding(.bottom, 4)
                        ForEach(g.1, id: \.self) { i in effectRow(i) }
                    }
                    section("參數").padding(.top, 18)
                    VStack(spacing: 12) {
                        HairSlider(label: "強度", value: $amount, range: 0.05...1.5) { String(format: "%.2f", $0) }
                        HairSlider(label: "範圍", value: $radius, range: 0.04...0.45) { String(format: "%.2f", $0) }
                        HairSlider(label: "回彈", value: $relax, range: 0...100) {
                            $0 <= 0 ? "∞ 留痕" : String(format: "%.1fs", 30 * pow(0.005, ($0 - 1) / 99))
                        }
                        // 只影響波紋類（07 噪聲蠕動／09 水波鏡面／12 水紋玻璃）
                        HairSlider(label: "波長", value: $waveScale, range: 0...1) {
                            String(format: "%.2f×", pow(2, ($0 - 0.375) * 4))
                        }
                    }.padding(.top, 6)
                    section("動作").padding(.top, 18)
                    VStack(spacing: 6) {
                        actionRow("開啟檔案", key: "⌘O") { openPanel() }.keyboardShortcut("o", modifiers: .command)
                        actionRow("截圖存檔", key: "⌘S") { savePanel() }.keyboardShortcut("s", modifiers: .command)
                        recordRow
                        actionRow("清除痕跡", key: "⌘K") { r.clearField(); say("CLEARED") }
                            .keyboardShortcut("k", modifiers: .command)
                        peekRow
                        Text("⌥ 拖曳＝反向清除塗抹")
                            .font(.system(size: 10)).foregroundStyle(Soft.faint)
                            .padding(.top, 4).padding(.leading, 2)
                    }.padding(.top, 6)
                }
            }
            Spacer(minLength: 12)
            footer
        }
        .padding(16)
        .frame(width: 236)
        .background(Soft.base)
        .onChange(of: fx) { _, v in r.mode = v }
        .onChange(of: amount) { _, v in r.strength = Float(v) }
        .onChange(of: radius) { _, v in r.radius = Float(v) }
        .onChange(of: relax) { _, v in r.relax = Float(v) }
        .onChange(of: waveScale) { _, v in r.wave = Float(v) }
    }

    private func section(_ t: String) -> some View {
        Text(t).font(.system(size: 11, weight: .semibold)).tracking(2.6).foregroundStyle(Soft.ink2)
    }

    private func effectRow(_ i: Int) -> some View {
        HStack(spacing: 8) {
            Text(String(format: "%02d", displayNo[i] ?? i + 1))
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(fx == i ? Soft.ink : Soft.faint)
            Text(names[i]).font(.system(size: 12.5, weight: fx == i ? .semibold : .regular))
                .foregroundStyle(fx == i ? Soft.ink : Soft.ink2)
            Spacer()
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(RoundedRectangle(cornerRadius: 7).fill(fx == i ? Color.white.opacity(0.10) : .clear))
        .overlay(RoundedRectangle(cornerRadius: 7)
            .stroke(fx == i ? Color.white.opacity(0.35) : .clear, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 7))
        .onTapGesture { fx = i }
    }

    private func actionRow(_ t: String, key: String, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            HStack {
                Text(t).font(.system(size: 12.5)).foregroundStyle(Soft.ink)
                Spacer()
                Text(key).font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(Soft.faint)
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 7).fill(Soft.card))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Soft.hair, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
    }

    /// 錄製畫布：影片播放＋抹痕＋回彈，看到什麼錄什麼（檔案裡沒有介面）。
    /// 紅點是全介面唯一的彩色（儀器慣例，承 iOS）
    private var recordRow: some View {
        Button {
            guard r.imageSize != .zero else { return say("NO MEDIA") }
            r.toggleRecord()
            say(r.recording ? "REC" : "…")
        } label: {
            HStack(spacing: 8) {
                Circle().fill(Color(red: 0.90, green: 0.25, blue: 0.25))
                    .frame(width: 8, height: 8)
                    .opacity(r.recording ? 1 : 0.45)
                Text(r.recording ? "停止錄製" : "錄製畫布").font(.system(size: 12.5)).foregroundStyle(Soft.ink)
                Spacer()
                Text("⌘R").font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(Soft.faint)
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 7).fill(Soft.card))
            .overlay(RoundedRectangle(cornerRadius: 7)
                .stroke(r.recording ? Color(red: 0.90, green: 0.25, blue: 0.25).opacity(0.6) : Soft.hair, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .keyboardShortcut("r", modifiers: .command)
    }

    /// 按住看原圖（放開恢復）
    private var peekRow: some View {
        HStack {
            Text("按住看原圖").font(.system(size: 12.5)).foregroundStyle(r.peek ? Soft.base : Soft.ink)
            Spacer()
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(RoundedRectangle(cornerRadius: 7).fill(r.peek ? Soft.ink : Soft.card))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Soft.hair, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 7))
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { _ in r.peek = true; r.objectWillChange.send() }
            .onEnded { _ in r.peek = false; r.objectWillChange.send() })
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 3) {
            if r.imageSize != .zero {
                // 先組成 String 再給 Text：直接插值會走 LocalizedStringKey，Int 被套千分位（1,280）
                Text(String("\(r.imageName) · \(Int(r.imageSize.width))×\(Int(r.imageSize.height))"))
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(Soft.faint)
                    .lineLimit(1).truncationMode(.middle)
            }
            if !status.isEmpty {
                Text(status).font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(Soft.ink2)
            }
        }
    }

    // MARK: 檔案進出

    private func open(_ url: URL) {
        let type = UTType(filenameExtension: url.pathExtension.lowercased())
        if type?.conforms(to: .audiovisualContent) == true {
            Task { @MainActor in
                say(await r.loadVideo(url: url) ? "VIDEO LOADED" : "OPEN FAILED")
            }
        } else {
            say(r.load(url: url) ? "LOADED" : "OPEN FAILED")
        }
    }

    private func openPanel() {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.image, .movie]
        if p.runModal() == .OK, let url = p.url { open(url) }
    }

    /// 錄完的暫存檔 → 問存哪（測試模式直接落到 RHEO_SAVE_MOV）
    private func saveVideo(_ tmp: URL) {
        if let p = ProcessInfo.processInfo.environment["RHEO_SAVE_MOV"] {
            let dst = URL(fileURLWithPath: p)
            try? FileManager.default.removeItem(at: dst)
            try? FileManager.default.moveItem(at: tmp, to: dst)
            say("REC SAVED")
            return
        }
        let pnl = NSSavePanel()
        pnl.allowedContentTypes = [.mpeg4Movie]
        pnl.nameFieldStringValue = (r.imageName.isEmpty ? "RHEO" : r.imageName) + "-RHEO.mp4"
        if pnl.runModal() == .OK, let url = pnl.url {
            try? FileManager.default.removeItem(at: url)
            do { try FileManager.default.moveItem(at: tmp, to: url); say("REC SAVED") }
            catch { say("REC SAVE FAILED") }
        } else {
            try? FileManager.default.removeItem(at: tmp)   // 取消＝丟棄
            say("REC DISCARDED")
        }
    }

    private func savePanel() {
        guard r.imageSize != .zero else { return say("NO IMAGE") }
        let p = NSSavePanel()
        p.allowedContentTypes = [.png]
        p.nameFieldStringValue = (r.imageName.isEmpty ? "RHEO" : r.imageName) + "-RHEO.png"
        if p.runModal() == .OK, let url = p.url {
            say(r.savePNG(to: url) ? "SAVED \(r.W)×\(r.H)" : "SAVE FAILED")
        }
    }

    private func drop(_ providers: [NSItemProvider]) -> Bool {
        guard let p = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) })
        else { return false }
        p.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            var url: URL?
            if let d = item as? Data { url = URL(dataRepresentation: d, relativeTo: nil) }
            else if let u = item as? URL { url = u }
            if let url { DispatchQueue.main.async { open(url) } }
        }
        return true
    }

    private func say(_ s: String) { status = s }

    /// RHEO_TEST=1：載入後自動抹一筆 S 形（向前推）；RHEO_SAVE=路徑 再把結果存 PNG；
    /// RHEO_SAVE_MOV=路徑 全程錄畫布（筆劃前開錄、抹完再收 1 秒回彈才停）
    /// ＝不靠螢幕就能驗完「開檔→筆刷→回彈→全解析度輸出」整條管線
    private func autoStroke() {
        Task { @MainActor in
            let env = ProcessInfo.processInfo.environment
            try? await Task.sleep(for: .seconds(1.0))
            if env["RHEO_DAB"] == "1" {
                // 範圍滑桿驗證：模擬「按住」，小半徑按一顆、大半徑按一顆（回彈關掉讓兩顆都留住）
                relax = 0; r.relax = 0
                radius = 0.06; r.radius = 0.06
                r.touch = SIMD2(0.3, 0.5); r.down = true
                try? await Task.sleep(for: .milliseconds(800))
                r.down = false
                radius = 0.4; r.radius = 0.4
                r.touch = SIMD2(0.7, 0.5); r.down = true
                try? await Task.sleep(for: .milliseconds(800))
                r.down = false
                if let out = env["RHEO_SAVE"] { r.savePNG(to: URL(fileURLWithPath: out)) }
                return
            }
            if env["RHEO_FREEZE"] == "1" { relax = 0; r.relax = 0 }
            if env["RHEO_SAVE_MOV"] != nil { r.toggleRecord() }
            if env["RHEO_FX"] == nil { fx = 3; r.mode = 3 }   // 沒指定效果才用預設的向前推
            var prev = CGPoint(x: 0.2, y: 0.45)
            for i in 1...30 {
                let t = Double(i) / 30
                let p = CGPoint(x: 0.2 + 0.6 * t, y: 0.45 + 0.15 * sin(t * .pi * 2))
                r.stamp(from: prev, to: p)
                prev = p
                try? await Task.sleep(for: .milliseconds(33))
            }
            if env["RHEO_ERASE"] == "1" {                    // 反向清除驗證：擦掉筆劃中段
                relax = 0; r.relax = 0
                try? await Task.sleep(for: .milliseconds(300))
                for i in 0...12 {
                    let t = 0.3 + 0.4 * Double(i) / 12
                    r.erase(at: CGPoint(x: 0.2 + 0.6 * t, y: 0.45 + 0.15 * sin(t * .pi * 2)))
                    try? await Task.sleep(for: .milliseconds(20))
                }
            }
            if let out = env["RHEO_SAVE"] {
                try? await Task.sleep(for: .milliseconds(400))
                r.savePNG(to: URL(fileURLWithPath: out))
            }
            if let out2 = env["RHEO_SAVE2"] {             // 留痕靜止驗證：隔 2.5 秒再存一張比對
                try? await Task.sleep(for: .seconds(2.5))
                r.savePNG(to: URL(fileURLWithPath: out2))
            }
            if env["RHEO_SAVE_MOV"] != nil {
                try? await Task.sleep(for: .seconds(1.0))
                r.toggleRecord()
            }
        }
    }
}

/// 時間軸：拖曳＝直接 seek（絕對位置）。拖曳期間畫面吃本地值，不跟播放進度打架
struct TimeSlider: View {
    let time: Double
    let duration: Double
    let onScrub: (Double) -> Void
    let onScrubState: (Bool) -> Void
    @State private var dragging = false
    @State private var local = 0.0

    var body: some View {
        GeometryReader { g in
            let t = duration > 0 ? min(max((dragging ? local : time) / duration, 0), 1) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12)).frame(height: 3)
                Capsule().fill(Soft.ink).frame(width: max(2, g.size.width * t), height: 3)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { v in
                    if !dragging { dragging = true; onScrubState(true) }
                    let x = min(max(v.location.x / g.size.width, 0), 1)
                    local = x * duration
                    onScrub(local)
                }
                .onEnded { _ in dragging = false; onScrubState(false) })
        }
        .frame(height: 24)
    }
}

/// 髮絲線滑桿：4px 軌＋白填充＋圓點，拖曳＝軌上絕對位置（不是增量累加）
struct HairSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let display: (Double) -> String

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(label).font(.system(size: 11, weight: .semibold)).tracking(2.2)
                    .foregroundStyle(Soft.ink2)
                Spacer()
                Text(display(value)).font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(Soft.ink)
            }
            GeometryReader { g in
                let t = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12)).frame(height: 3)
                    Capsule().fill(Soft.ink).frame(width: max(3, g.size.width * t), height: 3)
                    Circle().fill(Soft.ink).frame(width: 11, height: 11)
                        .offset(x: (g.size.width - 11) * t)
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                    let t = min(max(v.location.x / g.size.width, 0), 1)
                    value = range.lowerBound + t * (range.upperBound - range.lowerBound)
                })
            }
            .frame(height: 18)
        }
    }
}
