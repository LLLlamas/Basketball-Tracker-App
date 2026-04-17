import Foundation
import CoreGraphics

struct DetectedBall {
    let positionNormalized: CGPoint   // 0...1 of source video frame
    let radiusNormalized: CGFloat
    let confidence: Double
    let timestampMs: Double
}

/// Port of `isBallColor`, `buildBackgroundFrame`, `detectBallByColor` from index.html.
///
/// Two-phase pipeline:
/// 1. Accumulate a background mask of pixels that are "ball-colored most of the time" —
///    bright carpet, scoreboard, etc. — so we can ignore them.
/// 2. Every subsequent frame, find ball-colored pixels NOT in the mask, cluster them,
///    and return the most compact dense cluster as the ball.
final class ColorBallDetector {
    private let w = DetectionConstants.colorW
    private let h = DetectionConstants.colorH
    private var bgAccum: [UInt16]?
    private var bgMask: [UInt8]?
    private var bgFramesBuilt = 0

    var isMaskReady: Bool { bgMask != nil }

    func reset() {
        bgAccum = nil
        bgMask = nil
        bgFramesBuilt = 0
    }

    /// Run one detection tick. Caller is expected to throttle (e.g. every 3rd frame).
    /// Returns the best detected ball or nil.
    func process(
        pixelBuffer: LockedPixelBuffer,
        hoop: CGPoint,
        timestampMs: Double
    ) -> DetectedBall? {
        // Scan just the top of the frame — basketball physics means the ball rarely
        // stays below hoop + a little margin.
        let scanH = min(
            pixelBuffer.height,
            Int(Double(pixelBuffer.height) * (hoop.y + 0.18))
        )
        let pixels = pixelBuffer.resample(
            sourceRect: CGRect(x: 0, y: 0, width: pixelBuffer.width, height: max(1, scanH)),
            targetW: w,
            targetH: h
        )

        if bgMask == nil {
            accumulateBackground(pixels: pixels)
            return nil
        }

        // Fraction of full frame height the downsampled buffer represents.
        let scanFraction = min(1.0, hoop.y + 0.18)
        return findBall(pixels: pixels, scanFraction: scanFraction, timestampMs: timestampMs)
    }

    // MARK: - Background accumulation

    private func accumulateBackground(pixels: [UInt8]) {
        if bgAccum == nil {
            bgAccum = [UInt16](repeating: 0, count: w * h)
        }
        for y in 0..<h {
            let rowBase = y * w
            for x in 0..<w {
                let i = (rowBase + x) * 4
                if Self.isBallColor(r: pixels[i], g: pixels[i + 1], b: pixels[i + 2]) {
                    bgAccum![rowBase + x] &+= 1
                }
            }
        }
        bgFramesBuilt += 1
        if bgFramesBuilt >= DetectionConstants.bgFramesNeeded {
            let threshold = UInt16(
                Double(DetectionConstants.bgFramesNeeded) *
                DetectionConstants.bgStaticFractionThreshold
            )
            var mask = [UInt8](repeating: 0, count: w * h)
            for i in 0..<(w * h) where bgAccum![i] >= threshold {
                mask[i] = 1
            }
            bgMask = mask
            bgAccum = nil
        }
    }

    // MARK: - Detection

    private func findBall(pixels: [UInt8], scanFraction: CGFloat, timestampMs: Double) -> DetectedBall? {
        guard let mask = bgMask else { return nil }
        // Collect ball-colored pixels that aren't in the static background mask.
        var pts = [UInt16]()      // flat (x, y) pairs for speed
        pts.reserveCapacity(512)
        for y in 0..<h {
            let rowBase = y * w
            for x in 0..<w {
                let maskIdx = rowBase + x
                if mask[maskIdx] != 0 { continue }
                let i = maskIdx * 4
                if Self.isBallColor(r: pixels[i], g: pixels[i + 1], b: pixels[i + 2]) {
                    pts.append(UInt16(x))
                    pts.append(UInt16(y))
                }
            }
        }
        if pts.count < 6 { return nil }  // need at least 3 points

        // Grid cluster with 10-px cells.
        let cellSize = 10
        struct Cell {
            var sumX = 0
            var sumY = 0
            var count = 0
            var cellX = 0
            var cellY = 0
        }
        var grid = [Int64: Cell]()
        let cellsWide = (w + cellSize - 1) / cellSize
        var pi = 0
        while pi < pts.count {
            let px = Int(pts[pi])
            let py = Int(pts[pi + 1])
            let cx = px / cellSize
            let cy = py / cellSize
            let key = Int64(cy) * Int64(cellsWide) + Int64(cx)
            if var cell = grid[key] {
                cell.sumX += px
                cell.sumY += py
                cell.count += 1
                grid[key] = cell
            } else {
                grid[key] = Cell(sumX: px, sumY: py, count: 1, cellX: cx, cellY: cy)
            }
            pi += 2
        }

        let denseCells = grid.values.filter { $0.count >= 2 }.sorted { $0.count > $1.count }
        if denseCells.isEmpty { return nil }

        // BFS-merge nearby cells (within ±2 cells) into clusters.
        var used = Set<Int>()
        struct Cluster {
            var cells: [Cell]
            var totalCount: Int
            var avgX: Double
            var avgY: Double
            var bboxW: Int
            var bboxH: Int
        }
        var clusters: [Cluster] = []
        for (i, seed) in denseCells.enumerated() where !used.contains(i) {
            used.insert(i)
            var members = [seed]
            var qi = 0
            while qi < members.count {
                let c = members[qi]
                qi += 1
                for (j, candidate) in denseCells.enumerated() where !used.contains(j) {
                    if abs(candidate.cellX - c.cellX) <= 2 && abs(candidate.cellY - c.cellY) <= 2 {
                        members.append(candidate)
                        used.insert(j)
                    }
                }
            }
            var total = 0, sx = 0, sy = 0
            var minX = Int.max, maxX = Int.min, minY = Int.max, maxY = Int.min
            for cell in members {
                total += cell.count
                sx += cell.sumX
                sy += cell.sumY
                minX = min(minX, cell.cellX); maxX = max(maxX, cell.cellX)
                minY = min(minY, cell.cellY); maxY = max(maxY, cell.cellY)
            }
            clusters.append(Cluster(
                cells: members,
                totalCount: total,
                avgX: Double(sx) / Double(total),
                avgY: Double(sy) / Double(total),
                bboxW: (maxX - minX + 1) * cellSize,
                bboxH: (maxY - minY + 1) * cellSize
            ))
        }

        // Pick most compact, dense cluster.
        let scored = clusters.compactMap { cluster -> (Cluster, Double)? in
            guard cluster.totalCount >= 4 else { return nil }
            let maxDim = max(cluster.bboxW, cluster.bboxH)
            let minDim = max(1, min(cluster.bboxW, cluster.bboxH))
            let aspect = Double(maxDim) / Double(minDim)
            if aspect > 3.0 { return nil }               // reject long smears
            if maxDim > 140 { return nil }               // reject huge blobs
            // Confidence: density / area, penalize non-square shape.
            let density = Double(cluster.totalCount) / Double(max(1, maxDim * minDim))
            let squareness = 1.0 - min(1.0, (aspect - 1.0) / 2.0)
            let conf = min(1.0, density * 6.0) * squareness
            return (cluster, conf)
        }.sorted { $0.1 > $1.1 }

        guard let best = scored.first else { return nil }
        let cluster = best.0
        let confidence = best.1

        let radiusPx = Double(max(cluster.bboxW, cluster.bboxH)) / 2.0
        return DetectedBall(
            positionNormalized: CGPoint(
                x: cluster.avgX / Double(w),
                y: (cluster.avgY / Double(h)) * Double(scanFraction)
            ),
            radiusNormalized: CGFloat(radiusPx / Double(w)),
            confidence: confidence,
            timestampMs: timestampMs
        )
    }

    // MARK: - HSV + RGB rules (port of isBallColor)

    /// Port of `isBallColor(r, g, b)` — five-rule classifier that's resilient to
    /// lighting and ball wear. Returns true if a pixel plausibly belongs to a
    /// basketball.
    static func isBallColor(r: UInt8, g: UInt8, b: UInt8) -> Bool {
        let rI = Int(r), gI = Int(g), bI = Int(b)
        let maxC = max(rI, max(gI, bI))
        let minC = min(rI, min(gI, bI))
        let delta = maxC - minC
        let sat: Double = maxC == 0 ? 0 : Double(delta) / Double(maxC)
        let val: Double = Double(maxC) / 255.0
        var hue: Double = 0
        if delta > 0 {
            if maxC == rI {
                hue = 60.0 * (Double(gI - bI) / Double(delta)).truncatingRemainder(dividingBy: 6)
            } else if maxC == gI {
                hue = 60.0 * (Double(bI - rI) / Double(delta) + 2)
            } else {
                hue = 60.0 * (Double(rI - gI) / Double(delta) + 4)
            }
            if hue < 0 { hue += 360 }
        }

        if hue >= 8 && hue <= 42 && sat >= 0.15 && val >= 0.35 && rI > gI && rI > bI { return true }
        if hue >= 5 && hue <= 50 && sat >= 0.30 && val >= 0.40 { return true }
        if rI > 160 && gI > 50 && gI < 190 && bI < 120 && rI > gI && Double(rI) > Double(bI) * 1.5 { return true }
        if rI > 110 && gI > 70 && gI < 150 && bI > 45 && bI < 125 &&
           Double(rI) > Double(gI) * 1.05 && Double(rI) > Double(bI) * 1.2 && delta > 15 { return true }
        if rI > 95 && gI > 45 && gI < 105 && bI < 88 &&
           Double(rI) > Double(gI) * 1.15 && Double(rI) > Double(bI) * 1.4 { return true }
        return false
    }
}
