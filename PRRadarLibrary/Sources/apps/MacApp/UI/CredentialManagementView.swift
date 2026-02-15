import PRReviewFeature
import SwiftUI

struct CredentialManagementView: View {
    @Environment(SettingsModel.self) private var settingsModel
    @Environment(\.dismiss) private var dismiss
    @State private var editingAccount: EditableCredential?
    @State private var isAddingNew = false
    @State private var currentError: Error?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Credential Accounts")
                    .font(.title2)
                    .bold()
                Spacer()
                Button {
                    isAddingNew = true
                    editingAccount = EditableCredential(accountName: "", githubToken: "", anthropicKey: "")
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityIdentifier("addCredentialButton")
            }
            .padding()

            if settingsModel.credentialAccounts.isEmpty {
                ContentUnavailableView(
                    "No Credential Accounts",
                    systemImage: "key",
                    description: Text("Add a credential account to store API tokens in the Keychain.")
                )
                .frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(settingsModel.credentialAccounts, id: \.account) { status in
                        CredentialAccountRow(
                            status: status,
                            onEdit: {
                                isAddingNew = false
                                editingAccount = EditableCredential(accountName: status.account, githubToken: "", anthropicKey: "")
                            },
                            onDelete: {
                                do {
                                    try settingsModel.removeCredentials(account: status.account)
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
                    .accessibilityIdentifier("credentialsDoneButton")
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 500, height: 350)
        .alert("Credential Error", isPresented: isErrorPresented, presenting: currentError) { _ in
            Button("OK") { currentError = nil }
        } message: { error in
            Text(error.localizedDescription)
        }
        .sheet(item: $editingAccount) { credential in
            CredentialEditSheet(
                credential: credential,
                isNew: isAddingNew
            ) { updated in
                do {
                    try settingsModel.saveCredentials(
                        account: updated.accountName,
                        githubToken: updated.githubToken.isEmpty ? nil : updated.githubToken,
                        anthropicKey: updated.anthropicKey.isEmpty ? nil : updated.anthropicKey
                    )
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

// MARK: - Supporting Types

struct EditableCredential: Identifiable {
    let id = UUID()
    var accountName: String
    var githubToken: String
    var anthropicKey: String
}

// MARK: - Row View

private struct CredentialAccountRow: View {
    let status: CredentialStatus
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(status.account)
                    .font(.headline)
                HStack(spacing: 12) {
                    tokenIndicator(label: "GitHub token", isStored: status.hasGitHubToken)
                    tokenIndicator(label: "Anthropic key", isStored: status.hasAnthropicKey)
                }
                .font(.caption)
            }

            Spacer()

            Button(action: onEdit) {
                Image(systemName: "pencil")
            }
            .accessibilityIdentifier("editCredential_\(status.account)")
            .buttonStyle(.borderless)

            Button(action: onDelete) {
                Image(systemName: "trash")
            }
            .accessibilityIdentifier("deleteCredential_\(status.account)")
            .buttonStyle(.borderless)
            .foregroundStyle(.red)
        }
        .accessibilityIdentifier("credentialRow_\(status.account)")
        .padding(.vertical, 4)
    }

    private func tokenIndicator(label: String, isStored: Bool) -> some View {
        HStack(spacing: 3) {
            Image(systemName: isStored ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isStored ? .green : .secondary)
            Text(label + ": " + (isStored ? "stored" : "not set"))
                .foregroundStyle(isStored ? .primary : .secondary)
        }
    }
}

// MARK: - Edit Sheet

private struct CredentialEditSheet: View {
    @State var credential: EditableCredential
    let isNew: Bool
    let onSave: (EditableCredential) -> Void
    let onCancel: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isNew ? "Add Credential Account" : "Edit Credential Account")
                .font(.title2)
                .bold()

            if isNew {
                LabeledContent("Account Name") {
                    TextField("e.g. work, personal", text: $credential.accountName)
                        .textFieldStyle(.roundedBorder)
                }
            } else {
                LabeledContent("Account Name") {
                    Text(credential.accountName)
                        .foregroundStyle(.secondary)
                }
            }

            LabeledContent("GitHub Token") {
                SecureField("ghp_...", text: $credential.githubToken)
                    .textFieldStyle(.roundedBorder)
            }
            if !isNew {
                Text("Leave blank to keep the existing token.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            LabeledContent("Anthropic Key") {
                SecureField("sk-ant-...", text: $credential.anthropicKey)
                    .textFieldStyle(.roundedBorder)
            }
            if !isNew {
                Text("Leave blank to keep the existing key.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    onCancel()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("Save") {
                    onSave(credential)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(credential.accountName.isEmpty || (isNew && credential.githubToken.isEmpty && credential.anthropicKey.isEmpty))
            }
        }
        .padding()
        .frame(width: 450)
    }
}
