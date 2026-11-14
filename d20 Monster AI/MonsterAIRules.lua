local mod = dmhub.GetModLoading()

--The d20 rules adapter: everything the Monster AI knows about 5e / 5.5e rules
--lives here, so a Pathfinder version can replace this file (and keep the rest).
--  action economy (actions, bonus actions, reactions, legendary actions)
--  ability profiles: what an ability does, read from its behaviors
--  odds: attack hit chance, saving throw failure chance, advantage
--  Multiattack, read from the stat block's note text
--  loadouts (switching the weapons in hand) and spell slot costs

MonsterAIRules = {}

MonsterAIRules.LEGENDARY_RESOURCE = "58eda6fe-bbd4-4e6d-8fe6-4329f2135ce1"

---------------------------------------------------------------------------
--Conditions and effects, looked up by name so no ids are hard-coded.
---------------------------------------------------------------------------

local g_conditionIds = nil
local function ConditionIds()
	if g_conditionIds == nil then
		g_conditionIds = {}
		for id,cond in pairs(dmhub.GetTable(CharacterCondition.tableName) or {}) do
			if not cond:try_get("hidden") then
				g_conditionIds[string.lower(cond.name)] = id
			end
		end
	end
	return g_conditionIds
end

function MonsterAIRules.HasCondition(token, name)
	local id = ConditionIds()[string.lower(name)]
	if id == nil then
		return false
	end
	local ok, result = pcall(function() return token.properties:HasCondition(id) end)
	return ok and result == true
end

--Names (lowercase) of every ongoing effect on a token.
function MonsterAIRules.EffectNames(token)
	local names = {}
	local effectsTable = dmhub.GetTable("characterOngoingEffects") or {}
	pcall(function()
		for _,effect in ipairs(token.properties:ActiveOngoingEffects()) do
			local id = effect:try_get("ongoingEffectid")
			local info = id ~= nil and effectsTable[id] or nil
			if info ~= nil then
				names[string.lower(info.name)] = true
			end
		end
	end)
	return names
end

function MonsterAIRules.HasEffect(token, name)
	return MonsterAIRules.EffectNames(token)[string.lower(name)] == true
end

local g_incapacitatingConditions = {"Incapacitated", "Paralyzed", "Stunned", "Unconscious", "Petrified"}

--- @return boolean, string|nil
function MonsterAIRules.IsIncapacitated(token)
	local c = token.properties
	local down = false
	pcall(function() down = c:IsDown() or c:IsDying() end)
	if down then
		return true, "down"
	end
	for _,name in ipairs(g_incapacitatingConditions) do
		if MonsterAIRules.HasCondition(token, name) then
			return true, string.lower(name)
		end
	end
	return false
end

function MonsterAIRules.IsDying(token)
	local result = false
	pcall(function() result = token.properties:IsDeadOrDying() or token.properties:CurrentHitpoints() <= 0 end)
	return result
end

function MonsterAIRules.HitpointFraction(token)
	local c = token.properties
	local max = c:MaxHitpoints()
	if max == nil or max <= 0 then
		return 1
	end
	return math.max(0, c:CurrentHitpoints()) / max
end

---------------------------------------------------------------------------
--Action economy.
---------------------------------------------------------------------------

--How many of a resource (an action, a legendary action) the token has left.
function MonsterAIRules.ResourceAvailable(token, resid)
	local resourceTable = dmhub.GetTable("characterResources") or {}
	local resource = resourceTable[resid]
	if resource == nil then
		return 0
	end
	local c = token.properties
	local max = c:GetResources()[resid] or 0
	local used = c:GetResourceUsage(resid, resource.usageLimit) or 0
	return max - used
end

MonsterAIRules.kindResources = {
	action = "standardAction",
	bonus = "bonusAction",
	reaction = "reaction",
	legendary = MonsterAIRules.LEGENDARY_RESOURCE,
}

function MonsterAIRules.HasAction(token, kind)
	local resid = MonsterAIRules.kindResources[kind]
	if resid == nil then
		return true
	end
	return MonsterAIRules.ResourceAvailable(token, resid) > 0
end

--"action", "bonus", "reaction", "legendary", "move" or "free".
function MonsterAIRules.AbilityKind(ability)
	local res = ability:ActionResource()
	if ability.legendary or res == MonsterAIRules.LEGENDARY_RESOURCE then
		return "legendary"
	end
	if res == "standardAction" then
		return "action"
	elseif res == "bonusAction" then
		return "bonus"
	elseif res == "reaction" then
		return "reaction"
	elseif res == "movementAction" then
		return "move"
	end
	return "free"
end

--The cost the ability would be cast with (the rules' first choice, which
--spends the lowest spell slot that will do), and the symbols to cast with.
--Returns nil when the token cannot afford it.
function MonsterAIRules.CastCost(token, ability)
	local ok, cost = pcall(function() return ability:GetCost(token, {mode = 1}) end)
	if not ok or cost == nil or not cost.canAfford then
		return nil
	end
	local symbols = {mode = 1}
	if ability.isSpell then
		local upcastInfo = Spell.CalculateUpcast(cost)
		if upcastInfo ~= nil and upcastInfo.upcast ~= nil then
			symbols.upcast = upcastInfo.upcast
		end
	end
	return cost, symbols
end

function MonsterAIRules.IsConcentrating(token)
	local ok, result = pcall(function() return token.properties:HasConcentration() end)
	return ok and result == true
end

--Use up one of a resource outside a cast (an opportunity attack takes the
--reaction, not the attack's action).
function MonsterAIRules.ConsumeResource(token, resid, note)
	local resourceTable = dmhub.GetTable("characterResources") or {}
	local resource = resourceTable[resid]
	if resource == nil then
		return
	end
	token:ModifyProperties{
		description = note or "Use resource",
		execute = function()
			token.properties:ConsumeResource(resid, resource.usageLimit, 1, note)
		end,
	}
end

---------------------------------------------------------------------------
--Ability profiles: what an ability does, read from its behaviors.
---------------------------------------------------------------------------

--the standard rules actions every creature has, by name.
MonsterAIRules.basicActions = {
	["dash"] = true, ["dodge"] = true, ["disengage"] = true, ["hide"] = true,
	["help"] = true, ["study"] = true, ["influence"] = true, ["search"] = true,
	["utilize"] = true, ["ready"] = true, ["shove"] = true, ["grapple"] = true,
	["unarmed strike"] = true, ["magic"] = true, ["attack"] = true,
}

--condition words in an effect's name, and how much a creature suffering it is
--taken out of the fight (1 = a full turn lost).
MonsterAIRules.effectWeights = {
	{"paraly", 1.0}, {"stun", 1.0}, {"unconscious", 1.0}, {"petrif", 1.0},
	{"incapacitat", 0.9}, {"banish", 0.9}, {"asleep", 0.8}, {"sleep", 0.8},
	{"restrain", 0.5}, {"frighten", 0.45}, {"charm", 0.45}, {"blind", 0.45},
	{"grappl", 0.25}, {"prone", 0.25}, {"poison", 0.25}, {"slow", 0.4},
	{"command", 0.35}, {"deafen", 0.05},
}

function MonsterAIRules.EffectWeight(name)
	name = string.lower(name or "")
	for _,entry in ipairs(MonsterAIRules.effectWeights) do
		if string.find(name, entry[1], 1, true) then
			return entry[2]
		end
	end
	return 0
end

local function ExpectedValue(roll)
	if type(roll) == "number" then
		return roll
	end
	if type(roll) ~= "string" or roll == "" then
		return 0
	end
	local ok, value = pcall(function() return dmhub.RollExpectedValue(roll) end)
	if ok and type(value) == "number" then
		return value
	end
	return 0
end
MonsterAIRules.ExpectedValue = ExpectedValue

local function EvalRoll(token, roll, symbols, reason)
	if roll == nil then
		return nil
	end
	local ok, result = pcall(function()
		return dmhub.EvalGoblinScript(roll, token.properties:LookupSymbol(symbols or {}), reason or "Monster AI estimate")
	end)
	if ok then
		return result
	end
	return roll
end

--A profile of what `ability` does when `token` uses it, or nil if it is not
--something the AI knows how to use. Fields:
--  ability, name, kind (AbilityKind), targetType, range, longRange, radius,
--  numTargets, isSpell, level, concentration, recharge, basic (standard
--  action name), textOnly (no behaviors: the effect is in the text),
--  attack = {bonus, melee, avg}, save = {saveid, dc, avg, half, effects},
--  autoDamage (damage with no attack or save), heal, effects (names of ongoing
--  effects applied with no save), relocate (teleports the caster), symbols, cost.
function MonsterAIRules.ProfileAbility(token, ability)
	local c = token.properties
	local profile = {
		ability = ability,
		name = ability.name,
		lname = string.lower(ability.name or ""),
		kind = MonsterAIRules.AbilityKind(ability),
		targetType = ability.targetType,
		isSpell = ability.isSpell == true,
		level = ability:try_get("level", 0),
		concentration = ability:RequiresConcentration() == true,
		recharge = ability:RechargeResourceId() ~= nil,
		legendary = ability.legendary == true,
		textOnly = #ability.behaviors == 0,
		effects = {},
	}
	profile.basic = MonsterAIRules.basicActions[profile.lname] and profile.lname or nil

	local cost, symbols = MonsterAIRules.CastCost(token, ability)
	profile.cost = cost
	profile.symbols = symbols or {mode = 1}
	profile.affordable = cost ~= nil

	local okRange, range = pcall(function() return ability:GetRange(c, profile.symbols) end)
	profile.range = okRange and tonumber(range) or dmhub.unitsPerSquare
	profile.radius = tonumber(ability:try_get("radius", dmhub.unitsPerSquare)) or dmhub.unitsPerSquare
	local okTargets, numTargets = pcall(function() return ability:GetNumTargets(token, profile.symbols) end)
	profile.numTargets = okTargets and tonumber(numTargets) or 1

	local effectsTable = dmhub.GetTable("characterOngoingEffects") or {}

	for _,behavior in ipairs(ability.behaviors) do
		local typeName = behavior.typeName
		local hasSave = behavior:try_get("dc", "none") ~= "none"
		if typeName == "ActivatedAbilityAttackBehavior" then
			local ok, attack = pcall(function() return behavior:GetAttack(ability, c, {symbols = profile.symbols}) end)
			if ok and attack ~= nil then
				local avg = 0
				for _,instance in ipairs(attack.damageInstances or {}) do
					avg = avg + ExpectedValue(instance.damage)
				end
				profile.attack = {
					bonus = tonumber(attack.hit) or 0,
					melee = attack.melee == true,
					avg = avg,
				}
				local normal = attack:RangeNormal()
				local long = attack:RangeDisadvantage()
				if not profile.attack.melee and normal ~= nil and normal > dmhub.unitsPerSquare then
					profile.range = math.max(profile.range, normal)
					profile.longRange = long
				end
			end
		elseif typeName == "ActivatedAbilityDamageBehavior" then
			local roll = EvalRoll(token, behavior.roll, profile.symbols, "Monster AI damage estimate")
			local avg = ExpectedValue(roll)
			if hasSave then
				profile.save = profile.save or {saveid = behavior.dc, effects = {}}
				profile.save.avg = (profile.save.avg or 0) + avg
				profile.save.half = behavior:try_get("dcsuccess") == "half"
				profile.save.dc = MonsterAIRules.SaveDC(token, ability, behavior, profile.symbols)
			else
				profile.autoDamage = (profile.autoDamage or 0) + avg
			end
		elseif typeName == "ActivatedAbilityHealBehavior" then
			local roll = EvalRoll(token, behavior:try_get("roll"), profile.symbols, "Monster AI healing estimate")
			profile.heal = (profile.heal or 0) + ExpectedValue(roll)
		elseif typeName == "ActivatedAbilitySavingThrowBehavior" then
			profile.save = profile.save or {saveid = behavior.dc, avg = 0, effects = {}}
			profile.save.saveid = behavior.dc
			profile.save.dc = MonsterAIRules.SaveDC(token, ability, behavior, profile.symbols)
		elseif typeName == "ActivatedAbilityApplyOngoingEffectBehavior" then
			local info = effectsTable[behavior:try_get("ongoingEffect", "")]
			local name = info ~= nil and info.name or ""
			if hasSave or (profile.save ~= nil and behavior:try_get("applyto", "targets") ~= "caster") then
				profile.save = profile.save or {saveid = behavior.dc, avg = 0, effects = {}}
				if hasSave then
					profile.save.saveid = behavior.dc
					profile.save.dc = MonsterAIRules.SaveDC(token, ability, behavior, profile.symbols)
				end
				profile.save.effects[#profile.save.effects+1] = name
			else
				profile.effects[#profile.effects+1] = name
			end
		elseif typeName == "ActivatedAbilityRelocateCreatureBehavior" then
			profile.relocate = true
		else
			profile.other = true
		end
	end

	if profile.save ~= nil and profile.save.dc == nil then
		profile.save.dc = MonsterAIRules.SaveDC(token, ability, nil, profile.symbols)
	end

	return profile
end

function MonsterAIRules.SaveDC(token, ability, behavior, symbols)
	local ok, dc = pcall(function() return ability:SaveDC(token, behavior, symbols) end)
	if ok and type(dc) == "number" then
		return dc
	end
	return 10
end

--Profiles of every ability the token has (all loadouts: the AI can switch).
function MonsterAIRules.Profiles(token)
	local result = {}
	local ok, abilities = pcall(function()
		return token.properties:GetActivatedAbilities{bindCaster = true, allLoadouts = true}
	end)
	if not ok or abilities == nil then
		return result
	end
	for _,ability in ipairs(abilities) do
		local okProfile, profile = pcall(MonsterAIRules.ProfileAbility, token, ability)
		if okProfile and profile ~= nil then
			result[#result+1] = profile
		end
	end
	return result
end

--Does a profile do anything the generic planner can score?
function MonsterAIRules.IsOffensive(profile)
	return profile.attack ~= nil or profile.autoDamage ~= nil
		or (profile.save ~= nil and (profile.save.avg > 0 or #profile.save.effects > 0))
end

function MonsterAIRules.IsArea(profile)
	local t = profile.targetType
	return t == "sphere" or t == "cylinder" or t == "cube" or t == "cone" or t == "line" or t == "all"
end

---------------------------------------------------------------------------
--Odds.
---------------------------------------------------------------------------

--Chance a d20 attack with `bonus` hits armor class `ac`. advantage: 1, 0, -1.
function MonsterAIRules.HitChance(bonus, ac, advantage)
	local need = ac - bonus
	local p = (21 - need) / 20
	p = math.max(0.05, math.min(0.95, p))
	if advantage ~= nil and advantage > 0 then
		p = 1 - (1-p)*(1-p)
	elseif advantage ~= nil and advantage < 0 then
		p = p*p
	end
	return p
end

--Chance `target` fails a saving throw of type `saveid` against `dc`.
function MonsterAIRules.SaveFailChance(target, saveid, dc)
	local mod = 0
	pcall(function() mod = target.properties:SavingThrowMod(saveid) or 0 end)
	local success = (21 - (dc - mod)) / 20
	success = math.max(0, math.min(1, success))
	return 1 - success
end

function MonsterAIRules.ArmorClass(target)
	local ok, ac = pcall(function() return target.properties:ArmorClass() end)
	if ok and type(ac) == "number" then
		return ac
	end
	return 12
end

--Advantage (1), disadvantage (-1) or neither (0) on an attack. Any source of
--each cancels out, as in the rules.
--opts: distance (feet), ranged (bool), enemyAdjacent (an enemy within 5 feet
--of the attacker), packTactics (an ally of the attacker is next to the target).
function MonsterAIRules.AttackAdvantage(attacker, target, profile, opts)
	opts = opts or {}
	local adv, dis = false, false
	local melee = profile.attack ~= nil and profile.attack.melee
	local distance = opts.distance or 0

	for _,name in ipairs({"Blinded", "Poisoned", "Prone", "Frightened", "Restrained"}) do
		if MonsterAIRules.HasCondition(attacker, name) then
			dis = true
		end
	end
	if MonsterAIRules.HasCondition(attacker, "Invisible") or MonsterAIRules.HasEffect(attacker, "Hidden") then
		adv = true
	end

	if not melee then
		if opts.enemyAdjacent then
			dis = true
		end
		if profile.longRange ~= nil and profile.range ~= nil and distance > profile.range then
			dis = true
		end
	end

	for _,name in ipairs({"Blinded", "Paralyzed", "Restrained", "Stunned", "Unconscious", "Petrified"}) do
		if MonsterAIRules.HasCondition(target, name) then
			adv = true
		end
	end
	if MonsterAIRules.HasCondition(target, "Prone") then
		if distance <= dmhub.unitsPerSquare then
			adv = true
		else
			dis = true
		end
	end
	if MonsterAIRules.HasCondition(target, "Invisible") then
		dis = true
	end
	if MonsterAIRules.HasEffect(target, "Dodging") then
		dis = true
	end
	if opts.packTactics then
		adv = true
	end

	if adv and dis then
		return 0
	elseif adv then
		return 1
	elseif dis then
		return -1
	end
	return 0
end

--Expected damage of one attack (crits count a little more).
function MonsterAIRules.ExpectedAttackDamage(profile, target, advantage)
	local p = MonsterAIRules.HitChance(profile.attack.bonus, MonsterAIRules.ArmorClass(target), advantage)
	local critChance = advantage ~= nil and advantage > 0 and 0.0975 or 0.05
	return p*profile.attack.avg + critChance*profile.attack.avg*0.5, p
end

--Expected value of a saving-throw ability against one target: damage plus
--how much its conditions take the target out of the fight.
function MonsterAIRules.ExpectedSaveValue(profile, target, effectValue)
	local save = profile.save
	local fail = MonsterAIRules.SaveFailChance(target, save.saveid, save.dc or 10)
	local damage = save.avg or 0
	local value = damage*fail
	if save.half then
		value = value + damage*0.5*(1-fail)
	end
	for _,name in ipairs(save.effects or {}) do
		value = value + fail*MonsterAIRules.EffectWeight(name)*(effectValue or 10)
	end
	return value, fail
end

---------------------------------------------------------------------------
--Multiattack, from the stat block's note ("The dragon makes three Rend
--attacks. It can replace one attack with a use of Spellcasting to cast
--Scorching Ray."). Returns a list of routines; a routine is a list of slots
--and a slot is a list of the ability names (lowercase) it may use.
---------------------------------------------------------------------------

local g_numberWords = {
	one = 1, two = 2, three = 3, four = 4, five = 5, six = 6, seven = 7, eight = 8,
	a = 1, an = 1, twice = 2,
}

local function StripText(text)
	text = string.gsub(text or "", "<[^>]*>", "")
	text = string.gsub(text, "[\r\n]", " ")
	--fancy apostrophes and the like become plain spaces.
	text = string.gsub(text, "[^\x20-\x7E]", " ")
	return " " .. string.lower(text) .. " "
end

function MonsterAIRules.MultiattackText(token)
	local notes = token.properties:try_get("notes")
	if notes == nil then
		return nil
	end
	for _,note in pairs(notes) do
		local title = string.lower(tostring(note.title or ""))
		if string.find(title, "multiattack", 1, true) then
			return note.text or ""
		end
	end
	return nil
end

--names: lowercase names of the abilities that can be used in a Multiattack.
local function ParseCounts(part, names)
	local slots = {}
	for word,count in pairs(g_numberWords) do
		for _,name in ipairs(names) do
			local needle = " " .. word .. " " .. name .. " attack"
			local start = 1
			while true do
				local i = string.find(part, needle, start, true)
				if i == nil then
					break
				end
				for _=1,count do
					slots[#slots+1] = {name}
				end
				start = i + #needle
			end
		end
	end
	return slots
end

function MonsterAIRules.ParseMultiattack(token, names)
	local raw = MonsterAIRules.MultiattackText(token)
	if raw == nil then
		return nil
	end
	local text = StripText(raw)

	--longest names first, so "arcane burst (ranged)" is not read as "arcane burst".
	table.sort(names, function(a,b) return #a > #b end)

	local sentences = {}
	for sentence in string.gmatch(text, "[^%.]+") do
		sentences[#sentences+1] = " " .. sentence .. " "
	end

	local routines = {}
	local base = nil
	for _,sentence in ipairs(sentences) do
		if base == nil and string.find(sentence, " makes ", 1, true) then
			local named = {}
			for _,name in ipairs(names) do
				if string.find(sentence, name, 1, true) then
					named[#named+1] = name
				end
			end

			local total = nil
			for word,count in pairs(g_numberWords) do
				if string.find(sentence, " makes " .. word .. " attacks", 1, true)
					or string.find(sentence, " makes " .. word .. " melee attacks", 1, true)
					or string.find(sentence, " makes " .. word .. " ranged attacks", 1, true)
					or string.find(sentence, " makes " .. word .. " weapon attacks", 1, true) then
					total = count
				end
			end

			if total ~= nil then
				--"makes two attacks, using Scimitar or Shortbow in any combination"
				local routine = {}
				for _=1,total do
					routine[#routine+1] = #named > 0 and named or {"*"}
				end
				routines[#routines+1] = routine
				base = routine
			else
				--"makes one Bite attack and two Claw attacks", possibly with
				--alternatives: "makes two Scimitar attacks or two Shortbow attacks".
				local parts = {}
				local rest = sentence
				while true do
					local i = string.find(rest, " or ", 1, true)
					if i == nil then
						parts[#parts+1] = rest
						break
					end
					parts[#parts+1] = string.sub(rest, 1, i)
					rest = string.sub(rest, i + 3)
				end
				for _,part in ipairs(parts) do
					local slots = ParseCounts(" " .. part .. " ", names)
					if #slots > 0 then
						routines[#routines+1] = slots
						base = base or slots
					end
				end
			end
		elseif base ~= nil and (string.find(sentence, "replace", 1, true) or string.find(sentence, "in place of", 1, true)) then
			--"It can replace one attack with a use of Spellcasting to cast Scorching Ray."
			local replacement = {}
			for _,name in ipairs(names) do
				if string.find(sentence, name, 1, true) then
					replacement[#replacement+1] = name
				end
			end
			if #replacement > 0 then
				local count = 1
				if string.find(sentence, "replace two", 1, true) then
					count = 2
				end
				local baseRoutines = {}
				for _,r in ipairs(routines) do
					baseRoutines[#baseRoutines+1] = r
				end
				for _,r in ipairs(baseRoutines) do
					if #r > count then
						local alt = {}
						for i,slot in ipairs(r) do
							if i <= count then
								alt[#alt+1] = replacement
							else
								alt[#alt+1] = slot
							end
						end
						alt.replacement = true
						routines[#routines+1] = alt
					end
				end
			end
		end
	end

	if #routines == 0 then
		return nil
	end
	return routines
end

---------------------------------------------------------------------------
--Loadouts: which loadout holds the weapon an ability is made with.
---------------------------------------------------------------------------

--The loadout to switch to before using `ability`, or nil if no switch is needed.
function MonsterAIRules.LoadoutForAbility(token, ability)
	local weaponid = ability:try_get("weaponid")
	if weaponid == nil then
		return nil
	end
	local c = token.properties
	local selected = c.selectedLoadout
	local found = nil
	for slot,itemid in pairs(c:Equipment()) do
		local info = creature.EquipmentSlots[slot]
		if itemid == weaponid and info ~= nil then
			if info.loadout == nil or info.loadout == selected then
				return nil
			end
			found = found or info.loadout
		end
	end
	return found
end

function MonsterAIRules.SwitchLoadout(ai, token, loadout)
	local previous = token.properties.selectedLoadout
	token:ModifyProperties{
		description = "Change Loadout",
		execute = function()
			token.properties.selectedLoadout = loadout
		end,
	}
	pcall(function()
		game.Refresh{tokens = {token.charid}}
	end)
	ai:LogDecision("LOADOUT SWITCH", {
		actor = MonsterAI.TokenLogName(token),
		from = previous,
		to = loadout,
	})
	MonsterAI.Sleep(0.3)
end

--Find the token's current copy of an ability by name (after a loadout switch,
--a weapon's attack is rebuilt).
function MonsterAIRules.FindAbility(token, name, kind)
	local ok, abilities = pcall(function()
		return token.properties:GetActivatedAbilities{bindCaster = true}
	end)
	if not ok or abilities == nil then
		return nil
	end
	for _,ability in ipairs(abilities) do
		if ability.name == name and (kind == nil or MonsterAIRules.AbilityKind(ability) == kind) then
			return ability
		end
	end
	return nil
end
