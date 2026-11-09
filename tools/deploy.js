// Deploy the Anime Miner Tycoon scripts into the running Roblox Studio instance.
// Source injection via execute_luau is idempotent: it replaces Source instead of
// appending to it, so repeated deploys always produce exactly one copy.
// Usage: node tools/deploy.js [--verify-only]
// Optional: set env.STUDIO_ID to pin a specific Studio instance.

const fs = require("fs");
const path = require("path");
const { spawn } = require("child_process");

const ROOT = path.resolve(__dirname, "..");
// studio id is resolved from whatever Studio is connected (override with STUDIO_ID)
let STUDIO_ID = process.env.STUDIO_ID || "";

function mcpBatPath() {
  // Prefer an explicit MCP_BAT path if set, otherwise fall back to the local user's
  // standard Roblox mcp.bat location.
  const explicit = process.env.MCP_BAT;
  if (explicit && fs.existsSync(explicit)) return explicit;

  const localAppData = process.env.LOCALAPPDATA;
  if (localAppData) {
    const candidate = path.join(localAppData, "Roblox", "mcp.bat");
    if (fs.existsSync(candidate)) return candidate;
  }

  return path.join(process.env.LOCALAPPDATA || "C:\\Users\\sebas\\AppData\\Local", "Roblox", "mcp.bat");
}

const MCP_BAT = mcpBatPath();

// parent: service name, or "StarterPlayer.StarterPlayerScripts"
const targets = [
  { file: "game/src/GameConfig.luau", parent: "ReplicatedStorage", name: "GameConfig", className: "ModuleScript" },
  { file: "game/src/ServerScriptService/DataService.luau", parent: "ServerScriptService", name: "DataService", className: "ModuleScript" },
  { file: "game/src/ServerScriptService/CrewService.luau", parent: "ServerScriptService", name: "CrewService", className: "ModuleScript" },
  { file: "game/src/ServerScriptService/PetService.luau", parent: "ServerScriptService", name: "PetService", className: "ModuleScript" },
  { file: "game/src/ServerScriptService/ResearchService.luau", parent: "ServerScriptService", name: "ResearchService", className: "ModuleScript" },
  { file: "game/src/ServerScriptService/WeatherService.luau", parent: "ServerScriptService", name: "WeatherService", className: "ModuleScript" },
  { file: "game/src/ServerScriptService/ProgressService.luau", parent: "ServerScriptService", name: "ProgressService", className: "ModuleScript" },
  { file: "game/src/ServerScriptService/TreasureService.luau", parent: "ServerScriptService", name: "TreasureService", className: "ModuleScript" },
  { file: "game/src/ServerScriptService/HeroVisuals.luau", parent: "ServerScriptService", name: "HeroVisuals", className: "ModuleScript" },
  { file: "game/src/ServerScriptService/TutorialService.luau", parent: "ServerScriptService", name: "TutorialService", className: "ModuleScript" },
  { file: "game/src/ServerScriptService/NpcService.luau", parent: "ServerScriptService", name: "NpcService", className: "ModuleScript" },
  { file: "game/src/ServerScriptService/GamePassService.luau", parent: "ServerScriptService", name: "GamePassService", className: "ModuleScript" },
  { file: "game/src/ServerScriptService/LeaderboardService.luau", parent: "ServerScriptService", name: "LeaderboardService", className: "ModuleScript" },
  { file: "game/src/ServerScriptService/StationService.luau", parent: "ServerScriptService", name: "StationService", className: "ModuleScript" },
  { file: "game/src/ServerScriptService/WorldBuilder.luau", parent: "ServerScriptService", name: "WorldBuilder", className: "ModuleScript" },
  { file: "game/src/ServerScriptService/MiningService.luau", parent: "ServerScriptService", name: "MiningService", className: "ModuleScript" },
  { file: "game/src/ServerScriptService/TradeService.luau", parent: "ServerScriptService", name: "TradeService", className: "ModuleScript" },
  { file: "game/src/ServerScriptService/GameServer.server.luau", parent: "ServerScriptService", name: "GameServer", className: "Script" },
  { file: "game/src/ServerScriptService/HelloWorldScript.luau", parent: "ServerScriptService", name: "HelloWorldScript", className: "Script" },
  { file: "game/src/StarterPlayerScripts/ClientMain.client.luau", parent: "StarterPlayer.StarterPlayerScripts", name: "ClientMain", className: "LocalScript" },
];

const deployArgs = process.argv.slice(2);
const verifyOnly = deployArgs.includes("--verify-only");
const showHelp = deployArgs.includes("--help");
const help =
  "Usage: node tools/deploy.js [--verify-only] [--help]\n\n" +
  "Pushes the Luau sources under game/src/ into the running Roblox Studio session\n" +
  "that is connected to this machine's Studio MCP bridge.\n\n" +
  "Options:\n" +
  "  --verify-only   Read sources and verify them in Studio without pushing anything new.\n" +
  "  --help          Print this message and exit.\n\n" +
  "Environment:\n" +
  "  STUDIO_ID       Optional. If set, pins the target Studio instance instead of picking\n" +
  "                 whichever Studio is connected first.\n" +
  "  MCP_BAT         Optional. Overrides the path to the local Studio MCP bridge batch\n" +
  "                 file. Default: %LOCALAPPDATA%\\Roblox\\mcp.bat.";
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

function textOf(msg) {
  if (!msg) return "";
  if (msg.error) return JSON.stringify(msg.error);
  if (msg.result && msg.result.content && msg.result.content[0]) return msg.result.content[0].text;
  return JSON.stringify(msg.result || {});
}

function sourceCode(target, content) {
  const segments = target.parent.split(".");
  const parentLookup = segments
    .map((segment, index) =>
      index === 0 ? `game:GetService('${segment}')` : `:FindFirstChild('${segment}')`
    )
    .join("");

  return [
    `local parent = ${parentLookup}`,
    "if not parent then return 'parent missing' end",
    `local inst = parent:FindFirstChild('${target.name}')`,
    `if inst and inst.ClassName ~= '${target.className}' then inst:Destroy() inst = nil end`,
    "if not inst then",
    `  inst = Instance.new('${target.className}')`,
    `  inst.Name = '${target.name}'`,
    "  inst.Parent = parent",
    "end",
    `inst.Source = [==========[\n${content}\n]==========]`,
    `return '${target.name}: ' .. #inst.Source .. ' chars'`,
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

  if (showHelp) {
    console.log(help);
    child.kill();
    process.exit(0);
  }

  await rpc("initialize", {
    protocolVersion: "2024-11-01",
    capabilities: { tools: { listChanged: true } },
    clientInfo: { name: "anime-miner-deploy", version: "2.0.0" },
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
  STUDIO_ID = STUDIO_ID || (() => {
    const first = studios[0];
    return first.id || first.studioId || first.name || first;
  })();
  console.log("studio:", STUDIO_ID, "of", JSON.stringify(studios.map((s) => (typeof s === "string" ? s : s.id || s.studioId || s.name || s))));

  let failures = 0;

  if (!verifyOnly) {
    for (const target of targets) {
      const filePath = path.join(ROOT, target.file);
      if (!fs.existsSync(filePath)) {
        console.error("MISSING " + target.file);
        failures++;
        continue;
      }
      const content = fs.readFileSync(filePath, "utf8").replace(/\r\n/g, "\n").replace(/\n$/, "");
      const res = await tool("execute_luau", {
        datamodel_type: "Edit",
        studio_id: STUDIO_ID,
        code: sourceCode(target, content),
      });
      const failed = (res && (res.result && res.result.isError)) || res.error;
      if (failed) failures++;
      console.log((failed ? "FAIL " : "ok   ") + target.name + " :: " + textOf(res));
      if (!verifyOnly) await sleep(120);
    }
  }

  const verifyCode = [
    "local ss = game:GetService('ServerScriptService')",
    "local rs = game:GetService('ReplicatedStorage')",
    "local sps = game:GetService('StarterPlayer'):FindFirstChild('StarterPlayerScripts')",
    "local lines = {}",
    "for _, inst in ipairs(ss:GetChildren()) do",
    "  if inst:IsA('LuaSourceContainer') then",
    "    table.insert(lines, '  ' .. inst.ClassName .. ' :: ' .. inst.Name .. ' (' .. #inst.Source .. ' chars)')",
    "  end",
    "end",
    "local cfg = rs:FindFirstChild('GameConfig')",
    "table.insert(lines, 'GameConfig: ' .. tostring(cfg ~= nil) .. (cfg and (' ' .. #cfg.Source .. ' chars') or ''))",
    "table.insert(lines, 'ClientMain: ' .. tostring(sps ~= nil and sps:FindFirstChild('ClientMain') ~= nil))",
    "return table.concat(lines, '\\n')",
  ].join("\n");

  const verify = await tool("execute_luau", {
    datamodel_type: "Edit",
    studio_id: STUDIO_ID,
    code: verifyCode,
  });
  console.log("--- verification ---");
  console.log(textOf(verify));

  child.stdin.end();
  child.kill();
  process.exit(failures > 0 ? 2 : 0);
}

main().catch((err) => {
  console.error("deploy error:", err.message);
  process.exit(1);
});
