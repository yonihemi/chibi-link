import ChibiLink

var args = CommandLine.arguments
var index = args.startIndex + 1
var output: String?
var inputs: [String] = []
while index < args.count {
    switch args[index] {
    case "-o":
        index += 1
        output = args[index]
    default:
        inputs.append(args[index])
    }
    index += 1
}

guard let output = output else {
    fatalError("no output file specified")
}
do {
    let outputStream = try FileOutputByteStream(path: output)
    try performLinker(inputs, outputStream: outputStream)
} catch {
    fatalError("\(dump(error))")
}
