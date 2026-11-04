import AppKit
import SwiftUI
import UniformTypeIdentifiers
import ReplyCore

struct ProjectsView: View {
    @Bindable var model: AppModel
    @State private var projectID: UUID?
    @State private var projectName = ""
    @State private var creating = false
    @State private var deleting = false
    @State private var importBatch: ImportBatch?
    @State private var document: ProjectDocument?
    @Environment(\.desk) private var desk

    private var index: Int? { model.library.projects.firstIndex { $0.id == projectID } }
    private var project: Project? { index.map { model.library.projects[$0] } }

    var body: some View {
        VStack(alignment: .leading, spacing: 21) {
            HStack(alignment: .center) {
                PageTitle(kicker: "Your library", title: "Projects", subtitle: "Give replies the product facts they need.")
                Button("New Project", systemImage: "plus") { projectName = ""; creating = true }
                    .buttonStyle(DeskButton(kind: .primary))
            }
            if let project {
                Panel {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Picker("Project", selection: $projectID) {
                                ForEach(model.library.projects) { Text($0.name).tag(Optional($0.id)) }
                            }
                            Spacer()
                            Button("Delete Project", systemImage: "trash", role: .destructive) { deleting = true }
                                .labelStyle(.iconOnly).help("Delete project")
                        }
                        if let index {
                            TextField("Project name", text: $model.library.projects[index].name)
                                .modifier(DeskField())
                        }
                    }
                }
                HStack {
                    Text("Source files").font(.system(size: 25, design: .serif))
                    Spacer()
                    Button("Choose Files", systemImage: "plus") { chooseFiles() }
                        .buttonStyle(DeskButton())
                        .disabled(project.documents.count >= DocumentImport.maxDocuments)
                }
                Text("Choose a README, CLAUDE.md, AGENTS.md, or plain text notes. ReplyAI saves a snapshot of each file you approve.")
                    .font(.callout).foregroundStyle(.secondary)
                if project.documents.isEmpty {
                    Panel {
                        DeskEmptyState(icon: "doc.text", title: "No source files yet",
                                       text: "Choose a file to give your drafts product facts.")
                    }
                }
                if !project.documents.isEmpty {
                    Panel {
                        VStack(spacing: 0) {
                            ForEach(project.documents) { doc in
                                if doc.id != project.documents.first?.id {
                                    Rectangle().fill(desk.line).frame(height: 1)
                                }
                                HStack(spacing: 11) {
                                    DeskGlyph(symbol: "doc.text")
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(doc.name).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                                        Text(doc.importedAt, format: .dateTime.month().day().year())
                                            .font(.caption).foregroundStyle(desk.muted)
                                    }
                                    Spacer(minLength: 0)
                                    Button("View Snapshot") { document = doc }.buttonStyle(DeskButton())
                                    Button("Remove", systemImage: "trash", role: .destructive) {
                                        if let index { model.library.projects[index].documents.removeAll { $0.id == doc.id } }
                                    }
                                    .labelStyle(.iconOnly).buttonStyle(DeskButton(kind: .quiet))
                                    .help("Remove snapshot")
                                }
                                .padding(.vertical, 9)
                            }
                        }
                    }
                }
            } else {
                Panel {
                    DeskEmptyState(icon: "folder", title: "No projects yet",
                                   text: "Create a project, then choose the files you want ReplyAI to read. You can attach one project to a draft.")
                }
            }
        }
        .onAppear { if projectID == nil { projectID = model.library.projects.first?.id } }
        .alert("New project", isPresented: $creating) {
            TextField("Project name", text: $projectName)
            Button("Cancel", role: .cancel) {}
            Button("Create") {
                let name = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return }
                let value = Project(name: String(name.prefix(120)))
                model.library.projects.append(value)
                projectID = value.id
            }
        }
        .confirmationDialog("Delete this project and its imported snapshots?", isPresented: $deleting) {
            Button("Delete Project", role: .destructive) {
                model.library.projects.removeAll { $0.id == projectID }
                if model.selectedProjectID == projectID { model.selectedProjectID = nil }
                projectID = model.library.projects.first?.id
            }
        }
        .sheet(item: $importBatch) { batch in
            ImportReview(batch: batch) { approved in
                guard let index = model.library.projects.firstIndex(where: { $0.id == batch.projectID }) else { return }
                let capacity = DocumentImport.maxDocuments - model.library.projects[index].documents.count
                model.library.projects[index].documents.append(contentsOf: approved.prefix(capacity))
            }
        }
        .sheet(item: $document) { doc in
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SheetHeader(kicker: "Saved snapshot", title: doc.name)
                    Spacer()
                    Button("Done") { document = nil }.buttonStyle(DeskButton(kind: .primary)).keyboardShortcut(.defaultAction)
                }
                ScrollView {
                    Text(doc.text).font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(26)
            .frame(width: 620, height: 510)
            .background(desk.canvas)
        }
    }

    private func chooseFiles() {
        guard let project else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose project documents"
        panel.prompt = "Review Files"
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.resolvesAliases = false
        panel.allowedContentTypes = [.plainText, UTType(filenameExtension: "md") ?? .plainText,
                                    UTType(filenameExtension: "markdown") ?? .plainText]
        panel.begin { response in
            guard response == .OK else { return }
            var batch = ImportBatch(projectID: project.id)
            let capacity = DocumentImport.maxDocuments - project.documents.count
            if panel.urls.count > capacity {
                batch.errors.append("A project can hold 12 files. Only the first \(capacity) selections were reviewed.")
            }
            for url in panel.urls.prefix(capacity) {
                do {
                    batch.documents.append(try DocumentImport.read(url))
                } catch {
                    batch.errors.append("\(url.lastPathComponent): \(error.localizedDescription)")
                }
            }
            importBatch = batch
        }
    }
}

private struct ImportBatch: Identifiable {
    let id = UUID()
    let projectID: UUID
    var documents: [ProjectDocument] = []
    var errors: [String] = []
}

private struct ImportReview: View {
    let batch: ImportBatch
    let add: ([ProjectDocument]) -> Void
    @State private var skipped: Set<UUID> = []
    @Environment(\.dismiss) private var dismiss
    @Environment(\.desk) private var desk

    var body: some View {
        let documents = batch.documents.filter { !skipped.contains($0.id) }
        VStack(alignment: .leading, spacing: 12) {
            SheetHeader(kicker: "Project context", title: "Review project files")
            Text("Remove sensitive details at the source before adding a file. Review text before you attach this project to a draft.")
                .foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    ForEach(batch.errors.indices, id: \.self) { index in
                        Label(batch.errors[index], systemImage: "exclamationmark.circle")
                            .foregroundStyle(.red)
                    }
                    ForEach(documents) { doc in
                        HStack {
                            Text(doc.name).font(.headline)
                            Spacer()
                            Button("Skip") { skipped.insert(doc.id) }.buttonStyle(DeskButton())
                        }
                        Text(doc.text).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                        Divider()
                    }
                    if documents.isEmpty && batch.errors.isEmpty {
                        Text("No files selected for import.").foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Spacer()
                Button(documents.isEmpty ? "Done" : "Cancel") { dismiss() }.buttonStyle(DeskButton()).keyboardShortcut(.cancelAction)
                if !documents.isEmpty {
                    Button("Add \(documents.count) \(documents.count == 1 ? "File" : "Files")") {
                        add(documents)
                        dismiss()
                    }
                    .buttonStyle(DeskButton(kind: .primary))
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(26)
        .frame(width: 620, height: 510)
        .background(desk.canvas)
    }
}
