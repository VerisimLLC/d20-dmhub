local mod = dmhub.GetModLoading()

--Support assessment: how much of a monster's stat block the AI can play.
--The panel shows the summary under each monster type and the details as a
--tooltip, so a Director knows what to watch for (a trait written only as
--text, a reaction the AI never takes).

local Rules = MonsterAIRules

--what each part of a stat block is to the AI.
local USED = "used"
local PARTIAL = "partly"
local UNUSED = "not used"

local function Classify(profile, ctx)
	if profile.basic ~= nil then
		if profile.basic == "dash" or profile.basic == "dodge" or profile.basic == "disengage" then
			return USED, "basic action"
		end
		return nil
	end
	if profile.kind == "reaction" then
		if profile.attack ~= nil then
			return PARTIAL, "reaction: the AI only makes opportunity attacks"
		end
		return UNUSED, "reaction: the AI only makes opportunity attacks"
	end
	if profile.textOnly then
		if profile.kind == "bonus" and (MonsterAIGeneric.BonusBasic(ctx, "disengage") == profile or MonsterAIGeneric.BonusBasic(ctx, "dash") == profile) then
			return USED, "bonus action read as Disengage / Dash"
		end
		return UNUSED, "its effect is only described in text"
	end
	if Rules.IsOffensive(profile) then
		if Rules.IsArea(profile) then
			return USED, "area, aimed to catch the most enemies and fewest allies"
		end
		if profile.save ~= nil and profile.save.avg == 0 then
			return USED, "saving throw to impose a condition"
		end
		return USED, profile.attack ~= nil and "attack" or "damage"
	end
	if profile.heal ~= nil then
		return USED, "healing for allies below half hit points"
	end
	if profile.relocate and profile.kind == "bonus" then
		return USED, "teleport to escape melee"
	end
	if profile.relocate then
		return UNUSED, "movement ability"
	end
	return UNUSED, "a buff or utility the AI does not cast"
end

--- @return {summary: string, details: string[], used: integer, total: integer}
function MonsterAI.AssessSupport(token)
	local ai = MonsterAI.new{}
	local ctx = MonsterAIGeneric.BuildContext(ai, token)
	local details = {}
	local used, total = 0, 0

	for _,profile in ipairs(ctx.profiles) do
		local status, why = Classify(profile, ctx)
		if status ~= nil then
			if profile.basic == nil then
				total = total + 1
				if status == USED then
					used = used + 1
				end
			end
			details[#details+1] = string.format("%s (%s): %s - %s", profile.name, profile.kind, status, why)
		end
	end

	local notes = token.properties:try_get("notes") or {}
	local multiattack = nil
	if Rules.MultiattackText(token) ~= nil then
		local routines = MonsterAIGeneric.Routines(ctx, "action")
		for _,routine in ipairs(routines) do
			if routine.multiattack then
				local names = {}
				for _,slot in ipairs(routine.slots) do
					names[#names+1] = slot[1] ~= nil and slot[1].name or "?"
				end
				multiattack = multiattack or {}
				multiattack[#multiattack+1] = table.concat(names, ", ")
			end
		end
		if multiattack ~= nil then
			details[#details+1] = "Multiattack: " .. table.concat(multiattack, " | or | ")
		else
			details[#details+1] = "Multiattack: not understood; the AI makes single attacks"
		end
	end

	for _,note in pairs(notes) do
		local title = tostring(note.title or "")
		local lower = string.lower(title)
		if string.find(lower, "legendary resistance", 1, true) then
			details[#details+1] = title .. ": not used (the Director decides)"
		elseif string.find(lower, "pack tactics", 1, true) then
			details[#details+1] = title .. ": used (prefers targets next to its allies)"
		end
	end

	local band = MonsterAI.SpeechBandFor(token)
	local tactics = ctx.tactics
	local extras = {}
	if band ~= nil then
		extras[#extras+1] = "band speech"
	end
	for _,id in ipairs(MonsterAI.moveOrder) do
		local move = MonsterAI.moves[id]
		if not move.generic and move.monsters ~= nil and MonsterAI.MonsterMatches(token, move.monsters) then
			extras[#extras+1] = id
		end
	end

	local summary
	if total == 0 then
		summary = "Plays its basic actions only."
	else
		summary = string.format("Uses %d of %d abilities", used, total)
		if multiattack ~= nil then
			summary = summary .. ", Multiattack"
		end
		summary = summary .. "."
	end
	if #extras > 0 then
		summary = summary .. " Tactics: " .. table.concat(extras, ", ") .. "."
	end

	return {summary = summary, details = details, used = used, total = total}
end
