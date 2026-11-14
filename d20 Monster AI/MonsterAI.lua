local mod = dmhub.GetModLoading()

--d20 Monster AI: plays the turns of every creature the players do not control,
--under d20 (5e / 5.5e) rules. Modelled on the Draw Steel Codex Monster AI and
--sharing its registration API and its voice, but its rules are d20's: see
--MonsterAIRules.lua (the rules adapter a Pathfinder version would replace) and
--MonsterAIGeneric.lua (the stat-block player that runs every monster).
--
--Files, in load order:
--  MonsterAI.lua         this file: registries, logging, waiting notice, speech,
--                        movement, casting, the turn loop
--  MonsterAIRules.lua    d20 rules: action economy, ability profiles, odds,
--                        Multiattack parsing, loadouts, spell slots
--  MonsterAIGeneric.lua  the generic planner every monster uses
--  MonsterAIPreview.lua  plan preview (pause before acting)
--  MonsterAIPanel.lua    the "Monster AI" dockable panel and the AI thread
--  MonsterAIPrompts.lua  answers prompts an ability raises mid-cast
--  MonsterAITactics.lua  per-monster tactic profiles (RegisterTactic)
--  MonsterAISupport.lua  how well the AI can play each monster
--  MonsterAIBands.lua    hand-written tactics and speech for key monsters

MonsterAI = {}
MonsterAI.__index = MonsterAI

--registries (filled by the files that load after this one).
MonsterAI.moves = {}
MonsterAI.moveOrder = {}
MonsterAI.speechBands = {}
MonsterAI.tactics = {}
MonsterAI.prompts = {}

MonsterAI.active = false
MonsterAI.status = "Stopped"
MonsterAI.log = {}
MonsterAI.maxLogEntries = 300

--set by the panel: play the next plan without waiting for a preview.
MonsterAI.playEntireTurn = false

---------------------------------------------------------------------------
--Settings.
---------------------------------------------------------------------------

setting{
	id = "monsterai:preview",
	text = "Monster AI: preview each plan",
	description = "Pause before each monster action and show what it is about to do until Proceed is pressed.",
	storage = "pergamepreference",
	default = false,
	editor = "check",
}

setting{
	id = "monsterai:speech",
	text = "Monster AI: monsters speak",
	description = "Monsters that know a language call out short lines as they fight.",
	storage = "pergamepreference",
	default = true,
	editor = "check",
}

setting{
	id = "monsterai:opportunity",
	text = "Monster AI: opportunity attacks",
	description = "Monsters use their reaction to strike creatures that move out of their reach.",
	storage = "pergamepreference",
	default = true,
	editor = "check",
}

setting{
	id = "monsterai:legendary",
	text = "Monster AI: legendary actions",
	description = "Legendary monsters use legendary actions at the end of other creatures' turns.",
	storage = "pergamepreference",
	default = true,
	editor = "check",
}

setting{
	id = "monsterai:autosaves",
	text = "Monster AI: roll monster saves",
	description = "While the AI runs, it rolls every saving throw and check asked of a monster.",
	storage = "pergamepreference",
	default = true,
	editor = "check",
}

setting{
	id = "monsterai:spareDying",
	text = "Monster AI: leave dying heroes alone",
	description = "Monsters do not attack heroes who are already at 0 hit points, unless a monster's tactics say otherwise.",
	storage = "pergamepreference",
	default = true,
	editor = "check",
}

function MonsterAI.SettingOn(id)
	return dmhub.GetSettingValue("monsterai:" .. id) == true
end

---------------------------------------------------------------------------
--Instances. An instance carries the state of one actor's turn (ai.turn).
---------------------------------------------------------------------------

function MonsterAI.new(args)
	local ai = setmetatable(args or {}, MonsterAI)
	ai.turn = ai.turn or {}
	return ai
end

---------------------------------------------------------------------------
--Matching registrations to monsters.
--A `monsters` field is nil (every monster), a list of names (matched without
--case against the monster type and the token name; "goblin*" matches by
--prefix, "*dragon" by suffix), or a function(token) -> boolean.
---------------------------------------------------------------------------

local function NameMatches(pattern, name)
	if name == nil or name == "" then
		return false
	end
	pattern = string.lower(pattern)
	name = string.lower(name)
	local prefix = string.sub(pattern, -1) == "*"
	local suffix = string.sub(pattern, 1, 1) == "*"
	if prefix and suffix then
		return string.find(name, string.sub(pattern, 2, -2), 1, true) ~= nil
	elseif prefix then
		local p = string.sub(pattern, 1, -2)
		return string.sub(name, 1, #p) == p
	elseif suffix then
		local p = string.sub(pattern, 2)
		return #name >= #p and string.sub(name, -#p) == p
	end
	return name == pattern
end

--- The bestiary name of a token's monster ("Goblin Warrior"), else its name.
function MonsterAI.MonsterTypeName(token)
	if token == nil or not token.valid or token.properties == nil then
		return nil
	end
	local t = nil
	pcall(function() t = token.properties:GetMonsterType() end)
	if type(t) == "string" and t ~= "" then
		return t
	end
	return MonsterAI.DisplayName(token)
end

--- The name a token is shown with: its name, else its description.
function MonsterAI.DisplayName(token)
	if token == nil or not token.valid then
		return "creature"
	end
	local name = token.name
	if type(name) ~= "string" or name == "" then
		name = token.description
	end
	if type(name) ~= "string" or name == "" then
		name = "creature"
	end
	return name
end

function MonsterAI.MonsterMatches(token, monsters)
	if monsters == nil then
		return true
	end
	if type(monsters) == "function" then
		local ok, result = pcall(monsters, token)
		return ok and result == true
	end
	if type(monsters) == "string" then
		monsters = {monsters}
	end
	local typeName = MonsterAI.MonsterTypeName(token)
	for _,pattern in ipairs(monsters) do
		if NameMatches(pattern, typeName) or NameMatches(pattern, MonsterAI.DisplayName(token)) then
			return true
		end
	end
	return false
end

---------------------------------------------------------------------------
--Registration API.
---------------------------------------------------------------------------

--- Register a move: something an actor can do on its turn.
--- args: id, description, category ("Action", "Bonus Action", "Movement",
--- "Legendary", "Reaction", "Free"), monsters (see MonsterMatches),
--- score = function(ai, token, ctx) -> score, plan (nil or score <= 0 means no),
--- execute = function(ai, token, plan, ctx), maxScore (for the panel),
--- generic = true for the stat-block moves every monster has.
--- A hand-written move beats the generic moves when it scores higher; give it
--- a score above 1 to make sure it is chosen.
function MonsterAI.RegisterMove(args)
	assert(args.id ~= nil, "RegisterMove needs an id")
	if MonsterAI.moves[args.id] == nil then
		MonsterAI.moveOrder[#MonsterAI.moveOrder+1] = args.id
	end
	args.category = args.category or "Action"
	MonsterAI.moves[args.id] = args
	return args
end

--- Register lines a band of monsters says. args: monsters, language (optional
--- language id or name to speak in), lines = { [event] = {"Line!", ...} }.
--- Events: start (first turn), attack, spell, area, kill, hurt (bloodied),
--- dying (low hit points), retreat, opportunity, legendary, charge, miss.
function MonsterAI.RegisterSpeech(args)
	MonsterAI.speechBands[#MonsterAI.speechBands+1] = args
	return args
end

--- Register a tactic profile. See MonsterAITactics.lua for the options.
function MonsterAI.RegisterTactic(args)
	MonsterAI.tactics[#MonsterAI.tactics+1] = args
	return args
end

--- Register how the AI answers a prompt an ability raises mid-cast
--- (an invoked ability that wants targets). args: abilities (names),
--- monsters, handler = function(ai, casterToken, ability, symbols, options)
--- returning nil (default handling), "skip" or {targets = {...}}.
function MonsterAI.RegisterPrompt(args)
	MonsterAI.prompts[#MonsterAI.prompts+1] = args
	return args
end

---------------------------------------------------------------------------
--Per-game move switches (the panel's checkboxes), kept in a shared document
--so they are the same whoever hosts the AI.
---------------------------------------------------------------------------

local SETTINGS_DOC = "monsterAISettings"

function MonsterAI.MoveDisabled(monsterType, moveid)
	local doc = mod:GetDocumentSnapshot(SETTINGS_DOC)
	local disabled = doc.data.disabled
	if disabled == nil then
		return false
	end
	local key = monsterType or "*"
	return (disabled[key] ~= nil and disabled[key][moveid] == true)
		or (disabled["*"] ~= nil and disabled["*"][moveid] == true)
end

function MonsterAI.SetMoveDisabled(monsterType, moveid, value)
	local doc = mod:GetDocumentSnapshot(SETTINGS_DOC)
	doc:BeginChange()
	doc.data.disabled = doc.data.disabled or {}
	local key = monsterType or "*"
	doc.data.disabled[key] = doc.data.disabled[key] or {}
	doc.data.disabled[key][moveid] = value and true or nil
	doc:CompleteChange("Monster AI move setting", {undoable = false})
end

---------------------------------------------------------------------------
--Logging. Every decision is printed with an AI:: prefix (search the log for
--it) and kept in MonsterAI.log for the panel.
---------------------------------------------------------------------------

function MonsterAI.TokenLogName(token)
	if token == nil then
		return "nil"
	end
	if not token.valid then
		return "(invalid token)"
	end
	local name = MonsterAI.DisplayName(token)
	return string.format("%s[%s]", name, string.sub(token.charid or "", 1, 6))
end

function MonsterAI.LocLogName(loc)
	if loc == nil then
		return "nil"
	end
	return loc.str
end

local function FormatLogValue(v)
	if type(v) == "number" then
		if math.type(v) == "float" then
			return string.format("%.2f", v)
		end
		return tostring(v)
	end
	if type(v) == "table" then
		local parts = {}
		for _,item in ipairs(v) do
			parts[#parts+1] = FormatLogValue(item)
		end
		return "{" .. table.concat(parts, ", ") .. "}"
	end
	return tostring(v)
end

function MonsterAI:LogDecision(event, fields)
	fields = fields or {}
	local keys = {}
	for k,_ in pairs(fields) do
		keys[#keys+1] = k
	end
	table.sort(keys)
	local parts = {}
	for _,k in ipairs(keys) do
		parts[#parts+1] = string.format("%s=%s", k, FormatLogValue(fields[k]))
	end
	local text = table.concat(parts, " ")
	print("AI::", event, text)

	local log = MonsterAI.log
	log[#log+1] = {
		time = dmhub.Time(),
		event = event,
		actor = fields.actor,
		text = text,
	}
	while #log > MonsterAI.maxLogEntries do
		table.remove(log, 1)
	end
	MonsterAI.logChanged = dmhub.GenerateGuid()
end

---------------------------------------------------------------------------
--Coroutine helpers (as in the Codex).
---------------------------------------------------------------------------

function MonsterAI.Sleep(seconds)
	if seconds == nil or seconds <= 0 then
		return
	end
	local endTime = dmhub.Time() + seconds
	while dmhub.Time() < endTime do
		coroutine.yield(0.05)
	end
end

--Run fn in its own coroutine, passing its yields on, and report an error
--with a traceback instead of raising it.
local function RunYieldingFunction(fn)
	local thread = coroutine.create(fn)
	while coroutine.status(thread) ~= "dead" do
		local ok, delay = coroutine.resume(thread)
		if not ok then
			local err = delay
			pcall(function()
				err = debug.traceback(thread, tostring(delay))
			end)
			return false, err
		end
		if coroutine.status(thread) ~= "dead" then
			coroutine.yield(type(delay) == "number" and delay or 0.1)
		end
	end
	return true
end

--MonsterAI.RunYieldingFunction(fn) and ai:RunYieldingFunction(fn) are the
--same table field, so one function serves both call styles.
function MonsterAI.RunYieldingFunction(selfOrFn, fn)
	return RunYieldingFunction(fn or selfOrFn)
end

--True when the AI has been asked to stop; long waits poll it.
function MonsterAI.StopRequested()
	return mod.unloaded or not MonsterAI.active
end

---------------------------------------------------------------------------
--"The AI is waiting on a player" notice: published by the host to a shared
--document so every client's tip banner shows it ("Waiting for Aldric's
--Dexterity saving throw").
---------------------------------------------------------------------------

local WAITING_DOC = "monsterAIWaiting"
local NOTICE_GRACE_SECONDS = 1
local m_noticeText = nil
local m_noticeSince = 0

function MonsterAI.SetWaiting(key, text, subject)
	if type(text) ~= "string" or text == "" then
		MonsterAI.ClearWaiting()
		return
	end
	local charid = subject ~= nil and subject.charid or nil
	local doc = mod:GetDocumentSnapshot(WAITING_DOC)
	if doc.data.key == key and doc.data.text == text and doc.data.charid == charid then
		return
	end
	doc:BeginChange()
	doc.data.key = key
	doc.data.text = text
	doc.data.charid = charid
	doc:CompleteChange("Monster AI waiting: " .. text, {undoable = false})
end

function MonsterAI.ClearWaiting()
	local doc = mod:GetDocumentSnapshot(WAITING_DOC)
	if doc.data.key == nil and doc.data.text == nil and doc.data.charid == nil then
		return
	end
	doc:BeginChange()
	doc.data.key = nil
	doc.data.text = nil
	doc.data.charid = nil
	doc:CompleteChange("Monster AI waiting cleared", {undoable = false})
end

Tip.notices["monster-ai-waiting"] = {
	id = "monster-ai-waiting",
	priority = 1000,
	text = function()
		local q = dmhub.initiativeQueue
		if q == nil or q.hidden then
			m_noticeText = nil
			return nil
		end
		local doc = mod:GetDocumentSnapshot(WAITING_DOC)
		local text = doc.data.text
		if type(text) ~= "string" or text == "" then
			m_noticeText = nil
			return nil
		end
		if text ~= m_noticeText then
			m_noticeText = text
			m_noticeSince = dmhub.Time()
		end
		if dmhub.Time() - m_noticeSince < NOTICE_GRACE_SECONDS then
			return nil
		end
		--the roll is already open in front of this user: the banner would
		--only cover the dialog's title.
		local gamehud = GameHud.instance
		if gamehud and gamehud.rollDialog ~= nil and gamehud.rollDialog.data.IsShown() then
			return nil
		end

		local controls = nil
		local charid = doc.data.charid
		if type(charid) == "string" then
			local token = dmhub.GetTokenById(charid)
			if token ~= nil and token.valid and token.canControl then
				local selected = false
				for _,tok in ipairs(dmhub.selectedTokens or {}) do
					if tok.charid == charid then
						selected = true
					end
				end
				if not selected then
					controls = {
						action = {
							text = string.format("Select %s", MonsterAI.DisplayName(token)),
							press = function()
								dmhub.SelectToken(charid)
							end,
						},
					}
				end
			end
		end
		return text, controls
	end,
}

---------------------------------------------------------------------------
--Tokens.
---------------------------------------------------------------------------

function MonsterAI.TokenIsLiveCombatant(token)
	if token == nil or not token.valid or token.properties == nil then
		return false
	end
	local dead = false
	pcall(function() dead = token.properties:IsDead() end)
	if dead then
		return false
	end
	return true
end

--A creature the AI plays: alive or not, on the map, and controlled by no player.
function MonsterAI.IsAIPlayed(token)
	return token ~= nil and token.valid and token.properties ~= nil and not token.playerControlled
end

--Live creatures on this map that are hostile to token.
function MonsterAI:Enemies(token)
	local result = {}
	for _,other in ipairs(dmhub.allTokens) do
		if other.charid ~= token.charid and MonsterAI.TokenIsLiveCombatant(other)
			and other.floorIndex == token.floorIndex and not token:IsFriend(other) then
			result[#result+1] = other
		end
	end
	return result
end

--Live creatures on this map friendly to token (token itself excluded).
function MonsterAI:Allies(token)
	local result = {}
	for _,other in ipairs(dmhub.allTokens) do
		if other.charid ~= token.charid and MonsterAI.TokenIsLiveCombatant(other)
			and other.floorIndex == token.floorIndex and token:IsFriend(other) then
			result[#result+1] = other
		end
	end
	return result
end

--Focus the camera on an actor unless it is already in view.
function MonsterAI:FocusCameraOnActor(token)
	if not MonsterAI.TokenIsLiveCombatant(token) or MonsterAI.lastFocusedActor == token.charid then
		return false
	end
	MonsterAI.lastFocusedActor = token.charid
	local bounds = dmhub.cameraUsableBounds
	local pos = token.pos
	local halfSize = (token.tileSize or 1)*0.5
	if bounds ~= nil and pos ~= nil
		and pos.x - halfSize >= bounds.x1 and pos.x + halfSize <= bounds.x2
		and pos.y - halfSize >= bounds.y1 and pos.y + halfSize <= bounds.y2 then
		return false
	end
	local ok = pcall(function()
		dmhub.CenterOnToken(token.charid, {smooth = true})
		dmhub.SyncCamera{speed = 1}
	end)
	if ok then
		MonsterAI.Sleep(0.8)
	end
	return ok
end

---------------------------------------------------------------------------
--Speech. Short, punchy, in character, and sparse: a creature that knows no
--language says nothing. Lines come from the creature's band (RegisterSpeech)
--and otherwise from the generic lines below, which match the Codex's.
---------------------------------------------------------------------------

MonsterAI.genericSpeech = {
	opportunity = {"Take This!", "Die!", "I'll take a swing!"},
	dying = {"I'll take you with me!", "We die together!", "I won't go easily!"},
	charge = {"Charge!"},
	kill = {"Next!", "Who's next?", "One down!"},
	retreat = {"Fall back!", "Not today!"},
}

--chance a generic line is said when its moment comes (band lines always try).
MonsterAI.genericSpeechChance = 0.35
--seconds a creature stays quiet after speaking.
MonsterAI.speechCooldown = 12
local g_lastSpoke = {}

function MonsterAI.FindLanguageId(idOrName)
	local languages = dmhub.GetTable(Language.tableName) or {}
	if languages[idOrName] ~= nil then
		return idOrName
	end
	local wanted = string.lower(idOrName)
	for id, language in unhidden_pairs(languages) do
		if string.lower(tostring(language.name)) == wanted then
			return id
		end
	end
	return nil
end

--- The band speech registration for a token, or nil.
function MonsterAI.SpeechBandFor(token)
	for i=#MonsterAI.speechBands,1,-1 do
		local band = MonsterAI.speechBands[i]
		if MonsterAI.MonsterMatches(token, band.monsters) then
			return band
		end
	end
	return nil
end

--Show a speech bubble over a token straight away.
--options.language: a language id or name to speak in instead of its own.
function MonsterAI:SpeakNow(token, text, options)
	if not MonsterAI.TokenIsLiveCombatant(token) then
		return false
	end
	if type(text) == "table" then
		if #text == 0 then
			return false
		end
		text = text[math.random(1, #text)]
	end
	local language = nil
	if options ~= nil and options.language ~= nil then
		language = MonsterAI.FindLanguageId(options.language)
	end
	if language == nil then
		local ok, result = pcall(function() return token.properties:CurrentlySpokenLanguage() end)
		if ok then
			language = result
		end
	end
	if language == nil then
		--a creature that speaks no language says nothing.
		return false
	end
	token:ModifyProperties{
		description = "Speech",
		undoable = false,
		execute = function()
			token.properties:CharacterSpeech{
				text = text,
				langid = language,
			}
		end,
	}
	g_lastSpoke[token.charid] = dmhub.Time()
	self:LogDecision("SPEECH", {actor = MonsterAI.TokenLogName(token), text = text})
	return true
end

--Say a line for a moment of the fight (an event name above), if the
--creature has one to say and has not spoken just now.
function MonsterAI:Speak(token, event, options)
	options = options or {}
	if not MonsterAI.SettingOn("speech") or not MonsterAI.TokenIsLiveCombatant(token) then
		return false
	end
	local last = g_lastSpoke[token.charid]
	if last ~= nil and dmhub.Time() - last < MonsterAI.speechCooldown and not options.force then
		return false
	end
	local band = MonsterAI.SpeechBandFor(token)
	local lines = nil
	local chance = MonsterAI.genericSpeechChance
	if band ~= nil and band.lines ~= nil and band.lines[event] ~= nil then
		lines = band.lines[event]
		chance = band.chance or 0.7
	elseif band ~= nil and band.silent then
		return false
	else
		lines = MonsterAI.genericSpeech[event]
	end
	if lines == nil or #lines == 0 then
		return false
	end
	if not options.force and math.random() > chance then
		return false
	end
	local spoke = self:SpeakNow(token, lines, {language = options.language or (band ~= nil and band.language or nil)})
	if spoke then
		self.Sleep(0.45)
	end
	return spoke
end

---------------------------------------------------------------------------
--Movement.
---------------------------------------------------------------------------

--Feet of movement the token has left this turn.
function MonsterAI.MovementLeftFeet(token)
	local c = token.properties
	local speed = c:CurrentMovementSpeed() or 0
	local moved = c:DistanceMovedThisTurnInFeet() or 0
	return math.max(0, speed - moved)
end

--Where the token can end a move this turn: a table of {loc, cost} (cost in
--decis: tenths of a square), its own square always included. Squares where
--another creature stands are dropped.
function MonsterAI:CalculateMovementPaths(token, extraFeet)
	local feet = MonsterAI.MovementLeftFeet(token) + (extraFeet or 0)
	local decis = math.floor(feet / dmhub.unitsPerSquare * 10 + 0.001)
	local paths = {}
	if decis > 0 then
		local ok, result = pcall(function()
			return token:CalculatePathfindingArea(decis, {})
		end)
		if ok and result ~= nil then
			paths = result
		end
	end

	local here = token.loc
	local list = {}
	local haveHere = false
	local occupied = {}
	for _,other in ipairs(dmhub.allTokens) do
		if other.charid ~= token.charid and MonsterAI.TokenIsLiveCombatant(other) and other.floorIndex == token.floorIndex then
			for _,loc in ipairs(other.locsOccupying) do
				occupied[loc.str] = true
			end
		end
	end

	for _,info in pairs(paths) do
		local loc = info.loc
		local blocked = false
		local footprint = token:LocsOccupyingWhenAt(loc) or {loc}
		for _,l in ipairs(footprint) do
			if occupied[l.str] then
				blocked = true
				break
			end
		end
		if not blocked then
			if loc.str == here.str then
				haveHere = true
				list[#list+1] = {loc = loc, cost = 0}
			else
				list[#list+1] = {loc = loc, cost = info.cost or 0}
			end
		end
	end
	if not haveHere then
		list[#list+1] = {loc = here, cost = 0}
	end
	table.sort(list, function(a,b) return a.cost < b.cost end)
	return list
end

--Move the token and wait for it to arrive. Returns true if it moved.
function MonsterAI:MoveToken(token, loc, options)
	if loc == nil or token.loc.str == loc.str then
		return false
	end
	--the destination was chosen from CalculateMovementPaths, so it is within
	--the creature's movement; Move's own default cap (3 squares) is not.
	options = options or {}
	if options.maxCost == nil then
		options.maxCost = 10000
	end
	if options.ignoreFalling == nil then
		options.ignoreFalling = false
	end
	local fromLoc = token.loc
	self:LogDecision("MOVEMENT START", {
		actor = MonsterAI.TokenLogName(token),
		from = MonsterAI.LocLogName(fromLoc),
		to = MonsterAI.LocLogName(loc),
	})
	MonsterAI.ownMoves[token.charid] = true
	local ok, result = pcall(function()
		return token:Move(loc, options)
	end)
	if not ok then
		MonsterAI.ownMoves[token.charid] = nil
		error(result)
	end
	if result == nil then
		MonsterAI.ownMoves[token.charid] = nil
		self:LogDecision("MOVEMENT REFUSED", {
			actor = MonsterAI.TokenLogName(token),
			to = MonsterAI.LocLogName(loc),
			result = "no path returned",
		})
		return false
	end
	local start = dmhub.Time()
	coroutine.yield(0.1)
	while token.valid and token.isMoving and dmhub.Time() - start < 30 do
		coroutine.yield(0.05)
	end
	MonsterAI.Sleep(0.15)
	MonsterAI.ownMoves[token.charid] = nil
	MonsterAI.NoteTokenPositions()
	self:LogDecision("MOVEMENT DONE", {
		actor = MonsterAI.TokenLogName(token),
		at = token.valid and MonsterAI.LocLogName(token.loc) or "gone",
	})
	return true
end

--tokens the AI is moving right now (its own moves never trigger its own
--opportunity attacks).
MonsterAI.ownMoves = {}

--Last known square of every token, used to notice creatures leaving reach.
MonsterAI.lastPositions = {}

function MonsterAI.NoteTokenPositions()
	local positions = {}
	for _,token in ipairs(dmhub.allTokens) do
		positions[token.charid] = {loc = token.loc, floor = token.floorIndex}
	end
	MonsterAI.lastPositions = positions
end

---------------------------------------------------------------------------
--Distance, range and sight.
---------------------------------------------------------------------------

--Distance in feet, measured as the action bar measures it.
function MonsterAI.Distance(a, b)
	return a:Distance(b)
end

--The action bar's in-range test: an ability with range R reaches a creature
--whose measured distance is less than R plus one square.
function MonsterAI.InRange(range, distance)
	return distance < range + dmhub.unitsPerSquare
end

--Distance from `token` standing at `loc` to `target` (target where it stands).
function MonsterAI:DistanceFromLoc(token, loc, target)
	if loc == nil or loc.str == token.loc.str then
		return token:Distance(target)
	end
	local cache = self.turn.distanceCache
	if cache == nil then
		cache = {}
		self.turn.distanceCache = cache
	end
	local key = loc.str .. ">" .. target.charid .. "@" .. target.loc.str
	local d = cache[key]
	if d == nil then
		token:ExecuteWithTheoreticalLoc(loc, function()
			d = token:Distance(target)
		end)
		cache[key] = d
	end
	return d
end

--Line of sight (0..1) from token standing at loc to target.
function MonsterAI:LineOfSightFromLoc(token, loc, target)
	local cache = self.turn.losCache
	if cache == nil then
		cache = {}
		self.turn.losCache = cache
	end
	local key = (loc ~= nil and loc.str or token.loc.str) .. ">" .. target.charid .. "@" .. target.loc.str
	local v = cache[key]
	if v == nil then
		local fn = function()
			local ok, result = pcall(function() return token:GetLineOfSight(target) end)
			v = ok and type(result) == "number" and result or 1
		end
		if loc == nil or loc.str == token.loc.str then
			fn()
		else
			token:ExecuteWithTheoreticalLoc(loc, fn)
		end
		cache[key] = v
	end
	return v
end

--Forget cached distances and sight lines: the board changed.
function MonsterAI:BoardChanged()
	self.turn.distanceCache = nil
	self.turn.losCache = nil
end

---------------------------------------------------------------------------
--Casting. Every ability goes through the d20 rules' own Cast, exactly as a
--player's cast from the action bar, so its resources, rolls and effects
--are the rules' own. The AI's thread is a coroutine, so Cast runs the cast
--inline and returns when it is done; rolls asked of other creatures are
--waited on by AwaitRollRequest below.
---------------------------------------------------------------------------

function MonsterAI.TargetsLogName(targets)
	local names = {}
	for _,target in ipairs(targets or {}) do
		if target.token ~= nil then
			names[#names+1] = MonsterAI.TokenLogName(target.token)
		elseif target.loc ~= nil then
			names[#names+1] = target.loc.str
		end
	end
	return table.concat(names, ", ")
end

--- options: symbols, costOverride, targetArea, alreadyPaid, reason
function MonsterAI:ExecuteAbility(token, ability, targets, options)
	options = options or {}
	targets = targets or {}
	if not MonsterAI.TokenIsLiveCombatant(token) then
		return false
	end

	local done = false
	local castOptions = {
		symbols = options.symbols or {},
		costOverride = options.costOverride,
		targetArea = options.targetArea,
		alreadyPaid = options.alreadyPaid,
		OnFinishCastHandlers = {
			function()
				done = true
			end,
		},
	}

	self:LogDecision("CAST", {
		actor = MonsterAI.TokenLogName(token),
		ability = ability.name,
		targets = MonsterAI.TargetsLogName(targets),
		reason = options.reason,
		alreadyPaid = options.alreadyPaid or nil,
	})

	local activityId = dmhub.GenerateGuid()
	local previousActivity = creature.GetAIActivityInProgress()
	creature.SetAIActivityInProgress(activityId)
	local ok, err = pcall(function()
		ability:Cast(token, targets, castOptions)
	end)
	creature.SetAIActivityInProgress(previousActivity)
	if not ok then
		self:LogDecision("CAST ERROR", {
			actor = MonsterAI.TokenLogName(token),
			ability = ability.name,
			reason = tostring(err),
		})
		return false
	end

	--A cast that went off into its own coroutine (it was not run inline)
	--reports through OnFinishCast. One that was canceled never does, so stop
	--waiting once nothing is casting and no roll dialog is open.
	local start = dmhub.Time()
	local quietSince = nil
	while not done do
		if MonsterAI.StopRequested() then
			break
		end
		local busy = ActivatedAbility.IsCasting()
		pcall(function()
			if gamehud ~= nil and gamehud.rollDialog ~= nil and gamehud.rollDialog.data.IsShown() then
				busy = true
			end
		end)
		if busy then
			quietSince = nil
		else
			quietSince = quietSince or dmhub.Time()
			if dmhub.Time() - quietSince > 2 then
				self:LogDecision("CAST UNFINISHED", {
					actor = MonsterAI.TokenLogName(token),
					ability = ability.name,
					reason = "nothing is casting any more; treating the cast as over",
				})
				break
			end
		end
		if dmhub.Time() - start > 600 then
			break
		end
		coroutine.yield(0.1)
	end

	self:BoardChanged()
	MonsterAI.NoteTokenPositions()
	MonsterAI.Sleep(0.35)
	return true
end

--Wait for rolls a cast by an AI creature asked of other creatures (saving
--throws, contests), naming who is being waited on, then accept the result.
--Called by ActivatedAbility.AwaitCastRollRequest through creature.AIAwaitRollRequest.
function MonsterAI.AwaitRollRequest(casterToken, actionid, resultTable)
	resultTable = resultTable or {}
	local ai = MonsterAI.new{}
	local action = dmhub.GetPlayerActionRequest(actionid)
	local start = dmhub.Time()
	while action ~= nil do
		local incomplete = nil
		for tokid,actionInfo in pairs(action.info.tokens) do
			if actionInfo.status ~= "complete" and actionInfo.status ~= "cancel" then
				incomplete = incomplete or tokid
			end
		end

		if incomplete == nil then
			resultTable.result = true
			resultTable.action = action
			dmhub.CancelActionRequest(actionid)
			MonsterAI.ClearWaiting()
			return resultTable
		end

		local waitedOn = dmhub.GetTokenById(incomplete)
		if waitedOn ~= nil and waitedOn.playerControlled and dmhub.Time() - start > 0.5 then
			local what = "roll"
			pcall(function()
				local checks = action.info.checks
				if checks ~= nil and checks[1] ~= nil then
					what = checks[1]:Describe(true)
				end
			end)
			MonsterAI.SetWaiting("roll", string.format("Waiting for %s: %s", MonsterAI.DisplayName(waitedOn), what), {charid = waitedOn.charid})
		end

		if mod.unloaded or (not MonsterAI.active and dmhub.Time() - start > 5) then
			break
		end
		coroutine.yield(0.2)
		action = dmhub.GetPlayerActionRequest(actionid)
	end

	MonsterAI.ClearWaiting()
	if action ~= nil then
		dmhub.CancelActionRequest(actionid)
	end
	resultTable.result = false
	ai:LogDecision("ROLL REQUEST ABANDONED", {reason = "the AI stopped while waiting"})
	return resultTable
end

---------------------------------------------------------------------------
--Choosing and executing moves.
---------------------------------------------------------------------------

--The tactic profile for a token (MonsterAITactics.lua fills in defaults).
function MonsterAI:Tactics(token)
	if MonsterAI.TacticsFor ~= nil then
		return MonsterAI.TacticsFor(token)
	end
	return {}
end

--Every move this token may use now, scored. Returns a list of
--{move, score, plan}, best first.
function MonsterAI:ScoreMoves(token, ctx, categories)
	local monsterType = MonsterAI.MonsterTypeName(token)
	local results = {}
	for _,id in ipairs(MonsterAI.moveOrder) do
		local move = MonsterAI.moves[id]
		if move ~= nil and (categories == nil or categories[move.category])
			and MonsterAI.MonsterMatches(token, move.monsters)
			and not MonsterAI.MoveDisabled(monsterType, id) then
			local ok, score, plan = pcall(move.score, self, token, ctx)
			if not ok then
				self:LogDecision("MOVE SCORE ERROR", {
					actor = MonsterAI.TokenLogName(token),
					move = id,
					reason = tostring(score),
				})
			elseif type(score) == "number" and score > 0 then
				results[#results+1] = {move = move, score = score, plan = plan}
			end
		end
	end
	table.sort(results, function(a,b) return a.score > b.score end)
	return results
end

--Pick the best move and do it. Returns true if a move was made.
function MonsterAI:FindAndExecuteMove(token, ctx, categories)
	local scored = self:ScoreMoves(token, ctx, categories)
	if #scored == 0 then
		return false
	end

	local alternatives = {}
	for i=2,math.min(4, #scored) do
		alternatives[#alternatives+1] = string.format("%s(%.2f)", scored[i].move.id, scored[i].score)
	end

	local best = scored[1]
	self:LogDecision("MOVE CHOSEN", {
		actor = MonsterAI.TokenLogName(token),
		move = best.move.id,
		score = best.score,
		plan = best.plan ~= nil and best.plan.description or nil,
		alternatives = #alternatives > 0 and table.concat(alternatives, " ") or nil,
	})

	if MonsterAI.AwaitPlanPreview ~= nil then
		local proceed = MonsterAI.AwaitPlanPreview(self, token, best.move, best.plan)
		if proceed == "skip" then
			self.turn.skipped = self.turn.skipped or {}
			self.turn.skipped[best.move.id] = true
			return true
		elseif not proceed then
			self.turn.aborted = "preview stopped"
			return false
		end
	end

	local ok, err = self:RunYieldingFunction(function()
		best.move.execute(self, token, best.plan, ctx)
	end)
	if not ok then
		self:LogDecision("MOVE ERROR", {
			actor = MonsterAI.TokenLogName(token),
			move = best.move.id,
			reason = tostring(err),
		})
		self.turn.failedMoves = self.turn.failedMoves or {}
		self.turn.failedMoves[best.move.id] = (self.turn.failedMoves[best.move.id] or 0) + 1
	end
	self:BoardChanged()
	return true
end

--Play one creature's whole turn.
function MonsterAI:PlayTurn(token)
	self.token = token
	self.turn = {startLoc = token.loc, cycles = 0}

	if not MonsterAI.TokenIsLiveCombatant(token) then
		self:LogDecision("TURN SKIPPED", {actor = MonsterAI.TokenLogName(token), reason = "dead"})
		return
	end

	local incapacitated, why = MonsterAIRules.IsIncapacitated(token)
	if incapacitated then
		self:LogDecision("TURN SKIPPED", {actor = MonsterAI.TokenLogName(token), reason = why})
		return
	end

	creature.BeginAIControl(token.charid, function(casterToken, ability, symbols, options)
		return MonsterAI.HandlePrompt(self, casterToken, ability, symbols, options)
	end)

	local ok, err = self:RunYieldingFunction(function()
		self:LogDecision("TURN START", {
			actor = MonsterAI.TokenLogName(token),
			hp = string.format("%d/%d", token.properties:CurrentHitpoints(), token.properties:MaxHitpoints()),
			loc = token.loc.str,
		})
		self:FocusCameraOnActor(token)
		MonsterAI.status = string.format("Playing %s", MonsterAI.DisplayName(token))

		if MonsterAI.BeginTurnHook ~= nil then
			MonsterAI.BeginTurnHook(self, token)
		end

		local maxCycles = 8
		while self.turn.cycles < maxCycles do
			self.turn.cycles = self.turn.cycles + 1
			if MonsterAI.StopRequested() or self.turn.aborted or not MonsterAI.TokenIsLiveCombatant(token) then
				break
			end
			local ctx = MonsterAIGeneric.BuildContext(self, token)
			if not self:FindAndExecuteMove(token, ctx, MonsterAI.turnCategories) then
				break
			end
			MonsterAI.Sleep(0.25)
		end

		if MonsterAI.EndTurnHook ~= nil and MonsterAI.TokenIsLiveCombatant(token) then
			MonsterAI.EndTurnHook(self, token)
		end
	end)

	creature.EndAIControl(token.charid)
	MonsterAI.ClearWaiting()

	if not ok then
		self:LogDecision("TURN ERROR", {actor = MonsterAI.TokenLogName(token), reason = tostring(err)})
	end
	self:LogDecision("TURN END", {actor = MonsterAI.TokenLogName(token), cycles = self.turn.cycles})
end

MonsterAI.turnCategories = {
	["Action"] = true,
	["Bonus Action"] = true,
	["Movement"] = true,
	["Free"] = true,
}

---------------------------------------------------------------------------
--Prompts an ability raises mid-cast (an invoked ability that wants targets,
--the next target of a sequentially targeted ability).
---------------------------------------------------------------------------

function MonsterAI.HandlePrompt(ai, casterToken, ability, symbols, options)
	ai = ai or MonsterAI.new{}
	for i=#MonsterAI.prompts,1,-1 do
		local prompt = MonsterAI.prompts[i]
		local matchesAbility = prompt.abilities == nil
		for _,name in ipairs(prompt.abilities or {}) do
			if string.lower(name) == string.lower(ability.name or "") then
				matchesAbility = true
			end
		end
		if matchesAbility and MonsterAI.MonsterMatches(casterToken, prompt.monsters) then
			local result = prompt.handler(ai, casterToken, ability, symbols, options)
			if result ~= nil then
				ai:LogDecision("PROMPT ANSWERED", {
					actor = MonsterAI.TokenLogName(casterToken),
					ability = ability.name,
					result = type(result) == "table" and MonsterAI.TargetsLogName(result.targets) or tostring(result),
				})
				return result
			end
		end
	end
	return nil
end

---------------------------------------------------------------------------
--Hooks into the d20 rules (see Creature.lua "Monster AI hooks").
---------------------------------------------------------------------------

--While the AI runs on this client, it rolls for every creature it plays.
creature.AIRollsForCreature = function(c)
	if c == nil then
		return false
	end
	local token = dmhub.LookupToken(c)
	if token == nil then
		return false
	end
	if creature.IsTokenAIControlled(token.charid) then
		return true
	end
	return MonsterAI.active and MonsterAI.SettingOn("autosaves") and MonsterAI.IsAIPlayed(token)
end

creature.AIAwaitRollRequest = function(casterToken, actionid, resultTable)
	return MonsterAI.AwaitRollRequest(casterToken, actionid, resultTable)
end

creature.AIPromptCallbackForToken = function(token)
	if not MonsterAI.active or not MonsterAI.IsAIPlayed(token) then
		return nil
	end
	return function(casterToken, ability, symbols, options)
		return MonsterAI.HandlePrompt(nil, casterToken, ability, symbols, options)
	end
end
