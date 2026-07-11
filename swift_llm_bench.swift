#!/usr/bin/env swift
// SwiftLLM CLI Benchmark — compare Qwen3 vs Qwen3.5
// Usage: swift swift_llm_bench.swift

import Foundation
import Accelerate

// ============================================================
// Inline all SwiftLLM components for standalone CLI execution
// ============================================================

// MARK: - GGUF Types

enum GGMLType: UInt32 {
    case f32 = 0, f16 = 1, q4_0 = 2, q4_1 = 3, q5_0 = 6, q5_1 = 7
    case q8_0 = 8, q8_1 = 9, q2_K = 10, q3_K = 11, q4_K = 12
    case q5_K = 13, q6_K = 14, bf16 = 30

    var blockSize: Int {
        switch self {
        case .f32, .f16, .bf16: return 1
        case .q4_0, .q4_1, .q5_0, .q5_1, .q8_0, .q8_1: return 32
        case .q2_K, .q3_K, .q4_K, .q5_K, .q6_K: return 256
        }
    }
    var bytesPerBlock: Int {
        switch self {
        case .f32: return 4; case .f16, .bf16: return 2
        case .q4_0: return 18; case .q4_1: return 20
        case .q5_0: return 22; case .q5_1: return 24
        case .q8_0: return 34; case .q8_1: return 36
        case .q2_K: return 84; case .q3_K: return 110
        case .q4_K: return 144; case .q5_K: return 176; case .q6_K: return 210
        }
    }
}

enum GGUFValueType: UInt32 {
    case uint8=0,int8=1,uint16=2,int16=3,uint32=4,int32=5,float32=6
    case bool=7,string=8,array=9,uint64=10,int64=11,float64=12
}

enum GGUFValue {
    case uint8(UInt8),int8(Int8),uint16(UInt16),int16(Int16)
    case uint32(UInt32),int32(Int32),float32(Float),bool(Bool)
    case string(String),array([GGUFValue]),uint64(UInt64),int64(Int64),float64(Double)

    var asInt: Int? {
        switch self {
        case .uint32(let v): return Int(v); case .int32(let v): return Int(v)
        case .uint64(let v): return Int(v); case .int64(let v): return Int(v)
        default: return nil
        }
    }
    var asFloat: Float? { if case .float32(let v) = self { return v }; return nil }
    var asString: String? { if case .string(let v) = self { return v }; return nil }
    var asBool: Bool? { if case .bool(let v) = self { return v }; return nil }
}

struct TensorInfo {
    let name: String; let dims: [Int]; let type: GGMLType; let offset: UInt64
    var count: Int { dims.reduce(1, *) }
    var byteSize: Int { (count + type.blockSize - 1) / type.blockSize * type.bytesPerBlock }
}

// MARK: - GGUF Parser

struct GGUFFile {
    let meta: [String: GGUFValue]; let tensors: [String: TensorInfo]
    let dataOffset: UInt64; let data: Data

    var arch: String { meta["general.architecture"]?.asString ?? "unknown" }
    func i(_ k: String) -> Int { meta[k]?.asInt ?? 0 }
    func f(_ k: String) -> Float { meta[k]?.asFloat ?? 0 }

    func tensorBytes(_ t: TensorInfo) -> UnsafeRawBufferPointer {
        let s = Int(dataOffset + t.offset)
        return data.withUnsafeBytes { UnsafeRawBufferPointer(rebasing: $0[s..<s+t.byteSize]) }
    }
}

func parseGGUF(_ url: URL) -> GGUFFile? {
    guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
    var off = 0
    func r<T>(_ t: T.Type) -> T { let v = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: off, as: t) }; off += MemoryLayout<T>.size; return v }
    func rStr() -> String { let n = Int(r(UInt64.self)); let s = String(data: data[off..<off+n], encoding: .utf8) ?? ""; off += n; return s }
    func rVal() -> GGUFValue {
        let t = GGUFValueType(rawValue: r(UInt32.self))!
        switch t {
        case .uint8: return .uint8(r(UInt8.self)); case .int8: return .int8(r(Int8.self))
        case .uint32: return .uint32(r(UInt32.self)); case .int32: return .int32(r(Int32.self))
        case .float32: return .float32(r(Float.self)); case .bool: return .bool(r(UInt8.self) != 0)
        case .string: return .string(rStr())
        case .uint64: return .uint64(r(UInt64.self)); case .int64: return .int64(r(Int64.self))
        case .float64: return .float64(r(Double.self))
        case .uint16: return .uint16(r(UInt16.self)); case .int16: return .int16(r(Int16.self))
        case .array:
            let et = GGUFValueType(rawValue: r(UInt32.self))!; let c = Int(r(UInt64.self))
            var a = [GGUFValue]()
            for _ in 0..<c {
                switch et {
                case .string: a.append(.string(rStr())); case .uint32: a.append(.uint32(r(UInt32.self)))
                case .int32: a.append(.int32(r(Int32.self))); case .float32: a.append(.float32(r(Float.self)))
                case .uint8: a.append(.uint8(r(UInt8.self))); case .bool: a.append(.bool(r(UInt8.self) != 0))
                default: break
                }
            }
            return .array(a)
        }
    }

    let magic = r(UInt32.self); guard magic == 0x46554747 else { return nil }
    let ver = r(UInt32.self); guard ver >= 2 else { return nil }
    let nTensors = Int(r(UInt64.self)); let nMeta = Int(r(UInt64.self))

    var meta = [String: GGUFValue]()
    for _ in 0..<nMeta { let k = rStr(); meta[k] = rVal() }

    var tensors = [String: TensorInfo]()
    for _ in 0..<nTensors {
        let name = rStr(); let nd = Int(r(UInt32.self))
        var dims = [Int](); for _ in 0..<nd { dims.append(Int(r(UInt64.self))) }
        let type = GGMLType(rawValue: r(UInt32.self)) ?? .f32
        let toff = r(UInt64.self)
        tensors[name] = TensorInfo(name: name, dims: dims, type: type, offset: toff)
    }

    let align = meta["general.alignment"]?.asInt ?? 32
    let doff = UInt64((off + align - 1) / align * align)
    return GGUFFile(meta: meta, tensors: tensors, dataOffset: doff, data: data)
}

// MARK: - Float16

@inline(__always) func f16(_ h: UInt16) -> Float {
    var f16 = h; var f32: Float = 0
    withUnsafeMutablePointer(to: &f16) { s in
        withUnsafeMutablePointer(to: &f32) { d in
            var sb = vImage_Buffer(data: s, height: 1, width: 1, rowBytes: 2)
            var db = vImage_Buffer(data: d, height: 1, width: 1, rowBytes: 4)
            vImageConvert_Planar16FtoPlanarF(&sb, &db, 0)
        }
    }
    return f32
}

// MARK: - Dequantize

func deqQ4K(_ raw: UnsafeRawBufferPointer, n: Int) -> [Float] {
    let bs = 256, bpb = 144, nb = n / bs
    var out = [Float](repeating: 0, count: n)
    raw.withUnsafeBytes { p in
        for b in 0..<nb {
            let bo = b * bpb, oo = b * bs
            let d = f16(p.loadUnaligned(fromByteOffset: bo, as: UInt16.self))
            let dm = f16(p.loadUnaligned(fromByteOffset: bo+2, as: UInt16.self))
            let sb = (p.baseAddress! + bo + 4).assumingMemoryBound(to: UInt8.self)
            let qs = (p.baseAddress! + bo + 16).assumingMemoryBound(to: UInt8.self)
            var sc = [UInt8](repeating: 0, count: 8), mn = [UInt8](repeating: 0, count: 8)
            for j in 0..<4 { sc[j] = sb[j] & 63; mn[j] = sb[j+4] & 63 }
            for j in 0..<4 {
                sc[j+4] = (sb[8+j] & 0xF) | ((sb[j] >> 6) << 4)
                mn[j+4] = (sb[8+j] >> 4) | ((sb[j+4] >> 6) << 4)
            }
            for j in 0..<8 {
                let s = d * Float(sc[j]), m = dm * Float(mn[j])
                for k in 0..<16 {
                    let q = qs[j*16+k]
                    out[oo+j*32+k] = s * Float(q & 0xF) - m
                    out[oo+j*32+k+16] = s * Float(q >> 4) - m
                }
            }
        }
    }
    return out
}

func deqQ6K(_ raw: UnsafeRawBufferPointer, n: Int) -> [Float] {
    let bs = 256, bpb = 210, nb = n / bs
    var out = [Float](repeating: 0, count: n)
    raw.withUnsafeBytes { p in
        for b in 0..<nb {
            let bo = b * bpb, oo = b * bs
            let ql = (p.baseAddress! + bo).assumingMemoryBound(to: UInt8.self)
            let qh = (p.baseAddress! + bo + 128).assumingMemoryBound(to: UInt8.self)
            let sc = (p.baseAddress! + bo + 192).assumingMemoryBound(to: Int8.self)
            let d = f16(p.loadUnaligned(fromByteOffset: bo + 208, as: UInt16.self))
            for j in 0..<16 {
                let s = d * Float(sc[j])
                for k in 0..<16 {
                    let idx = j * 16 + k
                    let q4 = (idx % 2 == 0) ? (ql[idx/2] & 0xF) : (ql[idx/2] >> 4)
                    let q2 = (qh[idx/4] >> ((idx % 4) * 2)) & 3
                    out[oo + idx] = s * Float(Int(q4) | (Int(q2) << 4) - 32)
                }
            }
        }
    }
    return out
}

func deqQ8_0(_ raw: UnsafeRawBufferPointer, n: Int) -> [Float] {
    let nb = n / 32
    var out = [Float](repeating: 0, count: n)
    raw.withUnsafeBytes { p in
        for b in 0..<nb {
            let d = f16(p.loadUnaligned(fromByteOffset: b*34, as: UInt16.self))
            let qs = (p.baseAddress! + b*34 + 2).assumingMemoryBound(to: Int8.self)
            for k in 0..<32 { out[b*32+k] = d * Float(qs[k]) }
        }
    }
    return out
}

func deqF32(_ raw: UnsafeRawBufferPointer, n: Int) -> [Float] {
    var out = [Float](repeating: 0, count: n)
    raw.withUnsafeBytes { p in
        memcpy(&out, p.baseAddress!, n * 4)
    }
    return out
}

func deq(_ raw: UnsafeRawBufferPointer, t: GGMLType, n: Int) -> [Float] {
    switch t {
    case .f32: return deqF32(raw, n: n)
    case .q4_K: return deqQ4K(raw, n: n)
    case .q6_K: return deqQ6K(raw, n: n)
    case .q8_0: return deqQ8_0(raw, n: n)
    default: print("⚠️ Unsupported: \(t)"); return [Float](repeating: 0, count: n)
    }
}

// MARK: - Vector Ops

// GGUF dims: [inner, outer]. In row-major: W[outer][inner] = W[out_features][in_features]
// Standard matmul: y[out] = W[out, in] @ x[in] → NoTrans
func matvec(_ A: UnsafePointer<Float>, _ x: UnsafePointer<Float>, _ y: UnsafeMutablePointer<Float>, r: Int, c: Int) {
    cblas_sgemv(CblasRowMajor, CblasNoTrans, Int32(r), Int32(c), 1, A, Int32(c), x, 1, 0, y, 1)
}

func rmsNorm(_ x: UnsafePointer<Float>, _ w: UnsafePointer<Float>, _ y: UnsafeMutablePointer<Float>, n: Int, eps: Float) {
    var ss: Float = 0; vDSP_dotpr(x, 1, x, 1, &ss, vDSP_Length(n))
    var s = 1.0 / sqrtf(ss / Float(n) + eps)
    vDSP_vsmul(x, 1, &s, y, 1, vDSP_Length(n))
    vDSP_vmul(y, 1, w, 1, y, 1, vDSP_Length(n))
}

func softmax(_ x: UnsafeMutablePointer<Float>, n: Int) {
    var mx: Float = -.infinity; vDSP_maxv(x, 1, &mx, vDSP_Length(n))
    var nm = -mx; vDSP_vsadd(x, 1, &nm, x, 1, vDSP_Length(n))
    var nn = Int32(n); vvexpf(x, x, &nn)
    var sm: Float = 0; vDSP_sve(x, 1, &sm, vDSP_Length(n))
    var is_ = 1/sm; vDSP_vsmul(x, 1, &is_, x, 1, vDSP_Length(n))
}

func silu(_ x: UnsafePointer<Float>, _ y: UnsafeMutablePointer<Float>, n: Int) {
    var neg: Float = -1; vDSP_vsmul(x, 1, &neg, y, 1, vDSP_Length(n))
    var nn = Int32(n); vvexpf(y, y, &nn)
    var one: Float = 1; vDSP_vsadd(y, 1, &one, y, 1, vDSP_Length(n))
    vvrecf(y, y, &nn)
    vDSP_vmul(x, 1, y, 1, y, 1, vDSP_Length(n))
}

// RoPE neox style (half-split): rotate (x[i], x[i + half]) together
func rope(_ x: UnsafeMutablePointer<Float>, hd: Int, pos: Int, base: Float, nh: Int) {
    let half = hd / 2
    for h in 0..<nh {
        let o = h * hd
        for i in 0..<half {
            let freq = 1.0 / powf(base, Float(2*i) / Float(hd))
            let theta = Float(pos) * freq
            let c = cosf(theta), s = sinf(theta)
            let x0 = x[o+i], x1 = x[o+half+i]
            x[o+i] = x0*c - x1*s; x[o+half+i] = x0*s + x1*c
        }
    }
}

// MARK: - Transformer

struct LW { // Layer Weights
    let an: [Float]; let fn: [Float]
    let wq: [Float]; let wk: [Float]; let wv: [Float]; let wo: [Float]
    let wg: [Float]; let wu: [Float]; let wd: [Float]
    let qn: [Float]?; let kn: [Float]?
}

class TF { // Transformer
    let nl: Int; let nh: Int; let nkv: Int; let ed: Int; let hd: Int; let fd: Int; let vs: Int
    let eps: Float; let rb: Float
    let te: [Float]; let on: [Float]; let ow: [Float]?; let layers: [LW]
    var kc: [[Float]]; var vc: [[Float]]

    var gqa: Int { nh / nkv }

    init(g: GGUFFile) {
        let a = g.arch
        nl = g.i("\(a).block_count"); nh = g.i("\(a).attention.head_count")
        nkv = g.i("\(a).attention.head_count_kv"); ed = g.i("\(a).embedding_length")
        let keyLen = g.i("\(a).attention.key_length")
        hd = keyLen > 0 ? keyLen : ed / nh
        fd = g.i("\(a).feed_forward_length")
        eps = g.f("\(a).attention.layer_norm_rms_epsilon"); rb = g.f("\(a).rope.freq_base")

        // Vocab
        if case .array(let arr) = g.meta["tokenizer.ggml.tokens"] ?? .uint32(0) { vs = arr.count } else { vs = 0 }

        func ld(_ n: String) -> [Float] {
            guard let t = g.tensors[n] else { print("❌ Missing: \(n)"); return [] }
            return deq(g.tensorBytes(t), t: t.type, n: t.count)
        }

        print("  Loading embeddings...")
        te = ld("token_embd.weight"); on = ld("output_norm.weight")
        ow = g.tensors["output.weight"] != nil ? ld("output.weight") : nil

        var ls = [LW]()
        for i in 0..<nl {
            let p = "blk.\(i)"
            if i % 7 == 0 { print("  Loading layer \(i)/\(nl)...") }
            let qn: [Float]? = g.tensors["\(p).attn_q_norm.weight"] != nil ? ld("\(p).attn_q_norm.weight") : nil
            let kn: [Float]? = g.tensors["\(p).attn_k_norm.weight"] != nil ? ld("\(p).attn_k_norm.weight") : nil
            ls.append(LW(
                an: ld("\(p).attn_norm.weight"), fn: ld("\(p).ffn_norm.weight"),
                wq: ld("\(p).attn_q.weight"), wk: ld("\(p).attn_k.weight"),
                wv: ld("\(p).attn_v.weight"), wo: ld("\(p).attn_output.weight"),
                wg: ld("\(p).ffn_gate.weight"), wu: ld("\(p).ffn_up.weight"),
                wd: ld("\(p).ffn_down.weight"), qn: qn, kn: kn
            ))
        }
        layers = ls
        kc = Array(repeating: [], count: nl); vc = Array(repeating: [], count: nl)
    }

    func clear() { for i in 0..<nl { kc[i] = []; vc[i] = [] } }

    func forward(_ tid: Int, pos: Int) -> [Float] {
        var h = [Float](repeating: 0, count: ed)
        te.withUnsafeBufferPointer { src in
            h.withUnsafeMutableBufferPointer { dst in
                memcpy(dst.baseAddress!, src.baseAddress! + tid * ed, ed * 4)
            }
        }

        var nm = [Float](repeating: 0, count: ed)
        var q = [Float](repeating: 0, count: nh*hd), k = [Float](repeating: 0, count: nkv*hd), v = [Float](repeating: 0, count: nkv*hd)
        var ao = [Float](repeating: 0, count: nh*hd)
        var gt = [Float](repeating: 0, count: fd), up = [Float](repeating: 0, count: fd), sb = [Float](repeating: 0, count: fd)
        var fo = [Float](repeating: 0, count: ed)

        for li in 0..<nl {
            let w = layers[li]
            rmsNorm(&h, w.an, &nm, n: ed, eps: eps)
            matvec(w.wq, nm, &q, r: nh*hd, c: ed)
            matvec(w.wk, nm, &k, r: nkv*hd, c: ed)
            matvec(w.wv, nm, &v, r: nkv*hd, c: ed)

            // QK norm (applied before RoPE)
            if let qnw = w.qn, let knw = w.kn {
                q.withUnsafeMutableBufferPointer { qp in
                    for hi in 0..<nh {
                        var tmp = [Float](repeating: 0, count: hd)
                        rmsNorm(qp.baseAddress! + hi*hd, qnw, &tmp, n: hd, eps: eps)
                        memcpy(qp.baseAddress! + hi*hd, tmp, hd * 4)
                    }
                }
                k.withUnsafeMutableBufferPointer { kp in
                    for hi in 0..<nkv {
                        var tmp = [Float](repeating: 0, count: hd)
                        rmsNorm(kp.baseAddress! + hi*hd, knw, &tmp, n: hd, eps: eps)
                        memcpy(kp.baseAddress! + hi*hd, tmp, hd * 4)
                    }
                }
            }

            rope(&q, hd: hd, pos: pos, base: rb, nh: nh)
            rope(&k, hd: hd, pos: pos, base: rb, nh: nkv)

            kc[li].append(contentsOf: k); vc[li].append(contentsOf: v)

            let sl = pos + 1; let sc = 1.0 / sqrtf(Float(hd))
            ao = [Float](repeating: 0, count: nh*hd)
            var scores = [Float](repeating: 0, count: sl)

            q.withUnsafeBufferPointer { qp in
                ao.withUnsafeMutableBufferPointer { aop in
                    kc[li].withUnsafeBufferPointer { kcp in
                        vc[li].withUnsafeBufferPointer { vcp in
                            for hi in 0..<nh {
                                let kvh = hi / gqa
                                for p in 0..<sl {
                                    var d: Float = 0
                                    vDSP_dotpr(qp.baseAddress! + hi*hd, 1,
                                               kcp.baseAddress! + p*nkv*hd + kvh*hd, 1,
                                               &d, vDSP_Length(hd))
                                    scores[p] = d * sc
                                }
                                softmax(&scores, n: sl)
                                for p in 0..<sl {
                                    var s = scores[p]
                                    vDSP_vsma(vcp.baseAddress! + p*nkv*hd + kvh*hd, 1, &s,
                                              aop.baseAddress! + hi*hd, 1,
                                              aop.baseAddress! + hi*hd, 1, vDSP_Length(hd))
                                }
                            }
                        }
                    }
                }
            }

            var ap = [Float](repeating: 0, count: ed)
            matvec(w.wo, ao, &ap, r: ed, c: nh*hd)
            vDSP_vadd(h, 1, ap, 1, &h, 1, vDSP_Length(ed))

            rmsNorm(h, w.fn, &nm, n: ed, eps: eps)
            matvec(w.wg, nm, &gt, r: fd, c: ed)
            matvec(w.wu, nm, &up, r: fd, c: ed)
            silu(gt, &sb, n: fd)
            vDSP_vmul(sb, 1, up, 1, &sb, 1, vDSP_Length(fd))
            matvec(w.wd, sb, &fo, r: ed, c: fd)
            vDSP_vadd(h, 1, fo, 1, &h, 1, vDSP_Length(ed))
        }

        rmsNorm(h, on, &nm, n: ed, eps: eps)
        let outw = ow ?? te
        var logits = [Float](repeating: 0, count: vs)
        matvec(outw, nm, &logits, r: vs, c: ed)
        return logits
    }
}

// MARK: - Tokenizer (simplified)

class Tok {
    let vocab: [String]; let v2i: [String: Int]; let mergeR: [String: Int]; let eos: Int
    static let be: [UInt8: Character] = {
        var m = [UInt8: Character](); var n = 256
        for b in UInt8(33)...126 { m[b] = Character(UnicodeScalar(b)) }
        for b in UInt8(161)...172 { m[b] = Character(UnicodeScalar(b)) }
        for b in UInt8(174)...255 { m[b] = Character(UnicodeScalar(b)) }
        for b in UInt8(0)...255 { if m[b] == nil { m[b] = Character(UnicodeScalar(n)!); n += 1 } }
        return m
    }()
    static let bd: [Character: UInt8] = { var m = [Character: UInt8](); for (k,v) in be { m[v] = k }; return m }()

    init(_ g: GGUFFile) {
        var t = [String]()
        if case .array(let a) = g.meta["tokenizer.ggml.tokens"] ?? .uint32(0) { t = a.compactMap { $0.asString } }
        vocab = t
        var vi = [String: Int](); for (i,s) in t.enumerated() { vi[s] = i }; v2i = vi
        var mr = [String: Int]()
        if case .array(let a) = g.meta["tokenizer.ggml.merges"] ?? .uint32(0) {
            for (i, v) in a.enumerated() { if let s = v.asString { mr[s] = i } }
        }
        mergeR = mr; eos = g.meta["tokenizer.ggml.eos_token_id"]?.asInt ?? 151645
    }

    // Special tokens that must be matched literally before BPE
    lazy var specialTokens: [(String, Int)] = {
        var st = [(String, Int)]()
        for (i, t) in vocab.enumerated() {
            if t.hasPrefix("<|") && t.hasSuffix("|>") { st.append((t, i)) }
            if t == "<tool_call>" || t == "</tool_call>" { st.append((t, i)) }
        }
        // Sort by length descending for greedy matching
        return st.sorted { $0.0.count > $1.0.count }
    }()

    func encode(_ text: String) -> [Int] {
        // Split on special tokens first
        var tokens = [Int]()
        var remaining = text
        while !remaining.isEmpty {
            var foundSpecial = false
            for (st, id) in specialTokens {
                if remaining.hasPrefix(st) {
                    tokens.append(id)
                    remaining = String(remaining.dropFirst(st.count))
                    foundSpecial = true
                    break
                }
            }
            if foundSpecial { continue }

            // Find next special token position
            var nextSpecialIdx = remaining.endIndex
            for (st, _) in specialTokens {
                if let range = remaining.range(of: st) {
                    if range.lowerBound < nextSpecialIdx { nextSpecialIdx = range.lowerBound }
                }
            }

            // BPE encode the text before next special token
            let piece = String(remaining[remaining.startIndex..<nextSpecialIdx])
            remaining = String(remaining[nextSpecialIdx...])
            if !piece.isEmpty {
                tokens.append(contentsOf: bpeEncode(piece))
            }
        }
        return tokens
    }

    private func bpeEncode(_ text: String) -> [Int] {
        let enc = String(text.utf8.map { Self.be[$0] ?? Character(UnicodeScalar($0)) })
        var syms = enc.map { String($0) }
        if syms.count <= 1 { return syms.compactMap { v2i[$0] } }
        while syms.count > 1 {
            var best = Int.max, bi = -1
            for i in 0..<syms.count-1 {
                if let r = mergeR["\(syms[i]) \(syms[i+1])"], r < best { best = r; bi = i }
            }
            if bi < 0 { break }
            syms[bi] = syms[bi] + syms[bi+1]; syms.remove(at: bi+1)
        }
        return syms.compactMap { v2i[$0] }
    }

    func decode(_ ids: [Int]) -> String {
        let bytes = ids.flatMap { id -> [UInt8] in
            guard id >= 0 && id < vocab.count else { return [] }
            return vocab[id].map { Self.bd[$0] ?? UInt8($0.asciiValue ?? 0) }
        }
        return String(bytes: bytes, encoding: .utf8) ?? ""
    }
    func decode1(_ id: Int) -> String { decode([id]) }
}

// MARK: - Benchmark

func bench(_ path: String, label: String) {
    print("\n" + String(repeating: "=", count: 60))
    print("📊 \(label)")
    print("   File: \(path)")
    print(String(repeating: "=", count: 60))

    let url = URL(fileURLWithPath: path)
    guard FileManager.default.fileExists(atPath: path) else { print("❌ File not found"); return }

    // 1. Parse
    let t0 = CFAbsoluteTimeGetCurrent()
    guard let g = parseGGUF(url) else { print("❌ Parse failed"); return }
    let parseTime = CFAbsoluteTimeGetCurrent() - t0
    print("✅ Parsed in \(String(format: "%.2f", parseTime))s")
    print("   Arch: \(g.arch), Layers: \(g.i("\(g.arch).block_count")), Embd: \(g.i("\(g.arch).embedding_length"))")

    // 2. Load weights
    let t1 = CFAbsoluteTimeGetCurrent()
    let tok = Tok(g)
    let tf = TF(g: g)
    let loadTime = CFAbsoluteTimeGetCurrent() - t1
    print("✅ Weights loaded in \(String(format: "%.2f", loadTime))s, vocab=\(tok.vocab.count)")

    // 3. Tokenizer test
    let testStr = "Hello! こんにちは"
    let ids = tok.encode(testStr)
    let dec = tok.decode(ids)
    print("✅ Tokenizer: '\(testStr)' → \(ids.count) tokens → '\(dec)' \(dec == testStr ? "✅" : "❌")")

    // 3b. Simple next-token test
    let simplePrompt = "1+1="
    let simpleToks = tok.encode(simplePrompt)
    print("\n🔬 Simple test: '\(simplePrompt)' → tokens: \(simpleToks)")
    tf.clear()
    var simpleLogits = [Float]()
    for (i, tid) in simpleToks.enumerated() { simpleLogits = tf.forward(tid, pos: i) }
    // Top 5
    var indexed = simpleLogits.enumerated().map { ($0.offset, $0.element) }
    indexed.sort { $0.1 > $1.1 }
    print("   Top 5 predictions:")
    for item in indexed.prefix(5) {
        let decoded = tok.decode1(item.0)
        print("     id=\(item.0) tok='\(decoded)' logit=\(String(format: "%.2f", item.1))")
    }
    print("   Logit stats: min=\(String(format: "%.2f", simpleLogits.min()!)) max=\(String(format: "%.2f", simpleLogits.max()!)) mean=\(String(format: "%.4f", simpleLogits.reduce(0,+)/Float(simpleLogits.count)))")

    // 4. Generation test (greedy)
    let prompt = "<|im_start|>system\nYou are a helpful assistant.<|im_end|>\n<|im_start|>user\nWhat is 2+2?<|im_end|>\n<|im_start|>assistant\n<think>\n</think>\n"
    let promptToks = tok.encode(prompt)
    print("\n🔄 Generating (greedy, max 60 tokens)...")
    print("   Prompt: \(promptToks.count) tokens")

    tf.clear()

    // Prefill: process all prompt tokens, keep logits from last
    let t2 = CFAbsoluteTimeGetCurrent()
    var lastLogits = [Float]()
    for (i, tid) in promptToks.enumerated() {
        lastLogits = tf.forward(tid, pos: i)
    }
    let prefillTime = CFAbsoluteTimeGetCurrent() - t2
    let prefillTPS = Double(promptToks.count) / prefillTime
    print("   Prefill: \(String(format: "%.2f", prefillTime))s (\(String(format: "%.1f", prefillTPS)) t/s)")

    // Decode
    let t3 = CFAbsoluteTimeGetCurrent()
    var allToks = promptToks
    var output = ""
    var pos = promptToks.count

    for _ in 0..<60 {
        var logits = lastLogits
        // Greedy
        var mx: Float = -.infinity; var mi: vDSP_Length = 0
        vDSP_maxvi(&logits, 1, &mx, &mi, vDSP_Length(logits.count))
        let next = Int(mi)
        if next == tok.eos { break }
        allToks.append(next)
        output += tok.decode1(next)

        // Forward next token to get new logits
        lastLogits = tf.forward(next, pos: pos)
        pos += 1

        // Check stop
        if output.contains("<|im_end|>") {
            output = output.replacingOccurrences(of: "<|im_end|>", with: "")
            break
        }
    }
    let decodeTime = CFAbsoluteTimeGetCurrent() - t3
    let genCount = allToks.count - promptToks.count
    let decodeTPS = Double(genCount) / decodeTime
    print("   Decode:  \(String(format: "%.2f", decodeTime))s, \(genCount) tokens (\(String(format: "%.1f", decodeTPS)) t/s)")
    print("   Output:  '\(output.prefix(200))'")
    print("   Contains '4': \(output.contains("4") ? "✅" : "⚠️")")

    // Summary
    print("\n📋 Summary for \(label):")
    print("   Load:    \(String(format: "%.1f", loadTime))s")
    print("   Prefill: \(String(format: "%.1f", prefillTPS)) t/s")
    print("   Decode:  \(String(format: "%.1f", decodeTPS)) t/s")
    let fileSize = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int) ?? 0
    print("   Memory:  ~\(fileSize / 1048576) MB (file)")
}

// MARK: - Main

let models = [
    ("/Users/yuki/Library/Application Support/Koe/llm-models/Qwen3-0.6B-Q8_0.gguf", "Qwen3-0.6B (Q8_0)"),
]

print("🚀 SwiftLLM Benchmark — Pure Swift Inference Engine")
print("   Platform: macOS, CPU: Accelerate/vDSP/BLAS")
print("   Date: \(Date())")

for (path, label) in models {
    autoreleasepool {
        bench(path, label: label)
    }
}

print("\n" + String(repeating: "=", count: 60))
print("🏁 Benchmark complete!")
print(String(repeating: "=", count: 60))
String(repeating: "=", count: 60))
print("🏁 Benchmark complete!")
print(String(repeating: "=", count: 60))
