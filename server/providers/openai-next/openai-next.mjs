const DEFAULT_BASE_URL = 'https://api.openai-next.com/v1';
const DEFAULT_TIMEOUT_MS = 30_000;
const REASONING_PROFILES = Object.freeze(['medium', 'high', 'xhigh']);
const REASONING_PROFILE_SET = new Set(REASONING_PROFILES);
const SSE_DONE = Symbol('sse-done');

export { DEFAULT_BASE_URL, REASONING_PROFILES };

export class ProviderError extends Error {
  constructor(kind, message, status) {
    super(message);
    this.name = 'ProviderError';
    this.kind = kind;
    if (status !== undefined) this.status = status;
  }

  toJSON() {
    const result = { name: this.name, kind: this.kind };
    if (this.status !== undefined) result.status = this.status;
    result.message = this.message;
    return result;
  }
}

export class OpenAINextProvider {
  #apiKey;

  constructor({
    apiKey = process.env.OPENAI_NEXT_API_KEY,
    baseUrl = DEFAULT_BASE_URL,
    fetch: fetchImplementation = globalThis.fetch,
    logger = console,
    timeoutMs = DEFAULT_TIMEOUT_MS,
  } = {}) {
    if (typeof apiKey !== 'string' || apiKey.trim() === '') {
      throw new TypeError('OPENAI_NEXT_API_KEY is required');
    }
    if (typeof fetchImplementation !== 'function') {
      throw new TypeError('fetch implementation is required');
    }
    if (!Number.isFinite(timeoutMs) || timeoutMs <= 0) {
      throw new TypeError('timeoutMs must be a positive finite number');
    }

    this.#apiKey = apiKey;
    this.baseUrl = normalizeBaseUrl(baseUrl);
    this.fetch = fetchImplementation;
    this.logger = logger;
    this.timeoutMs = timeoutMs;
  }

  async chat(request) {
    const body = createChatBody(request, false);
    return this.#requestJson('/chat/completions', {
      method: 'POST',
      headers: jsonHeaders(this.#apiKey, 'application/json'),
      body: JSON.stringify(body),
      signal: request?.signal,
    });
  }

  async models({ signal } = {}) {
    return this.#requestJson('/models', {
      method: 'GET',
      headers: jsonHeaders(this.#apiKey, 'application/json'),
      signal,
    });
  }

  async *streamChat(request) {
    const body = createChatBody(request, true);
    const abort = createAbortState(request?.signal, this.timeoutMs);
    let reader;

    try {
      if (abort.signal.aborted) throw abortError(abort);
      const response = await abortable(() => this.fetch(this.#url('/chat/completions'), {
        method: 'POST',
        headers: jsonHeaders(this.#apiKey, 'text/event-stream'),
        body: JSON.stringify(body),
        signal: abort.signal,
      }), abort);
      if (abort.signal.aborted) throw abortError(abort);
      if (!response || !response.ok) {
        throw this.#httpError(response?.status, true);
      }
      if (!response.body || typeof response.body.getReader !== 'function') {
        throw new ProviderError('provider', 'OpenAI Next provider stream failed', response?.status);
      }

      reader = response.body.getReader();
      const decoder = new TextDecoder();
      let buffer = '';
      let dataLines = [];
      let complete = false;

      const dispatch = () => {
        if (dataLines.length === 0) return undefined;
        const data = dataLines.join('\n');
        dataLines = [];
        if (data === '[DONE]') return SSE_DONE;
        let value;
        try {
          value = JSON.parse(data);
        } catch {
          throw new ProviderError('provider', 'OpenAI Next provider stream failed');
        }
        if (value && typeof value === 'object' && value.error) {
          throw new ProviderError('provider', 'OpenAI Next provider stream failed');
        }
        return value;
      };

      const consumeLine = (line) => {
        if (line === '') return dispatch();
        if (line.startsWith(':')) return undefined;
        const separator = line.indexOf(':');
        const field = separator === -1 ? line : line.slice(0, separator);
        let value = separator === -1 ? '' : line.slice(separator + 1);
        if (value.startsWith(' ')) value = value.slice(1);
        if (field === 'data') dataLines.push(value);
        return undefined;
      };

      while (!complete) {
        if (abort.signal.aborted) throw abortError(abort);
        let part;
        try {
          part = await abortable(() => reader.read(), abort);
        } catch (error) {
          if (error instanceof ProviderError) throw error;
          throw this.#transportError(error, abort, true);
        }
        if (part.done) {
          buffer += decoder.decode();
          complete = true;
        } else {
          buffer += decoder.decode(part.value, { stream: true });
        }

        const lines = buffer.split(/\r\n|\n|\r/);
        buffer = lines.pop();
        for (const line of lines) {
          const event = consumeLine(line);
          if (event === SSE_DONE) {
            yield { type: 'done' };
            return;
          }
          const normalizedEvent = normalizeStreamChunk(event);
          if (normalizedEvent) yield normalizedEvent;
        }
      }

      if (buffer !== '') {
        const event = consumeLine(buffer);
        if (event === SSE_DONE) {
          yield { type: 'done' };
          return;
        }
        const normalizedEvent = normalizeStreamChunk(event);
        if (normalizedEvent) yield normalizedEvent;
      }
      const finalEvent = dispatch();
      if (finalEvent === SSE_DONE) {
        yield { type: 'done' };
        return;
      }
      const normalizedFinalEvent = normalizeStreamChunk(finalEvent);
      if (normalizedFinalEvent) yield normalizedFinalEvent;
    } catch (error) {
      if (error instanceof ProviderError) throw error;
      throw this.#transportError(error, abort, true);
    } finally {
      abort.cleanup();
      if (reader) {
        try {
          await reader.cancel();
        } catch {
          // Closing an already-finished stream is best effort.
        }
      }
    }
  }

  async #requestJson(path, init) {
    const abort = createAbortState(init.signal, this.timeoutMs);
    try {
      if (abort.signal.aborted) throw abortError(abort);
      const response = await abortable(() => this.fetch(this.#url(path), {
        ...init,
        signal: abort.signal,
      }), abort);
      if (abort.signal.aborted) throw abortError(abort);
      if (!response || !response.ok) {
        throw this.#httpError(response?.status, false);
      }
      let payload;
      try {
        payload = await abortable(() => response.json(), abort);
      } catch (error) {
        if (error instanceof ProviderError) throw error;
        throw new ProviderError('provider', 'OpenAI Next provider returned invalid JSON', response.status);
      }
      if (payload && typeof payload === 'object' && payload.error) {
        this.#log('error', 'request_failed', { kind: 'provider', status: response.status });
        throw new ProviderError('provider', 'OpenAI Next provider request failed');
      }
      return payload;
    } catch (error) {
      if (error instanceof ProviderError) throw error;
      throw this.#transportError(error, abort, false);
    } finally {
      abort.cleanup();
    }
  }

  #url(path) {
    return this.baseUrl + path;
  }

  #httpError(status, stream) {
    const safeStatus = Number.isInteger(status) ? status : undefined;
    const kind = classifyStatus(safeStatus);
    this.#log('error', 'request_failed', { kind, status: safeStatus });
    const message = stream
      ? 'OpenAI Next provider stream failed'
      : 'OpenAI Next provider request failed' + (safeStatus === undefined ? '' : ' (' + safeStatus + ')');
    return new ProviderError(kind, message, safeStatus);
  }

  #transportError(error, abort, stream) {
    if (abort.timedOut) {
      this.#log('error', 'request_failed', { kind: 'timeout' });
      return new ProviderError('timeout', 'OpenAI Next provider request timed out');
    }
    if (abort.cancelled || abort.signal.aborted) {
      this.#log('error', 'request_failed', { kind: 'cancelled' });
      return new ProviderError('cancelled', 'OpenAI Next provider request cancelled');
    }
    const kind = 'network';
    this.#log('error', 'request_failed', { kind });
    return new ProviderError(kind, stream
      ? 'OpenAI Next provider stream failed'
      : 'OpenAI Next provider network request failed');
  }

  #log(level, event, details) {
    const logMethod = this.logger && this.logger[level];
    if (typeof logMethod !== 'function') return;
    try {
      logMethod.call(this.logger, { provider: 'openai-next', event, ...details });
    } catch {
      // Logging must never alter provider behavior.
    }
  }
}

export default OpenAINextProvider;

function normalizeBaseUrl(value) {
  if (typeof value !== 'string' || value.trim() === '') {
    throw new TypeError('baseUrl must be an absolute HTTP(S) URL');
  }
  let url;
  try {
    url = new URL(value);
  } catch {
    throw new TypeError('baseUrl must be an absolute HTTP(S) URL');
  }
  if (url.protocol !== 'https:' && url.protocol !== 'http:') {
    throw new TypeError('baseUrl must be an absolute HTTP(S) URL');
  }
  if (url.search || url.hash) {
    throw new TypeError('baseUrl must not include a query or fragment');
  }
  return url.toString().replace(/\/+$/, '');
}

function jsonHeaders(apiKey, accept) {
  return {
    accept,
    'content-type': 'application/json',
    authorization: 'Bearer ' + apiKey,
  };
}

function createChatBody(request, stream) {
  if (!request || typeof request !== 'object') {
    throw new TypeError('chat request is required');
  }
  const {
    model,
    messages,
    reasoning,
    reasoningEffort,
    reasoning_effort: requestedReasoning,
    signal,
    stream: requestedStream,
    ...parameters
  } = request;
  void signal;
  void requestedStream;
  if (typeof model !== 'string' || model.trim() === '') {
    throw new TypeError('model is required');
  }
  if (!Array.isArray(messages)) {
    throw new TypeError('messages must be an array');
  }
  const suppliedProfiles = [reasoning, reasoningEffort, requestedReasoning]
    .filter((value) => value !== undefined);
  if (suppliedProfiles.some((value) => value !== suppliedProfiles[0])) {
    throw new TypeError('reasoning, reasoningEffort, and reasoning_effort must match');
  }
  const profile = suppliedProfiles[0];
  if (profile !== undefined && !REASONING_PROFILE_SET.has(profile)) {
    throw new TypeError('reasoning must be one of: medium, high, xhigh');
  }
  const body = { ...parameters, model, messages };
  if (profile !== undefined) body.reasoning_effort = profile;
  body.stream = stream;
  return body;
}

function normalizeStreamChunk(chunk) {
  if (!chunk || typeof chunk !== 'object' || !Array.isArray(chunk.choices)) return undefined;
  let text = '';
  for (const choice of chunk.choices) {
    const content = choice?.delta?.content;
    if (typeof content === 'string') {
      text += content;
      continue;
    }
    if (Array.isArray(content)) {
      for (const part of content) {
        if (typeof part?.text === 'string') text += part.text;
      }
    }
  }
  return text === '' ? undefined : { type: 'text', text };
}

function classifyStatus(status) {
  if (status === 401 || status === 403) return 'authentication';
  if (status === 408 || status === 504) return 'timeout';
  if (status === 429) return 'rate_limit';
  if (status === 400 || status === 422) return 'invalid_request';
  if (status === 404) return 'not_found';
  return 'provider';
}

function createAbortState(callerSignal, timeoutMs) {
  if (callerSignal !== undefined && (!callerSignal || typeof callerSignal.addEventListener !== 'function')) {
    throw new TypeError('signal must be an AbortSignal');
  }
  const controller = new AbortController();
  let timedOut = false;
  let cancelled = false;
  const onCallerAbort = () => {
    cancelled = true;
    if (!controller.signal.aborted) controller.abort(callerSignal.reason);
  };
  if (callerSignal) {
    callerSignal.addEventListener('abort', onCallerAbort, { once: true });
    if (callerSignal.aborted) onCallerAbort();
  }
  const timer = setTimeout(() => {
    timedOut = true;
    if (!controller.signal.aborted) controller.abort(new DOMException('request timed out', 'TimeoutError'));
  }, timeoutMs);
  return {
    signal: controller.signal,
    get timedOut() { return timedOut; },
    get cancelled() { return cancelled; },
    cleanup() {
      clearTimeout(timer);
      callerSignal?.removeEventListener?.('abort', onCallerAbort);
    },
  };
}

function abortable(operation, abort) {
  if (abort.signal.aborted) return Promise.reject(abortError(abort));
  return new Promise((resolve, reject) => {
    const onAbort = () => {
      cleanup();
      reject(abortError(abort));
    };
    const cleanup = () => abort.signal.removeEventListener('abort', onAbort);
    abort.signal.addEventListener('abort', onAbort, { once: true });
    let result;
    try {
      result = operation();
    } catch (error) {
      cleanup();
      reject(error);
      return;
    }
    Promise.resolve(result).then(
      (value) => { cleanup(); resolve(value); },
      (error) => { cleanup(); reject(error); },
    );
  });
}

function abortError(abort) {
  if (abort.timedOut) {
    return new ProviderError('timeout', 'OpenAI Next provider request timed out');
  }
  if (abort.cancelled || abort.signal.aborted) {
    return new ProviderError('cancelled', 'OpenAI Next provider request cancelled');
  }
  return new ProviderError('network', 'OpenAI Next provider network request failed');
}
