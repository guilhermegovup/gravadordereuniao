# Pauta — gravador de reuniões com IA

App nativo para **macOS** e **iPhone/iPad**, inspirado no fluxo do Plaud: grave uma reunião, receba a transcrição na hora e transforme tudo em ata, notas ou resumo com IA (Claude).

É um único projeto SwiftUI multiplataforma — o mesmo código roda no MacBook e no iPhone.

## Funcionalidades

- 🎙️ **Gravação de áudio** (AAC/.m4a) com pausa/retomada, cronômetro e forma de onda ao vivo. No iPhone, continua gravando com o app em segundo plano.
- ✍️ **Transcrição ao vivo, no aparelho** (reconhecimento de fala da Apple, pt-BR por padrão) — funciona offline e o áudio nunca sai do dispositivo. Gravações antigas também podem ser transcritas depois.
- ✨ **Resumos com IA** via API do Claude, com modelos de resumo: Ata de reunião, Aula/Palestra, Entrevista, Brainstorm e Resumo rápido. O texto chega em streaming, como no app original.
- 🪄 **Título automático** sugerido pela IA.
- ▶️ **Player** com velocidade (1x–2x), pulos de 15s e barra de progresso.
- 🔎 **Busca** em títulos, transcrições e resumos.
- 🔐 A chave de API fica no **Keychain**; os dados ficam locais (SwiftData + arquivos de áudio em Application Support).

## Requisitos

- **Xcode 16 ou mais novo** no MacBook (o projeto usa o formato de pastas sincronizadas do Xcode 16).
- macOS 14+ para rodar no Mac; iOS 17+ para rodar no iPhone.
- Uma conta de desenvolvedor Apple (a gratuita serve para rodar nos seus próprios aparelhos).
- Uma chave de API da Anthropic para os recursos de IA: <https://console.anthropic.com/settings/keys>

## Como rodar

1. Clone o repositório e abra `Pauta.xcodeproj` no Xcode.
2. Em **Signing & Capabilities** do target `Pauta`, selecione o seu **Team** e, se quiser, troque o bundle id (`io.govup.pauta`).
3. **No MacBook:** escolha o destino *My Mac* e aperte ▶︎ (Cmd+R).
4. **No iPhone:** conecte o aparelho pelo cabo (ou Wi-Fi), escolha-o como destino e aperte ▶︎. Na primeira vez, autorize o desenvolvedor em *Ajustes → Geral → VPN e Gerenciamento de Dispositivo*.
5. Abra os **Ajustes do app** (⌘, no Mac; engrenagem no iPhone), cole sua chave de API e toque em **Salvar chave**.
6. Grave (botão de gravação ou ⌘N), pare, e use **Gerar resumo com IA**.

Na primeira gravação o sistema pede permissão de **microfone** e de **reconhecimento de fala** — aceite as duas.

## Arquitetura

| Camada | Tecnologia |
|---|---|
| Interface | SwiftUI (NavigationSplitView, mesmo código nas duas plataformas) |
| Dados | SwiftData (`Recording`) + arquivos `.m4a` em Application Support |
| Gravação | `AVAudioEngine` com um único tap alimentando arquivo, medidor e transcrição |
| Transcrição | `SFSpeechRecognizer` on-device, com rotação de requisição a cada ~50s para gravações longas |
| IA | API do Claude (`POST /v1/messages`) com streaming SSE; modelo padrão `claude-opus-5` (com fallback de recusa server-side habilitado), alternável para Sonnet 5 ou Haiku 4.5 nos Ajustes |
| Segredos | Keychain |

## Estrutura

```
Pauta/
├── PautaApp.swift              # cenas (janela principal + Settings no macOS)
├── Models/
│   ├── Recording.swift         # modelo SwiftData + armazenamento de áudio
│   └── SummaryTemplate.swift   # modelos de resumo (system prompts)
├── Services/
│   ├── AudioRecorderService.swift   # gravação + transcrição ao vivo
│   ├── AudioPlayerService.swift     # reprodução
│   ├── TranscriptionService.swift   # transcrição de arquivos já gravados
│   ├── ClaudeService.swift          # cliente HTTP da API do Claude (streaming)
│   └── KeychainHelper.swift
└── Views/
    ├── ContentView.swift       # lista + busca + navegação
    ├── RecordView.swift        # tela de gravação (waveform, transcrição ao vivo)
    ├── RecordingDetailView.swift    # player, transcrição, resumo IA
    └── SettingsView.swift
```

## Limitações e próximos passos

- **Sincronização entre Mac e iPhone** ainda não está ligada. O caminho natural é habilitar CloudKit no SwiftData (exige capability de iCloud no target e conta de desenvolvedor paga).
- A transcrição usa o reconhecimento da Apple: para pt-BR funciona bem, mas não separa quem está falando (diarização). Uma evolução seria integrar Whisper/ElevenLabs para diarização.
- Importação de arquivos de áudio externos, exportação em PDF e widgets são boas próximas iterações.

> Nota: este projeto é um estudo funcional inspirado no Plaud — não usa marca, assets nem código do produto original.
