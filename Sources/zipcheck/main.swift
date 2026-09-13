import Foundation
import ZipCore
let args = CommandLine.arguments
if args.count < 3 {
    fputs("Usage: zipcheck OUTPUT.zip INPUT [INPUT ...]\n", stderr)
    exit(2)
}
do {
    try ZipWriter.create(sources: args.dropFirst(2).map { URL(fileURLWithPath: $0) }, destination: URL(fileURLWithPath: args[1]))
} catch { fputs(error.localizedDescription + "\n", stderr); exit(1) }
