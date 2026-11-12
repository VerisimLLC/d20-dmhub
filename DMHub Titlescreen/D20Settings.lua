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
