import test from 'node:test';
import assert from 'node:assert/strict';
import { Buffer } from 'node:buffer';
import DefaultMiniMaxProvider, {
  MiniMaxProvider,
  MiniMaxProviderError,
  createMinimaxAdapter,
  createMiniMaxAdapter,
  normalizeBaseResp,
} from './index.mjs';

const API_KEY = 'test-key-that-must-not-leak';

test('exposes a discoverable lowercase factory and all provider operations', () => {
  assert.equal(typeof createMinimaxAdapter, 'function');
  const adapter = createMinimaxAdapter({ apiKey: API_KEY, fetch: async () => { throw new Error('not called'); } });
  assert.equal(DefaultMiniMaxProvider, MiniMaxProvider);
  assert.equal(createMinimaxAdapter, createMiniMaxAdapter);
  for (const operation of ['uploadCloneAudio', 'uploadPromptAudio', 'voiceClone', 't2aV2', 'synthesize', 't2a_v2']) {
    assert.equal(typeof adapter[operation], 'function', operation);
  }
  const { uploadCloneAudio, uploadPromptAudio, voiceClone, t2aV2, synthesize } = adapter;
  assert.equal(typeof uploadCloneAudio, 'function');
  assert.equal(typeof uploadPromptAudio, 'function');
  assert.equal(typeof voiceClone, 'function');
  assert.equal(typeof t2aV2, 'function');
  assert.equal(typeof synthesize, 'function');
});


test('synthesize is a bound intuitive alias for synchronous t2aV2', async () => {
  const fetchImpl = fakeFetch(async (_url, init) => {
    assert.equal(JSON.parse(init.body).stream, false);
    return jsonResponse({ data: { audio: 'aa' }, base_resp: { status_code: 0, status_msg: 'success' } });
  });
  const adapter = createMinimaxAdapter({ apiKey: API_KEY, fetch: fetchImpl });
  const { synthesize } = adapter;
  const result = await synthesize({ text: 'hello', voiceId: 'voice-1' });
  assert.deepEqual(result.audio, Buffer.from([0xaa]));
});

test('factory operations remain callable when destructured from the adapter', async () => {
  const fetchImpl = fakeFetch(async () => jsonResponse({
    data: { audio: 'aa' },
    base_resp: { status_code: 0, status_msg: 'success' },
  }));
  const adapter = createMinimaxAdapter({ apiKey: API_KEY, fetch: fetchImpl });
  const { t2aV2 } = adapter;
  const result = await t2aV2({ text: 'hello', voiceId: 'voice-1' });
  assert.deepEqual(result.audio, Buffer.from([0xaa]));
});


function jsonResponse(body, { status = 200 } = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json' },
  });
}

function fakeFetch(handler) {
  const calls = [];
  const fetchImpl = async (url, init) => {
    calls.push({ url, init });
    return handler(url, init, calls);
  };
  fetchImpl.calls = calls;
  return fetchImpl;
}

function provider(fetchImpl, options = {}) {
  return new MiniMaxProvider({
    apiKey: API_KEY,
    fetch: fetchImpl,
    baseUrl: 'https://api.minimax.cn',
    timeoutMs: 1_000,
    ...options,
  });
}

test('normalizes official base_resp success and provider failures', () => {
  assert.deepEqual(normalizeBaseResp({ status_code: 0, status_msg: 'success' }), {
    ok: true,
    code: 0,
    message: 'success',
    statusCode: 0,
    statusMessage: 'success',
  });

  assert.throws(
    () => normalizeBaseResp({ status_code: 1004, status_msg: 'invalid file' }),
    (error) => {
      assert(error instanceof MiniMaxProviderError);
      assert.equal(error.code, 'PROVIDER_ERROR');
      assert.equal(error.providerCode, 1004);
      assert.equal(error.message, 'invalid file');
      return true;
    },
  );
});

test('uploads clone audio as multipart with server-injected authorization', async () => {
  const fetchImpl = fakeFetch(async (_url, init) => {
    assert.equal(init.headers.authorization, `Bearer ${API_KEY}`);
    assert.equal(init.headers['content-type'], undefined);
    assert(init.body instanceof FormData);
    assert.equal(init.body.get('purpose'), 'voice_clone');
    const file = init.body.get('file');
    assert.equal(file.name, 'consented.wav');
    assert.equal(file.type, 'audio/wav');
    assert.deepEqual(Buffer.from(await file.arrayBuffer()), Buffer.from('wav-bytes'));
    return jsonResponse({
      file: { file_id: 'file-clone-1' },
      base_resp: { status_code: 0, status_msg: 'success' },
    });
  });

  const result = await provider(fetchImpl).uploadCloneAudio({
    audio: Buffer.from('wav-bytes'),
    filename: 'consented.wav',
    contentType: 'audio/wav',
  });

  assert.equal(fetchImpl.calls.length, 1);
  assert.equal(fetchImpl.calls[0].url, 'https://api.minimax.cn/v1/files/upload');
  assert.equal(result.fileId, 'file-clone-1');
  assert.equal(result.baseResp.ok, true);
  assert.equal(result.baseResp.code, 0);
});

test('uploads prompt audio with the prompt_audio purpose', async () => {
  const fetchImpl = fakeFetch(async (_url, init) => {
    const form = init.body;
    assert.equal(form.get('purpose'), 'prompt_audio');
    assert.equal(form.get('file').name, 'prompt.m4a');
    return jsonResponse({ file_id: 'file-prompt-1', base_resp: { status_code: 0, status_msg: 'ok' } });
  });

  const result = await provider(fetchImpl).uploadPromptAudio({
    file: Buffer.from('prompt-bytes'),
    filename: 'prompt.m4a',
    contentType: 'audio/mp4',
  });

  assert.equal(fetchImpl.calls[0].url, 'https://api.minimax.cn/v1/files/upload');
  assert.equal(result.fileId, 'file-prompt-1');
});

test('calls voice_clone with JSON and normalizes its voice identifier', async () => {
  const fetchImpl = fakeFetch(async (_url, init) => {
    assert.equal(init.headers.authorization, `Bearer ${API_KEY}`);
    assert.equal(init.headers['content-type'], 'application/json');
    const body = JSON.parse(init.body);
    assert.equal(body.prompt_audio, undefined);
    assert.deepEqual(body, {
      file_id: 'file-clone-1',
      voice_id: 'friend-ai-voice',
      clone_prompt: { prompt_audio: 'file-prompt-1', prompt_text: '这是一段测试音色。' },
      model: 'speech-2.8-hd',
      text: '晚安，明天见。',
      text_validation: '晚安，明天见。',
      accuracy: 0.7,
      need_noise_reduction: false,
      need_volume_normalization: false,
      aigc_watermark: false,
    });
    return jsonResponse({ voice_id: 'friend-ai-voice', base_resp: { status_code: 0, status_msg: 'success' } });
  });

  const result = await provider(fetchImpl).voiceClone({
    fileId: 'file-clone-1',
    voiceId: 'friend-ai-voice',
    promptAudioFileId: 'file-prompt-1',
    promptText: '这是一段测试音色。',
    model: 'speech-2.8-hd',
    text: '晚安，明天见。',
    textValidation: '晚安，明天见。',
    accuracy: 0.7,
    needNoiseReduction: false,
    needVolumeNormalization: false,
    aigcWatermark: false,
  });

  assert.equal(fetchImpl.calls[0].url, 'https://api.minimax.cn/v1/voice_clone');
  assert.equal(result.voiceId, 'friend-ai-voice');
  assert.equal(result.baseResp.statusCode, 0);
});

test('accepts the official nested clone_prompt input and emits no legacy top-level prompt_audio', async () => {
  const fetchImpl = fakeFetch(async (_url, init) => {
    const body = JSON.parse(init.body);
    assert.deepEqual(body.clone_prompt, {
      prompt_audio: 'file-prompt-2',
      prompt_text: '官方提示文本。',
    });
    assert.equal(Object.hasOwn(body, 'prompt_audio'), false);
    assert.equal(Object.hasOwn(body.clone_prompt, 'arbitraryInput'), false);
    return jsonResponse({ voice_id: 'friend-ai-voice', base_resp: { status_code: 0, status_msg: 'success' } });
  });

  await provider(fetchImpl).voiceClone({
    file_id: 'file-clone-2',
    voice_id: 'friend-ai-voice',
    clone_prompt: {
      prompt_audio: 'file-prompt-2',
      prompt_text: '官方提示文本。',
      arbitraryInput: 'must-not-be-forwarded',
    },
    arbitraryInput: 'must-not-be-forwarded',
  });
});

test('voice_clone applies documented defaults and excludes arbitrary input', async () => {
  const fetchImpl = fakeFetch(async (_url, init) => {
    assert.deepEqual(JSON.parse(init.body), {
      file_id: 'file-clone-1',
      voice_id: 'friend-ai-voice',
      clone_prompt: { prompt_audio: 'file-prompt-1', prompt_text: '测试音色。' },
      text: '晚安，明天见。',
      model: 'speech-2.8-hd',
      text_validation: '晚安，明天见。',
      accuracy: 0.7,
      need_noise_reduction: false,
      need_volume_normalization: false,
      aigc_watermark: false,
    });
    return jsonResponse({ voice_id: 'friend-ai-voice', base_resp: { status_code: 0, status_msg: 'success' } });
  });

  await provider(fetchImpl).voiceClone({
    fileId: 'file-clone-1',
    voiceId: 'friend-ai-voice',
    promptAudioFileId: 'file-prompt-1',
    promptText: '测试音色。',
    text: '晚安，明天见。',
    arbitraryInput: 'must-not-be-forwarded',
  });
});

test('calls synchronous t2a_v2 with JSON and decodes official hex audio to Buffer', async () => {
  const fetchImpl = fakeFetch(async (_url, init) => {
    assert.equal(init.headers['content-type'], 'application/json');
    assert.deepEqual(JSON.parse(init.body), {
      model: 'speech-2.8-hd',
      text: '晚安，明天见。',
      stream: false,
      voice_setting: { voice_id: 'male-qn-qingse', speed: 1, vol: 1, pitch: 0, emotion: 'calm' },
      pronunciation_dict: { tone: ['晚安/wan3 an1'] },
      audio_setting: { sample_rate: 32_000, bitrate: 128_000, format: 'mp3', channel: 1 },
      subtitle_enable: false,
    });
    assert.equal(Object.hasOwn(JSON.parse(init.body), 'audio_sample_rate'), false);
    return jsonResponse({
      data: { audio: '000102aaff', status: 'success' },
      extra_info: { audio_format: 'mp3', audio_sample_rate: 32000, trace_note: 'safe metadata' },
      trace_id: 'trace-123',
      base_resp: { status_code: 0, status_msg: 'success' },
    });
  });

  const result = await provider(fetchImpl).t2aV2({
    text: '晚安，明天见。',
    voiceId: 'male-qn-qingse',
    model: 'speech-2.8-hd',
    voiceSetting: { speed: 1, vol: 1, pitch: 0, emotion: 'calm' },
    pronunciationDict: { tone: ['晚安/wan3 an1'] },
    audioSetting: { sample_rate: 32_000, bitrate: 128_000, format: 'mp3', channel: 1 },
  });

  assert.equal(fetchImpl.calls[0].url, 'https://api.minimax.cn/v1/t2a_v2');
  assert(Buffer.isBuffer(result.audio));
  assert.deepEqual(result.audio, Buffer.from([0, 1, 2, 0xaa, 0xff]));
  assert.equal(result.baseResp.message, 'success');
  assert.equal(result.status, 'success');
  assert.equal(result.traceId, 'trace-123');
  assert.deepEqual(result.extraInfo, {
    audio_format: 'mp3',
    audio_sample_rate: 32000,
    trace_note: 'safe metadata',
  });
});

test('maps an audio_sample_rate input alias to official sample_rate without forwarding the old key', async () => {
  const fetchImpl = fakeFetch(async (_url, init) => {
    const body = JSON.parse(init.body);
    assert.equal(body.audio_setting.sample_rate, 22_050);
    assert.equal(body.audio_setting.audio_sample_rate, undefined);
    assert.equal(body.arbitraryInput, undefined);
    return jsonResponse({ data: { audio: 'aa' }, base_resp: { status_code: 0, status_msg: 'success' } });
  });

  await provider(fetchImpl).t2aV2({
    text: 'hello',
    voiceId: 'voice-1',
    audioSetting: { audio_sample_rate: 22_050 },
    arbitraryInput: 'must-not-be-forwarded',
  });
});

test('does not log or expose the API key when upstream authentication fails', async () => {
  const fetchImpl = fakeFetch(async () => jsonResponse({ base_resp: { status_code: 1004, status_msg: 'authentication failed' } }, { status: 401 }));
  const originalError = console.error;
  const originalWarn = console.warn;
  const logs = [];
  console.error = (...args) => logs.push(args.join(' '));
  console.warn = (...args) => logs.push(args.join(' '));
  try {
    await assert.rejects(
      provider(fetchImpl).t2aV2({ text: 'hello', voiceId: 'male-qn-qingse' }),
      (error) => {
        assert(error instanceof MiniMaxProviderError);
        assert.equal(error.code, 'AUTHENTICATION_FAILED');
        assert(!error.message.includes(API_KEY));
        return true;
      },
    );
  } finally {
    console.error = originalError;
    console.warn = originalWarn;
  }
  assert.equal(logs.join('\n').includes(API_KEY), false);
});

test('maps malformed upstream JSON to a stable provider error without returning raw body', async () => {
  const fetchImpl = fakeFetch(async () => new Response('{not-json', { status: 200 }));
  await assert.rejects(
    provider(fetchImpl).t2aV2({ text: 'hello', voiceId: 'male-qn-qingse' }),
    (error) => {
      assert(error instanceof MiniMaxProviderError);
      assert.equal(error.code, 'MALFORMED_RESPONSE');
      assert.equal(error.message, 'MiniMax returned malformed JSON');
      assert.equal(error.message.includes('{not-json'), false);
      return true;
    },
  );
});

test('aborts a request on timeout and maps it to a stable timeout error', async () => {
  const fetchImpl = fakeFetch((_url, init) => new Promise((_resolve, reject) => {
    init.signal.addEventListener('abort', () => reject(init.signal.reason ?? new DOMException('aborted', 'AbortError')), { once: true });
  }));

  await assert.rejects(
    provider(fetchImpl, { timeoutMs: 10 }).t2aV2({ text: 'hello', voiceId: 'male-qn-qingse' }),
    (error) => {
      assert(error instanceof MiniMaxProviderError);
      assert.equal(error.code, 'TIMEOUT');
      return true;
    },
  );
});

test('propagates caller AbortSignal cancellation as CANCELLED', async () => {
  const fetchImpl = fakeFetch((_url, init) => new Promise((_resolve, reject) => {
    init.signal.addEventListener('abort', () => reject(init.signal.reason ?? new DOMException('aborted', 'AbortError')), { once: true });
  }));
  const controller = new AbortController();
  const request = provider(fetchImpl).t2aV2({ text: 'hello', voiceId: 'male-qn-qingse' }, { signal: controller.signal });
  controller.abort();

  await assert.rejects(request, (error) => {
    assert(error instanceof MiniMaxProviderError);
    assert.equal(error.code, 'CANCELLED');
    return true;
  });
});

test('rejects oversized audio before making a provider request', async () => {
  const fetchImpl = fakeFetch(async () => jsonResponse({}));
  await assert.rejects(
    provider(fetchImpl).uploadCloneAudio({ audio: Buffer.alloc(20 * 1024 * 1024 + 1), filename: 'voice.wav' }),
    (error) => {
      assert(error instanceof MiniMaxProviderError);
      assert.equal(error.code, 'INVALID_AUDIO');
      return true;
    },
  );
  assert.equal(fetchImpl.calls.length, 0);
});

test('uses the injected key without exposing it as public adapter state', async () => {
  const fetchImpl = fakeFetch(async (_url, init) => jsonResponse({
    data: { audio: 'aa' },
    base_resp: { status_code: 0, status_msg: 'success' },
  }));
  const client = provider(fetchImpl);
  assert.equal(client.apiKey, undefined);
  await client.t2aV2({ text: 'hello', voiceId: 'male-qn-qingse' });
  assert.equal(fetchImpl.calls[0].init.headers.authorization, `Bearer ${API_KEY}`);
  assert.doesNotMatch(JSON.stringify(new MiniMaxProviderError('UPSTREAM_ERROR', 'safe', { cause: new Error(API_KEY) })), new RegExp(API_KEY));
  assert.equal(Object.hasOwn(new MiniMaxProviderError('UPSTREAM_ERROR', 'safe', { cause: new Error(API_KEY) }), 'cause'), false);
});

test('supports string text overload and snake-case settings while forcing synchronous mode', async () => {
  const fetchImpl = fakeFetch(async (_url, init) => {
    const request = JSON.parse(init.body);
    assert.equal(request.stream, false);
    assert.equal(request.voice_setting.voice_id, 'voice-1');
    assert.equal(request.voice_setting.speed, 0.8);
    assert.equal(request.audio_setting.sample_rate, 32_000);
    assert.equal(request.audio_setting.audio_sample_rate, undefined);
    assert.equal(request.audio_setting.format, 'wav');
    return jsonResponse({ data: { audio: 'aa' }, base_resp: { status_code: 0, status_msg: 'ok' } });
  });
  const result = await provider(fetchImpl).t2aV2('hello', {
    voice_id: 'voice-1',
    voice_setting: { speed: 0.8 },
    audio_setting: { format: 'wav' },
  });
  assert.deepEqual(result.audio, Buffer.from([0xaa]));
});

test('maps HTTP status errors without parsing or exposing upstream bodies', async () => {
  const fetchImpl = fakeFetch(async () => new Response('private body with credentials', {
    status: 429,
    headers: { 'content-type': 'text/plain' },
  }));
  await assert.rejects(
    provider(fetchImpl).t2aV2({ text: 'hello', voiceId: 'voice-1' }),
    (error) => {
      assert.equal(error.code, 'RATE_LIMITED');
      assert.equal(error.status, 429);
      assert.equal(error.message.includes('private body'), false);
      return true;
    },
  );
});

test('rejects invalid hex and malformed identifiers as stable responses', async () => {
  const badAudio = fakeFetch(async () => jsonResponse({ data: { audio: 'abc' }, base_resp: { status_code: 0, status_msg: 'ok' } }));
  await assert.rejects(provider(badAudio).t2aV2({ text: 'hello', voiceId: 'voice-1' }), { code: 'MALFORMED_RESPONSE' });

  const badClone = fakeFetch(async () => jsonResponse({ base_resp: { status_code: 0, status_msg: 'ok' } }));
  await assert.rejects(provider(badClone).voiceClone({ fileId: 'file-1', voiceId: 'voice-1' }), { code: 'MALFORMED_RESPONSE' });
});

test('rejects invalid audio metadata before upload', async () => {
  const fetchImpl = fakeFetch(async () => jsonResponse({}));
  await assert.rejects(
    provider(fetchImpl).uploadCloneAudio({ audio: Buffer.from('x'), filename: 'voice.wav', durationSeconds: 9 }),
    { code: 'INVALID_AUDIO' },
  );
  await assert.rejects(
    provider(fetchImpl).uploadPromptAudio({ audio: Buffer.from('x'), filename: 'prompt.wav', durationSeconds: 8 }),
    { code: 'INVALID_AUDIO' },
  );
  assert.equal(fetchImpl.calls.length, 0);
});

test('maps a synchronous fake-fetch throw without leaking its detail', async () => {
  const fetchImpl = () => {
    throw new Error(`network detail ${API_KEY}`);
  };
  await assert.rejects(
    provider(fetchImpl).t2aV2({ text: 'hello', voiceId: 'voice-1' }),
    (error) => {
      assert.equal(error.code, 'UPSTREAM_UNAVAILABLE');
      assert.equal(error.message.includes(API_KEY), false);
      return true;
    },
  );
});
