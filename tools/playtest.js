// Play-test the Anime Miner Tycoon build inside Studio.
// Starts play mode, inspects the generated map, opens/closes the menu with a real
// mouse event, fires a gacha roll from the client, reads the HUD, dumps console output.

const { spawn } = require("child_process");

// resolved from the Studio instance that is actually connected
let STUDIO_ID = process.env.STUDIO_ID || "";
const MCP_BAT = "C:\\Users\\ruhtr\\AppData\\Local\\Roblox\\mcp.bat";

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function textOf(msg) {
  if (!msg) return "";
  if (msg.error) return JSON.stringify(msg.error);
  if (msg.result && msg.result.content && msg.result.content[0]) return msg.result.content[0].text;
  return JSON.stringify(msg.result || {});
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
  const edit = (code) => tool("execute_luau", { datamodel_type: "Server", studio_id: STUDIO_ID, code });
  const client = (code) => tool("execute_luau", { datamodel_type: "Client", studio_id: STUDIO_ID, code });

  await rpc("initialize", {
    protocolVersion: "2024-11-01",
    capabilities: { tools: { listChanged: true } },
    clientInfo: { name: "anime-miner-playtest", version: "3.0.0" },
  });

  let ready = false;
  for (let attempt = 0; attempt < 25 && !ready; attempt++) {
    const res = await tool("list_roblox_studios", {});
    try {
      ready = (JSON.parse(textOf(res)).studios || []).length > 0;
    } catch (e) {
      ready = false;
    }
    if (!ready) await sleep(1000);
  }
  if (!ready) {
    console.error("Studio not connected");
    process.exit(1);
  }

  if (!STUDIO_ID) {
    const list = await tool("list_roblox_studios", {});
    try {
      const found = JSON.parse(textOf(list)).studios || [];
      STUDIO_ID = found[0].id || found[0].studioId || found[0].name;
    } catch (e) {
      STUDIO_ID = "";
    }
  }
  console.log("studio:", STUDIO_ID);

  console.log("== starting play session ==");
  console.log(textOf(await tool("start_stop_play", { is_start: true, studio_id: STUDIO_ID })));
  await sleep(12000);

  console.log("\n== map ==");
  console.log(
    textOf(
      await edit([
        "local world = workspace:FindFirstChild('MineWorld')",
        "if not world then return 'MineWorld MISSING' end",
        "local zones = world:FindFirstChild('Zones')",
        "local oreModels, alive, parts, lights, emitters = 0, 0, 0, 0, 0",
        "local chests, heroRigs = 0, 0",
        "for _, d in ipairs(world:GetDescendants()) do",
        "  if d:IsA('BasePart') then parts += 1 end",
        "  if d:IsA('PointLight') then lights += 1 end",
        "  if d:IsA('ParticleEmitter') then emitters += 1 end",
        "  if d:IsA('Model') and d:GetAttribute('Zone') and d.Name:match('^Ore_') then",
        "    oreModels += 1",
        "    if d:GetAttribute('Alive') then alive += 1 end",
        "  end",
        "  if d:IsA('Model') and d.Name:match('^Chest_') then chests += 1 end",
        "end",
        "local zoneNames = {}",
        "for _, folder in ipairs(zones:GetChildren()) do",
        "  table.insert(zoneNames, folder.Name)",
        "  local heroes = folder:FindFirstChild('Heroes')",
        "  if heroes then heroRigs += #heroes:GetChildren() end",
        "end",
        "local hub = world:FindFirstChild('Hub')",
        "local portal = world:FindFirstChild('Portal') ~= nil",
        "return string.format('zones=%d [%s] oreModels=%d alive=%d chests=%d heroRigs=%d portal=%s parts=%d lights=%d emitters=%d hubParts=%d', #zoneNames, table.concat(zoneNames, ','), oreModels, alive, chests, heroRigs, tostring(portal), parts, lights, emitters, hub and #hub:GetChildren() or 0)",
      ].join("\n"))
    )
  );

  console.log("\n== lighting ==");
  console.log(
    textOf(
      await edit([
        "local l = game:GetService('Lighting')",
        "local bloom = l:FindFirstChildOfClass('BloomEffect')",
        "local cc = l:FindFirstChildOfClass('ColorCorrectionEffect')",
        "local atmo = l:FindFirstChildOfClass('Atmosphere')",
        "local lights = 0",
        "for _, d in ipairs(workspace:GetDescendants()) do if d:IsA('PointLight') then lights += 1 end end",
        "return string.format('brightness=%.2f ambient=%d,%d,%d bloom=%.2f saturation=%.2f atmosphere=%.2f lights=%d', l.Brightness, l.Ambient.R*255, l.Ambient.G*255, l.Ambient.B*255, bloom and bloom.Intensity or -1, cc and cc.Saturation or -1, atmo and atmo.Density or -1, lights)",
      ].join("\n"))
    )
  );

  console.log("\n== overlapping props ==");
  console.log(
    textOf(
      await edit([
        "local world = workspace:FindFirstChild('MineWorld')",
        "if not world then return 'no world' end",
        "local parts = {}",
        "for _, inst in ipairs(world:GetDescendants()) do",
        "  if inst:IsA('BasePart') and inst.Transparency < 0.9 and inst.Size.Magnitude > 1 then",
        "    local model = inst:FindFirstAncestorOfClass('Model')",
        "    local mname = model and model.Name or ''",
        "    if not mname:match('^Hero_') and not mname:match('^Ore_') and not inst:FindFirstAncestor('Stations') then",
        "      parts[#parts + 1] = inst",
        "    end",
        "  end",
        "end",
        "local reports = {}",
        "for i = 1, #parts do",
        "  local a = parts[i]",
        "  local ca, sa = a.CFrame, a.Size",
        "  for j = i + 1, #parts do",
        "    local b = parts[j]",
        "    if a.Name ~= b.Name then",
        "      local cb, sb = b.CFrame, b.Size",
        "      local delta = ca:PointToObjectSpace(cb.Position)",
        "      local depthX = (sa.X + sb.X) / 2 - math.abs(delta.X)",
        "      local depthY = (sa.Y + sb.Y) / 2 - math.abs(delta.Y)",
        "      local depthZ = (sa.Z + sb.Z) / 2 - math.abs(delta.Z)",
        "      if depthX > 0.5 and depthY > 0.5 and depthZ > 0.5 then",
        "        local volume = depthX * depthY * depthZ",
        "        if volume > 1.2 then",
        "          reports[#reports + 1] = { volume = volume, text = a.Name .. ' x ' .. b.Name .. ' @ ' .. tostring(a.Position) }\n        end",
        "      end",
        "    end",
        "  end",
        "end",
        "table.sort(reports, function(x, y) return x.volume > y.volume end)",
        "local out = { 'overlaps=' .. #reports }",
        "for i = 1, math.min(#reports, 10) do out[#out + 1] = string.format('%.1f  %s', reports[i].volume, reports[i].text) end",
        "return table.concat(out, ' | ')",
      ].join("\n"))
    )
  );

  console.log("\n== board clearance + hub detail ==");
  console.log(
    textOf(
      await edit([
        "local world = workspace:FindFirstChild('MineWorld')",
        "if not world then return 'no world' end",
        "local board = world:FindFirstChild('LeaderboardBoard', true)",
        "if not board then return 'LeaderboardBoard MISSING' end",
        "local hits = {}",
        "for _, part in ipairs(world:GetDescendants()) do",
        "  if part:IsA('BasePart') and part ~= board and part.Transparency < 0.95 then",
        "    local delta = board.CFrame:PointToObjectSpace(part.Position)",
        "    local depth = (board.Size + part.Size) / 2 - Vector3.new(math.abs(delta.X), math.abs(delta.Y), math.abs(delta.Z))",
        "    if depth.X > 0.4 and depth.Y > 0.4 and depth.Z > 0.4 then",
        "      hits[#hits + 1] = part.Name .. '@' .. string.format('%.1f', depth.X * depth.Y * depth.Z)",
        "    end",
        "  end",
        "end",
        "local rich, gems = 0, 0",
        "for _, model in ipairs(world:GetDescendants()) do",
        "  if model:IsA('Model') and model.Name:match('^Ore_') then",
        "    if model:GetAttribute('Rich') then rich += 1 end",
        "    if model:GetAttribute('GemNode') then gems += 1 end",
        "  end",
        "end",
        "local tally = {}",
        "for _, d in ipairs(world:GetDescendants()) do",
        "  local n = d.Name",
        "  if n == 'Paving' or n == 'Planter' or n == 'Bench' or n == 'Awning' or n == 'Crate' or n == 'Barrel' or n == 'Window' or n == 'BrazierFlame' then",
        "    tally[n] = (tally[n] or 0) + 1",
        "  end",
        "end",
        "local names = { 'Paving', 'Planter', 'Bench', 'Awning', 'Crate', 'Barrel', 'Window', 'BrazierFlame' }",
        "local out = {}",
        "for _, n in ipairs(names) do out[#out + 1] = n .. '=' .. tostring(tally[n] or 0) end",
        "local hub = world:FindFirstChild('Hub')",
        "return string.format('boardHits=%d [%s] richNodes=%d gemNodes=%d %s hubParts=%d', #hits, table.concat(hits, '; '), rich, gems, table.concat(out, ' '), hub and #hub:GetChildren() or 0)",
      ].join("\n")),
    ),
  );

  console.log("\n== animations ==");
  console.log(
    textOf(
      await edit([
        "local world = workspace:FindFirstChild('MineWorld')",
        "local plane = world and world:FindFirstChild('PortalPlane', true)",
        "if not plane then return 'portal plane missing' end",
        "local before = plane.Transparency",
        "task.wait(1.4)",
        "local after = plane.Transparency",
        "local pad = world:FindFirstChild('Zones') and world.Zones:FindFirstChild('Zone_1') and world.Zones.Zone_1:FindFirstChild('Pad_1')",
        "local padBefore = pad and pad.Transparency or -1",
        "task.wait(1.2)",
        "local padAfter = pad and pad.Transparency or -1",
        "return string.format('portal %.2f -> %.2f  pad %.2f -> %.2f', before, after, padBefore, padAfter)",
      ].join("\n"))
    )
  );

  console.log("\n== ambient motion ==");
  console.log(
    textOf(
      await edit([
        "local world = workspace:FindFirstChild('MineWorld')",
        "local ring = world and world:FindFirstChild('BeaconRing', true)",
        "local lock = world and world:FindFirstChild('Lock', true)",
        "if not ring then return 'missing ring' end",
        "local a = ring.CFrame.LookVector",
        "local la = lock and lock.Transparency or -1",
        "task.wait(1.3)",
        "local b = ring.CFrame.LookVector",
        "local lb = lock and lock.Transparency or -1",
        "return string.format('ringSpin=%s  lockGlow %.2f -> %.2f', tostring((a - b).Magnitude > 0.0005), la, lb)",
      ].join("\n"))
    )
  );

  console.log("\n== ui icons + hub checks ==");
  console.log(
    textOf(
      await client([
        "local world = workspace:FindFirstChild('MineWorld')",
        "local hub = world and world:FindFirstChild('Hub')",
        "local windows = 0",
        "for _, p in ipairs(hub:GetChildren()) do",
        "  if p:IsA('BasePart') and math.abs(p.Position.Z + 10.54) < 0.1 and p.Size.X == 8 and p.Size.Y == 11 then windows += 1 end",
        "end",
        "local orb = hub:FindFirstChild('FountainOrb')",
        "local low = orb and orb.Position.Y - orb.Size.Y / 2 or -1",
        "local gui = game.Players:GetPlayers()[1] and game.Players:GetPlayers()[1].PlayerGui:FindFirstChild('AnimeMinerUI')",
        "local open = gui and gui:FindFirstChild('OpenMenuButton')",
        "local panel = gui and gui:FindFirstChild('MenuPanel')",
        "local close = panel and panel:FindFirstChild('CloseButton', true)",
        "local icon = open and open:FindFirstChild('Icon')",
        "return string.format('guildWindows=%d orbBottom=%.2f openIconBars=%d openTextLen=%d closeIcon=%s', windows, low, icon and #icon:GetChildren() or 0, open and #open.Text or -1, tostring(close ~= nil and close:FindFirstChild('Icon') ~= nil))",
      ].join("\n"))
    )
  );

  console.log("\n== hero rig detail ==");
  console.log(
    textOf(
      await edit([
        "local world = workspace:FindFirstChild('MineWorld')",
        "local zones = world and world:FindFirstChild('Zones')",
        "local out = {}",
        "if zones then",
        "  for _, folder in ipairs(zones:GetChildren()) do",
        "    local heroes = folder:FindFirstChild('Heroes')",
        "    if heroes and #heroes:GetChildren() > 0 then",
        "      for _, rig in ipairs(heroes:GetChildren()) do",
        "        table.insert(out, folder.Name .. ':' .. rig.Name .. ' parts=' .. #rig:GetDescendants() .. ' pos=' .. tostring(math.floor(rig:GetPivot().Position.X)) .. ',' .. tostring(math.floor(rig:GetPivot().Position.Y)) .. ',' .. tostring(math.floor(rig:GetPivot().Position.Z)))",
        "      end",
        "    end",
        "  end",
        "end",
        "return #out > 0 and table.concat(out, ' | ') or 'NO HERO RIGS'",
      ].join("\n"))
    )
  );

  console.log("\n== UI close button ==");
  console.log(
    textOf(
      await client([
        "local players = game:GetService('Players'):GetPlayers()",
        "if #players == 0 then return 'no players' end",
        "local screen = players[1].PlayerGui:FindFirstChild('AnimeMinerUI')",
        "if not screen then return 'UI MISSING' end",
        "local panel = screen:FindFirstChild('MenuPanel', true)",
        "local closeBtn = screen:FindFirstChild('CloseButton', true)",
        "local openBtn = screen:FindFirstChild('OpenMenuButton', true)",
        "if not panel or not closeBtn or not openBtn then return 'menu controls missing' end",
        "local before = panel.Visible",
        "local pos = closeBtn.AbsolutePosition + closeBtn.AbsoluteSize * 0.5",
        "local okVim, vim = pcall(function() return game:GetService('VirtualInputManager') end)",
        "local clicked = okVim and 'no-service' or 'service-blocked:' .. tostring(vim)",
        "if okVim and vim then",
        "  local ok, err = pcall(function()",
        "    vim:SendMouseButtonEvent(math.floor(pos.X), math.floor(pos.Y), 0, true, nil, Enum.UserInputType.MouseButton1)",
        "    vim:SendMouseButtonEvent(math.floor(pos.X), math.floor(pos.Y), 0, false, nil, Enum.UserInputType.MouseButton1)",
        "  end)",
        "  clicked = ok and 'sent' or ('failed:' .. tostring(err))",
        "  task.wait(0.5)",
        "end",
        "local afterClose = panel.Visible",
        "local reopenShown = openBtn.Visible",
        "local menuControl = screen:FindFirstChild('MenuControl')",
        "if menuControl then",
        "  menuControl:Fire(false)",
        "  task.wait(0.3)",
        "  afterClose = panel.Visible",
        "  reopenShown = openBtn.Visible",
        "  menuControl:Fire(true)",
        "  task.wait(0.3)",
        "end",
        "return string.format('menuBefore=%s click=%s afterClose=%s reopenBtnShown=%s afterReopen=%s closeBtn=%s', tostring(before), tostring(clicked), tostring(afterClose), tostring(reopenShown), tostring(panel.Visible), tostring(closeBtn ~= nil))",
      ].join("\n"))
    )
  );

  console.log("\n== shop + quests ==");
  console.log(textOf(await client([
    "local players = game:GetService('Players'):GetPlayers()",
    "if #players == 0 then return 'no players' end",
    "local screen = players[1].PlayerGui:FindFirstChild('AnimeMinerUI')",
    "local function gems()",
    "  for _, d in ipairs(screen:GetDescendants()) do",
    "    if d:IsA('TextLabel') and d.Text:match('^%d+ gems$') then return tonumber(d.Text:match('^%d+')) end",
    "  end",
    "  return -1",
    "end",
    "local remotes = game:GetService('ReplicatedStorage'):FindFirstChild('Remotes')",
    "local before = gems()",
    "remotes.Action:FireServer('ClaimQuest', { id = 'mine50' })",
    "task.wait(1.6)",
    "local afterClaim = gems()",
    "remotes.Action:FireServer('BuyBoost', { id = 'coin' })",
    "task.wait(1.8)",
    "local afterBoost = gems()",
    "local chip = false",
    "for _, d in ipairs(screen:GetDescendants()) do",
    "  if d:IsA('TextLabel') and d.Text == 'Coin Surge' then chip = true end",
    "end",
    "return string.format('gemsBefore=%d afterQuestClaim=%d afterBoostPurchase=%d boostChip=%s', before, afterClaim, afterBoost, tostring(chip))",
  ].join("\n"))));

  console.log("\n== tutorial + forge ==");
  console.log(textOf(await client([
    "local players = game:GetService('Players'):GetPlayers()",
    "if #players == 0 then return 'no players' end",
    "local screen = players[1].PlayerGui:FindFirstChild('AnimeMinerUI')",
    "local remotes = game:GetService('ReplicatedStorage'):FindFirstChild('Remotes')",
    "local function find(pattern)",
    "  for _, d in ipairs(screen:GetDescendants()) do",
    "    if d:IsA('TextLabel') and d.Text:match(pattern) then return d.Text end",
    "  end",
    "  return 'none'",
    "end",
    "local function coins()",
    "  local t = find('^%d+ coins$')",
    "  return tonumber(t:match('^%d+')) or -1",
    "end",
    "local beforeStep = find('^GUIDED TOUR') ~= 'none' and 'GUIDED TOUR' or find('^TUTORIAL')",
    "remotes.Action:FireServer('TutorialStart')",
    "task.wait(1.4)",
    "local startedStep = find('^TUTORIAL')",
    "remotes.Action:FireServer('TutorialNext')",
    "task.wait(1.4)",
    "local afterStep = find('^TUTORIAL') ",
    "local beforeForge = coins()",
    "remotes.Action:FireServer('UpgradePickaxe')",
    "task.wait(1.8)",
    "local afterForge = coins()",
    "return string.format('tutorialBefore=[%s] afterStart=[%s] afterNext=[%s] coinsBeforeForge=%d coinsAfterForge=%d', beforeStep, startedStep, afterStep, beforeForge, afterForge)",
  ].join("\n"))));

  console.log("\n== tab audit ==");
  console.log(textOf(await client([
    "local players = game:GetService('Players'):GetPlayers()",
    "if #players == 0 then return 'no players' end",
    "local screen = players[1].PlayerGui:FindFirstChild('AnimeMinerUI')",
    "local tabs = screen and screen:FindFirstChild('TabControl')",
    "local menu = screen and screen:FindFirstChild('MenuControl')",
    "if not tabs then return 'no TabControl' end",
    "if menu then menu:Fire(true) end",
    "task.wait(0.4)",
    "local scroll = screen:FindFirstChild('ContentScroll', true)",
    "local out = {}",
    "for _, name in ipairs({'Summon','Crew','Pets','Research','Rebirth','Shop','Quests','Index','Weather','Trade','Guide'}) do",
    "  local ok, result = pcall(function() return tabs:Invoke(name) end)",
    "  task.wait(0.08)",
    "  local labels, clipped = 0, 0",
    "  if scroll then",
    "    for _, d in ipairs(scroll:GetDescendants()) do",
    "      if d:IsA('TextLabel') and d.Visible and #d.Text > 0 then",
    "        labels += 1",
    "        if d.AbsoluteSize.Y < 6 then clipped += 1 end",
    "      end",
    "    end",
    "  end",
    "  out[#out + 1] = name .. ':' .. tostring(ok and result) .. ' labels=' .. labels .. ' clipped=' .. clipped",
    "end",
    "if menu then menu:Fire(false) end",
    "return table.concat(out, ' | ')",
  ].join("\n"))));

  console.log("\n== panel collapse ==");
  console.log(textOf(await client([
    "local players = game:GetService('Players')",
    "local gui = players.LocalPlayer.PlayerGui:FindFirstChild('AnimeMinerUI')",
    "if not gui then return 'UI MISSING' end",
    "local menu = gui:FindFirstChild('MenuControl')",
    "local collapse = gui:FindFirstChild('CollapseControl')",
    "if menu then menu:Fire(true) end",
    "task.wait(0.5)",
    "if not collapse then return 'collapse control missing' end",
    "local panel = gui:FindFirstChild('MenuPanel', true)",
    "collapse:Invoke(true)",
    "task.wait(0.45)",
    "local smallH = panel and panel.Size.Y.Offset or 0",
    "local smallFlags = collapse:Invoke(true)",
    "collapse:Invoke(false)",
    "task.wait(0.45)",
    "local bigH = panel and panel.Size.Y.Offset or 0",
    "local bigFlags = collapse:Invoke(false)",
    "local loading = players.LocalPlayer.PlayerGui:FindFirstChild('AnimeMinerLoading')",
    "local shimmer = loading and loading:FindFirstChild('Shimmer', true)",
    "if menu then menu:Fire(false) end",
    "return string.format('collapsedH=%.0f flags=[%s] expandedH=%.0f flags=[%s] shimmer=%s', smallH, smallFlags, bigH, bigFlags, tostring(shimmer ~= nil))",
  ].join("\n"))));

  console.log("\n== rebirth ==");
  console.log(textOf(await edit([
    "local ProgressService = require(game.ServerScriptService.ProgressService)",
    "local Config = require(game.ReplicatedStorage.GameConfig)",
    "local fresh = { coins = 1200, pickaxe = 6, zone = 4, rebirths = 0, research = { power1 = true }, claimed = { mine50 = true }, stats = { blocksMined = 400, coinsEarned = 5000 } }",
    "local lowOk, lowMsg = ProgressService.Rebirth(fresh)",
    "local ready = { coins = 9000, pickaxe = 8, zone = 5, rebirths = 2, research = { power1 = true, zone2 = true }, claimed = { mine50 = true }, stats = { blocksMined = Config.BlocksForLevel(Config.Rebirth.levelReq) + 500, coinsEarned = 40000 } }",
    "local before = ProgressService.RebirthInfo(ready)",
    "local ok, msg = ProgressService.Rebirth(ready)",
    "local after = ProgressService.RebirthInfo(ready)",
    "local combined = ProgressService.Combined(ready)",
    "local kept = 0",
    "for _ in pairs(ready.research) do kept += 1 end",
    "return string.format('blocked=%s msg=[%s] | before lv=%d/%d ratio=%.2f can=%s x%.2f | ok=%s [%s] | after count=%d lv=%d coins=%d pickaxe=%d research=%d zone=%d claimKept=%s x%.2f combinedCoin=%.2f', tostring(lowOk), lowMsg, before.level, before.levelReq, before.ratio, tostring(before.canRebirth), before.coinMult, tostring(ok), msg, after.count, after.level, ready.coins, ready.pickaxe, kept, ready.zone, tostring(ready.claimed.mine50), after.coinMult, combined.coin)",
  ].join("\n"))));
  console.log(textOf(await client([
    "local players = game:GetService('Players')",
    "local gui = players.LocalPlayer.PlayerGui:FindFirstChild('AnimeMinerUI')",
    "if not gui then return 'UI MISSING' end",
    "local menu = gui:FindFirstChild('MenuControl')",
    "local tabs = gui:FindFirstChild('TabControl')",
    "if menu then menu:Fire(true) end",
    "if tabs then tabs:Invoke('Rebirth') end",
    "task.wait(0.8)",
    "local body = gui:FindFirstChild('ContentScroll', true)",
    "local labels, clipped = 0, 0",
    "local txt = {}",
    "for _, d in ipairs(body:GetDescendants()) do",
    "  if d:IsA('TextLabel') and d.Visible and #d.Text > 0 then",
    "    labels += 1",
    "    if d.AbsoluteSize.Y < 6 then clipped += 1 end",
    "    local t = d.Text",
    "    if t:match('REBIRTH') or t:match('^Miner Lv') or t:match('^COINS') or t:match('^RESETS') or t:match('^KEEPS') then txt[#txt + 1] = t:sub(1, 24) end",
    "  end",
    "end",
    "local tab = gui:FindFirstChild('Tab_Rebirth', true)",
    "local closeBtn = nil",
    "for _, d in ipairs(gui:GetDescendants()) do if d:IsA('TextButton') and d.Text:match('CLOSE') then closeBtn = d end end",
    "local gap = -1",
    "if tab and closeBtn then gap = math.floor(closeBtn.AbsolutePosition.Y - (tab.AbsolutePosition.Y + tab.AbsoluteSize.Y)) end",
    "if menu then menu:Fire(false) end",
    "return string.format('tab=%s labels=%d clipped=%d gapToClose=%dpx [%s]', tostring(tab ~= nil), labels, clipped, gap, table.concat(txt, ' ; '))",
  ].join("\n"))));

  console.log("\n== admin + zone labels ==");
  console.log(textOf(await client([
    "local players = game:GetService('Players'):GetPlayers()",
    "if #players == 0 then return 'no players' end",
    "local screen = players[1].PlayerGui:FindFirstChild('AnimeMinerUI')",
    "local adminBtn = screen and screen:FindFirstChild('AdminButton', true)",
    "local world = workspace:FindFirstChild('MineWorld')",
    "local zones = world and world:FindFirstChild('Zones')",
    "local shown = {}",
    "if zones then",
    "  for _, folder in ipairs(zones:GetChildren()) do",
    "    local signPart = folder:FindFirstChild('ZoneSign')",
    "    local gui = signPart and signPart:FindFirstChild('Sign')",
    "    if gui and gui:IsA('BillboardGui') and gui.Enabled then shown[#shown + 1] = folder.Name end",
    "  end",
    "end",
    "local gates = 0",
    "local portal = world and world:FindFirstChild('Portal')",
    "if portal then gates = #portal:GetChildren() end",
    "local returnGates = 0",
    "for _, d in ipairs(workspace:GetDescendants()) do",
    "  if d:IsA('Model') and d.Name == 'ReturnGate' then",
    "    returnGates += 1",
    "    if not d:FindFirstChild('PortalPlane', true) then returnGates -= 1 end",
    "  end",
    "end",
    "local npcs, npcWithClicks = 0, 0",
    "for _, d in ipairs(workspace:GetDescendants()) do",
    "  if d:IsA('Model') and d.Name:match('^Npc_') then",
    "    npcs += 1",
    "    if d:FindFirstChildOfClass('ClickDetector') or d:FindFirstChild('NpcRoot', true) then npcWithClicks += 1 end",
    "  end",
    "end",
    "local guildHall = world and world:FindFirstChild('GuildHall', true)",
    "local marketHall = world and world:FindFirstChild('Market', true)",
    "local loading = players[1].PlayerGui:FindFirstChild('AnimeMinerLoading')",
    "local playBtn = loading and loading:FindFirstChild('PlayButton', true)",
    "local loadingStatus = loading and loading:FindFirstChild('Root', true)",
    "local dialogPanel = screen and screen:FindFirstChild('DialoguePanel', true)",
    "local board = world and world:FindFirstChild('LeaderboardBoard', true)",
    "local boardGui = board and board:FindFirstChildOfClass('SurfaceGui')",
    "local boardRows = 0",
    "if boardGui then",
    "  for _, d in ipairs(boardGui:GetDescendants()) do",
    "    if d:IsA('TextLabel') and d.Text:match('^#%d+$') then boardRows += 1 end",
    "  end",
    "end",
    "local seer = 0",
    "for _, d in ipairs(workspace:GetDescendants()) do",
    "  if d:IsA('Model') and d.Name == 'Npc_seer' then seer += 1 end",
    "end",
    "local shrine = world and world:FindFirstChild('TraitShrine', true)",
    "return 'adminBtn=' .. tostring(adminBtn and adminBtn.Visible) .. ' gates=' .. gates .. ' returnGates=' .. returnGates .. ' npcs=' .. npcs .. ' guild=' .. tostring(guildHall ~= nil) .. ' market=' .. tostring(marketHall ~= nil) .. ' loading=' .. tostring(loading ~= nil and loading.Enabled) .. ' playBtn=' .. tostring(playBtn ~= nil and playBtn.Visible) .. ' dialogue=' .. tostring(dialogPanel ~= nil) .. ' board=' .. tostring(boardGui ~= nil) .. ' boardRows=' .. boardRows .. ' seer=' .. seer .. ' shrine=' .. tostring(shrine ~= nil) .. ' zoneSignsOn=[' .. table.concat(shown, ',') .. ']'",
  ].join("\n"))));

  console.log("\n== pets ==");
  console.log(
    textOf(
      await edit([
        "local PetService = require(game.ServerScriptService.PetService)",
        "local profile = { pets = {",
        "  { id = 'hikari', level = 12, equipped = true },",
        "  { id = 'orochi', level = 12, equipped = true },",
        "  { id = 'tsuki', level = 12, equipped = true },",
        "  { id = 'mochi', level = 12, equipped = false },",
        "} }",
        "local bonuses = PetService.Bonuses(profile)",
        "local solo = PetService.Bonuses({ pets = { { id = 'hikari', level = 1, equipped = true } } })",
        "return string.format('petCap coin=%.2f gem=%.2f · soloHikari coin=%.2f gem=%.2f', bonuses.coin, bonuses.gem, solo.coin, solo.gem)",
      ].join("\n")),
    ),
  );
  console.log(
    textOf(
      await client([
        "local Remotes = game:GetService('ReplicatedStorage'):WaitForChild('Remotes')",
        "local Action = Remotes:WaitForChild('Action')",
        "Action:FireServer('AdminGrant', { kind = 'gems', amount = 3000 })",
        "task.wait(1.2)",
        "for _ = 1, 4 do",
        "  Action:FireServer('HatchPet')",
        "  task.wait(0.7)",
        "end",
        "task.wait(1.5)",
        "return 'hatchRequests=4'",
      ].join("\n")),
    ),
  );
  console.log(
    textOf(
      await client([
        "local players = game:GetService('Players')",
        "local gui = players.LocalPlayer.PlayerGui:FindFirstChild('AnimeMinerUI')",
        "local menu = gui and gui:FindFirstChild('MenuControl')",
        "local tabs = gui and gui:FindFirstChild('TabControl')",
        "if menu then menu:Fire(true) end",
        "if tabs then tabs:Invoke('Pets') end",
        "task.wait(0.9)",
        "local labels, clipped = 0, 0",
        "local clippedNames = {}",
        "for _, label in ipairs(gui:GetDescendants()) do",
        "  if label:IsA('TextLabel') and label.Visible and label.Text ~= '' then",
        "    labels += 1",
        "    if label.TextBounds.X > label.AbsoluteSize.X + 1 and not label.TextWrapped then",
        "      clipped += 1",
        "      table.insert(clippedNames, label.Text:sub(1, 18) .. '@' .. tostring(math.floor(label.TextBounds.X - label.AbsoluteSize.X)))",
        "    end",
        "  end",
        "end",
        "local buttons, felt = 0, 0",
        "for _, b in ipairs(gui:GetDescendants()) do",
        "  if b:IsA('TextButton') then",
        "    buttons += 1",
        "    if b:GetAttribute('FlatFeel') and b.AutoButtonColor == false then felt += 1 end",
        "  end",
        "end",
        "local folder = workspace:FindFirstChild('LocalPets')",
        "local models, parts, moved = 0, 0, 0",
        "if folder then",
        "  for _, model in ipairs(folder:GetChildren()) do",
        "    models += 1",
        "    parts += #model:GetChildren()",
        "    local first = model:GetPivot().Position",
        "    task.wait(0.3)",
        "    if (model:GetPivot().Position - first).Magnitude > 0.01 then moved += 1 end",
        "  end",
        "end",
        "local humanoid = players.LocalPlayer.Character and players.LocalPlayer.Character:FindFirstChildOfClass('Humanoid')",
        "local canvas = gui and gui:FindFirstChild('Canvas')",
        "local uiScale = canvas and canvas:FindFirstChildOfClass('UIScale')",
        "local size = canvas and canvas.AbsoluteSize or Vector2.new(0, 0)",
        "local vp = workspace.CurrentCamera.ViewportSize",
        "return string.format('petTabLabels=%d clipped=%d names=[%s] petModels=%d petParts=%d animating=%d walkSpeed=%s uiScale=%.2f canvas=%.0fx%.0f vp=%.0fx%.0f fits=%s feel=%d/%d', labels, clipped, table.concat(clippedNames, '; '), models, parts, moved, tostring(humanoid and humanoid.WalkSpeed), uiScale and uiScale.Scale or 0, size.X, size.Y, vp.X, vp.Y, tostring(size.X <= vp.X + 1 and size.Y <= vp.Y + 1 and uiScale ~= nil), felt, buttons)",
      ].join("\n")),
    ),
  );

  console.log("\n== settings + hud density ==");
  console.log(
    textOf(
      await client([
        "local players = game:GetService('Players')",
        "local gui = players.LocalPlayer.PlayerGui:FindFirstChild('AnimeMinerUI')",
        "local menu = gui and gui:FindFirstChild('MenuControl')",
        "if menu then menu:Fire(false) end",
        "local control = gui and gui:FindFirstChild('SettingsControl')",
        "if not control then return 'settings control missing' end",
        "task.wait(0.3)",
        "local low = control:Invoke('quality', 'low')",
        "task.wait(0.3)",
        "local high = control:Invoke('quality', 'high')",
        "task.wait(0.2)",
        "local card = gui:FindFirstChild('ProfileCard', true)",
        "local bar = gui:FindFirstChild('TopBar', true)",
        "control:Invoke('hud', false)",
        "task.wait(0.2)",
        "local off = tostring(card.Visible) .. '/' .. tostring(bar.Visible)",
        "control:Invoke('hud', true)",
        "task.wait(0.2)",
        "local on = tostring(card.Visible) .. '/' .. tostring(bar.Visible)",
        "local toggle = gui:FindFirstChild('HudToggle', true)",
        "local label = toggle and toggle.Text or '?'",
        "control:Invoke('hud', false)",
        "local root = players.LocalPlayer.Character and players.LocalPlayer.Character:FindFirstChild('HumanoidRootPart')",
        "local folder = workspace:FindFirstChild('LocalPets')",
        "local rigs, behind = 0, 0",
        "if folder then",
        "  for _, model in ipairs(folder:GetChildren()) do",
        "    rigs += 1",
        "    if root and (model:GetPivot().Position - root.Position):Dot(root.CFrame.LookVector) < 0 then behind += 1 end",
        "  end",
        "end",
        "control:Invoke('pets', false)",
        "task.wait(0.35)",
        "local hiddenRigs = folder and #folder:GetChildren() or -1",
        "control:Invoke('pets', true)",
        "task.wait(0.7)",
        "local shownRigs = folder and #folder:GetChildren() or -1",
        "local loading = players.LocalPlayer.PlayerGui:FindFirstChild('AnimeMinerLoading')",
        "local startCard = loading and loading:FindFirstChild('StartCard', true)",
        "local startPanel = loading and loading:FindFirstChild('SettingsPanel', true)",
        "local startScale = startCard and startCard:FindFirstChildOfClass('UIScale')",
        "local centerOffset = -1",
        "local startRoot = loading and loading:FindFirstChild('Root', true)",
        "local rootSize = startRoot and startRoot.AbsoluteSize or Vector2.new()",
        "local screenSize = loading and loading.AbsoluteSize or Vector2.new()",
        "if startCard then",
        "  local center = startCard.AbsolutePosition + startCard.AbsoluteSize / 2",
        "  -- compare against the screen area the start GUI actually occupies",
        "  centerOffset = math.floor((center - screenSize / 2).Magnitude)",
        "end",
        "local admin = gui:FindFirstChild('AdminControl')",
        "local adminState = admin and admin:Invoke('open')",
        "local adminPanel = gui:FindFirstChild('AdminPanel', true)",
        "local confirm = adminPanel and adminPanel:FindFirstChild('ResetConfirm', true)",
        "local wipe = false",
        "if confirm then",
        "  for _, d in ipairs(confirm:GetDescendants()) do",
        "    if d:IsA('TextButton') and d.Text:match('WIPE') then wipe = true end",
        "  end",
        "end",
        "local resetStatus = adminPanel and adminPanel:FindFirstChild('ResetStatus', true)",
        "if admin then admin:Invoke('close') end",
        "return string.format('low=[%s] high=[%s] hudOff=%s hudOn=%s toggle=[%s] petRigs=%d behind=%d hiddenRigs=%d shownRigs=%d startCard=%.0fx%.0f startScale=%.2f centerOff=%dpx rect=%.0f,%.0f root=%.0fx%.0f screen=%.0fx%.0f startPanel=%s admin=%s confirm=%s wipe=%s status=%s', low, high, off, on, label, rigs, behind, hiddenRigs, shownRigs, startCard and startCard.AbsoluteSize.X or 0, startCard and startCard.AbsoluteSize.Y or 0, startScale and startScale.Scale or 0, centerOffset, startCard and startCard.AbsolutePosition.X or 0, startCard and startCard.AbsolutePosition.Y or 0, rootSize.X, rootSize.Y, screenSize.X, screenSize.Y, tostring(startPanel ~= nil), tostring(adminState), tostring(confirm ~= nil), tostring(wipe), tostring(resetStatus ~= nil))",
      ].join("\n")),
    ),
  );

  console.log("\n== portal walk-through ==");
  console.log(
    textOf(
      await edit([
        "local Players = game:GetService('Players')",
        "local player = Players:GetPlayers()[1]",
        "local world = workspace:FindFirstChild('MineWorld')",
        "local portal = world and world:FindFirstChild('Portal')",
        "local gate = portal and portal:FindFirstChild('Gate_1')",
        "local plane = gate and gate:FindFirstChild('PortalPlane')",
        "local character = player and player.Character",
        "local root = character and character:FindFirstChild('HumanoidRootPart')",
        "if not (plane and root) then return 'portalWalk=no plane or root' end",
        "root.CFrame = CFrame.new(0, 40, 140)",
        "task.wait(0.4)",
        "root.CFrame = plane.CFrame",
        "task.wait(1.4)",
        "local pad = world:FindFirstChild('Pad_1', true)",
        "local dist = pad and math.floor((pad.Position - root.Position).Magnitude) or -1",
        "return string.format('zone=%s padDist=%d', tostring(player:GetAttribute('Zone')), dist)",
      ].join("\n")),
    ),
  );

  console.log("\n== ui contrast ==");
  console.log(textOf(await client([
    "local players = game:GetService('Players'):GetPlayers()",
    "if #players == 0 then return 'no players' end",
    "local gui = players[1].PlayerGui:FindFirstChild('AnimeMinerUI')",
    "if not gui then return 'UI MISSING' end",
    "-- sample the open menu: that is the surface players read most",
    "local menu = gui:FindFirstChild('MenuControl')",
    "if menu then menu:Fire(true) end",
    "task.wait(0.9)",
    "local panel = gui:FindFirstChild('MenuPanel', true)",
    "local side = panel and panel:FindFirstChildOfClass('Frame')",
    "local function ch(v) v = v / 255 if v <= 0.03928 then return v / 12.92 end return ((v + 0.055) / 1.055) ^ 2.4 end",
    "local function lum(c) return 0.2126 * ch(c.R * 255) + 0.7152 * ch(c.G * 255) + 0.0722 * ch(c.B * 255) end",
    "local function ratio(a, b) local x, y = lum(a), lum(b) if x < y then x, y = y, x end return (x + 0.05) / (y + 0.05) end",
    "local total, low, worst = 0, 0, 99",
    "local samples = {}",
    "for _, d in ipairs(gui:GetDescendants()) do",
    "  if d:IsA('TextLabel') and d.Visible and d.TextTransparency < 0.35 and #d.Text > 0 then",
    "    local bg = nil",
    "    local node = d.Parent",
    "    while node and node ~= gui do",
    "      if node:IsA('GuiObject') and node.BackgroundTransparency < 0.85 then bg = node.BackgroundColor3 break end",
    "      node = node.Parent",
    "    end",
    "    if bg then",
    "      local r = ratio(d.TextColor3, bg)",
    "      total += 1",
    "      if r < worst then worst = r end",
    "      if r < 3 then low += 1 end",
    "      if #samples < 4 and r < 3.2 then samples[#samples + 1] = d.Text:sub(1, 20) .. '=' .. string.format('%.1f', r) end",
    "    end",
    "  end",
    "end",
    "local panelColor = panel and panel.BackgroundColor3 or Color3.new()",
    "local sideColor = side and side.BackgroundColor3 or Color3.new()",
    "return string.format('labels=%d below3to1=%d worst=%.2f panel=%d,%d,%d sidebar=%d,%d,%d [%s]', total, low, worst, panelColor.R * 255, panelColor.G * 255, panelColor.B * 255, sideColor.R * 255, sideColor.G * 255, sideColor.B * 255, table.concat(samples, ' ; '))",
  ].join("\n"))));

  console.log("\n== client roll (FireServer) ==");
  console.log(textOf(await client([
    "local remotes = game:GetService('ReplicatedStorage'):FindFirstChild('Remotes')",
    "if not remotes then return 'no remotes' end",
    "remotes.Action:FireServer('Roll', { count = 1 })",
    "return 'roll fired'",
  ].join("\n"))));
  await sleep(2500);

  console.log("\n== HUD text ==");
  console.log(textOf(await client([
    "local players = game:GetService('Players'):GetPlayers()",
    "if #players == 0 then return 'no players' end",
    "local screen = players[1]:FindFirstChild('PlayerGui') and players[1].PlayerGui:FindFirstChild('AnimeMinerUI')",
    "if not screen then return 'UI MISSING' end",
    "local coin, crew, dps, zone, weather, boost",
    "for _, d in ipairs(screen:GetDescendants()) do",
    "  if d:IsA('TextLabel') then",
    "    local t = d.Text",
    "    if t:match('^%d+ coins$') then coin = t end",
    "    if t:match('^Crew %d+/%d+') then crew = t end",
    "    if t:match('DPS') then dps = t end",
    "    if t:match('Luck x') then weather = t end",
    "    if t:match('ACTIVE') then boost = t end",
    "  end",
    "end",
    "return string.format('coins=[%s] crew=[%s] dps=[%s] luck=[%s] boost=[%s] descendants=%d', tostring(coin), tostring(crew), tostring(dps), tostring(weather), tostring(boost), #screen:GetDescendants())",
  ].join("\n"))));

  console.log("\n== console output (tail) ==");
  const logs = textOf(await tool("get_console_output", { studio_id: STUDIO_ID }));
  console.log(logs.split("\n").slice(-40).join("\n"));

  console.log("\n== performance ==");
  console.log(
    textOf(
      await edit([
        "local stats = game:GetService('Stats')",
        "local RunService = game:GetService('RunService')",
        "local function snapshot()",
        "  local parts, lights, emitters, clicks = 0, 0, 0, 0",
        "  local tally = {}",
        "  for _, d in ipairs(workspace:GetDescendants()) do",
        "    if d:IsA('BasePart') then parts += 1 end",
        "    if d:IsA('PointLight') then lights += 1 end",
        "    if d:IsA('ParticleEmitter') and d.Rate > 0 then emitters += 1 end",
        "    if d:IsA('ClickDetector') then",
        "      clicks += 1",
        "      tally[d.Name] = (tally[d.Name] or 0) + 1",
        "    end",
        "  end",
        "  return #workspace:GetDescendants(), math.floor(stats:GetTotalMemoryUsageMb()), parts, lights, emitters, clicks, tally",
        "end",
        "local function breakdown(t)",
        "  local names = {}",
        "  for name in pairs(t) do table.insert(names, name) end",
        "  table.sort(names)",
        "  local out = {}",
        "  for _, name in ipairs(names) do table.insert(out, name .. '=' .. t[name]) end",
        "  return table.concat(out, ',')",
        "end",
        "local desc0, mem0, p0, l0, e0, c0, t0 = snapshot()",
        "local frames, total = 0, 0",
        "local conn = RunService.Heartbeat:Connect(function(dt) frames += 1 total += dt end)",
        "task.wait(15)",
        "conn:Disconnect()",
        "local desc1, mem1 = snapshot()",
        "return string.format('heartbeat=%.1f/s instances=%d->%d (+%d) memoryMb=%d->%d (+%d) parts=%d lights=%d activeEmitters=%d detectors=%d order=[%s]', frames / math.max(total, 0.001), desc0, desc1, desc1 - desc0, mem0, mem1, mem1 - mem0, p0, l0, e0, c0, breakdown(t0))",
      ].join("\n")),
    ),
  );

  if (process.env.STRESS) {
    console.log("\n== stress: full roster, menu open ==");
    console.log(
      textOf(
        await client([
          "local remotes = game:GetService('ReplicatedStorage'):FindFirstChild('Remotes')",
          "if not remotes then return 'no remotes' end",
          "local action = remotes:FindFirstChild('Action')",
          "action:FireServer('AdminGrant', { kind = 'coins', amount = 5000000 })",
          "action:FireServer('AdminGrant', { kind = 'gems', amount = 5000 })",
          "task.wait(1)",
          "for i = 1, 12 do",
          "  action:FireServer('Roll', { count = 10 })",
          "  task.wait(0.45)",
          "end",
          "task.wait(1)",
          "local gui = game:GetService('Players').LocalPlayer.PlayerGui:FindFirstChild('AnimeMinerUI')",
          "local menu = gui and gui:FindFirstChild('MenuControl')",
          "if menu then menu:Fire(true) end",
          "local tabs = gui and gui:FindFirstChild('TabControl')",
          "if tabs then tabs:Invoke('Crew') end",
          "return 'rolled 120, crew tab open'",
        ].join("\n")),
      ),
    );
    console.log(
      textOf(
        await edit([
          "local stats = game:GetService('Stats')",
          "local RunService = game:GetService('RunService')",
          "local function snapshot()",
          "  return #workspace:GetDescendants(), math.floor(stats:GetTotalMemoryUsageMb())",
          "end",
          "local desc0, mem0 = snapshot()",
          "local frames, total = 0, 0",
          "local conn = RunService.Heartbeat:Connect(function(dt) frames += 1 total += dt end)",
          "task.wait(20)",
          "conn:Disconnect()",
          "local desc1, mem1 = snapshot()",
          "local players = game:GetService('Players'):GetPlayers()",
          "return string.format('heartbeat=%.1f/s instances=%d->%d (+%d) memoryMb=%d->%d (+%d)', frames / math.max(total, 0.001), desc0, desc1, desc1 - desc0, mem0, mem1, mem1 - mem0)",
        ].join("\n")),
      ),
    );
  }

  if (process.env.STRESS) {
    console.log("\n== profile: client with full roster ==");
    console.log(
      textOf(
        await client([
          "local players = game:GetService('Players')",
          "local RunService = game:GetService('RunService')",
          "local remotes = game:GetService('ReplicatedStorage'):FindFirstChild('Remotes')",
          "local stateRemote = remotes and remotes:FindFirstChild('State')",
          "local pushes = 0",
          "local pushConn = stateRemote and stateRemote.OnClientEvent:Connect(function() pushes += 1 end)",
          "local function sample(seconds)",
          "  local frames, total = 0, 0",
          "  local conn = RunService.RenderStepped:Connect(function(dt) frames += 1 total += dt end)",
          "  task.wait(seconds)",
          "  conn:Disconnect()",
          "  return frames / math.max(total, 0.001)",
          "end",
          "local gui = players.LocalPlayer.PlayerGui:FindFirstChild('AnimeMinerUI')",
          "local menu = gui and gui:FindFirstChild('MenuControl')",
          "local closed = sample(8)",
          "local pushesClosed = pushes",
          "if menu then menu:Fire(true) end",
          "local tabs = gui and gui:FindFirstChild('TabControl')",
          "if tabs then tabs:Invoke('Crew') end",
          "local open = sample(8)",
          "local pushesOpen = pushes - pushesClosed",
          "if menu then menu:Fire(false) end",
          "if pushConn then pushConn:Disconnect() end",
          "return string.format('fpsMenuClosed=%.1f fpsCrewOpen=%.1f pushesPerSecClosed=%.1f pushesPerSecOpen=%.1f', closed, open, pushesClosed / 8, pushesOpen / 8)",
        ].join("\n")),
      ),
    );
  }

  console.log("\n== stopping play session ==");
  console.log(textOf(await tool("start_stop_play", { is_start: false, studio_id: STUDIO_ID })));

  child.stdin.end();
  child.kill();
}

main().catch((err) => {
  console.error("playtest error:", err.message);
  process.exit(1);
});
