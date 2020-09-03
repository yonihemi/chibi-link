
class BinaryWriter {
    private let stream: OutputByteStream
    var offset: Offset { stream.currentOffset }
    init(stream: OutputByteStream) {
        self.stream = stream
    }

    // MARK: - Utilities

    struct Placeholder<Value> {
        fileprivate let offset: Offset
    }

    func writeSizePlaceholder() throws -> Placeholder<Size> {
        let offset = stream.currentOffset
        let placeholder = Placeholder<Size>(offset: offset)
        let dummyBytes = encodeULEB128(0 as UInt, padTo: LEB128.maxLength)
        try stream.write(dummyBytes)
        return placeholder
    }

    func fillSizePlaceholder(_ placeholder: Placeholder<Size>, value: Size) throws {
        let bytes = encodeULEB128(UInt32(value), padTo: LEB128.maxLength)
        try stream.write(bytes, at: placeholder.offset)
    }
    func writeIndex(_ index: Index) throws {
        try writeULEB128(UInt32(index))
    }
    func writeFixedUInt8(_ value: UInt8) throws {
        try stream.write([value])
    }
    func writeULEB128<T>(_ value: T) throws
        where T: UnsignedInteger, T: FixedWidthInteger {
        let bytes = encodeULEB128(value)
        try stream.write(bytes)
    }
    func writeSLEB128<T>(_ value: T) throws
        where T: SignedInteger, T: FixedWidthInteger {
        let bytes = encodeSLEB128(value)
        try stream.write(bytes)
    }
    func writeString(_ value: String) throws {
        let lengthBytes = encodeULEB128(UInt32(value.count))
        try stream.write(lengthBytes)
        try stream.writeString(value)
    }

    func writeBytes(_ bytes: ArraySlice<UInt8>) throws {
        try writeULEB128(UInt32(bytes.count))
        try stream.write(bytes)
    }

    // MARK: - Wasm binary format writers

    func writeHeader() throws {
        try stream.write(magic)
        try stream.write(version)
    }

    func writeSectionCode(_ code: BinarySection) throws {
        try writeFixedUInt8(code.rawValue)
    }

    func writeImport(_ theImport: ImportSeciton.Import) throws {
        try writeString(theImport.module)
        try writeString(theImport.field)
        switch theImport.kind {
        case let .function(signatureIndex):
            try writeFixedUInt8(ExternalKind.func.rawValue)
            try writeULEB128(UInt32(signatureIndex))
        case let .global(type, mutable):
            try writeFixedUInt8(ExternalKind.global.rawValue)
            try writeFixedUInt8(type.rawValue)
            try writeFixedUInt8(mutable ? 0 : 1)
        }
    }
    
    enum InitExpr {
        case i32(Int32)
    }
    
    func writeI32InitExpr(_ expr: InitExpr) throws {
        switch expr {
        case .i32(let value):
            try writeFixedUInt8(ConstOpcode.i32Const.rawValue)
            try writeSLEB128(value)
            try writeFixedUInt8(Opcode.end.rawValue)
        }
    }

    func writeDataSegment(_ segment: OutputSegment, startOffset: Offset) throws {
        try writeIndex(0) // memory index
        // TODO: i64?
        try writeI32InitExpr(.i32(Int32(startOffset)))
        try writeULEB128(UInt32(segment.size))
        let base = stream.currentOffset
        for chunk in segment.chunks {
            let written = stream.currentOffset - base
            let padding = chunk.offset - written
            let paddingBytes = Array<UInt8>(repeating: 0, count: padding)
            try stream.write(paddingBytes)
            try stream.write(chunk.segment.data)
        }
    }
    
    func writeSectionPayload(_ section: Section) throws {
        let offset = section.payloadOffset!
        let bytes = section.binary!.data[offset..<offset + section.payloadSize!]
        try stream.write(bytes)
    }
}

class OutputWriter {
    let writer: BinaryWriter
    let symbolTable: SymbolTable
    let inputs: [InputBinary]
    init(stream: OutputByteStream,
         symbolTable: SymbolTable,
         inputs: [InputBinary]) {
        self.writer = BinaryWriter(stream: stream)
        self.symbolTable = symbolTable
        self.inputs = inputs
    }

    func writeBinary() throws {
        try writer.writeHeader()

        var sectionsMap: [BinarySection: [Section]] = [:]
        for binary in inputs {
            for sec in binary.sections {
                sectionsMap[sec.sectionCode, default: []].append(sec)
            }
        }
        let typeSection = TypeSection(sections: sectionsMap[.type] ?? [])
        try typeSection.write(writer: writer)
        let importSection = ImportSeciton(symbolTable: symbolTable)
        try importSection.write(writer: writer)
        let dataSection = DataSection(sections: sectionsMap[.data] ?? [])
        try dataSection.write(writer: writer)
    }
}
