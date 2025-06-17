local Tinkr, Bastion = ...

-- 创建模块
local RetributionPaladinModule = Bastion.Module:New('RetributionPaladinModule')

-- 获取玩家和目标单位
local Player = Bastion.UnitManager:Get('player')
local Target = Bastion.UnitManager:Get('target')

-- 创建法术书（用于获取和管理技能）
local SpellBook = Bastion.Globals.SpellBook
-- 创建物品书
local ItemBook = Bastion.Globals.ItemBook

-- 定义技能
-- 基础技能
-- local AutoAttack = SpellBook:GetSpell(6603)            -- 自动攻击
local HammerOfWrath = SpellBook:GetSpell(48806)        -- 愤怒之锤
local CrusaderStrike = SpellBook:GetSpell(35395)       -- 十字军打击
local Exorcism = SpellBook:GetSpell(48801)             -- 驱邪术
local JudgementOfWisdom = SpellBook:GetSpell(53408)    -- 智慧审判
local JudgementOfLight = SpellBook:GetSpell(20271)     -- 圣光审判
local JudgementOfJustice = SpellBook:GetSpell(53407)   -- 公正审判
local Consecration = SpellBook:GetSpell(48819)         -- 奉献(单体用)
local DivineStorm = SpellBook:GetSpell(53385)          -- 神圣风暴(单体用)
local HandOfReckoning = SpellBook:GetSpell(62124)      -- 清算之手
local DivinePlea = SpellBook:GetSpell(54428)           -- 神圣恳求
local ArcaneTorrent = SpellBook:GetSpell(28730)        -- 奥术洪流
local DivineShield = SpellBook:GetSpell(642)           -- 圣盾术

-- AOE专用技能对象(创建真正独立的技能副本)
local Consecration_AOE = SpellBook:GetSpell(48819):Fresh()     -- 奉献(AOE用)
local DivineStorm_AOE = SpellBook:GetSpell(53385):Fresh()      -- 神圣风暴(AOE用)
local HolyWrath_AOE = SpellBook:GetSpell(48817):Fresh()        -- 神圣愤怒(AOE用)

-- 圣印
local SealOfCommand = SpellBook:GetSpell(20375)        -- 命令圣印
local SealOfCorruption = SpellBook:GetSpell(348704)    -- 腐蚀圣印

-- Buff与Debuff
local ArtOfWarBuff = SpellBook:GetSpell(59578)         -- 战争艺术Buff（使驱邪术瞬发）


-- 斩杀目标（生命值低于20%的目标）
local ExecuteTarget = Bastion.UnitManager:CreateCustomUnit('executetarget', function()
    -- 检查目标是否满足斩杀条件的函数（目标生命值低于20%）
    local function IsValidExecuteTarget(unit)
        return unit:IsAlive()
            and unit:GetHP() < 20
            and HammerOfWrath:IsInRange(unit)
            and unit:Exists()
            and Player:IsFacing(unit)
            and unit:IsAffectingCombat()
    end

    -- 首先检查当前目标是否满足斩杀条件
    if Target:Exists() and Target:IsAlive() and Target:GetHP() < 20 then
        return Target
    end

    -- 使用each方法查找血量最高的满足斩杀条件的目标
    local highestHpTarget = nil
    local highestHp = 0
    
    Bastion.ObjectManager.enemies:each(function(unit)
        if IsValidExecuteTarget(unit) then
            local currentHp = unit:GetHealth()
            if currentHp > highestHp then
                highestHp = currentHp
                highestHpTarget = unit
            end
        end
    end)

    return highestHpTarget or Bastion.UnitManager:Get('none')
end)

-- 寻找最佳目标（在近战范围内且面向玩家的敌人）
local BestTarget = Bastion.UnitManager:CreateCustomUnit('besttarget', function()
    -- 检查目标是否满足条件的函数
    local function IsValidTarget(unit)
        return unit:Exists()
            and unit:IsAlive()
            and unit:IsAffectingCombat()
            and Player:IsFacing(unit)
            and unit:InMelee(Player)
    end

    -- 使用each方法寻找血量最高的满足条件的敌人
    local highestHpTarget = nil
    local highestHp = 0
    
    Bastion.ObjectManager.enemies:each(function(unit)
        if IsValidTarget(unit) then
            local currentHp = unit:GetHealth()
            if currentHp > highestHp then
                highestHp = currentHp
                highestHpTarget = unit
            end
        end
    end)
    
    -- 如果没找到合适目标，返回none
    return highestHpTarget or Bastion.UnitManager:Get('none')
end)

-- 目标选择逻辑（当前目标不存在或不适合攻击时，选择新目标）
local function CheckAndSetTarget()
    -- 如果当前目标不存在，或是友善的，或已死亡
    if not Target:Exists() 
        or Target:IsFriendly() 
        or not Target:IsAlive() then
        if BestTarget.unit then
            SetTargetObject(BestTarget.unit)
            return true
        end
    end
    return false
end

-- 获取指定范围内的敌人数量（用于AOE技能判断）
local function GetEnemiesInRange(range)
    local count = 0
    Bastion.ObjectManager.enemies:each(function(unit)
        if unit:IsAffectingCombat() and unit:GetCombatDistance(Player) < range and unit:IsAlive() and unit:Exists() then
            count = count + 1
        end
    end)
    return count
end

-- 获取指定范围内的恶魔或亡灵敌人数量（用于神圣愤怒AOE判断）
local function GetDemonOrUndeadEnemiesInRange(range)
    local count = 0
    Bastion.ObjectManager.enemies:each(function(unit)
        if unit:IsAffectingCombat() 
           and unit:GetCombatDistance(Player) < range 
           and unit:IsAlive() 
           and unit:Exists() then
            local creatureType = UnitCreatureType(unit:GetOMToken())
            if creatureType == "恶魔" or creatureType == "亡灵" then
                count = count + 1
            end
        end
    end)
    return count
end

-- ===================== APL定义（行动优先级列表）=====================
local DefaultAPL = Bastion.APL:New('default')         -- 默认单体目标输出循环
local ResourceAPL = Bastion.APL:New('resource')       -- 法力资源管理循环
local AoeAPL = Bastion.APL:New('aoe')                 -- 多目标范围伤害循环
local DefensiveAPL = Bastion.APL:New('defensive')     -- 防御循环
local SimpleAPL = Bastion.APL:New('simple')           -- 简单循环

-- ===================== 防御循环 =====================
-- 治疗石
DefensiveAPL:AddAction("UseHealingStone", function()
    -- 先检查血量，避免不必要的背包搜索
    if Player:GetHP() <= 50 and Player:IsAffectingCombat() then
        local healingStone = ItemBook:GetItemByName("治疗石")
        if healingStone and not healingStone:IsOnCooldown() then
            healingStone:Use(Player)
            return true
        end
    end
    return false
end)

-- 圣盾术
DefensiveAPL:AddSpell(
    DivineShield:CastableIf(function(self)
        return GetKeyState(3)
    end):SetTarget(Player):PreCast(function(self)
        if Player:IsCastingOrChanneling() then
            SpellStopCasting()  -- 打断当前施法
        end
    end)
)

-- -- 自动攻击
-- DefensiveAPL:AddSpell(
--     AutoAttack:CastableIf(function(self)
--         return Target:Exists() 
--             and Target:IsAlive()
--             and Player:InMelee(Target)
--             and not IsCurrentSpell(6603)
--     end):SetTarget(Target)
-- )

-- 清算之手（嘲讽）
DefensiveAPL:AddSpell(
    HandOfReckoning:CastableIf(function(self)
        return Target:Exists()
            and Target:IsAlive()
            and self:IsKnownAndUsable()
            and HammerOfWrath:IsInRange(Target)
    end):SetTarget(Target)
)

-- ===================== 法力资源管理循环 =====================
-- 愤怒之锤（斩杀阶段，目标生命值低于20%时使用）
ResourceAPL:AddSpell(
    HammerOfWrath:CastableIf(function(self)
        return ExecuteTarget:Exists()
            and self:IsOnCooldown()
            and Player:IsAffectingCombat()
    end):SetTarget(ExecuteTarget)
)

-- 腐蚀圣印（单体战斗，提高伤害输出）
ResourceAPL:AddSpell(
    SealOfCorruption:CastableIf(function(self)
        return Target:Exists()
            and HERUICorruptionSeal()
            and Target:IsAlive()
            and not Player:GetAuras():FindMy(SealOfCorruption):IsUp()
            and self:IsKnownAndUsable()
    end):SetTarget(Player)
)

-- 命令圣印（AOE情景，提高多目标伤害）
ResourceAPL:AddSpell(
    SealOfCommand:CastableIf(function(self)
        return Target:Exists()
            and HERUICommandSeal()
            and Target:IsAlive()
            and not Player:GetAuras():FindMy(SealOfCommand):IsUp()  -- 没有命令圣印buff
            and self:IsKnownAndUsable()
    end):SetTarget(Player)
)

-- 奥术洪流（血精灵种族技能，恢复法力值）
ResourceAPL:AddSpell(
    ArcaneTorrent:CastableIf(function(self)
        -- 基础条件检查
        return self:IsKnownAndUsable()  -- 检查技能是否可用
            and Player:GetPP() < 70  -- 检查法力值是否低于70%
            and not Player:GetAuras():FindMy(DivinePlea):IsUp()  -- 检查是否已有神圣恳求buff
            and DivinePlea:GetCooldownRemaining() > 5  -- 神圣恳求CD大于5秒
            and (
                -- 主要技能在冷却中
                (CrusaderStrike:GetCooldownRemaining() > 0.5 and      -- 十字军打击冷却中
                JudgementOfWisdom:GetCooldownRemaining() > 0.5 and    -- 智慧审判冷却中较长
                DivineStorm:GetCooldownRemaining() > 0.5 and          -- 神圣风暴冷却中
                Consecration:GetCooldownRemaining() > 0.5)            -- 奉献冷却中
                or
                -- 不在近战范围内
                not Player:InMelee(Target)
            )
    end):SetTarget(Player)
)

-- 神圣恳求（当法力值低于90%且审判冷却较长时使用）
ResourceAPL:AddSpell(
    DivinePlea:CastableIf(function(self)
        -- 基础条件检查
        return Player:GetPP() < 90  -- 检查法力值是否低于90%
            and not Player:GetAuras():FindMy(DivinePlea):IsUp()  -- 检查是否已有神圣恳求buff
            and (
                -- 主要技能在冷却中
                (CrusaderStrike:GetCooldownRemaining() > 0.5 and      -- 十字军打击冷却中
                JudgementOfWisdom:GetCooldownRemaining() > 0.5 and    -- 智慧审判冷却中较长
                DivineStorm:GetCooldownRemaining() > 0.5 and          -- 神圣风暴冷却中
                Consecration:GetCooldownRemaining() > 0.5)            -- 奉献冷却中
                or
                -- 不在近战范围内
                not Player:InMelee(Target)
            )
    end):SetTarget(Player)
)

-- 智慧审判（对Boss和精英怪，回蓝）
ResourceAPL:AddSpell(
    JudgementOfWisdom:CastableIf(function(self)
        return Target:Exists()
            and Target:IsAlive()
            and not Player:InMelee(Target)
            and HERUIWisdomJudgement()
            and self:IsKnownAndUsable()
            and JudgementOfWisdom:IsInRange(Target)
    end):SetTarget(Target)
)

-- ===================== 默认单体循环 =====================
-- 十字军打击（主要输出技能）
DefaultAPL:AddSpell(
    CrusaderStrike:CastableIf(function(self)
        return Target:Exists()
            and Target:IsAlive()
            and Player:InMelee(Target)
            and self:IsKnownAndUsable()
    end):SetTarget(Target)
)

-- 智慧审判（对Boss和精英怪，回蓝）
DefaultAPL:AddSpell(
    JudgementOfWisdom:CastableIf(function(self)
        return Target:Exists()
            and Target:IsAlive()
            and CrusaderStrike:GetCooldownRemaining() > 0.5
            and HERUIWisdomJudgement()
            and self:IsKnownAndUsable()
            and JudgementOfWisdom:IsInRange(Target)
    end):SetTarget(Target)
)

-- 圣光审判（玩家血量低于60%时，回血）
DefaultAPL:AddSpell(
    JudgementOfLight:CastableIf(function(self)
        return Target:Exists()
            and Target:IsAlive()
            and CrusaderStrike:GetCooldownRemaining() > 0.5
            and HERUILightJudgement()
            and self:IsKnownAndUsable()
            and JudgementOfWisdom:IsInRange(Target)
    end):SetTarget(Target)
)

-- 公正审判（其他情况，减速目标）
DefaultAPL:AddSpell(
    JudgementOfJustice:CastableIf(function(self)
        return Target:Exists()
            and Target:IsAlive()
            and CrusaderStrike:GetCooldownRemaining() > 0.5
            and HERUIJusticeJudgement()
            and self:IsKnownAndUsable()
            and JudgementOfWisdom:IsInRange(Target)
    end):SetTarget(Target)
)

-- 神圣风暴（单体输出技能）
DefaultAPL:AddSpell(
    DivineStorm:CastableIf(function(self)
        return Target:Exists()
            and Target:IsEnemy()
            and Target:IsAlive()
            and Player:InMelee(Target)
            and CrusaderStrike:GetCooldownRemaining() > 0.5
            and self:IsKnownAndUsable()
    end):SetTarget(Player)
)

-- 奉献（范围伤害）
DefaultAPL:AddSpell(
    Consecration:CastableIf(function(self)
        return Target:Exists()
            and Target:IsAlive()
            and Target:IsEnemy()
            and Player:InMelee(Target)
            and self:IsKnownAndUsable()
            and CrusaderStrike:GetCooldownRemaining() > 0.5
            and not Player:IsMoving()
    end):SetTarget(Player)
)

-- 驱邪术（远程输出或战争艺术触发时）
DefaultAPL:AddSpell(
    Exorcism:CastableIf(function(self)
        return Target:Exists()
            and Target:IsAlive()
            and Player:GetAuras():FindMy(ArtOfWarBuff):IsUp()
            and self:IsKnownAndUsable()
            and CrusaderStrike:GetCooldownRemaining() > 0.5
            and JudgementOfWisdom:GetCooldownRemaining() > 0.5
    end):SetTarget(Target)
)

-- ===================== AOE多目标循环 =====================
-- 十字军打击（主要近战输出技能）
AoeAPL:AddSpell(
    CrusaderStrike:CastableIf(function(self)
        return Target:Exists()
            and Target:IsAlive()
            and Player:InMelee(Target)
            and self:IsKnownAndUsable()
    end):SetTarget(Target)
)

-- 奉献（至少4个目标时优先使用）
AoeAPL:AddSpell(
    Consecration_AOE:CastableIf(function(self)
        return Target:Exists()
            and Target:IsAlive()
            and CrusaderStrike:GetCooldownRemaining() > 0.5
            and GetEnemiesInRange(10) >= 4
            and Player:InMelee(Target)
            and self:IsKnownAndUsable()
            and not Player:IsMoving()
    end):SetTarget(Player):PreCast(function(self)
        if HERUIJump() then
            JumpOrAscendStart()
        end
    end)
)

-- 神圣风暴（多目标输出技能）
AoeAPL:AddSpell(
    DivineStorm_AOE:CastableIf(function(self)
        return Target:Exists()
            and Target:IsAlive()
            and Target:IsEnemy()
            and CrusaderStrike:GetCooldownRemaining() > 0.5
            and Player:InMelee(Target)
            and self:IsKnownAndUsable()
    end):SetTarget(Player):PreCast(function(self)
        if HERUIJump() then
            JumpOrAscendStart()
        end
    end)
)

-- 奉献（常规AOE输出）
AoeAPL:AddSpell(
    Consecration_AOE:CastableIf(function(self)
        return Target:Exists()
            and Target:IsAlive()
            and Target:IsEnemy()
            and CrusaderStrike:GetCooldownRemaining() > 0.5
            and Player:InMelee(Target)
            and self:IsKnownAndUsable()
            and not Player:IsMoving()
    end):SetTarget(Player):PreCast(function(self)
        if HERUIJump() then
            JumpOrAscendStart()
        end
    end)
)

-- 神圣愤怒（对恶魔和亡灵的AOE技能）
AoeAPL:AddSpell(
    HolyWrath_AOE:CastableIf(function(self)
        return Target:Exists()
            and Target:IsAlive()
            and Player:InMelee(Target)
            and self:IsKnownAndUsable()
            and CrusaderStrike:GetCooldownRemaining() > 0.5
            and GetDemonOrUndeadEnemiesInRange(10) >= 4  -- 检测周围10码范围内是否有至少4个恶魔或亡灵类型的敌人
    end):SetTarget(Player):PreCast(function(self)
        if HERUIJump() then
            JumpOrAscendStart()
        end
    end)
)

-- 智慧审判（对Boss和精英怪，回蓝）
AoeAPL:AddSpell(
    JudgementOfWisdom:CastableIf(function(self)
        return Target:Exists()
            and Target:IsAlive()
            and CrusaderStrike:GetCooldownRemaining() > 0.5
            and HERUIWisdomJudgement()
            and self:IsKnownAndUsable()
            and JudgementOfWisdom:IsInRange(Target)
    end):SetTarget(Target)
)

-- 圣光审判（玩家血量低于60%时，回血）
AoeAPL:AddSpell(
    JudgementOfLight:CastableIf(function(self)
        return Target:Exists()
            and Target:IsAlive()
            and CrusaderStrike:GetCooldownRemaining() > 0.5
            and HERUILightJudgement()
            and self:IsKnownAndUsable()
            and JudgementOfWisdom:IsInRange(Target)
    end):SetTarget(Target)
)

-- 公正审判（其他情况，减速目标）
AoeAPL:AddSpell(
    JudgementOfJustice:CastableIf(function(self)
        return Target:Exists()
            and Target:IsAlive()
            and CrusaderStrike:GetCooldownRemaining() > 0.5
            and HERUIJusticeJudgement()
            and self:IsKnownAndUsable()
            and JudgementOfWisdom:IsInRange(Target)
    end):SetTarget(Target)
)

-- 驱邪术（远程输出或战争艺术触发时）
AoeAPL:AddSpell(
    Exorcism:CastableIf(function(self)
        return Target:Exists()
            and Target:IsAlive()
            and Player:GetAuras():FindMy(ArtOfWarBuff):IsUp()
            and CrusaderStrike:GetCooldownRemaining() > 0.5
            and self:IsKnownAndUsable()
    end):SetTarget(Target)
)

-- ===================== 简单循环 =====================
-- 十字军打击（主要输出技能）
SimpleAPL:AddSpell(
    CrusaderStrike:CastableIf(function(self)
        return Target:Exists()
            and Target:IsAlive()
            and Player:InMelee(Target)
            and self:IsKnownAndUsable()
    end):SetTarget(Target)
)

-- 智慧审判（对Boss和精英怪，回蓝）
SimpleAPL:AddSpell(
    JudgementOfWisdom:CastableIf(function(self)
        return Target:Exists()
            and Target:IsAlive()
            and CrusaderStrike:GetCooldownRemaining() > 0.5
            and HERUIWisdomJudgement()
            and self:IsKnownAndUsable()
            and JudgementOfWisdom:IsInRange(Target)
    end):SetTarget(Target)
)

-- 圣光审判（玩家血量低于60%时，回血）
SimpleAPL:AddSpell(
    JudgementOfLight:CastableIf(function(self)
        return Target:Exists()
            and Target:IsAlive()
            and CrusaderStrike:GetCooldownRemaining() > 0.5
            and HERUILightJudgement()
            and self:IsKnownAndUsable()
            and JudgementOfWisdom:IsInRange(Target)
    end):SetTarget(Target)
)

-- 公正审判（其他情况，减速目标）
SimpleAPL:AddSpell(
    JudgementOfJustice:CastableIf(function(self)
        return Target:Exists()
            and Target:IsAlive()
            and CrusaderStrike:GetCooldownRemaining() > 0.5
            and HERUIJusticeJudgement()
            and self:IsKnownAndUsable()
            and JudgementOfWisdom:IsInRange(Target)
    end):SetTarget(Target)
)

-- 神圣风暴（单体输出技能）
SimpleAPL:AddSpell(
    DivineStorm:CastableIf(function(self)
        return Target:Exists()
            and Target:IsEnemy()
            and Target:IsAlive()
            and Player:InMelee(Target)
            and CrusaderStrike:GetCooldownRemaining() > 0.5
            and self:IsKnownAndUsable()
    end):SetTarget(Player)
)

-- 驱邪术（远程输出或战争艺术触发时）
SimpleAPL:AddSpell(
    Exorcism:CastableIf(function(self)
        return Target:Exists()
            and Target:IsAlive()
            and Player:GetAuras():FindMy(ArtOfWarBuff):IsUp()
            and self:IsKnownAndUsable()
            and CrusaderStrike:GetCooldownRemaining() > 0.5
            and JudgementOfWisdom:GetCooldownRemaining() > 0.5
    end):SetTarget(Target)
)

-- ===================== 模块同步执行逻辑 =====================

RetributionPaladinModule:Sync(function()
    -- 最高优先级：防御循环
    DefensiveAPL:Execute()
    -- 次高优先级：法力资源管理和圣印维持
    ResourceAPL:Execute()
    -- 战斗中切目标（当前目标不存在或不适合攻击时）
    if Player:IsAffectingCombat() then
        CheckAndSetTarget()
    end
    -- 多目标AOE循环（当满足AOE条件时执行）
    if HERUIAOE() then
        AoeAPL:Execute()
    end
    -- 默认单体输出循环（当满足单体输出条件时执行）
    if HERUINormal() then
        DefaultAPL:Execute()
    end
    -- 简单模式（不使用奉献）
    if HERUISimple() then
        SimpleAPL:Execute()
    end
end)

-- ===================== 注册模块 =====================
Bastion:Register(RetributionPaladinModule)