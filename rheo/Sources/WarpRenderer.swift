import AppKit
import AVFoundation
import CoreImage
import MetalKit
import UniformTypeIdentifiers

/// 位移場引擎（桌面編輯器版）——與 iOS 版同一套公式，拿掉相機／方向系統，加上影片播放。
/// 兩個桌面版的差異：
/// 1. 畫布＝**來源解析度**（上限 4096）——編輯器輸出的是素材，絕不縮圖充數
/// 2. 位移場**獨立解析度**（長邊 1024）——互動成本不隨來源大小長；shader 全程正規化 uv，兩張貼圖不必同尺寸
final class WarpRenderer: NSObject, MTKViewDelegate, ObservableObject {
    struct Uniforms {
        var c = SIMD2<Float>(0.5, 0.5)
        var dir = SIMD2<Float>(0, 0)
        var px = SIMD2<Float>(1.0 / 768, 1.0 / 1024)
        var r: Float = 0.18
        var amt: Float = 0.45
        var k: Float = 0.30
        var decay: Float = 1
        var diff: Float = 0.22
        var wave: Float = 0.5                // 波長滑桿（順序必須跟 .metal 一致）
        var time: Float = 0
        var mode: Int32 = 0
        var peek: Int32 = 0
    }

    private(set) var W = 1024, H = 1024               // 畫布＝來源像素
    private var FW = 1024, FH = 1024                  // 位移場（長邊 1024，同比例）

    let device: MTLDevice
    private let queue: MTLCommandQueue
    private let ci: CIContext
    private let pStamp, pErase, pLens, pRelax, pDraw: MTLRenderPipelineState
    private var fieldA, fieldB: MTLTexture
    private var srcTex: MTLTexture

    // 外部狀態
    var mode = 0
    var strength: Float = 0.45
    var radius: Float = 0.18
    var relax: Float = 40
    var wave: Float = 0.375                   // 波長（噪聲蠕動／水波鏡面／水紋玻璃）；0.375＝×1.0
    var peek = false
    var down = false
    var stroking = false                      // 拖曳中（按住不動的持續寫點要讓路給筆劃）
    var erasing = false                       // ⌥ 按著＝反向清除模式
    var touch = SIMD2<Float>(0.5, 0.5)
    @Published var imageSize: CGSize = .zero          // .zero＝還沒開檔
    @Published var imageName = ""

    // 影片
    @Published var isVideo = false
    @Published var playing = false
    @Published var duration = 0.0
    @Published var currentTime = 0.0
    private var player: AVPlayer?
    private var videoOutput: AVPlayerItemVideoOutput?
    private var videoTransform = CGAffineTransform.identity
    private var loopObserver: NSObjectProtocol?
    private var timeObserver: Any?

    // 錄製畫布
    @Published var recording = false
    private var recorder: Recorder?
    var onVideo: ((URL) -> Void)?

    private var pending: [(from: SIMD2<Float>, to: SIMD2<Float>)] = []
    private var pendingErase: [(at: SIMD2<Float>, amt: Float)] = []
    private let t0 = CACurrentMediaTime()
    private var lastT = CACurrentMediaTime()

    override init() {
        let dev = MTLCreateSystemDefaultDevice()!
        device = dev
        queue = dev.makeCommandQueue()!
        ci = CIContext(mtlCommandQueue: queue,
                       options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB) as Any])
        let lib = dev.makeDefaultLibrary()!
        func make(_ fs: String) -> MTLRenderPipelineState {
            let d = MTLRenderPipelineDescriptor()
            d.vertexFunction = lib.makeFunction(name: "v_main")
            d.fragmentFunction = lib.makeFunction(name: fs)
            d.colorAttachments[0].pixelFormat = fs == "f_draw" ? .bgra8Unorm : .rgba16Float
            return try! dev.makeRenderPipelineState(descriptor: d)
        }
        pStamp = make("f_stamp"); pErase = make("f_erase"); pLens = make("f_lens")
        pRelax = make("f_relax"); pDraw = make("f_draw")
        fieldA = Self.tex(dev, .rgba16Float, [.shaderRead, .renderTarget], 1024, 1024)
        fieldB = Self.tex(dev, .rgba16Float, [.shaderRead, .renderTarget], 1024, 1024)
        srcTex = Self.tex(dev, .bgra8Unorm, [.shaderRead, .shaderWrite, .renderTarget], 1024, 1024)
        super.init()
        clearField()
    }

    private static func tex(_ dev: MTLDevice, _ fmt: MTLPixelFormat, _ usage: MTLTextureUsage,
                            _ w: Int, _ h: Int) -> MTLTexture {
        let d = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: fmt, width: w, height: h, mipmapped: false)
        d.usage = usage
        d.storageMode = .private
        return dev.makeTexture(descriptor: d)!
    }

    /// 畫布與位移場一起重建。
    /// .shaderWrite 不能省：CIContext.render 用 compute shader 寫貼圖，少了它就靜默不寫＝整片洋紅
    private func rebuildTextures(w: Int, h: Int) {
        W = w; H = h
        if W >= H { FW = 1024; FH = max(16, Int((1024.0 * Double(H) / Double(W)).rounded())) }
        else      { FH = 1024; FW = max(16, Int((1024.0 * Double(W) / Double(H)).rounded())) }
        fieldA = Self.tex(device, .rgba16Float, [.shaderRead, .renderTarget], FW, FH)
        fieldB = Self.tex(device, .rgba16Float, [.shaderRead, .renderTarget], FW, FH)
        srcTex = Self.tex(device, .bgra8Unorm, [.shaderRead, .shaderWrite, .renderTarget], W, H)
        clearField()
    }

    /// CI 影像 → srcTex。CIContext.render 用左下原點寫貼圖，本引擎全套 uv 是左上原點
    /// → 先沿 y 翻（同 iOS 版教訓）。進來的影像原點須已歸零。
    private func renderToSrc(_ img: CIImage, cb: MTLCommandBuffer) {
        var input = img
        let e = input.extent
        if abs(e.width - CGFloat(W)) > 0.5 || abs(e.height - CGFloat(H)) > 0.5 {
            input = input.transformed(by: .init(scaleX: CGFloat(W) / e.width, y: CGFloat(H) / e.height))
        }
        input = input.transformed(by: CGAffineTransform(scaleX: 1, y: -1)
            .concatenating(.init(translationX: 0, y: CGFloat(H))))
        let bounds = CGRect(x: 0, y: 0, width: W, height: H)
        ci.render(input.cropped(to: bounds), to: srcTex, commandBuffer: cb,
                  bounds: bounds, colorSpace: CGColorSpaceCreateDeviceRGB())
    }

    // MARK: 開檔——照片

    /// CGImageSource 縮圖 API 一次做完「烘進 EXIF 方向＋上限 4096」
    @discardableResult
    func load(url: URL) -> Bool {
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 4096,
        ]
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return false }
        unloadVideo()
        rebuildTextures(w: cg.width, h: cg.height)
        if let cb = queue.makeCommandBuffer() {
            renderToSrc(CIImage(cgImage: cg), cb: cb)
            cb.commit()
        }
        imageSize = CGSize(width: cg.width, height: cg.height)
        imageName = url.deletingPathExtension().lastPathComponent
        return true
    }

    // MARK: 開檔——影片

    @MainActor
    func loadVideo(url: URL) async -> Bool {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let (size, xf) = try? await track.load(.naturalSize, .preferredTransform),
              let dur = try? await asset.load(.duration) else { return false }
        unloadVideo()

        // preferredTransform（手機直拍的旋轉標籤）套上去才是「看起來」的尺寸
        let shown = CGRect(origin: .zero, size: size).applying(xf)
        let cap = 4096.0
        let s = min(1.0, cap / Double(max(shown.width, shown.height)))
        rebuildTextures(w: max(16, Int((abs(shown.width) * s).rounded())),
                        h: max(16, Int((abs(shown.height) * s).rounded())))
        videoTransform = xf

        let item = AVPlayerItem(asset: asset)
        let out = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        item.add(out)
        videoOutput = out
        let pl = AVPlayer(playerItem: item)
        player = pl
        loopObserver = NotificationCenter.default.addObserver(       // 循環播放：素材是看反覆的
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            guard let self, let pl = self.player else { return }
            pl.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
            if self.playing { pl.play() }
        }
        timeObserver = pl.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 30), queue: .main) { [weak self] t in
            self?.currentTime = t.seconds
        }

        duration = dur.seconds
        currentTime = 0
        isVideo = true
        imageSize = CGSize(width: W, height: H)
        imageName = url.deletingPathExtension().lastPathComponent
        pl.play()
        playing = true
        return true
    }

    private func unloadVideo() {
        if recording { toggleRecord() }
        if let o = loopObserver { NotificationCenter.default.removeObserver(o); loopObserver = nil }
        if let t = timeObserver { player?.removeTimeObserver(t); timeObserver = nil }
        player?.pause()
        player = nil
        videoOutput = nil
        isVideo = false
        playing = false
        duration = 0
        currentTime = 0
    }

    func togglePlay() {
        guard let pl = player else { return }
        playing ? pl.pause() : pl.play()
        playing.toggle()
    }

    func seek(to sec: Double) {
        player?.seek(to: CMTime(seconds: sec, preferredTimescale: 600),
                     toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = sec
    }

    /// 影片有新幀就送進 srcTex；暫停時沒新幀＝srcTex 凍在當下（抹的痕跡照樣流動）
    private func updateVideoFrame(cb: MTLCommandBuffer) {
        guard let out = videoOutput else { return }
        let t = out.itemTime(forHostTime: CACurrentMediaTime())
        guard out.hasNewPixelBuffer(forItemTime: t),
              let pb = out.copyPixelBuffer(forItemTime: t, itemTimeForDisplay: nil) else { return }
        var img = CIImage(cvPixelBuffer: pb).transformed(by: videoTransform)
        img = img.transformed(by: .init(translationX: -img.extent.minX, y: -img.extent.minY))
        renderToSrc(img, cb: cb)
    }

    // MARK: 錄製畫布

    func toggleRecord() {
        if let r = recorder {
            recorder = nil
            r.finish { [weak self] url in
                DispatchQueue.main.async {
                    if let url { self?.onVideo?(url) }
                    self?.recording = false
                }
            }
        } else {
            recorder = Recorder(device: device, w: W, h: H)
            recording = recorder != nil
        }
    }

    // MARK: 筆刷與輸出

    func stamp(from: CGPoint, to: CGPoint) {
        pending.append((SIMD2(Float(from.x), Float(from.y)), SIMD2(Float(to.x), Float(to.y))))
    }

    /// 反向清除一筆（⌥ 拖曳）；半徑吃範圍滑桿，同一支筆刷
    func erase(at p: CGPoint, strength: Float = 0.35) {
        pendingErase.append((SIMD2(Float(p.x), Float(p.y)), strength))
    }

    func clearField() {
        guard let cb = queue.makeCommandBuffer() else { return }
        for t in [fieldA, fieldB] {
            let rp = MTLRenderPassDescriptor()
            rp.colorAttachments[0].texture = t
            rp.colorAttachments[0].loadAction = .clear
            rp.colorAttachments[0].storeAction = .store
            rp.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
            cb.makeRenderCommandEncoder(descriptor: rp)?.endEncoding()
        }
        cb.commit()
    }

    /// 截圖＝以來源解析度重畫這一幀（影片模式＝當下那一格，含扭曲）
    @discardableResult
    func savePNG(to url: URL) -> Bool {
        guard let out = snapshotTexture(), let cg = cgImage(from: out),
              let dst = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { return false }
        CGImageDestinationAddImage(dst, cg, nil)
        return CGImageDestinationFinalize(dst)
    }

    // MARK: 內部

    private func uniforms() -> Uniforms {
        var u = Uniforms()
        u.c = touch
        u.r = radius
        u.amt = strength
        u.wave = wave
        u.mode = Int32(mode)
        u.peek = peek ? 1 : 0
        u.time = Float(CACurrentMediaTime() - t0)
        return u
    }

    private func pass(_ p: MTLRenderPipelineState, u: Uniforms, cb: MTLCommandBuffer) {
        var uu = u
        let rp = MTLRenderPassDescriptor()
        rp.colorAttachments[0].texture = fieldB
        rp.colorAttachments[0].loadAction = .dontCare
        rp.colorAttachments[0].storeAction = .store
        guard let e = cb.makeRenderCommandEncoder(descriptor: rp) else { return }
        e.setRenderPipelineState(p)
        e.setFragmentTexture(fieldA, index: 0)
        e.setFragmentBytes(&uu, length: MemoryLayout<Uniforms>.stride, index: 0)
        e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        e.endEncoding()
        swap(&fieldA, &fieldB)
    }

    private func encodeDraw(into dst: MTLTexture, cb: MTLCommandBuffer) {
        var u = uniforms()
        let rp = MTLRenderPassDescriptor()
        rp.colorAttachments[0].texture = dst
        rp.colorAttachments[0].loadAction = .clear
        rp.colorAttachments[0].storeAction = .store
        guard let e = cb.makeRenderCommandEncoder(descriptor: rp) else { return }
        e.setRenderPipelineState(pDraw)
        e.setFragmentTexture(srcTex, index: 0)
        e.setFragmentTexture(fieldA, index: 1)
        e.setFragmentBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 0)
        e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        e.endEncoding()
    }

    private func snapshotTexture() -> MTLTexture? {
        let d = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: W, height: H, mipmapped: false)
        d.usage = [.renderTarget, .shaderRead]
        d.storageMode = .shared
        guard let out = device.makeTexture(descriptor: d), let cb = queue.makeCommandBuffer() else { return nil }
        encodeDraw(into: out, cb: cb)
        cb.commit(); cb.waitUntilCompleted()
        return out
    }

    private func cgImage(from t: MTLTexture) -> CGImage? {
        let w = t.width, h = t.height
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        t.getBytes(&bytes, bytesPerRow: w * 4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        let info: CGBitmapInfo = [.byteOrder32Little,
                                  CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue)]
        guard let ctx = CGContext(data: &bytes, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: info.rawValue) else { return nil }
        return ctx.makeImage()
    }

    func draw(in view: MTKView) {
        guard imageSize != .zero, let cb = queue.makeCommandBuffer() else { return }
        let now = CACurrentMediaTime()
        let dt = Float(min(now - lastT, 0.05)); lastT = now

        updateVideoFrame(cb: cb)                        // ⓪ 影片新幀（照片模式無事）

        if down, !stroking, erasing {                   // ⓪ 按住不動＋⌥＝持續擦
            var u = uniforms()
            u.amt = min(3.0 * dt, 0.5)
            pass(pErase, u: u, cb: cb)
        } else if down, !stroking, mode >= 9 {          // ⓪ 按住不動＝持續寫點：
            var u = uniforms()                          //    圓的半徑「即時」吃範圍滑桿（跟鏡片同直覺），
            u.dir = SIMD2(1, 0)                         //    按著調滑桿圓就跟著長；約 0.5 秒到遮罩飽和
            u.amt = 0.062 * strength * dt
            pass(pStamp, u: u, cb: cb)
        }

        for e in pendingErase {                         // ⓪′ 反向清除筆劃
            var u = uniforms()
            u.c = e.at
            u.amt = e.amt
            pass(pErase, u: u, cb: cb)
        }
        pendingErase.removeAll(keepingCapacity: true)

        for seg in pending {                            // ① 液化筆刷
            var d = seg.to - seg.from
            let L = length(d)
            if L < 1e-4 { continue }
            if mode == 4 { d = SIMD2(-d.y, d.x) }       // 側推＝切線轉 90°
            var u = uniforms()
            u.c = seg.to
            u.dir = d / L
            u.amt = min(L, 0.06) * strength * 0.9
            pass(pStamp, u: u, cb: cb)
        }
        pending.removeAll(keepingCapacity: true)

        if mode <= 2 && down {                          // ② 鏡片型
            var u = uniforms()
            u.r = radius * 1.6
            u.k = 0.30
            pass(pLens, u: u, cb: cb)
        }

        // ③ 回彈（9-20 全是筆刷畫進場；px 用位移場的像素尺寸）。
        // 留痕（回彈 0）＝整個 pass 跳過＝真正靜止——只停衰減不停擴散的話，
        // 痕跡會持續往外暈開（小高 2026-08-14 指正）。按著筆刷時例外保留擴散，
        // 不然流體攪動在留痕模式下會失去尾流感；放開＝完全凍結
        if mode <= 5 || mode >= 9, relax > 0 || down {
            var u = uniforms()
            let fluid = mode == 5
            u.decay = relax == 0 ? 1 : exp(-Float(log(2.0)) / halfLife * dt)
            u.diff = fluid ? 0.9 : 0.22
            let k: Float = fluid ? 1.7 : 1.0
            u.px = SIMD2(k / Float(FW), k / Float(FH))
            pass(pRelax, u: u, cb: cb)
        }

        if let d = view.currentDrawable {               // ④ 上畫面
            encodeDraw(into: d.texture, cb: cb)
            cb.present(d)
        }
        if let r = recorder {                           // ⑤ 錄製：同一幀再畫一份進 pixel buffer
            if let (tex, pb) = r.nextTexture() {
                encodeDraw(into: tex, cb: cb)
                cb.addCompletedHandler { _ in r.append(pb) }
            }
        }
        cb.commit()
    }

    /// 回彈半衰期（秒）：滑桿 1→30 秒、100→0.15 秒，指數映射；0＝不回彈
    var halfLife: Float {
        relax <= 0 ? .infinity : 30 * pow(0.005, (relax - 1) / 99)
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
}
