local mod = dmhub.GetModLoading()

--Settings DMHub defines for the shared code synced from the Draw Steel Codex
--(see CODEX_SYNC.md). The Codex keeps these in its DMHub Titlescreen/Settings.lua,
--which d20 does not sync; d20 used to define them in DMHub Core UI/SettingsGui.lua,
--which is now the Codex's. Copied unchanged from that d20 file. Several are read
--only by the engine (the canopy cutaway, the brush sizes, strict movement).
--In DMHub Titlescreen so they exist from the cold-boot title screen on.

--The current engine reads these settings, but nothing in the 5e mod set
--defines them (in Draw Steel they come from newer modules). Register them
--here with the same defaults so the reads work.
setting{
	id = "canopy:defaultradius",
	description = "Default Canopy Cutaway Radius",
	help = "Fallback cutaway radius (in tiles) used when a canopy-flagged object has no canopy layer above it. Set negative to disable the fallback cutaway.",
	storage = "game",
	section = "Map",
	editor = "slider",
	format = "F0",
	default = 3,
	min = -1,
	max = 40,
}

setting{
	id = "canopy:defaultfade",
	description = "Default Canopy Cutaway Fade",
	help = "Fallback cutaway fade width (in tiles) used when a canopy-flagged object has no canopy layer above it.",
	storage = "game",
	section = "Map",
	editor = "slider",
	format = "F1",
	default = 1,
	min = 0,
	max = 2,
}

setting{
	id = "canopy:defaultminopacity",
	description = "Default Canopy Minimum Opacity",
	help = "Fallback minimum opacity used when a canopy-flagged object has no canopy layer above it. 0 means fully transparent at the token.",
	storage = "game",
	section = "Map",
	editor = "slider",
	format = "F2",
	default = 0,
	min = 0,
	max = 1,
}

--The roll dialog's DM preroll checkbox reads this. It was never registered
--anywhere, so register it here to make the value save properly.
setting{
	id = "preroll",
	default = false,
	storage = "preference",
}

--The synced ModShare.lua reads this to decide whether to offer the Encounter
--of the Week module type. The Codex defines it in Codex
--Titlescreen/EncounterOfTheWeek.lua, which d20 does not have, so every read
--logged "Could not find setting". Encounter of the Week is a Draw Steel game
--mode, so register it here permanently off, with no editor so it never shows.
setting{
	id = "dev:encounteroftheweek",
	default = false,
	storage = "preference",
}

--Privacy toggle read by analytics helpers before sending any usage data.
setting{
	id = "telemetry_enabled",
	description = "Send Anonymous Usage Data",
	help = "Help improve DMHub by sending anonymous usage statistics. No personal information is collected.",
	storage = "preference",
	section = "General",
	editor = "check",
	default = true,
}

setting{
	id = "tileheight:overlay",
	description = "Show Tile Height Overlay",
	help = "Draws contour lines and integer labels showing the game-rules height of each tile on the current floor.",
	storage = "preference",
	section = "Map",
	editor = "check",
	default = false,
}

setting{
	id = "strict:movement",
	description = "Strictly Enforce Forced Movement Rules",
	help = "When enabled, players (and a GM viewing as a player) can only place forced movement (push, pull, slide, knockback) on legally reachable tiles.",
	storage = "game",
	editor = "check",
	default = false,
	section = "Game",
}

setting{
	id = "walls:indestructible",
	description = "Indestructible Walls",
	help = "When enabled, forced movement cannot break through walls, regardless of their solidity.",
	classes = {"dmonly"},
	section = "Game",
	default = false,
	storage = "game",
	editor = "check",
}

--Brush sizes for the map editing tools. No settings-dialog editor on
--purpose; the editing UI adjusts them, they just need to exist.
setting{
	id = "terrainbrushsize",
	default = 1,
	storage = "preference",
}

setting{
	id = "effectsbrushsize",
	default = 1,
	storage = "preference",
}

setting{
	id = "buildingbrushsize",
	default = 1,
	storage = "preference",
}

--Defined in the Codex's DMHub Titlescreen/Settings.lua and read by the synced
--code; neither the engine nor d20 defined them. Copied from the Codex.

setting{
    id = "lookup",
    description = "Creature is Lookiong Up",
    storage = "transient",
    default = 0,
}

--Gates the Patreon feature: the Patreon tab in the module browser and the
--Patreon/email sections of the account settings. On by default now that the
--feature ships; no editor field, so it never appears in the settings menus.
--Turn it off for a session with /set patreonsub false. Remove this setting
--once the gating is no longer needed at all.
setting{
    id = "patreonsub",
    description = "Show the Patreon features.",
    storage = "preference",
    default = true,
}

setting{
    id = "showmovementcrosssection",
    description = "Show Movement Cross-Section",
    help = "When dragging a token, show a small side-on cross-section diagram in the movement tooltip illustrating the vertical profile of the move (slopes, walls climbed or flown over, falls, and other tokens the path crosses). Turn this off to always show the plain text tooltip.",
    storage = "preference",
    section = "General",
    editor = "check",
    default = true,
}

setting{
    id = "redactdirectorlocation",
    description = "Redact DM Location",
    help = "When on, DMs' rich-status/location is hidden in the party and User Status panels for everyone in the game; only Online/Away/Offline is shown for DM users.",
    storage = "game",
    section = "General",
    editor = "check",
    default = true,
}

setting{
	id = "measure:distances",
	description = "Distances",
	storage = "preference",

	editor = "dropdown",
	default = "ignorediagonals",

	-- Only relevant for the Ruler and Cross Section when snapping to the grid,
	-- since the choice only affects how diagonal grid steps are counted (both
	-- report tile-stepping distances). Without snapping they already report the
	-- straight-line (Euclidean) length. Hidden on hex maps: hexes have no
	-- diagonals, so the engine always counts whole hexes there.
	monitorVisible = {'measure:shape', 'measure:snap', 'maplayout:tiletype', 'maplayout:stagger'},
	visible = function()
		local shape = dmhub.GetSettingValue('measure:shape')
		if (shape ~= "ruler" and shape ~= "crosssection") or dmhub.GetSettingValue('measure:snap') == "none" then
			return false
		end
		--This file loads before DMHub Game Rules (at the title screen), so look it up at call time.
		local measurement = rawget(_G, "MeasurementSystem")
		return measurement == nil or not measurement.IsHexMap()
	end,

	enum = {
		{
			value = "ignorediagonals",
			text = "Ignore Diagonals",
		},
		{
			value = "euclidean",
			text = "Euclidean",
		},
	},
}

setting{
    id = "strict:resources",
    description = "Strictly Enforce Action Economy and Resource Costs",
    storage = "game",
    editor = "check",
    default = false,
	section = "GameStrictRules",
}

setting{
    id = "strict:rolls",
    description = "Strictly Enforce Rolls",
    help = "When enabled, a roll's result stands: players (and a GM viewing as a player) cannot re-roll, edit the dice expression, click a tier row to override the outcome, or change which modifiers were applied -- and only the modifiers that actually apply are listed. Backing out of an ability with the card's close button is also refused once its cost has been paid. The DM is never restricted.",
    storage = "game",
    editor = "check",
    default = false,
    section = "GameStrictRules",
}

setting{
    id = "strict:autoadjudicate",
    description = "Automatic Rule Adjudication",
    help = "When enabled, the game decides rules questions that would otherwise be left to the table, instead of prompting. Applies to the DM as well as players.",
    storage = "game",
    editor = "check",
    default = false,
    section = "GameStrictRules",
}

--The map overlay, split into layers. Each is also reachable from the map
--overlay menu on the title bar's terrain chip (see CodexTitleBar), which
--additionally lists a per-zone-type toggle for every zone type present on the
--current map. Players only see overlay information on tiles currently inside
--their vision.
setting{
    id = "mapoverlay:walls",
    description = "Show Walls",
    help = "Draws the map's walls as lines colored by the cover they grant: black for full cover, greys for partial cover.",
    storage = "preference",
    section = "Map",
    editor = "check",
    default = false,
}

--Patreon account link, shown in Settings > Account. A player links their own
--Patreon here so creator content they support (map packs gated by a creator's
--Patreon, such as Tehox Maps) unlocks in DMHub. Adapted from the Codex's
--CreatePatreonAccountPanel (DMHub Titlescreen/SettingsScreen.lua), which d20 does
--not sync. The settings screen is the engine's settings-screen.txt; it builds
--every function in SettingsScreenAccountSections into its Account tab.
--
--Server side: DMHub's own copies of the Codex's Patreon functions (patreonAuthStart,
--patreonStatus, patreonUnlink, patreonRefreshOrgEntitlements on dmtool-cad62).
--net.Post adds {userid, secretid}, which is how those functions identify the user.
local function CreatePatreonAccountSection()
	local panel
	local m_finished = true  --true when no link attempt is waiting on the browser

	local ShowUnlinked
	local ShowLinked
	local RefreshStatus

	local function Heading()
		return gui.Label{
			width = "auto",
			height = "auto",
			fontSize = 16,
			bold = true,
			text = "Patreon",
		}
	end

	local function Text(text, extra)
		local args = {
			width = "auto",
			height = "auto",
			maxWidth = 600,
			fontSize = 14,
			vmargin = 2,
			text = text,
		}
		for k,v in pairs(extra or {}) do
			args[k] = v
		end
		return gui.Label(args)
	end

	local function Button(text, width, click)
		return gui.Button{
			width = width,
			height = 30,
			fontSize = 14,
			halign = "left",
			vmargin = 4,
			text = text,
			click = click,
		}
	end

	--The creators this Patreon account unlocks content from, live off /Patrons.
	--Gate on entitled, not active: a creator can let access persist after a lapse.
	local function EntitledOrgRows()
		local rows = {}
		for _,entry in ipairs(dmhub.patreonOrgEntitlements or {}) do
			if entry.entitled then
				local suffix = "access kept after your pledge ended"
				if entry.active then
					suffix = "active"
				end
				local orgid = entry.orgid
				local label
				label = Text(string.format("%s   <color=#999999>(%s)</color>", orgid, suffix), {
					markdown = true,
					create = function(element)
						--show the creator's name rather than the internal org id.
						module.GetOrganizationInfo{
							orgid = orgid,
							success = function(info)
								local name = (info.patreonCampaign and info.patreonCampaign.name) or info.displayName
								if label.valid and name ~= nil and name ~= "" then
									label.text = string.format("%s   <color=#999999>(%s)</color>", name, suffix)
								end
							end,
							failure = function(msg) end,
						}
					end,
				})
				rows[#rows+1] = label
			end
		end
		if #rows == 0 then
			return { Text("No creator content unlocked yet. Supporting a creator on Patreon unlocks their content here automatically.", {italics = true, color = "#999999"}) }
		end
		table.insert(rows, 1, Text("Creator content you have access to", {bold = true}))
		return rows
	end

	--ask patreonAuthStart for the Patreon sign-in page, open it in the browser,
	--then poll patreonStatus every 4s (180s limit) until the callback records it.
	local function BeginLink()
		m_finished = false
		local function Expired()
			return m_finished or mod.unloaded or panel == nil or not panel.valid
		end
		local function Failed(msg)
			m_finished = true
			ShowUnlinked(msg)
		end
		local function Progress(text)
			panel.children = {
				Heading(),
				Text(text, {italics = true}),
				Button("Cancel", 120, function(element) RefreshStatus() end),
			}
		end

		local deadline = 0
		local Tick
		Tick = function()
			if Expired() then
				return
			end
			net.Post{
				url = dmhub.cloudFunctionsBaseUrl .. "/patreonStatus",
				data = {},
				success = function(data)
					if Expired() then
						return
					end
					if type(data) == "table" and data.ok and data.linkConflict == "cancelled" then
						Failed("Linking cancelled. Your Patreon account is still linked to your other DMHub account.")
						return
					end
					if type(data) == "table" and data.ok and data.linkConflict == "pending" then
						Progress("This Patreon account is linked to another DMHub account. Confirm or cancel in your browser.")
						deadline = math.max(deadline, dmhub.Time() + 60)
						dmhub.Schedule(4, Tick)
						return
					end
					if type(data) == "table" and data.ok and data.linked then
						m_finished = true
						ShowLinked(data)
						return
					end
					if dmhub.Time() > deadline then
						Failed("Linking timed out. Try again after finishing in your browser.")
						return
					end
					dmhub.Schedule(4, Tick)
				end,
				error = function(msg)
					if Expired() then
						return
					end
					if dmhub.Time() > deadline then
						Failed("Linking timed out. Try again after finishing in your browser.")
						return
					end
					dmhub.Schedule(4, Tick)
				end,
			}
		end

		Progress("Opening Patreon in your browser...")
		net.Post{
			url = dmhub.cloudFunctionsBaseUrl .. "/patreonAuthStart",
			data = {},
			success = function(data)
				if Expired() then
					return
				end
				if type(data) == "table" and data.ok and type(data.authorizeUrl) == "string" then
					dmhub.OpenURL(data.authorizeUrl)
					Progress("Waiting for you to finish linking Patreon in your browser...")
					deadline = dmhub.Time() + 180
					Tick()
				else
					local err = "Could not start the link. Please try again."
					if type(data) == "table" and type(data.error) == "string" then
						err = data.error
					end
					Failed(err)
				end
			end,
			error = function(msg)
				if Expired() then
					return
				end
				Failed("Could not contact the server. Please try again.")
			end,
		}
	end

	ShowLinked = function(data)
		local children = { Heading() }
		local text = "Connected to Patreon"
		if (data.linkedAt or 0) > 0 then
			text = string.format("%s   linked %s", text, os.date("%d %b %Y", math.floor(data.linkedAt / 1000)))
		end
		children[#children+1] = Text(text)

		--a link made without the identity.memberships permission cannot see which
		--creators the user supports. nil means the server has not answered yet.
		if data.hasMemberships == false then
			children[#children+1] = Text("Patreon needs a new permission to see which creators you support. Until you reconnect, new creator memberships will not unlock content here.", {color = "#e0b050"})
			children[#children+1] = Button("Reconnect Patreon", 200, function(element) BeginLink() end)
		end

		for _,row in ipairs(EntitledOrgRows()) do
			children[#children+1] = row
		end

		--backstop for a missed Patreon notification: re-reads memberships server-side.
		children[#children+1] = Button("Check for new content", 190, function(element)
			element.text = "Checking..."
			element.interactable = false
			net.Post{
				url = dmhub.cloudFunctionsBaseUrl .. "/patreonRefreshOrgEntitlements",
				data = {},
				success = function(response)
					if panel.valid then
						RefreshStatus()
					end
				end,
				error = function(msg)
					if element.valid then
						element.text = "Check for new content"
						element.interactable = true
					end
				end,
			}
		end)

		children[#children+1] = Button("Disconnect Patreon", 190, function(element)
			local errorLabel = Text("", {classes = {"collapsed"}, color = "#ff6666"})
			panel.children = {
				Heading(),
				Text("Disconnect your Patreon account? You will lose any creator content your memberships unlock until you link it again."),
				gui.Panel{
					flow = "horizontal",
					width = "auto",
					height = "auto",
					Button("Confirm Disconnect", 180, function(confirm)
						confirm.text = "Disconnecting..."
						confirm.interactable = false
						net.Post{
							url = dmhub.cloudFunctionsBaseUrl .. "/patreonUnlink",
							data = {},
							success = function(response)
								if not panel.valid then
									return
								end
								if type(response) == "table" and response.ok then
									RefreshStatus()
								else
									confirm.text = "Confirm Disconnect"
									confirm.interactable = true
									errorLabel.text = "Could not disconnect. Please try again."
									errorLabel:SetClass("collapsed", false)
								end
							end,
							error = function(msg)
								if not panel.valid then
									return
								end
								confirm.text = "Confirm Disconnect"
								confirm.interactable = true
								errorLabel.text = "Could not contact the server. Please try again."
								errorLabel:SetClass("collapsed", false)
							end,
						}
					end),
					gui.Panel{ width = 8, height = 1 },
					Button("Cancel", 120, function(cancel) ShowLinked(data) end),
				},
				errorLabel,
			}
		end)

		panel.children = children
	end

	ShowUnlinked = function(message)
		local children = {
			Heading(),
			Text("Link your Patreon account to unlock content from creators you support. We only read which creators you support - never payment details."),
		}
		if message ~= nil then
			children[#children+1] = Text(message, {color = "#ff6666"})
		end
		children[#children+1] = Button("Link Patreon Account", 200, function(element) BeginLink() end)
		panel.children = children
	end

	--render the live /Patrons mirror at once, then let patreonStatus confirm it,
	--so opening the tab does not wait on a cloud function cold start.
	RefreshStatus = function()
		m_finished = true
		local id = dmhub.patreonUserId
		if id ~= nil and id ~= "" then
			ShowLinked{ linked = true, patreonUserId = id, linkedAt = dmhub.patreonLinkedAt }
		else
			panel.children = { Heading(), Text("Checking Patreon...", {italics = true}) }
		end
		net.Post{
			url = dmhub.cloudFunctionsBaseUrl .. "/patreonStatus",
			data = {},
			success = function(data)
				if not panel.valid or not m_finished then
					return
				end
				if type(data) == "table" and data.ok and data.linked then
					ShowLinked(data)
				else
					ShowUnlinked(nil)
				end
			end,
			error = function(msg)
				if not panel.valid or not m_finished then
					return
				end
				ShowUnlinked("Could not check Patreon status.")
			end,
		}
	end

	panel = gui.Panel{
		flow = "vertical",
		width = "100%",
		height = "auto",
		create = function(element)
			RefreshStatus()
		end,
	}
	return panel
end

--SettingsScreenAccountSections is created by the engine's settings-screen.txt.
--rawget: on an engine without it, reading the global would raise. Replaces the
--entry a previous load of this file added, so a Lua reload does not double it.
local accountSections = rawget(_G, "SettingsScreenAccountSections")
if accountSections ~= nil then
	local previous = rawget(_G, "g_dmhubPatreonAccountSection")
	local replaced = false
	for i,fn in ipairs(accountSections) do
		if previous ~= nil and fn == previous then
			accountSections[i] = CreatePatreonAccountSection
			replaced = true
		end
	end
	if not replaced then
		accountSections[#accountSections+1] = CreatePatreonAccountSection
	end
	g_dmhubPatreonAccountSection = CreatePatreonAccountSection
end

--Local Assets (dev only). The Codex defines these in its own DMHub
--Titlescreen/Settings.lua and edits them through a custom section of its
--settings screen, neither of which d20 syncs. The engine reads them in
--LocalAssetDirectory.MaybeActivate: when localassets:dirs is set for a game,
--the game's cloud assets are replaced by the YAML tree in those directories,
--in-game edits are written back to the files, and edits made on disk
--hot-reload. Same ids, storage and defaults as the Codex. d20 has no text
--editor for settings, so they are set with the /localassets macro below.
--
--localassets:dir is the older single-directory form, superseded by
--localassets:dirs when that is non-empty; kept so the engine's fallback read
--resolves.
setting{
	id = "localassets:dir",
	description = "Local Assets Directory (dev)",
	storage = "pergamepreference",
	default = "",
}

--Ordered list of directories, newline-delimited. The first entry has the
--highest precedence and receives newly created entries.
setting{
	id = "localassets:dirs",
	description = "Local Assets Directories (dev)",
	storage = "pergamepreference",
	default = "",
}

--Global: the Encounter of the Week directory list. Unused by d20, but the
--engine reads it on every game load.
setting{
	id = "localassets:eotwdirs",
	description = "Encounter of the Week Asset Directories (dev)",
	storage = "preference",
	default = "",
}

--Global: explicit path to git for the local-assets git status badges. Empty
--means auto-detect.
setting{
	id = "localassets:gitpath",
	description = "Git Executable for Local Assets (dev)",
	storage = "preference",
	default = "",
}

--/localassets and /exportassets, adapted from the Codex's Codex Macros. This
--file loads with DMHub Titlescreen, before Commands.RegisterMacro exists
--(DMHub Utils), so they register a moment later, as ThemeEngine.lua does.
dmhub.Schedule(0.1, function()
	if mod.unloaded or rawget(_G, "Commands") == nil or Commands.RegisterMacro == nil then
		return
	end

	Commands.RegisterMacro{
		name = "localassets",
		summary = "use local directories for this game's assets",
		doc = "Usage: /localassets <path> | off | (no args to show status)\nSets a per-game developer preference pointing at a local directory of YAML asset files. When set, the game's cloud assets are ignored: assets load from the directory, edits are written back to it as YAML, and external file changes hot-reload into the game. If the directory does not exist it is created and populated from the game's current assets on next load. Takes effect on the next game load. Separate several directories with ; (the first has the highest precedence). Dev only.",
		command = function(str)
			if not devmode() then
				print("localassets: developer mode only.")
				return
			end
			str = (str or ""):match("^%s*(.-)%s*$")
			if str == "" then
				local status = dmhub.LocalAssetsStatus()
				local pref = dmhub.GetSettingValue("localassets:dirs")
				if pref == nil or pref == "" then
					pref = dmhub.GetSettingValue("localassets:dir")
				end
				if status ~= nil and status.active then
					if status.directories ~= nil and #status.directories > 1 then
						print(string.format("localassets: ACTIVE, %d directories (top first):", #status.directories))
						for i,dir in ipairs(status.directories) do
							print(string.format("  %d. %s", i, dir))
						end
					else
						print(string.format("localassets: ACTIVE, using %s", status.directory))
					end
					if status.reloadRequired then
						print("localassets: the configured directory list has changed; reload the game to apply.")
					end
				elseif pref ~= nil and pref ~= "" then
					print(string.format("localassets: set to %s (takes effect on next game load)", (pref:gsub("\n", " ; "))))
				else
					print("localassets: not set for this game. Usage: /localassets <path> | off")
				end
			elseif str == "off" then
				dmhub.SetSettingValue("localassets:dirs", "")
				dmhub.SetSettingValue("localassets:dir", "")
				print("localassets: disabled. Reload the game to return to cloud assets.")
			else
				local dirs = {}
				for dir in str:gmatch("[^;]+") do
					dir = dir:match("^%s*(.-)%s*$")
					if dir ~= "" then
						dirs[#dirs+1] = dir
					end
				end
				local value = table.concat(dirs, "\n")
				dmhub.SetSettingValue("localassets:dirs", value)
				dmhub.SetSettingValue("localassets:dir", "")
				print(string.format("localassets: set to %s. Reload the game to activate.", (value:gsub("\n", " ; "))))
			end
		end,
	}

	Commands.RegisterMacro{
		name = "exportassets",
		summary = "export all game assets to yaml",
		doc = "Usage: /exportassets [directory]\nExports ALL asset categories of this game (compendium tables, monsters, images, audio, objects, etc.) to a YAML directory tree -- the format used by /localassets. With no directory, exports to the active local assets directory if one is set, else to the compendium/assets folder. Never export onto a git checkout you have not committed. Dev only.",
		command = function(str)
			if not devmode() then
				print("exportassets: developer mode only.")
				return
			end
			local options = {}
			str = (str or ""):match("^%s*(.-)%s*$")
			if str ~= "" then
				options.directory = str
			end
			local result = dmhub.ExportAllAssets(options)
			if result == nil then
				print("exportassets: could not resolve export directory")
			else
				print(string.format("exportassets: exported %d items in %d categories to %s", result.itemsExported, result.categoriesExported, result.directory))
			end
		end,
	}
end)
