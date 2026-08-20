import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Recording.createdAt, order: .reverse) private var recordings: [Recording]

    @State private var search = ""
    @State private var showRecorder = false
    @State private var selection: Recording?
    #if os(iOS)
    @State private var showSettings = false
    #endif

    private var filtered: [Recording] {
        guard !search.isEmpty else { return recordings }
        return recordings.filter {
            $0.title.localizedCaseInsensitiveContains(search)
                || $0.transcript.localizedCaseInsensitiveContains(search)
                || $0.summary.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(filtered) { recording in
                    RecordingRow(recording: recording)
                        .tag(recording)
                        .contextMenu {
                            Button(role: .destructive) {
                                delete(recording)
                            } label: {
                                Label("Apagar", systemImage: "trash")
                            }
                        }
                }
                .onDelete(perform: deleteAt)
            }
            .navigationTitle("Pauta")
            .searchable(text: $search, prompt: "Buscar em títulos e transcrições")
            .overlay {
                if recordings.isEmpty {
                    ContentUnavailableView(
                        "Nenhuma gravação",
                        systemImage: "mic.circle",
                        description: Text("Toque no botão de gravar para capturar sua primeira reunião.")
                    )
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showRecorder = true
                    } label: {
                        Label("Gravar", systemImage: "record.circle.fill")
                    }
                    .keyboardShortcut("n", modifiers: [.command])
                }
                #if os(iOS)
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showSettings = true
                    } label: {
                        Label("Ajustes", systemImage: "gearshape")
                    }
                }
                #endif
            }
            .navigationSplitViewColumnWidth(min: 260, ideal: 320)
        } detail: {
            if let selection {
                RecordingDetailView(recording: selection)
                    .id(selection.id)
            } else {
                ContentUnavailableView(
                    "Selecione uma gravação",
                    systemImage: "waveform",
                    description: Text("Escolha uma gravação na lista ou crie uma nova.")
                )
            }
        }
        .sheet(isPresented: $showRecorder) {
            RecordView()
        }
        #if os(iOS)
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                SettingsView()
            }
        }
        #endif
    }

    private func delete(_ recording: Recording) {
        if selection == recording { selection = nil }
        AudioStore.delete(recording.audioFileName)
        context.delete(recording)
        try? context.save()
    }

    private func deleteAt(_ offsets: IndexSet) {
        for index in offsets {
            delete(filtered[index])
        }
    }
}

struct RecordingRow: View {
    let recording: Recording

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(recording.title)
                .font(.headline)
                .lineLimit(1)
            HStack(spacing: 6) {
                Text(recording.createdAt, format: .dateTime.day().month(.abbreviated).hour().minute())
                Text("•")
                Text(TimeFormat.string(recording.duration))
                Spacer()
                if !recording.summary.isEmpty {
                    Image(systemName: "sparkles")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Recording.self, inMemory: true)
}
