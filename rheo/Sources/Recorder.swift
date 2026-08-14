import AVFoundation
import CoreVideo
import Metal

/// 把渲染好的畫布直接寫成 mp4（承 iOS 版）。
/// 走 pixel buffer pool → CVMetalTextureCache → Metal 直接畫進去＝零拷貝，
/// 錄的就是畫布那一幀（含影片、扭曲、回彈）——檔案裡沒有任何介面。
final class Recorder {
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private var cache: CVMetalTextureCache?
    private var started = false
    private(set) var frames = 0
    private var t0: CFTimeInterval = 0
    let url: URL

    init?(device: MTLDevice, w: Int, h: Int) {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("rheo-\(Int(Date().timeIntervalSince1970)).mp4")
        guard let wr = try? AVAssetWriter(outputURL: url, fileType: .mp4) else { return nil }
        writer = wr
        // 位元率跟像素數走（iOS 實測 1200×1600@60 要 30 Mbps 才不出色塊＝每像素每幀 0.26 bit），
        // 桌面畫布上看 4K，照同密度換算、天花板 120 Mbps
        let bps = min(120_000_000, max(20_000_000, Int(Double(w * h) * 0.26 * 60)))
        input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: w, AVVideoHeightKey: h,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: bps],
        ])
        input.expectsMediaDataInRealTime = true
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: w,
                kCVPixelBufferHeightKey as String: h,
                kCVPixelBufferMetalCompatibilityKey as String: true,
            ])
        guard writer.canAdd(input) else { return nil }
        writer.add(input)
        CVMetalTextureCacheCreate(nil, nil, device, nil, &cache)
    }

    /// 取一顆可以直接被 Metal 畫的 pixel buffer
    func nextTexture() -> (MTLTexture, CVPixelBuffer)? {
        if !started {
            guard writer.startWriting() else { return nil }
            writer.startSession(atSourceTime: .zero)
            t0 = CACurrentMediaTime()
            started = true
        }
        guard input.isReadyForMoreMediaData, let pool = adaptor.pixelBufferPool, let cache else { return nil }
        var pb: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pb) == kCVReturnSuccess, let pb else { return nil }
        var ref: CVMetalTexture?
        CVMetalTextureCacheCreateTextureFromImage(nil, cache, pb, nil, .bgra8Unorm,
                                                  CVPixelBufferGetWidth(pb), CVPixelBufferGetHeight(pb), 0, &ref)
        guard let ref, let tex = CVMetalTextureGetTexture(ref) else { return nil }
        return (tex, pb)
    }

    func append(_ pb: CVPixelBuffer) {
        guard input.isReadyForMoreMediaData else { return }
        let t = CMTime(seconds: CACurrentMediaTime() - t0, preferredTimescale: 600)
        if adaptor.append(pb, withPresentationTime: t) { frames += 1 }
    }

    func finish(_ done: @escaping (URL?) -> Void) {
        guard started else { return done(nil) }
        input.markAsFinished()
        // 強捕獲 self：呼叫端在 finish 前就把強引用放掉了（recorder = nil），
        // 弱引用會讓 Recorder 在收尾完成前被釋放＝檔案寫好也被扔掉（iOS 版「影片從沒出來過」的真兇）
        writer.finishWriting {
            done(self.writer.status == .completed ? self.url : nil)
        }
    }
}
