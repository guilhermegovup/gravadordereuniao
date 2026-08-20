// Pauta — aplicação principal: estado, telas e ações.

import { allRecordings, putRecording, deleteRecording } from './db.js';
import { Recorder, extensionFor } from './recorder.js';
import { LiveTranscriber } from './speech.js';
import { streamCompletion, complete } from './claude.js';
import * as drive from './drive.js';
import { TEMPLATES, TITLE_SYSTEM } from './templates.js';

const $ = (id) => document.getElementById(id);

// ---------- Configurações ----------
const settings = {
  get apiKey() { return localStorage.getItem('pauta.apiKey') || ''; },
  set apiKey(v) { localStorage.setItem('pauta.apiKey', v); },
  get model() { return localStorage.getItem('pauta.model') || 'claude-opus-5'; },
  set model(v) { localStorage.setItem('pauta.model', v); },
  get lang() { return localStorage.getItem('pauta.lang') || 'pt-BR'; },
  set lang(v) { localStorage.setItem('pauta.lang', v); },
  get liveTranscribe() { return localStorage.getItem('pauta.live') !== '0'; },
  set liveTranscribe(v) { localStorage.setItem('pauta.live', v ? '1' : '0'); },
  get driveClientId() { return localStorage.getItem('pauta.driveClientId') || ''; },
  set driveClientId(v) { localStorage.setItem('pauta.driveClientId', v); },
  get autoDrive() { return localStorage.getItem('pauta.autoDrive') === '1'; },
  set autoDrive(v) { localStorage.setItem('pauta.autoDrive', v ? '1' : '0'); },
  get driveAudio() { return localStorage.getItem('pauta.driveAudio') !== '0'; },
  set driveAudio(v) { localStorage.setItem('pauta.driveAudio', v ? '1' : '0'); }
};

// ---------- Estado ----------
let recordings = [];
let selectedId = null;
let audioUrl = null;
let generating = false;

// ---------- Utilitários ----------
function fmtTime(seconds) {
  const total = Math.round(seconds || 0);
  const h = Math.floor(total / 3600);
  const m = Math.floor((total % 3600) / 60);
  const s = total % 60;
  const pad = (n) => String(n).padStart(2, '0');
  return h > 0 ? `${h}:${pad(m)}:${pad(s)}` : `${pad(m)}:${pad(s)}`;
}

function fmtDate(timestamp) {
  return new Intl.DateTimeFormat('pt-BR', { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' })
    .format(new Date(timestamp));
}

function fmtDateLong(timestamp) {
  return new Intl.DateTimeFormat('pt-BR', { day: 'numeric', month: 'long', year: 'numeric', hour: '2-digit', minute: '2-digit' })
    .format(new Date(timestamp));
}

let toastTimer = null;
function toast(message) {
  const el = $('toast');
  el.textContent = message;
  el.hidden = false;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => { el.hidden = true; }, 3500);
}

function escapeHtml(text) {
  return text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

function inlineMd(text) {
  return escapeHtml(text)
    .replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>')
    .replace(/(^|\W)\*([^*\n]+)\*(?=\W|$)/g, '$1<em>$2</em>');
}

function mdToHtml(markdown) {
  const out = [];
  let inList = false;
  for (const rawLine of (markdown || '').split('\n')) {
    const line = rawLine.trim();
    const isBullet = line.startsWith('- ') || line.startsWith('* ');
    if (inList && !isBullet) { out.push('</ul>'); inList = false; }
    if (line.startsWith('### ')) out.push(`<h3>${inlineMd(line.slice(4))}</h3>`);
    else if (line.startsWith('## ')) out.push(`<h2>${inlineMd(line.slice(3))}</h2>`);
    else if (line.startsWith('# ')) out.push(`<h2>${inlineMd(line.slice(2))}</h2>`);
    else if (isBullet) {
      if (!inList) { out.push('<ul>'); inList = true; }
      out.push(`<li>${inlineMd(line.slice(2))}</li>`);
    } else if (line) out.push(`<p>${inlineMd(line)}</p>`);
  }
  if (inList) out.push('</ul>');
  return out.join('');
}

function selected() {
  return recordings.find((r) => r.id === selectedId) || null;
}

async function save(rec) {
  await putRecording(rec);
}

// ---------- Lista ----------
function renderList() {
  const query = $('search').value.trim().toLowerCase();
  const list = $('rec-list');
  const visible = query
    ? recordings.filter((r) =>
        (r.title || '').toLowerCase().includes(query) ||
        (r.transcript || '').toLowerCase().includes(query) ||
        (r.summary || '').toLowerCase().includes(query))
    : recordings;

  list.innerHTML = '';
  for (const rec of visible) {
    const li = document.createElement('li');
    li.className = 'rec-item' + (rec.id === selectedId ? ' active' : '');
    li.innerHTML = `
      <h3></h3>
      <div class="line2">
        <span class="when"></span>
        ${rec.summary ? '<span class="ai-mark" title="Tem resumo IA">✦</span>' : ''}
        <span class="dur mono"></span>
      </div>`;
    li.querySelector('h3').textContent = rec.title || 'Sem título';
    li.querySelector('.when').textContent = fmtDate(rec.createdAt);
    li.querySelector('.dur').textContent = fmtTime(rec.duration);
    li.addEventListener('click', () => select(rec.id));
    list.appendChild(li);
  }
  $('empty-state').hidden = recordings.length > 0;
}

// ---------- Detalhe ----------
function select(id) {
  selectedId = id;
  const rec = selected();
  const detail = $('pane-detail');
  if (!rec) {
    detail.hidden = true;
    renderList();
    return;
  }
  detail.hidden = false;
  document.body.classList.add('detail-open');
  if (window.innerWidth < 880) $('pane-list').style.display = 'none';

  $('detail-title').value = rec.title || '';
  $('detail-meta').textContent = `${fmtDateLong(rec.createdAt)} • ${fmtTime(rec.duration)}`;
  $('detail-error').hidden = true;
  $('summary-status').hidden = true;

  loadAudio(rec);
  renderTranscript(rec);
  renderSummary(rec);
  showTab('transcript');
  renderList();
}

function closeDetail() {
  selectedId = null;
  $('pane-detail').hidden = true;
  $('pane-list').style.display = '';
  document.body.classList.remove('detail-open');
  stopPlayback();
  renderList();
}

function renderTranscript(rec) {
  const has = !!(rec.transcript && rec.transcript.trim());
  $('transcript-empty').hidden = has;
  $('transcript-view').innerHTML = '';
  if (has) {
    const article = $('transcript-view');
    for (const paragraph of rec.transcript.split('\n')) {
      if (!paragraph.trim()) continue;
      const p = document.createElement('p');
      p.textContent = paragraph;
      article.appendChild(p);
    }
  }
}

function renderSummary(rec) {
  $('summary-view').innerHTML = rec.summary ? mdToHtml(rec.summary) : '';
  $('summary-setup').style.display = rec.summary || generating ? 'none' : 'flex';
  $('btn-summary').disabled = !(rec.transcript && rec.transcript.trim());
}

function showTab(which) {
  $('tab-transcript').classList.toggle('active', which === 'transcript');
  $('tab-summary').classList.toggle('active', which === 'summary');
  $('pane-transcript').hidden = which !== 'transcript';
  $('pane-summary').hidden = which !== 'summary';
}

function showError(message) {
  const el = $('detail-error');
  el.textContent = message;
  el.hidden = false;
}

// ---------- Player ----------
const audio = new Audio();
const RATES = [1, 1.25, 1.5, 2];
let rateIndex = 0;

function loadAudio(rec) {
  stopPlayback();
  const note = $('audio-note');
  if (rec.audio) {
    audioUrl = URL.createObjectURL(rec.audio);
    audio.src = audioUrl;
    $('player').style.opacity = '';
    note.hidden = true;
  } else {
    audio.removeAttribute('src');
    $('player').style.opacity = '0.4';
    note.textContent = rec.drive?.audioId
      ? 'O áudio desta gravação está no Google Drive. Use “⋯ → Baixar áudio do Drive”.'
      : 'Esta gravação não tem arquivo de áudio neste aparelho.';
    note.hidden = false;
  }
  $('player-pos').textContent = '00:00';
  $('player-dur').textContent = fmtTime(rec.duration);
  $('player-seek').value = 0;
  $('btn-play').textContent = '▶';
}

function stopPlayback() {
  audio.pause();
  if (audioUrl) {
    URL.revokeObjectURL(audioUrl);
    audioUrl = null;
  }
}

audio.addEventListener('timeupdate', () => {
  if (!audio.duration || !isFinite(audio.duration)) return;
  $('player-pos').textContent = fmtTime(audio.currentTime);
  $('player-seek').value = (audio.currentTime / audio.duration) * 100;
});
audio.addEventListener('loadedmetadata', () => {
  if (isFinite(audio.duration)) $('player-dur').textContent = fmtTime(audio.duration);
});
audio.addEventListener('ended', () => { $('btn-play').textContent = '▶'; });
audio.addEventListener('pause', () => { $('btn-play').textContent = '▶'; });
audio.addEventListener('play', () => { $('btn-play').textContent = '⏸'; });

$('btn-play').addEventListener('click', () => {
  if (!audio.src) return;
  if (audio.paused) audio.play().catch(() => toast('Não foi possível reproduzir o áudio.'));
  else audio.pause();
});
$('player-seek').addEventListener('input', () => {
  if (audio.duration && isFinite(audio.duration)) {
    audio.currentTime = (Number($('player-seek').value) / 100) * audio.duration;
  }
});
$('btn-rate').addEventListener('click', () => {
  rateIndex = (rateIndex + 1) % RATES.length;
  audio.playbackRate = RATES[rateIndex];
  $('btn-rate').textContent = `${RATES[rateIndex]}x`;
});

// ---------- Gravação ----------
let recorder = null;
let transcriber = null;
let recRaf = 0;
let waveLevels = new Array(64).fill(0);

async function startRecording() {
  if (!Recorder.supported()) {
    toast('Este navegador não suporta gravação de áudio.');
    return;
  }
  recorder = new Recorder();
  $('rec-error').hidden = true;
  $('rec-transcript').innerHTML = '<span class="muted">A transcrição ao vivo aparece aqui enquanto você fala…</span>';
  $('rec-lang').textContent = settings.lang;
  $('rec-state').textContent = 'Gravando';
  $('record-overlay').hidden = false;
  $('record-overlay').classList.remove('paused');

  try {
    await recorder.start();
  } catch (err) {
    $('record-overlay').hidden = true;
    toast(err?.name === 'NotAllowedError'
      ? 'Permissão de microfone negada. Libere o acesso nas configurações do navegador.'
      : `Não foi possível gravar: ${err.message || err}`);
    recorder = null;
    return;
  }

  if (settings.liveTranscribe) {
    transcriber = new LiveTranscriber(
      settings.lang,
      (text) => { $('rec-transcript').textContent = text || ''; scrollTranscript(); },
      (message) => { const el = $('rec-error'); el.textContent = message; el.hidden = false; }
    );
    transcriber.start();
  } else {
    transcriber = null;
  }

  waveLevels = new Array(64).fill(0);
  const canvas = $('rec-wave');
  const draw = () => {
    if (!recorder) return;
    $('rec-timer').textContent = fmtTime(recorder.elapsed());
    if (!recorder.paused) {
      waveLevels.shift();
      waveLevels.push(recorder.level());
    }
    drawWave(canvas, waveLevels);
    recRaf = requestAnimationFrame(draw);
  };
  recRaf = requestAnimationFrame(draw);
}

function scrollTranscript() {
  const box = $('rec-transcript');
  box.scrollTop = box.scrollHeight;
}

function drawWave(canvas, levels) {
  const dpr = window.devicePixelRatio || 1;
  const width = canvas.clientWidth || canvas.parentElement.clientWidth || 300;
  const height = 80;
  if (canvas.width !== width * dpr) { canvas.width = width * dpr; canvas.height = height * dpr; }
  const ctx = canvas.getContext('2d');
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  ctx.clearRect(0, 0, width, height);
  const barWidth = 3;
  const gap = Math.max(2, (width - levels.length * barWidth) / (levels.length - 1));
  const style = getComputedStyle(document.documentElement);
  ctx.fillStyle = style.getPropertyValue('--text').trim() || '#E9E7E1';
  levels.forEach((level, i) => {
    const barHeight = Math.max(3, level * height * 0.9);
    const x = i * (barWidth + gap);
    ctx.fillRect(x, (height - barHeight) / 2, barWidth, barHeight);
  });
}

function stopRecordingUi() {
  cancelAnimationFrame(recRaf);
  $('record-overlay').hidden = true;
}

$('btn-record').addEventListener('click', startRecording);

$('btn-rec-pause').addEventListener('click', () => {
  if (!recorder) return;
  if (recorder.paused) {
    recorder.resume();
    transcriber?.resumeListening();
    $('rec-state').textContent = 'Gravando';
    $('btn-rec-pause').textContent = '⏸';
    $('record-overlay').classList.remove('paused');
  } else {
    recorder.pause();
    transcriber?.suspend();
    $('rec-state').textContent = 'Pausado';
    $('btn-rec-pause').textContent = '▶';
    $('record-overlay').classList.add('paused');
  }
});

$('btn-rec-cancel').addEventListener('click', () => {
  transcriber?.stop();
  recorder?.cancel();
  recorder = null;
  transcriber = null;
  stopRecordingUi();
});

$('btn-rec-stop').addEventListener('click', async () => {
  if (!recorder) return;
  const transcript = transcriber ? transcriber.stop() : '';
  const { blob, duration, mimeType } = await recorder.stop();
  recorder = null;
  transcriber = null;
  stopRecordingUi();

  if (!blob.size && !transcript) {
    toast('Nada foi gravado.');
    return;
  }

  const rec = {
    id: crypto.randomUUID(),
    title: `Gravação de ${fmtDate(Date.now())}`,
    createdAt: Date.now(),
    duration,
    audio: blob.size ? blob : null,
    mimeType,
    transcript,
    summary: '',
    template: '',
    drive: null
  };
  await save(rec);
  recordings.unshift(rec);
  select(rec.id);
  toast('Gravação salva.');

  if (settings.autoDrive && settings.driveClientId) {
    sendToDrive(rec, { silent: true });
  }
});

// ---------- IA ----------
async function generateSummary() {
  const rec = selected();
  if (!rec || generating) return;
  if (!rec.transcript?.trim()) { showError('Esta gravação não tem transcrição para resumir.'); return; }
  if (!settings.apiKey) { showError('Configure sua chave de API da Anthropic nos Ajustes.'); return; }

  const template = TEMPLATES.find((t) => t.id === $('template-select').value) || TEMPLATES[0];
  generating = true;
  showTab('summary');
  $('summary-setup').style.display = 'none';
  $('detail-error').hidden = true;
  const status = $('summary-status');
  status.textContent = '✦ Gerando com o Claude…';
  status.hidden = false;
  const view = $('summary-view');
  view.innerHTML = '';
  let buffer = '';

  try {
    const text = await streamCompletion({
      system: template.system,
      user: `Transcrição da gravação:\n\n${rec.transcript}`,
      model: settings.model,
      apiKey: settings.apiKey,
      onDelta: (delta) => {
        buffer += delta;
        view.innerHTML = mdToHtml(buffer);
      }
    });
    rec.summary = text;
    rec.template = template.id;
    await save(rec);
    status.hidden = true;
    renderSummary(rec);
    renderList();
    toast('Resumo pronto.');
  } catch (err) {
    status.hidden = true;
    showError(err.message || String(err));
    renderSummary(rec);
  } finally {
    generating = false;
  }
}

async function suggestTitle() {
  const rec = selected();
  if (!rec?.transcript?.trim()) { toast('Sem transcrição para basear o título.'); return; }
  if (!settings.apiKey) { showError('Configure sua chave de API da Anthropic nos Ajustes.'); return; }
  toast('Sugerindo título…');
  try {
    const title = await complete({
      system: TITLE_SYSTEM,
      user: `Crie um título para esta gravação:\n\n${rec.transcript.slice(0, 3000)}`,
      model: settings.model,
      apiKey: settings.apiKey
    });
    rec.title = title.trim().replace(/^["“”']|["“”']$/g, '');
    await save(rec);
    $('detail-title').value = rec.title;
    renderList();
  } catch (err) {
    showError(err.message || String(err));
  }
}

// ---------- Google Drive ----------
function updateDriveBadge() {
  $('drive-badge').hidden = !drive.isConnected();
}

async function connectDrive() {
  try {
    await drive.connect(settings.driveClientId);
    updateDriveBadge();
    toast('Conectado ao Google Drive.');
    return true;
  } catch (err) {
    toast(err.message || String(err));
    return false;
  }
}

async function sendToDrive(rec, { silent = false } = {}) {
  if (!settings.driveClientId) {
    if (!silent) toast('Configure o Client ID do Google nos Ajustes.');
    return;
  }
  try {
    if (!drive.isConnected() && !(await connectDrive())) return;
    if (!silent) toast('Enviando ao Drive…');
    rec.drive = await drive.syncRecording(rec, {
      includeAudio: settings.driveAudio,
      audioExtension: extensionFor(rec.mimeType)
    });
    await save(rec);
    if (!silent) toast('Enviado à pasta Pauta do seu Drive.');
  } catch (err) {
    toast(err.message || String(err));
  }
}

async function importFromDrive() {
  if (!settings.driveClientId) { toast('Configure o Client ID do Google nos Ajustes.'); return; }
  if (!drive.isConnected() && !(await connectDrive())) return;
  toast('Procurando gravações no Drive…');
  try {
    const files = await drive.listRemote();
    const mdFiles = files.filter((f) => f.appProperties?.pautaKind === 'md');
    const audioByPautaId = new Map(
      files.filter((f) => f.appProperties?.pautaKind === 'audio')
        .map((f) => [f.appProperties.pautaId, f.id])
    );
    let imported = 0;
    for (const file of mdFiles) {
      const pautaId = file.appProperties.pautaId;
      if (recordings.some((r) => r.id === pautaId)) continue;
      const text = await drive.downloadText(file.id);
      const parsed = drive.parseMarkdown(text);
      if (!parsed) continue;
      const rec = {
        ...parsed,
        audio: null,
        mimeType: '',
        drive: { mdId: file.id, audioId: audioByPautaId.get(pautaId) || null, syncedAt: Date.now() }
      };
      await save(rec);
      recordings.push(rec);
      imported++;
    }
    recordings.sort((a, b) => b.createdAt - a.createdAt);
    renderList();
    toast(imported
      ? `${imported} gravação(ões) importada(s) do Drive.`
      : 'Nada novo para importar — tudo já está neste aparelho.');
  } catch (err) {
    toast(err.message || String(err));
  }
}

async function downloadAudioFromDrive() {
  const rec = selected();
  if (!rec?.drive?.audioId) { toast('Esta gravação não tem áudio no Drive.'); return; }
  if (!drive.isConnected() && !(await connectDrive())) return;
  toast('Baixando áudio do Drive…');
  try {
    const blob = await drive.downloadBlob(rec.drive.audioId);
    rec.audio = blob;
    rec.mimeType = blob.type || 'audio/mp4';
    await save(rec);
    loadAudio(rec);
    toast('Áudio baixado.');
  } catch (err) {
    toast(err.message || String(err));
  }
}

// ---------- Menu de ações ----------
function openActions() {
  const rec = selected();
  if (!rec) return;
  $('act-drive-audio').hidden = !(rec.drive?.audioId && !rec.audio);
  $('act-download').hidden = !rec.audio;
  $('actions-backdrop').hidden = false;
}
function closeActions() { $('actions-backdrop').hidden = true; }

$('btn-more').addEventListener('click', openActions);
$('act-close').addEventListener('click', closeActions);
$('actions-backdrop').addEventListener('click', (e) => {
  if (e.target === $('actions-backdrop')) closeActions();
});

$('act-title').addEventListener('click', () => { closeActions(); suggestTitle(); });
$('act-copy-transcript').addEventListener('click', async () => {
  closeActions();
  const rec = selected();
  if (!rec?.transcript) { toast('Sem transcrição para copiar.'); return; }
  await navigator.clipboard.writeText(rec.transcript);
  toast('Transcrição copiada.');
});
$('act-copy-summary').addEventListener('click', async () => {
  closeActions();
  const rec = selected();
  if (!rec?.summary) { toast('Sem resumo para copiar.'); return; }
  await navigator.clipboard.writeText(rec.summary);
  toast('Resumo copiado.');
});
$('act-download').addEventListener('click', () => {
  closeActions();
  const rec = selected();
  if (!rec?.audio) return;
  const a = document.createElement('a');
  a.href = URL.createObjectURL(rec.audio);
  a.download = `${rec.title || 'gravacao'}.${extensionFor(rec.mimeType)}`;
  a.click();
  setTimeout(() => URL.revokeObjectURL(a.href), 10000);
});
$('act-drive').addEventListener('click', () => {
  closeActions();
  const rec = selected();
  if (rec) sendToDrive(rec);
});
$('act-drive-audio').addEventListener('click', () => { closeActions(); downloadAudioFromDrive(); });
$('act-delete').addEventListener('click', async () => {
  closeActions();
  const rec = selected();
  if (!rec) return;
  if (!confirm(`Apagar "${rec.title}" deste aparelho? (arquivos já enviados ao Drive não são apagados)`)) return;
  await deleteRecording(rec.id);
  recordings = recordings.filter((r) => r.id !== rec.id);
  closeDetail();
  toast('Gravação apagada.');
});

// ---------- Ajustes ----------
function openSettings() {
  $('set-apikey').value = settings.apiKey;
  $('set-model').value = settings.model;
  $('set-lang').value = settings.lang;
  $('set-live').checked = settings.liveTranscribe;
  $('set-client').value = settings.driveClientId;
  $('set-autodrive').checked = settings.autoDrive;
  $('set-driveaudio').checked = settings.driveAudio;
  $('settings-backdrop').hidden = false;
}
function saveSettings() {
  settings.apiKey = $('set-apikey').value.trim();
  settings.model = $('set-model').value;
  settings.lang = $('set-lang').value;
  settings.liveTranscribe = $('set-live').checked;
  settings.driveClientId = $('set-client').value.trim();
  settings.autoDrive = $('set-autodrive').checked;
  settings.driveAudio = $('set-driveaudio').checked;
  toast('Ajustes salvos.');
}
$('btn-settings').addEventListener('click', openSettings);
$('btn-settings-save').addEventListener('click', () => { saveSettings(); $('settings-backdrop').hidden = true; });
$('btn-settings-close').addEventListener('click', () => { $('settings-backdrop').hidden = true; });
$('settings-backdrop').addEventListener('click', (e) => {
  if (e.target === $('settings-backdrop')) $('settings-backdrop').hidden = true;
});
$('btn-drive-connect').addEventListener('click', () => {
  settings.driveClientId = $('set-client').value.trim();
  connectDrive();
});
$('btn-drive-import').addEventListener('click', () => {
  settings.driveClientId = $('set-client').value.trim();
  importFromDrive();
});

// ---------- Demais eventos ----------
$('search').addEventListener('input', renderList);
$('btn-back').addEventListener('click', closeDetail);
$('tab-transcript').addEventListener('click', () => showTab('transcript'));
$('tab-summary').addEventListener('click', () => showTab('summary'));
$('btn-summary').addEventListener('click', generateSummary);
$('detail-title').addEventListener('change', async () => {
  const rec = selected();
  if (!rec) return;
  rec.title = $('detail-title').value.trim() || 'Sem título';
  await save(rec);
  renderList();
});

// ---------- Inicialização ----------
function fillTemplates() {
  const select = $('template-select');
  for (const template of TEMPLATES) {
    const option = document.createElement('option');
    option.value = template.id;
    option.textContent = template.name;
    select.appendChild(option);
  }
}

async function init() {
  fillTemplates();
  recordings = await allRecordings();
  renderList();
  updateDriveBadge();

  if ('serviceWorker' in navigator) {
    navigator.serviceWorker.register('./sw.js').catch(() => {});
  }
  // Pede armazenamento persistente para o navegador não descartar os áudios.
  navigator.storage?.persist?.().catch(() => {});
}

init();
