local mod = dmhub.GetModLoading()

--The Monster AI panel, and the AI thread it starts. The thread runs as a
--DockablePanel background process: it keeps playing monster turns when the
--panel is closed, and the panel's rail button spins its gear while it runs.
--
--Each tick the thread:
--  1. strikes creatures that moved out of a monster's reach (opportunity attacks)
--  2. on a change of turn, gives legendary monsters their legendary action
--  3. if the current initiative entry belongs to creatures no player controls,
--     plays each of them (MonsterAI:PlayTurn), then ends the turn

local Rules = MonsterAIRules

DockablePanel.Register{
	name = "Monster AI",
	icon = "phosphor/cpu-light.png",
	minHeight = 60,
	dmonly = true,
	content = function()
		return MonsterAI.CreatePanel()
	end,
}

---------------------------------------------------------------------------
--Opportunity attacks: noticed by watching where creatures stand.
---------------------------------------------------------------------------

--tokens seen moving along a path since the last check (a teleport never is,
--and does not provoke).
local g_movingSeen = {}

local function MeleeReach(ai, token)
	local reach = nil
	for _,profile in ipairs(Rules.Profiles(token)) do
		if profile.kind == "action" and profile.attack ~= nil and profile.attack.melee and profile.affordable ~= nil then
			reach = math.max(reach or 0, profile.range)
		end
	end
	return reach
end

local g_reachCache = {}
local function CachedReach(ai, token)
	local entry = g_reachCache[token.charid]
	if entry == nil or dmhub.Time() - entry.time > 10 then
		entry = {time = dmhub.Time(), reach = MeleeReach(ai, token)}
		g_reachCache[token.charid] = entry
	end
	return entry.reach
end

local function CheckOpportunityAttacks(ai, queue)
	local previous = MonsterAI.lastPositions or {}
	local current = queue:CurrentInitiativeId()
	for _,mover in ipairs(dmhub.allTokens) do
		if mover.isMoving then
			g_movingSeen[mover.charid] = true
		end
	end

	local provocations = {}
	for _,mover in ipairs(dmhub.allTokens) do
		local before = previous[mover.charid]
		if before ~= nil and before.loc.str ~= mover.loc.str and before.floor == mover.floorIndex
			and not MonsterAI.ownMoves[mover.charid] and MonsterAI.TokenIsLiveCombatant(mover)
			and (g_movingSeen[mover.charid] or mover.isMoving)
			and InitiativeQueue.GetInitiativeId(mover) == current
			and not Rules.HasEffect(mover, "Disengaged") then
			for _,monster in ipairs(dmhub.allTokens) do
				if monster.charid ~= mover.charid and MonsterAI.IsAIPlayed(monster) and MonsterAI.TokenIsLiveCombatant(monster)
					and monster.floorIndex == mover.floorIndex and not monster:IsFriend(mover)
					and previous[monster.charid] ~= nil and previous[monster.charid].loc.str == monster.loc.str
					and not Rules.IsIncapacitated(monster) and Rules.HasAction(monster, "reaction") then
					local reach = CachedReach(ai, monster)
					if reach ~= nil then
						local wasIn = false
						mover:ExecuteWithTheoreticalLoc(before.loc, function()
							wasIn = MonsterAI.InRange(reach, monster:Distance(mover))
						end)
						local nowIn = MonsterAI.InRange(reach, monster:Distance(mover))
						if wasIn and not nowIn then
							provocations[#provocations+1] = {monster = monster, mover = mover}
						end
					end
				end
			end
		end
		if not mover.isMoving then
			g_movingSeen[mover.charid] = nil
		end
	end
	MonsterAI.NoteTokenPositions()

	for _,p in ipairs(provocations) do
		if MonsterAI.StopRequested() then
			return
		end
		if MonsterAI.TokenIsLiveCombatant(p.mover) and MonsterAI.TokenIsLiveCombatant(p.monster) then
			local oa = MonsterAI.new{}
			creature.BeginAIControl(p.monster.charid, function(casterToken, ability, symbols, options)
				return MonsterAI.HandlePrompt(oa, casterToken, ability, symbols, options)
			end)
			local ok, err = oa:RunYieldingFunction(function()
				MonsterAIGeneric.OpportunityAttack(oa, p.monster, p.mover)
			end)
			creature.EndAIControl(p.monster.charid)
			if not ok then
				oa:LogDecision("OPPORTUNITY ATTACK ERROR", {actor = MonsterAI.TokenLogName(p.monster), reason = tostring(err)})
			end
		end
	end
end

---------------------------------------------------------------------------
--Legendary actions: at the end of each other creature's turn, each
--legendary monster may use one.
---------------------------------------------------------------------------

local function RunLegendaryWindow(endedInitiativeId)
	for _,token in ipairs(dmhub.allTokens) do
		if MonsterAI.StopRequested() then
			return
		end
		if MonsterAI.IsAIPlayed(token) and MonsterAI.TokenIsLiveCombatant(token)
			and InitiativeQueue.GetInitiativeId(token) ~= endedInitiativeId
			and not Rules.IsIncapacitated(token) and Rules.HasAction(token, "legendary") then
			local ai = MonsterAI.new{}
			ai.turn = {legendary = true, moveLocked = true}
			local plan, ctx = MonsterAIGeneric.PlanLegendary(ai, token)
			if plan ~= nil then
				ai:LogDecision("LEGENDARY ACTION", {
					actor = MonsterAI.TokenLogName(token),
					plan = plan.description,
					value = plan.value,
				})
				local proceed = true
				if MonsterAI.AwaitPlanPreview ~= nil then
					proceed = MonsterAI.AwaitPlanPreview(ai, token, {id = "legendary", category = "Legendary"}, plan)
				end
				if proceed == true then
					creature.BeginAIControl(token.charid, function(casterToken, ability, symbols, options)
						return MonsterAI.HandlePrompt(ai, casterToken, ability, symbols, options)
					end)
					local ok, err = ai:RunYieldingFunction(function()
						ai:FocusCameraOnActor(token)
						MonsterAIGeneric.ExecuteLegendary(ai, token, plan, ctx)
					end)
					creature.EndAIControl(token.charid)
					if not ok then
						ai:LogDecision("LEGENDARY ERROR", {actor = MonsterAI.TokenLogName(token), reason = tostring(err)})
					end
				end
			end
		end
	end
end

---------------------------------------------------------------------------
--The thread.
---------------------------------------------------------------------------

--The tokens of an initiative entry, and whether the AI plays the entry.
local function EntryTokens(initiativeid)
	local hud = GameHud.instance
	if not hud or not hud:has_key("initiativeInterface") then
		return nil, false
	end
	local tokens = hud:GetTokensForInitiativeId(hud.initiativeInterface, initiativeid)
	local live = {}
	local ours = true
	local any = false
	for _,tok in ipairs(tokens) do
		if tok ~= nil and tok.valid then
			any = true
			if not MonsterAI.IsAIPlayed(tok) then
				ours = false
			end
			live[#live+1] = tok
		end
	end
	if not any then
		--a monster entry whose monsters are all gone is ended for them.
		ours = string.starts_with(initiativeid, "MONSTER-")
	end
	return live, ours
end

local function TurnKey(queue, initiativeid)
	if initiativeid == nil then
		return nil
	end
	local entry = queue.entries[initiativeid]
	return string.format("%s:%d:%s:%s", tostring(queue.guid), queue.round, initiativeid, tostring(entry ~= nil and entry.round or "?"))
end

local function MonsterAIThread(process)
	ElevateToHostPermissions()

	local lifecycle = MonsterAI.new{}
	MonsterAI.active = true
	MonsterAI.status = "Running"
	MonsterAI.process = process
	lifecycle:LogDecision("AI STARTED", {result = "background process is active"})
	pcall(MonsterAI.ClearWaiting)
	pcall(MonsterAI.ClearPlanPreview)
	creature.SetAIActivityInProgress(nil)
	creature.ClearAIControl()
	MonsterAI.NoteTokenPositions()

	local played = {}
	local lastTurnKey = nil
	local lastInitiativeId = nil

	while true do
		coroutine.yield(0.1)
		if mod.unloaded or MonsterAI.stopRequested or (process ~= nil and process.stopRequested) then
			MonsterAI.active = false
			MonsterAI.status = "Stopped"
			lifecycle:LogDecision("AI STOPPED", {
				reason = mod.unloaded and "Monster AI module unloaded" or "stop requested",
			})
			pcall(MonsterAI.ClearWaiting)
			pcall(MonsterAI.ClearPlanPreview)
			pcall(creature.SetAIActivityInProgress, nil)
			pcall(creature.ClearAIControl)
			return
		end

		local ok, err = MonsterAI.RunYieldingFunction(function()
			local queue = dmhub.initiativeQueue
			if queue == nil or queue.hidden then
				MonsterAI.status = "Waiting for combat"
				MonsterAI.NoteTokenPositions()
				lastTurnKey = nil
				return
			end

			if MonsterAI.SettingOn("opportunity") then
				CheckOpportunityAttacks(lifecycle, queue)
			else
				MonsterAI.NoteTokenPositions()
			end

			local current = queue:CurrentInitiativeId()
			local turnKey = TurnKey(queue, current)
			if turnKey ~= lastTurnKey then
				local ended = lastInitiativeId
				lastTurnKey = turnKey
				lastInitiativeId = current
				if ended ~= nil and MonsterAI.SettingOn("legendary") then
					RunLegendaryWindow(ended)
				end
				--the window may have taken a while; look again next tick.
				return
			end

			if current == nil or played[turnKey] then
				return
			end

			local tokens, ours = EntryTokens(current)
			if not ours then
				MonsterAI.status = "Waiting for the players"
				return
			end

			played[turnKey] = true
			--let start-of-turn effects (recharges, ongoing damage) settle.
			MonsterAI.Sleep(0.6)

			for _,token in ipairs(tokens or {}) do
				if MonsterAI.StopRequested() then
					return
				end
				if MonsterAI.TokenIsLiveCombatant(token) then
					local ai = MonsterAI.new{}
					ai:PlayTurn(token)
				end
			end

			MonsterAI.status = "Ending turn"
			MonsterAI.Sleep(0.4)
			local q = dmhub.initiativeQueue
			if q ~= nil and not q.hidden and q:CurrentInitiativeId() == current and TurnKey(q, current) == turnKey
				and not MonsterAI.StopRequested() then
				--the HUD is briefly missing while it rebuilds (a Lua reload).
				local waited = 0
				while not GameHud.instance and waited < 10 and not MonsterAI.StopRequested() do
					MonsterAI.Sleep(0.5)
					waited = waited + 0.5
				end
				local hud = GameHud.instance
				if hud then
					hud:NextInitiative()
					hud.initiativeInterface.UploadInitiative()
					lifecycle:LogDecision("TURN ADVANCED", {initiative = current})
				end
			end
			MonsterAI.status = "Running"
		end)

		if not ok then
			lifecycle:LogDecision("AI THREAD ERROR", {reason = tostring(err)})
			MonsterAI.Sleep(1)
		end
	end
end

function MonsterAI.StartAI()
	MonsterAI.stopRequested = false
	MonsterAI.playEntireTurn = false
	DockablePanel.StartProcess{
		panel = "Monster AI",
		id = "monster-ai",
		coroutine = MonsterAIThread,
	}
end

function MonsterAI.StopAI()
	MonsterAI.stopRequested = true
	DockablePanel.StopProcess("Monster AI", "monster-ai")
end

function MonsterAI.IsAIRunning()
	return DockablePanel.HasActiveProcess("Monster AI")
end

---------------------------------------------------------------------------
--Analysis: what the AI will do with each monster on the map.
---------------------------------------------------------------------------

function MonsterAI.Analysis()
	local byType = {}
	local list = {}
	for _,token in ipairs(dmhub.allTokens) do
		if MonsterAI.IsAIPlayed(token) and token.properties ~= nil then
			local monsterType = MonsterAI.MonsterTypeName(token) or "creature"
			if byType[monsterType] == nil then
				local entry = {monsterType = monsterType, token = token, moves = {}}
				byType[monsterType] = entry
				list[#list+1] = entry
				local ok, language = pcall(function() return token.properties:CurrentlySpokenLanguage() end)
				if ok and language ~= nil then
					local info = (dmhub.GetTable(Language.tableName) or {})[language]
					entry.language = info ~= nil and info.name or nil
				end
				if MonsterAI.AssessSupport ~= nil then
					local okSupport, support = pcall(MonsterAI.AssessSupport, token)
					if okSupport then
						entry.support = support
					end
				end
				for _,id in ipairs(MonsterAI.moveOrder) do
					local move = MonsterAI.moves[id]
					if MonsterAI.MonsterMatches(token, move.monsters) then
						entry.moves[#entry.moves+1] = move
					end
				end
			end
		end
	end
	table.sort(list, function(a,b) return a.monsterType < b.monsterType end)
	return list
end

---------------------------------------------------------------------------
--The panel.
---------------------------------------------------------------------------

local function SettingCheck(id, text)
	return gui.Check{
		text = text,
		fontSize = 14,
		width = "auto",
		height = 22,
		value = dmhub.GetSettingValue("monsterai:" .. id) == true,
		change = function(element)
			dmhub.SetSettingValue("monsterai:" .. id, element.value)
		end,
	}
end

local function MonsterEntryPanel(entry)
	local children = {}
	local header = string.format("<b>%s</b>", entry.monsterType)
	if entry.language ~= nil then
		header = header .. string.format("  <i>speaks %s</i>", entry.language)
	else
		header = header .. "  <i>no language</i>"
	end
	children[#children+1] = gui.Label{
		fontSize = 15,
		width = "100%",
		height = "auto",
		text = header,
	}
	if entry.support ~= nil then
		children[#children+1] = gui.Label{
			fontSize = 13,
			width = "100%-8",
			lmargin = 8,
			height = "auto",
			text = entry.support.summary,
			hover = function(element)
				if entry.support.details ~= nil and #entry.support.details > 0 then
					gui.Tooltip(table.concat(entry.support.details, "\n"))(element)
				end
			end,
		}
	end
	local currentCategory = nil
	for _,move in ipairs(entry.moves) do
		if move.category ~= currentCategory then
			currentCategory = move.category
			children[#children+1] = gui.Label{
				fontSize = 13,
				lmargin = 8,
				width = "auto",
				height = "auto",
				text = string.format("<u>%s</u>", currentCategory),
			}
		end
		children[#children+1] = gui.Panel{
			flow = "horizontal",
			width = "100%-16",
			height = "auto",
			lmargin = 16,
			gui.Check{
				text = "",
				width = 14,
				height = 16,
				minWidth = 14,
				valign = "center",
				value = not MonsterAI.MoveDisabled(entry.monsterType, move.id),
				change = function(element)
					MonsterAI.SetMoveDisabled(entry.monsterType, move.id, not element.value)
				end,
			},
			gui.Label{
				fontSize = 13,
				hmargin = 4,
				width = "100%-24",
				height = "auto",
				text = move.generic and move.id or string.format("<b>%s</b>", move.id),
				hover = function(element)
					if move.description ~= nil then
						gui.Tooltip(move.description)(element)
					end
				end,
			},
		}
	end
	return gui.Panel{
		width = "100%",
		height = "auto",
		flow = "vertical",
		vmargin = 4,
		children = children,
	}
end

function MonsterAI.CreatePanel()
	local resultPanel
	local m_logChanged = nil

	local analysisPanel = gui.Panel{
		width = "100%",
		height = "auto",
		flow = "vertical",
		refreshAnalysis = function(element)
			local panels = {}
			for _,entry in ipairs(MonsterAI.Analysis()) do
				panels[#panels+1] = MonsterEntryPanel(entry)
			end
			if #panels == 0 then
				panels[1] = gui.Label{
					fontSize = 13,
					width = "100%",
					height = "auto",
					text = "No monsters on this map.",
				}
			end
			element.children = panels
		end,
	}

	local logLabel = gui.Label{
		fontSize = 12,
		width = "100%",
		height = "auto",
		text = "",
		refreshLog = function(element)
			local lines = {}
			local log = MonsterAI.log
			for i=math.max(1, #log-11),#log do
				local entry = log[i]
				lines[#lines+1] = string.format("%s %s", entry.event, entry.text)
			end
			element.text = table.concat(lines, "\n")
		end,
	}

	resultPanel = gui.Panel{
		width = "100%",
		height = "auto",
		flow = "vertical",

		create = function(element)
			analysisPanel:FireEvent("refreshAnalysis")
		end,

		gui.Panel{
			width = "100%",
			height = "auto",
			flow = "horizontal",
			gui.Button{
				text = "Start AI",
				width = 100,
				height = 30,
				fontSize = 14,
				thinkTime = 0.2,
				think = function(element)
					element.text = MonsterAI.IsAIRunning() and "Stop AI" or "Start AI"
				end,
				click = function(element)
					if MonsterAI.IsAIRunning() then
						MonsterAI.StopAI()
					else
						MonsterAI.StartAI()
					end
				end,
			},
			gui.Label{
				fontSize = 14,
				hmargin = 8,
				width = "auto",
				height = "auto",
				valign = "center",
				thinkTime = 0.2,
				think = function(element)
					if MonsterAI.IsAIRunning() then
						element.text = MonsterAI.stopRequested and "Stopping..." or (MonsterAI.status or "Running")
					else
						element.text = "Not running"
					end
					if MonsterAI.logChanged ~= m_logChanged then
						m_logChanged = MonsterAI.logChanged
						resultPanel:FireEventTree("refreshLog")
					end
				end,
			},
		},

		--shown while a plan preview waits.
		gui.Panel{
			width = "100%",
			height = "auto",
			flow = "vertical",
			classes = {"collapsed"},
			thinkTime = 0.2,
			think = function(element)
				local pending = MonsterAI.PreviewPending ~= nil and MonsterAI.PreviewPending() or nil
				element:SetClass("collapsed", pending == nil)
				if pending ~= nil then
					element.children[1].text = pending
				end
			end,
			gui.Label{
				fontSize = 14,
				width = "100%",
				height = "auto",
				text = "",
			},
			gui.Panel{
				width = "100%",
				height = "auto",
				flow = "horizontal",
				gui.Button{
					text = "Proceed",
					width = 100,
					height = 26,
					fontSize = 13,
					click = function()
						MonsterAI.ProceedPreview(false)
					end,
				},
				gui.Button{
					text = "Play Entire Turn",
					width = 140,
					height = 26,
					fontSize = 13,
					hmargin = 6,
					click = function()
						MonsterAI.ProceedPreview(true)
					end,
				},
				gui.Button{
					text = "Skip",
					width = 70,
					height = 26,
					fontSize = 13,
					click = function()
						MonsterAI.SkipPreview()
					end,
				},
			},
		},

		gui.Label{
			fontSize = 15,
			width = "100%",
			height = "auto",
			vmargin = 4,
			text = "<b>Options</b>",
		},
		SettingCheck("preview", "Preview each plan"),
		SettingCheck("speech", "Monsters speak"),
		SettingCheck("opportunity", "Opportunity attacks"),
		SettingCheck("legendary", "Legendary actions"),
		SettingCheck("autosaves", "Roll monster saves"),
		SettingCheck("spareDying", "Leave dying heroes alone"),

		gui.Panel{
			width = "100%",
			height = "auto",
			flow = "horizontal",
			vmargin = 4,
			gui.Label{
				fontSize = 15,
				width = "auto",
				height = "auto",
				text = "<b>Monsters</b>",
			},
			gui.Button{
				text = "Refresh",
				width = 70,
				height = 22,
				fontSize = 12,
				hmargin = 8,
				click = function()
					analysisPanel:FireEvent("refreshAnalysis")
				end,
			},
		},
		analysisPanel,

		gui.Label{
			fontSize = 15,
			width = "100%",
			height = "auto",
			vmargin = 4,
			text = "<b>Recent decisions</b>",
		},
		logLabel,
	}

	return resultPanel
end
