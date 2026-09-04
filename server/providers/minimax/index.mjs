import { Buffer } from 'node:buffer';

export const DEFAULT_BASE_URL = 'https://api.minimax.cn';
export const DEFAULT_T2A_MODEL = 'speech-2.8-hd';
export const MAX_AUDIO_BYTES = 20 * 1024 * 1024;

const AUDIO_TYPES = new Map([
  ['.mp3', 'audio/mpeg'],
  ['.m4a', 'audio/mp4'],
  ['.wav', 'audio/wav'],
]);

const own = (object, key) => Object.prototype.hasOwnProperty.call(object, key);
const isRecord = (value) => value !== null && typeof value === 'object' && !Array.isArray(value);

function messageFor(value, fallback) {
  if (typeof value === 'string' && value.trim()) return value.trim();
  if (value === undefined || value === null) return fallback;
  return String(value);
}

function redact(message, secret, fallback = 'MiniMax request failed') {
  const text = messageFor(message, fallback);
  return secret ? text.split(secret).join('[redacted]') : text;
}

export class MiniMaxProviderError extends Error {
  constructor(code, message, details = {}) {
    super(message);
    this.name = 'MiniMaxProviderError';
    this.code = code;
    if (details.status !== undefined) this.status = details.status;
    if (details.providerCode !== undefined) this.providerCode = details.providerCode;
    if (details.retryable !== undefined) this.retryable = details.retryable;
  }

  toJSON() {
    const result = { name: this.name, code: this.code, message: this.message };
    if (this.status !== undefined) result.status = this.status;
    if (this.providerCode !== undefined) result.providerCode = this.providerCode;
    if (this.retryable !== undefined) result.retryable = this.retryable;
    return result;
  }
}

/**
 * Convert MiniMax's `{ base_resp: { status_code, status_msg } }` contract into
 * a small provider-neutral status object. Non-zero provider statuses are
 * failures and are raised before an operation can return a partial result.
 */
export function normalizeBaseResp(baseResp, { secret } = {}) {
  if (!isRecord(baseResp) || !own(baseResp, 'status_code')) {
    throw new MiniMaxProviderError('MALFORMED_RESPONSE', 'MiniMax response omitted base_resp');
  }

  const rawStatusCode = baseResp.status_code;
  if ((typeof rawStatusCode !== 'number' && typeof rawStatusCode !== 'string') || String(rawStatusCode).trim() === '') {
    throw new MiniMaxProviderError('MALFORMED_RESPONSE', 'MiniMax response contained an invalid base_resp');
  }
  const statusCode = Number(rawStatusCode);
  if (!Number.isInteger(statusCode)) {
    throw new MiniMaxProviderError('MALFORMED_RESPONSE', 'MiniMax response contained an invalid base_resp');
  }

  const statusMessage = redact(
    baseResp.status_msg,
    secret,
    statusCode === 0 ? 'success' : 'MiniMax provider error',
  );
  const normalized = {
    ok: statusCode === 0,
    code: statusCode,
    message: statusMessage,
    statusCode,
    statusMessage,
  };

  if (statusCode !== 0) {
    throw new MiniMaxProviderError('PROVIDER_ERROR', statusMessage, {
      providerCode: statusCode,
      retryable: statusCode === 1002 || statusCode === 1008,
    });
  }
  return normalized;
}

export function decodeHexAudio(hex) {
  if (typeof hex !== 'string' || hex.length === 0 || hex.length % 2 !== 0 || !/^[0-9a-f]+$/i.test(hex)) {
    throw new MiniMaxProviderError('MALFORMED_RESPONSE', 'MiniMax response contained invalid hex audio');
  }
  return Buffer.from(hex, 'hex');
}

function requestInputError(message) {
  return new MiniMaxProviderError('INVALID_REQUEST', message);
}

function audioInputError(message) {
  return new MiniMaxProviderError('INVALID_AUDIO', message);
}

function pick(object, ...keys) {
  if (!isRecord(object)) return undefined;
  for (const key of keys) {
    if (own(object, key) && object[key] !== undefined) return object[key];
  }
  return undefined;
}

function extensionFor(filename) {
  const match = typeof filename === 'string' ? filename.toLowerCase().match(/\.[a-z0-9]+$/) : null;
  return match?.[0];
}

async function bytesFrom(value) {
  if (Buffer.isBuffer(value)) return Buffer.from(value);
  if (value instanceof Uint8Array) return Buffer.from(value.buffer, value.byteOffset, value.byteLength);
  if (value instanceof ArrayBuffer) return Buffer.from(value);
  if (value && typeof value.arrayBuffer === 'function') return Buffer.from(await value.arrayBuffer());
  throw audioInputError('Audio must be a Buffer, Uint8Array, ArrayBuffer, Blob, or File');
}

async function normalizeAudioInput(input, suppliedOptions, purpose) {
  const source = isRecord(input) && !Buffer.isBuffer(input) && !(input instanceof Uint8Array) && !(input instanceof ArrayBuffer) && typeof input.arrayBuffer !== 'function'
    ? input
    : {};
  const options = { ...source, ...(isRecord(suppliedOptions) ? suppliedOptions : {}) };
  const value = source === input
    ? pick(source, 'audio', 'file', 'data', 'bytes')
    : input;
  if (value === undefined || value === null) throw audioInputError('Audio is required');

  const filename = options.filename ?? (typeof value.name === 'string' ? value.name : undefined);
  if (!filename || typeof filename !== 'string') throw audioInputError('Audio filename is required');
  const extension = extensionFor(filename);
  if (!AUDIO_TYPES.has(extension)) throw audioInputError('Audio filename must end in .mp3, .m4a, or .wav');

  const bytes = await bytesFrom(value);
  if (bytes.byteLength > MAX_AUDIO_BYTES) throw audioInputError('Audio must not exceed 20 MiB');

  const durationSeconds = options.durationSeconds ?? options.duration_seconds;
  if (durationSeconds !== undefined) {
    if (!Number.isFinite(durationSeconds) || durationSeconds < 0) throw audioInputError('Audio duration is invalid');
    if (purpose === 'voice_clone' && (durationSeconds < 10 || durationSeconds > 300)) {
      throw audioInputError('Clone audio must be between 10 seconds and 5 minutes');
    }
    if (purpose === 'prompt_audio' && durationSeconds >= 8) {
      throw audioInputError('Prompt audio must be shorter than 8 seconds');
    }
  }

  const contentType = options.contentType ?? options.content_type ?? AUDIO_TYPES.get(extension);
  return { bytes, filename, contentType };
}

function asAbortError(message) {
  return typeof DOMException === 'function'
    ? new DOMException(message, 'AbortError')
    : Object.assign(new Error(message), { name: 'AbortError' });
}

export class MiniMaxProvider {
  constructor({
    apiKey = process.env.MINIMAX_API_KEY,
    baseUrl = DEFAULT_BASE_URL,
    fetch: fetchImpl = globalThis.fetch,
    timeoutMs = 30_000,
  } = {}) {
    if (typeof apiKey !== 'string' || apiKey.length === 0) {
      throw new MiniMaxProviderError('CONFIGURATION_ERROR', 'MINIMAX_API_KEY is required');
    }
    if (typeof fetchImpl !== 'function') {
      throw new MiniMaxProviderError('CONFIGURATION_ERROR', 'A fetch implementation is required');
    }
    if (!Number.isFinite(timeoutMs) || timeoutMs <= 0) {
      throw new MiniMaxProviderError('CONFIGURATION_ERROR', 'timeoutMs must be a positive number');
    }

    let normalizedBaseUrl;
    try {
      const parsedBaseUrl = new URL(baseUrl);
      if (!['https:', 'http:'].includes(parsedBaseUrl.protocol) || parsedBaseUrl.search || parsedBaseUrl.hash) {
        throw new Error('invalid URL');
      }
      normalizedBaseUrl = parsedBaseUrl.toString().replace(/\/+$/, '');
    } catch {
      throw new MiniMaxProviderError('CONFIGURATION_ERROR', 'baseUrl must be an absolute URL');
    }
    this.#apiKey = apiKey;
    this.baseUrl = normalizedBaseUrl;
    this.fetch = fetchImpl;
    this.timeoutMs = timeoutMs;
    for (const operation of [
      'uploadCloneAudio',
      'uploadPromptAudio',
      'uploadClone',
      'uploadPrompt',
      'voiceClone',
      'voice_clone',
      't2aV2',
      't2a_v2',
      'textToAudio',
      'synthesize',
    ]) {
      this[operation] = this[operation].bind(this);
    }
  }

  #apiKey;

  async _request(path, { body, json = false, signal } = {}) {
    const controller = new AbortController();
    let timeoutTriggered = false;
    let callerCancelled = Boolean(signal?.aborted);
    let timer;
    let removeCallerListener = () => {};

    const abort = (reason) => {
      if (!controller.signal.aborted) controller.abort(reason);
    };
    if (signal) {
      const onCallerAbort = () => {
        callerCancelled = true;
        abort(asAbortError('MiniMax request cancelled'));
      };
      if (signal.aborted) onCallerAbort();
      else {
        signal.addEventListener('abort', onCallerAbort, { once: true });
        removeCallerListener = () => signal.removeEventListener('abort', onCallerAbort);
      }
    }

    timer = setTimeout(() => {
      timeoutTriggered = true;
      abort(asAbortError('MiniMax request timed out'));
    }, this.timeoutMs);

    const headers = { authorization: `Bearer ${this.#apiKey}` };
    if (json) headers['content-type'] = 'application/json';
    let request;
    const abortPromise = new Promise((_, reject) => {
      if (controller.signal.aborted) reject(controller.signal.reason ?? asAbortError('MiniMax request cancelled'));
      else controller.signal.addEventListener('abort', () => reject(controller.signal.reason ?? asAbortError('MiniMax request cancelled')), { once: true });
    });

    try {
      request = this.fetch(`${this.baseUrl}${path}`, {
        method: 'POST',
        headers,
        body,
        signal: controller.signal,
      });
      const response = await Promise.race([request, abortPromise]);
      if (!response || !response.ok) {
        const status = response?.status;
        if (status === 401 || status === 403) {
          throw new MiniMaxProviderError('AUTHENTICATION_FAILED', 'MiniMax authentication failed', { status });
        }
        if (status === 408 || status === 504) {
          throw new MiniMaxProviderError('TIMEOUT', 'MiniMax request timed out', { status, retryable: true });
        }
        if (status === 429) {
          throw new MiniMaxProviderError('RATE_LIMITED', 'MiniMax rate limit exceeded', { status, retryable: true });
        }
        throw new MiniMaxProviderError('UPSTREAM_ERROR', 'MiniMax request failed', {
          ...(status !== undefined ? { status } : {}),
          retryable: status !== undefined && status >= 500,
        });
      }
      const text = await Promise.race([response.text(), abortPromise]);
      let payload;
      try {
        payload = JSON.parse(text);
      } catch {
        throw new MiniMaxProviderError('MALFORMED_RESPONSE', 'MiniMax returned malformed JSON');
      }
      if (!isRecord(payload)) throw new MiniMaxProviderError('MALFORMED_RESPONSE', 'MiniMax returned an invalid response');
      return payload;
    } catch (error) {
      if (error instanceof MiniMaxProviderError) throw error;
      if (timeoutTriggered) throw new MiniMaxProviderError('TIMEOUT', 'MiniMax request timed out', { retryable: true });
      if (callerCancelled || error?.name === 'AbortError') throw new MiniMaxProviderError('CANCELLED', 'MiniMax request cancelled');
      throw new MiniMaxProviderError('UPSTREAM_UNAVAILABLE', 'MiniMax service is unavailable', { retryable: true });
    } finally {
      clearTimeout(timer);
      removeCallerListener();
    }
  }

  _baseResp(payload) {
    return normalizeBaseResp(payload.base_resp, { secret: this.#apiKey });
  }

  async _uploadAudio(input, options, purpose) {
    const { bytes, filename, contentType } = await normalizeAudioInput(input, options, purpose);
    const form = new FormData();
    form.set('purpose', purpose);
    form.set('file', new Blob([bytes], { type: contentType }), filename);
    const payload = await this._request('/v1/files/upload', {
      body: form,
      signal: options?.signal,
    });
    const baseResp = this._baseResp(payload);
    const fileId = pick(payload, 'file_id', 'fileId') ?? pick(payload.file, 'file_id', 'fileId');
    if (typeof fileId !== 'string' || fileId.length === 0) {
      throw new MiniMaxProviderError('MALFORMED_RESPONSE', 'MiniMax upload response omitted file_id');
    }
    return { fileId, baseResp };
  }

  uploadCloneAudio(input, options = {}) {
    return this._uploadAudio(input, options, 'voice_clone');
  }

  uploadPromptAudio(input, options = {}) {
    return this._uploadAudio(input, options, 'prompt_audio');
  }

  uploadClone(input, options = {}) {
    return this.uploadCloneAudio(input, options);
  }

  uploadPrompt(input, options = {}) {
    return this.uploadPromptAudio(input, options);
  }

  async voiceClone(input, options = {}) {
    const source = typeof input === 'string' ? { fileId: input } : (isRecord(input) ? input : {});
    const merged = { ...source, ...(isRecord(options) ? options : {}) };
    const fileId = pick(merged, 'fileId', 'file_id');
    const voiceId = pick(merged, 'voiceId', 'voice_id');
    const clonePromptInput = pick(merged, 'clonePrompt', 'clone_prompt');
    const promptAudio = pick(merged, 'promptAudioFileId', 'promptAudio', 'prompt_audio', 'prompt_audio_file_id')
      ?? pick(clonePromptInput, 'promptAudio', 'prompt_audio', 'prompt_audio_file_id');
    const promptText = pick(merged, 'promptText', 'prompt_text')
      ?? pick(clonePromptInput, 'promptText', 'prompt_text');
    if (typeof fileId !== 'string' || fileId.length === 0) throw requestInputError('fileId is required');
    if (typeof voiceId !== 'string' || voiceId.length === 0) throw requestInputError('voiceId is required');

    // Construct the provider payload from an explicit allowlist. In
    // particular, clone prompt data can only be emitted under clone_prompt;
    // caller properties are never spread into the top-level request.
    const clonePrompt = {};
    if (promptAudio !== undefined) clonePrompt.prompt_audio = promptAudio;
    if (promptText !== undefined) clonePrompt.prompt_text = promptText;
    const requestBody = {
      file_id: fileId,
      voice_id: voiceId,
      ...(Object.keys(clonePrompt).length > 0 ? { clone_prompt: clonePrompt } : {}),
      model: pick(merged, 'model') ?? DEFAULT_T2A_MODEL,
      accuracy: pick(merged, 'accuracy') ?? 0.7,
      need_noise_reduction: pick(merged, 'need_noise_reduction', 'needNoiseReduction') ?? false,
      need_volume_normalization: pick(merged, 'need_volume_normalization', 'needVolumeNormalization') ?? false,
      aigc_watermark: pick(merged, 'aigc_watermark', 'aigcWatermark') ?? false,
    };

    const text = pick(merged, 'text');
    const textValidation = pick(merged, 'text_validation', 'textValidation');
    if (text !== undefined) requestBody.text = text;
    if (textValidation !== undefined || text !== undefined) {
      requestBody.text_validation = textValidation ?? text;
    }

    const payload = await this._request('/v1/voice_clone', {
      body: JSON.stringify(requestBody),
      json: true,
      signal: merged.signal,
    });
    const baseResp = this._baseResp(payload);
    const returnedVoiceId = pick(payload, 'voice_id', 'voiceId');
    if (typeof returnedVoiceId !== 'string' || returnedVoiceId.length === 0) {
      throw new MiniMaxProviderError('MALFORMED_RESPONSE', 'MiniMax clone response omitted voice_id');
    }
    return { voiceId: returnedVoiceId, baseResp };
  }

  voice_clone(input, options = {}) {
    return this.voiceClone(input, options);
  }

  async t2aV2(input, options = {}) {
    const source = typeof input === 'string' ? { text: input } : (isRecord(input) ? input : {});
    const spec = { ...source, ...(isRecord(options) ? options : {}) };
    const text = pick(spec, 'text');
    if (typeof text !== 'string' || text.length === 0) throw requestInputError('text is required');

    const voiceSetting = {
      speed: 1,
      vol: 1,
      pitch: 0,
      ...(pick(spec, 'voice_setting', 'voiceSetting') ?? {}),
    };
    const emotion = pick(spec, 'emotion');
    if (emotion !== undefined) voiceSetting.emotion = emotion;
    const voiceId = pick(spec, 'voiceId', 'voice_id') ?? voiceSetting.voice_id;
    if (typeof voiceId !== 'string' || voiceId.length === 0) throw requestInputError('voiceId is required');
    voiceSetting.voice_id = voiceId;

    const suppliedAudioSetting = pick(spec, 'audio_setting', 'audioSetting');
    // MiniMax's request field is sample_rate. A legacy input alias, when
    // supplied, is normalized into this canonical key and never forwarded.
    const audioSetting = {
      sample_rate: 32_000,
      bitrate: 128_000,
      format: 'mp3',
      channel: 1,
    };
    if (isRecord(suppliedAudioSetting)) {
      for (const key of ['sample_rate', 'bitrate', 'format', 'channel']) {
        if (suppliedAudioSetting[key] !== undefined) audioSetting[key] = suppliedAudioSetting[key];
      }
      if (suppliedAudioSetting.sample_rate === undefined && suppliedAudioSetting.audio_sample_rate !== undefined) {
        audioSetting.sample_rate = suppliedAudioSetting.audio_sample_rate;
      }
    }
    const requestBody = {
      model: pick(spec, 'model') ?? DEFAULT_T2A_MODEL,
      text,
      stream: false,
      voice_setting: voiceSetting,
      audio_setting: audioSetting,
      subtitle_enable: pick(spec, 'subtitle_enable', 'subtitleEnable') ?? false,
    };
    for (const [camel, snake] of [
      ['languageBoost', 'language_boost'],
      ['subtitleEnable', 'subtitle_enable'],
      ['pronunciationDict', 'pronunciation_dict'],
      ['continuousSound', 'continuous_sound'],
    ]) {
      const value = pick(spec, snake, camel);
      if (value !== undefined) requestBody[snake] = value;
    }

    const payload = await this._request('/v1/t2a_v2', {
      body: JSON.stringify(requestBody),
      json: true,
      signal: spec.signal,
    });
    const baseResp = this._baseResp(payload);
    const hexAudio = pick(payload.data, 'audio') ?? pick(payload, 'audio');
    const audio = decodeHexAudio(hexAudio);
    const extra = isRecord(payload.extra_info) ? payload.extra_info : {};
    return {
      audio,
      audioBuffer: audio,
      status: pick(payload.data, 'status'),
      extraInfo: extra,
      traceId: pick(payload, 'trace_id', 'traceId'),
      baseResp,
      audioFormat: pick(extra, 'audio_format', 'audioFormat') ?? audioSetting.format,
      sampleRate: pick(extra, 'audio_sample_rate', 'audioSampleRate') ?? audioSetting.sample_rate,
    };
  }

  t2a_v2(input, options = {}) {
    return this.t2aV2(input, options);
  }

  textToAudio(input, options = {}) {
    return this.t2aV2(input, options);
  }

  synthesize(input, options = {}) {
    return this.t2aV2(input, options);
  }
}

export function createMiniMaxProvider(options) {
  return new MiniMaxProvider(options);
}

export const createMiniMaxAdapter = createMiniMaxProvider;
export const createMinimaxAdapter = createMiniMaxProvider;
export const MiniMaxAdapter = MiniMaxProvider;
export const ProviderError = MiniMaxProviderError;
export default MiniMaxProvider;
