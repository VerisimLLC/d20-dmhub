local mod = dmhub.GetModLoading()

--Plan preview: with "Preview each plan" on, the AI stops before each thing a
--monster does, shows it to the table -- the move as an arrow, the targets as
--lines, an area as marked squares, and a line of text on the tip banner --
--and waits until the Director presses Proceed (on the banner or in the
--panel), Play Entire Turn (no more previews this turn) or Skip (the monster
--does not do that this turn).
--
--The host publishes the preview to a shared document; every client draws it.

local PREVIEW_DOC = "monsterAIPreview"

local function CurrentTurnKey()
	local q = dmhub.initiativeQueue
	if q == nil or q.hidden then
		return nil
	end
	return string.format("%s:%d:%s", tostring(q.guid), q.round, tostring(q:CurrentInitiativeId()))
end

function MonsterAI.PlanPreviewsOn()
	return MonsterAI.SettingOn("preview")
end

function MonsterAI.ClearPlanPreview()
	local doc = mod:GetDocumentSnapshot(PREVIEW_DOC)
	if doc.data.seq == nil then
		return
	end
	doc:BeginChange()
	doc.data.seq = nil
	doc.data.text = nil
	doc.data.actor = nil
	doc.data.to = nil
	doc.data.targets = nil
	doc.data.locs = nil
	doc.data.answer = nil
	doc:CompleteChange("Monster AI preview cleared", {undoable = false})
end

--The preview text the host is waiting on, or nil.
function MonsterAI.PreviewPending()
	local doc = mod:GetDocumentSnapshot(PREVIEW_DOC)
	if doc.data.seq ~= nil and doc.data.answer == nil then
		return doc.data.text
	end
	return nil
end

local function Answer(answer)
	local doc = mod:GetDocumentSnapshot(PREVIEW_DOC)
	if doc.data.seq == nil or doc.data.answer ~= nil then
		return
	end
	doc:BeginChange()
	doc.data.answer = answer
	doc:CompleteChange("Monster AI preview answered", {undoable = false})
end

function MonsterAI.ProceedPreview(entireTurn)
	Answer(entireTurn and "turn" or "proceed")
end

function MonsterAI.SkipPreview()
	Answer("skip")
end

--- Show what `token` is about to do and wait for an answer.
--- Returns true (go ahead), "skip" (don't do this move) or false (the AI stopped).
function MonsterAI.AwaitPlanPreview(ai, token, move, plan)
	if not MonsterAI.PlanPreviewsOn() or plan == nil then
		return true
	end
	local turnKey = CurrentTurnKey()
	if turnKey ~= nil and MonsterAI.playEntireTurnKey == turnKey then
		return true
	end

	local targets = {}
	local seen = {}
	local function AddTarget(t)
		if t ~= nil and t.valid and not seen[t.charid] then
			seen[t.charid] = true
			targets[#targets+1] = t.charid
		end
	end
	for _,use in ipairs(plan.uses or {}) do
		for _,t in ipairs(use.targets or {}) do
			AddTarget(t)
		end
	end
	if plan.target ~= nil then
		AddTarget(plan.target)
	end
	local locs = nil
	if plan.area ~= nil then
		for _,t in ipairs(plan.area.caught or {}) do
			AddTarget(t)
		end
		local shape = MonsterAIGeneric.AreaShape(token, plan.area.profile, plan.loc, plan.area.aim)
		if shape ~= nil then
			locs = {}
			for _,loc in ipairs(shape.locations or {}) do
				locs[#locs+1] = {x = loc.x, y = loc.y}
			end
		end
	end

	local text = string.format("%s: %s", MonsterAI.DisplayName(token),
		plan.description or move.description or move.id)
	local seq = dmhub.GenerateGuid()
	local doc = mod:GetDocumentSnapshot(PREVIEW_DOC)
	doc:BeginChange()
	doc.data.seq = seq
	doc.data.text = text
	doc.data.actor = token.charid
	doc.data.to = (plan.loc ~= nil and plan.loc.str ~= token.loc.str) and {x = plan.loc.x, y = plan.loc.y} or nil
	doc.data.floor = token.floorIndex
	doc.data.targets = targets
	doc.data.locs = locs
	doc.data.answer = nil
	doc:CompleteChange("Monster AI preview", {undoable = false})

	ai:LogDecision("PLAN PREVIEW", {actor = MonsterAI.TokenLogName(token), plan = text})
	MonsterAI.status = "Waiting: Proceed to continue"

	local answer = nil
	while true do
		coroutine.yield(0.1)
		if MonsterAI.StopRequested() then
			break
		end
		local current = mod:GetDocumentSnapshot(PREVIEW_DOC)
		if current.data.seq ~= seq then
			break
		end
		if current.data.answer ~= nil then
			answer = current.data.answer
			break
		end
		if not MonsterAI.PlanPreviewsOn() then
			answer = "proceed"
			break
		end
	end

	MonsterAI.ClearPlanPreview()
	MonsterAI.status = "Running"
	ai:LogDecision("PLAN PREVIEW ANSWERED", {actor = MonsterAI.TokenLogName(token), answer = answer or "none"})

	if answer == "turn" then
		MonsterAI.playEntireTurnKey = turnKey
		return true
	elseif answer == "proceed" then
		return true
	elseif answer == "skip" then
		return "skip"
	end
	return false
end

---------------------------------------------------------------------------
--Every client: the banner line and the marks on the map.
---------------------------------------------------------------------------

Tip.notices["monster-ai-preview"] = {
	id = "monster-ai-preview",
	priority = 900,
	text = function()
		local doc = mod:GetDocumentSnapshot(PREVIEW_DOC)
		if doc.data.seq == nil or doc.data.answer ~= nil or type(doc.data.text) ~= "string" then
			return nil
		end
		local actor = doc.data.actor ~= nil and dmhub.GetTokenById(doc.data.actor) or nil
		if actor == nil or not actor.valid then
			return nil
		end
		if not dmhub.isDM and not actor.canSee then
			return nil
		end
		if dmhub.isDM then
			--the banner's second button is always labelled "Dismiss" (GameHud,
			--synced from the Codex), so it skips the action; "Play Entire
			--Turn" lives in the Monster AI panel.
			return doc.data.text .. "  (Dismiss skips it)", {
				action = {
					text = "Proceed",
					press = function()
						MonsterAI.ProceedPreview(false)
					end,
				},
				dismiss = function()
					MonsterAI.SkipPreview()
				end,
			}
		end
		return doc.data.text
	end,
}

local m_drawnSeq = nil
local m_marks = {}
local m_arrowToken = nil

local function ClearMarks()
	for _,mark in ipairs(m_marks) do
		pcall(function() mark:Destroy() end)
	end
	m_marks = {}
	if m_arrowToken ~= nil then
		local tok = m_arrowToken
		pcall(function()
			if tok.valid then
				tok:ClearMovementArrow()
			end
		end)
		m_arrowToken = nil
	end
end

local function DrawPreview(data)
	local actor = data.actor ~= nil and dmhub.GetTokenById(data.actor) or nil
	if actor == nil or not actor.valid then
		return
	end
	if not dmhub.isDM and not actor.canSee then
		return
	end
	local fromPos = actor.pos
	if type(data.to) == "table" then
		pcall(function()
			local loc = core.Loc{x = data.to.x, y = data.to.y, floorIndex = data.floor or actor.floorIndex}
			actor:MarkMovementArrow(loc)
			m_arrowToken = actor
			fromPos = actor:PosAtLoc(loc)
		end)
	end
	for _,charid in ipairs(data.targets or {}) do
		local target = dmhub.GetTokenById(charid)
		if target ~= nil and target.valid and (dmhub.isDM or target.canSee) then
			pcall(function()
				m_marks[#m_marks+1] = dmhub.HighlightLine{
					a = fromPos,
					b = target.pos,
					floorIndex = actor.floorIndex,
					color = actor:IsFriend(target) and "#ffaa00" or "red",
				}
			end)
		end
	end
	if data.locs ~= nil and #data.locs > 0 then
		pcall(function()
			local locs = {}
			for _,l in ipairs(data.locs) do
				locs[#locs+1] = core.Loc{x = l.x, y = l.y, floorIndex = data.floor or actor.floorIndex}
			end
			m_marks[#m_marks+1] = dmhub.MarkLocs{
				locs = locs,
				color = "#ff440088",
			}
		end)
	end
end

dmhub.Coroutine(function()
	while not mod.unloaded do
		local ok, err = pcall(function()
			local doc = mod:GetDocumentSnapshot(PREVIEW_DOC)
			local seq = doc.data.answer == nil and doc.data.seq or nil
			if seq ~= m_drawnSeq then
				ClearMarks()
				m_drawnSeq = seq
				if seq ~= nil then
					DrawPreview(doc.data)
				end
			end
		end)
		if not ok then
			print("AI:: PREVIEW DRAW ERROR", tostring(err))
			m_drawnSeq = nil
			coroutine.yield(2)
		end
		coroutine.yield(0.2)
	end
	ClearMarks()
end)
