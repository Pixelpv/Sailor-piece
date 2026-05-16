--[[
╔══════════════════════════════════════════════════════════════════════╗
║         SAILOR PIECE HUB  —  Auto Farm Professional v4.0            ║
║                                                                      ║
║  ARQUITETURA EM MÓDULOS:                                             ║
║  • Core          → serviços, referências, utilidades base            ║
║  • Config        → configurações + save/load JSON                    ║
║  • Cache         → sistema inteligente de cache de mobs              ║
║  • Quest         → detecção e aceitação inteligente de missões       ║
║  • Combat        → sistema de ataque completo + hit aura             ║
║  • Movement      → Smart Tween + voo estável + anti-stuck            ║
║  • AutoStats     → distribuição automática de pontos                 ║
║  • AutoBoss      → detecção e combate contra bosses                  ║
║  • GUI           → HUB moderno com tabs, toggles, sliders            ║
╚══════════════════════════════════════════════════════════════════════╝
--]]

-- ═══════════════════════════════════════════════════════════════════
--  MÓDULO: CORE  —  Serviços, referências globais e utilitários
-- ═══════════════════════════════════════════════════════════════════
local Core = (function()
    local Players           = game:GetService("Players")
    local RunService        = game:GetService("RunService")
    local TweenService      = game:GetService("TweenService")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local StarterGui        = game:GetService("StarterGui")
    local Stats             = game:GetService("Stats")
    local UserInputService  = game:GetService("UserInputService")
    local HttpService       = game:GetService("HttpService")

    local player = Players.LocalPlayer
    local char, humanoid, hrp

    local function refresh()
        char     = player.Character or player.CharacterAdded:Wait()
        humanoid = char:WaitForChild("Humanoid", 10)
        hrp      = char:WaitForChild("HumanoidRootPart", 10)
    end
    refresh()

    local function isAlive()
        local c = player.Character
        if not c then return false end
        local h = c:FindFirstChildOfClass("Humanoid")
        local r = c:FindFirstChild("HumanoidRootPart")
        return h ~= nil and r ~= nil and h.Health > 0
    end

    local function getChar()  return player.Character end
    local function getHum()   return char and char:FindFirstChildOfClass("Humanoid") end
    local function getRoot()  return char and char:FindFirstChild("HumanoidRootPart") end

    local function notify(title, msg, dur)
        pcall(function()
            StarterGui:SetCore("SendNotification", {
                Title = title or "SP HUB", Text = msg or "", Duration = dur or 3
            })
        end)
    end

    local function log(tag, msg)
        print(string.format("[SP HUB][%s] %s", tag, tostring(msg)))
    end

    local function warn_(tag, msg)
        warn(string.format("[SP HUB][%s] %s", tag, tostring(msg)))
    end

    -- Ping em tempo real
    local function getPing()
        return math.floor(Stats.Network.ServerStatsItem["Data Ping"]:GetValue())
    end

    -- FPS em tempo real
    local lastFPSTime = tick()
    local fpsCount    = 0
    local currentFPS  = 60
    RunService.RenderStepped:Connect(function()
        fpsCount += 1
        if tick() - lastFPSTime >= 1 then
            currentFPS  = fpsCount
            fpsCount    = 0
            lastFPSTime = tick()
        end
    end)
    local function getFPS() return currentFPS end

    -- Distância entre dois pontos/partes
    local function dist(a, b)
        if typeof(a) == "Vector3" and typeof(b) == "Vector3" then
            return (a - b).Magnitude
        end
        local ra = (typeof(a) == "Instance") and a:FindFirstChild("HumanoidRootPart")
        local rb = (typeof(b) == "Instance") and b:FindFirstChild("HumanoidRootPart")
        if ra and rb then return (ra.Position - rb.Position).Magnitude end
        return math.huge
    end

    return {
        Players           = Players,
        RunService        = RunService,
        TweenService      = TweenService,
        ReplicatedStorage = ReplicatedStorage,
        StarterGui        = StarterGui,
        HttpService       = HttpService,
        UserInputService  = UserInputService,
        player            = player,
        refresh           = refresh,
        isAlive           = isAlive,
        getChar           = getChar,
        getHum            = getHum,
        getRoot           = getRoot,
        notify            = notify,
        log               = log,
        warn              = warn_,
        getPing           = getPing,
        getFPS            = getFPS,
        dist              = dist,
    }
end)()

-- ═══════════════════════════════════════════════════════════════════
--  MÓDULO: CONFIG  —  Configurações + Save/Load JSON
-- ═══════════════════════════════════════════════════════════════════
local Config = (function()
    local SAVE_FILE = "SP_HUB_Config.json"

    local defaults = {
        -- Toggles
        autoFarm      = false,
        autoHaki      = false,
        fastAttack    = false,
        autoStats     = false,
        autoBoss      = false,
        hitAura       = false,
        autoEquip     = true,

        -- Valores
        attackDist    = 5,       -- studs
        flySpeed      = 50,      -- studs/s para Smart Tween
        flyHeight     = 4,       -- studs acima do mob
        behindOffset  = 3,       -- studs atrás do mob
        attackDelay   = 0.12,    -- segundos entre ataques
        fastAtkDelay  = 0.02,    -- delay do fast attack
        maxMobDist    = 3000,    -- distância máxima de busca
        attackTimeout = 40,      -- segundos até timeout por mob
        questInterval = 12,      -- re-verificar quest a cada N seg
        cacheInterval = 2.5,     -- atualizar cache de mobs a cada N seg
        auraRadius    = 15,      -- raio da hit aura (studs)
        respawnWait   = 4,       -- segundos após morte
        afkInterval   = 55,      -- anti-AFK

        -- Stats priority (ordem de distribuição)
        statPriority  = { "Melee", "Defense", "Health", "Speed" },

        -- GUI
        guiX          = 12,
        guiY          = 0.5,

        -- Keybind
        toggleKey     = "RightBracket",
    }

    local current = {}
    for k, v in pairs(defaults) do current[k] = v end

    -- Carrega configuração salva
    local function load()
        pcall(function()
            if readfile then
                local raw = readfile(SAVE_FILE)
                if raw and #raw > 2 then
                    local ok, data = pcall(function()
                        return Core.HttpService:JSONDecode(raw)
                    end)
                    if ok and type(data) == "table" then
                        for k, v in pairs(data) do
                            if defaults[k] ~= nil then
                                current[k] = v
                            end
                        end
                        Core.log("Config", "Configuração carregada.")
                    end
                end
            end
        end)
    end

    -- Salva configuração
    local function save()
        pcall(function()
            if writefile then
                local ok, json = pcall(function()
                    return Core.HttpService:JSONEncode(current)
                end)
                if ok then
                    writefile(SAVE_FILE, json)
                end
            end
        end)
    end

    -- Auto-save a cada 30 segundos
    task.spawn(function()
        while true do
            task.wait(30)
            save()
        end
    end)

    load()

    return {
        get     = function(k) return current[k] end,
        set     = function(k, v) current[k] = v save() end,
        getAll  = function() return current end,
        save    = save,
        load    = load,
        defaults = defaults,
    }
end)()

-- ═══════════════════════════════════════════════════════════════════
--  MÓDULO: DATA  —  Nível, progressão e tabela de missões
-- ═══════════════════════════════════════════════════════════════════
local Data = (function()

    -- ⚠️ EDITE: mobName e questNpc devem ser IDÊNTICOS ao nome no jogo
    local QUEST_TABLE = {
        { min=100,   max=249,       mob="Thief Boss",         npc="Thief Quest NPC",       island="Starter Island",  isBoss=false },
        { min=250,   max=499,       mob="Monkey Hunter",      npc="Monkey Quest NPC",      island="Jungle Island",   isBoss=false },
        { min=500,   max=749,       mob="Monkey Boss",        npc="Monkey Boss NPC",       island="Jungle Island",   isBoss=true  },
        { min=750,   max=999,       mob="Desert Bandit",      npc="Desert Quest NPC",      island="Desert Island",   isBoss=false },
        { min=1000,  max=1699,      mob="Desert Boss",        npc="Desert Boss NPC",       island="Desert Island",   isBoss=true  },
        { min=1700,  max=2999,      mob="Snow Enemy",         npc="Snow Quest NPC",        island="Snow Island",     isBoss=false },
        { min=3000,  max=3999,      mob="Sorcerer Hunter",    npc="Sorcerer Quest NPC",    island="Shibuya",         isBoss=false },
        { min=4000,  max=4999,      mob="Panda Boss",         npc="Panda Quest NPC",       island="Panda Island",    isBoss=true  },
        { min=5000,  max=6249,      mob="Hollow Hunter",      npc="Hollow Quest NPC",      island="Hollow Island",   isBoss=false },
        { min=6250,  max=6999,      mob="Strong Sorcerer",    npc="Strong Sorcerer NPC",   island="Sorcerer Island", isBoss=false },
        { min=7000,  max=7999,      mob="Curse Hunter",       npc="Curse Quest NPC",       island="Curse Island",    isBoss=false },
        { min=8000,  max=8999,      mob="Slime Warrior",      npc="Slime Quest NPC",       island="Slime Island",    isBoss=false },
        { min=9000,  max=9999,      mob="Academy Challenge",  npc="Academy NPC",           island="Academy",         isBoss=false },
        { min=10000, max=10749,     mob="Blade Master",       npc="Blade Quest NPC",       island="Blade Island",    isBoss=false },
        { min=10750, max=11499,     mob="Quincy",             npc="Quincy Quest NPC",      island="Quincy Island",   isBoss=false },
        { min=11500, max=12999,     mob="Broken Sword Enemy", npc="Broken Sword NPC",      island="Sword Island",    isBoss=false },
        { min=13000, max=15999,     mob="Spirit Fighter",     npc="Spirit Quest NPC",      island="Spirit Island",   isBoss=false },
        { min=16000, max=math.huge, mob="Strong Slayer",      npc="Slayer Quest NPC",      island="Slayer Island",   isBoss=false },
    }

    -- ⚠️ EDITE: melees válidos — nome parcial, case-insensitive
    local VALID_MELEES = {
        "Cosmic Being", "Moon Slayer", "The World", "Spirit Warrior",
        "Strongest Shinobi", "Blessed Maiden", "Corrupted Excalibur",
        "Gilgamesh", "Strongest of Today", "Anos", "Strongest in History",
        "Vampire King", "Qin Shi", "Cursed Vessel", "Cursed King", "Combat",
    }

    -- Palavras-chave que identificam um boss
    local BOSS_KEYWORDS = { "boss", "king", "lord", "master", "chief", "captain", "elite" }

    -- Obtém nível do player (múltiplos métodos de fallback)
    local function getLevel()
        local p = Core.player
        -- Método 1: leaderstats
        local ls = p:FindFirstChild("leaderstats")
        if ls then
            for _, name in ipairs({"Level","Lv","level","Nivel","LVL"}) do
                local v = ls:FindFirstChild(name)
                if v and tonumber(v.Value) then return tonumber(v.Value) end
            end
        end
        -- Método 2: pastas de dados
        for _, folder in ipairs({"Stats","PlayerData","Data","Attributes","PlayerStats"}) do
            local f = p:FindFirstChild(folder)
            if f then
                for _, name in ipairs({"Level","Lv","level"}) do
                    local v = f:FindFirstChild(name)
                    if v and tonumber(v.Value) then return tonumber(v.Value) end
                end
            end
        end
        -- Método 3: atributos
        for _, name in ipairs({"Level","Lv","level"}) do
            local a = p:GetAttribute(name)
            if a then return tonumber(a) or 1 end
        end
        -- Método 4: PlayerGui labels
        for _, v in ipairs(p.PlayerGui:GetDescendants()) do
            if v:IsA("TextLabel") and v.Name:lower():find("level") then
                local n = tonumber(v.Text:match("%d+"))
                if n and n > 0 then return n end
            end
        end
        return 1
    end

    local function getQuestForLevel(level)
        for i = #QUEST_TABLE, 1, -1 do
            local q = QUEST_TABLE[i]
            if level >= q.min and level <= q.max then return q end
        end
        return QUEST_TABLE[1]
    end

    local function isValidMelee(tool)
        if not tool or not tool:IsA("Tool") then return false end
        local name = tool.Name:lower()
        for _, m in ipairs(VALID_MELEES) do
            if name:find(m:lower(), 1, true) then return true end
        end
        return false
    end

    local function isBossModel(model)
        local name = model.Name:lower()
        for _, kw in ipairs(BOSS_KEYWORDS) do
            if name:find(kw, 1, true) then return true end
        end
        return false
    end

    return {
        getLevel        = getLevel,
        getQuestForLevel= getQuestForLevel,
        isValidMelee    = isValidMelee,
        isBossModel     = isBossModel,
        VALID_MELEES    = VALID_MELEES,
        QUEST_TABLE     = QUEST_TABLE,
    }
end)()

-- ═══════════════════════════════════════════════════════════════════
--  MÓDULO: CACHE  —  Sistema de cache inteligente de mobs
--  Elimina GetDescendants() em loop; atualiza via eventos e timer
-- ═══════════════════════════════════════════════════════════════════
local Cache = (function()
    -- cache[model] = { hum, hrp, isBoss, lastSeen }
    local cache = {}
    local lastUpdate = 0

    -- Verifica se um modelo é um NPC válido (não player, não morto)
    local function isValidNPC(model)
        if not model or not model:IsA("Model") then return false end
        if Core.Players:GetPlayerFromCharacter(model) then return false end
        local hum = model:FindFirstChildOfClass("Humanoid")
        local hrp = model:FindFirstChild("HumanoidRootPart")
        if not hum or not hrp then return false end
        if hum.Health <= 0 or hum.MaxHealth <= 0 then return false end
        -- Ignora mobs com posição bugada (NaN ou infinito)
        local p = hrp.Position
        if p ~= p or p.Magnitude == math.huge then return false end
        return true
    end

    -- Adiciona modelo ao cache
    local function register(model)
        if not isValidNPC(model) then return end
        local hum = model:FindFirstChildOfClass("Humanoid")
        local hrp = model:FindFirstChild("HumanoidRootPart")
        cache[model] = {
            hum      = hum,
            hrp      = hrp,
            isBoss   = Data.isBossModel(model),
            lastSeen = tick(),
        }
        -- Remove do cache quando morrer
        hum.Died:Connect(function()
            cache[model] = nil
        end)
        -- Remove do cache quando sair do workspace
        model.AncestryChanged:Connect(function(_, parent)
            if parent == nil then cache[model] = nil end
        end)
    end

    -- Varre workspace UMA VEZ para popular o cache inicial
    local function fullScan()
        for _, obj in ipairs(workspace:GetDescendants()) do
            if obj:IsA("Model") then
                pcall(register, obj)
            end
        end
    end

    -- Escuta novos modelos adicionados ao workspace (event-driven)
    workspace.DescendantAdded:Connect(function(obj)
        if obj:IsA("Model") then
            task.defer(function() pcall(register, obj) end)
        end
    end)

    -- Atualização periódica leve (apenas remove entradas inválidas)
    task.spawn(function()
        while true do
            task.wait(Config.get("cacheInterval"))
            local now = tick()
            for model, entry in pairs(cache) do
                local ok = pcall(function()
                    if not model.Parent
                    or not entry.hum
                    or entry.hum.Health <= 0
                    or (now - entry.lastSeen) > 60
                    then
                        cache[model] = nil
                    else
                        entry.lastSeen = now
                    end
                end)
                if not ok then cache[model] = nil end
            end
        end
    end)

    -- Busca o mob mais próximo que corresponda ao nome da missão
    -- Retorna: model, entry | nil, nil
    local function findNearest(mobName, maxDist)
        local root = Core.getRoot()
        if not root then return nil, nil end

        local best, bestEntry, bestDist = nil, nil, (maxDist or Config.get("maxMobDist"))
        local searchName = mobName:lower()

        for model, entry in pairs(cache) do
            local ok, err = pcall(function()
                if not model.Parent then return end
                if not model.Name:lower():find(searchName, 1, true) then return end
                if not entry.hum or entry.hum.Health <= 0 then return end
                if not entry.hrp then return end

                local d = (root.Position - entry.hrp.Position).Magnitude
                if d < bestDist then
                    best      = model
                    bestEntry = entry
                    bestDist  = d
                end
            end)
            if not ok then cache[model] = nil end
        end

        return best, bestEntry, bestDist
    end

    -- Busca o boss mais próximo independente do nome
    local function findNearestBoss(maxDist)
        local root = Core.getRoot()
        if not root then return nil, nil end

        local best, bestEntry, bestDist = nil, nil, (maxDist or 1500)
        for model, entry in pairs(cache) do
            pcall(function()
                if not model.Parent or not entry.isBoss then return end
                if not entry.hum or entry.hum.Health <= 0 then return end
                local d = (root.Position - entry.hrp.Position).Magnitude
                if d < bestDist then
                    best      = model
                    bestEntry = entry
                    bestDist  = d
                end
            end)
        end
        return best, bestEntry, bestDist
    end

    -- Inicia o scan inicial
    fullScan()
    Core.log("Cache", "Cache populado. NPCs encontrados: " .. (function()
        local n = 0
        for _ in pairs(cache) do n += 1 end
        return n
    end)())

    return {
        findNearest     = findNearest,
        findNearestBoss = findNearestBoss,
        getAll          = function() return cache end,
        count           = function()
            local n = 0
            for _ in pairs(cache) do n += 1 end
            return n
        end,
    }
end)()

-- ═══════════════════════════════════════════════════════════════════
--  MÓDULO: MOVEMENT  —  Smart Tween + voo estável + anti-stuck
-- ═══════════════════════════════════════════════════════════════════
local Movement = (function()
    local TweenService = Core.TweenService
    local isFlying = false

    -- Remove todos os BodyMovers do HRP
    local function cleanBodyMovers()
        local root = Core.getRoot()
        if not root then return end
        for _, v in ipairs(root:GetChildren()) do
            if v:IsA("BodyMover") then v:Destroy() end
        end
    end

    -- Activa voo estável usando AlignPosition + AlignOrientation
    -- (mais estável que BodyPosition/BodyVelocity em executores modernos)
    local flyAP, flyAO

    local function enableFlight()
        if not Core.isAlive() then return end
        local root = Core.getRoot()
        if not root then return end

        cleanBodyMovers()

        -- AlignPosition
        if not root:FindFirstChild("_HUB_AP") then
            local ap = Instance.new("AlignPosition")
            ap.Name          = "_HUB_AP"
            ap.MaxForce      = 1e6
            ap.MaxVelocity   = 200
            ap.Responsiveness = 50
            ap.RigidityEnabled = false
            -- Precisa de um Attachment no root
            local att0 = Instance.new("Attachment", root)
            att0.Name = "_HUB_Att0"
            -- Attachment fixo no workspace (referência)
            local att1 = Instance.new("Attachment", workspace.Terrain)
            att1.Name       = "_HUB_Att1"
            att1.WorldPosition = root.Position
            ap.Attachment0  = att0
            ap.Attachment1  = att1
            ap.Parent       = root
            flyAP = ap
        else
            flyAP = root:FindFirstChild("_HUB_AP")
        end

        -- AlignOrientation
        if not root:FindFirstChild("_HUB_AO") then
            local ao = Instance.new("AlignOrientation")
            ao.Name           = "_HUB_AO"
            ao.MaxTorque      = 1e6
            ao.MaxAngularVelocity = 50
            ao.Responsiveness  = 30
            ao.RigidityEnabled = false
            local att0 = root:FindFirstChild("_HUB_Att0") or Instance.new("Attachment", root)
            att0.Name = "_HUB_Att0"
            ao.Attachment0 = att0
            ao.Parent = root
            flyAO = ao
        else
            flyAO = root:FindFirstChild("_HUB_AO")
        end

        isFlying = true
    end

    local function disableFlight()
        local root = Core.getRoot()
        if root then
            for _, v in ipairs(root:GetChildren()) do
                if v.Name:find("_HUB_") then v:Destroy() end
            end
            local terrain = workspace:FindFirstChild("Terrain")
            if terrain then
                for _, v in ipairs(terrain:GetChildren()) do
                    if v.Name == "_HUB_Att1" then v:Destroy() end
                end
            end
        end
        flyAP    = nil
        flyAO    = nil
        isFlying = false
    end

    --[[
        smartFlyTo(targetPos, onArrival?)
        ─────────────────────────────────
        Voa suavemente até targetPos usando TweenService no Attachment de referência.
        Velocidade real controlada por CONFIG.flySpeed (studs/s).
        Sem fling, sem bugs de física.
    --]]
    local function smartFlyTo(targetPos, onArrival)
        if not Core.isAlive() then return false end

        enableFlight()

        local root = Core.getRoot()
        if not root then return false end

        -- Calcula destino: acima + offset horizontal
        local dest = targetPos + Vector3.new(0, Config.get("flyHeight"), 0)

        local att1 = workspace.Terrain:FindFirstChild("_HUB_Att1")
        if not att1 then return false end

        -- Atualiza posição do Attachment de referência via Tween
        local speed    = Config.get("flySpeed")     -- studs/s
        local distance = (root.Position - dest).Magnitude
        local time     = math.clamp(distance / speed, 0.08, 5.0)

        local info = TweenInfo.new(time, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
        local tween = TweenService:Create(att1, info, { WorldPosition = dest })
        tween:Play()

        -- AlignPosition segue o Attachment automaticamente
        -- (já configurado no enableFlight)

        -- Atualiza orientação para olhar para o destino
        if flyAO and root then
            flyAO.CFrame = CFrame.lookAt(root.Position, Vector3.new(targetPos.X, root.Position.Y, targetPos.Z))
        end

        -- Aguarda chegada com timeout
        local t = 0
        repeat
            task.wait(0.05)
            t += 0.05
            if not Core.isAlive() then return false end
        until (root.Position - dest).Magnitude < 7 or t > time + 3

        if onArrival then pcall(onArrival) end
        return true
    end

    -- Posiciona atrás e acima do mob (melhor ângulo de ataque)
    local function positionOnTarget(mobHRP)
        if not mobHRP or not Core.isAlive() then return end
        local backVec = -mobHRP.CFrame.LookVector
        local offset  = Config.get("behindOffset")
        local height  = Config.get("flyHeight")
        local dest    = mobHRP.Position + (backVec * offset) + Vector3.new(0, height, 0)
        smartFlyTo(dest)
        -- Vira para o mob
        local root = Core.getRoot()
        if root and flyAO then
            flyAO.CFrame = CFrame.lookAt(root.Position, mobHRP.Position)
        end
    end

    -- ── Anti-Stuck avançado ────────────────────────────────────────
    local stuckData = {
        timer     = 0,
        lastPos   = nil,
        fallTimer = 0,
    }

    local STUCK_TIMEOUT   = 6   -- segundos parado
    local FALL_TIMEOUT    = 4   -- segundos em queda livre

    local function checkAntiStuck(targetPos)
        if not Core.isAlive() then return end
        local root = Core.getRoot()
        if not root then return end
        local pos = root.Position

        -- Detecta queda infinita (Y caindo rápido)
        if stuckData.lastPos then
            local dy = stuckData.lastPos.Y - pos.Y
            if dy > 2 then
                stuckData.fallTimer += 0.1
                if stuckData.fallTimer > FALL_TIMEOUT then
                    stuckData.fallTimer = 0
                    Core.log("AntiStuck", "Queda detectada — forçando voo")
                    enableFlight()
                    if targetPos then
                        local att1 = workspace.Terrain:FindFirstChild("_HUB_Att1")
                        if att1 then att1.WorldPosition = pos + Vector3.new(0, 20, 0) end
                    end
                end
            else
                stuckData.fallTimer = 0
            end

            -- Detecta preso (pouco movimento, mas deveria estar voando)
            local moved = (pos - stuckData.lastPos).Magnitude
            if moved < 0.3 and isFlying then
                stuckData.timer += 0.1
                if stuckData.timer >= STUCK_TIMEOUT then
                    stuckData.timer = 0
                    Core.log("AntiStuck", "Travamento detectado — reposicionando")
                    -- Puxa para cima primeiro, depois recalcula
                    local att1 = workspace.Terrain:FindFirstChild("_HUB_Att1")
                    if att1 then
                        att1.WorldPosition = pos + Vector3.new(
                            math.random(-8, 8), 12, math.random(-8, 8)
                        )
                    end
                    task.wait(0.8)
                end
            else
                stuckData.timer = 0
            end
        end

        stuckData.lastPos = pos
    end

    return {
        enableFlight    = enableFlight,
        disableFlight   = disableFlight,
        smartFlyTo      = smartFlyTo,
        positionOnTarget= positionOnTarget,
        checkAntiStuck  = checkAntiStuck,
        isFlying        = function() return isFlying end,
        cleanBodyMovers = cleanBodyMovers,
    }
end)()

-- ═══════════════════════════════════════════════════════════════════
--  MÓDULO: EQUIP  —  Equipagem inteligente de melee
-- ═══════════════════════════════════════════════════════════════════
local Equip = (function()
    local function getMeleeInChar()
        local c = Core.getChar()
        if not c then return nil end
        for _, v in ipairs(c:GetChildren()) do
            if Data.isValidMelee(v) then return v end
        end
        return nil
    end

    local function getMeleeInBackpack()
        local bp = Core.player:FindFirstChild("Backpack")
        if not bp then return nil end
        for _, v in ipairs(bp:GetChildren()) do
            if Data.isValidMelee(v) then return v end
        end
        return nil
    end

    -- Retorna true se melee está equipado (no personagem, não na mochila)
    local function isEquipped()
        return getMeleeInChar() ~= nil
    end

    -- Equipa o melhor melee disponível
    -- Retorna: true se equipado, false se não tem melee
    local function equip()
        if isEquipped() then return true end

        local tool = getMeleeInBackpack()
        if not tool then
            Core.warn("Equip", "Nenhum melee válido encontrado!")
            return false
        end

        local hum = Core.getHum()
        if hum then
            local ok = pcall(function() hum:EquipTool(tool) end)
            if ok then
                task.wait(0.2)
                Core.log("Equip", "Equipado: " .. tool.Name)
                return true
            end
        end
        return false
    end

    -- Garante que o melee correto está equipado antes de atacar
    local function ensure()
        if not isEquipped() then return equip() end
        return true
    end

    return {
        equip      = equip,
        ensure     = ensure,
        isEquipped = isEquipped,
        getEquipped= getMeleeInChar,
    }
end)()

-- ═══════════════════════════════════════════════════════════════════
--  MÓDULO: COMBAT  —  Sistema de ataque profissional
-- ═══════════════════════════════════════════════════════════════════
local Combat = (function()
    local RS = Core.ReplicatedStorage

    -- Cache de remotes detectados (evita busca repetida)
    local remoteCache = {}
    local remoteCacheTime = 0

    -- Detecta automaticamente remotes de combate no ReplicatedStorage
    local ATTACK_REMOTE_PATTERNS = {
        "Attack", "MeleeAttack", "Combat", "Punch", "Hit", "Strike",
        "Melee", "BasicAttack", "NormalAttack", "M1", "Click", "Swing",
    }

    local function findRemotes()
        if tick() - remoteCacheTime < 10 then return remoteCache end
        remoteCache = {}
        remoteCacheTime = tick()

        local function scan(parent, depth)
            if depth > 4 then return end
            for _, v in ipairs(parent:GetChildren()) do
                if v:IsA("RemoteEvent") or v:IsA("RemoteFunction") then
                    local name = v.Name:lower()
                    for _, pat in ipairs(ATTACK_REMOTE_PATTERNS) do
                        if name:find(pat:lower(), 1, true) then
                            table.insert(remoteCache, v)
                            break
                        end
                    end
                elseif v:IsA("Folder") or v:IsA("Configuration") then
                    scan(v, depth + 1)
                end
            end
        end

        scan(RS, 0)
        Core.log("Combat", "Remotes detectados: " .. #remoteCache)
        return remoteCache
    end

    -- Dispara um ataque via RemoteEvent
    local function fireRemoteAttack(targetHRP, target)
        local remotes = findRemotes()
        for _, remote in ipairs(remotes) do
            pcall(function()
                if remote:IsA("RemoteEvent") then
                    remote:FireServer(targetHRP.Position, target, targetHRP.CFrame)
                end
            end)
        end
    end

    -- Ativa a ferramenta equipada (simula click/activate)
    local function activateTool()
        local c = Core.getChar()
        if not c then return end
        for _, tool in ipairs(c:GetChildren()) do
            if Data.isValidMelee(tool) then
                pcall(function() tool:Activate() end)
                -- Tenta via remote interno da ferramenta
                for _, v in ipairs(tool:GetDescendants()) do
                    if v:IsA("RemoteEvent") then
                        pcall(function() v:FireServer() end)
                    end
                end
                break
            end
        end
    end

    -- Ataque completo em um alvo
    local function attack(mob, mobHRP)
        if not mob or not mobHRP or not Core.isAlive() then return end
        local root = Core.getRoot()
        if not root then return end

        -- Garante melee equipado
        if not Equip.ensure() then return end

        -- Olha para o alvo
        pcall(function()
            root.CFrame = CFrame.lookAt(root.Position, mobHRP.Position)
        end)

        -- Dispara via remotes detectados
        fireRemoteAttack(mobHRP, mob)

        -- Ativa a ferramenta
        activateTool()

        -- Mantém distância correta
        local d = (root.Position - mobHRP.Position).Magnitude
        if d > Config.get("attackDist") * 2.5 then
            Movement.positionOnTarget(mobHRP)
        end
    end

    -- ── Hit Aura ────────────────────────────────────────────────────
    -- Ataca todos os mobs dentro do raio da aura simultaneamente
    local hitAuraThread = nil
    local hitAuraActive = false

    local function startHitAura(mobName)
        if hitAuraActive then return end
        hitAuraActive = true
        hitAuraThread = task.spawn(function()
            while hitAuraActive and Core.isAlive() do
                task.wait(Config.get("fastAtkDelay") * 3)
                local root = Core.getRoot()
                if not root then continue end
                local radius = Config.get("auraRadius")
                for model, entry in pairs(Cache.getAll()) do
                    pcall(function()
                        if not model.Parent then return end
                        -- Filtra por nome se mobName fornecido
                        if mobName and not model.Name:lower():find(mobName:lower(), 1, true) then return end
                        if not entry.hum or entry.hum.Health <= 0 then return end
                        local d = (root.Position - entry.hrp.Position).Magnitude
                        if d <= radius then
                            fireRemoteAttack(entry.hrp, model)
                            activateTool()
                        end
                    end)
                end
            end
        end)
    end

    local function stopHitAura()
        hitAuraActive = false
        if hitAuraThread then
            task.cancel(hitAuraThread)
            hitAuraThread = nil
        end
    end

    -- Pré-detecta remotes ao carregar
    task.defer(findRemotes)

    return {
        attack        = attack,
        startHitAura  = startHitAura,
        stopHitAura   = stopHitAura,
        findRemotes   = findRemotes,
    }
end)()

-- ═══════════════════════════════════════════════════════════════════
--  MÓDULO: QUEST  —  Sistema inteligente de missões
-- ═══════════════════════════════════════════════════════════════════
local Quest = (function()
    local hasQuest   = false
    local lastCheck  = 0
    local currentNpc = nil

    -- Detecta se existe uma missão ativa via múltiplos métodos
    local function detectActiveQuest()
        local p = Core.player
        -- Método 1: atributos
        for _, name in ipairs({"HasQuest","QuestActive","InQuest","QuestAccepted"}) do
            local a = p:GetAttribute(name)
            if a == true then return true end
        end
        -- Método 2: pastas de dados
        for _, folder in ipairs({"QuestData","Quests","Data","PlayerData","Stats"}) do
            local f = p:FindFirstChild(folder)
            if f then
                local q = f:FindFirstChild("HasQuest") or f:FindFirstChild("QuestActive")
                        or f:FindFirstChild("CurrentQuest") or f:FindFirstChild("QuestName")
                if q then
                    if typeof(q.Value) == "boolean" and q.Value then return true end
                    if typeof(q.Value) == "string" and #q.Value > 0 then return true end
                    if typeof(q.Value) == "number" and q.Value > 0 then return true end
                end
            end
        end
        -- Método 3: GUI de quest visível
        for _, v in ipairs(p.PlayerGui:GetDescendants()) do
            if (v:IsA("Frame") or v:IsA("ScrollingFrame")) and v.Visible then
                local n = v.Name:lower()
                if n:find("quest") or n:find("mission") or n:find("missao") or n:find("task") then
                    -- Verifica se tem progresso (ex: "3/5")
                    for _, child in ipairs(v:GetDescendants()) do
                        if child:IsA("TextLabel") then
                            local t = child.Text
                            if t:match("%d+%s*/%s*%d+") then return true end
                        end
                    end
                end
            end
        end
        return false
    end

    -- Interage com um NPC (tenta todos os métodos)
    local function interactNPC(npc)
        -- ProximityPrompt
        for _, v in ipairs(npc:GetDescendants()) do
            if v:IsA("ProximityPrompt") then
                pcall(function()
                    if fireproximityprompt then
                        fireproximityprompt(v)
                    else
                        v.Triggered:Fire(Core.player)
                    end
                end)
                task.wait(0.5)
                break
            end
        end

        -- ClickDetector
        for _, v in ipairs(npc:GetDescendants()) do
            if v:IsA("ClickDetector") then
                pcall(function()
                    if fireclickdetector then
                        fireclickdetector(v)
                    end
                end)
                task.wait(0.5)
                break
            end
        end

        -- RemoteEvents de quest
        local RS = Core.ReplicatedStorage
        local questRemoteNames = {
            "AcceptQuest","TakeQuest","GetQuest","StartQuest",
            "QuestAccept","Quest","Talk","Interact","NpcTalk",
        }
        for _, rName in ipairs(questRemoteNames) do
            local function tryFind(parent)
                return parent:FindFirstChild(rName)
                    or (parent:FindFirstChild("Remotes") and parent.Remotes:FindFirstChild(rName))
                    or (parent:FindFirstChild("Events") and parent.Events:FindFirstChild(rName))
            end
            local r = tryFind(RS)
            if r and r:IsA("RemoteEvent") then
                pcall(function() r:FireServer(npc.Name) end)
                task.wait(0.3)
            end
        end
    end

    -- Clica em botões de aceitar na GUI
    local function clickAcceptButtons()
        task.wait(0.6)
        local keywords = { "accept","aceitar","start","começar","confirmar","ok","yes","sim","take" }
        for _, v in ipairs(Core.player.PlayerGui:GetDescendants()) do
            if v:IsA("TextButton") and v.Visible then
                local t = v.Text:lower()
                for _, kw in ipairs(keywords) do
                    if t:find(kw, 1, true) then
                        pcall(function() v.MouseButton1Click:Fire() end)
                        task.wait(0.3)
                        break
                    end
                end
            end
        end
    end

    -- Vai até o NPC e aceita a missão
    local function goAccept(questData)
        Core.log("Quest", "Indo ao NPC: " .. questData.npc)
        local searchName = questData.npc:lower()
        local npc = nil

        -- Procura NPC no workspace
        for _, obj in ipairs(workspace:GetDescendants()) do
            if obj:IsA("Model") and obj.Name:lower():find(searchName, 1, true) then
                if obj:FindFirstChild("HumanoidRootPart") then
                    npc = obj; break
                end
            end
        end

        if not npc then
            Core.warn("Quest", "NPC não encontrado: " .. questData.npc)
            task.wait(2)
            return false
        end

        currentNpc = npc
        local npcHRP = npc:FindFirstChild("HumanoidRootPart")
        if not npcHRP then return false end

        -- Voa até o NPC
        Movement.smartFlyTo(npcHRP.Position)
        task.wait(0.4)
        Movement.disableFlight()

        interactNPC(npc)
        clickAcceptButtons()

        hasQuest  = true
        lastCheck = tick()
        Core.log("Quest", "Missão aceita: " .. questData.mob)
        return true
    end

    -- Verifica se deve aceitar a missão (com intervalo inteligente)
    local function needsQuest()
        local now = tick()
        -- Só re-checa após QUEST_CHECK_EVERY segundos
        if now - lastCheck < Config.get("questInterval") then
            return not hasQuest
        end
        lastCheck = now
        local active = detectActiveQuest()
        hasQuest = active
        return not active
    end

    local function markQuestDone()
        hasQuest  = false
        lastCheck = 0
    end

    return {
        needsQuest    = needsQuest,
        goAccept      = goAccept,
        markQuestDone = markQuestDone,
        isActive      = function() return hasQuest end,
    }
end)()

-- ═══════════════════════════════════════════════════════════════════
--  MÓDULO: AUTOSTATS  —  Distribuição automática de pontos
-- ═══════════════════════════════════════════════════════════════════
local AutoStats = (function()
    local RS = Core.ReplicatedStorage
    local lastDist = 0

    -- Detecta remotes de stats
    local function findStatRemote()
        local names = { "AddStat","UpgradeStat","AddPoints","StatUp","LevelUp","UpgradeAttribute" }
        for _, n in ipairs(names) do
            local r = RS:FindFirstChild(n)
                   or (RS:FindFirstChild("Remotes") and RS.Remotes:FindFirstChild(n))
            if r and r:IsA("RemoteEvent") then return r end
        end
        return nil
    end

    local function distribute()
        if not Core.isAlive() then return end
        if tick() - lastDist < 3 then return end
        lastDist = tick()

        local r = findStatRemote()
        if not r then return end

        local priority = Config.get("statPriority")
        pcall(function() r:FireServer(priority[1]) end)
    end

    return { distribute = distribute }
end)()

-- ═══════════════════════════════════════════════════════════════════
--  MÓDULO: AUTOHAKI  —  Ativação automática de Haki
-- ═══════════════════════════════════════════════════════════════════
local AutoHaki = (function()
    local RS = Core.ReplicatedStorage
    local lastHaki = 0

    local function activate()
        if not Config.get("autoHaki") then return end
        if not Core.isAlive() then return end
        if tick() - lastHaki < 8 then return end
        lastHaki = tick()

        local names = { "Haki","Observation","Armament","CoO","CoA","Buso","Ken","Kenbunshoku" }
        for _, n in ipairs(names) do
            local r = RS:FindFirstChild(n)
                   or (RS:FindFirstChild("Remotes") and RS.Remotes:FindFirstChild(n))
            if r and r:IsA("RemoteEvent") then
                pcall(function() r:FireServer() end)
                return
            end
        end
    end

    return { activate = activate }
end)()

-- ═══════════════════════════════════════════════════════════════════
--  MÓDULO: STATE  —  Estado global centralizado
-- ═══════════════════════════════════════════════════════════════════
local State = {
    running       = false,
    isDead        = false,
    currentMob    = "—",
    currentIsland = "—",
    currentQuest  = "—",
    status        = "Inativo",
    targetDist    = 0,
    farmTime      = 0,
    farmStart     = 0,
    bossDetected  = false,
    bossName      = "—",
    killCount     = 0,
}

-- ═══════════════════════════════════════════════════════════════════
--  MÓDULO: FARM  —  Loop principal de farm
-- ═══════════════════════════════════════════════════════════════════
local Farm = (function()

    -- Respawn handler
    Core.player.CharacterAdded:Connect(function(newChar)
        State.isDead = false
        Equip.ensure()
        Movement.cleanBodyMovers()
        Core.refresh()
        task.wait(Config.get("respawnWait"))
        Quest.markQuestDone()
        Core.log("Farm", "Respawnado — pronto")
        if Config.get("autoEquip") then Equip.equip() end
    end)

    -- Anti-AFK em thread separada
    task.spawn(function()
        while true do
            task.wait(Config.get("afkInterval"))
            if Core.isAlive() then
                local root = Core.getRoot()
                local hum  = Core.getHum()
                if root and hum then
                    hum:MoveTo(root.Position + Vector3.new(math.random(-2,2), 0, math.random(-2,2)))
                end
            end
        end
    end)

    local function mainLoop()
        State.farmStart = tick()
        Core.log("Farm", "Loop principal iniciado")

        while State.running do
            task.wait(0.05)

            -- ── [1] Sobrevivência ───────────────────────────────────────
            if not Core.isAlive() then
                State.isDead  = true
                State.status  = "💀 Aguardando respawn..."
                Movement.disableFlight()
                task.wait(Config.get("respawnWait") + 1)
                Core.refresh()
                task.wait(1)
                continue
            end
            State.isDead = false
            State.farmTime = tick() - State.farmStart

            -- Sistemas paralelos
            AutoHaki.activate()
            Movement.checkAntiStuck(nil)

            -- ── [2] Nível e missão ─────────────────────────────────────
            local level = Data.getLevel()
            local quest = Data.getQuestForLevel(level)
            State.currentMob    = quest.mob
            State.currentIsland = quest.island
            State.currentQuest  = quest.mob .. " (" .. quest.island .. ")"

            -- ── [3] Auto Boss (prioridade se ativado) ─────────────────
            if Config.get("autoBoss") then
                local boss, bossEntry = Cache.findNearestBoss(1200)
                if boss and bossEntry then
                    State.bossDetected = true
                    State.bossName     = boss.Name
                    State.status       = "👑 Boss: " .. boss.Name

                    -- Combate com boss
                    local bossTimer = 0
                    while State.running and Core.isAlive()
                      and boss.Parent and bossEntry.hum.Health > 0
                    do
                        Movement.positionOnTarget(bossEntry.hrp)
                        Combat.attack(boss, bossEntry.hrp)
                        if Config.get("hitAura") then Combat.startHitAura(nil) end
                        local delay = Config.get("fastAttack") and Config.get("fastAtkDelay") or Config.get("attackDelay")
                        task.wait(delay)
                        bossTimer += delay
                        if bossTimer > 120 then break end
                    end

                    State.bossDetected = false
                    State.bossName     = "—"
                    Combat.stopHitAura()
                    Movement.disableFlight()
                    State.killCount += 1
                    continue
                end
                State.bossDetected = false
            end

            -- ── [4] Verificar missão ───────────────────────────────────
            if Quest.needsQuest() then
                State.status = "📋 Indo aceitar missão..."
                local ok = Quest.goAccept(quest)
                if not ok then task.wait(3) continue end
            end

            State.status = string.format("⚔️ Lv%d | %s", level, quest.mob)

            -- ── [5] Busca o mob mais próximo ───────────────────────────
            local mob, entry, mobDist = Cache.findNearest(quest.mob, Config.get("maxMobDist"))

            if not mob or not entry then
                State.status   = "🔍 Procurando " .. quest.mob .. "..."
                State.targetDist = 0
                task.wait(0.5)
                continue
            end

            State.targetDist = math.floor(mobDist)

            -- ── [6] Posicionamento ─────────────────────────────────────
            if mobDist > Config.get("attackDist") + 3 then
                State.status = "✈️ Voando até " .. quest.mob
                Movement.positionOnTarget(entry.hrp)
            end

            -- Equipa melee
            if not Equip.ensure() then
                State.status = "⚠️ Sem melee válido!"
                task.wait(2)
                continue
            end

            -- Inicia hit aura se ativada
            if Config.get("hitAura") then
                Combat.startHitAura(quest.mob)
            else
                Combat.stopHitAura()
            end

            -- ── [7] Loop de ataque ─────────────────────────────────────
            local atkTimer = 0
            while State.running and Core.isAlive()
              and mob and mob.Parent
              and entry.hum and entry.hum.Health > 0
            do
                Combat.attack(mob, entry.hrp)

                local delay = Config.get("fastAttack")
                    and Config.get("fastAtkDelay")
                    or  Config.get("attackDelay")
                task.wait(delay)
                atkTimer += delay

                -- Anti-stuck no loop de ataque
                Movement.checkAntiStuck(entry.hrp.Position)

                -- Auto stats periódico
                if Config.get("autoStats") and math.floor(atkTimer) % 5 == 0 then
                    AutoStats.distribute()
                end

                -- Timeout de segurança
                if atkTimer >= Config.get("attackTimeout") then
                    Core.log("Farm", "Timeout — mob: " .. quest.mob)
                    break
                end

                -- Atualiza distância no State
                local root = Core.getRoot()
                if root and entry.hrp then
                    State.targetDist = math.floor((root.Position - entry.hrp.Position).Magnitude)
                end
            end

            -- ── [8] Finalização do ciclo ───────────────────────────────
            Combat.stopHitAura()
            Movement.disableFlight()

            if entry.hum and entry.hum.Health <= 0 then
                State.killCount += 1
                -- Verifica se missão foi concluída
                task.wait(0.2)
                if not Quest.isActive() then
                    Quest.markQuestDone()
                    Core.log("Farm", "Missão concluída! Próximo ciclo...")
                end
            end
        end

        -- Encerramento limpo
        Movement.disableFlight()
        Combat.stopHitAura()
        State.status      = "Inativo"
        State.currentMob  = "—"
        Core.log("Farm", "Farm encerrado")
    end

    local function start()
        if State.running then return end
        State.running   = true
        State.farmStart = tick()
        State.killCount = 0
        Equip.equip()
        task.spawn(mainLoop)
    end

    local function stop()
        State.running = false
        Movement.disableFlight()
        Combat.stopHitAura()
    end

    return { start = start, stop = stop }
end)()

-- ═══════════════════════════════════════════════════════════════════
--  MÓDULO: GUI  —  HUB Profissional com Tabs
-- ═══════════════════════════════════════════════════════════════════
local GUI = (function()
    local player     = Core.player
    local TweenService = Core.TweenService

    -- Paleta de cores
    local C = {
        bg        = Color3.fromRGB(8, 10, 16),
        panel     = Color3.fromRGB(14, 17, 26),
        header    = Color3.fromRGB(0, 90, 220),
        accent    = Color3.fromRGB(0, 140, 255),
        accentOff = Color3.fromRGB(200, 50, 50),
        accentOn  = Color3.fromRGB(30, 200, 100),
        text      = Color3.fromRGB(210, 225, 255),
        subtext   = Color3.fromRGB(120, 145, 190),
        card      = Color3.fromRGB(18, 23, 38),
        border    = Color3.fromRGB(30, 60, 130),
        tab       = Color3.fromRGB(20, 25, 40),
        tabActive = Color3.fromRGB(0, 90, 220),
    }

    local function tween(obj, props, time, style, dir)
        TweenService:Create(obj,
            TweenInfo.new(time or 0.2, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out),
            props
        ):Play()
    end

    local function corner(parent, r)
        local c = Instance.new("UICorner")
        c.CornerRadius = UDim.new(0, r or 8)
        c.Parent = parent
    end

    local function stroke(parent, color, thickness)
        local s = Instance.new("UIStroke")
        s.Color = color or C.border
        s.Thickness = thickness or 1
        s.Parent = parent
    end

    local function label(parent, text, size, color, font, xa, ya)
        local l = Instance.new("TextLabel")
        l.BackgroundTransparency = 1
        l.Text = text or ""
        l.TextSize = size or 12
        l.TextColor3 = color or C.text
        l.Font = font or Enum.Font.Gotham
        l.TextXAlignment = xa or Enum.TextXAlignment.Left
        l.TextYAlignment = ya or Enum.TextYAlignment.Center
        l.Parent = parent
        return l
    end

    -- Remove GUI antiga
    local old = player.PlayerGui:FindFirstChild("SPHUB_GUI")
    if old then old:Destroy() end

    -- ── ScreenGui ──────────────────────────────────────────────────
    local sg = Instance.new("ScreenGui")
    sg.Name           = "SPHUB_GUI"
    sg.ResetOnSpawn   = false
    sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    sg.DisplayOrder   = 999
    sg.Parent         = player.PlayerGui

    -- ── Painel Principal ───────────────────────────────────────────
    local W, H = 300, 420
    local panel = Instance.new("Frame")
    panel.Name            = "Panel"
    panel.Size            = UDim2.new(0, W, 0, H)
    panel.Position        = UDim2.new(0, Config.get("guiX"), Config.get("guiY"), -H/2)
    panel.BackgroundColor3 = C.bg
    panel.BorderSizePixel = 0
    panel.Active          = true
    panel.Draggable       = true
    panel.Parent          = sg
    corner(panel, 12)
    stroke(panel, C.border, 1.5)

    -- Salva posição ao arrastar
    panel:GetPropertyChangedSignal("Position"):Connect(function()
        pcall(function()
            Config.set("guiX", panel.Position.X.Offset)
        end)
    end)

    -- ── Header ─────────────────────────────────────────────────────
    local header = Instance.new("Frame")
    header.Size             = UDim2.new(1, 0, 0, 46)
    header.BackgroundColor3 = C.header
    header.BorderSizePixel  = 0
    header.Parent           = panel
    corner(header, 12)
    -- Cobre cantos inferiores do header
    local hfill = Instance.new("Frame")
    hfill.Size = UDim2.new(1,0,0,12); hfill.Position = UDim2.new(0,0,1,-12)
    hfill.BackgroundColor3 = C.header; hfill.BorderSizePixel = 0; hfill.Parent = header

    local titleLbl = label(header, "⚓  SAILOR PIECE HUB", 14, Color3.new(1,1,1), Enum.Font.GothamBold)
    titleLbl.Size = UDim2.new(1,-12,1,0); titleLbl.Position = UDim2.new(0,12,0,0)

    local verLbl = label(header, "v4.0", 10, Color3.fromRGB(170,210,255))
    verLbl.Size = UDim2.new(0,36,1,0); verLbl.Position = UDim2.new(1,-40,0,0)
    verLbl.TextXAlignment = Enum.TextXAlignment.Right

    -- ── Status Bar ─────────────────────────────────────────────────
    local statusBar = Instance.new("Frame")
    statusBar.Size              = UDim2.new(0.92, 0, 0, 58)
    statusBar.Position          = UDim2.new(0.04, 0, 0, 54)
    statusBar.BackgroundColor3  = C.card
    statusBar.BorderSizePixel   = 0
    statusBar.Parent            = panel
    corner(statusBar, 8)
    stroke(statusBar, C.border)

    local lblStatus = label(statusBar, "📌 Inativo", 11, C.text)
    lblStatus.Size     = UDim2.new(1,-8,0,16)
    lblStatus.Position = UDim2.new(0,6,0,4)

    local lblMob = label(statusBar, "🎯 Mob: —", 10, C.subtext)
    lblMob.Size     = UDim2.new(1,-8,0,14)
    lblMob.Position = UDim2.new(0,6,0,22)

    local lblLvIsland = label(statusBar, "⭐ Lv — | —", 10, C.subtext)
    lblLvIsland.Size     = UDim2.new(1,-8,0,14)
    lblLvIsland.Position = UDim2.new(0,6,0,38)

    -- ── Stats rápidas (FPS / Ping / Kills / Dist) ──────────────────
    local statsRow = Instance.new("Frame")
    statsRow.Size             = UDim2.new(0.92, 0, 0, 28)
    statsRow.Position         = UDim2.new(0.04, 0, 0, 120)
    statsRow.BackgroundColor3 = C.card
    statsRow.BorderSizePixel  = 0
    statsRow.Parent           = panel
    corner(statsRow, 8)

    local function statCell(text, xFrac)
        local f = Instance.new("Frame")
        f.Size             = UDim2.new(0.25, -2, 1, 0)
        f.Position         = UDim2.new(xFrac, 1, 0, 0)
        f.BackgroundTransparency = 1
        f.Parent           = statsRow
        local l2 = label(f, text, 9, C.subtext, Enum.Font.GothamBold, Enum.TextXAlignment.Center)
        l2.Size = UDim2.new(1,0,1,0)
        return l2
    end

    local lblFPS   = statCell("FPS 60",  0)
    local lblPing  = statCell("PING 0",  0.25)
    local lblKills = statCell("0 kills", 0.5)
    local lblDist  = statCell("0 studs", 0.75)

    -- ── Separador ──────────────────────────────────────────────────
    local sep = Instance.new("Frame")
    sep.Size = UDim2.new(0.88,0,0,1); sep.Position = UDim2.new(0.06,0,0,155)
    sep.BackgroundColor3 = C.border; sep.BorderSizePixel = 0; sep.Parent = panel

    -- ── Tab Bar ────────────────────────────────────────────────────
    local tabBar = Instance.new("Frame")
    tabBar.Size             = UDim2.new(0.92, 0, 0, 28)
    tabBar.Position         = UDim2.new(0.04, 0, 0, 162)
    tabBar.BackgroundColor3 = C.tab
    tabBar.BorderSizePixel  = 0
    tabBar.Parent           = panel
    corner(tabBar, 8)

    local tabDefs = { "Farm", "Combat", "Stats", "Config" }
    local tabBtns = {}
    local tabPages = {}
    local activeTab = "Farm"

    -- Área de conteúdo das tabs
    local tabContent = Instance.new("Frame")
    tabContent.Size             = UDim2.new(0.92, 0, 0, H - 205)
    tabContent.Position         = UDim2.new(0.04, 0, 0, 197)
    tabContent.BackgroundTransparency = 1
    tabContent.ClipsDescendants = true
    tabContent.Parent           = panel

    local function showTab(name)
        activeTab = name
        for tabName, page in pairs(tabPages) do
            page.Visible = tabName == name
        end
        for _, def in ipairs(tabDefs) do
            local btn = tabBtns[def]
            if btn then
                local on = def == name
                tween(btn, { BackgroundColor3 = on and C.tabActive or C.tab }, 0.15)
                btn:FindFirstChildOfClass("TextLabel").TextColor3 = on and Color3.new(1,1,1) or C.subtext
            end
        end
    end

    -- Cria tabs e páginas
    for i, tabName in ipairs(tabDefs) do
        -- Botão da tab
        local btn = Instance.new("TextButton")
        btn.Size             = UDim2.new(0.25, -3, 1, 0)
        btn.Position         = UDim2.new((i-1)*0.25, (i-1)*3 + 1, 0, 0)
        btn.BackgroundColor3 = C.tab
        btn.BorderSizePixel  = 0
        btn.Text             = ""
        btn.Parent           = tabBar
        corner(btn, 6)

        local bl = label(btn, tabName, 11, C.subtext, Enum.Font.GothamBold, Enum.TextXAlignment.Center)
        bl.Size = UDim2.new(1,0,1,0)

        tabBtns[tabName] = btn

        -- Página da tab
        local page = Instance.new("ScrollingFrame")
        page.Name                 = tabName
        page.Size                 = UDim2.new(1,0,1,0)
        page.BackgroundTransparency = 1
        page.BorderSizePixel      = 0
        page.ScrollBarThickness   = 2
        page.ScrollBarImageColor3 = C.accent
        page.CanvasSize           = UDim2.new(0,0,0,0)
        page.Visible              = false
        page.Parent               = tabContent
        tabPages[tabName] = page

        local layout = Instance.new("UIListLayout")
        layout.Padding         = UDim.new(0, 5)
        layout.SortOrder       = Enum.SortOrder.LayoutOrder
        layout.Parent          = page

        local pad = Instance.new("UIPadding")
        pad.PaddingTop = UDim.new(0, 4); pad.PaddingBottom = UDim.new(0,4)
        pad.Parent = page

        -- Auto-resize canvas
        layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
            page.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 12)
        end)

        btn.MouseButton1Click:Connect(function() showTab(tabName) end)
    end

    showTab("Farm")

    -- ── Helpers para criar controles ───────────────────────────────

    local function makeCard(page, heightVal)
        local c = Instance.new("Frame")
        c.Size             = UDim2.new(1, -4, 0, heightVal or 34)
        c.BackgroundColor3 = C.card
        c.BorderSizePixel  = 0
        c.LayoutOrder      = #page:GetChildren()
        c.Parent           = page
        corner(c, 7)
        return c
    end

    -- Toggle button profissional
    local function makeToggle(page, labelText, icon, configKey, onToggle)
        local card = makeCard(page, 34)

        local iconL = label(card, icon or "●", 13, C.accent)
        iconL.Size = UDim2.new(0,28,1,0); iconL.Position = UDim2.new(0,4,0,0)
        iconL.TextXAlignment = Enum.TextXAlignment.Center

        local textL = label(card, labelText, 11, C.text, Enum.Font.GothamBold)
        textL.Size = UDim2.new(1,-80,1,0); textL.Position = UDim2.new(0,32,0,0)

        -- Pill ON/OFF
        local pillBg = Instance.new("Frame")
        pillBg.Size             = UDim2.new(0,44,0,20)
        pillBg.Position         = UDim2.new(1,-50,0.5,-10)
        pillBg.BackgroundColor3 = C.accentOff
        pillBg.BorderSizePixel  = 0
        pillBg.Parent           = card
        corner(pillBg, 10)

        local pillDot = Instance.new("Frame")
        pillDot.Size             = UDim2.new(0,16,0,16)
        pillDot.Position         = UDim2.new(0,2,0.5,-8)
        pillDot.BackgroundColor3 = Color3.new(1,1,1)
        pillDot.BorderSizePixel  = 0
        pillDot.Parent           = pillBg
        corner(pillDot, 8)

        local pillLbl = label(pillBg, "OFF", 8, Color3.new(1,1,1), Enum.Font.GothamBold, Enum.TextXAlignment.Right)
        pillLbl.Size = UDim2.new(1,-22,1,0); pillLbl.Position = UDim2.new(0,2,0,0)

        local function refresh()
            local on = Config.get(configKey)
            tween(pillBg, { BackgroundColor3 = on and C.accentOn or C.accentOff }, 0.15)
            tween(pillDot, { Position = on and UDim2.new(1,-18,0.5,-8) or UDim2.new(0,2,0.5,-8) }, 0.15)
            pillLbl.Text = on and "ON" or "OFF"
            pillLbl.Position = on and UDim2.new(0,4,0,0) or UDim2.new(1,-22,0,0)
        end

        refresh()

        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(1,0,1,0); btn.BackgroundTransparency = 1; btn.Text = ""; btn.Parent = card
        btn.MouseButton1Click:Connect(function()
            Config.set(configKey, not Config.get(configKey))
            refresh()
            if onToggle then pcall(onToggle, Config.get(configKey)) end
        end)

        return card
    end

    -- Slider profissional
    local function makeSlider(page, labelText, configKey, min_, max_, format)
        local card = makeCard(page, 46)
        local topLabel = label(card, labelText, 10, C.subtext)
        topLabel.Size = UDim2.new(0.6,0,0,18); topLabel.Position = UDim2.new(0,8,0,2)

        local valLabel = label(card, "", 10, C.accent, Enum.Font.GothamBold, Enum.TextXAlignment.Right)
        valLabel.Size = UDim2.new(0.35,0,0,18); valLabel.Position = UDim2.new(0.65,-8,0,2)

        local track = Instance.new("Frame")
        track.Size             = UDim2.new(1,-16,0,6)
        track.Position         = UDim2.new(0,8,0,28)
        track.BackgroundColor3 = C.border
        track.BorderSizePixel  = 0
        track.Parent           = card
        corner(track, 3)

        local fill = Instance.new("Frame")
        fill.Size             = UDim2.new(0,0,1,0)
        fill.BackgroundColor3 = C.accent
        fill.BorderSizePixel  = 0
        fill.Parent           = track
        corner(fill, 3)

        local knob = Instance.new("Frame")
        knob.Size             = UDim2.new(0,14,0,14)
        knob.AnchorPoint      = Vector2.new(0.5, 0.5)
        knob.BackgroundColor3 = Color3.new(1,1,1)
        knob.BorderSizePixel  = 0
        knob.Parent           = track
        corner(knob, 7)

        local dragging = false

        local function updateSlider(val)
            val = math.clamp(val, min_, max_)
            val = math.round(val * 100) / 100
            Config.set(configKey, val)
            local pct = (val - min_) / (max_ - min_)
            fill.Size     = UDim2.new(pct, 0, 1, 0)
            knob.Position = UDim2.new(pct, 0, 0.5, 0)
            valLabel.Text = format and string.format(format, val) or tostring(val)
        end

        -- Inicializa com valor atual
        updateSlider(Config.get(configKey) or min_)

        knob.InputBegan:Connect(function(inp)
            if inp.UserInputType == Enum.UserInputType.MouseButton1 then dragging = true end
        end)
        Core.UserInputService.InputEnded:Connect(function(inp)
            if inp.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
        end)
        Core.UserInputService.InputChanged:Connect(function(inp)
            if dragging and inp.UserInputType == Enum.UserInputType.MouseMovement then
                local trackAbs = track.AbsolutePosition
                local trackW   = track.AbsoluteSize.X
                local mx       = inp.Position.X - trackAbs.X
                local pct      = math.clamp(mx / trackW, 0, 1)
                local val      = min_ + pct * (max_ - min_)
                updateSlider(val)
            end
        end)

        return card
    end

    -- Seção separadora com título
    local function makeSectionLabel(page, text)
        local f = Instance.new("Frame")
        f.Size = UDim2.new(1,-4,0,20); f.BackgroundTransparency = 1; f.LayoutOrder = #page:GetChildren()
        f.Parent = page
        local l2 = label(f, "── " .. text .. " ──", 9, C.subtext)
        l2.Size = UDim2.new(1,0,1,0)
        return f
    end

    -- ── TAB: Farm ──────────────────────────────────────────────────
    local farmPage = tabPages["Farm"]
    makeSectionLabel(farmPage, "AUTOMAÇÃO")
    makeToggle(farmPage, "Auto Farm",    "🌾", "autoFarm", function(on)
        if on then Farm.start() else Farm.stop() end
    end)
    makeToggle(farmPage, "Auto Haki",    "👁️", "autoHaki")
    makeToggle(farmPage, "Auto Equip",   "🗡️", "autoEquip")
    makeToggle(farmPage, "Auto Boss",    "👑", "autoBoss")

    -- Notificação de boss
    local bossCard = makeCard(farmPage, 28)
    local bossLbl = label(bossCard, "👑 Boss: —", 10, C.subtext)
    bossLbl.Size = UDim2.new(1,-8,1,0); bossLbl.Position = UDim2.new(0,8,0,0)

    makeSectionLabel(farmPage, "TEMPO DE FARM")
    local timeCard = makeCard(farmPage, 28)
    local timeLbl = label(timeCard, "⏱ 00:00:00  |  0 kills", 10, C.subtext)
    timeLbl.Size = UDim2.new(1,-8,1,0); timeLbl.Position = UDim2.new(0,8,0,0)

    -- ── TAB: Combat ────────────────────────────────────────────────
    local combatPage = tabPages["Combat"]
    makeSectionLabel(combatPage, "ATAQUE")
    makeToggle(combatPage, "Fast Attack",  "⚡", "fastAttack")
    makeToggle(combatPage, "Hit Aura",     "💥", "hitAura", function(on)
        if not on then Combat.stopHitAura() end
    end)

    makeSectionLabel(combatPage, "VELOCIDADE")
    makeSlider(combatPage, "Delay Ataque (s)", "attackDelay", 0.01, 0.5, "%.2f s")
    makeSlider(combatPage, "Raio Hit Aura",    "auraRadius",  5, 50, "%.0f st")
    makeSlider(combatPage, "Dist. Ataque",     "attackDist",  2, 20, "%.0f st")

    -- ── TAB: Stats ─────────────────────────────────────────────────
    local statsPage = tabPages["Stats"]
    makeSectionLabel(statsPage, "DISTRIBUIÇÃO")
    makeToggle(statsPage, "Auto Stats", "📈", "autoStats")
    makeSectionLabel(statsPage, "PRIORIDADE (edite CONFIG)")

    local priorityInfo = makeCard(statsPage, 60)
    local pLbl = label(priorityInfo, "1º Melee → 2º Defense\n3º Health → 4º Speed\n(edite Config.statPriority)", 9, C.subtext)
    pLbl.Size = UDim2.new(1,-8,1,0); pLbl.Position = UDim2.new(0,8,0,0)
    pLbl.TextWrapped = true; pLbl.TextYAlignment = Enum.TextYAlignment.Top

    -- ── TAB: Config ────────────────────────────────────────────────
    local cfgPage = tabPages["Config"]
    makeSectionLabel(cfgPage, "MOVIMENTO")
    makeSlider(cfgPage, "Velocidade Voo (st/s)", "flySpeed",  10, 200, "%.0f")
    makeSlider(cfgPage, "Altura acima do mob",   "flyHeight",  1, 15,  "%.0f st")
    makeSlider(cfgPage, "Offset atrás do mob",   "behindOffset", 1, 10, "%.0f st")

    makeSectionLabel(cfgPage, "SISTEMA")
    makeSlider(cfgPage, "Dist. máx. de busca",   "maxMobDist", 200, 5000, "%.0f st")
    makeSlider(cfgPage, "Timeout por mob (s)",   "attackTimeout", 10, 120, "%.0f s")
    makeSlider(cfgPage, "Intervalo quest (s)",   "questInterval", 5, 60, "%.0f s")

    makeSectionLabel(cfgPage, "OUTROS")
    local saveCard = makeCard(cfgPage, 34)
    local saveBtn = Instance.new("TextButton")
    saveBtn.Size = UDim2.new(0.9,0,0,26); saveBtn.Position = UDim2.new(0.05,0,0.5,-13)
    saveBtn.BackgroundColor3 = C.header; saveBtn.BorderSizePixel = 0
    saveBtn.Text = "💾  Salvar Configuração"; saveBtn.TextColor3 = Color3.new(1,1,1)
    saveBtn.TextSize = 11; saveBtn.Font = Enum.Font.GothamBold; saveBtn.Parent = saveCard
    corner(saveBtn, 6)
    saveBtn.MouseButton1Click:Connect(function()
        Config.save()
        Core.notify("SP HUB", "Configuração salva!", 2)
    end)

    -- ── Rodapé ─────────────────────────────────────────────────────
    local footer = label(panel, "🖱️ Arraste  |  SP HUB v4.0", 8, Color3.fromRGB(50,70,110))
    footer.Size = UDim2.new(1,0,0,14); footer.Position = UDim2.new(0,0,1,-15)
    footer.TextXAlignment = Enum.TextXAlignment.Center

    -- ── Thread de atualização da GUI ───────────────────────────────
    task.spawn(function()
        while sg.Parent do
            task.wait(0.3)
            pcall(function()
                -- Status
                lblStatus.Text   = "📌 " .. State.status

                -- Mob e quest
                lblMob.Text      = "🎯 " .. State.currentMob

                -- Nível e ilha
                local lv = Data.getLevel()
                lblLvIsland.Text = string.format("⭐ Lv %d  |  %s", lv, State.currentIsland)

                -- Stats rápidas
                lblFPS.Text   = "FPS " .. Core.getFPS()
                pcall(function() lblPing.Text = "PING " .. Core.getPing() end)
                lblKills.Text = State.killCount .. " kills"
                lblDist.Text  = State.targetDist .. " st"

                -- Boss
                if State.bossDetected then
                    bossLbl.Text      = "👑 BOSS: " .. State.bossName
                    bossLbl.TextColor3 = Color3.fromRGB(255, 200, 0)
                else
                    bossLbl.Text      = "👑 Boss: não detectado"
                    bossLbl.TextColor3 = C.subtext
                end

                -- Tempo de farm
                if State.running and State.farmStart > 0 then
                    local elapsed = tick() - State.farmStart
                    local h = math.floor(elapsed / 3600)
                    local m = math.floor((elapsed % 3600) / 60)
                    local s = math.floor(elapsed % 60)
                    timeLbl.Text = string.format("⏱ %02d:%02d:%02d  |  %d kills", h, m, s, State.killCount)
                end
            end)
        end
    end)

    -- ── Keybind para toggle da GUI ──────────────────────────────────
    Core.UserInputService.InputBegan:Connect(function(inp, gp)
        if gp then return end
        local key = Config.get("toggleKey")
        if inp.KeyCode == Enum.KeyCode[key] then
            panel.Visible = not panel.Visible
        end
    end)

    Core.log("GUI", "HUB carregado com sucesso")
    return sg
end)()

-- ═══════════════════════════════════════════════════════════════════
--  INICIALIZAÇÃO FINAL
-- ═══════════════════════════════════════════════════════════════════
Core.notify("⚓ SP HUB v4.0", "Script carregado! Use ] para ocultar/mostrar.", 5)
Core.log("INIT", "=== Sailor Piece HUB v4.0 ativo ===")
Core.log("INIT", "Nível detectado: " .. Data.getLevel())
Core.log("INIT", "Cache NPCs: " .. Cache.count())
