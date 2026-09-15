import Foundation
import ZipCore
let args = CommandLine.arguments
if args.count < 3 {
    fputs("Usage: zipcheck OUTPUT.zip INPUT [INPUT ...]\n", stderr)
    exit(2)
}
do {
    let report = try ZipWriter.create(sources: args.dropFirst(2).map { URL(fileURLWithPath: $0) }, destination: URL(fileURLWithPath: args[1]))
    for path in report.skippedSymbolicLinks { fputs("已跳过符号链接：\(path)\n", stderr) }
} catch { fputs(error.localizedDescription + "\n", stderr); exit(1) }
