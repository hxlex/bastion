local Tinkr, Bastion = ...

-- 创建模块
local HunterModule = Bastion.Module:New('HunterModule')

-- 获取玩家和目标单位
local Player = Bastion.UnitManager:Get('player')
local Target = Bastion.UnitManager:Get('target')
local Pet = Bastion.UnitManager:Get('pet')
local PetTarget = Bastion.UnitManager:Get('pettarget')

-- 创建法术书
local SpellBook = Bastion.Globals.SpellBook
-- 创建物品书
local ItemBook = Bastion.Globals.ItemBook
-- 添加新变量来跟踪T键触发的威慑
local isTKeyIntimidationActive = false
-- 定义技能
-- 基础技能
local LeechingSwarm = SpellBook:GetSpell(66118)           -- 吸血虫群
local shalumingling = SpellBook:GetSpell(34026)           -- 杀戮命令
local MendPet = SpellBook:GetSpell(48990)                 -- 治疗宠物
local Intimidation = SpellBook:GetSpell(19263)            -- 威慑
local ConcussiveShot = SpellBook:GetSpell(5116)           -- 震荡射击
local FrostTrap = SpellBook:GetSpell(13810)               -- 冰霜陷阱
local HolyWrath = SpellBook:GetSpell(48817)               -- 神圣愤怒
local HammerOfJustice = SpellBook:GetSpell(10308)         -- 制裁之锤
local kuishe = SpellBook:GetSpell(34074)                  -- 蝰蛇守护
local longying = SpellBook:GetSpell(61847)                -- 龙鹰守护
local TrapSpell = SpellBook:GetSpell(425777)              -- 爆炸陷阱
local MultiShotSpell = SpellBook:GetSpell(58434)          -- 乱射范围技能
local KillShot = SpellBook:GetSpell(61006)                -- 杀戮射击
local SteadyShot = SpellBook:GetSpell(49052)              -- 稳固射击
local ExplosiveShot = SpellBook:GetSpell(60053)           -- 爆炸射击（4级）
local ExplosiveShott = SpellBook:GetSpell(60052)          -- 爆炸射击（3级）
local BlackArrow = SpellBook:GetSpell(63672)              -- 黑箭
local AimedShot = SpellBook:GetSpell(49050)               -- 瞄准射击
local MultiShot = SpellBook:GetSpell(49048)               -- 多重射击
local Serpent = SpellBook:GetSpell(49001)                 -- 毒蛇钉刺
local HuntersMark = SpellBook:GetSpell(53338)             -- 猎人印记
local heqiang = SpellBook:GetSpell(56453)                 -- 荷枪实弹
local Cower = SpellBook:GetSpell(1742)                    -- 畏缩
local FeignDeath = SpellBook:GetSpell(5384)               -- 假死

-- 寻找最佳目标
local BestTarget = Bastion.UnitManager:CreateCustomUnit('besttarget', function()
    local bestTarget = nil
    local highestHealth = 0

    -- 遍历所有敌人，寻找最适合的目标
    Bastion.ObjectManager.enemies:each(function(unit)
        -- 检查目标是否符合条件：
        -- 1. 正在战斗中
        -- 2. 在35码范围内
        -- 3. 玩家可以看见该目标
        -- 4. 目标距离玩家至少5码
        -- 5. 玩家面向该目标
        if unit:IsAffectingCombat() and ExplosiveShot:IsInRange(unit)
        and Player:CanSee(unit) and unit:IsAlive() and unit:Exists()
        and Player:IsFacing(unit) and unit:GetName() ~= "冰霜之球" then
            -- 如果没有最佳目标或当前单位血量更高
            if unit:GetHealth() > highestHealth then
                highestHealth = unit:GetHealth()
                bestTarget = unit
            end
        end
    end)

    -- 如果没找到合适目标，返回空目标
    return bestTarget or Bastion.UnitManager:Get('none')
end)

-- 选择目标
local function CheckAndSetTarget()
    if not Target:Exists() or Target:IsFriendly() or not Target:IsAlive() then
        if BestTarget.unit then -- 检查返回值有效
            -- 设置最佳目标为当前目标
            SetTargetObject(BestTarget.unit)
            return true
        end
    end
    return false
end

-- 检查目标是否为艾蒂丝、菲奥拉、小宝或大臭
local function IsTargetBoss()
    return Bastion.ObjectManager.enemies:find(function(unit)
        return unit:GetName() and (string.find(unit:GetName(), "艾蒂丝") or string.find(unit:GetName(), "菲奥拉") or string.find(unit:GetName(), "小宝") or string.find(unit:GetName(), "大臭"))
    end) ~= nil
end

-- 寻找可斩杀目标（生命值低于20%）
local ExecuteTarget = Bastion.UnitManager:CreateCustomUnit('executetarget', function()
    -- 检查目标是否满足斩杀条件的函数
    local function IsValidExecuteTarget(unit)
        return unit:Exists()
            and unit:IsAffectingCombat()
            and KillShot:IsInRange(unit)
            and Player:CanSee(unit)
            and unit:IsAlive()
            and unit:GetHP() < 20
            and unit:GetName() ~= "坍缩星"
            and Player:IsFacing(unit)
    end

    -- 首先检查当前目标是否满足斩杀条件
    if Player:IsAffectingCombat() and Target:Exists() and Target:IsAlive() and Target:GetHP() < 20 then
        return Target
    end

    -- 使用each方法遍历所有敌人，找出血量最高的目标
    local highestHpTarget = nil
    local highestHp = 0 -- 初始设置为0

    Bastion.ObjectManager.enemies:each(function(unit)
        if IsValidExecuteTarget(unit) and unit:GetHP() > highestHp then
            highestHp = unit:GetHP()
            highestHpTarget = unit
        end
    end)

    return highestHpTarget or Bastion.UnitManager:Get('none')
end)



-- ===================== APL定义 =====================
local DefaultAPL = Bastion.APL:New('default')         -- 默认输出循环
local DefensiveAPL = Bastion.APL:New('defensive')     -- 防御循环
local AoEAPL = Bastion.APL:New('aoe')                 -- AOE循环
local ResourceAPL = Bastion.APL:New('resource')       -- 资源管理循环
local ResourceAPL2 = Bastion.APL:New('resource2')     -- 资源管理循环2
local PetControlAPL = Bastion.APL:New('petcontrol')   -- 宠物控制
local DefaultSPAPL = Bastion.APL:New('DefaultSP')     -- 简单模式

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

-- 假死
DefensiveAPL:AddSpell(
    FeignDeath:CastableIf(function(self)
        return GetKeyState(3)  -- 按下F键时释放
            and not Player:GetAuras():FindMy(FeignDeath):IsUp()  -- 没有假死buff
    end):SetTarget(Player):PreCast(function(self)
        if Player:IsCastingOrChanneling() then
            SpellStopCasting()  -- 打断当前施法
        end
    end)
)

-- 威慑（原有逻辑）
DefensiveAPL:AddSpell(
    Intimidation:CastableIf(function(self)
        return Player:GetHP() <= 30 and
               not self:IsOnCooldown() and
               Player:IsAffectingCombat() and
               not Player:GetAuras():FindAny(LeechingSwarm):IsUp() and
               not IsTargetBoss() and
               not GetKeyState(17) -- 不在按T键时才使用原有逻辑
    end):SetTarget(Player):PreCast(function(self)
        if Player:IsCastingOrChanneling() then
            SpellStopCasting()
        end
    end)
)

-- 威慑（按T键触发）
DefensiveAPL:AddSpell(
    Intimidation:CastableIf(function(self)
        return GetKeyState(17) and -- 按下T键时释放
               not Player:GetAuras():FindMy(Intimidation):IsUp() -- 没有威慑buff
    end):SetTarget(Player):PreCast(function(self)
        if Player:IsCastingOrChanneling() then
            SpellStopCasting() -- 打断当前施法
        end
    end):OnCast(function(self)
        -- 标记这是T键触发的威慑
        isTKeyIntimidationActive = true
    end)
)

-- 取消威慑（松开T键时）
DefensiveAPL:AddAction("CancelTKeyIntimidation", function()
    if isTKeyIntimidationActive then
        -- T键触发的威慑，按原有逻辑处理
        if not GetKeyState(17) and Player:GetAuras():FindMy(Intimidation):IsUp() then
            CancelSpellByName("威慑")
            isTKeyIntimidationActive = false
            return true
        end
    else
        -- 非T键触发的威慑，血量大于等于80%时取消
        if not GetKeyState(17) and Player:GetHP() >= 80 and Player:GetAuras():FindMy(Intimidation):IsUp() then
            CancelSpellByName("威慑")
            return true
        end
    end
    return false
end)

-- 杀戮命令
DefensiveAPL:AddSpell(
    shalumingling:CastableIf(function(self)
        return Pet:IsAlive()
            and Pet:Exists()
            and Target:Exists()
		    and Target:IsAlive()
            and Target:IsEnemy()
            and self:IsKnownAndUsable()
            and Player:IsAffectingCombat()
            and not Player:IsChanneling()
    end):SetTarget(Target)
)

-- 震荡射击
DefensiveAPL:AddSpell(
    ConcussiveShot:CastableIf(function(self)
        return Target:Exists()
            and Target:IsAlive()
            and Target:IsEnemy()
            and self:IsKnownAndUsable()
            and self:IsInRange(Target)
            and not Target:GetAuras():FindAny(ConcussiveShot):IsUp()
            and not Target:GetAuras():FindAny(FrostTrap):IsUp()
            and not Target:GetAuras():FindAny(HolyWrath):IsUp()
            and not Target:GetAuras():FindAny(HammerOfJustice):IsUp()
            and (string.find(Target:GetName(), "瓦格里暗影戒卫者") or string.find(Target:GetName(), "脓疮僵尸"))
    end):SetTarget(Target)
)

-- 畏缩
PetControlAPL:AddSpell(
    Cower:CastableIf(function(self)
        return Pet:Exists()
            and Pet:IsAlive()
            and Player:IsAffectingCombat()
            and not self:IsOnCooldown()
            and Pet:GetHP() <= 80
    end):SetTarget(Pet)
)

-- 宠物攻击
PetControlAPL:AddAction("PetAttack", function()
    if Pet:Exists() and Pet:IsAlive()
        and not PetTarget:Exists()
        and Pet:GetHP() > 80
        and HERUIPetAttack()
        and Target:IsAlive()
        and Target:Exists()
        and Target:GetName() ~= "重压触须" then
        PetAttack()
        return true
    end
    return false
end)

-- 宠物跟随
PetControlAPL:AddAction("PetFollow", function()
    if Pet:Exists() and Pet:IsAlive()
        and PetTarget:Exists()
        and (HERUIPetFollow() or Pet:GetHP() <= 80) then
        PetFollow()
        return true
    end
    return false
end)

-- 治疗宠物
PetControlAPL:AddSpell(
    MendPet:CastableIf(function(self)
        return Pet:Exists()
            and Pet:IsAlive()
            and Pet:GetHP() < 80
            and Player:IsAffectingCombat()
            and not Pet:GetAuras():FindAny(MendPet):IsUp()
            and not Player:IsChanneling()
    end):SetTarget(Pet)
)

-- ===================== 资源管理循环 =====================
-- 守护切换
-- 蝰蛇
ResourceAPL:AddSpell(
    kuishe:CastableIf(function(self)
        return Player:GetPP() <= 7 and
               not Player:GetAuras():FindMy(kuishe):IsUp() and
               Player:IsAffectingCombat()
    end):SetTarget(Player)
)

-- 龙鹰
ResourceAPL:AddSpell(
    longying:CastableIf(function(self)
        return Player:GetPP() >= 50 and
               not Player:GetAuras():FindMy(longying):IsUp() and
               Player:IsAffectingCombat()
    end):SetTarget(Player)
)

-- 资源管理循环2
-- 蝰蛇
ResourceAPL2:AddSpell(
    kuishe:CastableIf(function(self)
        return not Player:GetAuras():FindMy(kuishe):IsUp()
               and Player:IsAffectingCombat()
    end):SetTarget(Player)
)

-- ===================== AOE循环 =====================
-- AOE循环技能序列
-- 斩杀射击（斩杀阶段使用）
AoEAPL:AddSpell(
    KillShot:CastableIf(function(self)
        return self:GetCooldownRemaining() < 1.5 and
               ExecuteTarget:Exists() and
               Player:IsAffectingCombat()
    end):SetTarget(ExecuteTarget):PreCast(function(self)
        if Player:IsCastingOrChanneling() then
            SpellStopCasting()  -- 打断当前施法
        end
    end)
)

-- 爆炸陷阱
AoEAPL:AddSpell(
    TrapSpell:CastableIf(function(self)
        return Target:Exists()
            and self:IsKnownAndUsable()
            and not Player:IsChanneling()
            and Target:IsAlive()
            and Target:IsEnemy()
            and HERUIExplosiveTrap()
    end):SetTarget(Target):PreCast(function(self)
        -- 检查是否正在读条稳固射击，如果是则停止施法
        if Player:IsCastingOrChanneling() and Player:GetCastingOrChannelingSpell():GetID() == 49052 then
            SpellStopCasting()
        end
    end):OnCast(function(self)
        local distance = Target:GetDistance(Player)
        local position
        
        if distance < 40 then
            -- 距离40码内，直接使用目标位置
            position = Target:GetPosition()
        else
            -- 距离40码外，计算向玩家方向退的位置
            local playerPos = Player:GetPosition()
            local targetPos = Target:GetPosition()
            local direction = (targetPos - playerPos):Normalize()
            position = targetPos - direction * math.floor(Target:GetCombatReach() / 3)
        end
        
        self:Click(position)
    end)
)

-- 乱射(直接使用目标坐标)
AoEAPL:AddSpell(
    MultiShotSpell:CastableIf(function(self)
        return Target:Exists()
            and not Player:IsChanneling()
            and Target:IsAlive()
            and Target:IsEnemy()
            and Target:GetDistance(Player) <= 35
            and TrapSpell:GetCooldownRemaining() > 1.1
    end):SetTarget(Target):PreCast(function(self)
        -- 检查是否正在读条稳固射击，如果是则停止施法
        if Player:IsCastingOrChanneling() and Player:GetCastingOrChannelingSpell():GetID() == 49052 then
            SpellStopCasting()
        end
    end):OnCast(function(self)
        local position = Target:GetPosition()
        self:Click(position)
    end)
)

-- ===================== 默认循环 =====================
-- 斩杀射击（斩杀阶段使用）
DefaultAPL:AddSpell(
    KillShot:CastableIf(function(self)
        return self:GetCooldownRemaining() < 1.5 and
               ExecuteTarget:Exists() and
               Player:IsAffectingCombat()
    end):SetTarget(ExecuteTarget):PreCast(function(self)
        if Player:IsCastingOrChanneling() then
            SpellStopCasting()  -- 打断当前施法
        end
    end)
)

-- 爆炸陷阱
DefaultAPL:AddSpell(
    TrapSpell:CastableIf(function(self)
        return Target:Exists()
            and self:IsKnownAndUsable()
            and not Player:IsCastingOrChanneling()
            and Target:IsAlive()
            and Target:IsEnemy()
            and HERUIExplosiveTrap()
    end):SetTarget(Target):OnCast(function(self)
        local distance = Target:GetDistance(Player)
        local position
        
        if distance < 40 then
            -- 距离40码内，直接使用目标位置
            position = Target:GetPosition()
        else
            -- 距离40码外，计算向玩家方向退的位置
            local playerPos = Player:GetPosition()
            local targetPos = Target:GetPosition()
            local direction = (targetPos - playerPos):Normalize()
            position = targetPos - direction * math.floor(Target:GetCombatReach() / 3)
        end
        
        self:Click(position)
    end)
)

-- 爆炸射击4
DefaultAPL:AddSpell(
    ExplosiveShot:CastableIf(function(self)
        return Target:Exists()
		    and Target:IsAlive()
            and self:IsKnownAndUsable()
			and (Player:GetAuras():FindMy(heqiang):GetCount() == 2 or Player:GetAuras():FindMy(heqiang):GetCount() == 0)
    end):SetTarget(Target)
)

-- 爆炸射击3
DefaultAPL:AddSpell(
    ExplosiveShott:CastableIf(function(self)
        return Target:Exists()
		    and Target:IsAlive()
            and self:IsKnownAndUsable()
			and Player:GetAuras():FindMy(heqiang):GetCount() == 1
    end):SetTarget(Target)
)

-- 黑箭
DefaultAPL:AddSpell(
    BlackArrow:CastableIf(function(self)
        return Target:Exists()
		    and Target:IsAlive()
            and self:IsKnownAndUsable()
			and HERUIBlackArrow()
    end):SetTarget(Target)
)

-- 毒蛇钉刺
DefaultAPL:AddSpell(
    Serpent:CastableIf(function(self)
        return Target:Exists()
            and Target:IsAlive()
            and self:IsKnownAndUsable()
            and Target:GetAuras():FindMy(Serpent):GetRemainingTime() < 3
            and ExplosiveShot:GetCooldownRemaining() > 0.5
            and TrapSpell:GetCooldownRemaining() > 0.5
    end):SetTarget(Target)
)

-- 多重射击
DefaultAPL:AddSpell(
    MultiShot:CastableIf(function(self)
        return Target:Exists()
		    and Target:IsAlive()
            and self:IsKnownAndUsable()
			and HERUIMultiShot()
			and ExplosiveShot:GetCooldownRemaining() > 0.5
			and TrapSpell:GetCooldownRemaining() > 0.5
    end):SetTarget(Target)
)

-- 瞄准射击
DefaultAPL:AddSpell(
    AimedShot:CastableIf(function(self)
        return Target:Exists()
		    and Target:IsAlive()
            and self:IsKnownAndUsable()
			and HERUIAimedShot()
			and ExplosiveShot:GetCooldownRemaining() > 0.5
			and TrapSpell:GetCooldownRemaining() > 0.5
    end):SetTarget(Target)
)

-- 猎人印记
DefaultAPL:AddSpell(
    HuntersMark:CastableIf(function(self)
        return Target:Exists()
		    and Target:IsAlive()
            and self:IsKnownAndUsable()
            and not Target:GetAuras():FindAny(HuntersMark):IsUp()
			and ExplosiveShot:GetCooldownRemaining() > 0.5
			and TrapSpell:GetCooldownRemaining() > 0.5
			and MultiShot:GetCooldownRemaining() > 0.5
    end):SetTarget(Target)
)

-- 稳固射击（基础填充技能）
DefaultAPL:AddSpell(
    SteadyShot:CastableIf(function(self)
        return ExplosiveShot:GetCooldownRemaining() > 0.5
            and TrapSpell:GetCooldownRemaining() > 0.5
            and AimedShot:GetCooldownRemaining() > 0.5
            and Target:Exists()
            and Target:IsAlive()
            and self:IsKnownAndUsable()
            and Target:GetAuras():FindMy(Serpent):GetRemainingTime() > 3
    end):SetTarget(Target)
)

-- ===================== 简单循环 =====================
-- 斩杀射击（斩杀阶段使用）
DefaultSPAPL:AddSpell(
    KillShot:CastableIf(function(self)
        return self:GetCooldownRemaining() < 1.5 and
               ExecuteTarget:Exists() and
               Player:IsAffectingCombat()
    end):SetTarget(ExecuteTarget):PreCast(function(self)
        if Player:IsCastingOrChanneling() then
            SpellStopCasting()  -- 打断当前施法
        end
    end)
)

-- 爆炸射击4
DefaultSPAPL:AddSpell(
    ExplosiveShot:CastableIf(function(self)
        return Target:Exists()
		    and Target:IsAlive()
            and self:IsKnownAndUsable()
			and (Player:GetAuras():FindMy(heqiang):GetCount() == 2 or Player:GetAuras():FindMy(heqiang):GetCount() == 0)
    end):SetTarget(Target)
)

-- 爆炸射击3
DefaultSPAPL:AddSpell(
    ExplosiveShott:CastableIf(function(self)
        return Target:Exists()
		    and Target:IsAlive()
            and self:IsKnownAndUsable()
			and Player:GetAuras():FindMy(heqiang):GetCount() == 1
    end):SetTarget(Target)
)

-- 多重射击
DefaultSPAPL:AddSpell(
    MultiShot:CastableIf(function(self)
        return ExplosiveShot:GetCooldownRemaining() > 0.5
            and Target:Exists()
		    and Target:IsAlive()
            and self:IsKnownAndUsable()
			and HERUIMultiShot()
    end):SetTarget(Target)
)

-- 瞄准射击
DefaultSPAPL:AddSpell(
    AimedShot:CastableIf(function(self)
        return ExplosiveShot:GetCooldownRemaining() > 0.5
            and Target:Exists()
		    and Target:IsAlive()
            and self:IsKnownAndUsable()
			and HERUIAimedShot()
    end):SetTarget(Target)
)

-- 稳固射击（基础填充技能）
DefaultSPAPL:AddSpell(
    SteadyShot:CastableIf(function(self)
        return Target:Exists()
            and Target:IsAlive()
            and self:IsKnownAndUsable()
            and MultiShot:GetCooldownRemaining() > 0.5
            and ExplosiveShot:GetCooldownRemaining() > 0.5
    end):SetTarget(Target)
)

-- ===================== 模块同步 =====================
HunterModule:Sync(function()
    -- 检查威慑状态，如果没有威慑buff则重置T键状态
    if isTKeyIntimidationActive and not Player:GetAuras():FindMy(Intimidation):IsUp() then
        isTKeyIntimidationActive = false
    end

    --最高优先级：防御和资源管理
    DefensiveAPL:Execute()
    PetControlAPL:Execute()

    -- 如果按住F键（假死状态）或T键（威慑状态），则不执行其他循环
    if GetKeyState(3) or GetKeyState(17) then
        return
    end

    -- 强制蝰蛇模式
    if HERUIViperSting() then
        ResourceAPL2:Execute()
    end
    if not HERUIViperSting() then
        ResourceAPL:Execute()
    end

    -- 战斗中切目标
    if Player:IsAffectingCombat() then
        CheckAndSetTarget()
    end
    if HERUIAOE() then
        AoEAPL:Execute()
    end
    if HERUINormal() then
        DefaultAPL:Execute()
    end
    if HERUISimple() then
        DefaultSPAPL:Execute()
    end
end)
-- ===================== 注册模块 =====================
Bastion:Register(HunterModule)