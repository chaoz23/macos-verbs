import AppKit
import ArgumentParser
import Foundation

struct ClipboardCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "clipboard",
        abstract: "Read and write the general pasteboard (text).",
        subcommands: [Get.self, Set.self]
    )

    struct Get: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Print clipboard text. Exit 1 if the clipboard has no text.")
        @OptionGroup var out: OutputOptions

        func run() throws {
            guard let text = NSPasteboard.general.string(forType: .string) else {
                throw VerbError(message: "clipboard has no text content")
            }
            Out.emit(out, human: text,
                     data: ["action": "clipboard_get", "text": text,
                            "length": text.count])
        }
    }

    struct Set: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Set clipboard text from the argument, or stdin if omitted.")
        @Argument(help: "Text to place on the clipboard. Omit to read stdin.")
        var text: String?
        @OptionGroup var out: OutputOptions

        func run() throws {
            let value: String
            if let text {
                value = text
            } else {
                let data = FileHandle.standardInput.readDataToEndOfFile()
                guard let s = String(data: data, encoding: .utf8), !s.isEmpty else {
                    throw VerbError(message: "no text given and stdin was empty")
                }
                value = s
            }
            let pb = NSPasteboard.general
            pb.clearContents()
            guard pb.setString(value, forType: .string) else {
                throw VerbError.system("pasteboard write failed")
            }
            Out.emit(out, human: "clipboard set (\(value.count) chars)",
                     data: ["action": "clipboard_set", "length": value.count])
        }
    }
}
