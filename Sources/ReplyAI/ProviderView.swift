import SwiftUI
import ReplyCore

struct ProviderView: View {
    @Bindable var model: AppModel
    @State private var key = ""
    @State private var notice: String?
    @State private var failed = false
    @State private var removing = false
    @State private var localModels = LocalModels.loading
    @Environment(\.desk) private var desk

    private enum LocalModels: Equatable {
        case loading, unreachable, found([String])
    }

    private var provider: Provider { model.library.settings.provider }

    var body: some View {
        VStack(alignment: .leading, spacing: 21) {
            PageTitle(kicker: "Preferences", title: "Settings", subtitle: "Choose the model that writes your drafts.")
            Panel {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        DeskGlyph(symbol: "cpu")
                        Text("Model provider").font(.system(size: 16, weight: .semibold))
                    }
                    Picker("Provider", selection: $model.library.settings.provider) {
                        ForEach(Provider.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.large)
                    TextField("Model ID (e.g. \(provider.exampleModel))", text: $model.library.settings.model)
                        .modifier(DeskField())
                        .accessibilityLabel("Model ID")
                    Text(provider == .ollama
                         ? "Start Ollama on this Mac and enter the exact name of an installed local model."
                         : "Enter a model ID your API account can use. API usage may be billed separately.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }

            if provider == .ollama {
                Panel {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Local connection", systemImage: "internaldrive").font(.headline)
                        Text("127.0.0.1:11434").font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                        Text("ReplyAI sends to the Ollama process on this Mac. Choose a local model to keep generation on the device.")
                            .foregroundStyle(.secondary)
                        Rectangle().fill(desk.line).frame(height: 1).padding(.vertical, 3)
                        HStack(spacing: 10) {
                            switch localModels {
                            case .loading:
                                Text("Checking for installed models…").foregroundStyle(.secondary)
                            case .unreachable:
                                Label("Couldn’t reach Ollama. Start it, then refresh.", systemImage: "exclamationmark.circle")
                                    .foregroundStyle(.secondary)
                            case .found(let names) where names.isEmpty:
                                Text("Ollama is running, but no local models are installed yet.").foregroundStyle(.secondary)
                            case .found(let names):
                                Menu {
                                    ForEach(names, id: \.self) { name in
                                        Button(name) { model.library.settings.model = name }
                                    }
                                } label: {
                                    Label("Choose Installed Model", systemImage: "list.bullet")
                                }
                                .menuStyle(.borderlessButton)
                                .fixedSize()
                                .accessibilityLabel("Choose installed model")
                            }
                            Spacer(minLength: 0)
                            Button("Refresh", systemImage: "arrow.clockwise") { Task { await loadLocalModels() } }
                                .buttonStyle(DeskButton())
                                .disabled(localModels == .loading)
                        }
                        .font(.callout)
                    }
                }
            } else {
                Panel {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label("API key", systemImage: "key.horizontal").font(.headline)
                            Spacer()
                            if model.keySaved {
                                Label("Saved in Keychain", systemImage: "checkmark.circle")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        SecureField(model.keySaved ? "Enter a replacement API key" : "Enter an API key", text: $key)
                            .modifier(DeskField())
                            .accessibilityLabel("API key")
                        HStack {
                            Button("Save API Key") {
                                update("API key saved.") {
                                    try Keychain.save(key.trimmingCharacters(in: .whitespacesAndNewlines), for: provider)
                                }
                            }
                            .buttonStyle(DeskButton(kind: .primary))
                            .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            if model.keySaved {
                                Button("Remove Key", role: .destructive) { removing = true }.buttonStyle(DeskButton())
                            }
                        }
                        Text("Keys are saved in the Mac Keychain. You’ll need an API key issued by your selected provider.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
            if let notice {
                Label(notice, systemImage: failed ? "exclamationmark.circle" : "checkmark.circle")
                    .foregroundStyle(failed ? AnyShapeStyle(desk.danger) : AnyShapeStyle(HierarchicalShapeStyle.secondary))
            }

            Panel {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        DeskGlyph(symbol: "keyboard")
                        Text("Capture and reading").font(.system(size: 16, weight: .semibold))
                    }
                    HStack {
                        Text("Global shortcut")
                        Spacer(minLength: 0)
                        Picker("Global shortcut", selection: $model.library.settings.shortcut) {
                            ForEach(ShortcutPreset.allCases) { preset in
                                Text(preset.title).tag(preset).accessibilityLabel(preset.spoken)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                    if let status = model.shortcutRegistrationStatus, status != 0 {
                        Label("This shortcut couldn’t register. Another app may be using it. Pick a different one.",
                              systemImage: "exclamationmark.circle")
                            .font(.callout).foregroundStyle(desk.danger)
                    }
                    Toggle("Start drafting as soon as text is captured", isOn: $model.library.settings.generateOnCapture)
                    Text("Applies to the shortcut and the Services menu. It never replaces a reply you are working on without asking.")
                        .font(.callout).foregroundStyle(.secondary)
                    Rectangle().fill(desk.line).frame(height: 1).padding(.vertical, 3)
                    HStack {
                        Text("Editor text size")
                        Spacer(minLength: 0)
                        Picker("Editor text size", selection: $model.library.settings.textSize) {
                            ForEach(EditorTextSize.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                    }
                }
            }

            HStack(alignment: .top, spacing: 11) {
                DeskGlyph(symbol: "lock.shield")
                VStack(alignment: .leading, spacing: 5) {
                    Text("What leaves this Mac").font(.system(size: 13, weight: .semibold))
                    Text("Review Input shows the comment, reply brief, writing examples, and project excerpts included in a generation. The request starts when you click Generate Reply.")
                        .font(.system(size: 12)).foregroundStyle(desk.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(desk.inset, in: RoundedRectangle(cornerRadius: 12))
        }
        .frame(maxWidth: 670, alignment: .leading)
        .task(id: provider) {
            if provider == .ollama { await loadLocalModels() }
        }
        .onChange(of: provider) { _, _ in
            key = ""
            notice = nil
            model.checkKey()
        }
        .onChange(of: model.library.settings.shortcut) { _, preset in
            if let apply = model.applyShortcut { model.shortcutRegistrationStatus = apply(preset) }
        }
        .confirmationDialog("Remove the saved API key?", isPresented: $removing) {
            Button("Remove Key", role: .destructive) {
                update("API key removed.") { try Keychain.remove(provider) }
            }
        }
    }

    private func loadLocalModels() async {
        localModels = .loading
        do {
            localModels = .found(try await HTTPGenerator.ollamaModels())
        } catch {
            localModels = .unreachable
        }
    }

    private func update(_ success: String, action: () throws -> Void) {
        do {
            try action()
            key = ""
            notice = success
            failed = false
            model.checkKey()
        } catch {
            failed = true
            notice = error.localizedDescription
        }
    }
}
