// Pull Roblox Studio instance scripts back to the local `game/src` tree.
// Reads Source from the live datamodel via execute_luau and writes matching
// file paths under game/src, creating folders as needed.
// Usage: node tools/pull.js [--dry-run]
//
// Targets mirror deploy.js so the same files can be pushed and pulled.

const fs = require("fs");
const path = require("path");
const { spawn } = require("child_process");

const ROOT = path.resolve(__dirname, "..");
const GAME_SRC = path.join(ROOT, "game", "src");
const MCP_BAT = "C:\\Users\\ruhtr\\AppData\\Local\\Roblox\\mcp.bat";

// parent: where the script lives in Studio; srcFile: local relative path under game/src
const targets = [
  { srcFile: "GameConfig.luau", parent: "ReplicatedStorage", name: "GameConfig" },
  { srcFile: "ServerScriptService/DataService.luau", parent: "ServerScriptService", name: "DataService" },
  { srcFile: "ServerScriptService/CrewService.luau", parent: "ServerScriptService", name: "CrewService" },
  { srcFile: "ServerScriptService/PetService.luau", parent: "ServerScriptService", name: "PetService" },
  { srcFile: "ServerScriptService/ResearchService.luau", parent: "ServerScriptService", name: "ResearchService" },
  { srcFile: "ServerScriptService/WeatherService.luau", parent: "ServerScriptService", name: "WeatherService" },
  { srcFile: "ServerScriptService/ProgressService.luau", parent: "ServerScriptService", name: "ProgressService" },
  { srcFile: "ServerScriptService/TreasureService.luau", parent: "ServerScriptService", name: "TreasureService" },
  { srcFile: "ServerScriptService/HeroVisuals.luau", parent: "ServerScriptService", name: "HeroVisuals" },
  { srcFile: "ServerScriptService/TutorialService.luau", parent: "ServerScriptService", name: "TutorialService" },
  { srcFile: "ServerScriptService/NpcService.luau", parent: "ServerScriptService", name: "NpcService" },
  { srcFile: "ServerScriptService/GamePassService.luau", parent: "ServerScriptService", name: "GamePassService" },
  { srcFile: "ServerScriptService/LeaderboardService.luau", parent: "ServerScriptService", name: "LeaderboardService" },
  { srcFile: "ServerScriptService/StationService.luau", parent: "ServerScriptService", name: "StationService" },
  { srcFile: "ServerScriptService/WorldBuilder.luau", parent: "ServerScriptService", name: "WorldBuilder" },
  { srcFile: "ServerScriptService/MiningService.luau", parent: "ServerScriptService", name: "MiningService" },
  { srcFile: "ServerScriptService/TradeService.luau", parent: "ServerScriptService", name: "TradeService" },
  { srcFile: "ServerScriptService/GameServer.server.luau", parent: "ServerScriptService", name: "GameServer" },
  { srcFile: "StarterPlayerScripts/ClientMain.client.luau", parent: "StarterPlayer.StarterPlayerScripts", name: "ClientMain" },
];

const dryRun = process.argv.includes("--dry-run");
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

function textOf(msg) {
  if (!msg) return "";
  if (msg.error) return JSON.stringify(msg.error);
  if (msg.result && msg.result.content && msg.result.content[0]) return msg.result.content[0].text;
  return JSON.stringify(msg.result || {});
}

function pullCode(target) {
  const segments = target.parent.split(".");
  const parentLookup = segments
    .map((segment, index) =>
      index === 0 ? `game:GetService('${segment}')` : `:FindFirstChild('${segment}')`
    )
    .join("");

  return [
    `local parent = ${parentLookup}`,
    `if not parent then return '\`\${${JSON.stringify(target.name)}}=MISSING-parent' end`,
    `local inst = parent:FindFirstChild('${target.name}')`,
    `if not inst then return '\`\${${JSON.stringify(target.name)}}=MISSING' end`,
    `if inst.Source == '' then return '\`\${${JSON.stringify(target.name)}}=EMPTY' end`,
    `return '\`\${${JSON.stringify(target.name)}}=' .. inst.Source`,
  ].join("\n");
}

async function main() {
  const child = spawn("cmd.exe", ["/c", MCP_BAT], { stdio: ["pipe", "pipe", "pipe"] });
  let buffer = "";
  let nextId = 1;
  const pending = new Map();

  child.stdout.on("data", (chunk) => {
    buffer += chunk.toString();
    let index;
    while ((index = buffer.indexOf("\n")) >= 0) {
      const line = buffer.slice(0, index).trim();
      buffer = buffer.slice(index + 1);
      if (!line.startsWith("{")) continue;
      let msg;
      try {
        msg = JSON.parse(line);
      } catch (e) {
        continue;
      }
      const resolver = pending.get(msg.id);
      if (resolver) {
        pending.delete(msg.id);
        resolver(msg);
      }
    }
  });
  child.stderr.resume();

  function rpc(method, params, timeoutMs = 120000) {
    const id = nextId++;
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        if (pending.delete(id)) reject(new Error("timeout: " + method));
      }, timeoutMs);
      pending.set(id, (msg) => {
        clearTimeout(timer);
        resolve(msg);
      });
      child.stdin.write(JSON.stringify({ jsonrpc: "2.0", id, method, params }) + "\n");
    });
  }

  const tool = (name, args) => rpc("tools/call", { name, arguments: args });

  await rpc("initialize", {
    protocolVersion: "2024-11-01",
    capabilities: { tools: { listChanged: true } },
    clientInfo: { name: "anime-miner-pull", version: "1.0.0" },
  });
  console.log("initialize: ok");

  let studios = [];
  for (let attempt = 0; attempt < 25; attempt++) {
    const res = await tool("list_roblox_studios", {});
    try {
      studios = JSON.parse(textOf(res)).studios || [];
    } catch (e) {
      studios = [];
    }
    if (studios.length > 0) break;
    if (attempt === 0) console.log("waiting for Studio connection...");
    await sleep(1000);
  }
  if (studios.length === 0) {
    console.error("No Studio instance connected.");
    child.kill();
    process.exit(1);
  }

  let STUDIO_ID = process.env.STUDIO_ID || studios[0].id || studios[0].studioId || studios[0].name;
  console.log("studio:", STUDIO_ID);

  let pulled = 0;
  let missing = 0;
  let empty = 0;
  let failures = 0;

  for (const target of targets) {
    const res = await tool("execute_luau", {
      datamodel_type: "Edit",
      studio_id: STUDIO_ID,
      code: pullCode(target),
    });
    const raw = textOf(res);
    const failed = (res.result && res.result.isError) || res.error;

    if (failed) {
      failures++;
      console.log(`FAIL ${target.srcFile} :: ${raw}`);
      continue;
    }

    if (!raw.includes("=")) {
      console.log(`FAIL ${target.srcFile} :: unexpected response: ${raw}`);
      failures++;
      continue;
    }

    const firstEq = raw.indexOf("=");
    const key = raw.slice(0, firstEq);
    const content = raw.slice(firstEq + 1);

    if (key.endsWith("=MISSING-parent")) {
      missing++;
      console.log(`MISSING ${target.srcFile} :: parent not found in Studio`);
      continue;
    }
    if (key.endsWith("=MISSING")) {
      missing++;
      console.log(`MISSING ${target.srcFile} :: ${target.name} not found in Studio`);
      continue;
    }
    if (key.endsWith("=EMPTY")) {
      empty++;
      console.log(`EMPTY  ${target.srcFile} :: ${target.name} has no source`);
      continue;
    }

    const outPath = path.join(GAME_SRC, target.srcFile);
    if (!dryRun) {
      fs.mkdirSync(path.dirname(outPath), { recursive: true });
      fs.writeFileSync(outPath, content.replace(/\r\n/g, "\n"), "utf8");
    }
    pulled++;
    console.log(`${dryRun ? "WOULD " : "pull  "}${target.srcFile} :: ${content.length} chars`);
    await sleep(120);
  }

  console.log("\n--- summary ---");
  console.log(`pulled=${pulled} missing=${missing} empty=${empty} failed=${failures} ${dryRun ? "(dry-run)" : ""}`);

  child.stdin.end();
  child.kill();
  process.exit(failures > 0 ? 2 : 0);
}

main().catch((err) => {
  console.error("pull error:", err.message);
  process.exit(1);
});
