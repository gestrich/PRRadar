import PRRadarConfigService
import SwiftUI

public struct SettingsView: View {
    @Environment(SettingsModel.self) private var settingsModel
    @Environment(\.dismiss) private var dismiss
    let selectedConfiguration: RepositoryConfiguration?
    @State private var editingConfig: RepositoryConfigurationJSON?
    @State private var isAddingNew = false
    @State private var currentError: Error?

    public init(selectedConfiguration: RepositoryConfiguration? = nil) {
        self.selectedConfiguration = selectedConfiguration
    }

    public var body: some View {
        TabView {
            Tab("Repositories", systemImage: "folder") {
                RepositoriesTabContent(
                    settingsModel: settingsModel,
                    selectedConfiguration: selectedConfiguration,
                    editingConfig: $editingConfig,
                    isAddingNew: $isAddingNew,
                    currentError: $currentError
                )
            }
            .accessibilityIdentifier("repositoriesTab")

            Tab("Credentials", systemImage: "key") {
                CredentialManagementView()
            }
            .accessibilityIdentifier("credentialsTab")
        }
        .tabViewStyle(.tabBarOnly)
        .frame(width: 700, height: 500)
        .alert("Settings Error", isPresented: isErrorPresented, presenting: currentError) { _ in
            Button("OK") { currentError = nil }
        } message: { error in
            Text(error.localizedDescription)
        }
        .sheet(item: $editingConfig) { config in
            ConfigurationEditSheet(
                config: config,
                isNew: isAddingNew,
                knownAccounts: settingsModel.credentialAccounts.map(\.account)
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

// MARK: - Repositories Tab Content

private struct RepositoriesTabContent: View {
    let settingsModel: SettingsModel
    let selectedConfiguration: RepositoryConfiguration?
    @Binding var editingConfig: RepositoryConfigurationJSON?
    @Binding var isAddingNew: Bool
    @Binding var currentError: Error?
    @State private var selectedConfigId: UUID?
    @State private var configIdToDelete: UUID?

    var body: some View {
        HSplitView {
            // Left pane - configuration list
            VStack(spacing: 0) {
                if settingsModel.settings.configurations.isEmpty {
                    ContentUnavailableView(
                        "No Configurations",
                        systemImage: "folder.badge.questionmark",
                        description: Text("Click + to add a repo configuration.")
                    )
                } else {
                    List(selection: $selectedConfigId) {
                        ForEach(settingsModel.settings.configurations) { config in
                            HStack {
                                Text(config.name)
                                if config.isDefault {
                                    Image(systemName: "star.fill")
                                        .foregroundStyle(.yellow)
                                        .font(.caption)
                                }
                            }
                            .tag(config.id)
                        }
                    }
                    .onChange(of: selectedConfigId) { _, newValue in
                        if newValue == nil, let firstConfig = settingsModel.settings.configurations.first {
                            selectedConfigId = firstConfig.id
                        }
                    }
                }

                Divider()

                HStack(spacing: 6) {
                    Button {
                        isAddingNew = true
                        editingConfig = RepositoryConfigurationJSON(name: "", repoPath: "", githubAccount: "")
                    } label: {
                        Image(systemName: "plus")
                            .frame(width: 14, height: 14)
                    }
                    .accessibilityIdentifier("addConfigButton")
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        if let configId = selectedConfigId {
                            configIdToDelete = configId
                        }
                    } label: {
                        Image(systemName: "minus")
                            .frame(width: 14, height: 14)
                    }
                    .accessibilityIdentifier("deleteConfigButton")
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(selectedConfigId == nil)

                    Spacer()
                }
                .padding(6)
            }
            .frame(minWidth: 180, idealWidth: 200, maxWidth: 250)

            // Right pane - configuration details
            Group {
                if let selectedConfigId,
                   let config = settingsModel.settings.configurations.first(where: { $0.id == selectedConfigId }) {
                    ConfigurationDetailView(
                        config: config,
                        onEdit: { editingConfig = config },
                        onSetDefault: {
                            do {
                                try settingsModel.setDefault(id: config.id)
                            } catch {
                                currentError = error
                            }
                        }
                    )
                } else {
                    ContentUnavailableView(
                        "Select a Configuration",
                        systemImage: "folder",
                        description: Text("Choose a repo configuration from the list.")
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if selectedConfigId == nil, let firstConfig = settingsModel.settings.configurations.first {
                selectedConfigId = firstConfig.id
            }
        }
        .confirmationDialog(
            "Delete Configuration",
            isPresented: Binding(
                get: { configIdToDelete != nil },
                set: { if !$0 { configIdToDelete = nil } }
            ),
            presenting: configIdToDelete.flatMap { id in
                settingsModel.settings.configurations.first(where: { $0.id == id })
            }
        ) { config in
            Button("Delete", role: .destructive) {
                do {
                    try settingsModel.removeConfiguration(id: config.id)
                    selectedConfigId = nil
                } catch {
                    currentError = error
                }
                configIdToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                configIdToDelete = nil
            }
        } message: { config in
            Text("Are you sure you want to delete the configuration '\(config.name)'?")
        }
    }
}

// MARK: - Configuration Detail View

private struct ConfigurationDetailView: View {
    let config: RepositoryConfigurationJSON
    let onEdit: () -> Void
    let onSetDefault: () -> Void

    var body: some View {
        Form {
            Section {
                LabeledContent("Name") {
                    HStack {
                        Text(config.name)
                            .foregroundStyle(.secondary)
                        if config.isDefault {
                            Image(systemName: "star.fill")
                                .foregroundStyle(.yellow)
                                .font(.caption)
                        }
                    }
                }

                LabeledContent("Repo Path") {
                    Text(config.repoPath)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                if !config.outputDir.isEmpty {
                    LabeledContent("Output Dir") {
                        Text(config.outputDir)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                if !config.rulesDir.isEmpty {
                    LabeledContent("Rules Dir") {
                        Text(config.rulesDir)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                LabeledContent("Credential Account") {
                    Text(config.githubAccount)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button("Edit") {
                    onEdit()
                }
                .accessibilityIdentifier("editConfig_\(config.name)")

                if !config.isDefault {
                    Button("Set as Default") {
                        onSetDefault()
                    }
                    .accessibilityIdentifier("setDefaultConfig_\(config.name)")
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ConfigurationEditSheet: View {
    @State var config: RepositoryConfigurationJSON
    @State private var githubAccountText: String = ""
    let isNew: Bool
    let knownAccounts: [String]
    let onSave: (RepositoryConfigurationJSON) -> Void
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
                if knownAccounts.isEmpty {
                    Text("No accounts — add one in the Credentials tab")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("", selection: $githubAccountText) {
                        Text("Select…").tag("")
                        ForEach(knownAccounts, id: \.self) { account in
                            Text(account).tag(account)
                        }
                    }
                    .labelsHidden()
                }
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    onCancel()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("Save") {
                    config.githubAccount = githubAccountText
                    onSave(config)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(config.name.isEmpty || config.repoPath.isEmpty || githubAccountText.isEmpty)
            }
        }
        .padding()
        .frame(width: 500)
        .onAppear {
            githubAccountText = config.githubAccount
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
