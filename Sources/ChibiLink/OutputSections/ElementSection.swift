class ElementSection: VectorSection {
    var section: BinarySection { .elem }
    var size: OutputSectionSize { .unknown }
    let count: Int = 1
    let elementCount: Int
    private let sections: [Section]
    private let funcSection: FunctionSection
    private let indexOffsetByFileName: [String: Offset]

    init(sections: [Section], funcSection: FunctionSection) {
        var totalElemCount = 0
        var indexOffsets: [String: Offset] = [:]
        for section in sections {
            indexOffsets[section.binary!.filename] = totalElemCount
            totalElemCount += section.count!
        }
        elementCount = totalElemCount
        self.sections = sections
        self.funcSection = funcSection
        indexOffsetByFileName = indexOffsets
    }

    func writeVectorContent(writer: BinaryWriter, relocator _: Relocator) throws {
        try writer.writeULEB128(UInt32(0)) // table index
        try writer.writeI32InitExpr(.i32(0)) // offset
        try writer.writeULEB128(UInt32(elementCount))
        // Read + Write + Relocate func indexes
        for section in sections {
            let payloadStart = section.payloadOffset!
            let payloadSize = section.payloadSize!
            let payloadEnd = payloadStart + payloadSize
            var readOffset = payloadStart
            let funcIndexOffset = funcSection.indexOffset(for: section.binary!)!
            for _ in 0 ..< section.count! {
                let payload = section.binary!.data[readOffset ..< payloadEnd]
                let (funcIndex, length) = decodeULEB128(payload, UInt32.self)
                readOffset += length
                try writer.writeIndex(Index(funcIndex) + funcIndexOffset)
            }
        }
    }
}