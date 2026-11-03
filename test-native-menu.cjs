"use strict";
const fs = require("node:fs");
const vm = require("node:vm");
const assert = require("node:assert/strict");
const path = require("node:path");
const source = fs.readFileSync(path.join(__dirname, "native-menu-zh.js"), "utf8");
const KEY = "__claudeNativeMenuZhBackupV1";
function fixture(options = {}) {
  const store = options.store || new Map();
  const calls = [];
  let locale = options.locale || "en-US";
  const api = {
    async getInitialLocale() { return {locale, messages: {}}; },
    async requestLocaleChange(value) {
      calls.push(value);
      if (options.reject) throw Error("request rejected");
      if (!options.ignore) locale = value;
    }
  };
  const context = vm.createContext({
    location: options.location || {protocol: "app:", hostname: "localhost"},
    "claude.hybrid": options.missing ? {} : {DesktopIntl: api},
    localStorage: {
      getItem: key => store.get(key) ?? null,
      setItem(key, value) { if (options.blockStorage) throw Error("storage blocked"); store.set(key, value); },
      removeItem(key) { if (options.blockRemove) throw Error("remove blocked"); store.delete(key); }
    }
  });
  const load = () => vm.runInContext(source, context);
  return {store, calls, api, context, load, locale: () => locale,
    setLocale: value => { locale = value; }};
}
let count = 0;
async function test(name, run) { await run(); count++; console.log("PASS:", name); }
(async () => {
  await test("reject unrelated origins without touching the bridge", async () => {
    const f = fixture({location: {protocol: "https:", hostname: "claude.ai.example.com"}});
    assert.throws(f.load, /Claude page/); assert.equal(f.calls.length, 0);
  });
  await test("missing bridge leaves web translation available", async () => {
    const f = fixture({missing: true}); const r = await f.load().apply();
    assert.equal(r.supported, false); assert.equal(f.store.size, 0);
  });
  await test("backup original locale before applying Chinese", async () => {
    const f = fixture(); const c = f.load();
    f.api.requestLocaleChange = async value => {
      assert.equal(JSON.parse(f.store.get(KEY)).previousLocale, "en-US");
      f.setLocale(value); f.calls.push(value);
    };
    const r = await c.apply(); assert.equal(r.locale, "zh-Hans");
    assert.equal(f.locale(), "zh-Hans"); assert.equal(f.calls.length, 1);
  });
  await test("repeated apply preserves the first backup", async () => {
    const f = fixture(); const c = f.load(); await c.apply(); const saved = f.store.get(KEY);
    await c.apply(); assert.equal(f.store.get(KEY), saved); assert.equal(f.calls.length, 1);
    assert.equal(f.load(), c);
  });
  await test("restore original locale and remove owned backup", async () => {
    const f = fixture({locale: "ja-JP"}); const c = f.load(); await c.apply(); await c.restore();
    assert.equal(f.locale(), "ja-JP"); assert.equal(f.store.size, 0);
  });
  await test("restore after page restart using persisted backup", async () => {
    const f = fixture(); await f.load().apply();
    const next = fixture({locale: "zh-Hans", store: f.store}); await next.load().restore();
    assert.equal(next.locale(), "en-US"); assert.equal(next.store.size, 0);
  });
  await test("native Chinese chosen before this script remains untouched", async () => {
    const f = fixture({locale: "zh-Hans"}); const c = f.load(); await c.apply(); await c.restore();
    assert.equal(f.calls.length, 0); assert.equal(f.store.size, 0);
  });
  await test("storage failure prevents native language change", async () => {
    const f = fixture({blockStorage: true}); await assert.rejects(f.load().apply(), /storage blocked/);
    assert.equal(f.calls.length, 0);
  });
  await test("malformed backup prevents apply and restore", async () => {
    const f = fixture({store: new Map([[KEY, "broken"]])}); const c = f.load();
    await assert.rejects(c.apply(), /backup/); await assert.rejects(c.restore(), /backup/);
    assert.equal(f.calls.length, 0); assert.equal(f.store.get(KEY), "broken");
  });
  await test("invalid prior locale is rejected", async () => {
    const f = fixture({locale: "../../outside"}); await assert.rejects(f.load().apply(), /locale/);
    assert.equal(f.calls.length, 0);
  });
  await test("external language change is not overwritten on restore", async () => {
    const f = fixture(); const c = f.load(); await c.apply(); f.setLocale("fr-FR");
    const r = await c.restore(); assert.equal(r.reason, "external-change"); assert.equal(f.locale(), "fr-FR");
  });
  await test("reapply after external change captures the new original", async () => {
    const f = fixture(); const c = f.load(); await c.apply(); f.setLocale("fr-FR");
    await c.apply(); await c.restore(); assert.equal(f.locale(), "fr-FR");
  });
  await test("request rejection keeps recovery metadata and permits retry", async () => {
    const options = {reject: true}; const f = fixture(options); const c = f.load();
    await assert.rejects(c.apply(), /request rejected/); assert(f.store.has(KEY));
    options.reject = false; await c.apply(); assert.equal(f.locale(), "zh-Hans");
  });
  await test("silent request failure is detected", async () => {
    const f = fixture({ignore: true}); await assert.rejects(f.load().apply(), /verification/);
    assert(f.store.has(KEY)); assert.equal(f.locale(), "en-US");
  });
  await test("failed restore preserves backup for retry", async () => {
    const options = {}; const f = fixture(options); const c = f.load(); await c.apply();
    options.reject = true; await assert.rejects(c.restore(), /request rejected/); assert(f.store.has(KEY));
    options.reject = false; await c.restore(); assert.equal(f.locale(), "en-US");
  });
  await test("concurrent apply and restore execute in order", async () => {
    const f = fixture(); const c = f.load(); await Promise.all([c.apply(), c.restore()]);
    assert.equal(f.locale(), "en-US"); assert.equal(f.store.size, 0);
  });
  await test("existing foreign controller is not replaced", async () => {
    const f = fixture(); f.context.__claudeNativeMenuZh = {version: "foreign"};
    assert.throws(f.load, /controller/); assert.equal(f.context.__claudeNativeMenuZh.version, "foreign");
  });
  await test("silent backup write loss prevents locale changes", async () => {
    const f = fixture(); f.context.localStorage.setItem = () => {};
    await assert.rejects(f.load().apply(), /backup could not be verified/); assert.equal(f.calls.length, 0);
  });
  await test("backup removal failure can be retried without another locale request", async () => {
    const options={}; const f=fixture(options); const c=f.load(); await c.apply();
    options.blockRemove=true; await assert.rejects(c.restore(), /remove blocked/);
    assert.equal(f.locale(), "en-US"); assert(f.store.has(KEY)); const calls=f.calls.length;
    options.blockRemove=false; await c.restore(); assert.equal(f.calls.length,calls); assert.equal(f.store.size,0);
  });
  await test("inspection reads only known menu labels without changing locale", async () => {
    const f=fixture(); f.api.getInitialLocale=async()=>({locale:"en-US",messages:{"+7sd9hoyZA":"Copy",private:"ignored"}});
    const r=await f.load().inspect(); assert.equal(r.labels.copy,"Copy"); assert.equal(r.labels.private,undefined);
    assert.equal(f.calls.length,0); assert.equal(f.store.size,0);
  });
  console.log(JSON.stringify({passed: true, test_count: count, ui_actions_performed: false}));
})().catch(error => { console.error(error); process.exitCode = 1; });
