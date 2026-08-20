// Gravação de áudio com MediaRecorder + medidor de nível (AnalyserNode).
// Mantém a tela acesa durante a gravação via Wake Lock quando disponível.

const MIME_CANDIDATES = ['audio/mp4', 'audio/webm;codecs=opus', 'audio/webm'];

export class Recorder {
  constructor() {
    this.stream = null;
    this.mediaRecorder = null;
    this.chunks = [];
    this.audioCtx = null;
    this.analyser = null;
    this.wakeLock = null;
    this.startedAt = 0;
    this.accumulated = 0;
    this.paused = false;
    this.mimeType = '';
  }

  static supported() {
    return !!(navigator.mediaDevices?.getUserMedia && window.MediaRecorder);
  }

  async start() {
    this.stream = await navigator.mediaDevices.getUserMedia({ audio: true });

    this.mimeType = MIME_CANDIDATES.find((m) => {
      try { return MediaRecorder.isTypeSupported(m); } catch { return false; }
    }) || '';

    const options = this.mimeType
      ? { mimeType: this.mimeType, audioBitsPerSecond: 96000 }
      : undefined;
    this.mediaRecorder = new MediaRecorder(this.stream, options);
    this.chunks = [];
    this.mediaRecorder.ondataavailable = (e) => {
      if (e.data && e.data.size > 0) this.chunks.push(e.data);
    };
    this.mediaRecorder.start(1000);

    const Ctx = window.AudioContext || window.webkitAudioContext;
    if (Ctx) {
      this.audioCtx = new Ctx();
      const source = this.audioCtx.createMediaStreamSource(this.stream);
      this.analyser = this.audioCtx.createAnalyser();
      this.analyser.fftSize = 512;
      source.connect(this.analyser);
    }

    try {
      this.wakeLock = await navigator.wakeLock?.request('screen');
    } catch {
      this.wakeLock = null;
    }

    this.startedAt = Date.now();
    this.accumulated = 0;
    this.paused = false;
  }

  elapsed() {
    if (!this.startedAt) return this.accumulated;
    return this.paused
      ? this.accumulated
      : this.accumulated + (Date.now() - this.startedAt) / 1000;
  }

  level() {
    if (!this.analyser) return 0;
    const data = new Uint8Array(this.analyser.fftSize);
    this.analyser.getByteTimeDomainData(data);
    let sum = 0;
    for (let i = 0; i < data.length; i++) {
      const v = (data[i] - 128) / 128;
      sum += v * v;
    }
    const rms = Math.sqrt(sum / data.length);
    const db = 20 * Math.log10(Math.max(rms, 0.00001));
    return Math.max(0, Math.min(1, (db + 50) / 50));
  }

  pause() {
    if (this.paused) return;
    try { this.mediaRecorder?.pause(); } catch { /* nem todo navegador suporta */ }
    this.accumulated += (Date.now() - this.startedAt) / 1000;
    this.paused = true;
  }

  resume() {
    if (!this.paused) return;
    try { this.mediaRecorder?.resume(); } catch { /* idem */ }
    this.startedAt = Date.now();
    this.paused = false;
  }

  async stop() {
    if (!this.paused && this.startedAt) {
      this.accumulated += (Date.now() - this.startedAt) / 1000;
    }
    const recorder = this.mediaRecorder;
    if (recorder && recorder.state !== 'inactive') {
      await new Promise((resolve) => {
        recorder.onstop = resolve;
        try { recorder.stop(); } catch { resolve(); }
      });
    }
    const type = recorder?.mimeType || this.mimeType || 'audio/webm';
    const blob = new Blob(this.chunks, { type });
    this.cleanup();
    return { blob, duration: this.accumulated, mimeType: type };
  }

  cancel() {
    try {
      if (this.mediaRecorder && this.mediaRecorder.state !== 'inactive') {
        this.mediaRecorder.stop();
      }
    } catch { /* ok */ }
    this.cleanup();
  }

  cleanup() {
    this.stream?.getTracks().forEach((t) => t.stop());
    this.stream = null;
    this.audioCtx?.close().catch(() => {});
    this.audioCtx = null;
    this.analyser = null;
    this.wakeLock?.release().catch(() => {});
    this.wakeLock = null;
    this.mediaRecorder = null;
    this.startedAt = 0;
  }
}

export function extensionFor(mimeType) {
  if (!mimeType) return 'webm';
  if (mimeType.includes('mp4')) return 'm4a';
  if (mimeType.includes('webm')) return 'webm';
  if (mimeType.includes('ogg')) return 'ogg';
  return 'audio';
}
