import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var vm = MeetingViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Status banner
            statusBanner

            // Audio device pickers
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Microphone (input)")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Picker("", selection: $vm.selectedInputName) {
                        ForEach(vm.inputDevices) { device in
                            Text(device.name).tag(device.name)
                        }
                    }
                    .labelsHidden()
                    .disabled(!vm.state.isIdle)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("System audio (output)")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Picker("", selection: $vm.selectedOutputName) {
                        ForEach(vm.outputDevices) { device in
                            Text(device.name).tag(device.name)
                        }
                    }
                    .labelsHidden()
                    .disabled(!vm.state.isIdle)
                }
            }

            // Template picker
            VStack(alignment: .leading, spacing: 4) {
                Text("Obsidian Template")
                    .font(.subheadline).foregroundStyle(.secondary)
                HStack {
                    Text(vm.selectedTemplate.isEmpty ? "No template selected"
                         : (vm.selectedTemplate as NSString).lastPathComponent)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundStyle(vm.selectedTemplate.isEmpty ? .secondary : .primary)
                    Button("Choose...") { chooseTemplate() }
                        .disabled(!vm.state.isIdle)
                }
            }

            // Attendees input
            VStack(alignment: .leading, spacing: 4) {
                Text("Attendees")
                    .font(.headline)
                TextField("e.g. Sam Carlos Isabelle", text: $vm.attendeeText)
                    .textFieldStyle(.roundedBorder)
                    .disabled(!vm.state.isIdle)
                    .onChange(of: vm.attendeeText) { vm.updateSuggestions() }
                    .onSubmit { startOrStop() }

                if !vm.suggestions.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(vm.suggestions, id: \.self) { name in
                            Button(name) { vm.acceptSuggestion(name) }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                    }
                }
            }

            // Action buttons
            HStack(spacing: 12) {
                switch vm.state {
                case .idle:
                    Button("Start Recording") { vm.startRecording() }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .controlSize(.large)

                    Spacer()

                    TextField("YYYYMMDD_HHMM", text: $vm.resumeTimestamp)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 150)
                    Button("Resume") { vm.resumeFromFiles() }
                        .controlSize(.large)
                        .disabled(vm.resumeTimestamp.trimmingCharacters(in: .whitespaces).isEmpty)

                case .recording:
                    Button("Stop Recording") { vm.stopRecording() }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                        .controlSize(.large)

                case .processing:
                    ProgressView()
                        .controlSize(.small)
                    Text("Processing...")
                        .foregroundStyle(.secondary)

                case .done:
                    Button("Open Note") { vm.openInObsidian() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    Button("New Meeting") { vm.reset() }
                        .controlSize(.large)

                case .error:
                    Button("Try Again") { vm.reset() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                }
            }

            // Log output
            VStack(alignment: .leading, spacing: 4) {
                Text("Log")
                    .font(.headline)
                ScrollViewReader { proxy in
                    ScrollView {
                        if vm.state.isRecording {
                            Text("Recording...")
                                .font(.system(.caption, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .foregroundStyle(.secondary)
                        } else {
                            Text(vm.logOutput.isEmpty ? "Waiting to start..." : vm.logOutput)
                                .font(.system(.caption, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .foregroundStyle(vm.logOutput.isEmpty ? .secondary : .primary)
                                .textSelection(.enabled)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .onChange(of: vm.logOutput) {
                        withAnimation { proxy.scrollTo("bottom") }
                    }
                }
                .frame(maxHeight: .infinity)
                .padding(8)
                .background(.background.secondary)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(20)
        .frame(width: 520, height: 620)
    }

    @ViewBuilder
    private var statusBanner: some View {
        HStack(spacing: 8) {
            switch vm.state {
            case .idle:
                Circle().fill(.secondary).frame(width: 10, height: 10)
                Text("Ready")

            case .recording:
                Circle().fill(.red).frame(width: 10, height: 10)
                    .shadow(color: .red.opacity(0.6), radius: 4)
                Text("Recording")
                    .foregroundStyle(.red)
                    .bold()

            case .processing(let step):
                ProgressView().controlSize(.mini)
                Text(step)
                    .foregroundStyle(.orange)

            case .done:
                Circle().fill(.green).frame(width: 10, height: 10)
                Text("Done")
                    .foregroundStyle(.green)

            case .error(let message):
                Circle().fill(.red).frame(width: 10, height: 10)
                Text(message)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
        }
        .font(.callout)
    }

    private func chooseTemplate() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "md")!]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Choose Obsidian Template"
        // Start in the directory of the current template if possible
        if !vm.selectedTemplate.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: (vm.selectedTemplate as NSString).deletingLastPathComponent)
        }
        if panel.runModal() == .OK, let url = panel.url {
            vm.selectedTemplate = url.path
        }
    }

    private func startOrStop() {
        if vm.state.isIdle {
            vm.startRecording()
        } else if vm.state.isRecording {
            vm.stopRecording()
        }
    }
}
