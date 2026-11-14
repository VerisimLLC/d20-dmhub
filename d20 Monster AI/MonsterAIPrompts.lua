local mod = dmhub.GetModLoading()

--Prompts an ability raises in the middle of a cast by an AI creature: an
--invoked ability that wants its targets chosen, or the next target of a
--sequentially targeted ability. Without an answer the Director would be
--shown the targeting UI for the monster. Bands can register their own
--answers with MonsterAI.RegisterPrompt; this file registers the fallback,
--which aims the ability the way the generic planner would.

local Rules = MonsterAIRules

local function GenericPrompt(ai, casterToken, ability, symbols, options)
	if casterToken == nil or not casterToken.valid then
		return nil
	end
	local profile = Rules.ProfileAbility(casterToken, ability)
	profile.symbols = symbols or profile.symbols
	local ctx = MonsterAIGeneric.BuildContext(ai, casterToken)
	ai.turn = ai.turn or {}

	local targetType = ability.targetType
	if targetType == "self" then
		return {targets = {{token = casterToken, loc = casterToken.loc}}}
	end

	if Rules.IsArea(profile) then
		local best, bestCaught = 0, nil
		for _,aim in ipairs(ctx.targets) do
			local value, caught = MonsterAIGeneric.EvaluateArea(ai, casterToken, ctx, profile, casterToken.loc, aim)
			if value ~= nil and value > best then
				best = value
				bestCaught = caught
			end
		end
		if bestCaught == nil then
			return "skip"
		end
		local targets = {}
		for _,t in ipairs(bestCaught) do
			targets[#targets+1] = {token = t, loc = t.loc}
		end
		return {targets = targets}
	end

	if targetType == "target" then
		local forbidden = symbols ~= nil and symbols.forbiddentargets or nil
		local helpful = profile.heal ~= nil or (not Rules.IsOffensive(profile) and #profile.effects > 0)
		local candidates = {}
		if helpful then
			candidates[#candidates+1] = casterToken
			for _,ally in ipairs(ctx.allies) do
				candidates[#candidates+1] = ally
			end
		else
			candidates = ctx.targets
		end
		local scored = {}
		for _,target in ipairs(candidates) do
			if forbidden == nil or not forbidden[target.charid] then
				local value = nil
				if helpful then
					if target.charid == casterToken.charid or MonsterAI.InRange(profile.range, casterToken:Distance(target)) then
						value = 1 + (1 - Rules.HitpointFraction(target))*10
					end
				else
					value = MonsterAIGeneric.ValueAgainst(ai, casterToken, ctx, profile, casterToken.loc, target)
				end
				if value ~= nil then
					scored[#scored+1] = {target = target, value = value}
				end
			end
		end
		table.sort(scored, function(a,b) return a.value > b.value end)
		local n = math.max(1, profile.numTargets or 1)
		local targets = {}
		for i=1,math.min(n, #scored) do
			targets[#targets+1] = {token = scored[i].target, loc = scored[i].target.loc}
		end
		if #targets == 0 then
			return "skip"
		end
		return {targets = targets}
	end

	--empty or any space (a teleport, a summon): stay put if nothing better.
	if targetType == "emptyspace" or targetType == "anyspace" or targetType == "emptyspacefriend" then
		local paths = ai:CalculateMovementPaths(casterToken, profile.range)
		local info = MonsterAIGeneric.AdvanceLoc(ai, casterToken, ctx, paths)
		if info ~= nil then
			return {targets = {{loc = info.loc}}}
		end
		return "skip"
	end

	return nil
end

MonsterAI.RegisterPrompt{
	abilities = nil,
	monsters = nil,
	handler = GenericPrompt,
}
