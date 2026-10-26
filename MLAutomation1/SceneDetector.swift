//
//  SceneDetector.swift
//  MLAutomation
//

import Foundation
import AppKit
import CoreGraphics
import Vision

// MARK: - 场景识别服务

// MARK: - 文字元素（扫描坐标用）
struct TextElement {
    let text:  String
    let x:     Int
    let y:     Int
    let w:     Int
    let h:     Int
    
    /// 归一化坐标（直接可填入 UIRegions）
    let normX: Double
    let normY: Double
    let normW: Double
    let normH: Double

    /// OCR 来源图尺寸（物理像素），用于 clickAtOCR 正确将 normX/Y 换算为屏幕逻辑点
    /// Retina 屏幕下 cgImage.width = 2 × window.frame.width，必须传入此字段才能消除向下偏移
    let srcW: Int
    let srcH: Int

    var description: String {
        "[\(text)]  像素:(x:\(x) y:\(y) w:\(w) h:\(h))  比例:(x:\(f(normX)) y:\(f(normY)) w:\(f(normW)) h:\(f(normH)))"
    }
    private func f(_ v: Double) -> String { String(format: "%.4f", v) }
}


// MARK: - 模板匹配结果
struct TemplateMatch {
    let found:      Bool
    let confidence: Double
    let rect:       CGRect   // 像素坐标（匹配到的位置）
    let normRect:   CGRect   // 归一化坐标（可直接用于点击）
}


// MARK:  UI 区域（相对窗口比例坐标）⚠️ 需根据实际分辨率校准
struct UIRegions {
    // 地图信息（通常在左上角或右上角）
    static let mapName       = CGRect(x: 0.00, y: 0.00, width: 0.35, height: 0.06)
    // 坐标（通常在地图名旁边或小地图下方）
    static let coordinate    = CGRect(x: 0.00, y: 0.05, width: 0.25, height: 0.05)
    // 地点:
    static let locationPx = CGRect(x: 0.0273, y: 0.0602, width: 0.0624, height: 0.0226)
    // 战斗回合
    static let fightPx = CGRect(x: 0.4737, y: 0.0551, width: 0.0741, height: 0.0226)
    // 坐标X
    static let xPx = CGRect(x: 0.0038, y: 0.1350, width: 0.0686, height: 0.0207)
    // 坐标Y
    static let yPx = CGRect(x: 0.0721, y: 0.1328, width: 0.0686, height: 0.0207)
    /// 任务检测
    static let oneTask = CGRect(x: 0.0721, y: 0.1328, width: 0.0686, height: 0.0207)
    // 背包 行囊字
    static let luggage = CGRect(x: 0.1326, y: 0.1855, width: 0.0643, height: 0.0226)
    //  合成旗字 长安
    static let heChangQiCAZi = CGRect(x: 0.5295, y: 0.2239, width: 0.0724, height: 0.0326)
    //  合成旗字 大唐过境
    static let heChangQiDTGJZi = CGRect(x: 0.5295, y: 0.2239, width: 0.0724, height: 0.0326)
     
    // 驿站老板名字标注区域（排除聊天栏，只扫场景中间）
    static let npcLabelROI = CGRect(x: 0.28, y: 0.26, width: 0.50, height: 0.35)
    // 对话框区域
    
    // 对话框区域（包含选项文字）
    static let dialogROI = CGRect(x: 0.17, y: 0.53, width: 0.38, height: 0.18)
}


class SceneDetector {
    
    // 模板缓存
    private var templates: [String: CGImage] = [:]

    init() { loadTemplates() }

    // MARK: - 模板加载
    private func loadTemplates() {
        let names = [
            "ca", "dtjw",
            "fxf",  "yan",
            "yizhanlaoban",
        ]
        for name in names {
            if let img   = NSImage(named: name),
               let cgImg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                templates[name] = cgImg
            }
        }
        print("[SceneDetector] 加载模板: \(templates.count)/\(names.count)")
    }
    
    
    
    // MARK: - 扫描全屏所有文字和位置
    func scanAllText(cgImage: CGImage) async -> [TextElement] {
        let imgW = cgImage.width
        let imgH = cgImage.height

        // 双通道：中文优先 + 英文专项，合并后去重，解决英文识别率低的问题
        async let zhPass = ocrPass(cgImage: cgImage,
                                   languages: ["zh-Hans", "zh-Hant", "en-US"],
                                   imgW: imgW, imgH: imgH)
        async let enPass = ocrPass(cgImage: cgImage,
                                   languages: ["en-US"],
                                   imgW: imgW, imgH: imgH)

        var merged = await zhPass
        for enEl in await enPass {
            // 若英文扫描结果与已有结果 IOU > 0.3，视为同一区域，跳过
            let overlaps = merged.contains { iouOverlap($0, enEl) > 0.3 }
            if !overlaps { merged.append(enEl) }
        }
        return merged.sorted { $0.y < $1.y }
    }

    /// 单次 OCR 扫描（抽取复用）
    private func ocrPass(cgImage: CGImage, languages: [String], imgW: Int, imgH: Int) async -> [TextElement] {
        await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { req, err in
                guard err == nil,
                      let observations = req.results as? [VNRecognizedTextObservation]
                else {
                    continuation.resume(returning: [])
                    return
                }
                let elements = observations.compactMap { obs -> TextElement? in
                    guard let text = obs.topCandidates(1).first?.string else { return nil }
                    let vb    = obs.boundingBox
                    let normX = vb.minX
                    let normY = 1.0 - vb.maxY   // Vision Y轴翻转
                    let normW = vb.width
                    let normH = vb.height
                    return TextElement(
                        text:  text,
                        x:     Int(normX * Double(imgW)),
                        y:     Int(normY * Double(imgH)),
                        w:     max(1, Int(normW * Double(imgW))),
                        h:     max(1, Int(normH * Double(imgH))),
                        normX: normX, normY: normY, normW: normW, normH: normH,
                        srcW:  imgW,  srcH:  imgH
                    )
                }
                continuation.resume(returning: elements)
            }
            request.recognitionLanguages   = languages
            request.recognitionLevel       = .accurate
            request.usesLanguageCorrection = false
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try? handler.perform([request])
        }
    }

    /// 计算两个 TextElement 归一化包围盒的 IoU（用于去重判断）
    private func iouOverlap(_ a: TextElement, _ b: TextElement) -> Double {
        let ax1 = a.normX, ay1 = a.normY, ax2 = ax1 + a.normW, ay2 = ay1 + a.normH
        let bx1 = b.normX, by1 = b.normY, bx2 = bx1 + b.normW, by2 = by1 + b.normH
        let ix1 = max(ax1, bx1), iy1 = max(ay1, by1)
        let ix2 = min(ax2, bx2), iy2 = min(ay2, by2)
        guard ix2 > ix1, iy2 > iy1 else { return 0 }
        let inter = (ix2 - ix1) * (iy2 - iy1)
        let union = a.normW * a.normH + b.normW * b.normH - inter
        return union > 0 ? inter / union : 0
    }




    // MARK: - Vision OCR 识别指定区域文字
    func ocrRegion(_ cgImage: CGImage, region: CGRect) async -> String {
        // 裁剪目标区域
        let x = Int(region.minX  * Double(cgImage.width))
        let y = Int(region.minY  * Double(cgImage.height))
        let w = max(1, Int(region.width  * Double(cgImage.width)))
        let h = max(1, Int(region.height * Double(cgImage.height)))

        guard let roi = cgImage.cropping(to: CGRect(x: x, y: y, width: w, height: h))
        else { return "" }

        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { req, err in
                guard err == nil,
                      let observations = req.results as? [VNRecognizedTextObservation]
                else {
                    continuation.resume(returning: "")
                    return
                }
                // 拼接所有识别到的文字
                let text = observations
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: " ")
                continuation.resume(returning: text)
            }
            // 优先识别中文+英文
            request.recognitionLanguages   = ["zh-Hans", "zh-Hant", "en-US"]
            request.recognitionLevel       = .accurate
            request.usesLanguageCorrection = false  // 游戏文字不需要语言纠正

            let handler = VNImageRequestHandler(cgImage: roi, options: [:])
            try? handler.perform([request])
        }
    }

    // MARK: - 🔧 调试工具：全图扫描所有文字+坐标（用于建立 UIRegions 坐标表）
        // 使用方式：在某个场景截图后调用一次，查看控制台输出，把关键坐标填入 UIRegions
        @discardableResult
        func scanAllTextElements(cgImage: CGImage) async -> [TextElement] {
            let imgW = cgImage.width
            let imgH = cgImage.height

            return await withCheckedContinuation { continuation in
                let request = VNRecognizeTextRequest { req, _ in
                    guard let observations = req.results as? [VNRecognizedTextObservation] else {
                        continuation.resume(returning: [])
                        return
                    }

                    var elements: [TextElement] = []

                    for obs in observations {
                        guard let candidate = obs.topCandidates(1).first else { continue }
                        let text = candidate.string
                        let box  = obs.boundingBox  // 归一化，Y 轴从底部算

                        // Vision boundingBox 是左下角原点，Y↑
                        // 翻转为左上角原点，Y↓，与 CGWindowList / UIRegions 坐标系一致
                        let normX = box.origin.x
                        let normY = 1.0 - box.origin.y - box.height
                        let normW = box.width
                        let normH = box.height

                        // 像素坐标
                        let px = Int(normX * Double(imgW))
                        let py = Int(normY * Double(imgH))
                        let pw = Int(normW * Double(imgW))
                        let ph = Int(normH * Double(imgH))

                        elements.append(TextElement(
                            text: text,
                            x: px, y: py, w: pw, h: ph,
                            normX: normX, normY: normY,
                            normW: normW, normH: normH,
                            srcW: imgW, srcH: imgH
                        ))
                    }

                    // 按 Y 从上到下排序
                    let sorted = elements.sorted { $0.y < $1.y }
                    continuation.resume(returning: sorted)
                }

                request.recognitionLevel       = .accurate
                request.recognitionLanguages   = ["zh-Hans", "zh-Hant", "en-US"]
                request.usesLanguageCorrection = false

                autoreleasepool {
                    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                    try? handler.perform([request])
                }
            }
      }


    private func nccScore(source: CGImage, template: CGImage) -> Double {
        let tw = template.width, th = template.height
        guard let srcCtx = makeContext(width: tw, height: th),
              let tplCtx = makeContext(width: tw, height: th) else { return 0.0 }
        srcCtx.draw(source,   in: CGRect(x: 0, y: 0, width: tw, height: th))
        tplCtx.draw(template, in: CGRect(x: 0, y: 0, width: tw, height: th))
        guard let srcData = srcCtx.data, let tplData = tplCtx.data else { return 0.0 }
        let src = srcData.bindMemory(to: UInt8.self, capacity: tw * th * 4)
        let tpl = tplData.bindMemory(to: UInt8.self, capacity: tw * th * 4)
        var diff = 0.0
        for i in 0..<tw * th {
            for c in 0..<3 { diff += abs(Double(src[i*4+c]) - Double(tpl[i*4+c])) }
        }
        return max(0, 1.0 - diff / Double(tw * th * 3 * 255) * 3)
    }

   

    private func makeContext(width: Int, height: Int) -> CGContext? {
        CGContext(data: nil, width: width, height: height,
                  bitsPerComponent: 8, bytesPerRow: width * 4,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue).rawValue)
    }
}

// MARK: - 识别结果
struct SceneDetection {
    var scene:      GameScene = .unknown
    var confidence: Double    = 0.0
    var hpPercent:  Double    = 1.0
    var mpPercent:  Double    = 1.0
    var gameInfo:   GameInfo  = GameInfo()
}


// MARK: - NPCFinder 模板匹配（加入 SceneDetector）
extension SceneDetector {
    

    /// 在 npcLabelROI 区域内用模板匹配找驿站老板，返回全图归一化点击坐标
    /// - Parameter clickYOffset: 点击位置相对模板顶部的 Y 偏移（像素），负数=往上，正数=往下
    func findNPCByTemplate(in cgImage: CGImage, clickYOffset: Int = 0) -> CGPoint? {

        let templateNames = ["station_boss_tmpl_A", "station_boss_tmpl_B", "station_boss_tmpl_C"]
        let loadedTemplates: [CGImage] = templateNames.compactMap {
            NSImage(named: $0)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        }
        guard !loadedTemplates.isEmpty else {
            print("[NPCFinder] ❌ 模板未加载，检查 Assets 名称")
            return nil
        }

        let sw = Double(cgImage.width)
        let sh = Double(cgImage.height)

        // ── 3. 按 npcLabelROI 裁剪搜索区域 ──
        // ⚠️ CGImage 坐标系原点在左下角，需要翻转 Y 轴
        let roi  = UIRegions.npcLabelROI
        let roiX = Int(roi.minX * sw)
        let roiY = Int(roi.minY * sh)
        let roiW = Int(roi.width  * sw)
        let roiH = Int(roi.height * sh)

        print("[NPCFinder] 📐 图片: \(Int(sw))×\(Int(sh))  ROI像素: (\(roiX),\(roiY)) \(roiW)×\(roiH)")

        guard let roiImage = cgImage.cropping(to: CGRect(x: roiX, y: roiY,
                                                          width: roiW, height: roiH))
        else {
            print("[NPCFinder] ❌ ROI 裁剪失败")
            return nil
        }

        // 按当前图片尺寸相对 CoordBase 的缩放比例，等比缩放模板
        let scaleX = sw / Double(CoordBase.width)
        let scaleY = sh / Double(CoordBase.height)

        // ── 4. 多模板匹配，取最高分 ──
        var bestScore: Float = 0
        var bestX = 0, bestY = 0
        var bestTW = 0, bestTH = 0

        for template in loadedTemplates {
            // 等比缩放模板到当前分辨率
            var scaledW = max(1, Int(Double(template.width)  * scaleX))
            var scaledH = max(1, Int(Double(template.height) * scaleY))

            // 兜底：模板必须小于 ROI 的 70%，否则自动缩小
            let maxTW = Int(Double(roiW) * 0.7)
            let maxTH = Int(Double(roiH) * 0.7)
            if scaledW > maxTW || scaledH > maxTH {
                let fitScale = min(Double(maxTW) / Double(scaledW), Double(maxTH) / Double(scaledH))
                scaledW = max(1, Int(Double(scaledW) * fitScale))
                scaledH = max(1, Int(Double(scaledH) * fitScale))
                print("[NPCFinder] ⚠️ 模板超出ROI，自动缩小至 \(scaledW)×\(scaledH)")
            }

            let scaledTemplate: CGImage
            if scaledW != template.width || scaledH != template.height {
                scaledTemplate = resizeCGImage(template,
                                               to: CGSize(width: scaledW, height: scaledH)) ?? template
            } else {
                scaledTemplate = template
            }

            guard let sceneGray    = extractGray(from: roiImage),
                  let templateGray = extractGray(from: scaledTemplate)
            else { continue }

            let tw = scaledTemplate.width, th = scaledTemplate.height
            let searchW = roiW - tw
            let searchH = roiH - th

            print("[NPCFinder] 📐 模板原始: \(template.width)×\(template.height)  缩放后: \(tw)×\(th)  searchW: \(searchW)  searchH: \(searchH)")

            guard searchW > 0, searchH > 0 else {
                print("[NPCFinder] ❌ 模板(\(tw)×\(th))大于ROI(\(roiW)×\(roiH))，请缩小模板或扩大 npcLabelROI")
                continue
            }
            
            let tMean = templateGray.reduce(0.0) { $0 + Double($1) } / Double(tw * th)
            let tStd  = sqrt(templateGray.reduce(0.0) { $0 + pow(Double($1) - tMean, 2) } / Double(tw * th))
            guard tStd > 0 else { continue }
            
            // 粗搜索（步长8）
            var candScore: Float = -1
            var candX = 0, candY = 0
            let step = 4
            for y in stride(from: 0, to: searchH, by: step) {
                for x in stride(from: 0, to: searchW, by: step) {
                    let s = nccScore(scenePixels: sceneGray, sceneW: roiW,
                                     templatePixels: templateGray, tw: tw, th: th,
                                     atX: x, atY: y, tMean: tMean, tStd: tStd)
                    if s > candScore { candScore = s; candX = x; candY = y }
                }
            }
            // 精细搜索（候选点 ±step）
            for y in max(0, candY-step)...min(searchH-1, candY+step) {
                for x in max(0, candX-step)...min(searchW-1, candX+step) {
                    let s = nccScore(scenePixels: sceneGray, sceneW: roiW,
                                     templatePixels: templateGray, tw: tw, th: th,
                                     atX: x, atY: y, tMean: tMean, tStd: tStd)
                    if s > candScore { candScore = s; candX = x; candY = y }
                }
            }
            
            if candScore > bestScore {
                bestScore = candScore
                bestX = candX; bestY = candY
                bestTW = tw;   bestTH = th
            }
        }
        
        guard bestScore > 0.15 else {
            print("[NPCFinder] ❌ 相似度不足: \(String(format:"%.3f", bestScore))")
            return nil
        }
        
        // ── 5. ROI坐标 → 全图坐标 → 归一化 ──
        // bestX/bestY 是模板左上角在 ROI 内的坐标；取模板中心再加 clickYOffset 微调
        let absX = roiX + bestX + bestTW / 2
        let absY = roiY + bestY + bestTH / 2 + clickYOffset

        let normX = Double(absX) / sw
        let normY = Double(max(0, min(Int(sh)-1, absY))) / sh

        print("[NPCFinder] 📐 match top=\(roiY+bestY) tmplH=\(bestTH) 中心Y=\(roiY+bestY+bestTH/2) offset=\(clickYOffset) final absY=\(absY) normY=\(String(format:"%.4f",normY))")

        // 边界保护：老板只在这个范围内活动
        guard (0.20...0.85).contains(normX),
              (0.10...0.80).contains(normY) else {
            print("[NPCFinder] ❌ 坐标超出活动范围: (\(normX), \(normY))")
            return nil
        }
        
        print("[NPCFinder] ✅ score=\(String(format:"%.3f",bestScore)) 点击=(\(String(format:"%.4f",normX)),\(String(format:"%.4f",normY)))")
        return CGPoint(x: normX, y: normY)
    }
    
    // MARK: - 工具方法
    private func resizeCGImage(_ image: CGImage, to size: CGSize) -> CGImage? {
        let ctx = CGContext(data: nil,
                            width: Int(size.width), height: Int(size.height),
                            bitsPerComponent: 8, bytesPerRow: Int(size.width) * 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        ctx?.interpolationQuality = .high
        ctx?.draw(image, in: CGRect(origin: .zero, size: size))
        return ctx?.makeImage()
    }
    

    private func extractGray(from image: CGImage) -> [UInt8]? {
        let w = image.width, h = image.height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)

        // Create the CGContext to render the image
        guard let ctx = CGContext(data: &pixels, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        
        // Draw the image into the context
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        
        // Now, map the pixels to grayscale
        var grayPixels = [UInt8](repeating: 0, count: w * h)
        
        for i in stride(from: 0, to: pixels.count, by: 4) {
            // Extract the red, green, and blue components
            let red = Int(pixels[i])
            let green = Int(pixels[i + 1])
            let blue = Int(pixels[i + 2])
            
            // Calculate the grayscale value using the luminosity formula
            let gray = (Double(red) * 0.299 + Double(green) * 0.587 + Double(blue) * 0.114)
            
            // Assign the grayscale value to the corresponding pixel
            grayPixels[i / 4] = UInt8(gray)
        }
        
        return grayPixels
    }
    
    private func nccScore(scenePixels: [UInt8], sceneW: Int,
                          templatePixels: [UInt8], tw: Int, th: Int,
                          atX: Int, atY: Int, tMean: Double, tStd: Double) -> Float {
        var sum = 0.0, sumSq = 0.0, cross = 0.0
        let count = tw * th
        for row in 0..<th {
            for col in 0..<tw {
                let sv = Double(scenePixels[(atY + row) * sceneW + (atX + col)])
                let tv = Double(templatePixels[row * tw + col])
                sum   += sv
                sumSq += sv * sv
                cross += sv * tv
            }
        }
        let sMean = sum / Double(count)
        let sStd  = sqrt(max(0, sumSq / Double(count) - sMean * sMean))
        guard sStd > 0 else { return 0 }
        return Float((cross / Double(count) - sMean * tMean) / (sStd * tStd))
    }
    
    
    /// 只扫指定区域内的文字，坐标还原到全图归一化
    func scanTextInRegion(cgImage: CGImage, region: CGRect) async -> [TextElement] {
        let fullW = cgImage.width
        let fullH = cgImage.height

        let cropX = Int(region.minX * Double(fullW))
        let cropY = Int(region.minY * Double(fullH))
        let cropW = max(1, Int(region.width  * Double(fullW)))
        let cropH = max(1, Int(region.height * Double(fullH)))

        guard let cropped = cgImage.cropping(to: CGRect(x: cropX, y: cropY,
                                                         width: cropW, height: cropH))
        else { return [] }

        // 对裁剪区域做OCR
        let roiElements = await scanAllTextElements(cgImage: cropped)

        // ROI内归一化坐标 → 还原回全图归一化坐标
        return roiElements.map { el in
            let absNormX = region.minX + el.normX * region.width
            let absNormY = region.minY + el.normY * region.height
            let absNormW = el.normW * region.width
            let absNormH = el.normH * region.height
            return TextElement(
                text: el.text,
                x: Int(absNormX * Double(fullW)),
                y: Int(absNormY * Double(fullH)),
                w: Int(absNormW * Double(fullW)),
                h: Int(absNormH * Double(fullH)),
                normX: absNormX, normY: absNormY,
                normW: absNormW, normH: absNormH,
                srcW: fullW, srcH: fullH          // 必须传全图尺寸，确保 clickAtOCR 换算准确
            )
        }
    }
}


// MARK: - 弹屏朝向检测结果
struct PopupResult {
    let index:     Int         // 最对称（正面朝前）角色的索引
    let center:    CGPoint     // 该角色区域中心（相对全图的归一化坐标，可直接用于点击）
    let score:     Double      // 最高对称度
    let allScores: [Double]    // 所有角色的对称度
    let absRegions: [CGRect]   // 所有角色区域还原到全图后的归一化坐标（调试用）
}

// MARK: - 弹屏朝向检测（左右对称性）
extension SceneDetector {

    /// 弹屏检测：先裁剪弹屏弹窗区域（隔离背景干扰），再在裁剪后的图中分析四个角色的左右对称性
    ///
    /// 原理：正面朝前的角色精灵图左右对称性最高，侧面/背面则不对称。
    /// - Parameters:
    ///   - cgImage: 当前画面全图截图
    ///   - popupROI: 弹屏弹窗整体区域（相对全图的归一化坐标）
    ///   - charRegions: 各角色的子区域（⚠️ 相对 popupROI 的归一化坐标，不是全图坐标）
    /// - Returns: 检测结果，nil 表示裁剪失败
    func findFrontFacingCharacter(
        in cgImage: CGImage,
        popupROI: CGRect,
        charRegions: [CGRect]
    ) -> PopupResult? {
        let fullW = cgImage.width
        let fullH = cgImage.height

        // ── 1. 先裁剪弹屏弹窗整体区域 ──
        let roiX = Int(popupROI.minX * Double(fullW))
        let roiY = Int(popupROI.minY * Double(fullH))
        let roiW = max(1, Int(popupROI.width  * Double(fullW)))
        let roiH = max(1, Int(popupROI.height * Double(fullH)))

        guard let roiImage = cgImage.cropping(to: CGRect(x: roiX, y: roiY,
                                                          width: roiW, height: roiH))
        else {
            print("[弹屏] ❌ 弹屏区域裁剪失败")
            return nil
        }

        print("[弹屏] 📐 全图: \(fullW)×\(fullH)  弹屏ROI像素: (\(roiX),\(roiY)) \(roiW)×\(roiH)")

        // ── 2. 在裁剪后的弹屏图中逐个分析角色子区域 ──
        var bestIndex = -1
        var bestScore = -1.0
        var allScores: [Double] = []
        var absRegions: [CGRect] = []  // 还原到全图的坐标

        for (i, subRegion) in charRegions.enumerated() {
            let cropX = Int(subRegion.minX * Double(roiW))
            let cropY = Int(subRegion.minY * Double(roiH))
            let cropW = max(1, Int(subRegion.width  * Double(roiW)))
            let cropH = max(1, Int(subRegion.height * Double(roiH)))

            // 子区域还原到全图归一化坐标
            let absX = popupROI.minX + subRegion.minX * popupROI.width
            let absY = popupROI.minY + subRegion.minY * popupROI.height
            let absW = subRegion.width  * popupROI.width
            let absH = subRegion.height * popupROI.height
            absRegions.append(CGRect(x: absX, y: absY, width: absW, height: absH))

            guard cropX >= 0, cropY >= 0,
                  cropX + cropW <= roiW,
                  cropY + cropH <= roiH,
                  let cropped = roiImage.cropping(to: CGRect(x: cropX, y: cropY,
                                                              width: cropW, height: cropH)),
                  let gray = extractGray(from: cropped)
            else {
                print("[弹屏] ⚠️ 角色\(i+1) 子区域裁剪失败 (\(cropX),\(cropY)) \(cropW)×\(cropH) in \(roiW)×\(roiH)")
                allScores.append(0)
                continue
            }

            let score = leftRightSymmetryScore(gray, width: cropW, height: cropH)
            allScores.append(score)
            print("[弹屏] 角色\(i+1) 对称度: \(String(format: "%.4f", score))")

            if score > bestScore {
                bestScore = score
                bestIndex = i
            }
        }

        guard bestIndex >= 0 else {
            print("[弹屏] ❌ 未检测到任何角色")
            return nil
        }

        // ── 3. 子区域中心 → 还原到全图归一化坐标 ──
        let bestSub = charRegions[bestIndex]
        let centerInROI_X = bestSub.midX    // 在 popupROI 内的归一化中心
        let centerInROI_Y = bestSub.midY
        let globalX = popupROI.minX + centerInROI_X * popupROI.width
        let globalY = popupROI.minY + centerInROI_Y * popupROI.height

        print("[弹屏] ✅ 正面角色: #\(bestIndex+1)/\(charRegions.count) "
              + "对称度=\(String(format: "%.4f", bestScore)) "
              + "点击=(\(String(format: "%.4f", globalX)), \(String(format: "%.4f", globalY)))")

        return PopupResult(index: bestIndex,
                           center: CGPoint(x: globalX, y: globalY),
                           score: bestScore,
                           allScores: allScores,
                           absRegions: absRegions)
    }

    // MARK: 左右对称性分数（0~1，1=完全对称）
    private func leftRightSymmetryScore(_ gray: [UInt8], width: Int, height: Int) -> Double {
        guard width > 4, height > 4 else { return 0 }
        let halfW = width / 2
        var totalDiff = 0.0
        var count = 0
        for y in 0..<height {
            for x in 0..<halfW {
                let left  = Double(gray[y * width + x])
                let right = Double(gray[y * width + (width - 1 - x)])
                totalDiff += abs(left - right)
                count += 1
            }
        }
        guard count > 0 else { return 0 }
        return 1.0 - totalDiff / (Double(count) * 255.0)
    }

    // MARK: 调试：绘制弹屏ROI + 角色区域框 + 对称度分数，保存到桌面
    func debugSavePopupDetection(
        _ cgImage: CGImage,
        popupROI: CGRect,
        charRegions: [CGRect],
        result: PopupResult
    ) {
        let w = cgImage.width, h = cgImage.height
        guard let ctx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return }

        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))

        // 画弹屏 ROI 大框（蓝色虚线）
        let roiRect = CGRect(
            x: popupROI.minX * Double(w),
            y: popupROI.minY * Double(h),
            width: popupROI.width * Double(w),
            height: popupROI.height * Double(h)
        )
        ctx.setStrokeColor(CGColor(red: 0.3, green: 0.5, blue: 1.0, alpha: 1))
        ctx.setLineWidth(3)
        ctx.setLineDash(phase: 0, lengths: [10, 6])
        ctx.stroke(roiRect)
        ctx.setLineDash(phase: 0, lengths: [])  // 恢复实线

        // 画各角色子区域（还原到全图坐标）
        for (i, absRegion) in result.absRegions.enumerated() {
            let rect = CGRect(
                x: absRegion.minX * Double(w),
                y: absRegion.minY * Double(h),
                width: absRegion.width * Double(w),
                height: absRegion.height * Double(h)
            )

            let isSelected = (i == result.index)
            let color: CGColor = isSelected
                ? CGColor(red: 0, green: 1, blue: 0, alpha: 1)
                : CGColor(red: 1, green: 1, blue: 0, alpha: 1)

            ctx.setStrokeColor(color)
            ctx.setLineWidth(isSelected ? 4 : 2)
            ctx.stroke(rect)

            // 标注分数文字
            if i < result.allScores.count {
                let label = String(format: "#%d: %.3f%@", i + 1, result.allScores[i],
                                   isSelected ? " ✅" : "")
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .bold),
                    .foregroundColor: isSelected ? NSColor.green : NSColor.yellow
                ]
                let attrStr = NSAttributedString(string: label, attributes: attrs)
                let line = CTLineCreateWithAttributedString(attrStr)
                ctx.textPosition = CGPoint(x: rect.minX + 4,
                                           y: Double(h) - rect.minY - 18)
                CTLineDraw(line, ctx)
            }
        }

        guard let resultImg = ctx.makeImage() else { return }
        let formatter = DateFormatter()
        formatter.dateFormat = "HHmmss_SSS"
        let ts = formatter.string(from: Date())
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
        let url = desktop.appendingPathComponent("debug_popup_\(ts).png")
        if let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) {
            CGImageDestinationAddImage(dest, resultImg, nil)
            if CGImageDestinationFinalize(dest) {
                print("[弹屏] 📸 调试图已保存: \(url.lastPathComponent)")
            }
        }
    }
}
