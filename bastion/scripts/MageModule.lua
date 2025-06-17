local Tinkr, Bastion = ...

-- ===================== 1. 创建模块 =====================
local MageModule = Bastion.Module:New('MageModule')

-- ===================== 2. 获取基础单位 =====================
local Player = Bastion.UnitManager:Get('player')
local Target = Bastion.UnitManager:Get('target')

-- ===================== 3. 创建基础系统 =====================
-- 创建法术书
local SpellBook = Bastion.Globals.SpellBook
-- 创建物品书
local ItemBook = Bastion.Globals.ItemBook
-- 创建计时器
local Timer = Bastion.Timer

-- ===================== 4. 定义技能 =====================
-- 基础技能
local LivingBomb = SpellBook:GetSpell(55360)        -- 活动炸弹
local Pyroblast = SpellBook:GetSpell(42891)         -- 炎爆术
local Fireball = SpellBook:GetSpell(42833)          -- 火球术
local HotStreak = SpellBook:GetSpell(48108)         -- 法术连击
local Spellsteal = SpellBook:GetSpell(30449)        -- 法术吸取
local VoidEnergy = SpellBook:GetSpell(66228)        -- 虚空之能
-- local VoidEnergy = SpellBook:GetSpell(52281)        -- 虚空之能
local Combustion = SpellBook:GetSpell(11129)        -- 燃烧
local Combustionbuff = SpellBook:GetSpell(28682)    -- 燃烧buff
local FireBlast = SpellBook:GetSpell(42873)         -- 火焰冲击
local Berserking = SpellBook:GetSpell(26297)        -- 狂暴
local EngineeringGloves = ItemBook:GetItem(47763)   -- 工程手套
local MirrorImage = SpellBook:GetSpell(55342)       -- 镜像
local IceBarrier = SpellBook:GetSpell(45438)        -- 寒冰屏障（冰箱）
local Frostbolt = SpellBook:GetSpell(42842)           -- 寒冰箭
local QueensKiss = SpellBook:GetSpell(66334)        -- 女王之吻
local Counterspell = SpellBook:GetSpell(2139)       -- 法术反制
local VampiricEmbrace = SpellBook:GetSpell(70674)   -- 吸血鬼之力

-- ===================== 5. 状态追踪 =====================
-- 简单直观的状态变量
local hasCrit = false        -- 是否暴击
local hasHotStreak = false   -- 是否有法术连击
local combustionActive = false    -- 燃烧是否激活
local remainingCrits = 0     -- 燃烧剩余暴击次数

-- 活动炸弹施放计时器
local livingBombTimers = {}

-- 火焰法术ID列表
local fireSpells = {
    [42833] = true,  -- 火球术
    [42859] = true,  -- 灼烧
    [42873] = true,  -- 火焰冲击
    [55362] = true   -- 活动炸弹
}

-- ===================== 6. 目标系统 =====================
-- 找打断目标
local InterruptTarget = Bastion.UnitManager:CreateCustomUnit('interrupttarget', function()
    -- 使用find方法查找第一个符合条件的敌人
    local target = Bastion.ObjectManager.enemies:find(function(unit)
        -- 检查单位是否在施法
        if not unit:IsCastingOrChanneling() then
            return false
        end

        -- 检查是否是目标技能ID (71420或70594)
        local spell = unit:GetCastingOrChannelingSpell()
        local spellID = spell:GetID()
        if not (spellID == 71420 or spellID == 70594) then
            return false
        end
        
        -- 计算施法剩余时间
        local endTime = unit:GetCastingOrChannelingEndTime()
        local remainingTime = endTime - GetTime()
        
        -- 检查剩余时间是否小于1秒
        return remainingTime > 0 and remainingTime < 0.8
            and unit:Exists()
            and unit:IsAlive()
            and unit:IsAffectingCombat()
            and Player:CanSee(unit)
            and Player:IsFacing(unit)
            and Counterspell:IsInRange(unit)
    end)
    
    return target or Bastion.UnitManager:Get('none')
end)

-- 找目标
local BestTarget = Bastion.UnitManager:CreateCustomUnit('besttarget', function()
    local bestTarget = nil
    local highestHealth = 0

    Bastion.ObjectManager.enemies:each(function(unit)
        -- 先检查单位是否存在和存活
        if not (unit:Exists() and unit:IsAlive()) then
            return false
        end

        -- 再检查其他条件
        if unit:IsAffectingCombat()
           and LivingBomb:IsInRange(unit)
           and Player:CanSee(unit)
           and Player:IsFacing(unit)
           and unit:GetName() ~= "冰霜之球" then
            -- 如果没有最佳目标或当前单位血量更高
            if unit:GetHealth() > highestHealth then
                bestTarget = unit
                highestHealth = unit:GetHealth()
            end
        end
    end)

    return bestTarget or Bastion.UnitManager:Get('none')
end)

-- 获取最佳活动炸弹目标
local BestLivingBombTarget = Bastion.UnitManager:CreateCustomUnit('bestlivingbombtarget', function()
    -- 使用each方法遍历敌人列表
    local bestTarget = nil
    local highestHealth = 0

    Bastion.ObjectManager.enemies:each(function(unit)
        -- 先检查单位是否存在和存活
        if not (unit:Exists() and unit:IsAlive()) then
            return false
        end

        -- 检查目标是否在计时器记录内
        if livingBombTimers[unit:GetGUID()] and livingBombTimers[unit:GetGUID()]:GetTime() < 11 then
            return false
        end

        -- 检查目标是否符合所有条件
        if LivingBomb:IsInRange(unit)
           and not unit:GetAuras():FindMy(LivingBomb):IsUp()
           and unit:IsAffectingCombat()
           and Player:CanSee(unit) then
            -- 如果没有最佳目标或当前单位血量更高
            if unit:GetHealth() > highestHealth then
                bestTarget = unit
                highestHealth = unit:GetHealth()
            end
        end
    end)

    return bestTarget or Bastion.UnitManager:Get('none')
end)

-- 寻找可偷取法术的目标
local SpellstealTarget = Bastion.UnitManager:CreateCustomUnit('spellstealtarget', function()
    -- 使用find方法查找第一个符合条件的敌人
    local target = Bastion.ObjectManager.enemies:find(function(unit)
        return (unit:GetAuras():Find(VoidEnergy):IsUp() or unit:GetAuras():Find(VampiricEmbrace):IsUp())
           and unit:IsAlive()
           and unit:IsAffectingCombat()
           and Spellsteal:IsInRange(unit)
           and Player:CanSee(unit)
    end)
    
    return target or Bastion.UnitManager:Get('none')
end)

-- ===================== 7. 辅助函数 =====================
-- 选择目标
local function CheckAndSetTarget()
    if not Target:Exists() or Target:IsFriendly() or not Target:IsAlive() then
        if BestTarget.unit then
            SetTargetObject(BestTarget.unit)
            return true
        end
    end
    return false
end

-- ===================== 8. APL定义 =====================
local DefensiveAPL = Bastion.APL:New('defensive')  -- 防御循环
local SingleTargetAPL = Bastion.APL:New('singletarget')  -- 单体循环
local BurstAPL = Bastion.APL:New('burst')  -- 爆发循环
local AoeAPL = Bastion.APL:New('aoe')      -- AOE循环
local SimpleAPL = Bastion.APL:New('simple')  -- 简单循环

-- ===================== 9. 防御循环 =====================
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

-- 寒冰屏障（冰箱）
DefensiveAPL:AddSpell(
    IceBarrier:CastableIf(function(self)
        return GetKeyState(3)  -- 按下F键时释放
            and not Player:GetAuras():FindMy(IceBarrier):IsUp()  -- 没有寒冰屏障buff
    end):SetTarget(Player):PreCast(function(self)
        if Player:IsCastingOrChanneling() then
            SpellStopCasting()  -- 打断当前施法
        end
    end)
)

-- 取消寒冰屏障（冰箱）
DefensiveAPL:AddAction("CancelIceBarrier", function()
    if not GetKeyState(3)  -- F键松开时
        and Player:GetAuras():FindMy(IceBarrier):IsUp() then  -- 有寒冰屏障buff
        CancelSpellByName("寒冰屏障")
        return true
    end
    return false
end)

-- 法术吸取
DefensiveAPL:AddSpell(
    Spellsteal:CastableIf(function(self)
        return HERUISpellSteal() and
            SpellstealTarget:Exists()
    end):SetTarget(SpellstealTarget):PreCast(function(self)
        if Player:IsCastingOrChanneling() then
            SpellStopCasting()
        end
    end)
)

-- 寒冰箭
DefensiveAPL:AddSpell(
    Frostbolt:CastableIf(function(self)
        return Player:GetAuras():FindAny(QueensKiss):IsUp()
            and (not SpellstealTarget:Exists() or not HERUISpellSteal())
    end):SetTarget(Target):PreCast(function(self)
        if Player:IsCastingOrChanneling() and Player:GetCastingOrChannelingSpell():GetID() ~= 42842 then
            SpellStopCasting()  -- 打断当前施法
        end
    end)
)

-- 法术反制
DefensiveAPL:AddSpell(
    Counterspell:CastableIf(function(self)
        return InterruptTarget:Exists()
    end):SetTarget(InterruptTarget):PreCast(function(self)
        if Player:IsCastingOrChanneling() then
            SpellStopCasting()  -- 打断当前施法
        end
    end)
)

-- ===================== 10. 爆发循环 =====================
-- 工程手套
BurstAPL:AddItem(
    EngineeringGloves:UsableIf(function(self)
        return Target:Exists()
            and self:IsEquipped()
            and self:IsUsable()
            and not self:IsOnCooldown()
            and (Player:GetAuras():FindMy(Combustionbuff):IsUp() or Combustion:GetCooldownRemaining() > 10)
    end):SetTarget(Player)
)

-- 狂暴
BurstAPL:AddSpell(
    Berserking:CastableIf(function(self)
        return Target:Exists()
            and self:IsKnownAndUsable()
            and (Player:GetAuras():FindMy(Combustionbuff):IsUp() or Combustion:GetCooldownRemaining() > 10)
    end):SetTarget(Player)
)

-- 镜像
BurstAPL:AddSpell(
    MirrorImage:CastableIf(function(self)
        return Target:Exists()
            and self:IsKnownAndUsable()
            and (Player:GetAuras():FindMy(Combustionbuff):IsUp() or Combustion:GetCooldownRemaining() > 10)
    end):SetTarget(Player)
)

-- 燃烧
BurstAPL:AddSpell(
    Combustion:CastableIf(function(self)
        return Target:Exists()
            and self:IsKnownAndUsable()
            and Target:GetAuras():FindMy(LivingBomb):GetRemainingTime() > 7  -- 确保目标身上的活动炸弹debuff剩余时间充足
            and not Player:GetAuras():FindMy(HotStreak):IsUp()
    end):SetTarget(Player)
)

-- ===================== 11. AOE循环 =====================
-- 活动炸弹（多目标优先）
AoeAPL:AddSpell(
    LivingBomb:CastableIf(function(self)
        if Player:GetAuras():FindMy(HotStreak):IsUp() and hasCrit == true then
            return false
        end
        return BestLivingBombTarget:Exists()
            and self:IsKnownAndUsable()
            and not Player:GetAuras():FindMy(Combustionbuff):IsUp()
    end):SetTarget(BestLivingBombTarget)
)

-- 炎爆术（法术连击触发时）
AoeAPL:AddSpell(
    Pyroblast:CastableIf(function(self)
        return Target:Exists()
            and self:IsKnownAndUsable()
            and Player:GetAuras():FindMy(HotStreak):IsUp()  -- 有法术连击特效
            and (
                (Player:IsCasting() and Player:GetAuras():FindMy(Combustionbuff):IsUp() and remainingCrits == 1)
                or not Player:GetAuras():FindMy(Combustionbuff):IsUp()
            )
    end):SetTarget(Target)
)

-- 火焰冲击（目标有活动炸弹且玩家移动且无法术连击时）
AoeAPL:AddSpell(
    FireBlast:CastableIf(function(self)
        return Target:Exists()
            and self:IsKnownAndUsable()
            and Target:GetAuras():FindMy(LivingBomb):IsUp()  -- 目标有活动炸弹debuff
            and not Player:GetAuras():FindMy(HotStreak):IsUp()  -- 玩家没有法术连击buff
            and Player:IsMoving()  -- 玩家在移动中
    end):SetTarget(Target)
)

-- 火球术填充
AoeAPL:AddSpell(
    Fireball:CastableIf(function(self)
        return Target:Exists()
            and self:IsKnownAndUsable()
    end):SetTarget(Target)
)

-- ===================== 12. 单体循环 =====================

-- 活动炸弹（单目标）
SingleTargetAPL:AddSpell(
    LivingBomb:CastableIf(function(self)
        if Player:GetAuras():FindMy(HotStreak):IsUp() and hasCrit == true then
            return false
        end

        -- 检查目标是否存在且可以使用技能
        if not (Target:Exists() and self:IsKnownAndUsable()) then
            return false
        end

        -- 检查目标是否已有debuff
        if Target:GetAuras():FindMy(LivingBomb):IsUp() then
            return false
        end

        -- 检查玩家是否有燃烧buff
        if Player:GetAuras():FindMy(Combustionbuff):IsUp() then
            return false
        end

        return true
    end):SetTarget(Target)
)

-- 炎爆术（法术连击触发时）
SingleTargetAPL:AddSpell(
    Pyroblast:CastableIf(function(self)
        return Target:Exists()
            and self:IsKnownAndUsable()
            and Player:GetAuras():FindMy(HotStreak):IsUp()  -- 有法术连击特效
            and (
                (Player:IsCasting() and Player:GetAuras():FindMy(Combustionbuff):IsUp() and remainingCrits == 1)
                or not Player:GetAuras():FindMy(Combustionbuff):IsUp()
            )
    end):SetTarget(Target)
)

-- 火焰冲击（目标有活动炸弹且玩家移动且无法术连击时）
SingleTargetAPL:AddSpell(
    FireBlast:CastableIf(function(self)
        return Target:Exists()
            and self:IsKnownAndUsable()
            and Target:GetAuras():FindMy(LivingBomb):IsUp()  -- 目标有活动炸弹debuff
            and not Player:GetAuras():FindMy(HotStreak):IsUp()  -- 玩家没有法术连击buff
            and Player:IsMoving()  -- 玩家在移动中
    end):SetTarget(Target)
)

-- 火球术填充
SingleTargetAPL:AddSpell(
    Fireball:CastableIf(function(self)
        return Target:Exists()
            and self:IsKnownAndUsable()
    end):SetTarget(Target)
)

-- ===================== 13. 简单循环 =====================
-- 炎爆术（法术连击触发时）
SimpleAPL:AddSpell(
    Pyroblast:CastableIf(function(self)
        return Target:Exists()
            and self:IsKnownAndUsable()
            and Player:GetAuras():FindMy(HotStreak):IsUp()  -- 有法术连击特效
    end):SetTarget(Target)
)

-- 火焰冲击（目标有活动炸弹且玩家移动且无法术连击时）
SimpleAPL:AddSpell(
    FireBlast:CastableIf(function(self)
        return Target:Exists()
            and self:IsKnownAndUsable()
            and Target:GetAuras():FindMy(LivingBomb):IsUp()  -- 目标有活动炸弹debuff
            and not Player:GetAuras():FindMy(HotStreak):IsUp()  -- 玩家没有法术连击buff
            and Player:IsMoving()  -- 玩家在移动中
    end):SetTarget(Target)
)

-- 火球术填充
SimpleAPL:AddSpell(
    Fireball:CastableIf(function(self)
        return Target:Exists()
            and self:IsKnownAndUsable()
    end):SetTarget(Target)
)

-- ===================== 14. 模块同步 =====================
MageModule:Sync(function()
    if Player:IsAffectingCombat() then
        CheckAndSetTarget()
    end

    DefensiveAPL:Execute()

    if GetKeyState(58) then
        BurstAPL:Execute()
    end

    if HERUIAOE() then
        AoeAPL:Execute()
    end

    if HERUINormal() then
        SingleTargetAPL:Execute()
    end

    if HERUISimple() then
        SimpleAPL:Execute()
    end
end)

Bastion:Register(MageModule)


-- ===================== 15. 战斗事件 =====================
Bastion.Globals.EventManager:RegisterWoWEvent('COMBAT_LOG_EVENT_UNFILTERED', function()
    local _, class = UnitClass("player")
    if class ~= "MAGE" then return end

    local _, event, _, sourceGUID, _, _, _, destGUID, _, _, _, spellId, spellName, _, _, _, _, _, _, _, critical = CombatLogGetCurrentEventInfo()
    if sourceGUID ~= Player:GetGUID() then return end

    -- 检测女王之吻buff获得
    if event == "SPELL_AURA_APPLIED" and spellId == 66334 then
        if Player:GetCastingOrChannelingSpell() and Player:GetCastingOrChannelingSpell():GetID() ~= 42842 then
            SpellStopCasting()
            if Target:Exists() and (not SpellstealTarget:Exists() or not HERUISpellSteal()) then
                Frostbolt:Cast(Target)
            end
        end
    end

    -- 检查法术暴击用
    if event == "SPELL_DAMAGE" and fireSpells[spellId] then
        hasCrit = critical and true or false

        -- 燃烧效果暴击追踪
        if Player:GetAuras():FindMy(Combustionbuff):IsUp() and critical and combustionActive then
            remainingCrits = remainingCrits - 1
        end
    end

    -- 检测活动炸弹施放
    if spellId == 55360 and event == "SPELL_CAST_SUCCESS" then
        if not livingBombTimers[destGUID] then
            livingBombTimers[destGUID] = Timer:New('livingbomb')
        else
            livingBombTimers[destGUID]:Reset()
        end
        livingBombTimers[destGUID]:Start()
    end

    -- 燃烧效果开始
    if event == "SPELL_AURA_APPLIED" and spellId == 28682 then
        combustionActive = true
        remainingCrits = 3
    end

    -- 燃烧效果结束
    if event == "SPELL_AURA_REMOVED" and spellId == 28682 then
        combustionActive = false
        remainingCrits = 0
    end

    -- 当法术连击首次触发时，重置暴击状态
    if event == "SPELL_AURA_APPLIED" and spellId == 48108 and not hasHotStreak then
        hasCrit = false
        hasHotStreak = true
    elseif event == "SPELL_AURA_REMOVED" and spellId == 48108 then
        hasHotStreak = false
    end
end)
