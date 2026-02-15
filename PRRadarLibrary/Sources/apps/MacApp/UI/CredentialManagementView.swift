import PRReviewFeature
import SwiftUI

struct CredentialManagementView: View {
    @Environment(SettingsModel.self) private var settingsModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedAccount: String?
    @State private var editingAccount: EditableCredential?
    @State private var isAddingNew = false
    @State private var currentError: Error?
    @State private var accountToDelete: String?

    var body: some View {
        HSplitView {
            // Left pane - account list
            VStack(spacing: 0) {
                if settingsModel.credentialAccounts.isEmpty {
                    ContentUnavailableView(
                        "No Accounts",
                        systemImage: "key",
                        description: Text("Click + to add a credential account.")
                    )
                } else {
                    List(selection: $selectedAccount) {
                        ForEach(settingsModel.credentialAccounts, id: \.account) { status in
                            Text(status.account)
                                .tag(status.account)
                        }
                    }
                    .onChange(of: selectedAccount) { _, newValue in
                        // Prevent deselection - always keep something selected
                        if newValue == nil, let firstAccount = settingsModel.credentialAccounts.first {
                            selectedAccount = firstAccount.account
                        }
                    }
                }

                Divider()

                HStack(spacing: 6) {
                    Button {
                        isAddingNew = true
                        editingAccount = EditableCredential(accountName: "", githubToken: "", anthropicKey: "")
                    } label: {
                        Image(systemName: "plus")
                            .frame(width: 14, height: 14)
                    }
                    .accessibilityIdentifier("addCredentialButton")
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        if let account = selectedAccount {
                            accountToDelete = account
                        }
                    } label: {
                        Image(systemName: "minus")
                            .frame(width: 14, height: 14)
                    }
                    .accessibilityIdentifier("deleteCredentialButton")
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(selectedAccount == nil)

                    Spacer()
                }
                .padding(6)
            }
            .frame(minWidth: 180, idealWidth: 200, maxWidth: 250)

            // Right pane - account details
            Group {
                if let selectedAccount,
                   let status = settingsModel.credentialAccounts.first(where: { $0.account == selectedAccount }) {
                    AccountDetailView(
                        status: status,
                        onEdit: {
                            isAddingNew = false
                            editingAccount = EditableCredential(accountName: status.account, githubToken: "", anthropicKey: "")
                        }
                    )
                } else {
                    ContentUnavailableView(
                        "Select an Account",
                        systemImage: "key",
                        description: Text("Choose a credential account from the list.")
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if selectedAccount == nil, let firstAccount = settingsModel.credentialAccounts.first {
                selectedAccount = firstAccount.account
            }
        }
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
        .confirmationDialog(
            "Delete Credential Account",
            isPresented: Binding(
                get: { accountToDelete != nil },
                set: { if !$0 { accountToDelete = nil } }
            ),
            presenting: accountToDelete
        ) { account in
            Button("Delete", role: .destructive) {
                do {
                    try settingsModel.removeCredentials(account: account)
                    selectedAccount = nil
                } catch {
                    currentError = error
                }
                accountToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                accountToDelete = nil
            }
        } message: { account in
            Text("Are you sure you want to delete the credential account '\(account)'? This will remove all stored tokens from the Keychain.")
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

// MARK: - Account Detail View

private struct AccountDetailView: View {
    let status: CredentialStatus
    let onEdit: () -> Void

    var body: some View {
        Form {
            Section {
                LabeledContent("Account") {
                    Text(status.account)
                        .foregroundStyle(.secondary)
                }

                LabeledContent("GitHub Token") {
                    HStack {
                        Image(systemName: status.hasGitHubToken ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(status.hasGitHubToken ? .green : .red)
                        Text(status.hasGitHubToken ? "Stored" : "Not Set")
                            .foregroundStyle(.secondary)
                    }
                }

                LabeledContent("Anthropic Key") {
                    HStack {
                        Image(systemName: status.hasAnthropicKey ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(status.hasAnthropicKey ? .green : .red)
                        Text(status.hasAnthropicKey ? "Stored" : "Not Set")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Button("Edit") {
                    onEdit()
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
