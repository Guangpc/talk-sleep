import test from "node:test";
import assert from "node:assert/strict";
import { createGateway } from "./gateway.mjs";

async function withGateway(options, callback) {
  const server = createGateway(options);
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  const address = server.address();
  try {
    return await callback(`http://127.0.0.1:${address.port}`);
  } finally {
    await new Promise((resolve, reject) => server.close((error) => error ? reject(error) : resolve()));
  }
}

function fixtures() {
  return {
    llm: {
      async *streamChat() {
        yield { type: "text", text: "先陪你待一会儿。" };
        yield { type: "done" };
      },
    },
    speech: {
      async synthesize() {
        return { audio: Buffer.from([0x49, 0x44, 0x33]), format: "mp3", sampleRate: 32000 };
      },
      async uploadCloneAudio(input) {
        return { fileId: input.filename === "source.wav" ? "clone-file-1" : "unexpected" };
      },
      async uploadPromptAudio() {
        return { fileId: "prompt-file-1" };
      },
      async voiceClone(input) {
        return { voiceId: input.voiceId };
      },
    },
  };
}

test("health is public and does not disclose provider configuration", async () => {
  const { llm, speech } = fixtures();
  await withGateway({ llm, speech, authToken: "local-test-token" }, async (base) => {
    const response = await fetch(`${base}/health`);
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), { ok: true });
  });
});

test("LLM route requires gateway authentication and streams normalized text", async () => {
  const { llm, speech } = fixtures();
  await withGateway({ llm, speech, authToken: "local-test-token" }, async (base) => {
    const denied = await fetch(`${base}/v1/llm/chat`, { method: "POST", body: "{}" });
    assert.equal(denied.status, 401);

    const response = await fetch(`${base}/v1/llm/chat`, {
      method: "POST",
      headers: { authorization: "Bearer local-test-token", "content-type": "application/json" },
      body: JSON.stringify({ model: "gpt-5.6-terra", reasoningEffort: "medium", messages: [{ role: "user", content: "我有点累。" }] }),
    });
    assert.equal(response.status, 200);
    assert.match(response.headers.get("content-type"), /text\/event-stream/);
    assert.match(await response.text(), /先陪你待一会儿/);
  });
});

test("LLM route rejects unsupported reasoning without calling provider", async () => {
  let called = false;
  const { speech } = fixtures();
  const llm = { async *streamChat() { called = true; yield { type: "text", text: "unexpected" }; } };
  await withGateway({ llm, speech, authToken: "local-test-token" }, async (base) => {
    const response = await fetch(`${base}/v1/llm/chat`, {
      method: "POST",
      headers: { authorization: "Bearer local-test-token", "content-type": "application/json" },
      body: JSON.stringify({ model: "gpt-5.6-sol", reasoningEffort: "unknown", messages: [] }),
    });
    assert.equal(response.status, 400);
    assert.equal(called, false);
  });
});

test("TTS route returns audio as app-facing base64 and does not proxy raw provider JSON", async () => {
  const { llm, speech } = fixtures();
  await withGateway({ llm, speech, authToken: "local-test-token" }, async (base) => {
    const response = await fetch(`${base}/v1/tts/synthesize`, {
      method: "POST",
      headers: { authorization: "Bearer local-test-token", "content-type": "application/json" },
      body: JSON.stringify({ model: "speech-2.8-hd", voiceId: "male-qn-qingse", text: "晚安" }),
    });
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), { audioBase64: "SUQz", format: "mp3", sampleRate: 32000 });
  });
});

test("oversized JSON is rejected before provider invocation", async () => {
  let called = false;
  const llm = { async *streamChat() { called = true; yield { type: "done" }; } };
  const speech = { async synthesize() { called = true; return {}; } };
  await withGateway({ llm, speech, authToken: "local-test-token", maxBodyBytes: 1024 }, async (base) => {
    const response = await fetch(`${base}/v1/tts/synthesize`, {
      method: "POST",
      headers: { authorization: "Bearer local-test-token", "content-type": "application/json" },
      body: "{" + "x".repeat(1400) + "}",
    });
    assert.equal(response.status, 413);
    assert.equal(called, false);
  });
});

test("voice source upload accepts bounded base64 and returns only a file identifier", async () => {
  const { llm, speech } = fixtures();
  await withGateway({ llm, speech, authToken: "local-test-token" }, async (base) => {
    const response = await fetch(`${base}/v1/tts/upload`, {
      method: "POST",
      headers: { authorization: "Bearer local-test-token", "content-type": "application/json" },
      body: JSON.stringify({ purpose: "voice_clone", filename: "source.wav", durationSeconds: 12, audioBase64: "SUQz" }),
    });
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), { fileId: "clone-file-1" });
  });
});

test("voice clone route returns a stable voice identifier", async () => {
  const { llm, speech } = fixtures();
  await withGateway({ llm, speech, authToken: "local-test-token" }, async (base) => {
    const response = await fetch(`${base}/v1/tts/clone`, {
      method: "POST",
      headers: { authorization: "Bearer local-test-token", "content-type": "application/json" },
      body: JSON.stringify({ fileId: "clone-file-1", voiceId: "friend-ai-voice", promptText: "测试" }),
    });
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), { voiceId: "friend-ai-voice" });
  });
});

test("invalid base64 upload is rejected before provider invocation", async () => {
  let called = false;
  const { llm } = fixtures();
  const speech = {
    async uploadCloneAudio() { called = true; return { fileId: "unexpected" }; },
    async synthesize() { called = true; return {}; },
  };
  await withGateway({ llm, speech, authToken: "local-test-token" }, async (base) => {
    const response = await fetch(`${base}/v1/tts/upload`, {
      method: "POST",
      headers: { authorization: "Bearer local-test-token", "content-type": "application/json" },
      body: JSON.stringify({ purpose: "voice_clone", filename: "source.wav", durationSeconds: 12, audioBase64: "not-base64" }),
    });
    assert.equal(response.status, 400);
    assert.equal(called, false);
  });
});

test("rejects unsafe source filenames and clone identifiers before provider invocation", async () => {
  let uploadCalled = false;
  let cloneCalled = false;
  const { llm } = fixtures();
  const speech = {
    async synthesize() { return { audio: Buffer.from([1]), format: "mp3" }; },
    async uploadCloneAudio() { uploadCalled = true; return { fileId: "unexpected" }; },
    async voiceClone() { cloneCalled = true; return { voiceId: "unexpected" }; },
  };
  await withGateway({ llm, speech, authToken: "local-test-token" }, async (base) => {
    const headers = { authorization: "Bearer local-test-token", "content-type": "application/json" };
    const unsafeFilename = await fetch(`${base}/v1/tts/upload`, {
      method: "POST",
      headers,
      body: JSON.stringify({ purpose: "voice_clone", filename: "../friend.wav", durationSeconds: 12, audioBase64: "SUQz" }),
    });
    assert.equal(unsafeFilename.status, 400);

    const unsafeClone = await fetch(`${base}/v1/tts/clone`, {
      method: "POST",
      headers,
      body: JSON.stringify({ fileId: "file-1", voiceId: "friend voice" }),
    });
    assert.equal(unsafeClone.status, 400);
    assert.equal(uploadCalled, false);
    assert.equal(cloneCalled, false);
  });
});

test("maps MiniMax provider errors to stable public codes for upload and clone", async () => {
  const { llm } = fixtures();
  const uploadSpeech = {
    async synthesize() { return { audio: Buffer.from([1]), format: "mp3" }; },
    async uploadCloneAudio() {
      const error = new Error("provider body contains secret");
      error.code = "INVALID_REQUEST";
      throw error;
    },
  };
  await withGateway({ llm, speech: uploadSpeech, authToken: "local-test-token" }, async (base) => {
    const response = await fetch(`${base}/v1/tts/upload`, {
      method: "POST",
      headers: { authorization: "Bearer local-test-token", "content-type": "application/json" },
      body: JSON.stringify({ purpose: "voice_clone", filename: "source.wav", durationSeconds: 12, audioBase64: "SUQz" }),
    });
    assert.equal(response.status, 502);
    assert.deepEqual(await response.json(), { error: { code: "provider_invalid_request" } });
  });
});

test("provider failures become stable errors without leaking provider payloads", async () => {
  const { speech } = fixtures();
  const llm = { async *streamChat() { const error = new Error("upstream secret payload"); error.kind = "provider_authentication"; error.status = 401; throw error; } };
  await withGateway({ llm, speech, authToken: "local-test-token" }, async (base) => {
    const response = await fetch(`${base}/v1/llm/chat`, {
      method: "POST",
      headers: { authorization: "Bearer local-test-token", "content-type": "application/json" },
      body: JSON.stringify({ model: "gpt-5.6-sol", reasoningEffort: "medium", messages: [{ role: "user", content: "测试" }] }),
    });
    assert.equal(response.status, 200);
    const body = await response.text();
    assert.doesNotMatch(body, /upstream secret payload/);
    assert.match(body, /provider_authentication/);
  });
});
