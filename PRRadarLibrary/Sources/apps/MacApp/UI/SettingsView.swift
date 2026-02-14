import PRRadarConfigService
import SwiftUI

struct SettingsView: View {
    let model: AllPRsModel
    @Environment(SettingsModel.self) private var settingsModel
    @Environment(\.dismiss) private var dismiss
    @State private var editingConfig: RepoConfiguration?
    @State private var isAddingNew = false
    @State private var currentError: Error?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Repo Configurations")
                    .font(.title2)
                    .bold()
                Spacer()
                Button {
                    isAddingNew = true
                    editingConfig = RepoConfiguration(name: "", repoPath: "")
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityIdentifier("addConfigButton")
            }
            .padding()

            if settingsModel.settings.configurations.isEmpty {
                ContentUnavailableView(
                    "No Configurations",
                    systemImage: "folder.badge.questionmark",
                    description: Text("Add a repo configuration to get started.")
                )
                .frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(settingsModel.settings.configurations) { config in
                        ConfigurationRow(
                            config: config,
                            isSelected: config.id == model.repoConfig.id,
                            onEdit: { editingConfig = config },
                            onSetDefault: {
                                do {
                                    try settingsModel.setDefault(id: config.id)
                                } catch {
                                    currentError = error
                                }
                            },
                            onDelete: {
                                do {
                                    try settingsModel.removeConfiguration(id: config.id)
                                } catch {
                                    currentError = error
                                }
                            }
                        )
                    }
                }
            }

            Divider()

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .accessibilityIdentifier("settingsDoneButton")
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 550, height: 400)
        .alert("Settings Error", isPresented: isErrorPresented, presenting: currentError) { _ in
            Button("OK") { currentError = nil }
        } message: { error in
            Text(error.localizedDescription)
        }
        .sheet(item: $editingConfig) { config in
            ConfigurationEditSheet(
                config: config,
                isNew: isAddingNew
            ) { updatedConfig in
                do {
                    if isAddingNew {
                        try settingsModel.addConfiguration(updatedConfig)
                    } else {
                        try settingsModel.updateConfiguration(updatedConfig)
                    }
                } catch {
                    currentError = error
                }
                isAddingNew = false
            } onCancel: {
                isAddingNew = false
            }
        }
    }

    private var isErrorPresented: Binding<Bool> {
        Binding(
            get: { currentError != nil },
            set: { if !$0 { currentError = nil } }
        )
    }
}

private struct ConfigurationRow: View {
    let config: RepoConfiguration
    let isSelected: Bool
    let onEdit: () -> Void
    let onSetDefault: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(config.name)
                        .font(.headline)
                    if config.isDefault {
                        Text("Default")
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.blue.opacity(0.15))
                            .foregroundStyle(.blue)
                            .clipShape(Capsule())
                    }
                }
                Text(config.repoPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button(action: onEdit) {
                Image(systemName: "pencil")
            }
            .accessibilityIdentifier("editConfig_\(config.name)")
            .buttonStyle(.borderless)

            if !config.isDefault {
                Button(action: onSetDefault) {
                    Image(systemName: "star")
                }
                .accessibilityIdentifier("setDefaultConfig_\(config.name)")
                .buttonStyle(.borderless)
                .help("Set as default")
            }

            Button(action: onDelete) {
                Image(systemName: "trash")
            }
            .accessibilityIdentifier("deleteConfig_\(config.name)")
            .buttonStyle(.borderless)
            .foregroundStyle(.red)
        }
        .accessibilityIdentifier("configRow_\(config.name)")
        .padding(.vertical, 4)
    }
}

private struct ConfigurationEditSheet: View {
    @State var config: RepoConfiguration
    @State private var credentialAccountText: String = ""
    let isNew: Bool
    let onSave: (RepoConfiguration) -> Void
    let onCancel: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isNew ? "Add Configuration" : "Edit Configuration")
                .font(.title2)
                .bold()

            LabeledContent("Name") {
                TextField("My Repo", text: $config.name)
                    .textFieldStyle(.roundedBorder)
            }

            pathField(label: "Repo Path", text: $config.repoPath, placeholder: "/path/to/repo")
            pathField(label: "Output Dir", text: $config.outputDir, placeholder: "~/Desktop/code-reviews")
            pathField(label: "Rules Dir", text: $config.rulesDir, placeholder: "/path/to/rules")

            LabeledContent("Credential Account") {
                TextField("e.g. work, personal", text: $credentialAccountText)
                    .textFieldStyle(.roundedBorder)
            }
            Text("Optional. References a Keychain-stored credential account. Falls back to GITHUB_TOKEN environment variable.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Cancel") {
                    onCancel()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("Save") {
                    config.credentialAccount = credentialAccountText.isEmpty ? nil : credentialAccountText
                    onSave(config)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(config.name.isEmpty || config.repoPath.isEmpty)
            }
        }
        .padding()
        .frame(width: 500)
        .onAppear {
            credentialAccountText = config.credentialAccount ?? ""
        }
    }

    private func pathField(label: String, text: Binding<String>, placeholder: String) -> some View {
        LabeledContent(label) {
            HStack {
                TextField(placeholder, text: text)
                    .textFieldStyle(.roundedBorder)
                Button("Browse...") {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = false
                    panel.canChooseDirectories = true
                    panel.allowsMultipleSelection = false
                    if panel.runModal() == .OK, let url = panel.url {
                        text.wrappedValue = url.path
                    }
                }
            }
        }
    }
}
