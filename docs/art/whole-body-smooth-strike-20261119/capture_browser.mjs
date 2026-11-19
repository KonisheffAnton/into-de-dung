// Забирает завершённый QA JSON напрямую; не ждёт окончания анимационного DOM.
import { spawn } from "node:child_process";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { resolve, join } from "node:path";
import { pathToFileURL } from "node:url";
import { randomUUID } from "node:crypto";

const [pagePath, outputPath, cachePath] = process.argv.slice(2);
if (!pagePath || !outputPath || !cachePath) throw Error("Expected page, output JSON and cache paths");
const profile = join(resolve(cachePath), "profile-cdp-" + randomUUID());
await mkdir(profile, { recursive: true });
const sleep = ms => new Promise(r => setTimeout(r, ms));
const browser = spawn("C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe", [
  "--headless", "--disable-gpu", "--no-first-run", "--no-default-browser-check",
  "--remote-debugging-port=0", "--user-data-dir=" + profile,
  "--allow-file-access-from-files", "--hide-scrollbars", "--window-size=1440,1100", "about:blank",
], { stdio: "ignore", windowsHide: true });
let exited = false, launchError = null;
browser.on("exit", () => { exited = true; });
browser.on("error", error => { launchError = error; exited = true; });

async function connect(url) {
  const socket = new WebSocket(url), pending = new Map();
  let sequence = 0;
  await new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(Error("CDP connect timeout")), 10000);
    socket.addEventListener("open", () => { clearTimeout(timer); resolve(); }, { once: true });
    socket.addEventListener("error", () => { clearTimeout(timer); reject(Error("CDP socket error")); }, { once: true });
  });
  socket.addEventListener("message", event => {
    const response = JSON.parse(event.data);
    const request = pending.get(response.id);
    if (!request) return;
    pending.delete(response.id); clearTimeout(request.timer);
    if (response.error) request.reject(Error(JSON.stringify(response.error)));
    else request.resolve(response.result);
  });
  socket.addEventListener("close", () => {
    for (const request of pending.values()) { clearTimeout(request.timer); request.reject(Error("CDP closed")); }
    pending.clear();
  });
  return {
    call(method, params = {}, timeout = 120000) {
      return new Promise((resolve, reject) => {
        const id = ++sequence;
        const timer = setTimeout(() => { pending.delete(id); reject(Error("CDP timeout: " + method)); }, timeout);
        pending.set(id, { resolve, reject, timer });
        socket.send(JSON.stringify({ id, method, params }));
      });
    },
    close: () => socket.close(),
  };
}

let root, page;
try {
  let port;
  for (let i = 0; i < 200; i++) {
    if (launchError) throw launchError;
    if (exited) throw Error("Headless Edge exited before CDP was ready");
    try {
      port = Number((await readFile(join(profile, "DevToolsActivePort"), "utf8")).split("\n")[0]);
      if (port > 0) break;
    } catch {}
    await sleep(50);
  }
  if (!port) throw Error("Headless Edge did not expose its isolated CDP port");
  const endpoint = "http://127.0.0.1:" + port;
  const info = await (await fetch(endpoint + "/json/version", { signal: AbortSignal.timeout(10000) })).json();
  root = await connect(info.webSocketDebuggerUrl);
  const { targetId } = await root.call("Target.createTarget", { url: pathToFileURL(resolve(pagePath)).href }, 10000);
  const targets = await (await fetch(endpoint + "/json/list", { signal: AbortSignal.timeout(10000) })).json();
  const target = targets.find(t => t.id === targetId);
  if (!target) throw Error("Created QA tab is absent from CDP target list");
  page = await connect(target.webSocketDebuggerUrl);
  const deadline = Date.now() + 150000;
  let text;
  while (Date.now() < deadline) {
    const value = await page.call("Runtime.evaluate", {
      expression: 'document.querySelector("#qa-output")?.textContent || null', returnByValue: true,
    }, Math.max(1, deadline - Date.now()));
    if (value.exceptionDetails) throw Error("QA capture evaluation failed");
    text = value.result?.value;
    if (text) break;
    await sleep(50);
  }
  if (!text) throw Error("QA result was not published before capture deadline");
  const report = JSON.parse(text);
  if (typeof report.pass !== "boolean") throw Error("QA result has no boolean pass status");
  await writeFile(resolve(outputPath), text, "utf8");
  console.log(JSON.stringify({ captured: true, pass: report.pass, checks: report.checks?.length, bytes: Buffer.byteLength(text) }));
} finally {
  if (page) page.close();
  if (root) {
    try { await root.call("Browser.close", {}, 5000); } catch {}
    root.close();
  }
  for (let i = 0; i < 50 && !exited; i++) await sleep(100);
  if (!exited) browser.kill();
}
