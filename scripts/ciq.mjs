#!/usr/bin/env node
// Connect IQ helper behind the pnpm scripts in package.json.
//
//   node scripts/ciq.mjs <command> [app] [-d device] [-- extra monkeyc args]
//
// Commands: build, start, sim, package, devices, clean, apps
//
// [app] is an app directory (one containing manifest.xml + monkey.jungle).
// If omitted it's taken from the directory you ran pnpm in, or the only
// app in the repo. [device] defaults to the first product in manifest.xml.

import { spawn, spawnSync } from "node:child_process";
import { existsSync, readFileSync, readdirSync, rmSync, mkdirSync } from "node:fs";
import { basename, dirname, join, relative, resolve } from "node:path";
import { connect } from "node:net";
import { fileURLToPath } from "node:url";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const SIM_PORT = 1234;

const die = (msg) => {
  console.error(`ciq: ${msg}`);
  process.exit(1);
};

// ---------------------------------------------------------------- args

function parseArgs(argv) {
  const [command, ...rest] = argv;
  const opts = { command, app: undefined, device: undefined, extra: [] };
  for (let i = 0; i < rest.length; i++) {
    const a = rest[i];
    if (a === "--") {
      opts.extra = rest.slice(i + 1);
      break;
    } else if (a === "-d" || a === "--device") {
      opts.device = rest[++i];
    } else if (!opts.app) {
      opts.app = a;
    } else {
      die(`unexpected argument: ${a}`);
    }
  }
  return opts;
}

// ---------------------------------------------------------------- apps

const isApp = (dir) =>
  existsSync(join(dir, "manifest.xml")) && existsSync(join(dir, "monkey.jungle"));

function listApps() {
  return readdirSync(ROOT, { withFileTypes: true })
    .filter((e) => e.isDirectory() && !e.name.startsWith(".") && e.name !== "node_modules")
    .map((e) => join(ROOT, e.name))
    .filter(isApp);
}

function resolveApp(name) {
  if (name) {
    for (const candidate of [resolve(process.env.INIT_CWD ?? process.cwd(), name), join(ROOT, name)]) {
      if (isApp(candidate)) return candidate;
    }
    die(`'${name}' is not an app directory (needs manifest.xml and monkey.jungle)`);
  }
  // Walk up from where pnpm was invoked.
  let dir = resolve(process.env.INIT_CWD ?? process.cwd());
  while (dir.startsWith(ROOT) && dir !== ROOT) {
    if (isApp(dir)) return dir;
    dir = dirname(dir);
  }
  const apps = listApps();
  if (apps.length === 1) return apps[0];
  if (apps.length === 0) die("no apps found in the repo");
  die(`several apps found, pass one: ${apps.map((a) => basename(a)).join(", ")}`);
}

function manifestProducts(app) {
  const xml = readFileSync(join(app, "manifest.xml"), "utf8");
  return [...xml.matchAll(/<iq:product\s+id="([^"]+)"/g)].map((m) => m[1]);
}

function resolveDevice(app, device) {
  const products = manifestProducts(app);
  if (device) {
    if (!products.includes(device)) {
      console.warn(`ciq: warning: '${device}' isn't listed in manifest.xml (${products.join(", ")})`);
    }
    return device;
  }
  if (products.length === 0) die("manifest.xml lists no products; pass -d <device>");
  return products[0];
}

const prgPath = (app) => join(app, "bin", `${basename(app)}.prg`);

// ---------------------------------------------------------------- tools

function developerKey() {
  const key = process.env.CIQ_DEVELOPER_KEY;
  if (!key) die("CIQ_DEVELOPER_KEY is not set; are you in the nix dev shell? (direnv reload)");
  if (!existsSync(key)) die(`developer key not found at ${key}; run ciq-keygen`);
  return key;
}

function run(cmd, args, cwd) {
  console.log(`$ ${[cmd, ...args].join(" ")}`);
  const r = spawnSync(cmd, args, { cwd, stdio: "inherit" });
  if (r.error?.code === "ENOENT") die(`'${cmd}' not found; are you in the nix dev shell?`);
  if (r.status !== 0) process.exit(r.status ?? 1);
}

const simListening = () =>
  new Promise((ok) => {
    const s = connect(SIM_PORT, "127.0.0.1");
    s.once("connect", () => (s.destroy(), ok(true)));
    s.once("error", () => ok(false));
  });

async function ensureSim() {
  if (await simListening()) return;
  console.log("Starting simulator (ciq-sim)...");
  // The FHS sandbox runs bwrap with --die-with-parent, so the simulator would
  // die as soon as this script exits. A detached `sh` stays alive as its
  // parent (the trailing `:` stops sh from exec'ing ciq-sim in place).
  const child = spawn("sh", ["-c", "command -v ciq-sim >/dev/null || exit 127; ciq-sim; :"], {
    detached: true,
    stdio: "ignore",
  });
  child.on("error", (e) => die(e.message));
  child.unref();
  let exited = null;
  child.on("exit", (code) => (exited = code));
  const deadline = Date.now() + 30_000;
  while (Date.now() < deadline) {
    if (exited === 127) die("'ciq-sim' not found; are you in the nix dev shell?");
    if (exited !== null) die("simulator exited during startup; run 'ciq-sim' directly to see why");
    if (await simListening()) return;
    await new Promise((r) => setTimeout(r, 500));
  }
  die(`simulator didn't start listening on port ${SIM_PORT} within 30s`);
}

// ---------------------------------------------------------------- commands

function build(app, device, extra) {
  mkdirSync(join(app, "bin"), { recursive: true });
  run("monkeyc", ["-f", "monkey.jungle", "-d", device, "-y", developerKey(), "-o", relative(app, prgPath(app)), ...extra], app);
}

const commands = {
  apps() {
    for (const a of listApps()) console.log(`${basename(a)}\t${manifestProducts(a).join(", ")}`);
  },

  devices({ app }) {
    console.log(manifestProducts(resolveApp(app)).join("\n"));
  },

  build({ app, device, extra }) {
    app = resolveApp(app);
    build(app, resolveDevice(app, device), extra);
  },

  async start({ app, device, extra }) {
    app = resolveApp(app);
    device = resolveDevice(app, device);
    build(app, device, extra);
    await ensureSim();
    run("monkeydo", [relative(app, prgPath(app)), device], app);
  },

  async sim() {
    if (await simListening()) return console.log(`Simulator already running on port ${SIM_PORT}.`);
    await ensureSim();
    console.log("Simulator running.");
  },

  package({ app, extra }) {
    app = resolveApp(app);
    mkdirSync(join(app, "bin"), { recursive: true });
    const out = join("bin", `${basename(app)}.iq`);
    run("monkeyc", ["-e", "-r", "-f", "monkey.jungle", "-y", developerKey(), "-o", out, ...extra], app);
    console.log(`Store package: ${join(relative(ROOT, app), out)}`);
  },

  clean({ app }) {
    app = resolveApp(app);
    rmSync(join(app, "bin"), { recursive: true, force: true });
    console.log(`Removed ${join(relative(ROOT, app), "bin")}`);
  },
};

const opts = parseArgs(process.argv.slice(2));
const fn = commands[opts.command];
if (!fn) die(`unknown command '${opts.command ?? ""}'. Use one of: ${Object.keys(commands).join(", ")}`);
await fn(opts);
