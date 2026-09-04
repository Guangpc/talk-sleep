# OpenAI Next provider adapter contract

This is a server-only ESM adapter. It is the single seam between SleepMate server code and an OpenAI-compatible chat/completions endpoint; callers do not need to know HTTP, SSE framing, credential headers, or abort cleanup.

## Public interface

~~~js
new OpenAINextProvider({
  apiKey,                 // optional; defaults to process.env.OPENAI_NEXT_API_KEY
  baseUrl,                // optional; defaults to https://api.openai-next.com/v1
  fetch,                  // optional injected fetch; defaults to globalThis.fetch
  logger,                 // optional logger; defaults to console
  timeoutMs,              // optional positive finite timeout; defaults to 30000
})

await provider.chat({ model, messages, reasoning?, ...chatParameters })
for await (const event of provider.streamChat({ model, messages, reasoning?, reasoningEffort?, ...chatParameters })) {}
await provider.models({ signal? })
~~~

- **chat** always sends stream=false. **streamChat** always sends stream=true, parses SSE internally, and yields normalized events of the form { type: 'text', text } or { type: 'done' }; the [DONE] marker becomes the done event.
- **reasoning**, **reasoningEffort** (the server gateway spelling), or an explicitly supplied **reasoning_effort** may only be medium, high, or xhigh. When set, the exact value is sent as reasoning_effort; unsupported values fail before a request, never downgrade.
- HTTP failures, malformed responses, transport failures, timeouts, and caller cancellation reject with **ProviderError**. Its stable **kind** is one of authentication, timeout, rate_limit, invalid_request, not_found, provider, network, or cancelled; upstream error text is intentionally not exposed.

## Runtime assumptions

- Node 24 built-ins only: native fetch/Response, AbortController, TextDecoder, and ESM. No package install or .env.local parser is used. Tests inject fake fetch/Response and never access the network.
- The server owns the adapter and the credential. The iOS client must call the server and must never receive a provider key.
- baseUrl is an absolute http: or https: URL whose path already identifies the provider API prefix (normally /v1).

## Red lines

- Never print, return, serialize, or place the API key in an error, log record, response payload, or client-facing object.
- Logs contain only provider/event plus safe status or error kind; they never contain Authorization, request headers, or prompt/message bodies.
- Never read .env.local in this adapter, use a real key in tests, or silently map/downgrade reasoning profiles.
- Keep provider compatibility details, timeout cleanup, cancellation, and SSE parsing behind this seam; callers should not reimplement them.
