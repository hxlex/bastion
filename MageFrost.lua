local Tinkr, Bastion, TinkrBot = ...

-- =====================================================================
-- TinkrBot - 冰霜法师循环（远程炮台冰）
-- 基于白皮书 APL：爆发联动 → 触发特效(2+1) → 寒冰箭填充
-- =====================================================================

local Player = TinkrBot.Player
local Target = TinkrBot.Target
local Utils = TinkrBot.Utils
local GetSpell = Utils.GetSpell
local HasBuff = Utils.HasBuff
local HasAnyBuff = Utils.HasAnyBuff
local IsMoving = Utils.IsMoving
local ShouldPause = Utils.ShouldPause
local CountNearbyEnemies = Utils.CountNearbyEnemies
local CountEnemiesAroundTarget = Utils.CountEnemiesAroundTarget
local GetEnemyCenterPosition = Utils.GetEnemyCenterPosition
local GetTargetPosition = Utils.GetTargetPosition
local CastGroundAOE = Utils.CastGroundAOE
local SpellBook = TinkrBot.SpellBook

-- ===================== 创建模块 =====================
local MageFrost = Bastion.Module:New('TinkrBot_MageFrost')

-- ===================== 配置 =====================
local Config = {
    Enabled = true,
    FrostNovaHP = 50,      -- 血量低于此值时冰霜新星
    UseSpellsteal = true,  -- 自动法术偷取
    InterruptMode = "all", -- "all" / "off"
    UseBlizzard = true,    -- 是否释放暴风雪
    BlizzardThreshold = 3, -- 几个怪才放暴风雪
}

-- ===================== 技能定义 =====================
-- 技能变量（延迟初始化，等角色完全载入后再获取，确保拿到最高等级版本）
local Frostbolt, Fireball, FireBlast, IceLance, FrostfireBolt, DeepFreeze
local Blizzard, ConeOfCold
local FrostNova, IcyVeins, ColdSnap, Berserking, IceBarrier, IceBlock
local Counterspell, MirrorImage, SummonWaterElemental, Spellsteal
local IceArmor, FrostArmor, MageArmor, MoltenArmor, ArcaneIntellect
local ArcaneBrilliance, DalaranIntellect, DalaranBrilliance

local spellsInitialized = false
local moduleLoadTime = nil

local function InitSpells()
    -- 单体技能
    Frostbolt = GetSpell("寒冰箭")
    Fireball = GetSpell("火球术")
    FireBlast = GetSpell("火焰冲击")
    IceLance = GetSpell("冰枪术")
    FrostfireBolt = SpellBook:GetSpell(47610)  -- 霜火之箭
    DeepFreeze = GetSpell("深度冻结")
    -- AOE技能
    Blizzard = GetSpell("暴风雪")
    ConeOfCold = GetSpell("冰锥术")
    -- 工具/防御技能
    FrostNova = GetSpell("冰霜新星")
    IcyVeins = GetSpell("冰冷血脉")
    ColdSnap = GetSpell("急速冷却")
    Berserking = GetSpell("狂暴")
    IceBarrier = GetSpell("寒冰护体")
    IceBlock = GetSpell("寒冰屏障")
    Counterspell = GetSpell("法术反制")
    -- 中国服 GetSpellInfo 返回的是显示ID，需要从法术书获取真实可施放ID
    for i = 1, 300 do
        local name = GetSpellBookItemName(i, "spell")
        if not name then break end
        if name == "法术反制" then
            local _, id = GetSpellBookItemInfo(i, "spell")
            if id and (not Counterspell or Counterspell:GetID() ~= id) then
                Counterspell = SpellBook:GetSpell(id)
            end
            break
        end
    end
    MirrorImage = GetSpell("镜像")
    SummonWaterElemental = GetSpell("召唤水元素")
    Spellsteal = GetSpell("法术吸取")
    -- Buff技能
    IceArmor = GetSpell("冰甲术")
    FrostArmor = GetSpell("霜甲术")
    MageArmor = GetSpell("法师护甲")
    MoltenArmor = GetSpell("熔岩护甲")
    ArcaneIntellect = GetSpell("奥术智慧")
    ArcaneBrilliance = GetSpell("奥术光辉")
    DalaranIntellect = GetSpell("达拉然智慧")
    DalaranBrilliance = GetSpell("达拉然光辉")
    -- 重建 BuffAPL（顶层执行时技能均为 nil，现在才能正确注册）
    BuffAPL = Bastion.APL:New('MF_Buff')
    -- 护甲优先级：熔岩护甲 > 冰甲 > 霜甲
    if MoltenArmor then
        BuffAPL:AddSpell(
            MoltenArmor:CastableIf(function(self)
                return self:IsKnownAndUsable() and not HasArmorBuff() and not Player:IsCastingOrChanneling()
            end):SetTarget(Player)
        )
    elseif IceArmor then
        BuffAPL:AddSpell(
            IceArmor:CastableIf(function(self)
                return self:IsKnownAndUsable() and not HasArmorBuff() and not Player:IsCastingOrChanneling()
            end):SetTarget(Player)
        )
    elseif FrostArmor then
        BuffAPL:AddSpell(
            FrostArmor:CastableIf(function(self)
                return self:IsKnownAndUsable() and not HasArmorBuff() and not Player:IsCastingOrChanneling()
            end):SetTarget(Player)
        )
    end
    if ArcaneIntellect then
        BuffAPL:AddSpell(
            ArcaneIntellect:CastableIf(function(self)
                return self:IsKnownAndUsable() and not HasAI() and not Player:IsCastingOrChanneling()
            end):SetTarget(Player)
        )
    end
    spellsInitialized = true
    print("|cFF00FF00[TinkrBot] 冰霜法师技能已初始化|r")
end

-- Proc / Buff ID
local FINGERS_OF_FROST_ID = 74396   -- 寒冰指
local BRAIN_FREEZE_ID     = 57761   -- 思维冷却
local ICY_VEINS_BUFF_ID   = 12472   -- 冰冷血脉 buff
local ARCANE_BRILLIANCE_ID = 23028  -- 奥术光辉

-- ===================== 瞬发预队列系统 =====================
-- 在读条最后 200ms 内调用 CastSpellByID，利用 WoW 的 SpellQueueWindow 机制
-- WoW 会自动在读条结束的瞬间释放排队的技能（和人类玩家按键一样）
local pendingSpellID = nil     -- 预定要释放的技能 ID
local pendingTarget = nil      -- 预定的目标 token
local preQueueFired = false    -- 本次读条是否已经发送过队列
local preQueueFiredAt = 0      -- 预队列释放时间戳，防止 Sync 覆盖
local _UnitCastingInfo = TinkrBot.API.UnitCastingInfo
local _UnitAffectingCombat = TinkrBot.API.UnitAffectingCombat
local _GetTime = TinkrBot.API.GetTime
local _GetSpellInfo = TinkrBot.API.GetSpellInfo

local spellQueueFrame = TinkrBot.Frames.SpellQueue
spellQueueFrame:SetScript("OnUpdate", function(self, elapsed)
    -- 脱战时清理
    if not _UnitAffectingCombat('player') then
        pendingSpellID = nil
        pendingTarget = nil
        preQueueFired = false
        return
    end

    if not pendingSpellID then
        preQueueFired = false
        return
    end

    -- 检查读条状态和剩余时间
    local name, _, _, _, endTimeMS = _UnitCastingInfo('player')
    if not name then
        -- 不在读条：清理状态
        preQueueFired = false
        return
    end

    -- 在读条中且有待释放技能：检查是否在最后 200ms 窗口内
    if not preQueueFired then
        local nowMS = _GetTime() * 1000
        local remainMS = endTimeMS - nowMS
        if remainMS < 400 then
            -- 在读条最后 400ms，通过主入口调用 CastSpellByID
            -- WoW 的 SpellQueueWindow 会队列此技能，读条结束瞬间自动释放
            TinkrBot.PendingSpellCast = { spellID = pendingSpellID, target = pendingTarget }
            preQueueFired = true
            preQueueFiredAt = _GetTime()
            pendingSpellID = nil
            pendingTarget = nil
        end
    end
end)

-- 饰品 API
local GetInventoryItemID = TinkrBot.API.GetInventoryItemID
local UseInventoryItem = TinkrBot.API.UseInventoryItem
local GetInventoryItemCooldown = TinkrBot.API.GetInventoryItemCooldown
local TRINKET_SLOT_1 = 13
local TRINKET_SLOT_2 = 14

-- 水元素防御模式追踪
local petModeSet = false

-- ===================== 辅助函数 =====================

local function PrintSpell(name, id)
    Utils.PrintSpellUsed("冰法", name, id)
end

-- 尝试使用指定栏位的饰品
local function UseTrinketSlot(slot)
    local itemID = GetInventoryItemID("player", slot)
    if not itemID or itemID == 0 then return false end
    local start, duration, enable = GetInventoryItemCooldown("player", slot)
    if enable == 1 and (start == 0 or (duration > 0 and start + duration - GetTime() <= 0)) then
        UseInventoryItem(slot)
        return true
    end
    return false
end

-- 检查寒冰指buff，返回 层数(0/1/2), 剩余时间
-- WotLK实测: name[1] icon[2] count[3] debuffType[4] duration[5] expirationTime[6] caster[7] ...[8] ...[9] spellId[10]
local function GetFingersOfFrost()
    for i = 1, 40 do
        local a, b, c, d, e, f, g, h, j, k = UnitBuff("player", i)
        if not a then break end
        -- 按名字或spellId匹配（双重保险）
        if a == "寒冰指" or a == "Fingers of Frost" or k == FINGERS_OF_FROST_ID then
            local remain = f and (f - GetTime()) or 0
            local count = (c and c > 0) and c or 1
            return count, remain
        end
    end
    return 0, 0
end

-- 检查是否有思维冷却
local function HasBrainFreeze()
    for i = 1, 40 do
        local a, b, c, d, e, f, g, h, j, k = UnitBuff("player", i)
        if not a then break end
        if a == "思维冷却" or a == "Brain Freeze" or k == BRAIN_FREEZE_ID then return true end
    end
    return false
end

-- 检查是否在冰冷血脉期间
local function HasIcyVeinsBuff()
    return HasAnyBuff(ICY_VEINS_BUFF_ID)
end


-- 合并敌人扫描（每 tick 只遍历一次 EnumEnemies）
local scan = { nearbyCount = 0, blizzardCount = 0 }
local lastScanTime = 0

local function RunScan()
    local now = GetTime()
    if now == lastScanTime then return scan end
    lastScanTime = now

    scan.nearbyCount = 0
    scan.blizzardCount = 0

    Bastion.UnitManager:EnumEnemies(function(enemy)
        if not enemy:IsAlive() or not enemy:IsAffectingCombat() then return end
        if not Player:CanSee(enemy) then return end
        local dist = Player:GetDistance(enemy)

        if dist <= 10 then
            scan.nearbyCount = scan.nearbyCount + 1
        end
        if dist <= 40 then
            scan.blizzardCount = scan.blizzardCount + 1
        end
    end)
    return scan
end

local function HasArmorBuff()
    if MoltenArmor and HasBuff(MoltenArmor:GetID()) then return true end
    if IceArmor and HasBuff(IceArmor:GetID()) then return true end
    if FrostArmor and HasBuff(FrostArmor:GetID()) then return true end
    if MageArmor and HasBuff(MageArmor:GetID()) then return true end
    return false
end

local function HasAI()
    if ArcaneIntellect and HasAnyBuff(ArcaneIntellect:GetID()) then return true end
    if ArcaneBrilliance and HasAnyBuff(ArcaneBrilliance:GetID()) then return true end
    if DalaranIntellect and HasAnyBuff(DalaranIntellect:GetID()) then return true end
    if DalaranBrilliance and HasAnyBuff(DalaranBrilliance:GetID()) then return true end
    return false
end


-- ===================== 2+1 状态追踪 =====================
-- 寒冰指最多2层：游戏直接给出层数，不再手动追踪消耗计数
-- fofStacks==2 → 还需搓1发寒冰箭消耗一层；fofStacks==1 → 直接打瞬发
local lastPrintedFofStacks = -1  -- 上一次打印时的层数（-1表示未初始化）

-- ===================== APL 定义 =====================
local BuffAPL = Bastion.APL:New('MF_Buff')  -- InitSpells() 后会重建

-- ===================== 主循环（手动控制优先级） =====================
MageFrost:Sync(function()
    -- 总开关
    if not TinkrBot.MasterEnabled then return end
    if not Config.Enabled then return end
    if not Player:IsAlive() then return end

    -- 延迟初始化：等角色完全载入 2 秒后再获取技能，确保拿到最高等级版本
    if not spellsInitialized then
        if not moduleLoadTime then
            moduleLoadTime = GetTime()
        end
        if GetTime() - moduleLoadTime < 2 then return end
        InitSpells()
    end
    local inCombat = UnitAffectingCombat('player')

    -- 脱战时维护 buff
    if not inCombat then
        petModeSet = false
        if not Player:IsCastingOrChanneling() then
            local _CastSpellByID = TinkrBot.API.CastSpellByID
            local armor = MoltenArmor or IceArmor or FrostArmor
            if not HasArmorBuff() and armor and armor:IsKnownAndUsable() then
                _CastSpellByID(armor:GetID())
                return
            end
            if not HasAI() and ArcaneIntellect and ArcaneIntellect:IsKnownAndUsable() then
                _CastSpellByID(ArcaneIntellect:GetID())
                return
            end
        end
        return
    end

    -- 基本条件检查
    if not Target:Exists() or Target:IsDead() or not Target:IsEnemy() then
        return
    end
    if not Player:CanSee(Target) then return end

    -- 每 tick 合并扫描一次敌人
    RunScan()

    -- 水元素：进入战斗自动防御，死了自动重召
    if UnitExists("pet") and not petModeSet then
        PetDefensiveMode()
        petModeSet = true
    end
    if SummonWaterElemental and SummonWaterElemental:IsKnownAndUsable()
       and not UnitExists("pet") and not IsMoving() then
        SummonWaterElemental:Cast(Player)
        PrintSpell("召唤水元素", SummonWaterElemental:GetID())
        return
    end

    -- ==================== 2+1 状态读取 ====================
    local fofStacks, fofRemain = GetFingersOfFrost()  -- 0/1/2 层
    local hasFoF = fofStacks > 0
    local hasBF = HasBrainFreeze()

    if fofStacks ~= lastPrintedFofStacks then
        if hasFoF then
            print("|cFFFFFF00[FoF] 寒冰指 " .. fofStacks .. " 层 剩" .. string.format("%.1f", fofRemain) .. "秒|r")
        end
        lastPrintedFofStacks = fofStacks
    end

    -- ==================== 引导中不打断 ====================
    if Player:IsChanneling() then return end

    -- ==================== 1. 法术反制（扫描所有战斗中的敌人）====================
    if Config.InterruptMode ~= "off" and Counterspell then
        local intTarget = nil
        Bastion.ObjectManager.enemies:each(function(enemy)
            if intTarget then return end
            if not enemy:IsAlive() or not enemy:IsAffectingCombat() then return end
            if not enemy:IsInterruptible() then return end
            if Player:GetDistance(enemy) > 30 then return end
            if not Player:CanSee(enemy) then return end
            intTarget = enemy
        end)
        if intTarget then
            local gcdStart, gcdDur = GetSpellCooldown(61304)
            local gcdLeft = (gcdStart + gcdDur) - GetTime()
            if gcdLeft <= 0.1 and not Counterspell:IsOnCooldown() then
                if Player:IsCasting() then SpellStopCasting() end
                Counterspell:ForceCast(intTarget)
                PrintSpell("法术反制", Counterspell:GetID())
                return
            end
        end
    end

    -- ==================== 2. 法术吸取（扫描进入战斗的敌人）====================
    if Config.UseSpellsteal and Spellsteal and Spellsteal:IsKnown() and not Spellsteal:IsOnCooldown() then
        local stealTarget = nil
        Bastion.UnitManager:EnumEnemies(function(enemy)
            if stealTarget then return end
            if not enemy:IsAlive() or not enemy:IsAffectingCombat() then return end
            if not Player:CanSee(enemy) then return end
            if Player:GetDistance(enemy) > 30 then return end
            if enemy:GetAuras():HasAnyStealableAura() then
                stealTarget = enemy
            end
        end)
        if stealTarget then
            Spellsteal:Cast(stealTarget)
            PrintSpell("法术吸取", Spellsteal:GetID())
            return
        end
    end

    -- ==================== 预队列（读条中设置，读条外清除）====================
    if Player:IsCasting() then
        local castName = UnitCastingInfo('player')
        local isCastingFrostbolt = Frostbolt and castName == GetSpellInfo(Frostbolt:GetID())
        if isCastingFrostbolt then
            local targetToken = Target:GetOMToken()
            if fofStacks == 1 then
                if DeepFreeze and DeepFreeze:IsKnown() and not DeepFreeze:IsOnCooldown() then
                    pendingSpellID = DeepFreeze:GetID()
                    pendingTarget = targetToken
                elseif hasBF and FrostfireBolt and FrostfireBolt:IsKnownAndUsable() then
                    pendingSpellID = FrostfireBolt:GetID()
                    pendingTarget = targetToken
                elseif IceLance and IceLance:IsKnownAndUsable() then
                    pendingSpellID = IceLance:GetID()
                    pendingTarget = targetToken
                else
                    pendingSpellID = nil
                    pendingTarget = nil
                end
            elseif not hasFoF and hasBF and FrostfireBolt and FrostfireBolt:IsKnownAndUsable() then
                pendingSpellID = FrostfireBolt:GetID()
                pendingTarget = targetToken
            else
                pendingSpellID = nil
                pendingTarget = nil
            end
        end
        return
    end
    pendingSpellID = nil
    pendingTarget = nil

    if GetTime() - preQueueFiredAt < 0.3 then return end

    -- ==================== 2.5 暴风雪（开关+阈值）====================
    if Config.UseBlizzard and Blizzard and Blizzard:IsKnownAndUsable()
       and not IsMoving() and scan.blizzardCount >= Config.BlizzardThreshold then
        local pos = GetTargetPosition()
        if pos then
            local success = CastGroundAOE(Blizzard, pos)
            if success then
                PrintSpell("暴风雪", Blizzard:GetID())
                return
            end
        end
    end

    -- ==================== 3. 冰霜新星（近战自保）====================
    if FrostNova and FrostNova:IsKnownAndUsable() and
       Player:GetDistance(Target) <= 10 and
       (Player:GetHP() < Config.FrostNovaHP or scan.nearbyCount >= 2) then
        FrostNova:Cast(Player)
        PrintSpell("冰霜新星", FrostNova:GetID())
        return
    end

    -- ==================== 4. 有FoF移动中：瞬发优先 ====================
    -- ==================== 5. 有FoF站桩：搓寒冰箭（2+1核心）====================
    if hasFoF then
        if IsMoving() then
            if DeepFreeze and DeepFreeze:IsKnown() and not DeepFreeze:IsOnCooldown() then
                DeepFreeze:Cast(Target)
                PrintSpell("深度冻结(寒冰指移动)", DeepFreeze:GetID())
                return
            end
            if hasBF and FrostfireBolt and FrostfireBolt:IsKnownAndUsable() and FrostfireBolt:IsInRange(Target) then
                FrostfireBolt:Cast(Target)
                PrintSpell("霜火箭(寒冰指移动)", FrostfireBolt:GetID())
                return
            end
            if FireBlast and FireBlast:IsKnownAndUsable() and FireBlast:IsInRange(Target) then
                FireBlast:Cast(Target)
                PrintSpell("火焰冲击(寒冰指移动)", FireBlast:GetID())
                return
            end
            if IceLance and IceLance:IsKnownAndUsable() and IceLance:IsInRange(Target) then
                IceLance:Cast(Target)
                PrintSpell("冰枪术(寒冰指移动)", IceLance:GetID())
                return
            end
            return
        end
        if Frostbolt and Frostbolt:IsKnownAndUsable() and Frostbolt:IsInRange(Target) then
            Frostbolt:Cast(Target)
            PrintSpell("寒冰箭(寒冰指" .. fofStacks .. "层)", Frostbolt:GetID())
        end
        return
    end

    -- ==================== 6. 思维冷却兜底（不在读条时）====================
    if hasBF and FrostfireBolt and FrostfireBolt:IsKnownAndUsable() and FrostfireBolt:IsInRange(Target) then
        FrostfireBolt:Cast(Target)
        PrintSpell("霜火箭(思维冷却)", FrostfireBolt:GetID())
        return
    end

    -- ==================== 7. 移动中无proc：火焰冲击 > 冰枪术 ====================
    if IsMoving() then
        if FireBlast and FireBlast:IsKnownAndUsable() and FireBlast:IsInRange(Target) then
            FireBlast:Cast(Target)
            PrintSpell("火焰冲击(移动)", FireBlast:GetID())
            return
        end
        if IceLance and IceLance:IsKnownAndUsable() and IceLance:IsInRange(Target) then
            IceLance:Cast(Target)
            PrintSpell("冰枪术(移动)", IceLance:GetID())
            return
        end
        return
    end

    -- ==================== 8. 站桩填充：寒冰箭 ====================
    if Frostbolt and Frostbolt:IsKnownAndUsable() and Frostbolt:IsInRange(Target) then
        Frostbolt:Cast(Target)
        PrintSpell("寒冰箭", Frostbolt:GetID())
        return
    end
end)

-- ===================== 注册模块 =====================
Bastion:Register(MageFrost)
MageFrost:Enable()

-- 导出配置供 UI 使用
local Rotation = {
    Name = "冰霜法师",
    Class = "MAGE",
    Module = MageFrost,
    Config = Config,
    PullSpells = {
        ["寒冰箭"] = Frostbolt,
        ["火球术"] = Fireball,
        ["冰枪术"] = IceLance,
        ["火焰冲击"] = FireBlast,
    },
}

TinkrBot.Rotation = Rotation
SetCVar("SpellQueueWindow", 400)
print("|cFF00FF00[zHelper] 冰霜法师循环(远程炮台)已加载|r")
return Rotation
