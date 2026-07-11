import Foundation
import Accelerate

// MARK: - Tensor Operations
// Pure Swift + Accelerate tensor operations for transformer inference

/// Simple contiguous float tensor
struct Tensor {
    var data: [Float]
    let shape: [Int]

    var count: Int { data.count }
    var rows: Int { shape.count >= 2 ? shape[0] : 1 }
    var cols: Int { shape.count >= 2 ? shape[1] : shape[0] }

    init(shape: [Int], data: [Float]) {
        self.shape = shape
        self.data = data
    }

    init(zeros shape: [Int]) {
        self.shape = shape
        self.data = [Float](repeating: 0, count: shape.reduce(1, *))
    }

    init(shape: [Int], repeating value: Float) {
        self.shape = shape
        self.data = [Float](repeating: value, count: shape.reduce(1, *))
    }

    subscript(i: Int) -> Float {
        get { data[i] }
        set { data[i] = newValue }
    }
}

// MARK: - Dequantization

enum Dequantize {

    /// Dequantize Q4_K block to float array
    /// Block structure (256 elements per block, 144 bytes):
    ///   - d: Float16 (2 bytes) - super-block scale
    ///   - dmin: Float16 (2 bytes) - super-block min
    ///   - scales: [12]UInt8 - sub-block scales/mins (6-bit packed)
    ///   - qs: [128]UInt8 - quantized values (4-bit packed)
    static func dequantizeQ4K(_ raw: UnsafeRawBufferPointer, count: Int) -> [Float] {
        let blockSize = 256
        let bytesPerBlock = 144
        let numBlocks = count / blockSize
        var output = [Float](repeating: 0, count: count)

        raw.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) in
            for block in 0..<numBlocks {
                let blockStart = block * bytesPerBlock
                let outStart = block * blockSize

                // Read d and dmin as Float16
                let dRaw = ptr.loadUnaligned(fromByteOffset: blockStart, as: UInt16.self)
                let dminRaw = ptr.loadUnaligned(fromByteOffset: blockStart + 2, as: UInt16.self)
                let d = float16ToFloat(dRaw)
                let dmin = float16ToFloat(dminRaw)

                // Read scales (12 bytes at offset 4)
                let scalesPtr = ptr.baseAddress! + blockStart + 4

                // Read quantized values (128 bytes at offset 16)
                let qsPtr = (ptr.baseAddress! + blockStart + 16).assumingMemoryBound(to: UInt8.self)

                // Decode 6-bit scales/mins from 12 bytes
                // The 12 bytes encode 8 scales (6-bit each) and 8 mins (6-bit each)
                var scales = [UInt8](repeating: 0, count: 8)
                var mins = [UInt8](repeating: 0, count: 8)
                let sb = scalesPtr.assumingMemoryBound(to: UInt8.self)

                // First 4 sub-blocks: lower 6 bits from bytes 0-7
                for j in 0..<4 {
                    scales[j] = sb[j] & 63
                    mins[j] = sb[j + 4] & 63
                }
                // Last 4 sub-blocks: combine bits from bytes 0-7 (upper 2) and bytes 8-11
                for j in 0..<4 {
                    let upper2_scale = (sb[j] >> 6) & 3
                    let upper2_min = (sb[j + 4] >> 6) & 3
                    scales[j + 4] = (sb[8 + j] & 0xF) | (upper2_scale << 4)
                    mins[j + 4] = (sb[8 + j] >> 4) | (upper2_min << 4)
                }

                // Dequantize 256 values in 8 sub-blocks of 32
                for j in 0..<8 {
                    let sc = d * Float(scales[j])
                    let mn = dmin * Float(mins[j])
                    let qOffset = j * 16  // 32 values = 16 bytes (4-bit packed)

                    for k in 0..<16 {
                        let qByte = qsPtr[qOffset + k]
                        let lo = Float(qByte & 0xF)
                        let hi = Float(qByte >> 4)
                        output[outStart + j * 32 + k] = sc * lo - mn
                        output[outStart + j * 32 + k + 16] = sc * hi - mn
                    }
                }
            }
        }
        return output
    }

    /// Dequantize Q6_K block to float array
    /// Block structure (256 elements per block, 210 bytes)
    static func dequantizeQ6K(_ raw: UnsafeRawBufferPointer, count: Int) -> [Float] {
        let blockSize = 256
        let bytesPerBlock = 210
        let numBlocks = count / blockSize
        var output = [Float](repeating: 0, count: count)

        raw.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) in
            for block in 0..<numBlocks {
                let blockStart = block * bytesPerBlock
                let outStart = block * blockSize

                // Layout: ql[128] + qh[64] + scales[16] + d[2]
                let qlPtr = (ptr.baseAddress! + blockStart).assumingMemoryBound(to: UInt8.self)
                let qhPtr = (ptr.baseAddress! + blockStart + 128).assumingMemoryBound(to: UInt8.self)
                let scPtr = (ptr.baseAddress! + blockStart + 192).assumingMemoryBound(to: Int8.self)
                let dRaw = ptr.loadUnaligned(fromByteOffset: blockStart + 208, as: UInt16.self)
                let d = float16ToFloat(dRaw)

                for j in 0..<16 {  // 16 sub-blocks of 16 values
                    let sc = d * Float(scPtr[j])
                    for k in 0..<16 {
                        let idx = j * 16 + k
                        let qlIdx = idx / 2
                        let qhIdx = idx / 4

                        // Low 4 bits from ql
                        let qlByte = qlPtr[qlIdx]
                        let q4 = (idx % 2 == 0) ? (qlByte & 0xF) : (qlByte >> 4)

                        // High 2 bits from qh
                        let qhByte = qhPtr[qhIdx]
                        let shift = (idx % 4) * 2
                        let q2 = (qhByte >> shift) & 3

                        let q = Int(q4) | (Int(q2) << 4)
                        output[outStart + idx] = sc * Float(q - 32)
                    }
                }
            }
        }
        return output
    }

    /// Dequantize Q8_0 block to float array
    static func dequantizeQ8_0(_ raw: UnsafeRawBufferPointer, count: Int) -> [Float] {
        let blockSize = 32
        let bytesPerBlock = 34  // 2 (d) + 32 (qs)
        let numBlocks = count / blockSize
        var output = [Float](repeating: 0, count: count)

        raw.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) in
            for block in 0..<numBlocks {
                let blockStart = block * bytesPerBlock
                let outStart = block * blockSize

                let dRaw = ptr.loadUnaligned(fromByteOffset: blockStart, as: UInt16.self)
                let d = float16ToFloat(dRaw)
                let qsPtr = (ptr.baseAddress! + blockStart + 2).assumingMemoryBound(to: Int8.self)

                for k in 0..<32 {
                    output[outStart + k] = d * Float(qsPtr[k])
                }
            }
        }
        return output
    }

    /// Dequantize F32 (no-op copy)
    static func dequantizeF32(_ raw: UnsafeRawBufferPointer, count: Int) -> [Float] {
        var output = [Float](repeating: 0, count: count)
        raw.withUnsafeBytes { ptr in
            let floatPtr = ptr.baseAddress!.assumingMemoryBound(to: Float.self)
            for i in 0..<count {
                output[i] = floatPtr[i]
            }
        }
        return output
    }

    /// Dequantize F16 to F32
    static func dequantizeF16(_ raw: UnsafeRawBufferPointer, count: Int) -> [Float] {
        var output = [Float](repeating: 0, count: count)
        raw.withUnsafeBytes { ptr in
            let f16Ptr = ptr.baseAddress!.assumingMemoryBound(to: UInt16.self)
            for i in 0..<count {
                output[i] = float16ToFloat(f16Ptr[i])
            }
        }
        return output
    }

    /// Generic dequantize based on type
    static func dequantize(_ raw: UnsafeRawBufferPointer, type: GGMLType, count: Int) -> [Float] {
        switch type {
        case .f32: return dequantizeF32(raw, count: count)
        case .f16: return dequantizeF16(raw, count: count)
        case .q4_K: return dequantizeQ4K(raw, count: count)
        case .q6_K: return dequantizeQ6K(raw, count: count)
        case .q8_0: return dequantizeQ8_0(raw, count: count)
        default:
            print("[SwiftLLM] Warning: unsupported quant type \(type), returning zeros")
            return [Float](repeating: 0, count: count)
        }
    }

    // MARK: - Float16 conversion

    @inline(__always)
    static func float16ToFloat(_ h: UInt16) -> Float {
        var f16 = h
        var f32: Float = 0
        withUnsafeMutablePointer(to: &f16) { src in
            withUnsafeMutablePointer(to: &f32) { dst in
                var srcBuf = vImage_Buffer(data: src, height: 1, width: 1, rowBytes: 2)
                var dstBuf = vImage_Buffer(data: dst, height: 1, width: 1, rowBytes: 4)
                vImageConvert_Planar16FtoPlanarF(&srcBuf, &dstBuf, 0)
            }
        }
        return f32
    }
}

// MARK: - Vector / Matrix operations using Accelerate

enum VecOps {

    /// Matrix-vector multiply: y = A * x, where A is (rows x cols), x is (cols,), y is (rows,)
    @inline(__always)
    static func matvec(_ A: UnsafePointer<Float>, _ x: UnsafePointer<Float>,
                       _ y: UnsafeMutablePointer<Float>, rows: Int, cols: Int) {
        cblas_sgemv(CblasRowMajor, CblasNoTrans, Int32(rows), Int32(cols),
                    1.0, A, Int32(cols), x, 1, 0.0, y, 1)
    }

    /// Element-wise multiply: c = a * b
    @inline(__always)
    static func mul(_ a: UnsafePointer<Float>, _ b: UnsafePointer<Float>,
                    _ c: UnsafeMutablePointer<Float>, count: Int) {
        vDSP_vmul(a, 1, b, 1, c, 1, vDSP_Length(count))
    }

    /// Element-wise add: c = a + b
    @inline(__always)
    static func add(_ a: UnsafePointer<Float>, _ b: UnsafePointer<Float>,
                    _ c: UnsafeMutablePointer<Float>, count: Int) {
        vDSP_vadd(a, 1, b, 1, c, 1, vDSP_Length(count))
    }

    /// Scale: y = alpha * x
    @inline(__always)
    static func scale(_ x: UnsafePointer<Float>, _ alpha: Float,
                      _ y: UnsafeMutablePointer<Float>, count: Int) {
        var a = alpha
        vDSP_vsmul(x, 1, &a, y, 1, vDSP_Length(count))
    }

    /// Dot product
    @inline(__always)
    static func dot(_ a: UnsafePointer<Float>, _ b: UnsafePointer<Float>, count: Int) -> Float {
        var result: Float = 0
        vDSP_dotpr(a, 1, b, 1, &result, vDSP_Length(count))
        return result
    }

    /// RMS Norm: y = x * (1/rms) * weight, where rms = sqrt(mean(x^2) + eps)
    static func rmsNorm(_ x: UnsafePointer<Float>, _ weight: UnsafePointer<Float>,
                        _ y: UnsafeMutablePointer<Float>, count: Int, eps: Float) {
        // Compute mean of squares
        var sumSq: Float = 0
        vDSP_dotpr(x, 1, x, 1, &sumSq, vDSP_Length(count))
        let rms = sqrtf(sumSq / Float(count) + eps)
        let scale = 1.0 / rms

        // y = x * scale * weight
        var s = scale
        vDSP_vsmul(x, 1, &s, y, 1, vDSP_Length(count))
        vDSP_vmul(y, 1, weight, 1, y, 1, vDSP_Length(count))
    }

    /// Softmax in-place
    static func softmax(_ x: UnsafeMutablePointer<Float>, count: Int) {
        // Find max for numerical stability
        var maxVal: Float = -Float.infinity
        vDSP_maxv(x, 1, &maxVal, vDSP_Length(count))

        // Subtract max and exponentiate
        var negMax = -maxVal
        vDSP_vsadd(x, 1, &negMax, x, 1, vDSP_Length(count))

        var n = Int32(count)
        vvexpf(x, x, &n)

        // Normalize
        var sum: Float = 0
        vDSP_sve(x, 1, &sum, vDSP_Length(count))
        var invSum = 1.0 / sum
        vDSP_vsmul(x, 1, &invSum, x, 1, vDSP_Length(count))
    }

    /// SiLU activation: silu(x) = x * sigmoid(x)
    static func silu(_ x: UnsafePointer<Float>, _ y: UnsafeMutablePointer<Float>, count: Int) {
        // sigmoid(x) = 1 / (1 + exp(-x))
        var negOne: Float = -1.0
        vDSP_vsmul(x, 1, &negOne, y, 1, vDSP_Length(count))
        var n = Int32(count)
        vvexpf(y, y, &n)
        var one: Float = 1.0
        vDSP_vsadd(y, 1, &one, y, 1, vDSP_Length(count))
        // y = 1.0 / y  (sigmoid)
        vvrecf(y, y, &n)
        // y = x * sigmoid(x)
        vDSP_vmul(x, 1, y, 1, y, 1, vDSP_Length(count))
    }

    /// RoPE: Apply rotary position embedding
    static func applyRoPE(_ x: UnsafeMutablePointer<Float>, headDim: Int, position: Int,
                          ropeFreqBase: Float, nHeads: Int) {
        let halfDim = headDim / 2
        for h in 0..<nHeads {
            let offset = h * headDim
            for i in 0..<halfDim {
                let freq = 1.0 / powf(ropeFreqBase, Float(2 * i) / Float(headDim))
                let theta = Float(position) * freq
                let cosVal = cosf(theta)
                let sinVal = sinf(theta)
                let x0 = x[offset + i]
                let x1 = x[offset + halfDim + i]
                x[offset + i] = x0 * cosVal - x1 * sinVal
                x[offset + halfDim + i] = x0 * sinVal + x1 * cosVal
            }
        }
    }
}
