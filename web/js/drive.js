// Integração com o Google Drive: as transcrições e resumos vão para a pasta
// "Pauta" como arquivos Markdown legíveis (com front-matter para reimportação),
// e o áudio como arquivo separado. Usa OAuth via Google Identity Services e o
// escopo drive.file (o app só enxerga arquivos que ele mesmo criou).

const SCOPE = 'https://www.googleapis.com/auth/drive.file';
const FILES = 'https://www.googleapis.com/drive/v3/files';
const UPLOAD = 'https://www.googleapis.com/upload/drive/v3/files';
const FOLDER_MIME = 'application/vnd.google-apps.folder';

let accessToken = null;
let tokenExpiry = 0;
let folderId = null;

function loadGis() {
  if (window.google?.accounts?.oauth2) return Promise.resolve();
  return new Promise((resolve, reject) => {
    const script = document.createElement('script');
    script.src = 'https://accounts.google.com/gsi/client';
    script.onload = () => resolve();
    script.onerror = () => reject(new Error('Não foi possível carregar o login do Google. Verifique a conexão.'));
    document.head.appendChild(script);
  });
}

export function isConnected() {
  return !!accessToken && Date.now() < tokenExpiry - 60000;
}

export async function connect(clientId) {
  if (!clientId) throw new Error('Informe o Client ID do Google nos Ajustes.');
  if (isConnected()) return accessToken;
  await loadGis();
  return new Promise((resolve, reject) => {
    const client = window.google.accounts.oauth2.initTokenClient({
      client_id: clientId,
      scope: SCOPE,
      callback: (resp) => {
        if (resp.error) {
          reject(new Error(`Login do Google falhou: ${resp.error}`));
          return;
        }
        accessToken = resp.access_token;
        tokenExpiry = Date.now() + (Number(resp.expires_in) || 3600) * 1000;
        resolve(accessToken);
      },
      error_callback: (err) => {
        reject(new Error(err?.message || 'Login do Google cancelado.'));
      }
    });
    client.requestAccessToken({ prompt: '' });
  });
}

async function api(url, options = {}) {
  const res = await fetch(url, {
    ...options,
    headers: {
      Authorization: `Bearer ${accessToken}`,
      ...(options.headers || {})
    }
  });
  if (res.status === 401) {
    accessToken = null;
    throw new Error('Sessão do Google expirou. Conecte ao Drive de novo.');
  }
  if (!res.ok) {
    let detail = `HTTP ${res.status}`;
    try {
      const data = await res.json();
      detail = data?.error?.message || detail;
    } catch { /* corpo não-JSON */ }
    throw new Error(`Erro do Drive: ${detail}`);
  }
  return res;
}

async function ensureFolder() {
  if (folderId) return folderId;
  const q = encodeURIComponent(`name='Pauta' and mimeType='${FOLDER_MIME}' and trashed=false`);
  const res = await api(`${FILES}?q=${q}&fields=files(id)`);
  const data = await res.json();
  if (data.files?.length) {
    folderId = data.files[0].id;
    return folderId;
  }
  const created = await api(FILES, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ name: 'Pauta', mimeType: FOLDER_MIME })
  });
  folderId = (await created.json()).id;
  return folderId;
}

function multipart(metadata, content, contentType) {
  const boundary = 'pauta' + Math.random().toString(36).slice(2);
  const body = new Blob(
    [
      `--${boundary}\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n${JSON.stringify(metadata)}\r\n`,
      `--${boundary}\r\nContent-Type: ${contentType}\r\n\r\n`,
      content,
      `\r\n--${boundary}--`
    ],
    { type: `multipart/related; boundary=${boundary}` }
  );
  return body;
}

async function findByProps(pautaId, kind) {
  const q = encodeURIComponent(
    `appProperties has { key='pautaId' and value='${pautaId}' } and ` +
    `appProperties has { key='pautaKind' and value='${kind}' } and trashed=false`
  );
  const res = await api(`${FILES}?q=${q}&fields=files(id)`);
  const data = await res.json();
  return data.files?.[0]?.id || null;
}

async function upsert({ existingId, pautaId, kind, name, content, contentType }) {
  const parent = await ensureFolder();
  let fileId = existingId || (await findByProps(pautaId, kind));
  const metadata = fileId
    ? { name, appProperties: { pautaId, pautaKind: kind } }
    : { name, parents: [parent], appProperties: { pautaId, pautaKind: kind } };
  const body = multipart(metadata, content, contentType);
  const url = fileId
    ? `${UPLOAD}/${fileId}?uploadType=multipart&fields=id`
    : `${UPLOAD}?uploadType=multipart&fields=id`;
  const res = await api(url, {
    method: fileId ? 'PATCH' : 'POST',
    headers: { 'content-type': body.type },
    body
  });
  return (await res.json()).id;
}

function sanitizeName(name) {
  return (name || 'Sem título').replace(/[\\/:*?"<>|]/g, ' ').trim().slice(0, 80);
}

function dateName(timestamp) {
  const d = new Date(timestamp);
  const pad = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}h${pad(d.getMinutes())}`;
}

export function buildMarkdown(rec) {
  return [
    '---',
    `pauta_id: ${rec.id}`,
    `titulo: ${rec.title || 'Sem título'}`,
    `criado_em: ${new Date(rec.createdAt).toISOString()}`,
    `duracao_s: ${Math.round(rec.duration || 0)}`,
    `modelo_resumo: ${rec.template || ''}`,
    '---',
    '',
    `# ${rec.title || 'Sem título'}`,
    '',
    '## Transcrição',
    '',
    rec.transcript || '_Sem transcrição._',
    '',
    '## Resumo',
    '',
    rec.summary || '_Sem resumo ainda._',
    ''
  ].join('\n');
}

export function parseMarkdown(text) {
  const match = text.match(/^---\n([\s\S]*?)\n---\n?/);
  if (!match) return null;
  const meta = {};
  for (const line of match[1].split('\n')) {
    const idx = line.indexOf(':');
    if (idx > 0) meta[line.slice(0, idx).trim()] = line.slice(idx + 1).trim();
  }
  if (!meta.pauta_id) return null;
  const body = text.slice(match[0].length);
  const transcript = (body.match(/## Transcrição\n\n([\s\S]*?)(?=\n## Resumo|$)/) || [])[1]?.trim() || '';
  const summary = (body.match(/## Resumo\n\n([\s\S]*)$/) || [])[1]?.trim() || '';
  return {
    id: meta.pauta_id,
    title: meta.titulo || 'Sem título',
    createdAt: Date.parse(meta.criado_em) || Date.now(),
    duration: Number(meta.duracao_s) || 0,
    template: meta.modelo_resumo || '',
    transcript: transcript === '_Sem transcrição._' ? '' : transcript,
    summary: summary === '_Sem resumo ainda._' ? '' : summary
  };
}

/** Envia (ou atualiza) a transcrição e, opcionalmente, o áudio de uma gravação. */
export async function syncRecording(rec, { includeAudio, audioExtension }) {
  const baseName = `${dateName(rec.createdAt)} — ${sanitizeName(rec.title)}`;
  const mdId = await upsert({
    existingId: rec.drive?.mdId || null,
    pautaId: rec.id,
    kind: 'md',
    name: `${baseName}.md`,
    content: buildMarkdown(rec),
    contentType: 'text/markdown; charset=UTF-8'
  });
  let audioId = rec.drive?.audioId || null;
  if (includeAudio && rec.audio) {
    audioId = await upsert({
      existingId: audioId,
      pautaId: rec.id,
      kind: 'audio',
      name: `${baseName}.${audioExtension}`,
      content: rec.audio,
      contentType: rec.mimeType || 'audio/mp4'
    });
  }
  return { mdId, audioId, syncedAt: Date.now() };
}

/** Lista os arquivos do app na pasta Pauta. */
export async function listRemote() {
  const parent = await ensureFolder();
  const q = encodeURIComponent(`'${parent}' in parents and trashed=false`);
  const res = await api(`${FILES}?q=${q}&fields=files(id,name,mimeType,appProperties,modifiedTime)&pageSize=1000`);
  return (await res.json()).files || [];
}

export async function downloadText(fileId) {
  const res = await api(`${FILES}/${fileId}?alt=media`);
  return res.text();
}

export async function downloadBlob(fileId) {
  const res = await api(`${FILES}/${fileId}?alt=media`);
  return res.blob();
}
