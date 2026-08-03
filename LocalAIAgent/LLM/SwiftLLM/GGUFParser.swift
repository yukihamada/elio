import Foundation

// MARK: - GGUF File Parser
// Pure Swift implementation for reading GGUF v3 model files

enum GGMLType: UInt32 {
    case f32 = 0
    case f16 = 1
    case q4_0 = 2
    case q4_1 = 3
    case q5_0 = 6
    case q5_1 = 7
    case q8_0 = 8
    case q8_1 = 9
    case q2_K = 10
    case q3_K = 11
    case q4_K = 12
    case q5_K = 13
    case q6_K = 14
    case iq2_xxs = 16
    case iq2_xs = 17
    case iq3_xxs = 18
    case iq1_s = 19
    case iq4_nl = 20
    case iq3_s = 21
    case iq2_s = 22
    case iq4_xs = 23
    case i8 = 24
    case i16 = 25
    case i32 = 26
    case i64 = 27
    case f64 = 28
    case iq1_m = 29
    case bf16 = 30

    /// Block size for quantized types
    var blockSize: Int {
        switch self {
        case .f32, .i32: return 1
        case .f16, .bf16, .i16: return 1
        case .i8: return 1
        case .q4_0, .q4_1: return 32
        case .q5_0, .q5_1: return 32
        case .q8_0, .q8_1: return 32
        case .q2_K: return 256
        case .q3_K: return 256
        case .q4_K: return 256
        case .q5_K: return 256
        case .q6_K: return 256
        default: return 32
        }
    }

    /// Bytes per block for quantized types
    var bytesPerBlock: Int {
        switch self {
        case .f32: return 4
        case .f16, .bf16: return 2
        case .i8: return 1
        case .i16: return 2
        case .i32: return 4
        case .q4_0: return 18  // 2 + 32/2
        case .q4_1: return 20  // 2 + 2 + 32/2
        case .q5_0: return 22  // 2 + 4 + 32/2
        case .q5_1: return 24  // 2 + 2 + 4 + 32/2
        case .q8_0: return 34  // 2 + 32
        case .q8_1: return 36  // 4 + 4 + 32 (but actually 2+2+32)
        case .q2_K: return 256/16*2 + 256/4 + 2 + 2  // 84
        case .q3_K: return 256/8 + 256/4 + 12 + 2    // 110
        case .q4_K: return 2 + 2 + 12 + 256/2        // 144
        case .q5_K: return 2 + 2 + 12 + 256/8 + 256/2 // 176
        case .q6_K: return 256/2 + 256/4 + 256/16 + 2 // 210
        default: return 0
        }
    }
}

enum GGUFValueType: UInt32 {
    case uint8 = 0
    case int8 = 1
    case uint16 = 2
    case int16 = 3
    case uint32 = 4
    case int32 = 5
    case float32 = 6
    case bool = 7
    case string = 8
    case array = 9
    case uint64 = 10
    case int64 = 11
    case float64 = 12
}

enum GGUFValue {
    case uint8(UInt8)
    case int8(Int8)
    case uint16(UInt16)
    case int16(Int16)
    case uint32(UInt32)
    case int32(Int32)
    case float32(Float)
    case bool(Bool)
    case string(String)
    case array([GGUFValue])
    case uint64(UInt64)
    case int64(Int64)
    case float64(Double)

    var asUInt32: UInt32? {
        switch self {
        case .uint32(let v): return v
        case .int32(let v): return UInt32(v)
        case .uint64(let v): return UInt32(v)
        default: return nil
        }
    }

    var asInt: Int? {
        switch self {
        case .uint32(let v): return Int(v)
        case .int32(let v): return Int(v)
        case .uint64(let v): return Int(v)
        case .int64(let v): return Int(v)
        default: return nil
        }
    }

    var asFloat: Float? {
        switch self {
        case .float32(let v): return v
        case .float64(let v): return Float(v)
        default: return nil
        }
    }

    var asString: String? {
        if case .string(let v) = self { return v }
        return nil
    }

    var asBool: Bool? {
        if case .bool(let v) = self { return v }
        return nil
    }

    var asStringArray: [String]? {
        if case .array(let arr) = self {
            return arr.compactMap { $0.asString }
        }
        return nil
    }
}

struct GGUFTensorInfo {
    let name: String
    let dimensions: [Int]
    let type: GGMLType
    let offset: UInt64

    var elementCount: Int {
        dimensions.reduce(1, *)
    }

    var byteSize: Int {
        let blocks = (elementCount + type.blockSize - 1) / type.blockSize
        return blocks * type.bytesPerBlock
    }
}

struct GGUFFile {
    let metadata: [String: GGUFValue]
    let tensors: [String: GGUFTensorInfo]
    let tensorDataOffset: UInt64
    let fileHandle: FileHandle
    let mappedData: Data  // mmap'd file data

    // MARK: - Convenience accessors

    var architecture: String {
        metadata["general.architecture"]?.asString ?? "unknown"
    }

    var contextLength: Int {
        let key = "\(architecture).context_length"
        return metadata[key]?.asInt ?? 4096
    }

    var embeddingLength: Int {
        let key = "\(architecture).embedding_length"
        return metadata[key]?.asInt ?? 0
    }

    var blockCount: Int {
        let key = "\(architecture).block_count"
        return metadata[key]?.asInt ?? 0
    }

    var headCount: Int {
        let key = "\(architecture).attention.head_count"
        return metadata[key]?.asInt ?? 0
    }

    var headCountKV: Int {
        let key = "\(architecture).attention.head_count_kv"
        return metadata[key]?.asInt ?? headCount
    }

    var feedForwardLength: Int {
        let key = "\(architecture).feed_forward_length"
        return metadata[key]?.asInt ?? 0
    }

    var rmsNormEps: Float {
        let key = "\(architecture).attention.layer_norm_rms_epsilon"
        return metadata[key]?.asFloat ?? 1e-6
    }

    var ropeFreqBase: Float {
        let key = "\(architecture).rope.freq_base"
        return metadata[key]?.asFloat ?? 10000.0
    }

    var vocabSize: Int {
        if let tokens = metadata["tokenizer.ggml.tokens"] {
            if case .array(let arr) = tokens { return arr.count }
        }
        return 0
    }

    var eosTokenId: Int {
        metadata["tokenizer.ggml.eos_token_id"]?.asInt ?? 0
    }

    /// Get raw pointer to tensor data (zero-copy from mmap)
    func tensorData(for tensor: GGUFTensorInfo) -> UnsafeRawBufferPointer {
        let start = Int(tensorDataOffset + tensor.offset)
        let size = tensor.byteSize
        return mappedData.withUnsafeBytes { buf in
            UnsafeRawBufferPointer(rebasing: buf[start..<start+size])
        }
    }

    /// Get tensor data as a contiguous slice of the mapped data
    func tensorDataSlice(for tensor: GGUFTensorInfo) -> Data {
        let start = Int(tensorDataOffset + tensor.offset)
        let size = tensor.byteSize
        return mappedData[start..<start+size]
    }
}

// MARK: - Parser

final class GGUFParser {
    private var data: Data
    private var offset: Int = 0

    init(data: Data) {
        self.data = data
    }

    static func parse(url: URL) throws -> GGUFFile {
        // Memory-map the file for zero-copy tensor access
        let mappedData = try Data(contentsOf: url, options: .mappedIfSafe)
        let parser = GGUFParser(data: mappedData)

        // Magic number
        let magic = parser.readUInt32()
        guard magic == 0x46554747 else { // "GGUF"
            throw GGUFError.invalidMagic
        }

        // Version
        let version = parser.readUInt32()
        guard version >= 2 && version <= 3 else {
            throw GGUFError.unsupportedVersion(version)
        }

        // Counts
        let tensorCount = parser.readUInt64()
        let metadataKVCount = parser.readUInt64()

        // Parse metadata
        var metadata: [String: GGUFValue] = [:]
        for _ in 0..<metadataKVCount {
            let key = parser.readString()
            let value = parser.readValue()
            metadata[key] = value
        }

        // Parse tensor infos
        var tensors: [String: GGUFTensorInfo] = [:]
        for _ in 0..<tensorCount {
            let name = parser.readString()
            let nDims = parser.readUInt32()
            var dims: [Int] = []
            for _ in 0..<nDims {
                dims.append(Int(parser.readUInt64()))
            }
            let typeRaw = parser.readUInt32()
            let type = GGMLType(rawValue: typeRaw) ?? .f32
            let tensorOffset = parser.readUInt64()
            tensors[name] = GGUFTensorInfo(
                name: name,
                dimensions: dims,
                type: type,
                offset: tensorOffset
            )
        }

        // Tensor data starts at alignment boundary after header
        let alignment = metadata["general.alignment"]?.asInt ?? 32
        let headerEnd = parser.offset
        let tensorDataOffset = UInt64((headerEnd + alignment - 1) / alignment * alignment)

        let fileHandle = try FileHandle(forReadingFrom: url)

        return GGUFFile(
            metadata: metadata,
            tensors: tensors,
            tensorDataOffset: tensorDataOffset,
            fileHandle: fileHandle,
            mappedData: mappedData
        )
    }

    // MARK: - Reading primitives

    private func readUInt8() -> UInt8 {
        let v = data[data.startIndex + offset]
        offset += 1
        return v
    }

    private func readUInt32() -> UInt32 {
        let v = data.withUnsafeBytes { buf in
            buf.loadUnaligned(fromByteOffset: offset, as: UInt32.self)
        }
        offset += 4
        return v
    }

    private func readInt32() -> Int32 {
        let v = data.withUnsafeBytes { buf in
            buf.loadUnaligned(fromByteOffset: offset, as: Int32.self)
        }
        offset += 4
        return v
    }

    private func readUInt64() -> UInt64 {
        let v = data.withUnsafeBytes { buf in
            buf.loadUnaligned(fromByteOffset: offset, as: UInt64.self)
        }
        offset += 8
        return v
    }

    private func readFloat32() -> Float {
        let v = data.withUnsafeBytes { buf in
            buf.loadUnaligned(fromByteOffset: offset, as: Float.self)
        }
        offset += 4
        return v
    }

    private func readFloat64() -> Double {
        let v = data.withUnsafeBytes { buf in
            buf.loadUnaligned(fromByteOffset: offset, as: Double.self)
        }
        offset += 8
        return v
    }

    private func readBool() -> Bool {
        let v = readUInt8()
        return v != 0
    }

    private func readString() -> String {
        let length = Int(readUInt64())
        let bytes = data[data.startIndex + offset ..< data.startIndex + offset + length]
        offset += length
        return String(data: bytes, encoding: .utf8) ?? ""
    }

    private func readValue() -> GGUFValue {
        let typeRaw = readUInt32()
        guard let type = GGUFValueType(rawValue: typeRaw) else {
            return .uint32(0) // fallback
        }

        switch type {
        case .uint8: return .uint8(readUInt8())
        case .int8: return .int8(Int8(bitPattern: readUInt8()))
        case .uint16:
            let v = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt16.self) }
            offset += 2
            return .uint16(v)
        case .int16:
            let v = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: Int16.self) }
            offset += 2
            return .int16(v)
        case .uint32: return .uint32(readUInt32())
        case .int32: return .int32(readInt32())
        case .float32: return .float32(readFloat32())
        case .bool: return .bool(readBool())
        case .string: return .string(readString())
        case .uint64: return .uint64(readUInt64())
        case .int64:
            let v = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: Int64.self) }
            offset += 8
            return .int64(v)
        case .float64: return .float64(readFloat64())
        case .array:
            let elemType = GGUFValueType(rawValue: readUInt32()) ?? .uint32
            let count = Int(readUInt64())
            var arr: [GGUFValue] = []
            arr.reserveCapacity(count)
            for _ in 0..<count {
                switch elemType {
                case .string: arr.append(.string(readString()))
                case .uint32: arr.append(.uint32(readUInt32()))
                case .int32: arr.append(.int32(readInt32()))
                case .float32: arr.append(.float32(readFloat32()))
                case .uint8: arr.append(.uint8(readUInt8()))
                case .int8: arr.append(.int8(Int8(bitPattern: readUInt8())))
                case .bool: arr.append(.bool(readBool()))
                case .uint64: arr.append(.uint64(readUInt64()))
                case .int64:
                    let v = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: Int64.self) }
                    offset += 8
                    arr.append(.int64(v))
                case .float64: arr.append(.float64(readFloat64()))
                default: break
                }
            }
            return .array(arr)
        }
    }
}

enum GGUFError: Error, LocalizedError {
    case invalidMagic
    case unsupportedVersion(UInt32)
    case tensorNotFound(String)
    case unsupportedQuantization(GGMLType)

    var errorDescription: String? {
        switch self {
        case .invalidMagic: return "Not a valid GGUF file"
        case .unsupportedVersion(let v): return "Unsupported GGUF version: \(v)"
        case .tensorNotFound(let name): return "Tensor not found: \(name)"
        case .unsupportedQuantization(let t): return "Unsupported quantization: \(t)"
        }
    }
}
