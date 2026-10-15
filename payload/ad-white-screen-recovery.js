"use strict";

// Local recovery add-on. It does not access the game's save data or translations.
const { app, globalShortcut } = require("electron");
const fs = require("fs");
const path = require("path");

const SHORTCUTS = ["F5", "CommandOrControl+Alt+R"];
const LOG_LIMIT = 1024 * 1024;

function attach(window) {
  if (window.__adWhiteScreenRecovery) return;
  window.__adWhiteScreenRecovery = true;
  const contents = window.webContents;
  const ownedShortcuts = new Set();
  let fallbackTimer;
  let lastRecovery = 0;
  let unresponsive = false;

  function log(event, details = {}) {
    try {
      const directory = path.join(app.getPath("userData"), "white-screen-recovery");
      fs.mkdirSync(directory, { recursive: true });
      const file = path.join(directory, "recovery.log");
      if (fs.existsSync(file) && fs.statSync(file).size > LOG_LIMIT) return;
      fs.appendFileSync(file, JSON.stringify({ at: new Date().toISOString(), event, ...details }) + "\n", "utf8");
    } catch (_) {
      // Logging must never prevent recovery or affect the game.
    }
  }

  function memorySnapshot() {
    try {
      return app.getAppMetrics().map(metric => ({
        type: metric.type,
        workingSetKB: metric.memory && metric.memory.workingSetSize,
        privateKB: metric.memory && metric.memory.privateBytes
      }));
    } catch (_) { return []; }
  }

  function clearFallback() {
    if (fallbackTimer !== undefined) clearTimeout(fallbackTimer);
    fallbackTimer = undefined;
  }

  function recreateRenderer(reason) {
    if (window.isDestroyed() || contents.isDestroyed()) return;
    clearFallback();
    log("renderer-recreate", { reason, memory: memorySnapshot() });
    try {
      contents.forcefullyCrashRenderer();
      contents.reload();
    } catch (error) {
      log("recovery-error", { message: String(error.message || error) });
    }
  }

  function recover() {
    if (window.isDestroyed() || !window.isFocused() || contents.isDestroyed()) return;
    const now = Date.now();
    if (now - lastRecovery < 2000) return;
    lastRecovery = now;
    log("manual-recovery", { unresponsive, memory: memorySnapshot() });
    clearFallback();
    // If a renderer stopped responding, a normal navigation may also hang.
    if (unresponsive) {
      recreateRenderer("window-unresponsive");
      return;
    }
    fallbackTimer = setTimeout(() => recreateRenderer("reload-timeout"), 8000);
    try {
      contents.reloadIgnoringCache();
    } catch (error) {
      log("reload-error", { message: String(error.message || error) });
      recreateRenderer("reload-error");
    }
  }

  function unregister() {
    for (const shortcut of ownedShortcuts) globalShortcut.unregister(shortcut);
    ownedShortcuts.clear();
  }

  function register() {
    if (window.isDestroyed() || !window.isFocused()) return;
    for (const shortcut of SHORTCUTS) {
      if (ownedShortcuts.has(shortcut)) continue;
      if (globalShortcut.register(shortcut, recover)) ownedShortcuts.add(shortcut);
      else log("shortcut-unavailable", { shortcut });
    }
  }

  window.on("focus", register);
  window.on("blur", unregister);
  window.on("closed", () => { clearFallback(); unregister(); });
  window.on("unresponsive", () => {
    unresponsive = true;
    log("window-unresponsive", { memory: memorySnapshot() });
  });
  window.on("responsive", () => { unresponsive = false; log("window-responsive"); });
  contents.on("did-finish-load", () => {
    clearFallback();
    unresponsive = false;
    log("page-loaded");
  });
  contents.on("render-process-gone", (_event, details) => {
    log("renderer-gone", { reason: details.reason, exitCode: details.exitCode, memory: memorySnapshot() });
  });
  app.on("before-quit", () => { clearFallback(); unregister(); });
  log("recovery-ready", { version: "1.0.0", electron: process.versions.electron, shortcuts: SHORTCUTS });
  register();
}

module.exports = { attach };
