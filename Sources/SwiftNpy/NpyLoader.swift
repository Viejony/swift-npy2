
import Foundation

// https://docs.scipy.org/doc/numpy-dev/neps/npy-format.html

extension Npy {
    public init(contentsOf url: URL) throws {
        let data = try Data(contentsOf: url)
        try self.init(data: data)
    }
    
    public init(data: Data) throws {
        let magic = data.subdata(in: 0..<6)
        guard magic == MAGIC_PREFIX else {
            throw NpyLoaderError.ParseFailed(message: "Invalid prefix: \(magic)")
        }
        
        let major = data[6]
        guard major == 1 || major == 2 else {
            throw NpyLoaderError.ParseFailed(message: "Invalid major version: \(major)")
        }
        
        let minor = data[7]
        guard minor == 0 else {
            throw NpyLoaderError.ParseFailed(message: "Invalid minor version: \(minor)")
        }
        
        let headerLen: Int
        let rest: Data
        switch major {
        case 1:
            let tmp = Data(data[8...9]).withUnsafeBytes { (ptr: UnsafePointer<UInt8>) in
                ptr.withMemoryRebound(to: UInt16.self, capacity: 1) {
                    UInt16(littleEndian: $0.pointee)
                }
            }
            headerLen = Int(tmp)
            rest = data.subdata(in: 10..<data.count)
        case 2:
            let tmp = Data(data[8...11]).withUnsafeBytes { (ptr: UnsafePointer<UInt8>) in
                ptr.withMemoryRebound(to: UInt32.self, capacity: 1) {
                    UInt32(littleEndian: $0.pointee)
                }
            }
            headerLen = Int(tmp)
            rest = data.subdata(in: 12..<data.count)
        default:
            fatalError("Never happens.")
        }
        
        let headerData = rest.subdata(in: 0..<headerLen)
        let header = try parseHeader(headerData)
        
        let elemData = rest.subdata(in: headerLen..<rest.count)
        
        self.init(header: header, elementsData: elemData)
    }
}

public enum NpyLoaderError: Error {
    case ParseFailed(message: String)
    case TypeMismatch(message: String)
}

protocol MultiByteUInt {
    init(bigEndian: Self)
    init(littleEndian: Self)
}
extension UInt16: MultiByteUInt {}
extension UInt32: MultiByteUInt {}
extension UInt64: MultiByteUInt {}

func loadUInts<T: MultiByteUInt>(data: Data, count: Int, endian: Endian) -> [T] {
    
    switch endian {
    case .host:
        let uints = data.withUnsafeBytes { (ptr: UnsafePointer<UInt8>) in
            ptr.withMemoryRebound(to: T.self, capacity: count) { ptr2 in
                [T](UnsafeBufferPointer(start: ptr2, count: count))
            }
        }
        return uints
    case .big:
        return data.withUnsafeBytes { (ptr: UnsafePointer<UInt8>) in
            ptr.withMemoryRebound(to: T.self, capacity: count) { ptr2 in
                (0..<count).map { T(bigEndian: ptr2.advanced(by: $0).pointee) }
            }
        }
    case .little:
        return data.withUnsafeBytes { (ptr: UnsafePointer<UInt8>) in
            ptr.withMemoryRebound(to: T.self, capacity: count) { ptr2 in
                (0..<count).map { T(littleEndian: ptr2.advanced(by: $0).pointee) }
            }
        }
    case .na:
        fatalError("Invalid byteorder.")
    }
}

func loadUInt8s(data: Data, count: Int) -> [UInt8] {
    let uints = data.withUnsafeBytes { (ptr: UnsafePointer<UInt8>) in
        [UInt8](UnsafeBufferPointer(start: ptr, count: count))
    }
    return uints
}

func loadStrings(data: Data, count: Int, stringSize: Int) -> [String] {
    precondition(data.count == count * stringSize)

    var strings: [String] = []
    var startIndex = 0
    if data.count > 0 {
        while startIndex < data.count {

            // Determine the size of the slice
            let endIndex = min(startIndex + stringSize, data.count)
            var slice = data.subdata(in: startIndex..<endIndex)

            // Find the first non-zero byte index and create a new Data instance starting from the first non-zero byte
            if let lastNonZeroIndex = slice.lastIndex(where: { $0 != 0 }) {
                let trimmedSlice = slice.subdata(in: 0..<lastNonZeroIndex + 1)
                slice = trimmedSlice
            }
            
            strings.append(String(data: slice, encoding: .utf8) ?? "")

            // Increase index
            startIndex += stringSize
        }
    } else {
        for _ in 0..<count {
            strings.append("")
        }
    }
    return strings
}