# MiniMax provider adapter contract

The complete callable interface is specified in [`contract.md`](./contract.md).

`MiniMaxProvider` is a server-only adapter. It keeps the MiniMax credential in
server process memory, sends requests with `Authorization: Bearer <key>`, and
returns only stable identifiers/status or decoded audio. It never logs a key,
request header, request body, provider response body, or raw audio.

## Configuration

```js
import { createMinimaxAdapter } from './minimax.mjs';

const minimax = createMinimaxAdapter({
  apiKey: process.env.MINIMAX_API_KEY,
  // Optional test seam; defaults to globalThis.fetch.
  fetch: globalThis.fetch,
  // Optional; defaults to https://api.minimax.cn.
  baseUrl: 'https://api.minimax.cn',
  // Optional; defaults to 30 seconds.
  timeoutMs: 30_000,
});
```

The adapter reads `MINIMAX_API_KEY` only when `apiKey` is omitted. It does not
load dotenv files. Production callers should inject the value from their
server secret manager; the iOS application must not receive it.

## Public exports

The discoverable entry point is `minimax.mjs` (it re-exports `index.mjs`):

```js
import { createMinimaxAdapter } from './minimax.mjs';

const { uploadCloneAudio, uploadPromptAudio, voiceClone, t2aV2 } =
  createMinimaxAdapter({ apiKey: process.env.MINIMAX_API_KEY });
```

The factory returns a `MiniMaxProvider` with bound operation methods, so they
remain callable when destructured. `MiniMaxProvider`, `MiniMaxAdapter`,
`createMiniMaxProvider`, `createMiniMaxAdapter`, `createMinimaxAdapter`,
`ProviderError`, `normalizeBaseResp`, and `decodeHexAudio` are also named
exports. The method aliases `uploadClone`, `uploadPrompt`, `voice_clone`,
`t2a_v2`, `textToAudio`, and `synthesize` are available for integrations
using provider endpoint or application naming.

## Operations

All operations are `POST` requests to the official synchronous endpoints:

| Adapter method | Endpoint | Request format | Stable result |
| --- | --- | --- | --- |
| `uploadCloneAudio({ audio, filename, contentType })` | `/v1/files/upload` | `multipart/form-data`, `purpose=voice_clone`, `file` | `{ fileId, baseResp }` |
| `uploadPromptAudio({ audio, filename, contentType })` | `/v1/files/upload` | `multipart/form-data`, `purpose=prompt_audio`, `file` | `{ fileId, baseResp }` |
| `voiceClone({ fileId, voiceId, promptAudioFileId, promptText, text, model, ...supportedOptions })` | `/v1/voice_clone` | JSON with nested `clone_prompt` | `{ voiceId, baseResp }` |
| `t2aV2({ text, voiceId, model, voiceSetting, pronunciationDict, audioSetting, subtitleEnable })` | `/t2a_v2` (versioned `/v1/t2a_v2`) | JSON, `stream=false` | `{ audio: Buffer, audioBuffer, status, extraInfo, traceId, baseResp, audioFormat, sampleRate }` |

`voiceClone` sends MiniMax's official snake-case fields (`file_id` and
`voice_id`). Prompt audio/text are nested under `clone_prompt` as
`prompt_audio`/`prompt_text` (never top-level `prompt_audio`); optional `text`,
`model`, `text_validation`, `accuracy`, `need_noise_reduction`,
`need_volume_normalization`, and `aigc_watermark` are sent at the documented
top level with defaults `speech-2.8-hd`, `0.7`, `false`, `false`, and `false`;
unknown input properties are ignored. `t2aV2` sends `voice_setting` (including optional `emotion`),
`pronunciation_dict` (including optional `tone: [...]`),
`audio_setting: { sample_rate, bitrate, format, channel }`, and
`subtitle_enable: false` by default. Any legacy input `audio_sample_rate` is
normalized to the official emitted `sample_rate` and is never sent. It
 defaults to model `speech-2.8-hd`,
32 kHz / 128 kbps / MP3 / mono output, and voice speed/volume 1 with pitch 0. Pass `model: 'speech-2.8'` when that model is enabled for the
account. `t2a_v2`, `textToAudio`, and `synthesize` are aliases for `t2aV2`.

Audio uploads accept `Buffer`, `Uint8Array`, `ArrayBuffer`, `Blob`, or `File`
under `audio` (also `file`/`data` aliases), and require an `.mp3`, `.m4a`, or
`.wav` filename. Files larger than 20 MiB are rejected locally. When optional
`durationSeconds` metadata is supplied, clone audio must be 10 seconds through
5 minutes and prompt audio must be shorter than 8 seconds; no provider request
is made for invalid input.

## Status and cancellation

The provider's official `base_resp` is normalized to:

```js
{ ok, code, message, statusCode, statusMessage }
```

A non-zero `status_code` becomes `MiniMaxProviderError` with `code:
'PROVIDER_ERROR'`; malformed upstream JSON or missing required response fields
becomes `MALFORMED_RESPONSE`. HTTP 401/403, 429, 408/504, and 5xx responses map
to stable authentication, rate-limit, timeout, and upstream errors. Error text
is deliberately generic and never contains the request or response body.

Every operation accepts `{ signal }` as its second argument (or as a property
of its input object). The adapter supplies an `AbortSignal` to `fetch`, aborts
at `timeoutMs`, and maps caller cancellation to `CANCELLED` and its own deadline
to `TIMEOUT`.

## Verification

From `server/`:

```sh
node --test providers/minimax/minimax.test.mjs
```

The tests use only Node 24 built-ins (`node:test`, `node:assert`, `Buffer`,
`FormData`, `Blob`, and `Response`) and a fake `fetch`; they never call MiniMax
or read `.env.local`.
