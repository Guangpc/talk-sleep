import http from "node:http";
import crypto from "node:crypto";

export const ALLOWED_REASONING_EFFORTS = new Set(["medium", "high", "xhigh"]);
const SAFE_ERROR_KINDS = new Set([
  "provider_authentication",
  "provider_rate_limit",
  "provider_timeout",
  "provider_unavailable",
  "provider_invalid_request",
  "provider_malformed_response",
  "cancelled",
]);
const PROVIDER_ERROR_KINDS = new Map([
  ["AUTHENTICATION_FAILED", "provider_authentication"],
  ["RATE_LIMITED", "provider_rate_limit"],
  ["TIMEOUT", "provider_timeout"],
  ["CANCELLED", "cancelled"],
  ["INVALID_REQUEST", "provider_invalid_request"],
  ["AUDIO_INPUT_INVALID", "provider_invalid_request"],
  ["MALFORMED_RESPONSE", "provider_malformed_response"],
  ["UPSTREAM_ERROR", "provider_unavailable"],
  ["UPSTREAM_UNAVAILABLE", "provider_unavailable"],
]);

function publicError(error) {
  const candidate = error?.kind ?? error?.code;
  const kind = SAFE_ERROR_KINDS.has(candidate)
    ? candidate
    : (PROVIDER_ERROR_KINDS.get(candidate) ?? "provider_unavailable");
  const status = kind === "provider_rate_limit" ? 429 : 502;
  return { status, body: { error: { code: kind } } };
}

function constantTimeEqual(left, right) {
  const a = Buffer.from(left ?? "", "utf8");
  const b = Buffer.from(right ?? "", "utf8");
  const padded = Buffer.alloc(Math.max(a.length, b.length));
  const paddedOther = Buffer.alloc(Math.max(a.length, b.length));
  a.copy(padded);
  b.copy(paddedOther);
  return crypto.timingSafeEqual(padded, paddedOther) && a.length === b.length;
}

function authorized(request, expectedToken) {
  const header = request.headers.authorization ?? "";
  const match = /^Bearer (.+)$/.exec(header);
  return match !== null && constantTimeEqual(match[1], expectedToken);
}

function sendJson(response, status, value) {
  const payload = JSON.stringify(value);
  response.writeHead(status, {
    "content-type": "application/json; charset=utf-8",
    "cache-control": "no-store",
    "content-length": Buffer.byteLength(payload),
  });
  response.end(payload);
}

function readJson(request, maxBodyBytes) {
  return new Promise((resolve, reject) => {
    const declaredLength = Number(request.headers["content-length"] ?? 0);
    if (Number.isFinite(declaredLength) && declaredLength > maxBodyBytes) {
      request.resume();
      reject(Object.assign(new Error("payload too large"), { kind: "payload_too_large", status: 413 }));
      return;
    }

    const chunks = [];
    let bytes = 0;
    request.on("data", (chunk) => {
      bytes += chunk.length;
      if (bytes > maxBodyBytes) {
        request.resume();
        reject(Object.assign(new Error("payload too large"), { kind: "payload_too_large", status: 413 }));
        return;
      }
      chunks.push(chunk);
    });
    request.on("end", () => {
      try {
        const value = JSON.parse(Buffer.concat(chunks).toString("utf8"));
        resolve(value);
      } catch {
        reject(Object.assign(new Error("invalid json"), { kind: "invalid_json", status: 400 }));
      }
    });
    request.on("error", () => reject(Object.assign(new Error("request failed"), { kind: "request_failed", status: 400 })));
  });
}

function requestAbortSignal(request) {
  const controller = new AbortController();
  const abort = () => controller.abort();
  request.once("aborted", abort);
  request.once("error", abort);
  return controller;
}

function validateChat(input) {
  if (!input || typeof input !== "object" || !Array.isArray(input.messages) || input.messages.length === 0) {
    throw Object.assign(new Error("invalid chat request"), { kind: "invalid_request", status: 400 });
  }
  if (typeof input.model !== "string" || input.model.length === 0 || input.model.length > 120) {
    throw Object.assign(new Error("invalid model"), { kind: "invalid_request", status: 400 });
  }
  if (!ALLOWED_REASONING_EFFORTS.has(input.reasoningEffort)) {
    throw Object.assign(new Error("unsupported reasoning effort"), { kind: "invalid_request", status: 400 });
  }
  for (const message of input.messages) {
    if (!message || typeof message !== "object" || !["system", "user", "assistant"].includes(message.role) || typeof message.content !== "string") {
      throw Object.assign(new Error("invalid message"), { kind: "invalid_request", status: 400 });
    }
  }
}

function validateSpeech(input) {
  if (!input || typeof input !== "object" || typeof input.text !== "string" || input.text.trim().length === 0 || input.text.length > 4000) {
    throw Object.assign(new Error("invalid speech text"), { kind: "invalid_request", status: 400 });
  }
  if (!safeVoiceIdentifier(input.voiceId)) {
    throw Object.assign(new Error("invalid voice id"), { kind: "invalid_request", status: 400 });
  }
  if (input.speed !== undefined && (!Number.isFinite(input.speed) || input.speed < 0.5 || input.speed > 2)) {
    throw Object.assign(new Error("invalid speech speed"), { kind: "invalid_request", status: 400 });
  }
  if (input.pitch !== undefined && (!Number.isInteger(input.pitch) || input.pitch < -12 || input.pitch > 12)) {
    throw Object.assign(new Error("invalid speech pitch"), { kind: "invalid_request", status: 400 });
  }
  if (input.model !== undefined && !safeIdentifier(input.model, 120)) {
    throw Object.assign(new Error("invalid speech model"), { kind: "invalid_request", status: 400 });
  }
}

function logEvent(logger, event) {
  try {
    logger(event);
  } catch {
    // Logging must never change request behavior.
  }
}

async function handleChat(request, response, { llm, logger, maxBodyBytes }) {
  const controller = requestAbortSignal(request);
  let input;
  try {
    input = await readJson(request, maxBodyBytes);
    validateChat(input);
  } catch (error) {
    sendJson(response, error.status ?? 400, { error: { code: error.kind === "payload_too_large" ? "payload_too_large" : "invalid_request" } });
    return;
  }

  response.writeHead(200, {
    "content-type": "text/event-stream; charset=utf-8",
    "cache-control": "no-cache, no-store",
    connection: "keep-alive",
    "x-content-type-options": "nosniff",
  });
  let emitted = false;
  try {
    for await (const event of llm.streamChat({
      model: input.model,
      messages: input.messages,
      reasoningEffort: input.reasoningEffort,
      maxTokens: input.maxTokens,
      signal: controller.signal,
    })) {
      if (!event || typeof event !== "object") continue;
      const providerText = event.type === "text"
        ? event.text
        : event.choices?.[0]?.delta?.content;
      if (typeof providerText === "string" && providerText.length > 0) {
        emitted = true;
        response.write(`data: ${JSON.stringify({ type: "text", text: providerText })}\n\n`);
      } else if (event.type === "done") {
        response.write(`data: ${JSON.stringify({ type: "done" })}\n\n`);
      }
    }
    if (!response.writableEnded) {
      response.write("data: [DONE]\n\n");
      response.end();
    }
    logEvent(logger, { operation: "llm_stream_complete", model: input.model, reasoningEffort: input.reasoningEffort, emitted });
  } catch (error) {
    const mapped = error?.name === "AbortError" ? { status: 499, body: { error: { code: "cancelled" } } } : publicError(error);
    logEvent(logger, { operation: "llm_stream_error", model: input.model, reasoningEffort: input.reasoningEffort, code: mapped.body.error.code });
    if (response.writableEnded) return;
    response.write(`event: error\ndata: ${JSON.stringify(mapped.body)}\n\n`);
    response.end();
  }
}

function decodeBase64Audio(value) {
  if (typeof value !== "string" || value.length === 0 || value.length % 4 !== 0 || !/^[A-Za-z0-9+/]*={0,2}$/.test(value)) {
    throw Object.assign(new Error("invalid audio"), { kind: "invalid_request", status: 400 });
  }
  const audio = Buffer.from(value, "base64");
  if (audio.length === 0 || audio.toString("base64") !== value) {
    throw Object.assign(new Error("invalid audio"), { kind: "invalid_request", status: 400 });
  }
  return audio;
}

function safeVoiceIdentifier(value, maxLength = 200) {
  return typeof value === "string"
    && value.length > 0
    && value.length <= maxLength
    && value.trim() === value
    && !/[\u0000-\u001f\u007f]/.test(value);
}

function safeIdentifier(value, maxLength = 200) {
  return typeof value === "string"
    && value.length > 0
    && value.length <= maxLength
    && !/[\s\u0000-\u001f\u007f]/.test(value);
}

function safeUploadFilename(value) {
  return typeof value === "string"
    && value.length > 0
    && value.length <= 255
    && value.trim() === value
    && !/[\u0000-\u001f\u007f]/.test(value)
    && !value.includes("/")
    && !value.includes("\\")
    && /\.(mp3|m4a|wav)$/i.test(value);
}

function validateVoiceCloneConsent(consent) {
  const complete = consent
    && typeof consent === "object"
    && consent.authorized === true
    && consent.intendedUseAcknowledged === true
    && consent.cloudProcessingAcknowledged === true
    && consent.retentionAndDeletionAcknowledged === true
    && typeof consent.acceptedAt === "string"
    && Number.isFinite(Date.parse(consent.acceptedAt));
  if (!complete) {
    throw Object.assign(new Error("complete voice consent attestation is required"), { kind: "invalid_request", status: 400 });
  }
}

function validateUpload(input) {
  if (!input || typeof input !== "object" || !["voice_clone", "prompt_audio"].includes(input.purpose)) {
    throw Object.assign(new Error("invalid upload purpose"), { kind: "invalid_request", status: 400 });
  }
  if (!safeUploadFilename(input.filename)) {
    throw Object.assign(new Error("invalid audio filename"), { kind: "invalid_request", status: 400 });
  }
  if (input.purpose === "voice_clone") validateVoiceCloneConsent(input.consent);
  if (input.durationSeconds !== undefined && (!Number.isFinite(input.durationSeconds) || input.durationSeconds < 0)) {
    throw Object.assign(new Error("invalid audio duration"), { kind: "invalid_request", status: 400 });
  }
  if (input.purpose === "voice_clone" && (input.durationSeconds === undefined || input.durationSeconds < 10 || input.durationSeconds > 300)) {
    throw Object.assign(new Error("clone audio duration is outside the verified range"), { kind: "invalid_request", status: 400 });
  }
  if (input.purpose === "prompt_audio" && input.durationSeconds !== undefined && input.durationSeconds >= 8) {
    throw Object.assign(new Error("prompt audio must be shorter than eight seconds"), { kind: "invalid_request", status: 400 });
  }
  const audio = decodeBase64Audio(input.audioBase64);
  if (audio.length > 20 * 1024 * 1024) {
    throw Object.assign(new Error("audio is too large"), { kind: "invalid_request", status: 400 });
  }
  return audio;
}

function validateClone(input) {
  if (!input || typeof input !== "object" || !safeIdentifier(input.fileId) || !safeIdentifier(input.voiceId)) {
    throw Object.assign(new Error("invalid clone request"), { kind: "invalid_request", status: 400 });
  }
}

async function handleUpload(request, response, { speech, logger, maxBodyBytes }) {
  const controller = requestAbortSignal(request);
  let input;
  try {
    input = await readJson(request, maxBodyBytes);
    const audio = validateUpload(input);
    const operation = input.purpose === "voice_clone" ? "uploadCloneAudio" : "uploadPromptAudio";
    if (typeof speech[operation] !== "function") throw Object.assign(new Error("upload operation unavailable"), { kind: "provider_unavailable" });
    const result = await speech[operation]({
      audio,
      filename: input.filename,
      contentType: input.contentType,
      durationSeconds: input.durationSeconds,
      signal: controller.signal,
    });
    if (!result || typeof result.fileId !== "string" || result.fileId.length === 0) {
      throw Object.assign(new Error("malformed upload result"), { kind: "provider_malformed_response" });
    }
    sendJson(response, 200, { fileId: result.fileId });
    logEvent(logger, { operation: "tts_upload_complete", purpose: input.purpose });
  } catch (error) {
    if (error?.status === 400 || error?.kind === "invalid_request" || error?.kind === "payload_too_large") {
      sendJson(response, error.status ?? 400, { error: { code: error.kind === "payload_too_large" ? "payload_too_large" : "invalid_request" } });
      return;
    }
    const mapped = publicError(error);
    logEvent(logger, { operation: "tts_upload_error", purpose: input?.purpose, code: mapped.body.error.code });
    sendJson(response, mapped.status, mapped.body);
  }
}

async function handleClone(request, response, { speech, logger, maxBodyBytes }) {
  const controller = requestAbortSignal(request);
  let input;
  try {
    input = await readJson(request, maxBodyBytes);
    validateClone(input);
    if (typeof speech.voiceClone !== "function") throw Object.assign(new Error("clone operation unavailable"), { kind: "provider_unavailable" });
    const result = await speech.voiceClone({
      fileId: input.fileId,
      voiceId: input.voiceId,
      promptAudioFileId: input.promptAudioFileId,
      promptText: input.promptText,
      model: input.model,
      text: input.text,
      textValidation: input.textValidation,
      accuracy: input.accuracy,
      needNoiseReduction: input.needNoiseReduction,
      needVolumeNormalization: input.needVolumeNormalization,
      aigcWatermark: input.aigcWatermark,
      signal: controller.signal,
    });
    if (!result || typeof result.voiceId !== "string" || result.voiceId.length === 0) {
      throw Object.assign(new Error("malformed clone result"), { kind: "provider_malformed_response" });
    }
    sendJson(response, 200, { voiceId: result.voiceId });
    logEvent(logger, { operation: "tts_clone_complete" });
  } catch (error) {
    if (error?.status === 400 || error?.kind === "invalid_request" || error?.kind === "payload_too_large") {
      sendJson(response, error.status ?? 400, { error: { code: error.kind === "payload_too_large" ? "payload_too_large" : "invalid_request" } });
      return;
    }
    const mapped = publicError(error);
    logEvent(logger, { operation: "tts_clone_error", code: mapped.body.error.code });
    sendJson(response, mapped.status, mapped.body);
  }
}

async function handleSpeech(request, response, { speech, logger, maxBodyBytes }) {
  const controller = requestAbortSignal(request);
  let input;
  try {
    input = await readJson(request, maxBodyBytes);
    validateSpeech(input);
  } catch (error) {
    sendJson(response, error.status ?? 400, { error: { code: error.kind === "payload_too_large" ? "payload_too_large" : "invalid_request" } });
    return;
  }

  try {
    const result = await speech.synthesize({
      model: input.model,
      text: input.text,
      voiceId: input.voiceId,
      speed: input.speed,
      volume: input.volume,
      pitch: input.pitch,
      emotion: input.emotion,
      signal: controller.signal,
    });
    if (!result || !Buffer.isBuffer(result.audio)) {
      throw Object.assign(new Error("malformed speech result"), { kind: "provider_malformed_response" });
    }
    const body = {
      audioBase64: result.audio.toString("base64"),
      format: result.format ?? "mp3",
      ...(result.sampleRate ? { sampleRate: result.sampleRate } : {}),
    };
    sendJson(response, 200, body);
    logEvent(logger, { operation: "tts_complete", model: input.model, format: body.format, audioBytes: result.audio.length });
  } catch (error) {
    const mapped = error?.name === "AbortError" ? { status: 499, body: { error: { code: "cancelled" } } } : publicError(error);
    logEvent(logger, { operation: "tts_error", model: input.model, code: mapped.body.error.code });
    if (!response.writableEnded) sendJson(response, mapped.status, mapped.body);
  }
}

export function createGateway({ llm, speech, authToken, logger = () => {}, maxBodyBytes = 64 * 1024, maxUploadBodyBytes = 28 * 1024 * 1024 } = {}) {
  if (!llm || typeof llm.streamChat !== "function") throw new Error("llm gateway dependency is required");
  if (!speech || typeof speech.synthesize !== "function") throw new Error("speech gateway dependency is required");
  if (typeof authToken !== "string" || authToken.length < 16) throw new Error("a non-trivial gateway auth token is required");
  if (!Number.isInteger(maxBodyBytes) || maxBodyBytes < 1024) throw new Error("maxBodyBytes is too small");
  if (!Number.isInteger(maxUploadBodyBytes) || maxUploadBodyBytes < maxBodyBytes) throw new Error("maxUploadBodyBytes is too small");

  return http.createServer(async (request, response) => {
    if (request.method === "GET" && request.url === "/health") {
      sendJson(response, 200, { ok: true });
      return;
    }
    if (!authorized(request, authToken)) {
      sendJson(response, 401, { error: { code: "gateway_unauthorized" } });
      return;
    }
    if (request.method === "POST" && request.url === "/v1/llm/chat") {
      await handleChat(request, response, { llm, logger, maxBodyBytes });
      return;
    }
    if (request.method === "POST" && request.url === "/v1/tts/upload") {
      await handleUpload(request, response, { speech, logger, maxBodyBytes: maxUploadBodyBytes });
      return;
    }
    if (request.method === "POST" && request.url === "/v1/tts/clone") {
      await handleClone(request, response, { speech, logger, maxBodyBytes });
      return;
    }
    if (request.method === "POST" && request.url === "/v1/tts/synthesize") {
      await handleSpeech(request, response, { speech, logger, maxBodyBytes });
      return;
    }
    sendJson(response, 404, { error: { code: "not_found" } });
  });
}
