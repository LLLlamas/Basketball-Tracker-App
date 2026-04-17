import CoreVideo
import CoreGraphics

/// Safe BGRA CVPixelBuffer access. Locks on init, unlocks on deinit.
/// The `Resampled` helpers downsample a region into a fresh buffer so
/// detectors can iterate without worrying about stride or cropping.
final class LockedPixelBuffer {
    let buffer: CVPixelBuffer
    let base: UnsafeMutableRawPointer
    let width: Int
    let height: Int
    let bytesPerRow: Int

    init?(_ buffer: CVPixelBuffer) {
        guard CVPixelBufferLockBaseAddress(buffer, .readOnly) == kCVReturnSuccess,
              let base = CVPixelBufferGetBaseAddress(buffer)
        else { return nil }
        self.buffer = buffer
        self.base = base
        self.width = CVPixelBufferGetWidth(buffer)
        self.height = CVPixelBufferGetHeight(buffer)
        self.bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
    }

    deinit {
        CVPixelBufferUnlockBaseAddress(buffer, .readOnly)
    }

    /// Downsample a region of this BGRA buffer into an RGBA UInt8 array of size
    /// `targetW * targetH * 4`. Uses nearest-neighbor — fast and good enough
    /// for the 64×64 and 360×320 detector inputs.
    func resample(
        sourceRect: CGRect,
        targetW: Int,
        targetH: Int
    ) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: targetW * targetH * 4)
        let sx0 = max(0, Int(sourceRect.minX))
        let sy0 = max(0, Int(sourceRect.minY))
        let sw = max(1, min(width - sx0, Int(sourceRect.width)))
        let sh = max(1, min(height - sy0, Int(sourceRect.height)))
        for ty in 0..<targetH {
            let sy = sy0 + (ty * sh) / targetH
            let srcRow = base.advanced(by: sy * bytesPerRow).assumingMemoryBound(to: UInt8.self)
            for tx in 0..<targetW {
                let sx = sx0 + (tx * sw) / targetW
                let srcIdx = sx * 4
                let dstIdx = (ty * targetW + tx) * 4
                // Source is BGRA; target is RGBA so the downstream code can read index 0 as R.
                out[dstIdx + 0] = srcRow[srcIdx + 2] // R
                out[dstIdx + 1] = srcRow[srcIdx + 1] // G
                out[dstIdx + 2] = srcRow[srcIdx + 0] // B
                out[dstIdx + 3] = srcRow[srcIdx + 3] // A
            }
        }
        return out
    }
}
