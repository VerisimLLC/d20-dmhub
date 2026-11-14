local mod = dmhub.GetModLoading()

--Tactic profiles: how a monster likes to fight. The generic planner reads
--these; MonsterAIBands.lua registers profiles for key monsters, and every
--monster gets a default profile from its stat block (a beast fights like a
--beast, a clever creature picks on the weak).
--
--MonsterAI.RegisterTactic{ monsters = {...}, <options> }. Options:
--  style          "melee" | "ranged" | nil (decided from its attacks)
--  focus          "weakest" | "strongest" | nil (a slight lean to healthy targets)
--  finishDowned   true: attacks creatures at 0 hit points
--  fleeBelow      hit point fraction below which it Disengages and runs
--  retreatBelow   hit point fraction below which it uses an escape bonus action
--  holdPosition   true: never advances or repositions
--  packTactics    true: values targets an ally stands next to
--  friendlyFire   how much it minds catching allies in an area (default 1.5)
--  provokePenalty damage-equivalent cost of each opportunity attack it provokes (default 6)
--  adjacentPenalty cost for a ranged fighter of ending next to an enemy (default 3)
--  prefer         { ["ability name"] = multiplier } on the value of using it
--  avoidAbilities { ["ability name"] = true } never used by the generic planner
--Later registrations override earlier ones, option by option.

local Rules = MonsterAIRules

local function IntelligenceModifier(token)
	local mod = 0
	pcall(function()
		mod = token.properties:GetAttribute("int"):Modifier()
	end)
	return mod
end

local function DefaultTactics(token)
	local tactics = {}
	local intMod = IntelligenceModifier(token)
	if intMod <= -4 then
		--a beast or a mindless thing: whatever is in front of it, down or not.
		tactics.finishDowned = true
		tactics.provokePenalty = 3
	elseif intMod >= 2 then
		tactics.focus = "weakest"
		tactics.provokePenalty = 8
	end
	return tactics
end

local g_cache = {}

--- The merged tactic profile for a token.
function MonsterAI.TacticsFor(token)
	local key = token.charid
	local entry = g_cache[key]
	if entry ~= nil and dmhub.Time() - entry.time < 5 then
		return entry.tactics
	end
	local tactics = DefaultTactics(token)
	for _,registration in ipairs(MonsterAI.tactics) do
		if MonsterAI.MonsterMatches(token, registration.monsters) then
			for k,v in pairs(registration) do
				if k ~= "monsters" then
					if type(v) == "table" and type(tactics[k]) == "table" then
						local merged = {}
						for k2,v2 in pairs(tactics[k]) do
							merged[k2] = v2
						end
						for k2,v2 in pairs(v) do
							merged[k2] = v2
						end
						tactics[k] = merged
					else
						tactics[k] = v
					end
				end
			end
		end
	end
	--ability names are matched in lowercase.
	for _,field in ipairs({"prefer", "avoidAbilities"}) do
		if tactics[field] ~= nil then
			local lowered = {}
			for k,v in pairs(tactics[field]) do
				lowered[string.lower(k)] = v
			end
			tactics[field] = lowered
		end
	end
	g_cache[key] = {time = dmhub.Time(), tactics = tactics}
	return tactics
end

--Multiplier a tactic profile puts on using a profile.
function MonsterAI.PreferenceFor(tactics, profile)
	if tactics == nil or tactics.prefer == nil then
		return 1
	end
	return tactics.prefer[profile.lname] or 1
end
