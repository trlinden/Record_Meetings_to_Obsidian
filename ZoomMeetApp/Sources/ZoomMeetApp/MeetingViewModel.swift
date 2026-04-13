import Foundation
import SwiftUI

enum MeetingState: Equatable {
    case idle
    case recording
    case processing(step: String)
    case done(notePath: String)
    case error(message: String)

    var isIdle: Bool { if case .idle = self { return true } else { return false } }
    var isRecording: Bool { if case .recording = self { return true } else { return false } }
    var isDone: Bool { if case .done = self { return true } else { return false } }
}

@MainActor
class MeetingViewModel: ObservableObject {
    @Published var state: MeetingState = .idle
    @Published var logOutput: String = ""
    @Published var attendeeText: String = ""
    @Published var suggestions: [String] = []
    @Published var inputDevices: [AudioDevice] = []
    @Published var outputDevices: [AudioDevice] = []
    @Published var selectedInputName: String = ""
    @Published var selectedOutputName: String = ""
    @Published var selectedTemplate: String = ""
    @Published var resumeTimestamp: String = ""

    let peopleStore: PeopleStore
    private let scriptPath: String
    private let workingDir: String
    private var process: Process?
    private var stdinPipe: Pipe?
    private var lineBuffer: String = ""
    private var suppressStderr: Bool = false

    init() {
        // Resolve script location relative to the audio directory
        let audioDir = ProcessInfo.processInfo.environment["ZOOMMEET_DIR"]
            ?? (NSString("~/audio").expandingTildeInPath)
        scriptPath = (audioDir as NSString).appendingPathComponent("zoommeet2")
        workingDir = audioDir
        let peoplePath = (audioDir as NSString).appendingPathComponent("people.txt")
        peopleStore = PeopleStore(filePath: peoplePath)

        // Load audio devices
        let allDevices = listAudioDevices()
        inputDevices = allDevices.filter { $0.hasInput }
        outputDevices = allDevices.filter { $0.hasOutput }

        // Read config defaults for initial selection
        let configPath = (audioDir as NSString).appendingPathComponent("config.yaml")
        let configMic = Self.yamlValue("microphone", from: configPath) ?? ""
        let configOutput = Self.yamlValue("output_device", from: configPath) ?? "BlackHole 2ch"
        let configTemplate = Self.yamlValue("obsidian_template", from: configPath) ?? ""

        // Default input/output to config values
        selectedInputName = inputDevices.first(where: { $0.name == configMic })?.name
            ?? inputDevices.first?.name ?? ""
        selectedOutputName = outputDevices.first(where: { $0.name == configOutput })?.name
            ?? outputDevices.first(where: { $0.name.contains("BlackHole") })?.name
            ?? outputDevices.first?.name ?? ""

        // Default template from config (expand ~)
        selectedTemplate = NSString(string: configTemplate).expandingTildeInPath
    }

    private static func yamlValue(_ key: String, from path: String) -> String? {
        guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        for line in contents.components(separatedBy: .newlines) {
            if line.hasPrefix("\(key):") {
                return line.replacingOccurrences(of: "\(key):", with: "")
                    .trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    func refreshDevices() {
        let allDevices = listAudioDevices()
        inputDevices = allDevices.filter { $0.hasInput }
        outputDevices = allDevices.filter { $0.hasOutput }
    }

    func updateSuggestions() {
        let tokens = attendeeText.components(separatedBy: " ")
        guard let last = tokens.last, !last.isEmpty else {
            suggestions = []
            return
        }
        let alreadyEntered = Set(tokens.dropLast().map { $0.lowercased() })
        suggestions = peopleStore.suggestions(for: last)
            .filter { !alreadyEntered.contains($0.lowercased()) }
    }

    func acceptSuggestion(_ name: String) {
        var tokens = attendeeText.components(separatedBy: " ")
        if !tokens.isEmpty { tokens.removeLast() }
        tokens.append(name)
        attendeeText = tokens.joined(separator: " ") + " "
        suggestions = []
    }

    func startRecording() {
        launchScript(resume: false)
    }

    func resumeFromFiles() {
        let ts = resumeTimestamp.trimmingCharacters(in: .whitespaces)
        guard !ts.isEmpty else { return }
        launchScript(resume: true)
    }

    private func launchScript(resume: Bool) {
        guard state.isIdle else { return }

        logOutput = ""
        lineBuffer = ""
        suppressStderr = !resume  // suppress sox noise during live recording

        let proc = Process()
        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()

        proc.executableURL = URL(fileURLWithPath: "/bin/bash")
        var args: [String] = [scriptPath]
        if resume {
            args += ["--resume", resumeTimestamp.trimmingCharacters(in: .whitespaces)]
        }
        let attendees = attendeeText.trimmingCharacters(in: .whitespaces)
        if !attendees.isEmpty {
            args += attendees.components(separatedBy: " ").filter { !$0.isEmpty }
        }
        proc.arguments = args
        proc.currentDirectoryURL = URL(fileURLWithPath: workingDir)
        var env = ProcessInfo.processInfo.environment
        env["ZOOMMEET_MIC"] = selectedInputName
        env["ZOOMMEET_OUTPUT"] = selectedOutputName
        env["ZOOMMEET_TEMPLATE"] = selectedTemplate
        proc.environment = env
        proc.standardInput = stdin
        proc.standardOutput = stdout
        proc.standardError = stderr

        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                self?.appendOutput(text)
            }
        }

        stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                guard let self = self else { return }
                if !self.suppressStderr {
                    self.logOutput += text
                }
            }
        }

        proc.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                guard let self = self else { return }
                stdout.fileHandleForReading.readabilityHandler = nil
                stderr.fileHandleForReading.readabilityHandler = nil
                if proc.terminationStatus != 0 {
                    if case .done = self.state { return }
                    self.state = .error(message: "Script exited with status \(proc.terminationStatus)")
                }
            }
        }

        do {
            try proc.run()
        } catch {
            state = .error(message: "Failed to launch: \(error.localizedDescription)")
            return
        }

        self.process = proc
        self.stdinPipe = resume ? nil : stdin
        state = resume ? .processing(step: "Resuming from files...") : .recording
    }

    func stopRecording() {
        guard state.isRecording, let pipe = stdinPipe else { return }
        pipe.fileHandleForWriting.write(Data("\n".utf8))
        pipe.fileHandleForWriting.closeFile()
        suppressStderr = false
        state = .processing(step: "Stopping recording...")
    }

    func reset() {
        if let proc = process, proc.isRunning {
            proc.terminate()
        }
        process = nil
        stdinPipe = nil
        state = .idle
        logOutput = ""
        lineBuffer = ""
    }

    func openInObsidian() {
        guard case .done(let path) = state else { return }
        let expanded = NSString(string: path).expandingTildeInPath
        NSWorkspace.shared.open(URL(fileURLWithPath: expanded))
    }

    private func appendOutput(_ text: String) {
        logOutput += text
        lineBuffer += text

        // Process complete lines
        while let newlineRange = lineBuffer.range(of: "\n") {
            let line = String(lineBuffer[lineBuffer.startIndex..<newlineRange.lowerBound])
            lineBuffer = String(lineBuffer[newlineRange.upperBound...])
            parseLine(line)
        }
    }

    private func parseLine(_ line: String) {
        if line.contains("Press Enter to stop") {
            state = .recording
        } else if line.contains("Combining tracks") {
            state = .processing(step: "Combining audio tracks...")
        } else if line.contains("Transcribing microphone") {
            state = .processing(step: "Transcribing microphone...")
        } else if line.contains("Transcribing Zoom") {
            state = .processing(step: "Transcribing Zoom audio...")
        } else if line.contains("Summarizing with Claude") {
            state = .processing(step: "Summarizing with Claude...")
        } else if line.contains("Preparing Obsidian") {
            state = .processing(step: "Creating Obsidian note...")
        } else if line.contains("Meeting note saved to:") {
            let path = line.components(separatedBy: "Meeting note saved to:").last?
                .trimmingCharacters(in: .whitespaces) ?? ""
            state = .done(notePath: path)
        }
    }
}
