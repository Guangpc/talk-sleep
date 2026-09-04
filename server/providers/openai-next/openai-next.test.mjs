import test from 'node:test';
import assert from 'node:assert/strict';
import { OpenAINextProvider, ProviderError } from './openai-next.mjs';

const API_KEY = 'test-key-never-log';

function response(body, { status = 200, headers = {} } = {}) {
  return new Response(typeof body === 'string' ? body : JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json', ...headers },
  });
}

function fakeFetch(queue) {
  const calls = [];
  const fetch = async (url, init) => {
    calls.push({ url, init });
    const next = queue.shift();
    if (next instanceof Error) throw next;
    return typeof next === 'function' ? next(url, init) : next;
  };
  fetch.calls = calls;
  return fetch;
}

test('chat completion sends injected auth and explicit reasoning profile without exposing secrets', async () => {
  const fetch = fakeFetch([response({
    id: 'chatcmpl-1',
    choices: [{ message: { role: 'assistant', content: '晚安' } }],
  })]);
  const provider = new OpenAINextProvider({ apiKey: API_KEY, fetch });
  const result = await provider.chat({
    model: 'gpt-5.6-sol',
    messages: [{ role: 'user', content: '请说晚安' }],
    reasoning: 'high',
  });

  assert.equal(result.choices[0].message.content, '晚安');
  assert.equal(fetch.calls.length, 1);
  assert.equal(fetch.calls[0].url, 'https://api.openai-next.com/v1/chat/completions');
  assert.equal(fetch.calls[0].init.headers.authorization, 'Bearer ' + API_KEY);
  assert.deepEqual(JSON.parse(fetch.calls[0].init.body), {
    model: 'gpt-5.6-sol',
    messages: [{ role: 'user', content: '请说晚安' }],
    reasoning_effort: 'high',
    stream: false,
  });
});

test('chat rejects unsupported reasoning profile instead of silently downgrading', async () => {
  const fetch = fakeFetch([]);
  const provider = new OpenAINextProvider({ apiKey: API_KEY, fetch });
  await assert.rejects(
    provider.chat({ model: 'gpt-5.6-sol', messages: [], reasoning: 'low' }),
    (error) => error instanceof TypeError && /medium, high, xhigh/.test(error.message),
  );
  assert.equal(fetch.calls.length, 0);
});

test('chat returns normalized provider errors without leaking credentials or prompt', async () => {
  const prompt = 'private prompt that must not appear';
  const logs = [];
  const fetch = fakeFetch([response({ error: { message: 'upstream secret detail', type: 'rate_limit_error', code: 'rate_limit' } }, { status: 429 })]);
  const provider = new OpenAINextProvider({ apiKey: API_KEY, fetch, logger: { error: (...args) => logs.push(args) } });

  await assert.rejects(
    provider.chat({ model: 'gpt-5.6-sol', messages: [{ role: 'user', content: prompt }] }),
    (error) => {
      assert.ok(error instanceof ProviderError);
      assert.equal(error.kind, 'rate_limit');
      assert.equal(error.status, 429);
      assert.equal(error.message, 'OpenAI Next provider request failed (429)');
      assert.deepEqual(JSON.stringify(error), JSON.stringify({ name: 'ProviderError', kind: 'rate_limit', status: 429, message: error.message }));
      return true;
    },
  );
  const logText = JSON.stringify(logs);
  assert.doesNotMatch(logText, /test-key-never-log|Authorization|private prompt|upstream secret detail/i);
});

test('models lists provider models', async () => {
  const fetch = fakeFetch([response({ object: 'list', data: [{ id: 'gpt-5.6-sol', object: 'model' }] })]);
  const provider = new OpenAINextProvider({ apiKey: API_KEY, fetch });
  const result = await provider.models();
  assert.deepEqual(result.data.map(({ id }) => id), ['gpt-5.6-sol']);
  assert.equal(fetch.calls[0].url, 'https://api.openai-next.com/v1/models');
  assert.equal(fetch.calls[0].init.method, 'GET');
});

test('stream parses chat completion SSE data and ignores comments/done marker', async () => {
  const body = [
    ': keep-alive',
    'data: {"choices":[{"delta":{"content":"晚"}}]}',
    '',
    'data: {"choices":[{"delta":{"content":"安"}}]}',
    '',
    'data: [DONE]',
    '',
  ].join('\n');
  const fetch = fakeFetch([response(body, { headers: { 'content-type': 'text/event-stream' } })]);
  const provider = new OpenAINextProvider({ apiKey: API_KEY, fetch });
  const chunks = [];
  for await (const chunk of provider.streamChat({
    model: 'gpt-5.6-sol',
    messages: [{ role: 'user', content: 'say goodnight' }],
    reasoningEffort: 'medium',
  })) chunks.push(chunk);
  assert.deepEqual(chunks, [
    { type: 'text', text: '晚' },
    { type: 'text', text: '安' },
    { type: 'done' },
  ]);
  assert.equal(JSON.parse(fetch.calls[0].init.body).stream, true);
  assert.equal(JSON.parse(fetch.calls[0].init.body).reasoning_effort, 'medium');
});

test('stream reports normalized SSE provider errors', async () => {
  const body = 'data: {"error":{"message":"private upstream message","type":"server_error"}}\n\n';
  const fetch = fakeFetch([response(body, { headers: { 'content-type': 'text/event-stream' } })]);
  const provider = new OpenAINextProvider({ apiKey: API_KEY, fetch });
  const iterator = provider.streamChat({ model: 'gpt-5.6-sol', messages: [] });
  await assert.rejects(iterator.next(), (error) => {
    assert.ok(error instanceof ProviderError);
    assert.equal(error.kind, 'provider');
    assert.equal(error.message, 'OpenAI Next provider stream failed');
    return true;
  });
});

test('timeout aborts request and normalizes timeout error', async () => {
  let observedSignal;
  const fetch = async (_url, init) => {
    observedSignal = init.signal;
    return await new Promise((_, reject) => {
      init.signal.addEventListener('abort', () => reject(init.signal.reason), { once: true });
    });
  };
  const provider = new OpenAINextProvider({ apiKey: API_KEY, fetch, timeoutMs: 5 });
  await assert.rejects(provider.models(), (error) => {
    assert.ok(error instanceof ProviderError);
    assert.equal(error.kind, 'timeout');
    assert.equal(error.message, 'OpenAI Next provider request timed out');
    return true;
  });
  assert.equal(observedSignal.aborted, true);
});

test('caller AbortSignal cancellation is preserved as cancellation', async () => {
  const controller = new AbortController();
  const fetch = async (_url, init) => await new Promise((_, reject) => {
    init.signal.addEventListener('abort', () => reject(init.signal.reason), { once: true });
    controller.abort();
  });
  const provider = new OpenAINextProvider({ apiKey: API_KEY, fetch, timeoutMs: 1000 });
  await assert.rejects(provider.models({ signal: controller.signal }), (error) => {
    assert.ok(error instanceof ProviderError);
    assert.equal(error.kind, 'cancelled');
    assert.equal(error.message, 'OpenAI Next provider request cancelled');
    return true;
  });
});

test('api key can be read from the named environment variable without ever logging it', async () => {
  const previous = process.env.OPENAI_NEXT_API_KEY;
  process.env.OPENAI_NEXT_API_KEY = API_KEY;
  try {
    const fetch = fakeFetch([response({ object: 'list', data: [] })]);
    const provider = new OpenAINextProvider({ fetch });
    await provider.models();
    assert.match(fetch.calls[0].init.headers.authorization, /^Bearer test-key/);
  } finally {
    if (previous === undefined) delete process.env.OPENAI_NEXT_API_KEY;
    else process.env.OPENAI_NEXT_API_KEY = previous;
  }
});


test('stream timeout interrupts a pending body reader', { timeout: 500 }, async () => {
  const fetch = async () => new Response(new ReadableStream({
    start(controller) {
      controller.enqueue(new TextEncoder().encode('data: {"choices":[]}\\n\\n'));
    },
  }), { headers: { 'content-type': 'text/event-stream' } });
  const provider = new OpenAINextProvider({ apiKey: API_KEY, fetch, timeoutMs: 5 });
  const iterator = provider.streamChat({ model: 'gpt-5.6-sol', messages: [] });
  await assert.rejects(iterator.next(), (error) => {
    assert.ok(error instanceof ProviderError);
    assert.equal(error.kind, 'timeout');
    return true;
  });
});


test('constructor requires a server-injected key when the environment is empty', () => {
  const previous = process.env.OPENAI_NEXT_API_KEY;
  delete process.env.OPENAI_NEXT_API_KEY;
  try {
    assert.throws(() => new OpenAINextProvider({ fetch: fakeFetch([]) }), (error) => {
      assert.ok(error instanceof TypeError);
      assert.equal(error.message, 'OPENAI_NEXT_API_KEY is required');
      return true;
    });
  } finally {
    if (previous === undefined) delete process.env.OPENAI_NEXT_API_KEY;
    else process.env.OPENAI_NEXT_API_KEY = previous;
  }
});


test('chat normalizes an error payload even when a compatible gateway returns HTTP 200', async () => {
  const fetch = fakeFetch([response({ error: { message: 'private upstream detail', type: 'server_error' } })]);
  const provider = new OpenAINextProvider({ apiKey: API_KEY, fetch });
  await assert.rejects(provider.chat({ model: 'gpt-5.6-sol', messages: [] }), (error) => {
    assert.ok(error instanceof ProviderError);
    assert.equal(error.kind, 'provider');
    assert.equal(error.message, 'OpenAI Next provider request failed');
    assert.doesNotMatch(error.message, /private upstream detail/);
    return true;
  });
});
