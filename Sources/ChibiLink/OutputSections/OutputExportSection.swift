class OutputExportSection: OutputVectorSection {
    enum Error: Swift.Error {
        case functionNotFound(String)
    }
    
    struct Export {
        let kind: Kind
        let name: String
        enum Kind {
            case function(Index)
            case global(Index)
            case memory(Index)
        }
    }

    var section: SectionCode { .export }
    var count: Int { exports.count }
    var size: OutputSectionSize { .unknown }
    private(set) var exports: [Export]

    func addExport(_ export: Export) {
        exports.append(export)
    }

    init(
        symbolTable: SymbolTable,
        exportSymbols: [String],
        funcSection: OutputFunctionSection,
        globalSection: OutputGlobalSection
    ) throws {
        var exports: [String: Export] = [:]
        func exportFunction(_ target: IndexableTarget) {
            let base = funcSection.indexOffset(for: target.binary)!
            let index = base + target.itemIndex - target.binary.funcImports.count
            let export = target.binary.exports[target.itemIndex]
            let exportName = export?.name ?? target.name
            exports[exportName] = OutputExportSection.Export(kind: .function(index), name: exportName)
        }

        exports["memory"] = OutputExportSection.Export(kind: .memory(0), name: "memory")
        if case let .function(symbol) = symbolTable.find("_start"),
            case let .defined(target) = symbol.target
        {
            exportFunction(target)
        }
        for export in exportSymbols {
            guard case let .function(symbol) = symbolTable.find(export),
                case let .defined(target) = symbol.target
            else {
                throw Error.functionNotFound(export)
            }
            exportFunction(target)
        }
        for export in symbolTable.symbols() where export.flags.isExported {
            guard case let .function(symbol) = export,
                case let .defined(target) = symbol.target
            else { continue }
            exportFunction(target)
        }
        self.exports = Array(exports.values)
    }

    func writeVectorContent(writer: BinaryWriter, relocator _: Relocator) throws {
        for export in exports {
            try writer.writeExport(export)
        }
    }
}
