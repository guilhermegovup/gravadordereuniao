// Transcrição ao vivo com a Web Speech API (quando o navegador suporta).
// Reinicia a requisição automaticamente para cobrir gravações longas.

export class LiveTranscriber {
  constructor(lang, onUpdate, onUnavailable) {
    this.lang = lang;
    this.onUpdate = onUpdate;
    this.onUnavailable = onUnavailable;
    this.finalized = '';
    this.interim = '';
    this.active = false;
    this.recognition = null;
  }

  static supported() {
    return !!(window.SpeechRecognition || window.webkitSpeechRecognition);
  }

  start() {
    const SR = window.SpeechRecognition || window.webkitSpeechRecognition;
    if (!SR) {
      this.onUnavailable?.('Este navegador não oferece transcrição ao vivo. A gravação continua normalmente.');
      return;
    }
    this.active = true;
    this._startSession(SR);
  }

  _startSession(SR) {
    const rec = new SR();
    rec.lang = this.lang;
    rec.continuous = true;
    rec.interimResults = true;

    rec.onresult = (event) => {
      let interim = '';
      for (let i = event.resultIndex; i < event.results.length; i++) {
        const result = event.results[i];
        const text = result[0]?.transcript || '';
        if (result.isFinal) {
          this.finalized += (this.finalized ? ' ' : '') + text.trim();
        } else {
          interim += text;
        }
      }
      this.interim = interim.trim();
      this.onUpdate?.(this.text);
    };

    rec.onerror = (event) => {
      if (event.error === 'not-allowed' || event.error === 'service-not-allowed') {
        this.active = false;
        this.onUnavailable?.('A transcrição ao vivo foi bloqueada pelo navegador. A gravação continua normalmente.');
      }
      // 'no-speech' e 'aborted' são esperados; onend cuida do reinício.
    };

    rec.onend = () => {
      this.interim = '';
      if (this.active) {
        setTimeout(() => {
          if (this.active) {
            try { this._startSession(SR); } catch { this.active = false; }
          }
        }, 250);
      }
    };

    this.recognition = rec;
    try {
      rec.start();
    } catch {
      this.active = false;
      this.onUnavailable?.('Não foi possível iniciar a transcrição ao vivo. A gravação continua normalmente.');
    }
  }

  get text() {
    return [this.finalized, this.interim].filter(Boolean).join(' ').trim();
  }

  suspend() {
    // A Web Speech API não tem pausa: paramos e retomamos depois.
    this.active = false;
    try { this.recognition?.stop(); } catch { /* ok */ }
  }

  resumeListening() {
    if (!LiveTranscriber.supported() || this.active) return;
    this.active = true;
    this._startSession(window.SpeechRecognition || window.webkitSpeechRecognition);
  }

  stop() {
    this.active = false;
    try { this.recognition?.stop(); } catch { /* ok */ }
    return this.text;
  }
}
