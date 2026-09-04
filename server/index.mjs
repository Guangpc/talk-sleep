import path from "node:path";
import { fileURLToPath } from "node:url";
import { createGateway } from "./gateway.mjs";
import { loadEnvFile, defaultEnvFilePath, requireGatewaySecrets } from "./config.mjs";
import { OpenAINextProvider } from "./providers/openai-next/openai-next.mjs";
import { MiniMaxProvider } from "./providers/minimax/index.mjs";

const SERVER_ROOT = path.dirname(fileURLToPath(import.meta.url));

export function createServerFromEnv({
  env = process.env,
  envFilePath = defaultEnvFilePath(),
  fetchImpl = globalThis.fetch,
  logger = (event) => console.error(JSON.stringify(event)),
  providerLogger = console,
  timeoutMs,
  maxBodyBytes,
} = {}) {
  const runtimeEnv = { ...env };
  loadEnvFile(envFilePath, { env: runtimeEnv });
  const secrets = requireGatewaySecrets(runtimeEnv);
  const llm = new OpenAINextProvider({
    apiKey: secrets.openaiApiKey,
    fetch: fetchImpl,
    ...(timeoutMs ? { timeoutMs } : {}),
    logger: providerLogger,
  });
  const minimax = new MiniMaxProvider({
    apiKey: secrets.minimaxApiKey,
    fetch: fetchImpl,
    ...(timeoutMs ? { timeoutMs } : {}),
  });
  const speech = {
    async synthesize(input) {
      const result = await minimax.t2aV2({
        model: input.model,
        text: input.text,
        voiceId: input.voiceId,
        voice_setting: {
          voice_id: input.voiceId,
          speed: input.speed ?? 1,
          vol: input.volume ?? 1,
          pitch: input.pitch ?? 0,
          ...(input.emotion ? { emotion: input.emotion } : {}),
        },
        signal: input.signal,
      });
      return {
        audio: result.audio,
        format: result.audioFormat,
        sampleRate: result.sampleRate,
      };
    },
    async uploadCloneAudio(input) {
      return minimax.uploadCloneAudio({
        audio: input.audio,
        filename: input.filename,
        contentType: input.contentType,
        durationSeconds: input.durationSeconds,
        signal: input.signal,
      });
    },
    async uploadPromptAudio(input) {
      return minimax.uploadPromptAudio({
        audio: input.audio,
        filename: input.filename,
        contentType: input.contentType,
        durationSeconds: input.durationSeconds,
        signal: input.signal,
      });
    },
    async voiceClone(input) {
      return minimax.voiceClone({
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
        signal: input.signal,
      });
    },
  };
  return createGateway({
    llm,
    speech,
    authToken: secrets.gatewayToken,
    logger,
    ...(maxBodyBytes ? { maxBodyBytes } : {}),
  });
}

export function startServer({ env = process.env, ...options } = {}) {
  const runtimeEnv = { ...env };
  loadEnvFile(options.envFilePath ?? defaultEnvFilePath(), { env: runtimeEnv });
  const server = createServerFromEnv({ ...options, env: runtimeEnv });
  const port = Number(runtimeEnv.PORT ?? 8787);
  const host = runtimeEnv.HOST ?? "127.0.0.1";
  if (!Number.isInteger(port) || port < 1 || port > 65535) throw new Error("PORT must be a valid TCP port");
  server.listen(port, host, () => console.log(`SleepMate gateway listening on ${host}:${port}`));
  return server;
}

const entryPath = process.argv[1] ? path.resolve(process.argv[1]) : "";
if (entryPath === path.join(SERVER_ROOT, "index.mjs")) startServer();
