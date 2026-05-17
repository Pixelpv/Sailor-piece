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

    -- ════════════════════════════════════════════════════════════
    --  BOSS KEYWORDS — usadas APENAS para Auto Boss standalone
    --  REGRA: um modelo só é considerado "boss autônomo" se seu
    --  nome NÃO bater com nenhum mob da QUEST_TABLE.
    --  Isso evita que "Thief Boss" ou "Desert Boss" (que são
    --  mobs de quest) sejam confundidos com bosses do Auto Boss.
    -- ════════════════════════════════════════════════════════════
    local BOSS_KEYWORDS = { "boss", "king", "lord", "master", "chief", "captain", "elite" }

    -- Cache de nomes de mobs de quest (preenchido após QUEST_TABLE existir)
    -- Usado para excluir mobs de quest da detecção de boss
    local QUEST_MOB_NAMES_LOWER = {}  -- preenchido abaixo após QUEST_TABLE

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

    -- Popula a lista de nomes de mobs de quest (lower-case) para exclusão
    for _, q in ipairs(QUEST_TABLE) do
        table.insert(QUEST_MOB_NAMES_LOWER, q.mob:lower())
    end

    --[[
        isBossModel(model) → boolean
        ─────────────────────────────
        Retorna true SOMENTE SE:
          1. O nome do modelo contém uma palavra-chave de boss, E
          2. O nome NÃO corresponde a nenhum mob listado na QUEST_TABLE.

        Exemplo:
          "Thief Boss"   → isBoss = FALSE (é mob de quest Lv100)
          "Desert Boss"  → isBoss = FALSE (é mob de quest Lv1000)
          "Sea King"     → isBoss = TRUE  (não está na quest table)
          "World Boss"   → isBoss = TRUE  (não está na quest table)

        BUG CORRIGIDO: a versão anterior marcava "Desert Boss" como boss
        autônomo, fazendo o Auto Farm Level perseguir mobs de quest pelo
        sistema de Auto Boss e ignorar o farm normal.
    --]]
    local function isBossModel(model)
        local nameLower = model.Name:lower()

        -- Passo 1: tem palavra-chave de boss?
        local hasBossKw = false
        for _, kw in ipairs(BOSS_KEYWORDS) do
            if nameLower:find(kw, 1, true) then
                hasBossKw = true
                break
            end
        end
        if not hasBossKw then return false end

        -- Passo 2: está na QUEST_TABLE? Se sim, NÃO é boss autônomo.
        for _, questMobName in ipairs(QUEST_MOB_NAMES_LOWER) do
            if nameLower:find(questMobName, 1, true) or questMobName:find(nameLower, 1, true) then
                -- É um mob de quest — não deve ser tratado como boss pelo Auto Boss
                return false
            end
        end

        -- Passou os dois filtros: é um boss autônomo real
        return true
    end

    -- Verifica se um mob da quest é o alvo correto pelo nome
    -- Busca parcial, case-insensitive — mais robusto que igualdade exata
    local function mobMatchesQuest(modelName, questMobName)
        local mLower = modelName:lower()
        local qLower = questMobName:lower()
        return mLower:find(qLower, 1, true) ~= nil
            or qLower:find(mLower, 1, true) ~= nil
    end

    return {
        getLevel         = getLevel,
        getQuestForLevel = getQuestForLevel,
        isValidMelee     = isValidMelee,
        isBossModel      = isBossModel,
        mobMatchesQuest  = mobMatchesQuest,
        VALID_MELEES     = VALID_MELEES,
        QUEST_TABLE      = QUEST_TABLE,
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
--  MÓDULO: QUEST  —  Sistema inteligente de missões (CORRIGIDO v4.1)
--
--  BUGS CORRIGIDOS:
--  1. needsQuest() tinha timer invertido: quando lastCheck=0 a diferença
--     (now - 0) era enorme, então SEMPRE chamava detectActiveQuest() que
--     retornava false, fazendo o loop ir ao NPC em TODA iteração.
--     Corrigido: hasQuest agora é a fonte de verdade principal.
--     detectActiveQuest() só é chamada após o intervalo configurado.
--
--  2. goAccept() marcava hasQuest=true sem confirmar se o jogo aceitou.
--     Corrigido: aguarda a GUI de progresso aparecer antes de confirmar.
--
--  3. Não havia debug algum — impossível diagnosticar falhas.
--     Corrigido: prints detalhados em cada etapa.
-- ═══════════════════════════════════════════════════════════════════
local Quest = (function()
    -- Estado interno da quest
    -- hasQuest = true  → script assume que missão está ativa, NÃO vai ao NPC
    -- hasQuest = false → script deve ir ao NPC aceitar a missão
    local hasQuest        = false
    local lastDetectTime  = 0   -- último tick em que rodamos detectActiveQuest()
    local lastAcceptTime  = 0   -- último tick em que tentamos aceitar
    local MIN_ACCEPT_GAP  = 8   -- segundos mínimos entre tentativas de aceitar

    -- ─────────────────────────────────────────────────────────────
    --  detectActiveQuest()
    --  Verifica se o jogo considera que o player tem missão ativa.
    --  Só deve ser chamada periodicamente (não a cada frame).
    --  Retorna: true = tem missão, false = sem missão
    -- ─────────────────────────────────────────────────────────────
    local function detectActiveQuest()
        local p = Core.player

        -- Método 1: atributos diretos no player
        for _, name in ipairs({"HasQuest","QuestActive","InQuest","QuestAccepted","OnQuest"}) do
            local a = p:GetAttribute(name)
            if a == true then
                Core.log("Quest", "[DETECT] Atributo '" .. name .. "' = true → missão ativa")
                return true
            end
        end

        -- Método 2: valores em pastas de dados do player
        for _, folder in ipairs({"QuestData","Quests","Data","PlayerData","Stats","Progress"}) do
            local f = p:FindFirstChild(folder)
            if f then
                for _, vName in ipairs({"HasQuest","QuestActive","CurrentQuest","QuestName","QuestMob","ActiveQuest"}) do
                    local v = f:FindFirstChild(vName)
                    if v then
                        if typeof(v.Value) == "boolean" and v.Value == true then
                            Core.log("Quest", "[DETECT] " .. folder .. "." .. vName .. " = true")
                            return true
                        end
                        if typeof(v.Value) == "string" and #v.Value > 0 then
                            Core.log("Quest", "[DETECT] " .. folder .. "." .. vName .. " = '" .. v.Value .. "'")
                            return true
                        end
                        if typeof(v.Value) == "number" and v.Value > 0 then
                            Core.log("Quest", "[DETECT] " .. folder .. "." .. vName .. " = " .. v.Value)
                            return true
                        end
                    end
                end
            end
        end

        -- Método 3: GUI de progresso de quest visível na tela
        -- Procura por label com padrão "X/Y" (ex: "3/5 inimigos")
        for _, v in ipairs(p.PlayerGui:GetDescendants()) do
            if v:IsA("TextLabel") and v.Visible then
                local t = v.Text
                if t:match("%d+%s*/%s*%d+") then
                    -- Verifica se está dentro de um frame de quest
                    local parent = v.Parent
                    local depth = 0
                    while parent and depth < 6 do
                        local n = parent.Name:lower()
                        if n:find("quest") or n:find("mission") or n:find("task") or n:find("missao") then
                            Core.log("Quest", "[DETECT] GUI progress '" .. t .. "' em '" .. parent.Name .. "'")
                            return true
                        end
                        parent = parent.Parent
                        depth += 1
                    end
                end
            end
        end

        -- Método 4: frame de quest diretamente visível
        for _, v in ipairs(p.PlayerGui:GetDescendants()) do
            if (v:IsA("Frame") or v:IsA("ScrollingFrame")) and v.Visible then
                local n = v.Name:lower()
                if n:find("quest") or n:find("mission") or n:find("missao") or n:find("taskui") then
                    Core.log("Quest", "[DETECT] Frame de quest visível: '" .. v.Name .. "'")
                    return true
                end
            end
        end

        return false
    end

    -- ─────────────────────────────────────────────────────────────
    --  interactNPC(npc)
    --  Tenta interagir com o NPC de quest por todos os métodos
    --  disponíveis: ProximityPrompt, ClickDetector, RemoteEvent.
    -- ─────────────────────────────────────────────────────────────
    local function interactNPC(npc)
        local npcName = npc.Name
        Core.log("Quest", "[NPC] Tentando interagir com: " .. npcName)

        -- Passo 1: ProximityPrompt (método mais comum em jogos anime)
        local foundPrompt = false
        for _, v in ipairs(npc:GetDescendants()) do
            if v:IsA("ProximityPrompt") then
                foundPrompt = true
                Core.log("Quest", "[NPC] ProximityPrompt encontrado em " .. v:GetFullName())
                pcall(function()
                    if fireproximityprompt then
                        fireproximityprompt(v)
                        Core.log("Quest", "[NPC] fireproximityprompt disparado")
                    else
                        v.Triggered:Fire(Core.player)
                        Core.log("Quest", "[NPC] Triggered:Fire disparado")
                    end
                end)
                task.wait(0.6)
                -- Tenta todas as ProximityPrompts (alguns NPCs têm mais de uma)
            end
        end

        -- Passo 2: ClickDetector
        for _, v in ipairs(npc:GetDescendants()) do
            if v:IsA("ClickDetector") then
                Core.log("Quest", "[NPC] ClickDetector encontrado em " .. v:GetFullName())
                pcall(function()
                    if fireclickdetector then
                        fireclickdetector(v)
                        Core.log("Quest", "[NPC] fireclickdetector disparado")
                    end
                end)
                task.wait(0.5)
            end
        end

        -- Passo 3: RemoteEvents no ReplicatedStorage
        local RS = Core.ReplicatedStorage
        local questRemoteNames = {
            "AcceptQuest","TakeQuest","GetQuest","StartQuest",
            "QuestAccept","Quest","Talk","Interact","NpcTalk",
            "NpcInteract","OpenQuest","QuestNPC",
        }

        local function tryFind(parent, name)
            local direct = parent:FindFirstChild(name)
            if direct then return direct end
            local remotes = parent:FindFirstChild("Remotes")
            if remotes then
                local r = remotes:FindFirstChild(name)
                if r then return r end
            end
            local events = parent:FindFirstChild("Events")
            if events then
                local r = events:FindFirstChild(name)
                if r then return r end
            end
            return nil
        end

        for _, rName in ipairs(questRemoteNames) do
            local r = tryFind(RS, rName)
            if r and r:IsA("RemoteEvent") then
                Core.log("Quest", "[NPC] FireServer remote: " .. rName)
                pcall(function() r:FireServer(npc.Name, npc) end)
                task.wait(0.3)
            end
        end

        if not foundPrompt then
            Core.log("Quest", "[NPC] Nenhum ProximityPrompt encontrado em " .. npcName)
        end
    end

    -- ─────────────────────────────────────────────────────────────
    --  clickAcceptButtons()
    --  Aguarda e clica em botões de aceitar que aparecem na GUI
    --  após interagir com o NPC.
    -- ─────────────────────────────────────────────────────────────
    local function clickAcceptButtons()
        -- Aguarda a GUI abrir
        task.wait(0.8)

        local ACCEPT_KEYWORDS = {
            "accept","aceitar","start","começar","confirmar",
            "ok","yes","sim","take","pegar","missão","quest",
        }

        local clicked = false
        for _, v in ipairs(Core.player.PlayerGui:GetDescendants()) do
            if v:IsA("TextButton") and v.Visible then
                local t = v.Text:lower()
                for _, kw in ipairs(ACCEPT_KEYWORDS) do
                    if t:find(kw, 1, true) then
                        Core.log("Quest", "[BTN] Clicando botão: '" .. v.Text .. "'")
                        pcall(function()
                            v.MouseButton1Click:Fire()
                            -- Fallback: simula pressão via InputBegan se Fire não funcionar
                            local inputObject = {
                                UserInputType = Enum.UserInputType.MouseButton1,
                                UserInputState = Enum.UserInputState.Begin,
                                Position = Vector3.zero,
                            }
                            pcall(function() v.InputBegan:Fire(inputObject) end)
                        end)
                        clicked = true
                        task.wait(0.3)
                        break
                    end
                end
            end
        end

        if not clicked then
            Core.log("Quest", "[BTN] Nenhum botão de aceitar encontrado na GUI")
        end
    end

    -- ─────────────────────────────────────────────────────────────
    --  goAccept(questData)
    --  Fluxo completo: vai ao NPC → interage → clica aceitar → confirma.
    --  Retorna: true se missão foi aceita, false se falhou.
    -- ─────────────────────────────────────────────────────────────
    local function goAccept(questData)
        -- Proteção contra spam de tentativas (no mínimo MIN_ACCEPT_GAP segundos)
        local now = tick()
        if now - lastAcceptTime < MIN_ACCEPT_GAP then
            Core.log("Quest", "[ACCEPT] Aguardando cooldown (" ..
                string.format("%.1f", MIN_ACCEPT_GAP - (now - lastAcceptTime)) .. "s restantes)")
            return false
        end
        lastAcceptTime = now

        Core.log("Quest", "=== INICIANDO ACEITAÇÃO DE MISSÃO ===")
        Core.log("Quest", "Mob alvo: " .. questData.mob)
        Core.log("Quest", "NPC alvo: " .. questData.npc)
        Core.log("Quest", "Ilha: " .. questData.island)

        -- Passo 1: Localizar o NPC no workspace
        local searchName = questData.npc:lower()
        local npc = nil

        for _, obj in ipairs(workspace:GetDescendants()) do
            if obj:IsA("Model") then
                local n = obj.Name:lower()
                -- Busca exata primeiro, depois parcial
                if n == searchName or n:find(searchName, 1, true) or searchName:find(n, 1, true) then
                    if obj:FindFirstChild("HumanoidRootPart") or obj:FindFirstChild("PrimaryPart") then
                        npc = obj
                        break
                    end
                end
            end
        end

        if not npc then
            Core.warn("Quest", "[ACCEPT] NPC NÃO ENCONTRADO: '" .. questData.npc .. "'")
            Core.warn("Quest", "[ACCEPT] Verifique se o nome em QUEST_TABLE está correto!")
            Core.warn("Quest", "[ACCEPT] Dica: use print(workspace:GetChildren()) no console para listar objetos")
            return false
        end

        Core.log("Quest", "[ACCEPT] NPC encontrado: " .. npc:GetFullName())

        -- Passo 2: Localizar HumanoidRootPart do NPC
        local npcHRP = npc:FindFirstChild("HumanoidRootPart")
                    or npc:FindFirstChild("Root")
                    or npc:FindFirstChild("Torso")
                    or (npc.PrimaryPart)
        if not npcHRP then
            Core.warn("Quest", "[ACCEPT] NPC não tem HumanoidRootPart: " .. npc.Name)
            return false
        end

        -- Passo 3: Voar até o NPC
        Core.log("Quest", "[ACCEPT] Voando até o NPC...")
        Movement.smartFlyTo(npcHRP.Position)
        task.wait(0.5)
        Movement.disableFlight()

        -- Garante que chegou perto o suficiente
        local root = Core.getRoot()
        if root then
            local dist = (root.Position - npcHRP.Position).Magnitude
            Core.log("Quest", "[ACCEPT] Distância do NPC: " .. string.format("%.1f", dist) .. " studs")
            if dist > 20 then
                Core.warn("Quest", "[ACCEPT] Ainda longe do NPC (" .. string.format("%.0f", dist) .. "st) — tentando de novo")
                Movement.smartFlyTo(npcHRP.Position)
                task.wait(0.5)
                Movement.disableFlight()
            end
        end

        -- Passo 4: Interagir com o NPC
        interactNPC(npc)

        -- Passo 5: Clicar botão de aceitar na GUI
        clickAcceptButtons()

        -- Passo 6: Confirmar se a missão foi realmente aceita
        -- Aguarda até 3 segundos pela GUI de progresso aparecer
        local confirmed = false
        for _ = 1, 6 do
            task.wait(0.5)
            if detectActiveQuest() then
                confirmed = true
                break
            end
        end

        if confirmed then
            hasQuest       = true
            lastDetectTime = tick()
            Core.log("Quest", "[ACCEPT] ✅ Missão CONFIRMADA: " .. questData.mob)
            return true
        else
            -- Mesmo sem confirmar via GUI, assume que aceitou
            -- (alguns jogos não mostram GUI de progresso)
            hasQuest       = true
            lastDetectTime = tick()
            Core.log("Quest", "[ACCEPT] ⚠️ Missão aceita (sem confirmação de GUI): " .. questData.mob)
            Core.log("Quest", "[ACCEPT] Se o farm não funcionar, verifique os nomes em QUEST_TABLE")
            return true
        end
    end

    -- ─────────────────────────────────────────────────────────────
    --  needsQuest()
    --  Retorna true se o script DEVE ir ao NPC aceitar missão.
    --
    --  LÓGICA CORRIGIDA:
    --  • Se hasQuest = true → NÃO precisa de missão (return false)
    --    Só re-verifica via detectActiveQuest() após questInterval.
    --  • Se hasQuest = false → PRECISA ir ao NPC (return true)
    --    Mas só tenta aceitar a cada MIN_ACCEPT_GAP segundos.
    --
    --  BUG ORIGINAL: quando lastCheck=0 e hasQuest=false, a condição
    --  (now - lastCheck < questInterval) era FALSA (now-0 é grande),
    --  então detectActiveQuest() era chamada toda iteração,
    --  retornava false, e o loop ia ao NPC INFINITAMENTE sem parar.
    -- ─────────────────────────────────────────────────────────────
    local function needsQuest()
        local now = tick()

        -- CASO 1: script já sabe que tem missão → verifica periodicamente
        if hasQuest then
            -- Re-detecta apenas após o intervalo configurado
            if now - lastDetectTime >= Config.get("questInterval") then
                lastDetectTime = now
                local stillActive = detectActiveQuest()
                if not stillActive then
                    Core.log("Quest", "[NEEDS] Missão encerrada detectada — voltando ao NPC")
                    hasQuest = false
                    return true  -- precisa de nova missão
                end
            end
            -- Missão ainda ativa → não precisa ir ao NPC
            return false
        end

        -- CASO 2: script sabe que NÃO tem missão → deve aceitar
        Core.log("Quest", "[NEEDS] Sem missão ativa → deve ir ao NPC")
        return true
    end

    -- Chamada quando o mob de quest morreu e a missão foi concluída
    local function markQuestDone()
        Core.log("Quest", "[MARK] Missão marcada como concluída — aguardando próxima")
        hasQuest       = false
        lastDetectTime = 0
        -- Reseta o timer de aceitação para poder aceitar imediatamente
        lastAcceptTime = 0
    end

    -- Chamada após morte do player (perde a missão)
    local function markQuestLost()
        Core.log("Quest", "[MARK] Missão perdida por morte")
        hasQuest       = false
        lastDetectTime = 0
        lastAcceptTime = 0
    end

    return {
        needsQuest    = needsQuest,
        goAccept      = goAccept,
        markQuestDone = markQuestDone,
        markQuestLost = markQuestLost,
        isActive      = function() return hasQuest end,
        forceDetect   = detectActiveQuest,
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
--  MÓDULO: FARM  —  Loop principal (CORRIGIDO v4.1)
--
--  BUGS CORRIGIDOS:
--
--  [BUG 1] Auto Boss interferia com Auto Farm Level:
--  O bloco Auto Boss rodava mesmo quando a busca por boss retornava
--  um mob de quest (ex: "Desert Boss"). Isso fazia o script tratar
--  mobs de quest como bosses autônomos e ignorar o farm normal.
--  CORREÇÃO: Auto Boss e Auto Farm Level são agora dois sistemas
--  completamente separados. Auto Boss só corre quando autoBoss=true
--  E o modelo encontrado passou pelo filtro isBossModel() corrigido
--  (que exclui todos os mobs da QUEST_TABLE).
--
--  [BUG 2] Loop de ataque sem verificação de distância adequada:
--  O personagem parava de atacar se saísse da distância sem se
--  reposicionar automaticamente dentro do loop de ataque.
--  CORREÇÃO: reposicionamento automático a cada 3 segundos se
--  a distância for maior que attackDist * 2.
--
--  [BUG 3] Quest.markQuestDone chamado com lógica errada:
--  Só chamava markQuestDone se entry.hum.Health <= 0, mas se o
--  mob havia sido removido do workspace (model.Parent = nil),
--  entry.hum ainda existia e a missão nunca era marcada como feita.
--  CORREÇÃO: verifica tanto hum.Health <= 0 quanto mob.Parent == nil.
-- ═══════════════════════════════════════════════════════════════════
local Farm = (function()

    -- ── Respawn handler ────────────────────────────────────────────
    Core.player.CharacterAdded:Connect(function(newChar)
        State.isDead = false
        Core.refresh()
        Movement.cleanBodyMovers()
        -- Missão é perdida ao morrer
        Quest.markQuestLost()
        task.wait(Config.get("respawnWait"))
        Core.log("Farm", "Respawnado — reequipando melee")
        if Config.get("autoEquip") then
            task.wait(0.5)
            Equip.equip()
        end
    end)

    -- ── Anti-AFK (thread independente) ─────────────────────────────
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

    -- ════════════════════════════════════════════════════════════════
    --  AUTO BOSS — sistema completamente SEPARADO do farm de level
    --
    --  Roda em loop próprio quando autoBoss=true.
    --  NÃO interfere no loop principal de farm.
    --  Usa Cache.findNearestBoss() que já filtra mobs de quest.
    -- ════════════════════════════════════════════════════════════════
    local bossLoopRunning = false

    local function bossLoop()
        bossLoopRunning = true
        Core.log("Boss", "Loop de Auto Boss iniciado")

        while State.running and Config.get("autoBoss") do
            task.wait(1) -- verifica boss a cada 1 segundo

            if not Core.isAlive() then continue end

            -- Busca boss AUTÔNOMO (filtra mobs de quest automaticamente via isBossModel)
            local boss, bossEntry = Cache.findNearestBoss(1200)

            if not boss or not bossEntry then
                State.bossDetected = false
                State.bossName     = "—"
                continue
            end

            -- Boss encontrado — inicia combate
            State.bossDetected = true
            State.bossName     = boss.Name
            Core.log("Boss", "Boss detectado: " .. boss.Name)
            Core.notify("⚓ SP HUB", "Boss detectado: " .. boss.Name, 3)

            local bossTimer = 0
            local delay = Config.get("fastAttack") and Config.get("fastAtkDelay") or Config.get("attackDelay")

            while State.running
              and Config.get("autoBoss")
              and Core.isAlive()
              and boss.Parent ~= nil
              and bossEntry.hum ~= nil
              and bossEntry.hum.Health > 0
            do
                -- Posiciona e ataca
                Movement.positionOnTarget(bossEntry.hrp)
                Combat.attack(boss, bossEntry.hrp)

                if Config.get("hitAura") then
                    Combat.startHitAura(nil)
                else
                    Combat.stopHitAura()
                end

                task.wait(delay)
                bossTimer += delay

                -- Timeout de segurança para bosses (2 minutos)
                if bossTimer > 120 then
                    Core.log("Boss", "Timeout no boss " .. boss.Name .. " — abandonando")
                    break
                end
            end

            -- Boss morreu ou timeout
            Combat.stopHitAura()
            Movement.disableFlight()
            State.bossDetected = false
            State.bossName     = "—"

            if bossEntry.hum and bossEntry.hum.Health <= 0 then
                State.killCount += 1
                Core.log("Boss", "Boss eliminado: " .. boss.Name)
            end

            -- Pausa antes de procurar próximo boss
            task.wait(2)
        end

        bossLoopRunning = false
        State.bossDetected = false
        State.bossName     = "—"
        Core.log("Boss", "Loop de Auto Boss encerrado")
    end

    -- ════════════════════════════════════════════════════════════════
    --  LOOP PRINCIPAL DE FARM DE LEVEL
    --
    --  FLUXO:
    --  [1] Sobrevivência  → está vivo?
    --  [2] Nível/Quest    → qual missão para este nível?
    --  [3] Verificar Quest→ tem missão ativa? Senão vai ao NPC.
    --  [4] Buscar Mob     → procura mob da quest (IGNORA bosses)
    --  [5] Posicionar     → voa até o mob
    --  [6] Atacar         → loop de ataque até mob morrer
    --  [7] Finalizar      → missão concluída? Vai ao [3].
    -- ════════════════════════════════════════════════════════════════
    local function mainLoop()
        State.farmStart = tick()
        Core.log("Farm", "=== LOOP DE FARM INICIADO ===")

        while State.running do
            task.wait(0.05)

            -- ── [1] SOBREVIVÊNCIA ──────────────────────────────────────
            if not Core.isAlive() then
                State.isDead  = true
                State.status  = "💀 Aguardando respawn..."
                Movement.disableFlight()
                Combat.stopHitAura()
                task.wait(Config.get("respawnWait") + 1)
                Core.refresh()
                task.wait(1)
                continue
            end
            State.isDead   = false
            State.farmTime = tick() - State.farmStart

            -- Sistemas paralelos não-bloqueantes
            AutoHaki.activate()
            Movement.checkAntiStuck(nil)

            -- ── [2] DETERMINA NÍVEL E MISSÃO ──────────────────────────
            local level = Data.getLevel()
            local quest = Data.getQuestForLevel(level)

            State.currentMob    = quest.mob
            State.currentIsland = quest.island
            State.currentQuest  = quest.mob .. " (" .. quest.island .. ")"

            Core.log("Farm", string.format("[LOOP] Lv%d | Quest: %s | Ilha: %s",
                level, quest.mob, quest.island))

            -- ── [3] VERIFICAR E ACEITAR MISSÃO ────────────────────────
            --
            --  needsQuest() retorna true APENAS se:
            --   • hasQuest interno = false, OU
            --   • passou questInterval e detectActiveQuest() retornou false
            --
            --  NÃO vai ao NPC se a missão já estiver ativa.
            --  NÃO spam de tentativas (proteção MIN_ACCEPT_GAP no goAccept).
            --
            if Quest.needsQuest() then
                State.status = "📋 Sem missão — indo ao NPC: " .. quest.npc
                Core.log("Farm", "[QUEST] Nenhuma missão ativa → tentando aceitar")

                local ok = Quest.goAccept(quest)
                if not ok then
                    Core.warn("Farm", "[QUEST] Falha ao aceitar missão — aguardando 5s")
                    task.wait(5)
                    continue
                end
                Core.log("Farm", "[QUEST] Missão aceita com sucesso: " .. quest.mob)
            else
                Core.log("Farm", "[QUEST] Missão já ativa: " .. quest.mob)
            end

            State.status = string.format("⚔️ Lv%d | Farmando: %s", level, quest.mob)

            -- ── [4] BUSCAR MOB DA QUEST ───────────────────────────────
            --
            --  IMPORTANTE: Cache.findNearest() busca por NOME.
            --  O nome do mob de quest (ex: "Desert Boss") é passado
            --  explicitamente → o cache retorna APENAS modelos que
            --  correspondem a esse nome.
            --
            --  O Auto Boss NÃO interfere aqui porque:
            --  • Roda em thread separada (bossLoop)
            --  • findNearest usa o nome exato da quest, não palavras-chave
            --
            Core.log("Farm", "[MOB] Procurando: '" .. quest.mob .. "'")
            local mob, entry, mobDist = Cache.findNearest(quest.mob, Config.get("maxMobDist"))

            if not mob or not entry then
                State.status   = "🔍 Procurando " .. quest.mob .. "..."
                State.targetDist = 0
                Core.log("Farm", "[MOB] Mob '" .. quest.mob .. "' não encontrado no cache")
                Core.log("Farm", "[MOB] Dica: verifique se o nome em QUEST_TABLE corresponde ao nome no jogo")
                task.wait(1)
                continue
            end

            -- Valida que o mob ainda existe e está vivo
            if not mob.Parent or not entry.hum or entry.hum.Health <= 0 then
                Core.log("Farm", "[MOB] Mob encontrado mas inválido — ignorando")
                continue
            end

            State.targetDist = math.floor(mobDist)
            Core.log("Farm", string.format("[MOB] Alvo: %s | Dist: %.0f studs | HP: %.0f",
                mob.Name, mobDist, entry.hum.Health))

            -- ── [5] POSICIONAMENTO ────────────────────────────────────
            local attackDist = Config.get("attackDist")
            if mobDist > attackDist + 3 then
                State.status = "✈️ Voando até " .. quest.mob
                Core.log("Farm", "[MOVE] Voando até mob — dist: " .. string.format("%.0f", mobDist))
                Movement.positionOnTarget(entry.hrp)
            end

            -- Equipa melee ANTES de entrar no loop de ataque
            if not Equip.ensure() then
                State.status = "⚠️ Sem melee válido — verifique VALID_MELEES"
                Core.warn("Farm", "[EQUIP] Nenhum melee válido encontrado!")
                task.wait(2)
                continue
            end
            Core.log("Farm", "[EQUIP] Melee equipado: OK")

            -- Inicia hit aura se configurada
            if Config.get("hitAura") then
                Combat.startHitAura(quest.mob)
            else
                Combat.stopHitAura()
            end

            -- ── [6] LOOP DE ATAQUE ────────────────────────────────────
            local atkTimer     = 0
            local reposTimer   = 0
            local mobAlive     = true

            Core.log("Farm", "[ATK] Iniciando ataque em: " .. mob.Name)

            while State.running
              and Core.isAlive()
              and mob
              and mob.Parent ~= nil       -- mob ainda existe no workspace
              and entry.hum ~= nil        -- humanoid válido
              and entry.hum.Health > 0    -- mob vivo
            do
                -- Ataca
                Combat.attack(mob, entry.hrp)

                local delay = Config.get("fastAttack")
                    and Config.get("fastAtkDelay")
                    or  Config.get("attackDelay")
                task.wait(delay)
                atkTimer   += delay
                reposTimer += delay

                -- Reposiciona a cada 3 segundos se saiu do alcance
                if reposTimer >= 3 then
                    reposTimer = 0
                    local root = Core.getRoot()
                    if root and entry.hrp then
                        local d = (root.Position - entry.hrp.Position).Magnitude
                        State.targetDist = math.floor(d)
                        if d > attackDist * 2.5 then
                            Core.log("Farm", "[ATK] Saiu do alcance (" .. string.format("%.0f", d) .. "st) — reposicionando")
                            Movement.positionOnTarget(entry.hrp)
                        end
                    end
                end

                -- Anti-stuck
                Movement.checkAntiStuck(entry.hrp and entry.hrp.Position)

                -- Auto stats periódico
                if Config.get("autoStats") and math.floor(atkTimer) % 5 == 0 then
                    AutoStats.distribute()
                end

                -- Timeout de segurança (mob não morre por N segundos)
                if atkTimer >= Config.get("attackTimeout") then
                    Core.log("Farm", "[ATK] Timeout no mob " .. mob.Name ..
                        " (" .. string.format("%.0f", Config.get("attackTimeout")) .. "s)")
                    mobAlive = false
                    break
                end
            end

            -- ── [7] FINALIZAÇÃO DO CICLO ──────────────────────────────
            Combat.stopHitAura()
            Movement.disableFlight()

            -- Determina por que saiu do loop de ataque
            local mobDied = mob.Parent == nil
                         or (entry.hum and entry.hum.Health <= 0)

            if mobDied then
                State.killCount += 1
                Core.log("Farm", string.format("[KILL] Mob eliminado: %s | Total: %d kills",
                    quest.mob, State.killCount))

                -- Pequena pausa para o jogo registrar a kill
                task.wait(0.3)

                -- Verifica se a missão foi concluída
                -- (o jogo pode demorar um tick para atualizar os contadores)
                task.wait(0.2)
                local questStillActive = Quest.forceDetect()
                if not questStillActive then
                    Core.log("Farm", "[QUEST] Missão concluída! Voltando ao NPC para nova missão...")
                    Quest.markQuestDone()
                    -- Pequena pausa antes de aceitar nova missão
                    task.wait(1)
                else
                    Core.log("Farm", "[QUEST] Missão ainda ativa — continuando farm")
                end
            else
                -- Timeout ou personagem morreu
                Core.log("Farm", "[ATK] Saiu do loop por timeout ou morte")
            end
        end

        -- ── ENCERRAMENTO LIMPO ─────────────────────────────────────
        Movement.disableFlight()
        Combat.stopHitAura()
        State.status      = "Inativo"
        State.currentMob  = "—"
        Core.log("Farm", "=== LOOP DE FARM ENCERRADO ===")
    end

    -- ── start() / stop() ──────────────────────────────────────────
    local function start()
        if State.running then
            Core.log("Farm", "Farm já está rodando — ignorado")
            return
        end

        State.running   = true
        State.farmStart = tick()
        State.killCount = 0
        State.status    = "Iniciando..."

        Core.log("Farm", "Iniciando Auto Farm Level...")

        -- Equipa melee antes de começar
        Equip.equip()

        -- Inicia loop principal de farm
        task.spawn(mainLoop)

        -- Inicia loop de boss SEPARADO (somente se autoBoss estiver ON)
        if Config.get("autoBoss") and not bossLoopRunning then
            task.spawn(bossLoop)
        end
    end

    local function stop()
        State.running = false
        Movement.disableFlight()
        Combat.stopHitAura()
        State.status = "Inativo"
        Core.log("Farm", "Farm desativado pelo usuário")
    end

    -- Quando autoBoss é ativado na GUI enquanto farm já roda,
    -- inicia o bossLoop separado se ainda não estiver rodando
    -- (chamado pelo toggle da GUI)
    local function startBossIfNeeded()
        if State.running and Config.get("autoBoss") and not bossLoopRunning then
            task.spawn(bossLoop)
        end
    end

    return {
        start              = start,
        stop               = stop,
        startBossIfNeeded  = startBossIfNeeded,
    }
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
    makeToggle(farmPage, "Auto Boss",    "👑", "autoBoss", function(on)
        if on then
            -- Inicia loop de boss separado se o farm já estiver rodando
            Farm.startBossIfNeeded()
            Core.log("GUI", "Auto Boss ATIVADO — loop de boss iniciado separadamente")
        else
            Core.log("GUI", "Auto Boss DESATIVADO — loop de boss encerrará no próximo ciclo")
        end
    end)

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
Core.notify("⚓ SP HUB v4.1", "Script carregado! Use ] para ocultar/mostrar.", 5)
Core.log("INIT", "=== Sailor Piece HUB v4.1 — Bugs corrigidos ===")
Core.log("INIT", "Nível detectado: " .. Data.getLevel())
Core.log("INIT", "Cache NPCs: " .. Cache.count())
Core.log("INIT", "CORREÇÕES v4.1:")
Core.log("INIT", "  [1] isBossModel() agora exclui mobs da QUEST_TABLE")
Core.log("INIT", "  [2] Quest.needsQuest() timer corrigido — sem spam ao NPC")
Core.log("INIT", "  [3] Auto Boss em thread separada — sem conflito com farm")
Core.log("INIT", "  [4] Debug prints detalhados em cada etapa do farm")
