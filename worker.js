const TARGET_GITHUB_REPO = "mohammedmezo99/medo_lite";
const DEFAULT_WORKFLOW_FILE = "build.yml";
const INVALID_USAGE_MESSAGE = "Please send /mezo <ROM_LINK> with a valid ROM link.";
const ACK_MESSAGE = "Link received.\nDeadZone Lite request accepted.\nPlease wait 40-60 minutes.";
const DISPATCH_FAILURE_MESSAGE = "Build request could not be started. Please contact MEZO.";

// This Worker is the only webhook target for the Telegram bot.
// Telegram supports only one active webhook per bot token. If an older Worker still owns
// the webhook, point the bot webhook to this Worker URL or use a separate Telegram bot.

export default {
  async fetch(request, env) {
    if (request.method !== "POST") {
      return new Response("Method Not Allowed", { status: 405 });
    }

    const secretHeader = request.headers.get("X-Telegram-Bot-Api-Secret-Token");
    if (!secretHeader || secretHeader !== env.TELEGRAM_WEBHOOK_SECRET) {
      return new Response("Forbidden", { status: 403 });
    }

    let update;
    try {
      update = await request.json();
    } catch {
      return new Response("Bad Request", { status: 400 });
    }

    const message = update?.message;
    const hasText = typeof message?.text === "string";
    const chatId = String(message?.chat?.id ?? "");
    const expectedChatId = String(env.TELEGRAM_CHAT_GROUP_ID ?? "");
    console.log("[worker] webhook update", {
      chatId,
      expectedTelegramChatGroupId: expectedChatId,
      hasText,
    });

    if (!message || typeof message.text !== "string") {
      return new Response("OK", { status: 200 });
    }

    if (!chatId || chatId !== expectedChatId) {
      return new Response("OK", { status: 200 });
    }

    const parsed = parseMezoCommand(message.text);
    console.log("[worker] command parse", {
      chatId,
      parsedMezoCommand: parsed.isCommand,
      romLinkValid: Boolean(parsed.romLink),
    });

    if (!parsed.isCommand) {
      return new Response("OK", { status: 200 });
    }

    if (!parsed.romLink) {
      await sendTelegramMessage(env, chatId, INVALID_USAGE_MESSAGE, message.message_id);
      return new Response("OK", { status: 200 });
    }

    await sendTelegramMessage(env, chatId, ACK_MESSAGE, message.message_id);

    const dispatched = await dispatchWorkflow(env, parsed.romLink, buildDisplayName(message.from), message.from?.id);
    if (!dispatched) {
      await sendTelegramMessage(env, chatId, DISPATCH_FAILURE_MESSAGE, message.message_id);
    }

    return new Response("OK", { status: 200 });
  },
};

function parseMezoCommand(text) {
  const trimmed = text.trim();
  const match = trimmed.match(/^\/mezo(?:@[\w_]+)?(?:\s+(.+))?$/i);
  if (!match) {
    return { isCommand: false, romLink: null };
  }

  const romLink = match[1]?.trim() ?? "";
  if (!isValidHttpUrl(romLink)) {
    return { isCommand: true, romLink: null };
  }

  return { isCommand: true, romLink };
}

function isValidHttpUrl(value) {
  if (!value) {
    return false;
  }

  try {
    const parsed = new URL(value);
    return parsed.protocol === "http:" || parsed.protocol === "https:";
  } catch {
    return false;
  }
}

function buildDisplayName(from) {
  if (!from || typeof from !== "object") {
    return "";
  }

  const parts = [from.first_name, from.last_name].filter(Boolean).map((value) => String(value).trim()).filter(Boolean);
  if (parts.length > 0) {
    return parts.join(" ").slice(0, 120);
  }

  if (from.username) {
    return String(from.username).slice(0, 120);
  }

  return "";
}

function resolveRepo(env) {
  const repo = String(env.GITHUB_REPO || TARGET_GITHUB_REPO).trim();
  const allowOverride = String(env.ALLOW_GITHUB_REPO_OVERRIDE || "").toLowerCase() === "true";
  if (!allowOverride && repo !== TARGET_GITHUB_REPO) {
    throw new Error("invalid_github_repo");
  }
  return repo;
}

async function sendTelegramMessage(env, chatId, text, replyToMessageId) {
  const response = await fetch(`https://api.telegram.org/bot${env.TELEGRAM_BOT_TOKEN}/sendMessage`, {
    method: "POST",
    headers: { "content-type": "application/json; charset=UTF-8" },
    body: JSON.stringify({
      chat_id: chatId,
      text,
      disable_web_page_preview: true,
      ...(replyToMessageId ? { reply_to_message_id: replyToMessageId } : {}),
    }),
  });

  if (!response.ok) {
    throw new Error("telegram_send_failed");
  }
}

async function dispatchWorkflow(env, romLink, builderName, builderId) {
  try {
    const repo = resolveRepo(env);
    const workflowFile = String(env.WORKFLOW_FILE || DEFAULT_WORKFLOW_FILE).trim() || DEFAULT_WORKFLOW_FILE;
    const response = await fetch(`https://api.github.com/repos/${repo}/actions/workflows/${workflowFile}/dispatches`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${env.GITHUB_TOKEN}`,
        Accept: "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
        "User-Agent": "medo-lite-telegram-worker",
        "Content-Type": "application/json; charset=UTF-8",
      },
      body: JSON.stringify({
        ref: "main",
        inputs: {
          input_url: romLink,
          request_source: "telegram",
          publish_release: "true",
          builder_name: builderName || "",
          builder_id: builderId ? String(builderId) : "",
        },
      }),
    });

    console.log("[worker] GitHub dispatch response", {
      status: response.status,
      ok: response.ok,
    });
    await logSafeDispatchResponseText(response, env);

    return response.ok;
  } catch (error) {
    console.warn("[worker] GitHub dispatch exception", {
      message: error instanceof Error ? error.message : String(error),
    });
    return false;
  }
}

async function logSafeDispatchResponseText(response, env) {
  const responseText = await response.text();
  if (!responseText) {
    return;
  }

  if (containsSensitiveValue(responseText, env)) {
    console.warn("[worker] GitHub dispatch response text omitted because it may contain sensitive data");
    return;
  }

  console.log("[worker] GitHub dispatch response text", responseText);
}

function containsSensitiveValue(text, env) {
  const sensitiveValues = [
    env.TELEGRAM_BOT_TOKEN,
    env.GITHUB_TOKEN,
    env.TELEGRAM_WEBHOOK_SECRET,
  ]
    .filter(Boolean)
    .map((value) => String(value));

  return sensitiveValues.some((value) => value && text.includes(value));
}
