# Pauta — gravador de reuniões com IA

Grave uma reunião, receba a transcrição na hora e transforme tudo em ata, notas ou resumo com IA (Claude). Inspirado no fluxo do Plaud.

O repositório tem **duas versões** do app:

| Versão | Onde roda | Precisa de Xcode? | Sincronização |
|---|---|---|---|
| **PWA** (`web/`) — recomendada para começar | Qualquer navegador; instalável no iPhone (Safari → Compartilhar → "Adicionar à Tela de Início") e no Mac | **Não** | Google Drive (pasta "Pauta") |
| **Nativa** (`Pauta/` + `Pauta.xcodeproj`) | macOS 14+ e iOS 17+ | Sim (Xcode 16+) | — (roadmap: iCloud) |

---

## Versão PWA (sem Xcode)

### Endereço do app

O app está publicado em **<https://guilhermegovup.github.io/gravadordereuniao/>** (GitHub Pages, servido pelo branch `gh-pages`). Qualquer alteração em `web/` que chegue ao `main` é republicada automaticamente pelo workflow `Publicar PWA no GitHub Pages`.

### Instalar

- **iPhone:** abra a URL no Safari → botão Compartilhar → **Adicionar à Tela de Início**. O app abre em tela cheia, com ícone próprio.
- **MacBook:** abra a URL no Safari (Arquivo → Adicionar à Dock) ou no Chrome (ícone de instalar na barra de endereço).

### Configurar a IA

Nos **Ajustes** do app (engrenagem), cole sua chave de API da Anthropic ([obter aqui](https://console.anthropic.com/settings/keys)). A chave fica salva só no navegador e vai direto para a API — não passa por nenhum servidor nosso.

### Configurar o Google Drive (opcional, ~5 minutos, uma vez)

As transcrições e resumos vão para uma pasta **Pauta** no seu Drive, como arquivos Markdown legíveis (e o áudio junto, se quiser). É isso que sincroniza MacBook ↔ iPhone: grave num aparelho, toque em "Enviar ao Drive", e no outro use "Importar do Drive".

1. Acesse <https://console.cloud.google.com/> com sua conta Google e crie um projeto (ex.: "Pauta").
2. Em **APIs e serviços → Biblioteca**, ative a **Google Drive API**.
3. Em **APIs e serviços → Tela de permissão OAuth**, configure como *Externo*, preencha nome e e-mail e adicione seu e-mail como *usuário de teste*.
4. Em **APIs e serviços → Credenciais → Criar credenciais → ID do cliente OAuth**, tipo **Aplicativo da Web**, e em *Origens JavaScript autorizadas* adicione `https://guilhermegovup.github.io`.
5. Copie o **Client ID** gerado (termina em `.apps.googleusercontent.com`) e cole nos Ajustes do app, em Google Drive.

O app usa o escopo `drive.file`: ele só enxerga os arquivos que ele mesmo criou — nada além da pasta Pauta.

### Limitações honestas da PWA

- **No iPhone, a gravação para se a tela bloquear ou você trocar de app** (limitação do Safari para páginas web). O app mantém a tela acesa durante a gravação para atenuar; para gravar com a tela apagada, use a versão nativa.
- A transcrição ao vivo usa o reconhecimento de voz do navegador (Web Speech API). Funciona bem em pt-BR no Safari e no Chrome, mas em alguns aparelhos pode conflitar com a gravação — se acontecer, desligue "Transcrever ao vivo" nos Ajustes (a gravação continua e você pode gerar o resumo a partir do áudio em outra ferramenta).
- Os áudios ficam no armazenamento do navegador (IndexedDB). O app pede armazenamento persistente, mas o backup no Drive é a garantia real.

---

## Versão nativa (SwiftUI)

App nativo para **macOS** e **iPhone/iPad** — um único projeto SwiftUI multiplataforma, com transcrição on-device (offline) e gravação em segundo plano no iPhone.

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
