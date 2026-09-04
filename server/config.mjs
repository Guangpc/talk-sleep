import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ENV_NAME = /^[A-Za-z_][A-Za-z0-9_]*$/;
const REQUIRED = ["OPENAI_NEXT_API_KEY", "MINIMAX_API_KEY", "SLEEPMATE_GATEWAY_TOKEN"];

function parseValue(value) {
  const trimmed = value.trim();
  if (trimmed.length >= 2 && ((trimmed.startsWith('"') && trimmed.endsWith('"')) || (trimmed.startsWith("'") && trimmed.endsWith("'")))) {
    return trimmed.slice(1, -1);
  }
  return trimmed;
}

export function loadEnvFile(filePath, { env = process.env, readFile = fs.readFileSync } = {}) {
  let contents;
  try {
    contents = readFile(filePath, "utf8");
  } catch (error) {
    if (error?.code === "ENOENT") return [];
    throw error;
  }

  const loaded = [];
  for (const line of String(contents).split(/\r?\n/)) {
    const match = /^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$/.exec(line);
    if (!match || match[1].startsWith("__")) continue;
    const [, name, rawValue] = match;
    if (Object.hasOwn(env, name)) continue;
    env[name] = parseValue(rawValue);
    loaded.push(name);
  }
  return loaded;
}

function requiredSecret(env, name, minimumLength = 1) {
  const value = env[name];
  if (typeof value !== "string" || value.trim().length < minimumLength || /\s/.test(value)) {
    throw new Error(`${name} is required`);
  }
  return value;
}

export function requireGatewaySecrets(env = process.env) {
  return {
    openaiApiKey: requiredSecret(env, REQUIRED[0]),
    minimaxApiKey: requiredSecret(env, REQUIRED[1]),
    gatewayToken: requiredSecret(env, REQUIRED[2], 16),
  };
}

export function defaultEnvFilePath() {
  return path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", ".env.local");
}
