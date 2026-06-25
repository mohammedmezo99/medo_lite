const TARGET_GITHUB_REPO = "mohammedmezo99/medo_lite";
const DEFAULT_WORKFLOW_FILE = "build.yml";
const INVALID_USAGE_MESSAGE = `Usage:
/mezo <ROM_LINK> — Build from direct ROM link
/mezo <codename> — Show available DeadZone builds

Examples:
/mezo https://example.com/rom.zip
/mezo zircon`;
const BUILD_USAGE_MESSAGE = `Usage:
/build <codename> <region>
/build <codename> latest

Example:
/build zircon china`;
const DISPATCH_FAILURE_MESSAGE = "Build request could not be started. Please contact MEZO.";
const ACK_MESSAGE = "\u{1F4E5} Link received by MEZO.\n\u26A1 DeadZone Lite is now building.\n\u23F3 Please wait 40–60 minutes.";
const HELP_MESSAGE = `🔥 DeadZone Lite Bot

⚡ Available now:
• DeadZone Lite ROM Builds

🎮 Other premium styles:
• GamingPlus / Legend / Ninja

━━━━━━━━━━━━━━━

📥 /mezo <ROM_LINK> — Send your ROM link to MEZO for a fast Lite build
📦 /mezo <codename> — Show available DeadZone Lite builds

━━━━━━━━━━━━━━━

🤖 Made by MEZO to help you build faster.
👤 Contact MEZO: https://t.me/MohamedMezo1`;
const ROM_SOURCE_URL =
  "https://raw.githubusercontent.com/XiaomiFirmwareUpdater/miui-updates-tracker/master/data/latest.yml";
const ROM_SOURCE_NAME = "XiaomiFirmwareUpdater/miui-updates-tracker";
const ROM_CACHE_TTL_MS = 12 * 60 * 60 * 1000;
const PUBLIC_ROM_LIMIT = 10;
const PUBLIC_ROM_ALL_LIMIT = 20;
const PUBLIC_BUILDS_LIMIT = 5;
const PRIVATE_BUILDS_LIMIT = 5;
const BUILD_STATUS_ORDER = ["queued", "building", "uploading", "success", "failed"];
const ACTIVE_BUILD_STATUS_ORDER = ["queued", "building", "uploading"];
const REGION_ORDER = ["China", "Global", "EEA", "India", "Indonesia", "Russia", "Turkey", "Taiwan", "Japan", "Unknown"];
const REGION_ALIASES = new Map([
  ["china", "China"],
  ["cn", "China"],
  ["global", "Global"],
  ["eea", "EEA"],
  ["eu", "EEA"],
  ["europe", "EEA"],
  ["india", "India"],
  ["in", "India"],
  ["indonesia", "Indonesia"],
  ["id", "Indonesia"],
  ["russia", "Russia"],
  ["ru", "Russia"],
  ["turkey", "Turkey"],
  ["tr", "Turkey"],
  ["taiwan", "Taiwan"],
  ["tw", "Taiwan"],
  ["japan", "Japan"],
  ["jp", "Japan"],
  ["unknown", "Unknown"],
]);

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.pathname === "/internal/builds/sync") {
      return handleInternalBuildSync(request, env);
    }
    return handleTelegramWebhook(request, env);
  },
};

async function handleTelegramWebhook(request, env) {
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
  if (!message) {
    return new Response("OK", { status: 200 });
  }

  if (Array.isArray(message.new_chat_members) && message.new_chat_members.length > 0) {
    return handleNewChatMembers(env, message);
  }

  if (typeof message.text !== "string") {
    return new Response("OK", { status: 200 });
  }

  const command = parseCommand(message.text);
  if (!command) {
    return new Response("OK", { status: 200 });
  }

  const chatId = String(message.chat?.id ?? "");
  const chatType = String(message.chat?.type ?? "");
  const fromId = String(message.from?.id ?? "");
  const publicChatId = String(env.TELEGRAM_CHAT_GROUP_ID ?? "");
  const privateOwnerId = String(env.MEZO_PRIVATE_CHAT_ID ?? "");
  const isPublicChat = Boolean(chatId) && chatId === publicChatId;
  const isAuthorizedPrivateChat = chatType === "private" && Boolean(fromId) && fromId === privateOwnerId;

  console.log("[worker] webhook update", {
    command: command.name,
    chatId,
    chatType,
    isPublicChat,
    isAuthorizedPrivateChat,
  });

  switch (command.name) {
    case "status":
      return handlePrivateStatusCommand(env, message, chatId, chatType, isPublicChat, isAuthorizedPrivateChat);
    case "queue":
      return handlePrivateListCommand(env, message, chatId, chatType, isPublicChat, isAuthorizedPrivateChat, {
        publicMessage: "\u{1F512} Queue is private.",
        unauthorizedMessage: "⛔ Unauthorized.",
        formatter: formatQueueBuilds,
      });
    case "failed":
      return handlePrivateListCommand(env, message, chatId, chatType, isPublicChat, isAuthorizedPrivateChat, {
        publicMessage: "\u{1F512} Failed builds are private.",
        unauthorizedMessage: "⛔ Unauthorized.",
        formatter: formatFailedBuilds,
      });
    default:
      break;
  }

  if (!isPublicChat && !isAuthorizedPrivateChat) {
    return new Response("OK", { status: 200 });
  }

  switch (command.name) {
    case "help":
      await sendTelegramMessage(env, chatId, HELP_MESSAGE, message.message_id);
      return okResponse();
    case "latest":
      await sendTelegramMessage(env, chatId, await formatLatestBuild(env), message.message_id);
      return okResponse();
    case "builds":
      await sendTelegramMessage(env, chatId, await formatRecentBuilds(env), message.message_id);
      return okResponse();
    case "roms":
      await sendTelegramMessage(env, chatId, await handleRomsCommand(env, command.args), message.message_id);
      return okResponse();
    case "regions":
      await sendTelegramMessage(env, chatId, await handleRegionsCommand(env, command.args), message.message_id);
      return okResponse();
    case "device":
      await sendTelegramMessage(env, chatId, await handleDeviceCommand(env, command.args), message.message_id);
      return okResponse();
    case "build":
      if (!isPublicChat) {
        return okResponse();
      }
      return handleBuildCommand(env, message, command.args);
    case "mezo":
      if (!isPublicChat) {
        return okResponse();
      }
      return handleMezoCommand(env, message, command.args);
    default:
      return okResponse();
  }
}

async function handlePrivateStatusCommand(env, message, chatId, chatType, isPublicChat, isAuthorizedPrivateChat) {
  if (isPublicChat) {
    await sendTelegramMessage(env, chatId, "\u{1F512} Status is private.", message.message_id);
    return okResponse();
  }

  if (!isAuthorizedPrivateChat) {
    if (chatType === "private") {
      await sendTelegramMessage(env, chatId, "⛔ Unauthorized.", message.message_id);
    }
    return okResponse();
  }

  await sendTelegramMessage(env, chatId, await formatCurrentStatus(env), message.message_id);
  return okResponse();
}

async function handlePrivateListCommand(env, message, chatId, chatType, isPublicChat, isAuthorizedPrivateChat, options) {
  if (isPublicChat) {
    await sendTelegramMessage(env, chatId, options.publicMessage, message.message_id);
    return okResponse();
  }

  if (!isAuthorizedPrivateChat) {
    if (chatType === "private") {
      await sendTelegramMessage(env, chatId, options.unauthorizedMessage, message.message_id);
    }
    return okResponse();
  }

  await sendTelegramMessage(env, chatId, await options.formatter(env), message.message_id);
  return okResponse();
}

async function handleMezoCommand(env, message, args) {
  const chatId = String(message.chat?.id ?? "");
  const input = args.trim();

  if (!input) {
    await sendTelegramMessage(env, chatId, INVALID_USAGE_MESSAGE, message.message_id);
    return okResponse();
  }

  // Mode 1: direct ROM link -> build normally.
  if (isValidHttpUrl(input)) {
    await startBuildFromRomLink(env, message, input, {
      ackMessage: ACK_MESSAGE,
    });
    return okResponse();
  }

  // Mode 2: codename -> show DeadZone builds already available.
  const tokens = splitArgs(input);
  if (tokens.length !== 1) {
    await sendTelegramMessage(env, chatId, INVALID_USAGE_MESSAGE, message.message_id);
    return okResponse();
  }

  const codename = normalizeLookupCodename(tokens[0] || "");
  if (!codename) {
    await sendTelegramMessage(env, chatId, INVALID_USAGE_MESSAGE, message.message_id);
    return okResponse();
  }

  await sendTelegramMessage(env, chatId, await formatPublishedRomsForCodename(env, codename), message.message_id);
  return okResponse();
}


async function handleNewChatMembers(env, message) {
  const chatId = String(message.chat?.id ?? "");
  const publicChatId = String(env.TELEGRAM_CHAT_GROUP_ID ?? "");

  if (!chatId || chatId !== publicChatId) {
    return okResponse();
  }

  const members = message.new_chat_members.filter((member) => !member.is_bot);
  if (members.length === 0) {
    return okResponse();
  }

  const names = members
    .slice(0, 3)
    .map((member) => formatMemberName(member))
    .join(", ");

  const text = [
    `👋 Welcome ${names} to DeadZone Discussion!`,
    "",
    "🔥 DeadZone Lite Builds",
    "",
    "Use:",
    "/mezo <codename> — Show available DeadZone builds",
    "/mezo <ROM_LINK> — Request a new Lite build",
    "",
    "Example:",
    "/mezo zircon",
    "",
    "Need help? Contact MEZO:",
    "https://t.me/MohamedMezo1",
  ].join("\n");

  await sendTelegramMessage(env, chatId, text, message.message_id);
  return okResponse();
}

function formatMemberName(member) {
  const firstName = String(member.first_name || "").trim();
  const lastName = String(member.last_name || "").trim();
  const username = String(member.username || "").trim();

  if (firstName || lastName) {
    return `${firstName} ${lastName}`.trim();
  }

  if (username) {
    return `@${username}`;
  }

  return "new member";
}

async function formatPublishedRomsForCodename(env, codename) {
  const query = `
    SELECT device_codename, device_name, rom_version, region, android, drive_link, updated_at
    FROM builds
    WHERE status = 'success'
      AND drive_link IS NOT NULL
      AND TRIM(drive_link) != ''
      AND LOWER(COALESCE(device_codename, '')) = ?
    ORDER BY datetime(updated_at) DESC, id DESC
    LIMIT 10
  `;

  const results = await env.medo_lite_bot.prepare(query).bind(codename).all();
  const rows = results?.results || [];

  if (rows.length === 0) {
    return [
      `❌ No DeadZone builds found for ${codename.toUpperCase()}.`,
      "",
      "This device has no published DeadZone Lite builds yet.",
      "",
      "You can request a new build with:",
      "/mezo <ROM_LINK>",
    ].join("\n");
  }

  const lines = [`📦 DeadZone Builds for ${codename.toUpperCase()}`, ""];

  rows.forEach((row, index) => {
    lines.push(`${toKeycapNumber(index + 1)} ${row.device_name || "Unknown Xiaomi Device"}`);
    lines.push(`🧩 ROM: ${row.rom_version || "Unknown"}`);
    lines.push(`🌍 Region: ${row.region || "Unknown"}`);
    lines.push(`🤖 Android: ${normalizeAndroidTag(row.android)}`);
    lines.push(`⬇️ Download: ${compactLink(row.drive_link)}`);
    lines.push("");
  });

  lines.push("━━━━━━━━━━━━━━━");
  lines.push("To request a new build:");
  lines.push("/mezo <ROM_LINK>");

  return lines.join("\n").trim();
}

async function handleBuildCommand(env, message, args) {
  const parsed = parseBuildArgs(args);
  const chatId = String(message.chat?.id ?? "");

  if (!parsed.codename || parsed.invalid) {
    await sendTelegramMessage(env, chatId, BUILD_USAGE_MESSAGE, message.message_id);
    return okResponse();
  }

  const lookup = await fetchBuildableRomsForCodename(env, parsed.codename);
  const roms = lookup.roms;
  if (lookup.sourceUnavailable) {
    await sendTelegramMessage(env, chatId, "⚠️ ROM source is temporarily unavailable.\nPlease try again later.", message.message_id);
    return okResponse();
  }
  if (roms.length === 0) {
    await sendTelegramMessage(env, chatId, buildNoRomsMessage(parsed.codename), message.message_id);
    return okResponse();
  }

  const selected = parsed.region ? roms.filter((rom) => rom.region === parsed.region) : roms;
  if (selected.length === 0) {
    await sendTelegramMessage(
      env,
      chatId,
      `❌ No OTA ROMs found for ${parsed.codename.toUpperCase()} in region: ${parsed.region}.\nUse /regions ${parsed.codename} to see available regions.`,
      message.message_id,
    );
    return okResponse();
  }

  const newest = selected[0];
  const ackPrefix = parsed.region
    ? `\u{1F4E5} Latest ${parsed.codename.toUpperCase()} ${parsed.region} ROM selected by MEZO.`
    : `\u{1F4E5} Latest ${parsed.codename.toUpperCase()} ROM selected by MEZO.`;

  await startBuildFromRomLink(env, message, newest.downloadLink, {
    ackMessage: `${ackPrefix}\n\u{1F9E9} ${newest.romVersion} • ${newest.android}\n\u26A1 DeadZone Lite is now building.\n\u23F3 Please wait 40–60 minutes.`,
    metadata: romToBuildMetadata(newest),
  });
  return okResponse();
}

async function handleRomsCommand(env, args) {
  const tokens = splitArgs(args);
  const codename = normalizeLookupCodename(tokens[0] || "");
  if (!codename) {
    return "Please send /roms <codename>.";
  }

  const secondToken = (tokens[1] || "").toLowerCase();
  const showAll = secondToken === "all";
  const regionFilter = showAll ? null : normalizeRegionToken(secondToken);
  if (tokens[1] && !showAll && !regionFilter) {
    return "Unknown region. Try china, global, eea, india, indonesia, russia, turkey, taiwan, or japan.";
  }

  const lookup = await fetchBuildableRomsForCodename(env, codename, { regionFilter });
  const roms = lookup.roms;
  if (lookup.sourceUnavailable) {
    return "\u26A0\uFE0F ROM source is temporarily unavailable.\nPlease try again later.";
  }
  if (roms.length === 0) {
    return regionFilter
      ? `❌ No OTA ROMs found for ${codename.toUpperCase()} in region: ${regionFilter}.\nUse /regions ${codename} to see available regions.`
      : buildNoRomsMessage(codename);
  }

  const limit = showAll ? PUBLIC_ROM_ALL_LIMIT : PUBLIC_ROM_LIMIT;
  const truncated = roms.length > limit;
  const selected = roms.slice(0, limit);
  const exampleRegion = (selected[0]?.region || "china").toLowerCase();
  const lines = [`\u{1F50E} OTA ROMs for ${codename.toUpperCase()}`, ""];

  selected.forEach((rom, index) => {
    lines.push(`${toKeycapNumber(index + 1)} \u{1F30D} Region: ${rom.region}`);
    lines.push(`\u{1F9E9} Version: ${rom.romVersion}`);
    lines.push(`\u{1F916} Android: ${rom.android}`);
    lines.push(`\u{1F517} /mezo ${rom.downloadLink}`);
    lines.push("");
  });

  if (!showAll && roms.length > PUBLIC_ROM_LIMIT) {
    lines.push(`\u27A1\uFE0F Use /roms ${codename} all for more.`);
  } else if (showAll && truncated) {
    lines.push("\u2139\uFE0F Showing first 20 results.");
  }

  if (lookup.usedCachedResults) {
    lines.push("\u2139\uFE0F Showing cached results.");
  }

  if (lines[lines.length - 1] !== "") {
    lines.push("");
  }
  lines.push(`\u26A1 To build directly, send: /build ${codename} ${exampleRegion}`);

  return lines.join("\n").trim();
}

async function handleRegionsCommand(env, args) {
  const codename = normalizeLookupCodename(args);
  if (!codename) {
    return "Please send /regions <codename>.";
  }

  const lookup = await fetchBuildableRomsForCodename(env, codename);
  const roms = lookup.roms;
  if (lookup.sourceUnavailable) {
    return "\u26A0\uFE0F ROM source is temporarily unavailable.\nPlease try again later.";
  }
  const regions = sortRegions(uniqueValues(roms.map((rom) => rom.region)));
  if (regions.length === 0) {
    return `❌ No regions found for ${codename.toUpperCase()}.\nCheck the codename and try again.`;
  }

  return [
    `\u{1F30D} Available regions for ${codename.toUpperCase()}`,
    "",
    ...regions,
    "",
    "Use:",
    ` /build ${codename} ${regions[0].toLowerCase()}`,
    ...(lookup.usedCachedResults ? ["", "\u2139\uFE0F Showing cached results."] : []),
  ].join("\n");
}

async function handleDeviceCommand(env, args) {
  const codename = normalizeLookupCodename(args);
  if (!codename) {
    return "Please send /device <codename>.";
  }

  const lookup = await fetchBuildableRomsForCodename(env, codename);
  const roms = lookup.roms;
  if (lookup.sourceUnavailable) {
    return "\u26A0\uFE0F ROM source is temporarily unavailable.\nPlease try again later.";
  }
  if (roms.length === 0) {
    return `❌ No device data found for ${codename.toUpperCase()}.\nCheck the codename and try again.`;
  }

  const latest = roms[0];
  const regions = sortRegions(uniqueValues(roms.map((rom) => rom.region)));

  return [
    `\u{1F4F1} ${codename.toUpperCase()}`,
    "",
    `\u{1F3F7} Device: ${latest.deviceName || "Unknown Xiaomi Device"}`,
    `\u{1F9E9} Latest ROM: ${latest.romVersion || "Unknown"}`,
    `\u{1F30D} Region: ${latest.region || "Unknown"}`,
    `\u{1F916} Android: ${latest.android || "Unknown"}`,
    `\u{1F4E6} Buildable ROMs: ${roms.length}`,
    `\u{1F310} Regions: ${regions.join(", ")}`,
    "",
    "Use:",
    ` /build ${codename} ${latest.region.toLowerCase()}`,
    ...(lookup.usedCachedResults ? ["", "\u2139\uFE0F Showing cached results."] : []),
  ].join("\n");
}

async function formatLatestBuild(env) {
  const query = `
    SELECT device_name, rom_version, region, android, drive_link
    FROM builds
    WHERE status = 'success'
      AND drive_link IS NOT NULL
      AND TRIM(drive_link) != ''
    ORDER BY datetime(updated_at) DESC, id DESC
    LIMIT 1
  `;
  const row = await env.medo_lite_bot.prepare(query).first();
  if (!row) {
    return "\u2139\uFE0F No completed builds found yet.";
  }

  return [
    "\u2705 Latest DeadZone Lite Build",
    "",
    `\u{1F4F1} Device: ${row.device_name || "Unknown"}`,
    `\u{1F9E9} ROM: ${row.rom_version || "Unknown"}`,
    `\u{1F30D} Region: ${row.region || "Unknown"}`,
    `\u{1F916} Android: ${normalizeAndroidTag(row.android)}`,
    "",
    "\u{1F517} Download:",
    row.drive_link,
  ].join("\n");
}

async function formatRecentBuilds(env) {
  const query = `
    SELECT device_codename, rom_version, android, drive_link
    FROM builds
    WHERE status = 'success'
    ORDER BY datetime(updated_at) DESC, id DESC
    LIMIT ?
  `;
  const results = await env.medo_lite_bot.prepare(query).bind(PUBLIC_BUILDS_LIMIT).all();
  const rows = results?.results || [];
  if (rows.length === 0) {
    return "\u2139\uFE0F No completed builds found yet.";
  }

  const lines = ["\u{1F4E6} Latest Builds", ""];
  rows.forEach((row, index) => {
    lines.push(`${index + 1}. \u{1F4F1} ${(row.device_codename || "UNKNOWN").toUpperCase()} • \u{1F9E9} ${row.rom_version || "Unknown"} • \u{1F916} ${normalizeAndroidTag(row.android)}`);
    if (row.drive_link) {
      lines.push(`   \u{1F517} ${compactLink(row.drive_link)}`);
    }
  });
  return lines.join("\n");
}

async function formatQueueBuilds(env) {
  const placeholders = ACTIVE_BUILD_STATUS_ORDER.map(() => "?").join(", ");
  const query = `
    SELECT device_codename, status
    FROM builds
    WHERE status IN (${placeholders})
    ORDER BY datetime(updated_at) DESC, id DESC
    LIMIT ?
  `;
  const results = await env.medo_lite_bot.prepare(query).bind(...ACTIVE_BUILD_STATUS_ORDER, PRIVATE_BUILDS_LIMIT).all();
  const rows = results?.results || [];
  if (rows.length === 0) {
    return "\u2139\uFE0F No active builds found.";
  }

  const lines = ["\u{1F7E1} Build Queue", ""];
  rows.forEach((row, index) => {
    lines.push(`${index + 1}. \u{1F4F1} ${(row.device_codename || "UNKNOWN").toUpperCase()} • ${row.status || "Unknown"}`);
  });
  return lines.join("\n");
}

async function formatFailedBuilds(env) {
  const query = `
    SELECT device_codename, status
    FROM builds
    WHERE status = 'failed'
    ORDER BY datetime(updated_at) DESC, id DESC
    LIMIT ?
  `;
  const results = await env.medo_lite_bot.prepare(query).bind(PRIVATE_BUILDS_LIMIT).all();
  const rows = results?.results || [];
  if (rows.length === 0) {
    return "ℹ️ No failed builds found.";
  }

  const lines = ["❌ Failed Builds", ""];
  rows.forEach((row, index) => {
    lines.push(`${index + 1}.  ${(row.device_codename || "UNKNOWN").toUpperCase()} • ${row.status || "failed"}`);
  });
  return lines.join("\n");
}

async function formatCurrentStatus(env) {
  const placeholders = BUILD_STATUS_ORDER.map(() => "?").join(", ");
  const query = `
    SELECT status, device_name, rom_version, user_name, updated_at
    FROM builds
    WHERE status IN (${placeholders})
    ORDER BY datetime(updated_at) DESC, id DESC
    LIMIT 1
  `;
  const row = await env.medo_lite_bot.prepare(query).bind(...BUILD_STATUS_ORDER).first();
  if (!row) {
    return "No builds found yet.";
  }

  return [
    "Current Status",
    "",
    ` Status: ${row.status || "Unknown"}`,
    ` Device: ${row.device_name || "Unknown"}`,
    ` ROM: ${row.rom_version || "Unknown"}`,
    ` Requested by: ${row.user_name || "Unknown"}`,
    ` Updated: ${formatStatusTime(row.updated_at)}`,
  ].join("\n");
}

async function startBuildFromRomLink(env, message, romLink, options = {}) {
  const now = new Date().toISOString();
  const buildId = `${Date.now()}-${message.message_id ?? "0"}`;
  const userId = String(message.from?.id ?? "");
  const userName = buildDisplayName(message.from);
  const chatId = String(message.chat?.id ?? "");

  await createBuildRecord(env, {
    buildId,
    userId,
    userName,
    romLink,
    createdAt: now,
    metadata: options.metadata || null,
  });

  await sendTelegramMessage(env, chatId, options.ackMessage || ACK_MESSAGE, message.message_id);

  const dispatched = await dispatchWorkflow(env, romLink, userName, message.from?.id);
  if (!dispatched) {
    await updateBuildAfterDispatchFailure(env, buildId);
    await sendTelegramMessage(env, chatId, DISPATCH_FAILURE_MESSAGE, message.message_id);
  }
}

async function handleInternalBuildSync(request, env) {
  if (request.method !== "POST") {
    return new Response("Method Not Allowed", { status: 405 });
  }

  const configuredToken = String(env.BUILD_STATUS_WEBHOOK_TOKEN || "").trim();
  if (!configuredToken) {
    return new Response("Not Found", { status: 404 });
  }

  const authHeader = request.headers.get("Authorization") || "";
  if (authHeader !== `Bearer ${configuredToken}`) {
    return new Response("Forbidden", { status: 403 });
  }

  let payload;
  try {
    payload = await request.json();
  } catch {
    return new Response("Bad Request", { status: 400 });
  }

  const romLink = String(payload?.rom_link || "").trim();
  const userId = String(payload?.builder_id || "").trim();
  const userName = String(payload?.builder_name || "").trim();
  const status = normalizeBuildStatus(payload?.status);
  const updatedAt = new Date().toISOString();

  if (!romLink || !status) {
    return new Response("Bad Request", { status: 400 });
  }

  const metadata = sanitizeBuildMetadata(payload);
  const updated = await updateBuildFromWorkflow(env, {
    romLink,
    userId,
    userName,
    status,
    updatedAt,
    metadata,
  });

  return Response.json({ ok: updated }, { status: updated ? 200 : 404 });
}

async function createBuildRecord(env, build) {
  const metadata = build.metadata || {};
  const query = `
    INSERT INTO builds (
      build_id, user_id, user_name, rom_link, status, device_codename, device_name, rom_version, region, android, created_at, updated_at
    ) VALUES (?, ?, ?, ?, 'queued', ?, ?, ?, ?, ?, ?, ?)
  `;
  await env.medo_lite_bot
    .prepare(query)
    .bind(
      build.buildId,
      build.userId,
      build.userName,
      build.romLink,
      metadata.deviceCodename || null,
      metadata.deviceName || null,
      metadata.romVersion || null,
      metadata.region || null,
      metadata.android || null,
      build.createdAt,
      build.createdAt,
    )
    .run();
}

async function updateBuildAfterDispatchFailure(env, buildId) {
  const now = new Date().toISOString();
  await env.medo_lite_bot.prepare("UPDATE builds SET status = 'failed', updated_at = ? WHERE build_id = ?").bind(now, buildId).run();
}

async function updateBuildFromWorkflow(env, build) {
  const selectQuery = `
    SELECT id
    FROM builds
    WHERE rom_link = ?
      AND (? = '' OR user_id = ?)
      AND (? = '' OR user_name = ? OR user_name = '')
    ORDER BY datetime(created_at) DESC, id DESC
    LIMIT 1
  `;
  const row = await env.medo_lite_bot
    .prepare(selectQuery)
    .bind(build.romLink, build.userId, build.userId, build.userName, build.userName)
    .first();

  if (!row?.id) {
    return false;
  }

  const query = `
    UPDATE builds
    SET status = ?,
        device_codename = COALESCE(NULLIF(?, ''), device_codename),
        device_name = COALESCE(NULLIF(?, ''), device_name),
        rom_version = COALESCE(NULLIF(?, ''), rom_version),
        region = COALESCE(NULLIF(?, ''), region),
        android = COALESCE(NULLIF(?, ''), android),
        final_zip = COALESCE(NULLIF(?, ''), final_zip),
        drive_link = COALESCE(NULLIF(?, ''), drive_link),
        updated_at = ?
    WHERE id = ?
  `;

  await env.medo_lite_bot
    .prepare(query)
    .bind(
      build.status,
      build.metadata.deviceCodename,
      build.metadata.deviceName,
      build.metadata.romVersion,
      build.metadata.region,
      build.metadata.android,
      build.metadata.finalZip,
      build.metadata.driveLink,
      build.updatedAt,
      row.id,
    )
    .run();

  return true;
}

async function fetchBuildableRomsForCodename(env, codename, options = {}) {
  const regionFilter = options.regionFilter || null;

  try {
    let roms = await getCachedRoms(env, codename, regionFilter);
    if (roms.length > 0) {
      return {
        roms,
        usedCachedResults: false,
        sourceUnavailable: false,
      };
    }

    roms = await refreshRomsForCodename(env, codename);
    return {
      roms: regionFilter ? roms.filter((rom) => rom.region === regionFilter) : roms,
      usedCachedResults: false,
      sourceUnavailable: false,
    };
  } catch (error) {
    console.warn("[worker] rom lookup failed", {
      codename,
      regionFilter,
      message: error instanceof Error ? error.message : String(error),
    });
    const cachedRoms = await getAnyCachedRoms(env, codename, regionFilter);
    if (cachedRoms.length > 0) {
      return {
        roms: cachedRoms,
        usedCachedResults: true,
        sourceUnavailable: false,
      };
    }
    return {
      roms: [],
      usedCachedResults: false,
      sourceUnavailable: true,
    };
  }
}

async function getCachedRoms(env, codename, regionFilter) {
  const query = `
    SELECT codename, device_name, region, rom_version, android, rom_type, download_link, source, updated_at
    FROM rom_cache
    WHERE codename = ?
      AND datetime(updated_at) >= datetime(?)
      AND (? IS NULL OR region = ?)
    ORDER BY id ASC
  `;
  const cutoff = new Date(Date.now() - ROM_CACHE_TTL_MS).toISOString();
  const results = await env.medo_lite_bot.prepare(query).bind(codename, cutoff, regionFilter, regionFilter).all();
  return normalizeCachedRomRows(results?.results || []);
}

async function getAnyCachedRoms(env, codename, regionFilter) {
  const query = `
    SELECT codename, device_name, region, rom_version, android, rom_type, download_link, source, updated_at
    FROM rom_cache
    WHERE codename = ?
      AND (? IS NULL OR region = ?)
    ORDER BY id ASC
  `;
  const results = await env.medo_lite_bot.prepare(query).bind(codename, regionFilter, regionFilter).all();
  return normalizeCachedRomRows(results?.results || []);
}

async function refreshRomsForCodename(env, codename) {
  const response = await fetch(ROM_SOURCE_URL, {
    headers: { "User-Agent": "medo-lite-telegram-worker" },
  });
  if (!response.ok) {
    throw new Error(`rom_source_http_${response.status}`);
  }

  const content = await response.text();
  const parsed = extractRomsFromYaml(content, codename);
  if (parsed.length === 0) {
    return [];
  }

  await replaceRomCache(env, codename, parsed);
  return parsed;
}

async function replaceRomCache(env, codename, roms) {
  const now = new Date().toISOString();
  await env.medo_lite_bot.prepare("DELETE FROM rom_cache WHERE codename = ?").bind(codename).run();

  const statement = env.medo_lite_bot.prepare(`
    INSERT INTO rom_cache (
      codename, device_name, region, rom_version, android, rom_type, download_link, source, created_at, updated_at
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `);

  const batch = roms.map((rom) =>
    statement.bind(
      codename,
      rom.deviceName,
      rom.region,
      rom.romVersion,
      rom.android,
      rom.romType,
      rom.downloadLink,
      rom.source,
      now,
      now,
    ),
  );

  if (batch.length > 0) {
    await env.medo_lite_bot.batch(batch);
  }
}

function extractRomsFromYaml(content, lookupCodename) {
  const blocks = content
    .split(/\n-(?=\s)/)
    .map((block, index) => (index === 0 ? block : `-${block}`))
    .filter(Boolean);
  const matched = [];
  const seenLinks = new Set();

  for (const block of blocks) {
    const entry = parseSimpleYamlBlock(block);
    if (!entry) {
      continue;
    }

    const rawCodename = String(entry.codename || "").trim();
    if (normalizeBaseCodename(rawCodename) !== lookupCodename) {
      continue;
    }

    const method = String(entry.method || "").trim().toLowerCase();
    const link = String(entry.link || "").trim();
    if (!isBuildableRomLink(link, method)) {
      continue;
    }

    if (seenLinks.has(link)) {
      continue;
    }
    seenLinks.add(link);

    matched.push({
      codename: lookupCodename,
      deviceName: String(entry.name || "").trim() || "Unknown Xiaomi Device",
      region: inferRegion(rawCodename, String(entry.name || ""), String(entry.version || ""), link),
      romVersion: String(entry.version || "").trim() || "Unknown",
      android: normalizeAndroidTag(entry.android),
      romType: "Recovery",
      downloadLink: link,
      source: ROM_SOURCE_NAME,
      sortDate: String(entry.date || "").trim(),
    });
  }

  matched.sort((left, right) => {
    const leftTime = Date.parse(left.sortDate || "");
    const rightTime = Date.parse(right.sortDate || "");
    return (Number.isNaN(rightTime) ? 0 : rightTime) - (Number.isNaN(leftTime) ? 0 : leftTime);
  });

  return matched.map(({ sortDate, ...rom }) => rom);
}

function parseSimpleYamlBlock(block) {
  const result = {};
  const lines = block.split(/\r?\n/);
  for (const line of lines) {
    const cleaned = line.replace(/^- /, "").trim();
    const match = cleaned.match(/^([A-Za-z0-9_]+):\s*(.*)$/);
    if (!match) {
      continue;
    }

    const key = match[1];
    let value = match[2].trim();
    if ((value.startsWith("'") && value.endsWith("'")) || (value.startsWith("\"") && value.endsWith("\""))) {
      value = value.slice(1, -1);
    }
    result[key] = value === "null" ? "" : value;
  }

  return result;
}

function normalizeCachedRomRows(rows) {
  return rows
    .map((row) => ({
      codename: String(row.codename || "").trim(),
      deviceName: String(row.device_name || "").trim() || "Unknown Xiaomi Device",
      region: String(row.region || "").trim() || "Unknown",
      romVersion: String(row.rom_version || "").trim() || "Unknown",
      android: normalizeAndroidTag(row.android),
      romType: String(row.rom_type || "").trim() || "Recovery",
      downloadLink: String(row.download_link || "").trim(),
      source: String(row.source || "").trim() || ROM_SOURCE_NAME,
    }))
    .filter((row) => row.downloadLink);
}

function parseCommand(text) {
  const trimmed = text.trim();
  const match = trimmed.match(/^\/([a-z_]+)(?:@[\w_]+)?(?:\s+([\s\S]+))?$/i);
  if (!match) {
    return null;
  }

  return {
    name: String(match[1] || "").toLowerCase(),
    args: String(match[2] || "").trim(),
  };
}

function parseBuildArgs(args) {
  const tokens = splitArgs(args);
  const codename = normalizeLookupCodename(tokens[0] || "");
  if (!codename) {
    return { codename: "", region: null, invalid: true };
  }

  if (tokens.length === 1 && tokens[0]) {
    return { codename, region: null, invalid: true };
  }

  if (tokens.length > 3) {
    return { codename, region: null, invalid: true };
  }

  let region = null;
  let invalid = false;
  for (let index = 1; index < tokens.length; index += 1) {
    const token = String(tokens[index] || "").toLowerCase();
    if (token === "latest") {
      continue;
    }

    const normalizedRegion = normalizeRegionToken(token);
    if (!normalizedRegion || region) {
      invalid = true;
      break;
    }
    region = normalizedRegion;
  }

  return { codename, region, invalid };
}

function splitArgs(args) {
  return String(args || "")
    .split(/\s+/)
    .map((value) => value.trim())
    .filter(Boolean);
}

function buildNoRomsMessage(codename) {
  return `❌ No OTA ROMs found for ${codename.toUpperCase()}.\nCheck the codename and try again.`;
}

function romToBuildMetadata(rom) {
  return {
    deviceCodename: rom.codename || "",
    deviceName: rom.deviceName || "",
    romVersion: rom.romVersion || "",
    region: rom.region || "",
    android: rom.android || "",
  };
}

function uniqueValues(values) {
  return [...new Set(values.filter(Boolean))];
}

function sortRegions(regions) {
  return [...regions].sort((left, right) => {
    const leftIndex = REGION_ORDER.indexOf(left);
    const rightIndex = REGION_ORDER.indexOf(right);
    const safeLeftIndex = leftIndex === -1 ? REGION_ORDER.length : leftIndex;
    const safeRightIndex = rightIndex === -1 ? REGION_ORDER.length : rightIndex;
    return safeLeftIndex - safeRightIndex || left.localeCompare(right);
  });
}

function compactLink(link) {
  try {
    const parsed = new URL(String(link || ""));
    return `${parsed.hostname}${parsed.pathname}`;
  } catch {
    return String(link || "");
  }
}

function isBuildableRomLink(link, method) {
  const normalizedLink = String(link || "").trim().toLowerCase();
  if (!normalizedLink.endsWith(".zip")) {
    return false;
  }
  if (normalizedLink.endsWith(".tgz")) {
    return false;
  }
  if (method && method !== "recovery") {
    return false;
  }
  return (
    normalizedLink.includes("ota_full") ||
    normalizedLink.includes("/miui_") ||
    normalizedLink.includes("_global_") ||
    normalizedLink.includes("_eea_") ||
    normalizedLink.includes("_cn_") ||
    normalizedLink.includes("_in_") ||
    normalizedLink.includes("_id_") ||
    normalizedLink.includes("_ru_") ||
    normalizedLink.includes("_tr_") ||
    normalizedLink.includes("_tw_") ||
    normalizedLink.includes("_jp_")
  );
}

function normalizeLookupCodename(value) {
  return String(value || "")
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9_]+/g, "");
}

function normalizeBaseCodename(value) {
  const normalized = normalizeLookupCodename(value);
  return normalized
    .replace(/_(eea|in|id|ru|tr|tw|jp)_global$/, "")
    .replace(/_(sg)_global$/, "")
    .replace(/_global$/, "");
}

function normalizeRegionToken(value) {
  return REGION_ALIASES.get(String(value || "").trim().toLowerCase()) || null;
}

function inferRegion(codename, name, version, link) {
  const normalizedCodename = normalizeLookupCodename(codename);
  const normalizedName = String(name || "").toLowerCase();
  const normalizedVersion = String(version || "").toUpperCase();
  const normalizedLink = String(link || "").toLowerCase();

  if (normalizedCodename.endsWith("_eea_global") || normalizedName.includes(" eea") || normalizedVersion.endsWith("EUXM")) {
    return "EEA";
  }
  if (normalizedCodename.endsWith("_in_global") || normalizedName.includes(" india") || normalizedVersion.endsWith("INXM")) {
    return "India";
  }
  if (normalizedCodename.endsWith("_id_global") || normalizedName.includes(" indonesia") || normalizedVersion.endsWith("IDXM")) {
    return "Indonesia";
  }
  if (normalizedCodename.endsWith("_ru_global") || normalizedName.includes(" russia") || normalizedVersion.endsWith("RUXM")) {
    return "Russia";
  }
  if (normalizedCodename.endsWith("_tr_global") || normalizedName.includes(" turkey") || normalizedVersion.endsWith("TRXM")) {
    return "Turkey";
  }
  if (normalizedCodename.endsWith("_tw_global") || normalizedName.includes(" taiwan") || normalizedVersion.endsWith("TWXM")) {
    return "Taiwan";
  }
  if (normalizedCodename.endsWith("_jp_global") || normalizedName.includes(" japan") || normalizedVersion.endsWith("JPXM")) {
    return "Japan";
  }
  if (normalizedCodename.endsWith("_global") || normalizedName.includes(" global") || normalizedVersion.endsWith("MIXM")) {
    return "Global";
  }
  if (normalizedName.includes(" china") || normalizedVersion.endsWith("CNXM") || normalizedLink.includes("_cn_") || !normalizedCodename.includes("_global")) {
    return "China";
  }
  return "Unknown";
}

function normalizeAndroidTag(value) {
  const text = String(value || "").trim();
  if (!text) {
    return "Unknown";
  }

  const numericMatch = text.match(/^(\d+)(?:\.\d+)?$/);
  if (numericMatch) {
    return `A${numericMatch[1]}`;
  }

  const androidMatch = text.match(/(\d+)(?:\.\d+)?/);
  if (androidMatch) {
    return `A${androidMatch[1]}`;
  }

  return "Unknown";
}

function toKeycapNumber(value) {
  const keycaps = ["1️⃣", "2️⃣", "3️⃣", "4️⃣", "5️⃣", "6️⃣", "7️⃣", "8️⃣", "9️⃣", "🔟"];
  return keycaps[value - 1] || `${value}.`;
}

function formatStatusTime(value) {
  const date = new Date(String(value || ""));
  if (Number.isNaN(date.getTime())) {
    return String(value || "Unknown");
  }
  return date.toISOString().replace("T", " ").replace(".000Z", " UTC");
}

function normalizeBuildStatus(value) {
  const normalized = String(value || "").trim().toLowerCase();
  switch (normalized) {
    case "queued":
      return "queued";
    case "request_received":
    case "build_started":
    case "packaging_started":
    case "building":
      return "building";
    case "upload_started":
    case "uploading":
      return "uploading";
    case "success":
      return "success";
    case "fail":
    case "failed":
      return "failed";
    default:
      return "";
  }
}

function sanitizeBuildMetadata(payload) {
  return {
    deviceCodename: String(payload?.device_codename || "").trim().slice(0, 120),
    deviceName: String(payload?.device_name || "").trim().slice(0, 200),
    romVersion: String(payload?.rom_version || "").trim().slice(0, 120),
    region: String(payload?.region || "").trim().slice(0, 60),
    android: normalizeAndroidTag(payload?.android),
    finalZip: String(payload?.final_zip || "").trim().slice(0, 255),
    driveLink: sanitizeUrl(payload?.drive_link),
  };
}

function sanitizeUrl(value) {
  const text = String(value || "").trim();
  return isValidHttpUrl(text) ? text : "";
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
  const sensitiveValues = [env.TELEGRAM_BOT_TOKEN, env.GITHUB_TOKEN, env.TELEGRAM_WEBHOOK_SECRET, env.BUILD_STATUS_WEBHOOK_TOKEN]
    .filter(Boolean)
    .map((value) => String(value));

  return sensitiveValues.some((value) => value && text.includes(value));
}

function okResponse() {
  return new Response("OK", { status: 200 });
}
