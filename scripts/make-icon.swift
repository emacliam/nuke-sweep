import Foundation

// Copy the approved multi-resolution brand artwork; never regenerate the old mark.
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let source = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("branding/nuke-sweep/NukeSweep.iconset", isDirectory: true)
let target = output.appendingPathComponent("NukeSweep.iconset", isDirectory: true)
if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
try FileManager.default.copyItem(at: source, to: target)
