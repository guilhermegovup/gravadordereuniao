// Cliente da API do Claude (POST /v1/messages) direto do navegador.
// O header anthropic-dangerous-direct-browser-access habilita CORS na API.

const ENDPOINT = 'https://api.anthropic.com/v1/messages';

function baseHeaders(apiKey) {
  return {
    'content-type': 'application/json',
    'x-api-key': apiKey,
    'anthropic-version': '2023-06-01',
    'anthropic-dangerous-direct-browser-access': 'true'
  };
}

function wantsFallbacks(model) {
  return /opus-5|fable-5/.test(model);
}

async function errorMessage(res) {
  try {
    const data = await res.json();
    return data?.error?.message || JSON.stringify(data).slice(0, 300);
  } catch {
    return `HTTP ${res.status}`;
  }
}

export async function streamCompletion({ system, user, model, apiKey, maxTokens = 16000, onDelta, useFallbacks = true }) {
  const headers = baseHeaders(apiKey);
  const body = {
    model,
    max_tokens: maxTokens,
    stream: true,
    system,
    messages: [{ role: 'user', content: user }]
  };
  const withFallbacks = useFallbacks && wantsFallbacks(model);
  if (withFallbacks) {
    body.fallbacks = 'default';
    headers['anthropic-beta'] = 'server-side-fallback-2026-07-01';
  }

  const res = await fetch(ENDPOINT, { method: 'POST', headers, body: JSON.stringify(body) });
  if (!res.ok) {
    const message = await errorMessage(res);
    // Conta sem acesso ao beta de fallback: tenta de novo sem o parâmetro.
    if (res.status === 400 && withFallbacks && /fallback/i.test(message)) {
      return streamCompletion({ system, user, model, apiKey, maxTokens, onDelta, useFallbacks: false });
    }
    throw new Error(`Erro da API (${res.status}): ${message}`);
  }

  const reader = res.body.getReader();
  const decoder = new TextDecoder();
  let buffer = '';
  let text = '';
  let stopReason = null;

  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    buffer += decoder.decode(value, { stream: true });
    const lines = buffer.split('\n');
    buffer = lines.pop();
    for (const line of lines) {
      if (!line.startsWith('data:')) continue;
      let event;
      try {
        event = JSON.parse(line.slice(5).trim());
      } catch {
        continue;
      }
      if (event.type === 'content_block_delta' && event.delta?.type === 'text_delta') {
        text += event.delta.text;
        onDelta?.(event.delta.text);
      } else if (event.type === 'message_delta' && event.delta?.stop_reason) {
        stopReason = event.delta.stop_reason;
      } else if (event.type === 'error') {
        throw new Error(event.error?.message || 'Erro desconhecido da API.');
      }
    }
  }

  if (stopReason === 'refusal') throw new Error('O modelo recusou esta solicitação.');
  if (!text) throw new Error('A API devolveu uma resposta vazia.');
  return text;
}

export async function complete({ system, user, model, apiKey, maxTokens = 300 }) {
  const res = await fetch(ENDPOINT, {
    method: 'POST',
    headers: baseHeaders(apiKey),
    body: JSON.stringify({
      model,
      max_tokens: maxTokens,
      system,
      messages: [{ role: 'user', content: user }]
    })
  });
  if (!res.ok) {
    throw new Error(`Erro da API (${res.status}): ${await errorMessage(res)}`);
  }
  const data = await res.json();
  if (data.stop_reason === 'refusal') throw new Error('O modelo recusou esta solicitação.');
  const text = (data.content || [])
    .filter((block) => block.type === 'text')
    .map((block) => block.text)
    .join('');
  if (!text) throw new Error('A API devolveu uma resposta vazia.');
  return text;
}
