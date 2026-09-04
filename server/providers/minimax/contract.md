# MiniMax provider adapter contract

This file is the public contract for the server-side MiniMax adapter. The
adapter has one deep seam: construct `MiniMaxProvider` (or use the factory),
inject `fetch`, and call one of its provider operations. Tests use that seam
with a fake fetch; callers do not depend on multipart construction, timeout
bookkeeping, response parsing, or MiniMax error details.

## Public module surface

`index.mjs` is the canonical module and has both named and default exports:

```js
import MiniMaxProvider, {
  MiniMaxAdapter,
  MiniMaxProvider,
  MiniMaxProviderError,
  ProviderError,
  createMiniMaxAdapter,
  createMiniMaxProvider,
  createMinimaxAdapter,
  decodeHexAudio,
  normalizeBaseResp,
} from './index.mjs';
```

`minimax.mjs` re-exports the same surface for callers that import by provider
name. `createMinimaxAdapter` is the preferred spelling. The capitalized
`createMiniMaxAdapter` and `createMiniMaxProvider` spellings remain supported.

```js
const adapter = createMinimaxAdapter({
  apiKey: process.env.MINIMAX_API_KEY,
  fetch: globalThis.fetch,
  baseUrl: 'https://api.minimax.cn',
  timeoutMs: 30_000,
});
```

`apiKey` is optional only when `MINIMAX_API_KEY` exists in the server process.
No dotenv file is loaded. The key is private adapter state and is used only in
an `authorization: Bearer ...` request header. The adapter does not log the
key, headers, request/response bodies, or raw audio.

## Operation interface

The factory returns a `MiniMaxProvider` whose operation methods are bound and
therefore safe to destructure:

```js
const {
  uploadCloneAudio,
  uploadPromptAudio,
  voiceClone,
  t2aV2,
  synthesize,
} = createMinimaxAdapter(options);
```

### Audio upload

```js
uploadCloneAudio(
  input: AudioInput,
  options?: UploadOptions,
): Promise<{ fileId: string, baseResp: BaseResp }>

uploadPromptAudio(
  input: AudioInput,
  options?: UploadOptions,
): Promise<{ fileId: string, baseResp: BaseResp }>
```

`AudioInput` is a `Buffer`, `Uint8Array`, `ArrayBuffer`, `Blob`, or `File`, or
an object containing one of those as `audio`, `file`, `data`, or `bytes`.
`filename` is required for raw byte inputs; a `File` name is used when present.
The recognized file extensions are `.mp3`, `.m4a`, and `.wav`. `contentType`,
`content_type`, and `mimeType` are accepted aliases. `UploadOptions` also
accepts `filename`, `fileName`, `durationSeconds`/`duration_seconds`, and an
optional `signal`.

Both methods use `POST /v1/files/upload` as `multipart/form-data`, with a
`purpose` form field (`voice_clone` or `prompt_audio`) and a `file` form
field. The adapter lets the runtime set the multipart boundary; callers must
not provide a `content-type` header. Files over 20 MiB are rejected before a
request. If duration metadata is supplied, clone audio must be 10 seconds
through 5 minutes and prompt audio must be shorter than 8 seconds.

The method aliases `uploadClone` and `uploadPrompt` are equivalent to the
corresponding audio methods.

### Voice clone

```js
voiceClone(
  input: string | {
    fileId?: string,
    file_id?: string,
    voiceId?: string,
    voice_id?: string,
    promptAudioFileId?: string,
    promptAudio?: string,
    prompt_audio?: string,
    prompt_audio_file_id?: string,
    clonePrompt?: { prompt_audio?: string, prompt_text?: string },
    clone_prompt?: { prompt_audio?: string, prompt_text?: string },
    promptText?: string,
    prompt_text?: string,
    text?: string,
    model?: string,
    textValidation?: unknown,
    text_validation?: unknown,
    accuracy?: number,
    needNoiseReduction?: boolean,
    need_noise_reduction?: boolean,
    needVolumeNormalization?: boolean,
    need_volume_normalization?: boolean,
    aigcWatermark?: boolean,
    aigc_watermark?: boolean,
  },
  options?: { signal?: AbortSignal },
): Promise<{ voiceId: string, baseResp: BaseResp }>
```

The operation uses `POST /v1/voice_clone` with JSON fields `file_id` and
`voice_id`. If prompt audio or prompt text is supplied, it is always nested
under `clone_prompt`:

```json
{
  "file_id": "clone-file-id",
  "voice_id": "friend-ai-voice",
  "clone_prompt": {
    "prompt_audio": "prompt-file-id",
    "prompt_text": "这是一段测试音色。"
  },
  "text": "晚安，明天见。",
  "model": "speech-2.8-hd",
  "text_validation": "晚安，明天见。",
  "accuracy": 0.7,
  "need_noise_reduction": false,
  "need_volume_normalization": false,
  "aigc_watermark": false
}
```

`promptAudioFileId`/`promptAudio`/`prompt_audio` map to
`clone_prompt.prompt_audio`, and `promptText`/`prompt_text` map to
`clone_prompt.prompt_text`; there is no top-level `prompt_audio` field. The
adapter sends only this allowlisted request shape: `file_id`, `voice_id`,
`clone_prompt`, `text`, `model`, `text_validation`, `accuracy`,
`need_noise_reduction`, `need_volume_normalization`, and `aigc_watermark`.
Unknown input properties are ignored. `model` defaults to `speech-2.8-hd`,
`accuracy` to `0.7`, and the three boolean flags to `false`. When `text` is
provided without `text_validation`, the same text is used for validation.
A string input is shorthand for `{ fileId: input }`; `voiceId` is still
required through the second argument or object form. `voice_clone` is an
endpoint-name alias for `voiceClone`.

### Synchronous text-to-audio

```js
t2aV2(
  input: string | {
    text: string,
    model?: string,
    voiceId?: string,
    voice_id?: string,
    emotion?: string,
    voiceSetting?: {
      voice_id?: string,
      speed?: number,
      vol?: number,
      pitch?: number,
      emotion?: string,
      [key: string]: unknown,
    },
    voice_setting?: object,
    pronunciationDict?: { tone?: string[], [key: string]: unknown },
    pronunciation_dict?: { tone?: string[], [key: string]: unknown },
    audioSetting?: {
      sample_rate?: number,
      /** Accepted for compatibility but emitted as official sample_rate. */
      audio_sample_rate?: number,
      bitrate?: number,
      format?: string,
      channel?: number,
      [key: string]: unknown,
    },
    audio_setting?: object,
    subtitleEnable?: boolean,
    subtitle_enable?: boolean,
    languageBoost?: unknown,
    language_boost?: unknown,
    continuousSound?: unknown,
    continuous_sound?: unknown,
    signal?: AbortSignal,
  },
  options?: object & { signal?: AbortSignal },
): Promise<{
  audio: Buffer,
  audioBuffer: Buffer,
  status?: string,
  extraInfo: object,
  traceId?: string,
  baseResp: BaseResp,
  audioFormat: string,
  sampleRate: number,
}>
```

`t2aV2` uses the official `POST /t2a_v2` operation on the versioned MiniMax
API base (the default absolute URL is `https://api.minimax.cn/v1/t2a_v2`).
It sends JSON with `model`, `text`, `stream: false`,
`voice_setting: { voice_id, speed, vol, pitch, emotion }`,
`pronunciation_dict` (including optional `tone: [...]`),
`audio_setting: { sample_rate, bitrate, format, channel }` and
`subtitle_enable: false` by default. The legacy input alias
`audio_sample_rate` is accepted only as an input convenience and is always
normalized to emitted `sample_rate`; `audio_sample_rate` is never sent in the
request body. `emotion`, pronunciation entries, and
other documented settings are forwarded without changing their snake-case
shape. The default model is `speech-2.8-hd`; default voice settings are
`speed: 1`, `vol: 1`, and `pitch: 0`; default audio settings are
`sample_rate: 32000`, `bitrate: 128000`, `format: 'mp3'`, and `channel: 1`.

A successful response includes `data.audio` as a hex string, `data.status`,
`extra_info`, `trace_id`, and `base_resp.status_code: 0`. The adapter returns
`audio`/`audioBuffer` as a Node `Buffer`, `status` from `data.status`, a safe
`extraInfo` metadata object, and `traceId` from `trace_id`. Invalid or empty
hex is a `MALFORMED_RESPONSE` error. The raw hex string and upstream response
body are not returned.

The `t2a_v2`, `textToAudio`, and `synthesize` methods are equivalent aliases.
The `synthesize` alias delegates to the non-streaming operation and returns a
Promise for the completed result.

## Base response and errors

Every successful operation normalizes MiniMax's
`{ base_resp: { status_code, status_msg } }` to:

```js
type BaseResp = {
  ok: boolean,
  code: number,
  message: string,
  statusCode: number,
  statusMessage: string,
};
```

A non-zero provider `status_code` throws `MiniMaxProviderError` with
`code: 'PROVIDER_ERROR'` and a numeric `providerCode`. Malformed provider
responses throw `MALFORMED_RESPONSE`. Other stable error codes are
`CONFIGURATION_ERROR`, `INVALID_REQUEST`, `INVALID_AUDIO`,
`AUTHENTICATION_FAILED`, `RATE_LIMITED`, `TIMEOUT`, `CANCELLED`,
`UPSTREAM_ERROR`, and `UPSTREAM_UNAVAILABLE`. Errors intentionally omit raw
provider bodies and transport causes; `JSON.stringify(error)` exposes only
safe normalized fields.

## Cancellation and timeout

Each operation accepts an `AbortSignal` either in the input object or in its
second options argument. The adapter passes a derived signal to `fetch`,
aborts after `timeoutMs`, and maps caller cancellation to `CANCELLED` and its
deadline to `TIMEOUT`. The signal covers the fetch and response-body parsing.

## Verification

From `server/`:

```sh
node --test providers/minimax/minimax.test.mjs
npm test
```

The MiniMax contract tests use only Node 24 built-ins (`node:test`,
`node:assert/strict`, `Buffer`, `FormData`, `Blob`, `Response`) and fake fetch
implementations. They do not contact MiniMax and do not read `.env.local`.
