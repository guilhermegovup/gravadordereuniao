import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("claudeModel") private var model = "claude-opus-5"
    @AppStorage("transcriptLocale") private var localeId = "pt-BR"
    @State private var apiKey = ""
    @State private var saved = false

    var body: some View {
        Form {
            Section {
                SecureField("Chave de API da Anthropic (sk-ant-…)", text: $apiKey)
                    .onSubmit(saveKey)
                HStack {
                    Button(saved ? "Chave salva ✓" : "Salvar chave") {
                        saveKey()
                    }
                    .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Spacer()
                    Link("Obter uma chave", destination: URL(string: "https://console.anthropic.com/settings/keys")!)
                        .font(.footnote)
                }
                Picker("Modelo", selection: $model) {
                    Text("Claude Opus 5 — recomendado").tag("claude-opus-5")
                    Text("Claude Sonnet 5 — mais barato").tag("claude-sonnet-5")
                    Text("Claude Haiku 4.5 — mais rápido").tag("claude-haiku-4-5")
                }
            } header: {
                Text("Inteligência artificial")
            } footer: {
                Text("A chave fica guardada no Keychain do aparelho e é usada apenas para chamar a API do Claude ao gerar resumos e títulos.")
            }

            Section {
                Picker("Idioma da transcrição", selection: $localeId) {
                    Text("Português (Brasil)").tag("pt-BR")
                    Text("English (US)").tag("en-US")
                    Text("Español").tag("es-ES")
                    Text("Idioma do sistema").tag(Locale.current.identifier)
                }
            } header: {
                Text("Transcrição")
            } footer: {
                Text("A transcrição acontece no próprio aparelho com o reconhecimento de fala da Apple — o áudio não é enviado para a nuvem.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Ajustes")
        .onAppear {
            apiKey = KeychainHelper.load(key: ClaudeService.apiKeyKeychainKey) ?? ""
        }
        .onChange(of: apiKey) { _, _ in
            saved = false
        }
        #if os(iOS)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Concluir") {
                    saveKey()
                    dismiss()
                }
            }
        }
        #endif
    }

    private func saveKey() {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        KeychainHelper.save(trimmed, key: ClaudeService.apiKeyKeychainKey)
        saved = true
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
