local Tinkr, Bastion, TinkrBot = ...

-- =====================================================================
-- TinkrBot - 鲜血死亡骑士（深血血沸流）
-- 三色周期循环：IT→BB→DnD, IT→BB→PS, IT→BB→PS  (9步固定序列)
-- 仇恨驱动目标切换 + UnitDetailedThreatSituation 精确仇恨
-- =====================================================================

local Player    = TinkrBot.Player
local Target    = TinkrBot.Target
local Utils     = TinkrBot.Utils
local GetSpell  = Utils.GetSpell
local HasBuff    = Utils.HasBuff
local HasAnyBuff = Utils.HasAnyBuff
local ShouldPause = Utils.ShouldPause
local SpellBook = TinkrBot.SpellBook

local DKBloodBB = Bastion.Module:New('TinkrBot_DKBloodBB')

local Config = {
    Enabled          = true,
    AOEMode          = true,    -- true=群体(智能切目标) / false=单体(只打当前目标)
    InterruptMode    = "all",   -- all / off
    TauntEnabled     = true,
    HPRuneTap        = 50,
    HPVampiricBlood  = 40,
    HPDeathPact      = 30,
    HPIceboundFort   = 20,
    HPDeathStrike    = 40,
    RPDeathCoil      = 90,
}

-- ==================== 技能变量 ====================
local IcyTouch, PlagueStrike, Pestilence
local RuneStrike, DeathStrike, BloodBoil, DeathCoil, DeathAndDecay
local IceboundFortitude, VampiricBlood, RuneTap, AntiMagicShell
local EmpowerRuneWeapon, DeathPact
local HornOfWinter, RaiseDead, DeathGrip, DarkCommand
local MindFreeze, Strangulate

local spellsInitialized = false
local moduleLoadTime = nil

-- ==================== 法术书ID校正 ====================
local function BuildSpellBookLookup()
    local lookup = {}
    for i = 1, 300 do
        local name = GetSpellBookItemName(i, "spell")
        if not name then break end
        local _, id = GetSpellBookItemInfo(i, "spell")
        if id then lookup[name] = id end
    end
    return lookup
end

local function GetSpellFixed(name, lookup)
    local bookID = lookup[name]
    if bookID then return SpellBook:GetSpell(bookID) end
    return GetSpell(name)
end

local function InitSpells()
    local lookup = BuildSpellBookLookup()
    local S = function(name) return GetSpellFixed(name, lookup) end
    IcyTouch      = S("冰冷触摸")
    PlagueStrike  = S("暗影打击")
    Pestilence    = S("传染")
    RuneStrike    = S("符文打击")
    DeathStrike   = S("灵界打击")
    BloodBoil     = S("血液沸腾")
    DeathCoil     = S("凋零缠绕")
    DeathAndDecay = S("枯萎凋零")
    IceboundFortitude = S("冰封之韧")
    VampiricBlood     = S("吸血鬼之血")
    RuneTap           = S("符文分流")
    AntiMagicShell    = S("反魔法护罩")
    EmpowerRuneWeapon = S("符文武器增效")
    DeathPact         = S("天灾契约")
    HornOfWinter = S("寒冬号角")
    RaiseDead    = S("亡者复生")
    DeathGrip    = S("死亡之握")
    DarkCommand  = S("黑暗命令")
    MindFreeze   = S("心灵冰冻")
    Strangulate  = S("绞袭")
    spellsInitialized = true
    print("|cFF00FF00[TinkrBot] 血DK(血沸流)技能已初始化|r")
end

-- ==================== 常量 & 工具函数 ====================
local HOW_BUFF_ID      = 57623
local FROST_FEVER_ID   = 55095
local BLOOD_PLAGUE_ID  = 55078

local function GetHornOfWinterRemaining()
    for i = 1, 40 do
        local name, _, _, _, dur, exp, _, _, _, sid = UnitBuff("player", i)
        if not name then break end
        if sid == HOW_BUFF_ID then return exp - GetTime() end
    end
    return 0
end

local function GetRunicPower()
    return UnitPower("player", 6) or 0
end

local function GetHPPercent()
    return (UnitHealth("player") / UnitHealthMax("player")) * 100
end

local function HasFrostFeverOn(unit)
    if not unit or not unit:Exists() then return false end
    local token = unit:GetOMToken()
    for i = 1, 40 do
        local name, _, _, _, _, _, caster, _, _, sid = UnitDebuff(token, i)
        if not name then break end
        if sid == FROST_FEVER_ID and caster == "player" then return true end
    end
    return false
end

local function HasBloodPlagueOn(unit)
    if not unit or not unit:Exists() then return false end
    local token = unit:GetOMToken()
    for i = 1, 40 do
        local name, _, _, _, _, _, caster, _, _, sid = UnitDebuff(token, i)
        if not name then break end
        if sid == BLOOD_PLAGUE_ID and caster == "player" then return true end
    end
    return false
end

local _CastSpellByID = TinkrBot.API.CastSpellByID
local _GetSpellInfo  = TinkrBot.API.GetSpellInfo

local function PrintSpell(id, extra)
    local name = _GetSpellInfo(id)
    local msg = id .. "--" .. (name or "?")
    if extra then msg = msg .. " (" .. extra .. ")" end
    print("[DK-BB] " .. msg)
end

local function TryCast(spell, unit)
    if not spell or not spell:IsKnownAndUsable() then return false end
    if unit and spell:HasRange() and not spell:IsInRange(unit) then return false end
    PrintSpell(spell:GetID())
    spell:Cast(unit or Player)
    return true
end

local function TryCastGround(spell, pos)
    if not spell or not spell:IsKnownAndUsable() then return false end
    PrintSpell(spell:GetID())
    _CastSpellByID(spell:GetID())
    spell:Click(pos)
    return true
end

-- ==================== 仇恨驱动目标选择 ====================
-- 优先级：仇恨丢失 > 仇恨最低 > 缺疾病 > 最近
-- 帧缓存：每帧只计算一次，避免重复遍历
local cachedBestTarget = nil
local cachedBestTime = 0

local function FindBestTarget()
    local now = GetTime()
    if now == cachedBestTime and cachedBestTarget then
        return cachedBestTarget
    end

    local looseEnemy = nil
    local lowestEnemy, lowestVal = nil, math.huge
    local noDiseaseEnemy = nil
    local closestEnemy, closestDist = nil, 999

    Bastion.UnitManager:EnumEnemies(function(enemy)
        if not enemy:IsAlive() or not enemy:IsAffectingCombat() then return end
        local dist = Player:GetDistance(enemy)
        if dist > 30 then return end

        local tok = enemy:GetOMToken()
        local isTanking, _, _, _, threatVal = UnitDetailedThreatSituation("player", tok)

        if not isTanking and not looseEnemy then
            looseEnemy = enemy
        end

        if threatVal and threatVal < lowestVal then
            lowestVal = threatVal
            lowestEnemy = enemy
        end

        if not noDiseaseEnemy then
            if not HasFrostFeverOn(enemy) or not HasBloodPlagueOn(enemy) then
                noDiseaseEnemy = enemy
            end
        end

        if dist < closestDist then
            closestDist = dist
            closestEnemy = enemy
        end
    end)

    local result = looseEnemy or lowestEnemy or noDiseaseEnemy or closestEnemy
    if not result and Target:Exists() and not Target:IsDead() and Target:IsEnemy()
       and Player:GetDistance(Target) <= 30 then
        result = Target
    end

    cachedBestTarget = result
    cachedBestTime = now
    return result
end

-- 单体/群体模式：单体只打当前Target，群体走智能选目标
local function GetPrimaryTarget()
    if not Config.AOEMode then
        if Target:Exists() and not Target:IsDead() and Target:IsEnemy()
           and Player:GetDistance(Target) <= 30 then
            return Target
        end
        return nil
    end
    return FindBestTarget()
end

-- ==================== 9步固定序列引擎 ====================
-- 第1组: IT → BB → DnD
-- 第2组: IT → BB → PS
-- 第3组: IT → BB → PS
local cycleStep = 1
local groupTarget = nil

local CYCLE = { "IT", "BB", "DND", "IT", "BB", "PS", "IT", "BB", "PS" }

local function AdvanceCycle()
    cycleStep = cycleStep % 9 + 1
end

local function GetGroupTarget()
    if groupTarget and groupTarget:Exists() and groupTarget:IsAlive() then
        return groupTarget
    end
    return GetPrimaryTarget()
end

local function ExecuteCycleStep()
    local step = CYCLE[cycleStep]

    if step == "IT" then
        groupTarget = GetPrimaryTarget()
        if not groupTarget then return false end
        if TryCast(IcyTouch, groupTarget) then
            AdvanceCycle(); return true
        end
        return false
    end

    if step == "BB" then
        if BloodBoil and BloodBoil:IsKnownAndUsable() then
            PrintSpell(BloodBoil:GetID())
            BloodBoil:Cast(Player)
            AdvanceCycle(); return true
        end
        return false
    end

    if step == "DND" then
        if DeathAndDecay and DeathAndDecay:IsKnownAndUsable() then
            local t = GetGroupTarget()
            local pos = t and t:GetPosition() or Player:GetPosition()
            if TryCastGround(DeathAndDecay, pos) then
                AdvanceCycle(); return true
            end
            return false
        end
        -- DnD 在 CD，降级为 PS
        local t = GetGroupTarget()
        if t and TryCast(PlagueStrike, t) then
            AdvanceCycle(); return true
        end
        return false
    end

    if step == "PS" then
        local t = GetGroupTarget()
        if t and TryCast(PlagueStrike, t) then
            AdvanceCycle(); return true
        end
        return false
    end

    return false
end

-- ==================== 主循环 ====================
DKBloodBB:Sync(function()
    if not TinkrBot.MasterEnabled then return end
    if not Config.Enabled then return end

    if not spellsInitialized then
        if not moduleLoadTime then moduleLoadTime = GetTime() end
        if GetTime() - moduleLoadTime < 0.5 then return end
        InitSpells()
    end

    if ShouldPause() then return end
    if not Player:IsAlive() then return end

    -- ==================== 脱战：维护寒冬号角，重置序列 ====================
    if not UnitAffectingCombat('player') then
        cycleStep = 1
        groupTarget = nil
        if HornOfWinter and HornOfWinter:IsKnownAndUsable() and GetHornOfWinterRemaining() <= 0 then
            HornOfWinter:Cast(Player)
        end
        return
    end

    local anyEnemy = GetPrimaryTarget()
    if not anyEnemy then return end

    if not IsCurrentSpell(6603) then _CastSpellByID(6603) end

    local hp = GetHPPercent()
    local rp = GetRunicPower()

    -- ==================== 打断 ====================
    if Config.InterruptMode ~= "off" then
        local intTargetMelee, intTargetStrang = nil, nil
        Bastion.UnitManager:EnumEnemies(function(enemy)
            if not enemy:IsAlive() or not enemy:IsAffectingCombat() then return end
            if not enemy:IsInterruptible() then return end
            if not Player:CanSee(enemy) then return end
            local dist = Player:GetDistance(enemy)
            if dist <= 3  and not intTargetMelee then intTargetMelee = enemy end
            if dist <= 5  and not intTargetStrang then intTargetStrang = enemy end
        end)
        if intTargetMelee and MindFreeze and MindFreeze:IsKnown() and not MindFreeze:IsOnCooldown() then
            PrintSpell(MindFreeze:GetID())
            MindFreeze:ForceCast(intTargetMelee); return
        end
        if intTargetStrang and Strangulate and Strangulate:IsKnown() and not Strangulate:IsOnCooldown() then
            PrintSpell(Strangulate:GetID())
            Strangulate:ForceCast(intTargetStrang); return
        end
    end

    -- ==================== 生存链（从低到高检查）====================

    -- HP < 20%: 符文武器增效（RP不足以开冰封之韧时先重置符文+25RP）
    if hp <= Config.HPIceboundFort then
        if rp < 20 and EmpowerRuneWeapon and EmpowerRuneWeapon:IsKnownAndUsable() then
            PrintSpell(EmpowerRuneWeapon:GetID(), "紧急重置+25RP")
            EmpowerRuneWeapon:Cast(Player); return
        end
        if TryCast(IceboundFortitude, Player) then return end
    end

    -- HP < 30%: 天灾契约（有食尸鬼直接吃，没食尸鬼先召唤）
    if hp <= Config.HPDeathPact then
        if UnitExists("pet") and DeathPact and DeathPact:IsKnownAndUsable() then
            PrintSpell(DeathPact:GetID(), "吃宠物回40%血")
            DeathPact:Cast(Player); return
        end
        if not UnitExists("pet") and RaiseDead and RaiseDead:IsKnownAndUsable() then
            PrintSpell(RaiseDead:GetID(), "为天灾契约召唤")
            RaiseDead:Cast(Player); return
        end
    end

    -- HP < 40%: 吸血鬼之血
    if hp <= Config.HPVampiricBlood and TryCast(VampiricBlood, Player) then return end

    -- HP < 50%: 符文分流
    if hp <= Config.HPRuneTap and RuneTap and RuneTap:IsKnownAndUsable() then
        RuneTap:Cast(Player); return
    end

    -- AMS: 附近有施法敌人时自动开启
    if AntiMagicShell and AntiMagicShell:IsKnownAndUsable() then
        local hasCaster = false
        Bastion.UnitManager:EnumEnemies(function(enemy)
            if hasCaster then return end
            if not enemy:IsAlive() or not enemy:IsAffectingCombat() then return end
            if Player:GetDistance(enemy) > 20 then return end
            if enemy:IsInterruptible() then hasCaster = true end
        end)
        if hasCaster then
            PrintSpell(AntiMagicShell:GetID())
            AntiMagicShell:Cast(Player); return
        end
    end

    -- ==================== 嘲讽 ====================
    if Config.TauntEnabled and (UnitInRaid("player") or GetNumSubgroupMembers() > 0) then
        if DarkCommand and DarkCommand:IsKnownAndUsable() then
            local tauntTarget = nil
            Bastion.UnitManager:EnumEnemies(function(enemy)
                if tauntTarget then return end
                if not enemy:IsAlive() or not enemy:IsAffectingCombat() then return end
                if Player:GetDistance(enemy) > 30 then return end
                local tok = enemy:GetOMToken()
                local isTanking = UnitDetailedThreatSituation("player", tok)
                if not isTanking then tauntTarget = enemy end
            end)
            if tauntTarget then
                PrintSpell(DarkCommand:GetID())
                DarkCommand:ForceCast(tauntTarget); return
            end
        end
    end

    -- ==================== 符文打击（不占GCD，可用就用）====================
    if RuneStrike and RuneStrike:IsKnownAndUsable() then
        local rsTarget = GetGroupTarget() or anyEnemy
        RuneStrike:Cast(rsTarget)
    end

    -- ==================== HP < 40%: 灵界打击替代序列 ====================
    if hp <= Config.HPDeathStrike and DeathStrike and DeathStrike:IsKnownAndUsable() then
        local dsTarget = GetGroupTarget() or anyEnemy
        if TryCast(DeathStrike, dsTarget) then return end
    end

    -- ==================== 核心循环：9步固定序列 ====================
    if ExecuteCycleStep() then return end

    -- ==================== 间隙填充（符文CD期间）====================

    -- 凋零缠绕泄能（RP >= 90，只对当前目标释放）
    if rp >= Config.RPDeathCoil and Target:Exists() and not Target:IsDead() and TryCast(DeathCoil, Target) then return end

    -- 寒冬号角填充（万能GCD填充，不需要等buff过期，产10RP填空档）
    if HornOfWinter and HornOfWinter:IsKnownAndUsable() then
        HornOfWinter:Cast(Player); return
    end
end)

Bastion:Register(DKBloodBB)
DKBloodBB:Enable()

local Rotation = {
    Name   = "鲜血死亡骑士(血沸流)",
    Class  = "DEATHKNIGHT",
    Module = DKBloodBB,
    Config = Config,
}
TinkrBot.Rotation = Rotation
print("|cFF00FF00[TinkrBot] 鲜血DK(血沸流)已加载|r")
return Rotation
