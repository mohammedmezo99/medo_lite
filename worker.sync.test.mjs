import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import vm from "node:vm";

function loadWorkerTestables() {
  const workerPath = path.resolve("worker.js");
  const source = fs.readFileSync(workerPath, "utf8");
  const transformed = `${source.replace("export default {", "const __workerDefault = {")}
globalThis.__workerTestables = {
  createBuildRecord,
  updateBuildFromWorkflow,
  formatPublishedRomsForCodename,
  formatLatestBuild,
  formatRecentBuilds,
  callTelegramApi,
  sendTelegramMessage,
  sanitizeBuildMetadata,
  handleCallbackQuery,
  publishLatestManualBuild,
  formatReleaseCaptionFromBuild,
  buildPublishToken,
  __setFetchImpl: (impl) => {
    globalThis.__fetchImpl = impl;
  },
};
`;
  const context = {
    console,
    URL,
    Response,
    fetch: async (...args) => {
      if (typeof context.__fetchImpl !== "function") {
        throw new Error("fetch not implemented in tests");
      }
      return context.__fetchImpl(...args);
    },
    setTimeout,
    clearTimeout,
  };
  context.globalThis = context;
  vm.runInNewContext(transformed, context, { filename: workerPath });
  return context.__workerTestables;
}

class FakeStatement {
  constructor(db, query) {
    this.db = db;
    this.query = query;
    this.params = [];
  }

  bind(...params) {
    this.params = params;
    return this;
  }

  async run() {
    return this.db.run(this.query, this.params);
  }

  async first() {
    return this.db.first(this.query, this.params);
  }

  async all() {
    return this.db.all(this.query, this.params);
  }
}

class FakeD1 {
  constructor() {
    this.rows = [];
    this.nextId = 1;
  }

  prepare(query) {
    return new FakeStatement(this, query);
  }

  async run(query, params) {
    if (query.includes("INSERT INTO builds") && query.includes("'queued'")) {
      const [buildId, userId, userName, romLink, deviceCodename, deviceName, romVersion, region, android, createdAt, updatedAt] = params;
      this.rows.push({
        id: this.nextId++,
        build_id: buildId,
        user_id: userId,
        user_name: userName,
        rom_link: romLink,
        status: "queued",
        device_codename: deviceCodename,
        device_name: deviceName,
        rom_version: romVersion,
        region,
        android,
        final_zip: null,
        drive_link: null,
        created_at: createdAt,
        updated_at: updatedAt,
      });
      return { success: true };
    }

    if (query.includes("INSERT INTO builds") && query.includes("final_zip")) {
      const [
        buildId,
        userId,
        userName,
        romLink,
        status,
        deviceCodename,
        deviceName,
        romVersion,
        region,
        android,
        finalZip,
        driveLink,
        createdAt,
        updatedAt,
      ] = params;
      this.rows.push({
        id: this.nextId++,
        build_id: buildId,
        user_id: userId,
        user_name: userName,
        rom_link: romLink,
        status,
        device_codename: deviceCodename,
        device_name: deviceName,
        rom_version: romVersion,
        region,
        android,
        final_zip: finalZip,
        drive_link: driveLink,
        created_at: createdAt,
        updated_at: updatedAt,
      });
      return { success: true };
    }

    if (query.includes("UPDATE builds") && query.includes("drive_link = COALESCE")) {
      const [userId, userName, status, deviceCodename, deviceName, romVersion, region, android, finalZip, driveLink, updatedAt, id] = params;
      const row = this.rows.find((entry) => entry.id === id);
      assert.ok(row, `missing row ${id}`);
      row.user_id = userId || row.user_id;
      row.user_name = userName || row.user_name;
      row.status = status;
      row.device_codename = deviceCodename || row.device_codename;
      row.device_name = deviceName || row.device_name;
      row.rom_version = romVersion || row.rom_version;
      row.region = region || row.region;
      row.android = android || row.android;
      row.final_zip = finalZip || row.final_zip;
      row.drive_link = driveLink || row.drive_link;
      row.updated_at = updatedAt;
      return { success: true };
    }

    throw new Error(`Unsupported run query: ${query}`);
  }

  async first(query, params) {
    if (query.includes("SELECT id") && query.includes("WHERE rom_link = ?")) {
      const [romLink, userId] = params;
      const matches = this.rows
        .filter((row) => row.rom_link === romLink)
        .sort((a, b) => {
          const aUser = userId && (a.user_id || "") === userId ? 0 : 1;
          const bUser = userId && (b.user_id || "") === userId ? 0 : 1;
          if (aUser !== bUser) return aUser - bUser;
          const statusOrder = { queued: 0, building: 1, uploading: 1, success: 2, failed: 2 };
          const aStatus = statusOrder[a.status] ?? 3;
          const bStatus = statusOrder[b.status] ?? 3;
          if (aStatus !== bStatus) return aStatus - bStatus;
          if (a.created_at !== b.created_at) return b.created_at.localeCompare(a.created_at);
          return b.id - a.id;
        });
      return matches[0] ? { id: matches[0].id } : null;
    }

    if (query.includes("SELECT device_name, rom_version, region, android, drive_link")) {
      const rows = this.publishedRows().slice(0, 1);
      if (rows.length === 0) return null;
      const row = rows[0];
      return {
        device_name: row.device_name,
        rom_version: row.rom_version,
        region: row.region,
        android: row.android,
        drive_link: row.drive_link,
      };
    }

    throw new Error(`Unsupported first query: ${query}`);
  }

  async all(query, params) {
    if (query.includes("SELECT id, device_codename, device_name, rom_version, region, android, final_zip, drive_link, updated_at")) {
      const rows = this.rows
        .filter((row) => row.status === "success" && String(row.drive_link || "").trim() && String(row.final_zip || "").trim())
        .sort((a, b) => this.compareByUpdatedDesc(a, b))
        .slice(0, 20)
        .map((row) => ({
          id: row.id,
          device_codename: row.device_codename,
          device_name: row.device_name,
          rom_version: row.rom_version,
          region: row.region,
          android: row.android,
          final_zip: row.final_zip,
          drive_link: row.drive_link,
          updated_at: row.updated_at,
        }));
      return { results: rows };
    }

    if (query.includes("LOWER(COALESCE(device_codename, '')) = ?")) {
      const [codename] = params;
      const rows = this.publishedRows()
        .filter((row) => (row.device_codename || "").toLowerCase() === codename)
        .slice(0, 10)
        .map((row) => ({
          device_codename: row.device_codename,
          device_name: row.device_name,
          rom_version: row.rom_version,
          region: row.region,
          android: row.android,
          drive_link: row.drive_link,
          updated_at: row.updated_at,
        }));
      return { results: rows };
    }

    if (query.includes("SELECT device_codename, rom_version, android, drive_link")) {
      const [limit] = params;
      const rows = this.rows
        .filter((row) => row.status === "success")
        .sort((a, b) => this.compareByUpdatedDesc(a, b))
        .slice(0, limit)
        .map((row) => ({
          device_codename: row.device_codename,
          rom_version: row.rom_version,
          android: row.android,
          drive_link: row.drive_link,
        }));
      return { results: rows };
    }

    throw new Error(`Unsupported all query: ${query}`);
  }

  publishedRows() {
    return this.rows
      .filter((row) => row.status === "success" && String(row.drive_link || "").trim())
      .sort((a, b) => this.compareByUpdatedDesc(a, b));
  }

  compareByUpdatedDesc(a, b) {
    if (a.updated_at !== b.updated_at) return b.updated_at.localeCompare(a.updated_at);
    return b.id - a.id;
  }
}

function makeEnv() {
  return {
    medo_lite_bot: new FakeD1(),
    TELEGRAM_BOT_TOKEN: "test-bot-token",
    TELEGRAM_RELEASE_GROUP_ID: "-100release",
    TELEGRAM_CHAT_GROUP_ID: "-100public",
    MEZO_PRIVATE_CHAT_ID: "999",
  };
}

async function main() {
  const {
    createBuildRecord,
    updateBuildFromWorkflow,
    formatPublishedRomsForCodename,
    formatLatestBuild,
    formatRecentBuilds,
    callTelegramApi,
    sendTelegramMessage,
    sanitizeBuildMetadata,
    handleCallbackQuery,
    publishLatestManualBuild,
    formatReleaseCaptionFromBuild,
    buildPublishToken,
    __setFetchImpl,
  } = loadWorkerTestables();

  {
    const env = makeEnv();
    await createBuildRecord(env, {
      buildId: "queued-1",
      userId: "100",
      userName: "telegram-user",
      romLink: "https://example.com/rom-1.zip",
      createdAt: "2026-06-26T10:00:00.000Z",
      metadata: {
        deviceCodename: "zircon",
        deviceName: "Redmi Note",
        romVersion: "OS2.0",
        region: "Global",
        android: "A15",
      },
    });

    const updated = await updateBuildFromWorkflow(env, {
      romLink: "https://example.com/rom-1.zip",
      userId: "100",
      userName: "",
      status: "success",
      updatedAt: "2026-06-26T11:00:00.000Z",
      metadata: sanitizeBuildMetadata({
        device_codename: "zircon",
        device_name: "Redmi Note",
        rom_version: "OS2.0.1",
        region: "Global",
        android: "A15",
        final_zip: "deadzone-zircon.zip",
        drive_link: "https://drive.google.com/file/d/abc/view",
      }),
    });

    assert.equal(updated, true);
    assert.equal(env.medo_lite_bot.rows.length, 1);
    assert.equal(env.medo_lite_bot.rows[0].status, "success");
    assert.equal(env.medo_lite_bot.rows[0].drive_link, "https://drive.google.com/file/d/abc/view");
    assert.equal(env.medo_lite_bot.rows[0].final_zip, "deadzone-zircon.zip");
  }

  {
    const env = makeEnv();
    const inserted = await updateBuildFromWorkflow(env, {
      romLink: "https://example.com/rom-2.zip",
      userId: "200",
      userName: "github-builder",
      status: "success",
      updatedAt: "2026-06-26T12:00:00.000Z",
      metadata: sanitizeBuildMetadata({
        device_codename: "garnet",
        device_name: "Redmi Note 13 Pro",
        rom_version: "OS2.1.0",
        region: "India",
        android: "A16",
        final_zip: "deadzone-garnet.zip",
        drive_link: "https://drive.google.com/file/d/xyz/view",
      }),
    });

    assert.equal(inserted, true);
    assert.equal(env.medo_lite_bot.rows.length, 1);
    assert.equal(env.medo_lite_bot.rows[0].status, "success");
    assert.equal(env.medo_lite_bot.rows[0].device_codename, "garnet");
    assert.equal(env.medo_lite_bot.rows[0].drive_link, "https://drive.google.com/file/d/xyz/view");
  }

  {
    const env = makeEnv();
    await updateBuildFromWorkflow(env, {
      romLink: "https://example.com/rom-3.zip",
      userId: "300",
      userName: "builder",
      status: "success",
      updatedAt: "2026-06-26T13:00:00.000Z",
      metadata: sanitizeBuildMetadata({
        device_codename: "peridot",
        device_name: "POCO X6",
        rom_version: "OS2.2.0",
        region: "EEA",
        android: "A15",
        final_zip: "deadzone-peridot.zip",
        drive_link: "https://drive.google.com/file/d/peridot/view",
      }),
    });

    const text = await formatPublishedRomsForCodename(env, "peridot");
    assert.match(text, /DeadZone Builds for PERIDOT/);
    assert.match(text, /drive\.google\.com/);

    const latest = await formatLatestBuild(env);
    assert.match(latest, /Latest DeadZone Lite Build/);
    assert.match(latest, /drive\.google\.com/);

    const recent = await formatRecentBuilds(env);
    assert.match(recent, /Latest Builds/);
    assert.match(recent, /drive\.google\.com/);
  }

  {
    const env = makeEnv();
    await updateBuildFromWorkflow(env, {
      romLink: "https://example.com/rom-query.zip",
      userId: "301",
      userName: "builder",
      status: "success",
      updatedAt: "2026-06-26T13:30:00.000Z",
      metadata: sanitizeBuildMetadata({
        device_codename: "zircon",
        device_name: "Redmi Note <Pro>",
        rom_version: "OS2.2.1 & Beta",
        region: "Global > EEA",
        android: "A15",
        final_zip: "deadzone-zircon-query.zip",
        drive_link: "https://drive.google.com/open?id=test123",
      }),
    });

    const text = await formatPublishedRomsForCodename(env, "zircon");
    assert.match(text, /https:\/\/drive\.google\.com\/open\?id=test123/);
    assert.match(text, /<a href="https:\/\/drive\.google\.com\/open\?id=test123">Click Here<\/a>/);
    assert.doesNotMatch(text, /href="https:\/\/drive\.google\.com\/open"/);
    assert.match(text, /Redmi Note &lt;Pro&gt;/);
    assert.match(text, /OS2\.2\.1 &amp; Beta/);
    assert.match(text, /Global &gt; EEA/);
  }

  {
    const env = makeEnv();
    const text = await formatPublishedRomsForCodename(env, "unknowncodename");
    assert.match(text, /No DeadZone builds found for UNKNOWNCODENAME/);
    assert.match(text, /<code>\/mezo &lt;ROM_LINK&gt;<\/code>/);
    assert.doesNotMatch(text, /\/mezo <ROM_LINK>/);
  }

  {
    const env = makeEnv();
    await updateBuildFromWorkflow(env, {
      romLink: "https://example.com/rom-4.zip",
      userId: "400",
      userName: "builder",
      status: "success",
      updatedAt: "2026-06-26T14:00:00.000Z",
      metadata: sanitizeBuildMetadata({
        device_codename: "moon",
        device_name: "Xiaomi Moon",
        rom_version: "OS2.3.0",
        region: "China",
        android: "A16",
        final_zip: "deadzone-moon.zip",
        drive_link: "https://drive.google.com/file/d/moon/view",
      }),
    });

    const preserved = await updateBuildFromWorkflow(env, {
      romLink: "https://example.com/rom-4.zip",
      userId: "400",
      userName: "",
      status: "success",
      updatedAt: "2026-06-26T15:00:00.000Z",
      metadata: sanitizeBuildMetadata({
        device_codename: "moon",
        device_name: "",
        rom_version: "",
        region: "",
        android: "",
        final_zip: "",
        drive_link: "",
      }),
    });

    assert.equal(preserved, true);
    assert.equal(env.medo_lite_bot.rows[0].drive_link, "https://drive.google.com/file/d/moon/view");
    assert.equal(env.medo_lite_bot.rows[0].final_zip, "deadzone-moon.zip");
  }

  {
    const env = makeEnv();
    const calls = [];
    __setFetchImpl(async (url, options) => {
      calls.push({ url, options: JSON.parse(options.body) });
      return new Response(JSON.stringify({ ok: true, result: { message_id: 777 } }), {
        status: 200,
        headers: { "content-type": "application/json" },
      });
    });

    await updateBuildFromWorkflow(env, {
      romLink: "https://example.com/rom-5.zip",
      userId: "",
      userName: "manual-builder",
      status: "success",
      updatedAt: "2026-06-26T16:00:00.000Z",
      metadata: sanitizeBuildMetadata({
        device_codename: "topaz",
        device_name: "Xiaomi Topaz",
        rom_version: "OS3.0.1",
        region: "Global",
        android: "A16",
        final_zip: "DeadZoneLite_v1.23_TOPAZ_OS3.0.1_Global-A16.zip",
        drive_link: "https://drive.google.com/file/d/topaz/view",
      }),
    });

    const token = buildPublishToken(env.medo_lite_bot.rows[0]);
    const result = await publishLatestManualBuild(env, token);
    assert.equal(result.ok, true);
    assert.equal(calls.length, 1);
    assert.match(calls[0].url, /sendMessage$/);
    assert.equal(calls[0].options.chat_id, "-100release");
    assert.equal(calls[0].options.parse_mode, "HTML");
    assert.match(calls[0].options.text, /DeadZone Lite v1\.23 Released/);
    assert.match(calls[0].options.text, /Click Here/);

    const caption = formatReleaseCaptionFromBuild(env.medo_lite_bot.rows[0]);
    assert.match(caption, /#topaz #DeadZoneLite #HyperOS3 #Android16 #MEZO/);
  }

  {
    const env = makeEnv();
    const calls = [];
    __setFetchImpl(async (url, options) => {
      calls.push({ url, options: JSON.parse(options.body) });
      return new Response(JSON.stringify({ ok: true, result: true }), {
        status: 200,
        headers: { "content-type": "application/json" },
      });
    });

    await updateBuildFromWorkflow(env, {
      romLink: "https://example.com/rom-6.zip",
      userId: "",
      userName: "manual-builder",
      status: "success",
      updatedAt: "2026-06-26T17:00:00.000Z",
      metadata: sanitizeBuildMetadata({
        device_codename: "agate",
        device_name: "Xiaomi Agate",
        rom_version: "OS2.9.0",
        region: "India",
        android: "A15",
        final_zip: "DeadZoneLite_v2.00_AGATE_OS2.9.0_India-A15.zip",
        drive_link: "https://drive.google.com/file/d/agate/view",
      }),
    });

    const token = buildPublishToken(env.medo_lite_bot.rows[0]);
    await handleCallbackQuery(env, {
      id: "cb-yes",
      data: `dz_publish_yes:${token}`,
      from: { id: "999" },
      message: { chat: { id: "999" }, message_id: 500 },
    });

    assert.equal(calls.length, 3);
    assert.match(calls[0].url, /sendMessage$/);
    assert.match(calls[1].url, /editMessageText$/);
    assert.match(calls[2].url, /answerCallbackQuery$/);
    assert.match(calls[1].options.text, /Published to release channel/);
  }

  {
    const env = makeEnv();
    const calls = [];
    __setFetchImpl(async (url, options) => {
      calls.push({ url, options: JSON.parse(options.body) });
      return new Response(JSON.stringify({ ok: true, result: true }), {
        status: 200,
        headers: { "content-type": "application/json" },
      });
    });

    await handleCallbackQuery(env, {
      id: "cb-no",
      data: "dz_publish_no:deadbeef",
      from: { id: "999" },
      message: { chat: { id: "999" }, message_id: 501 },
    });

    assert.equal(calls.length, 2);
    assert.match(calls[0].url, /editMessageText$/);
    assert.match(calls[1].url, /answerCallbackQuery$/);
    assert.match(calls[0].options.text, /Release post skipped by MEZO/);
  }

  {
    const env = makeEnv();
    const calls = [];
    __setFetchImpl(async (url, options) => {
      calls.push({ url, options: JSON.parse(options.body) });
      return new Response(JSON.stringify({ ok: true, result: true }), {
        status: 200,
        headers: { "content-type": "application/json" },
      });
    });

    await handleCallbackQuery(env, {
      id: "cb-unauthorized",
      data: "dz_publish_yes:deadbeef",
      from: { id: "123" },
      message: { chat: { id: "123" }, message_id: 502 },
    });

    assert.equal(calls.length, 1);
    assert.match(calls[0].url, /answerCallbackQuery$/);
    assert.equal(calls[0].options.text, "Unauthorized");
  }

  {
    const env = makeEnv();
    const calls = [];
    const warnings = [];
    const originalWarn = console.warn;
    console.warn = (...args) => warnings.push(args.join(" "));
    __setFetchImpl(async (url, options) => {
      const payload = JSON.parse(options.body);
      calls.push({ url, options: payload });
      if (calls.length === 1) {
        return new Response(JSON.stringify({
          ok: false,
          error_code: 400,
          description: "Bad Request: message to be replied not found",
        }), {
          status: 200,
          headers: { "content-type": "application/json" },
        });
      }
      return new Response(JSON.stringify({ ok: true, result: { message_id: 900 } }), {
        status: 200,
        headers: { "content-type": "application/json" },
      });
    });

    try {
      await sendTelegramMessage(env, "-100public", "hello", 123, "HTML");
    } finally {
      console.warn = originalWarn;
    }

    assert.equal(calls.length, 2);
    assert.equal(calls[0].options.reply_to_message_id, 123);
    assert.equal(calls[0].options.parse_mode, "HTML");
    assert.ok(!("reply_to_message_id" in calls[1].options));
    assert.equal(calls[1].options.parse_mode, "HTML");
    assert.equal(warnings.length, 2);
    assert.match(warnings[0], /\[telegram\] API returned ok=false sendMessage description=Bad Request: message to be replied not found/);
    assert.match(warnings[1], /\[telegram\] Reply target missing; retrying sendMessage without reply_to_message_id/);
  }

  {
    const env = makeEnv();
    const warnings = [];
    const originalWarn = console.warn;
    console.warn = (...args) => warnings.push(args.join(" "));
    __setFetchImpl(async () => new Response("bad html payload", { status: 400 }));

    try {
      await callTelegramApi(env, "sendMessage", { text: "test" }, "telegram_send_failed");
      assert.fail("expected callTelegramApi to throw on non-OK HTTP response");
    } catch (error) {
      assert.equal(error.message, "telegram_send_failed");
      assert.equal(error.telegramStatus, 400);
      assert.equal(error.telegramDescription, "bad html payload");
      assert.equal(error.telegramBody, "bad html payload");
    } finally {
      console.warn = originalWarn;
    }

    assert.equal(warnings.length, 1);
    assert.match(warnings[0], /\[telegram\] API failed sendMessage status=400 body=bad html payload/);
  }

  {
    const env = makeEnv();
    const warnings = [];
    const originalWarn = console.warn;
    console.warn = (...args) => warnings.push(args.join(" "));
    __setFetchImpl(async () =>
      new Response(JSON.stringify({ ok: false, description: "Bad Request: can't parse entities" }), {
        status: 200,
        headers: { "content-type": "application/json" },
      }),
    );

    try {
      await callTelegramApi(env, "sendMessage", { text: "test" }, "telegram_send_failed");
      assert.fail("expected callTelegramApi to throw when Telegram returns ok=false");
    } catch (error) {
      assert.equal(error.message, "telegram_send_failed");
      assert.equal(error.telegramStatus, 200);
      assert.equal(error.telegramDescription, "Bad Request: can't parse entities");
      assert.match(error.telegramBody, /can't parse entities/);
    } finally {
      console.warn = originalWarn;
    }

    assert.equal(warnings.length, 1);
    assert.match(warnings[0], /\[telegram\] API returned ok=false sendMessage description=Bad Request: can't parse entities/);
  }

  console.log("worker.sync.test: ok");
}

await main();
