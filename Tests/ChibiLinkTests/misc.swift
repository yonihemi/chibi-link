@testable import ChibiLink
import Foundation

func exec(_ launchPath: String, _ arguments: [String]) {
    let process = Process()
    process.launchPath = launchPath
    process.arguments = arguments
    process.launch()
    process.waitUntilExit()
    assert(process.terminationStatus == 0)
}

func makeTemporaryFile() -> (URL, FileHandle) {
    let tempdir = URL(fileURLWithPath: NSTemporaryDirectory())
    let templatePath = tempdir.appendingPathComponent("chibi-link.XXXXXX")
    var template = [UInt8](templatePath.path.utf8).map { Int8($0) } + [Int8(0)]
    let fd = mkstemp(&template)
    if fd == -1 {
        fatalError("Failed to create temp directory")
    }
    let url = URL(fileURLWithPath: String(cString: template))
    let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    return (url, handle)
}

func createFile(_ content: String) -> URL {
    let (url, handle) = makeTemporaryFile()
    handle.write(content.data(using: .utf8)!)
    return url
}

func compileWat(_ content: String, options: [String] = []) -> URL {
    let module = createFile(content)
    let (output, _) = makeTemporaryFile()
    exec("/usr/local/bin/wat2wasm", [module.path, "-o", output.path] + options)
    return output
}

func createInputBinary(_ url: URL, filename: String? = nil) -> InputBinary {
    let bytes = try! Array(Data(contentsOf: url))
    let filename = filename ?? url.lastPathComponent
    return InputBinary(filename: filename, data: bytes)
}


class InMemoryOutputByteStream: OutputByteStream {
    private(set) var bytes: [UInt8] = []
    private(set) var currentOffset: Offset = 0

    func write(_ bytes: Array<UInt8>, at offset: Offset) throws {
        for index in offset..<(offset+bytes.count) {
            self.bytes[index] = bytes[index - offset]
        }
    }

    func write(_ bytes: ArraySlice<UInt8>) throws {
        self.bytes.append(contentsOf: bytes)
        currentOffset += bytes.count
    }

    func writeString(_ value: String) throws {
        self.bytes.append(contentsOf: value.utf8)
        currentOffset += value.utf8.count
    }
}