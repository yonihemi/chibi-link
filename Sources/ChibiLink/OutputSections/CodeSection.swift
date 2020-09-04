class CodeSection: VectorSection {
    var section: BinarySection { .code }
    let size: OutputSectionSize
    let count: Int
    let sections: [Section]

    init(sections: [Section]) {
        var totalSize = 0
        var totalCount = 0
        for section in sections {
            totalSize += section.payloadSize!
            totalCount += section.count!
        }
        let lengthBytes = encodeULEB128(UInt32(totalCount))
        totalSize += lengthBytes.count
        self.sections = sections
        count = totalCount
        size = .fixed(totalSize)
    }

    func writeVectorContent(writer: BinaryWriter, relocator: Relocator) throws {
        for section in sections {
            let body = relocator.relocate(chunk: section)
            let payload = body[(section.payloadOffset! - section.offset)...]
            try writer.writeBytes(payload)
        }
    }
}