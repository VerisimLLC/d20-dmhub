local mod = dmhub.GetModLoading()

--The generic planner: plays any monster from its stat block. Every cycle of a
--turn it scores what the monster could do now -- an attack routine
--(Multiattack or a single attack, spell or area), a bonus action, an escape,
--an advance, Dodge -- from every square it could move to, and the turn loop
--in MonsterAI.lua does the best of them. Hand-written moves (MonsterAIBands)
--compete with these and win when they score higher.
--
--Scores: generic moves score between 0.1 and 0.95 by how much they are
--worth; a hand-written move that should always win scores above 1.

MonsterAIGeneric = {}

local Rules = MonsterAIRules

---------------------------------------------------------------------------
--Context: what a monster knows at the start of a planning cycle.
---------------------------------------------------------------------------

function MonsterAIGeneric.BuildContext(ai, token)
	local ctx = {
		token = token,
		tactics = ai:Tactics(token),
		profiles = Rules.Profiles(token),
		enemies = ai:Enemies(token),
		allies = ai:Allies(token),
	}

	local spareDying = MonsterAI.SettingOn("spareDying") and not ctx.tactics.finishDowned
	ctx.targets = {}
	for _,enemy in ipairs(ctx.enemies) do
		if not (spareDying and Rules.IsDying(enemy)) then
			ctx.targets[#ctx.targets+1] = enemy
		end
	end

	ctx.byKind = {}
	for _,profile in ipairs(ctx.profiles) do
		local list = ctx.byKind[profile.kind]
		if list == nil then
			list = {}
			ctx.byKind[profile.kind] = list
		end
		list[#list+1] = profile
	end

	ctx.prefersRange = MonsterAIGeneric.PrefersRange(ctx)
	return ctx
end

--Profiles of a kind that deal damage or impose conditions, ready to use.
function MonsterAIGeneric.OffensiveProfiles(ctx, kind)
	local result = {}
	for _,profile in ipairs(ctx.byKind[kind] or {}) do
		if Rules.IsOffensive(profile) and profile.basic ~= "grapple" and profile.basic ~= "shove"
			and not MonsterAIGeneric.ProfileExcluded(ctx, profile) then
			result[#result+1] = profile
		end
	end
	return result
end

function MonsterAIGeneric.ProfileExcluded(ctx, profile)
	local avoid = ctx.tactics.avoidAbilities
	if avoid ~= nil and avoid[profile.lname] then
		return true
	end
	return false
end

--Does this monster do more from range than in melee?
function MonsterAIGeneric.PrefersRange(ctx)
	if ctx.tactics.style == "ranged" then
		return true
	elseif ctx.tactics.style == "melee" then
		return false
	end
	local bestMelee, bestRanged = 0, 0
	for _,profile in ipairs(MonsterAIGeneric.OffensiveProfiles(ctx, "action")) do
		local value = 0
		if profile.attack ~= nil then
			value = profile.attack.avg * math.max(1, profile.numTargets)
		elseif profile.save ~= nil then
			value = profile.save.avg
		elseif profile.autoDamage ~= nil then
			value = profile.autoDamage
		end
		if profile.attack ~= nil and profile.attack.melee then
			bestMelee = math.max(bestMelee, value)
		elseif profile.range > dmhub.unitsPerSquare*2 then
			bestRanged = math.max(bestRanged, value)
		else
			bestMelee = math.max(bestMelee, value)
		end
	end
	--Multiattack usually repeats the melee attack, which favours melee.
	if Rules.MultiattackText(ctx.token) ~= nil then
		bestMelee = bestMelee * 1.4
	end
	return bestRanged > bestMelee*1.1
end

---------------------------------------------------------------------------
--Squares worth considering this cycle, with what each one means.
---------------------------------------------------------------------------

local function TilesBetween(a, b)
	return a:DistanceInTiles(b)
end

function MonsterAIGeneric.Paths(ai, token, ctx)
	if ctx.paths == nil then
		ctx.paths = ai:CalculateMovementPaths(token)
	end
	return ctx.paths
end

--The squares to plan from: where it stands, the cheapest squares near each
--target, and for ranged monsters squares no enemy is next to.
function MonsterAIGeneric.CandidateLocs(ai, token, ctx)
	if ctx.candidates ~= nil then
		return ctx.candidates
	end
	local paths = MonsterAIGeneric.Paths(ai, token, ctx)
	local chosen = {}
	local result = {}
	local function Add(info)
		if info ~= nil and not chosen[info.loc.str] then
			chosen[info.loc.str] = true
			result[#result+1] = info
		end
	end

	Add(paths[1])
	if ai.turn.moveLocked then
		ctx.candidates = result
		return result
	end

	local maxReachTiles = 1
	local maxRangeTiles = 1
	for _,profile in ipairs(ctx.profiles) do
		if Rules.IsOffensive(profile) then
			local tiles = math.ceil(profile.range / dmhub.unitsPerSquare)
			if profile.attack ~= nil and profile.attack.melee then
				maxReachTiles = math.max(maxReachTiles, tiles)
			end
			maxRangeTiles = math.max(maxRangeTiles, tiles)
		end
	end

	for _,target in ipairs(ctx.targets) do
		local reach = maxReachTiles + math.max(1, target.tileSize or 1)
		local count = 0
		for _,info in ipairs(paths) do
			if TilesBetween(info.loc, target.loc) <= reach then
				Add(info)
				count = count + 1
				if count >= 6 then
					break
				end
			end
		end
	end

	if ctx.prefersRange then
		local count = 0
		for _,info in ipairs(paths) do
			local nearest = 999
			for _,enemy in ipairs(ctx.enemies) do
				nearest = math.min(nearest, TilesBetween(info.loc, enemy.loc))
			end
			if nearest >= 2 then
				for _,target in ipairs(ctx.targets) do
					if TilesBetween(info.loc, target.loc) <= maxRangeTiles then
						Add(info)
						count = count + 1
						break
					end
				end
			end
			if count >= 12 then
				break
			end
		end
	end

	ctx.candidates = result
	return result
end

--Enemies whose reach `token` leaves by moving from where it stands to `loc`
--(each may make an opportunity attack).
function MonsterAIGeneric.ProvokersAt(ai, token, ctx, loc)
	if loc.str == token.loc.str or MonsterAIRules.HasEffect(token, "Disengaged") or ai.turn.disengaged then
		return 0
	end
	local count = 0
	for _,enemy in ipairs(ctx.enemies) do
		if not Rules.IsIncapacitated(enemy) and MonsterAI.InRange(dmhub.unitsPerSquare, token:Distance(enemy))
			and not MonsterAI.InRange(dmhub.unitsPerSquare, ai:DistanceFromLoc(token, loc, enemy)) then
			count = count + 1
		end
	end
	return count
end

function MonsterAIGeneric.EnemyAdjacentAt(ai, token, ctx, loc)
	for _,enemy in ipairs(ctx.enemies) do
		if not Rules.IsIncapacitated(enemy) and MonsterAI.InRange(dmhub.unitsPerSquare, ai:DistanceFromLoc(token, loc, enemy)) then
			return true
		end
	end
	return false
end

--How much a target matters: the damage a hit on it is worth.
function MonsterAIGeneric.TargetWeight(ctx, target)
	local frac = Rules.HitpointFraction(target)
	local focus = ctx.tactics.focus
	if focus == "weakest" then
		return 1.4 - frac*0.5
	elseif focus == "strongest" then
		return 0.8 + frac*0.3
	end
	--the house default: a slight lean towards healthy targets, so monsters
	--spread their pressure (finishing a target off is rewarded separately).
	return 0.95 + frac*0.1
end

--What a condition on the target is worth, in damage.
function MonsterAIGeneric.EffectValue(target)
	local maxhp = 10
	pcall(function() maxhp = target.properties:MaxHitpoints() end)
	return math.min(35, 8 + maxhp*0.15)
end

local function HasPackTactics(ctx)
	if ctx.packTactics == nil then
		local found = ctx.tactics.packTactics == true
		if not found then
			local notes = ctx.token.properties:try_get("notes") or {}
			for _,note in pairs(notes) do
				if string.find(string.lower(tostring(note.title or "")), "pack tactics", 1, true) then
					found = true
				end
			end
		end
		ctx.packTactics = found
	end
	return ctx.packTactics
end

local function AllyNextTo(ctx, target)
	for _,ally in ipairs(ctx.allies) do
		if not Rules.IsIncapacitated(ally) and MonsterAI.InRange(dmhub.unitsPerSquare, ally:Distance(target)) then
			return true
		end
	end
	return false
end

--Can `profile`, used from `loc`, reach `target`?
function MonsterAIGeneric.CanReach(ai, token, ctx, profile, loc, target)
	local distance = ai:DistanceFromLoc(token, loc, target)
	local range = profile.longRange or profile.range
	if not MonsterAI.InRange(range, distance) then
		return false, distance
	end
	if not profile.ability:TargetPassesFilter(token, target) then
		return false, distance
	end
	if ai:LineOfSightFromLoc(token, loc, target) <= 0 then
		return false, distance
	end
	return true, distance
end

--Expected value of one use of `profile` against one target from `loc`.
function MonsterAIGeneric.ValueAgainst(ai, token, ctx, profile, loc, target)
	local reachable, distance = MonsterAIGeneric.CanReach(ai, token, ctx, profile, loc, target)
	if not reachable then
		return nil
	end
	local value = 0
	if profile.attack ~= nil then
		local advantage = Rules.AttackAdvantage(token, target, profile, {
			distance = distance,
			enemyAdjacent = (not profile.attack.melee) and MonsterAIGeneric.EnemyAdjacentAt(ai, token, ctx, loc),
			packTactics = HasPackTactics(ctx) and AllyNextTo(ctx, target),
		})
		value = Rules.ExpectedAttackDamage(profile, target, advantage)
	end
	if profile.save ~= nil then
		value = value + Rules.ExpectedSaveValue(profile, target, MonsterAIGeneric.EffectValue(target))
	end
	if profile.autoDamage ~= nil then
		value = value + profile.autoDamage
	end
	return value
end

---------------------------------------------------------------------------
--Attack routines: Multiattack, or one ability used once.
---------------------------------------------------------------------------

--Routines for a kind of action: lists of slots, each slot a list of profiles.
function MonsterAIGeneric.Routines(ctx, kind)
	local cacheKey = "routines:" .. kind
	if ctx[cacheKey] ~= nil then
		return ctx[cacheKey]
	end
	local routines = {}
	local offensive = MonsterAIGeneric.OffensiveProfiles(ctx, kind)

	for _,profile in ipairs(offensive) do
		if profile.affordable and not Rules.IsArea(profile) then
			routines[#routines+1] = {slots = {{profile}}, label = profile.name}
		end
	end

	if kind == "action" then
		local byName = {}
		local names = {}
		for _,profile in ipairs(ctx.profiles) do
			if Rules.IsOffensive(profile) and (profile.kind == "action" or profile.kind == "free") and profile.basic == nil then
				--"Arcane Burst (Ranged)" fills a Multiattack's "Arcane Burst" slot:
				--5.5e stat blocks split melee and ranged versions this way.
				local base = string.gsub(profile.lname, "%s*%b()%s*$", "")
				if base == "" then
					base = profile.lname
				end
				if byName[base] == nil then
					names[#names+1] = base
				end
				byName[base] = byName[base] or {}
				table.insert(byName[base], profile)
			end
		end
		local parsed = Rules.ParseMultiattack(ctx.token, names)
		for _,parsedRoutine in ipairs(parsed or {}) do
			local slots = {}
			local valid = true
			for _,slotNames in ipairs(parsedRoutine) do
				local options = {}
				for _,name in ipairs(slotNames) do
					if name == "*" then
						for _,profile in ipairs(offensive) do
							if profile.attack ~= nil and profile.basic == nil then
								options[#options+1] = profile
							end
						end
					else
						for _,profile in ipairs(byName[name] or {}) do
							if not MonsterAIGeneric.ProfileExcluded(ctx, profile) then
								options[#options+1] = profile
							end
						end
					end
				end
				if #options == 0 then
					valid = false
					break
				end
				slots[#slots+1] = options
			end
			if valid and #slots > 0 then
				routines[#routines+1] = {slots = slots, multiattack = true, label = "Multiattack"}
			end
		end
	end

	ctx[cacheKey] = routines
	return routines
end

--Spend-a-resource cost of a profile in damage terms: limited spells and
--abilities are kept for when they are worth it.
local function UseCost(ctx, profile)
	local cost = 0
	--higher slots are scarcer (a Mage has one 5th-level slot a day), so they
	--cost more: a single-target big spell must clearly beat the free attack.
	if profile.isSpell and (profile.level or 0) > 0 then
		cost = 1 + 2*profile.level
	end
	--a recharge ability may not come back for several rounds.
	if profile.recharge then
		cost = cost + 4
	end
	if profile.concentration and Rules.IsConcentrating(ctx.token) then
		cost = cost + 12
	end
	if profile.basic == "unarmed strike" then
		cost = cost + 1
	end
	return cost
end

--Best way to run `routine` from `loc`: returns value and the planned uses
--{profile, targets = {token...}}.
function MonsterAIGeneric.EvaluateRoutine(ai, token, ctx, routine, loc)
	local hpLeft = {}
	local uses = {}
	local total = 0
	for _,slot in ipairs(routine.slots) do
		local bestValue, bestUse = 0, nil
		for _,profile in ipairs(slot) do
			if profile.affordable or routine.multiattack then
				local n = math.max(1, profile.numTargets or 1)
				local scored = {}
				for _,target in ipairs(ctx.targets) do
					local v = MonsterAIGeneric.ValueAgainst(ai, token, ctx, profile, loc, target)
					if v ~= nil and v > 0 then
						local left = hpLeft[target.charid] or math.max(1, target.properties:CurrentHitpoints())
						local credited = math.min(v, left + 2)
						if v >= left then
							credited = credited + 5
						end
						scored[#scored+1] = {target = target, value = credited*MonsterAIGeneric.TargetWeight(ctx, target), raw = v}
					end
				end
				table.sort(scored, function(a,b) return a.value > b.value end)
				local value = 0
				local targets = {}
				local duplicates = profile.ability:CanDuplicateTargets()
				for i=1,n do
					local entry = scored[i] or (duplicates and scored[1]) or nil
					if entry == nil then
						break
					end
					value = value + entry.value
					targets[#targets+1] = entry.target
				end
				value = value*MonsterAI.PreferenceFor(ctx.tactics, profile) - UseCost(ctx, profile)
				if #targets > 0 and value > bestValue then
					bestValue = value
					bestUse = {profile = profile, targets = targets, raw = scored[1].raw}
				end
			end
		end
		if bestUse ~= nil then
			total = total + bestValue
			uses[#uses+1] = bestUse
			for _,target in ipairs(bestUse.targets) do
				local left = hpLeft[target.charid] or math.max(1, target.properties:CurrentHitpoints())
				hpLeft[target.charid] = left - (bestUse.raw or 0)
			end
		end
	end
	return total, uses
end

---------------------------------------------------------------------------
--Areas: aim each area ability at each target and count who is caught.
---------------------------------------------------------------------------

function MonsterAIGeneric.AreaShape(token, profile, loc, aimToken)
	local shapeName = profile.targetType
	local args = {
		shape = shapeName,
		token = token,
		range = profile.range,
		radius = profile.radius,
	}
	if shapeName == "all" then
		args.shape = "RadiusFromCreature"
		args.radius = profile.range
	else
		args.targetPoint = aimToken.loc.point3
	end
	local shape = nil
	local fn = function()
		local ok, result = pcall(dmhub.CalculateShape, args)
		if ok then
			shape = result
		end
	end
	if loc == nil or loc.str == token.loc.str then
		fn()
	else
		token:ExecuteWithTheoreticalLoc(loc, fn)
	end
	return shape
end

--Value of an area ability aimed at aimToken from loc, and who it catches.
function MonsterAIGeneric.EvaluateArea(ai, token, ctx, profile, loc, aimToken)
	if profile.targetType ~= "all" then
		local distance = ai:DistanceFromLoc(token, loc, aimToken)
		local reach = profile.range
		if profile.targetType == "sphere" or profile.targetType == "cylinder" or profile.targetType == "cube" then
			reach = profile.range
		end
		if not MonsterAI.InRange(reach, distance) then
			return nil
		end
	end
	local shape = MonsterAIGeneric.AreaShape(token, profile, loc, aimToken)
	if shape == nil then
		return nil
	end
	local value = 0
	local caught = {}
	local enemiesCaught = 0
	for _,other in ipairs(dmhub.allTokens) do
		if MonsterAI.TokenIsLiveCombatant(other) and other.floorIndex == token.floorIndex then
			local inside = false
			pcall(function() inside = shape:ContainsToken(other) end)
			if other.charid == token.charid then
				local t = profile.targetType
				if loc.str ~= token.loc.str or t == "all" or t == "cone" or t == "line" then
					--an area from the caster leaves it out; and at a square it
					--moves to, this is where it stands now, not where it will.
					inside = false
				end
			end
			if inside and profile.ability:TargetPassesFilter(token, other) then
				local v = 0
				if profile.save ~= nil then
					v = v + Rules.ExpectedSaveValue(profile, other, MonsterAIGeneric.EffectValue(other))
				end
				if profile.autoDamage ~= nil then
					v = v + profile.autoDamage
				end
				if other.charid == token.charid or token:IsFriend(other) then
					value = value - v*(ctx.tactics.friendlyFire or 1.5)
				elseif not (MonsterAI.SettingOn("spareDying") and not ctx.tactics.finishDowned and Rules.IsDying(other)) then
					value = value + v*MonsterAIGeneric.TargetWeight(ctx, other)
					enemiesCaught = enemiesCaught + 1
				end
				caught[#caught+1] = other
			end
		end
	end
	if enemiesCaught == 0 then
		return nil
	end
	value = value*MonsterAI.PreferenceFor(ctx.tactics, profile) - UseCost(ctx, profile)
	return value, caught, shape, enemiesCaught
end

---------------------------------------------------------------------------
--Planning an action (or bonus or legendary action).
---------------------------------------------------------------------------

local function MovementPenalty(ai, token, ctx, info)
	local penalty = (info.cost or 0) / 10 * 0.05
	local provokers = MonsterAIGeneric.ProvokersAt(ai, token, ctx, info.loc)
	penalty = penalty + provokers * (ctx.tactics.provokePenalty or 6)
	if ctx.prefersRange and MonsterAIGeneric.EnemyAdjacentAt(ai, token, ctx, info.loc) then
		penalty = penalty + (ctx.tactics.adjacentPenalty or 3)
	end
	return penalty, provokers
end

--The best plan for one kind of action. Returns value, plan.
--options.noMove: plan only from where it stands.
function MonsterAIGeneric.PlanOffense(ai, token, ctx, kind, options)
	options = options or {}
	local locs
	if options.noMove then
		locs = {{loc = token.loc, cost = 0}}
	else
		locs = MonsterAIGeneric.CandidateLocs(ai, token, ctx)
	end

	local best, bestPlan = 0, nil
	local routines = MonsterAIGeneric.Routines(ctx, kind)
	local areas = {}
	for _,profile in ipairs(MonsterAIGeneric.OffensiveProfiles(ctx, kind)) do
		if profile.affordable and Rules.IsArea(profile) then
			areas[#areas+1] = profile
		end
	end

	for index,info in ipairs(locs) do
		local penalty, provokers = MovementPenalty(ai, token, ctx, info)
		for _,routine in ipairs(routines) do
			local value, uses = MonsterAIGeneric.EvaluateRoutine(ai, token, ctx, routine, info.loc)
			value = value - penalty
			if #uses > 0 and value > best then
				best = value
				bestPlan = {
					kind = kind,
					loc = info.loc,
					cost = info.cost,
					provokers = provokers,
					routine = routine,
					uses = uses,
					value = value,
				}
			end
		end
		--areas are aimed from where it stands and the closest squares only.
		if index <= 6 then
			for _,profile in ipairs(areas) do
				for _,aim in ipairs(ctx.targets) do
					local value, caught, shape, count = MonsterAIGeneric.EvaluateArea(ai, token, ctx, profile, info.loc, aim)
					if value ~= nil then
						value = value - penalty
						if value > best then
							best = value
							bestPlan = {
								kind = kind,
								loc = info.loc,
								cost = info.cost,
								provokers = provokers,
								area = {profile = profile, aim = aim, caught = caught, count = count},
								value = value,
							}
						end
					end
				end
			end
		end
	end

	if bestPlan ~= nil then
		bestPlan.description = MonsterAIGeneric.DescribePlan(token, bestPlan)
	end
	return best, bestPlan
end

function MonsterAIGeneric.DescribePlan(token, plan)
	local parts = {}
	if plan.loc ~= nil and plan.loc.str ~= token.loc.str then
		parts[#parts+1] = string.format("move %d ft", math.floor((plan.cost or 0)/10*dmhub.unitsPerSquare + 0.5))
	end
	if plan.area ~= nil then
		parts[#parts+1] = string.format("%s catching %d", plan.area.profile.name, #plan.area.caught)
	elseif plan.uses ~= nil then
		local uses = {}
		for _,use in ipairs(plan.uses) do
			local names = {}
			for _,target in ipairs(use.targets) do
				names[#names+1] = MonsterAI.DisplayName(target)
			end
			uses[#uses+1] = string.format("%s on %s", use.profile.name, table.concat(names, ", "))
		end
		if plan.routine ~= nil and plan.routine.multiattack then
			parts[#parts+1] = "Multiattack: " .. table.concat(uses, "; ")
		else
			parts[#parts+1] = table.concat(uses, "; ")
		end
	end
	if plan.provokers ~= nil and plan.provokers > 0 then
		parts[#parts+1] = string.format("(provokes %d)", plan.provokers)
	end
	return table.concat(parts, ", ")
end

--Map a plan's value (expected damage) to a move score in 0.3..0.95.
function MonsterAIGeneric.ScoreFromValue(value, base, span)
	base = base or 0.3
	span = span or 0.65
	if value <= 0 then
		return 0
	end
	return base + span*(1 - math.exp(-value/15))
end

---------------------------------------------------------------------------
--Executing plans.
---------------------------------------------------------------------------

--Move to the plan's square, saying "Charge!" on a long run into melee.
function MonsterAIGeneric.MoveForPlan(ai, token, plan, ctx)
	if plan.loc == nil or plan.loc.str == token.loc.str then
		return
	end
	local squares = (plan.cost or 0)/10
	local melee = false
	for _,use in ipairs(plan.uses or {}) do
		if use.profile.attack ~= nil and use.profile.attack.melee then
			melee = true
		end
	end
	if melee and squares >= 4 then
		ai:Speak(token, "charge")
	end
	ai:MoveToken(token, plan.loc)
	ai.turn.moved = true
	ai:BoardChanged()
end

--Use one profile on targets, switching loadout first if its weapon is not in hand.
function MonsterAIGeneric.UseProfile(ai, token, profile, targets, options)
	options = options or {}
	local ability = profile.ability
	local loadout = Rules.LoadoutForAbility(token, ability)
	if loadout ~= nil then
		Rules.SwitchLoadout(ai, token, loadout)
		local fresh = Rules.FindAbility(token, ability.name)
		if fresh ~= nil then
			ability = fresh
		end
	end
	local castTargets = {}
	for _,target in ipairs(targets) do
		if target.valid then
			castTargets[#castTargets+1] = {token = target, loc = target.loc}
		end
	end
	if #castTargets == 0 and ability.targetType ~= "self" then
		return false
	end
	local symbols = DeepCopy(profile.symbols or {mode = 1})
	local costOverride = nil
	if not options.alreadyPaid then
		local cost, castSymbols = Rules.CastCost(token, ability)
		if cost == nil then
			ai:LogDecision("CAST SKIPPED", {
				actor = MonsterAI.TokenLogName(token),
				ability = ability.name,
				reason = "cannot afford it any more",
			})
			return false
		end
		costOverride = cost
		symbols = castSymbols or symbols
	end
	local hpBefore = {}
	for _,target in ipairs(targets) do
		if target.valid then
			hpBefore[target.charid] = target.properties:CurrentHitpoints()
		end
	end
	ai:ExecuteAbility(token, ability, castTargets, {
		symbols = symbols,
		costOverride = costOverride,
		alreadyPaid = options.alreadyPaid,
		targetArea = options.targetArea,
		reason = options.reason,
	})
	--a creature it just dropped.
	for _,target in ipairs(targets) do
		if target.valid and not token:IsFriend(target) and hpBefore[target.charid] ~= nil
			and hpBefore[target.charid] > 0 and Rules.IsDying(target) then
			ai:Speak(token, "kill")
			break
		end
	end
	return true
end

--Re-aim a planned use at the best target in reach right now (the planned
--target may have dropped to an earlier attack).
local function RetargetUse(ai, token, ctx, use)
	local alive = {}
	for _,target in ipairs(use.targets) do
		if MonsterAI.TokenIsLiveCombatant(target) and not (MonsterAI.SettingOn("spareDying") and not ctx.tactics.finishDowned and Rules.IsDying(target))
			and MonsterAIGeneric.CanReach(ai, token, ctx, use.profile, token.loc, target) then
			alive[#alive+1] = target
		end
	end
	if #alive >= #use.targets then
		return alive
	end
	local fresh = MonsterAIGeneric.BuildContext(ai, token)
	local best, bestTarget = 0, nil
	for _,target in ipairs(fresh.targets) do
		local v = MonsterAIGeneric.ValueAgainst(ai, token, fresh, use.profile, token.loc, target)
		if v ~= nil and v > best then
			best = v
			bestTarget = target
		end
	end
	if bestTarget ~= nil then
		while #alive < #use.targets do
			alive[#alive+1] = bestTarget
		end
	end
	return alive
end

function MonsterAIGeneric.ExecuteOffense(ai, token, plan, ctx)
	MonsterAIGeneric.MoveForPlan(ai, token, plan, ctx)
	if not MonsterAI.TokenIsLiveCombatant(token) then
		return
	end

	if plan.area ~= nil then
		local profile = plan.area.profile
		local aim = plan.area.aim
		local fresh = MonsterAIGeneric.BuildContext(ai, token)
		local value, caught, shape = MonsterAIGeneric.EvaluateArea(ai, token, fresh, profile, token.loc, aim)
		if value == nil or value <= 0 then
			ai:LogDecision("AREA ABANDONED", {
				actor = MonsterAI.TokenLogName(token),
				ability = profile.name,
				reason = "after moving, the area no longer catches anyone worth it",
			})
			return
		end
		ai:Speak(token, profile.isSpell and "spell" or "area")
		MonsterAIGeneric.UseProfile(ai, token, profile, caught, {targetArea = shape, reason = plan.description})
		return
	end

	local uses = plan.uses or {}
	local spoke = false
	if plan.routine ~= nil and plan.routine.multiattack then
		--a spell or limited ability in the routine goes first and pays the
		--action; the other attacks of the Multiattack are already paid for.
		table.sort(uses, function(a,b)
			local aSpell = a.profile.isSpell and 1 or 0
			local bSpell = b.profile.isSpell and 1 or 0
			return aSpell > bSpell
		end)
	end
	for i,use in ipairs(uses) do
		if not MonsterAI.TokenIsLiveCombatant(token) or MonsterAI.StopRequested() then
			break
		end
		local targets = RetargetUse(ai, token, ctx, use)
		if #targets == 0 then
			ai:LogDecision("ATTACK SKIPPED", {
				actor = MonsterAI.TokenLogName(token),
				ability = use.profile.name,
				reason = "no target in reach",
			})
		else
			if not spoke then
				spoke = ai:Speak(token, use.profile.isSpell and "spell" or "attack")
			end
			local alreadyPaid = plan.routine ~= nil and plan.routine.multiattack and i > 1
			MonsterAIGeneric.UseProfile(ai, token, use.profile, targets, {alreadyPaid = alreadyPaid, reason = plan.description})
		end
	end
end

---------------------------------------------------------------------------
--Basic actions: Dash, Disengage, Dodge, Hide.
---------------------------------------------------------------------------

function MonsterAIGeneric.FindBasic(ctx, name, kind)
	for _,profile in ipairs(ctx.profiles) do
		if profile.lname == name and (kind == nil or profile.kind == kind) and profile.affordable then
			return profile
		end
	end
	return nil
end

--A bonus action that is described as a Dash, Disengage or Hide
--("Nimble Escape: The goblin takes the Disengage or Hide action.").
function MonsterAIGeneric.BonusBasic(ctx, name)
	for _,profile in ipairs(ctx.byKind["bonus"] or {}) do
		if profile.affordable then
			if profile.lname == name then
				return profile
			end
			if profile.textOnly then
				local text = string.lower(profile.ability.description or "")
				for _,note in pairs(ctx.token.properties:try_get("notes") or {}) do
					if string.lower(tostring(note.title or "")):find(profile.lname, 1, true) then
						text = text .. " " .. string.lower(note.text or "")
					end
				end
				if string.find(text, name .. " action", 1, true) or string.find(text, name .. " or ", 1, true)
					or string.find(text, " or " .. name, 1, true) then
					return profile
				end
			end
		end
	end
	return nil
end

--Take a basic action (Dash, Disengage, Dodge) with an action, or with a
--bonus action that grants it.
function MonsterAIGeneric.TakeBasic(ai, token, ctx, name, useBonus)
	local basic = MonsterAIGeneric.FindBasic(ctx, name, "action")
	if useBonus then
		local bonus = MonsterAIGeneric.BonusBasic(ctx, name)
		if bonus == nil then
			return false
		end
		if bonus.lname == name or basic == nil then
			MonsterAIGeneric.UseProfile(ai, token, bonus, {token}, {reason = name})
		else
			--pay with the bonus action, then apply the basic action's effect.
			MonsterAIGeneric.UseProfile(ai, token, bonus, {token}, {reason = name})
			MonsterAIGeneric.UseProfile(ai, token, basic, {token}, {alreadyPaid = true, reason = name})
		end
	else
		if basic == nil then
			return false
		end
		MonsterAIGeneric.UseProfile(ai, token, basic, {token}, {reason = name})
	end
	if name == "disengage" then
		ai.turn.disengaged = true
	elseif name == "dash" then
		ai.turn.dashed = true
	end
	return true
end

---------------------------------------------------------------------------
--Moving: advancing on the enemy, falling back, keeping range.
---------------------------------------------------------------------------

--The reachable square that gets closest to the nearest target.
function MonsterAIGeneric.AdvanceLoc(ai, token, ctx, paths)
	local best, bestInfo = nil, nil
	for _,info in ipairs(paths) do
		for _,target in ipairs(ctx.targets) do
			local d = TilesBetween(info.loc, target.loc)
			local score = d*10 + (info.cost or 0)*0.01
			if best == nil or score < best then
				best = score
				bestInfo = info
			end
		end
	end
	return bestInfo
end

--The reachable square farthest from the enemies (keeping a target in range
--when keepTarget is set).
function MonsterAIGeneric.RetreatLoc(ai, token, ctx, paths, keepRange)
	local best, bestInfo = nil, nil
	for _,info in ipairs(paths) do
		local nearest = 999
		local inRange = keepRange == nil
		for _,enemy in ipairs(ctx.enemies) do
			local d = TilesBetween(info.loc, enemy.loc)
			nearest = math.min(nearest, d)
			if keepRange ~= nil and d*dmhub.unitsPerSquare <= keepRange then
				inRange = true
			end
		end
		if inRange then
			local score = nearest - (info.cost or 0)*0.002
			if best == nil or score > best then
				best = score
				bestInfo = info
			end
		end
	end
	return bestInfo
end

function MonsterAIGeneric.LongestRange(ctx)
	local best = nil
	for _,profile in ipairs(MonsterAIGeneric.OffensiveProfiles(ctx, "action")) do
		if profile.range > dmhub.unitsPerSquare*2 then
			best = math.max(best or 0, profile.range)
		end
	end
	return best
end

---------------------------------------------------------------------------
--The generic moves.
---------------------------------------------------------------------------

MonsterAI.RegisterMove{
	id = "generic-action",
	description = "Attack, Multiattack, cast a spell or use an area ability, moving first if it helps.",
	category = "Action",
	generic = true,
	maxScore = 0.95,
	score = function(ai, token, ctx)
		if ai.turn.actionUsed or not Rules.HasAction(token, "action") then
			return 0
		end
		local value, plan = MonsterAIGeneric.PlanOffense(ai, token, ctx, "action")
		if plan == nil then
			return 0
		end
		return MonsterAIGeneric.ScoreFromValue(value), plan
	end,
	execute = function(ai, token, plan, ctx)
		ai.turn.actionUsed = true
		MonsterAIGeneric.ExecuteOffense(ai, token, plan, ctx)
	end,
}

MonsterAI.RegisterMove{
	id = "generic-bonus",
	description = "Use a bonus action that deals damage, imposes a condition or heals.",
	category = "Bonus Action",
	generic = true,
	maxScore = 0.85,
	score = function(ai, token, ctx)
		if ai.turn.bonusUsed or not Rules.HasAction(token, "bonus") then
			return 0
		end
		--bonus attacks are planned from where the action leaves it.
		local value, plan = MonsterAIGeneric.PlanOffense(ai, token, ctx, "bonus", {noMove = not ai.turn.actionUsed and Rules.HasAction(token, "action")})
		if plan == nil then
			return 0
		end
		return MonsterAIGeneric.ScoreFromValue(value, 0.25, 0.6), plan
	end,
	execute = function(ai, token, plan, ctx)
		ai.turn.bonusUsed = true
		MonsterAIGeneric.ExecuteOffense(ai, token, plan, ctx)
	end,
}

--Healing an ally (or itself) who is badly hurt.
local function PlanHeal(ai, token, ctx, kind)
	local best, bestPlan = 0, nil
	for _,profile in ipairs(ctx.byKind[kind] or {}) do
		if profile.heal ~= nil and profile.heal > 0 and profile.affordable then
			local candidates = {token}
			for _,ally in ipairs(ctx.allies) do
				candidates[#candidates+1] = ally
			end
			for _,ally in ipairs(candidates) do
				local frac = Rules.HitpointFraction(ally)
				if frac < 0.5 then
					local ok = true
					if profile.targetType == "self" then
						ok = ally.charid == token.charid
					elseif ally.charid ~= token.charid then
						ok = MonsterAI.InRange(profile.range, token:Distance(ally)) and profile.ability:TargetPassesFilter(token, ally)
					end
					if ok then
						local missing = ally.properties:MaxHitpoints() - ally.properties:CurrentHitpoints()
						local value = math.min(profile.heal, missing)*(1.5 - frac) - UseCost(ctx, profile)
						if Rules.IsDying(ally) then
							value = value + 10
						end
						if value > best then
							best = value
							bestPlan = {profile = profile, target = ally, description = string.format("%s on %s", profile.name, MonsterAI.DisplayName(ally))}
						end
					end
				end
			end
		end
	end
	return best, bestPlan
end

MonsterAI.RegisterMove{
	id = "generic-heal",
	description = "Heal an ally (or itself) below half hit points.",
	category = "Action",
	generic = true,
	maxScore = 0.9,
	score = function(ai, token, ctx)
		local best, bestPlan, bestKind = 0, nil, nil
		for _,kind in ipairs({"action", "bonus"}) do
			local used = (kind == "action" and ai.turn.actionUsed) or (kind == "bonus" and ai.turn.bonusUsed)
			if not used and Rules.HasAction(token, kind) then
				local value, plan = PlanHeal(ai, token, ctx, kind)
				if kind == "bonus" then
					value = value*1.2
				end
				if plan ~= nil and value > best then
					best, bestPlan, bestKind = value, plan, kind
				end
			end
		end
		if bestPlan == nil then
			return 0
		end
		bestPlan.kind = bestKind
		return MonsterAIGeneric.ScoreFromValue(best, 0.3, 0.6), bestPlan
	end,
	execute = function(ai, token, plan, ctx)
		if plan.kind == "bonus" then
			ai.turn.bonusUsed = true
		else
			ai.turn.actionUsed = true
		end
		ai:Speak(token, "heal")
		MonsterAIGeneric.UseProfile(ai, token, plan.profile, {plan.target}, {reason = plan.description})
	end,
}

--Teleport or Disengage away from melee: ranged monsters before they attack,
--and anyone badly hurt whose tactics say to fall back.
MonsterAI.RegisterMove{
	id = "generic-escape",
	description = "Get out of melee with a bonus action (Misty Step, Nimble Escape) when fighting from range or badly hurt.",
	category = "Bonus Action",
	generic = true,
	maxScore = 0.7,
	score = function(ai, token, ctx)
		if ai.turn.bonusUsed or ai.turn.escaped or not Rules.HasAction(token, "bonus") then
			return 0
		end
		local adjacent = MonsterAIGeneric.EnemyAdjacentAt(ai, token, ctx, token.loc)
		if not adjacent then
			return 0
		end
		local hurt = Rules.HitpointFraction(token) < (ctx.tactics.retreatBelow or 0)
		if not ctx.prefersRange and not hurt then
			return 0
		end

		--a teleport (Misty Step).
		for _,profile in ipairs(ctx.byKind["bonus"] or {}) do
			if profile.relocate and profile.affordable and (profile.targetType == "emptyspace" or profile.targetType == "anyspace") then
				return 0.7, {profile = profile, teleport = true, description = profile.name .. " away from melee"}
			end
		end

		--a bonus Disengage (Nimble Escape), then step away.
		local bonus = MonsterAIGeneric.BonusBasic(ctx, "disengage")
		if bonus ~= nil and MonsterAI.MovementLeftFeet(token) > 0 then
			return 0.65, {disengage = true, description = bonus.name .. " (Disengage) and step away"}
		end
		return 0
	end,
	execute = function(ai, token, plan, ctx)
		ai.turn.bonusUsed = true
		ai.turn.escaped = true
		ai:Speak(token, "retreat")
		if plan.teleport then
			local profile = plan.profile
			local radiusTiles = math.floor(profile.range/dmhub.unitsPerSquare)
			local best, bestLoc = nil, nil
			local here = token.loc
			for dx=-radiusTiles,radiusTiles do
				for dy=-radiusTiles,radiusTiles do
					local loc = here:dir(dx, dy)
					if loc.isOnMap and math.max(math.abs(dx), math.abs(dy)) >= 2 then
						local free = true
						for _,other in ipairs(dmhub.allTokens) do
							if other.charid ~= token.charid and other.floorIndex == token.floorIndex then
								for _,l in ipairs(other.locsOccupying) do
									if l.x == loc.x and l.y == loc.y then
										free = false
									end
								end
							end
						end
						if free and MonsterAI.InRange(profile.range, token:Distance(loc)) then
							local nearest = 999
							for _,enemy in ipairs(ctx.enemies) do
								nearest = math.min(nearest, TilesBetween(loc, enemy.loc))
							end
							local longest = MonsterAIGeneric.LongestRange(ctx)
							local keeps = longest == nil
							for _,target in ipairs(ctx.targets) do
								if longest ~= nil and TilesBetween(loc, target.loc)*dmhub.unitsPerSquare <= longest then
									keeps = true
								end
							end
							local score = nearest + (keeps and 5 or 0)
							if best == nil or score > best then
								best = score
								bestLoc = loc
							end
						end
					end
				end
			end
			if bestLoc ~= nil then
				ai:ExecuteAbility(token, profile.ability, {{loc = bestLoc}}, {
					symbols = profile.symbols,
					costOverride = profile.cost,
					reason = plan.description,
				})
			end
			ai.turn.moveLocked = nil
			return
		end

		MonsterAIGeneric.TakeBasic(ai, token, ctx, "disengage", true)
		local fresh = MonsterAIGeneric.BuildContext(ai, token)
		local paths = ai:CalculateMovementPaths(token)
		local loc = MonsterAIGeneric.RetreatLoc(ai, token, fresh, paths, MonsterAIGeneric.LongestRange(fresh))
		if loc ~= nil then
			ai:MoveToken(token, loc.loc)
			ai.turn.moved = true
		end
	end,
}

--Nothing in reach this turn: close in, dashing if the action has no better use.
MonsterAI.RegisterMove{
	id = "generic-advance",
	description = "Move towards the nearest enemy when nothing is in reach, Dashing if there is nothing better to do with the action.",
	category = "Movement",
	generic = true,
	maxScore = 0.2,
	score = function(ai, token, ctx)
		if ai.turn.advanced or #ctx.targets == 0 or ctx.tactics.holdPosition then
			return 0
		end
		--the action is spent and something is already in reach from here (an
		--archer that just shot): stay rather than walk into melee.
		if ai.turn.actionUsed or not Rules.HasAction(token, "action") then
			for _,profile in ipairs(MonsterAIGeneric.OffensiveProfiles(ctx, "action")) do
				for _,target in ipairs(ctx.targets) do
					if MonsterAIGeneric.CanReach(ai, token, ctx, profile, token.loc, target) then
						return 0
					end
				end
			end
		end
		local paths = MonsterAIGeneric.Paths(ai, token, ctx)
		local info = MonsterAIGeneric.AdvanceLoc(ai, token, ctx, paths)
		local dash = not ai.turn.actionUsed and Rules.HasAction(token, "action") and MonsterAIGeneric.FindBasic(ctx, "dash", "action") ~= nil
		local bonusDash = not ai.turn.bonusUsed and Rules.HasAction(token, "bonus") and MonsterAIGeneric.BonusBasic(ctx, "dash") ~= nil
		if (info == nil or info.loc.str == token.loc.str) and not dash and not bonusDash then
			return 0
		end
		return 0.15, {loc = info ~= nil and info.loc or nil, dash = dash, bonusDash = bonusDash, description = "advance on the enemy"}
	end,
	execute = function(ai, token, plan, ctx)
		ai.turn.advanced = true
		if plan.loc ~= nil and plan.loc.str ~= token.loc.str then
			ai:MoveToken(token, plan.loc)
			ai.turn.moved = true
		end
		--still nothing to hit: Dash and keep coming.
		local fresh = MonsterAIGeneric.BuildContext(ai, token)
		local value = 0
		if Rules.HasAction(token, "action") and not ai.turn.actionUsed then
			value = MonsterAIGeneric.PlanOffense(ai, token, fresh, "action")
		end
		if value <= 0 and (plan.dash or plan.bonusDash) and #fresh.targets > 0 then
			local dashed = false
			if plan.bonusDash and not ai.turn.bonusUsed then
				dashed = MonsterAIGeneric.TakeBasic(ai, token, fresh, "dash", true)
				if dashed then
					ai.turn.bonusUsed = true
				end
			end
			if not dashed and plan.dash then
				dashed = MonsterAIGeneric.TakeBasic(ai, token, fresh, "dash", false)
				if dashed then
					ai.turn.actionUsed = true
				end
			end
			if dashed then
				local paths = ai:CalculateMovementPaths(token)
				local info = MonsterAIGeneric.AdvanceLoc(ai, token, fresh, paths)
				if info ~= nil and info.loc.str ~= token.loc.str then
					ai:MoveToken(token, info.loc)
				end
			end
		end
	end,
}

--After acting, a ranged monster steps back out of reach.
MonsterAI.RegisterMove{
	id = "generic-reposition",
	description = "After attacking, a monster that fights from range moves away from the enemy, keeping a target in range.",
	category = "Movement",
	generic = true,
	maxScore = 0.12,
	score = function(ai, token, ctx)
		if ai.turn.repositioned or not ctx.prefersRange or not ai.turn.actionUsed or ctx.tactics.holdPosition then
			return 0
		end
		if MonsterAI.MovementLeftFeet(token) < dmhub.unitsPerSquare then
			return 0
		end
		local paths = MonsterAIGeneric.Paths(ai, token, ctx)
		local info = MonsterAIGeneric.RetreatLoc(ai, token, ctx, paths, MonsterAIGeneric.LongestRange(ctx))
		if info == nil or info.loc.str == token.loc.str then
			return 0
		end
		local provokers = MonsterAIGeneric.ProvokersAt(ai, token, ctx, info.loc)
		if provokers > 0 then
			return 0
		end
		local nearestNow, nearestThen = 999, 999
		for _,enemy in ipairs(ctx.enemies) do
			nearestNow = math.min(nearestNow, TilesBetween(token.loc, enemy.loc))
			nearestThen = math.min(nearestThen, TilesBetween(info.loc, enemy.loc))
		end
		if nearestThen <= nearestNow then
			return 0
		end
		return 0.12, {loc = info.loc, description = "fall back to keep range"}
	end,
	execute = function(ai, token, plan, ctx)
		ai.turn.repositioned = true
		ai:MoveToken(token, plan.loc)
	end,
}

--Badly hurt and its tactics say to run: Disengage and get away.
MonsterAI.RegisterMove{
	id = "generic-flee",
	description = "A monster whose tactics say to flee when badly hurt takes the Disengage action and runs.",
	category = "Action",
	generic = true,
	maxScore = 0.98,
	score = function(ai, token, ctx)
		local below = ctx.tactics.fleeBelow
		if below == nil or ai.turn.fled or Rules.HitpointFraction(token) >= below then
			return 0
		end
		if ai.turn.actionUsed or not Rules.HasAction(token, "action") then
			return 0
		end
		return 0.98, {description = "flee"}
	end,
	execute = function(ai, token, plan, ctx)
		ai.turn.fled = true
		ai.turn.actionUsed = true
		ai:Speak(token, "retreat", {force = true})
		if MonsterAIGeneric.EnemyAdjacentAt(ai, token, ctx, token.loc) then
			if not (not ai.turn.bonusUsed and MonsterAIGeneric.TakeBasic(ai, token, ctx, "disengage", true)) then
				MonsterAIGeneric.TakeBasic(ai, token, ctx, "disengage", false)
			end
		else
			MonsterAIGeneric.TakeBasic(ai, token, ctx, "dash", false)
		end
		local paths = ai:CalculateMovementPaths(token)
		local info = MonsterAIGeneric.RetreatLoc(ai, token, ctx, paths, nil)
		if info ~= nil then
			ai:MoveToken(token, info.loc)
		end
	end,
}

--Nothing better to do with the action while enemies are close: Dodge.
MonsterAI.RegisterMove{
	id = "generic-dodge",
	description = "Take the Dodge action when enemies are close and there is nothing better to do.",
	category = "Action",
	generic = true,
	maxScore = 0.1,
	score = function(ai, token, ctx)
		if ai.turn.actionUsed or not Rules.HasAction(token, "action") then
			return 0
		end
		if MonsterAIGeneric.FindBasic(ctx, "dodge", "action") == nil then
			return 0
		end
		if not MonsterAIGeneric.EnemyAdjacentAt(ai, token, ctx, token.loc) then
			return 0
		end
		return 0.1, {description = "Dodge"}
	end,
	execute = function(ai, token, plan, ctx)
		ai.turn.actionUsed = true
		MonsterAIGeneric.TakeBasic(ai, token, ctx, "dodge", false)
	end,
}

---------------------------------------------------------------------------
--Between turns: legendary actions and opportunity attacks.
---------------------------------------------------------------------------

--The best legendary action for `token` now, if one is worth using.
function MonsterAIGeneric.PlanLegendary(ai, token)
	if not Rules.HasAction(token, "legendary") then
		return nil
	end
	local ctx = MonsterAIGeneric.BuildContext(ai, token)
	local value, plan = MonsterAIGeneric.PlanOffense(ai, token, ctx, "legendary", {noMove = true})
	if plan == nil or value < 2 then
		return nil
	end
	return plan, ctx
end

function MonsterAIGeneric.ExecuteLegendary(ai, token, plan, ctx)
	ai:Speak(token, "legendary")
	MonsterAIGeneric.ExecuteOffense(ai, token, plan, ctx)
end

--Strike a creature that just moved out of reach, with the reaction.
function MonsterAIGeneric.OpportunityAttack(ai, token, target)
	if not Rules.HasAction(token, "reaction") or Rules.IsIncapacitated(token) then
		return false
	end
	local ctx = MonsterAIGeneric.BuildContext(ai, token)
	local best, bestProfile = 0, nil
	for _,profile in ipairs(MonsterAIGeneric.OffensiveProfiles(ctx, "action")) do
		if profile.attack ~= nil and profile.attack.melee and not Rules.IsArea(profile) and (profile.numTargets or 1) <= 1 then
			local advantage = Rules.AttackAdvantage(token, target, profile, {distance = dmhub.unitsPerSquare})
			local value = Rules.ExpectedAttackDamage(profile, target, advantage)
			if Rules.LoadoutForAbility(token, profile.ability) ~= nil then
				--no time to change weapons.
				value = 0
			end
			if value > best then
				best = value
				bestProfile = profile
			end
		end
	end
	if bestProfile == nil then
		return false
	end
	ai:LogDecision("OPPORTUNITY ATTACK", {
		actor = MonsterAI.TokenLogName(token),
		target = MonsterAI.TokenLogName(target),
		ability = bestProfile.name,
		expected = best,
	})
	ai:Speak(token, "opportunity")
	Rules.ConsumeResource(token, "reaction", "Opportunity Attack")
	MonsterAIGeneric.UseProfile(ai, token, bestProfile, {target}, {alreadyPaid = true, reason = "opportunity attack"})
	return true
end

---------------------------------------------------------------------------
--Speech at the start of a turn: a battle cry on its first turn of the fight,
--and a line when it is first bloodied and when it is near death.
---------------------------------------------------------------------------

local g_spokenMoments = {}

MonsterAI.BeginTurnHook = function(ai, token)
	local q = dmhub.initiativeQueue
	local combat = q ~= nil and tostring(q.guid) or "none"
	local function Once(moment)
		local key = combat .. ":" .. token.charid .. ":" .. moment
		if g_spokenMoments[key] then
			return false
		end
		g_spokenMoments[key] = true
		return true
	end
	local frac = Rules.HitpointFraction(token)
	if frac < 0.25 then
		if Once("dying") then
			ai:Speak(token, "dying", {force = true})
		end
	elseif frac < 0.5 then
		if Once("hurt") then
			ai:Speak(token, "hurt")
		end
	elseif Once("start") then
		local band = MonsterAI.SpeechBandFor(token)
		if band ~= nil and band.lines ~= nil and band.lines.start ~= nil then
			ai:Speak(token, "start")
		end
	end
end
