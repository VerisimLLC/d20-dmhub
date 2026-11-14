local mod = dmhub.GetModLoading()

--This file implements the main roll prompt dialog that appears when you get a dice roll prompt.
--
--Form factor follows the Draw Steel Codex's ability roll card (Timeline/EmbeddedRollDialog.lua
--and Timeline/AbilitySidebar.lua there), rebuilt for 5e rules:
--
--  * The dialog is a card on the right side of the screen, mounted into the HUD's standalone
--    roll host (GameHud:CreateStandaloneRollHost). When the roll comes from an ability
--    (options.ability), that ability's card is drawn above the roll.
--  * The dice to be rolled rest in a dice cage inside the card (gui.DicePreview). Click them,
--    drag-and-throw them, or press Roll Dice; they are hurled across the screen.
--  * Disadvantage / Normal / Advantage, modifiers, critical hit and inspiration are pills.
--  * The card stays up while the dice roll, showing the live total, then the result, and
--    fades away a moment later.
--
--Networking: while the rolling token has the current initiative turn and the roll is
--visible to everyone, the roll's state is written to a shared document. Everyone else sees a
--read-only copy of the card (the ability, advantage, modifiers, the dice landing and the
--result) in the HUD's ability display panel (GameHud:InitAbilityDisplayPanel).
--
--GameHud.instance.rollDialog is a small invisible controller panel: GameHud.lua places it in
--the HUD's root children, while the visible card lives in the standalone roll host. Callers
--use only rollDialog.data (ShowDialog / IsShown / Cancel / rollid), which is unchanged.

setting{
	id = "privaterolls",
	description = "Default Roll Visibility",
	storage = "preference",
	default = "visible",
	editor = "dropdown",
	section = "Game",

	enum = {
		{
			value = "visible",
			text = "Visible to Everyone",
		},
		{
			value = "dm",
			text = cond(dmhub.isDM, "Visible to GM only", "Visible to you and GM"),
		}
	}
}

setting{
	id = "privaterolls:save",
	description = "Save roll visibility preferences",
	storage = "preference",
	default = true,
	editor = "check",
}

local g_rollOptionsDM = {
	{
		id = "visible",
		text = "Visible to Everyone",
	},
	{
		id = "dm",
		text = "Visible to GM only",
	},
}

local g_rollOptionsPlayer = {
	{
		id = "visible",
		text = "Visible to Everyone",
	},
	{
		id = "dm",
		text = "Visible to you and GM",
	},
}

--Width of the roll card. Fits the HUD's ability display panel (360) used for the remote copy.
local CARD_WIDTH = 360

--How long the result stays on the card after the dice land.
local RESULT_LINGER_SECONDS = 4

--Roll types that roll a d20 and can land a natural 20 / natural 1.
local g_d20RollTypes = {
	d20 = true,
	check = true,
	save = true,
	skill = true,
	attribute = true,
	initiative = true,
	deathsave = true,
}

--Styles for the card and the remote copy. Resolved against the active color scheme by
--ThemeEngine.MergeTokens; the host panels already carry the base theme cascade.
local g_cardStyles = {
	{
		selectors = {"rollFrame"},
		--panel widths exclude padding: this keeps the frame, pad included, at CARD_WIDTH
		--so it lines up with the ability card above it.
		width = CARD_WIDTH - 20,
		height = "auto",
		flow = "vertical",
		bgimage = "panels/square.png",
		--the ability card's backdrop, with plain hard edges.
		bgcolor = "#000000f6",
		cornerRadius = 10,
		pad = 10,
	},
	{
		selectors = {"rollTitle"},
		--room for the settings cog and close X.
		width = "100%-56",
		height = "auto",
		halign = "left",
		fontSize = 20,
		bold = true,
		color = "@fgStrong",
		textWrap = true,
	},
	{
		selectors = {"rollSubtitle"},
		width = "100%",
		height = "auto",
		fontSize = 14,
		color = "@fgMuted",
		italics = true,
		textWrap = true,
	},
	{
		selectors = {"explanation"},
		width = "auto",
		height = "auto",
		fontSize = 14,
		color = "@fg",
		textWrap = true,
		maxWidth = CARD_WIDTH - 40,
	},
	{
		selectors = {"rollPanel"},
		--less its own pad, so it stays inside the frame.
		width = "100%-12",
		height = "auto",
		flow = "vertical",
		bgimage = true,
		bgcolor = "@bgAlt",
		borderWidth = 1,
		borderColor = "@border",
		cornerRadius = 6,
		pad = 6,
		vmargin = 6,
	},
	{
		selectors = {"rollTab"},
		bgimage = true,
		bgcolor = "@accent",
		cornerRadius = 4,
	},
	{
		selectors = {"rollTabLabel"},
		color = "black",
		bold = true,
		fontSize = 16,
	},

	--pills: the advantage bar, modifiers, critical hit and inspiration.
	{
		selectors = {"pillRow"},
		width = "100%",
		height = "auto",
		flow = "horizontal",
		wrap = true,
		halign = "center",
	},
	{
		--a row that never wraps (the advantage bar): shrink to its pills so it centers.
		selectors = {"pillRow", "centered"},
		width = "auto",
	},
	{
		selectors = {"pill"},
		width = "auto",
		height = 24,
		flow = "horizontal",
		hpad = 8,
		hmargin = 2,
		vmargin = 2,
		bgimage = true,
		bgcolor = "@bg",
		borderWidth = 2,
		borderColor = "@border",
		cornerRadius = 4,
	},
	{
		selectors = {"pill", "hover", "~readOnly"},
		borderColor = "@accentHover",
	},
	{
		selectors = {"pill", "selected"},
		borderColor = "@info",
	},
	{
		selectors = {"pill", "selected", "advantage"},
		borderColor = "@success",
	},
	{
		selectors = {"pill", "selected", "disadvantage"},
		borderColor = "@danger",
	},
	{
		selectors = {"pillLabel"},
		width = "auto",
		height = "auto",
		valign = "center",
		fontSize = 14,
		color = "@fgMuted",
	},
	{
		selectors = {"pillLabel", "selected"},
		color = "@fg",
		bold = true,
	},
	{
		selectors = {"pillLock"},
		width = 12,
		height = 12,
		valign = "center",
		lmargin = 4,
		bgcolor = "@fg",
		collapsed = 1,
	},
	{
		selectors = {"pillLock", "locked"},
		collapsed = 0,
	},

	--the result: live total while the dice roll, then outcome and dice.
	{
		selectors = {"rollTotal"},
		width = "auto",
		height = "auto",
		halign = "center",
		textAlignment = "center",
		fontSize = 40,
		bold = true,
		color = "@fgStrong",
	},
	{
		selectors = {"rollOutcome"},
		width = "auto",
		height = "auto",
		halign = "center",
		textAlignment = "center",
		fontSize = 20,
		bold = true,
	},
	{
		selectors = {"rollText"},
		width = "auto",
		height = "auto",
		halign = "center",
		fontSize = 14,
		color = "@fgMuted",
	},
	{
		selectors = {"diceChip"},
		width = "auto",
		height = 22,
		hpad = 6,
		hmargin = 2,
		vmargin = 2,
		bgimage = true,
		bgcolor = "@bg",
		borderWidth = 1,
		borderColor = "@border",
		cornerRadius = 4,
	},
	{
		selectors = {"diceChipLabel"},
		width = "auto",
		height = "auto",
		valign = "center",
		fontSize = 14,
		color = "@fg",
	},
	{
		selectors = {"diceChipLabel", "dropped"},
		color = "@fgMuted",
	},

	--roll state: the card carries "rolling" while the dice are in the air and
	--"finished" once they land.
	{
		selectors = {"collapsedWhenRolling", "rolling"},
		collapsed = 1,
	},
	{
		selectors = {"collapsedWhenRolling", "finished"},
		collapsed = 1,
	},
	{
		selectors = {"collapsedWhenFinished", "finished"},
		collapsed = 1,
	},
	{
		selectors = {"shownWhenRolling", "~rolling", "~finished"},
		collapsed = 1,
	},
	{
		selectors = {"shownWhenFinished", "~finished"},
		collapsed = 1,
	},

	--the settings cog beside the close X, and the panel it opens.
	{
		selectors = {"rollSettingsCog"},
		bgcolor = "@fgMuted",
	},
	{
		selectors = {"rollSettingsCog", "hover"},
		bgcolor = "@fgStrong",
	},
	{
		selectors = {"rollSettingsCog", "open"},
		bgcolor = "@accent",
	},
	{
		selectors = {"rollSettingsPanel"},
		width = "100%-12",
		height = "auto",
		flow = "vertical",
		bgimage = true,
		bgcolor = "@bgAlt",
		borderWidth = 1,
		borderColor = "@border",
		cornerRadius = 6,
		pad = 6,
		tmargin = 6,
	},

	--below the title while the roll is not visible to everyone.
	{
		selectors = {"hiddenRollBanner"},
		width = "100%-12",
		height = "auto",
		hpad = 6,
		vpad = 3,
		tmargin = 4,
		bgimage = true,
		bgcolor = "#5a3a0aff",
		borderWidth = 1,
		borderColor = "#c8963cff",
		cornerRadius = 4,
		fontSize = 13,
		bold = true,
		color = "#ffe2a8ff",
		textAlignment = "center",
		textWrap = true,
	},

	{
		priority = 100,
		selectors = {"collapsed-anim"},
		collapsed = 1,
	},
	{
		selectors = {"checkbox"},
		height = 24,
		width = "auto",
	},
	{
		selectors = {"checkbox-label"},
		fontSize = 16,
	},
}

local function CardStyles()
	return ThemeEngine.MergeTokens(g_cardStyles)
end

-----------------------------------------------------------------------
--Shared helpers for the local card and the read-only remote copy.

--A pill: a small bordered toggle. args: text, value, classes, readOnly, data, change, linger.
--element.value reads/writes it (assignment does not fire change), like gui.Check.
local function CreatePill(args)
	local m_value = args.value == true

	local classes = {"pill"}
	for _,c in ipairs(args.classes or {}) do
		classes[#classes+1] = c
	end
	if args.readOnly then
		classes[#classes+1] = "readOnly"
	end

	local label = gui.Label{
		classes = {"pillLabel"},
		text = args.text or "",
		interactable = false,
	}

	local data = args.data or {}
	data.text = args.text
	data.SetText = function(text)
		data.text = text
		label.text = text
	end

	local params = {
		classes = classes,
		data = data,
		interactable = not args.readOnly,
		label,

		GetValue = function(element)
			return m_value
		end,

		SetValue = function(element, val, firechange)
			val = val == true
			local changed = (val ~= m_value)
			m_value = val
			element:SetClassTree("selected", val)
			if changed and firechange == true then
				element:FireEvent("change")
			end
		end,

		change = args.change,
		linger = args.linger,
		prepare = args.prepare,
	}

	if args.press ~= nil then
		params.press = args.press
	elseif not args.readOnly then
		params.press = function(element)
			element.SetValue(element, not m_value, true)
		end
	end

	for _,child in ipairs(args.children or {}) do
		params[#params+1] = child
	end

	local result = gui.Panel(params)
	result:SetClassTree("selected", m_value)
	return result
end

--The outcome a finished roll reached (e.g. Hit / Miss / Success), or nil.
local function RollOutcome(rollInfo)
	local ok, outcome = pcall(function()
		local props = rollInfo.properties
		if props == nil then
			return nil
		end
		return props:GetOutcome(rollInfo)
	end)
	if not ok or type(outcome) ~= "table" then
		return nil
	end
	if type(outcome.outcome) ~= "string" or outcome.outcome == "" then
		return nil
	end
	return {
		text = outcome.outcome,
		color = outcome.color,
	}
end

--Each landed die as plain data, so it can ride in the shared document.
local function CollectDice(rollInfo)
	local result = {}
	pcall(function()
		for _,roll in ipairs(rollInfo.rolls or {}) do
			result[#result+1] = {
				faces = roll.numFaces,
				result = roll.result,
				dropped = roll.dropped == true,
			}
		end
	end)
	return result
end

--Natural 20 / natural 1 on a d20 roll: "nat20", "nat1" or nil.
local function NaturalResult(rollInfo, rollType)
	if not g_d20RollTypes[rollType or ""] then
		return nil
	end
	local result = nil
	pcall(function()
		if rollInfo.nat20 then
			result = "nat20"
		elseif rollInfo.nat1 then
			result = "nat1"
		end
	end)
	return result
end

--The result block: total (live while the dice roll), outcome, natural 20/1, and the dice.
--Events: beginDice(rollInfo) subscribes to a roll's dice; showResult(result) shows a
--finished roll, result = {total, outcome = {text,color}, natural, dice = CollectDice()};
--clearResult resets it.
local function CreateResultDisplay()
	local totalLabel
	totalLabel = gui.Label{
		classes = {"rollTotal"},
		text = "",
		data = {
			faces = {},
			dropped = {},
			mod = 0,
		},

		beginDice = function(element, rollInfo)
			local d = element.data
			d.faces = {}
			d.dropped = {}
			local mod = tonumber(rollInfo.total) or 0
			local count = 0
			for _,roll in ipairs(rollInfo.rolls or {}) do
				count = count + 1
				if roll.dropped then
					d.dropped[roll.guid] = true
				else
					mod = mod - (tonumber(roll.result) or 0)
				end
				local events = chat.DiceEvents(roll.guid)
				if events ~= nil then
					events:Listen(element)
				end
			end
			d.mod = mod
			if count == 0 then
				element.text = tostring(rollInfo.total or "")
			else
				element.text = ""
			end
		end,

		diceface = function(element, diceguid, num, timeRemaining)
			local d = element.data
			d.faces[diceguid] = num
			local total = d.mod
			for guid,value in pairs(d.faces) do
				if not d.dropped[guid] then
					total = total + value
				end
			end
			element.text = tostring(total)
		end,

		showResult = function(element, result)
			element.text = tostring(result.total or "")
		end,

		clearResult = function(element)
			element.data.faces = {}
			element.data.dropped = {}
			element.text = ""
		end,
	}

	local outcomeLabel = gui.Label{
		classes = {"rollOutcome", "collapsed"},
		text = "",
		showResult = function(element, result)
			local parts = {}
			local color = nil
			if result.outcome ~= nil and result.outcome.text ~= nil then
				parts[#parts+1] = result.outcome.text
				color = result.outcome.color
			end
			if result.natural == "nat20" then
				parts[#parts+1] = "Natural 20!"
				color = color or "#88ff88"
			elseif result.natural == "nat1" then
				parts[#parts+1] = "Natural 1"
				color = color or "#ff8888"
			end
			element.text = table.concat(parts, " - ")
			element.selfStyle.color = color or "white"
			element:SetClass("collapsed", #parts == 0)
		end,
		clearResult = function(element)
			element.text = ""
			element:SetClass("collapsed", true)
		end,
	}

	local diceRow = gui.Panel{
		classes = {"pillRow", "collapsed"},
		showResult = function(element, result)
			local children = {}
			for _,die in ipairs(result.dice or {}) do
				local text = string.format("d%s: %s", tostring(die.faces or "?"), tostring(die.result or "?"))
				if die.dropped then
					text = string.format("<s>%s</s>", text)
				end
				children[#children+1] = gui.Panel{
					classes = {"diceChip"},
					gui.Label{
						classes = {"diceChipLabel", cond(die.dropped, "dropped")},
						text = text,
					},
				}
			end
			element.children = children
			element:SetClass("collapsed", #children == 0)
		end,
		clearResult = function(element)
			element.children = {}
			element:SetClass("collapsed", true)
		end,
	}

	return gui.Panel{
		classes = {"shownWhenRolling"},
		width = "100%",
		height = "auto",
		flow = "vertical",
		vmargin = 4,
		totalLabel,
		outcomeLabel,
		diceRow,
	}
end

--The ability card drawn above a roll, in a scroll box so a long spell does not push the
--roll off screen. Returns nil if the ability has no card.
local function CreateAbilityCardPanel(ability, token)
	if ability == nil then
		return nil
	end

	--The tooltip's width excludes its 24px pad on each side; size it so the whole
	--card, pad included, is CARD_WIDTH and nothing is clipped by the scroll box.
	local ok, tooltip = pcall(function()
		return CreateAbilityTooltip(ability, {width = CARD_WIDTH - 48, token = token})
	end)
	if not ok or tooltip == nil then
		return nil
	end

	tooltip.selfStyle.halign = "center"
	tooltip.selfStyle.valign = "top"
	tooltip:MakeNonInteractiveRecursive()

	--A scroll box stretches its direct child to its own width, which would
	--override the tooltip's width, so the tooltip sits in a plain inner panel.
	return gui.Panel{
		width = CARD_WIDTH,
		height = "auto",
		maxHeight = 380,
		vscroll = true,
		flow = "vertical",
		bmargin = 2,
		gui.Panel{
			width = "100%",
			height = "auto",
			flow = "vertical",
			tooltip,
		},
	}
end

--Which ability a card shows: the same ability cast by the same token keeps its card.
local function AbilityKey(ability, token)
	if ability == nil then
		return nil
	end
	local guid = nil
	local name = nil
	pcall(function() guid = ability:try_get("guid") end)
	pcall(function() name = ability.name end)
	local charid = nil
	if token ~= nil and token.valid then
		charid = token.charid
	end
	return string.format("%s|%s|%s", tostring(charid), tostring(guid), tostring(name))
end

-----------------------------------------------------------------------
--Roll sharing: one shared document, written only by the client whose roll is on screen.
--Fields: userid, casterTokenId, ability (a copy, function fields stripped), heartbeat, and
--roll = {rollId, state ("preparing" | "rolling" | "finished"), title, explanation,
--rollText, rollType, advantage, modifiers = {{name, enabled}}, result}.

local g_shareDocId = "d20RollShare"

local g_share = nil
local g_writeScheduled = false
local g_heartbeatRunning = false

--True while this client's own roll card is up; the remote copy hides meanwhile.
local g_localCardVisible = false

--Refreshes the remote copy now (set by InitAbilityDisplayPanel).
local g_refreshRemote = nil

local function ShareDoc()
	return mod:GetDocumentSnapshot(g_shareDocId)
end

local function WriteShareNow()
	local doc = ShareDoc()
	doc:BeginChange()
	for k in pairs(doc.data) do
		doc.data[k] = nil
	end
	if g_share ~= nil then
		for k,v in pairs(g_share) do
			doc.data[k] = v
		end
		doc.data.heartbeat = ServerTimestamp()
	end
	doc:CompleteChange(cond(g_share ~= nil, "Share roll", "Clear roll share"), {undoable = false})
end

--Coalesce rapid changes (CalculateRollText runs many times while a dialog prepares).
local function ScheduleShareWrite()
	if g_writeScheduled then
		return
	end
	g_writeScheduled = true
	dmhub.Schedule(0.1, function()
		g_writeScheduled = false
		if mod.unloaded or g_share == nil then
			return
		end
		WriteShareNow()
	end)
end

local function Heartbeat()
	if mod.unloaded or g_share == nil then
		g_heartbeatRunning = false
		return
	end

	local doc = ShareDoc()
	doc:BeginChange()
	doc.data.heartbeat = ServerTimestamp()
	doc:CompleteChange("Heartbeat roll share", {undoable = false})

	dmhub.Schedule(3, Heartbeat)
end

--Whether the token holds the current initiative turn.
local function IsTokenOnCurrentTurn(token)
	local q = dmhub.initiativeQueue
	if q == nil then
		return false
	end

	--d20's InitiativeQueue (DMHub Game Rules/InitiativeQueue.lua); its fields are
	--strict, so a missing one raises rather than reading nil.
	local ok, currentId = pcall(function()
		if q.hidden then
			return nil
		end
		return q:CurrentInitiativeId()
	end)
	if not ok or type(currentId) ~= "string" then
		return false
	end

	if not GameHud.instance or not GameHud.instance:has_key("initiativeInterface") then
		return false
	end

	local tokens = GameHud.instance:GetTokensForInitiativeId(GameHud.instance.initiativeInterface, currentId) or {}
	for _,tok in ipairs(tokens) do
		if tok ~= nil and tok.charid == token.charid then
			return true
		end
	end

	return false
end

--The Codex's rule: share while the roller's token is on the current turn and the roll is
--visible to everyone.
local function ShouldShareRoll(token, visibility)
	if token == nil or not token.valid then
		return false
	end
	if not token.canControl then
		return false
	end
	if RollPrivacyAllowed() and visibility ~= "visible" then
		return false
	end
	return IsTokenOnCurrentTurn(token)
end

--A copy of the ability safe to put in a document: function-valued fields would serialize
--as null and the echo would strip them from the live object.
local function ShareableAbility(ability)
	if ability == nil then
		return nil
	end
	local ok, copy = pcall(DeepCopy, ability)
	if not ok or type(copy) ~= "table" then
		return nil
	end
	for field,value in pairs(copy) do
		if type(value) == "function" then
			copy[field] = nil
		end
	end
	return copy
end

local function BeginShare(token, ability, rollState)
	g_share = {
		userid = dmhub.loginUserid,
		casterTokenId = token.charid,
		ability = ShareableAbility(ability),
		roll = rollState,
	}
	ScheduleShareWrite()

	if not g_heartbeatRunning then
		g_heartbeatRunning = true
		dmhub.Schedule(3, Heartbeat)
	end
end

local function UpdateShare(rollState)
	if g_share == nil then
		return
	end
	g_share.roll = rollState
	ScheduleShareWrite()
end

local function EndShare()
	if g_share == nil then
		return
	end
	g_share = nil
	WriteShareNow()
end

-----------------------------------------------------------------------
--The read-only copy of someone else's roll card.

local function CreateRemoteRollCard(data)
	local casterToken = nil
	if data.casterTokenId ~= nil then
		casterToken = dmhub.GetTokenById(data.casterTokenId)
	end

	local headerChildren = {}
	if casterToken ~= nil and casterToken.valid then
		headerChildren[#headerChildren+1] = gui.CreateTokenImage(casterToken, {
			width = 28,
			height = 28,
		})
	end

	local casterName = "A creature"
	if casterToken ~= nil and casterToken.valid then
		casterName = casterToken.description or casterToken.name or casterName
	end

	headerChildren[#headerChildren+1] = gui.Label{
		classes = {"rollSubtitle"},
		width = "auto",
		valign = "center",
		lmargin = 6,
		text = string.format("%s is rolling", casterName),
	}

	--It floats over the map, so it gets the card's dark backdrop to stay readable.
	local header = gui.Panel{
		flow = "horizontal",
		width = "auto",
		height = "auto",
		halign = "center",
		bmargin = 4,
		hpad = 10,
		vpad = 4,
		bgimage = "panels/square.png",
		bgcolor = "#000000f6",
		cornerRadius = 8,
		children = headerChildren,
	}

	local abilityPanel = nil
	if data.ability ~= nil then
		abilityPanel = CreateAbilityCardPanel(data.ability, casterToken)
	end

	local titleLabel = gui.Label{
		classes = {"rollTitle"},
		width = "100%",
		shareUpdate = function(element, roll)
			element.text = roll.title or "Roll Dice"
		end,
	}

	local explanationLabel = gui.Label{
		classes = {"explanation"},
		shareUpdate = function(element, roll)
			element.text = roll.explanation or ""
			element:SetClass("collapsed", (roll.explanation or "") == "")
		end,
	}

	local advantageNames = {"Disadvantage", "Normal", "Advantage"}
	local advantageIds = {"disadvantage", "normal", "advantage"}
	local advantagePills = {}
	for i,name in ipairs(advantageNames) do
		advantagePills[#advantagePills+1] = CreatePill{
			text = name,
			readOnly = true,
			classes = {advantageIds[i]},
		}
	end

	local advantageRow = gui.Panel{
		classes = {"pillRow", "centered"},
		children = advantagePills,
		shareUpdate = function(element, roll)
			element:SetClass("collapsed", roll.advantage == nil)
			for i,pill in ipairs(advantagePills) do
				pill.value = (roll.advantage == advantageIds[i])
			end
		end,
	}

	local modifiersRow = gui.Panel{
		classes = {"pillRow"},
		shareUpdate = function(element, roll)
			local children = {}
			for _,m in ipairs(roll.modifiers or {}) do
				children[#children+1] = CreatePill{
					text = m.name or "",
					value = m.enabled,
					readOnly = true,
				}
			end
			element.children = children
			element:SetClass("collapsed", #children == 0)
		end,
	}

	local rollTextLabel = gui.Label{
		classes = {"rollText"},
		shareUpdate = function(element, roll)
			element.text = roll.rollText or ""
		end,
	}

	local statusLabel = gui.Label{
		classes = {"rollSubtitle"},
		width = "auto",
		halign = "center",
		shareUpdate = function(element, roll)
			if roll.state == "preparing" then
				element.text = "Preparing the roll..."
			elseif roll.state == "rolling" then
				element.text = "Rolling..."
			else
				element.text = ""
			end
			element:SetClass("collapsed", element.text == "")
		end,
	}

	local resultDisplay = CreateResultDisplay()

	--Follows the roll's dice as they land, once its chat message arrives.
	local m_rollId = nil
	local m_subscribed = false
	local m_finishedShown = false

	local rollPanel = gui.Panel{
		classes = {"rollPanel"},
		advantageRow,
		modifiersRow,
		rollTextLabel,
		statusLabel,
		resultDisplay,

		thinkTime = 0.2,
		think = function(element)
			if m_rollId == nil or m_subscribed or m_finishedShown then
				return
			end
			for _,msg in ipairs(chat.messages) do
				if msg.key == m_rollId then
					local numRolls = 0
					pcall(function()
						for _ in ipairs(msg.rolls or {}) do
							numRolls = numRolls + 1
						end
					end)
					if numRolls > 0 then
						m_subscribed = true
						resultDisplay:FireEventTree("beginDice", msg)
					end
					break
				end
			end
		end,

		shareUpdate = function(element, roll)
			if roll.rollId ~= m_rollId then
				m_rollId = roll.rollId
				m_subscribed = false
				m_finishedShown = false
				resultDisplay:FireEventTree("clearResult")
			end

			local frame = element.parent
			if frame ~= nil then
				frame:SetClassTree("rolling", roll.state == "rolling")
				frame:SetClassTree("finished", roll.state == "finished")
			end

			if roll.state == "finished" and roll.result ~= nil and not m_finishedShown then
				m_finishedShown = true
				resultDisplay:FireEventTree("showResult", roll.result)
			end
		end,
	}

	local frame = gui.Panel{
		classes = {"rollFrame"},
		titleLabel,
		explanationLabel,
		rollPanel,
	}

	local children = {header}
	if abilityPanel ~= nil then
		children[#children+1] = abilityPanel
	end
	children[#children+1] = frame

	local result = gui.Panel{
		styles = CardStyles(),
		width = CARD_WIDTH,
		height = "auto",
		halign = "right",
		valign = "center",
		flow = "vertical",
		interactable = false,
		children = children,
	}

	if data.roll ~= nil then
		result:FireEventTree("shareUpdate", data.roll)
	end

	return result
end

--Replaces the HUD's (Codex-only) ability display: here it shows the read-only copy of
--another client's roll.
function GameHud:InitAbilityDisplayPanel(abilityDisplayPanel)
	local m_key = nil
	local m_card = nil

	local remotePanel
	local function Refresh()
		if remotePanel == nil or not remotePanel.valid then
			return
		end

		local data = ShareDoc().data
		local roll = data and data.roll

		local show = roll ~= nil
			and data.userid ~= nil
			and data.userid ~= dmhub.loginUserid
			and data.heartbeat ~= nil
			and TimestampAgeInSeconds(data.heartbeat) < 10
			and not g_localCardVisible

		if not show then
			if m_card ~= nil then
				m_card = nil
				m_key = nil
				remotePanel.children = {}
			end
			return
		end

		local key = string.format("%s|%s|%s", tostring(data.userid), tostring(data.casterTokenId), tostring(roll.rollId))
		if key == m_key and m_card ~= nil and m_card.valid then
			m_card:FireEventTree("shareUpdate", roll)
			return
		end

		m_key = key
		m_card = CreateRemoteRollCard(data)
		remotePanel.children = {m_card}
	end

	remotePanel = gui.Panel{
		width = "100%",
		height = "100%",
		flow = "vertical",
		interactable = false,

		monitorGame = ShareDoc().path,
		refreshGame = function(element)
			Refresh()
		end,

		--catches heartbeat expiry and the local card coming and going.
		thinkTime = 1,
		think = function(element)
			Refresh()
		end,
	}

	g_refreshRemote = Refresh

	abilityDisplayPanel.children = {remotePanel}
end

--The HUD's standalone roll host holds the local roll card.
function GameHud:InitStandaloneRollHost(hostPanel)
	self.standaloneRollHost = hostPanel
	local dialog = rawget(self, "rollDialog")
	if dialog ~= nil and dialog.valid and dialog.data.card ~= nil then
		hostPanel.children = {dialog.data.card}
	end
end

-----------------------------------------------------------------------

function GameHud.CreateRollDialog(self)

	--the creature doing the roll
	local creature = nil

	--creature targeted by the roll.
	local targetCreature = nil

	--a table of multiple tokens targeted by this roll.
	local m_multitargets = nil

	local m_symbols = nil

	local rollType = ''
	local rollSubtype = ''
	local rollProperties = nil

	--the invisible controller panel (GameHud.instance.rollDialog) and the visible card.
	local resultPanel
	local card
	local CalculateRollText

	local rollAllPrompts = nil
	local rollActive = nil
	local beginRoll = nil
	local completeRoll = nil
	local cancelRoll = nil

	local m_shown = 0
	local m_richStatus = nil

	--true from ShowDialog until the roll is thrown or cancelled.
	local m_preparing = false

	--bumped whenever the card is shown for a new roll or hidden, so callbacks from an
	--earlier roll (the result linger) leave a newer one alone.
	local m_generation = 0

	--the dice cage panel, once it exists.
	local m_cage = nil

	--the token / ability the card is showing.
	local m_token = nil
	local m_ability = nil
	local m_abilityKey = nil

	local OnShow = function(richStatus)
		chat.events:Push()
		chat.events:Listen(resultPanel)
        if m_richStatus ~= nil then
            dmhub.PopUserRichStatus(m_richStatus)
            m_richStatus = nil
        end

        m_richStatus = dmhub.PushUserRichStatus(richStatus)

		m_shown = m_shown+1
	end

	local OnHide = function()
        if m_richStatus ~= nil then
            dmhub.PopUserRichStatus(m_richStatus)
            m_richStatus = nil
        end

		if m_shown > 0 then
			chat.events:Pop()
			m_shown = m_shown-1
		end

		if m_shown <= 0 then
			--relinquish the coroutine owning this panel.
			resultPanel.data.coroutineOwner = nil
		end
	end

	local SetCageRegistered = function(registered)
		if m_cage ~= nil and m_cage.valid then
			pcall(function() m_cage:SetAsDicePreviewPanel(registered) end)
		end
	end

	local BuildShareState

	--Puts the card away (after a cancel, a silent roll, or once a result has been seen).
	local HideCard = function()
		m_generation = m_generation + 1
		if card ~= nil and card.valid then
			card:SetClass("hidden", true)
			card:SetClassTree("rolling", false)
			card:SetClassTree("finished", false)
		end
		SetCageRegistered(false)
		g_localCardVisible = false
		EndShare()
		if g_refreshRemote ~= nil then
			g_refreshRemote()
		end
	end

	local title = gui.Label{
		id = "rollDialogTitle",
		classes = {'rollTitle'},
	}

	local explanation = gui.Label{
		classes = {'explanation'},
	}

	local ShowTargetHints

	local rollInput = gui.Input{
		classes = {'roll-input', 'collapsedWhenRolling'},
		width = "100%-36",
		height = 26,
		fontSize = 16,
		bold = true,
		halign = "left",
		valign = "center",
		events = {
			edit = function(element)
				chat.PreviewChat(string.format('/roll %s', element.text))
				ShowTargetHints(element.text)
			end,
			change = function(element)
				chat.PreviewChat(string.format('/roll %s', element.text))
			end,
		},
	}


	local autoRollCheck = gui.Check{
		text = "Auto-roll",
		value = false,
	}
	local autoHideCheck = gui.Check{
		text = "Auto-hide",
		value = false,
	}
	local autoQuickCheck = gui.Check{
		text = "Auto-quick",
		value = false,
	}

	local rollAllPromptsCheck = gui.Check{
		classes = {"collapsedWhenRolling"},
		text = "Roll all prompts",
		value = true,
	}

	local autoRollId = nil

	local autoRollPanel = gui.Panel{
		width = "100%",
		height = "auto",
		flow = "vertical",
		autoHideCheck,
		autoQuickCheck,
		autoRollCheck,
	}

	local prerollCheck = gui.Check{
		text = "Pre-roll dice",
		value = dmhub.GetSettingValue("preroll"),
		change = function(element)
			dmhub.SetSettingValue("preroll", element.value)
			CalculateRollText()
		end,
		textCalculated = function(element)
			element:SetClass("collapsed", (not dmhub.isDM))
		end,
	}

	local updateRollVisibility
	local UpdateHiddenBanner
	local hideRollDropdown = gui.Dropdown{
		width = "100%",
		height = 28,
		fontSize = 16,
		idChosen = dmhub.GetSettingValue("privaterolls"),
		options = cond(dmhub.isDM, g_rollOptionsDM, g_rollOptionsPlayer),
		prepare = function(element)
			element.idChosen = dmhub.GetSettingValue("privaterolls")
		end,

		change = function(element)
			updateRollVisibility:FireEvent("prepare")
			UpdateHiddenBanner()

			--stop sharing at once if the roll became private; start it if it went public.
			if element.idChosen ~= "visible" and RollPrivacyAllowed() then
				EndShare()
			elseif g_share == nil and m_preparing and ShouldShareRoll(m_token, element.idChosen) then
				BeginShare(m_token, m_ability, BuildShareState("preparing"))
			end
		end,
	}

	updateRollVisibility = gui.Check{
		text = "Use for all rolls",
		value = dmhub.GetSettingValue("privaterolls:save"),
		prepare = function(element)
			updateRollVisibility:SetClass("collapsed", hideRollDropdown.idChosen == dmhub.GetSettingValue("privaterolls"))
		end,
	}

	local m_options

	--a selectors which allows alternate roll options to be selected, e.g. choosing between an Athletics and Acrobatics check.
	local alternateRollsBar


	--targets we record damage or other things about.
	local targetHints = nil

	ShowTargetHints = function(rollText)
		for i,hint in ipairs(targetHints or {}) do
			local str = rollText

			if m_multitargets ~= nil and m_multitargets[i] ~= nil then
				local boons = m_multitargets[i].boons
				if boons ~= nil and boons > 0 then
					str = string.format("%s + %dd4", str, boons)
				elseif boons ~= nil and boons < 0 then
					str = string.format("%s - %dd4", str, -boons)
				end
			end

			if hint.half then
				str = str .. " HALF"
			end

			creature.UploadExpectedCreatureDamage(hint.charid, resultPanel.data.rollid, str)
		end
	end

	local RemoveTargetHints = function()
		for _,hint in ipairs(targetHints or {}) do
			creature.UploadExpectedCreatureDamage(hint.charid, resultPanel.data.rollid, nil)
		end
	end

	local rollDisabledLabel
	local rollDiceButton

	local modifierChecks = {}
	local modifierDropdowns = {}
	local criticalHit
	local inspirationCheck
	local advantageBar
	local advantageElements = {}
	local advantageOptions = {'Disadvantage', 'Normal', 'Advantage'}
	local advantageIds = {'disadvantage', 'normal', 'advantage'}
	local advantageState = 2
	local advantageStateLocked = false

	local m_boons = 0

	local boonBar

	local activeModifiers = {}

	local SetAdvantageState

	local m_customContainer
	local m_tableContainer

	--The roll as the shared document carries it.
	BuildShareState = function(state, result)
		local modifiers = {}
		for _,element in ipairs(modifierChecks) do
			if element.valid and not element:HasClass("collapsed-anim") then
				modifiers[#modifiers+1] = {
					name = element.data.text or "",
					enabled = element.value == true,
				}
			end
		end

		for _,dropdown in ipairs(modifierDropdowns) do
			if dropdown.valid then
				for _,option in ipairs(dropdown.data.mod.modifierOptions or {}) do
					if option.id == dropdown.idChosen and option.text ~= nil then
						modifiers[#modifiers+1] = {
							name = string.format("%s: %s", dropdown.data.mod.text or "", option.text),
							enabled = true,
						}
					end
				end
			end
		end

		if criticalHit ~= nil and criticalHit.valid and not criticalHit:HasClass("collapsed-anim") then
			modifiers[#modifiers+1] = {
				name = "Critical Hit",
				enabled = criticalHit.value == true,
			}
		end

		if inspirationCheck ~= nil and inspirationCheck.valid and not inspirationCheck:HasClass("collapsed-anim") and inspirationCheck.value then
			modifiers[#modifiers+1] = {
				name = "Inspiration",
				enabled = true,
			}
		end

		local advantage = nil
		if advantageBar ~= nil and advantageBar.valid and not advantageBar:HasClass("collapsed-anim") then
			advantage = advantageIds[advantageState]
		end

		return {
			rollId = resultPanel.data.rollid,
			state = state,
			title = title.text,
			explanation = explanation.text,
			rollText = rollInput.text,
			rollType = rollType or "",
			advantage = advantage,
			modifiers = modifiers,
			result = result,
		}
	end


	--this is the current 'base roll' that is being calculated based on.
	local baseRoll = '1d6'
	CalculateRollText = function()
		activeModifiers = {}

		local rollDisallowed = nil

		local roll = baseRoll

		if rollProperties ~= nil then
			rollProperties:ResetMods()
			for i,element in ipairs(modifierChecks) do
				if element.value then
					element.data.mod.modifier:ModifyRollProperties(element.data.mod.context, creature, rollProperties)
				end
			end

			if not m_customContainer:HasClass("collapsed") then
				m_customContainer:FireEventTree("refreshMods")
			end

			if not m_tableContainer:HasClass("collapsed") then
				m_tableContainer:FireEventTree("refreshMods")
			end
		end

		if GameSystem.UseBoons then
			roll = GameSystem.ApplyBoons(roll, m_boons)
		end

		local isd20roll = rollType == 'd20' or rollType == 'check'

		--do modifiers on the raw goblin script here.
		if creature and isd20roll then
			for i,element in ipairs(modifierChecks) do
				if element.data.mod.modFromTarget then
					--pass
				elseif element.value then
					roll = element.data.mod.modifier:ModifyD20RollEarly(element.data.mod.context, creature, rollSubtype, roll)
				end
			end
		end


		if creature then
			local syms = {
				target = GenerateSymbols(targetCreature)
			}

			if m_symbols ~= nil then
				for k,v in pairs(m_symbols) do
					syms[k] = v
				end
			end
			roll = dmhub.NormalizeRoll(roll, creature:LookupSymbol(syms), "Calculate roll")
		end

		local afterCritMods = {}

		if creature then
			for i,element in ipairs(modifierChecks) do
				local show = true
				if rollType == 'damage' then
					show = (not element.data.mod.modifier:CriticalHitsOnly()) or criticalHit.value
					element:SetClass('collapsed-anim', not show)
				end

				if show and element.value then
					--call this generic function which might be modified by mods.
					roll = element.data.mod.modifier:ApplyToRoll(element.data.mod.context, creature, targetCreature, rollType, roll)

					if rollType == 'damage' then
						if element.data.mod.modFromTarget then
							roll = element.data.mod.modifier:ModifyDamageAgainstUs(element.data.mod.context, targetCreature, creature, roll)

						elseif element.data.mod.modifier:CriticalHitsOnly() then
							afterCritMods[#afterCritMods+1] = element.data.mod
						else
							roll = element.data.mod.modifier:ModifyDamageRoll(element.data.mod, creature, targetCreature, roll)
						end
					end

					if isd20roll then
						if element.data.mod.modFromTarget then
							roll = element.data.mod.modifier:ModifyAttackAgainstUs(element.data.mod.context, targetCreature, creature, roll)
						else
							roll = element.data.mod.modifier:ModifyD20Roll(element.data.mod.context, creature, rollSubtype, roll)
						end
					end
					activeModifiers[#activeModifiers+1] = element.data.mod.modifier
				end
			end

			for i,dropdown in ipairs(modifierDropdowns) do
				for j,option in ipairs(dropdown.data.mod.modifierOptions) do
					if option.id == dropdown.idChosen and option.mod ~= nil then
						if rollType == 'damage' then
							roll = option.mod:ModifyDamageRoll(option, creature, targetCreature, roll)
						end

						if isd20roll then
							roll = option.mod:ModifyD20Roll(option.context, creature, rollSubtype, roll)
						end
						activeModifiers[#activeModifiers+1] = option.mod

						if option.disableRoll then
							rollDisallowed = option.disableRoll
						end
					end
				end
			end
		end

		if rollDisallowed ~= nil then
			rollDisabledLabel:SetClass("collapsed-anim", false)
			rollDisabledLabel.text = rollDisallowed
		else
			rollDisabledLabel:SetClass("collapsed-anim", true)
		end

		rollDiceButton:SetClass("hidden", rollDisallowed ~= nil)


		if inspirationCheck.value then
			roll = roll .. " advantage"
		end

		if advantageStateLocked then
			if advantageOptions[advantageState] == 'Advantage' then
				roll = dmhub.ForceRollAdvantage(roll, 'advantage')
			elseif advantageOptions[advantageState] == 'Disadvantage' then
				roll = dmhub.ForceRollAdvantage(roll, 'disadvantage')
			else
				roll = dmhub.ForceRollAdvantage(roll, 'normal')
			end
		else
			local adv = dmhub.GetRollAdvantage(roll)
			if adv == "disadvantage" then
				SetAdvantageState(1)
			elseif adv == "advantage" then
				SetAdvantageState(3)
			else
				SetAdvantageState(2)
			end
		end

		local rollInfo = dmhub.ParseRoll(roll, creature)

		local newText = dmhub.RollToString(rollInfo)

		if #afterCritMods > 0 then
			for i,mod in ipairs(afterCritMods) do
				newText = mod.modifier:ModifyDamageRoll(mod, creature, targetCreature, newText)
			end

			rollInfo = dmhub.ParseRoll(newText, creature)
			newText = dmhub.RollToString(rollInfo)
		end

		if m_multitargets ~= nil then
			local extraboons = 0
			local extrabanes = 0
			for i,target in ipairs(m_multitargets) do
				if target.boons > 0 then
					extraboons = math.max(extraboons, target.boons)
				else
					extrabanes = math.max(extrabanes, -target.boons)
				end
			end

			if extraboons > 0 then
				newText = string.format("%s %dd4 [extraboons]", newText, extraboons)
			end

			if extrabanes > 0 then
				newText = string.format("%s -%dd4 [extrabanes]", newText, extrabanes)
			end
		end

		if dmhub.isDM and dmhub.GetSettingValue("preroll") then
			local cats = dmhub.RollInstantCategorized(newText)
			newText = ""
			for k,n in pairs(cats) do
				newText = string.format("%s%s%s [%s]", newText, cond(newText == "", "", " "), n, k)
			end

			newText = dmhub.RollToString(dmhub.ParseRoll(newText, creature))
		end

		if GameSystem.CombineNegativesForRolls then
			newText = dmhub.NormalizeRoll(newText, nil, nil, {"NormalizeNegatives"})
		end

		if newText ~= rollInput.text then
			rollInput.text = newText
		else
			rollInput:FireEvent('change')
		end

		ShowTargetHints(newText)

		card:FireEventTree("textCalculated")

		if m_preparing then
			UpdateShare(BuildShareState("preparing"))
		end
	end

	local rerollFudgedButton = gui.IconButton{
		icon = "panels/hud/clockwise-rotation.png",
		halign = "right",
		valign = "center",
		style = {
			width = 24,
			height = 24,
		},
		click = function(element)
			CalculateRollText()
		end,
		textCalculated = function(element)
			element:SetClass("hidden", (not dmhub.isDM) or (not dmhub.GetSettingValue("preroll")))
		end,
	}

	local rollInputContainer = gui.Panel{
		classes = {"collapsedWhenRolling"},
		flow = "horizontal",
		width = '100%',
		halign = 'center',
		height = 28,
		vmargin = 2,
		rollInput,
		rerollFudgedButton,
	}

	local tableStyles = {
		Styles.Table,
		gui.Style{
			selectors = {"label"},
			pad = 4,
			fontSize = 16,
			width = "auto",
			height = "auto",
			color = Styles.textColor,
			valign = "center",
		},
		gui.Style{
			selectors = {"row"},
			width = "auto",
			height = "auto",
			bgimage = "panels/square.png",
			borderColor = Styles.textColor,
			borderWidth = 1,
		},
		gui.Style{
			selectors = {"row", "oddRow"},
			bgcolor = "#222222ff",
		},
		gui.Style{
			selectors = {"row", "evenRow"},
			bgcolor = "#444444ff",
		},
	}

	m_customContainer = gui.Panel{
		width = "100%",
		height = "auto",
		halign = "center",
		flow = "vertical",
		styles = tableStyles,
	}

	m_tableContainer = gui.Table{
		width = "100%",
		height = "auto",
		halign = "center",
		flow = "vertical",
		styles = tableStyles,
	}

	local multitokenContainer = gui.Panel{
		classes = {"collapsedWhenRolling"},
		width = "100%",
		height = "auto",
		halign = "center",
		flow = "horizontal",
		wrap = true,
		prepare = function(element, options)
			if m_multitargets == nil or #m_multitargets <= 1 then
				element:SetClass("collapsed", true)
				return
			end

			element:SetClass("collapsed", false)

			local children = {}

			for i,target in ipairs(m_multitargets) do
				local boonLabel = gui.Label{
					fontSize = 12,
					color = cond(target.text == nil, Styles.textColor, "#9999ffff"),
					width = "auto",
					height = 16,
					halign = "center",
					valign = "top",
					prepare = function(element)
						if target.boons == 0 then
							element.text = "--"
						elseif target.boons == 1 then
							element.text = "1 Boon"
						elseif target.boons == -1 then
							element.text = "1 Bane"
						elseif target.boons > 0 then
							element.text = string.format("%d Boons", target.boons)
						else
							element.text = string.format("%d Banes", -target.boons)
						end
					end,

					hover = function(element)
						if target.text ~= nil then
							gui.Tooltip(target.text)(element)
						end
					end,
				}

				local tokenPanel = gui.Panel{
					width = 80,
					height = 80,
					flow = "vertical",

					gui.CreateTokenImage(target.token, {
						halign = "center",
						valign = "top",
						width = 48,
						height = 48,

					}),

					boonLabel,

					gui.Panel{
						flow = "horizontal",
						width = 80,
						height = 16,

						gui.Button{
							borderWidth = 1,
							hmargin = 0,
							vmargin = 0,
							width = 34,
							height = 14,
							halign = "center",
							fontSize = 10,
							text = "+Boon",
							click = function(element)
								target.boons = target.boons + 1
								boonLabel:FireEvent("prepare")
								CalculateRollText()
							end,
						},

						gui.Button{
							borderWidth = 1,
							hmargin = 0,
							vmargin = 0,
							width = 34,
							height = 14,
							halign = "center",
							fontSize = 10,
							text = "+Bane",
							click = function(element)
								target.boons = target.boons - 1
								boonLabel:FireEvent("prepare")
								CalculateRollText()
							end,
						},
					}
				}

				children[#children+1] = tokenPanel
			end

			element.children = children
		end,
	}

	criticalHit = CreatePill{
		text = 'Critical Hit',
		classes = {"advantage"},
		change = function(element)
			CalculateRollText()
		end,
		prepare = function(element, options)
			element:SetClass('collapsed-anim', options.type ~= 'damage' or options.critical == nil or GameSystem.CriticalHitsModifyDamage == false)
			element.SetValue(element, options.critical == true, false)
		end,
	}

	inspirationCheck = CreatePill{
		text = "Use Inspiration",
		classes = {"advantage"},
		change = function(element)
			CalculateRollText()
		end,
		prepare = function(element, options)
			element:SetClass('collapsed-anim', options.type ~= 'd20' or creature == nil or not creature:HasInspiration())
			element.SetValue(element, false)
		end,
	}

	SetAdvantageState = function(n, locked)
		advantageStateLocked = locked
		advantageState = n
		for i,element in ipairs(advantageElements) do
			element.value = (i == n)
			element:SetClassTree('locked', i == n and locked)
		end
	end

	for i,option in ipairs(advantageOptions) do
		local nIndex = i
		advantageElements[#advantageElements+1] = CreatePill{
			text = option,
			classes = {advantageIds[i]},
			linger = gui.Tooltip("Click to force this choice. Click again to go back to the rules' choice."),
			children = {
				gui.Panel{
					classes = {'pillLock'},
					bgimage = 'game-icons/padlock.png',
					interactable = false,
				},
			},
			--advantage pills are a radio group, not toggles.
			press = function(element)
				SetAdvantageState(nIndex, cond(advantageStateLocked and advantageState == nIndex, false, true))
				CalculateRollText()
			end,
		}
	end

	alternateRollsBar = gui.Panel{
		classes = {'pillRow', 'collapsedWhenRolling'},
		prepare = function(element, options)
			if options.alternateOptions == nil or #options.alternateOptions <= 1 then
				element:SetClass("collapsed-anim", true)
				return
			end

			local chooseAlternate = options.chooseAlternate
			local children = {}
			for optionIndex,alternate in ipairs(options.alternateOptions) do
				children[#children+1] = CreatePill{
					text = alternate.text,
					value = options.alternateChosen == optionIndex,
					press = function(element)
						chooseAlternate(optionIndex)
					end,
				}
			end

			element.children = children
			element:SetClass("collapsed-anim", false)
		end,
	}

	if GameSystem.UseBoons then
		boonBar = gui.Panel{
			classes = {"collapsedWhenRolling"},
			width = "100%",
			height = "auto",
			halign = "center",
			valign = "top",
			flow = "horizontal",

			prepare = function(element, options)
				element:SetClass("collapsed", not GameSystem.AllowBoonsForRoll(options))
				m_boons = 0
			end,

			gui.Button{
				width = 120,
				height = 28,
				text = "+ Edge",
				halign = "left",
				click = function(element)
					if m_boons < 2 then
						m_boons = m_boons + 1
						CalculateRollText()
					end
				end,
			},

			gui.Button{
				width = 120,
				height = 28,
				text = "+ Bane",
				halign = "right",
				click = function(element)
					if m_boons > -2 then
						m_boons = m_boons - 1
						CalculateRollText()
					end
				end,
			},
		}
	end

	advantageBar = gui.Panel{
		classes = {'pillRow', 'centered', 'collapsedWhenRolling'},
		children = advantageElements,
		prepare = function(element, options)
			element:SetClass('collapsed-anim', options.type ~= 'd20' and options.type ~= 'save' and options.type ~= 'check')
			SetAdvantageState(2)
		end,
	}

	local modifiersPanel = gui.Panel{
		classes = {'pillRow', 'collapsedWhenRolling'},
		criticalHit,
		events = {
			prepare = function(element, options)


				modifierChecks = {}
				modifierDropdowns = {}
				if creature == nil or options.modifiers == nil then
					element.children = {criticalHit}
					element:SetClass('collapsed-anim', true)
					return
				end

				element:SetClass('collapsed-anim', false)

				local addedCritical = false

				local children = {}

				for i,mod in ipairs(options.modifiers) do
					if mod.modifier then
						local ischecked = false
						local force = mod.modifier:try_get("force", false)
						if force then
							ischecked = true
						elseif mod.hint ~= nil then
							ischecked = mod.hint.result
						end

						local check --pill that will come out of this.

						local tooltip = mod.modifier:GetSummaryText()
						for i,justification in ipairs(mod.hint.justification) do
							tooltip = string.format("%s\n<color=%s>%s", tooltip, cond(ischecked, '#aaffaa', '#ffaaaa'), justification)
						end

						local text = mod.modifier.name
						if mod.modFromTarget then
							text = string.format("Target is %s", text)
						end

						local upcastPanels = nil
						local upcastCells = nil

						--is the resource for this modifier an upcastable resource (spell slot) and we should let them select
						--which slot to use from a table of icons.
						local upcastable = mod.modifier:IsResourceCostUpcastable()
						if upcastable then
							mod.modifier:get_or_add("_tmp_symbols", {}).upcast = 0

							--these variables should all initialize fine based on IsResourceCostUpcastable being true.
							local resourceid = mod.modifier.resourceCost
							local resourceTable = dmhub.GetTable("characterResources")
							local baseResource = resourceTable[resourceid]

							local baseLevel = baseResource:GetSpellSlot()

							local resourcesAvailable = creature:GetResources()

							--lists of lists of resources, each a row of ascending order resources.
							local rows = {}

							local slotResources = {}

							for k,v in pairs(resourcesAvailable) do
								local resourceInfo = resourceTable[k]
								if resourceInfo ~= nil and resourceInfo:GetSpellSlot() ~= nil and resourceInfo:GetSpellSlot() >= baseLevel then
									slotResources[k] = resourceInfo
									if resourceInfo:GetSpellSlot() == baseLevel then
										rows[#rows+1] = {resourceInfo}
									end
								end
							end

							for _,row in ipairs(rows) do
								local foundNew = true
								local count = 0
								while foundNew and count < 100 do

									foundNew = false
									for _,resourceInfo in pairs(slotResources) do
										if resourceInfo.levelsFrom == row[#row].id then
											row[#row+1] = resourceInfo
											foundNew = true
										end
									end


									count = count + 1
								end
							end

							table.sort(rows, function(a,b) return a[1] == baseResource end)

							upcastCells = {}
							upcastPanels = {}
							for _,row in ipairs(rows) do
								local cells = {}

								for nupcast,cell in ipairs(row) do
									local maxResources = resourcesAvailable[cell.id]
									local curResources = math.max(0, maxResources - creature:GetResourceUsage(cell.id, cell.usageLimit))
									local cellPanel = gui.Panel{
										classes = {"cell", cond(cell == baseResource, "selected")},
										flow = "vertical",
										width = "auto",
										height = "auto",
										bgimage = "panels/square.png",
										bgcolor = "clear",
										styles = {
											{
												selectors = {"cell", "hover"},
												borderWidth = 2,
												borderColor = "#ffffff99",
											},
											{
												selectors = {"cell", "selected"},
												borderWidth = 2,
												borderColor = "white",
											},
										},

										press = function(element)
											for _,p in ipairs(upcastCells) do
												p:SetClass("selected", p == element)
											end

											check.data.mod.modifier.consumeResourceOverride = cell.id
											check.data.mod.modifier:get_or_add("_tmp_symbols", {}).upcast = nupcast-1

											CalculateRollText()
										end,

										gui.Panel{
											width = 32,
											height = 32,
											classes = {cond(curResources == 0, "expended", "normal")},
											styles = cell:CreateStyles(),
										},
										gui.Label{
											height = 16,
											width = 32,
											fontSize = 12,
											textAlignment = "center",
											color = cond(curResources == 0, "#ffffff77", "white"),
											text = string.format("%d/%d", curResources, maxResources),
										}
									}
									cells[#cells+1] = cellPanel
									upcastCells[#upcastCells+1] = cellPanel
								end

								local rowPanel = gui.Panel{
									classes = {cond(ischecked, nil, "collapsed-anim")},
									height = "auto",
									width = "100%",
									flow = "horizontal",
									children = cells,
								}

								upcastPanels[#upcastPanels+1] = rowPanel
							end

						else --end of upcastable section.

							--non upcastable resource usage gets an availability description.
							local availability = mod.modifier:DescribeResourceAvailability(creature)
							if availability then
								text = string.format("%s (%s)", text, availability)
							end

						end


						local classes = {}

						if force then
							classes = {"collapsed-anim"}
						end

						if mod.modifier:CriticalHitsOnly() then
							if addedCritical == false then
								children[#children+1] = criticalHit
								addedCritical = true
							end

							if not options.critical then
								classes = {"collapsed-anim"}
							end
						end

						check = CreatePill{
							classes = classes,
							text = text,
							value = ischecked,
							data = {
								mod = mod,
							},
							change = function(element)
								CalculateRollText()
								if upcastPanels ~= nil then
									for _,p in ipairs(upcastPanels) do
										p:SetClass("collapsed-anim", not element.value)
									end
								end
							end,
							linger = gui.Tooltip{
								text = tooltip,
								maxWidth = 600,
							},
						}

						children[#children+1] = check
						modifierChecks[#modifierChecks+1] = check

						if upcastPanels ~= nil then
							for _,p in ipairs(upcastPanels) do
								children[#children+1] = p
							end
						end

					elseif mod.check then
						--this is a checkbox that is passed in that we will pass the results of straight out.

						local check = CreatePill{
							text = mod.text,
							value = mod.value,
							data = {
								mod = mod,
							},
							change = function(element)
								element.data.mod.change(element.value)
							end,
							linger = function(element)
								if mod.tooltip ~= nil then
									gui.Tooltip{
										text = element.data.mod.tooltip,
										maxWidth = 600,
									}(element)
								end
							end,
						}

						children[#children+1] = check
					elseif mod.modifierOptions then
						local dropdown = gui.Dropdown{
							width = 200,
							height = 26,
							valign = "center",
							fontSize = 16,
							idChosen = mod.hint.result,
							options = mod.modifierOptions,
							data = {
								mod = mod,
							},
							change = function(element)
								CalculateRollText()
							end,
						}

						local panel = gui.Panel{
							flow = "horizontal",
							height = 32,
							width = "100%",
							gui.Label{
								text = mod.text .. ":",
								classes = "explanation",
								halign = "left",
								valign = "center",
								width = 120,
							},
							linger = gui.Tooltip{
								text = mod.tooltip,
								maxWidth = 600,
							},
							dropdown,
						}

						modifierDropdowns[#modifierDropdowns+1] = dropdown
						children[#children+1] = panel
					end
				end

				if addedCritical == false then
					children[#children+1] = criticalHit
					addedCritical = true
				end

				element.children = children
			end
		},
	}

	local CancelRollDialog = function()
		RemoveTargetHints()
		local wasPreparing = m_preparing
		m_preparing = false
		if cancelRoll ~= nil and wasPreparing then
			if not rollAllPromptsCheck:HasClass("collapsed-anim") and rollAllPromptsCheck.value and rollAllPrompts ~= nil then
				rollAllPrompts()
			end
			cancelRoll()
		end
		chat.PreviewChat('')
		--PreviewChat('') skips clearing while an unarmed dice cage is registered -- this
		--card's own cage is -- which would orphan the resting dice in mid-screen. Clear
		--them explicitly, as the Codex's roll dialogs do; the fallback is for an older
		--engine without the scoped method.
		local cleared = pcall(function() dmhub.ClearChatPreviewDice() end)
		if not cleared then
			dmhub.CancelCurrentRoll()
		end
		HideCard()
		if wasPreparing then
			OnHide()
		end
	end

	--Throws the dice resting in the cage (they hurl across the screen); the engine then
	--submits the roll through the chat events. With nothing in the cage -- no dice in the
	--roll, or the preview did not arm -- submit directly.
	local ThrowDice = function()
		if not m_preparing then
			return
		end

		local hasDice = (m_cage ~= nil and m_cage.valid and not dmhub.IsRollDeterministic(rollInput.text))
		if not hasDice then
			resultPanel:FireEvent('submit')
			return
		end

		local rollid = resultPanel.data.rollid
		pcall(function() dice.Click() end)

		dmhub.Schedule(0.3, function()
			if resultPanel.valid and m_preparing and resultPanel.data.rollid == rollid then
				resultPanel:FireEvent('submit')
			end
		end)
	end

	rollDiceButton = gui.Button{
		classes = {"collapsedWhenRolling"},
		text = 'Roll Dice',
		width = "100%",
		height = 44,
		halign = "center",
		fontSize = 22,
		tmargin = 6,
		events = {
			click = function(element)
				ThrowDice()
			end,
			enter = function(element)
				element:FireEvent("click")
			end,
		}
	}

	rollDisabledLabel = gui.Label{
		classes = {'explanation', "collapsed-anim"},
		color = "#ffaaaaff",
	}

	--Close (X) in the card's corner: cancels a roll being prepared, or puts away a result.
	local closeButton = gui.CloseButton{
		halign = "right",
		valign = "top",
		floating = true,
		width = 20,
		height = 20,
		escapeActivates = true,
		escapePriority = EscapePriority.EXIT_ROLL_DIALOG,
		click = function(element)
			if m_preparing then
				CancelRollDialog()
			else
				HideCard()
			end
		end,
	}

	--gui.DicePreview is the engine's dice-preview cage; fall back to a plain panel on an
	--older binary.
	local diceCageCtor = gui.Panel
	pcall(function() diceCageCtor = gui.DicePreview or gui.Panel end)

	local diceCage = diceCageCtor{
		--once thrown the dice roll across the screen, so the empty cage folds away.
		classes = {"collapsedWhenRolling"},
		styles = {
			gui.Style{
				opacity = 0,
			},
		},
		width = "90%",
		height = 110,
		halign = "center",
		bgimage = true,
		bgcolor = "white",
		draggable = true,
		dragMove = false,

		create = function(element)
			m_cage = element
			--Dice thrown out of the cage roll across the whole screen rather than a tight box
			--around this little panel.
			pcall(function() element.dicePreviewScreenBounds = true end)
			if m_preparing then
				SetCageRegistered(true)
			end
		end,

		destroy = function(element)
			pcall(function() element:SetAsDicePreviewPanel(false) end)
			if m_cage == element then
				m_cage = nil
			end
		end,

		--panel-scoped dice input: only this cage's resting dice react.
		hover = function(element)
			pcall(function() element:DicePreviewMouseEnter() end)
		end,
		dehover = function(element)
			pcall(function() element:DicePreviewMouseLeave() end)
		end,
		click = function(element)
			pcall(function() element:DicePreviewClick() end)
		end,
		dragging = function(element)
			pcall(function() element:DicePreviewDragThink() end)
		end,
		drag = function(element)
			pcall(function() element:DicePreviewDragEnd() end)
		end,

		textCalculated = function(element)
			element:SetClass("collapsed", dmhub.IsRollDeterministic(rollInput.text))
		end,
	}

	local resultDisplay = CreateResultDisplay()

	--Roll visibility and pre-roll live behind the cog by the title, out of the way. It
	--stays open or shut between rolls.
	local optionsPanel = gui.Panel{
		classes = {"rollSettingsPanel", "collapsedWhenRolling", "collapsed"},
		hideRollDropdown,
		updateRollVisibility,
		prerollCheck,
		autoRollPanel,
	}

	local settingsCog = gui.Panel{
		classes = {"rollSettingsCog", "collapsedWhenRolling"},
		bgimage = "phosphor/gear-fine-fill.png",
		halign = "right",
		valign = "top",
		floating = true,
		width = 18,
		height = 18,
		rmargin = 28,
		tmargin = 4,
		linger = gui.Tooltip("Roll settings"),
		press = function(element)
			local open = optionsPanel:HasClass("collapsed")
			optionsPanel:SetClass("collapsed", not open)
			element:SetClass("open", open)
		end,
	}

	--Says so under the title while the roll is not visible to everyone.
	local hiddenBanner = gui.Label{
		classes = {"hiddenRollBanner", "collapsed"},
		prepare = function(element)
			UpdateHiddenBanner(dmhub.GetSettingValue("privaterolls"))
		end,
	}

	UpdateHiddenBanner = function(id)
		if not hiddenBanner.valid then
			return
		end
		id = id or hideRollDropdown.idChosen
		if (not RollPrivacyAllowed()) or id == nil or id == "visible" then
			hiddenBanner:SetClass("collapsed", true)
			return
		end

		local text = "Hidden roll"
		for _,option in ipairs(cond(dmhub.isDM, g_rollOptionsDM, g_rollOptionsPlayer)) do
			if option.id == id then
				text = string.format("Hidden roll: %s", option.text)
			end
		end
		hiddenBanner.text = text
		hiddenBanner:SetClass("collapsed", false)
	end

	local rollPanel = gui.Panel{
		classes = {"rollPanel"},

		--the "Roll Dice" tab on the card's left edge, as on the Codex's roll card.
		gui.Panel{
			classes = {"rollTab", "collapsedWhenRolling"},
			floating = true,
			x = -30,
			valign = "top",
			halign = "left",
			width = 24,
			height = 110,
			gui.Label{
				classes = {"rollTabLabel"},
				text = "Roll Dice",
				width = "auto",
				height = "auto",
				rotate = 90,
				halign = "center",
				valign = "center",
			},
		},

		alternateRollsBar,
		advantageBar,
		diceCage,
		modifiersPanel,
		inspirationCheck,
		boonBar,
		multitokenContainer,
		m_tableContainer,
		m_customContainer,
		rollInputContainer,
		resultDisplay,
	}

	local abilityContainer = gui.Panel{
		classes = {"collapsed"},
		width = "100%",
		height = "auto",
		flow = "vertical",
	}

	local SetAbilityCard = function(ability, token)
		local key = AbilityKey(ability, token)
		if key == m_abilityKey then
			return
		end
		m_abilityKey = key

		local panel = CreateAbilityCardPanel(ability, token)
		if panel == nil then
			abilityContainer.children = {}
			abilityContainer:SetClass("collapsed", true)
			m_abilityKey = nil
			return
		end

		abilityContainer.children = {panel}
		abilityContainer:SetClass("collapsed", false)
	end

	local frame = gui.Panel{
		classes = {"rollFrame"},
		closeButton,
		settingsCog,
		title,
		hiddenBanner,
		optionsPanel,
		explanation,
		rollPanel,
		rollDisabledLabel,
		rollAllPromptsCheck,
		rollDiceButton,
	}

	card = gui.Panel{
		classes = {"hidden"},
		styles = CardStyles(),
		width = CARD_WIDTH,
		height = "auto",
		halign = "right",
		valign = "center",
		flow = "vertical",
		abilityContainer,
		frame,

		--a finished result can be dismissed with a click.
		press = function(element)
			if element:HasClass("finished") then
				HideCard()
			end
		end,
	}

	ThemeEngine.OnThemeChanged(mod, function()
		if card ~= nil and card.valid then
			card.styles = CardStyles()
		end
	end)

	local delayRoll = 0
	local rollIsSilent = false

	--Shows a landed roll on the card and on the shared copy, then puts the card away.
	local ShowRollResult = function(rollInfo, generation)
		if generation ~= m_generation or not card.valid then
			return
		end

		local result = {
			total = rollInfo.total,
			outcome = RollOutcome(rollInfo),
			natural = NaturalResult(rollInfo, rollType),
			dice = CollectDice(rollInfo),
		}

		card:SetClassTree("rolling", false)
		card:SetClassTree("finished", true)
		resultDisplay:FireEventTree("showResult", result)

		--the dice have settled; release the cage so they can clear away.
		SetCageRegistered(false)

		UpdateShare(BuildShareState("finished", result))

		dmhub.Schedule(RESULT_LINGER_SECONDS, function()
			if generation == m_generation and resultPanel.valid then
				HideCard()
			end
		end)
	end

	resultPanel = gui.Panel{
		classes = {'hidden'},
		width = 1,
		height = 1,
		floating = true,
		interactable = false,

		data = {

			rollid = nil,

			coroutineOwner = nil,

			--the visible card; GameHud:InitStandaloneRollHost mounts it.
			card = card,

			ShowDialog = function(options)


				if not resultPanel.valid then
					return
				end

				--deep copy any modifiers so we can freely modify them.
				options.modifiers = DeepCopy(options.modifiers or {})
                table.sort(options.modifiers, function(a,b)
                    if a.modifier ~= nil and b.modifier == nil then
                        return true
                    end

                    if a.modifier == nil and b.modifier ~= nil then
                        return false
                    end

                    if a.modifier == nil then
                        return false
                    end

                    return a.modifier.priority < b.modifier.priority
                end)

				if coroutine.GetCurrentId() ~= nil then
					if resultPanel.data.coroutineOwner == nil then
						resultPanel.data.coroutineOwner = coroutine.GetCurrentId()
					else
						while resultPanel.data.coroutineOwner ~= coroutine.GetCurrentId() and coroutine.IsCoroutineWithIdStillRunning(resultPanel.data.coroutineOwner) do
							coroutine.yield(0.01)
						end

						resultPanel.data.coroutineOwner = coroutine.GetCurrentId()
					end
				end

				if options.delay ~= nil then

					if dmhub.inCoroutine then
						local t = dmhub.Time()
						while dmhub.Time() < t + options.delay do
							coroutine.yield(0.02)
						end
					else

						local delay = options.delay

						local optionsCopy = {}
						for k,v in pairs(options) do
							optionsCopy[k] = v
						end

						optionsCopy.rollid = dmhub.GenerateGuid()
						optionsCopy.delay = nil

						dmhub.Schedule(delay, function()
							if resultPanel.valid then
								resultPanel.data.ShowDialog(optionsCopy)
							end
						end)


						return optionsCopy.rollid
					end
				end

				if dmhub.inCoroutine then
					while m_preparing do
						coroutine.yield(0.02)

						if not resultPanel.valid then
							return
						end
					end
				elseif m_preparing then
					local rollid = dmhub.GenerateGuid()
					--not in a coroutine so just reschedule this.
					dmhub.Schedule(1.0, function()
						if resultPanel.valid then
							local optionsCopy = {}
							for k,v in pairs(options) do
								optionsCopy[k] = v
							end

							optionsCopy.rollid = rollid

							resultPanel.data.ShowDialog(optionsCopy)
						end
					end)

					return rollid
				end

				if options.skipDeterministic and dmhub.IsRollDeterministic(options.roll) then
					--this is a quick, happy path that we try to take if the roll is deterministic and we don't need to show the dialog.
					--This is used to avoid the significant performance cost of creating the UI elements.

					local activeModifiers = false
					for _,mod in ipairs(options.modifiers or {}) do
						if mod.modifier then

							local ischecked = false
							local force = mod.modifier:try_get("force", false)
							if force then
								ischecked = true
							elseif mod.hint ~= nil then
								ischecked = mod.hint.result
							end

							if ischecked then
								activeModifiers = true
								break
							end
						end
					end

					if not activeModifiers then

						local guid = dmhub.GenerateGuid()

						local tokenid = nil
						if options.creature ~= nil then
							tokenid = dmhub.LookupTokenId(options.creature)
						end

						dmhub.Roll{
							guid = guid,
							description = options.description,
							tokenid = tokenid,
							silent = true,
							instant = true,
							roll = options.roll,
							creature = options.creature,
							properties = options.rollProperties,
							complete = function(rollInfo)
								if options.completeRoll ~= nil then
									options.completeRoll(rollInfo)
								end
							end
						}

						return guid
					end
				end

				if options.tableRef ~= nil then
					--delegate table rolls to the specialized dialog for them.
					return resultPanel.data.rollOnTableDialog.data.ShowDialog(options)
				end

				if options.PopulateTable ~= nil then
					m_tableContainer:SetClass("collapsed", false)
					options.PopulateTable(m_tableContainer)
				else
					m_tableContainer:SetClass("collapsed", true)
				end

				if options.PopulateCustom ~= nil then
					m_customContainer:SetClass("collapsed", false)
					options.PopulateCustom(m_customContainer)
				else
					m_customContainer:SetClass("collapsed", true)
				end

				rollDiceButton.hasFocus = true

				m_symbols = options.symbols

				resultPanel.data.rollid = options.rollid or dmhub.GenerateGuid()
				rollIsSilent = false
				delayRoll = 0

                local richStatus = "Rolling dice"
                if options.title then
                    richStatus = string.format("Rolling %s", options.title)
                end

				--a new roll takes over the card, including from a result still on show.
				m_generation = m_generation + 1
				m_preparing = true
				card:SetClassTree("rolling", false)
				card:SetClassTree("finished", false)
				resultDisplay:FireEventTree("clearResult")
				card:SetClass("hidden", false)
				g_localCardVisible = true
				if g_refreshRemote ~= nil then
					g_refreshRemote()
				end
				SetCageRegistered(true)
				OnShow(richStatus)

				if not options.nofadein then
					card:PulseClass("fadein")
				end

				m_options = options

				targetHints = options.targetHints


				advantageStateLocked = false
				rollType = options.type
				rollSubtype = options.subtype
				rollProperties = options.rollProperties

				creature = options.creature
				targetCreature = options.targetCreature
				m_multitargets = options.multitargets

				m_token = nil
				if creature ~= nil then
					m_token = dmhub.LookupToken(creature)
				end
				m_ability = options.ability
				SetAbilityCard(m_ability, m_token)

				title.text = options.title or 'Roll Dice'
				explanation.text = options.explanation or ''
				explanation:SetClass("collapsed", (options.explanation or '') == '')
				if rollInput.text == options.roll then
					--force the edit event if we already have this set.
					rollInput:FireEvent('edit')
				end

				rollAllPrompts = options.rollAllPrompts
				rollActive = options.rollActive
				beginRoll = options.beginRoll
				completeRoll = options.completeRoll
				cancelRoll = options.cancelRoll

				card:FireEventTree('prepare', options)

				--sharing decides on the visibility the dropdown just took from the setting.
				if ShouldShareRoll(m_token, hideRollDropdown.idChosen) then
					BeginShare(m_token, m_ability, nil)
				else
					EndShare()
				end

				baseRoll = options.roll
				CalculateRollText()

				if options.numPrompts ~= nil and options.numPrompts > 1 then
					rollAllPromptsCheck.value = true
					rollAllPromptsCheck.data.SetText(string.format("Roll all %d prompts", options.numPrompts))
					rollAllPromptsCheck:SetClass("collapsed-anim", false)
				else
					rollAllPromptsCheck.value = false
					rollAllPromptsCheck:SetClass("collapsed-anim", true)
				end

				if options.skipDeterministic and dmhub.IsRollDeterministic(rollInput.text) and dmhub.IsRollDeterministic(options.roll) then
					rollIsSilent = true
					if options.delayInstant ~= nil then
						delayRoll = options.delayInstant
					end
					resultPanel:FireEvent('submit')
				elseif options.autoroll == true or dmhub.GetSettingValue("autorollall") or (options.creature ~= nil and (options.creature._tmp_aicontrol > 0 or creature.AIRollsForCreature(options.creature))) then
					if options.delayInstant ~= nil then
						delayRoll = options.delayInstant or 0.05
					else
						--TODO: Work out why instant rolls have a problem if we don't include a small delay.
						delayRoll = 0.05
					end
					resultPanel:FireEvent('submit')
				elseif options.autoroll == "cancel" then
					CancelRollDialog()
				elseif options.autoroll ~= nil then

					local autoroll = dmhub.GetSettingValue(string.format("%s:autoroll", options.autoroll.id))
					local hideFromPlayers = dmhub.GetSettingValue(string.format("%s:hideFromPlayers", options.autoroll.id))
					local quickRoll = dmhub.GetSettingValue(string.format("%s:quickRoll", options.autoroll.id))

					autoRollPanel:SetClass("collapsed-anim", false)
					autoRollCheck.value = autoroll or false
					autoRollCheck.data.SetText(string.format("Auto-roll %s in future", options.autoroll.text))
					autoHideCheck.data.SetText(string.format("Hide %s from players", options.autoroll.text))
					autoQuickCheck.data.SetText(string.format("Skip rolling animation for %s", options.autoroll.text))
					autoRollId = options.autoroll.id

					autoHideCheck.value = hideFromPlayers or false
					autoQuickCheck.value = quickRoll or false


					if autoroll then
						resultPanel:FireEvent('submit')
					end
				else
					autoRollPanel:SetClass("collapsed-anim", true)
					autoRollId = nil
				end

				return resultPanel.data.rollid
			end,

			IsShown = function()
				return m_preparing
			end,

			Cancel = function()
				CancelRollDialog()
			end,
		},

		events = {
			submit = function(element)
				if not m_preparing then
					return
				end
				m_preparing = false

				RemoveTargetHints()

				OnHide()

				local dmonly = false
				local instant = false

				if autoRollId ~= nil then

					dmonly = autoHideCheck.value
					instant = autoQuickCheck.value

					dmhub.SetSettingValue(string.format("%s:autoroll", autoRollId), autoRollCheck.value)
					dmhub.SetSettingValue(string.format("%s:hideFromPlayers", autoRollId), autoHideCheck.value)
					dmhub.SetSettingValue(string.format("%s:quickRoll", autoRollId), autoQuickCheck.value)

				end

				if hideRollDropdown.idChosen == "dm" then
					dmonly = true
				end

				if hideRollDropdown.idChosen ~= dmhub.GetSettingValue("privaterolls") and updateRollVisibility.value then
					--update the setting for private rolls from now on.
					dmhub.SetSettingValue("privaterolls", hideRollDropdown.idChosen)
				end

				dmhub.SetSettingValue("privaterolls:save", updateRollVisibility.value)

				local inspirationUsed = inspirationCheck.value

				if rollAllPrompts ~= nil and rollAllPromptsCheck.value then
					rollAllPrompts()
				end

				--we must save off anything from the surrounding scope since this dialog might be reused after this.
				local activeRollFn = rollActive
				local beginRollFn = beginRoll
				local completeRollFn = completeRoll
				local creatureUsed = creature
				local modifiersUsed = dmhub.DeepCopy(activeModifiers)

				local tokenid = nil

				if creature ~= nil then
					tokenid = dmhub.LookupTokenId(creature)
				end

				rollProperties = rollProperties or RollProperties.new{}
				if not criticalHit:HasClass("collapsed-anim") then
					rollProperties.criticalHitDamage = criticalHit.value
				end

				--Keep the card up to show the dice landing and the result, unless there is
				--nothing to watch: a silent or animation-free roll, or no dice at all.
				local showResult = (not rollIsSilent) and (not instant) and (not dmhub.IsRollDeterministic(rollInput.text))
				local generation = m_generation
				if showResult then
					card:SetClassTree("rolling", true)
					card:SetClassTree("finished", false)
					UpdateShare(BuildShareState("rolling"))
				else
					HideCard()
				end

				local activeRoll = dmhub.Roll{
					guid = resultPanel.data.rollid,
					description = m_options.description,
					amendable = m_options.amendable,
					tokenid = tokenid,
					silent = rollIsSilent,
					delay = delayRoll,
					dmonly = dmonly,
					instant = instant,
					roll = rollInput.text,
					creature = creature,
					properties = rollProperties,
					begin = function(rollInfo)
						if showResult and generation == m_generation and resultDisplay.valid then
							resultDisplay:FireEventTree("beginDice", rollInfo)
						end

						if beginRollFn ~= nil then
							beginRollFn(rollInfo)
						end
					end,
					complete = function(rollInfo)
						local resourceConsumed = false
						local ongoingEffects = {}
						local consumeResources = function()
							for i,modifier in ipairs(modifiersUsed) do
								local consume = modifier:ConsumeResource(creatureUsed)
								resourceConsumed = consume or resourceConsumed
							end

							for i,modifier in ipairs(modifiersUsed) do
								local newOngoingEffects = modifier:ApplyOngoingEffectsToSelfOnRoll(creature)
								if newOngoingEffects ~= nil then
									for j,c in ipairs(newOngoingEffects) do
										ongoingEffects[#ongoingEffects+1] = c
									end
								end
							end
						end

						local creatureToken = nil
						if creatureUsed ~= nil then
							creatureToken = dmhub.LookupToken(creatureUsed)
						end

						if creatureToken ~= nil then
							creatureToken:ModifyProperties{
								description = 'Used resource',
								execute = function()
									consumeResources()
									if resourceConsumed or #ongoingEffects > 0 or inspirationUsed then
										creatureUsed:SetInspiration(false)
										for i,cond in ipairs(ongoingEffects) do
											creatureUsed:ApplyOngoingEffect(cond.ongoingEffect, cond.duration, nil, {
												untilEndOfTurn = cond.durationUntilEndOfTurn,
											})
										end
									end
								end,
							}
						else
							consumeResources()
						end

						if showResult then
							ShowRollResult(rollInfo, generation)
						end

						if completeRollFn ~= nil then
							completeRollFn(rollInfo)
						end
					end
				}

				if activeRollFn ~= nil then
					activeRollFn(activeRoll)
				end

				chat.PreviewChat('')
			end,
		},
	}

	return resultPanel
end

--Hot reload: a Lua reload does not rebuild the HUD, so swap a fresh roll dialog into the
--live one (as the Codex's EmbeddedRollDialog.lua does) and re-initialize the two right-side
--hosts this file owns.
if GameHud.instance and rawget(GameHud.instance, "rollDialog") then
	local hud = GameHud.instance
	local parent = rawget(hud, "parentPanel")
	if parent ~= nil and parent.valid then
		local children = parent.children
		for index, child in ipairs(children) do
			if child == hud.rollDialog then
				hud.rollDialog = hud:CreateRollDialog()
				children[index] = hud.rollDialog
				parent.children = children
				break
			end
		end
	end

	local host = rawget(hud, "standaloneRollHostPanel")
	if host ~= nil and host.valid then
		hud:InitStandaloneRollHost(host)
	end

	local abilityDisplay = rawget(hud, "abilityDisplayPanel")
	if abilityDisplay ~= nil and abilityDisplay.valid then
		hud:InitAbilityDisplayPanel(abilityDisplay)
	end
end
