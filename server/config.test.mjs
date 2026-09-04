import test from "node:test";
import assert from "node:assert/strict";
import { loadEnvFile, requireGatewaySecrets } from "./config.mjs";

test("loads only valid KEY=VALUE entries without overwriting injected environment", async () => {
  const env = { OPENAI_NEXT_API_KEY: "injected" };
  const loaded = loadEnvFile("/tmp/sleepmate-test.env", {
    env,
    readFile: () => "# comment\nOPENAI_NEXT_API_KEY=file\nMINIMAX_API_KEY=minimax\nINVALID-NAME=x\n",
  });
  assert.deepEqual(loaded, ["MINIMAX_API_KEY"]);
  assert.equal(env.OPENAI_NEXT_API_KEY, "injected");
  assert.equal(env.MINIMAX_API_KEY, "minimax");
  assert.equal(Object.hasOwn(env, "INVALID-NAME"), false);
});

test("requires separate gateway and provider secrets", () => {
  assert.deepEqual(requireGatewaySecrets({
    OPENAI_NEXT_API_KEY: "llm-secret",
    MINIMAX_API_KEY: "tts-secret",
    SLEEPMATE_GATEWAY_TOKEN: "gateway-token-123456",
  }), {
    openaiApiKey: "llm-secret",
    minimaxApiKey: "tts-secret",
    gatewayToken: "gateway-token-123456",
  });
  assert.throws(() => requireGatewaySecrets({ OPENAI_NEXT_API_KEY: "llm-secret" }), /MINIMAX_API_KEY/);
  assert.throws(() => requireGatewaySecrets({ OPENAI_NEXT_API_KEY: "llm-secret", MINIMAX_API_KEY: "tts-secret", SLEEPMATE_GATEWAY_TOKEN: "short" }), /SLEEPMATE_GATEWAY_TOKEN/);
});
