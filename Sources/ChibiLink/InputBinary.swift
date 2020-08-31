class DataSegment {
    let memoryIndex: Index
    var offset: Offset!
    var data: ArraySlice<UInt8>!
    var size: Size!

    internal init(memoryIndex: Index) {
        self.memoryIndex = memoryIndex
    }
}

struct Relocation {
    let type: RelocType
    let offset: Offset
    let index: Index
    let addend: UInt32
}

class Section {
    let sectionCode: BinarySection
    let size: Size
    let offset: Offset

    var payloadOffset: Offset?
    var payloadSize: Size?
    let count: Int?

    var memoryInitialSize: Size?

    var relocations: [Relocation] = []

    var dataSegments: [DataSegment] = []

    weak var binary: InputBinary?

    init(sectionCode: BinarySection, size: Size, offset: Offset,
         payloadOffset: Offset?, payloadSize: Size?, count: Int?,
         binary: InputBinary)
    {
        self.sectionCode = sectionCode
        self.size = size
        self.offset = offset
        self.payloadOffset = payloadOffset
        self.payloadSize = payloadSize
        self.count = count
        self.binary = binary
    }
}

class FunctionImport {
    let module: String
    let field: String
    let signatureIdx: Int
    var unresolved: Bool
    var relocatedFunctionIndex: Index?

    init(module: String, field: String, signatureIdx: Int, unresolved: Bool) {
        self.module = module
        self.field = field
        self.signatureIdx = signatureIdx
        self.unresolved = unresolved
    }
}

class GlobalImport {
    internal init(module: String, field: String, type: ValueType, mutable: Bool) {
        self.module = module
        self.field = field
        self.type = type
        self.mutable = mutable
    }

    let module: String
    let field: String
    let type: ValueType
    let mutable: Bool
}

class Export {
    let kind: ExternalKind
    let name: String
    let index: Index

    init(kind: ExternalKind, name: String, index: Index) {
        self.kind = kind
        self.name = name
        self.index = index
    }
}

class InputBinary {
    let filename: String
    let data: [UInt8]

    fileprivate(set) var sections: [Section] = []
    fileprivate(set) var funcImports: [FunctionImport] = []
    fileprivate(set) var globalImports: [GlobalImport] = []

    fileprivate(set) var exports: [Export] = []

    fileprivate(set) var functionCount: Int!
    fileprivate(set) var tableElemSize: Size = 0

    fileprivate(set) var debugNames: [String] = []
    
    
    struct RelocOffsets {
        var importedFunctionIndexOffset: Offset
        var importedGlobalindexOffset: Offset
        var memoryPageOffset: Offset
        var tableIndexOffset: Offset?
        var typeIndexOffset: Offset?
        var globalIndexOffset: Offset?
        var functionIndexOffset: Offset?
    }

    var relocOffsets: RelocOffsets? = nil
    
    var memoryPageCount: Int {
        sections.first(where: { $0.sectionCode == .memory })?.memoryInitialSize ?? 0
    }
    var unresolvedFunctionImportsCount: Int = 0

    init(filename: String, data: [UInt8]) {
        self.filename = filename
        self.data = data
    }
}

func hasCount(_ section: BinarySection) -> Bool {
    section != .custom && section != .start
}

class LinkInfoCollector: BinaryReaderDelegate {
    var state: BinaryReader.State!
    var currentSection: Section!
    var currentRelocSection: Section!
    let binary: InputBinary
    init(binary: InputBinary) {
        self.binary = binary
    }

    func setState(_ state: BinaryReader.State) {
        self.state = state
    }

    func beginSection(_ sectionCode: BinarySection, size: Size) {
        var count: UInt32?
        var payloadOffset: Offset?
        var payloadSize: Size?
        if hasCount(sectionCode) {
            let (itemCount, offset) = decodeLEB128(binary.data[state.offset...])
            assert(itemCount != 0)
            count = itemCount
            payloadOffset = state.offset + offset
            payloadSize = size - offset
        }
        let section = Section(
            sectionCode: sectionCode, size: size, offset: state.offset,
            payloadOffset: payloadOffset,
            payloadSize: payloadSize,
            count: count.map(Int.init),
            binary: binary
        )
        binary.sections.append(section)
        currentSection = section
    }

    func onImportFunc(_: Index, _ module: String, _ field: String, _: Int, _ signatureIndex: Index) {
        let funcImport = FunctionImport(
            module: module, field: field,
            signatureIdx: signatureIndex,
            unresolved: true
        )
        binary.funcImports.append(funcImport)
        binary.unresolvedFunctionImportsCount += 1
    }

    func onImportMemory(_: Index, _: String, _: String, _: Index, _: Limits) {
        fatalError("TODO")
    }

    func onImportGlobal(_: Index, _ module: String, _ field: String, _: Index, _ type: ValueType, _ mutable: Bool) {
        let globalImport = GlobalImport(module: module, field: field, type: type, mutable: mutable)
        binary.globalImports.append(globalImport)
    }

    func onFunctionCount(_ count: Int) {
        binary.functionCount = count
    }

    func onTable(_: Index, _: ElementType, _ limits: Limits) {
        binary.tableElemSize = limits.initial
    }

    func onElementSegmentFunctionIndexCount(_: Index, _: Int) {
        let sec = currentSection!
        let delta = state.offset - sec.payloadOffset!
        sec.payloadOffset! += delta
        sec.payloadSize! -= delta
    }

    func onMemory(_: Index, _ pageLimits: Limits) {
        currentSection.memoryInitialSize = Int(pageLimits.initial)
    }

    func onExport(_: Index, _ kind: ExternalKind, _ itemIndex: Index, _ name: String) {
        let export = Export(kind: kind, name: name, index: itemIndex)
        binary.exports.append(export)
    }

    func beginDataSegment(_: Index, _ memoryIndex: Index) {
        let sec = currentSection!
        let segment = DataSegment(memoryIndex: memoryIndex)
        sec.dataSegments.append(segment)
    }

    func onInitExprI32ConstExpr(_: Index, _ value: UInt32) {
        let sec = currentSection!
        guard sec.sectionCode == .data else { return }
        let segment = sec.dataSegments.last!
        segment.offset = Int(value)
    }

    func onDataSegmentData(_: Index, _ data: ArraySlice<UInt8>, _ size: Size) {
        let sec = currentSection!
        let segment = sec.dataSegments.last!
        segment.data = data
        segment.size = size
    }

    func beginNamesSection(_: Size) {
        let funcSize = binary.functionCount + binary.funcImports.count
        binary.debugNames = Array(repeating: "", count: funcSize)
    }

    func onFunctionName(_ index: Index, _ name: String) {
        binary.debugNames[index] = name
    }

    func onRelocCount(_: Int, _ sectionIndex: Index) {
        currentRelocSection = binary.sections[sectionIndex]
    }

    func onReloc(_ type: RelocType, _ offset: Offset, _ index: Index, _ addend: UInt32) {
        let reloc = Relocation(type: type, offset: offset, index: index, addend: addend)
        currentRelocSection.relocations.append(reloc)
    }
}
