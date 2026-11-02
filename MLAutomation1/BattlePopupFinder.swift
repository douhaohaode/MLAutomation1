//
//  BattlePopupFinder.swift
//  MLAutomation
//
//  战斗选人弹框。模型来自 https://github.com/BestBurning/mhxy 的 model/mhxy.h5，
//  已转成 Core ML（MHXYFront）。网络是二分类、输出 logit：
//  训练目录按字母序 front=0、others=1，数值越小越像正面。
//  四个头像各跑一次，点 logit 最小的那一个，和原仓库 model_predict 一样。
//

import Foundation
import AppKit
import CoreML
import CoreVideo
import Vision

struct BattlePortraitHit {
    /// 0...3，从左到右
    let index: Int
    /// 相对整张截图的归一化中心，配合 clickAtOCR 使用
    let center: CGPoint
    let logit: Double
    let logits: [Double]
}

final class BattlePopupFinder {

    /// 原仓库截图宽。把当前窗口缩到这个宽度后再做模板匹配，偏移量才和 constant.py 一致。
    private static let referenceWidth = 812

    /// 人物条在参考分辨率下是 360×120，从左到右四等分。
    private static let stripWidth = 360
    private static let stripHeight = 120

    /// 模板框 (x, y, x+w, y+h) 再加上这组偏移，得到 360×120 的人物条。
    /// 数值来自 constant.py 的 popup_move_shapes，顺序对应两张旗标。
    private struct FlagSpec {
        let resource: String
        let width: Int
        let height: Int
        let dx1: Int
        let dy1: Int
        let dx2: Int
        let dy2: Int
        let keywords: [String]
    }

    private static let flags: [FlagSpec] = [
        FlagSpec(resource: "popup_flag_2", width: 96, height: 14,
                 dx1: -82, dy1: 29, dx2: 182, dy2: 135,
                 keywords: ["面对着你"]),
        FlagSpec(resource: "popup_flag_1", width: 180, height: 13,
                 dx1: -84, dy1: 33, dx2: 96, dy2: 140,
                 keywords: ["意外奖励", "将会得到"]),
    ]

    private let model: MLModel?
    private var templates: [(FlagSpec, [UInt8])] = []
    private var didLogModelMiss = false

    init() {
        let config = MLModelConfiguration()
        config.computeUnits = .cpuOnly
        if let url = Bundle.main.url(forResource: "MHXYFront", withExtension: "mlmodelc") {
            model = try? MLModel(contentsOf: url, configuration: config)
        } else {
            model = nil
        }
        for spec in Self.flags {
            guard let url = Bundle.main.url(forResource: spec.resource, withExtension: "jpg"),
                  let image = NSImage(contentsOf: url),
                  let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
                  let gray = Self.topDownGray(cg),
                  gray.count == spec.width * spec.height else { continue }
            templates.append((spec, gray))
        }
    }

    /// 找到四人条并选出正面角色。没有弹框时返回 nil。
    func frontPortrait(in image: CGImage) async -> BattlePortraitHit? {
        guard let model else {
            if !didLogModelMiss {
                didLogModelMiss = true
                print("[弹框] 没有加载到 MHXYFront.mlmodelc")
            }
            return nil
        }

        let strip: CGRect
        if let matched = matchTemplateStrip(in: image) {
            strip = matched
        } else if let read = await matchTextStrip(in: image) {
            strip = read
        } else {
            return nil
        }

        var logits: [Double] = []
        var centers: [CGPoint] = []
        let cellW = strip.width / 4
        for i in 0..<4 {
            let cell = CGRect(x: strip.minX + CGFloat(i) * cellW,
                              y: strip.minY,
                              width: cellW,
                              height: strip.height)
            guard let crop = crop(image, to: cell),
                  let buffer = Self.buffer(from: crop, width: 100, height: 100),
                  let logit = predict(buffer, model: model) else {
                print("[弹框] 第 \(i + 1) 张头像没能送进模型")
                return nil
            }
            logits.append(logit)
            centers.append(CGPoint(x: cell.midX / CGFloat(image.width),
                                   y: cell.midY / CGFloat(image.height)))
        }

        guard let best = logits.enumerated().min(by: { $0.element < $1.element }) else { return nil }
        let text = logits.map { String(format: "%.2f", $0) }.joined(separator: ", ")
        print("[弹框] logits [\(text)] → 正面 #\(best.offset + 1)")
        return BattlePortraitHit(index: best.offset,
                                 center: centers[best.offset],
                                 logit: best.element,
                                 logits: logits)
    }

    // MARK: - 定位人物条

    /// 在缩放到参考宽度的灰度图上做归一化相关，命中后把偏移映射回原图像素。
    private func matchTemplateStrip(in image: CGImage) -> CGRect? {
        guard !templates.isEmpty,
              let work = workingGray(from: image) else { return nil }

        var best: (score: Double, spec: FlagSpec, x: Int, y: Int)?
        for (spec, gray) in templates {
            guard let hit = locate(template: gray, tw: spec.width, th: spec.height,
                                   scene: work.pixels, sw: work.w, sh: work.h) else { continue }
            if hit.score >= 0.45 {
                print(String(format: "[弹框] 模板 %@ 相关 %.3f @ (%d,%d)",
                             spec.resource, hit.score, hit.x, hit.y))
            }
            guard hit.score >= 0.60 else { continue }
            if let current = best, hit.score <= current.score { continue }
            best = (hit.score, spec, hit.x, hit.y)
        }
        guard let best else { return nil }

        let x1 = Double(best.x + best.spec.dx1)
        let y1 = Double(best.y + best.spec.dy1)
        let x2 = Double(best.x + best.spec.width + best.spec.dx2)
        let y2 = Double(best.y + best.spec.height + best.spec.dy2)
        let rect = CGRect(x: x1 * work.scaleX,
                          y: y1 * work.scaleY,
                          width: (x2 - x1) * work.scaleX,
                          height: (y2 - y1) * work.scaleY)
        guard stripLooksValid(rect, in: image) else { return nil }
        return rect
    }

    /// 游戏字缩放后和 Windows 截图像素对不齐时，用文字框按同样的相对偏移推人物条。
    private func matchTextStrip(in image: CGImage) async -> CGRect? {
        let texts = await recognize(image)
        let width = image.width
        let height = image.height
        for spec in Self.flags {
            // 旗标是一小段完整文字。识别结果比它长很多时，框会把前后的字也包进去，偏移会错。
            let expectedCount = max(4, spec.width / 12)
            guard let box = texts.first(where: { text in
                spec.keywords.contains { text.text.contains($0) }
                    && abs(text.text.count - expectedCount) <= 6
            }) else { continue }
            let scale = Double(box.w) / Double(spec.width)
            guard scale > 0.3, scale < 12 else { continue }
            let rect = CGRect(
                x: Double(box.x) + Double(spec.dx1) * scale,
                y: Double(box.y) + Double(spec.dy1) * scale,
                width: Double(Self.stripWidth) * scale,
                height: Double(Self.stripHeight) * scale
            )
            guard stripLooksValid(rect, inWidth: width, height: height) else { continue }
            print("[弹框] 文字「\(box.text)」定位人物条")
            return rect
        }
        return nil
    }

    private func stripLooksValid(_ rect: CGRect, in image: CGImage) -> Bool {
        stripLooksValid(rect, inWidth: image.width, height: image.height)
    }

    private func stripLooksValid(_ rect: CGRect, inWidth width: Int, height: Int) -> Bool {
        guard rect.width > 80, rect.height > 30 else { return false }
        let ratio = rect.width / rect.height
        guard ratio > 2.2, ratio < 4.0 else { return false }
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        let inside = rect.intersection(bounds)
        return inside.width >= rect.width * 0.9 && inside.height >= rect.height * 0.9
    }

    // MARK: - 模板相关

    private struct WorkGray {
        let pixels: [UInt8]
        let w: Int
        let h: Int
        let scaleX: Double
        let scaleY: Double
    }

    private func workingGray(from image: CGImage) -> WorkGray? {
        let srcW = image.width
        let srcH = image.height
        guard srcW > 10, srcH > 10 else { return nil }
        let w = Self.referenceWidth
        let h = max(1, Int((Double(srcH) * Double(w) / Double(srcW)).rounded()))
        guard let resized = Self.resize(image, width: w, height: h),
              let gray = Self.topDownGray(resized),
              gray.count == w * h else { return nil }
        return WorkGray(pixels: gray, w: w, h: h,
                        scaleX: Double(srcW) / Double(w),
                        scaleY: Double(srcH) / Double(h))
    }

    private func locate(template: [UInt8], tw: Int, th: Int,
                        scene: [UInt8], sw: Int, sh: Int) -> (x: Int, y: Int, score: Double)? {
        guard sw > tw, sh > th else { return nil }
        let n = Double(tw * th)
        var tSum = 0.0
        var tSq = 0.0
        for v in template {
            let d = Double(v)
            tSum += d
            tSq += d * d
        }
        let tMean = tSum / n
        let tVar = tSq / n - tMean * tMean
        guard tVar > 1 else { return nil }
        let tStd = sqrt(tVar)

        let step = 4
        let xMax = sw - tw
        let yMax = sh - th
        let ys = Array(stride(from: 0, through: yMax, by: step))
        var bestX = [Int](repeating: 0, count: ys.count)
        var bestScore = [Double](repeating: -2, count: ys.count)
        DispatchQueue.concurrentPerform(iterations: ys.count) { i in
            let y = ys[i]
            var localX = 0
            var localS = -2.0
            var x = 0
            while x <= xMax {
                let s = ncc(scene: scene, sw: sw, template: template, tw: tw, th: th,
                            x: x, y: y, tMean: tMean, tStd: tStd)
                if s > localS {
                    localS = s
                    localX = x
                }
                x += step
            }
            bestX[i] = localX
            bestScore[i] = localS
        }

        var bx = 0
        var by = 0
        var bs = -2.0
        for i in ys.indices where bestScore[i] > bs {
            bs = bestScore[i]
            bx = bestX[i]
            by = ys[i]
        }

        let x0 = max(0, bx - step)
        let y0 = max(0, by - step)
        let x1 = min(xMax, bx + step)
        let y1 = min(yMax, by + step)
        var y = y0
        while y <= y1 {
            var x = x0
            while x <= x1 {
                let s = ncc(scene: scene, sw: sw, template: template, tw: tw, th: th,
                            x: x, y: y, tMean: tMean, tStd: tStd)
                if s > bs {
                    bs = s
                    bx = x
                    by = y
                }
                x += 1
            }
            y += 1
        }
        return (bx, by, bs)
    }

    private func ncc(scene: [UInt8], sw: Int, template: [UInt8], tw: Int, th: Int,
                     x: Int, y: Int, tMean: Double, tStd: Double) -> Double {
        var sum = 0.0
        var sumSq = 0.0
        var cross = 0.0
        let count = Double(tw * th)
        for row in 0..<th {
            let sBase = (y + row) * sw + x
            let tBase = row * tw
            for col in 0..<tw {
                let sv = Double(scene[sBase + col])
                let tv = Double(template[tBase + col])
                sum += sv
                sumSq += sv * sv
                cross += sv * tv
            }
        }
        let sMean = sum / count
        let sVar = sumSq / count - sMean * sMean
        guard sVar > 1 else { return -1 }
        return (cross / count - sMean * tMean) / (sqrt(sVar) * tStd)
    }

    // MARK: - 模型

    private func predict(_ buffer: CVPixelBuffer, model: MLModel) -> Double? {
        let value = MLFeatureValue(pixelBuffer: buffer)
        guard let provider = try? MLDictionaryFeatureProvider(dictionary: ["image": value]),
              let result = try? model.prediction(from: provider),
              let array = result.featureValue(for: "logit")?.multiArrayValue,
              array.count > 0 else { return nil }
        return array[0].doubleValue
    }

    private func crop(_ image: CGImage, to rect: CGRect) -> CGImage? {
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let clipped = rect.intersection(bounds)
        guard clipped.width > 8, clipped.height > 8 else { return nil }
        let pixel = CGRect(x: floor(clipped.minX), y: floor(clipped.minY),
                           width: floor(clipped.maxX) - floor(clipped.minX),
                           height: floor(clipped.maxY) - floor(clipped.minY))
        return image.cropping(to: pixel)
    }

    // MARK: - 文字

    /// Vision 的完成回调有时和 perform 的错误路径都会走到，只恢复一次。
    private final class ResumeOnce {
        private let lock = NSLock()
        private var done = false
        func resume(_ continuation: CheckedContinuation<[TextBox], Never>, returning boxes: [TextBox]) {
            lock.lock()
            let first = !done
            done = true
            lock.unlock()
            if first { continuation.resume(returning: boxes) }
        }
    }

    private struct TextBox {
        let text: String
        let x: Int
        let y: Int
        let w: Int
        let h: Int
    }

    private func recognize(_ image: CGImage) async -> [TextBox] {
        let width = image.width
        let height = image.height
        return await withCheckedContinuation { continuation in
            let gate = ResumeOnce()
            let request = VNRecognizeTextRequest { req, _ in
                let observations = (req.results as? [VNRecognizedTextObservation]) ?? []
                let boxes = observations.compactMap { obs -> TextBox? in
                    guard let text = obs.topCandidates(1).first?.string else { return nil }
                    let box = obs.boundingBox
                    let x = Int(box.minX * Double(width))
                    let y = Int((1.0 - box.maxY) * Double(height))
                    let w = max(1, Int(box.width * Double(width)))
                    let h = max(1, Int(box.height * Double(height)))
                    return TextBox(text: text, x: x, y: y, w: w, h: h)
                }
                gate.resume(continuation, returning: boxes)
            }
            request.recognitionLanguages = ["zh-Hans", "zh-Hant"]
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            do {
                try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
            } catch {
                gate.resume(continuation, returning: [])
            }
        }
    }

    // MARK: - 图像

    /// 第一行是图像顶部，和 CGImage、JPEG 的行序一致。
    private static func topDownGray(_ image: CGImage) -> [UInt8]? {
        let w = image.width
        let h = image.height
        guard w > 0, h > 0 else { return nil }
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(
            data: &pixels, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        // 不要再翻转。CGBitmapContext 的第 0 行就是图像顶部，和 CGImage 裁剪坐标一致。
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

        var gray = [UInt8](repeating: 0, count: w * h)
        for i in 0..<(w * h) {
            let o = i * 4
            let y = 0.299 * Double(pixels[o]) + 0.587 * Double(pixels[o + 1]) + 0.114 * Double(pixels[o + 2])
            gray[i] = UInt8(min(255, max(0, y.rounded())))
        }
        return gray
    }

    private static func resize(_ image: CGImage, width: Int, height: Int) -> CGImage? {
        guard let ctx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()
    }

    /// 送进 Core ML 的像素缓冲，第 0 行是图像顶部。
    private static func buffer(from image: CGImage, width: Int, height: Int) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        let attrs = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
        ] as CFDictionary
        guard CVPixelBufferCreate(kCFAllocatorDefault, width, height,
                                  kCVPixelFormatType_32BGRA, attrs, &buffer) == kCVReturnSuccess,
              let buffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let ctx = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        // 第 0 行保持为图像顶部。多翻一次会把角色倒过来，logit 会和原模型对不上。
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return buffer
    }
}
