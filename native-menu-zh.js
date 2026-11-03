/* MIT License; see LICENSE. Native locale bridge for Claude Desktop. */
(() => {
  "use strict";
  if (!((location.protocol === "app:" && location.hostname === "localhost") ||
        (location.protocol === "https:" && location.hostname === "claude.ai") ||
        (location.protocol === "file:" && /\/resources\/ion-dist(?:\.asar)?\//i.test(location.pathname || "")))) {
    throw new Error("Native menu translation requires a Claude page.");
  }
  const CONTROLLER = "__claudeNativeMenuZh";
  const STORAGE = "__claudeNativeMenuZhBackupV1";
  const TARGET = "zh-Hans";
  const VERSION = "0.5.0";
  const existing = globalThis[CONTROLLER];
  if (existing) {
    if (existing.version !== VERSION || typeof existing.apply !== "function" || typeof existing.restore !== "function") {
      throw new Error("Unknown native menu controller; refresh the page before retrying.");
    }
    return existing;
  }
  let queue = Promise.resolve();
  let last = {supported: false, changed: false, reason: "not-run"};
  const validLocale = value => typeof value === "string" && /^[a-z]{2,3}(?:-[A-Za-z0-9]{2,8})*$/.test(value);
  function bridge() {
    const api = globalThis["claude.hybrid"]?.DesktopIntl;
    return api && typeof api.getInitialLocale === "function" && typeof api.requestLocaleChange === "function" ? api : null;
  }
  async function readLocale(api) {
    const result = await api.getInitialLocale();
    if (!validLocale(result?.locale)) throw new Error("Invalid native locale response.");
    return result.locale;
  }
  function readBackup() {
    const raw = localStorage.getItem(STORAGE);
    if (raw === null) return null;
    let record;
    try { record = JSON.parse(raw); } catch { throw new Error("Invalid native locale backup; preserved for inspection."); }
    if (record?.version !== 1 || record.targetLocale !== TARGET || !validLocale(record.previousLocale) || record.previousLocale === TARGET) {
      throw new Error("Invalid native locale backup; preserved for inspection.");
    }
    return record;
  }
  function saveBackup(previousLocale) {
    const record = {version: 1, previousLocale, targetLocale: TARGET};
    const raw = JSON.stringify(record);
    localStorage.setItem(STORAGE, raw);
    if (localStorage.getItem(STORAGE) !== raw) throw new Error("Native locale backup could not be verified; no change requested.");
  }
  async function applyNative() {
    const api = bridge();
    if (!api) return {supported: false, changed: false, reason: "bridge-unavailable"};
    const current = await readLocale(api);
    readBackup(); // Do not destroy an unreadable recovery record.
    if (current === TARGET) return {supported: true, changed: false, locale: current};
    saveBackup(current); // Must succeed before changing the application's persisted locale.
    await api.requestLocaleChange(TARGET);
    if (await readLocale(api) !== TARGET) throw new Error("Native locale verification failed; backup retained.");
    return {supported: true, changed: true, locale: TARGET};
  }
  async function restoreNative() {
    const api = bridge();
    if (!api) return {supported: false, changed: false, reason: "bridge-unavailable"};
    const backup = readBackup();
    if (!backup) return {supported: true, changed: false, reason: "no-owned-backup"};
    const current = await readLocale(api);
    if (current === backup.previousLocale) {
      localStorage.removeItem(STORAGE);
      return {supported: true, changed: false, locale: current};
    }
    if (current !== TARGET) return {supported: true, changed: false, locale: current, reason: "external-change"};
    await api.requestLocaleChange(backup.previousLocale);
    if (await readLocale(api) !== backup.previousLocale) throw new Error("Native restore verification failed; backup retained.");
    localStorage.removeItem(STORAGE);
    return {supported: true, changed: true, locale: backup.previousLocale};
  }
  async function inspectNative() {
    const api = bridge();
    if (!api) return {supported: false};
    const data = await api.getInitialLocale();
    if (!validLocale(data?.locale)) throw new Error("Invalid native locale response.");
    const ids = {undo:"Xda79B7DPP",redo:"R0/CZEcsoI",cut:"4MLbtbVfJv",copy:"+7sd9hoyZA",
      paste:"JVwNvMZjVT",selectAll:"grarAzxOkG",inspectElement:"KETtxy51p+"};
    const labels = {};
    for (const [name, id] of Object.entries(ids)) {
      if (typeof data.messages?.[id] === "string") labels[name] = data.messages[id];
    }
    return {supported: true, locale: data.locale, labels};
  }
  function run(operation) {
    const result = queue.then(operation);
    queue = result.catch(() => {}); // A failed request must not poison subsequent retries.
    return result.then(value => { last = value; return {...value}; });
  }
  const controller = Object.freeze({version: VERSION,
    apply: () => run(applyNative), restore: () => run(restoreNative),
    inspect: () => queue.then(inspectNative), status: () => ({...last})});
  globalThis[CONTROLLER] = controller;
  return controller;
})();
