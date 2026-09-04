import test from "node:test";
import assert from "node:assert/strict";
import { createServerFromEnv } from "./index.mjs";

test("builds a server with provider secrets kept inside server adapters", async () => {
  const calls = [];
  const fakeFetch = async (url, init) => {
    calls.push({ url, headers: init?.headers });
    return new Response(`data: ${JSON.stringify({ choices: [{ delta: { content: "测试回复" } }] })}\n\ndata: [DONE]\n\n`, {
      status: 200,
      headers: { "content-type": "text/event-stream" },
    });
  };
  const server = createServerFromEnv({
    env: {
      OPENAI_NEXT_API_KEY: "llm-secret",
      MINIMAX_API_KEY: "tts-secret",
      SLEEPMATE_GATEWAY_TOKEN: "gateway-token-123456",
    },
    fetchImpl: fakeFetch,
    logger: () => {},
  });
  assert.ok(server);
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  const address = server.address();
  try {
    const response = await fetch(`http://127.0.0.1:${address.port}/v1/llm/chat`, {
      method: "POST",
      headers: { authorization: "Bearer gateway-token-123456", "content-type": "application/json" },
      body: JSON.stringify({ model: "gpt-5.6-terra", reasoningEffort: "medium", messages: [{ role: "user", content: "你好" }] }),
    });
    assert.equal(response.status, 200);
    assert.match(await response.text(), /测试回复/);
    assert.equal(calls.length, 1);
    assert.equal(calls[0].headers.authorization, "Bearer llm-secret");
  } finally {
    await new Promise((resolve, reject) => server.close((error) => error ? reject(error) : resolve()));
  }
});


test("composes MiniMax upload and clone methods into the production gateway", async () => {
  const calls = [];
  const fakeFetch = async (url, init) => {
    calls.push({ url, headers: init?.headers });
    if (url.endsWith("/v1/files/upload")) {
      return new Response(JSON.stringify({ file_id: "provider-file-1", base_resp: { status_code: 0 } }), {
        status: 200,
        headers: { "content-type": "application/json" },
      });
    }
    if (url.endsWith("/v1/voice_clone")) {
      return new Response(JSON.stringify({ voice_id: "provider-voice-1", base_resp: { status_code: 0 } }), {
        status: 200,
        headers: { "content-type": "application/json" },
      });
    }
    throw new Error(`unexpected provider URL: ${url}`);
  };
  const server = createServerFromEnv({
    env: {
      OPENAI_NEXT_API_KEY: "llm-secret",
      MINIMAX_API_KEY: "tts-secret",
      SLEEPMATE_GATEWAY_TOKEN: "gateway-token-123456",
    },
    fetchImpl: fakeFetch,
    logger: () => {},
  });
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  const address = server.address();
  try {
    const gatewayHeaders = {
      authorization: "Bearer gateway-token-123456",
      "content-type": "application/json",
    };
    const upload = await fetch(`http://127.0.0.1:${address.port}/v1/tts/upload`, {
      method: "POST",
      headers: gatewayHeaders,
      body: JSON.stringify({
        purpose: "voice_clone",
        filename: "friend.m4a",
        durationSeconds: 12,
        audioBase64: Buffer.from("test-audio").toString("base64"),
      }),
    });
    assert.equal(upload.status, 200);
    assert.deepEqual(await upload.json(), { fileId: "provider-file-1" });

    const clone = await fetch(`http://127.0.0.1:${address.port}/v1/tts/clone`, {
      method: "POST",
      headers: gatewayHeaders,
      body: JSON.stringify({ fileId: "provider-file-1", voiceId: "requested-voice-1" }),
    });
    assert.equal(clone.status, 200);
    assert.deepEqual(await clone.json(), { voiceId: "provider-voice-1" });
    assert.equal(calls.length, 2);
    assert.equal(calls[0].url, "https://api.minimax.cn/v1/files/upload");
    assert.equal(calls[1].url, "https://api.minimax.cn/v1/voice_clone");
    assert.equal(calls[0].headers.authorization, "Bearer tts-secret");
    assert.equal(calls[1].headers.authorization, "Bearer tts-secret");
  } finally {
    await new Promise((resolve, reject) => server.close((error) => error ? reject(error) : resolve()));
  }
});
