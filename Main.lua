--[[
    ╔══════════════════════════════════════════════════════════╗
    ║          SAILOR PIECE - AUTO FARM SCRIPT v2.0            ║
    ║         Desenvolvido para uso educacional                ║
    ╚══════════════════════════════════════════════════════════╝

    COMO PERSONALIZAR:
    ━━━━━━━━━━━━━━━━━
    • Nomes de mobs      → Tabela "QUEST_TABLE" (linha ~60)
    • Nomes de NPCs      → Campo "questNpc" em cada entrada da tabela
    • Distância          → CONFIG.ATTACK_DISTANCE (linha ~40)
    • Velocidade Tween   → CONFIG.FLY_SPEED (linha ~41)
    • Método de ataque   → Função attackTarget() (linha ~280)
    • Melees válidos     → Tabela VALID_MELEES (linha ~50)
--]]

-- ════════════════════════════════════════════════
--               SERVIÇOS ROBLOX
-- ════════════════════════════════════════════════
local Players            = game:GetService("Players")
local RunService         = game:GetService("RunService")
local TweenService       = game:GetService("TweenService")
local UserInputService   = game:GetService("UserInputService")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local StarterGui         = game:GetService("StarterGui")

local player   = Players.LocalPlayer
local char     = player.Character or player.CharacterAdded:Wait()
local humanoid = char:WaitForChild("Humanoid")
local hrp      = char:WaitForChild("HumanoidRootPart")

-- ════════════════════════════════════════════════
--          CONFIGURAÇÕES PRINCIPAIS
-- ════════════════════════════════════════════════
local CONFIG = {
    ATTACK_DISTANCE   = 6,       -- Distância para atacar (studs)
    FLY_SPEED         = 0.35,    -- Tempo do Tween de voo (segundos, menor = mais rápido)
    FLY_HEIGHT        = 3,       -- Altura acima do inimigo ao voar
    LOOP_DELAY        = 0.05,    -- Delay do loop principal
    ATTACK_DELAY      = 0.1,     -- Delay entre ataques
    STUCK_TIMEOUT     = 5,       -- Segundos para detectar "preso"
    RESPAWN_WAIT      = 4,       -- Segundos para aguardar respawn
    AFK_INTERVAL      = 60,      -- Intervalo anti-AFK (segundos)
    MAX_DIST_TO_MOB   = 2000,    -- Distância máxima para considerar um mob
    FAST_ATTACK_DELAY = 0.01,    -- Delay do fast attack
}

-- ════════════════════════════════════════════════
--           MELEES VÁLIDOS PARA EQUIPAR
-- ════════════════════════════════════════════════
-- ⚠️ Adicione ou remova nomes conforme os itens do jogo
local VALID_MELEES = {
    "Cosmic Being",
    "Moon Slayer",
    "The World",
    "Spirit Warrior",
    "Strongest Shinobi",
    "Blessed Maiden",
    "Corrupted Excalibur",
    "Gilgamesh",
    "Strongest of Today",
    "Anos",
    "Strongest in History",
    "Vampire King",
    "Qin Shi",
    "Cursed Vessel",
    "Cursed King",
    "Combat",
}

-- ════════════════════════════════════════════════
--         TABELA DE PROGRESSÃO DE MISSÕES
-- ════════════════════════════════════════════════
--[[
    COMO EDITAR:
    • "minLevel"  → Nível mínimo para esta missão
    • "maxLevel"  → Nível máximo (nil = sem limite superior)
    • "mobName"   → Nome EXATO do mob no workspace (case-sensitive!)
    • "questNpc"  → Nome EXATO do NPC de missão
    • "island"    → Nome da ilha (apenas informativo)
--]]
local QUEST_TABLE = {
    {
        minLevel = 100,   maxLevel = 249,
        mobName  = "Thief Boss",
        questNpc = "Thief Quest NPC",
        island   = "Starter Island",
    },
    {
        minLevel = 250,   maxLevel = 499,
        mobName  = "Monkey Hunter",
        questNpc = "Monkey Quest NPC",
        island   = "Jungle Island",
    },
    {
        minLevel = 500,   maxLevel = 749,
        mobName  = "Monkey Boss",
        questNpc = "Monkey Boss NPC",
        island   = "Jungle Island",
    },
    {
        minLevel = 750,   maxLevel = 999,
        mobName  = "Desert Bandit",
        questNpc = "Desert Quest NPC",
        island   = "Desert Island",
    },
    {
        minLevel = 1000,  maxLevel = 1699,
        mobName  = "Desert Boss",
        questNpc = "Desert Boss NPC",
        island   = "Desert Island",
    },
    {
        minLevel = 1700,  maxLevel = 2999,
        mobName  = "Snow Enemy",
        questNpc = "Snow Quest NPC",
        island   = "Snow Island",
    },
    {
        minLevel = 3000,  maxLevel = 3999,
        mobName  = "Sorcerer Hunter",
        questNpc = "Sorcerer Quest NPC",
        island   = "Shibuya",
    },
    {
        minLevel = 4000,  maxLevel = 4999,
        mobName  = "Panda Boss",
        questNpc = "Panda Quest NPC",
        island   = "Panda Island",
    },
    {
        minLevel = 5000,  maxLevel = 6249,
        mobName  = "Hollow Hunter",
        questNpc = "Hollow Quest NPC",
        island   = "Hollow Island",
    },
    {
        minLevel = 6250,  maxLevel = 6999,
        mobName  = "Strong Sorcerer",
        questNpc = "Strong Sorcerer NPC",
        island   = "Sorcerer Island",
    },
    {
        minLevel = 7000,  maxLevel = 7999,
        mobName  = "Curse Hunter",
        questNpc = "Curse Quest NPC",
        island   = "Curse Island",
    },
    {
        minLevel = 8000,  maxLevel = 8999,
        mobName  = "Slime Warrior",
        questNpc = "Slime Quest NPC",
        island   = "Slime Island",
    },
    {
        minLevel = 9000,  maxLevel = 9999,
        mobName  = "Academy Challenge",
        questNpc = "Academy NPC",
        island   = "Academy",
    },
    {
        minLevel = 10000, maxLevel = 10749,
        mobName  = "Blade Master",
        questNpc = "Blade Quest NPC",
        island   = "Blade Island",
    },
    {
        minLevel = 10750, maxLevel = 11499,
        mobName  = "Quincy",
        questNpc = "Quincy Quest NPC",
        island   = "Quincy Island",
    },
    {
        minLevel = 11500, maxLevel = 12999,
        mobName  = "Broken Sword Enemy",
        questNpc = "Broken Sword NPC",
        island   = "Sword Island",
    },
    {
        minLevel = 13000, maxLevel = 15999,
        mobName  = "Spirit Fighter",
        questNpc = "Spirit Quest NPC",
        island   = "Spirit Island",
    },
    {
        minLevel = 16000, maxLevel = math.huge,
        mobName  = "Strong Slayer",
        questNpc = "Slayer Quest NPC",
        island   = "Slayer Island",
    },
}

-- ════════════════════════════════════════════════
--              ESTADO DO SCRIPT
-- ════════════════════════════════════════════════
local State = {
    autoFarm    = false,
    autoHaki    = false,
    fastAttack  = false,
    autoStats   = false,
    autoBoss    = false,
    currentMob  = "Nenhum",
    status      = "Inativo",
    isDead      = false,
    isFlying    = false,
    equipped    = false,
    stuckTimer  = 0,
    lastPos     = nil,
}

-- ════════════════════════════════════════════════
--           UTILITÁRIOS GERAIS
-- ════════════════════════════════════════════════

-- Obtém o nível atual do player
local function getPlayerLevel()
    -- ⚠️ Ajuste o caminho conforme o jogo armazena o level
    local stats = player:FindFirstChild("leaderstats")
        or player:FindFirstChild("Stats")
        or player:FindFirstChild("PlayerData")
    if stats then
        local lvl = stats:FindFirstChild("Level")
            or stats:FindFirstChild("Lv")
            or stats:FindFirstChild("level")
        if lvl then return lvl.Value end
    end
    -- Fallback: tenta via PlayerGui ou outros caminhos
    local pgui = player.PlayerGui
    for _, v in ipairs(pgui:GetDescendants()) do
        if v.Name:lower():find("level") and v:IsA("TextLabel") then
            local num = tonumber(v.Text:match("%d+"))
            if num then return num end
        end
    end
    return 1
end

-- Seleciona a missão correta pelo nível
local function getQuestForLevel(level)
    for i = #QUEST_TABLE, 1, -1 do
        local q = QUEST_TABLE[i]
        if level >= q.minLevel and level <= (q.maxLevel or math.huge) then
            return q
        end
    end
    return QUEST_TABLE[1]
end

-- Verifica se o personagem está vivo
local function isAlive()
    local c = player.Character
    if not c then return false end
    local h = c:FindFirstChild("Humanoid")
    return h and h.Health > 0
end

-- Recria referências do personagem
local function refreshCharacter()
    char     = player.Character or player.CharacterAdded:Wait()
    humanoid = char:WaitForChild("Humanoid", 10)
    hrp      = char:WaitForChild("HumanoidRootPart", 10)
end

-- Notificação na tela (não bloqueia)
local function notify(msg, dur)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title    = "AutoFarm SP",
            Text     = msg,
            Duration = dur or 3,
        })
    end)
end

-- ════════════════════════════════════════════════
--           SISTEMA DE AUTO EQUIP MELEE
-- ════════════════════════════════════════════════

-- Verifica se uma ferramenta é um melee válido
local function isValidMelee(tool)
    if not tool or not tool:IsA("Tool") then return false end
    for _, name in ipairs(VALID_MELEES) do
        if tool.Name:lower():find(name:lower()) then
            return true
        end
    end
    return false
end

-- Verifica se algum melee já está equipado no personagem
local function isMeleeEquipped()
    if not player.Character then return false end
    for _, v in ipairs(player.Character:GetChildren()) do
        if isValidMelee(v) then return true end
    end
    return false
end

-- Equipa o melee automaticamente
local function equipMelee()
    if isMeleeEquipped() then
        State.equipped = true
        return true
    end

    -- Procura no Backpack
    local backpack = player:FindFirstChild("Backpack")
    if backpack then
        for _, tool in ipairs(backpack:GetChildren()) do
            if isValidMelee(tool) then
                -- Equipa via humanoid
                humanoid:EquipTool(tool)
                task.wait(0.3)
                State.equipped = true
                State.status = "Melee equipado: " .. tool.Name
                return true
            end
        end
    end

    State.status = "⚠️ Nenhum melee válido encontrado!"
    notify("Nenhum melee válido no inventário!", 5)
    State.equipped = false
    return false
end

-- ════════════════════════════════════════════════
--           SISTEMA DE VOO (TWEEN)
-- ════════════════════════════════════════════════

-- Desativa gravidade e colisão para voar
local function enableFlight()
    if not isAlive() then return end
    local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    if not root then return end
    -- Remove gravidade do root temporariamente
    root.CustomPhysicalProperties = PhysicalProperties.new(0, 0, 0, 0, 0)
    local bp = root:FindFirstChild("FlyBodyPosition")
    if not bp then
        bp = Instance.new("BodyPosition")
        bp.Name = "FlyBodyPosition"
        bp.MaxForce = Vector3.new(1e5, 1e5, 1e5)
        bp.P = 1e4
        bp.Parent = root
    end
    local bv = root:FindFirstChild("FlyBodyVelocity")
    if not bv then
        bv = Instance.new("BodyVelocity")
        bv.Name = "FlyBodyVelocity"
        bv.MaxForce = Vector3.new(1e5, 1e5, 1e5)
        bv.Velocity = Vector3.zero
        bv.Parent = root
    end
    State.isFlying = true
end

-- Desativa o voo e restaura física
local function disableFlight()
    local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    if root then
        local bp = root:FindFirstChild("FlyBodyPosition")
        local bv = root:FindFirstChild("FlyBodyVelocity")
        if bp then bp:Destroy() end
        if bv then bv:Destroy() end
        root.CustomPhysicalProperties = PhysicalProperties.new(0.7, 0.3, 0.5, 0, 0)
    end
    State.isFlying = false
end

-- Voa suavemente até uma posição usando TweenService
local function flyTo(targetPos, speedOverride)
    if not isAlive() then return end
    local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    if not root then return end

    enableFlight()

    local destPos = targetPos + Vector3.new(0, CONFIG.FLY_HEIGHT, 0)

    -- Atualiza BodyPosition para voar
    local bp = root:FindFirstChild("FlyBodyPosition")
    if bp then
        bp.Position = destPos
    end

    -- Tween suave de câmera/rotação
    local dist = (root.Position - destPos).Magnitude
    local tweenTime = math.clamp(dist * (speedOverride or CONFIG.FLY_SPEED) / 100, 0.1, 3)

    local tweenInfo = TweenInfo.new(tweenTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    local goal = { CFrame = CFrame.lookAt(destPos, Vector3.new(targetPos.X, destPos.Y, targetPos.Z)) }
    local tween = TweenService:Create(root, tweenInfo, goal)
    tween:Play()

    -- Aguarda chegar próximo ao destino
    local timeout = 0
    repeat
        task.wait(0.05)
        timeout += 0.05
        if not isAlive() then return end
    until (root.Position - destPos).Magnitude < 8 or timeout > 5

    return true
end

-- ════════════════════════════════════════════════
--         SISTEMA ANTI-STUCK
-- ════════════════════════════════════════════════

local function checkAntiStuck()
    if not isAlive() then return end
    local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    if not root then return end

    if State.lastPos then
        local moved = (root.Position - State.lastPos).Magnitude
        if moved < 1 then
            State.stuckTimer += CONFIG.LOOP_DELAY
        else
            State.stuckTimer = 0
        end
        if State.stuckTimer >= CONFIG.STUCK_TIMEOUT then
            State.status = "Anti-Stuck ativado!"
            State.stuckTimer = 0
            -- Teleporta levemente para desbloquear
            root.CFrame = root.CFrame + Vector3.new(0, 5, 0)
            task.wait(0.5)
        end
    end
    State.lastPos = root.Position
end

-- ════════════════════════════════════════════════
--         SISTEMA DE BUSCA DE MOBS
-- ════════════════════════════════════════════════

-- Encontra o mob mais próximo pelo nome
local function findNearestMob(mobName)
    if not isAlive() then return nil end
    local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    if not root then return nil end

    local nearest, nearestDist = nil, CONFIG.MAX_DIST_TO_MOB

    for _, obj in ipairs(workspace:GetDescendants()) do
        -- Filtra por nome e verifica se é NPC válido (não é player)
        if obj.Name:lower():find(mobName:lower()) then
            local objHum = obj:FindFirstChildOfClass("Humanoid")
            local objHRP = obj:FindFirstChild("HumanoidRootPart")

            if objHum and objHRP
                and objHum.Health > 0
                and not Players:GetPlayerFromCharacter(obj)
            then
                local dist = (root.Position - objHRP.Position).Magnitude
                if dist < nearestDist then
                    nearest    = obj
                    nearestDist = dist
                end
            end
        end
    end

    return nearest, nearestDist
end

-- ════════════════════════════════════════════════
--         SISTEMA DE ATAQUE
-- ════════════════════════════════════════════════

-- Ataca o alvo usando o melee equipado
local function attackTarget(target)
    if not target or not isAlive() then return end
    local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    if not root then return end

    local targetHRP = target:FindFirstChild("HumanoidRootPart")
    if not targetHRP then return end

    -- Garante que o melee está equipado
    if not isMeleeEquipped() then
        equipMelee()
        task.wait(0.3)
    end

    -- Posiciona atrás/acima do inimigo
    local attackPos = targetHRP.Position + Vector3.new(0, CONFIG.FLY_HEIGHT, CONFIG.ATTACK_DISTANCE)
    root.CFrame = CFrame.lookAt(attackPos, targetHRP.Position)

    -- ⚠️ MÉTODO DE ATAQUE: Simula clique do mouse (M1)
    -- Se o jogo usar outro método, substitua aqui
    local mouse = player:GetMouse()

    -- Ataque via fireclick no inimigo
    local targetHum = target:FindFirstChildOfClass("Humanoid")
    if targetHum and targetHum.Health > 0 then
        -- Simula mouse down/up para atacar
        mouse.Hit = targetHRP.CFrame
        -- Tenta usar remotes de ataque se existirem
        local attackRemote = ReplicatedStorage:FindFirstChild("Attack")
            or ReplicatedStorage:FindFirstChild("Combat")
            or ReplicatedStorage:FindFirstChild("Melee")

        if attackRemote and attackRemote:IsA("RemoteEvent") then
            attackRemote:FireServer(targetHRP.Position)
        end

        -- Fallback: humanoid move toward para atacar corpo a corpo
        if humanoid then
            humanoid:MoveTo(
                targetHRP.Position + (root.Position - targetHRP.Position).Unit * CONFIG.ATTACK_DISTANCE
            )
        end
    end
end

-- ════════════════════════════════════════════════
--         SISTEMA DE MISSÕES (QUEST)
-- ════════════════════════════════════════════════

-- Aceita missão no NPC
local function acceptQuest(npcName)
    State.status = "Procurando NPC: " .. npcName
    local npc = nil

    -- Procura o NPC no workspace
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj.Name:lower():find(npcName:lower()) and obj:FindFirstChild("HumanoidRootPart") then
            npc = obj
            break
        end
    end

    if not npc then
        State.status = "NPC não encontrado: " .. npcName
        return false
    end

    -- Voa até o NPC
    local npcHRP = npc:FindFirstChild("HumanoidRootPart")
    if npcHRP then
        flyTo(npcHRP.Position)
        task.wait(0.5)

        -- Tenta interagir com o NPC via ProximityPrompt ou Remote
        local prompt = npc:FindFirstChildOfClass("ProximityPrompt", true)
        if prompt then
            fireproximityprompt(prompt) -- função do executor
            task.wait(0.5)
        end

        -- Tenta encontrar e clicar botões de aceitar missão
        local playerGui = player.PlayerGui
        for _, gui in ipairs(playerGui:GetDescendants()) do
            if gui:IsA("TextButton") then
                local t = gui.Text:lower()
                if t:find("accept") or t:find("aceitar") or t:find("quest") or t:find("missão") then
                    pcall(function() gui.MouseButton1Click:Fire() end)
                    task.wait(0.3)
                end
            end
        end

        State.status = "Missão aceita!"
        return true
    end
    return false
end

-- ════════════════════════════════════════════════
--         SISTEMA DE AUTO HAKI
-- ════════════════════════════════════════════════

local function autoHaki()
    if not State.autoHaki or not isAlive() then return end
    -- ⚠️ Ajuste o nome do remote/keybind do Haki conforme o jogo
    local hakiRemote = ReplicatedStorage:FindFirstChild("Haki")
        or ReplicatedStorage:FindFirstChild("Observation")
        or ReplicatedStorage:FindFirstChild("Armament")

    if hakiRemote and hakiRemote:IsA("RemoteEvent") then
        hakiRemote:FireServer()
    end

    -- Tenta ativar via tecla (se o jogo usar)
    -- VirtualInputManager pode ser usado dependendo do executor
end

-- ════════════════════════════════════════════════
--         SISTEMA DE AUTO STATS
-- ════════════════════════════════════════════════

local function autoStats()
    if not State.autoStats or not isAlive() then return end
    -- ⚠️ Ajuste conforme os remotes de status do jogo
    -- Geralmente distribui pontos em Melee/Força
    local statsRemote = ReplicatedStorage:FindFirstChild("AddStat")
        or ReplicatedStorage:FindFirstChild("UpgradeStat")

    if statsRemote and statsRemote:IsA("RemoteEvent") then
        -- Prioriza Melee → Vida → Defesa
        statsRemote:FireServer("Melee")
    end
end

-- ════════════════════════════════════════════════
--         SISTEMA ANTI-AFK
-- ════════════════════════════════════════════════

local afkThread = task.spawn(function()
    while true do
        task.wait(CONFIG.AFK_INTERVAL)
        if isAlive() then
            -- Move aleatoriamente para evitar AFK
            local r = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
            if r then
                local offset = Vector3.new(math.random(-3,3), 0, math.random(-3,3))
                humanoid:MoveTo(r.Position + offset)
            end
        end
    end
end)

-- ════════════════════════════════════════════════
--         DETECÇÃO DE MORTE E RESPAWN
-- ════════════════════════════════════════════════

player.CharacterAdded:Connect(function(newChar)
    State.isDead   = false
    State.equipped = false
    State.isFlying = false
    char = newChar
    humanoid = newChar:WaitForChild("Humanoid", 10)
    hrp      = newChar:WaitForChild("HumanoidRootPart", 10)

    -- Aguarda respawn estabilizar
    task.wait(CONFIG.RESPAWN_WAIT)

    if State.autoFarm then
        State.status = "Respawnado - Reequipando..."
        equipMelee()
    end
end)

-- ════════════════════════════════════════════════
--               LOOP PRINCIPAL DE FARM
-- ════════════════════════════════════════════════

local function mainFarmLoop()
    while State.autoFarm do
        task.wait(CONFIG.LOOP_DELAY)

        -- Verifica se está vivo
        if not isAlive() then
            State.isDead  = true
            State.status  = "Morto - aguardando respawn..."
            disableFlight()
            task.wait(CONFIG.RESPAWN_WAIT + 1)
            refreshCharacter()
            task.wait(1)
            continue
        end

        State.isDead = false
        checkAntiStuck()

        -- Auto Haki
        autoHaki()

        -- Equipa melee se necessário
        if not equipMelee() then
            State.status = "Sem melee! Verifique o inventário."
            task.wait(2)
            continue
        end

        -- Obtém nível e missão atual
        local level = getPlayerLevel()
        local quest = getQuestForLevel(level)

        State.currentMob = quest.mobName
        State.status = string.format("Lv%d | Farmando: %s", level, quest.mobName)

        -- Aceita missão (tenta periodicamente)
        -- Em um script real você verificaria se a missão já foi aceita
        acceptQuest(quest.questNpc)

        -- Encontra mob mais próximo
        local mob, mobDist = findNearestMob(quest.mobName)

        if not mob then
            State.status = "Procurando " .. quest.mobName .. "..."
            task.wait(1)
            continue
        end

        local mobHRP = mob:FindFirstChild("HumanoidRootPart")
        local mobHum = mob:FindFirstChildOfClass("Humanoid")

        if not mobHRP or not mobHum or mobHum.Health <= 0 then
            continue
        end

        -- Voa até o mob se estiver longe
        if mobDist > CONFIG.ATTACK_DISTANCE + 2 then
            State.status = "Voando até " .. quest.mobName
            flyTo(mobHRP.Position)
        end

        -- Loop de ataque até mob morrer
        local attackTimeout = 0
        while State.autoFarm and isAlive() and mob and mobHum and mobHum.Health > 0 do
            attackTarget(mob)

            local delay = State.fastAttack and CONFIG.FAST_ATTACK_DELAY or CONFIG.ATTACK_DELAY
            task.wait(delay)

            attackTimeout += delay
            if attackTimeout > 30 then
                -- Timeout: abandona este mob e busca outro
                break
            end

            -- Auto stats enquanto ataca
            if State.autoStats and attackTimeout % 5 < delay then
                autoStats()
            end

            -- Reposiciona se saiu muito longe
            if mobHRP and (hrp.Position - mobHRP.Position).Magnitude > CONFIG.ATTACK_DISTANCE * 3 then
                flyTo(mobHRP.Position)
            end
        end

        disableFlight()
        task.wait(0.2)
    end

    -- Encerra voo ao desativar
    disableFlight()
    State.status  = "Inativo"
    State.currentMob = "Nenhum"
end

-- ════════════════════════════════════════════════
--                INTERFACE GRÁFICA (GUI)
-- ════════════════════════════════════════════════

local function createGUI()
    -- Remove GUI antiga se existir
    local existing = player.PlayerGui:FindFirstChild("AutoFarmGUI")
    if existing then existing:Destroy() end

    local screenGui = Instance.new("ScreenGui")
    screenGui.Name           = "AutoFarmGUI"
    screenGui.ResetOnSpawn   = false
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui.Parent         = player.PlayerGui

    -- ── Frame Principal ──────────────────────────────
    local mainFrame = Instance.new("Frame")
    mainFrame.Name            = "Main"
    mainFrame.Size            = UDim2.new(0, 260, 0, 320)
    mainFrame.Position        = UDim2.new(0, 10, 0.5, -160)
    mainFrame.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
    mainFrame.BorderSizePixel = 0
    mainFrame.Active          = true
    mainFrame.Draggable       = true
    mainFrame.Parent          = screenGui

    Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0, 10)

    -- Borda decorativa
    local stroke = Instance.new("UIStroke")
    stroke.Color     = Color3.fromRGB(80, 160, 255)
    stroke.Thickness = 1.5
    stroke.Parent    = mainFrame

    -- ── Header ──────────────────────────────────────
    local header = Instance.new("Frame")
    header.Size              = UDim2.new(1, 0, 0, 40)
    header.BackgroundColor3  = Color3.fromRGB(20, 80, 180)
    header.BorderSizePixel   = 0
    header.Parent            = mainFrame

    Instance.new("UICorner", header).CornerRadius = UDim.new(0, 10)

    local title = Instance.new("TextLabel")
    title.Size              = UDim2.new(1, 0, 1, 0)
    title.BackgroundTransparency = 1
    title.Text              = "⚓ SAILOR PIECE AUTO FARM"
    title.TextColor3        = Color3.fromRGB(255, 255, 255)
    title.TextSize          = 13
    title.Font              = Enum.Font.GothamBold
    title.Parent            = header

    -- ── Status Labels ────────────────────────────────
    local function makeLabel(text, yOffset)
        local lbl = Instance.new("TextLabel")
        lbl.Size              = UDim2.new(1, -10, 0, 18)
        lbl.Position          = UDim2.new(0, 5, 0, yOffset)
        lbl.BackgroundTransparency = 1
        lbl.TextColor3        = Color3.fromRGB(180, 220, 255)
        lbl.TextSize          = 11
        lbl.Font              = Enum.Font.Gotham
        lbl.TextXAlignment    = Enum.TextXAlignment.Left
        lbl.Text              = text
        lbl.Parent            = mainFrame
        return lbl
    end

    local statusLabel  = makeLabel("Status: Inativo", 48)
    local mobLabel     = makeLabel("Mob: Nenhum",     66)
    local levelLabel   = makeLabel("Level: --",       84)

    -- Atualiza labels em tempo real
    task.spawn(function()
        while screenGui.Parent do
            task.wait(0.5)
            statusLabel.Text = "Status: " .. State.status
            mobLabel.Text    = "Mob: "    .. State.currentMob
            local lv = pcall(getPlayerLevel) and getPlayerLevel() or "--"
            levelLabel.Text  = "Level: "  .. tostring(lv)
        end
    end)

    -- Separador
    local sep = Instance.new("Frame")
    sep.Size             = UDim2.new(0.9, 0, 0, 1)
    sep.Position         = UDim2.new(0.05, 0, 0, 108)
    sep.BackgroundColor3 = Color3.fromRGB(50, 100, 200)
    sep.BorderSizePixel  = 0
    sep.Parent           = mainFrame

    -- ── Botões Toggle ────────────────────────────────
    local function makeToggle(labelText, yPos, stateKey)
        local btn = Instance.new("TextButton")
        btn.Size              = UDim2.new(0.9, 0, 0, 30)
        btn.Position          = UDim2.new(0.05, 0, 0, yPos)
        btn.BackgroundColor3  = Color3.fromRGB(30, 30, 40)
        btn.TextColor3        = Color3.fromRGB(255, 80, 80)
        btn.Text              = "● " .. labelText .. ": OFF"
        btn.TextSize          = 12
        btn.Font              = Enum.Font.GothamBold
        btn.BorderSizePixel   = 0
        btn.Parent            = mainFrame

        Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)

        local function updateBtn()
            if State[stateKey] then
                btn.BackgroundColor3 = Color3.fromRGB(20, 60, 20)
                btn.TextColor3       = Color3.fromRGB(80, 255, 80)
                btn.Text             = "● " .. labelText .. ": ON"
            else
                btn.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
                btn.TextColor3       = Color3.fromRGB(255, 80, 80)
                btn.Text             = "● " .. labelText .. ": OFF"
            end
        end

        btn.MouseButton1Click:Connect(function()
            State[stateKey] = not State[stateKey]
            updateBtn()

            -- Inicia loop de farm ao ativar
            if stateKey == "autoFarm" and State.autoFarm then
                State.status = "Iniciando..."
                task.spawn(mainFarmLoop)
            end
        end)

        return btn
    end

    makeToggle("Auto Farm",    115, "autoFarm")
    makeToggle("Auto Haki",    152, "autoHaki")
    makeToggle("Fast Attack",  189, "fastAttack")
    makeToggle("Auto Stats",   226, "autoStats")
    makeToggle("Auto Boss",    263, "autoBoss")

    -- Rodapé
    local footer = Instance.new("TextLabel")
    footer.Size              = UDim2.new(1, 0, 0, 14)
    footer.Position          = UDim2.new(0, 0, 1, -16)
    footer.BackgroundTransparency = 1
    footer.Text              = "Arraste para mover  |  v2.0"
    footer.TextColor3        = Color3.fromRGB(80, 80, 100)
    footer.TextSize          = 10
    footer.Font              = Enum.Font.Gotham
    footer.Parent            = mainFrame

    return screenGui
end

-- ════════════════════════════════════════════════
--              INICIALIZAÇÃO
-- ════════════════════════════════════════════════

local function init()
    -- Aguarda personagem carregar completamente
    task.wait(2)
    refreshCharacter()

    -- Cria a GUI
    createGUI()

    -- Registra mortes do humanoid
    if humanoid then
        humanoid.Died:Connect(function()
            State.isDead   = true
            State.status   = "Morto..."
            State.equipped = false
            disableFlight()
        end)
    end

    notify("AutoFarm Sailor Piece carregado!", 4)
    print("[AutoFarm SP] Script iniciado com sucesso!")
    print("[AutoFarm SP] Use a GUI para ativar os sistemas.")
end

-- ═══════════════════════════════════════
-- Proteção anti-crash global
local ok, err = pcall(init)
if not ok then
    warn("[AutoFarm SP] Erro na inicialização: " .. tostring(err))
    -- Tenta criar GUI mesmo com erro
    pcall(createGUI)
end
