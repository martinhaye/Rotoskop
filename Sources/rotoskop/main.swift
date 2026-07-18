import Foundation
import RotoskopCore

@main
enum RotoskopMain {
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        guard let first = args.first else {
            printUsage()
            exit(1)
        }

        switch first {
        case "run":
            exit(Int32(runCommand(Array(args.dropFirst()))))
        case "assemble", "asm":
            exit(Int32(assembleCommand(Array(args.dropFirst()))))
        case "build":
            exit(Int32(buildCommand(Array(args.dropFirst()))))
        case "-h", "--help", "help":
            printUsage()
            exit(0)
        default:
            fputs("Unknown command: \(first)\n\n", stderr)
            printUsage()
            exit(1)
        }
    }

    static func printUsage() {
        let text = """
        rotoskop — 6502 IDE tooling (emulator, assembler, build)

        Usage:
          rotoskop build [project-root]
          rotoskop assemble <source.s> -o <out.bin> [-I dir] [--list out.lst]
          rotoskop run <config.json|project-root> [options]

        Build:
          Reads rotoskop.yaml; runs generate / assemble / pack_image steps.

        Run options (JSON config or after build via yaml run:):
          -t, --trace                 Print instruction trace
          -n, --max-instructions N   Instruction cap (default 1000)
          -v, --verbose              Verbose output
          --screen                   Dump 40-column text screen on exit
          --keys STRING              Keyboard input (repeatable; \\n → CR)
          --disk IMAGE               .2mg disk image (slot 2)
          --profile NAME             Overlay profile from rotoskop.yaml

        Assemble options:
          -o, --output PATH          Output binary (required)
          -I, --include DIR          Include search path (repeatable)
          --list PATH                Write listing file

        """
        print(text, terminator: "")
    }

    static func buildCommand(_ args: [String]) -> Int {
        var root = "."
        var i = 0
        while i < args.count {
            let a = args[i]
            if a == "-h" || a == "--help" {
                printUsage()
                return 0
            }
            if a.hasPrefix("-") {
                fputs("Error: unknown option \(a)\n", stderr)
                return 1
            }
            root = a
            i += 1
        }
        do {
            let engine = try BuildEngine(projectRoot: root)
            let result = engine.build()
            for d in result.diagnostics {
                fputs("\(d)\n", stderr)
            }
            if result.succeeded {
                fputs("Build OK (\(result.artifacts.count) artifacts)\n", stderr)
                for a in result.artifacts {
                    fputs("  \(a)\n", stderr)
                }
                return 0
            }
            return 1
        } catch {
            fputs("Error: \(error)\n", stderr)
            return 1
        }
    }

    static func assembleCommand(_ args: [String]) -> Int {
        var source: String?
        var output: String?
        var includes: [String] = []
        var listPath: String?

        var i = 0
        while i < args.count {
            let a = args[i]
            switch a {
            case "-o", "--output":
                i += 1
                guard i < args.count else { fputs("Error: \(a) needs a path\n", stderr); return 1 }
                output = args[i]
            case "-I", "--include":
                i += 1
                guard i < args.count else { fputs("Error: \(a) needs a directory\n", stderr); return 1 }
                includes.append(args[i])
            case "--list":
                i += 1
                guard i < args.count else { fputs("Error: --list needs a path\n", stderr); return 1 }
                listPath = args[i]
            case "-h", "--help":
                printUsage()
                return 0
            default:
                if a.hasPrefix("-") {
                    fputs("Error: unknown option \(a)\n", stderr)
                    return 1
                }
                if source != nil {
                    fputs("Error: unexpected \(a)\n", stderr)
                    return 1
                }
                source = a
            }
            i += 1
        }

        guard let source else {
            fputs("Error: missing source .s file\n", stderr)
            return 1
        }
        guard let output else {
            fputs("Error: -o/--output is required\n", stderr)
            return 1
        }

        let asm = Assembler(options: AssembleOptions(includePaths: includes, generateListing: listPath != nil))
        let result = asm.assemble(file: source)
        for d in result.diagnostics {
            fputs("\(d)\n", stderr)
        }
        guard result.succeeded else { return 1 }

        do {
            try Data(result.binary).write(to: URL(fileURLWithPath: output))
        } catch {
            fputs("Error: cannot write \(output): \(error)\n", stderr)
            return 1
        }
        if let listPath {
            do {
                try result.listing.write(toFile: listPath, atomically: true, encoding: .utf8)
            } catch {
                fputs("Error: cannot write listing: \(error)\n", stderr)
                return 1
            }
        }
        fputs(String(format: "Wrote %d bytes (base $%04X) to %@\n", result.binary.count, result.baseAddress, output), stderr)
        return 0
    }

    static func runCommand(_ args: [String]) -> Int {
        var configPath: String?
        var trace = false
        var maxInstructions = 1000
        var verbose = false
        var screen = false
        var keys: [String] = []
        var disk: String?

        var i = 0
        while i < args.count {
            let a = args[i]
            switch a {
            case "-t", "--trace":
                trace = true
            case "-v", "--verbose":
                verbose = true
            case "--screen":
                screen = true
            case "-n", "--max-instructions":
                i += 1
                guard i < args.count, let n = Int(args[i]) else {
                    fputs("Error: \(a) requires an integer\n", stderr)
                    return 1
                }
                maxInstructions = n
            case "--keys":
                i += 1
                guard i < args.count else {
                    fputs("Error: --keys requires a string\n", stderr)
                    return 1
                }
                keys.append(args[i])
            case "--disk":
                i += 1
                guard i < args.count else {
                    fputs("Error: --disk requires a path\n", stderr)
                    return 1
                }
                disk = args[i]
            case "-h", "--help":
                printUsage()
                return 0
            default:
                if a.hasPrefix("-") {
                    fputs("Error: unknown option \(a)\n", stderr)
                    return 1
                }
                if configPath != nil {
                    fputs("Error: unexpected argument \(a)\n", stderr)
                    return 1
                }
                configPath = a
            }
            i += 1
        }

        guard let configPath else {
            fputs("Error: missing config.json path\n", stderr)
            printUsage()
            return 1
        }

        let cfg: SimulatorConfig
        do {
            cfg = try SimulatorConfig.fromJSONFile(configPath)
        } catch {
            fputs("Error: Invalid config: \(error)\n", stderr)
            return 1
        }

        let sim = Simulator(config: cfg)

        if !keys.isEmpty {
            sim.setupKeyboard(inputStrings: keys)
        }

        if let disk {
            do {
                try sim.setupHardDrive(imagePath: disk)
            } catch {
                fputs("Error: Cannot open disk image: \(error)\n", stderr)
                return 1
            }
        }

        do {
            try sim.load()
        } catch {
            fputs("Error: \(error)\n", stderr)
            return 1
        }

        let reason = sim.run(maxInstructions: maxInstructions, trace: trace)

        if trace {
            print("Trace:")
            for line in sim.trace {
                print("  \(line)")
            }
            print()
        }

        if verbose || trace {
            print("Instructions executed: \(sim.instructionCount)")
        }

        if screen {
            let text = sim.dumpScreen()
            if !text.isEmpty {
                fputs("\nScreen:\n\(text)\n", stderr)
            }
        }

        switch reason {
        case .success:
            if verbose { print("Simulation completed successfully") }
            return 0
        case .instructionLimit:
            fputs("Simulation halted without reaching success address (instruction limit)\n", stderr)
            fputs("\(sim.cpu.registerDump())\n", stderr)
            return 1
        case .unhandledBRK:
            fputs("Unhandled BRK (IRQ vector unset)\n", stderr)
            fputs("\(sim.cpu.registerDump())\n", stderr)
            return 1
        case .illegalOpcode(let op):
            fputs(String(format: "Illegal opcode $%02X\n", op), stderr)
            fputs("\(sim.cpu.registerDump())\n", stderr)
            return 1
        case .explicitStop:
            fputs("Stopped\n", stderr)
            return 1
        case .ioError(let msg):
            fputs("I/O error: \(msg)\n", stderr)
            fputs("\(sim.cpu.registerDump())\n", stderr)
            return 1
        }
    }
}
