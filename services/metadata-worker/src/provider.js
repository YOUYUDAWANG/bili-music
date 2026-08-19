export async function callOpenAICompatible(env, systemPrompt, input, options = {}) {
  if (!env.UPSTREAM_API_KEY) throw new Error("missing_upstream_key");
  const baseURL = String(env.UPSTREAM_BASE_URL || "").replace(/\/+$/u, "");
  if (!baseURL.startsWith("https://")) throw new Error("invalid_upstream_url");
  const timeoutMilliseconds = boundedTimeout(options.timeoutMilliseconds);

  const jsonObjectResponse = await fetch(`${baseURL}/v1/chat/completions`, {
    method: "POST",
    headers: upstreamHeaders(env),
    body: JSON.stringify(buildChatJSONBody(env.MODEL, systemPrompt, input, options.maxCompletionTokens)),
    signal: AbortSignal.timeout(timeoutMilliseconds),
  });
  if (jsonObjectResponse.ok) {
    return { value: parseChatCompletionsResponse(await jsonObjectResponse.json()), protocol: "chat-json-object" };
  }
  if (![400, 404, 405, 422].includes(jsonObjectResponse.status)) {
    throw new Error(`chat_json_${jsonObjectResponse.status}`);
  }

  const plainChatResponse = await fetch(`${baseURL}/v1/chat/completions`, {
    method: "POST",
    headers: upstreamHeaders(env),
    body: JSON.stringify(buildChatPlainBody(env.MODEL, systemPrompt, input)),
    signal: AbortSignal.timeout(timeoutMilliseconds),
  });
  if (plainChatResponse.ok) {
    return { value: parseChatCompletionsResponse(await plainChatResponse.json()), protocol: "chat-plain-json" };
  }
  if (![400, 404, 405, 422].includes(plainChatResponse.status)) {
    throw new Error(`chat_plain_${plainChatResponse.status}`);
  }

  const plainResponsesResponse = await fetch(`${baseURL}/v1/responses`, {
    method: "POST",
    headers: upstreamHeaders(env),
    body: JSON.stringify(buildResponsesPlainBody(env.MODEL, systemPrompt, input)),
    signal: AbortSignal.timeout(timeoutMilliseconds),
  });
  if (plainResponsesResponse.ok) {
    return { value: parseResponsesResponse(await plainResponsesResponse.json()), protocol: "responses-plain-json" };
  }
  throw new Error(
    `compat_${jsonObjectResponse.status}_${plainChatResponse.status}_${plainResponsesResponse.status}`,
  );
}

function boundedTimeout(value) {
  const milliseconds = Number(value);
  if (!Number.isFinite(milliseconds)) return 25_000;
  return Math.min(Math.max(Math.round(milliseconds), 5_000), 45_000);
}

export function buildChatJSONBody(model, systemPrompt, input, maxCompletionTokens = 700) {
  return {
    model,
    messages: [
      { role: "system", content: systemPrompt },
      { role: "user", content: JSON.stringify(input) },
    ],
    response_format: { type: "json_object" },
    max_completion_tokens: maxCompletionTokens,
  };
}

export function buildChatPlainBody(model, systemPrompt, input) {
  return {
    model,
    messages: [
      { role: "system", content: `${systemPrompt}\nReturn one valid JSON object and no markdown.` },
      { role: "user", content: JSON.stringify(input) },
    ],
  };
}

export function buildResponsesPlainBody(model, systemPrompt, input) {
  return {
    model,
    instructions: `${systemPrompt}\nReturn one valid JSON object and no markdown.`,
    input: JSON.stringify(input),
  };
}

function upstreamHeaders(env) {
  return {
    authorization: `Bearer ${env.UPSTREAM_API_KEY}`,
    "content-type": "application/json",
  };
}

export function parseChatCompletionsResponse(payload) {
  const content = payload?.choices?.[0]?.message?.content;
  if (content && typeof content === "object") return content;
  if (typeof content !== "string") throw new Error("invalid_upstream_response");
  const cleaned = content.replace(/^```json\s*|\s*```$/gu, "");
  const value = JSON.parse(cleaned);
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("invalid_upstream_json");
  }
  return value;
}

export function parseResponsesResponse(payload) {
  const direct = typeof payload?.output_text === "string" ? payload.output_text : null;
  const nested = Array.isArray(payload?.output)
    ? payload.output.flatMap((item) => Array.isArray(item?.content) ? item.content : [])
      .find((item) => item?.type === "output_text")?.text
    : null;
  const content = direct || nested;
  if (typeof content !== "string") throw new Error("invalid_responses_output");
  const value = JSON.parse(content.replace(/^```json\s*|\s*```$/gu, ""));
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("invalid_responses_json");
  }
  return value;
}
