local mod = dmhub.GetModLoading()

-- d20 adapter for the Map Markup zone-type model. The source panel is shared
-- with Draw Steel, where EnvironmentalKeyword lives in Draw Steel Core Rules.
-- d20 has no such type, so initialize its system-neutral portion lazily after
-- CharacterFeature, Aura, and Compendium have loaded.
DMHubMapMarkupD20 = rawget(_G, "DMHubMapMarkupD20") or {}

function DMHubMapMarkupD20.EnsureEnvironmentalKeyword()
    if rawget(_G, "EnvironmentalKeyword") ~= nil then
        return EnvironmentalKeyword
    end
    if rawget(_G, "CharacterFeature") == nil
        or rawget(_G, "Aura") == nil
        or rawget(_G, "Compendium") == nil then
        return nil
    end

    --This file implements Environmental Keywords: named environmental conditions
    --(e.g. "Dark", "Lava") that are known to the game and attach one or more
    --CharacterModifiers to any creature affected by them. They are authored in the
    --Compendium under Rules and stored in the "environmentalKeywords" object table.
    --
    --An EnvironmentalKeyword derives from CharacterFeature, so it carries a list of
    --modifiers plus the shared modifier editor (CharacterFeature:EditorPanel). This
    --is the same relationship CharacterCondition has with CharacterFeature.
    
    --- @class EnvironmentalKeyword:CharacterFeature
    --- @field name string Display name of the keyword (e.g. "Dark", "Lava"). Class default "New Environmental Keyword" applies when absent.
    --- @field description string Rules text shown to players. Class default "" applies when absent.
    --- @field tableName string Name of the data table this keyword is stored in ("environmentalKeywords"). Class-level default; often absent on serialized instances.
    --- @field source string Source label ("Environmental Keyword"). Class-level default; often absent on serialized instances.
    --- @field iconid string Icon shown in the UI. Class-level default applies when absent.
    --- @field display table Icon display settings (bgcolor/hueshift/saturation/brightness).
    --- @field difficultTerrain boolean If true, an area marked with this keyword counts as difficult terrain. Uses the same terrain rule flag name as tiles (asset.rules.difficultTerrain).
    --- @field water boolean If true, an area marked with this keyword counts as water. Uses the same terrain rule flag name as tiles (asset.rules.water).
    --- @field concealment boolean If true, an area marked with this keyword grants concealment. Uses the same terrain rule flag name as tiles (asset.rules.concealment).
    --- @field climbable boolean If true, an area marked with this keyword can be climbed, like a climbable wall: creatures in it may climb up to the ceiling of the floor.
    --- @field climbersOnly boolean Only meaningful when climbable is true: restricts climbing to natural climbers (climb speed >= walk speed), matching walls' "Climbable (Climbers Only)". Uses the same terrain rule flag name as tiles (rules.climbersOnly).
    --- @field dynamicLight boolean If true, the Map Markup zone palette offers the "Dynamic Light" option for this keyword (its zones/blanket apply only where the map's light level is below a per-map threshold). Purely a UI/eligibility gate: the sampling and carving live in MapMarkupPanel.lua; unchecking disables an already-configured threshold without deleting it.
    --- @field dispels string[]|nil Ids (environmentalKeywords table keys) of keywords this keyword dispels. Painting a zone of this keyword deletes the overlap from zones of a dispelled keyword (and a dispelled keyword cannot be painted over this one); an aura carrying this keyword suppresses zones of dispelled keywords beneath it for as long as the aura covers them. No class default: assigned per instance by the editor (a class-level default table would be shared-mutable).
    --- @field movedamage string Damage type dealt to creatures moving through an area with this keyword, or "none" for no damage. Uses the same field names as Aura so the values copy straight onto zone auras.
    --- @field damage number Damage dealt per tile of the area a creature moves through (only meaningful when movedamage is not "none").
    --- @field movementDamageFilter string Which movement the damage applies to: "all", "nonshift" (shifting avoids it), or "forced" (forced movement only).
    --- @field powerRollEnabled boolean If true, a 2d10 + powerRollBonus power roll is made against any creature entering the area or starting its turn there. Same field names as Aura; copied onto zone auras.
    --- @field powerRollBonus number The X in the 2d10 + X power roll.
    --- @field powerRollTiers string[]|nil The three power table tier texts (tier 1 = 11 or less, tier 2 = 12-16, tier 3 = 17+). No class default: assigned per instance by the editor.
    --- @field powerRollShiftEntryMode "normal"|"bane"|"ignore" How the simple power roll handles entry during a Shift: normal rolls normally, bane adds one non-stacking bane, and ignore suppresses only the simple power roll for that entry. Same field name as Aura; a non-normal keyword mode is copied additively onto zone auras that do not already have a non-normal mode.
    --- @field includeAdjacent boolean If true, areas marked with this keyword extend one tile outward (8-way): creatures adjacent to the area count as touching it for enter/start-of-turn triggers (the entry power roll fires for them at the start of their turn, with a bane), but adjacent tiles do not take the keyword's terrain rules, move damage, or modifiers. Same field name as Aura; copied onto zone auras.
    --- @field creatureFilter string GoblinScript evaluated against each creature to decide whether the keyword affects it at all. Empty (the class default) affects everyone. Applies to the whole keyword -- modifiers, triggers, the entry power roll, the move damage, AND the terrain rules (difficult terrain, water, concealment, climbable). The terrain half needs the engine: an aura reporting a filter is left out of FloorController.GetTileRulesAtLoc unless the caller names the creature it is asking about, and Aura.ApplyTo consults the filter for everything else, evaluating this script through AuraInstance:CreaturePassesFilterForToken and caching the verdict per creature per game update. Merged onto an aura's own creatureFilter with an "and" rather than skipped like the other fields, because a filter is a restriction -- dropping it would WIDEN who the keyword affects.
    --- @field defaultHeight number|nil Default vertical extent, in tiles above the ground, stamped onto new zones painted with this keyword from the Map Markup panel. 0 = ground only (affects creatures standing in the zone but not flyers above it); N = up to N tiles above the ground; absent = unlimited height. Zone bands are ground-relative, so this follows the terrain over ledges and pits. Only a DEFAULT: each painted zone stores its own height and can be re-set in the Edit Zone dialog. No class default: absent = unlimited.
    --- @field appearance table|nil Optional visual representation drawn on the map for zones of this keyword (beyond the overlay stripes), edited in the Edit Appearance dialog. mode = "floor": {mode, tileid = tilesheet asset id filling the tiles, edgeWallId = wall asset id drawn as a decorative ring around the boundary (nil = none), alpha = fill opacity, fractalEdge = deterministic organic-boundary strength from 0 to 1 (nil = 0), edgeFade = inward fill fade in tiles from 0 to 0.35 (nil = 0), tileImageId/edgeImageId = source image asset ids shown in the dialog's IconEditors (nil when the asset was copied from an existing tilesheet/wall), tileOwned/edgeOwned = true when the asset was created/forked for this keyword (replaced assets are Delete()d)}. Floor fills force the private tilesheet asset to oneLargeTile so the whole image is the repeating unit. mode = "sprites": {mode, sprites = image asset ids, spriteScale = quad size within the tile, spriteAlpha}. Texture scale/hue/saturation/brightness live on the referenced ASSETS, exactly like real floors and walls. MapMarkupPanel stamps this onto zone aura instances (AuraInstance:GetAppearance); the engine's MarkupZoneVisuals renders it resting on the ground, terrain-conformed and parallax-correct. No class default: absent = no visual.
    --- @field appearanceDefaultOff boolean|nil When true, new zones painted with this keyword from the Map Markup panel start with their visual representation hidden (record field hideAppearance; stripes only). Toggled by the "Visuals" pill on the zone palette chip. Only a DEFAULT stamped at paint time: each painted zone owns its own flag afterward (the Visuals badge on its zone-list row), so flipping this never disturbs existing zones. Only meaningful when appearance is set. No class default: absent = visuals shown.
    --- @field script string|nil Optional Lua zone-script source, edited in the Edit Script dialog. When set, one instance of the script runs on EVERY client for each zone of this keyword on the current map (Entire Map blankets included). The source must RETURN a table of handlers, all optional: create(zone), destroy(zone), locsChanged(zone), think(zone), and thinkInterval (seconds between think calls, default 1). destroy is guaranteed to run when the zone is de-instantiated: erased or deleted, its keyword deleted, the map changed, the script edited, or mods reloaded. If locsChanged is absent the script is restarted (destroy then create) whenever the zone's tiles change. The zone object passed to handlers carries zoneid/floorid/floorIndex/mapid, name, keyword (type name), keywordid, color, altitude, height (nil = unlimited), entireMap, locs (list of Loc userdata, ready for e.g. dmhub.CreateWorldDistortion), locsAndAdjacent (locs plus every tile 8-way adjacent to the zone; computed lazily on first read and refreshed when the zone's tiles change) and data (an empty scratch table for script state). No class default: absent = no script.
    --- @field mapid string|nil When set, this keyword is a map-scoped zone type: it was created from that map's Zone Types palette and is hidden from the compendium, other maps' palettes, and keyword dropdowns until promoted ("Make Available to All Maps" clears the field). No class default: absent = a full keyword.
    EnvironmentalKeyword = RegisterGameType("EnvironmentalKeyword", "CharacterFeature")
    
    EnvironmentalKeyword.name = "New Environmental Keyword"
    EnvironmentalKeyword.description = ""
    EnvironmentalKeyword.tableName = "environmentalKeywords"
    EnvironmentalKeyword.source = "Environmental Keyword"
    EnvironmentalKeyword.iconid = "ui-icons/skills/1.png"
    EnvironmentalKeyword.difficultTerrain = false
    EnvironmentalKeyword.water = false
    EnvironmentalKeyword.concealment = false
    EnvironmentalKeyword.climbable = false
    EnvironmentalKeyword.climbersOnly = false
    EnvironmentalKeyword.dynamicLight = false
    EnvironmentalKeyword.movedamage = "none"
    EnvironmentalKeyword.damage = 0
    EnvironmentalKeyword.movementDamageFilter = "all"
    EnvironmentalKeyword.powerRollEnabled = false
    EnvironmentalKeyword.powerRollBonus = 0
    EnvironmentalKeyword.powerRollShiftEntryMode = "normal"
    EnvironmentalKeyword.includeAdjacent = false
    EnvironmentalKeyword.creatureFilter = ""
    
    --Index of keywords by lower-case name, rebuilt whenever tables refresh. Used by
    --runtime code that needs to resolve a keyword from its name.
    EnvironmentalKeyword.keywordsByName = {}
    
    function EnvironmentalKeyword.OnDeserialize(self)
    	if not self:has_key("guid") then
    		self.guid = dmhub.GenerateGuid()
    	end
    end
    
    --- @return EnvironmentalKeyword
    function EnvironmentalKeyword.CreateNew()
    	return EnvironmentalKeyword.new{
    		guid = dmhub.GenerateGuid(),
    		name = "New Environmental Keyword",
    		source = "Environmental Keyword",
    		description = "",
    		modifiers = {},
    		iconid = "ui-icons/skills/1.png",
    		display = {
    			bgcolor = "white",
    			hueshift = 0,
    			saturation = 1,
    			brightness = 1,
    		},
    	}
    end
    
    --- Folds an Environmental Keyword's mechanical effects into an aura definition.
    ---
    --- This is the single place that knows what "an area marked with this keyword"
    --- means mechanically. Both aura-creation paths call it, so a keyword means the
    --- same thing however the area was made:
    ---   * painted map-markup zones (MapMarkup BuildZoneAuraInstance), and
    ---   * ability auras that name a keyword (ActivatedAbilityAuraBehavior:CastOnArea).
    ---
    --- The merge is ADDITIVE ONLY: a keyword can switch an effect on but never off,
    --- and never overwrites a value the aura already specifies. That keeps auras that
    --- spell out their own flags behaving exactly as before (e.g. the shadow elf
    --- darkness auras, which already set concealment directly), and means attaching a
    --- keyword to an existing aura can only ever add to it.
    ---
    --- Deliberately NOT copied: name, iconid, display. Those are the aura's own
    --- identity -- an ability aura keeps the ability's icon and colour, and a zone
    --- aura takes the keyword's separately in BuildZoneAuraInstance.
    ---
    --- @param auraDef Aura The aura definition to mutate. nil is a no-op.
    --- @param keywordid string|nil Id in the environmentalKeywords table. nil, or an id
    ---        that no longer resolves (deleted keyword), is a no-op.
    --- @return Aura|nil auraDef The same definition, for call chaining.
    function EnvironmentalKeyword.ApplyToAura(auraDef, keywordid)
    	if auraDef == nil or keywordid == nil then
    		return auraDef
    	end
    
    	local dataTable = dmhub.GetTable(EnvironmentalKeyword.tableName) or {}
    	local keyword = dataTable[keywordid]
    	if keyword == nil then
    		return auraDef
    	end
    
    	--Stamp the id so runtime code can tell which keyword this area came from:
    	--the creature and Loc "Environment" symbols, and the darkness test in
    	--creature:HasConcealmentIgnoringDarkness, both resolve it against this table.
    	auraDef.environmentalKeywordId = keywordid
    
    	--Terrain rule flags, sharing the tile-rule flag names. try_get throughout:
    	--older serialized keywords predate some fields, and game-typed instances
    	--raise on unknown-field reads.
    	pcall(function()
    		if keyword:try_get("difficultTerrain", false) == true then
    			auraDef.difficult_terrain = true
    		end
    		if keyword:try_get("water", false) == true then
    			auraDef.water = true
    		end
    		if keyword:try_get("concealment", false) == true then
    			auraDef.concealment = true
    		end
    		--climbersOnly rides along only when this keyword is the one turning
    		--climbable on: it is a restriction, so it must never tighten an aura
    		--that already declared itself climbable for all creatures.
    		if keyword:try_get("climbable", false) == true and auraDef:try_get("climbable", false) ~= true then
    			auraDef.climbable = true
    			if keyword:try_get("climbersOnly", false) == true then
    				auraDef.climbersOnly = true
    			end
    		end
    		--the area extends one tile outward for enter/start-of-turn trigger
    		--contact (adjacent tiles never take terrain rules or modifiers, so
    		--this is additive-safe like the other flags).
    		if keyword:try_get("includeAdjacent", false) == true then
    			auraDef.includeAdjacent = true
    		end
    		local keywordShiftEntryMode = keyword:try_get("powerRollShiftEntryMode", "normal")
    		local auraShiftEntryMode = auraDef:try_get("powerRollShiftEntryMode", "normal")
    		if (keywordShiftEntryMode == "bane" or keywordShiftEntryMode == "ignore") and auraShiftEntryMode == "normal" then
    			auraDef.powerRollShiftEntryMode = keywordShiftEntryMode
    		end
    	end)
    
    	--Modifiers applied to creatures inside the area. Deep-copied because
    	--GetModifiers stamps transient symbol state onto modifier objects, and the
    	--table's own copies are shared with the compendium editor and every other
    	--area built from this keyword. Appended to a FRESH list rather than mutated
    	--in place: CharacterFeature.modifiers is a class-level default table, so an
    	--aura that never set its own would otherwise append into the shared default.
    	pcall(function()
    		local keywordModifiers = keyword:try_get("modifiers")
    		if keywordModifiers ~= nil and #keywordModifiers > 0 then
    			local modifiers = {}
    			for _,m in ipairs(auraDef:try_get("modifiers", {})) do
    				modifiers[#modifiers+1] = m
    			end
    			for _,m in ipairs(keywordModifiers) do
    				modifiers[#modifiers+1] = dmhub.DeepCopy(m)
    			end
    			auraDef.modifiers = modifiers
    		end
    	end)
    
    	--Damage per tile of the area a creature moves through. Skipped when the
    	--aura already defines its own move damage, so the two can't compound.
    	pcall(function()
    		local movedamage = keyword:try_get("movedamage", "none")
    		if movedamage ~= nil and movedamage ~= "none" and auraDef:try_get("movedamage", "none") == "none" then
    			auraDef.movedamage = movedamage
    			auraDef.damage = keyword:try_get("damage", 0)
    			auraDef.movementDamageFilter = keyword:try_get("movementDamageFilter", "all")
    		end
    	end)
    
    	--Power roll against creatures entering the area or starting a turn in it
    	--(creature:EnterAura -> Aura:GetSimplePowerRollTrigger). Skipped when the
    	--aura already rolls its own, since only one roll can fire per entry.
    	pcall(function()
    		if keyword:try_get("powerRollEnabled", false) and auraDef:try_get("powerRollEnabled", false) == false then
    			local tiers = keyword:try_get("powerRollTiers")
    			if tiers ~= nil then
    				auraDef.powerRollEnabled = true
    				auraDef.powerRollBonus = keyword:try_get("powerRollBonus", 0)
    				auraDef.powerRollTiers = dmhub.DeepCopy(tiers)
    			end
    		end
    	end)
    
    	--Creature filter: only creatures matching this GoblinScript are affected.
    	--Unlike every other field here this one MERGES rather than defers to the aura,
    	--because it is a restriction, not an addition: skipping it because the aura
    	--already carries a filter of its own would quietly let the keyword affect
    	--creatures its author excluded. Two filters therefore "and" together, and the
    	--plain-text containment check keeps a second application of the same keyword
    	--(re-merging an aura def that was already merged) from growing the string.
    	pcall(function()
    		local keywordFilter = keyword:try_get("creatureFilter", "")
    		if type(keywordFilter) == "string" and keywordFilter ~= "" then
    			local auraFilter = auraDef:try_get("creatureFilter", "")
    			if auraFilter == nil or auraFilter == "" then
    				auraDef.creatureFilter = keywordFilter
    			elseif type(auraFilter) == "string" then
    				if string.find(auraFilter, keywordFilter, 1, true) == nil then
    					auraDef.creatureFilter = string.format("(%s) and (%s)", auraFilter, keywordFilter)
    				end
    			--an aura carrying the level-tiered table form of a filter cannot be
    			--text-merged with. Leave it alone rather than clobber a restriction
    			--the aura's own author wrote: an aura the keyword cannot narrow is a
    			--better outcome than one whose own filter silently disappeared.
    			end
    		end
    	end)
    
    	return auraDef
    end
    
    --- True if this aura definition, or any of its sub-auras, names an Environmental
    --- Keyword. Callers that share an aura definition rather than owning it (e.g. the
    --- token-attached aura modifier, whose auras are regenerated on every creature
    --- invalidation) use this to decide whether making a copy is worth it at all.
    --- @param auraDef Aura|nil
    --- @return boolean
    function EnvironmentalKeyword.AuraNamesKeyword(auraDef)
    	if auraDef == nil then
    		return false
    	end
    
    	if auraDef:try_get("environmentalKeywordId") ~= nil then
    		return true
    	end
    
    	for _,childDef in ipairs(auraDef:try_get("subauras", {})) do
    		if childDef:try_get("environmentalKeywordId") ~= nil then
    			return true
    		end
    	end
    
    	return false
    end
    
    --- Applies each keyword named in an aura definition to the payload that names it:
    --- the parent's keyword to the parent, and each sub-aura's own keyword to that
    --- sub-aura. Sub-auras carry their own terrain flags, modifiers, and move damage,
    --- so they merge independently rather than inheriting the parent's keyword.
    ---
    --- Mutates auraDef in place -- pass a copy if you do not own it.
    --- @param auraDef Aura|nil
    --- @return Aura|nil auraDef The same definition, for call chaining.
    function EnvironmentalKeyword.ApplyToAuraTree(auraDef)
    	if auraDef == nil then
    		return auraDef
    	end
    
    	EnvironmentalKeyword.ApplyToAura(auraDef, auraDef:try_get("environmentalKeywordId"))
    
    	for _,childDef in ipairs(auraDef:try_get("subauras", {})) do
    		EnvironmentalKeyword.ApplyToAura(childDef, childDef:try_get("environmentalKeywordId"))
    	end
    
    	return auraDef
    end
    
    --- Appends {id, text} entries for all environmental keywords into options (sorted by name).
    --- Map-scoped zone types (mapid set) are included only when they belong to the current map.
    --- @param options DropdownOption[]
    function EnvironmentalKeyword.FillDropdownOptions(options)
    	local result = {}
    	local dataTable = dmhub.GetTable(EnvironmentalKeyword.tableName) or {}
    	for k,keyword in unhidden_pairs(dataTable) do
    		local mapid = keyword:try_get("mapid")
    		if mapid == nil or mapid == game.currentMapId then
    			result[#result+1] = {
    				id = k,
    				text = keyword.name,
    			}
    		end
    	end
    
    	table.sort(result, function(a,b) return a.text < b.text end)
    	for i,item in ipairs(result) do
    		options[#options+1] = item
    	end
    end
    
    local UploadKeywordWithId = function(id)
    	local dataTable = dmhub.GetTable(EnvironmentalKeyword.tableName) or {}
    	dmhub.SetAndUploadTableItem(EnvironmentalKeyword.tableName, dataTable[id])
    end
    
    --=== Zone appearance (visual representation) =================================
    --Zones of a keyword can optionally draw a real visual on the map beyond the
    --overlay stripes: either a floor-texture fill with an optional wall "edge
    --brush" around the boundary (drawn exactly like floors and walls, resting on
    --the ground and following the terrain), or one pseudo-randomly chosen square
    --sprite per tile. The config lives on the keyword as `appearance`;
    --MapMarkupPanel stamps it onto each zone's aura instance and the engine's
    --MarkupZoneVisuals renders it.
    --
    --The floor/edge appearance knobs (texture scale, hue shift, saturation,
    --brightness) live on tilesheet/wall ASSETS owned by this keyword: uploading a
    --texture creates a private asset, and picking an existing floor tile or wall
    --forks a private copy first (assets:DuplicateTilesheet/DuplicateWall, the
    --markup-wall-types pattern), so slider edits never disturb art that real
    --floors or walls are drawn with. Owned assets are Delete()d (hidden) when
    --replaced.
    
    local DescribeAppearance = function(keyword)
    	local appearance = keyword:try_get("appearance")
    	if appearance == nil or appearance.mode == nil or appearance.mode == "none" then
    		return "None"
    	end
    	if appearance.mode == "floor" then
    		if appearance.tileid ~= nil and appearance.edgeWallId ~= nil then
    			return "Floor texture with edge"
    		end
    		if appearance.edgeWallId ~= nil then
    			return "Edge brush only"
    		end
    		if appearance.tileid ~= nil then
    			return "Floor texture"
    		end
    		return "Floor (no texture chosen)"
    	end
    	if appearance.mode == "sprites" then
    		local numSprites = 0
    		if appearance.sprites ~= nil then
    			numSprites = #appearance.sprites
    		end
    		if numSprites == 1 then
    			return "1 sprite"
    		end
    		return string.format("%d sprites", numSprites)
    	end
    	return "None"
    end
    
    --Opens the appearance editor in its own modal layer (the keyword editor may
    --itself be inside ShowEditDialog's modal when opened from the Map Markup
    --panel's zone chips -- same dialog-over-dialog pattern as the markup panel's
    --zone height dialog). Changes save as they are made; Close just dismisses.
    local ShowAppearanceDialog = function(keyword, UploadKeyword, onChanged)
    	--work on the keyword's stored table directly, creating it on first edit.
    	--Mode "none" removes the field entirely (nil-assignment drops it from
    	--serialization).
    	local appearance = keyword:try_get("appearance")
    	if appearance == nil then
    		appearance = { mode = "none", alpha = 1, fractalEdge = 0, edgeFade = 0, spriteScale = 1, spriteAlpha = 1 }
    	end
    
    	local modalLayer = nil
    	local dialogPanel = nil
    
    	local Commit = function()
    		--Remove the retired midpoint-displacement detail setting from any
    		--appearance authored while that prototype was being tested.
    		appearance.fractalDetail = nil
    		if appearance.mode == nil or appearance.mode == "none" then
    			keyword.appearance = nil
    		else
    			keyword.appearance = appearance
    		end
    		UploadKeyword()
    		if onChanged ~= nil then
    			onChanged()
    		end
    	end
    
    	local GetFillAsset = function()
    		if appearance.tileid == nil then
    			return nil
    		end
    		return assets.tilesheets[appearance.tileid]
    	end
    
    	local GetEdgeAsset = function()
    		if appearance.edgeWallId == nil then
    			return nil
    		end
    		return assets.walls[appearance.edgeWallId]
    	end
    
    	local EnsureFillUsesOneLargeTile = function()
    		local asset = GetFillAsset()
    		if asset ~= nil and asset.oneLargeTile ~= true then
    			--Zone floor textures use the same tiling mode as the terrain
    			--editor's "One Large Tile" option: the complete image is one
    			--repeating unit rather than an atlas of 128px tiles.
    			asset.oneLargeTile = true
    			asset:Upload()
    		end
    	end
    
    	--Migrate private fill assets saved by older versions when their appearance
    	--is next edited. Never mutate a legacy shared asset that this keyword does
    	--not explicitly own.
    	if appearance.tileOwned == true then
    		EnsureFillUsesOneLargeTile()
    	end
    
    	--when replacing an asset this keyword owns (uploaded or forked here), hide
    	--the old one so the floor/wall palettes don't accumulate orphans.
    	local ReleaseFillAsset = function()
    		if appearance.tileOwned == true then
    			local old = GetFillAsset()
    			if old ~= nil then
    				old:Delete()
    			end
    		end
    		appearance.tileid = nil
    		appearance.tileOwned = nil
    	end
    
    	local ReleaseEdgeAsset = function()
    		if appearance.edgeOwned == true then
    			local old = GetEdgeAsset()
    			if old ~= nil then
    				old:Delete()
    			end
    		end
    		appearance.edgeWallId = nil
    		appearance.edgeOwned = nil
    	end
    
    	--adoption can arrive from an async upload callback after the dialog was
    	--closed; the commit still applies, only the visual refresh is skipped.
    	local AdoptFillAsset = function(tileid, owned)
    		ReleaseFillAsset()
    		appearance.tileid = tileid
    		appearance.tileOwned = cond(owned, true)
    		EnsureFillUsesOneLargeTile()
    		Commit()
    		if dialogPanel ~= nil and dialogPanel.valid then
    			dialogPanel:FireEventTree("refreshAppearance")
    		end
    	end
    
    	local AdoptEdgeAsset = function(wallid, owned)
    		ReleaseEdgeAsset()
    		appearance.edgeWallId = wallid
    		appearance.edgeOwned = cond(owned, true)
    		Commit()
    		if dialogPanel ~= nil and dialogPanel.valid then
    			dialogPanel:FireEventTree("refreshAppearance")
    		end
    	end
    
    	--pick an existing floor tile / wall: fork a private copy so the sliders
    	--below never edit art that real floors/walls use.
    	local PickExistingFill = function(tileid)
    		local forkid = assets:DuplicateTilesheet(tileid)
    		if forkid == nil then
    			return
    		end
    		local fork = assets.tilesheets[forkid]
    		if fork ~= nil then
    			fork.description = string.format("%s Zone", keyword.name)
    		end
    		--a copied tilesheet has no single source image; the icon editor
    		--shows empty for it.
    		appearance.tileImageId = nil
    		AdoptFillAsset(forkid, true)
    	end
    
    	local PickExistingEdge = function(wallid)
    		local forkid = assets:DuplicateWall(wallid)
    		if forkid == nil then
    			return
    		end
    		local fork = assets.walls[forkid]
    		if fork ~= nil then
    			fork.description = string.format("%s Zone Edge", keyword.name)
    			fork:Upload()
    		end
    		appearance.edgeImageId = nil
    		AdoptEdgeAsset(forkid, true)
    	end
    
    	local FillPickerOptions = function()
    		local options = {}
    		for tileid,tilesheet in pairs(assets.tilesheets) do
    			local include = false
    			pcall(function()
    				include = tilesheet.isfloor and tilesheet.hidden ~= true
    			end)
    			if include then
    				options[#options+1] = { id = tileid, text = tilesheet.description }
    			end
    		end
    		table.sort(options, function(a, b)
    			return string.lower(a.text or "") < string.lower(b.text or "")
    		end)
    		table.insert(options, 1, { id = "none", text = "Copy Existing Floor Tile..." })
    		return options
    	end
    
    	local EdgePickerOptions = function()
    		local options = {}
    		for wallid,wall in pairs(assets.walls) do
    			local include = false
    			pcall(function()
    				include = wall.hidden ~= true and wall.invisible ~= true
    			end)
    			if include then
    				options[#options+1] = { id = wallid, text = wall.description }
    			end
    		end
    		table.sort(options, function(a, b)
    			return string.lower(a.text or "") < string.lower(b.text or "")
    		end)
    		table.insert(options, 1, { id = "none", text = "Copy Existing Wall..." })
    		return options
    	end
    
    	--explicit pixel height: the slider's drag handle sizes itself to 100% of
    	--the slider's height, and these rows are auto-height under ThemeEngine --
    	--a percentage here resolves against the wrong ancestor and blows the
    	--handle up to fill the dialog (the Tilesheet dialog this styling came
    	--from gives its rows fixed heights, which is why '50%' worked there).
    	local sliderStyle = {
    		fontSize = '80%',
    		valign = 'center',
    		halign = 'right',
    		height = 26,
    		width = '100%',
    		borderWidth = 0,
    	}
    
    	--A labeled slider bound to an asset/appearance value through get/set
    	--closures. change = live preview on the in-memory value; confirm (drag
    	--released) additionally persists. Hidden while getAsset() is nil.
    	local AppearanceSlider = function(args)
    		return gui.Panel{
    			classes = {"formStackedRow"},
    			refreshAppearance = function(element)
    				element:SetClass("collapsed", args.visible ~= nil and not args.visible())
    			end,
    			gui.Label{
    				classes = {"formStacked"},
    				text = args.text,
    			},
    			gui.Slider{
    				value = args.get(),
    				minValue = args.minValue,
    				maxValue = args.maxValue,
    				sliderWidth = 200,
    				labelWidth = 50,
    				formatFunction = args.formatFunction,
    				deformatFunction = args.deformatFunction,
    				refreshAppearance = function(element)
    					element.value = args.get()
    				end,
    				change = function(element)
    					args.set(element.value, false)
    				end,
    				confirm = function(element)
    					args.set(element.value, true)
    				end,
    				style = sliderStyle,
    			},
    		}
    	end
    
    	local percentFormat = function(num)
    		return string.format('%d%%', round(num*100))
    	end
    	local percentDeformat = function(num)
    		return num*0.01
    	end
    
    	--=== floor mode section ===
    
    	local fillNameLabel = gui.Label{
    		classes = {"formStacked"},
    		text = "No texture chosen",
    		refreshAppearance = function(element)
    			local asset = GetFillAsset()
    			if asset ~= nil then
    				element.text = asset.description
    			elseif appearance.tileid ~= nil then
    				element.text = "(texture missing)"
    			else
    				element.text = "No texture chosen"
    			end
    		end,
    	}
    
    	--The standard image widget (gui.IconEditor, Zone Art library) owns
    	--browse/upload/paste for the fill and edge textures. Picking an image
    	--builds a private tilesheet/wall asset from it via
    	--assets:CreateTilesheetFromImage / CreateWallFromImage -- synchronous,
    	--since the image is already uploaded (no async-registration gap like the
    	--old file-based flow). appearance.tileImageId/edgeImageId remember the
    	--source image so the widget shows the current choice; assets adopted from
    	--the Copy Existing dropdowns have no source image and show empty.
    	--
    	--NOTE: IconEditor value ASSIGNMENT fires change on a real difference
    	--(unlike gui.Slider), so both the refresh sync and the change handler
    	--carry echo guards against loops and duplicate asset creation.
    	local fillIconEditor
    	fillIconEditor = gui.IconEditor{
    		library = "zoneart",
    		allowNone = true,
    		allowPaste = true,
    		width = 64,
    		height = 64,
    		halign = "left",
    		valign = "center",
    		hmargin = 4,
    		value = appearance.tileImageId,
    		refreshAppearance = function(element)
    			if element.value ~= appearance.tileImageId then
    				element.value = appearance.tileImageId
    			end
    		end,
    		change = function(element)
    			local imageid = element.value
    			if imageid == "" then
    				imageid = nil
    			end
    			if imageid == appearance.tileImageId then
    				return
    			end
    			if imageid == nil then
    				--cleared from the picker: drop the fill texture.
    				ReleaseFillAsset()
    				appearance.tileImageId = nil
    				Commit()
    				if dialogPanel ~= nil and dialogPanel.valid then
    					dialogPanel:FireEventTree("refreshAppearance")
    				end
    				return
    			end
    
    			local tileid = assets:CreateTilesheetFromImage{
    				imageid = imageid,
    				floor = true,
    				description = string.format("%s Zone", keyword.name),
    				error = function(text)
    					gui.ModalMessage{
    						title = "Error creating zone texture",
    						message = text,
    					}
    				end,
    			}
    			if tileid == nil then
    				--invalid image: snap the picker back.
    				element.value = appearance.tileImageId
    				return
    			end
    
    			appearance.tileImageId = imageid
    			AdoptFillAsset(tileid, true)
    		end,
    	}
    
    	local edgeIconEditor
    	edgeIconEditor = gui.IconEditor{
    		library = "zoneart",
    		allowNone = true,
    		allowPaste = true,
    		width = 64,
    		height = 64,
    		halign = "left",
    		valign = "center",
    		hmargin = 4,
    		value = appearance.edgeImageId,
    		refreshAppearance = function(element)
    			if element.value ~= appearance.edgeImageId then
    				element.value = appearance.edgeImageId
    			end
    		end,
    		change = function(element)
    			local imageid = element.value
    			if imageid == "" then
    				imageid = nil
    			end
    			if imageid == appearance.edgeImageId then
    				return
    			end
    			if imageid == nil then
    				ReleaseEdgeAsset()
    				appearance.edgeImageId = nil
    				Commit()
    				if dialogPanel ~= nil and dialogPanel.valid then
    					dialogPanel:FireEventTree("refreshAppearance")
    				end
    				return
    			end
    
    			local wallid = assets:CreateWallFromImage{
    				imageid = imageid,
    				description = string.format("%s Zone Edge", keyword.name),
    				error = function(text)
    					gui.ModalMessage{
    						title = "Error creating zone edge",
    						message = text,
    					}
    				end,
    			}
    			if wallid == nil then
    				element.value = appearance.edgeImageId
    				return
    			end
    
    			appearance.edgeImageId = imageid
    			AdoptEdgeAsset(wallid, true)
    		end,
    	}
    
    	local floorSection = gui.Panel{
    		width = "100%",
    		height = "auto",
    		flow = "vertical",
    		refreshAppearance = function(element)
    			element:SetClass("collapsed", appearance.mode ~= "floor")
    		end,
    
    		gui.Panel{
    			classes = {"formStackedRow"},
    			gui.Label{
    				classes = {"formStacked"},
    				text = "Fill Texture:",
    			},
    			fillIconEditor,
    			fillNameLabel,
    		},
    
    		gui.Panel{
    			classes = {"formStackedRow"},
    			gui.Dropdown{
    				classes = {"formStacked"},
    				idChosen = "none",
    				options = FillPickerOptions(),
    				change = function(element)
    					if element.idChosen ~= "none" then
    						PickExistingFill(element.idChosen)
    						element.idChosen = "none"
    					end
    				end,
    			},
    		},
    
    		AppearanceSlider{
    			text = "Texture Scale:",
    			visible = function() return GetFillAsset() ~= nil end,
    			minValue = -4,
    			maxValue = 4,
    			get = function()
    				local asset = GetFillAsset()
    				return cond(asset ~= nil, -(asset or {scale=0}).scale, 0)
    			end,
    			set = function(value, upload)
    				local asset = GetFillAsset()
    				if asset ~= nil then
    					asset.scale = -value
    					if upload then
    						asset:Upload()
    					end
    				end
    			end,
    			formatFunction = function(num)
    				return string.format('%d%%', round((2^num)*100))
    			end,
    			deformatFunction = function(num)
    				local n = num*0.01
    				return math.log(n)/math.log(2)
    			end,
    		},
    
    		AppearanceSlider{
    			text = "Hue Shift:",
    			visible = function() return GetFillAsset() ~= nil end,
    			minValue = 0,
    			maxValue = 1,
    			get = function()
    				local asset = GetFillAsset()
    				return cond(asset ~= nil, (asset or {hueshift=0}).hueshift, 0)
    			end,
    			set = function(value, upload)
    				local asset = GetFillAsset()
    				if asset ~= nil then
    					asset.hueshift = value
    					if upload then
    						asset:Upload()
    					end
    				end
    			end,
    		},
    
    		AppearanceSlider{
    			text = "Saturation:",
    			visible = function() return GetFillAsset() ~= nil end,
    			minValue = -1,
    			maxValue = 1,
    			get = function()
    				local asset = GetFillAsset()
    				return cond(asset ~= nil, (asset or {saturation=0}).saturation, 0)
    			end,
    			set = function(value, upload)
    				local asset = GetFillAsset()
    				if asset ~= nil then
    					asset.saturation = value
    					if upload then
    						asset:Upload()
    					end
    				end
    			end,
    		},
    
    		AppearanceSlider{
    			text = "Brightness:",
    			visible = function() return GetFillAsset() ~= nil end,
    			minValue = -1,
    			maxValue = 1,
    			get = function()
    				local asset = GetFillAsset()
    				return cond(asset ~= nil, (asset or {brightness=0}).brightness, 0)
    			end,
    			set = function(value, upload)
    				local asset = GetFillAsset()
    				if asset ~= nil then
    					asset.brightness = value
    					if upload then
    						asset:Upload()
    					end
    				end
    			end,
    		},
    
    		AppearanceSlider{
    			text = "Opacity:",
    			visible = function() return GetFillAsset() ~= nil end,
    			minValue = 0.05,
    			maxValue = 1,
    			get = function()
    				return appearance.alpha or 1
    			end,
    			set = function(value, upload)
    				appearance.alpha = value
    				if upload then
    					Commit()
    				end
    			end,
    			formatFunction = percentFormat,
    			deformatFunction = percentDeformat,
    		},
    
    		AppearanceSlider{
    			text = "Organic Edge:",
    			visible = function() return GetFillAsset() ~= nil or GetEdgeAsset() ~= nil end,
    			minValue = 0,
    			maxValue = 1,
    			get = function()
    				return appearance.fractalEdge or 0
    			end,
    			set = function(value, upload)
    				appearance.fractalEdge = value
    				if upload then
    					Commit()
    				end
    			end,
    			formatFunction = percentFormat,
    			deformatFunction = percentDeformat,
    		},
    
    		AppearanceSlider{
    			text = "Edge Fade (tiles):",
    			visible = function() return GetFillAsset() ~= nil end,
    			minValue = 0,
    			maxValue = 0.35,
    			get = function()
    				return appearance.edgeFade or 0
    			end,
    			set = function(value, upload)
    				appearance.edgeFade = value
    				if upload then
    					Commit()
    				end
    			end,
    			formatFunction = function(num)
    				return string.format('%.2f', num)
    			end,
    			deformatFunction = function(num)
    				return num
    			end,
    		},
    
    		--edge brush: a wall drawn around the boundary of each zone.
    		gui.Panel{
    			classes = {"formStackedRow"},
    			gui.Label{
    				classes = {"formStacked"},
    				text = "Edge Brush:",
    			},
    			edgeIconEditor,
    			gui.Label{
    				classes = {"formStacked"},
    				text = "None",
    				refreshAppearance = function(element)
    					local asset = GetEdgeAsset()
    					if asset ~= nil then
    						element.text = asset.description
    					elseif appearance.edgeWallId ~= nil then
    						element.text = "(edge missing)"
    					else
    						element.text = "None"
    					end
    				end,
    			},
    			gui.Button{
    				classes = {"sizeM", cond(appearance.edgeWallId == nil, "collapsed")},
    				text = "Remove",
    				refreshAppearance = function(element)
    					element:SetClass("collapsed", appearance.edgeWallId == nil)
    				end,
    				click = function(element)
    					ReleaseEdgeAsset()
    					appearance.edgeImageId = nil
    					Commit()
    					dialogPanel:FireEventTree("refreshAppearance")
    				end,
    			},
    		},
    
    		gui.Panel{
    			classes = {"formStackedRow"},
    			gui.Dropdown{
    				classes = {"formStacked"},
    				idChosen = "none",
    				options = EdgePickerOptions(),
    				change = function(element)
    					if element.idChosen ~= "none" then
    						PickExistingEdge(element.idChosen)
    						element.idChosen = "none"
    					end
    				end,
    			},
    		},
    
    		AppearanceSlider{
    			text = "Edge Scale:",
    			visible = function() return GetEdgeAsset() ~= nil end,
    			minValue = 0,
    			maxValue = 2,
    			get = function()
    				local asset = GetEdgeAsset()
    				return cond(asset ~= nil, (asset or {scale=1}).scale, 1)
    			end,
    			set = function(value, upload)
    				local asset = GetEdgeAsset()
    				if asset ~= nil then
    					asset.scale = value
    					if upload then
    						asset:Upload()
    					end
    				end
    			end,
    		},
    
    		AppearanceSlider{
    			text = "Edge Hue Shift:",
    			visible = function() return GetEdgeAsset() ~= nil end,
    			minValue = 0,
    			maxValue = 1,
    			get = function()
    				local asset = GetEdgeAsset()
    				return cond(asset ~= nil, (asset or {hueshift=0}).hueshift, 0)
    			end,
    			set = function(value, upload)
    				local asset = GetEdgeAsset()
    				if asset ~= nil then
    					asset.hueshift = value
    					if upload then
    						asset:Upload()
    					end
    				end
    			end,
    		},
    	}
    
    	--=== sprites mode section ===
    
    	--one gui.IconEditor chip per sprite (browse/upload/paste all built in),
    	--plus a trailing empty chip that appends a new sprite when set. The grid
    	--rebuilds its children on every refreshAppearance, so the chips are
    	--always constructed with their current values (no assignment echoes) and
    	--the add-chip resets naturally after an append.
    	local spriteGrid = gui.Panel{
    		width = "100%",
    		height = "auto",
    		flow = "horizontal",
    		wrap = true,
    		halign = "left",
    		refreshAppearance = function(element)
    			local children = {}
    			local sprites = appearance.sprites or {}
    			for i,imageid in ipairs(sprites) do
    				children[#children+1] = gui.IconEditor{
    					library = "zoneart",
    					allowNone = true,
    					allowPaste = true,
    					width = 48,
    					height = 48,
    					margin = 4,
    					value = imageid,
    					hover = gui.Tooltip("Click to change this sprite; choose None to remove it"),
    					change = function(child)
    						if child.value == nil or child.value == "" then
    							table.remove(appearance.sprites, i)
    						else
    							appearance.sprites[i] = child.value
    						end
    						Commit()
    						dialogPanel:FireEventTree("refreshAppearance")
    					end,
    				}
    			end
    
    			children[#children+1] = gui.IconEditor{
    				library = "zoneart",
    				allowPaste = true,
    				width = 48,
    				height = 48,
    				margin = 4,
    				value = nil,
    				hover = gui.Tooltip("Add a sprite"),
    				change = function(child)
    					if child.value ~= nil and child.value ~= "" then
    						appearance.sprites = appearance.sprites or {}
    						appearance.sprites[#appearance.sprites+1] = child.value
    						Commit()
    						dialogPanel:FireEventTree("refreshAppearance")
    					end
    				end,
    			}
    
    			element.children = children
    		end,
    	}
    
    	local spritesSection = gui.Panel{
    		width = "100%",
    		height = "auto",
    		flow = "vertical",
    		refreshAppearance = function(element)
    			element:SetClass("collapsed", appearance.mode ~= "sprites")
    		end,
    
    		gui.Label{
    			classes = {"formStacked", "fgMuted"},
    			width = "94%",
    			height = "auto",
    			text = "Each tile of a zone shows one of these sprites, chosen and rotated pseudo-randomly but consistently: the same tile always shows the same sprite, on every screen.",
    		},
    
    		spriteGrid,
    
    		AppearanceSlider{
    			text = "Sprite Size:",
    			minValue = 0.3,
    			maxValue = 1.5,
    			get = function()
    				return appearance.spriteScale or 1
    			end,
    			set = function(value, upload)
    				appearance.spriteScale = value
    				if upload then
    					Commit()
    				end
    			end,
    			formatFunction = percentFormat,
    			deformatFunction = percentDeformat,
    		},
    
    		AppearanceSlider{
    			text = "Opacity:",
    			minValue = 0.05,
    			maxValue = 1,
    			get = function()
    				return appearance.spriteAlpha or 1
    			end,
    			set = function(value, upload)
    				appearance.spriteAlpha = value
    				if upload then
    					Commit()
    				end
    			end,
    			formatFunction = percentFormat,
    			deformatFunction = percentDeformat,
    		},
    	}
    
    	--=== dialog shell ===
    
    	local children = {
    		gui.Label{
    			classes = {"dialogTitle"},
    			text = "Zone Appearance",
    		},
    	}
    
    	children[#children+1] = gui.Panel{
    		classes = {"formStackedRow"},
    		gui.Label{
    			classes = {"formStacked"},
    			text = "Appearance:",
    		},
    		gui.Dropdown{
    			classes = {"formStacked"},
    			idChosen = cond(appearance.mode == nil, "none", appearance.mode),
    			options = {
    				{ id = "none", text = "None" },
    				{ id = "floor", text = "Floor Texture" },
    				{ id = "sprites", text = "Sprites" },
    			},
    			change = function(element)
    				appearance.mode = element.idChosen
    				Commit()
    				dialogPanel:FireEventTree("refreshAppearance")
    			end,
    		},
    	}
    
    	children[#children+1] = gui.Panel{
    		width = "100%",
    		height = "100%-140",
    		flow = "vertical",
    		vscroll = true,
    		floorSection,
    		spritesSection,
    	}
    
    	children[#children+1] = gui.Button{
    		classes = {"sizeM"},
    		text = "Close",
    		halign = "center",
    		valign = "bottom",
    		vmargin = 8,
    		click = function(element)
    			dialogPanel:FireEvent("escape")
    		end,
    	}
    
    	dialogPanel = gui.Panel{
    		id = "ZoneAppearanceDialog",
    		classes = {"framedPanel"},
    		styles = ThemeEngine.GetStyles(),
    		width = 700,
    		height = "85%",
    		pad = 16,
    		borderBox = true,
    		flow = "vertical",
    		halign = "center",
    		valign = "center",
    
    		captureEscape = true,
    		escapePriority = EscapePriority.EXIT_MODAL_DIALOG,
    		escape = function(element)
    			--persist any slider edits that only previewed (change without a
    			--confirm, e.g. keyboard-nudged values) before dismissing.
    			if appearance.tileOwned == true then
    				local fill = GetFillAsset()
    				if fill ~= nil then
    					fill:Upload()
    				end
    			end
    			if appearance.edgeOwned == true then
    				local edge = GetEdgeAsset()
    				if edge ~= nil then
    					edge:Upload()
    				end
    			end
    			gui.CloseModalInLayer(modalLayer)
    		end,
    
    		children = children,
    	}
    
    	modalLayer = gui.ShowModal(dialogPanel)
    	dialogPanel:FireEventTree("refreshAppearance")
    end
    
    --=== Zone scripts ===========================================================
    --A keyword may carry Lua source (keyword.script) that runs once per zone of
    --that keyword on the current map, on every client - the zone-visuals of code.
    --The source RETURNS a table of handlers (the AbilityScript/EncounterScript
    --load-with-env precedent): create/destroy/locsChanged/think + thinkInterval.
    --
    --MapMarkupPanel calls EnvironmentalKeyword.SyncZoneScripts at the end of
    --every zone-cache rebuild (which runs on every client via the map-aura feed,
    --panel open or not). The manager diffs the rebuilt zone list against its
    --running instances: zones that appeared instantiate, zones that vanished run
    --their exit routine. destroy is HARD-GUARANTEED at de-instantiation through
    --three layered mechanisms:
    --  1. the sync diff - erasing/deleting the zone, deleting its keyword,
    --     breaking or editing the script, hiding the floor, and map changes all
    --     land here, because every one of them triggers a cache rebuild;
    --  2. a heartbeat (which also drives think) that destroys any instance whose
    --     map is no longer the current map, for teardowns whose rebuild the feed
    --     never polled;
    --  3. mod.unloadHandlers, for Lua reloads.
    --Every handler call is pcall-wrapped: a script error is reported (once per
    --handler per instance) and never breaks the zone cache or another script.
    
    local ZoneScripts = {
    	--key "mapid|floorid|zoneid" -> running instance {key, code, def, zone,
    	--locsSig, created, destroyed, nextThink, errorReported}
    	instances = {},
    	heartbeatActive = false,
    	--compiled-definition cache keyed by the exact source string. Definitions
    	--are pure (no side effects at load), so identical source always yields
    	--the same definition; treat cached defs as read-only.
    	definitionCache = {},
    }
    
    ZoneScripts.starterTemplate = [[--Zone script: runs on every client, one instance per zone of this type
    --on the current map. Return a table of handlers; all are optional.
    --
    --Handlers receive the zone object:
    --  zone.locs        the Loc tiles the zone currently covers
    --  zone.locsAndAdjacent  zone.locs plus every tile adjacent to it (8-way)
    --  zone.color       the zone type's color, e.g. "#3373d9"
    --  zone.name        this zone's display name
    --  zone.keyword     the zone type's name
    --  zone.zoneid, zone.floorid, zone.floorIndex, zone.mapid
    --  zone.altitude    tiles above the ground the zone starts at
    --  zone.height      tiles of vertical extent, or nil for unlimited
    --  zone.entireMap   true for an "Entire Map" blanket
    --  zone.data        an empty table for your own state
    --
    --destroy is guaranteed to run when the zone is erased, the map changes,
    --the script is edited, or mods reload. If locsChanged is omitted, the
    --script restarts (destroy then create) whenever the zone's tiles change.
    --think(zone) runs every thinkInterval seconds while the zone exists.
    
    local def = {}
    
    def.create = function(zone)
    	--example: shimmer the air over the zone for as long as it exists.
    	zone.data.heat = dmhub.CreateWorldDistortion{
    		type = "heatwave",
    		locs = zone.locs,
    		strength = 4,
    		speed = 0.9,
    		fadeIn = 0.5,
    		fadeOut = 0.5,
    	}
    end
    
    def.locsChanged = function(zone)
    	if zone.data.heat ~= nil then
    		zone.data.heat:SetLocs(zone.locs)
    	end
    end
    
    def.destroy = function(zone)
    	if zone.data.heat ~= nil then
    		zone.data.heat:Stop()
    	end
    end
    
    return def]]
    
    --Compile zone-script source into a normalized definition table, or nil plus
    --an error string. Follows EncounterScript.CompileDefinition: load(code, name,
    --"t", env) with an environment that reads globals but keeps writes local to
    --the chunk.
    ZoneScripts.Compile = function(code)
    	if code == nil or code == "" then
    		return nil, "The script is empty"
    	end
    
    	local cached = ZoneScripts.definitionCache[code]
    	if cached ~= nil then
    		return cached.def, cached.error
    	end
    
    	local result = { def = nil, error = nil }
    	ZoneScripts.definitionCache[code] = result
    
    	local env = setmetatable({}, { __index = _G })
    	local chunk, err = load(code, "ZoneScript", "t", env)
    	if chunk == nil then
    		result.error = "Compile error: " .. tostring(err)
    		return nil, result.error
    	end
    
    	local ok, def = pcall(chunk)
    	if not ok then
    		result.error = "Error running script: " .. tostring(def)
    		return nil, result.error
    	end
    	if type(def) ~= "table" then
    		result.error = "The script must return a table of handlers"
    		return nil, result.error
    	end
    
    	local norm = {}
    	for _,handler in ipairs({"create", "destroy", "locsChanged", "think"}) do
    		local fn = def[handler]
    		if fn ~= nil and type(fn) ~= "function" then
    			result.error = string.format("Invalid definition: %s must be a function", handler)
    			return nil, result.error
    		end
    		norm[handler] = fn
    	end
    
    	local interval = tonumber(def.thinkInterval) or 1
    	if interval < 0.25 then
    		interval = 0.25
    	end
    	norm.thinkInterval = interval
    
    	result.def = norm
    	return norm, nil
    end
    
    --Human-readable summary for editor status rows.
    ZoneScripts.DescribeDefinition = function(def)
    	local handlers = {}
    	for _,handler in ipairs({"create", "think", "locsChanged", "destroy"}) do
    		if def[handler] ~= nil then
    			handlers[#handlers+1] = handler
    		end
    	end
    	if #handlers == 0 then
    		return "Script OK (declares no handlers yet)"
    	end
    	return "Runs " .. table.concat(handlers, ", ")
    end
    
    ZoneScripts.Describe = function(keyword)
    	local code = keyword:try_get("script")
    	if code == nil or code == "" then
    		return "None"
    	end
    	local def, err = ZoneScripts.Compile(code)
    	if def == nil then
    		return "Script has errors"
    	end
    	return ZoneScripts.DescribeDefinition(def)
    end
    
    --Report a handler error once per handler per instance: a broken think would
    --otherwise spam an error every tick. The flag doubles as the "stop calling
    --think" gate below.
    ZoneScripts.ReportError = function(instance, handler, err)
    	if instance.errorReported[handler] then
    		return
    	end
    	instance.errorReported[handler] = true
    	dmhub.CloudError(string.format("Zone script (%s, zone %s): error in %s: %s",
    		tostring(instance.zone.keyword), tostring(instance.zone.name), handler, tostring(err)))
    end
    
    --Order-independent signature of a zone's active tiles, used to detect
    --geometry changes across rebuilds. locs are Loc userdata built from integer
    --tile coords; round defensively like the dispel carve does.
    ZoneScripts.LocsSignature = function(locs)
    	local parts = {}
    	for _,loc in ipairs(locs or {}) do
    		parts[#parts+1] = string.format("%d,%d", math.floor(loc.x + 0.5), math.floor(loc.y + 0.5))
    	end
    	table.sort(parts)
    	return table.concat(parts, ";")
    end
    
    --zone.locs dilated one tile outward, 8-way: the zone plus its adjacent ring,
    --deduped. The ring tiles are fresh core.Loc userdata on the zone's floor;
    --coords are rounded defensively like LocsSignature.
    ZoneScripts.DilateLocs = function(locs, floorIndex)
    	local seen = {}
    	local result = {}
    	for _,loc in ipairs(locs or {}) do
    		local x = math.floor(loc.x + 0.5)
    		local y = math.floor(loc.y + 0.5)
    		local key = x .. "," .. y
    		if seen[key] == nil then
    			seen[key] = true
    			result[#result+1] = loc
    		end
    	end
    
    	--walk only the original tiles; result grows past numOriginal as the ring
    	--is appended.
    	local numOriginal = #result
    	for i = 1,numOriginal do
    		local loc = result[i]
    		local x = math.floor(loc.x + 0.5)
    		local y = math.floor(loc.y + 0.5)
    		for dy = -1,1 do
    			for dx = -1,1 do
    				if dx ~= 0 or dy ~= 0 then
    					local key = (x+dx) .. "," .. (y+dy)
    					if seen[key] == nil then
    						seen[key] = true
    						result[#result+1] = core.Loc{
    							x = x + dx,
    							y = y + dy,
    							floorIndex = floorIndex,
    						}
    					end
    				end
    			end
    		end
    	end
    	return result
    end
    
    ZoneScripts.BuildZoneObject = function(entry)
    	local zone = {
    		zoneid = entry.zoneid,
    		floorid = entry.floorid,
    		floorIndex = entry.floorIndex,
    		mapid = game.currentMapId,
    		name = entry.name,
    		keyword = entry.keywordName,
    		keywordid = entry.keywordid,
    		color = entry.patternColor,
    		altitude = entry.altitude or 0,
    		height = entry.height,
    		entireMap = entry.entireMap == true,
    		locs = entry.locsUserdata,
    		data = {},
    		destroyed = false,
    	}
    	--zone.locsAndAdjacent computes lazily on first read and then caches as a
    	--real field, so blanket-sized zones never pay for a dilation no script
    	--asks for. UpdateInstance nil-assigns the field when locs change, which
    	--routes the next read back through here against the fresh locs.
    	setmetatable(zone, {
    		__index = function(t, key)
    			if key == "locsAndAdjacent" then
    				local value = ZoneScripts.DilateLocs(rawget(t, "locs"), rawget(t, "floorIndex"))
    				rawset(t, "locsAndAdjacent", value)
    				return value
    			end
    			return nil
    		end,
    	})
    	return zone
    end
    
    --Runs the exit routine and unregisters the instance. Reentrant-safe: the
    --destroyed flag is set BEFORE the handler runs, so a destroy that somehow
    --triggers a sync cannot double-fire.
    ZoneScripts.DestroyInstance = function(instance)
    	if instance.destroyed then
    		return
    	end
    	instance.destroyed = true
    	instance.zone.destroyed = true
    	ZoneScripts.instances[instance.key] = nil
    	if instance.created and instance.def.destroy ~= nil then
    		local ok, err = pcall(instance.def.destroy, instance.zone)
    		if not ok then
    			ZoneScripts.ReportError(instance, "destroy", err)
    		end
    	end
    end
    
    ZoneScripts.CreateInstance = function(key, entry, code, def)
    	local instance = {
    		key = key,
    		code = code,
    		def = def,
    		zone = ZoneScripts.BuildZoneObject(entry),
    		locsSig = ZoneScripts.LocsSignature(entry.locsUserdata),
    		--created is set before create runs: if create errors partway it may
    		--already hold resources, so destroy must still fire for it.
    		created = true,
    		destroyed = false,
    		nextThink = dmhub.Time() + def.thinkInterval,
    		errorReported = {},
    	}
    	ZoneScripts.instances[key] = instance
    	if def.create ~= nil then
    		local ok, err = pcall(def.create, instance.zone)
    		if not ok then
    			ZoneScripts.ReportError(instance, "create", err)
    		end
    	end
    	ZoneScripts.EnsureHeartbeat()
    end
    
    --Reconciles a retained instance with its freshly rebuilt cache entry: name
    --and color updates apply in place; a floor or vertical-band change restarts
    --the script; a tile change goes to locsChanged when the script declares it
    --and restarts the script otherwise.
    ZoneScripts.UpdateInstance = function(instance, entry)
    	local zone = instance.zone
    	zone.name = entry.name
    	zone.keyword = entry.keywordName
    	zone.keywordid = entry.keywordid
    	zone.color = entry.patternColor
    
    	local altitude = entry.altitude or 0
    	if zone.floorIndex ~= entry.floorIndex or zone.altitude ~= altitude or zone.height ~= entry.height then
    		ZoneScripts.DestroyInstance(instance)
    		ZoneScripts.CreateInstance(instance.key, entry, instance.code, instance.def)
    		return
    	end
    
    	local sig = ZoneScripts.LocsSignature(entry.locsUserdata)
    	if sig == instance.locsSig then
    		return
    	end
    	instance.locsSig = sig
    	zone.locs = entry.locsUserdata
    	--drop the cached dilation; the next locsAndAdjacent read recomputes it
    	--against the fresh locs via the zone metatable.
    	zone.locsAndAdjacent = nil
    	if instance.def.locsChanged ~= nil then
    		local ok, err = pcall(instance.def.locsChanged, zone)
    		if not ok then
    			ZoneScripts.ReportError(instance, "locsChanged", err)
    		end
    	else
    		ZoneScripts.DestroyInstance(instance)
    		ZoneScripts.CreateInstance(instance.key, entry, instance.code, instance.def)
    	end
    end
    
    ZoneScripts.StopAll = function()
    	local all = {}
    	for _,instance in pairs(ZoneScripts.instances) do
    		all[#all+1] = instance
    	end
    	for _,instance in ipairs(all) do
    		ZoneScripts.DestroyInstance(instance)
    	end
    end
    
    --The heartbeat runs only while instances exist: it destroys any instance
    --whose map is no longer current (the backstop for teardowns whose cache
    --rebuild never got polled) and drives think handlers.
    ZoneScripts.EnsureHeartbeat = function()
    	if ZoneScripts.heartbeatActive then
    		return
    	end
    	ZoneScripts.heartbeatActive = true
    
    	local Tick
    	Tick = function()
    		if mod.unloaded then
    			ZoneScripts.heartbeatActive = false
    			ZoneScripts.StopAll()
    			return
    		end
    		if next(ZoneScripts.instances) == nil then
    			ZoneScripts.heartbeatActive = false
    			return
    		end
    
    		local mapid = game.currentMapId
    		local now = dmhub.Time()
    		local stale = nil
    		for _,instance in pairs(ZoneScripts.instances) do
    			if instance.zone.mapid ~= mapid then
    				stale = stale or {}
    				stale[#stale+1] = instance
    			elseif instance.def.think ~= nil and (not instance.errorReported.think) and now >= instance.nextThink then
    				instance.nextThink = now + instance.def.thinkInterval
    				local ok, err = pcall(instance.def.think, instance.zone)
    				if not ok then
    					ZoneScripts.ReportError(instance, "think", err)
    				end
    			end
    		end
    		for _,instance in ipairs(stale or {}) do
    			ZoneScripts.DestroyInstance(instance)
    		end
    
    		dmhub.Schedule(0.25, Tick)
    	end
    
    	dmhub.Schedule(0.25, Tick)
    end
    
    mod.unloadHandlers[#mod.unloadHandlers+1] = function()
    	ZoneScripts.StopAll()
    end
    
    --- Called by MapMarkupPanel at the end of every zone-cache rebuild with the
    --- rebuilt entry lists (painted zones and Entire Map blankets); {} tears
    --- everything down (no map). Instances are keyed by mapid|floorid|zoneid, so
    --- a map change naturally retires the old map's instances. Only entries that
    --- are live on a visible floor (non-empty locsUserdata) and whose keyword
    --- carries a compilable script are instantiated; everything else - including
    --- an instance whose script broke or changed - is destroyed, with the exit
    --- routine run.
    --- @param entryLists table[] lists of zone-cache entries
    function EnvironmentalKeyword.SyncZoneScripts(entryLists)
    	if mod.unloaded then
    		ZoneScripts.StopAll()
    		return
    	end
    
    	local mapid = game.currentMapId
    	local desired = {}
    	for _,entries in ipairs(entryLists or {}) do
    		for _,entry in ipairs(entries) do
    			if entry.floorIndex ~= nil and entry.floorIndex >= 0
    				and entry.locsUserdata ~= nil and #entry.locsUserdata > 0
    				and entry.keywordInfo ~= nil then
    
    				local code = entry.keywordInfo:try_get("script")
    				if code ~= nil and code ~= "" then
    					local def = ZoneScripts.Compile(code)
    					if def ~= nil then
    						local key = string.format("%s|%s|%s", tostring(mapid), tostring(entry.floorid), tostring(entry.zoneid))
    						desired[key] = { entry = entry, code = code, def = def }
    					end
    				end
    			end
    		end
    	end
    
    	--destroy first, in a collected list (DestroyInstance mutates instances):
    	--anything not desired anymore, and anything whose script text changed
    	--(the edit restarts the instance against the new definition).
    	local stale = nil
    	for key,instance in pairs(ZoneScripts.instances) do
    		local want = desired[key]
    		if want == nil or want.code ~= instance.code then
    			stale = stale or {}
    			stale[#stale+1] = instance
    		end
    	end
    	for _,instance in ipairs(stale or {}) do
    		ZoneScripts.DestroyInstance(instance)
    	end
    
    	for key,want in pairs(desired) do
    		local instance = ZoneScripts.instances[key]
    		if instance == nil then
    			ZoneScripts.CreateInstance(key, want.entry, want.code, want.def)
    		else
    			ZoneScripts.UpdateInstance(instance, want.entry)
    		end
    	end
    end
    
    --Opens the script editor in its own modal layer (dialog-over-dialog, same as
    --the appearance dialog above). The script saves on commit (deselect/close);
    --an unedited starter template is never saved.
    ZoneScripts.ShowDialog = function(keyword, UploadKeyword, onChanged)
    	local modalLayer = nil
    	local dialogPanel = nil
    
    	local Commit = function(text)
    		if text == nil or text:match("^%s*$") ~= nil then
    			--nil-assignment removes the field from serialization.
    			keyword.script = nil
    		else
    			keyword.script = text
    		end
    		UploadKeyword()
    		if onChanged ~= nil then
    			onChanged()
    		end
    	end
    
    	local initialText = keyword:try_get("script")
    	if initialText == nil or initialText == "" then
    		initialText = ZoneScripts.starterTemplate
    	end
    
    	local statusLabel = gui.Label{
    		classes = {"formLabel"},
    		width = "100%",
    		height = "auto",
    		halign = "left",
    		vmargin = 6,
    		refreshStatus = function(element, text)
    			if text == nil or text:match("^%s*$") ~= nil then
    				element.text = "No script."
    				return
    			end
    			local def, err = ZoneScripts.Compile(text)
    			if def == nil then
    				element.text = tostring(err)
    			else
    				element.text = ZoneScripts.DescribeDefinition(def)
    			end
    		end,
    	}
    
    	local codeInput = gui.Input{
    		width = "100%",
    		height = "auto",
    		minHeight = 420,
    		fontFace = "Courier",
    		fontSize = 14,
    		multiline = true,
    		textAlignment = "topleft",
    		characterLimit = 20000,
    		text = initialText,
    		--keep the compile status live while typing, coalesced by editlag.
    		editlag = 0.25,
    		edit = function(element)
    			statusLabel:FireEvent("refreshStatus", element.text)
    		end,
    		change = function(element)
    			statusLabel:FireEvent("refreshStatus", element.text)
    			Commit(element.text)
    		end,
    	}
    
    	local children = {
    		gui.Label{
    			classes = {"dialogTitle"},
    			text = "Zone Script",
    		},
    
    		gui.Panel{
    			width = "100%",
    			height = "100%-140",
    			flow = "vertical",
    			vscroll = true,
    			codeInput,
    		},
    
    		statusLabel,
    
    		gui.Button{
    			classes = {"sizeM"},
    			text = "Close",
    			halign = "center",
    			valign = "bottom",
    			vmargin = 8,
    			click = function(element)
    				dialogPanel:FireEvent("escape")
    			end,
    		},
    	}
    
    	dialogPanel = gui.Panel{
    		id = "ZoneScriptDialog",
    		classes = {"framedPanel"},
    		styles = ThemeEngine.GetStyles(),
    		width = 780,
    		height = "85%",
    		pad = 16,
    		borderBox = true,
    		flow = "vertical",
    		halign = "center",
    		valign = "center",
    
    		captureEscape = true,
    		escapePriority = EscapePriority.EXIT_MODAL_DIALOG,
    		escape = function(element)
    			--commit any edit still sitting uncommitted in the input, but
    			--never save a starter template the user did not touch.
    			local stored = keyword:try_get("script")
    			local baseline = stored
    			if baseline == nil or baseline == "" then
    				baseline = ZoneScripts.starterTemplate
    			end
    			if codeInput.text ~= baseline then
    				Commit(codeInput.text)
    			end
    			gui.CloseModalInLayer(modalLayer)
    		end,
    
    		children = children,
    	}
    
    	modalLayer = gui.ShowModal(dialogPanel)
    	statusLabel:FireEvent("refreshStatus", initialText)
    end
    
    local SetData = function(tableName, keywordPanel, keyid)
    	local dataTable = dmhub.GetTable(tableName) or {}
    	local keyword = dataTable[keyid]
    
    	--guard: the id may be stale (e.g. an old palette entry stranded on an id
    	--that is not in the table). Leave the panel as-is rather than erroring.
    	if keyword == nil then
    		dmhub.Debug(string.format("EnvironmentalKeyword:: SetData: no keyword with id %s", tostring(keyid)))
    		return
    	end
    
    	local UploadKeyword = function()
    		dmhub.SetAndUploadTableItem(tableName, keyword)
    	end
    
    	--if we were displaying a different keyword and it has unsaved changes, flush it.
    	if keywordPanel.data.keyid ~= "" and keywordPanel.data.keyid ~= keyid and dmhub.ToJson(dataTable[keywordPanel.data.keyid]) ~= keywordPanel.data.keywordjson then
    		UploadKeywordWithId(keywordPanel.data.keyid)
    	end
    
    	keywordPanel.data.keyid = keyid
    	keywordPanel.data.keywordjson = dmhub.ToJson(keyword)
    
    	--make sure the icon display info exists (older items may predate it).
    	keyword:get_or_add("display", {
    		bgcolor = "white",
    		hueshift = 0,
    		saturation = 1,
    		brightness = 1,
    	})
    
    	local children = {}
    
    	if devmode() then
    		--the id of the keyword.
    		children[#children+1] = gui.Panel{
    			classes = {"formStackedRow"},
    			gui.Label{
    				classes = {"formStacked"},
    				text = "ID:",
    			},
    			gui.Input{
    				classes = {"formStacked"},
    				text = keyword.id,
    				editable = false,
    			},
    		}
    	end
    
    	--the name of the keyword.
    	children[#children+1] = gui.Panel{
    		classes = {"formStackedRow"},
    		gui.Label{
    			classes = {"formStacked"},
    			text = "Name:",
    		},
    		gui.Input{
    			classes = {"formStacked"},
    			text = keyword.name,
    			change = function(element)
    				keyword.name = element.text
    				UploadKeyword()
    			end,
    		},
    	}
    
    	--map-scoped zone types: created from a map's Zone Types palette and hidden
    	--from the compendium and other maps until promoted to a full keyword.
    	if keyword:try_get("mapid") ~= nil then
    		children[#children+1] = gui.Panel{
    			classes = {"formStackedRow"},
    			gui.Label{
    				classes = {"formStacked"},
    				text = "This zone type is only available on this map.",
    			},
    			gui.Button{
    				classes = {"sizeM"},
    				halign = "left",
    				text = "Make Available to All Maps",
    				click = function(element)
    					keyword.mapid = nil
    					UploadKeyword()
    					element.parent:SetClass("collapsed", true)
    				end,
    			},
    		}
    	end
    
    	--the keyword's icon.
    	local iconEditor = gui.IconEditor{
    		library = "ongoingEffects",
    		bgcolor = keyword.display['bgcolor'] or "white",
    		margin = 20,
    		width = 64,
    		height = 64,
    		halign = "left",
    		value = keyword.iconid,
    		change = function(element)
    			keyword.iconid = element.value
    			UploadKeyword()
    		end,
    		create = function(element)
    			element.selfStyle.hueshift = keyword.display['hueshift']
    			element.selfStyle.saturation = keyword.display['saturation']
    			element.selfStyle.brightness = keyword.display['brightness']
    		end,
    	}
    
    	local iconColorPicker = gui.ColorPicker{
    		value = keyword.display['bgcolor'] or "white",
    		hmargin = 8,
    		width = 24,
    		height = 24,
    		valign = 'center',
    
    		confirm = function(element)
    			iconEditor.selfStyle.bgcolor = element.value
    			keyword.display['bgcolor'] = element.value
    			UploadKeyword()
    		end,
    
    		change = function(element)
    			iconEditor.selfStyle.bgcolor = element.value
    		end,
    	}
    
    	children[#children+1] = gui.Panel{
    		width = 'auto',
    		height = 'auto',
    		flow = 'horizontal',
    		halign = 'left',
    		iconEditor,
    		iconColorPicker,
    	}
    
    	--keyword description.
    	children[#children+1] = gui.Panel{
    		classes = {"formStackedRow"},
    		gui.Label{
    			classes = {"formStacked"},
    			text = "Details:",
    		},
    		gui.Input{
    			classes = {"formStacked"},
    			text = keyword.description,
    			multiline = true,
    			textAlignment = "topLeft",
    			height = 60,
    			characterLimit = 600,
    			change = function(element)
    				keyword.description = element.text
    				UploadKeyword()
    			end,
    		}
    	}
    
    	--an area marked with this keyword is difficult terrain.
    	children[#children+1] = gui.Panel{
    		classes = {"formStackedRow"},
    		gui.Check{
    			value = keyword:try_get("difficultTerrain", false),
    			text = "Difficult Terrain",
    			change = function(element)
    				keyword.difficultTerrain = element.value
    				UploadKeyword()
    			end,
    		},
    	}
    
    	--an area marked with this keyword is water.
    	children[#children+1] = gui.Panel{
    		classes = {"formStackedRow"},
    		gui.Check{
    			value = keyword:try_get("water", false),
    			text = "Water",
    			change = function(element)
    				keyword.water = element.value
    				UploadKeyword()
    			end,
    		},
    	}
    
    	--an area marked with this keyword grants concealment.
    	children[#children+1] = gui.Panel{
    		classes = {"formStackedRow"},
    		gui.Check{
    			value = keyword:try_get("concealment", false),
    			text = "Concealment",
    			change = function(element)
    				keyword.concealment = element.value
    				UploadKeyword()
    			end,
    		},
    	}
    
    	--an area marked with this keyword can be climbed (like a climbable wall:
    	--creatures in it may climb up to the ceiling of the floor). The second
    	--checkbox restricts it to natural climbers (climb speed >= walk speed),
    	--matching walls' "Climbable (Climbers Only)"; it only shows while
    	--Climbable is checked.
    	local climbersOnlyCheck
    	climbersOnlyCheck = gui.Check{
    		value = keyword:try_get("climbersOnly", false),
    		text = "Climbers Only",
    		hmargin = 24,
    		change = function(element)
    			keyword.climbersOnly = element.value
    			UploadKeyword()
    		end,
    	}
    	if keyword:try_get("climbable", false) ~= true then
    		climbersOnlyCheck:SetClass("collapsed", true)
    	end
    
    	children[#children+1] = gui.Panel{
    		classes = {"formStackedRow"},
    		gui.Check{
    			value = keyword:try_get("climbable", false),
    			text = "Climbable",
    			change = function(element)
    				keyword.climbable = element.value
    				climbersOnlyCheck:SetClass("collapsed", not element.value)
    				UploadKeyword()
    			end,
    		},
    		climbersOnlyCheck,
    	}
    
    	--How far up a zone painted with this keyword reaches, by default. Zone bands
    	--are ground-relative (AuraInstance:GetGroundRelative), so this follows the
    	--terrain: "Ground Only" covers a creature standing in the zone whether the
    	--zone is on flat ground, in a pit, or up on a ledge, and excludes anything
    	--flying over it. Only a DEFAULT -- it is stamped onto zones as they are
    	--painted (MapMarkupPanel CreateZone), and each zone keeps its own height
    	--afterwards, editable in the Edit Zone dialog. Changing it here does not
    	--touch zones already on a map.
    	local defaultHeightMode = "infinite"
    	local storedDefaultHeight = keyword:try_get("defaultHeight")
    	if storedDefaultHeight ~= nil then
    		defaultHeightMode = cond(storedDefaultHeight <= 0, "ground", "amount")
    	end
    
    	--the amount box keeps a usable number even in the modes that hide it, so
    	--switching to Set Amount never lands on a value the change handler rejects.
    	--Its units caption collapses with it: "tiles above the ground" reads as a
    	--claim about the mode when it is left hanging next to Unlimited/Ground Only.
    	local defaultHeightUnits = gui.Label{
    		classes = {"formStacked", "fgMuted", cond(defaultHeightMode ~= "amount", "collapsed")},
    		text = "tiles above the ground",
    	}
    
    	local defaultHeightAmount
    	defaultHeightAmount = gui.Input{
    		classes = {"formStacked", cond(defaultHeightMode ~= "amount", "collapsed")},
    		text = tostring(cond(storedDefaultHeight ~= nil and storedDefaultHeight >= 1, storedDefaultHeight, 2)),
    		characterLimit = 3,
    		change = function(element)
    			local num = tonumber(element.text)
    			if num == nil or num < 1 then
    				element.text = tostring(math.max(1, keyword:try_get("defaultHeight", 2)))
    			else
    				keyword.defaultHeight = math.floor(num)
    				UploadKeyword()
    			end
    		end,
    	}
    
    	children[#children+1] = gui.Panel{
    		classes = {"formStackedRow"},
    		gui.Label{
    			classes = {"formStacked"},
    			text = "Default Height:",
    		},
    		gui.Dropdown{
    			classes = {"formStacked"},
    			idChosen = defaultHeightMode,
    			options = {
    				{id = "infinite", text = "Unlimited"},
    				{id = "ground", text = "Ground Only"},
    				{id = "amount", text = "Set Amount"},
    			},
    			change = function(element)
    				if element.idChosen == "infinite" then
    					keyword.defaultHeight = nil
    				elseif element.idChosen == "ground" then
    					keyword.defaultHeight = 0
    				else
    					local num = tonumber(defaultHeightAmount.text)
    					if num == nil or num < 1 then
    						num = 2
    						defaultHeightAmount.text = "2"
    					end
    					keyword.defaultHeight = math.floor(num)
    				end
    				defaultHeightAmount:SetClass("collapsed", element.idChosen ~= "amount")
    				defaultHeightUnits:SetClass("collapsed", element.idChosen ~= "amount")
    				UploadKeyword()
    			end,
    		},
    		defaultHeightAmount,
    		defaultHeightUnits,
    	}
    
    	--optional visual representation drawn on the map for zones of this type:
    	--a floor-texture fill with an optional edge brush, or per-tile sprites.
    	--Configured in its own dialog; the label summarizes what is set up.
    	local appearanceSummary = gui.Label{
    		classes = {"formStacked", "fgMuted"},
    		text = DescribeAppearance(keyword),
    	}
    	children[#children+1] = gui.Panel{
    		classes = {"formStackedRow"},
    		gui.Label{
    			classes = {"formStacked"},
    			text = "Appearance:",
    		},
    		appearanceSummary,
    		gui.Button{
    			classes = {"sizeM"},
    			halign = "left",
    			text = "Edit Appearance...",
    			click = function(element)
    				ShowAppearanceDialog(keyword, UploadKeyword, function()
    					if appearanceSummary ~= nil and appearanceSummary.valid then
    						appearanceSummary.text = DescribeAppearance(keyword)
    					end
    				end)
    			end,
    		},
    	}
    
    	--optional Lua script: one instance runs on every client for each zone of
    	--this type on the map, with a guaranteed exit routine when the zone goes
    	--away. Edited in its own dialog; the label summarizes what is declared.
    	local scriptSummary = gui.Label{
    		classes = {"formStacked", "fgMuted"},
    		text = ZoneScripts.Describe(keyword),
    	}
    	children[#children+1] = gui.Panel{
    		classes = {"formStackedRow"},
    		gui.Label{
    			classes = {"formStacked"},
    			text = "Script:",
    		},
    		scriptSummary,
    		gui.Button{
    			classes = {"sizeM"},
    			halign = "left",
    			text = "Edit Script...",
    			click = function(element)
    				ZoneScripts.ShowDialog(keyword, UploadKeyword, function()
    					if scriptSummary ~= nil and scriptSummary.valid then
    						scriptSummary.text = ZoneScripts.Describe(keyword)
    					end
    				end)
    			end,
    		},
    	}
    
    	--the area extends one tile outward: creatures adjacent to it count as
    	--touching it for enter/start-of-turn triggers (the entry power roll fires
    	--for them at the start of their turn, with a bane), but adjacent tiles do
    	--not take the keyword's terrain rules, move damage, or modifiers.
    	children[#children+1] = gui.Panel{
    		classes = {"formStackedRow"},
    		gui.Check{
    			value = keyword:try_get("includeAdjacent", false),
    			text = "Affects Adjacent Squares",
    			tooltip = "The area extends one square outward. Creatures adjacent to the area count as touching it for enter and start-of-turn triggers - the entry power roll fires for them at the start of their turn, with a bane - but adjacent squares do not take the keyword's terrain rules, movement damage, or modifiers.",
    			change = function(element)
    				keyword.includeAdjacent = element.value
    				UploadKeyword()
    			end,
    		},
    	}
    
    	--whether the Map Markup zone palette offers the "Dynamic Light" option for
    	--this keyword (zones apply only where map light is below a threshold).
    	--Eligibility only: most keywords (Water, Difficult Terrain) have no use for
    	--it, so the palette stays uncluttered unless a keyword opts in.
    	children[#children+1] = gui.Panel{
    		classes = {"formStackedRow"},
    		gui.Check{
    			value = keyword:try_get("dynamicLight", false),
    			text = "Can Use Dynamic Light",
    			tooltip = "Zones of this type can be set (in the map's Zone Types palette) to only apply where the light level on the map is below a threshold - e.g. Darkness that recedes around a carried torch. Unchecking hides the option and disables any configured threshold without deleting it.",
    			change = function(element)
    				keyword.dynamicLight = element.value
    				UploadKeyword()
    			end,
    		},
    	}
    
    	--keywords this keyword dispels. Painting this keyword over a zone of a
    	--dispelled keyword deletes the overlap (and a dispelled keyword cannot be
    	--painted over this one); an aura carrying this keyword suppresses zones
    	--of dispelled keywords beneath it until the aura moves on or expires.
    	--The list and its add-dropdown live in a self-refreshing sub-panel.
    	children[#children+1] = gui.Panel{
    		classes = {"formStackedRow"},
    		gui.Label{
    			classes = {"formStacked"},
    			text = "Dispels:",
    		},
    		gui.Panel{
    			classes = {"formStacked"},
    			flow = "vertical",
    			height = "auto",
    
    			create = function(element)
    				element:FireEvent("refreshDispels")
    			end,
    
    			refreshDispels = function(element)
    				local listPanel = element
    				local liveTable = dmhub.GetTable(tableName) or {}
    				local rows = {}
    				local dispels = keyword:try_get("dispels", {})
    
    				for i,dispelledId in ipairs(dispels) do
    					local target = liveTable[dispelledId]
    					local targetName = "(deleted keyword)"
    					if target ~= nil and target.name ~= nil then
    						targetName = target.name
    					end
    
    					local index = i
    					rows[#rows+1] = gui.Panel{
    						flow = "horizontal",
    						width = "100%",
    						height = "auto",
    						vmargin = 2,
    						gui.Label{
    							fontSize = 18,
    							width = "80%",
    							height = "auto",
    							halign = "left",
    							valign = "center",
    							text = targetName,
    						},
    						gui.DeleteItemButton{
    							width = 16,
    							height = 16,
    							halign = "right",
    							valign = "center",
    							click = function()
    								local items = keyword:try_get("dispels", {})
    								table.remove(items, index)
    								if #items == 0 then
    									--nil-assignment removes the field from serialization.
    									keyword.dispels = nil
    								else
    									keyword.dispels = items
    								end
    								UploadKeyword()
    								listPanel:FireEvent("refreshDispels")
    							end,
    						},
    					}
    				end
    
    				--keywords that can be added: everything except this keyword,
    				--those already listed, and zone types scoped to another map.
    				local have = {}
    				for _,dispelledId in ipairs(dispels) do
    					have[dispelledId] = true
    				end
    
    				local options = {}
    				for k,other in unhidden_pairs(liveTable) do
    					local mapid = other:try_get("mapid")
    					if k ~= keyid and have[k] == nil and (mapid == nil or mapid == game.currentMapId) then
    						options[#options+1] = { id = k, text = other.name }
    					end
    				end
    				table.sort(options, function(a,b) return a.text < b.text end)
    
    				if #options > 0 then
    					table.insert(options, 1, { id = "none", text = "Add Keyword..." })
    					rows[#rows+1] = gui.Dropdown{
    						classes = {"formStacked"},
    						vmargin = 2,
    						idChosen = "none",
    						options = options,
    						change = function(dropdown)
    							if dropdown.idChosen == "none" then
    								return
    							end
    							local items = keyword:get_or_add("dispels", {})
    							items[#items+1] = dropdown.idChosen
    							keyword.dispels = items
    							UploadKeyword()
    							listPanel:FireEvent("refreshDispels")
    						end,
    					}
    				elseif #rows == 0 then
    					rows[#rows+1] = gui.Label{
    						classes = {"formStacked"},
    						fontSize = 14,
    						text = "No other keywords available.",
    					}
    				end
    
    				listPanel.children = rows
    			end,
    		},
    	}
    
    	--damage dealt to creatures that move through an area with this keyword.
    	--The amount/filter rows only show while a damage type is chosen.
    	local moveDamageDetails
    	children[#children+1] = gui.Panel{
    		classes = {"formStackedRow"},
    		gui.Label{
    			classes = {"formStacked"},
    			text = "Move Damage:",
    		},
    		gui.Dropdown{
    			classes = {"formStacked"},
    			idChosen = keyword:try_get("movedamage", "none"),
    			options = table.append_arrays({{id = "none", text = "none"}}, map(rules.damageTypesAvailable, function(a) return {id = a, text = a} end)),
    			change = function(element)
    				keyword.movedamage = element.idChosen
    				moveDamageDetails:SetClass("collapsed", element.idChosen == "none")
    				UploadKeyword()
    			end,
    		},
    	}
    
    	moveDamageDetails = gui.Panel{
    		classes = {"formStackedRow", cond(keyword:try_get("movedamage", "none") == "none", "collapsed")},
    		gui.Label{
    			classes = {"formStacked"},
    			text = "Damage Per Tile:",
    		},
    		gui.Input{
    			classes = {"formStacked"},
    			text = tostring(keyword:try_get("damage", 0)),
    			characterLimit = 4,
    			change = function(element)
    				local num = tonumber(element.text)
    				if num == nil then
    					element.text = tostring(keyword:try_get("damage", 0))
    				else
    					keyword.damage = num
    					UploadKeyword()
    				end
    			end,
    		},
    		gui.Label{
    			classes = {"formStacked"},
    			text = "Applies To:",
    		},
    		gui.Dropdown{
    			classes = {"formStacked"},
    			idChosen = keyword:try_get("movementDamageFilter", "all"),
    			options = {
    				{id = "all", text = "All Movement"},
    				{id = "nonshift", text = "Non-Shifting Movement"},
    				{id = "forced", text = "Forced Movement Only"},
    			},
    			change = function(element)
    				keyword.movementDamageFilter = element.idChosen
    				UploadKeyword()
    			end,
    		},
    	}
    	children[#children+1] = moveDamageDetails
    
    	--optional GoblinScript restricting who the keyword affects. Covers the whole
    	--keyword, terrain rules included: the engine keeps a filtered aura out of the
    	--per-tile rules lookup and decides it per creature instead (Aura.ApplyTo ->
    	--AuraInstance:CreaturePassesFilterForToken).
    	children[#children+1] = gui.Panel{
    		classes = {"formStackedRow"},
    		gui.Label{
    			classes = {"formStacked"},
    			text = "Affects Only:",
    			hover = gui.Tooltip("Optional filter. When set, only creatures this GoblinScript returns true for are affected by the keyword at all - its terrain rules, movement damage, power roll and modifiers alike. Leave it empty to affect everyone."),
    		},
    		gui.GoblinScriptInput{
    			classes = {"formStacked"},
    			value = keyword:try_get("creatureFilter", ""),
    			--plain text only: the widget's right-click menu otherwise offers the
    			--level-tiered table form, which means nothing for an environmental
    			--keyword (there is no level context) and would break the string merge
    			--in ApplyToAura.
    			displayTypes = "none",
    			change = function(element)
    				keyword.creatureFilter = element.value
    				UploadKeyword()
    			end,
    			documentation = {
    				help = "This GoblinScript determines which creatures this environmental keyword affects. It is evaluated for each creature in an area marked with the keyword, and none of the keyword takes hold unless it returns true - terrain rules, movement damage, power roll and modifiers alike. An empty script affects every creature.",
    				output = "boolean",
    				examples = {
    					{
    						script = 'not (Keywords has "Fire")',
    						text = "Only creatures that are not themselves Fire creatures are affected -- a fire elemental wades through its own element unharmed.",
    					},
    					{
    						script = 'OnGround',
    						text = "Only creatures on the ground are affected; anything flying, burrowing, or climbing over the area is not.",
    					},
    				},
    				subject = creature.helpSymbols,
    				subjectDescription = "Creature in the area marked with this keyword.",
    				symbols = {
    					target = {
    						name = "Target",
    						type = "creature",
    						desc = "The creature being tested. A synonym for 'Self' in this script.",
    					},
    					caster = {
    						name = "Caster",
    						type = "creature",
    						desc = "The creature that created the area, when it came from an ability. Painted map zones have no caster.",
    					},
    					aura = {
    						name = "Aura",
    						type = "aura",
    						desc = "The area applying this keyword.",
    					},
    				},
    			},
    		},
    	}
    
    	--Draw Steel's 2d10 environmental power-roll editor is intentionally absent in d20.
    
    	--list of modifiers that this keyword applies to affected creatures.
    	children[#children+1] = gui.Panel{
    		width = 800,
    		height = "auto",
    		halign = "left",
    		styles = {
    			{
    				selectors = {"namePanel"},
    				collapsed = 1,
    			},
    			{
    				selectors = {"sourcePanel"},
    				collapsed = 1,
    			},
    			{
    				selectors = {"descriptionPanel"},
    				collapsed = 1,
    			},
    		},
    
    		keyword:EditorPanel{
    			noscroll = true,
    			modifierRefreshed = function(element)
    				UploadKeyword()
    			end,
    		},
    	}
    
    	keywordPanel.children = children
    end
    
    --- @param options nil|{width: number|string, height: number|string} Optional size overrides (the compendium default is 1200 x 90%).
    function EnvironmentalKeyword.CreateEditor(options)
    	options = options or {}
    	local keywordPanel
    	keywordPanel = gui.Panel{
    		data = {
    			SetData = function(tableName, keyid)
    				SetData(tableName, keywordPanel, keyid)
    			end,
    			keyid = "",
    			keywordjson = "",
    		},
    		destroy = function(element)
    			local dataTable = dmhub.GetTable(EnvironmentalKeyword.tableName) or {}
    
    			--if the keyword changed, then upload it.
    			if element.data.keyid ~= "" and dmhub.ToJson(dataTable[element.data.keyid]) ~= element.data.keywordjson then
    				UploadKeywordWithId(element.data.keyid)
    			end
    		end,
    		vscroll = true,
    		width = options.width or 1200,
    		height = options.height or "90%",
    		halign = "left",
    		flow = "vertical",
    		pad = 20,
    		borderBox = true,
    	}
    
    	return keywordPanel
    end
    
    --- Opens the keyword editor in a modal dialog: the same editor the compendium
    --- shows, framed for use outside the compendium (the Map Markup panel's Zone
    --- Types interface uses this for its settings cog). Changes save as they are
    --- made; Close just dismisses.
    --- @param keyid string Id of the keyword in the environmentalKeywords table.
    function EnvironmentalKeyword.ShowEditDialog(keyid)
    	local keywordPanel = EnvironmentalKeyword.CreateEditor{
    		width = "100%",
    		height = "100%-110",
    	}
    
    	local dialogPanel = gui.Panel{
    		id = "EnvironmentalKeywordDialog",
    		classes = {"framedPanel"},
    		styles = ThemeEngine.GetStyles(),
    		width = 900,
    		height = "90%",
    		pad = 16,
    		borderBox = true,
    		flow = "vertical",
    		halign = "center",
    		valign = "center",
    
    		captureEscape = true,
    		escapePriority = EscapePriority.EXIT_MODAL_DIALOG,
    		escape = function(element)
    			gui.CloseModal()
    		end,
    
    		gui.Label{
    			classes = {"dialogTitle"},
    			text = "Edit Zone Type",
    		},
    
    		keywordPanel,
    
    		gui.Button{
    			classes = {"sizeM"},
    			text = "Close",
    			halign = "center",
    			valign = "bottom",
    			vmargin = 8,
    			click = function(element)
    				gui.CloseModal()
    			end,
    		},
    	}
    
    	--attach the dialog before populating it: if SetData ever errors, the
    	--panel must not be left orphaned.
    	gui.ShowModal(dialogPanel)
    
    	keywordPanel.data.SetData(EnvironmentalKeyword.tableName, keyid)
    end
    
    --- @param contentPanel Panel
    local ShowEnvironmentalKeywordsPanel = function(contentPanel)
    	local keywordPanel = EnvironmentalKeyword.CreateEditor()
    	local SetData = keywordPanel.data.SetData
    
    	local listItems = {}
    
    	local itemsListPanel
    	itemsListPanel = gui.Panel{
    		classes = {'list-panel'},
    		vscroll = true,
    		monitorAssets = true,
    		refreshAssets = function(element)
    			local children = {}
    			local dataTable = dmhub.GetTable(EnvironmentalKeyword.tableName) or {}
    			local newListItems = {}
    
    			for k,item in pairs(dataTable) do
    				--map-scoped zone types stay out of the compendium until promoted.
    				if item:try_get("mapid") == nil then
    					newListItems[k] = listItems[k] or Compendium.CreateListItem{
    						select = element.aliveTime > 0.2,
    						tableName = EnvironmentalKeyword.tableName,
    						key = k,
    						click = function()
    							SetData(EnvironmentalKeyword.tableName, k)
    						end,
    					}
    
    					newListItems[k].text = item.name
    
    					children[#children+1] = newListItems[k]
    				end
    			end
    
    			table.sort(children, function(a,b) return a.text < b.text end)
    
    			listItems = newListItems
    			itemsListPanel.children = children
    		end,
    	}
    
    	itemsListPanel:FireEvent('refreshAssets')
    
    	local leftPanel = gui.Panel{
    		selfStyle = {
    			flow = 'vertical',
    			height = '100%',
    			width = 'auto',
    		},
    
    		itemsListPanel,
    		Compendium.AddButton{
    			click = function(element)
    				dmhub.SetAndUploadTableItem(EnvironmentalKeyword.tableName, EnvironmentalKeyword.CreateNew())
    			end,
    		}
    	}
    
    	contentPanel.children = {leftPanel, keywordPanel}
    end
    
    Compendium.Register{
    	section = "Rules",
    	text = "Environmental Keywords",
    	contentType = EnvironmentalKeyword.tableName,
    	click = function(contentPanel)
    		ShowEnvironmentalKeywordsPanel(contentPanel)
    	end,
    }
    
    dmhub.RegisterEventHandler("refreshTables", function()
    	local byName = {}
    	local dataTable = dmhub.GetTable(EnvironmentalKeyword.tableName) or {}
    	for k,v in unhidden_pairs(dataTable) do
    		byName[string.lower(v.name)] = v
    	end
    	EnvironmentalKeyword.keywordsByName = byName
    end)

    return EnvironmentalKeyword
end

-- d20 footstep registry and playback used by the panel's Footsteps tab.
function DMHubMapMarkupD20.IsProne(props)
    if props == nil then
        return false
    end
    local conditionsType = rawget(_G, "CharacterCondition")
    if conditionsType ~= nil then
        local conditions = dmhub.GetTable(conditionsType.tableName) or {}
        for conditionid,condition in unhidden_pairs(conditions) do
            if string.lower(condition.name or "") == "prone"
                and props:HasCondition(conditionid) then
                return true
            end
        end
    end
    local down = false
    pcall(function() down = props:IsDown() end)
    return down
end

function DMHubMapMarkupD20.InstallFootsteps()
    if DMHubMapMarkupD20.footstepsInstalled then
        return
    end
    if rawget(_G, "audio") == nil then
        return
    end

    --d20 predates the shared audio module. Own the footstep resources here
    --and register the standalone volume bus that every event below uses.
    audio.RegisterAudioMod(mod)
    audio.MixGroup{
        id = "footsteps",
        name = tr("Footsteps"),
    }

    DMHubMapMarkupD20.footstepsInstalled = true

    AudioSurfaceTypes = rawget(_G, "AudioSurfaceTypes") or {
        surfaces = {
            { id = 1, text = "Generic", sound = "Foot.Generic_Generic" },
            { id = 2, text = "Dirt", sound = "Foot.Generic_Dirt" },
            { id = 3, text = "Grass", sound = "Foot.Generic_Grass" },
            { id = 4, text = "Hollow Metal", sound = "Foot.Generic_MetalHollow" },
            { id = 5, text = "Solid Metal", sound = "Foot.Generic_MetalSolid" },
            { id = 6, text = "Stone", sound = "Foot.Generic_Stone" },
            { id = 7, text = "Wood", sound = "Foot.Generic_Wood" },
            { id = 8, text = "Puddle", sound = "Foot.Generic_Dirt", puddleSound = true },
            { id = 9, text = "Snow", sound = "Foot.Generic_Snow" },
        },
    }

    --Footsteps
    
    --Generic Boot Generic Surface
    audio.SoundEvent{
        name = "Foot.Generic_Generic",
        mixgroup = "footsteps",
        sounds = {"foot/FS_Walk_Gnrc_Gnrc_v1_01.wav","foot/FS_Walk_Gnrc_Gnrc_v1_02.wav","foot/FS_Walk_Gnrc_Gnrc_v1_03.wav","foot/FS_Walk_Gnrc_Gnrc_v1_04.wav","foot/FS_Walk_Gnrc_Gnrc_v1_05.wav","foot/FS_Walk_Gnrc_Gnrc_v1_06.wav"},
        volume = 0.15,
        pitchRand = 0.3,
        ignoreDuplicates = 0.05,
    }
    
    audio.SoundEvent{
        name = "Foot.Generic_Dirt",
        mixgroup = "footsteps",
        sounds = {"foot/FS_Walk_Gnrc_Dirt_v1_01.wav","foot/FS_Walk_Gnrc_Dirt_v1_02.wav","foot/FS_Walk_Gnrc_Dirt_v1_03.wav","foot/FS_Walk_Gnrc_Dirt_v1_04.wav","foot/FS_Walk_Gnrc_Dirt_v1_05.wav","foot/FS_Walk_Gnrc_Dirt_v1_06.wav"},
        volume = 0.15,
        pitchRand = 0.3,
        ignoreDuplicates = 0.05,
    }
    
    audio.SoundEvent{
        name = "Foot.Generic_Grass",
        mixgroup = "footsteps",
        sounds = {"foot/FS_Walk_Gnrc_Grass_v1_01.wav","foot/FS_Walk_Gnrc_Grass_v1_02.wav","foot/FS_Walk_Gnrc_Grass_v1_03.wav","foot/FS_Walk_Gnrc_Grass_v1_04.wav","foot/FS_Walk_Gnrc_Grass_v1_05.wav","foot/FS_Walk_Gnrc_Grass_v1_06.wav"},
        volume = 0.1,
        pitchRand = 0.3,
        ignoreDuplicates = 0.05,
    }
    
    audio.SoundEvent{
        name = "Foot.Generic_MetalHollow",
        mixgroup = "footsteps",
        sounds = {"foot/FS_Walk_Gnrc_MetalHollow_v1_01.wav","foot/FS_Walk_Gnrc_MetalHollow_v1_02.wav","foot/FS_Walk_Gnrc_MetalHollow_v1_03.wav","foot/FS_Walk_Gnrc_MetalHollow_v1_04.wav","foot/FS_Walk_Gnrc_MetalHollow_v1_05.wav","foot/FS_Walk_Gnrc_MetalHollow_v1_06.wav"},
        volume = 0.15,
        pitchRand = 0.3,
        ignoreDuplicates = 0.05,
    }
    
    audio.SoundEvent{
        name = "Foot.Generic_MetalSolid",
        mixgroup = "footsteps",
        sounds = {"foot/FS_Walk_Gnrc_MetalSolid_v1_01.wav","foot/FS_Walk_Gnrc_MetalSolid_v1_02.wav","foot/FS_Walk_Gnrc_MetalSolid_v1_03.wav","foot/FS_Walk_Gnrc_MetalSolid_v1_04.wav","foot/FS_Walk_Gnrc_MetalSolid_v1_05.wav","foot/FS_Walk_Gnrc_MetalSolid_v1_06.wav"},
        volume = 0.15,
        pitchRand = 0.3,
        ignoreDuplicates = 0.05,
    }
    
    audio.SoundEvent{
        name = "Foot.Generic_Stone",
        mixgroup = "footsteps",
        sounds = {"foot/FS_Walk_Gnrc_Stone_v1_01.wav","foot/FS_Walk_Gnrc_Stone_v1_02.wav","foot/FS_Walk_Gnrc_Stone_v1_03.wav","foot/FS_Walk_Gnrc_Stone_v1_04.wav","foot/FS_Walk_Gnrc_Stone_v1_05.wav","foot/FS_Walk_Gnrc_Stone_v1_06.wav"},
        volume = 0.15,
        pitchRand = 0.3,
        --ignoreDuplicates = 0.05,
    }
    
    audio.SoundEvent{
        name = "Foot.Generic_Wood",
        mixgroup = "footsteps",
        sounds = {"foot/FS_Walk_Gnrc_Wood_v1_01.wav","foot/FS_Walk_Gnrc_Wood_v1_02.wav","foot/FS_Walk_Gnrc_Wood_v1_03.wav","foot/FS_Walk_Gnrc_Wood_v1_04.wav","foot/FS_Walk_Gnrc_Wood_v1_05.wav","foot/FS_Walk_Gnrc_Wood_v1_06.wav"},
        volume = 0.15,
        pitchRand = 0.3,
        ignoreDuplicates = 0.05,
    }
    
    audio.SoundEvent{
        name = "Foot.Generic_Snow",
        mixgroup = "footsteps",
        sounds = {"foot/FS_Walk_Gnrc_Snow_v1_01.wav","foot/FS_Walk_Gnrc_Snow_v1_02.wav","foot/FS_Walk_Gnrc_Snow_v1_03.wav","foot/FS_Walk_Gnrc_Snow_v1_04.wav","foot/FS_Walk_Gnrc_Snow_v1_05.wav","foot/FS_Walk_Gnrc_Snow_v1_06.wav"},
        volume = 0.15,
        pitchRand = 0.3,
        ignoreDuplicates = 0.05,
    }
    
    audio.SoundEvent{
        name = "Foot.Stairwell",
        mixgroup = "footsteps",
        play = function()
            audio.FireSoundEvent("Foot.Generic_Stone")
            audio.FireSoundEvent("Foot.Generic_Stone", {
                delay = 0.1,
                pitch = 1.2,
                volume = 0.8,
            })
            audio.FireSoundEvent("Foot.Generic_Stone", {
                delay = 0.2,
                pitch = 1.4,
                volume = 0.6,
            })
        end,
    }
    
    
    
    
    
    
    
    
    --Other locomotion actions
    
    audio.SoundEvent{
        name = "Foot.Fly_Wing",
        mixgroup = "footsteps",
        sounds = {"foot/FS_Fly_Wing_Gnrc_v1_01.wav","foot/FS_Fly_Wing_Gnrc_v1_02.wav","foot/FS_Fly_Wing_Gnrc_v1_03.wav","foot/FS_Fly_Wing_Gnrc_v1_04.wav","foot/FS_Fly_Wing_Gnrc_v1_05.wav","foot/FS_Fly_Wing_Gnrc_v1_06.wav","foot/FS_Fly_Wing_Gnrc_v1_07.wav","foot/FS_Fly_Wing_Gnrc_v1_08.wav","foot/FS_Fly_Wing_Gnrc_v1_09.wav","foot/FS_Fly_Wing_Gnrc_v1_10.wav"},
        volume = 0.15,
        pitchRand = 0.15,
        ignoreDuplicates = 0.3,
    }
    
    audio.SoundEvent{
        name = "Foot.Swim_Generic",
        mixgroup = "footsteps",
        sounds = {"foot/FS_Swim_Gnrc_v1_01.wav","foot/FS_Swim_Gnrc_v1_02.wav","foot/FS_Swim_Gnrc_v1_03.wav","foot/FS_Swim_Gnrc_v1_04.wav","foot/FS_Swim_Gnrc_v1_05.wav","foot/FS_Swim_Gnrc_v1_06.wav","foot/FS_Swim_Gnrc_v1_07.wav","foot/FS_Swim_Gnrc_v1_08.wav","foot/FS_Swim_Gnrc_v1_09.wav","foot/FS_Swim_Gnrc_v1_10.wav"},
        volume = 0.12,
        pitchRand = 0.1,
        ignoreDuplicates = 0.3,
    }
    
    audio.SoundEvent{
        name = "Foot.Crawl_Generic",
        mixgroup = "footsteps",
        sounds = {"foot/FS_Crawl_Gnrc_v1_01.wav","foot/FS_Crawl_Gnrc_v1_02.wav","foot/FS_Crawl_Gnrc_v1_03.wav","foot/FS_Crawl_Gnrc_v1_04.wav","foot/FS_Crawl_Gnrc_v1_05.wav","foot/FS_Crawl_Gnrc_v1_06.wav"},
        volume = 0.06,
        pitchRand = 0.1,
        ignoreDuplicates = 0.2,
    }
    
    audio.SoundEvent{
        name = "Foot.Burrow_Generic",
        mixgroup = "footsteps",
        sounds = {"foot/FS_Burrow_Gnrc_v1_01.wav","foot/FS_Burrow_Gnrc_v1_02.wav","foot/FS_Burrow_Gnrc_v1_03.wav","foot/FS_Burrow_Gnrc_v1_04.wav","foot/FS_Burrow_Gnrc_v1_05.wav","foot/FS_Burrow_Gnrc_v1_06.wav"},
        volume = 0.08,
        pitchRand = 0.1,
        ignoreDuplicates = 0.2,
    }
    
    audio.SoundEvent{
        name = "Foot.Float_Generic",
        mixgroup = "footsteps",
        sounds = {"foot/FS_Float_Gnrc_v1_01.wav","foot/FS_Float_Gnrc_v1_02.wav","foot/FS_Float_Gnrc_v1_03.wav","foot/FS_Float_Gnrc_v1_04.wav","foot/FS_Float_Gnrc_v1_05.wav","foot/FS_Float_Gnrc_v1_06.wav"},
        volume = 0.08,
        pitchRand = 0.0,
        ignoreDuplicates = 0.5,
    }
    
    
    
    
    
    audio.SoundEvent{
        name = "Foot.Climb_Generic",
        mixgroup = "footsteps",
        sounds = {"foot/Fol_Climb_Start_v1_01.wav"},
        volume = 0.08,
        pitchRand = 0.1,
        ignoreDuplicates = 0.2,
    }

    dmhub.TokenMovingOnPath = function(args)
        local surface = args.path:GetStepSurfaceType(args.stepIndex) or 0
        local surfaceInfo = AudioSurfaceTypes.surfaces[surface]
    
        --Map Markup footsteps (MapMarkupPanel.lua): a tile inside a PAINTED
        --footstep region keeps its stamped surface; on any other ground the
        --map's default footstep surface, when one is set, overrides the
        --tile-derived surface (map backgrounds often carry a surfaceType of
        --their own - the default is what the DM says this map's ground sounds
        --like). The Settings-registry check keeps this quiet (no engine error
        --log per step) when the MapMarkup module, which registers the setting,
        --isn't loaded.
        local painted = nil
        pcall(function()
            local markup = rawget(_G, "MapMarkupFootsteps")
            if markup ~= nil and args.position ~= nil then
                painted = markup.GetPaintedSurfaceAt(args.token.floorid,
                    math.floor(args.position.x + 0.5), math.floor(args.position.y + 0.5))
            end
        end)
        if painted ~= nil and AudioSurfaceTypes.surfaces[painted] ~= nil then
            surfaceInfo = AudioSurfaceTypes.surfaces[painted]
        else
            local settingsTable = rawget(_G, "Settings")
            if settingsTable ~= nil and settingsTable["markup:footstepdefault"] ~= nil then
                local okDefault, defaultSurface = pcall(function()
                    return tonumber(dmhub.GetSettingValue("markup:footstepdefault"))
                end)
                if okDefault and defaultSurface ~= nil and AudioSurfaceTypes.surfaces[defaultSurface] ~= nil then
                    surfaceInfo = AudioSurfaceTypes.surfaces[defaultSurface]
                end
            end
        end
        surfaceInfo = surfaceInfo or {}
    
        local flags = args.path:GetStepFlags(args.stepIndex)
        local inwater = table.contains(flags or {}, "Water")
        local flying = args.path.movementType == "fly"
        local burrowing = args.path.movementType == "burrow"
        --NOTE: painted footstep surfaces are deliberately LOWER priority than
        --real conditions - the dispatch below checks flying / burrowing / water
        --before ever using the surface sound.
        local sound = surfaceInfo.sound or "Foot.Generic_Generic"
    
        local puddle = surfaceInfo.puddleSound
    
        if flying then
           sound = "Foot.Fly_Wing"
        elseif burrowing then
           sound = "Foot.Burrow_Generic"
        elseif inwater then
           sound = "Foot.Swim_Generic"
        elseif DMHubMapMarkupD20.IsProne(args.token.properties) then
            sound = "Foot.Crawl_Generic"
        end
    
        if burrowing or flying or inwater or args.path.movementType == "walk" or args.path.movementType == "swim" or args.path.movementType == "shift" then
            --the size of the creature. Use the raw token radius squared to emphasize
            --large creatures being large.
            --local creatureSize = args.token.radiusInTiles*args.token.radiusInTiles
    
            --trying out raw token radius added to itself so the value range is smaller between largest and smallest
            local creatureSize = args.token.radiusInTiles+args.token.radiusInTiles
    
    
            --how many seconds between footsteps. Larger creatures
            --will play less frequent footsteps.
            local playFrequency = 2.0*creatureSize
            
    
            --make it so the first footstep plays quickly, to ensure we
            --get at least one footstep and to make sure that there is a quick
            --audible response to moving.
            if args.lastPlayed == nil then
                playFrequency = playFrequency*0.1
            end
    
            --the larger the creature, the louder their footsteps.
            local volumeScale = creatureSize*1.5
    
            if args.path.movementType == "shift" then
                --when shifting we play footsteps at a lower volume and frequency
                volumeScale = volumeScale * 0.3
                playFrequency = playFrequency * 1.2
            end
    
            --as creatures get larger, their footsteps become deeper.
            local pitch = math.max(0.5, 1.8 - args.token.radiusInTiles*1.6)
    
    
            
            if args.distanceMoved - (args.lastPlayed or 0) >= playFrequency then
                audio.FireSoundEvent(sound, {
                    volume = volumeScale,
                    pitch = pitch,
                })
    
                if puddle then
                    audio.FireSoundEvent("Foot.Swim_Generic", {
                        volume = volumeScale*0.4,
                        pitch = pitch,
                    })
                end
    
                args.lastPlayed = (args.lastPlayed or 0) + playFrequency
            end
        end
    end
end

DMHubMapMarkupD20.InstallFootsteps()

--Modern map-overlay preferences consumed by the engine and the panel feed.
--The legacy d20 system only registered tileheight:overlay, so carry the
--source migration here with the feature that needs the split settings.
setting{
    id = "mapoverlay:walls",
    description = "Show Walls",
    help = "Draws the map's walls as lines colored by the cover they grant: black for full cover, greys for partial cover.",
    storage = "preference",
    section = "Map",
    editor = "check",
    default = false,
}

setting{
    id = "mapoverlay:elevation",
    description = "Show Elevation",
    help = "Draws contour lines wherever tile elevation changes, and an integer height label inside each region.",
    storage = "preference",
    section = "Map",
    editor = "check",
    default = false,
}

setting{
    id = "mapoverlay:hiddenzones",
    description = "Hidden Map Overlay Zone Types",
    storage = "preference",
    default = "",
}

setting{
    id = "mapoverlay:shownbuiltins",
    description = "Shown Built-in Terrain Types",
    storage = "preference",
    default = "",
}

setting{
    id = "mapoverlay:migrated",
    description = "Map overlay settings migrated",
    storage = "preference",
    default = false,
}

if not dmhub.GetSettingValue("mapoverlay:migrated") then
    dmhub.SetSettingValue("mapoverlay:migrated", true)
    if dmhub.GetSettingValue("tileheight:overlay") then
        dmhub.SetSettingValue("mapoverlay:walls", true)
        dmhub.SetSettingValue("mapoverlay:elevation", true)
        dmhub.SetSettingValue("mapoverlay:shownbuiltins", "climbable;concealment;difficult;water")
    end
end


--============================================================================
--Map Markup panel: mark up an imported map image with the gameplay layer
--(walls, doors, zones, surfaces, elevation, props) without touching the
--map's art. Design brief:
--  docs/superpowers/specs/2026-07-22-map-markup-panel-design.md
--
--This file implements the panel shell (mode tabs), the Walls mode, the
--Zones mode and the Footsteps mode (including the zone/surface storage/
--aura/overlay runtime, which runs on every client whether or not the panel
--is open). Footsteps (mode id "surfaces") paints footstep-SOUND regions:
--it only affects the footstep sounds played for creatures moving there.
--Props is a placeholder tab for now.
--
--How wall drawing works: the engine polls dmhub.GetSelectedWall every frame
--(DMSheetHud.selectedWallId). The Building editor publishes its selection
--when it has focus; we chain onto the same hook and publish our selected
--markup wall when this panel has focus instead. Since we never publish a
--floor, the engine is in walls-only mode, where the shape tool draws open
--polylines - which is exactly the markup "Line" tool.
--============================================================================

local function track(eventType, fields)
    if dmhub.GetSettingValue("telemetry_enabled") == false then
        return
    end
    fields.type = eventType
    fields.userid = dmhub.userid
    fields.gameid = dmhub.gameid
    fields.version = dmhub.version
    analytics.Event(fields)
end

--============================================================================
--"Fade Map": dims the whole map so the markup being drawn stands out instead
--of competing with busy map art. Purely a local viewing aid - not map data,
--and never seen by players.
--
--The engine reads this setting DIRECTLY (SettingsManager.GetFloatOptional in
--TileHeightOverlay.Update), so there is nothing to feed through
--dmhub.GetMarkupZones and no revision to bump; the slider's live
--PreviewSettingValue during a drag is picked up on the very next frame.
--MapFadeOverlay.cs applies it, gated on the panel actually being open, so a
--value left on the slider cannot follow the Director back to the table.
--
--`transient`, deliberately, NOT a preference: a fade left near the top blacks
--the map out with no on-screen explanation, and the only control that undoes
--it is the last row of a panel that can run off the bottom of the screen.
--Bug 327JQQFP was exactly that - a value set in some earlier session made the
--map render as an unexplained void every time the panel was opened, session
--after session. Runtime-only means the worst case now lasts until restart,
--and every fresh launch starts unfaded.
--
--No `section`, so it stays out of the global Settings screen - it does
--nothing with this panel closed, and CreateSettingsEditorsForSection only
--picks up settings that declare one.
--============================================================================
setting{
    id = "markup:fade",
    description = "Fade Map",
    help = "Dims the map - terrain, walls, objects, tokens and all - so the markup you are drawing stands out. Only applies while this panel is open.",
    storage = "transient",
    editor = "slider",
    default = 0,
    min = 0,
    max = 1,
    percent = true,
}

--The Core invisible ("see-thru") wall asset markup wall types are duplicated
--from. Wall assets require an image (ImageAsset.ValidationCheck), so presets
--cannot be created from scratch; we duplicate this invisible base and set
--gameplay fields on the copy. Same asset MapImport uses for invisible walls.
local BASE_INVISIBLE_WALL_ID = "eae7f3fe-d278-455c-853a-ac43f948c743"

--The Core "Invisible Floor" tilesheet (invisible=true, Building layer): the
--shared TOP face of every markup solid block. The top face of an invisible
--tilesheet never renders on player clients (and only faintly for the DM while
--an editing tool is open), so one shared sheet serves every solid type - the
--per-type differences live entirely in the wall asset.
local INVISIBLE_TILESHEET_ID = "-MGAVDxkFE-ZzzNYBV0D"

--============================================================================
--Openable walls (doors).
--
--An "openable" wall type is an ordinary markup wall type with
--WallAsset.openable set: it draws REAL wall geometry with the normal thin
--wall tools, so the full drawn stroke blocks exactly like any wall of its
--type. What openable adds is per-stroke door state, engine-side: every
--building operation drawn with an openable wall type is a door. The engine
--(MarkupDoorController) floats a door icon at the operation's midpoint -
--always for the Director, and for players whose token is within 2 tiles
--with line of sight. Clicking it toggles the operation's doorOpen flag
--(clone op + fresh timestamp + patch swap, the Points-tool pattern), and an
--OPEN door op simply contributes no walls at all
--(TerrainLayerInfo.ApplyWallOperation skips it), so movement, vision,
--light, cover and sound occlusion all stop at once and undo/multiplayer
--sync are free. The Director can right-click the icon to lock/unlock the
--door (padlock badge; players see the icon but cannot use it). The open and
--close sounds come from the wall asset (openSound/closeSound) and play as
--networked game sound events.
--============================================================================

--Draw Steel door open/close audio assets (data/audio/ds-opendoor-wav.yaml /
--ds-closedoor-wav.yaml), stamped onto openable wall assets so the engine's
--door toggle plays them for every client.
local DOOR_OPEN_SOUND_ID = "f6bc62cc-7225-48cf-b719-b86280ea198d"
local DOOR_CLOSE_SOUND_ID = "e9950541-0c22-41d3-baba-f7f307b3e81a"

--Gameplay fields stamped on the wall asset backing a new openable type: a
--closed door blocks like a stone wall; opening it disables all of this.
local DOOR_TYPE_FIELDS = {
    blocksMovement = true,
    blocksForcedMovement = true,
    occludesVision = true,
    occludesLight = true,
    cover = "Full",
    soundOcclusion = 0.9,
    climbable = "NotClimbable",
    openable = true,
}

--Preset roster from the design brief (section 4; stats PROPOSED pending
--sign-off). height is the per-placement wall height stamped into the height
--setting when the preset is selected (nil = full height); wall height is a
--property of the drawing operation, not of the wall asset.
local WALL_PRESETS = {
    {
        key = "stone",
        name = "Stone Wall",
        summary = "Blocks all - full cover",
        height = nil,
        fields = {
            blocksMovement = true,
            blocksForcedMovement = true,
            occludesVision = true,
            occludesLight = true,
            cover = "Full",
            soundOcclusion = 0.9,
            climbable = "NotClimbable",
        },
    },
    {
        key = "window",
        name = "Window",
        summary = "See-through - half cover",
        height = nil,
        fields = {
            blocksMovement = true,
            blocksForcedMovement = true,
            occludesVision = false,
            occludesLight = false,
            cover = "Half",
            soundOcclusion = 0.5,
            climbable = "NotClimbable",
        },
    },
    {
        key = "fence",
        name = "Wooden Fence",
        summary = "Height 1 - climbable",
        height = 1,
        fields = {
            blocksMovement = true,
            blocksForcedMovement = true,
            occludesVision = false,
            occludesLight = false,
            cover = "Half",
            soundOcclusion = 0.1,
            climbable = "AllCreatures",
        },
    },
    {
        key = "lowwall",
        name = "Low Wall",
        summary = "Height 1 - half cover",
        height = 1,
        fields = {
            blocksMovement = true,
            blocksForcedMovement = true,
            occludesVision = false,
            occludesLight = false,
            cover = "Half",
            soundOcclusion = 0.2,
            climbable = "AllCreatures",
        },
    },
    {
        key = "curtain",
        name = "Curtain",
        summary = "Blocks sight only",
        height = nil,
        fields = {
            blocksMovement = false,
            blocksForcedMovement = false,
            occludesVision = true,
            occludesLight = true,
            cover = "None",
            soundOcclusion = 0.3,
            climbable = "NotClimbable",
        },
    },
    {
        key = "barrier",
        name = "Invisible Barrier",
        summary = "Blocks movement only",
        height = nil,
        fields = {
            blocksMovement = true,
            blocksForcedMovement = true,
            occludesVision = false,
            occludesLight = false,
            cover = "None",
            soundOcclusion = 0,
            climbable = "NotClimbable",
        },
    },
}

local WALL_PRESETS_BY_KEY = {}
for _,preset in ipairs(WALL_PRESETS) do
    WALL_PRESETS_BY_KEY[preset.key] = preset
end

--============================================================================
--Breakability. Any markup wall - thin or solid - can be made breakable: a
--creature shoved into it with enough force smashes through instead of
--stopping. The force needed is the wall's breakStamina.
--
--The material is DERIVED from breakStamina rather than stored: the wall asset
--has no material field, and 1/3/6 map back to Glass/Wood/Stone unambiguously.
--Anything else reads as Custom, so a hand-typed value round-trips as Custom
--and a typed 3 simply reads back as Wood (which it is, mechanically).
--============================================================================

local BREAK_MATERIALS = {
    {
        id = "glass",
        text = "Glass",
        stamina = 1,
    },
    {
        id = "wood",
        text = "Wood",
        stamina = 3,
    },
    {
        id = "stone",
        text = "Stone",
        stamina = 6,
    },
    {
        id = "custom",
        text = "Custom",
        stamina = nil,
    },
}

local DEFAULT_BREAK_STAMINA = 3

local function BreakMaterialForStamina(stamina)
    for _,material in ipairs(BREAK_MATERIALS) do
        if material.stamina ~= nil and material.stamina == stamina then
            return material.id
        end
    end
    return "custom"
end

local function BreakMaterialById(id)
    for _,material in ipairs(BREAK_MATERIALS) do
        if material.id == id then
            return material
        end
    end
    return nil
end

local function AssetIsBreakable(asset)
    return asset ~= nil and asset.solidity ~= "Unbreakable" and (asset.breakStamina or 0) > 0
end

--Writes breakability onto a wall asset.
--
--`solidity` is the engine's BREAK BEHAVIOR selector, not a "is this a solid
--block" flag: WallSolidity.Thin punches a hole through a thin wall,
--WallSolidity.Solid tunnels a cavity through a filled block. Since a markup
--wall type can now be drawn EITHER way, the asset can't know which applies -
--so markup walls are marked Thin and the engine picks the cavity branch from
--the drawn geometry instead (a broken wall that bounds a real solid region
--carves). See MAP_MARKUP_REFERENCE.md "Breakability".
--
--rubble fields stay empty: smashing an invisible wall over imported art must
--not spawn visible debris the DM never placed.
local function SetAssetBreakable(asset, breakable, stamina)
    if breakable then
        asset.solidity = "Thin"
        asset.breakStamina = math.max(1, math.floor((stamina or DEFAULT_BREAK_STAMINA) + 0.5))
    else
        asset.solidity = "Unbreakable"
        asset.breakStamina = 0
    end
    asset.rubbleKeyword = ""
    asset.rubbleTerrainId = ""
end

--============================================================================
--Per-map palette storage.
--
--The palette is stored in a map-scoped setting as a ';'-joined token list:
--  "preset:<key>"          preset not yet materialized as a wall asset
--  "preset:<key>:<guid>"   preset materialized as game wall asset <guid>
--  "custom:<guid>"         custom markup wall created from this panel
--  "wall:<guid>"           existing wall asset added from the library
--  "none"                  explicitly empty palette (distinct from default)
--
--Note there is no door token kind: openable-ness is a property of the WALL
--ASSET (WallAsset.openable), so door types are ordinary custom/wall chips.
--
--Note there is no solid-vs-thin distinction here: solidity is a DRAW MODE
--(the Thin/Solid toggle by the tool strip), not a property of a wall type -
--every palette entry can be drawn either way.
--============================================================================

local DEFAULT_PALETTE = "preset:stone;preset:window;preset:fence;preset:lowwall;preset:curtain;preset:barrier"

local g_paletteSetting = setting{
    id = "markup:wallpalette",
    description = "Map Markup Wall Palette",
    storage = "map",
    default = DEFAULT_PALETTE,
}

local function ParsePalette()
    local result = {}
    local str = g_paletteSetting:Get()
    if type(str) ~= "string" or str == "" or str == "none" then
        return result
    end

    for _,token in ipairs(string.split(str, ";")) do
        local parts = string.split(token, ":")
        if parts[1] == "preset" and parts[2] ~= nil then
            result[#result+1] = {
                kind = "preset",
                key = parts[2],
                guid = parts[3],
            }
        elseif (parts[1] == "wall" or parts[1] == "custom") and parts[2] ~= nil then
            result[#result+1] = {
                kind = parts[1],
                guid = parts[2],
            }
        end
    end

    return result
end

local function SerializePalette(entries)
    local tokens = {}
    for _,entry in ipairs(entries) do
        if entry.kind == "preset" then
            if entry.guid ~= nil then
                tokens[#tokens+1] = string.format("preset:%s:%s", entry.key, entry.guid)
            else
                tokens[#tokens+1] = string.format("preset:%s", entry.key)
            end
        elseif entry.guid ~= nil then
            tokens[#tokens+1] = string.format("%s:%s", entry.kind, entry.guid)
        end
    end

    if #tokens == 0 then
        return "none"
    end
    return table.concat(tokens, ";")
end

local function SavePalette(entries)
    g_paletteSetting:Set(SerializePalette(entries))
end

--============================================================================
--Popup survival across list rebuilds.
--
--Every list in this panel rebuilds its children wholesale from a monitor, and
--a monitor fires on the round trip of OUR OWN write just as readily as on
--another DM's edit. Destroying a panel destroys any popup it owns, so a
--refresh landing while the user has a color popout or a context menu open
--yanks it out from under the cursor: the popup appears to open and instantly
--close again. Rebuilds stand down while a popup is open and replay once it
--is gone - gui.RebuildDeferringPopups / gui.ThinkDeferredRebuild in Gui.lua.
--The list on screen is momentarily stale, but it matches the popup the user
--is interacting with, which is the more important consistency.
--============================================================================

--============================================================================
--Palette entry helpers.
--============================================================================

local function EntryWallAsset(entry)
    if entry == nil or entry.guid == nil then
        return nil
    end
    return assets.walls[entry.guid]
end

--============================================================================
--Map-private wall types.
--
--Every wall asset the panel creates (materialized presets, Custom, Door) is
--stamped with the current map's id (WallAsset.markupMapId, engine build
--required) and hidden from other maps' pickers until promoted via Edit
--Wall's "Make Available to All Maps" - the same lifecycle map-scoped zone
--types get from EnvironmentalKeyword.mapid. Removing an unused, map-private
--type from the palette deletes its asset outright: nothing can reference it
--at that point. On engine builds without the field everything degrades to
--the old behavior (game-wide walls, no deletion).
--
--One table rather than several locals: this file-level chunk is AT Lua's
--200-local cap (the openable probe's cache lives here as a field for the
--same reason). The keyword-side helpers are added as extra fields further
--down, below the GetKeyword/FindKeywordIdByName locals they need.
--============================================================================
local m_mapScope
m_mapScope = {
    openableSupport = nil,

    --Engine gate, same probe recipe as OpenableWallsSupported: the accessor
    --reads "" (never nil) when unset precisely so this probe works.
    wallSupportCache = nil,
    WallSupported = function()
        if m_mapScope.wallSupportCache ~= nil then
            return m_mapScope.wallSupportCache
        end
        local probe = assets.walls[BASE_INVISIBLE_WALL_ID]
        if probe == nil then
            for _,wall in pairs(assets.walls) do
                probe = wall
                break
            end
        end
        if probe == nil then
            --no wall assets at all; leave undecided so we re-probe later.
            return false
        end
        local value = nil
        pcall(function()
            value = probe.markupMapId
        end)
        m_mapScope.wallSupportCache = (value ~= nil)
        return m_mapScope.wallSupportCache
    end,

    --the map id a wall type is private to, or nil for game-wide/legacy walls
    --and pre-scoping engine builds.
    WallMapId = function(asset)
        if asset == nil then
            return nil
        end
        local result = nil
        pcall(function()
            local id = asset.markupMapId
            if type(id) == "string" and id ~= "" then
                result = id
            end
        end)
        return result
    end,

    --Whether a wall asset is usable on the current map: game-wide walls
    --always are; map-private ones only on the map they were created on.
    --The wall twin of KeywordAvailableOnThisMap.
    WallAvailableOnThisMap = function(asset)
        local mapid = m_mapScope.WallMapId(asset)
        return mapid == nil or mapid == game.currentMapId
    end,

    --Stamps a freshly created markup wall as private to the current map.
    --Quietly does nothing on engine builds without the field: the wall is
    --then simply game-wide, exactly as before this feature.
    StampWall = function(asset)
        pcall(function()
            asset.markupMapId = game.currentMapId
        end)
    end,

    --Whether any building operation on the current map still draws with this
    --wall type. Engine-gated (map:GetWallOperationCount): unknown = true, so
    --callers keep the asset rather than deleting something possibly in use.
    WallInUseOnMap = function(guid)
        local count = nil
        pcall(function()
            count = game.currentMap:GetWallOperationCount(guid)
        end)
        if count == nil then
            return true
        end
        return count > 0
    end,

    --Deletes a map-private wall type when removing its chip orphans it:
    --private to THIS map (so no other map's palette or geometry can
    --reference it), no walls drawn with it anywhere on the map, and no
    --other chip still pointing at the asset. Game-wide and library walls
    --are shared content and are never deleted here.
    DeleteWallIfOrphaned = function(guid, remainingEntries)
        local asset = assets.walls[guid]
        if asset == nil then
            return
        end
        local mapid = m_mapScope.WallMapId(asset)
        if mapid == nil or mapid ~= game.currentMapId then
            return
        end
        for _,entry in ipairs(remainingEntries or {}) do
            if entry.guid == guid then
                return
            end
        end
        if m_mapScope.WallInUseOnMap(guid) then
            return
        end
        asset:Delete()
    end,
}

--Engine gate: WallAsset.openable (and the door icon/toggle machinery) needs
--an engine build. NOTE: reading an unknown property on engine userdata does
--NOT error - it silently returns nil (verified live 2026-07-27) - so the
--probe must check the VALUE is non-nil, not just that the read succeeded.
--On a supporting build the accessor returns a real boolean. Cached (on
--m_mapScope, sparing a file-level local): chips and dialogs consult this
--repeatedly.
local function OpenableWallsSupported()
    if m_mapScope.openableSupport ~= nil then
        return m_mapScope.openableSupport
    end
    local probe = assets.walls[BASE_INVISIBLE_WALL_ID]
    if probe == nil then
        for _,wall in pairs(assets.walls) do
            probe = wall
            break
        end
    end
    if probe == nil then
        --no wall assets at all; leave undecided so we re-probe later.
        return false
    end
    local ok, value = pcall(function()
        return probe.openable
    end)
    m_mapScope.openableSupport = ok and value ~= nil
    return m_mapScope.openableSupport
end

local function AssetIsOpenable(asset)
    if asset == nil then
        return false
    end
    local ok, openable = pcall(function()
        return asset.openable
    end)
    return ok and openable == true
end

--Openable wall types draw real wall geometry; each stroke is a door the
--engine floats a toggle icon over.
local function EntryIsOpenable(entry)
    return AssetIsOpenable(EntryWallAsset(entry))
end

--Single writer for an asset's openable state. Enabling stamps the Draw
--Steel door sounds if the asset has none, so engine door toggles are
--audible on every client by default.
local function SetAssetOpenable(asset, openable)
    local ok = pcall(function()
        asset.openable = openable == true
        if openable then
            if asset.openSound == nil or asset.openSound == "" then
                asset.openSound = DOOR_OPEN_SOUND_ID
            end
            if asset.closeSound == nil or asset.closeSound == "" then
                asset.closeSound = DOOR_CLOSE_SOUND_ID
            end
        end
    end)
    return ok
end

--The preset table behind a palette entry, or nil for library/custom walls.
local function PresetForEntry(entry)
    if entry == nil or entry.kind ~= "preset" then
        return nil
    end
    return WALL_PRESETS_BY_KEY[entry.key]
end

local function EntryDisplayName(entry)
    local asset = EntryWallAsset(entry)
    if asset ~= nil then
        return asset.description or "Wall"
    end
    local preset = PresetForEntry(entry)
    if preset ~= nil then
        return preset.name
    end
    return "Unknown Wall"
end

local function AssetFields(asset)
    return {
        blocksMovement = asset.blocksMovement,
        blocksForcedMovement = asset.blocksForcedMovement,
        occludesVision = asset.occludesVision,
        occludesLight = asset.occludesLight,
        visionOneWay = asset.visionOneWay,
        movementOneWay = asset.movementOneWay,
        cover = asset.cover,
        soundOcclusion = asset.soundOcclusion,
        climbable = asset.climbable,
    }
end

local function EntryFields(entry)
    local asset = EntryWallAsset(entry)
    if asset ~= nil then
        return AssetFields(asset)
    end
    local preset = PresetForEntry(entry)
    if preset ~= nil then
        return preset.fields
    end
    return nil
end

--Short consequence readout generated from a wall's gameplay flags. Kept to
--two clauses so it fits on one line of a palette tile; presets carry a
--curated summary string instead.
local function SummarizeFields(fields)
    if fields == nil then
        return "Wall asset missing"
    end

    local result
    if fields.blocksMovement and fields.occludesVision then
        result = "Blocks all"
    elseif fields.blocksMovement then
        result = "Blocks movement"
    elseif fields.occludesVision then
        result = "Blocks sight"
    else
        result = "Passable"
    end

    local coverNames = {
        Half = "half cover",
        ThreeQuarters = "3/4 cover",
        Full = "full cover",
    }
    local coverName = coverNames[fields.cover or "None"]
    if coverName ~= nil then
        result = result .. " - " .. coverName
    end

    return result
end

local function SummarizeEntry(entry)
    if EntryIsOpenable(entry) then
        return "Openable - click icon to open/close"
    end
    local preset = PresetForEntry(entry)
    if preset ~= nil and preset.summary ~= nil then
        return preset.summary
    end
    return SummarizeFields(EntryFields(entry))
end

--A miniature of the skeleton centerline the engine draws for this wall in
--the building tools: solid = occludes light/vision, dashed = blocks movement
--only, dotted = blocks forced movement only, ">" = one-way. Mirrors the
--classification in WallMesh.BuildSkeleton. color is the wall type's markup
--color ("#rrggbb" or nil): when set, the engine draws this type's skeleton
--in it, so the preview line tints to match. narrow trims the dash/dot
--counts to fit the palette chips' 70px preview column (the color swatches
--sit beside it); the library modal keeps the full-width pattern.
local function CreateWallLinePreview(fields, color, narrow)
    local segments = {}

    local dashed = false
    local dotted = false
    if fields ~= nil and (not fields.occludesLight) and (not fields.occludesVision) then
        if fields.blocksMovement then
            dashed = true
        elseif fields.blocksForcedMovement then
            dotted = true
        end
    end

    --Segment sizing keeps the widest pattern under the preview column width
    --(100px, or 70px narrow), so a dash never runs under the name.
    if dashed then
        for _ = 1,cond(narrow, 5, 7) do
            segments[#segments+1] = gui.Panel{
                classes = {"markupWallLine"},
                bgimage = true,
                bgcolor = color,
                width = 9,
                height = 3,
                hmargin = 2,
                valign = "center",
            }
        end
    elseif dotted then
        for _ = 1,cond(narrow, 9, 12) do
            segments[#segments+1] = gui.Panel{
                classes = {"markupWallLine"},
                bgimage = true,
                bgcolor = color,
                width = 3,
                height = 3,
                hmargin = 2,
                valign = "center",
            }
        end
    else
        segments[#segments+1] = gui.Panel{
            classes = {"markupWallLine"},
            bgimage = true,
            bgcolor = color,
            width = "100%",
            height = 3,
            valign = "center",
        }
    end

    if fields ~= nil and (fields.visionOneWay or fields.movementOneWay) then
        segments[#segments+1] = gui.Label{
            classes = {"bold"},
            floating = true,
            halign = "center",
            valign = "center",
            text = ">",
            width = "auto",
            height = "auto",
        }
    end

    return gui.Panel{
        width = "100%",
        height = 8,
        flow = "horizontal",
        halign = "center",
        children = segments,
    }
end

--Door chips mirror what the map draws over an openable segment: the wall
--line thickening into a thin filled rectangle - the door leaf - with the
--door glyph the engine floats on top of it. "This type is the clickable
--door." The leaf is drawn filled because that is a CLOSED door, the state a
--freshly drawn door starts in; open doors draw the same rectangle hollow,
--which a static chip has no way to show. color tints the wall line + leaf
--like CreateWallLinePreview's, matching the type's markup color on the map.
local function CreateDoorLinePreview(color)
    return gui.Panel{
        width = "100%",
        height = 14,
        halign = "center",

        gui.Panel{
            width = "100%",
            height = "100%",
            flow = "horizontal",
            halign = "center",
            valign = "center",

            gui.Panel{
                classes = {"markupWallLine"},
                bgimage = true,
                bgcolor = color,
                width = "22%",
                height = 3,
                valign = "center",
            },
            gui.Panel{
                classes = {"markupWallLine"},
                bgimage = true,
                bgcolor = color,
                width = "46%",
                height = 9,
                valign = "center",
            },
            gui.Panel{
                classes = {"markupWallLine"},
                bgimage = true,
                bgcolor = color,
                width = "22%",
                height = 3,
                valign = "center",
            },
        },

        --floating so the glyph can overhang the 9px leaf the way it overhangs
        --the leaf rectangle on the map.
        gui.Panel{
            floating = true,
            width = 14,
            height = 14,
            halign = "center",
            valign = "center",
            bgimage = "game-icons/exit-door.png",
            bgcolor = "@fgColor",
        },
    }
end

--Solid chips render a filled-region preview - a bordered box of diagonal
--stripes, echoing how the tile height overlay draws solid blocks on the map -
--instead of the thin chips' line preview. This is the "fills area" marker.
--Spans the chip's full width like the thin chip's line, so the two draw-mode
--previews read as equals. The stripe count deliberately OVERFILLS the box
--and clip trims the excess at the border, so the pattern reaches the right
--edge exactly at any chip width instead of stopping wherever a fixed count
--happens to end.
local function CreateSolidBlockPreview()
    local stripes = {}
    for _ = 1,24 do
        stripes[#stripes+1] = gui.Panel{
            classes = {"markupWallLine"},
            bgimage = true,
            width = 3,
            height = 12,
            hmargin = 3,
            valign = "center",
            rotate = 45,
        }
    end

    --Border on the outer panel, stripes clipped in an inner layer: clip uses
    --the panel's own bgimage as the mask (Unity Mask semantics) and clipHidden
    --keeps that mask image from drawing - the islandLayer recipe from
    --MarkdownDocument.lua. Clipping the border's panel itself would eat the
    --border pixels at the mask edge.
    return gui.Panel{
        width = "100%",
        height = 12,
        halign = "center",
        bgimage = true,
        bgcolor = "clear",
        borderWidth = 1,
        borderColor = "@fgMuted",

        gui.Panel{
            width = "100%-2",
            height = "100%-2",
            halign = "center",
            valign = "center",
            flow = "horizontal",
            bgimage = "panels/square.png",
            bgcolor = "clear",
            clip = true,
            clipHidden = true,
            children = stripes,
        },
    }
end

local function ApplyFieldsToWall(wall, fields)
    wall.invisible = true
    wall.blocksMovement = fields.blocksMovement == true
    wall.blocksForcedMovement = fields.blocksForcedMovement == true
    wall.occludesVision = fields.occludesVision == true
    wall.occludesLight = fields.occludesLight == true
    wall.cover = fields.cover or "None"
    wall.soundOcclusion = fields.soundOcclusion or 0
    wall.climbable = fields.climbable or "NotClimbable"
    --The base asset we duplicate from is the Core "One-Direction See-Thru"
    --wall, so both one-way flags must be reset explicitly or every markup
    --wall inherits one-way vision (and the one-way skeleton triangles).
    wall.visionOneWay = fields.visionOneWay == true
    wall.movementOneWay = false

    --Breakability is opt-in per wall type (Edit Wall -> Breakable). Set it
    --explicitly rather than letting it inherit: the Core base asset simply
    --omits solidity/breakStamina, so today it lands on the engine's
    --Unbreakable default by luck, and would change silently if that asset did.
    local stamina = fields.breakStamina or 0
    SetAssetBreakable(wall, stamina > 0, stamina)

    --Openable (door) types: engine-build gated, so this quietly does nothing
    --on a stale engine and the type behaves as a plain wall.
    SetAssetOpenable(wall, fields.openable == true)
end

--Creates a game wall asset by duplicating the invisible base and applying
--the given name + gameplay fields. Returns the new guid, or nil on failure.
local function CreateMarkupWallAsset(name, fields)
    if assets.walls[BASE_INVISIBLE_WALL_ID] == nil then
        dmhub.Debug("MARKUP:: base invisible wall asset is not available in this game")
        return nil
    end

    local guid = assets:DuplicateWall(BASE_INVISIBLE_WALL_ID)
    if guid == nil then
        return nil
    end

    local wall = assets.walls[guid]
    wall.description = name
    ApplyFieldsToWall(wall, fields)
    --new markup walls are private to the map they were created on until
    --promoted from Edit Wall's "Make Available to All Maps".
    m_mapScope.StampWall(wall)
    wall:Upload()
    return guid
end

--============================================================================
--Wall height helpers. The markup height stepper drives the same settings the
--Building editor uses, which dmhub.GetWallHeight (Terrain.lua) already reads,
--so per-placement heights stamp onto operations with no extra plumbing.
--============================================================================

local function GetWallHeightSetting()
    if dmhub.GetSettingValue("building:specifywallheight") then
        return dmhub.GetSettingValue("building:wallheightvalue")
    end
    return nil
end

local function SetWallHeightSetting(height)
    if height == nil then
        dmhub.SetSettingValue("building:specifywallheight", false)
    else
        dmhub.SetSettingValue("building:specifywallheight", true)
        dmhub.SetSettingValue("building:wallheightvalue", height)
    end
end

--============================================================================
--Zones: named tile regions carrying an Environmental Keyword, applied to the
--game through the aura system (design brief section 5, storage model Z1).
--
--Storage: per-floor markup zone records via the engine's
--floor:SetMarkupZone / floor:RemoveMarkupZone / floor.markupZones API
--(undo + multiplayer sync are the engine's ExecuteCommand). Record schema
--(owned here, opaque to the engine):
--  {
--    name = "Lava",                  -- display name (also the overlay label)
--    keyword = "<keyword id>",       -- environmentalKeywords table key
--    locs = { {x=0,y=0}, ... },      -- tiles, plain x/y pairs (floor implied)
--    altitude = 0,                   -- base altitude of the vertical range
--    height = 2,                     -- affects up to this many tiles above
--                                    -- altitude; ABSENT = unlimited height
--    playerVisible = true,           -- players see the overlay stripes
--                                    -- (new zones default to true; the Edit
--                                    -- Zone dialog turns it off per zone)
--    pattern = { color = "#rrggbb", angle = <radians> },
--    ord = 1,                        -- creation order (stable list sorting)
--  }
--
--The same store also holds the Footsteps mode's surface records, marked by
--category (records without a category are zone records). One record per
--surface family per floor, id "surface-<id>" - surfaces are exclusive per
--tile, so there is no naming/splitting machinery like zones have:
--  {
--    category = "surface",
--    surface = 6,                    -- AudioSurfaceTypes.surfaces index
--    surfaceName = "Stone",          -- informational (debugging/healing)
--    locs = { {x=0,y=0}, ... },
--  }
--
--Runtime: ZoneManager (below) builds one AuraInstance per zone from the
--records and hands them to the engine via dmhub.GetMapAuras (re-polled on
--every aura rebuild). The keyword's difficultTerrain/water/concealment/
--climbable flags ride the aura into tile rules, its CharacterModifiers reach
--creatures via
--the normal FillModifiersFromAuras path, and the height field drives the
--engine's vertical-overlap test (a height-2 Lava zone burns a ground token
--and ignores a flyer at altitude 3).
--
--Rendering: dmhub.GetMarkupZones feeds the tile height overlay, which draws
--each zone as diagonal stripes + a name label. DM-only unless the zone is
--marked playerVisible - which new zones are, so a painted hazard reads to the
--table without the DM remembering to publish each one. A zone the DM wants
--kept secret is turned off individually in the Edit Zone dialog.
--
--This file loads before EnvironmentalKeyword.lua (main.lua order), so every
--reference to the EnvironmentalKeyword global is runtime + rawget-guarded.
--============================================================================

--Built-in zone types (design: built-ins ARE Environmental Keywords - ship as
--presets that lazily materialize into the environmentalKeywords table on
--first use, exactly like wall presets materialize wall assets). Colors match
--the tile height overlay's built-in stripe colors so the readout stays
--consistent with un-zoned tiles that carry the same rules.
local ZONE_PRESETS = {
    {
        key = "difficult",
        name = "Difficult Terrain",
        summary = "Costs double to move through",
        color = "#8c5926",
        description = "This area is difficult terrain.",
        fields = { difficultTerrain = true },
    },
    {
        key = "water",
        name = "Water",
        summary = "Water - swim or wade",
        color = "#3373d9",
        description = "This area is water.",
        fields = { water = true },
    },
    {
        key = "concealing",
        name = "Concealing",
        summary = "Grants concealment",
        color = "#4d594d",
        description = "Creatures in this area have concealment.",
        fields = { concealment = true },
    },
}

local ZONE_PRESETS_BY_KEY = {}
for _,preset in ipairs(ZONE_PRESETS) do
    ZONE_PRESETS_BY_KEY[preset.key] = preset
end

--Fallback chip/stripe colors for keywords whose icon color is white/unset.
local ZONE_FALLBACK_COLORS = {
    "#d94a3d", "#7a3dd9", "#3dd9c8", "#d9b83d", "#d93d9e", "#4ad93d",
}

local ZONE_ANGLE_A = math.pi * 0.25
local ZONE_ANGLE_B = math.pi * 0.75

--Zone stripes, shared by the map overlay and the panel's little zone swatches.
--Kept in one table rather than as several file-level locals: this chunk is
--close to Lua's 200-locals cap (same reason as m_dispelState below).
--
--  .HashAngle(id)        angle from the keyword id alone
--  .AngleForKeyword(id)  the angle actually used - the map-wide assignment when
--                        there is one, else the hash
--  .Assign(zoneCache)    recomputes that assignment (defined below KeywordColor,
--                        which it needs; see the note there)
--  .Swatch(color, angle) the panel's little striped zone chip
--
--`assignment` starts empty, so everything falls back to the hash until the zone
--cache has been built at least once for the current map.
local m_zoneStripes = { gradients = {}, assignment = {}, swatchPeriod = 0.28 }

--Two angles only. Which one a keyword gets is decided in .Assign below; this is
--the starting point and the tiebreak - a stable function of the keyword id, so
--a keyword with nothing to clash with stripes the same way on every map.
function m_zoneStripes.HashAngle(keywordid)
    if type(keywordid) ~= "string" or keywordid == "" then
        return ZONE_ANGLE_A
    end

    local hash = 0
    for i = 1,string.len(keywordid) do
        hash = (hash * 31 + string.byte(keywordid, i)) % 65536
    end

    --a middle bit rather than the low one: with an odd multiplier the low bit
    --is just the parity of the byte sum, which clumps for similar ids.
    if math.floor(hash / 128) % 2 == 1 then
        return ZONE_ANGLE_B
    end

    return ZONE_ANGLE_A
end

--The stripe angle for a keyword. This is a property of the KEYWORD, not of
--paint order: every Darkness zone on a map stripes one way and every Sunlight
--zone the other, so same-keyword regions read as one thing at a glance. (It
--used to alternate with the number of zones already on the floor, which gave
--two zones of the same keyword different angles.)
function m_zoneStripes.AngleForKeyword(keywordid)
    if type(keywordid) ~= "string" or keywordid == "" then
        return ZONE_ANGLE_A
    end

    return m_zoneStripes.assignment[keywordid] or m_zoneStripes.HashAngle(keywordid)
end

--============================================================================
--Per-zone-type fade: the opacity slider on each group in the Zones list.
--
--Purely a local viewing aid, in the same spirit as Fade Map above: it dims
--one zone TYPE on the map so the others (or the map art under them) read
--clearly. Session-only - nothing is written to a setting, a preference or the
--map record - so it starts at 100% on every load, and it is applied only
--while the Map Markup panel is open, so a slider left at 20% cannot follow
--the Director back to the table or reach a player.
--
--It is applied to the COLOUR the overlay feed hands the engine, not to any
--stored data, which is why it costs an overlay re-mesh (the colours are baked
--into the mesh) and nothing else. Zone labels take the same colour
--(TileHeightOverlay.EmitMarkupZones sets textColor = zone.color), so a faded
--type's labels fade with its stripes.
--
--  .opacity[key]    0..1 per group key; ABSENT means full strength
--  .opacitySeq      bumped on every real change - the feed's re-mesh signal
--  .opacityFeedSeq  the seq the feed last published (see dmhub.GetMarkupZones)
--
--(Fields on m_zoneStripes rather than file-level locals: this chunk is at
--Lua's 200-locals cap, same reason the rest of this table exists.)
--============================================================================
m_zoneStripes.opacity = {}
m_zoneStripes.opacitySeq = 0
m_zoneStripes.opacityFeedSeq = 0

--Zones group by keyword - one group, one slider, per zone type. A record
--whose keyword id could not be resolved (dead id from the table-creation
--race; see MaterializeZonePreset) falls back to its stored keyword NAME, so
--it still groups with its siblings instead of splitting off on its own.
function m_zoneStripes.GroupKey(entry)
    if type(entry.keywordid) == "string" and entry.keywordid ~= "" then
        return entry.keywordid
    end
    return "name:" .. tostring(entry.keywordName or "Zone")
end

function m_zoneStripes.Opacity(key)
    if type(key) ~= "string" or key == "" then
        return 1
    end
    return m_zoneStripes.opacity[key] or 1
end

function m_zoneStripes.SetOpacity(key, value)
    if type(key) ~= "string" or key == "" then
        return
    end

    local v = tonumber(value) or 1
    if v < 0 then
        v = 0
    elseif v > 1 then
        v = 1
    end
    --quantized to the slider's own 1% display resolution: a drag fires an
    --event per frame and every distinct value costs an overlay re-mesh, so
    --sub-percent jitter is not worth re-meshing for.
    v = math.floor(v * 100 + 0.5) / 100

    --full strength is stored as absent, so AnyFade below is a plain emptiness
    --test and the feed can skip the whole pass in the common case.
    local stored = nil
    if v < 1 then
        stored = v
    end

    if m_zoneStripes.opacity[key] == stored then
        return
    end

    m_zoneStripes.opacity[key] = stored
    m_zoneStripes.opacitySeq = m_zoneStripes.opacitySeq + 1
end

function m_zoneStripes.AnyFade()
    for _,_ in pairs(m_zoneStripes.opacity) do
        return true
    end
    return false
end

--The stripe colour scaled by a fade factor. Only the "#rrggbb"/"#rrggbbaa"
--forms can be scaled; anything else (a named colour) passes through, matching
--ZoneOverlayColor's own rule.
function m_zoneStripes.FadeColor(color, opacity)
    if opacity >= 1 or type(color) ~= "string" or string.sub(color, 1, 1) ~= "#" then
        return color
    end

    local len = string.len(color)
    local alpha = 255
    if len == 9 then
        alpha = tonumber(string.sub(color, 8, 9), 16) or 255
    elseif len ~= 7 then
        return color
    end

    alpha = math.floor(alpha * opacity + 0.5)
    if alpha < 0 then
        alpha = 0
    elseif alpha > 255 then
        alpha = 255
    end

    return string.format("%s%02x", string.sub(color, 1, 7), alpha)
end

--Muted, compact styling for the group opacity sliders, matching the per-floor
--sliders in the Floors panel. Passed at the PercentSlider call site: the
--control attaches its OWN styles list, which outranks the panel's cascade
--rules, so muting it from the cascade is a no-op. Resolved via MergeTokens at
--build time (the list rebuilds on every refresh, so a live theme switch is
--picked up on the next refresh).
function m_zoneStripes.OpacitySliderStyles()
    return ThemeEngine.MergeTokens{
        {
            selectors = {"percentSlider"},
            borderWidth = 1,
            borderColor = "@border",
            cornerRadius = 2,
            bgimage = "panels/square.png",
            bgcolor = "@bg",
            height = 12,
            flow = "none",
        },
        {
            selectors = {"percentSliderLabel"},
            color = "@fg",
            fontSize = 10,
            bold = true,
            halign = "left",
            valign = "center",
            width = 40,
            textAlignment = "center",
            height = "auto",
        },
        --the clipped duplicate that shows over the filled portion needs the
        --inverse treatment to stay legible against the fill.
        {
            selectors = {"percentSliderLabel", "fill"},
            color = "@bg",
        },
        {
            selectors = {"percentFill"},
            bgcolor = "@fgMuted",
            height = "100%",
            width = "0%",
            halign = "left",
            cornerRadius = 2,
        },
    }
end

--{h, s, v} in 0..1 for a "#rrggbb" / "#rrggbbaa" colour; nil for anything else
--(named colours, which the panel's colours never are in practice).
function m_zoneStripes.HSV(color)
    if type(color) ~= "string" or string.sub(color, 1, 1) ~= "#" then
        return nil
    end

    local len = string.len(color)
    if len ~= 7 and len ~= 9 then
        return nil
    end

    local r = tonumber(string.sub(color, 2, 3), 16)
    local g = tonumber(string.sub(color, 4, 5), 16)
    local b = tonumber(string.sub(color, 6, 7), 16)
    if r == nil or g == nil or b == nil then
        return nil
    end

    r = r / 255
    g = g / 255
    b = b / 255

    local maxc = math.max(r, g, b)
    local minc = math.min(r, g, b)
    local delta = maxc - minc

    local h = 0
    if delta > 0 then
        if maxc == r then
            --Lua's % is floored, so the negative case wraps to 0..6 correctly.
            h = ((g - b) / delta) % 6
        elseif maxc == g then
            h = (b - r) / delta + 2
        else
            h = (r - g) / delta + 4
        end
        h = h / 6
    end

    local s = 0
    if maxc > 0 then
        s = delta / maxc
    end

    return { h = h, s = s, v = maxc }
end

--"How hard would these two be to tell apart as stripe washes over map art."
--Not a real perceptual metric - hue carries most of it, because the stripes are
--translucent and lose a lot of their value/saturation to whatever is under
--them. Greys have no meaningful hue, so hue only counts as far as the LESS
--saturated of the two is actually coloured. 0 = identical; .similarThreshold is
--about where two colours stop reading as the same wash.
m_zoneStripes.similarThreshold = 0.25

function m_zoneStripes.ColorDistance(a, b)
    local dh = math.abs(a.h - b.h)
    if dh > 0.5 then
        dh = 1 - dh
    end

    return dh * 2 * math.min(a.s, b.s)
        + math.abs(a.v - b.v) * 0.6
        + math.abs(a.s - b.s) * 0.3
end

--Diagonal stripes as a gradient: a linear gradient along (cos angle, sin
--angle) - the same direction vector the overlay shader uses, so the panel
--stripes run the same way the map ones do - that flips hard between the colour
--and its transparent form. The a->b vector is one stripe period long and the
--gradient wraps ('repeat'), so period is a fraction of the swatch, not of the
--gradient. Returns nil for colours we can't build a transparent twin of (named
--colours), in which case callers fall back to a flat chip.
function m_zoneStripes.Gradient(color, angle)
    if type(color) ~= "string" or string.sub(color, 1, 1) ~= "#" then
        return nil
    end

    local len = string.len(color)
    if len ~= 7 and len ~= 9 then
        return nil
    end

    angle = angle or ZONE_ANGLE_A

    local rgb = string.sub(color, 1, 7)
    local key = rgb .. "/" .. tostring(angle)
    if m_zoneStripes.gradients[key] ~= nil then
        return m_zoneStripes.gradients[key]
    end

    --the transparent stop keeps the same RGB so the (narrow) blend band
    --between stripe and gap doesn't darken towards black.
    local result = gui.Gradient{
        type = "linear",
        point_a = {x = 0.5, y = 0.5},
        point_b = {
            x = 0.5 + math.cos(angle) * m_zoneStripes.swatchPeriod,
            y = 0.5 + math.sin(angle) * m_zoneStripes.swatchPeriod,
        },
        ["repeat"] = true,
        stops = {
            {position = 0.00, color = rgb .. "ff"},
            {position = 0.48, color = rgb .. "ff"},
            {position = 0.52, color = rgb .. "00"},
            {position = 1.00, color = rgb .. "00"},
        },
    }

    m_zoneStripes.gradients[key] = result
    return result
end

--The little 14x14 zone swatch used by the palette chips and the zone list.
function m_zoneStripes.Swatch(color, angle)
    local gradient = m_zoneStripes.Gradient(color, angle)

    --the gradient MULTIPLIES the panel's own colour, so with a gradient the
    --colour lives in the stops and the panel itself must be white.
    local bgcolor = color
    if gradient ~= nil then
        bgcolor = "white"
    end

    return gui.Panel{
        width = 14,
        height = 14,
        valign = "center",
        bgimage = true,
        bgcolor = bgcolor,
        gradient = gradient,
        borderWidth = 1,
        borderColor = "@border",
    }
end

--Per-map zone palette, exactly like the wall palette: ';'-joined tokens.
--  "preset:<key>"            built-in not yet materialized as a keyword
--  "preset:<key>:<id>"       built-in materialized as keyword <id>
--  "keyword:<id>"            keyword added from the library / created new
--  "none"                    explicitly empty
local DEFAULT_ZONE_PALETTE = "preset:difficult;preset:water;preset:concealing"

local g_zonePaletteSetting = setting{
    id = "markup:zonepalette",
    description = "Map Markup Zone Palette",
    storage = "map",
    default = DEFAULT_ZONE_PALETTE,
}

local function ParseZonePalette()
    local result = {}
    local str = g_zonePaletteSetting:Get()
    if type(str) ~= "string" or str == "" or str == "none" then
        return result
    end

    for _,token in ipairs(string.split(str, ";")) do
        local parts = string.split(token, ":")
        if parts[1] == "preset" and parts[2] ~= nil then
            result[#result+1] = {
                kind = "preset",
                key = parts[2],
                keywordid = parts[3],
            }
        elseif parts[1] == "keyword" and parts[2] ~= nil then
            result[#result+1] = {
                kind = "keyword",
                keywordid = parts[2],
            }
        end
    end

    return result
end

local function SerializeZonePalette(entries)
    local tokens = {}
    for _,entry in ipairs(entries) do
        if entry.kind == "preset" then
            if entry.keywordid ~= nil then
                tokens[#tokens+1] = string.format("preset:%s:%s", entry.key, entry.keywordid)
            else
                tokens[#tokens+1] = string.format("preset:%s", entry.key)
            end
        elseif entry.keywordid ~= nil then
            tokens[#tokens+1] = string.format("keyword:%s", entry.keywordid)
        end
    end

    if #tokens == 0 then
        return "none"
    end
    return table.concat(tokens, ";")
end

local function SaveZonePalette(entries)
    g_zonePaletteSetting:Set(SerializeZonePalette(entries))
end

--============================================================================
--"Entire Map" zone types: a type the whole map carries by default, with no
--painted region. Stored per map as a ';'-joined list of keyword ids, exactly
--like the palette above; the palette chip's "Entire Map" button toggles it.
--
--A blanket type registers one aura per floor covering every tile of the map's
--extent EXCEPT the tiles of painted zones that interact with it: zones of the
--same keyword (which would otherwise double up on those tiles), zones whose
--keyword dispels it, and zones of keywords it dispels. Explicit painting
--always wins over the blanket -- which is also what keeps a blanketed map
--paintable, since the paint-time dispel rules only ever consult painted
--records (ZonesOnFloor), never these entries.
--
--Blankets deliberately do NOT feed the overlay: striping every tile of the
--map would bury the painted zones the DM is actually working with. The lit
--button on the palette chip is the indicator.
--
--One table rather than a handful of file-level locals: this chunk is a few
--locals short of Lua's 200-locals cap (same reason as m_zoneStripes and
--m_dispelState). Rebuild is assigned much further down, where the keyword
--helpers and the zone cache it reads are already in scope.
--============================================================================
local m_entireMap = {
    --resolved blanket entries (same shape as m_zoneCache entries, plus
    --entireMap = true); rebuilt with the zone cache.
    entries = {},

    --the CacheKey value the entries were built from; see EnsureZoneCache.
    cacheKey = false,

    setting = setting{
        id = "markup:zoneentiremap",
        description = "Map Markup Entire-Map Zone Types",
        storage = "map",
        default = "",
    },
}

--pcall-guarded: this is read from EnsureZoneCache, which runs on every aura
--poll -- including polls that land before there is a map to scope a
--map-storage setting to (boot, map switches).
function m_entireMap.Serialized()
    local str = nil
    pcall(function()
        str = m_entireMap.setting:Get()
    end)
    if type(str) ~= "string" then
        return ""
    end
    return str
end

--Set of keyword ids this map blankets.
function m_entireMap.Keywords()
    local result = {}
    for _,id in ipairs(string.split(m_entireMap.Serialized(), ";")) do
        if id ~= "" then
            result[id] = true
        end
    end
    return result
end

function m_entireMap.IsSet(keywordid)
    if keywordid == nil then
        return false
    end
    return m_entireMap.Keywords()[keywordid] == true
end

--Turns the blanket on or off for a keyword. Ids are stored sorted so the
--serialized value is stable: it doubles as part of the zone cache's validity
--key, and a reordering would rebuild the cache for nothing.
function m_entireMap.Set(keywordid, value)
    if keywordid == nil then
        return
    end

    local ids = m_entireMap.Keywords()
    if (ids[keywordid] == true) == (value == true) then
        return
    end

    if value == true then
        ids[keywordid] = true
    else
        ids[keywordid] = nil
    end

    local sorted = {}
    for id,_ in pairs(ids) do
        sorted[#sorted+1] = id
    end
    table.sort(sorted)
    m_entireMap.setting:Set(table.concat(sorted, ";"))
end

--The zone cache's validity key for blankets. The setting can change without
--any zone record changing (and can change on another client), so the cache
--compares this rather than trusting a callback. The map extent rides along
--because that is exactly what a blanket covers: resizing the map has to
--rebuild it. Empty string when nothing is blanketed -- the common case, and
--the reason the extent is only read when it can matter (this runs on every
--aura poll).
function m_entireMap.CacheKey()
    local str = m_entireMap.Serialized()
    if str == "" then
        return ""
    end

    local dims = nil
    pcall(function()
        local map = game.currentMap
        if map ~= nil then
            dims = map.dimensions
        end
    end)
    if dims == nil then
        return str
    end

    return string.format("%s@%d,%d,%d,%d", str,
        math.floor(dims.x), math.floor(dims.y), math.floor(dims.z), math.floor(dims.w))
end

local ENVIRONMENTAL_KEYWORDS_TABLE = "environmentalKeywords"

local function GetKeywordTable()
    DMHubMapMarkupD20.EnsureEnvironmentalKeyword()
    return dmhub.GetTable(ENVIRONMENTAL_KEYWORDS_TABLE) or {}
end

local function GetKeyword(keywordid)
    if keywordid == nil then
        return nil
    end
    return GetKeywordTable()[keywordid]
end

--"x,y" key for a tile. Defined here (not with the editing operations below)
--because the ZoneManager's dispel machinery keys tiles too.
local function ZoneLocKey(x, y)
    return string.format("%d,%d", x, y)
end

--Dynamic-light zone types: a zone type can be set to only apply where the map's
--light level is below a per-type threshold (the flagship use: Darkness that is
--dynamically calculated from the light on the map). The engine samples light
--deterministically (dmhub.GetDarkTiles: ambient day/night + token/object lights
--with wall shadowing, animation-free), and the sampled dark sets carve the
--type's footprints -- painted zones AND its Entire Map blanket -- exactly like
--the dispel machinery carves them: records are untouched, the auras and overlay
--stripes just skip lit tiles.
--
--Per-map setting "kwid:pct;kwid:pct" (pct = light threshold percent; below it a
--tile counts as dark), sorted for a stable cache key. Sampled state lives here
--too: [floorid.."@"..pct] = {state=<engine hash>, dark={[lockey]=true}}, with
--`serial` bumped on every change so EnsureZoneCache rebuilds. All of it on ONE
--table: this chunk runs close to Lua's 200-locals-per-function cap (see
--m_entireMap).
local m_dynamicLight = {
    setting = setting{
        id = "markup:zonedynamiclight",
        description = "Map Markup Dynamic-Light Zone Types",
        storage = "map",
        default = "",
    },

    --nil = not probed yet; the engine API is new, so the UI hides on old builds.
    supported = nil,

    states = {},
    serial = 0,

    --the CacheKey value the current zone cache was built from (EnsureZoneCache).
    cacheKey = false,
}

function m_dynamicLight.Supported()
    if m_dynamicLight.supported == nil then
        local ok, value = pcall(function()
            return dmhub.supportsDynamicLightZones
        end)
        m_dynamicLight.supported = (ok and value == true)
    end
    return m_dynamicLight.supported
end

--pcall-guarded like m_entireMap.Serialized: read on aura polls that can land
--before there is a map to scope a map-storage setting to.
function m_dynamicLight.Serialized()
    local str = nil
    pcall(function()
        str = m_dynamicLight.setting:Get()
    end)
    if type(str) ~= "string" then
        return ""
    end
    return str
end

--{ keywordid -> threshold percent (integer 1..100) }. Only keywords whose
--compendium entry has "Can Use Dynamic Light" checked count: unchecking the
--flag disables an already-configured threshold everywhere (carve, sampling,
--chip UI) without deleting it -- re-checking restores it. The flag lives on
--the keyword so the palette only offers Dynamic Light where it makes sense
--(Darkness), not on every chip. refreshTables bumps m_zoneTablesGen, which
--is already part of the zone cache key, so a flag flip rebuilds promptly.
function m_dynamicLight.Thresholds()
    local result = {}
    for _,item in ipairs(string.split(m_dynamicLight.Serialized(), ";")) do
        if item ~= "" then
            local kwid, pct = string.match(item, "^(.-):(%d+)$")
            pct = tonumber(pct)
            if kwid ~= nil and kwid ~= "" and pct ~= nil and pct > 0 then
                local allowed = false
                local kw = GetKeyword(kwid)
                if kw ~= nil then
                    --pcall: this file loads before EnvironmentalKeyword, so
                    --keyword instances are only known well-typed at runtime.
                    pcall(function()
                        allowed = kw:try_get("dynamicLight", false) == true
                    end)
                end
                if allowed then
                    result[kwid] = pct
                end
            end
        end
    end
    return result
end

function m_dynamicLight.GetThreshold(keywordid)
    if keywordid == nil then
        return nil
    end
    return m_dynamicLight.Thresholds()[keywordid]
end

--Sets or clears (pct = nil) the threshold for a keyword. Stored sorted so the
--serialized value is stable: it is part of the zone cache's validity key.
function m_dynamicLight.Set(keywordid, pct)
    if keywordid == nil then
        return
    end

    local thresholds = m_dynamicLight.Thresholds()
    if thresholds[keywordid] == pct then
        return
    end
    thresholds[keywordid] = pct

    local sorted = {}
    for id,value in pairs(thresholds) do
        sorted[#sorted+1] = string.format("%s:%d", id, value)
    end
    table.sort(sorted)
    m_dynamicLight.setting:Set(table.concat(sorted, ";"))
end

--The zone cache's validity key for dynamic light: the configuration plus the
--sampling serial (a sample changing what is dark must rebuild the footprints).
--Empty string when the feature is off -- the common case.
function m_dynamicLight.CacheKey()
    local str = m_dynamicLight.Serialized()
    if str == "" then
        return ""
    end
    return string.format("%s#%d", str, m_dynamicLight.serial)
end

function m_dynamicLight.StateKey(floorid, pct)
    return string.format("%s@%d", floorid, pct)
end

--entry.locs filtered to the currently-dark tiles when the entry's keyword is
--light-gated; entry.locs itself otherwise. NEVER mutates entry.locs -- the
--record locs also drive painting/splitting, and a filtered list written back
--would drop lit tiles from the record on its next write. An unsampled
--(floor, threshold) applies the zone unfiltered: painted zones stay in force
--until the first sample lands (<1s), rather than flashing off.
function m_dynamicLight.ApplyFilter(thresholds, entry)
    local pct = nil
    if entry.keywordid ~= nil then
        pct = thresholds[entry.keywordid]
    end
    if pct == nil then
        return entry.locs
    end

    local darkState = m_dynamicLight.states[m_dynamicLight.StateKey(entry.floorid, pct)]
    if darkState == nil then
        return entry.locs
    end

    local filtered = {}
    for _,l in ipairs(entry.locs) do
        local key = ZoneLocKey(l.x, l.y)
        --a tile the sampler has never seen (just painted; next sample is
        --<1s away) defaults to applying, like an unsampled floor does --
        --absent from `sampled` means unknown, not lit. Rect-mode samples
        --(blankets) have sampled == nil: the rect covers the whole map.
        if darkState.dark[key] ~= nil
            or (darkState.sampled ~= nil and darkState.sampled[key] == nil) then
            filtered[#filtered+1] = l
        end
    end
    return filtered
end

--The keyword's stripe/chip color: its icon background color when it has a
--real one, otherwise a fallback picked stably from the keyword id.
local function KeywordColor(keywordid, kw)
    local color = nil
    if kw ~= nil then
        pcall(function()
            local display = kw:try_get("display")
            if display ~= nil then
                color = display.bgcolor
            end
        end)
    end

    --the compendium color picker persists its value as a Color USERDATA
    --(the standard display.bgcolor idiom across compendium editors); its
    --.tostring PROPERTY is the real "#RRGGBBAA" hex string. Presets and
    --older items store plain strings. Normalize to a string, and trim a
    --fully-opaque alpha suffix so the overlay's standard stripe alpha
    --still applies (ZoneOverlayColor only decorates 7-char "#rrggbb").
    if type(color) == "userdata" then
        local ok, str = pcall(function() return color.tostring end)
        if ok and type(str) == "string" then
            color = str
        else
            color = nil
        end
    end
    if type(color) == "string" and string.len(color) == 9
        and string.lower(string.sub(color, 8, 9)) == "ff" then
        color = string.sub(color, 1, 7)
    end

    if type(color) == "string" and color ~= "" and string.lower(color) ~= "white"
        and string.lower(color) ~= "#ffffff" and string.lower(color) ~= "#ffffffff" then
        return color
    end

    local hash = 0
    for i = 1, #(keywordid or "") do
        hash = (hash * 31 + string.byte(keywordid, i)) % 65536
    end
    return ZONE_FALLBACK_COLORS[(hash % #ZONE_FALLBACK_COLORS) + 1]
end

--Picks a stripe angle for every keyword on the map in ONE pass over the whole
--set, so keywords whose colours are close can be pushed to opposite angles:
--two similar reds side by side then read as two regions instead of one blur.
--(Lives here rather than up with the rest of m_zoneStripes because it needs
--KeywordColor and ParseZonePalette, and a closure written above a file-level
--local can't see it - it would compile to a global read and come back nil.)
--
--The set is the keywords with painted zones plus the ones in the map's palette.
--Live auras are deliberately NOT included: they come and go mid-encounter and
--would restripe the painted map underneath them.
--
--Greedy, in sorted-id order. Each keyword takes whichever angle leaves it the
--most colour distance from what is already on that angle, and keeps its hash
--angle when nothing assigned is close enough to be confusable. With only two
--angles a chain of three or more similar colours cannot be fully separated -
--this keeps the closest pairs apart and accepts the rest. Deterministic given
--the set, so an angle only moves when the map's zone types actually change.
local function AssignZoneStripeAngles(zoneCache)
    local colors = {}
    local ids = {}

    local function Add(keywordid)
        if type(keywordid) ~= "string" or keywordid == "" or colors[keywordid] ~= nil then
            return
        end

        local hsv = m_zoneStripes.HSV(KeywordColor(keywordid, GetKeyword(keywordid)))
        if hsv == nil then
            return
        end

        colors[keywordid] = hsv
        ids[#ids+1] = keywordid
    end

    for _,entry in ipairs(zoneCache or {}) do
        Add(entry.keywordid)
    end
    for _,entry in ipairs(ParseZonePalette()) do
        Add(entry.keywordid)
    end

    table.sort(ids)

    local assignment = {}
    for _,id in ipairs(ids) do
        --closest already-assigned colour on each angle.
        local nearA = nil
        local nearB = nil
        for otherid,otherAngle in pairs(assignment) do
            local d = m_zoneStripes.ColorDistance(colors[id], colors[otherid])
            if otherAngle == ZONE_ANGLE_A then
                if nearA == nil or d < nearA then
                    nearA = d
                end
            else
                if nearB == nil or d < nearB then
                    nearB = d
                end
            end
        end

        local angle = m_zoneStripes.HashAngle(id)
        if (nearA ~= nil and nearA < m_zoneStripes.similarThreshold)
            or (nearB ~= nil and nearB < m_zoneStripes.similarThreshold) then
            local a = nearA or math.huge
            local b = nearB or math.huge
            if a > b then
                angle = ZONE_ANGLE_A
            elseif b > a then
                angle = ZONE_ANGLE_B
            end
        end

        assignment[id] = angle
    end

    m_zoneStripes.assignment = assignment
end

--Effective rule flags a keyword contributes to tiles. try_get throughout:
--older serialized keywords predate some fields, and game-typed instances
--raise on unknown-field reads.
local function KeywordFlags(kw)
    local flags = { difficultTerrain = false, water = false, concealment = false, climbable = false, climbersOnly = false }
    if kw == nil then
        return flags
    end
    pcall(function()
        flags.difficultTerrain = kw:try_get("difficultTerrain", false) == true
        flags.water = kw:try_get("water", false) == true
        flags.concealment = kw:try_get("concealment", false) == true
        flags.climbable = kw:try_get("climbable", false) == true
        flags.climbersOnly = kw:try_get("climbersOnly", false) == true
    end)
    return flags
end

--Set of keyword ids this keyword dispels (EnvironmentalKeyword.dispels), as
--a lookup table. Empty for nil keywords and keywords predating the field.
local function KeywordDispels(kw)
    local result = {}
    if kw == nil then
        return result
    end
    pcall(function()
        for _,id in ipairs(kw:try_get("dispels", {})) do
            result[id] = true
        end
    end)
    return result
end

--============================================================================
--Default zone height, per zone TYPE. The height a zone reaches is a property
--of what the zone is - lava is ground only, a gas cloud is a couple of tiles,
--darkness fills the room - so the default lives on the EnvironmentalKeyword
--(field defaultHeight) rather than on the map or the tool. It is stamped onto
--each zone by CreateZone as it is painted; the zone owns its height from then
--on (Edit Zone dialog), so changing the type later does not disturb zones
--already on a map.
--
--Values: nil = unlimited, 0 = ground only, N = up to N tiles above the ground.
--Bands are GROUND-RELATIVE (BuildZoneAuraInstance sets auraGroundRelative), so
--"ground only" covers a creature standing in the zone whether the zone sits on
--flat ground, in a pit, or on a raised ledge, and excludes anything flying
--over it.
--
--Everything hangs off this ONE table: MapMarkupPanel's main chunk is at Lua's
--200-local ceiling, and this declaration takes the last free slot. Do NOT add
--another file-level local here without first re-probing (append dummy locals
--to a copy and run luac -p until it reports "too many local variables").
local m_zoneHeight = {}

--The type's default height, or nil for unlimited. try_get + pcall: keywords
--serialized before this field exist, and game-typed instances raise on
--unknown-field reads.
function m_zoneHeight.Get(kw)
    if kw == nil then
        return nil
    end
    local result = nil
    pcall(function()
        local value = kw:try_get("defaultHeight")
        if value ~= nil then
            result = math.max(0, math.floor(tonumber(value) or 0))
        end
    end)
    return result
end

--Writes the default onto the keyword. nil clears it back to unlimited (the
--same nil-assign the keyword editor uses to clear mapid).
function m_zoneHeight.Set(keywordid, height)
    local kw = GetKeyword(keywordid)
    if kw == nil then
        return
    end
    if height == nil then
        kw.defaultHeight = nil
    else
        kw.defaultHeight = math.max(0, math.floor(height))
    end
    dmhub.SetAndUploadTableItem(ENVIRONMENTAL_KEYWORDS_TABLE, kw)
end

--Human-readable height for chip summaries, list rows and menus. Unlimited is
--the default and reads as clutter everywhere, so it describes as nil.
function m_zoneHeight.Describe(height)
    if height == nil then
        return nil
    end
    if height <= 0 then
        return "Ground only"
    end
    if height == 1 then
        return "Up to 1 tile high"
    end
    return string.format("Up to %d tiles high", height)
end

local function KeywordModifierCount(kw)
    local count = 0
    if kw == nil then
        return 0
    end
    pcall(function()
        local modifiers = kw:try_get("modifiers")
        if modifiers ~= nil then
            count = #modifiers
        end
    end)
    return count
end

local function KeywordSummary(kw)
    local parts = {}
    local flags = KeywordFlags(kw)
    if flags.difficultTerrain then parts[#parts+1] = "Difficult terrain" end
    if flags.water then parts[#parts+1] = "Water" end
    if flags.concealment then parts[#parts+1] = "Concealment" end
    if flags.climbable then
        if flags.climbersOnly then
            parts[#parts+1] = "Climbable (climbers only)"
        else
            parts[#parts+1] = "Climbable"
        end
    end
    pcall(function()
        local movedamage = kw:try_get("movedamage", "none")
        if movedamage ~= nil and movedamage ~= "none" then
            local amount = math.floor(tonumber(kw:try_get("damage", 0)) or 0)
            parts[#parts+1] = string.format("%d %s on move", amount, movedamage)
        end
    end)
    pcall(function()
        if kw:try_get("powerRollEnabled", false) and kw:try_get("powerRollTiers") ~= nil then
            parts[#parts+1] = "Damaging"
        end
    end)
    pcall(function()
        if kw:try_get("includeAdjacent", false) == true then
            parts[#parts+1] = "Affects adjacent"
        end
    end)
    --a keyword restricted to some creatures reads very differently from one
    --that catches everyone, so the palette says so without quoting the script.
    pcall(function()
        if kw:try_get("creatureFilter", "") ~= "" then
            parts[#parts+1] = "Filtered"
        end
    end)
    --the default height a zone of this type is painted with; unlimited (the
    --default) describes as nil and stays out of the summary.
    local heightText = m_zoneHeight.Describe(m_zoneHeight.Get(kw))
    if heightText ~= nil then
        parts[#parts+1] = heightText
    end
    pcall(function()
        local dispels = kw:try_get("dispels")
        if dispels ~= nil and #dispels > 0 then
            local names = {}
            local dataTable = GetKeywordTable()
            for _,id in ipairs(dispels) do
                local target = dataTable[id]
                if target ~= nil and target.name ~= nil then
                    names[#names+1] = target.name
                end
            end
            if #names > 0 then
                parts[#parts+1] = "Dispels " .. table.concat(names, ", ")
            end
        end
    end)
    pcall(function()
        if kw:try_get("mapid") ~= nil then
            parts[#parts+1] = "This map only"
        end
    end)
    local nmods = KeywordModifierCount(kw)
    if nmods == 1 then
        parts[#parts+1] = "1 modifier"
    elseif nmods > 1 then
        parts[#parts+1] = string.format("%d modifiers", nmods)
    end
    if #parts == 0 then
        return "No effects yet"
    end
    return table.concat(parts, " - ")
end

--Whether a keyword is usable on the current map: full keywords always are;
--map-scoped zone types (mapid set; see EnvironmentalKeyword.mapid) only on
--the map they were created on.
local function KeywordAvailableOnThisMap(kw)
    local mapid = nil
    pcall(function() mapid = kw:try_get("mapid") end)
    return mapid == nil or mapid == game.currentMapId
end

--Finds a keyword id by (case-insensitive) name, or nil. Skips zone types
--scoped to other maps so preset adoption and dead-id healing never cross maps.
local function FindKeywordIdByName(name)
    if name == nil or name == "" then
        return nil
    end
    for k,kw in unhidden_pairs(GetKeywordTable()) do
        if string.lower(kw.name or "") == string.lower(name) and KeywordAvailableOnThisMap(kw) then
            return k
        end
    end
    return nil
end

--Whether any zone record on the current map still uses this keyword. Records
--reference keywords by id but heal dead ids by stored name (see
--RebuildZoneCache), so a record whose id no longer resolves and whose
--keywordName matches counts as using it too. Assigned here rather than in
--the m_mapScope constructor because it needs GetKeyword, which is declared
--below that constructor (a closure written above a file-level local compiles
--to a global read and comes back nil).
m_mapScope.KeywordInUseOnMap = function(keywordid, kw)
    local map = game.currentMap
    if map == nil then
        --can't tell; report in-use so the caller keeps the keyword.
        return true
    end
    local kwName = nil
    pcall(function() kwName = kw.name end)
    for _,floor in ipairs(map.floors or {}) do
        local zones = nil
        pcall(function() zones = floor.markupZones end)
        if zones ~= nil then
            for _,record in pairs(zones) do
                if type(record) == "table" and record.category == nil then
                    if record.keyword == keywordid then
                        return true
                    end
                    if kwName ~= nil and record.keywordName ~= nil
                        and GetKeyword(record.keyword) == nil
                        and string.lower(record.keywordName) == string.lower(kwName) then
                        return true
                    end
                end
            end
        end
    end
    return false
end

--Deletes a map-scoped zone type when removing its chip orphans it: scoped to
--THIS map (mapid set; so no other map's palette, zones, or dropdowns can
--reference it), no zone records still using it, and no other chip pointing
--at it. Promoted and compendium keywords are shared content and are never
--deleted here. The blanket/dynamic-light configs are cleared by the removal
--path before this runs.
m_mapScope.DeleteKeywordIfOrphaned = function(keywordid, remainingEntries)
    local kw = GetKeyword(keywordid)
    if kw == nil then
        return
    end
    local mapid = nil
    pcall(function() mapid = kw:try_get("mapid") end)
    if mapid == nil or mapid ~= game.currentMapId then
        return
    end
    for _,entry in ipairs(remainingEntries or {}) do
        if entry.keywordid == keywordid then
            return
        end
    end
    if m_mapScope.KeywordInUseOnMap(keywordid, kw) then
        return
    end
    kw.hidden = true
    dmhub.SetAndUploadTableItem(ENVIRONMENTAL_KEYWORDS_TABLE, kw)
end

--Materializes a built-in zone preset as a real Environmental Keyword in this
--game's table (or adopts an existing keyword with the same name - e.g. one
--another map's palette already created). Returns the keyword id, or nil when
--the EnvironmentalKeyword type isn't available.
--
--GOTCHA (hit live 2026-07-26): the very first SetAndUploadTableItem into a
--game auto-creates the environmentalKeywords table server-side, and items
--uploaded during that window can be lost when the server's authoritative
--table arrives - leaving palette/zone records pointing at keyword ids that
--no longer exist. That is why zone records also store keywordName and the
--zone cache heals dead ids by name (see RebuildZoneCache).
local function MaterializeZonePreset(preset)
    local keywordType = rawget(_G, "EnvironmentalKeyword")
    if keywordType == nil then
        dmhub.Debug("MARKUP:: EnvironmentalKeyword type not loaded; cannot materialize zone preset")
        return nil
    end

    local existing = FindKeywordIdByName(preset.name)
    if existing ~= nil then
        return existing
    end

    local kw = keywordType.CreateNew()
    kw.name = preset.name
    kw.description = preset.description
    kw.display = {
        bgcolor = preset.color,
        hueshift = 0,
        saturation = 1,
        brightness = 1,
    }
    for field,value in pairs(preset.fields) do
        kw[field] = value
    end

    --NOTE: the item's TABLE ID is assigned by SetAndUploadTableItem and
    --returned (also stamped onto kw.id); it is NOT kw.guid. Referencing
    --kw.guid here left palette entries and zone records stranded on ids
    --that never existed in the table (masked by the heal-by-name path).
    local keywordid = dmhub.SetAndUploadTableItem(ENVIRONMENTAL_KEYWORDS_TABLE, kw)

    if GetKeyword(keywordid) == nil then
        --table-creation race: the item isn't locally visible yet. Zone
        --records created against this id heal by keywordName once the
        --table settles.
        dmhub.Debug("MARKUP:: keyword '" .. preset.name .. "' not yet visible after upload (table creation race); records will heal by name")
    end

    return keywordid
end

--============================================================================
--Footsteps (mode id "surfaces"): painted footstep-SOUND regions. Zone-like
--records (category = "surface", schema above) that feed ONE thing: the
--surfaceType tile rule, which the footstep pipeline reads when a creature
--walks there. Deliberately lower priority than real conditions: the
--playback dispatch (AudioMain.TokenMovingOnPath) checks flying / burrowing
--/ water BEFORE the surface sound, so water always sounds like water and
--flyers never footstep, regardless of what is painted here.
--
--The palette is the fixed AudioSurfaceTypes registry (accessed at runtime:
--it loads from another module), not a per-map palette like walls/zones.
--============================================================================

local function SurfaceRegistry()
    local registry = rawget(_G, "AudioSurfaceTypes")
    if registry ~= nil and registry.surfaces ~= nil then
        return registry.surfaces
    end
    return {}
end

local function SurfaceInfoById(surfaceId)
    for _,info in ipairs(SurfaceRegistry()) do
        if info.id == surfaceId then
            return info
        end
    end
    return nil
end

--Overlay tint per surface family (labels always render too, so color is
--never the sole signifier). Families added to the registry later fall back.
local SURFACE_COLORS = {
    [1] = "#b0a99b", --Generic
    [2] = "#8a5a2e", --Dirt
    [3] = "#4a9e3d", --Grass
    [4] = "#8fa6bf", --Hollow Metal
    [5] = "#52616e", --Solid Metal
    [6] = "#8c8c94", --Stone
    [7] = "#b5813f", --Wood
    [8] = "#3d8fd9", --Puddle
    [9] = "#d9e8f2", --Snow
}
local SURFACE_FALLBACK_COLOR = "#9a9a9a"

local function SurfaceColor(surfaceId)
    return SURFACE_COLORS[surfaceId] or SURFACE_FALLBACK_COLOR
end

--The map's default footstep surface: what unpainted tiles (surfaceType 0)
--sound like. Read at playback time by AudioMain.TokenMovingOnPath and
--creature.PlayLandingFootstep via dmhub.GetSettingValue. Map storage: DM
--writes it, it syncs to every client (players play their own footsteps),
--and it changes with the map. 0 = no default (the engine's Generic).
local g_footstepDefaultSetting = setting{
    id = "markup:footstepdefault",
    description = "Map Default Footsteps",
    storage = "map",
    default = 0,
}

--Fires a one-shot preview of a surface family's footstep sound - the same
--event playback uses, including the puddle splash overlay.
local function PlaySurfaceSample(surfaceInfo)
    local sound = "Foot.Generic_Generic"
    if surfaceInfo ~= nil and surfaceInfo.sound ~= nil then
        sound = surfaceInfo.sound
    end
    audio.FireSoundEvent(sound, { volume = 1 })
    if surfaceInfo ~= nil and surfaceInfo.puddleSound then
        audio.FireSoundEvent("Foot.Swim_Generic", { volume = 0.4 })
    end
end

--============================================================================
--ZoneManager: the cache of zone records resolved against their keywords,
--rebuilt whenever the records (dmhub.markupZonesSeq), the map, or the
--compendium tables change. Feeds both engine hooks.
--============================================================================

--Engine support probe: the zone storage API, the GetMapAuras hook and the
--overlay feed all shipped in the same engine build as dmhub.markupZonesSeq.
local m_zoneEngineSupport = nil
local function ZonesSupported()
    if m_zoneEngineSupport == nil then
        local ok = pcall(function()
            return dmhub.markupZonesSeq
        end)
        m_zoneEngineSupport = ok
    end
    return m_zoneEngineSupport
end

--Forward declarations: assigned in the panel-state section below. Used by the
--overlay feed's panel-open backstop and its mode report.
local m_markupHudRef = function() return nil end
local m_markupModeRef = function() return "walls" end

local m_zoneCache = nil            --list of resolved zone entries, all floors
local m_surfaceCache = nil         --list of resolved footstep-surface entries, all floors
local m_zoneCacheSeq = nil
local m_zoneCacheMapid = nil
local m_zoneCacheTablesGen = nil
local m_zoneTablesGen = 0          --bumped on refreshTables (keyword edits)
local m_zoneRevision = 0           --bumped on every cache rebuild; overlay cache key
local m_zoneAuraInstances = {}     --what dmhub.GetMapAuras returns
local m_zoneOverlayZones = {}      --GetMarkupZones list: the rules zones
local m_surfaceOverlayZones = {}   --footstep-surface region overlay entries
local m_footstepsOverlayZones = {} --GetMarkupZones list in footsteps mode:
                                   --the surface regions + water rules zones
--(The feed's last-reported footstepsMode/panelOpen flags used to be two
--file-level locals here; they now live on m_dispelState as feedFootstepsMode /
--feedPanelOpen -- alongside its feedZoneFilter -- to free local slots under the
--200-locals cap for m_holes below.)

--Dispel suppression state (EnvironmentalKeyword.dispels): live auras whose
--keyword dispels other keywords temporarily carve their tiles out of zones
--of the dispelled keywords -- rules and overlay both -- with the records left
--untouched, so the zones come back when the aura moves on or expires.
--One table rather than several locals plus a function: this chunk is close
--to Lua's 200-locals-per-function cap.
--  signature      what the active footprints looked like when the derived
--                 lists were last built (false = must rebuild)
--  footprints     list of {floorIndex, locKeys = set of "x,y", dispelledIds}
--  auraInstances  m_zoneAuraInstances with dispelled tiles removed, or nil
--                 when nothing is suppressed (use the base list)
--  overlayZones   m_zoneOverlayZones likewise, or nil
--  auraSources    index-aligned with m_zoneAuraInstances: the m_zoneCache
--                 entry an instance was built from (absent for surfaces and
--                 holes -- both pass through RebuildLists untouched)
--  overlaySources index-aligned with m_zoneOverlayZones, same idea
--  RebuildLists   derives auraInstances/overlayZones from the base lists
--  feedFootstepsMode / feedPanelOpen / feedZoneFilter
--                 the overlay feed's last-reported state; a flip bumps
--                 m_zoneRevision so the overlay mesh rebuilds (fields here
--                 rather than file-level locals: 200-locals cap)
local m_dispelState = {
    signature = false,
    footprints = {},
    auraInstances = nil,
    overlayZones = nil,
    auraSources = {},
    overlaySources = {},
}

--============================================================================
--Markup "Hole" zones: regions that cut a REAL hole through the floor, using
--the same tech as the excavate hole object (ObjectComponentExcavate).
--
--Storage: one markupZones record per drawn stroke, category "hole":
--  { category = "hole", polygons = { <polygon>, ... }, locs = {{x,y},...} }
--where <polygon> is a flat {x1,y1,x2,y2,...} ring as painted (v1), or a
--structured { points = ring, holes = {ring, ...} } entry once the eraser has
--clipped it (a rect erased from the middle of a hole leaves a donut). The
--cache normalizes both to the structured form on read. The drawn rings are
--kept (they shape the smooth visual cut, the way drawing floors keeps its
--polygons); the rasterized locs drive gameplay per tile, like zone records.
--
--Runtime: one AuraInstance per record with `hole = true` on its Aura
--definition (read by AuraInstance:GetHole). The engine turns that into
--forceGameRules.hole (GetTileRulesAtLoc reports no floor there), registers
--MapGeometry holes from the aura's tiles (creatures fall through), and builds
--the excavation visual from the polygons (MarkupHoleVisuals) -- the same
--alpha-punch material the excavate object uses, so the floor beneath shows
--through. While the Map Markup panel is open the engine hides the visual cut
--and the overlay feed stripes the holes like zones instead.
--
--Holes have no keyword and are not editable like zone types: no Edit dialog,
--no height, no Entire Map pill. The zone eraser CLIPS holes like floor
--erasing clips floors: the erase region is subtracted from the polygons via
--dmhub.ClipPolygons (trim, bisect, or donut; empty result deletes the
--record). On engines without ClipPolygons it falls back to deleting touched
--shapes whole.
--
--One table rather than several file-level locals: 200-locals cap.
--============================================================================
local m_holes = {
    color = "#555555",   --stripe/swatch color; holes have no keyword to color them
    cache = {},          --resolved hole entries, all floors; rebuilt with the zone cache
    overlayZones = {},   --stripe overlay entries, fed only while the panel is open
    engineSupport = nil,
}

--Engine capability probe. On a stale engine the hole aura registers as a
--harmless no-op aura and no hole appears, so painting refuses instead of
--appearing to do nothing. (Unknown dmhub properties read as nil silently, so
--== true is the whole test; see supportsObjectEditingFilter for the pattern.)
function m_holes.Supported()
    if m_holes.engineSupport == nil then
        m_holes.engineSupport = (dmhub.supportsMarkupHoles == true)
    end
    return m_holes.engineSupport
end

--The aura that makes a hole real: `hole = true` rides AuraInstance:GetHole
--into the engine (forceGameRules.hole + fall-through map geometry + the
--excavation visual); the polygons ride AuraInstance:GetHolePolygons into the
--visual's mesh.
function m_holes.BuildAuraInstance(entry)
    local auraType = rawget(_G, "Aura")
    local auraInstanceType = rawget(_G, "AuraInstance")
    if auraType == nil or auraInstanceType == nil then
        return nil
    end
    if entry.locsUserdata == nil or #entry.locsUserdata == 0 then
        return nil
    end

    local okShape, shape = pcall(function()
        return dmhub.CalculateShape{
            shape = "locations",
            locations = entry.locsUserdata,
            locOverride = entry.locsUserdata[1],
            range = 0,
            radius = 0,
            checklos = false,
        }
    end)
    if not okShape or shape == nil then
        return nil
    end

    local auraDef = auraType.Create{
        name = "Hole",
        applyto = "all",
        modifiers = {},
        hole = true,
    }

    --No casterid, no duration: permanent and floor-scoped, like zone auras.
    --guid = the record id so the aura identity is stable across rebuilds.
    return auraInstanceType.new{
        aura = auraDef,
        guid = entry.zoneid,
        name = "Hole",
        iconid = "ui-icons/skills/1.png",
        display = { bgcolor = m_holes.color, hueshift = 0, saturation = 1, brightness = 1 },
        area = shape,
        holePolygons = entry.polygons,
    }
end

--Writes a new hole record from a closed stroke. One record per stroke;
--overlapping holes simply overlap (the hole rule and the visual are both
--idempotent per tile), so there is none of the zones' merge/split machinery.
function m_holes.Paint(floor, points, locs)
    if not m_holes.Supported() then
        dmhub.Debug("MARKUP:: hole zones need an engine build with dmhub.supportsMarkupHoles")
        return
    end

    --copy the engine path's points into a plain flat array for storage.
    local polygon = {}
    for i = 1,#points do
        polygon[i] = points[i]
    end

    local cleanLocs = {}
    for _,l in ipairs(locs) do
        cleanLocs[#cleanLocs+1] = { x = l.x, y = l.y }
    end

    floor:SetMarkupZone(dmhub.GenerateGuid(), {
        category = "hole",
        polygons = { polygon },
        locs = cleanLocs,
    })
end

--The label the overlay paints on the map for a zone. Zone names exist to
--tell zones apart in the "Zones on This Floor" list; on the MAP the terrain
--type is the information, so auto-generated names ("Difficult Terrain",
--"Difficult Terrain 2") collapse to the bare type name. A zone the user
--deliberately renamed keeps its custom name on the map.
local function ZoneOverlayLabel(entry)
    local kwName = entry.keywordName
    if kwName == nil or kwName == "" then
        return entry.name
    end

    local name = entry.name or ""
    if name == kwName then
        return kwName
    end
    if string.gsub(name, "%s+%d+$", "") == kwName then
        return kwName
    end
    return name
end

--Rough location of a zone on the map for the "Zones on This Floor" list:
--the map's extent is cut into a 3x3 grid of areas, and the zone's centroid
--picks one. Indexed [row][col] with row 1 = south (low y), col 1 = west
--(low x); world +y is north (the top of the map).
local ZONE_AREA_NAMES = {
    { "SW Corner", "South Side", "SE Corner" },
    { "West Side", "Center",     "East Side" },
    { "NW Corner", "North Side", "NE Corner" },
}

local function ZoneAreaDescription(entry)
    if entry.locs == nil or #entry.locs == 0 then
        return nil
    end

    local dims = nil
    pcall(function()
        local map = game.currentMap
        if map ~= nil then
            dims = map.dimensions
        end
    end)
    if dims == nil then
        return nil
    end

    --dimensions = (dimMin.x, dimMin.y, dimMax.x+1, dimMax.y+1) in tile-index
    --space: tiles from x to z-1 inclusive. A loc's cell spans [x, x+1) there.
    local w = dims.z - dims.x
    local h = dims.w - dims.y
    if w <= 0 or h <= 0 then
        return nil
    end

    local cx, cy = 0, 0
    for _,l in ipairs(entry.locs) do
        cx = cx + l.x
        cy = cy + l.y
    end
    cx = cx / #entry.locs
    cy = cy / #entry.locs

    local fx = (cx + 0.5 - dims.x) / w
    local fy = (cy + 0.5 - dims.y) / h

    local col = 1 + math.floor(fx * 3)
    local row = 1 + math.floor(fy * 3)
    if col < 1 then col = 1 elseif col > 3 then col = 3 end
    if row < 1 then row = 1 elseif row > 3 then row = 3 end

    return ZONE_AREA_NAMES[row][col]
end

--The stripe color handed to the overlay: the stored pattern color with a
--~75% alpha suffix (matching the built-in zone stripe translucency) unless
--the stored color already carries explicit alpha. Only "#rrggbb" strings can
--take the suffix; named colors ("red") and shorthand forms pass through.
local function ZoneOverlayColor(color)
    if type(color) ~= "string" or color == "" then
        return "#d94a3dbf"
    end
    if string.sub(color, 1, 1) ~= "#" then
        return color
    end
    if string.len(color) == 7 then
        return color .. "bf"
    end
    return color
end

local function BuildZoneAuraInstance(entry)
    local auraType = rawget(_G, "Aura")
    local auraInstanceType = rawget(_G, "AuraInstance")
    if auraType == nil or auraInstanceType == nil then
        return nil
    end
    if entry.keywordInfo == nil or entry.locsUserdata == nil or #entry.locsUserdata == 0 then
        return nil
    end

    local okShape, shape = pcall(function()
        return dmhub.CalculateShape{
            shape = "locations",
            locations = entry.locsUserdata,
            locOverride = entry.locsUserdata[1],
            range = 0,
            radius = 0,
            checklos = false,
        }
    end)
    if not okShape or shape == nil then
        return nil
    end

    local auraDef = auraType.Create{
        name = entry.name,
        applyto = "all",
    }

    --Everything the keyword contributes -- terrain flags, modifiers, move
    --damage, entry power roll -- plus the keyword's own table id, which zone
    --auras need because zone names are uniquified per floor and user-renameable,
    --so runtime code that must know WHICH keyword this came from (e.g. the
    --creature "Environment" symbol) resolves the id rather than the name.
    --
    --Shared with the ability-aura path (ActivatedAbilityAuraBehavior:CastOnArea)
    --so a keyword means the same thing whether the area was painted here or
    --created by an ability. EnvironmentalKeyword loads after this module, hence
    --the runtime lookup.
    local environmentalKeywordType = rawget(_G, "EnvironmentalKeyword")
    if environmentalKeywordType ~= nil then
        environmentalKeywordType.ApplyToAura(auraDef, entry.keywordid)
    end

    if entry.height ~= nil then
        auraDef.auraHeight = entry.height
        --Zone bands follow the terrain: the engine measures [altitude,
        --altitude+height] up from the GROUND under each tile tested rather
        --than from the floor's zero altitude (Aura.BandBaseAtLoc /
        --BandBaseForToken). Without this a "ground only" zone would miss a
        --creature standing on a ledge inside it, and a height-2 gas cloud
        --painted across a slope would sit at one absolute altitude instead of
        --hugging the ground. entry.altitude stays an offset above ground.
        auraDef.auraGroundRelative = true
    end
    if entry.altitude ~= nil and entry.altitude ~= 0 then
        auraDef.auraAltitude = entry.altitude
    end

    local iconid = "ui-icons/skills/1.png"
    local display = { bgcolor = entry.patternColor, hueshift = 0, saturation = 1, brightness = 1 }
    pcall(function()
        iconid = entry.keywordInfo:try_get("iconid", iconid)
        local kwDisplay = entry.keywordInfo:try_get("display")
        if kwDisplay ~= nil then
            display = dmhub.DeepCopy(kwDisplay)
        end
    end)

    --The zone type's optional visual representation rides on the INSTANCE
    --(like holePolygons): purely presentational, read by the engine through
    --the AuraInstance:GetAppearance hook and rendered by MarkupZoneVisuals.
    --The dispel machinery rebuilds suppressed zones through this same
    --function with carved locsUserdata, so the visuals follow the carving.
    --Blanket ("Entire Map") entries skip it deliberately: repainting the
    --whole map's floor or scattering thousands of sprites from a palette
    --pill is a footgun. A zone whose visuals are toggled off (the Visuals
    --badge in the zone list, or painted while the type's Visuals pill was
    --off) skips it too and renders as stripes only.
    local appearance = nil
    if entry.entireMap ~= true and entry.hideAppearance ~= true then
        pcall(function()
            local kwAppearance = entry.keywordInfo:try_get("appearance")
            if kwAppearance == nil or kwAppearance.mode == nil or kwAppearance.mode == "none" then
                return
            end
            --hash seed derived from the keyword id: sprite layout and organic
            --edge noise key on absolute world coords + this seed, so
            --every zone of a keyword renders identically on every client and
            --every rebuild. Sprite choices never reshuffle on surviving tiles;
            --organic noise remains anchored to its world-space coordinates.
            local keywordid = entry.keywordid or ""
            local seed = 0
            for i = 1, #keywordid do
                seed = (seed * 33 + string.byte(keywordid, i)) % 1000000007
            end

            if kwAppearance.mode == "floor" then
                if kwAppearance.tileid ~= nil or kwAppearance.edgeWallId ~= nil then
                    appearance = {
                        mode = "floor",
                        tileid = kwAppearance.tileid,
                        edgeWallId = kwAppearance.edgeWallId,
                        alpha = kwAppearance.alpha,
                        fractalEdge = kwAppearance.fractalEdge or 0,
                        edgeFade = kwAppearance.edgeFade or 0,
                        seed = seed,
                    }
                end
            elseif kwAppearance.mode == "sprites" then
                local sprites = kwAppearance.sprites
                if sprites ~= nil and #sprites > 0 then
                    appearance = {
                        mode = "sprites",
                        sprites = dmhub.DeepCopy(sprites),
                        spriteScale = kwAppearance.spriteScale,
                        spriteAlpha = kwAppearance.spriteAlpha,
                        seed = seed,
                    }
                end
            end
        end)
    end

    --No casterid, no tokenAttached, no duration: a permanent, floor-scoped,
    --uncontrolled aura. guid = zoneid so triggers/entered-tracking key stably.
    return auraInstanceType.new{
        aura = auraDef,
        guid = entry.zoneid,
        name = entry.name,
        iconid = iconid,
        display = display,
        area = shape,
        appearance = appearance,
    }
end

--Builds the aura that applies a footstep-surface region to the game: it
--carries ONLY surfaceType (no modifiers, no rule flags), so the region
--affects footstep sounds and nothing else. Water flags from tile art or
--Water zones co-exist on the same tiles and win at playback time.
local function BuildSurfaceAuraInstance(entry)
    local auraType = rawget(_G, "Aura")
    local auraInstanceType = rawget(_G, "AuraInstance")
    if auraType == nil or auraInstanceType == nil then
        return nil
    end
    if entry.locsUserdata == nil or #entry.locsUserdata == 0 then
        return nil
    end

    local okShape, shape = pcall(function()
        return dmhub.CalculateShape{
            shape = "locations",
            locations = entry.locsUserdata,
            locOverride = entry.locsUserdata[1],
            range = 0,
            radius = 0,
            checklos = false,
        }
    end)
    if not okShape or shape == nil then
        return nil
    end

    --"Footsteps: Stone" rather than a bare "Stone": the aura name is what any
    --aura-listing UI would show, and the region only changes footstep sounds.
    local auraName = string.format("Footsteps: %s", entry.name)
    local auraDef = auraType.Create{
        name = auraName,
        applyto = "all",
        modifiers = {},
        surfaceType = entry.surface,
    }

    --guid: surface record ids repeat across floors ("surface-6" on every
    --floor), so qualify with the floor for a stable unique aura identity.
    return auraInstanceType.new{
        aura = auraDef,
        guid = string.format("%s-%s", entry.floorid, entry.zoneid),
        name = auraName,
        iconid = "ui-icons/skills/1.png",
        display = { bgcolor = entry.patternColor, hueshift = 0, saturation = 1, brightness = 1 },
        area = shape,
    }
end

--Builds the blanket entries for the current map: one per (blanket keyword,
--floor), covering the map's whole extent minus the tiles of painted zones
--that interact with that keyword. Called from RebuildZoneCache after the
--record walk, because it carves against the painted zones that walk found.
--`floors` is the {floorid, floorIndex} list collected there.
function m_entireMap.Rebuild(floors)
    m_entireMap.entries = {}

    local ids = m_entireMap.Keywords()
    if next(ids) == nil then
        return
    end

    local dims = nil
    pcall(function()
        local map = game.currentMap
        if map ~= nil then
            dims = map.dimensions
        end
    end)
    if dims == nil then
        return
    end

    --dimensions = (dimMin.x, dimMin.y, dimMax.x+1, dimMax.y+1) in tile-index
    --space -- tiles run x..z-1 inclusive. See ZoneAreaDescription.
    local x0, y0 = math.floor(dims.x), math.floor(dims.y)
    local x1, y1 = math.floor(dims.z) - 1, math.floor(dims.w) - 1
    if x1 < x0 or y1 < y0 then
        return
    end

    local dynThresholds = m_dynamicLight.Thresholds()

    for keywordid,_ in pairs(ids) do
        local kw = GetKeyword(keywordid)
        if kw ~= nil then
            local dispels = KeywordDispels(kw)
            local kwName = kw.name or "Zone"
            local dynPct = dynThresholds[keywordid]

            for _,floorInfo in ipairs(floors) do
                --tiles the blanket yields to. Same keyword: a painted zone
                --already covers them (and a second aura would double up any
                --damage/modifier the keyword carries). Either dispel
                --direction: the explicitly painted zone takes the ground,
                --matching "last drawn wins" at paint time.
                local blocked = {}
                for _,entry in ipairs(m_zoneCache) do
                    if entry.floorid == floorInfo.floorid and entry.keywordid ~= nil
                        and (entry.keywordid == keywordid
                            or dispels[entry.keywordid] ~= nil
                            or KeywordDispels(entry.keywordInfo)[keywordid] ~= nil) then
                        for _,l in ipairs(entry.locs) do
                            blocked[ZoneLocKey(l.x, l.y)] = true
                        end
                    end
                end

                --a dynamic-light blanket covers only the tiles the light
                --sampler currently reports dark. No sample yet = covers
                --nothing: on a lit map that avoids a flash of whole-map
                --darkness in the second before the first sample lands.
                local darkState = nil
                if dynPct ~= nil then
                    darkState = m_dynamicLight.states[m_dynamicLight.StateKey(floorInfo.floorid, dynPct)]
                end

                local locs = {}
                if dynPct == nil or darkState ~= nil then
                    for y = y0, y1 do
                        for x = x0, x1 do
                            local key = ZoneLocKey(x, y)
                            if blocked[key] == nil
                                and (dynPct == nil or darkState.dark[key] ~= nil) then
                                locs[#locs+1] = { x = x, y = y }
                            end
                        end
                    end
                end

                if #locs > 0 then
                    m_entireMap.entries[#m_entireMap.entries+1] = {
                        --stable per keyword+floor: the aura guid keys
                        --triggers and entered-tracking off it.
                        zoneid = string.format("entiremap-%s-%s", keywordid, floorInfo.floorid),
                        floorid = floorInfo.floorid,
                        floorIndex = floorInfo.floorIndex,
                        name = kwName,
                        keywordid = keywordid,
                        keywordName = kwName,
                        keywordInfo = kw,
                        flags = KeywordFlags(kw),
                        locs = locs,
                        altitude = 0,
                        --height stays absent: unlimited, so the blanket
                        --reaches flyers as well as the ground.
                        playerVisible = false,
                        patternColor = KeywordColor(keywordid, kw),
                        patternAngle = m_zoneStripes.AngleForKeyword(keywordid),
                        entireMap = true,
                    }
                end
            end
        end
    end
end

local function RebuildZoneCache()
    m_zoneCache = {}
    m_surfaceCache = {}
    m_zoneAuraInstances = {}
    m_zoneOverlayZones = {}
    m_surfaceOverlayZones = {}
    m_footstepsOverlayZones = {}
    m_holes.cache = {}
    m_holes.overlayZones = {}

    --any active dispel suppression must re-derive against the fresh lists;
    --signature=false forces that on the next EnsureKeywordAuraZones.
    m_dispelState.signature = false
    m_dispelState.auraInstances = nil
    m_dispelState.overlayZones = nil
    m_dispelState.auraSources = {}
    m_dispelState.overlaySources = {}

    local map = game.currentMap
    if map == nil then
        --no map = no zone instances: any running zone scripts must get their
        --exit routine. (EnvironmentalKeyword loads after this file, so it is
        --resolved at call time, rawget-guarded like the other keyword refs.)
        local keywordType = rawget(_G, "EnvironmentalKeyword")
        if keywordType ~= nil and rawget(keywordType, "SyncZoneScripts") ~= nil then
            keywordType.SyncZoneScripts({})
        end
        return
    end

    --every floor the map currently shows, for the "Entire Map" blanket pass
    --below. Layers are separate entries here with their own floorIndex, which
    --is right: a token stands on exactly one of them.
    local floorList = {}

    for _,floor in ipairs(map.floors or {}) do
        local zones = nil
        local floorIndex = nil
        pcall(function()
            zones = floor.markupZones
            floorIndex = floor.floorIndex
        end)

        if floorIndex ~= nil and floorIndex >= 0 then
            floorList[#floorList+1] = { floorid = floor.floorid, floorIndex = floorIndex }
        end

        --floorIndex is -1 when the floor isn't currently visible (e.g. the
        --title screen); keep the records in the cache (the zone list needs
        --them) and skip only the aura/overlay build below.
        if zones ~= nil and floorIndex ~= nil then
            local floorid = floor.floorid
            for zoneid,record in pairs(zones) do
                if type(record) == "table" and record.category == "surface" then
                    local surfaceId = math.floor(tonumber(record.surface) or 0)
                    local surfaceInfo = SurfaceInfoById(surfaceId)
                    local locs = {}
                    for _,l in ipairs(record.locs or {}) do
                        if type(l) == "table" and l.x ~= nil and l.y ~= nil then
                            locs[#locs+1] = { x = math.floor(l.x), y = math.floor(l.y) }
                        end
                    end

                    local name = record.surfaceName or "Surface"
                    if surfaceInfo ~= nil then
                        name = surfaceInfo.text
                    end

                    m_surfaceCache[#m_surfaceCache+1] = {
                        zoneid = zoneid,
                        floorid = floorid,
                        floorIndex = floorIndex,
                        surface = surfaceId,
                        name = name,
                        locs = locs,
                        patternColor = SurfaceColor(surfaceId),
                        --a surface family is exclusive per tile and has no
                        --keyword, so its angle just alternates by family id;
                        --stored here so the panel's swatch can match the map.
                        patternAngle = cond(surfaceId % 2 == 0, ZONE_ANGLE_B, ZONE_ANGLE_A),
                    }
                elseif type(record) == "table" and record.category == "hole" then
                    local locs = {}
                    for _,l in ipairs(record.locs or {}) do
                        if type(l) == "table" and l.x ~= nil and l.y ~= nil then
                            locs[#locs+1] = { x = math.floor(l.x), y = math.floor(l.y) }
                        end
                    end

                    --normalize each stored polygon to the structured form
                    --{points = flat ring, holes = {flat ring, ...}}. Paint
                    --writes flat rings (the v1 shape); the eraser's clip
                    --rewrites write structured entries. A valid ring is a
                    --flat array of at least three vertices.
                    local polygons = {}
                    for _,polygon in ipairs(record.polygons or {}) do
                        if type(polygon) == "table" then
                            if type(polygon[1]) == "number" then
                                if #polygon >= 6 then
                                    polygons[#polygons+1] = { points = polygon, holes = {} }
                                end
                            elseif type(polygon.points) == "table" and #polygon.points >= 6 then
                                local holeRings = {}
                                for _,holeRing in ipairs(polygon.holes or {}) do
                                    if type(holeRing) == "table" and #holeRing >= 6 then
                                        holeRings[#holeRings+1] = holeRing
                                    end
                                end
                                polygons[#polygons+1] = { points = polygon.points, holes = holeRings }
                            end
                        end
                    end

                    m_holes.cache[#m_holes.cache+1] = {
                        zoneid = zoneid,
                        floorid = floorid,
                        floorIndex = floorIndex,
                        locs = locs,
                        polygons = polygons,
                    }
                elseif type(record) == "table" and record.category == nil then
                    --resolve the keyword by id, healing dead ids by stored
                    --name (ids can be lost to the objectTable-creation race;
                    --see MaterializeZonePreset). The healed id flows back
                    --into the record on the zone's next write.
                    local kwId = record.keyword
                    local kw = GetKeyword(kwId)
                    if kw == nil and record.keywordName ~= nil then
                        local healedId = FindKeywordIdByName(record.keywordName)
                        if healedId ~= nil then
                            kwId = healedId
                            kw = GetKeyword(healedId)
                        end
                    end
                    local kwName = record.keywordName
                    if kw ~= nil and kw.name ~= nil then
                        kwName = kw.name
                    end
                    local pattern = record.pattern or {}

                    --the keyword's LIVE color wins so recoloring a keyword in
                    --the compendium recolors its painted zones. The color
                    --stored on the record is only a fallback for records
                    --whose keyword can't be resolved (dead id from the
                    --table-creation race; see MaterializeZonePreset).
                    local patternColor
                    if kw ~= nil then
                        patternColor = KeywordColor(kwId, kw)
                    else
                        patternColor = pattern.color or KeywordColor(kwId, kw)
                    end

                    --the angle is derived from the keyword for the same reason
                    --the color is: it must be the same for every zone of that
                    --keyword on the map, whatever angle happened to be stored
                    --when each one was painted. Deriving it needs the whole map
                    --at once (see AssignZoneStripeAngles), so this is only the
                    --fallback for records whose keyword can't be resolved; the
                    --second pass below overwrites the rest.
                    local locs = {}
                    for _,l in ipairs(record.locs or {}) do
                        if type(l) == "table" and l.x ~= nil and l.y ~= nil then
                            locs[#locs+1] = { x = math.floor(l.x), y = math.floor(l.y) }
                        end
                    end

                    m_zoneCache[#m_zoneCache+1] = {
                        zoneid = zoneid,
                        floorid = floorid,
                        floorIndex = floorIndex,
                        name = record.name or "Zone",
                        keywordid = kwId,
                        keywordName = kwName,
                        keywordInfo = kw,
                        flags = KeywordFlags(kw),
                        locs = locs,
                        altitude = record.altitude or 0,
                        height = record.height,
                        playerVisible = record.playerVisible == true,
                        hideAppearance = record.hideAppearance == true,
                        patternColor = patternColor,
                        patternAngle = pattern.angle or ZONE_ANGLE_A,
                        ord = record.ord or 0,
                    }
                end
            end
        end
    end

    --Stripe angles are decided across the whole map at once so similar-coloured
    --keywords land on opposite angles, which can only happen once every zone is
    --in the cache. Records whose keyword didn't resolve keep the angle stored
    --on them (AngleForKeyword has nothing better to offer for a dead id).
    AssignZoneStripeAngles(m_zoneCache)
    for _,entry in ipairs(m_zoneCache) do
        if entry.keywordid ~= nil then
            entry.patternAngle = m_zoneStripes.AngleForKeyword(entry.keywordid)
        end
    end

    table.sort(m_surfaceCache, function(a, b)
        if a.floorid ~= b.floorid then
            return a.floorid < b.floorid
        end
        return a.surface < b.surface
    end)

    --Surface overlay entries go in their own list: the feed hands the engine
    --the rules zones normally, or - on the Footsteps tab - the footstep
    --surface regions plus the water rules zones (assembled into
    --m_footstepsOverlayZones below; see dmhub.GetMarkupZones). Surfaces
    --render in the normal zone-stripe style, distinguished by the footprints
    --icon on their labels; the stripe angle alternates by family so adjacent
    --regions of similar colors still read as distinct.
    for _,entry in ipairs(m_surfaceCache) do
        if #entry.locs > 0 and entry.floorIndex >= 0 then
            local locsUserdata = {}
            for _,l in ipairs(entry.locs) do
                locsUserdata[#locsUserdata+1] = core.Loc{
                    x = l.x,
                    y = l.y,
                    floorIndex = entry.floorIndex,
                }
            end
            entry.locsUserdata = locsUserdata

            m_surfaceOverlayZones[#m_surfaceOverlayZones+1] = {
                locs = locsUserdata,
                color = ZoneOverlayColor(entry.patternColor),
                angleRadians = entry.patternAngle,
                label = entry.name,
                labelIcon = "phosphor/footprints-fill.png",
                playerVisible = false,
                floorIndex = entry.floorIndex,
            }

            local instance = BuildSurfaceAuraInstance(entry)
            if instance ~= nil then
                m_zoneAuraInstances[#m_zoneAuraInstances+1] = instance
            end
        end
    end

    table.sort(m_zoneCache, function(a, b)
        if a.floorid ~= b.floorid then
            return a.floorid < b.floorid
        end
        if a.ord ~= b.ord then
            return a.ord < b.ord
        end
        return a.zoneid < b.zoneid
    end)

    --dynamic-light types register/stripe only their currently-dark tiles; the
    --record locs (entry.locs) stay pristine -- they drive painting/splitting.
    local dynThresholds = m_dynamicLight.Thresholds()

    for _,entry in ipairs(m_zoneCache) do
        local paintLocs = m_dynamicLight.ApplyFilter(dynThresholds, entry)
        if #paintLocs > 0 and entry.floorIndex >= 0 then
            local locsUserdata = {}
            for _,l in ipairs(paintLocs) do
                locsUserdata[#locsUserdata+1] = core.Loc{
                    x = l.x,
                    y = l.y,
                    floorIndex = entry.floorIndex,
                }
            end
            entry.locsUserdata = locsUserdata

            m_zoneOverlayZones[#m_zoneOverlayZones+1] = {
                locs = locsUserdata,
                color = ZoneOverlayColor(entry.patternColor),
                angleRadians = entry.patternAngle,
                label = ZoneOverlayLabel(entry),
                playerVisible = entry.playerVisible,
                difficultTerrain = entry.flags.difficultTerrain,
                water = entry.flags.water,
                concealment = entry.flags.concealment,
                climbable = entry.flags.climbable,
                floorIndex = entry.floorIndex,
                --the engine ignores this; the feed uses it to filter zones by
                --the user's per-zone-type visibility preference.
                keywordid = entry.keywordid,
                --likewise ignored by the engine: the feed uses it to apply the
                --Zones list's per-group opacity slider. Separate from
                --keywordid because a record with an unresolvable keyword still
                --belongs to a group (see m_zoneStripes.GroupKey).
                zonegroup = m_zoneStripes.GroupKey(entry),
            }
            m_dispelState.overlaySources[#m_zoneOverlayZones] = entry

            local instance = BuildZoneAuraInstance(entry)
            if instance ~= nil then
                m_zoneAuraInstances[#m_zoneAuraInstances+1] = instance
                m_dispelState.auraSources[#m_zoneAuraInstances] = entry
            end
        end
    end

    --Markup holes: one aura per record. No dispel bookkeeping (holes have no
    --keyword): instances appended WITHOUT an auraSources entry pass through
    --m_dispelState.RebuildLists untouched, which is exactly right. The overlay
    --entries go in their own list; the feed appends them only while the panel
    --is open (with it closed the engine renders the actual hole instead).
    for _,entry in ipairs(m_holes.cache) do
        if #entry.locs > 0 and entry.floorIndex >= 0 then
            local locsUserdata = {}
            for _,l in ipairs(entry.locs) do
                locsUserdata[#locsUserdata+1] = core.Loc{
                    x = l.x,
                    y = l.y,
                    floorIndex = entry.floorIndex,
                }
            end
            entry.locsUserdata = locsUserdata

            m_holes.overlayZones[#m_holes.overlayZones+1] = {
                locs = locsUserdata,
                color = ZoneOverlayColor(m_holes.color),
                angleRadians = ZONE_ANGLE_A,
                label = "Hole",
                playerVisible = false,
                floorIndex = entry.floorIndex,
            }

            local instance = m_holes.BuildAuraInstance(entry)
            if instance ~= nil then
                m_zoneAuraInstances[#m_zoneAuraInstances+1] = instance
            end
        end
    end

    --"Entire Map" types: one aura per floor over everything the painted zones
    --left it, and NO overlay entry - a blanket that striped the whole map
    --would bury the zones the DM is painting. They go in auraSources like any
    --other zone so a live dispelling aura suppresses them the same way.
    m_entireMap.Rebuild(floorList)
    for _,entry in ipairs(m_entireMap.entries) do
        local locsUserdata = {}
        for _,l in ipairs(entry.locs) do
            locsUserdata[#locsUserdata+1] = core.Loc{
                x = l.x,
                y = l.y,
                floorIndex = entry.floorIndex,
            }
        end
        entry.locsUserdata = locsUserdata

        local instance = BuildZoneAuraInstance(entry)
        if instance ~= nil then
            m_zoneAuraInstances[#m_zoneAuraInstances+1] = instance
            m_dispelState.auraSources[#m_zoneAuraInstances] = entry
        end
    end

    --Footsteps-mode feed list: the surface regions plus any WATER rules
    --zones. A water tile plays water sounds over any painted footstep
    --surface, so the DM needs to see water while painting footsteps. Water
    --zones go last so they draw over surface stripes where the two overlap
    --(the water sound is what actually wins there).
    for _,overlayZone in ipairs(m_surfaceOverlayZones) do
        m_footstepsOverlayZones[#m_footstepsOverlayZones+1] = overlayZone
    end
    for _,overlayZone in ipairs(m_zoneOverlayZones) do
        if overlayZone.water then
            m_footstepsOverlayZones[#m_footstepsOverlayZones+1] = overlayZone
        end
    end

    --Zone scripts: one instance of a keyword's Lua script per zone of that
    --keyword on the map, Entire Map blankets included. The runtime lives in
    --EnvironmentalKeyword.lua; it diffs against the previous rebuild, so
    --zones that appeared here instantiate and zones that vanished run their
    --guaranteed exit routine. Runs LAST so every entry's locsUserdata (the
    --active tiles - dynamic light already applied) is in place.
    --(EnvironmentalKeyword loads after this file: resolve at call time,
    --rawget-guarded like the other keyword refs.)
    local keywordType = rawget(_G, "EnvironmentalKeyword")
    if keywordType ~= nil and rawget(keywordType, "SyncZoneScripts") ~= nil then
        keywordType.SyncZoneScripts({m_zoneCache, m_entireMap.entries})
    end
end

--Derives the dispel-suppressed lists from the base lists and the current
--footprints: zones of a dispelled keyword lose the tiles a dispelling aura
--covers, in both the registered aura (rules) and the overlay (stripes). The
--records are untouched -- when the aura leaves, the footprints change and
--the full zone comes back. nil derived lists mean "nothing suppressed, use
--the base lists". Coordinates are rounded before keying: aura-area locs are
--not guaranteed exact integers (see CollectKeywordAuraZones).
--(A field on m_dispelState rather than a chunk local: locals-cap, see above.)
function m_dispelState.RebuildLists()
    m_dispelState.auraInstances = nil
    m_dispelState.overlayZones = nil

    local footprints = m_dispelState.footprints or {}
    if #footprints == 0 then
        return
    end

    --zoneid -> set of suppressed "x,y" keys. Painted zones and "Entire Map"
    --blankets alike: a live dispelling aura carves both.
    local suppressedByZone = {}
    local CollectSuppressed = function(entries)
        for _,entry in ipairs(entries or {}) do
            if entry.keywordid ~= nil and entry.floorIndex ~= nil and entry.floorIndex >= 0 then
                local suppressed = nil
                for _,fp in ipairs(footprints) do
                    if fp.floorIndex == entry.floorIndex and fp.dispelledIds[entry.keywordid] ~= nil then
                        for _,l in ipairs(entry.locs) do
                            local key = ZoneLocKey(l.x, l.y)
                            if fp.locKeys[key] ~= nil then
                                suppressed = suppressed or {}
                                suppressed[key] = true
                            end
                        end
                    end
                end
                if suppressed ~= nil then
                    suppressedByZone[entry.zoneid] = suppressed
                end
            end
        end
    end
    CollectSuppressed(m_zoneCache)
    CollectSuppressed(m_entireMap.entries)

    if next(suppressedByZone) == nil then
        return
    end

    local instances = {}
    for i,instance in ipairs(m_zoneAuraInstances) do
        local entry = m_dispelState.auraSources[i]
        local suppressed = nil
        if entry ~= nil then
            suppressed = suppressedByZone[entry.zoneid]
        end
        if suppressed == nil then
            instances[#instances+1] = instance
        else
            local filtered = {}
            for _,loc in ipairs(entry.locsUserdata or {}) do
                if suppressed[ZoneLocKey(math.floor(loc.x + 0.5), math.floor(loc.y + 0.5))] == nil then
                    filtered[#filtered+1] = loc
                end
            end
            --a fully-suppressed zone registers no aura at all.
            if #filtered > 0 then
                local subEntry = {}
                for k,v in pairs(entry) do
                    subEntry[k] = v
                end
                subEntry.locsUserdata = filtered
                local subInstance = BuildZoneAuraInstance(subEntry)
                if subInstance ~= nil then
                    instances[#instances+1] = subInstance
                end
            end
        end
    end
    m_dispelState.auraInstances = instances

    local overlays = {}
    for i,zone in ipairs(m_zoneOverlayZones) do
        local entry = m_dispelState.overlaySources[i]
        local suppressed = nil
        if entry ~= nil then
            suppressed = suppressedByZone[entry.zoneid]
        end
        if suppressed == nil then
            overlays[#overlays+1] = zone
        else
            local filtered = {}
            for _,loc in ipairs(zone.locs or {}) do
                if suppressed[ZoneLocKey(math.floor(loc.x + 0.5), math.floor(loc.y + 0.5))] == nil then
                    filtered[#filtered+1] = loc
                end
            end
            if #filtered > 0 then
                local copy = {}
                for k,v in pairs(zone) do
                    copy[k] = v
                end
                copy.locs = filtered
                overlays[#overlays+1] = copy
            end
        end
    end
    m_dispelState.overlayZones = overlays
end

local function EnsureZoneCache()
    if not ZonesSupported() then
        return
    end

    local seq = dmhub.markupZonesSeq
    local mapid = game.currentMapId
    --blankets live in a per-map setting, not in the zone records, so no
    --record write (and no seq bump) accompanies a change to them -- here or
    --on another client. Compare the value itself. Dynamic light is the same
    --shape: a per-map setting plus the sampling serial.
    local blanketKey = m_entireMap.CacheKey()
    local dynamicKey = m_dynamicLight.CacheKey()
    if m_zoneCache ~= nil and seq == m_zoneCacheSeq and mapid == m_zoneCacheMapid
        and m_zoneCacheTablesGen == m_zoneTablesGen and blanketKey == m_entireMap.cacheKey
        and dynamicKey == m_dynamicLight.cacheKey then
        return
    end

    m_zoneCacheSeq = seq
    m_zoneCacheMapid = mapid
    m_zoneCacheTablesGen = m_zoneTablesGen
    m_entireMap.cacheKey = blanketKey
    m_dynamicLight.cacheKey = dynamicKey
    m_zoneRevision = m_zoneRevision + 1
    RebuildZoneCache()
end

--The engine hooks (dmhub.GetMapAuras / dmhub.GetMarkupZones) are assigned
--BELOW EnsureKeywordAuraZones -- both closures call it, and a local is only
--captured when it is already in scope at closure creation (the same trap as
--m_markupHudRef above).

--Openness is read from the LIVE panel, not from the show/hide events.
--showpanel/hidepanel only fire on a dock TAB switch (DockablePanel.lua's
--buttonContainer `select`), so a tracked flag goes stale in two ways that
--both leave the overlay dark with the panel plainly on screen:
--  * a Lua reload rebuilds the panel content (refreshMod -> init -> content())
--    with no showpanel;
--  * a saved dock layout can build the content at startup without showing it.
--So: open means the content exists, is alive, is parented into the UI, and no
--ancestor is collapsed away. Every host hides this content with the
--"collapsed" class on some ancestor -- the dock on its dockablePanel, the
--rail panel window (DocumentSystem's PanelDocument host, which has NO
--dockablePanel ancestor) on both its per-tab wrapper (tab switched away) and
--its contentArea (window shaded) -- so walking the parent chain covers all of
--them, plus the harness, without host-specific casing. Checking only the
--dockablePanel ancestor here was exactly the bug that left the Fade Map
--slider dead when the panel was hosted in a rail window.
local function MarkupPanelIsOpen()
    local hud = m_markupHudRef()
    if hud == nil or not hud.valid then
        return false
    end
    local ok, parent = pcall(function() return hud.parent end)
    if not ok or parent == nil then
        return false
    end

    local p = parent
    while p ~= nil and p.valid do
        if p:HasClass("collapsed") then
            return false
        end
        local okParent, nextParent = pcall(function() return p.parent end)
        if not okParent then
            return false
        end
        p = nextParent
    end

    return true
end

--Live auras that name an Environmental Keyword paint like a hand-painted zone:
--the keyword's colour, the keyword's name, and the same stripe treatment, so
--darkness dropped by an ability reads identically to a Darkness zone painted
--here. Without this they fall through to the engine's built-in terrain-rule
--overlay, which flood-fills by rule flag and labels generically -- an ability's
--darkness came out as "Concealment" (TileHeightOverlay.cs ZoneLabelText).
--Routing them through this feed also suppresses the built-in stripe on their
--tiles (BuiltinZoneSuppressed), so the two treatments don't double up.
--
--Auras are reached through their owners: everything cast onto the map or granted
--by an aura modifier is registered on a creature (creature:AddAura). Auras on
--map OBJECTS (AuraComponent) are not reachable from Lua and so are not covered.
--Painted zones are not collected here either -- they reach the feed already,
--via m_zoneCache.
--
--State lives in one table rather than two locals: this chunk is close to Lua's
--200-locals-per-function cap. `instances` holds the rules-only AuraInstance
--clones registered with the engine for keyword auras that have no other
--registration path (see CollectKeywordAuraZones below).
local m_keywordAuraOverlay = { zones = {}, signature = false, instances = nil }

--Appends one overlay entry per (aura, keyword) pair, and accumulates into
--`signature` everything the resulting overlay mesh depends on. Also appends
--a dispel footprint per (aura, keyword-with-dispels) pair into `footprints`
--(the tiles where that keyword's dispelled zones are suppressed; see
--m_dispelState) and accumulates everything the suppression depends on into
--`dispelSignature`.
--
--`ruleSources` collects the aura instances that need ENGINE RULES
--registration through the dmhub.GetMapAuras feed: a placed (not
--token-attached) aura's tile rules normally reach the engine through its
--spawned map object, and a token-attached aura's through
--CharacterToken.CalculateAuras -- but a placed aura with NO object (the
--zone-styled ability auras, e.g. Shadow Drag's difficult terrain trail) has
--neither vehicle, so its difficult_terrain/water/move-damage rules would
--silently not exist. Those instances are cloned rules-only (modifiers
--stripped -- the token-aura walk already applies modifiers Lua-side, so
--carrying them here would double-apply) and returned from the GetMapAuras
--hook alongside the zone auras.
local function CollectKeywordAuraZones(auraInstance, keywordsTable, zones, signature, footprints, dispelSignature, ruleSources)
    local auraDef = auraInstance:try_get("aura")
    if auraDef == nil then
        return
    end

    --Parent and sub-auras each carry their own keyword and share one area, so a
    --single aura can paint its tiles with more than one keyword.
    local keywordIds = {}
    local seenKeywords = {}
    local function AddKeyword(keywordid)
        if keywordid ~= nil and seenKeywords[keywordid] == nil then
            seenKeywords[keywordid] = true
            keywordIds[#keywordIds+1] = keywordid
        end
    end

    AddKeyword(auraDef:try_get("environmentalKeywordId"))
    for _,childDef in ipairs(auraDef:try_get("subauras", {})) do
        AddKeyword(childDef:try_get("environmentalKeywordId"))
    end

    if #keywordIds == 0 then
        return
    end

    local area = auraInstance:GetArea()
    if area == nil then
        return
    end

    --One floor per entry, matching the engine's per-floor emit. An aura area
    --sits on a single floor in practice; the first location decides, and stray
    --locations from another floor are dropped rather than mislabelled there.
    --
    --The read accessor is loc.floor (Definitions/Loc.lua), NOT loc.floorIndex --
    --core.Loc{} takes floorIndex when CONSTRUCTING one, but reading that name
    --back yields nil silently, which drops every aura here.
    local locs = {}
    local floorIndex = nil
    for _,loc in ipairs(area.locations or {}) do
        if floorIndex == nil then
            floorIndex = loc.floor
        end
        if loc.floor == floorIndex then
            locs[#locs+1] = loc
            --plain concatenation, not string.format("%d"): that throws in 5.4 on
            --any coordinate without an exact integer representation, and this
            --runs inside a pcall where the throw would silently drop the aura.
            signature[#signature+1] = floorIndex .. "." .. loc.x .. "." .. loc.y
        end
    end

    if #locs == 0 or floorIndex == nil or floorIndex < 0 then
        return
    end

    --Needs engine-rules registration via GetMapAuras: placed (not
    --token-attached, so CharacterToken doesn't register it) and objectless
    --(so no spawned object registers it either).
    if not auraInstance:try_get("tokenAttached", false) and auraInstance:try_get("object") == nil then
        ruleSources[#ruleSources+1] = auraInstance
    end

    for _,keywordid in ipairs(keywordIds) do
        local keyword = keywordsTable[keywordid]
        if keyword ~= nil then
            local flags = KeywordFlags(keyword)
            zones[#zones+1] = {
                locs = locs,
                color = ZoneOverlayColor(KeywordColor(keywordid, keyword)),
                --same angle a painted zone of this keyword gets, so an
                --ability's darkness stripes identically to a Darkness zone.
                angleRadians = m_zoneStripes.AngleForKeyword(keywordid),
                label = keyword.name,
                --a painted zone can be DM-only, but an aura is already on screen
                --for everyone, so hiding just its label would be strange.
                playerVisible = true,
                difficultTerrain = flags.difficultTerrain,
                water = flags.water,
                concealment = flags.concealment,
                climbable = flags.climbable,
                floorIndex = floorIndex,
                --the engine ignores this; the feed uses it to filter zones by
                --the user's per-zone-type visibility preference.
                keywordid = keywordid,
            }
            signature[#signature+1] = keywordid

            --dispel footprint: the aura's tiles, keyed the way zone locs are
            --keyed. Rounded rather than %d-formatted for the same reason as
            --the concatenation note above: coordinates are not guaranteed to
            --be exact integers, and this runs inside a pcall where a throw
            --would silently drop the aura.
            local dispelledIds = KeywordDispels(keyword)
            if next(dispelledIds) ~= nil then
                local locKeys = {}
                for _,loc in ipairs(locs) do
                    locKeys[ZoneLocKey(math.floor(loc.x + 0.5), math.floor(loc.y + 0.5))] = true
                end
                footprints[#footprints+1] = {
                    floorIndex = floorIndex,
                    locKeys = locKeys,
                    dispelledIds = dispelledIds,
                }
                for dispelledId,_ in pairs(dispelledIds) do
                    dispelSignature[#dispelSignature+1] = keywordid .. ">" .. dispelledId
                end
                for _,loc in ipairs(locs) do
                    dispelSignature[#dispelSignature+1] = keywordid .. "@" .. floorIndex .. "." .. loc.x .. "." .. loc.y
                end
            end
        end
    end
end

--Rebuilds the keyword-aura overlay entries when anything they depend on moves.
--This runs on the every-frame feed, so the walk stays cheap (tokens and their
--aura lists) and the entries are only replaced -- and the overlay revision only
--bumped -- when the signature actually changes. Auras follow their token and
--expire mid-round, so the signature covers occupied tiles as well as identity:
--miss that and the overlay keeps drawing darkness that has already ended, or
--fails to draw one just cast. The signature is sorted so it identifies the SET
--of painted tiles: were it order-sensitive, any reshuffle of area.locations
--would bump the revision every frame and re-mesh the overlay continuously.
local function EnsureKeywordAuraZones(suppressAuraRefresh)
    local zones = {}
    local signature = {}
    local footprints = {}
    local dispelSignature = {}
    local ruleSources = {}

    pcall(function()
        local keywordsTable = dmhub.GetTable(ENVIRONMENTAL_KEYWORDS_TABLE) or {}
        for _,token in ipairs(dmhub.allTokensIncludingObjects) do
            local props = token.properties
            if props ~= nil then
                local auras = props:try_get("auras", {})
                local ok, generatedAuras = pcall(function()
                    if type(props.GetAuras) == "function" then
                        return props:GetAuras()
                    end
                end)
                if ok and generatedAuras ~= nil then
                    auras = generatedAuras
                end

                --one bad aura shouldn't cost the whole overlay.
                for _,auraInstance in ipairs(auras) do
                    pcall(function()
                        if not auraInstance:try_get("isChildAura", false) then
                            CollectKeywordAuraZones(auraInstance, keywordsTable, zones, signature, footprints, dispelSignature, ruleSources)
                        end
                    end)
                end
            end
        end
    end)

    table.sort(signature)
    local newSignature = table.concat(signature, "|")
    if newSignature ~= m_keywordAuraOverlay.signature then
        m_keywordAuraOverlay.signature = newSignature
        m_keywordAuraOverlay.zones = zones
        m_zoneRevision = m_zoneRevision + 1

        --Rebuild the rules-only clones the GetMapAuras hook hands the engine
        --(see the ruleSources note on CollectKeywordAuraZones). Rebuilt only on
        --signature change: this walk runs on the every-frame overlay feed, and
        --per-frame DeepCopies would be pure garbage churn. The clone shares the
        --source instance's guid (so entered-tracking keys the same) and its
        --area userdata, and carries casterid/casterPartyId so the engine's
        --ApplyTo allegiance gating of the tile rules keeps working.
        local instances = {}
        pcall(function()
            local auraInstanceType = rawget(_G, "AuraInstance")
            if auraInstanceType ~= nil then
                for _,src in ipairs(ruleSources) do
                    pcall(function()
                        local def = dmhub.DeepCopy(src:try_get("aura"))
                        def.modifiers = {}
                        for _,child in ipairs(def:try_get("subauras", {})) do
                            child.modifiers = {}
                        end
                        instances[#instances+1] = auraInstanceType.new{
                            aura = def,
                            guid = src:try_get("guid"),
                            name = src:try_get("name"),
                            iconid = src:try_get("iconid", "ui-icons/skills/1.png"),
                            display = src:try_get("display"),
                            casterid = src:try_get("casterid"),
                            casterPartyId = src:try_get("casterPartyId"),
                            area = src:GetArea(),
                        }
                    end)
                end
            end
        end)
        m_keywordAuraOverlay.instances = instances

        --The engine only learns about these rules by re-polling the map-aura
        --feed; most changes (a cast, an expiry) already trigger an aura
        --rebuild, but ask for one explicitly so the rules can never lag the
        --stripes. Suppressed while the engine is polling us right now.
        if not suppressAuraRefresh then
            pcall(function()
                dmhub.RefreshMapAuras()
            end)
        end
    end

    --Dispel suppression rides the same walk. When the footprints change
    --(a dispelling aura appeared, moved, or expired -- or the zone cache was
    --rebuilt, which resets the signature to false), re-derive the suppressed
    --lists; and when that actually changes what is suppressed, re-mesh the
    --overlay and ask the engine to re-poll the map auras. suppressAuraRefresh
    --skips the re-poll request when the engine is polling us RIGHT NOW
    --(dmhub.GetMapAuras below) -- the fresh lists are what it receives.
    table.sort(dispelSignature)
    local newDispelSignature = table.concat(dispelSignature, "|")
    if newDispelSignature ~= m_dispelState.signature then
        local hadSuppression = m_dispelState.auraInstances ~= nil
        m_dispelState.signature = newDispelSignature
        m_dispelState.footprints = footprints
        m_dispelState.RebuildLists()

        if hadSuppression or m_dispelState.auraInstances ~= nil then
            m_zoneRevision = m_zoneRevision + 1
            if not suppressAuraRefresh then
                pcall(function()
                    dmhub.RefreshMapAuras()
                end)
            end
        end
    end

    return m_keywordAuraOverlay.zones
end

--The engine hooks. Assigned inside pcall: on a stale engine build these
--dmhub properties don't exist and assignment raises - zones then simply
--don't register or render, and the panel shows its needs-an-engine-build
--notice. We own these hooks outright (no chaining like GetSelectedWall):
--reassignment on reload just replaces our own stale closure.
--
--GetMapAuras runs the keyword-aura walk too, so a dispelling aura that just
--moved, appeared, or expired takes effect in the very aura rebuild that is
--re-polling this hook.
pcall(function()
    dmhub.GetMapAuras = function()
        EnsureZoneCache()
        EnsureKeywordAuraZones(true)
        local base = m_zoneAuraInstances
        if m_dispelState.auraInstances ~= nil then
            base = m_dispelState.auraInstances
        end

        --Objectless keyword ability auras ride along as rules-only clones
        --(see EnsureKeywordAuraZones). Appended into a fresh list: the base
        --lists must not be mutated -- m_dispelState keeps index-aligned
        --source tables for both of them.
        local extra = m_keywordAuraOverlay.instances
        if extra == nil or #extra == 0 then
            return base
        end
        local combined = {}
        for _,inst in ipairs(base) do
            combined[#combined+1] = inst
        end
        for _,inst in ipairs(extra) do
            combined[#combined+1] = inst
        end
        return combined
    end
end)

pcall(function()
    dmhub.GetMarkupZones = function()
        EnsureZoneCache()
        local panelOpen = MarkupPanelIsOpen()
        local mode = m_markupModeRef()

        --The Footsteps tab swaps the overlay wholesale: the normal zone
        --striping (rules zones here, built-in terrain-rule stripes engine
        --side, both regardless of the tileheight:overlay preference) hides,
        --and the footstep-surface regions render in that same stripe style
        --instead - marked apart by the footprints icon on their labels.
        --WATER stays visible on both layers (water rules zones ride along in
        --the footsteps list; the engine keeps the built-in water striping):
        --water plays water sounds over any painted footstep surface.
        local footstepsMode = panelOpen and mode == "surfaces"

        --a mode flip changes the zones list without any record changing, so
        --bump the revision to invalidate the overlay mesh - this is what
        --makes the swap take effect on engine builds old and new alike.
        if footstepsMode ~= m_dispelState.feedFootstepsMode then
            m_dispelState.feedFootstepsMode = footstepsMode
            m_zoneRevision = m_zoneRevision + 1
        end

        --same reasoning for panelOpen: with the tileheight:overlay preference
        --off, this flag alone decides whether the zone layer draws at all, and
        --no record has changed when it flips (opening/closing the panel, or a
        --Lua reload re-deriving it). Bump the revision so the overlay mesh is
        --rebuilt rather than serving a cached empty layer.
        if panelOpen ~= m_dispelState.feedPanelOpen then
            m_dispelState.feedPanelOpen = panelOpen
            m_zoneRevision = m_zoneRevision + 1
        end

        local zones = m_zoneOverlayZones
        if footstepsMode then
            zones = m_footstepsOverlayZones
        else
            --Keyword auras ride on the normal zone layer. The Footsteps tab
            --swaps that layer wholesale for surface regions, so they sit that
            --one out. Called unconditionally otherwise, because it owns the
            --revision bumps that tell the engine to re-mesh when an aura
            --appears or expires -- including the dispel suppression, which is
            --why it must run BEFORE the overlay list is chosen: zones being
            --dispelled render with the suppressed tiles removed, matching
            --the reduced aura registered for them.
            local auraZones = EnsureKeywordAuraZones(false)
            if m_dispelState.overlayZones ~= nil then
                zones = m_dispelState.overlayZones
            end
            if #auraZones > 0 then
                local combined = {}
                for _,zone in ipairs(zones) do
                    combined[#combined+1] = zone
                end
                for _,zone in ipairs(auraZones) do
                    combined[#combined+1] = zone
                end
                zones = combined
            end
        end

        --Per-zone-type visibility: the map overlay menu (title bar terrain
        --chip) hides zone types via the mapoverlay:hiddenzones preference
        --(';'-joined keyword ids). The ZONES tab overrides the filter - you
        --are editing the zones, so you see all of them. A filter change is
        --invisible to the engine's other cache signals, so bump the revision
        --when the effective filter flips (including the zones-tab override
        --kicking in and out).
        local hiddenStr = ""
        if not (panelOpen and mode == "zones") then
            hiddenStr = tostring(dmhub.GetSettingValue("mapoverlay:hiddenzones") or "")
        end
        if hiddenStr ~= m_dispelState.feedZoneFilter then
            m_dispelState.feedZoneFilter = hiddenStr
            m_zoneRevision = m_zoneRevision + 1
        end
        if hiddenStr ~= "" then
            local hidden = {}
            for id in string.gmatch(hiddenStr, "[^;]+") do
                hidden[id] = true
            end
            local filtered = {}
            for _,zone in ipairs(zones) do
                if zone.keywordid == nil or hidden[zone.keywordid] == nil then
                    filtered[#filtered+1] = zone
                end
            end
            zones = filtered
        end

        --Per-zone-type fade: the opacity slider on each group in the Zones
        --list, applied to the colours here rather than to any record (see the
        --m_zoneStripes.opacity block). Gated on the panel being open, so a
        --slider left part-way down has no effect once the panel closes. A
        --fade change is invisible to the engine's other cache signals, so the
        --published seq drives a revision bump the same way the zone-type
        --filter above does - including the whole feature switching off when
        --the last slider returns to 100%.
        local fadeSeq = 0
        if panelOpen and m_zoneStripes.AnyFade() then
            fadeSeq = m_zoneStripes.opacitySeq
        end
        if fadeSeq ~= m_zoneStripes.opacityFeedSeq then
            m_zoneStripes.opacityFeedSeq = fadeSeq
            m_zoneRevision = m_zoneRevision + 1
        end
        if fadeSeq ~= 0 then
            local faded = {}
            for _,zone in ipairs(zones) do
                --keyword-aura zones (a monster's Darkness) carry no zonegroup
                --but do carry a keyword, and fade with their painted kin.
                local opacity = m_zoneStripes.Opacity(zone.zonegroup or zone.keywordid)
                if opacity >= 1 then
                    faded[#faded+1] = zone
                else
                    --the cached entry is shared with the aura/dispel lists and
                    --must not be recoloured in place; the copy is shallow, so
                    --the loc list is shared rather than rebuilt per poll.
                    local copy = {}
                    for k,v in pairs(zone) do
                        copy[k] = v
                    end
                    copy.color = m_zoneStripes.FadeColor(zone.color, opacity)
                    faded[#faded+1] = copy
                end
            end
            zones = faded
        end

        --Markup holes stripe like zones while the panel is open (the actual
        --cut renders too; the stripe overlay draws into the CURRENT floor's
        --composite, above the punched art layer, so the stripes hover over
        --the empty space), and outside the panel when opted in via the map
        --overlay menu's Hole row -- stored as the reserved id "hole" in
        --mapoverlay:shownbuiltins (opt-IN like the built-ins: the default
        --with the panel closed stays "the map just has a hole in it"). The
        --engine ignores unknown ids in that setting. Holes carry no
        --keywordid/zonegroup, so the hidden-zones filter and the fade pass
        --above both leave them alone -- right, they are not zone types;
        --appended after both passes.
        local holesShown = panelOpen
        if not holesShown and #m_holes.overlayZones > 0 then
            local shownStr = tostring(dmhub.GetSettingValue("mapoverlay:shownbuiltins") or "")
            for id in string.gmatch(shownStr, "[^;]+") do
                if id == "hole" then
                    holesShown = true
                    break
                end
            end
        end
        --a pref flip changes the list with no record write; bump the revision
        --so the overlay mesh rebuilds (panelOpen flips already bump above,
        --the redundant second bump is harmless).
        if holesShown ~= m_dispelState.feedHolesShown then
            m_dispelState.feedHolesShown = holesShown
            m_zoneRevision = m_zoneRevision + 1
        end
        if holesShown and #m_holes.overlayZones > 0 then
            local combined = {}
            for _,zone in ipairs(zones) do
                combined[#combined+1] = zone
            end
            for _,zone in ipairs(m_holes.overlayZones) do
                combined[#combined+1] = zone
            end
            zones = combined
        end

        --"Entire Map" types draw nothing (that is the point - a blanket is
        --implied), but their auras still contribute terrain rules to every
        --tile, and the engine's BUILT-IN rule stripes/labels are driven off
        --GetTileRulesAtLoc. Without telling the overlay which flags the whole
        --floor now carries, turning a blanket on floods the map with built-in
        --stripes -- which looks exactly like the blanket drawing itself.
        --Flags only, no tiles: a per-tile suppression set would marshal the
        --whole map across the bridge on every poll of this feed.
        local blankets = {}
        for _,entry in ipairs(m_entireMap.entries) do
            blankets[#blankets+1] = {
                floorIndex = entry.floorIndex,
                difficultTerrain = entry.flags.difficultTerrain,
                water = entry.flags.water,
                concealment = entry.flags.concealment,
                climbable = entry.flags.climbable,
            }
        end

        return {
            panelOpen = panelOpen,
            blankets = blankets,
            --The Zones tab also lights up the overlay's built-in terrain-rule
            --striping (water/difficult/concealment/climbable), so the user
            --sees existing terrain conditions alongside the zones they are
            --painting - without needing the Show Terrain Features preference.
            terrainZones = panelOpen and mode == "zones",
            footstepsMode = footstepsMode,
            --The Walls tab force-renders solid-block interiors; any open tab
            --forces the wall cover lines. The Elevation tab force-renders the
            --height contours + number labels. Each rides on its mapoverlay:*
            --preference otherwise (see TileHeightOverlay.Update).
            wallsMode = panelOpen and mode == "walls",
            elevationMode = panelOpen and mode == "elevation",
            revision = m_zoneRevision,
            zones = zones,
        }
    end
end)

--Public API for the title bar's map overlay menu (CodexTitleBar): the zone
--types present on the current map, one entry per environmental keyword, as
--{ keywordid, name, color ("#rrggbb"), angleRadians, playerVisible }.
--playerVisible is true when at least one zone of the type is player-visible
--(keyword-aura zones - a monster's Darkness - are always on screen for
--everyone and count as player-visible). Non-DM clients only receive the
--player-visible types, so the menu cannot leak hidden zone types.
--Lives on a global table so the title bar can reach it with rawget: the
--module may be absent (lobby game) or not yet loaded.
if rawget(_G, "MapMarkup") == nil then
    MapMarkup = {}
end

function MapMarkup.GetZoneTypesOnMap()
    if not ZonesSupported() then
        return {}
    end
    EnsureZoneCache()
    pcall(function()
        EnsureKeywordAuraZones(false)
    end)

    local seen = {}
    local result = {}
    local function Add(keywordid, name, color, playerVisible)
        if keywordid == nil then
            return
        end
        --normalize colors to "#rrggbb": overlay feed colors carry the "bf"
        --stripe alpha, keyword colors can be 9-char too.
        if type(color) == "string" and string.len(color) == 9 then
            color = string.sub(color, 1, 7)
        end
        local entry = seen[keywordid]
        if entry == nil then
            entry = {
                keywordid = keywordid,
                name = name or "Zone",
                color = color,
                angleRadians = m_zoneStripes.AngleForKeyword(keywordid),
                playerVisible = playerVisible == true,
            }
            seen[keywordid] = entry
            result[#result+1] = entry
        elseif playerVisible == true then
            entry.playerVisible = true
        end
    end

    for _,entry in ipairs(m_zoneCache) do
        if entry.floorIndex ~= nil and entry.floorIndex >= 0 then
            Add(entry.keywordid, entry.keywordName or entry.name, entry.patternColor, entry.playerVisible)
        end
    end
    --"Entire Map" blankets: the type is in force even though nothing is drawn
    --for it. Never player-visible.
    for _,entry in ipairs(m_entireMap.entries) do
        Add(entry.keywordid, entry.keywordName or entry.name, entry.patternColor, false)
    end
    --keyword-carrying auras (abilities, monster traits): on screen for
    --everyone already.
    for _,zone in ipairs(m_keywordAuraOverlay.zones or {}) do
        Add(zone.keywordid, zone.label, zone.color, true)
    end

    if not dmhub.isDM then
        local filtered = {}
        for _,entry in ipairs(result) do
            if entry.playerVisible then
                filtered[#filtered+1] = entry
            end
        end
        result = filtered
    end

    table.sort(result, function(a, b)
        return string.lower(a.name or "") < string.lower(b.name or "")
    end)
    return result
end

--Markup holes present on the current map, for the title bar's map overlay
--menu: {color, angleRadians}, or nil when the map has none. The menu shows an
--opt-IN row for it (reserved id "hole" in mapoverlay:shownbuiltins) -- with
--the Map Markup panel closed the default is just the actual cut, no stripes.
--DM-only: hole stripes are never player-visible, so players get no row.
function MapMarkup.GetHoleTypeOnMap()
    if not dmhub.isDM then
        return nil
    end
    if not ZonesSupported() then
        return nil
    end
    EnsureZoneCache()
    for _,entry in ipairs(m_holes.cache) do
        if entry.floorIndex ~= nil and entry.floorIndex >= 0 then
            return {
                color = m_holes.color,
                angleRadians = ZONE_ANGLE_A,
            }
        end
    end
    return nil
end

--Keyword edits (refreshTables) change what zone auras contribute: invalidate
--the cache, and if this map actually has zones, rebuild the aura index so
--the changes reach creatures without waiting for an unrelated rebuild.
dmhub.RegisterEventHandler("refreshTables", function()
    m_zoneTablesGen = m_zoneTablesGen + 1
    if not ZonesSupported() then
        return
    end
    EnsureZoneCache()
    if (m_zoneCache ~= nil and #m_zoneCache > 0) or #m_entireMap.entries > 0 then
        pcall(function()
            dmhub.RefreshMapAuras()
        end)
    end
end)

--============================================================================
--Dynamic-light sampling. A slow poll (below) asks the engine which candidate
--tiles are currently dark; when the answer changes (a torch moved, a door
--closed, night fell), the sampling serial bumps -- which invalidates the zone
--cache -- and the aura index is asked to re-poll dmhub.GetMapAuras. The
--engine hashes the dark set and returns nil while it matches knownState, so
--an unchanged poll marshals nothing and rebuilds nothing.
--============================================================================

--One engine call per (floor, distinct threshold): candidates are the whole
--map extent when any keyword at that threshold blankets the map, else the
--union of that threshold's painted zone tiles on the floor (built in stable
--cache order -- the candidate order is part of the engine's state hash).
function m_dynamicLight.Sample()
    if not m_dynamicLight.Supported() or not ZonesSupported() then
        return
    end

    local thresholds = m_dynamicLight.Thresholds()
    if next(thresholds) == nil then
        if next(m_dynamicLight.states) ~= nil then
            m_dynamicLight.states = {}
            m_dynamicLight.serial = m_dynamicLight.serial + 1
            --without this the carve lingers until some unrelated aura
            --rebuild happens to re-poll the zone cache.
            pcall(function()
                dmhub.RefreshMapAuras()
            end)
        end
        return
    end

    local map = game.currentMap
    if map == nil then
        return
    end

    EnsureZoneCache()

    local floors = {}
    for _,floor in ipairs(map.floors or {}) do
        pcall(function()
            local floorIndex = floor.floorIndex
            if floorIndex ~= nil and floorIndex >= 0 then
                floors[#floors+1] = { floorid = floor.floorid, floorIndex = floorIndex }
            end
        end)
    end

    local dims = nil
    pcall(function()
        dims = map.dimensions
    end)

    local blankets = m_entireMap.Keywords()

    --pct -> { kwids = set, blanket = bool }
    local groups = {}
    for kwid,pct in pairs(thresholds) do
        local group = groups[pct]
        if group == nil then
            group = { kwids = {}, blanket = false }
            groups[pct] = group
        end
        group.kwids[kwid] = true
        if blankets[kwid] == true then
            group.blanket = true
        end
    end

    local live = {}
    local changed = false

    for pct,group in pairs(groups) do
        for _,floorInfo in ipairs(floors) do
            local args = {
                floorIndex = floorInfo.floorIndex,
                threshold = pct / 100,
            }

            local haveCandidates = false
            if group.blanket and dims ~= nil then
                args.x1 = math.floor(dims.x)
                args.y1 = math.floor(dims.y)
                args.x2 = math.floor(dims.z) - 1
                args.y2 = math.floor(dims.w) - 1
                haveCandidates = args.x2 >= args.x1 and args.y2 >= args.y1
            else
                local locs = {}
                for _,entry in ipairs(m_zoneCache) do
                    if entry.floorid == floorInfo.floorid and entry.keywordid ~= nil
                        and group.kwids[entry.keywordid] == true then
                        for _,l in ipairs(entry.locs) do
                            locs[#locs+1] = l.x
                            locs[#locs+1] = l.y
                        end
                    end
                end
                if #locs > 0 then
                    args.locs = locs
                    haveCandidates = true
                end
            end

            if haveCandidates then
                local key = m_dynamicLight.StateKey(floorInfo.floorid, pct)
                live[key] = true

                local prev = m_dynamicLight.states[key]
                if prev ~= nil then
                    args.knownState = prev.state
                end

                local ok, result = pcall(function()
                    return dmhub.GetDarkTiles(args)
                end)
                if ok and result ~= nil then
                    local dark = {}
                    local resultLocs = result.locs or {}
                    for i = 1, #resultLocs - 1, 2 do
                        dark[ZoneLocKey(resultLocs[i], resultLocs[i+1])] = true
                    end

                    --locs mode also records WHICH tiles were sampled, so
                    --ApplyFilter can tell "sampled and lit" (drop) from
                    --"never sampled" (keep until the next sample). Rect mode
                    --covers the whole map, so nothing is ever unknown there.
                    local sampled = nil
                    if args.locs ~= nil then
                        sampled = {}
                        for i = 1, #args.locs - 1, 2 do
                            sampled[ZoneLocKey(args.locs[i], args.locs[i+1])] = true
                        end
                    end

                    m_dynamicLight.states[key] = { state = result.state, dark = dark, sampled = sampled }
                    changed = true
                end
            end
        end
    end

    --configuration/zones that stopped being sampled must not keep carving.
    for key,_ in pairs(m_dynamicLight.states) do
        if live[key] ~= true then
            m_dynamicLight.states[key] = nil
            changed = true
        end
    end

    if changed then
        m_dynamicLight.serial = m_dynamicLight.serial + 1
        pcall(function()
            dmhub.RefreshMapAuras()
        end)
    end
end

--reschedule-first so a Sample error can't kill the loop; cheap when the
--feature is unconfigured (one setting read).
function m_dynamicLight.Tick()
    if mod.unloaded then
        return
    end
    dmhub.Schedule(0.7, m_dynamicLight.Tick)
    pcall(m_dynamicLight.Sample)
end

dmhub.Schedule(0.7, m_dynamicLight.Tick)

--============================================================================
--Zone editing operations (paint / erase / create / update / delete).
--ZoneLocKey lives up with the keyword helpers: the ZoneManager uses it too.
--============================================================================

--Rasterizes a closed stroke polygon (interleaved x,y world coords) to the
--tiles whose CENTERS it contains. Tile (x,y)'s center is world (x,y) on
--square grids (Loc-centered convention; snap = Round). If the polygon is so
--small it contains no center, falls back to the tile under its centroid so
--a click-sized stroke still paints one tile.
local function PolygonToLocs(points)
    local n = #points
    if n < 6 then
        return {}
    end

    local minX, minY = points[1], points[2]
    local maxX, maxY = points[1], points[2]
    local cxSum, cySum, npts = 0, 0, 0
    for i = 1, n - 1, 2 do
        local px, py = points[i], points[i+1]
        if px < minX then minX = px end
        if px > maxX then maxX = px end
        if py < minY then minY = py end
        if py > maxY then maxY = py end
        cxSum = cxSum + px
        cySum = cySum + py
        npts = npts + 1
    end

    local function PointInPolygon(px, py)
        local inside = false
        local j = n - 1
        for i = 1, n - 1, 2 do
            local ax, ay = points[i], points[i+1]
            local bx, by = points[j], points[j+1]
            if (ay > py) ~= (by > py) then
                local t = (py - ay) / (by - ay)
                if px < ax + t * (bx - ax) then
                    inside = not inside
                end
            end
            j = i
        end
        return inside
    end

    local result = {}
    for ty = math.floor(minY + 0.5), math.floor(maxY + 0.5) do
        for tx = math.floor(minX + 0.5), math.floor(maxX + 0.5) do
            if PointInPolygon(tx, ty) then
                result[#result+1] = { x = tx, y = ty }
            end
        end
    end

    if #result == 0 and npts > 0 then
        result[#result+1] = {
            x = math.floor(cxSum / npts + 0.5),
            y = math.floor(cySum / npts + 0.5),
        }
    end

    return result
end

--Even-odd point-in-ring test against a flat {x1,y1,x2,y2,...} ring, matching
--PolygonToLocs' fill rule.
function m_holes.PointInRing(ring, px, py)
    local n = #ring
    local inside = false
    local j = n - 1
    for i = 1, n - 1, 2 do
        local ax, ay = ring[i], ring[i+1]
        local bx, by = ring[j], ring[j+1]
        if (ay > py) ~= (by > py) then
            local t = (py - ay) / (by - ay)
            if px < ax + t * (bx - ax) then
                inside = not inside
            end
        end
        j = i
    end
    return inside
end

--Tiles covered by a hole's structured polygon list: each outer ring
--rasterizes like a paint stroke, minus tiles whose center falls in one of
--its clipped-out hole rings. Merged and deduplicated across entries.
function m_holes.EntryLocs(polygons)
    local seen = {}
    local result = {}
    for _,entry in ipairs(polygons or {}) do
        for _,l in ipairs(PolygonToLocs(entry.points or {})) do
            local inHole = false
            for _,holeRing in ipairs(entry.holes or {}) do
                if m_holes.PointInRing(holeRing, l.x, l.y) then
                    inHole = true
                    break
                end
            end
            if not inHole then
                local key = ZoneLocKey(l.x, l.y)
                if not seen[key] then
                    seen[key] = true
                    result[#result+1] = { x = l.x, y = l.y }
                end
            end
        end
    end
    return result
end

--A fresh storable record built from a cache entry with replacement fields.
--Always build fresh tables for writes: the engine's markupZones getter hands
--back the stored table itself, and mutating it in place corrupts undo.
local function BuildZoneRecord(entry, overrides)
    overrides = overrides or {}
    local locs = {}
    for _,l in ipairs(overrides.locs or entry.locs) do
        locs[#locs+1] = { x = l.x, y = l.y }
    end

    local record = {
        name = overrides.name or entry.name,
        --entry.keywordid is the RESOLVED id (possibly healed by name), so
        --rewriting the record here also repairs a dead stored id.
        keyword = entry.keywordid,
        keywordName = entry.keywordName,
        locs = locs,
        altitude = entry.altitude or 0,
        playerVisible = entry.playerVisible == true,
        pattern = {
            color = entry.patternColor,
            angle = entry.patternAngle,
        },
        ord = entry.ord or 0,
    }

    --height: nil means unlimited and stays absent from the record.
    if overrides.clearHeight then
        record.height = nil
    elseif overrides.height ~= nil then
        record.height = overrides.height
    else
        record.height = entry.height
    end

    --visuals: the shown state is the default and stays absent from the record.
    if entry.hideAppearance == true then
        record.hideAppearance = true
    end
    if overrides.hideAppearance ~= nil then
        record.hideAppearance = (overrides.hideAppearance == true) or nil
    end

    if overrides.name ~= nil then record.name = overrides.name end
    if overrides.playerVisible ~= nil then record.playerVisible = overrides.playerVisible end

    return record
end

--Zone entries on the given floor, in list order.
local function ZonesOnFloor(floorid)
    EnsureZoneCache()
    local result = {}
    for _,entry in ipairs(m_zoneCache or {}) do
        if entry.floorid == floorid then
            result[#result+1] = entry
        end
    end
    return result
end

local function FindZoneEntry(zoneid)
    EnsureZoneCache()
    for _,entry in ipairs(m_zoneCache or {}) do
        if entry.zoneid == zoneid then
            return entry
        end
    end
    return nil
end

--A unique display name for a new zone of the given keyword on a floor:
--"Lava", then "Lava 2", "Lava 3", ...
local function UniqueZoneName(floorid, baseName)
    local taken = {}
    for _,entry in ipairs(ZonesOnFloor(floorid)) do
        taken[entry.name] = true
    end

    if not taken[baseName] then
        return baseName
    end

    local i = 2
    while taken[string.format("%s %d", baseName, i)] do
        i = i + 1
    end
    return string.format("%s %d", baseName, i)
end

--Creates a new zone record of the given keyword on the current floor and
--returns its id. locs may be empty (a fresh separate zone to paint into).
--fallbackInfo ({name, color}, optional) covers the keyword-upload race: the
--keyword may not be locally visible yet, but the caller knows what it is.
local function CreateZone(keywordid, locs, fallbackInfo)
    local floor = game.currentFloor
    if floor == nil then
        return nil
    end

    local kw = GetKeyword(keywordid)
    local kwName = nil
    if kw ~= nil and kw.name ~= nil then
        kwName = kw.name
    elseif fallbackInfo ~= nil then
        kwName = fallbackInfo.name
    end
    kwName = kwName or "Zone"

    local floorZones = ZonesOnFloor(floor.floorid)
    local maxOrd = 0
    for _,entry in ipairs(floorZones) do
        if (entry.ord or 0) > maxOrd then
            maxOrd = entry.ord
        end
    end

    --stripe angle is a function of the keyword, so every zone of a keyword on
    --this map stripes the same way. (The overlay feed re-derives it anyway;
    --this is only what gets stored on the record.)
    local angle = m_zoneStripes.AngleForKeyword(keywordid)

    local color = KeywordColor(keywordid, kw)
    if kw == nil and fallbackInfo ~= nil and fallbackInfo.color ~= nil then
        color = fallbackInfo.color
    end

    local zoneid = dmhub.GenerateGuid()
    local record = {
        name = UniqueZoneName(floor.floorid, kwName),
        keyword = keywordid,
        keywordName = kwName,
        locs = locs or {},
        altitude = 0,
        --new zones are player-visible: a painted zone is nearly always terrain
        --the table is meant to see (and players still have to turn the tile
        --overlay on). Secret zones are turned off in the Edit Zone dialog.
        playerVisible = true,
        pattern = {
            color = color,
            angle = angle,
        },
        ord = maxOrd + 1,
    }

    --The zone TYPE's default height is stamped on at paint time; the zone owns
    --it from here on (Edit Zone dialog), so re-defaulting the type later leaves
    --zones already painted alone. nil = unlimited and stays off the record.
    record.height = m_zoneHeight.Get(kw)

    --Same deal for the type's "draw with visuals" toggle (the Visuals pill on
    --the palette chip): pill off = the new zone starts with its visual
    --representation hidden. The zone owns the flag from here on (the Visuals
    --badge on its list row), so flipping the pill later leaves painted zones
    --alone. Shown is the default and stays off the record.
    pcall(function()
        if kw ~= nil and kw:try_get("appearanceDefaultOff", false) == true then
            record.hideAppearance = true
        end
    end)

    floor:SetMarkupZone(zoneid, record)
    return zoneid
end

--Splits a loc set into 4-connected contiguous components, largest first.
--Contiguity matches the overlay's per-block labelling, so one component =
--one labelled region on the map.
local function SplitContiguousComponents(locs)
    local remaining = {}
    local orderedKeys = {}
    for _,l in ipairs(locs) do
        local key = ZoneLocKey(l.x, l.y)
        if remaining[key] == nil then
            remaining[key] = { x = l.x, y = l.y }
            orderedKeys[#orderedKeys+1] = key
        end
    end

    local components = {}
    for _,startKey in ipairs(orderedKeys) do
        if remaining[startKey] ~= nil then
            local component = {}
            local queue = { remaining[startKey] }
            remaining[startKey] = nil

            while #queue > 0 do
                local cell = table.remove(queue)
                component[#component+1] = cell

                local neighborKeys = {
                    ZoneLocKey(cell.x + 1, cell.y),
                    ZoneLocKey(cell.x - 1, cell.y),
                    ZoneLocKey(cell.x, cell.y + 1),
                    ZoneLocKey(cell.x, cell.y - 1),
                }
                for _,nkey in ipairs(neighborKeys) do
                    local ncell = remaining[nkey]
                    if ncell ~= nil then
                        remaining[nkey] = nil
                        queue[#queue+1] = ncell
                    end
                end
            end

            components[#components+1] = component
        end
    end

    table.sort(components, function(a, b) return #a > #b end)
    return components
end

--Writes a zone's new loc set, automatically separating non-contiguous
--regions into their own zone records: the largest region keeps the zone's
--identity (id, name, settings), each additional region becomes a new zone
--of the same type and settings named "<Base> 2", "<Base> 3", ... An empty
--set deletes the zone. Callers wrap multi-zone operations in a transaction.
local function WriteZoneLocsSplitting(floor, entry, newLocs)
    local components = SplitContiguousComponents(newLocs)
    if #components == 0 then
        --NOTE: a stale m_zoneTargetId pointing at the removed zone is
        --harmless - target lookups search the cache by id and just miss.
        floor:RemoveMarkupZone(entry.zoneid)
        return
    end

    floor:SetMarkupZone(entry.zoneid, BuildZoneRecord(entry, { locs = components[1] }))

    if #components > 1 then
        --split-off names derive from the zone's own name with any trailing
        --number stripped, so "Lava 2" splits into "Lava 3", not "Lava 2 2".
        local baseName = string.gsub(entry.name, "%s+%d+$", "")
        if baseName == "" then
            baseName = entry.name
        end

        for i = 2, #components do
            local record = BuildZoneRecord(entry, { locs = components[i] })
            --UniqueZoneName consults the freshly-written records (local
            --writes apply synchronously), so each split gets a fresh name.
            record.name = UniqueZoneName(floor.floorid, baseName)
            floor:SetMarkupZone(dmhub.GenerateGuid(), record)
        end
    end
end

--Splits any multi-region zone records on the current floor into one record
--per contiguous region. Auto-splitting normally happens as strokes are
--written, but records created before that existed (or written by an older
--client) can still hold disjoint regions - the zones list runs this before
--refreshing so such zones separate as soon as the DM looks at them. One
--undo step for the whole pass; a no-op when everything is already split.
local function NormalizeZonesOnFloor(floorid)
    if not ZonesSupported() then
        return
    end

    local floor = game.currentFloor
    if floor == nil or floor.floorid ~= floorid then
        return
    end

    local needSplit = {}
    for _,entry in ipairs(ZonesOnFloor(floorid)) do
        if #entry.locs > 0 and #SplitContiguousComponents(entry.locs) > 1 then
            needSplit[#needSplit+1] = entry
        end
    end

    if #needSplit == 0 then
        return
    end

    dmhub.BeginTransaction()
    for _,entry in ipairs(needSplit) do
        WriteZoneLocsSplitting(floor, entry, entry.locs)
    end
    dmhub.EndTransaction()
end

--============================================================================
--Footstep-surface editing operations (paint / erase). Surfaces are exclusive
--per tile: painting one family removes those tiles from every other family.
--No naming or contiguity machinery - one record per family per floor.
--============================================================================

local function SurfacesOnFloor(floorid)
    EnsureZoneCache()
    local result = {}
    for _,entry in ipairs(m_surfaceCache or {}) do
        if entry.floorid == floorid then
            result[#result+1] = entry
        end
    end
    return result
end

--Writes a surface family's loc set on a floor, removing the record when the
--set goes empty. Record ids are deterministic per family ("surface-6"), so
--painting the same family always merges into its one record.
local function WriteSurfaceLocs(floor, surfaceId, locs)
    local recordId = string.format("surface-%d", surfaceId)
    if locs == nil or #locs == 0 then
        floor:RemoveMarkupZone(recordId)
        return
    end

    local surfaceInfo = SurfaceInfoById(surfaceId)
    local cleanLocs = {}
    for _,l in ipairs(locs) do
        cleanLocs[#cleanLocs+1] = { x = l.x, y = l.y }
    end

    floor:SetMarkupZone(recordId, {
        category = "surface",
        surface = surfaceId,
        surfaceName = (surfaceInfo ~= nil and surfaceInfo.text) or "Surface",
        locs = cleanLocs,
    })
end

--============================================================================
--Public footstep lookup for the audio layer (AudioMain.TokenMovingOnPath and
--creature.PlayLandingFootstep). The map default footstep surface overrides
--tile-DERIVED surfaces (imported map backgrounds often carry a surfaceType of
--their own), but painted footstep regions must keep theirs - and at playback
--both are just ints. This lookup is how the audio code tells them apart.
--Rebuilt lazily from the surface cache whenever the records change.
--============================================================================

local m_paintedSurfaceLookup = nil    --floorid -> { "x,y" -> surface id }
local m_paintedSurfaceLookupRev = nil

MapMarkupFootsteps = {
    --Returns the painted footstep-surface family id at a tile, or nil when no
    --footstep region is painted there.
    GetPaintedSurfaceAt = function(floorid, x, y)
        if floorid == nil or x == nil or y == nil or not ZonesSupported() then
            return nil
        end
        EnsureZoneCache()

        if m_paintedSurfaceLookup == nil or m_paintedSurfaceLookupRev ~= m_zoneRevision then
            m_paintedSurfaceLookupRev = m_zoneRevision
            m_paintedSurfaceLookup = {}
            for _,entry in ipairs(m_surfaceCache or {}) do
                local floorMap = m_paintedSurfaceLookup[entry.floorid]
                if floorMap == nil then
                    floorMap = {}
                    m_paintedSurfaceLookup[entry.floorid] = floorMap
                end
                for _,l in ipairs(entry.locs) do
                    floorMap[ZoneLocKey(l.x, l.y)] = entry.surface
                end
            end
        end

        local floorMap = m_paintedSurfaceLookup[floorid]
        if floorMap == nil then
            return nil
        end
        return floorMap[ZoneLocKey(x, y)]
    end,
}

--============================================================================
--Zone flash: clicking a row in the zones list pans the camera to the zone
--and briefly pulses a highlight over its tiles so the user can spot it.
--============================================================================

local m_zoneFlashMarks = nil
local m_zoneFlashGen = 0

local function ClearZoneFlash()
    if m_zoneFlashMarks ~= nil then
        pcall(function()
            m_zoneFlashMarks:Destroy()
        end)
        m_zoneFlashMarks = nil
    end
end

local function JumpToZone(entry)
    if entry == nil or entry.locs == nil or #entry.locs == 0 then
        return
    end

    --camera target: the zone tile nearest the centroid, so an L-shaped or
    --sprawling region centers on actual zone tiles rather than a gap.
    local cx, cy = 0, 0
    for _,l in ipairs(entry.locs) do
        cx = cx + l.x
        cy = cy + l.y
    end
    cx = cx / #entry.locs
    cy = cy / #entry.locs

    local best = entry.locs[1]
    local bestD = nil
    for _,l in ipairs(entry.locs) do
        local d = (l.x - cx) * (l.x - cx) + (l.y - cy) * (l.y - cy)
        if bestD == nil or d < bestD then
            bestD = d
            best = l
        end
    end

    dmhub.CenterOnLoc{
        x = best.x,
        y = best.y,
        floorid = entry.floorid,
        smooth = true,
    }

    --pulse the zone's area: on / off / on, then clear. A newer flash (or a
    --reload) cancels the remainder of an older one via the generation guard.
    ClearZoneFlash()
    m_zoneFlashGen = m_zoneFlashGen + 1
    local gen = m_zoneFlashGen

    local locsUserdata = entry.locsUserdata
    if locsUserdata == nil then
        return
    end

    local okShape, shape = pcall(function()
        return dmhub.CalculateShape{
            shape = "locations",
            locations = locsUserdata,
            locOverride = locsUserdata[1],
            range = 0,
            radius = 0,
            checklos = false,
        }
    end)
    if not okShape or shape == nil then
        return
    end

    local PULSE_STEPS = { 0.4, 0.15, 0.4 } --on, off, on (seconds)

    local ShowPulse
    ShowPulse = function(step)
        if (mod ~= nil and mod.unloaded) or gen ~= m_zoneFlashGen then
            return
        end
        if step > #PULSE_STEPS then
            ClearZoneFlash()
            return
        end

        if step % 2 == 1 then
            local ok, marks = pcall(function()
                return shape:Mark{
                    color = entry.patternColor,
                    video = "divinationline.webm",
                }
            end)
            if ok then
                m_zoneFlashMarks = marks
            end
        else
            ClearZoneFlash()
        end

        dmhub.Schedule(PULSE_STEPS[step], function()
            ShowPulse(step + 1)
        end)
    end
    ShowPulse(1)
end

--============================================================================
--Panel state + the engine-polled selection hook.
--============================================================================

local m_markupHud = nil
m_markupHudRef = function() return m_markupHud end
local m_mode = "walls"
m_markupModeRef = function() return m_mode end
local m_selectedIndex = 1
local m_paletteEntries = {}
--"rectangle" / "line" / "free" draw walls through the engine building tools,
--and "points" drives the engine's wall vertex-editing tool the same way;
--"erase" / "delete" and the solid shape tools are custom map tools driven
--from this panel. Reset to each mode's first tool when the panel is built.
local m_toolId = "rectangle"

--============================================================================
--ARMED: whether this panel's tool is live, i.e. whether clicks on the map do
--markup. EXPLICIT, and deliberately NOT derived from GUI focus any more.
--
--Focus used to BE the armed state, and it disarmed for reasons the user never
--performed: focus parked on a chip died when a stroke rebuilt the chip list
--(one stroke landed, every later one silently did nothing), and the Building
--editor's palette stole focus a frame after a tool press (wall drawing simply
--stopped, and the only way back was clicking a wall type). Both needed
--defensive workarounds -- see TakeMarkupFocus's comment and the late
--ReassertMarkupFocus -- and neither made the state predictable.
--
--Now arming is a verb: pressing a tool arms it, pressing the armed tool again
--disarms, Escape disarms, closing the panel disarms, and NOTHING else does.
--Focus is still taken so the panel keeps its keyboard routing, but losing it
--no longer means anything, which is what makes the state worth showing.
--ONE table, not a flag plus two functions: this file's main chunk is at Lua's
--200-local ceiling, so three new locals will not compile. Everything arming
--needs hangs off m_arm.
local m_arm = {}
m_arm.on = false

--The one predicate every drawing path gates on. Also requires the hud to
--exist: an armed flag with no panel behind it must not publish tools.
function m_arm.Armed()
    return m_arm.on and m_markupHud ~= nil and m_markupHud.valid
end

--Arm or disarm, and tell the panel. The `markuparmed` event already drives
--the armed dot on the mode tab; firing `think` re-runs the tool registration
--paths, which are gated on m_arm.Armed() and so register or unregister the
--engine's custom map tools as the state flips.
function m_arm.Set(on)
    on = on == true
    if m_arm.on == on then
        return
    end
    m_arm.on = on
    if m_markupHud ~= nil and m_markupHud.valid then
        m_markupHud:FireEventTree("markuparmed", on)
        --the tool strip lights its tool only while live (see refreshtools),
        --so every arm change has to repaint it...
        m_markupHud:FireEventTree("refreshtools")
        --...and think re-runs the registration paths, which are gated on
        --m_arm.Armed() and so hand the engine's custom map tools out or take
        --them back as the state flips.
        m_markupHud:FireEventTree("think")
    end
end
--Draw mode, independent of which wall type is selected: false draws thin
--walls (barriers on a tile boundary), true draws area-filling solid blocks
--of the SAME wall type. Toggled by the Thin/Solid control by the tool strip.
local m_solidMode = false

--Zones mode state: the selected zone-type chip (index into
--m_zonePaletteEntries), the active zone tool, and the target zone new
--strokes merge into (nil = auto-pick / create by selected type).
local m_zonePaletteEntries = {}
local m_zoneSelectedType = 1
local m_zoneToolId = "zonerect"
local m_zoneTargetId = nil

--Footsteps mode state: the selected surface family (AudioSurfaceTypes id)
--and the active paint tool.
local m_footstepSelected = 1
local m_footstepToolId = "footrect"

--============================================================================
--Props mode: invisible gameplay objects placed on the map. The palette is
--DATA-DRIVEN: every object asset tagged with the "markup" keyword (the
--Keywords field in the object's properties in the Objects panel) is a prop
--type, shown under the asset's own name and art. Placing one spawns an
--instance of that asset, stamps "markup" onto the instance's Core keywords,
--and locks it so it is inert everywhere except this panel. The engine's
--object-editing filter (dmhub.GetObjectEditingFilter, needs an engine build)
--makes every markup prop visible and draggable while the Props tab is
--focused. The property editors are component-aware: an asset with a Light
--component gets the light editing UI (color/brightness/radius/flicker).
--============================================================================

--The tag that makes an object asset a prop type, and the Core keyword the
--engine filter + selection handler match on placed instances.
local MARKUP_PROP_KEYWORD = "markup"

--Object assets tagged "markup" form the props palette. GetObjectsWithKeyword
--matches the asset's keywords exactly (case-insensitive) but does NOT skip
--deleted (hidden) assets or folders, so filter those here. Sorted by name so
--the chip order is stable.
local function MarkupPropAssets()
    local result = {}
    for _,node in ipairs(assets:GetObjectsWithKeyword(MARKUP_PROP_KEYWORD)) do
        if (not node.isfolder) and (not node.hidden) then
            result[#result+1] = node
        end
    end
    table.sort(result, function(a, b)
        local an = string.lower(tostring(a.description or ""))
        local bn = string.lower(tostring(b.description or ""))
        if an == bn then
            return a.id < b.id
        end
        return an < bn
    end)
    return result
end

--Find a component on an object ASSET node by its display name ("Light",
--"Core", "Mount", ...) - node.components is keyed by component guid, and
--comp.name carries the component type's description.
local function NodeGetComponent(node, componentName)
    local comps = node.components
    if comps == nil then
        return nil
    end
    for _,comp in pairs(comps) do
        if comp.name == componentName then
            return comp
        end
    end
    return nil
end

--Read a component field's live value (component.fields carries the engine's
--reflected descriptors). Works on asset-node components and placed-instance
--components alike.
local function GetComponentFieldValue(comp, id)
    for _,f in ipairs(comp.fields) do
        if f.id == id then
            return f.currentValue
        end
    end
    return nil
end

--Props mode state: the selected prop type (assetid of a palette chip), the
--placed prop currently bound to the property editors (clicked on the map),
--and per-asset session defaults stamped onto newly placed props. Defaults
--are seeded lazily from the asset's own component values and then track the
--last values edited, so consecutive placements inherit them.
--
--Teleporter state: teleLink is the link name the NEXT pair will use
--(auto-generated unique when nil/blank; the user can edit it), teleStyle the
--style ("teleport"/"stairwell") stamped on new pairs and kept identical
--across both ends of a pair. pendingPartnerId/pendingLink/pendingFloorId
--track a placed first teleporter awaiting its partner: the next placement
--completes the pair, and ANY abort (Escape, chip/tab switch, focus loss,
--selecting something else) deletes the first one again.
local m_props = {
    selected = nil,
    editingId = nil,    --primary bound prop (single-value reads)
    editingIds = nil,   --the FULL bound selection; property edits hit all of them
    defaults = {},
    --text defaults live in their own table: Light and Text both have a
    --"color" field, so one shared per-asset table would cross-contaminate.
    textDefaults = {},

    teleLink = nil,
    teleStyle = "teleport",
    pendingPartnerId = nil,
    pendingLink = nil,
    pendingFloorId = nil,
}

--The engine pairs teleporters by trimmed, lowercased linkName
--(ObjectComponentTeleporter.FindPartner); mirror that when comparing.
local function LinkKey(name)
    return string.lower(trim(tostring(name or "")))
end

--Every markup teleporter prop on the current map (all floors): entries of
--{obj, comp, link, floorid}.
local function MarkupTeleportersOnMap()
    local result = {}
    local map = game.currentMap
    if map == nil then
        return result
    end
    for _,floor in ipairs(map.floors or {}) do
        for _,obj in pairs(floor.objects or {}) do
            local kw = obj.keywords
            if kw ~= nil and kw[MARKUP_PROP_KEYWORD] ~= nil then
                local comp = obj:GetComponent("Teleporter")
                if comp ~= nil then
                    result[#result+1] = {
                        obj = obj,
                        comp = comp,
                        link = tostring(GetComponentFieldValue(comp, "linkName") or ""),
                        floorid = obj.floorid,
                    }
                end
            end
        end
    end
    return result
end

--Generate the next free "teleporterN" name. Uniqueness is checked against
--EVERY teleporter component on the current map (markup or not - a clash with
--an art teleporter would mis-pair just the same). Cross-map clashes are not
--checked (no Lua access to other maps' teleporter indexes), but the engine
--prefers a same-map partner, so a local pair always wins.
local function GenerateTeleporterLinkName()
    local used = {}
    local map = game.currentMap
    if map ~= nil then
        for _,floor in ipairs(map.floors or {}) do
            for _,obj in pairs(floor.objects or {}) do
                local comp = obj:GetComponent("Teleporter")
                if comp ~= nil then
                    used[LinkKey(GetComponentFieldValue(comp, "linkName"))] = true
                end
            end
        end
    end
    local n = 1
    while used["teleporter" .. n] ~= nil do
        n = n + 1
    end
    return "teleporter" .. n
end

--The link name the next pair will use, generating a fresh unique one when
--none is set (first use, or after a pair was completed).
local function CurrentTeleporterLinkName()
    if m_props.teleLink == nil or trim(m_props.teleLink) == "" then
        m_props.teleLink = GenerateTeleporterLinkName()
    end
    return m_props.teleLink
end

--Abort a half-placed teleporter pair: delete the first teleporter and clear
--the pending state. Safe to call when nothing is pending.
local function AbortPendingTeleporterPair()
    local pendingId = m_props.pendingPartnerId
    if pendingId == nil then
        return
    end
    local pendingFloorId = m_props.pendingFloorId
    m_props.pendingPartnerId = nil
    m_props.pendingLink = nil
    m_props.pendingFloorId = nil

    local floor = nil
    if pendingFloorId ~= nil then
        floor = game.GetFloor(pendingFloorId)
    end
    if floor == nil then
        floor = game.currentFloor
    end
    if floor ~= nil then
        local obj = floor:GetObject(pendingId)
        if obj ~= nil and obj.valid then
            obj:Destroy()
        end
    end

    if m_markupHud ~= nil and m_markupHud.valid then
        m_markupHud:FireEventTree("refreshprops")
    end
end

--The props engine half (the object-editing filter) needs an engine build. A
--stale build shows a muted message instead of the props UI - placing props it
--cannot show or manipulate would strand them invisibly on the map.
--
--GOTCHA: the callback itself CANNOT be probed. Unknown properties on the dmhub
--bridge read as nil AND accept writes silently (verified live 2026-07-28), so
--both "read it" and "assign it, read it back" succeed on a stale engine. Hence
--the dedicated supportsObjectEditingFilter probe property, the same pattern as
--floor.supportsSolidOperations. pcall + == true: nil on older builds.
local function PropsSupported()
    local supported = false
    pcall(function()
        supported = dmhub.supportsObjectEditingFilter == true
    end)
    return supported
end

--Props mode's half of the engine's object-editing filter poll. Non-nil makes
--objects tagged with the returned keyword visible/selectable/draggable (and
--everything else inert) - so it must be non-nil only while the Props tab is
--focused. Every markup prop matches, whatever its type: with a data-driven
--roster, scoping interaction to just the selected chip would make the rest
--of the DM's placed props invisible AND inert, which reads as "my props
--vanished". Clicking a prop selects its palette chip instead (see
--MarkupHandleObjectsSelected).
local function GetMarkupObjectEditingFilter()
    if m_mode ~= "props" then
        return nil
    end

    if not m_arm.Armed() then
        return nil
    end

    return MARKUP_PROP_KEYWORD
end

--The placement ghost needs an engine build beyond the object-editing filter:
--the object tool must show its preview WITHOUT placing on click while the
--filter is active (this panel owns placement, so the engine placing too
--would drop a second unconfigured copy), keep props mouseoverable while the
--preview is armed, and expose the preview's snapped position. Probe
--property, same pattern as supportsObjectEditingFilter.
local function GhostSupported()
    local supported = false
    pcall(function()
        supported = editor.supportsObjectPlacementPreview == true
    end)
    return supported
end

--Props mode's half of the engine's palette-selection poll
--(dmhub.GetSelectedObject): a non-nil object assetid makes the object tool
--show a placement preview ('ghost') at the cursor, exactly like the Objects
--panel's palette. Published only while the Props tab is armed for PLACEMENT:
--focused, the ghost-capable engine build, a type selected, and no placed
--prop bound to the editors (while editing, clicks should select/drag - and
--pre-ghost builds clear the object selection every frame while a palette id
--is published). The engine indexes the returned id straight into the object
--asset table, so never publish an id whose asset is missing.
local function GetMarkupSelectedObject()
    if GetMarkupObjectEditingFilter() == nil then
        return nil
    end
    if not GhostSupported() then
        return nil
    end
    if m_props.selected == nil or m_props.editingId ~= nil then
        return nil
    end
    if assets:GetObjectNode(m_props.selected) == nil then
        return nil
    end
    return m_props.selected
end

--Props mode's half of the engine's object-selection callback: when the Props
--tab is focused and everything selected is a markup prop, bind the selection
--to the panel's property editors and suppress the generic object-properties
--dialog. The engine passes LuaObjectInstance userdata (not id strings,
--despite the stub). Returns true when the selection was consumed.
local function MarkupHandleObjectsSelected(objects)
    if m_mode ~= "props" then
        return false
    end

    if not m_arm.Armed() then
        return false
    end

    local valid = {}
    for _,obj in ipairs(objects or {}) do
        if obj.valid then
            valid[#valid+1] = obj
        end
    end

    if #valid == 0 then
        --selection cleared: unbind our editors, but let the generic dialog
        --see the clear too in case it is open.
        if m_props.editingId ~= nil then
            m_props.editingId = nil
            m_props.editingIds = nil
            m_markupHud:FireEventTree("refreshprops")
        end
        return false
    end

    for _,obj in ipairs(valid) do
        local kw = obj.keywords
        if kw == nil or kw[MARKUP_PROP_KEYWORD] == nil then
            return false
        end
    end

    --selecting an existing prop while a teleporter pair is half-placed means
    --the user moved on without placing the partner: abort (deletes the first
    --teleporter). Selecting the pending teleporter itself keeps the pair
    --pending - clicking the thing you just placed should not destroy it.
    if m_props.pendingPartnerId ~= nil then
        local selectedPending = false
        for _,obj in ipairs(valid) do
            if obj.objid == m_props.pendingPartnerId then
                selectedPending = true
                break
            end
        end
        if not selectedPending then
            AbortPendingTeleporterPair()
        end
    end

    --bind the WHOLE selection: the first prop is the primary (single-value
    --reads come from it), and property edits apply to every bound prop.
    m_props.editingId = valid[1].objid
    local ids = {}
    for _,obj in ipairs(valid) do
        ids[#ids+1] = obj.objid
    end
    m_props.editingIds = ids

    --select the clicked prop's palette chip too, so the property editors
    --and the placement type follow what the DM is looking at. A prop whose
    --asset is no longer in the palette (untagged, or a legacy prop from the
    --preset-roster build) binds to the editors without moving the selection.
    local assetid = valid[1].assetid
    if assetid ~= nil and assetid ~= m_props.selected then
        for _,node in ipairs(MarkupPropAssets()) do
            if node.id == assetid then
                m_props.selected = assetid
                break
            end
        end
    end

    --Teleporters select as a UNIT: selecting one end pulls its same-floor
    --partner into the engine selection, so both ends highlight, drag
    --together, and the engine's Delete key removes both. Cross-floor
    --partners are deliberately NOT co-selected: the object tool's drag and
    --delete paths assume current-floor objects (dragging would blind-move
    --the invisible off-floor end, and DeleteObjects indexes
    --currentFloor.objects), and the selection callback stamps every entry
    --with currentFloorId. Idempotent - setting editorSelection on an
    --already-selected object is a no-op - so the next-frame re-fire of this
    --handler with both ends selected converges instead of recursing.
    local firstComp = valid[1]:GetComponent("Teleporter")
    if firstComp ~= nil then
        local link = GetComponentFieldValue(firstComp, "linkName")
        if link ~= nil and trim(tostring(link)) ~= "" then
            for _,entry in ipairs(MarkupTeleportersOnMap()) do
                if LinkKey(entry.link) == LinkKey(link)
                    and entry.obj.objid ~= valid[1].objid
                    and entry.floorid == valid[1].floorid then
                    entry.obj.editorSelection = true
                end
            end
        end
    end

    m_markupHud:FireEventTree("refreshprops")
    return true
end

--Elevation editing is a patron feature: ElevationPanel.lua only registers the
--Elevation Editor dock panel when patronTier > 0, and the engine returns a nil
--heightEditingInfo for non-patrons even while isHeightEditingEnabled is true.
--Gate our clone the same way so we can never put the engine in that state.
local function ElevationSupported()
    return dmhub.patronTier > 0
end

--Elevation mode's half of the engine's height-editing poll. The engine calls
--dmhub.GetHeightEditingInfo every frame; non-nil turns height painting on and
--carries the brush parameters. Same shape (and the same settings) as
--ElevationPanel.lua's version, focus-gated the same way -- the wrapper at the
--bottom of this file chains the two so whichever panel has focus wins.
local function GetMarkupHeightEditingInfo()
    if m_mode ~= "elevation" or not ElevationSupported() then
        return nil
    end

    if not m_arm.Armed() then
        return nil
    end

    return {
        height = dmhub.GetSettingValue("heightmap:height"),
        directional = dmhub.GetSettingValue("heightmap:gradient") == "slope",
        opacity = dmhub.GetSettingValue("heightmap:opacity"),
        blend = dmhub.GetSettingValue("heightmap:blend"),
    }
end

local function GetMarkupSelectedWall()
    if m_markupHud == nil or not m_markupHud.valid then
        return nil
    end

    --The dock ancestor is optional: panel content can be hosted outside the
    --dock (e.g. the document system's PanelDocument bridge), so only use it
    --for the highlight, never as a gate.
    local dockPanel = m_markupHud:FindParentWithClass("dockablePanel")

    --erase/delete are custom map tools, not wall drawing: publish no wall so
    --the engine building tools stay inactive while they run.
    if m_mode ~= "walls" or m_toolId == "erase" or m_toolId == "delete" or not m_arm.Armed() then
        if dockPanel ~= nil then
            dockPanel:SetClass("highlightPanel", false)
        end
        return nil
    end

    local entry = m_paletteEntries[m_selectedIndex or 0]

    --Solid draw mode publishes no wall: solid strokes run through custom map
    --tools + ExecutePolygonOperation{solid=true}, not the engine building
    --tools. Publishing here would let the building tools draw THIN walls
    --while the panel is in Solid mode.
    --EXCEPT for the Points tool: it EDITS existing geometry (solid block
    --outlines included, with an engine build) rather than drawing, so its
    --activation token can't draw anything - and publishing it is also what
    --keeps GetWallPointsInvisibleOnly scoping the tool away from art walls.
    --Gated on the engine tool actually being "points", like the fallback
    --below, so the exception can never leak into wall drawing.
    if m_solidMode and not (m_toolId == "points" and dmhub.GetSettingValue("buildingtool") == "points") then
        if dockPanel ~= nil then
            dockPanel:SetClass("highlightPanel", false)
        end
        return nil
    end

    local guid = nil
    if entry ~= nil then
        guid = entry.guid
    end

    if guid == nil or assets.walls[guid] == nil then
        --The points tool edits existing walls, so the published wall is only
        --the engine's activation token: fall back to the base invisible wall
        --when the palette selection is unmaterialized (fresh preset chips have
        --no asset until first clicked). Gated on the engine tool actually
        --being "points" so the fallback can never leak into wall DRAWING.
        if m_toolId == "points" and dmhub.GetSettingValue("buildingtool") == "points" then
            if assets.walls[BASE_INVISIBLE_WALL_ID] ~= nil then
                guid = BASE_INVISIBLE_WALL_ID
            end
        end
    end

    if guid == nil or assets.walls[guid] == nil then
        if dockPanel ~= nil then
            dockPanel:SetClass("highlightPanel", false)
        end
        return nil
    end

    if dockPanel ~= nil then
        dockPanel:SetClass("highlightPanel", true)
    end
    return guid
end

--============================================================================
--Edit dialog for markup walls: the gameplay fields only, none of the art
--fields that are meaningless on an invisible wall.
--============================================================================

--owner (optional) = the element the edit was invoked from; when it lives in
--a popped-out Map Markup window the dialog shows inside that OS window
--(gui.ShowModal owner routing). The dialog closes via the captured layer so
--a palette rebuild destroying the owner cannot strand it open.
local function ShowMarkupWallDialog(wallid, owner)
    local asset = assets.walls[wallid]
    if asset == nil then
        return
    end

    local modalLayer = nil

    local originalValues = {
        description = asset.description,
        blocksMovement = asset.blocksMovement,
        blocksForcedMovement = asset.blocksForcedMovement,
        occludesVision = asset.occludesVision,
        occludesLight = asset.occludesLight,
        visionOneWay = asset.visionOneWay,
        cover = asset.cover,
        soundOcclusion = asset.soundOcclusion,
        climbable = asset.climbable,
        solidity = asset.solidity,
        breakStamina = asset.breakStamina,
        rubbleKeyword = asset.rubbleKeyword,
        rubbleTerrainId = asset.rubbleTerrainId,
    }

    --pcall + engine gate, like the openable fields below: pre-scoping engine
    --builds have no markupMapId to capture or restore.
    if m_mapScope.WallSupported() then
        pcall(function()
            originalValues.markupMapId = asset.markupMapId
        end)
    end

    local RevertChanges = function()
        asset.description = originalValues.description
        asset.blocksMovement = originalValues.blocksMovement
        asset.blocksForcedMovement = originalValues.blocksForcedMovement
        asset.occludesVision = originalValues.occludesVision
        asset.occludesLight = originalValues.occludesLight
        asset.visionOneWay = originalValues.visionOneWay
        asset.cover = originalValues.cover
        asset.soundOcclusion = originalValues.soundOcclusion
        asset.climbable = originalValues.climbable
        asset.solidity = originalValues.solidity
        asset.breakStamina = originalValues.breakStamina
        asset.rubbleKeyword = originalValues.rubbleKeyword
        asset.rubbleTerrainId = originalValues.rubbleTerrainId
        if originalValues.openable ~= nil then
            pcall(function()
                asset.openable = originalValues.openable
                asset.openSound = originalValues.openSound
                asset.closeSound = originalValues.closeSound
            end)
        end
        if originalValues.markupMapId ~= nil then
            pcall(function()
                asset.markupMapId = originalValues.markupMapId
            end)
        end
    end

    --Breakability working state. The material is derived from the stamina on
    --open (see BreakMaterialForStamina) and both live here until Save, so
    --Cancel reverts cleanly like every other field in this dialog.
    local breakable = AssetIsBreakable(asset)
    local breakStamina = asset.breakStamina or 0
    if breakable and breakStamina <= 0 then
        breakStamina = DEFAULT_BREAK_STAMINA
    end
    local breakMaterialId = BreakMaterialForStamina(breakStamina)

    --Openable (door) state lives on the WALL ASSET (WallAsset.openable, plus
    --the open/close sounds SetAssetOpenable stamps). Applied live like every
    --other field: Save uploads, Cancel reverts. Needs the engine build - the
    --checkbox only shows when the asset supports the field.
    local canBeOpenable = OpenableWallsSupported()
    local openable = AssetIsOpenable(asset)
    if canBeOpenable then
        originalValues.openable = openable
        pcall(function()
            originalValues.openSound = asset.openSound
            originalValues.closeSound = asset.closeSound
        end)
    end

    --Pushes the working break state onto the asset. Called on every change so
    --the live asset always matches the controls; Save uploads, Cancel reverts.
    local ApplyBreakToAsset = function()
        SetAssetBreakable(asset, breakable, breakStamina)
    end

    --Shared ("global") walls fork on save rather than being edited in place:
    --a wall other maps can also use must not change under them. Save creates
    --a copy carrying the edits, private to this map, and retypes every wall
    --drawn with the original on this map to the copy (palette chips follow).
    --"Save Changes to This Wall for All Maps" is the explicit opt-in to edit
    --the shared wall in place - and once the wall has been RENAMED it swaps
    --to "Make Available to All Maps", because a renamed wall is a different
    --wall: the fork then uploads game-wide instead of map-private, leaving
    --the original untouched either way. Requires the scoping engine build:
    --on a stale build every wall reads as unscoped, so forking is disabled
    --and the dialog saves in place exactly as before.
    local isGlobalWall = m_mapScope.WallSupported() and m_mapScope.WallMapId(asset) == nil

    local IsRenamed = function()
        return (asset.description or "") ~= (originalValues.description or "")
    end

    --any difference from the state the dialog opened with, so a Save on an
    --untouched shared wall does not fork pointlessly.
    local IsEdited = function()
        if IsRenamed()
            or asset.blocksMovement ~= originalValues.blocksMovement
            or asset.blocksForcedMovement ~= originalValues.blocksForcedMovement
            or asset.occludesVision ~= originalValues.occludesVision
            or asset.occludesLight ~= originalValues.occludesLight
            or asset.visionOneWay ~= originalValues.visionOneWay
            or asset.cover ~= originalValues.cover
            or asset.soundOcclusion ~= originalValues.soundOcclusion
            or asset.climbable ~= originalValues.climbable
            or asset.solidity ~= originalValues.solidity
            or asset.breakStamina ~= originalValues.breakStamina then
            return true
        end
        local openableChanged = false
        if originalValues.openable ~= nil then
            pcall(function()
                openableChanged = asset.openable ~= originalValues.openable
                    or asset.openSound ~= originalValues.openSound
                    or asset.closeSound ~= originalValues.closeSound
            end)
        end
        return openableChanged
    end

    --Creates the fork and points this map at it. DuplicateWall serializes
    --the LIVE in-memory asset, so the copy snapshots the dialog's edits
    --exactly as they stand; the original is then reverted and never
    --uploaded - other maps keep it exactly as it was. Every operation drawn
    --with the original on this map is retyped to the fork
    --(ReplaceWallOperations keeps each op's timestamp so geometry re-applies
    --in the same order), and palette chips follow - a forked library chip
    --becomes a custom chip so Edit Wall stays available on it.
    local ForkAsset = function(makeGlobal)
        local newGuid = assets:DuplicateWall(wallid)
        if newGuid == nil then
            RevertChanges()
            return
        end

        local fork = assets.walls[newGuid]
        if makeGlobal then
            pcall(function()
                fork.markupMapId = ""
            end)
        else
            m_mapScope.StampWall(fork)
        end
        fork:Upload()

        RevertChanges()

        pcall(function()
            game.currentMap:ReplaceWallOperations(wallid, newGuid)
        end)

        local changed = false
        for _,entry in ipairs(m_paletteEntries) do
            if entry.guid == wallid then
                entry.guid = newGuid
                if entry.kind == "wall" then
                    entry.kind = "custom"
                end
                changed = true
            end
        end
        if changed then
            SavePalette(m_paletteEntries)
        end
    end

    local dialogPanel
    dialogPanel = gui.Panel{
        id = "MarkupWallDialog",
        classes = {"framedPanel"},
        --94% of the modal layer, capped at the design width: full size in
        --the main window, shrink-to-fit inside a small popout window.
        width = "94%",
        maxWidth = 460,
        height = "auto",
        pad = 16,
        borderBox = true,
        flow = "vertical",
        styles = ThemeEngine.MergeStyles{
            Styles.Panel,
            Styles.Form,
            {
                classes = {"formStackedRow"},
                width = "96%",
            },
            {
                classes = {"slider"},
                height = 30,
            },
            {
                classes = {"sliderLabel"},
                fontSize = 14,
            },
            {
                classes = {"formCheck"},
                lmargin = 8,
                vmargin = 2,
            },
        },

        children = {
            gui.Label{
                classes = {"dialogTitle"},
                text = "Edit Markup Wall",
            },

            gui.Panel{
                classes = {"formStackedRow"},
                gui.Label{
                    classes = {"formStacked"},
                    text = "Name:",
                },
                gui.Input{
                    classes = {"formStacked"},
                    text = asset.description or "",
                    change = function(element)
                        asset.description = element.text
                        --renaming a shared wall makes it a new wall: the
                        --shared-wall row's label and button follow the name.
                        dialogPanel:FireEventTree("refreshscope")
                    end,
                },
            },

            --map-private wall types: created from this map's palette and
            --hidden from other maps' pickers until promoted, mirroring the
            --zone type editor's button. Applied live like every other field
            --in this dialog: Save uploads the promotion, Cancel reverts it.
            gui.Panel{
                classes = {"formStackedRow", cond(m_mapScope.WallMapId(asset) ~= nil, nil, "collapsed")},
                gui.Label{
                    classes = {"formStacked"},
                    text = "This wall type is only available on this map.",
                },
                gui.Button{
                    classes = {"sizeM"},
                    halign = "left",
                    text = "Make Available to All Maps",
                    click = function(element)
                        pcall(function()
                            asset.markupMapId = ""
                        end)
                        element.parent:SetClass("collapsed", true)
                    end,
                },
            },

            --shared walls: the explicit opt-in to edit the wall in place for
            --every map that uses it - or, once renamed, to make the FORK
            --available to all maps instead (a renamed wall is a new wall;
            --see the fork comment above). Both act immediately and close.
            gui.Panel{
                classes = {"formStackedRow", cond(isGlobalWall, nil, "collapsed")},
                flow = "vertical",
                height = "auto",

                gui.Label{
                    classes = {"formStacked"},
                    width = "100%",
                    text = "This wall is shared with other maps. Save makes a copy private to this map.",
                    refreshscope = function(element)
                        if IsRenamed() then
                            element.text = "Renamed: saving creates a new wall type for this map."
                        else
                            element.text = "This wall is shared with other maps. Save makes a copy private to this map."
                        end
                    end,
                },

                gui.Button{
                    classes = {"sizeM"},
                    halign = "left",
                    vmargin = 4,
                    text = "Save Changes to This Wall for All Maps",
                    refreshscope = function(element)
                        if IsRenamed() then
                            element.text = "Make Available to All Maps"
                        else
                            element.text = "Save Changes to This Wall for All Maps"
                        end
                    end,
                    click = function()
                        if IsRenamed() then
                            --a renamed wall is a new wall: fork it game-wide,
                            --leaving the original untouched.
                            ForkAsset(true)
                        else
                            --edit the shared wall in place: every map using
                            --it sees the changes.
                            asset:Upload()
                        end
                        gui.CloseModalInLayer(modalLayer)
                    end,
                },
            },

            gui.Check{
                classes = {"formCheck", cond(canBeOpenable, nil, "collapsed")},
                text = "Openable (Door)",
                tooltip = "When set, every wall segment drawn with this type is a door: a clickable icon floats over it, and opening it disables the whole segment's blocking until it is closed again. The Director can right-click the icon to lock the door.",
                value = openable,
                change = function(element)
                    openable = element.value
                    SetAssetOpenable(asset, openable)
                    dialogPanel:FireEventTree("refreshopenable")
                end,
            },

            gui.Label{
                classes = {"fgMuted", "sizeXs"},
                text = "While closed, the door blocks exactly like this wall type (all the settings below apply). Opening it via its icon disables the drawn segment entirely; the sound plays for everyone. The Director always sees door icons and can right-click them to lock or unlock; players can use a door within 2 tiles and line of sight.",
                width = "96%",
                height = "auto",
                halign = "center",
                vmargin = 2,
                refreshopenable = function(element)
                    element:SetClass("collapsed", not openable)
                end,
            },

            gui.Check{
                classes = {"formCheck"},
                text = "Blocks Movement",
                value = asset.blocksMovement == true,
                change = function(element)
                    asset.blocksMovement = element.value
                end,
            },

            gui.Check{
                classes = {"formCheck"},
                text = "Blocks Forced Movement",
                value = asset.blocksForcedMovement == true,
                change = function(element)
                    asset.blocksForcedMovement = element.value
                end,
            },

            gui.Check{
                classes = {"formCheck"},
                text = "Blocks Vision",
                value = asset.occludesVision == true,
                change = function(element)
                    asset.occludesVision = element.value
                end,
            },

            gui.Check{
                classes = {"formCheck"},
                text = "Blocks Light",
                value = asset.occludesLight == true,
                change = function(element)
                    asset.occludesLight = element.value
                end,
            },

            gui.Check{
                classes = {"formCheck"},
                text = "One-Way Vision & Light",
                tooltip = "When set, the wall only blocks vision and light from one side. The side depends on the direction the wall was drawn in.",
                value = asset.visionOneWay == true,
                change = function(element)
                    asset.visionOneWay = element.value
                end,
            },

            gui.Panel{
                classes = {"formStackedRow"},
                gui.Label{
                    classes = {"formStacked"},
                    text = "Cover:",
                },
                gui.Dropdown{
                    classes = {"formStacked"},
                    idChosen = asset.cover or "None",
                    options = {
                        {
                            id = "None",
                            text = "No Cover",
                        },
                        {
                            id = "Half",
                            text = "Half Cover",
                        },
                        {
                            id = "ThreeQuarters",
                            text = "Three-Quarters Cover",
                        },
                        {
                            id = "Full",
                            text = "Full Cover",
                        },
                    },
                    change = function(element)
                        asset.cover = element.idChosen
                    end,
                },
            },

            gui.Panel{
                classes = {"formStackedRow"},
                gui.Label{
                    classes = {"formStacked"},
                    text = "Climbable:",
                },
                gui.Dropdown{
                    classes = {"formStacked"},
                    idChosen = asset.climbable or "NotClimbable",
                    options = {
                        {
                            id = "NotClimbable",
                            text = "Not Climbable",
                        },
                        {
                            id = "ClimbersOnly",
                            text = "Climbable (Climbers Only)",
                        },
                        {
                            id = "AllCreatures",
                            text = "Climbable (All Creatures)",
                        },
                    },
                    change = function(element)
                        asset.climbable = element.idChosen
                    end,
                },
            },

            gui.Panel{
                classes = {"formStackedRow"},
                gui.Label{
                    classes = {"formStacked"},
                    text = "Blocks Sounds:",
                },
                gui.Slider{
                    value = asset.soundOcclusion or 0,
                    minValue = 0,
                    maxValue = 1,
                    sliderWidth = 240,
                    labelWidth = 50,
                    events = {
                        change = function(element)
                            asset.soundOcclusion = element.value
                        end,
                    },
                },
            },

            --Breakable: a creature shoved into this wall with enough force
            --smashes through it. Applies to thin walls and solid blocks
            --alike. The material rows below stay hidden until it is on.
            gui.Check{
                classes = {"formCheck"},
                text = "Breakable",
                tooltip = "When set, a creature shoved into this wall hard enough smashes through it instead of stopping. The force needed is the wall's stamina.",
                value = breakable,
                change = function(element)
                    breakable = element.value
                    ApplyBreakToAsset()
                    dialogPanel:FireEventTree("refreshbreak")
                end,
            },

            gui.Panel{
                classes = {"formStackedRow"},
                refreshbreak = function(element)
                    element:SetClass("collapsed", not breakable)
                end,

                gui.Label{
                    classes = {"formStacked"},
                    text = "Material:",
                },
                gui.Dropdown{
                    classes = {"formStacked"},
                    idChosen = breakMaterialId,
                    options = (function()
                        local result = {}
                        for _,material in ipairs(BREAK_MATERIALS) do
                            result[#result+1] = {
                                id = material.id,
                                text = material.text,
                            }
                        end
                        return result
                    end)(),
                    change = function(element)
                        breakMaterialId = element.idChosen
                        local material = BreakMaterialById(breakMaterialId)
                        --Presets stamp their stamina; Custom keeps whatever
                        --value was already there as the starting point.
                        if material ~= nil and material.stamina ~= nil then
                            breakStamina = material.stamina
                        end
                        ApplyBreakToAsset()
                        dialogPanel:FireEventTree("refreshbreak")
                    end,
                },
            },

            gui.Panel{
                classes = {"formStackedRow"},
                refreshbreak = function(element)
                    element:SetClass("collapsed", not breakable)
                end,

                gui.Label{
                    classes = {"formStacked"},
                    text = "Stamina:",
                },

                --Preset materials show their fixed value; only Custom is
                --editable. Both live here and swap by collapse so the row
                --keeps its layout either way.
                gui.Label{
                    classes = {"formStacked"},
                    text = "",
                    refreshbreak = function(element)
                        element:SetClass("collapsed", breakMaterialId == "custom")
                        element.text = string.format("%d", breakStamina)
                    end,
                },

                gui.Input{
                    classes = {"formStacked"},
                    text = string.format("%d", breakStamina),
                    width = 60,
                    characterLimit = 3,
                    numeric = true,
                    selectAllOnFocus = true,
                    refreshbreak = function(element)
                        element:SetClass("collapsed", breakMaterialId ~= "custom")
                    end,
                    change = function(element)
                        local n = tonumber(element.text)
                        if n == nil or n < 1 then
                            --reject non-numeric / zero: restore the last good
                            --value rather than silently making it unbreakable.
                            element.text = string.format("%d", breakStamina)
                            return
                        end
                        breakStamina = math.floor(n + 0.5)
                        element.text = string.format("%d", breakStamina)
                        ApplyBreakToAsset()
                    end,
                },
            },

            gui.Panel{
                width = "100%",
                height = "auto",
                flow = "horizontal",
                halign = "center",
                vmargin = 8,

                gui.Button{
                    classes = {"sizeM"},
                    text = "Cancel",
                    halign = "center",
                    captureEscape = true,
                    escapePriority = EscapePriority.EXIT_DIALOG,
                    events = {
                        click = function(element)
                            element:FireEvent("escape")
                        end,
                        escape = function()
                            RevertChanges()
                            gui.CloseModalInLayer(modalLayer)
                        end,
                    },
                },

                gui.Button{
                    classes = {"sizeM"},
                    text = cond(isGlobalWall, "Save Copy for This Map", "Save"),
                    halign = "center",
                    events = {
                        click = function()
                            if isGlobalWall then
                                --editing a shared wall forks it (see the
                                --fork comment above); untouched = nothing
                                --to fork, so just restore and close.
                                if IsEdited() then
                                    ForkAsset(false)
                                else
                                    RevertChanges()
                                end
                            else
                                asset:Upload()
                            end
                            gui.CloseModalInLayer(modalLayer)
                        end,
                    },
                },
            },
        },
    }

    --settle the breakability + openable rows' initial collapse state + values,
    --and the shared-wall row's label/button text.
    dialogPanel:FireEventTree("refreshbreak")
    dialogPanel:FireEventTree("refreshopenable")
    dialogPanel:FireEventTree("refreshscope")

    modalLayer = gui.ShowModal(dialogPanel, {owner = owner})
end

--============================================================================
--The panel.
--============================================================================

local MODES = {
    {
        id = "walls",
        text = "Walls",
    },
    {
        id = "zones",
        text = "Zones",
    },
    {
        id = "surfaces",
        text = "Footsteps",
    },
    {
        id = "elevation",
        text = "Elevation",
    },
    {
        id = "props",
        text = "Props",
    },
}

--Tools with a `tool` field drive the engine building tools (drawing).
--Tools with a `mapTool` field are custom map tools (editor.SetMapTool) whose
--strokes come back to this panel as 'tool' events. The eraser and Delete
--Wall tools are shared between the thin and solid tool strips.
local TOOL_ERASE = {
    id = "erase",
    text = "Erase",
    icon = "phosphor/eraser-fill.png",
    mapTool = "rectangle",
    mapToolClosed = true,
    --draws the engine's stroke preview red instead of white (see the think
    --handler's SetMapTool call), like the zone and footstep erasers.
    erase = true,
    help = "Eraser: drag a rectangle to erase every markup wall (and markup solid block) inside it. Visible art walls are not affected.",
}

local TOOL_DELETE = {
    id = "delete",
    text = "Delete",
    icon = "ui-icons/close.png",
    --Inert sentinel: keeping a custom map tool alive (wallSkeletons=true)
    --leaves the grey wall skeleton overlay up so the user can see the walls
    --they are removing. This string matches no real map tool ("free",
    --"rectangle", "shape"...), so it captures no drawing - the Delete tool's
    --input comes from map focus (maphover/mappress) instead. See the think
    --loop and the maphover/mappress handlers below.
    mapTool = "markupdelete",
    mapToolClosed = false,
    help = "Delete Wall: hover a markup wall to highlight the segment under the cursor, then click to remove just that segment. Visible art walls are not affected.",
}

--Apply Type ("retype"): converts drawn markup walls to the SELECTED palette
--type. Two gestures through one real rectangle map tool: a click converts
--the WHOLE drawn operation under the cursor (the same hover machinery as
--Delete, tinted the target type's color and extended to the full wall
--path), and a drag converts every wall edge the rectangle touches, at edge
--granularity, with the captured edges highlighted live as the rect grows.
--Input arrives twice over - map focus (mappress, like Delete) AND the
--rectangle stroke (a click is a degenerate stroke) - because which of the
--two the engine delivers for a click depends on how it arbitrates a live
--custom tool against map focus; handling both is safe since retyping an
--already-converted wall is a no-op (RetypeWallEdges skips ops already of
--the target type).
local TOOL_RETYPE = {
    id = "retype",
    text = "Retype",
    icon = "phosphor/paint-roller-fill.png",
    mapTool = "rectangle",
    mapToolClosed = true,
    help = "Apply Type: click a markup wall to change that whole drawn wall to the selected wall type, or drag a rectangle starting on empty space to convert every wall edge it touches. Visible art walls are not affected.",
}

--`shape` pairs a tool with its counterpart in the other draw mode, so switching
--Thin <-> Solid keeps the shape the user picked instead of resetting the strip.
--Both strips lead with the rectangle so the two modes read the same.
local TOOLS = {
    {
        id = "rectangle",
        shape = "rect",
        text = "Rect",
        icon = "game-icons/square.png",
        tool = "rectangle",
        help = "Rectangle tool: drag to draw a rectangle of walls.",
    },
    {
        id = "line",
        shape = "poly",
        text = "Line",
        icon = "game-icons/polygon-segments.png",
        tool = "shape",
        help = "Line tool: click to chain wall segments; double-click or press Enter to finish.",
    },
    {
        id = "free",
        shape = "free",
        text = "Draw",
        icon = "panels/hud/icon_line_tool_82.png",
        tool = "free",
        help = "Freehand tool: drag to draw walls along the cursor.",
    },
    {
        id = "points",
        text = "Points",
        icon = "icons/icon_gesture/icon_gesture_47.png",
        tool = "points",
        help = "Edit Points: drag a wall vertex to move it. Right-click a vertex to delete it, click on a wall line to add a vertex, and click a one-way wall's direction marker to flip its facing.",
    },
    TOOL_RETYPE,
    TOOL_ERASE,
    TOOL_DELETE,
}

--Tool strip in SOLID draw mode: a solid block is a filled region, not an open
--polyline, so the drawing tools are closed shapes running as custom map tools
--(like the eraser) - never the engine building tools. Their strokes come back
--as 'tool' events and turn into ExecutePolygonOperation{solid=true} (see
--markupsolid below). The Points tool is the one engine building tool in this
--strip: PointEditingTool edits solid-op outlines too (it exempts solid ops
--from its floor-op skip), reshaping the block's area. On a stale engine build
--the tool activates but shows no vertices for solids - harmless no-op.
local SOLID_TOOLS = {
    {
        id = "solidrect",
        shape = "rect",
        text = "Rect",
        icon = "game-icons/square.png",
        mapTool = "rectangle",
        mapToolClosed = true,
        help = "Rectangle block: drag to fill a rectangle with a solid block of the selected wall type.",
    },
    {
        id = "solidpoly",
        shape = "poly",
        text = "Poly",
        icon = "game-icons/polygon-segments.png",
        mapTool = "shape",
        mapToolClosed = true,
        help = "Polygon block: click to chain vertices around the area to fill; double-click or press Enter to finish.",
    },
    {
        id = "solidfree",
        shape = "free",
        text = "Draw",
        icon = "panels/hud/icon_line_tool_82.png",
        mapTool = "free",
        mapToolClosed = true,
        help = "Freehand block: drag to trace the outline of the area to fill.",
    },
    {
        --same id as the thin strip's entry so switching Thin <-> Solid keeps
        --the Points tool selected (rebuildtools' validTool check passes).
        id = "points",
        text = "Points",
        icon = "icons/icon_gesture/icon_gesture_47.png",
        tool = "points",
        help = "Edit Points: drag a vertex of a solid block to reshape its area. Right-click a vertex to delete it; click on an edge to add a vertex.",
    },
    TOOL_RETYPE,
    TOOL_ERASE,
    TOOL_DELETE,
}

--Zone painting tools: all closed-shape custom map tools (a zone is a filled
--tile region). Strokes come back as 'tool' events and rasterize to the tiles
--whose centers the stroke contains.
local ZONE_TOOLS = {
    {
        id = "zonerect",
        text = "Rect",
        icon = "game-icons/square.png",
        mapTool = "rectangle",
        help = "Rectangle: drag to paint the selected zone type over an area.",
    },
    {
        id = "zonepoly",
        text = "Poly",
        icon = "game-icons/polygon-segments.png",
        mapTool = "shape",
        help = "Polygon: click to chain vertices around the area to paint; double-click or press Enter to finish.",
    },
    {
        id = "zonefree",
        text = "Draw",
        icon = "panels/hud/icon_line_tool_82.png",
        mapTool = "free",
        help = "Freehand: drag to trace the outline of the area to paint.",
    },
    {
        id = "zoneerase",
        text = "Erase",
        icon = "phosphor/eraser-fill.png",
        mapTool = "rectangle",
        erase = true,
        help = "Eraser: drag a rectangle to remove zone tiles from every zone in the region. Holes are clipped against the region.",
    },
}

local function ZoneToolById(id)
    for _,toolInfo in ipairs(ZONE_TOOLS) do
        if toolInfo.id == id then
            return toolInfo
        end
    end
    return nil
end

--Footsteps mode paint tools: the same closed-shape custom map tools as the
--zone tools, painting the selected surface family instead of a keyword.
local FOOTSTEP_TOOLS = {
    {
        id = "footrect",
        text = "Rect",
        icon = "game-icons/square.png",
        mapTool = "rectangle",
        help = "Rectangle: drag to paint the selected footstep surface over an area.",
    },
    {
        id = "footpoly",
        text = "Poly",
        icon = "game-icons/polygon-segments.png",
        mapTool = "shape",
        help = "Polygon: click to chain vertices around the area to paint; double-click or press Enter to finish.",
    },
    {
        id = "footfree",
        text = "Draw",
        icon = "panels/hud/icon_line_tool_82.png",
        mapTool = "free",
        help = "Freehand: drag to trace the outline of the area to paint.",
    },
    {
        id = "footerase",
        text = "Erase",
        icon = "phosphor/eraser-fill.png",
        mapTool = "rectangle",
        erase = true,
        help = "Eraser: drag a rectangle to clear painted footstep surfaces from the region.",
    },
}

local function FootstepToolById(id)
    for _,toolInfo in ipairs(FOOTSTEP_TOOLS) do
        if toolInfo.id == id then
            return toolInfo
        end
    end
    return nil
end

--Looks a tool id up in either strip (the draw-mode switch needs the OUTGOING
--tool's shape, which by then is no longer in the active strip).
local function FindToolInfo(id)
    for _,toolInfo in ipairs(TOOLS) do
        if toolInfo.id == id then
            return toolInfo
        end
    end
    for _,toolInfo in ipairs(SOLID_TOOLS) do
        if toolInfo.id == id then
            return toolInfo
        end
    end
    return nil
end

--The active tool strip follows the DRAW MODE, not the selected wall type:
--thin mode drives the engine building tools, solid mode drives closed-shape
--custom map tools. Openable (door) types are thin-only - selecting one
--forces thin mode (SelectChip) - so no separate strip is needed.
local function ActiveToolInfos()
    if m_solidMode and not EntryIsOpenable(m_paletteEntries[m_selectedIndex or 0]) then
        return SOLID_TOOLS
    end
    return TOOLS
end

--Chip rules are shared between the panel and the library modal: modals
--re-root the style cascade, so the modal needs its own copy of these rules.
local function MarkupChipStyles()
    return {
        {
            selectors = {"markupChip"},
            borderWidth = 1,
            borderColor = "@border",
            bgcolor = "clear",
        },
        {
            selectors = {"markupChip", "hover"},
            borderColor = "@fg",
        },
        --the selected chip must be unmistakable at a glance: filled AND a
        --thicker accent border, not just a slightly brighter outline.
        {
            selectors = {"markupChip", "selected"},
            bgcolor = "@bgAlt",
            borderColor = "@accent",
            borderWidth = 2,
        },
        {
            selectors = {"markupWallLine"},
            bgcolor = "@fgMuted",
        },

        --the Wall Color swatches: a quiet outline normally, brightening on
        --hover, and a thick bright ring on the chosen swatch. The ring is
        --@fg rather than @accent because it sits on an arbitrary swatch
        --color and must read against all eight.
        {
            selectors = {"markupColorSwatch"},
            borderWidth = 1,
            borderColor = "@border",
        },
        {
            selectors = {"markupColorSwatch", "hover"},
            borderColor = "@fg",
        },
        {
            selectors = {"markupColorSwatch", "selected"},
            borderWidth = 2,
            borderColor = "@fg",
        },

        --the zone chip's "Entire Map" toggle: a small pill that lights up
        --while this zone type blankets the whole map.
        {
            selectors = {"markupEntireMap"},
            borderWidth = 1,
            borderColor = "@border",
            bgcolor = "clear",
        },
        {
            selectors = {"markupEntireMap", "hover"},
            borderColor = "@fg",
        },
        {
            selectors = {"markupEntireMap", "lit"},
            bgcolor = "@accent",
            borderColor = "@accent",
        },
        {
            selectors = {"markupEntireMapLabel"},
            color = "@fgMuted",
        },
        {
            selectors = {"markupEntireMapLabel", "parent:hover"},
            color = "@fg",
        },
        {
            selectors = {"markupEntireMapLabel", "parent:lit"},
            color = "@fgInverse",
        },

        --small uppercase section headers ("WALL TYPES", "SHAPE", "TOOL"):
        --quieter than body text so the selectable content reads first.
        {
            selectors = {"markupSectionHeader"},
            fontSize = 12,
            bold = true,
            color = "@fgMuted",
        },

        --the armed-state dot on the active mode tab: bright while the panel
        --holds focus (drawing armed), dim when a click elsewhere disarmed it.
        {
            selectors = {"markupStateDot"},
            bgcolor = "@disabled",
        },
        {
            selectors = {"markupStateDot", "armed"},
            bgcolor = "@fgStrong",
        },

        --tool chips: icon over a small caption. The destructive pair (erase /
        --delete) is tinted @danger so it cannot be mistaken for a drawing tool.
        {
            selectors = {"markupToolChip"},
            borderWidth = 1,
            borderColor = "@border",
            bgcolor = "clear",
        },
        {
            selectors = {"markupToolChip", "hover"},
            borderColor = "@fg",
        },
        {
            selectors = {"markupToolChip", "selected"},
            bgcolor = "@bgAlt",
            borderColor = "@accent",
            borderWidth = 2,
        },
        --after selected, so a selected destructive tool keeps the red border.
        {
            selectors = {"markupToolChip", "danger"},
            borderColor = "@danger",
        },
        {
            selectors = {"markupToolIcon"},
            bgcolor = "@fg",
        },
        {
            selectors = {"markupToolIcon", "danger"},
            bgcolor = "@danger",
        },
        {
            selectors = {"markupToolLabel"},
            fontSize = 10,
            color = "@fgMuted",
        },
        {
            selectors = {"markupToolLabel", "danger"},
            color = "@danger",
        },
        {
            selectors = {"markupToolDivider"},
            bgcolor = "@border",
        },

        --gui.Slider deliberately sets NO default width/height (Gui.lua: doing
        --so would be selfStyle and would beat any cascade rule the caller
        --supplied), and it sizes its handle off its own height
        --(handle width = "100% height", holding a 60% square rotated 45).
        --An unsized slider therefore renders as a giant diamond. The Edit
        --Wall dialog solves this with the same two rules; the panel body
        --needs its own copy because that dialog is a separate modal with
        --separate styles. Width leaves room for the row's 80px name label.
        {
            selectors = {"slider"},
            width = "100%-84",
            height = 24,
            valign = "center",
        },
        {
            selectors = {"sliderLabel"},
            fontSize = 14,
        },
    }
end

local function GetPanelStyles()
    return ThemeEngine.MergeStyles{
        MarkupChipStyles(),
    }
end

--Tooltip that opens to the SIDE of the hovered control - over the map, not
--over the panel - so it never covers the controls it describes. Side is
--picked per hover from where the control actually sits on screen: open
--toward whichever side has more room. The engine clamps tooltips back
--onto the screen, so opening toward a nearby screen edge would slide the
--tooltip over the control itself (the old dock-class check missed
--undocked/windowed hosts and did exactly that).
--
--In a POPOUT window there is no map to open over - the whole window is
--panel, so a tooltip that FITS the window necessarily sits on the
--controls. There the tooltip is pushed just past the window edge instead:
--the engine's tooltip promote-on-overflow (popout Phase 5.2) lifts it into
--a desktop-level child window BESIDE the OS window, vertically centered on
--the control. Gated on child-window support; without it (old engine or
--companion) the in-window clamp degrades this to today's behavior.
local function SideTooltip(text)
    if text == nil then
        return nil
    end
    return function(element)
        local halign = "right"

        local dock = element:FindParentWithClass("dock")
        local popoutHost = nil
        if dock ~= nil and dock.data.nativeWindowRoot then
            popoutHost = dock
        end

        if popoutHost ~= nil and dmhub.popoutChildWindowsSupported and
            dmhub.supportsPopoutTooltipPlacement then
            --Popout window: the tooltip opens flush beside the hovered
            --control exactly like in-app; when it does not fit the window,
            --the engine's tooltip promote-on-overflow lifts it into a
            --desktop-level child window at that same anchor-adjacent spot,
            --so it extends past the window edge (partly over the window,
            --partly over the desktop) instead of clamping onto the panel.
            --Only the SIDE choice differs from in-app: the in-window rooms
            --are all tiny in a small popout, so pick whichever side of the
            --OS window has more DESKTOP room, with the app's own screen
            --size as the best available desktop proxy. A wrong guess is
            --not fatal - the OS clamps child windows back onto the display.
            --Gated on placement-fixed engine builds: older ones return
            --mirrored distances and mirrored promotion offsets (the popout
            --canvas rect carries a -1 x scale).
            local geo = popoutHost.data.popoutGeometry
            local screenDim = dmhub.screenDimensions
            local screenX = geo ~= nil and geo.x or nil
            if screenX ~= nil and geo.width ~= nil and
                screenX > screenDim.x - (screenX + geo.width) then
                halign = "left"
            end
        else
            --x1/x2 = screen room to the left/right of the element.
            local distances = element.distancesToScreenEdge
            if distances ~= nil and distances.x2 < distances.x1 then
                halign = "left"
            end
        end

        element.tooltip = CreateTooltipPanel{
            text = text,
            halign = halign,
            valign = "center",
        }
    end
end

--============================================================================
--Delete tool helpers.
--
--The Delete tool is a hover-then-click interaction driven by map focus
--(maphover/mappress), not a stroke: moving over a wall highlights the single
--segment (edge) under the cursor, and a click erases just that edge. The
--engine's GetNearestWallSegment returns the nearest wall's WHOLE centerline
--path; we pick the nearest edge of that path ourselves so a click removes only
--the touched segment instead of the entire wall (which is what erasing the
--full path used to do - "deletes large swathes of wall").
--============================================================================

--The highlighted "about to delete" line, plus a key identifying its segment so
--the marker is only rebuilt when the target segment actually changes (maphover
--fires on every mouse move).
local m_deleteHighlight = nil
local m_deleteHighlightKey = nil
--The warn-once flag for engine builds lacking GetNearestWallSegment lives on
--m_mapScope (m_mapScope.deleteWarnedNoEngine) rather than in its own local:
--this file-level chunk is AT Lua's 200-local cap.

local function DistancePointToSegment(px, py, ax, ay, bx, by)
    local dx = bx - ax
    local dy = by - ay
    local lenSq = dx*dx + dy*dy
    local t = 0
    if lenSq > 0.00000001 then
        t = ((px - ax)*dx + (py - ay)*dy) / lenSq
        if t < 0 then t = 0 elseif t > 1 then t = 1 end
    end
    local cx = ax + t*dx
    local cy = ay + t*dy
    local ex = px - cx
    local ey = py - cy
    return math.sqrt(ex*ex + ey*ey)
end

--Returns { a = {x,y}, b = {x,y} } for the nearest invisible-wall edge to the
--cursor world point - or, when a markup DOOR's segment is nearer, that
--segment with its object in the `door` field - or nil if nothing is within
--reach / the point is off-map.
local function FindNearestDeleteSegment(point)
    if point == nil then
        return nil
    end
    local floor = game.currentFloor
    if floor == nil then
        return nil
    end

    --The maphover/mappress point is parallax-adjusted using the mouseover
    --floor's heightmap only, but walls render projected by the full surface
    --altitude (heightmap + elevation overlay + platforms). On ground raised or
    --lowered from 0 the two disagree, so the selection landed off the wall
    --under the cursor. editor.mouseEditSurfacePoint uses the same projection
    --as wall rendering; pcall so a stale engine build degrades to the event
    --point instead of erroring every mouse move.
    local okSurface, surfacePoint = pcall(function()
        return editor.mouseEditSurfacePoint
    end)
    if okSurface and surfacePoint ~= nil then
        point = surfacePoint
    end

    --pcall: maphover fires every frame, so a stale engine build (no
    --GetNearestWallSegment) must degrade quietly instead of erroring per move.
    --atMouse: engines that support it ignore x/y and match walls in projected
    --screen space against the actual cursor -- the only approach that stays
    --accurate on steep slopes, where a wall renders far from its stored
    --coordinates and any converted point comparison can exceed maxDistance.
    --Older engines ignore the flag and use x/y as before.
    local ok, seg = pcall(function()
        return floor:GetNearestWallSegment{
            x = point.x,
            y = point.y,
            atMouse = true,
            maxDistance = 0.7,
            invisibleOnly = true,
        }
    end)
    if not ok then
        if not m_mapScope.deleteWarnedNoEngine then
            m_mapScope.deleteWarnedNoEngine = true
            dmhub.Debug("MARKUP:: delete tool needs an engine build with GetNearestWallSegment support")
        end
        return nil
    end
    if seg == nil then
        return nil
    end

    --Engines with atMouse support hand back the nearest edge directly (matched
    --in projected screen space, so it is the edge visually under the cursor
    --even on steep slopes). Prefer it over re-deriving the edge here. The
    --wall's whole path rides along in `points` (interleaved x,y) for callers
    --that preview the full wall (the Apply Type hover).
    if seg.segment ~= nil and #seg.segment >= 4 then
        return {
            a = { x = seg.segment[1], y = seg.segment[2] },
            b = { x = seg.segment[3], y = seg.segment[4] },
            points = seg.points,
        }
    end

    local pts = seg.points
    if pts == nil or #pts < 4 then
        return nil
    end

    --Older engines: pts is an interleaved x,y list of the wall's whole path;
    --find the single edge (consecutive vertex pair) closest to the cursor.
    local bestDist = nil
    local best = nil
    for i = 1, #pts - 3, 2 do
        local ax, ay = pts[i], pts[i+1]
        local bx, by = pts[i+2], pts[i+3]
        local d = DistancePointToSegment(point.x, point.y, ax, ay, bx, by)
        if bestDist == nil or d < bestDist then
            bestDist = d
            best = { a = { x = ax, y = ay }, b = { x = bx, y = by }, points = pts }
        end
    end
    return best
end

--A hair-thin open-path erase EXACTLY along the wall centerline is unreliable on
--short segments: clipper's collinear-overlap handling (the ribbon sits right on
--the wall line) is numerically unstable -> "sometimes deletes nothing". So we
--erase a CLOSED box oriented along the segment: the wall centerline runs
--through the box INTERIOR (no collinear edge, so clipper is stable).
--
--DELETE_MIN_GAP guarantees the cut survives the engine's wall endpoint
--auto-merge (WallInfo.PointsCloseEnoughToMerge). That threshold used to be 0.3
--tiles - which forced MIN_GAP to 0.4 and made deleting one fine segment clear
--its neighbours too. The engine now welds only within 0.01, so the gap can be
--near-exact and a click removes just the touched segment.
--REQUIRES that engine build: against an older engine (0.3 weld) gaps this
--small heal straight back and deletion appears to do nothing.
local DELETE_MIN_GAP = 0.05      --min cleared length along the wall (> 0.01 merge threshold)
local DELETE_HALF_WIDTH = 0.05   --box half-width; keeps the centerline off the box edges
local DELETE_END_OVERSHOOT = 0.02 --push the cut just past a long segment's ends so both are removed

--Given a touched edge { a = {x,y}, b = {x,y} } returns:
--  a, b : the two axis endpoints of the cleared span (for the highlight preview)
--  box  : an interleaved-coord closed quad to feed ExecutePolygonOperation
local function DeleteSegmentGeometry(seg)
    local ax, ay = seg.a.x, seg.a.y
    local bx, by = seg.b.x, seg.b.y
    local dx, dy = bx - ax, by - ay
    local len = math.sqrt(dx*dx + dy*dy)
    if len < 0.0001 then
        --degenerate edge: clear an axis-aligned chunk around the point.
        dx, dy, len = 1, 0, 1
    end
    local ux, uy = dx/len, dy/len   --unit along the segment
    local nx, ny = -uy, ux          --unit perpendicular to it
    local mx, my = (ax + bx)*0.5, (ay + by)*0.5
    local halfLen = math.max(len*0.5 + DELETE_END_OVERSHOOT, DELETE_MIN_GAP*0.5)
    local hw = DELETE_HALF_WIDTH

    local e1x, e1y = mx + ux*halfLen, my + uy*halfLen
    local e2x, e2y = mx - ux*halfLen, my - uy*halfLen

    return {
        a = { x = e1x, y = e1y },
        b = { x = e2x, y = e2y },
        box = {
            e1x + nx*hw, e1y + ny*hw,
            e1x - nx*hw, e1y - ny*hw,
            e2x - nx*hw, e2y - ny*hw,
            e2x + nx*hw, e2y + ny*hw,
        },
    }
end

--m_deleteHighlight holds either one HighlightLine handle (Delete's single
--edge) or a plain list of them (Apply Type's whole-wall / marquee preview).
local function ClearDeleteHighlight()
    local h = m_deleteHighlight
    m_deleteHighlight = nil
    m_deleteHighlightKey = nil
    if h == nil then
        return
    end
    if type(h) == "table" then
        for _,line in ipairs(h) do
            line:Destroy()
        end
    else
        h:Destroy()
    end
end

--Also used by the Apply Type (retype) tool, which tints the highlight the
--target type's color instead of the delete red.
local function ShowDeleteHighlight(seg, color)
    color = color or "#ff4d4d"
    local key = string.format("%.4f,%.4f,%.4f,%.4f,%s", seg.a.x, seg.a.y, seg.b.x, seg.b.y, color)
    if key == m_deleteHighlightKey and m_deleteHighlight ~= nil then
        return
    end
    ClearDeleteHighlight()
    --terrainParallax: the wall skeleton parallax-shifts with the camera + terrain
    --height every frame, so a flat (z=0) line drifts off the wall wherever the
    --map has parallax. This projects the highlight with the same parallax.
    m_deleteHighlight = dmhub.HighlightLine{
        color = color,
        a = core.Vector2(seg.a.x, seg.a.y),
        b = core.Vector2(seg.b.x, seg.b.y),
        floorIndex = game.currentFloorIndex,
        terrainParallax = true,
    }
    m_deleteHighlightKey = key
end

--Multi-line variant for the Apply Type tool: one highlight line per edge in
--a flat interleaved {ax,ay,bx,by, ...} list (the whole hovered wall on
--hover; the captured edges during a marquee drag). Shares the delete
--highlight's storage, so the two previews never stack. A field on
--m_mapScope rather than a new file-level local: this chunk is AT Lua's
--200-local cap.
m_mapScope.ShowSegmentsHighlight = function(segments, color)
    if segments == nil or #segments < 4 then
        ClearDeleteHighlight()
        return
    end
    local parts = { color }
    for i = 1, #segments do
        parts[#parts+1] = string.format("%.3f", segments[i])
    end
    local key = table.concat(parts, ",")
    if key == m_deleteHighlightKey and m_deleteHighlight ~= nil then
        return
    end
    ClearDeleteHighlight()
    local lines = {}
    for i = 1, #segments - 3, 4 do
        lines[#lines+1] = dmhub.HighlightLine{
            color = color,
            a = core.Vector2(segments[i], segments[i+1]),
            b = core.Vector2(segments[i+2], segments[i+3]),
            floorIndex = game.currentFloorIndex,
            terrainParallax = true,
        }
    end
    m_deleteHighlight = lines
    m_deleteHighlightKey = key
end

local CreateMarkupEditor

DockablePanel.Register{
    name = "Map Markup",
    icon = "icons/standard/Icon_App_Whiteboard.png",
    vscroll = true,
    dmonly = true,
    minHeight = 200,
    folder = "Map Editing",
    stickyFocus = true,
    --a press anywhere on the panel -- its background, its title bar --
    --arms it, not just its individual tool controls.
    focusOnClick = true,
    content = function()
        track("panel_open", {
            panel = "Map Markup",
            dailyLimit = 30,
        })
        return CreateMarkupEditor()
    end,
}

CreateMarkupEditor = function()
    local contentPanel
    local palettePanel
    --forward-declared: the draw-mode toggle rebuilds the tool strip and
    --relabels the height stepper, so it must close over both. SetDrawMode is
    --forward-declared because SelectChip forces thin mode for openable types.
    local toolsPanel
    local drawModePanel
    local heightPanel
    local SelectChip
    local AddPaletteEntry
    local RemovePaletteEntry
    local SetDrawMode
    --Every drawing path in this panel is focus-gated (see the tool-strip think
    --handlers): the engine building tools only draw while our focus-gated wall
    --selection is published, and the custom map tools are re-registered from a
    --0.3s think that bails without panel focus. So ANY press that changes what
    --would be drawn must also take focus and re-register immediately, or the
    --click after it silently does nothing. Forward-declared because it closes
    --over the per-mode tool panels, which are declared further down.
    local TakeMarkupFocus

    --Small uppercase section header used by every mode's sections, quieter
    --than the selectable content beneath it.
    local SectionHeader = function(text)
        return gui.Label{
            classes = {"markupSectionHeader"},
            text = text,
            uppercase = true,
            width = "96%",
            height = "auto",
            halign = "center",
            vmargin = 4,
        }
    end

    m_paletteEntries = ParsePalette()
    if m_selectedIndex ~= nil and m_selectedIndex > #m_paletteEntries then
        m_selectedIndex = nil
    end
    if m_selectedIndex == nil and #m_paletteEntries > 0 then
        m_selectedIndex = 1
    end

    --Each mode's default drawing tool is its first: the rectangle, in both.
    --Solid mode's tools are custom map tools, so it leaves the shared
    --building-tool settings alone. Openable (door) types are thin-only.
    if m_solidMode and EntryIsOpenable(m_paletteEntries[m_selectedIndex or 0]) then
        m_solidMode = false
    end
    if m_solidMode then
        m_toolId = "solidrect"
    else
        m_toolId = "rectangle"
        dmhub.SetSettingValue("buildingtool", "rectangle")
        dmhub.SetSettingValue("building:erase", false)
    end

    --Materializes the wall asset behind a preset entry if needed, returning
    --the asset guid or nil.
    local MaterializeEntry = function(entry)
        if entry.guid ~= nil and assets.walls[entry.guid] ~= nil then
            return entry.guid
        end

        local preset = PresetForEntry(entry)
        if preset == nil then
            return nil
        end

        local guid = CreateMarkupWallAsset(preset.name, preset.fields)
        if guid == nil then
            return nil
        end

        entry.guid = guid
        SavePalette(m_paletteEntries)
        return guid
    end

    --Wall colors: 8 distinct colors, drawn as a tiny 4x2 swatch grid ON each
    --palette chip (left of the line preview - see CreateWallChip). The color
    --lives on the wall ASSET (WallAsset.markupColor, engine build required),
    --so every wall of that type on the map - thin skeleton lines and
    --solid-block striping alike - draws in it, on every client. One table
    --rather than several locals: this function is already large and locals
    --are capped at 200 per function.
    local m_wallColor
    m_wallColor = {
        --The first swatch is the engine's stock skeleton grey and CLEARS the
        --stored color instead of writing one, so "no color" stays the
        --engine-default styling rather than pinning a lookalike grey.
        COLORS = {
            { name = "Default", color = "#d9d9d9", default = true },
            { name = "Red", color = "#e5484d" },
            { name = "Orange", color = "#f76b15" },
            { name = "Yellow", color = "#ffc53d" },
            { name = "Green", color = "#46a758" },
            { name = "Cyan", color = "#00a2c7" },
            { name = "Blue", color = "#3e63dd" },
            { name = "Purple", color = "#ab4aba" },
        },

        --Engine gate, same probe recipe as OpenableWallsSupported: reading an
        --unknown property on engine userdata silently returns nil, so check
        --the VALUE. A supporting build returns a string - deliberately ""
        --rather than nil when unset, exactly so this probe works.
        supportCache = nil,
        Supported = function()
            if m_wallColor.supportCache ~= nil then
                return m_wallColor.supportCache
            end
            local probe = assets.walls[BASE_INVISIBLE_WALL_ID]
            if probe == nil then
                for _,wall in pairs(assets.walls) do
                    probe = wall
                    break
                end
            end
            if probe == nil then
                --no wall assets at all; leave undecided so we re-probe later.
                return false
            end
            local value = nil
            pcall(function()
                value = probe.markupColor
            end)
            m_wallColor.supportCache = (value ~= nil)
            return m_wallColor.supportCache
        end,

        --the type's stored color ("#rrggbb"), or nil for unset/unmaterialized
        --entries and pre-color engine builds.
        EntryColor = function(entry)
            local asset = EntryWallAsset(entry)
            if asset == nil then
                return nil
            end
            local result = nil
            pcall(function()
                local c = asset.markupColor
                if type(c) == "string" and c ~= "" then
                    result = c
                end
            end)
            return result
        end,

        --writes the chosen swatch onto the entry's wall asset, materializing
        --a preset chip first exactly like selecting it does. Upload syncs the
        --asset, which recolors the type's walls on every client.
        SetEntryColor = function(entry, colorInfo)
            local guid = MaterializeEntry(entry)
            if guid == nil then
                return
            end
            local wall = assets.walls[guid]
            if wall == nil then
                return
            end
            local ok = pcall(function()
                if colorInfo.default then
                    wall.markupColor = ""
                else
                    wall.markupColor = colorInfo.color
                end
            end)
            if ok then
                wall:Upload()
            end
        end,
    }

    SelectChip = function(index)
        local entry = m_paletteEntries[index]
        if entry == nil then
            return
        end

        m_selectedIndex = index

        local preset = PresetForEntry(entry)
        if preset ~= nil then
            MaterializeEntry(entry)
            SetWallHeightSetting(preset.height)
        end

        --Picking a wall type means "I want to draw this", so the destructive
        --tools don't stay armed on the new type: Eraser / Delete Wall fall
        --back to the active strip's default drawing tool (the rectangle).
        --Deliberately only for those two - a drawing tool the user chose is
        --their choice and survives changing type.
        local rearmedTool = nil
        if m_toolId == "erase" or m_toolId == "delete" then
            local defaultTool = ActiveToolInfos()[1]
            m_toolId = defaultTool.id
            rearmedTool = defaultTool
            --settings first: refreshtools reads buildingtool back to decide
            --which engine drawing tool shows selected.
            if defaultTool.tool ~= nil then
                dmhub.SetSettingValue("building:erase", false)
                dmhub.SetSettingValue("buildingtool", defaultTool.tool)
            end
            if toolsPanel ~= nil and toolsPanel.valid then
                toolsPanel:FireEvent("refreshtools")
            end
        end

        if palettePanel ~= nil and palettePanel.valid then
            palettePanel:FireEvent("refreshchips")
            --focus + immediate tool registration: in solid mode the tools are
            --custom map tools that only exist while we have focus.
            TakeMarkupFocus()
        end

        --Openable (door) types draw thin walls only: force thin mode so the
        --strokes are real wall operations the engine can attach door state
        --to. SetDrawMode also rebuilds the tool strip and pushes the shared
        --building-tool setting.
        if m_solidMode and EntryIsOpenable(entry) then
            SetDrawMode(false)
        end

        --(A focus steal used to matter here: rearming a thin drawing tool
        --writes the shared building-tool setting, the Building editor's
        --palette re-presses its own chip on the next monitor poll, and the
        --focus TakeMarkupFocus had just taken went with it -- disarming the
        --panel. Arming is explicit now and survives that entirely, so the
        --re-grab is gone.)

        --the selection can flip between openable and plain types, which
        --hides/shows the Draw As toggle. The Wall Color swatches follow the
        --selected type too.
        if contentPanel ~= nil and contentPanel.valid then
            contentPanel:FireEventTree("refreshdoorchip")
            contentPanel:FireEventTree("refreshwallcolors")
        end
    end

    AddPaletteEntry = function(entry)
        m_paletteEntries[#m_paletteEntries+1] = entry
        m_selectedIndex = #m_paletteEntries
        SavePalette(m_paletteEntries)
        SelectChip(m_selectedIndex)
    end

    RemovePaletteEntry = function(index)
        local removed = m_paletteEntries[index]
        if removed == nil then
            return
        end

        table.remove(m_paletteEntries, index)
        if m_selectedIndex ~= nil then
            if m_selectedIndex == index then
                m_selectedIndex = nil
            elseif m_selectedIndex > index then
                m_selectedIndex = m_selectedIndex - 1
            end
        end
        SavePalette(m_paletteEntries)

        --a map-private type with no walls drawn is orphaned once its chip is
        --gone: delete the asset rather than stranding it in the library.
        if removed.guid ~= nil then
            m_mapScope.DeleteWallIfOrphaned(removed.guid, m_paletteEntries)
        end
    end

    local CreateChipContextMenuItems = function(element, index)
        local entry = m_paletteEntries[index]
        local result = {}

        --library ("wall") chips were deliberately not editable while editing
        --meant mutating the shared asset under other maps; with the scoping
        --engine build, editing a shared wall forks it instead (see
        --ShowMarkupWallDialog), so they become safely editable too.
        local editableKind = entry ~= nil and (entry.kind == "preset" or entry.kind == "solid" or entry.kind == "custom"
            or (entry.kind == "wall" and m_mapScope.WallSupported()))

        if editableKind and entry.guid ~= nil and assets.walls[entry.guid] ~= nil then
            result[#result+1] = {
                text = "Edit Wall...",
                click = function()
                    element.popup = nil
                    ShowMarkupWallDialog(entry.guid, element)
                end,
            }
        end

        result[#result+1] = {
            text = "Remove from Palette",
            click = function()
                element.popup = nil
                RemovePaletteEntry(index)
            end,
        }

        return result
    end

    --A palette row: the name over a one-line summary, then a fixed-width
    --preview of the line the wall draws on the map at the right; one row per
    --type. Text leads because the name is what the user scans for; the
    --preview shows the wall's own behavior (blocks / one-way), which is the
    --same whether it is drawn thin or solid, so it does not vary with the
    --draw mode.
    local CreateWallChip = function(index, entry)
        --the preview line draws in the type's markup color, matching the
        --skeleton the engine draws on the map. nil = the stock grey.
        local wallColor = m_wallColor.EntryColor(entry)

        --the color control rides ON the chip: one larger square showing the
        --type's current color, to the left of the line preview (which
        --narrows to make room). Clicking it pops out the full 4x2 palette
        --to choose from. Engine-gated: on builds without
        --WallAsset.markupColor no square is built and the chip keeps its
        --original full-width layout.
        local colorSwatch = nil
        if m_wallColor.Supported() then
            --the popout: the 4x2 swatch grid the chip used to carry inline.
            --Rebuilt on every open so the ring always marks the type's
            --current color. anchor is the square the popup hangs off.
            local CreatePalettePopout = function(anchor)
                local current = m_wallColor.EntryColor(m_paletteEntries[index])
                local gridRows = {}
                for rowIndex = 0,1 do
                    local swatches = {}
                    for col = 1,4 do
                        local colorInfo = m_wallColor.COLORS[rowIndex*4 + col]
                        --ring the type's current color; Default is lit when
                        --the type has none stored.
                        local selected
                        if current == nil then
                            selected = colorInfo.default == true
                        else
                            selected = (not colorInfo.default) and string.lower(current) == colorInfo.color
                        end
                        swatches[#swatches+1] = gui.Panel{
                            classes = {"markupColorSwatch", cond(selected, "selected")},
                            bgimage = true,
                            bgcolor = colorInfo.color,
                            width = 20,
                            height = 20,
                            borderBox = true,
                            hmargin = 2,
                            vmargin = 2,

                            data = {
                                colorInfo = colorInfo,
                            },

                            press = function(element)
                                anchor.popup = nil
                                local chipEntry = m_paletteEntries[index]
                                if chipEntry == nil then
                                    return
                                end
                                m_wallColor.SetEntryColor(chipEntry, element.data.colorInfo)
                                --picking a color is also picking the type:
                                --select the chip like any press on the row
                                --(this also takes markup focus and fires
                                --refreshwallcolors tree-wide, updating the
                                --squares before the asset-driven rebuild).
                                SelectChip(index)
                            end,
                        }
                    end
                    gridRows[#gridRows+1] = gui.Panel{
                        width = "auto",
                        height = "auto",
                        flow = "horizontal",
                        halign = "center",
                        children = swatches,
                    }
                end
                --popups render in the overlay layer with no style cascade of
                --their own, so re-attach the panel styles explicitly.
                return gui.Panel{
                    styles = GetPanelStyles(),
                    classes = {"framedPanel"},
                    --2 rows / 4 cols of 24px cells (20px swatch + 2px
                    --margins) plus 8px padding each side.
                    width = 112,
                    height = 64,
                    flow = "vertical",
                    pad = 8,
                    borderBox = true,
                    children = gridRows,
                }
            end

            colorSwatch = gui.Panel{
                classes = {"markupColorSwatch"},
                bgimage = true,
                --a single 24px square exactly fills the chip's content
                --height (36 minus 6px borderBox padding each side).
                width = 24,
                height = 24,
                borderBox = true,
                hmargin = 2,
                valign = "center",
                popupPositioning = "panel",

                --presses bubble to ancestors by default, so without this the
                --chip's own press ran too and SELECTED the type - and
                --selecting an unmaterialized preset creates + uploads its wall
                --asset and rewrites the palette setting. Those writes come
                --back as a monitor, the palette rebuilds, and the popout we
                --just opened dies with the square that owns it. Opening the
                --color picker is not "I want to draw this" anyway; picking a
                --color from it selects the type explicitly (see below).
                swallowPress = true,

                events = {
                    create = function(element)
                        element:FireEvent("refreshwallcolors")
                    end,

                    --show the type's current color; Default shows the stock
                    --grey when the type has none stored.
                    refreshwallcolors = function(element)
                        local current = m_wallColor.EntryColor(m_paletteEntries[index])
                        element.selfStyle.bgcolor = current or m_wallColor.COLORS[1].color
                    end,

                    press = function(element)
                        if element.popup ~= nil then
                            element.popup = nil
                            return
                        end
                        element.popup = CreatePalettePopout(element)
                    end,
                },
            }
        end

        local previewWidth = cond(colorSwatch ~= nil, 70, 100)
        local preview
        if EntryIsOpenable(entry) then
            preview = CreateDoorLinePreview(wallColor)
        else
            preview = CreateWallLinePreview(EntryFields(entry), wallColor, colorSwatch ~= nil)
        end

        --Summaries follow a "<behavior> - <cover/extra>" grammar. Rendered as
        --one string the separator lands wherever the first clause ends, which
        --looks ragged stacked in a list - so split at the first " - " and lay
        --the clauses out as two fixed columns; the second clause then starts
        --at the same x on every row and needs no separator at all.
        local summaryA, summaryB = string.match(SummarizeEntry(entry), "^(.-) %- (.*)$")
        if summaryA == nil then
            summaryA = SummarizeEntry(entry)
        end
        local summaryPanel
        if summaryB == nil then
            summaryPanel = gui.Label{
                classes = {"fgMuted", "sizeXs"},
                text = summaryA,
                width = "100%",
                height = "auto",
            }
        else
            summaryPanel = gui.Panel{
                width = "100%",
                height = "auto",
                flow = "horizontal",

                gui.Label{
                    classes = {"fgMuted", "sizeXs"},
                    text = summaryA,
                    width = 76,
                    height = "auto",
                },

                gui.Label{
                    classes = {"fgMuted", "sizeXs"},
                    text = summaryB,
                    width = "100%-76",
                    height = "auto",
                },
            }
        end
        return gui.Panel{
            classes = {"markupChip", cond(index == m_selectedIndex, "selected")},
            --palettePanel is already the panel's 96% content column, so rows
            --fill it entirely; the Add Wall Type row below is a sibling OF
            --that column at 96% itself, and the two must end up equally wide.
            width = "100%",
            height = 36,
            halign = "center",
            flow = "horizontal",
            bgimage = true,
            pad = 6,
            borderBox = true,
            vmargin = 1,

            data = {
                index = index,
            },

            press = function(element)
                SelectChip(element.data.index)
            end,

            rightClick = function(element)
                element.popup = gui.ContextMenu{
                    entries = CreateChipContextMenuItems(element, element.data.index),
                }
            end,

            gui.Panel{
                --the color square + narrowed preview together take the same
                --room the full-width preview did, less the 2px saved by the
                --square being narrower than the old inline grid.
                width = cond(colorSwatch ~= nil, "100%-108", "100%-110"),
                height = "auto",
                valign = "center",
                flow = "vertical",
                hmargin = 4,

                gui.Label{
                    classes = {"bold"},
                    text = EntryDisplayName(entry),
                    width = "100%",
                    height = "auto",
                },

                summaryPanel,
            },

            --square + preview assembled via a children list: colorSwatch is
            --nil on non-supporting engines, and a nil POSITIONAL child would
            --leave a constructor hole that ends ipairs and drops the preview.
            gui.Panel{
                width = cond(colorSwatch ~= nil, 98, 100),
                height = "auto",
                valign = "center",
                flow = "horizontal",
                children = (function()
                    local kids = {}
                    kids[#kids+1] = colorSwatch
                    kids[#kids+1] = gui.Panel{
                        width = previewWidth,
                        height = "auto",
                        valign = "center",
                        flow = "horizontal",
                        preview,
                    }
                    return kids
                end)(),
            },
        }
    end

    --Horizontal strip of mode tabs across the top of the panel.
    local modeTabs = gui.Panel{
        classes = {"tabBar"},
        width = "98%",
        height = 26,
        halign = "center",
        vmargin = 4,
        flow = "horizontal",
        children = (function()
            local result = {}
            for _,modeInfo in ipairs(MODES) do
                result[#result+1] = gui.Label{
                    classes = {"tab", cond(modeInfo.id == m_mode, "selected")},
                    text = modeInfo.text,
                    --The theme's tab sizing (130x40 / 18pt) is for full-width
                    --tab strips; five tabs must fit in the dock width.
                    width = "20%",
                    height = "100%",
                    fontSize = 13,
                    hpad = 0,
                    data = {
                        modeid = modeInfo.id,
                        modetext = modeInfo.text,
                    },
                    press = function(element)
                        m_mode = element.data.modeid
                        for _,tab in ipairs(element.parent.children) do
                            tab:SetClass("selected", tab.data.modeid == m_mode)
                        end
                        element.parent:FireEventTree("refreshtab")
                        contentPanel:FireEventTree("markupmode")
                        --arm the new mode's tool right away: switching tabs is
                        --a deliberate "I want to draw this" click.
                        TakeMarkupFocus()
                    end,

                    --Armed-state dot on the active tab: bright while the panel
                    --holds GUI focus (every drawing path is focus-gated, so
                    --focus IS "clicks on the map will draw"), dim otherwise.
                    --Driven by contentPanel's childfocus/childdefocus, which
                    --already fire to highlight the dock title.
                    gui.Panel{
                        classes = {"markupStateDot", cond(modeInfo.id ~= m_mode, "hidden")},
                        floating = true,
                        bgimage = "game-icons/plain-circle.png",
                        width = 6,
                        height = 6,
                        halign = "right",
                        valign = "center",
                        hmargin = 5,

                        refreshtab = function(element)
                            element:SetClass("hidden", element.parent.data.modeid ~= m_mode)
                        end,

                        markuparmed = function(element, armed)
                            element:SetClass("armed", armed)
                        end,
                    },
                }
            end
            return result
        end)(),
    }

    --the rebuild proper, split out so refreshpalette can hand it to
    --RebuildDeferringPopups and have it replayed later if a popup is open.
    local RebuildPalette = function(element)
        m_paletteEntries = ParsePalette()
        if m_selectedIndex ~= nil and m_selectedIndex > #m_paletteEntries then
            m_selectedIndex = nil
        end

        local children = {}
        for i,entry in ipairs(m_paletteEntries) do
            children[#children+1] = CreateWallChip(i, entry)
        end
        element.children = children

        --the selected chip can have become openable (Edit Wall on it,
        --or a remote change); openable types are thin-only.
        if m_solidMode and EntryIsOpenable(m_paletteEntries[m_selectedIndex or 0]) and SetDrawMode ~= nil then
            SetDrawMode(false)
        end

        --the selection (and with it the thin-vs-solid tool strip) can
        --change with the palette contents.
        if toolsPanel ~= nil and toolsPanel.valid then
            toolsPanel:FireEvent("rebuildtools")
        end
        if contentPanel ~= nil and contentPanel.valid then
            contentPanel:FireEventTree("refreshdoorchip")
            --a palette change can change which type is selected (and a
            --remote edit can change its color) - resync the swatches.
            contentPanel:FireEventTree("refreshwallcolors")
        end
    end

    palettePanel = gui.Panel{
        width = "96%",
        height = "auto",
        halign = "center",
        flow = "vertical",

        monitorAssets = "Tilesheet",
        multimonitor = {"markup:wallpalette"},

        --gui.RebuildDeferringPopups parks a stood-down rebuild in here.
        data = {},

        events = {
            think = gui.ThinkDeferredRebuild,

            --the palette setting changed: our own write, another DM's, or a
            --map switch changing the effective value.
            monitor = function(element)
                element:FireEvent("refreshpalette")
            end,

            refreshAssets = function(element)
                element:FireEvent("refreshpalette")
            end,

            --replaces every chip, taking any open color popout or chip
            --context menu down with it - so it waits its turn.
            refreshpalette = function(element)
                gui.RebuildDeferringPopups(element, RebuildPalette)
            end,

            refreshchips = function(element)
                for _,chip in ipairs(element.children) do
                    chip:SetClass("selected", chip.data.index == m_selectedIndex)
                end
            end,
        },
    }

    --Styled as one more palette row (full width, chip border) so the list
    --reads as a single column ending in its add action, not a separate button.
    local addButton
    addButton = gui.Panel{
        classes = {"markupChip"},
        width = "96%",
        height = 28,
        halign = "center",
        bgimage = true,
        borderBox = true,
        vmargin = 2,

        gui.Label{
            classes = {"fgMuted"},
            text = "+ Add Wall Type",
            fontSize = 14,
            width = "auto",
            height = "auto",
            halign = "center",
            valign = "center",
        },

        events = {
            press = function(element)
                local entries = {}

                for _,preset in ipairs(WALL_PRESETS) do
                    local inPalette = false
                    for _,entry in ipairs(m_paletteEntries) do
                        if entry.kind == "preset" and entry.key == preset.key then
                            inPalette = true
                            break
                        end
                    end

                    if not inPalette then
                        entries[#entries+1] = {
                            text = preset.name,
                            click = function()
                                element.popup = nil
                                AddPaletteEntry{
                                    kind = "preset",
                                    key = preset.key,
                                }
                            end,
                        }
                    end
                end

                entries[#entries+1] = {
                    text = "Door (Openable)",
                    click = function()
                        element.popup = nil
                        --openable lives on the wall asset, which needs the
                        --engine build; refuse with a message rather than
                        --quietly adding a plain wall.
                        if not OpenableWallsSupported() then
                            gui.ModalMessage{
                                owner = element,
                                title = "Door (Openable)",
                                message = "Openable walls need an engine build with door support.",
                            }
                            return
                        end
                        local guid = CreateMarkupWallAsset("Door", DOOR_TYPE_FIELDS)
                        if guid ~= nil then
                            AddPaletteEntry{
                                kind = "custom",
                                guid = guid,
                            }
                        end
                    end,
                }

                entries[#entries+1] = {
                    text = "Other Invisible Walls...",
                    click = function()
                        element.popup = nil
                        element:FireEvent("showlibrary")
                    end,
                }

                entries[#entries+1] = {
                    text = "Custom...",
                    click = function()
                        element.popup = nil
                        local guid = CreateMarkupWallAsset("Custom Markup Wall", WALL_PRESETS_BY_KEY["stone"].fields)
                        if guid ~= nil then
                            AddPaletteEntry{
                                kind = "custom",
                                guid = guid,
                            }
                            ShowMarkupWallDialog(guid, element)
                        end
                    end,
                }

                element.popup = gui.ContextMenu{
                    entries = entries,
                }
            end,

            showlibrary = function(element)
                --closes via the captured layer; shown owner-routed so a
                --popped-out Map Markup gets the dialog in its own window.
                local modalLayer = nil
                --Markup is invisible-walls-only: visible art walls belong to
                --the Building editor. Also skip walls already in the palette.
                local paletteGuids = {}
                for _,entry in ipairs(m_paletteEntries) do
                    if entry.guid ~= nil then
                        paletteGuids[entry.guid] = true
                    end
                end

                local sortedWalls = {}
                for id,wall in pairs(assets.walls) do
                    --wall types private to other maps never appear here.
                    if (not wall.hidden) and wall.invisible == true and (not paletteGuids[id]) and m_mapScope.WallAvailableOnThisMap(wall) then
                        sortedWalls[#sortedWalls+1] = {
                            id = id,
                            wall = wall,
                        }
                    end
                end
                table.sort(sortedWalls, function(a, b)
                    local aname = a.wall.description or a.id
                    local bname = b.wall.description or b.id
                    return aname < bname or (aname == bname and a.id < b.id)
                end)

                local rows = {}
                for _,info in ipairs(sortedWalls) do
                    rows[#rows+1] = gui.Panel{
                        classes = {"markupChip"},
                        width = "96%",
                        height = 32,
                        halign = "center",
                        flow = "horizontal",
                        bgimage = true,
                        pad = 4,
                        borderBox = true,
                        vmargin = 1,

                        data = {
                            wallid = info.id,
                        },

                        press = function(rowElement)
                            AddPaletteEntry{
                                kind = "wall",
                                guid = rowElement.data.wallid,
                            }
                            gui.CloseModalInLayer(modalLayer)
                        end,

                        gui.Panel{
                            width = 110,
                            height = "100%",
                            valign = "center",
                            flow = "horizontal",
                            CreateWallLinePreview(AssetFields(info.wall)),
                        },

                        gui.Label{
                            text = info.wall.description or info.id,
                            width = "auto",
                            height = "auto",
                            hmargin = 8,
                            valign = "center",
                        },
                    }
                end

                if #rows == 0 then
                    rows[#rows+1] = gui.Label{
                        classes = {"fgMuted"},
                        text = "No other invisible wall types in this game.",
                        width = "90%",
                        height = "auto",
                        halign = "center",
                        vmargin = 12,
                        textAlignment = "center",
                    }
                end

                local dialogPanel = gui.Panel{
                    id = "MarkupWallLibraryDialog",
                    classes = {"framedPanel"},
                    --clamped to the modal layer: full design size in the
                    --main window, shrink-to-fit inside a small popout.
                    width = "94%",
                    maxWidth = 440,
                    height = "92%",
                    maxHeight = 620,
                    pad = 16,
                    borderBox = true,
                    flow = "vertical",
                    styles = ThemeEngine.MergeStyles{
                        Styles.Panel,
                        MarkupChipStyles(),
                    },

                    gui.Label{
                        classes = {"dialogTitle"},
                        text = "Add Invisible Wall",
                    },

                    gui.Panel{
                        width = "100%",
                        height = "100%-100",
                        vscroll = true,
                        flow = "vertical",
                        children = rows,
                    },

                    gui.Button{
                        classes = {"sizeM"},
                        text = "Cancel",
                        halign = "center",
                        valign = "bottom",
                        vmargin = 8,
                        captureEscape = true,
                        escapePriority = EscapePriority.EXIT_DIALOG,
                        events = {
                            click = function(buttonElement)
                                buttonElement:FireEvent("escape")
                            end,
                            escape = function()
                                gui.CloseModalInLayer(modalLayer)
                            end,
                        },
                    },
                }

                modalLayer = gui.ShowModal(dialogPanel, {owner = element})
            end,
        },
    }

    --Tool selection strip: icon buttons in the same style the settings
    --system's iconbuttons editor uses (SettingsGui.lua). Thin-wall drawing
    --tools write the shared engine building-tool settings; solid drawing
    --tools, erase and delete run as custom map tools kept alive by this
    --panel's think loop, with their strokes coming back as 'tool' events.
    --The strip's buttons are rebuilt when the selected chip flips between
    --thin and solid (rebuildtools).
    --Each tool is an icon-over-caption chip; the destructive pair (erase /
    --delete) sits behind a divider and is tinted @danger, so a misclick
    --cannot silently turn a drawing gesture into a removal.
    local BuildToolButtons = function()
        local result = {}
        local dividerAdded = false
        for _,toolInfo in ipairs(ActiveToolInfos()) do
            local destructive = toolInfo.id == "erase" or toolInfo.id == "delete"
            if destructive and not dividerAdded then
                dividerAdded = true
                result[#result+1] = gui.Panel{
                    classes = {"markupToolDivider"},
                    bgimage = true,
                    width = 1,
                    height = "70%",
                    valign = "center",
                    hmargin = 4,
                    --refreshtools iterates children by data.toolid; give the
                    --divider an empty data table so it reads as "no tool".
                    data = {},
                }
            end

            local chipClasses = {"markupToolChip"}
            if toolInfo.id == m_toolId then
                chipClasses[#chipClasses+1] = "selected"
            end
            if destructive then
                chipClasses[#chipClasses+1] = "danger"
            end

            result[#result+1] = gui.Panel{
                classes = chipClasses,
                width = 44,
                height = 42,
                flow = "vertical",
                bgimage = true,
                borderBox = true,
                valign = "center",
                hmargin = 1,
                hover = SideTooltip(toolInfo.help),
                data = {
                    toolid = toolInfo.id,
                    tool = toolInfo.tool,
                },
                press = function(element)
                    --Pressing a tool ALWAYS arms it, including the one
                    --already live. Deliberately not a toggle: a button that
                    --disarms on its second press makes pressing your current
                    --tool a coin flip between "keep drawing" and "stop", and
                    --a mis-aimed re-press silently puts the panel down.
                    --Escape is the way out.
                    m_toolId = element.data.toolid
                    if element.data.tool ~= nil then
                        dmhub.SetSettingValue("building:erase", false)
                        dmhub.SetSettingValue("buildingtool", element.data.tool)
                    end
                    toolsPanel:FireEvent("refreshtools")
                    --ARM. This is the whole state now: it survives whatever
                    --happens to focus afterwards, so the Building editor's
                    --palette stealing focus a frame later (the reason
                    --ReassertMarkupFocus existed) no longer stops drawing.
                    m_arm.Set(true)
                    --Focus is still taken, but only so the panel keeps its
                    --keyboard routing -- it no longer decides anything. Still
                    --on contentPanel rather than this button: the strip is
                    --rebuilt wholesale by rebuildtools and focus parked on a
                    --destroyed button goes nil.
                    TakeMarkupFocus()
                end,

                gui.Panel{
                    classes = {"markupToolIcon", cond(destructive, "danger")},
                    bgimage = toolInfo.icon,
                    width = 18,
                    height = 18,
                    halign = "center",
                    vmargin = 3,
                },

                gui.Label{
                    classes = {"markupToolLabel", cond(destructive, "danger")},
                    text = toolInfo.text or "",
                    width = "100%",
                    height = "auto",
                    textAlignment = "center",
                },
            }
        end
        return result
    end

    toolsPanel = gui.Panel{
        width = "96%",
        height = 48,
        halign = "center",
        flow = "horizontal",

        multimonitor = {"buildingtool", "building:erase"},

        --keep the custom map tool alive while erase/delete is active. The
        --engine expires custom tools after ~1s, so this must re-register
        --faster than that; each registration returns a fresh event source
        --that has to be listened to again.
        thinkTime = 0.3,

        events = {
            monitor = function(element)
                element:FireEvent("refreshtools")
            end,

            refreshtools = function(element)
                --custom map tools (erase, delete, the solid shape tools) are
                --owned by this panel outright; engine drawing tools reflect
                --the shared building-tool settings, so if the Building editor
                --switched the shape (or turned its erase checkbox on) no
                --markup chip shows selected.
                local tools = ActiveToolInfos()
                local activeInfo = nil
                for _,toolInfo in ipairs(tools) do
                    if toolInfo.id == m_toolId then
                        activeInfo = toolInfo
                    end
                end

                local activeid = m_toolId
                if activeInfo == nil or activeInfo.mapTool == nil then
                    activeid = nil
                    if not dmhub.GetSettingValue("building:erase") then
                        local tool = dmhub.GetSettingValue("buildingtool")
                        for _,toolInfo in ipairs(tools) do
                            if toolInfo.tool == tool then
                                activeid = toolInfo.id
                            end
                        end
                    end
                end

                --A tool lights ONLY while the panel is armed. Disarmed, the
                --whole strip goes dark: "nothing here is live right now" is
                --the thing the user could not tell before, and showing a lit
                --tool that does nothing when you click the map is precisely
                --the lie this rework is removing. Pressing any tool (the same
                --one included) arms it again.
                local armed = m_arm.Armed()
                for _,child in ipairs(element.children) do
                    child:SetClass("selected", armed and child.data.toolid == activeid)
                end
            end,

            --the selected chip flipped between thin and solid (or the palette
            --changed under us): swap the button set for the matching tool
            --strip. If the active tool doesn't exist in the new strip, fall
            --back to its default drawing tool - without touching the shared
            --building-tool settings, since this can fire from a remote
            --palette change while the Building editor is in use.
            rebuildtools = function(element)
                local tools = ActiveToolInfos()

                local validTool = false
                for _,toolInfo in ipairs(tools) do
                    if toolInfo.id == m_toolId then
                        validTool = true
                    end
                end

                if not validTool then
                    --carry the equivalent shape across the mode switch (rect stays
                    --rect, polygon stays polygon) so only the strip changes, not the
                    --user's choice; otherwise fall back to the first tool.
                    local outgoing = FindToolInfo(m_toolId)
                    local wantShape = nil
                    if outgoing ~= nil then
                        wantShape = outgoing.shape
                    end

                    m_toolId = nil
                    if wantShape ~= nil then
                        for _,toolInfo in ipairs(tools) do
                            if toolInfo.shape == wantShape then
                                m_toolId = toolInfo.id
                            end
                        end
                    end
                    if m_toolId == nil then
                        m_toolId = tools[1].id
                    end
                end

                element.children = BuildToolButtons()
                element:FireEvent("refreshtools")
            end,

            think = function(element)
                --The Delete and Apply Type (retype) tools take map focus so
                --they get maphover/mappress (hover-highlight + click-on-one-
                --segment). Own map focus only while one of them is the active
                --markup tool and this panel is focused; release it and drop
                --any highlight otherwise. Gating on focus keeps us from
                --stealing map focus from ability targeting etc. This runs
                --before the m_mode guard so switching mode/tool tears the
                --overlay down promptly.
                local wantDelete = m_mode == "walls"
                    and (m_toolId == "delete" or m_toolId == "retype")
                    and m_arm.Armed()

                if wantDelete then
                    if not element.mapfocus then
                        element.mapfocus = true
                    end
                else
                    if element.mapfocus then
                        element.mapfocus = false
                    end
                    ClearDeleteHighlight()
                    m_mapScope.retypeAnchor = nil
                end

                if m_mode ~= "walls" then
                    return
                end

                local toolInfo = nil
                for _,t in ipairs(ActiveToolInfos()) do
                    if t.id == m_toolId and t.mapTool ~= nil then
                        toolInfo = t
                    end
                end
                if toolInfo == nil then
                    return
                end

                if not m_arm.Armed() then
                    return
                end

                --Both erase (rectangle) and delete (the inert "markupdelete"
                --sentinel) keep a custom map tool alive purely so the engine
                --leaves the wall skeleton overlay up (wallSkeletons) - the user
                --needs to see the walls they are removing. The sentinel captures
                --no drawing; delete's real input arrives via map focus.
                local eventSource = editor:SetMapTool{
                    tool = toolInfo.mapTool,
                    closed = toolInfo.mapToolClosed,
                    expires = 1,
                    stabilization = 0,
                    wallSkeletons = true,
                    --These tools draw/erase MAP GEOMETRY, so they snap like the
                    --building tools (and honor ctrl to invert). Without it a
                    --custom tool falls through to the separate OBJECT snap
                    --setting, since it publishes no wall selection -- which is
                    --why solid blocks did not snap while thin walls did.
                    --Needs an engine build; older engines ignore the field.
                    --NOT for Apply Type: its rectangle is an edge-SELECTION
                    --gesture, and a snapped border landing exactly on a tile
                    --boundary would catch every wall lying on that boundary -
                    --a free rect lets the user offset slightly to include or
                    --exclude a boundary wall unambiguously.
                    snapToGrid = toolInfo.id ~= "retype",
                    --Show the engine's editor cursor dot (where a stroke would
                    --start), like the Building editor's tools do. Not for the
                    --Delete sentinel: it highlights the hovered wall segment
                    --instead, and a dot would suggest drawing. Older engines
                    --ignore the field.
                    editorCursor = toolInfo.id ~= "delete",
                    --Draw the stroke preview in the erase colour (red) rather
                    --than white. A custom map tool's stroke comes back to us
                    --as a 'tool' event instead of going through the engine's
                    --building-operation path, so it never sets building:erase
                    --and the engine cannot tell on its own that we are about
                    --to erase. Display only; older engines ignore the field.
                    erase = toolInfo.erase == true,
                }
                if eventSource ~= nil then
                    eventSource:Listen(element)
                end
            end,

            tool = function(element, path)
                if m_mode ~= "walls" or path == nil then
                    return
                end
                --Erase (rectangle) and the solid shape tools deliver strokes.
                --Delete's sentinel map tool captures nothing; its input
                --arrives via maphover/mappress.
                if m_toolId == "erase" then
                    element:FireEvent("markuperase", path)
                elseif m_toolId == "retype" then
                    element:FireEvent("markupretype", path)
                elseif m_toolId == "solidrect" or m_toolId == "solidpoly" or m_toolId == "solidfree" then
                    element:FireEvent("markupsolid", path)
                end
            end,

            --Apply Type rectangle stroke: convert every markup wall edge the
            --rectangle touches to the selected type, at edge granularity. A
            --degenerate (click-sized) stroke routes to the single-edge click
            --path instead - whether a plain click arrives here, via mappress,
            --or both depends on how the engine arbitrates the live rectangle
            --tool against map focus, and all three are safe (see TOOL_RETYPE).
            markupretype = function(element, path)
                --the marquee (or click) is over: drop the drag anchor and the
                --live preview before applying.
                m_mapScope.retypeAnchor = nil
                ClearDeleteHighlight()

                local floor = game.currentFloor
                if floor == nil then
                    return
                end
                local ok, points = pcall(function()
                    return path.points
                end)
                if not ok or points == nil or #points < 4 then
                    if not ok then
                        dmhub.Debug("MARKUP:: Apply Type needs an engine build with MapPath points support")
                    end
                    return
                end

                local minx, miny = points[1], points[2]
                local maxx, maxy = points[1], points[2]
                for i = 1, #points - 1, 2 do
                    local x, y = points[i], points[i+1]
                    if x < minx then minx = x end
                    if x > maxx then maxx = x end
                    if y < miny then miny = y end
                    if y > maxy then maxy = y end
                end

                if (maxx - minx) < 0.12 and (maxy - miny) < 0.12 then
                    --a click, not a marquee. FindNearestDeleteSegment matches
                    --atMouse (the cursor is still at the release point), so
                    --the passed point only feeds older-engine fallbacks.
                    element:FireEvent("markupretypeclick", { x = (minx + maxx)*0.5, y = (miny + maxy)*0.5 })
                    return
                end

                local entry = m_paletteEntries[m_selectedIndex or 0]
                if entry == nil then
                    return
                end
                local guid = MaterializeEntry(entry)
                if guid == nil then
                    return
                end

                local okCall = pcall(function()
                    floor:RetypeWallEdges{
                        wallid = guid,
                        rect = { minx, miny, maxx, maxy },
                    }
                end)
                if not okCall then
                    dmhub.Debug("MARKUP:: Apply Type needs an engine build with RetypeWallEdges support")
                end
            end,

            --Apply Type click: convert the WHOLE drawn operation under the
            --cursor to the selected palette type (segment mode retypes every
            --op with an edge coincident with the touched one). Reached from
            --mappress AND from a degenerate rectangle stroke; double delivery
            --is harmless because RetypeWallEdges skips ops already of the
            --target type.
            markupretypeclick = function(element, point)
                local floor = game.currentFloor
                if floor == nil then
                    return
                end
                local seg = FindNearestDeleteSegment(point)
                if seg == nil then
                    return
                end
                local entry = m_paletteEntries[m_selectedIndex or 0]
                if entry == nil then
                    return
                end
                local guid = MaterializeEntry(entry)
                if guid == nil then
                    return
                end
                local okCall = pcall(function()
                    floor:RetypeWallEdges{
                        wallid = guid,
                        segment = { seg.a.x, seg.a.y, seg.b.x, seg.b.y },
                    }
                end)
                if not okCall then
                    dmhub.Debug("MARKUP:: Apply Type needs an engine build with RetypeWallEdges support")
                    return
                end
                --the highlighted edge just changed type; recompute on the
                --next hover so the tint follows the new state.
                ClearDeleteHighlight()
            end,

            --rectangle stroke: erase every invisible wall - and, on engine
            --builds that support it, every invisible solid block - in the
            --region.
            markuperase = function(element, path)
                local floor = game.currentFloor
                if floor == nil then
                    return
                end

                --path.points needs the engine half of this feature; guard so
                --a stale engine build logs instead of erroring.
                local ok, points = pcall(function()
                    return path.points
                end)
                if not ok or points == nil or #points < 4 then
                    if not ok then
                        dmhub.Debug("MARKUP:: eraser needs an engine build with MapPath points support")
                    end
                    return
                end

                --floor=true routes the op through the floor-erase path, which
                --carves markup solid blocks; the engine only honors
                --eraseInvisibleOnly there on builds with the solid support, so
                --older engines keep the walls-only op (a type-blind floor
                --erase would destroy art). One op = one undo step.
                local okSupport, supportsSolids = pcall(function()
                    return floor.supportsSolidOperations
                end)
                local carveSolids = okSupport and supportsSolids == true

                floor:ExecutePolygonOperation{
                    points = {points},
                    erase = true,
                    eraseInvisibleOnly = true,
                    walls = true,
                    floor = carveSolids,
                    closed = path.closed,
                }
            end,

            --closed solid stroke: fill the region with an invisible solid
            --block of the selected solid wall type, at the height stepper's
            --height (blank/To Roof = 0 = floor-to-ceiling, no standable top).
            markupsolid = function(element, path)
                local floor = game.currentFloor
                if floor == nil then
                    return
                end

                local entry = m_paletteEntries[m_selectedIndex or 0]
                if entry == nil or not m_solidMode then
                    return
                end

                --Engine gate: a stale engine ignores solid=true and would
                --draw a plain (invisible) floor over the map's ground tiles
                --instead - visually silent but destructive. The probe
                --property only exists on builds with the passthrough.
                local okSupport, supportsSolids = pcall(function()
                    return floor.supportsSolidOperations
                end)
                if not okSupport or supportsSolids ~= true then
                    dmhub.Debug("MARKUP:: solid walls need an engine build with ExecutePolygonOperation solid support")
                    return
                end

                if assets.tilesheets[INVISIBLE_TILESHEET_ID] == nil then
                    dmhub.Debug("MARKUP:: the Core invisible tilesheet is not available in this game")
                    return
                end

                local guid = MaterializeEntry(entry)
                if guid == nil then
                    return
                end

                local ok, points = pcall(function()
                    return path.points
                end)
                if not ok or points == nil or #points < 6 then
                    return
                end

                local height = GetWallHeightSetting()

                floor:ExecutePolygonOperation{
                    points = {points},
                    wallid = guid,
                    tileid = INVISIBLE_TILESHEET_ID,
                    wallheight = math.floor((height or 0) + 0.5),
                    solid = true,
                    walls = true,
                    floor = true,
                    closed = true,
                }
            end,

            --Delete / Apply Type hover previews, tinted delete red for Delete
            --and the TARGET type's color for Apply Type (the hover literally
            --shows what will change):
            --  Delete            - the single segment a click clears.
            --  Apply Type hover  - the WHOLE wall under the cursor (a click
            --                      retypes the entire drawn operation).
            --  Apply Type drag   - the edges the current marquee rect would
            --                      convert, live as the rect grows.
            maphover = function(element, loc, point)
                if m_mode ~= "walls" or (m_toolId ~= "delete" and m_toolId ~= "retype") then
                    ClearDeleteHighlight()
                    return
                end

                if m_toolId == "retype" then
                    local entry = m_paletteEntries[m_selectedIndex or 0]
                    local color = m_wallColor.EntryColor(entry) or "#4da6ff"

                    --marquee-in-progress: while the left button is held, the
                    --press point (or, when the press was swallowed by the
                    --live rectangle tool, the first held-button hover)
                    --anchors the rect and the captured edges highlight live.
                    if element:GetMouseButton(0) then
                        local anchor = m_mapScope.retypeAnchor
                        if anchor == nil and point ~= nil then
                            anchor = { x = point.x, y = point.y }
                            m_mapScope.retypeAnchor = anchor
                        end
                        if anchor ~= nil and point ~= nil
                            and (math.abs(point.x - anchor.x) >= 0.12 or math.abs(point.y - anchor.y) >= 0.12) then
                            local floor = game.currentFloor
                            local segments = nil
                            if floor ~= nil then
                                pcall(function()
                                    segments = floor:GetWallEdgesInRect{
                                        rect = { anchor.x, anchor.y, point.x, point.y },
                                        --edges already of the target type are
                                        --omitted, matching what the retype
                                        --will skip. nil for unmaterialized
                                        --presets (no exclusion).
                                        wallid = entry ~= nil and entry.guid or nil,
                                    }
                                end)
                            end
                            m_mapScope.ShowSegmentsHighlight(segments or {}, color)
                            return
                        end
                    else
                        m_mapScope.retypeAnchor = nil
                    end

                    local seg = FindNearestDeleteSegment(point)
                    if seg == nil then
                        ClearDeleteHighlight()
                        return
                    end
                    --a click converts the whole drawn operation, so preview
                    --the whole wall path under the cursor. The derived wall
                    --is the visual unit the user is pointing at; a merged or
                    --multi-path operation can differ slightly, but this is
                    --the honest approximation available without op access.
                    local pts = seg.points
                    if pts ~= nil and #pts >= 4 then
                        local segments = {}
                        for i = 1, #pts - 3, 2 do
                            segments[#segments+1] = pts[i]
                            segments[#segments+1] = pts[i+1]
                            segments[#segments+1] = pts[i+2]
                            segments[#segments+1] = pts[i+3]
                        end
                        m_mapScope.ShowSegmentsHighlight(segments, color)
                    else
                        ShowDeleteHighlight(seg, color)
                    end
                    return
                end

                local seg = FindNearestDeleteSegment(point)
                if seg == nil then
                    ClearDeleteHighlight()
                    return
                end
                --highlight the span that will actually be cleared (>= the
                --touched edge on short segments) so the preview is honest.
                ShowDeleteHighlight(DeleteSegmentGeometry(seg))
            end,

            --Delete tool click: clear just the segment under the cursor (or the
            --minimum stable span around it - see DeleteSegmentGeometry), leaving
            --the rest of the wall intact, instead of wiping the whole wall.
            --Apply Type routes its click to the shared single-edge handler.
            mappress = function(element, loc, point)
                if m_mode ~= "walls" then
                    return
                end
                if m_toolId == "retype" then
                    --the press anchors a potential marquee (maphover shows
                    --the live rect's captured edges while the button stays
                    --down) and, when it lands on a wall, converts that whole
                    --drawn operation immediately.
                    if point ~= nil then
                        m_mapScope.retypeAnchor = { x = point.x, y = point.y }
                    end
                    element:FireEvent("markupretypeclick", point)
                    return
                end
                if m_toolId ~= "delete" then
                    return
                end
                local floor = game.currentFloor
                if floor == nil then
                    return
                end
                local seg = FindNearestDeleteSegment(point)
                if seg == nil then
                    return
                end

                --Erase a closed box straddling the segment (see
                --DeleteSegmentGeometry): stable on short segments where a
                --hair-thin centerline erase either did nothing or got healed
                --straight back by the wall auto-merge.
                local geom = DeleteSegmentGeometry(seg)
                floor:ExecutePolygonOperation{
                    points = { geom.box },
                    erase = true,
                    eraseInvisibleOnly = true,
                    walls = true,
                    floor = false,
                    closed = true,
                }

                --the highlighted segment is gone now; drop the marker so the
                --next hover recomputes against the updated walls.
                ClearDeleteHighlight()
            end,

            --Release map focus and clear any highlight if the panel goes away
            --while the Delete tool is active.
            destroy = function(element)
                if element.mapfocus then
                    element.mapfocus = false
                end
                ClearDeleteHighlight()
            end,
        },

        children = BuildToolButtons(),
    }

    --Draw-mode toggle: the SAME selected wall type can be drawn either as a
    --thin barrier on a tile boundary or as an area-filling solid block. Sits
    --directly under the tool strip because it changes which tools are shown.
    --(Forward-declared at the top of CreateMarkupEditor.)
    SetDrawMode = function(solid)
        if m_solidMode == solid then
            return
        end
        m_solidMode = solid

        --swaps the tool strip and, if the active tool has no counterpart in
        --the new mode, falls back to that mode's default drawing tool.
        if toolsPanel ~= nil and toolsPanel.valid then
            toolsPanel:FireEvent("rebuildtools")
        end

        --Thin mode's drawing tools ARE the engine building tools, so the
        --shared setting has to be pushed when we land on one. (rebuildtools
        --deliberately never writes settings - it also fires on remote palette
        --changes, where stealing the Building editor's tool would be rude.)
        if not m_solidMode then
            for _,toolInfo in ipairs(ActiveToolInfos()) do
                if toolInfo.id == m_toolId and toolInfo.tool ~= nil then
                    dmhub.SetSettingValue("building:erase", false)
                    dmhub.SetSettingValue("buildingtool", toolInfo.tool)
                end
            end
        end

        if drawModePanel ~= nil and drawModePanel.valid then
            drawModePanel:FireEventTree("refreshdrawmode")
        end
        --the stepper is labelled Wall Height / Block Height by mode.
        if heightPanel ~= nil and heightPanel.valid then
            heightPanel:FireEventTree("refreshheight")
        end

        --Solid mode draws with custom map tools that expire after ~1s;
        --register immediately instead of waiting for the think tick.
        if toolsPanel ~= nil and toolsPanel.valid then
            toolsPanel:FireEvent("think")
        end
        --(No focus re-grab here any more. Landing on thin mode writes
        --buildingtool, which used to make the Building editor's palette
        --refocus its own chip and disarm this panel; explicit arming is
        --immune to that.)
    end

    local CreateDrawModeChip = function(solid)
        --NOT cond(): it evaluates both arguments, which would build an orphan
        --gui.Panel every time this chip is created.
        local preview
        if solid then
            preview = CreateSolidBlockPreview()
        else
            preview = CreateWallLinePreview(nil)
        end

        return gui.Panel{
            classes = {"markupChip", cond(m_solidMode == solid, "selected")},
            --the pair plus the 4px spacer between them spans the full 96%
            --content column, so the toggle's outer edges line up with the
            --palette rows and the Add Wall Type row above.
            width = "50%-2",
            height = "100%",
            flow = "vertical",
            bgimage = true,
            pad = 4,
            borderBox = true,

            data = {
                solid = solid,
            },

            press = function(element)
                --focus first: SetDrawMode registers the custom map tool, and
                --the think handler that does it is focus-gated. On
                --contentPanel rather than this chip, per TakeMarkupFocus.
                TakeMarkupFocus()
                SetDrawMode(element.data.solid)
            end,

            refreshdrawmode = function(element)
                element:SetClass("selected", m_solidMode == element.data.solid)
            end,

            gui.Label{
                classes = {"sizeXs"},
                text = cond(solid, "Solid Block", "Thin Wall"),
                width = "100%",
                height = "auto",
                textAlignment = "center",
                vmargin = 2,
            },

            --the same miniatures the palette uses, so the difference between
            --a line and a filled region is visible rather than just named.
            --Below the name, mirroring the palette rows' text-then-visual.
            preview,
        }
    end

    drawModePanel = gui.Panel{
        width = "96%",
        height = 40,
        halign = "center",
        flow = "horizontal",
        vmargin = 2,

        hover = SideTooltip("Thin Wall draws a barrier along the line you trace. Solid Block fills the area you draw with volume: it has a height, can be stood on and climbed, and blocks sight up to its height. Both use the wall type selected above."),

        --openable (door) types are thin-only (their strokes must be wall
        --operations the engine attaches door state to), so the toggle hides.
        create = function(element)
            element:FireEvent("refreshdoorchip")
        end,
        refreshdoorchip = function(element)
            element:SetClass("collapsed", EntryIsOpenable(m_paletteEntries[m_selectedIndex or 0]))
        end,

        children = {
            CreateDrawModeChip(false),
            gui.Panel{
                width = 4,
                height = 1,
            },
            CreateDrawModeChip(true),
        },
    }

    --Wall height stepper: blank ("To Roof") means walls run floor to ceiling;
    --a number is the height in tiles stamped on each placement, letting
    --creatures fly, see, and climb over per the wall height rules. In solid
    --mode the same value is the block's height (To Roof = no standable top).
    heightPanel = gui.Panel{
        width = "96%",
        height = "auto",
        halign = "center",
        flow = "vertical",

        multimonitor = {"building:specifywallheight", "building:wallheightvalue"},

        events = {
            monitor = function(element)
                element:FireEventTree("refreshheight")
            end,
        },

        hover = SideTooltip("Walls with a height can be flown over, seen over, and climbed over by creatures high enough. Walls set To Roof always block. For solid blocks the height is the block's height: a block with a height has a standable top, while To Roof fills floor to ceiling."),

        --Section header like Shape / Wall Types; on its own line so the
        --stepper beneath cannot read as "Wall Height: -" / "To Roof: +".
        gui.Label{
            classes = {"markupSectionHeader"},
            text = "Wall Height",
            uppercase = true,
            width = "100%",
            height = "auto",
            vmargin = 4,
            refreshheight = function(element)
                element.text = cond(m_solidMode, "Block Height", "Wall Height")
            end,
        },

        gui.Panel{
            width = "auto",
            height = "auto",
            halign = "center",
            flow = "horizontal",

            gui.Button{
                classes = {"sizeS"},
                text = "-",
                width = 30,
                valign = "center",
                hmargin = 6,
                events = {
                    click = function()
                        local height = GetWallHeightSetting()
                        if height == nil then
                            return
                        end
                        if height <= 1 then
                            SetWallHeightSetting(nil)
                        else
                            SetWallHeightSetting(height - 1)
                        end
                    end,
                },
            },

            gui.Label{
                text = "",
                fontSize = 18,
                --wide enough for "To Roof" (the no-height label) without wrapping.
                width = 90,
                height = "auto",
                valign = "center",
                textAlignment = "center",
                create = function(element)
                    element:FireEvent("refreshheight")
                end,
                refreshheight = function(element)
                    local height = GetWallHeightSetting()
                    if height == nil then
                        element.text = "To Roof"
                    else
                        element.text = string.format("%d", math.floor(height + 0.5))
                    end
                end,
            },

            gui.Button{
                classes = {"sizeS"},
                text = "+",
                width = 30,
                valign = "center",
                hmargin = 6,
                events = {
                    click = function()
                        local height = GetWallHeightSetting()
                        if height == nil then
                            SetWallHeightSetting(1)
                        elseif height < 10 then
                            SetWallHeightSetting(height + 1)
                        end
                    end,
                },
            },
        },
    }

    local wallsPanel = gui.Panel{
        classes = {cond(m_mode ~= "walls", "collapsed")},
        width = "100%",
        height = "auto",
        flow = "vertical",

        markupmode = function(element)
            element:SetClass("collapsed", m_mode ~= "walls")
        end,

        --Fixed "how you draw" controls lead; the wall type list comes last
        --because it is the only section that grows (custom types), and
        --putting it below keeps the tool strip at a stable position.
        SectionHeader("Tool"),

        toolsPanel,

        --"Shape" groups the stroke's geometry: thin vs solid, and the height
        --stamped on each placement. It sits directly under the tool strip
        --because the toggle swaps which tool strip is shown. The header
        --stays up even for openable (door) types, where the thin/solid
        --toggle collapses but the height stepper still applies.
        SectionHeader("Shape"),

        drawModePanel,

        heightPanel,

        SectionHeader("Wall Types"),

        palettePanel,

        addButton,
    }

    --========================================================================
    --Zones mode UI: zone-type palette (Environmental Keywords), paint tools,
    --and the list of zones on the current floor.
    --========================================================================

    local zonePalettePanel
    local zoneToolsPanel
    local zoneListPanel
    local zonesPanel

    local RefreshZoneUI = function()
        if zonesPanel ~= nil and zonesPanel.valid then
            zonesPanel:FireEventTree("refreshzones")
        end
    end

    --Resolves a zone-type chip to a keyword id, materializing preset chips
    --into real Environmental Keywords on first use (recording the new id back
    --into the palette, like wall presets record their materialized asset).
    local EnsureZoneTypeKeyword = function(index)
        local entry = m_zonePaletteEntries[index or 0]
        if entry == nil then
            return nil
        end

        if entry.keywordid ~= nil then
            if GetKeyword(entry.keywordid) ~= nil then
                return entry.keywordid
            end
            if entry.kind ~= "preset" then
                --keyword chip whose keyword was deleted from the compendium.
                return nil
            end
        end

        if entry.kind == "preset" then
            local preset = ZONE_PRESETS_BY_KEY[entry.key]
            if preset == nil then
                return nil
            end
            local keywordid = MaterializeZonePreset(preset)
            if keywordid == nil then
                return nil
            end
            entry.keywordid = keywordid
            SaveZonePalette(m_zonePaletteEntries)
            return keywordid
        end

        return nil
    end

    --Opens the zone type's keyword editor dialog (the same editor the
    --compendium uses), materializing preset entries into real keywords first.
    local EditZoneTypeKeyword = function(index)
        local keywordid = EnsureZoneTypeKeyword(index)
        if keywordid == nil then
            return
        end
        local keywordType = rawget(_G, "EnvironmentalKeyword")
        if keywordType == nil or rawget(keywordType, "ShowEditDialog") == nil then
            dmhub.Debug("MARKUP:: EnvironmentalKeyword.ShowEditDialog not available")
            return
        end
        keywordType.ShowEditDialog(keywordid)
    end

    --"Set Amount..." prompt behind the chip's Default Height submenu. A typed
    --number rather than a stepper: unlike wall height there is no small fixed
    --range, and "Ground Only"/"Unlimited" (the two common answers) are already
    --one click away in the menu. apply(height) does the writing, so this is
    --shared by the per-type default and the per-zone override.
    local ShowZoneHeightDialog = function(currentHeight, apply, owner)
        local heightText = tostring(cond(currentHeight ~= nil and currentHeight >= 1, currentHeight, 2))

        local modalLayer = nil
        local dialogPanel
        dialogPanel = gui.Panel{
            id = "MarkupZoneHeightDialog",
            classes = {"framedPanel"},
            --94% of the modal layer, capped at the design width (see
            --MarkupWallDialog).
            width = "94%",
            maxWidth = 380,
            height = "auto",
            pad = 16,
            borderBox = true,
            flow = "vertical",
            styles = ThemeEngine.MergeStyles{
                Styles.Panel,
                MarkupChipStyles(),
            },

            gui.Label{
                classes = {"dialogTitle"},
                text = "Zone Height",
            },

            gui.Panel{
                classes = {"formStackedRow"},
                gui.Label{
                    classes = {"formStacked"},
                    text = "Affects up to height:",
                },
                gui.Input{
                    classes = {"formStacked"},
                    text = heightText,
                    width = 60,
                    characterLimit = 3,
                    numeric = true,
                    selectAllOnFocus = true,
                    change = function(element)
                        heightText = element.text
                    end,
                },
            },

            gui.Label{
                classes = {"fgMuted", "sizeXs"},
                text = "Tiles above the ground the zone reaches. The height follows the terrain, so a zone that runs up onto a ledge still reaches this far above the ledge.",
                width = "94%",
                height = "auto",
                halign = "center",
                vmargin = 2,
            },

            gui.Panel{
                width = "100%",
                height = "auto",
                flow = "horizontal",
                halign = "center",
                vmargin = 8,

                gui.Button{
                    classes = {"sizeM"},
                    text = "Cancel",
                    halign = "center",
                    captureEscape = true,
                    escapePriority = EscapePriority.EXIT_DIALOG,
                    events = {
                        click = function(element)
                            element:FireEvent("escape")
                        end,
                        escape = function()
                            gui.CloseModalInLayer(modalLayer)
                        end,
                    },
                },

                gui.Button{
                    classes = {"sizeM"},
                    text = "Save",
                    halign = "center",
                    events = {
                        click = function()
                            --a blank or junk entry means "no limit"; 0 typed
                            --here is the same answer as the menu's Ground Only.
                            local n = tonumber(heightText)
                            if n == nil or n < 0 then
                                apply(nil)
                            else
                                apply(math.floor(n))
                            end
                            gui.CloseModalInLayer(modalLayer)
                        end,
                    },
                },
            },
        }

        modalLayer = gui.ShowModal(dialogPanel, {owner = owner})
    end

    --The built-in "Hole" chip: always last in the palette, not keyword-backed
    --and not editable -- no right-click menu, no Entire Map pill, no dynamic
    --light row. Painting with it cuts real holes in the map (see m_holes).
    local CreateHoleZoneChip = function(index)
        local summary = "Cuts a hole through the floor"
        if not m_holes.Supported() then
            summary = "Needs an engine update"
        end

        local gradient = m_zoneStripes.Gradient(m_holes.color, ZONE_ANGLE_A)
        local swatchColor = m_holes.color
        if gradient ~= nil then
            swatchColor = "white"
        end

        return gui.Panel{
            classes = {"markupChip", cond(index == m_zoneSelectedType, "selected")},
            width = "100%",
            height = 36,
            halign = "center",
            flow = "vertical",
            bgimage = true,
            pad = 6,
            borderBox = true,
            vmargin = 1,

            data = {
                index = index,
            },

            press = function(element)
                m_zoneSelectedType = element.data.index
                --a fresh type selection paints new holes, not whatever zone
                --was last targeted.
                m_zoneTargetId = nil
                zonePalettePanel:FireEvent("refreshchips")
                RefreshZoneUI()
                --picking the type must arm the paint tool by itself, exactly
                --like the zone chips.
                TakeMarkupFocus()
            end,

            gui.Panel{
                width = "100%",
                height = 24,
                flow = "horizontal",

                gui.Panel{
                    --no Entire Map pill on this chip, so only the swatch
                    --column comes off the width: this panel's own 4+4 hmargin
                    --plus the swatch's 28 + 4+4. Get this wrong and the swatch
                    --sits out of line with the keyword chips' swatches.
                    width = "100%-44",
                    height = "auto",
                    valign = "center",
                    flow = "vertical",
                    hmargin = 4,

                    gui.Label{
                        classes = {"bold"},
                        text = "Hole",
                        width = "100%",
                        height = "auto",
                    },

                    gui.Label{
                        classes = {"fgMuted", "sizeXs"},
                        text = summary,
                        width = "100%",
                        height = "auto",
                        textWrap = false,
                        textOverflow = "ellipsis",
                    },
                },

                gui.Panel{
                    width = 28,
                    height = 28,
                    hmargin = 4,
                    valign = "center",
                    bgimage = true,
                    bgcolor = swatchColor,
                    gradient = gradient,
                    borderWidth = 1,
                    borderColor = "@border",
                },
            },
        }
    end

    --Whether the keyword carries a USABLE visual representation (the same
    --test BuildZoneAuraInstance applies before stamping it on an aura): a
    --floor appearance with a fill or edge asset, or a sprites appearance
    --with at least one sprite. Gates the Visuals pill on palette chips and
    --the Visuals badge on zone rows - a type with no art gets neither.
    local ZoneTypeHasVisuals = function(kw)
        if kw == nil then
            return false
        end
        local has = false
        pcall(function()
            local appearance = kw:try_get("appearance")
            if appearance == nil then
                return
            end
            if appearance.mode == "floor" then
                has = appearance.tileid ~= nil or appearance.edgeWallId ~= nil
            elseif appearance.mode == "sprites" then
                has = appearance.sprites ~= nil and #appearance.sprites > 0
            end
        end)
        return has
    end

    local CreateZoneChip = function(index, entry)
        if entry.kind == "hole" then
            return CreateHoleZoneChip(index)
        end

        local kw = GetKeyword(entry.keywordid)
        local preset = nil
        if entry.kind == "preset" then
            preset = ZONE_PRESETS_BY_KEY[entry.key]
        end

        local name, color, summary
        if kw ~= nil then
            name = kw.name or "Keyword"
            color = KeywordColor(entry.keywordid, kw)
            summary = KeywordSummary(kw)
        elseif preset ~= nil then
            name = preset.name
            color = preset.color
            summary = preset.summary
        else
            name = "Unknown Keyword"
            color = "#666666"
            summary = "Missing from the compendium"
        end

        --"Entire Map": this type blankets the whole map instead of only the
        --regions painted with it. Nothing is striped on the map for it -- the
        --lit pill is the indicator -- so keep the tooltip explicit about that.
        local entireMapButton
        entireMapButton = gui.Panel{
            classes = {"markupEntireMap", cond(m_entireMap.IsSet(entry.keywordid), "lit")},
            width = 60,
            height = 16,
            valign = "center",
            bgimage = "panels/square.png",
            hover = SideTooltip("Apply this zone type to the whole map. Zones that dispel it (and zones painted with it) carve it out. Nothing is drawn on the map for it."),

            click = function(element)
                --a preset chip has no keyword until something uses it.
                local keywordid = EnsureZoneTypeKeyword(index)
                if keywordid == nil then
                    return
                end

                local lit = not m_entireMap.IsSet(keywordid)
                m_entireMap.Set(keywordid, lit)
                element:SetClass("lit", lit)

                --a blanket registers (or drops) real auras, so rebuild now
                --instead of waiting for an unrelated aura rebuild.
                pcall(function()
                    dmhub.RefreshMapAuras()
                end)
            end,

            gui.Label{
                classes = {"markupEntireMapLabel", "sizeXs"},
                text = "Entire Map",
                fontSize = 10,
                width = "auto",
                height = "auto",
                halign = "center",
                valign = "center",
            },
        }

        --"Visuals": only for types with a visual representation (Edit
        --Appearance art). Lit = zones drawn with this type display their
        --art; unlit = they get stripes only. Only a DEFAULT stamped at
        --paint time - each zone's art then toggles from the Visuals badge
        --on its list row, so flipping this never disturbs painted zones.
        --Always constructed and collapsed when ineligible: a nil positional
        --child would hole the topRow constructor's array and drop the
        --children after it.
        local hasVisuals = ZoneTypeHasVisuals(kw)
        local visualsOn = true
        if hasVisuals then
            pcall(function()
                visualsOn = kw:try_get("appearanceDefaultOff", false) ~= true
            end)
        end
        local visualsButton = gui.Panel{
            classes = {"markupEntireMap", cond(visualsOn, "lit"), cond(not hasVisuals, "collapsed")},
            width = 48,
            height = 16,
            hmargin = 2,
            valign = "center",
            bgimage = "panels/square.png",
            hover = SideTooltip("This zone type has a visual representation. When lit, zones you draw display it on the map; when unlit, new zones show only their stripes. Each painted zone can still be toggled from its row in the zone list."),

            click = function(element)
                --the pill only shows for a resolved keyword (the
                --appearance lives on it), so this is just the dead-id
                --healing path, same as the Entire Map pill.
                local keywordid = EnsureZoneTypeKeyword(index)
                if keywordid == nil then
                    return
                end
                local keyword = GetKeyword(keywordid)
                if keyword == nil then
                    return
                end
                local off = false
                pcall(function()
                    off = keyword:try_get("appearanceDefaultOff", false) == true
                end)
                if off then
                    --shown is the default; nil-assign clears the field
                    --(same idiom defaultHeight uses).
                    keyword.appearanceDefaultOff = nil
                else
                    keyword.appearanceDefaultOff = true
                end
                dmhub.SetAndUploadTableItem(ENVIRONMENTAL_KEYWORDS_TABLE, keyword)
                element:SetClass("lit", off)
            end,

            gui.Label{
                classes = {"markupEntireMapLabel", "sizeXs"},
                text = "Visuals",
                fontSize = 10,
                width = "auto",
                height = "auto",
                halign = "center",
                valign = "center",
            },
        }

        --"Dynamic Light": the zone type only applies where the map's light
        --level is below the slider's threshold, recomputed live as lights
        --move and the time of day changes. Double-gated: the engine must
        --support the sampling API (new), and the KEYWORD must have "Can Use
        --Dynamic Light" checked in its editor -- most zone types (Water,
        --Difficult Terrain) have no use for it, so only opted-in types
        --(Darkness) grow the second row. Preset chips have no keyword yet
        --and so never show it; materialize the keyword and check the flag.
        local dynEligible = false
        if kw ~= nil then
            pcall(function()
                dynEligible = kw:try_get("dynamicLight", false) == true
            end)
        end

        local dynRow = nil
        if dynEligible and m_dynamicLight.Supported() then
            local dynPct = m_dynamicLight.GetThreshold(entry.keywordid)

            local dynSlider
            dynSlider = gui.PercentSlider{
                --the args table REPLACES PercentSlider's own classes list, so
                --"percentSlider" must ride along or the control loses its look.
                classes = {"percentSlider", cond(dynPct == nil, "hidden")},
                width = 100,
                height = 14,
                halign = "left",
                valign = "center",
                hmargin = 8,
                value = (dynPct or 30) / 100,
                hover = SideTooltip("Light threshold: tiles where the light level is below this count as dark, and this zone type applies only there."),
                confirm = function(element)
                    local keywordid = entry.keywordid
                    if keywordid == nil then
                        return
                    end
                    local pct = round(element.value * 100)
                    if pct < 1 then
                        pct = 1
                    end
                    m_dynamicLight.Set(keywordid, pct)
                    --sample the new threshold NOW: waiting for the ticker
                    --leaves a visible blink where the zone rebuilds unfiltered
                    --(new threshold = no sample yet) and then snaps back a
                    --poll later.
                    pcall(m_dynamicLight.Sample)
                end,
            }

            local dynButton
            dynButton = gui.Panel{
                classes = {"markupEntireMap", cond(dynPct ~= nil, "lit")},
                width = 78,
                height = 16,
                halign = "left",
                valign = "center",
                bgimage = "panels/square.png",
                hover = SideTooltip("Calculate this zone type dynamically from the light on the map: it only applies where the light level is below the threshold. Updates as lights move, doors close and night falls. Painted zones and the Entire Map blanket are both filtered."),

                click = function(element)
                    --the row only shows for a resolved keyword (the
                    --dynamicLight flag lives on it), so this is just the
                    --dead-id healing path, same as the Entire Map pill.
                    local keywordid = EnsureZoneTypeKeyword(index)
                    if keywordid == nil then
                        return
                    end

                    local lit = m_dynamicLight.GetThreshold(keywordid) == nil
                    if lit then
                        local pct = round(dynSlider.value * 100)
                        if pct < 1 then
                            pct = 30
                        end
                        m_dynamicLight.Set(keywordid, pct)
                    else
                        m_dynamicLight.Set(keywordid, nil)
                    end
                    element:SetClass("lit", lit)
                    dynSlider:SetClass("hidden", not lit)
                    --sample immediately: enabling carves in the same tick
                    --(no unfiltered blink), disabling clears the stored dark
                    --sets and refreshes the auras without waiting a poll.
                    pcall(m_dynamicLight.Sample)
                end,

                gui.Label{
                    classes = {"markupEntireMapLabel", "sizeXs"},
                    text = "Dynamic Light",
                    fontSize = 10,
                    width = "auto",
                    height = "auto",
                    halign = "center",
                    valign = "center",
                },
            }

            dynRow = gui.Panel{
                width = "100%",
                height = 24,
                flow = "horizontal",

                dynButton,
                dynSlider,
            }
        end

        --A wider version of m_zoneStripes.Swatch for the row's right-side
        --visual, mirroring the wall rows' line-preview column: the stripe
        --pattern at the angle the map will actually paint.
        local gradient = m_zoneStripes.Gradient(color, m_zoneStripes.AngleForKeyword(entry.keywordid))
        local swatchColor = color
        if gradient ~= nil then
            swatchColor = "white"
        end

        --the classic chip content; on engines with light sampling the chip
        --grows a second row holding the Dynamic Light controls.
        local topRow = gui.Panel{
            width = "100%",
            height = 24,
            flow = "horizontal",

            gui.Panel{
                --the Visuals pill (48 + 2+2 hmargin) comes off the text
                --column when present, on top of the standing 104 (label
                --margins + Entire Map pill + swatch).
                width = cond(hasVisuals, "100%-156", "100%-104"),
                height = "auto",
                valign = "center",
                flow = "vertical",
                hmargin = 4,

                gui.Label{
                    classes = {"bold"},
                    text = name,
                    width = "100%",
                    height = "auto",
                },

                --the summary can outgrow the chip (e.g. Lava: difficult
                --terrain + damaging + affects adjacent), so it ellipsizes on
                --one line rather than wrapping out of the fixed-height row;
                --hovering shows the untruncated string.
                gui.Label{
                    classes = {"fgMuted", "sizeXs"},
                    text = summary,
                    width = "100%",
                    height = "auto",
                    textWrap = false,
                    textOverflow = "ellipsis",
                    linger = function(element)
                        if summary ~= nil and summary ~= "" then
                            gui.Tooltip(summary)(element)
                        end
                    end,
                },
            },

            visualsButton,

            entireMapButton,

            --No settings cog: editing lives in the right-click menu ("Edit
            --Zone Type..."). A square swatch at the row's right edge, nearly
            --the row's full inner height: a filled region reads as an area,
            --unlike the walls' thin lines.
            gui.Panel{
                width = 28,
                height = 28,
                hmargin = 4,
                valign = "center",
                bgimage = true,
                bgcolor = swatchColor,
                gradient = gradient,
                borderWidth = 1,
                borderColor = "@border",
            },
        }

        return gui.Panel{
            classes = {"markupChip", cond(index == m_zoneSelectedType, "selected")},
            width = "100%",
            height = cond(dynRow ~= nil, 60, 36),
            halign = "center",
            flow = "vertical",
            bgimage = true,
            pad = 6,
            borderBox = true,
            vmargin = 1,

            data = {
                index = index,
            },

            press = function(element)
                m_zoneSelectedType = element.data.index
                --a fresh type selection paints into that type's existing zone
                --(or a new one), not whatever zone was last targeted.
                m_zoneTargetId = nil
                zonePalettePanel:FireEvent("refreshchips")
                RefreshZoneUI()
                --picking a zone type must arm the paint tool by itself: without
                --this the next click on the map lands with no custom map tool
                --registered and silently does nothing.
                TakeMarkupFocus()
            end,

            rightClick = function(element)
                --"Default Height" writes to the KEYWORD, so a preset chip has
                --to materialize its keyword first (same lazy-materialize the
                --Entire Map pill does). Setting a default never touches zones
                --already painted - it is only what the next one is stamped with.
                local SetDefaultHeight = function(height)
                    local keywordid = EnsureZoneTypeKeyword(element.data.index)
                    if keywordid == nil then
                        return
                    end
                    m_zoneHeight.Set(keywordid, height)
                    zonePalettePanel:FireEvent("refreshzonepalette")
                end

                local currentHeight = m_zoneHeight.Get(GetKeyword(entry.keywordid))

                element.popup = gui.ContextMenu{
                    entries = {
                        {
                            text = "Edit Zone Type...",
                            click = function()
                                element.popup = nil
                                EditZoneTypeKeyword(element.data.index)
                            end,
                        },
                        {
                            text = "Default Height",
                            submenu = {
                                {
                                    text = cond(currentHeight == nil, "Unlimited (current)", "Unlimited"),
                                    click = function()
                                        element.popup = nil
                                        SetDefaultHeight(nil)
                                    end,
                                },
                                {
                                    text = cond(currentHeight == 0, "Ground Only (current)", "Ground Only"),
                                    click = function()
                                        element.popup = nil
                                        SetDefaultHeight(0)
                                    end,
                                },
                                {
                                    text = cond(currentHeight ~= nil and currentHeight > 0,
                                        string.format("Set Amount... (%d)", currentHeight or 0), "Set Amount..."),
                                    click = function()
                                        element.popup = nil
                                        ShowZoneHeightDialog(currentHeight, SetDefaultHeight, element)
                                    end,
                                },
                            },
                        },
                        {
                            text = "Remove from Palette",
                            click = function()
                                element.popup = nil
                                --drop the blanket (and the dynamic-light
                                --config) with the chip: otherwise they keep
                                --applying to the map with no UI left to turn
                                --them off.
                                local removed = m_zonePaletteEntries[element.data.index]
                                if removed ~= nil and removed.keywordid ~= nil then
                                    if m_entireMap.IsSet(removed.keywordid) then
                                        m_entireMap.Set(removed.keywordid, false)
                                        pcall(function()
                                            dmhub.RefreshMapAuras()
                                        end)
                                    end
                                    m_dynamicLight.Set(removed.keywordid, nil)
                                end
                                table.remove(m_zonePaletteEntries, element.data.index)
                                if m_zoneSelectedType > #m_zonePaletteEntries then
                                    m_zoneSelectedType = #m_zonePaletteEntries
                                end
                                if m_zoneSelectedType < 1 then
                                    m_zoneSelectedType = 1
                                end
                                SaveZonePalette(m_zonePaletteEntries)

                                --a map-scoped zone type with no zones painted
                                --is orphaned once its chip is gone: delete the
                                --keyword rather than stranding it hidden in
                                --the table.
                                if removed ~= nil and removed.keywordid ~= nil then
                                    m_mapScope.DeleteKeywordIfOrphaned(removed.keywordid, m_zonePaletteEntries)
                                end
                            end,
                        },
                    },
                }
            end,

            topRow,
            dynRow,
        }
    end

    --split out so refreshzonepalette can hand it to RebuildDeferringPopups
    --and have it replayed later if a chip context menu is open.
    local RebuildZonePalette = function(element)
        m_zonePaletteEntries = ParseZonePalette()
        --the built-in Hole type is always present, after the user's zone
        --types. SerializeZonePalette skips it (no kind "preset", no
        --keywordid), so it never reaches the stored palette setting.
        m_zonePaletteEntries[#m_zonePaletteEntries+1] = { kind = "hole" }
        if m_zoneSelectedType > #m_zonePaletteEntries then
            m_zoneSelectedType = #m_zonePaletteEntries
        end
        if m_zoneSelectedType < 1 then
            m_zoneSelectedType = 1
        end

        --the chips stripe at the angle the map will actually use, and
        --that assignment is computed by the zone cache rebuild. Cheap
        --when the cache is already warm.
        EnsureZoneCache()

        local children = {}
        for i,entry in ipairs(m_zonePaletteEntries) do
            children[#children+1] = CreateZoneChip(i, entry)
        end
        element.children = children
    end

    zonePalettePanel = gui.Panel{
        width = "96%",
        height = "auto",
        halign = "center",
        flow = "vertical",

        --monitorAssets: keyword table edits change chip names/colors/summaries.
        monitorAssets = true,
        --zoneentiremap and zonedynamiclight as well as the palette: the
        --"Entire Map" and "Dynamic Light" pills read them, and they can
        --change from another client (or from an undo).
        multimonitor = {"markup:zonepalette", "markup:zoneentiremap", "markup:zonedynamiclight"},

        --gui.RebuildDeferringPopups parks a stood-down rebuild in here.
        data = {},

        events = {
            think = gui.ThinkDeferredRebuild,

            monitor = function(element)
                element:FireEvent("refreshzonepalette")
            end,

            refreshAssets = function(element)
                element:FireEvent("refreshzonepalette")
            end,

            --replaces every chip, so it stands down while a chip context
            --menu is open rather than closing it under the cursor.
            refreshzonepalette = function(element)
                gui.RebuildDeferringPopups(element, RebuildZonePalette)
            end,

            refreshchips = function(element)
                for _,chip in ipairs(element.children) do
                    if chip.data ~= nil and chip.data.index ~= nil then
                        chip:SetClass("selected", chip.data.index == m_zoneSelectedType)
                    end
                end
            end,
        },
    }

    --Adding a zone type selects it, mirroring what pressing its chip does.
    --Without this the palette grows but m_zoneSelectedType stays put, so the
    --new chip renders unselected and the next click on the map paints the
    --PREVIOUS type. The rebuild triggered by SaveZonePalette restamps the
    --chips, and CreateZoneChip reads m_zoneSelectedType at construction, so
    --the new chip is born selected without an explicit refreshchips.
    --Callers that also want the paint tool armed call TakeMarkupFocus()
    --afterwards; the "New Zone Type..." path deliberately does not, because it
    --opens a modal editor for the new keyword immediately.
    local AppendZoneTypeAndSelect = function(entry)
        m_zonePaletteEntries[#m_zonePaletteEntries+1] = entry
        m_zoneSelectedType = #m_zonePaletteEntries
        --a fresh type selection paints into that type's existing zone (or a
        --new one), not whatever zone was last targeted.
        m_zoneTargetId = nil
        SaveZonePalette(m_zonePaletteEntries)
        RefreshZoneUI()
    end

    --Styled as one more palette row, like the walls tab's Add Wall Type.
    local zoneAddButton
    zoneAddButton = gui.Panel{
        classes = {"markupChip"},
        width = "96%",
        height = 28,
        halign = "center",
        bgimage = true,
        borderBox = true,
        vmargin = 2,

        gui.Label{
            classes = {"fgMuted"},
            text = "+ Add Zone Type",
            fontSize = 14,
            width = "auto",
            height = "auto",
            halign = "center",
            valign = "center",
        },

        press = function(element)
            local entries = {}

            for _,preset in ipairs(ZONE_PRESETS) do
                local inPalette = false
                for _,entry in ipairs(m_zonePaletteEntries) do
                    if entry.kind == "preset" and entry.key == preset.key then
                        inPalette = true
                        break
                    end
                end

                if not inPalette then
                    entries[#entries+1] = {
                        text = preset.name,
                        click = function()
                            element.popup = nil
                            AppendZoneTypeAndSelect{
                                kind = "preset",
                                key = preset.key,
                            }
                            TakeMarkupFocus()
                        end,
                    }
                end
            end

            local paletteKeywords = {}
            for _,entry in ipairs(m_zonePaletteEntries) do
                if entry.keywordid ~= nil then
                    paletteKeywords[entry.keywordid] = true
                end
            end

            local sortedKeywords = {}
            for k,kw in unhidden_pairs(GetKeywordTable()) do
                --zone types scoped to other maps never appear here.
                if (not paletteKeywords[k]) and KeywordAvailableOnThisMap(kw) then
                    sortedKeywords[#sortedKeywords+1] = {
                        id = k,
                        name = kw.name or k,
                    }
                end
            end
            table.sort(sortedKeywords, function(a, b) return a.name < b.name end)

            for _,info in ipairs(sortedKeywords) do
                entries[#entries+1] = {
                    text = info.name,
                    click = function()
                        element.popup = nil
                        AppendZoneTypeAndSelect{
                            kind = "keyword",
                            keywordid = info.id,
                        }
                        TakeMarkupFocus()
                    end,
                }
            end

            entries[#entries+1] = {
                text = "New Zone Type...",
                click = function()
                    element.popup = nil
                    local keywordType = rawget(_G, "EnvironmentalKeyword")
                    if keywordType == nil then
                        dmhub.Debug("MARKUP:: EnvironmentalKeyword type not loaded")
                        return
                    end
                    --Created scoped to THIS map (mapid): hidden from the
                    --compendium and other maps until promoted via the editor's
                    --"Make Available to All Maps" button. Opens the editor
                    --dialog immediately so it can be named and configured.
                    --The table id comes from SetAndUploadTableItem's return
                    --value; kw.guid is a DIFFERENT id and never the table key.
                    local kw = keywordType.CreateNew()
                    kw.name = "New Zone Type"
                    kw.mapid = game.currentMapId
                    local keywordid = dmhub.SetAndUploadTableItem(ENVIRONMENTAL_KEYWORDS_TABLE, kw)
                    AppendZoneTypeAndSelect{
                        kind = "keyword",
                        keywordid = keywordid,
                    }
                    --no TakeMarkupFocus here on purpose: ShowEditDialog opens a
                    --modal editor for the brand-new keyword, and arming the map
                    --paint tool underneath it fights the dialog for focus.

                    if rawget(keywordType, "ShowEditDialog") ~= nil then
                        keywordType.ShowEditDialog(keywordid)
                    end
                end,
            }

            element.popup = gui.ContextMenu{
                entries = entries,
            }
        end,
    }

    --Per-zone edit dialog: name, height limit, player visibility.
    local ShowZoneDialog = function(entry, owner)
        local modalLayer = nil
        local name = entry.name
        local playerVisible = entry.playerVisible == true

        --Height as a mode + amount, matching the zone type's Default Height.
        --The amount box keeps a usable number even while hidden, so switching
        --to Set Amount never lands on a value Save has to reject.
        local heightMode = "infinite"
        if entry.height ~= nil then
            heightMode = cond(entry.height <= 0, "ground", "amount")
        end
        local heightText = tostring(cond(entry.height ~= nil and entry.height >= 1, entry.height, 2))

        local heightAmountPanel
        heightAmountPanel = gui.Panel{
            classes = {"formStackedRow", cond(heightMode ~= "amount", "collapsed")},
            gui.Label{
                classes = {"formStacked"},
                text = "Tiles above ground:",
            },
            gui.Input{
                classes = {"formStacked"},
                text = heightText,
                width = 60,
                characterLimit = 3,
                numeric = true,
                selectAllOnFocus = true,
                change = function(element)
                    heightText = element.text
                end,
            },
        }

        local dialogPanel
        dialogPanel = gui.Panel{
            id = "MarkupZoneDialog",
            classes = {"framedPanel"},
            --94% of the modal layer, capped at the design width (see
            --MarkupWallDialog).
            width = "94%",
            maxWidth = 440,
            height = "auto",
            pad = 16,
            borderBox = true,
            flow = "vertical",
            styles = ThemeEngine.MergeStyles{
                Styles.Panel,
                MarkupChipStyles(),
            },

            gui.Label{
                classes = {"dialogTitle"},
                text = "Edit Zone",
            },

            gui.Panel{
                classes = {"formStackedRow"},
                gui.Label{
                    classes = {"formStacked"},
                    text = "Name:",
                },
                gui.Input{
                    classes = {"formStacked"},
                    text = name,
                    characterLimit = 60,
                    change = function(element)
                        if element.text ~= "" then
                            name = element.text
                        else
                            element.text = name
                        end
                    end,
                },
            },

            --Same three-way vocabulary as the zone type's Default Height, so
            --"Ground Only" is a named choice here rather than a 0 the user has
            --to know to type. The amount box only shows for Set Amount.
            gui.Panel{
                classes = {"formStackedRow"},
                gui.Label{
                    classes = {"formStacked"},
                    text = "Height:",
                },
                gui.Dropdown{
                    classes = {"formStacked"},
                    idChosen = heightMode,
                    options = {
                        {id = "infinite", text = "Unlimited"},
                        {id = "ground", text = "Ground Only"},
                        {id = "amount", text = "Set Amount"},
                    },
                    change = function(element)
                        heightMode = element.idChosen
                        heightAmountPanel:SetClass("collapsed", heightMode ~= "amount")
                    end,
                },
            },

            heightAmountPanel,

            gui.Label{
                classes = {"fgMuted", "sizeXs"},
                text = "How far up the zone reaches, measured from the ground under it - so it follows the terrain over ledges and pits. Ground Only affects creatures standing in the zone but not flyers above it; Unlimited affects everything over it as well.",
                width = "94%",
                height = "auto",
                halign = "center",
                vmargin = 2,
            },

            gui.Check{
                classes = {"formCheck"},
                text = "Visible to players",
                tooltip = "Players see this zone's stripes and name on their map when they turn on the tile overlay. On by default; turn it off for a zone the players are not meant to know about.",
                value = playerVisible,
                change = function(element)
                    playerVisible = element.value
                end,
            },

            gui.Panel{
                width = "100%",
                height = "auto",
                flow = "horizontal",
                halign = "center",
                vmargin = 8,

                gui.Button{
                    classes = {"sizeM"},
                    text = "Cancel",
                    halign = "center",
                    captureEscape = true,
                    escapePriority = EscapePriority.EXIT_DIALOG,
                    events = {
                        click = function(element)
                            element:FireEvent("escape")
                        end,
                        escape = function()
                            gui.CloseModalInLayer(modalLayer)
                        end,
                    },
                },

                gui.Button{
                    classes = {"sizeM"},
                    text = "Save",
                    halign = "center",
                    events = {
                        click = function()
                            local floor = game.currentFloor
                            if floor ~= nil then
                                local overrides = {
                                    name = name,
                                    playerVisible = playerVisible,
                                }
                                if heightMode == "infinite" then
                                    overrides.clearHeight = true
                                elseif heightMode == "ground" then
                                    overrides.height = 0
                                else
                                    --junk in the amount box falls back to
                                    --unlimited rather than silently saving 0,
                                    --which would read as Ground Only.
                                    local n = tonumber(heightText)
                                    if n == nil or n < 0 then
                                        overrides.clearHeight = true
                                    else
                                        overrides.height = math.floor(n)
                                    end
                                end
                                floor:SetMarkupZone(entry.zoneid, BuildZoneRecord(entry, overrides))
                                RefreshZoneUI()
                            end
                            gui.CloseModalInLayer(modalLayer)
                        end,
                    },
                },
            },
        }

        modalLayer = gui.ShowModal(dialogPanel, {owner = owner})
    end

    local CreateZoneRow = function(entry)
        local meta = {}
        meta[#meta+1] = string.format("%d tiles", #entry.locs)
        --"height 0" would read as "no height"; describe the modes by name.
        --Unlimited is spelled out here rather than left blank (Describe returns
        --nil for it, which is right for chips and menus): on a row that already
        --reads "N tiles", a silent height is indistinguishable from a zone whose
        --height nobody has looked at.
        meta[#meta+1] = string.lower(m_zoneHeight.Describe(entry.height) or "Unlimited height")
        --player-visible is the default now, so the row calls out the exception:
        --a zone the DM has deliberately kept to themselves.
        if not entry.playerVisible then
            meta[#meta+1] = "hidden from players"
        end

        --Rows read as "<type> -- <where>": the collapsed type/custom name
        --(same rule as the map labels) plus the zone's area of the map. The
        --raw numbered record name stays visible in the Edit Zone dialog.
        local displayName = ZoneOverlayLabel(entry)
        local area = ZoneAreaDescription(entry)
        if area ~= nil then
            displayName = displayName .. " -- " .. area
        end
        if #entry.locs == 0 then
            displayName = displayName .. " (empty)"
        end

        --Same enlarged swatch treatment as the zone-type rows.
        local rowGradient = m_zoneStripes.Gradient(entry.patternColor, entry.patternAngle)
        local rowSwatchColor = entry.patternColor
        if rowGradient ~= nil then
            rowSwatchColor = "white"
        end

        --"Visuals" badge: only for zones whose TYPE has a visual
        --representation. Lit = this zone displays its art on the map;
        --click toggles the zone's own hideAppearance flag (the record
        --write triggers the aura rebuild that adds/removes the art).
        local rowHasVisuals = ZoneTypeHasVisuals(entry.keywordInfo)
        local visualsBadge = nil
        if rowHasVisuals then
            visualsBadge = gui.Panel{
                classes = {"markupEntireMap", cond(entry.hideAppearance ~= true, "lit")},
                width = 48,
                height = 16,
                hmargin = 2,
                valign = "center",
                bgimage = "panels/square.png",
                hover = SideTooltip("This zone's type has a visual representation. When lit, this zone displays it on the map; click to show only the stripes for this zone."),

                --MUST swallow the press. Without it the mouse-DOWN bubbles to
                --the row, whose press selects the zone and calls RefreshZoneUI
                ---- which replaces zoneListPanel.children, destroying this very
                --badge before the mouse comes back up, so the click never
                --fires and only the row's selection is seen. (The identical
                --badge on the zone-TYPE chip needs no such guard: that chip's
                --press only re-runs "refreshchips", which retags the selected
                --class instead of rebuilding.)
                swallowPress = true,

                click = function(element)
                    local floor = game.currentFloor
                    if floor == nil then
                        return
                    end
                    local hide = entry.hideAppearance ~= true
                    floor:SetMarkupZone(entry.zoneid, BuildZoneRecord(entry, { hideAppearance = hide }))
                    RefreshZoneUI()
                end,

                gui.Label{
                    classes = {"markupEntireMapLabel", "sizeXs"},
                    text = "Visuals",
                    fontSize = 10,
                    width = "auto",
                    height = "auto",
                    halign = "center",
                    valign = "center",
                },
            }
        end

        return gui.Panel{
            classes = {"markupChip", cond(entry.zoneid == m_zoneTargetId, "selected")},
            --zoneListPanel is already the 96% content column, so rows fill it
            --entirely and line up with the zone-type rows above.
            width = "100%",
            height = 36,
            halign = "center",
            flow = "horizontal",
            bgimage = true,
            pad = 4,
            borderBox = true,
            vmargin = 1,

            data = {
                zoneid = entry.zoneid,
            },

            --NOTE: a bare `tooltip = "..."` arg on a plain gui.Panel eagerly
            --constructs an orphaned tooltip label at create time ("was created
            --but not attached to a parent" on game entry); the idiom for
            --hover tooltips on panels is gui.Tooltip as the hover handler.
            hover = gui.Tooltip("Click to select this zone and show it on the map. Right-click for options."),

            press = function(element)
                m_zoneTargetId = entry.zoneid
                --also select the matching type chip so continued painting
                --extends this zone rather than switching types.
                for i,paletteEntry in ipairs(m_zonePaletteEntries) do
                    if paletteEntry.keywordid ~= nil and paletteEntry.keywordid == entry.keywordid then
                        m_zoneSelectedType = i
                        break
                    end
                end
                zonePalettePanel:FireEvent("refreshchips")
                RefreshZoneUI()
                --pan to the zone and pulse a highlight over its tiles.
                JumpToZone(entry)
                --selecting a zone sets the paint target, so arm the tool too.
                TakeMarkupFocus()
            end,

            rightClick = function(element)
                element.popup = gui.ContextMenu{
                    entries = {
                        {
                            text = "Edit Zone...",
                            click = function()
                                element.popup = nil
                                ShowZoneDialog(entry, element)
                            end,
                        },
                        {
                            text = "Delete Zone",
                            click = function()
                                element.popup = nil
                                local floor = game.currentFloor
                                if floor ~= nil then
                                    floor:RemoveMarkupZone(entry.zoneid)
                                    if m_zoneTargetId == entry.zoneid then
                                        m_zoneTargetId = nil
                                    end
                                    RefreshZoneUI()
                                end
                            end,
                        },
                    },
                }
            end,

            gui.Panel{
                width = 28,
                height = 28,
                valign = "center",
                bgimage = true,
                bgcolor = rowSwatchColor,
                gradient = rowGradient,
                borderWidth = 1,
                borderColor = "@border",
            },

            gui.Panel{
                --the Visuals badge (48 + 2+2 hmargin) comes off the text
                --column when present, on top of the standing 36 (swatch +
                --this column's margins).
                width = cond(rowHasVisuals, "100%-88", "100%-36"),
                height = "100%",
                flow = "vertical",
                hmargin = 4,

                gui.Label{
                    classes = {"bold", "sizeXs"},
                    text = displayName,
                    width = "100%",
                    height = "auto",
                },

                gui.Label{
                    classes = {"fgMuted", "sizeXs"},
                    text = table.concat(meta, ", "),
                    width = "100%",
                    height = "auto",
                },
            },

            --last positional entry: may be nil (no visuals for this type),
            --and a nil mid-constructor would hole the array.
            visualsBadge,
        }
    end

    --The floor's zones bucketed by zone TYPE, in the order the types first
    --appear in the (ord-sorted) list, with each bucket's zones still in ord
    --order. Grouping is what makes a long list legible - a floor with a dozen
    --zones is nearly always three or four types painted several times over -
    --and it is what the opacity slider hangs off, since fading is a property
    --of the type, not of one painted region.
    local GroupZonesOnFloor = function(floorid)
        local groups = {}
        local order = {}

        for _,entry in ipairs(ZonesOnFloor(floorid)) do
            local key = m_zoneStripes.GroupKey(entry)
            local group = groups[key]
            if group == nil then
                group = {
                    key = key,
                    name = entry.keywordName or "Zone",
                    --the first zone's swatch stands for the group: colour and
                    --stripe angle are properties of the keyword, so every zone
                    --in the group looks the same on the map anyway.
                    patternColor = entry.patternColor,
                    patternAngle = entry.patternAngle,
                    entries = {},
                }
                groups[key] = group
                order[#order+1] = group
            end
            group.entries[#group.entries+1] = entry
        end

        return order
    end

    --A group's header: the striped type swatch, the type name and how many
    --zones of it are on this floor, and the opacity slider that fades the
    --whole type on the map. Widths add up to exactly 100% (margins count in
    --horizontal flow), so nothing wraps as the panel is resized.
    local CreateZoneGroupHeader = function(group)
        local gradient = m_zoneStripes.Gradient(group.patternColor, group.patternAngle)
        local swatchColor = group.patternColor
        if gradient ~= nil then
            swatchColor = "white"
        end

        local ApplyOpacity = function(element)
            m_zoneStripes.SetOpacity(group.key, element.value)
        end

        return gui.Panel{
            width = "100%",
            height = 20,
            halign = "center",
            flow = "horizontal",
            vmargin = 3,

            --hmargin 4 lines the swatch up with the row swatches below, which
            --are inset by the chip's own pad of 4.
            gui.Panel{
                width = 14,
                height = 14,
                hmargin = 4,
                valign = "center",
                bgimage = true,
                bgcolor = swatchColor,
                gradient = gradient,
                borderWidth = 1,
                borderColor = "@border",
            },

            gui.Label{
                classes = {"markupSectionHeader"},
                text = string.format("%s (%d)", group.name, #group.entries),
                uppercase = true,
                width = "100%-118",
                height = "auto",
                valign = "center",
            },

            --transient and local: nothing here is written to the map, a
            --setting or the players' clients. See m_zoneStripes.opacity.
            gui.PercentSlider{
                width = 88,
                hmargin = 4,
                valign = "center",
                styles = m_zoneStripes.OpacitySliderStyles(),
                value = m_zoneStripes.Opacity(group.key),
                hover = gui.Tooltip("Fades this zone type on the map so you can see what is under it. A local viewing aid only - it is not saved, and players never see it."),
                --a drag fires 'preview' per frame and 'confirm' on release;
                --a click on the bar fires 'confirm' alone. All three land on
                --the same handler so the map tracks the bar live.
                preview = ApplyOpacity,
                change = ApplyOpacity,
                confirm = ApplyOpacity,
            },
        }
    end

    --Same icon-over-caption chips as the walls tool strip, with the eraser
    --behind a divider and tinted @danger.
    local BuildZoneToolButtons = function()
        local result = {}
        local dividerAdded = false
        for _,toolInfo in ipairs(ZONE_TOOLS) do
            local destructive = toolInfo.erase == true
            if destructive and not dividerAdded then
                dividerAdded = true
                result[#result+1] = gui.Panel{
                    classes = {"markupToolDivider"},
                    bgimage = true,
                    width = 1,
                    height = "70%",
                    valign = "center",
                    hmargin = 4,
                    data = {},
                }
            end

            local chipClasses = {"markupToolChip"}
            if toolInfo.id == m_zoneToolId then
                chipClasses[#chipClasses+1] = "selected"
            end
            if destructive then
                chipClasses[#chipClasses+1] = "danger"
            end

            result[#result+1] = gui.Panel{
                classes = chipClasses,
                width = 44,
                height = 42,
                flow = "vertical",
                bgimage = true,
                borderBox = true,
                valign = "center",
                hmargin = 1,
                hover = SideTooltip(toolInfo.help),
                data = {
                    toolid = toolInfo.id,
                },
                press = function(element)
                    m_zoneToolId = element.data.toolid
                    zoneToolsPanel:FireEvent("refreshzonetools")
                    --focus + immediate tool registration; TakeMarkupFocus
                    --parks focus on contentPanel (chips are transient) and
                    --re-fires this strip's think.
                    TakeMarkupFocus()
                end,

                gui.Panel{
                    classes = {"markupToolIcon", cond(destructive, "danger")},
                    bgimage = toolInfo.icon,
                    width = 18,
                    height = 18,
                    halign = "center",
                    vmargin = 3,
                },

                gui.Label{
                    classes = {"markupToolLabel", cond(destructive, "danger")},
                    text = toolInfo.text or "",
                    width = "100%",
                    height = "auto",
                    textAlignment = "center",
                },
            }
        end
        return result
    end

    zoneToolsPanel = gui.Panel{
        width = "96%",
        height = 48,
        halign = "center",
        flow = "horizontal",

        --keep the custom map tool alive: the engine expires custom tools
        --after ~1s, and every registration returns a fresh event source that
        --must be listened to again.
        thinkTime = 0.3,

        events = {
            refreshzonetools = function(element)
                for _,child in ipairs(element.children) do
                    child:SetClass("selected", child.data.toolid == m_zoneToolId)
                end
            end,

            think = function(element)
                if m_mode ~= "zones" or not ZonesSupported() then
                    return
                end

                local toolInfo = ZoneToolById(m_zoneToolId)
                if toolInfo == nil then
                    return
                end

                if not m_arm.Armed() then
                    return
                end

                local eventSource = editor:SetMapTool{
                    tool = toolInfo.mapTool,
                    closed = true,
                    expires = 1,
                    stabilization = 0,
                    snapToGrid = true,
                    --Show the engine's editor cursor dot (where a stroke would
                    --start), like the Building editor's tools do. Older
                    --engines ignore the field.
                    editorCursor = true,
                    --Draw the stroke preview in the erase colour (red) rather
                    --than white: a custom map tool never sets building:erase,
                    --so the engine cannot tell on its own. Display only; older
                    --engines ignore the field.
                    erase = toolInfo.erase == true,
                }
                if eventSource ~= nil then
                    eventSource:Listen(element)
                end
            end,

            tool = function(element, path)
                if m_mode ~= "zones" or path == nil then
                    return
                end
                local toolInfo = ZoneToolById(m_zoneToolId)
                if toolInfo == nil then
                    return
                end
                if toolInfo.erase then
                    element:FireEvent("zoneerase", path)
                else
                    element:FireEvent("zonepaint", path)
                end
            end,

            --closed stroke: rasterize to tiles and merge into the target zone
            --of the selected type (creating one when none exists).
            zonepaint = function(element, path)
                local floor = game.currentFloor
                if floor == nil or not ZonesSupported() then
                    return
                end

                local ok, points = pcall(function()
                    return path.points
                end)
                if not ok or points == nil or #points < 6 then
                    if not ok then
                        dmhub.Debug("MARKUP:: zone painting needs an engine build with MapPath points support")
                    end
                    return
                end

                local locs = PolygonToLocs(points)
                if #locs == 0 then
                    return
                end

                --the built-in Hole type: keep the drawn polygon and cut a
                --real hole instead of painting a keyword zone. None of the
                --keyword machinery below (dispels, contiguity merging)
                --applies to holes.
                local selectedEntry = m_zonePaletteEntries[m_zoneSelectedType]
                if selectedEntry ~= nil and selectedEntry.kind == "hole" then
                    m_holes.Paint(floor, points, locs)
                    RefreshZoneUI()
                    return
                end

                local keywordid = EnsureZoneTypeKeyword(m_zoneSelectedType)
                if keywordid == nil then
                    dmhub.Debug("MARKUP:: no valid zone type selected; stroke ignored")
                    return
                end

                --what the selected chip calls this type: used to name a new
                --zone (and to heal by name) when the keyword upload hasn't
                --landed locally yet.
                local fallbackInfo = nil
                local paletteEntry = m_zonePaletteEntries[m_zoneSelectedType]
                if paletteEntry ~= nil and paletteEntry.kind == "preset" then
                    local preset = ZONE_PRESETS_BY_KEY[paletteEntry.key]
                    if preset ~= nil then
                        fallbackInfo = { name = preset.name, color = preset.color }
                    end
                end

                --Dispel interactions with zones of OTHER types
                --(EnvironmentalKeyword.dispels), resolved at paint time by
                --editing the records: tiles of a type dispelled by the
                --painted type are DELETED where the stroke covers them, and
                --conversely the stroke cannot paint over a zone whose type
                --dispels the painted type (those tiles drop out of the
                --stroke). When two types dispel each other, the painted one
                --wins -- last drawn takes the ground.
                local paintedDispels = KeywordDispels(GetKeyword(keywordid))
                local dispelBlocked = {}
                for _,entry in ipairs(ZonesOnFloor(floor.floorid)) do
                    if entry.keywordid ~= nil and entry.keywordid ~= keywordid
                        and paintedDispels[entry.keywordid] == nil
                        and KeywordDispels(entry.keywordInfo)[keywordid] ~= nil then
                        for _,l in ipairs(entry.locs) do
                            dispelBlocked[ZoneLocKey(l.x, l.y)] = true
                        end
                    end
                end
                if next(dispelBlocked) ~= nil then
                    local kept = {}
                    for _,l in ipairs(locs) do
                        if dispelBlocked[ZoneLocKey(l.x, l.y)] == nil then
                            kept[#kept+1] = l
                        end
                    end
                    locs = kept
                    if #locs == 0 then
                        dmhub.Debug("MARKUP:: stroke entirely inside a zone type that dispels the painted type; nothing painted")
                        return
                    end
                end

                --Contiguity-based painting: the stroke joins the same-type
                --zones it overlaps or borders (bridging strokes unify them
                --into one record); a stroke touching none becomes its own
                --new zone. Non-contiguous results are auto-split, so one
                --zone record = one contiguous region on the map.
                local strokeSet = {}
                for _,l in ipairs(locs) do
                    strokeSet[ZoneLocKey(l.x, l.y)] = true
                end

                --zones of a type the painted type dispels lose the stroke's
                --tiles (applied inside the stroke's transaction below).
                local dispelEdits = {}
                if next(paintedDispels) ~= nil then
                    for _,entry in ipairs(ZonesOnFloor(floor.floorid)) do
                        if entry.keywordid ~= nil and entry.keywordid ~= keywordid
                            and paintedDispels[entry.keywordid] ~= nil then
                            local kept = {}
                            local removedAny = false
                            for _,l in ipairs(entry.locs) do
                                if strokeSet[ZoneLocKey(l.x, l.y)] then
                                    removedAny = true
                                else
                                    kept[#kept+1] = { x = l.x, y = l.y }
                                end
                            end
                            if removedAny then
                                dispelEdits[#dispelEdits+1] = { entry = entry, kept = kept }
                            end
                        end
                    end
                end

                local touched = {}
                for _,entry in ipairs(ZonesOnFloor(floor.floorid)) do
                    if entry.keywordid == keywordid then
                        for _,l in ipairs(entry.locs) do
                            if strokeSet[ZoneLocKey(l.x, l.y)]
                                or strokeSet[ZoneLocKey(l.x + 1, l.y)]
                                or strokeSet[ZoneLocKey(l.x - 1, l.y)]
                                or strokeSet[ZoneLocKey(l.x, l.y + 1)]
                                or strokeSet[ZoneLocKey(l.x, l.y - 1)] then
                                touched[#touched+1] = entry
                                break
                            end
                        end
                    end
                end

                if #touched == 0 then
                    --a (rare) self-intersecting freehand stroke can rasterize
                    --to several separate regions: one zone per region.
                    local components = SplitContiguousComponents(locs)
                    dmhub.BeginTransaction()
                    for _,edit in ipairs(dispelEdits) do
                        --deletes emptied zones, splits bisected ones.
                        WriteZoneLocsSplitting(floor, edit.entry, edit.kept)
                    end
                    for i,component in ipairs(components) do
                        local zoneid = CreateZone(keywordid, component, fallbackInfo)
                        if i == 1 then
                            m_zoneTargetId = zoneid
                        end
                    end
                    dmhub.EndTransaction()
                else
                    --primary keeps its identity/settings: the targeted zone
                    --when the stroke touches it, else the largest touched.
                    local primary = nil
                    for _,entry in ipairs(touched) do
                        if primary == nil or #entry.locs > #primary.locs then
                            primary = entry
                        end
                    end
                    for _,entry in ipairs(touched) do
                        if entry.zoneid == m_zoneTargetId then
                            primary = entry
                        end
                    end

                    local seen = {}
                    local newLocs = {}
                    local AddLoc = function(x, y)
                        local key = ZoneLocKey(x, y)
                        if not seen[key] then
                            seen[key] = true
                            newLocs[#newLocs+1] = { x = x, y = y }
                        end
                    end
                    for _,entry in ipairs(touched) do
                        for _,l in ipairs(entry.locs) do
                            AddLoc(l.x, l.y)
                        end
                    end
                    for _,l in ipairs(locs) do
                        AddLoc(l.x, l.y)
                    end

                    dmhub.BeginTransaction()
                    for _,edit in ipairs(dispelEdits) do
                        --deletes emptied zones, splits bisected ones.
                        WriteZoneLocsSplitting(floor, edit.entry, edit.kept)
                    end
                    for _,entry in ipairs(touched) do
                        if entry.zoneid ~= primary.zoneid then
                            floor:RemoveMarkupZone(entry.zoneid)
                        end
                    end
                    WriteZoneLocsSplitting(floor, primary, newLocs)
                    dmhub.EndTransaction()

                    m_zoneTargetId = primary.zoneid
                end

                RefreshZoneUI()
            end,

            --eraser stroke: remove the region's tiles from every zone on the
            --floor; zones left empty are deleted. One undo step per stroke.
            zoneerase = function(element, path)
                local floor = game.currentFloor
                if floor == nil or not ZonesSupported() then
                    return
                end

                local ok, points = pcall(function()
                    return path.points
                end)
                if not ok or points == nil or #points < 6 then
                    return
                end

                local locs = PolygonToLocs(points)
                if #locs == 0 then
                    return
                end

                local remove = {}
                for _,l in ipairs(locs) do
                    remove[ZoneLocKey(l.x, l.y)] = true
                end

                local edits = {}
                for _,entry in ipairs(ZonesOnFloor(floor.floorid)) do
                    local kept = {}
                    local removedAny = false
                    for _,l in ipairs(entry.locs) do
                        if remove[ZoneLocKey(l.x, l.y)] then
                            removedAny = true
                        else
                            kept[#kept+1] = { x = l.x, y = l.y }
                        end
                    end
                    if removedAny then
                        edits[#edits+1] = { entry = entry, kept = kept }
                    end
                end

                --holes erase by CLIPPING, like floor erasing: the erase
                --region is subtracted from each touched hole's polygons
                --(dmhub.ClipPolygons, Clipper-backed), so erasing across a
                --hole trims or bisects the shape rather than deleting it. A
                --rect erased from the middle leaves a donut ({points, holes}
                --entries); a fully covered hole deletes its record. The
                --stroke's own polygon is the clip region -- the geometric
                --shape, not the rasterized tiles the zone edits use. The
                --cache is fresh here (ZonesOnFloor ran EnsureZoneCache).
                --Fallback on engines without ClipPolygons: delete any hole
                --shape the region's tiles touch, whole.
                local holeEdits = {}
                local clipSupported = false
                pcall(function()
                    clipSupported = dmhub.ClipPolygons ~= nil
                end)
                if clipSupported then
                    local eraseRing = {}
                    for i = 1,#points do
                        eraseRing[i] = points[i]
                    end
                    for _,entry in ipairs(m_holes.cache) do
                        if entry.floorid == floor.floorid and #entry.polygons > 0 then
                            local ok, touched = pcall(function()
                                local inter = dmhub.ClipPolygons{
                                    subjects = entry.polygons,
                                    clips = { eraseRing },
                                    operation = "intersection",
                                }
                                return #inter > 0
                            end)
                            if ok and touched then
                                local okDiff, clipped = pcall(function()
                                    return dmhub.ClipPolygons{
                                        subjects = entry.polygons,
                                        clips = { eraseRing },
                                        operation = "difference",
                                    }
                                end)
                                if okDiff and clipped ~= nil then
                                    holeEdits[#holeEdits+1] = { entry = entry, polygons = clipped }
                                end
                            end
                        end
                    end
                else
                    for _,entry in ipairs(m_holes.cache) do
                        if entry.floorid == floor.floorid then
                            for _,l in ipairs(entry.locs) do
                                if remove[ZoneLocKey(l.x, l.y)] then
                                    holeEdits[#holeEdits+1] = { entry = entry, polygons = {} }
                                    break
                                end
                            end
                        end
                    end
                end

                if #edits == 0 and #holeEdits == 0 then
                    return
                end

                dmhub.BeginTransaction()
                for _,edit in ipairs(edits) do
                    --deletes emptied zones, and splits a zone the erase cut
                    --in half into separate records (one per region).
                    WriteZoneLocsSplitting(floor, edit.entry, edit.kept)
                    if #edit.kept == 0 and m_zoneTargetId == edit.entry.zoneid then
                        m_zoneTargetId = nil
                    end
                end
                for _,edit in ipairs(holeEdits) do
                    if #edit.polygons == 0 then
                        floor:RemoveMarkupZone(edit.entry.zoneid)
                    else
                        floor:SetMarkupZone(edit.entry.zoneid, {
                            category = "hole",
                            polygons = edit.polygons,
                            locs = m_holes.EntryLocs(edit.polygons),
                        })
                    end
                end
                dmhub.EndTransaction()

                RefreshZoneUI()
            end,
        },

        children = BuildZoneToolButtons(),
    }

    zoneListPanel = gui.Panel{
        width = "96%",
        height = "auto",
        halign = "center",
        flow = "vertical",

        --cheap change detection: the records (any client) or the current
        --floor changing rebuilds the list.
        thinkTime = 0.5,

        data = {
            seq = nil,
            floorid = nil,
        },

        events = {
            think = function(element)
                if m_mode ~= "zones" or not ZonesSupported() then
                    return
                end
                if dmhub.markupZonesSeq ~= element.data.seq or game.currentFloorId ~= element.data.floorid then
                    element:FireEvent("refreshzones")
                end
            end,

            refreshzones = function(element)
                if not ZonesSupported() then
                    return
                end

                --split any legacy multi-region records first, THEN snapshot
                --the sequence: the snapshot includes the normalization writes,
                --so the think loop doesn't immediately re-fire this event.
                NormalizeZonesOnFloor(game.currentFloorId)

                element.data.seq = dmhub.markupZonesSeq
                element.data.floorid = game.currentFloorId

                --grouped by zone type, each group under its own header (which
                --carries the type's opacity slider).
                local children = {}
                if element.data.floorid ~= nil then
                    for _,group in ipairs(GroupZonesOnFloor(element.data.floorid)) do
                        children[#children+1] = CreateZoneGroupHeader(group)
                        for _,entry in ipairs(group.entries) do
                            children[#children+1] = CreateZoneRow(entry)
                        end
                    end
                end

                if #children == 0 then
                    children[#children+1] = gui.Label{
                        classes = {"fgMuted", "sizeXs"},
                        text = "No zones on this floor yet. Pick a zone type and paint on the map.",
                        width = "90%",
                        height = "auto",
                        halign = "center",
                        vmargin = 4,
                        textAlignment = "center",
                    }
                end

                element.children = children
            end,
        },
    }

    zonesPanel = gui.Panel{
        classes = {cond(m_mode ~= "zones", "collapsed")},
        width = "100%",
        height = "auto",
        flow = "vertical",

        markupmode = function(element)
            element:SetClass("collapsed", m_mode ~= "zones")
            if m_mode == "zones" then
                zonePalettePanel:FireEvent("refreshzonepalette")
                zoneListPanel:FireEvent("refreshzones")
            end
        end,

        gui.Label{
            classes = {"fgMuted", cond(ZonesSupported(), "collapsed")},
            text = "Zones need an engine build with markup zone support.",
            width = "90%",
            height = "auto",
            halign = "center",
            vmargin = 8,
            textAlignment = "center",
        },

        --Tool first, matching the walls tab: fixed controls at a stable
        --position on top, the growable type list below.
        SectionHeader("Tool"),

        zoneToolsPanel,

        SectionHeader("Zone Types"),

        zonePalettePanel,

        zoneAddButton,

        SectionHeader("Zones on This Floor"),

        zoneListPanel,
    }

    --========================================================================
    --Footsteps mode UI: map default dropdown, the fixed surface-family
    --palette (with sound previews), paint tools, and the per-floor list.
    --========================================================================

    local footstepPalettePanel
    local footstepToolsPanel
    local footstepListPanel
    local footstepsPanel
    local footstepDefaultDropdown

    local RefreshFootstepUI = function()
        if footstepsPanel ~= nil and footstepsPanel.valid then
            footstepsPanel:FireEventTree("refreshfootsteps")
        end
    end

    --Grid chip: name at the left, sound-preview play button, then a square
    --color swatch at the right edge - the walls/zones row treatment, kept
    --two per row since surfaces are a short fixed set with no summaries.
    --"50%-2" plus 1px side margins makes each pair span the full content
    --column, so the grid's outer edges line up with the sections above.
    local CreateFootstepChip = function(surfaceInfo)
        return gui.Panel{
            classes = {"markupChip", cond(surfaceInfo.id == m_footstepSelected, "selected")},
            width = "50%-2",
            height = 32,
            flow = "horizontal",
            bgimage = true,
            pad = 4,
            borderBox = true,
            hmargin = 1,
            vmargin = 1,

            data = {
                surfaceid = surfaceInfo.id,
            },

            press = function(element)
                m_footstepSelected = element.data.surfaceid
                footstepPalettePanel:FireEvent("refreshchips")
                --picking a surface must arm the paint tool by itself; see
                --TakeMarkupFocus.
                TakeMarkupFocus()
                --hear what was just selected. The play button still has a
                --job: auditioning a surface WITHOUT changing the selection.
                PlaySurfaceSample(surfaceInfo)
            end,

            --Swatch on the LEFT here, unlike the walls/zones rows: it is the
            --surface's identity mark, like the zone list rows' swatches.
            gui.Panel{
                width = 22,
                height = 22,
                valign = "center",
                bgimage = true,
                bgcolor = SurfaceColor(surfaceInfo.id),
                borderWidth = 1,
                borderColor = "@border",
            },

            gui.Label{
                classes = {"bold", "sizeXs"},
                text = surfaceInfo.text,
                width = "100%-50",
                height = "auto",
                hmargin = 4,
                valign = "center",
            },

            gui.Panel{
                --markupToolIcon for the themed icon tint: inline "@token"
                --fields do not resolve (they ship the literal string and
                --render black), only style rules routed through the cascade.
                classes = {"markupToolIcon"},
                width = 16,
                height = 16,
                valign = "center",
                bgimage = "ui-icons/ph-play-fill.png",
                hover = SideTooltip("Preview this footstep sound."),
                press = function()
                    PlaySurfaceSample(surfaceInfo)
                end,
            },
        }
    end

    footstepPalettePanel = gui.Panel{
        width = "96%",
        height = "auto",
        halign = "center",
        flow = "horizontal",
        wrap = true,

        events = {
            refreshchips = function(element)
                for _,chip in ipairs(element.children) do
                    if chip.data ~= nil and chip.data.surfaceid ~= nil then
                        chip:SetClass("selected", chip.data.surfaceid == m_footstepSelected)
                    end
                end
            end,
        },

        children = (function()
            local chips = {}
            for _,info in ipairs(SurfaceRegistry()) do
                chips[#chips+1] = CreateFootstepChip(info)
            end
            return chips
        end)(),
    }

    local BuildFootstepDefaultOptions = function()
        local options = {
            --0 = no default: tiles keep whatever surface their art carries
            --(Generic where none). Any other choice overrides tile-derived
            --surfaces map-wide; painted footstep regions and water still win.
            { id = "0", text = "None - Use Tile Surfaces" },
        }
        for _,info in ipairs(SurfaceRegistry()) do
            options[#options+1] = { id = tostring(info.id), text = info.text }
        end
        return options
    end

    footstepDefaultDropdown = gui.Dropdown{
        width = 200,
        height = 26,
        idChosen = tostring(math.floor(tonumber(g_footstepDefaultSetting:Get()) or 0)),
        options = BuildFootstepDefaultOptions(),
        change = function(element)
            g_footstepDefaultSetting:Set(tonumber(element.idChosen) or 0)
        end,
    }

    local footstepDefaultRow = gui.Panel{
        width = "96%",
        height = "auto",
        halign = "center",
        flow = "horizontal",

        --re-sync on remote changes and on map switches (the map's value is
        --the effective value; the monitor fires for both).
        multimonitor = {"markup:footstepdefault"},

        events = {
            monitor = function(element)
                local current = tostring(math.floor(tonumber(g_footstepDefaultSetting:Get()) or 0))
                if footstepDefaultDropdown.idChosen ~= current then
                    footstepDefaultDropdown.idChosen = current
                end
            end,
        },

        footstepDefaultDropdown,

        gui.Panel{
            --markupToolIcon for the themed icon tint; see the chip play icon.
            classes = {"markupToolIcon"},
            width = 18,
            height = 18,
            valign = "center",
            hmargin = 8,
            bgimage = "ui-icons/ph-play-fill.png",
            hover = SideTooltip("Preview the default footstep sound."),
            press = function()
                local defaultSurface = math.floor(tonumber(g_footstepDefaultSetting:Get()) or 0)
                PlaySurfaceSample(SurfaceInfoById(defaultSurface))
            end,
        },
    }

    --Same icon-over-caption chips as the walls tool strip, with the eraser
    --behind a divider and tinted @danger.
    local BuildFootstepToolButtons = function()
        local result = {}
        local dividerAdded = false
        for _,toolInfo in ipairs(FOOTSTEP_TOOLS) do
            local destructive = toolInfo.erase == true
            if destructive and not dividerAdded then
                dividerAdded = true
                result[#result+1] = gui.Panel{
                    classes = {"markupToolDivider"},
                    bgimage = true,
                    width = 1,
                    height = "70%",
                    valign = "center",
                    hmargin = 4,
                    data = {},
                }
            end

            local chipClasses = {"markupToolChip"}
            if toolInfo.id == m_footstepToolId then
                chipClasses[#chipClasses+1] = "selected"
            end
            if destructive then
                chipClasses[#chipClasses+1] = "danger"
            end

            result[#result+1] = gui.Panel{
                classes = chipClasses,
                width = 44,
                height = 42,
                flow = "vertical",
                bgimage = true,
                borderBox = true,
                valign = "center",
                hmargin = 1,
                hover = SideTooltip(toolInfo.help),
                data = {
                    toolid = toolInfo.id,
                },
                press = function(element)
                    m_footstepToolId = element.data.toolid
                    footstepToolsPanel:FireEvent("refreshfoottools")
                    --focus + immediate tool registration; TakeMarkupFocus
                    --parks focus on contentPanel (chips are transient) and
                    --re-fires this strip's think.
                    TakeMarkupFocus()
                end,

                gui.Panel{
                    classes = {"markupToolIcon", cond(destructive, "danger")},
                    bgimage = toolInfo.icon,
                    width = 18,
                    height = 18,
                    halign = "center",
                    vmargin = 3,
                },

                gui.Label{
                    classes = {"markupToolLabel", cond(destructive, "danger")},
                    text = toolInfo.text or "",
                    width = "100%",
                    height = "auto",
                    textAlignment = "center",
                },
            }
        end
        return result
    end

    footstepToolsPanel = gui.Panel{
        width = "96%",
        height = 48,
        halign = "center",
        flow = "horizontal",

        --keep the custom map tool alive: the engine expires custom tools
        --after ~1s, and every registration returns a fresh event source that
        --must be listened to again.
        thinkTime = 0.3,

        events = {
            refreshfoottools = function(element)
                for _,child in ipairs(element.children) do
                    child:SetClass("selected", child.data.toolid == m_footstepToolId)
                end
            end,

            think = function(element)
                if m_mode ~= "surfaces" or not ZonesSupported() then
                    return
                end

                local toolInfo = FootstepToolById(m_footstepToolId)
                if toolInfo == nil then
                    return
                end

                if not m_arm.Armed() then
                    return
                end

                local eventSource = editor:SetMapTool{
                    tool = toolInfo.mapTool,
                    closed = true,
                    expires = 1,
                    stabilization = 0,
                    snapToGrid = true,
                    --Show the engine's editor cursor dot (where a stroke would
                    --start), like the Building editor's tools do. Older
                    --engines ignore the field.
                    editorCursor = true,
                    --Draw the stroke preview in the erase colour (red) rather
                    --than white: a custom map tool never sets building:erase,
                    --so the engine cannot tell on its own. Display only; older
                    --engines ignore the field.
                    erase = toolInfo.erase == true,
                }
                if eventSource ~= nil then
                    eventSource:Listen(element)
                end
            end,

            tool = function(element, path)
                if m_mode ~= "surfaces" or path == nil then
                    return
                end
                local toolInfo = FootstepToolById(m_footstepToolId)
                if toolInfo == nil then
                    return
                end
                if toolInfo.erase then
                    element:FireEvent("footerase", path)
                else
                    element:FireEvent("footpaint", path)
                end
            end,

            --closed stroke: rasterize to tiles, strip them from every other
            --surface family (exclusive per tile), and merge them into the
            --selected family's one record on this floor.
            footpaint = function(element, path)
                local floor = game.currentFloor
                if floor == nil or not ZonesSupported() then
                    return
                end

                local ok, points = pcall(function()
                    return path.points
                end)
                if not ok or points == nil or #points < 6 then
                    if not ok then
                        dmhub.Debug("MARKUP:: surface painting needs an engine build with MapPath points support")
                    end
                    return
                end

                local locs = PolygonToLocs(points)
                if #locs == 0 then
                    return
                end

                if SurfaceInfoById(m_footstepSelected) == nil then
                    dmhub.Debug("MARKUP:: no valid footstep surface selected; stroke ignored")
                    return
                end

                local strokeSet = {}
                for _,l in ipairs(locs) do
                    strokeSet[ZoneLocKey(l.x, l.y)] = true
                end

                local selectedLocs = nil
                local edits = {}
                for _,entry in ipairs(SurfacesOnFloor(floor.floorid)) do
                    if entry.surface == m_footstepSelected then
                        selectedLocs = entry.locs
                    else
                        local kept = {}
                        local removedAny = false
                        for _,l in ipairs(entry.locs) do
                            if strokeSet[ZoneLocKey(l.x, l.y)] then
                                removedAny = true
                            else
                                kept[#kept+1] = { x = l.x, y = l.y }
                            end
                        end
                        if removedAny then
                            edits[#edits+1] = { surface = entry.surface, locs = kept }
                        end
                    end
                end

                local seen = {}
                local newLocs = {}
                local AddLoc = function(x, y)
                    local key = ZoneLocKey(x, y)
                    if not seen[key] then
                        seen[key] = true
                        newLocs[#newLocs+1] = { x = x, y = y }
                    end
                end
                for _,l in ipairs(selectedLocs or {}) do
                    AddLoc(l.x, l.y)
                end
                for _,l in ipairs(locs) do
                    AddLoc(l.x, l.y)
                end

                dmhub.BeginTransaction()
                for _,edit in ipairs(edits) do
                    WriteSurfaceLocs(floor, edit.surface, edit.locs)
                end
                WriteSurfaceLocs(floor, m_footstepSelected, newLocs)
                dmhub.EndTransaction()

                RefreshFootstepUI()
            end,

            --eraser stroke: clear the region's tiles from every surface
            --family on the floor. One undo step per stroke.
            footerase = function(element, path)
                local floor = game.currentFloor
                if floor == nil or not ZonesSupported() then
                    return
                end

                local ok, points = pcall(function()
                    return path.points
                end)
                if not ok or points == nil or #points < 6 then
                    return
                end

                local locs = PolygonToLocs(points)
                if #locs == 0 then
                    return
                end

                local remove = {}
                for _,l in ipairs(locs) do
                    remove[ZoneLocKey(l.x, l.y)] = true
                end

                local edits = {}
                for _,entry in ipairs(SurfacesOnFloor(floor.floorid)) do
                    local kept = {}
                    local removedAny = false
                    for _,l in ipairs(entry.locs) do
                        if remove[ZoneLocKey(l.x, l.y)] then
                            removedAny = true
                        else
                            kept[#kept+1] = { x = l.x, y = l.y }
                        end
                    end
                    if removedAny then
                        edits[#edits+1] = { surface = entry.surface, locs = kept }
                    end
                end

                if #edits == 0 then
                    return
                end

                dmhub.BeginTransaction()
                for _,edit in ipairs(edits) do
                    WriteSurfaceLocs(floor, edit.surface, edit.locs)
                end
                dmhub.EndTransaction()

                RefreshFootstepUI()
            end,
        },

        children = BuildFootstepToolButtons(),
    }

    local CreateFootstepRow = function(entry)
        --Same enlarged swatch treatment as the zone rows.
        local rowGradient = m_zoneStripes.Gradient(entry.patternColor, entry.patternAngle)
        local rowSwatchColor = entry.patternColor
        if rowGradient ~= nil then
            rowSwatchColor = "white"
        end

        return gui.Panel{
            classes = {"markupChip"},
            --footstepListPanel is already the 96% content column; fill it.
            width = "100%",
            height = 32,
            halign = "center",
            flow = "horizontal",
            bgimage = true,
            pad = 4,
            borderBox = true,
            vmargin = 1,

            hover = SideTooltip("Click to select this surface and show it on the map. Right-click for options."),

            press = function(element)
                m_footstepSelected = entry.surface
                footstepPalettePanel:FireEvent("refreshchips")
                JumpToZone(entry)
                TakeMarkupFocus()
                --hear what was just selected: the row IS the surface, so the
                --click doubles as the sound preview.
                PlaySurfaceSample(SurfaceInfoById(entry.surface))
            end,

            rightClick = function(element)
                element.popup = gui.ContextMenu{
                    entries = {
                        {
                            text = "Clear From This Floor",
                            click = function()
                                element.popup = nil
                                local floor = game.currentFloor
                                if floor ~= nil then
                                    WriteSurfaceLocs(floor, entry.surface, {})
                                    RefreshFootstepUI()
                                end
                            end,
                        },
                    },
                }
            end,

            gui.Panel{
                width = 24,
                height = 24,
                valign = "center",
                bgimage = true,
                bgcolor = rowSwatchColor,
                gradient = rowGradient,
                borderWidth = 1,
                borderColor = "@border",
            },

            gui.Label{
                classes = {"bold", "sizeXs"},
                text = entry.name,
                width = "50%",
                height = "auto",
                hmargin = 4,
                valign = "center",
            },

            gui.Label{
                classes = {"fgMuted", "sizeXs"},
                text = string.format("%d tiles", #entry.locs),
                width = "auto",
                height = "auto",
                valign = "center",
            },
        }
    end

    footstepListPanel = gui.Panel{
        width = "96%",
        height = "auto",
        halign = "center",
        flow = "vertical",

        --cheap change detection: the records (any client) or the current
        --floor changing rebuilds the list.
        thinkTime = 0.5,

        data = {
            seq = nil,
            floorid = nil,
            popupDeferred = false,
        },

        events = {
            think = function(element)
                if m_mode ~= "surfaces" or not ZonesSupported() then
                    return
                end
                if element.data.popupDeferred or dmhub.markupZonesSeq ~= element.data.seq or game.currentFloorId ~= element.data.floorid then
                    element:FireEvent("refreshfootsteps")
                end
            end,

            refreshfootsteps = function(element)
                if not ZonesSupported() then
                    return
                end

                --a rebuild would destroy the row a context menu hangs off, so
                --stand down and let the think poll above retry once the menu
                --is gone.
                if gui.SubtreeHasPopup(element) then
                    element.data.popupDeferred = true
                    return
                end
                element.data.popupDeferred = false

                element.data.seq = dmhub.markupZonesSeq
                element.data.floorid = game.currentFloorId

                local children = {}
                if element.data.floorid ~= nil then
                    for _,entry in ipairs(SurfacesOnFloor(element.data.floorid)) do
                        children[#children+1] = CreateFootstepRow(entry)
                    end
                end

                if #children == 0 then
                    children[#children+1] = gui.Label{
                        classes = {"fgMuted", "sizeXs"},
                        text = "No footstep surfaces painted on this floor yet. Pick a surface and paint on the map.",
                        width = "90%",
                        height = "auto",
                        halign = "center",
                        vmargin = 4,
                        textAlignment = "center",
                    }
                end

                element.children = children
            end,
        },
    }

    footstepsPanel = gui.Panel{
        classes = {cond(m_mode ~= "surfaces", "collapsed")},
        width = "100%",
        height = "auto",
        flow = "vertical",

        markupmode = function(element)
            element:SetClass("collapsed", m_mode ~= "surfaces")
            if m_mode == "surfaces" then
                footstepPalettePanel:FireEvent("refreshchips")
                footstepListPanel:FireEvent("refreshfootsteps")
            end
        end,

        gui.Label{
            classes = {"fgMuted", cond(ZonesSupported(), "collapsed")},
            text = "Footsteps need an engine build with markup zone support.",
            width = "90%",
            height = "auto",
            halign = "center",
            vmargin = 8,
            textAlignment = "center",
        },

        --Tool first, matching the other tabs: fixed controls at a stable
        --position on top.
        SectionHeader("Tool"),

        footstepToolsPanel,

        SectionHeader("Map Default"),

        footstepDefaultRow,

        gui.Label{
            classes = {"fgMuted", "sizeXs"},
            text = "What this map's ground sounds like, overriding any surface the map's tiles carry. Painted regions override it; water always sounds like water, and flying creatures never make footsteps.",
            width = "94%",
            height = "auto",
            halign = "center",
            vmargin = 2,
        },

        SectionHeader("Paint Surface"),

        footstepPalettePanel,

        SectionHeader("Footsteps on This Floor"),

        footstepListPanel,
    }

    --========================================================================
    --Elevation mode UI: for now a straight clone of the Elevation Editor dock
    --panel (DMHub Core Panels/ElevationPanel.lua). It drives the very same
    --"heightmap:*" settings, so the two panels stay in sync automatically;
    --what makes painting actually happen from here is the focus-gated
    --GetHeightEditingInfo chain at the bottom of this file.
    --========================================================================

    --Every form-style setting in this mode uses the stacked (label-above-
    --control) layout, matching the Elevation Editor.
    local elevationStackedOpts = {stacked = true}

    local function SlopeHintVisible()
        local tool = dmhub.GetSettingValue("heightmaptool")
        local toolUsesGradient = tool == "rectangle" or tool == "oval" or tool == "shape"
        return toolUsesGradient and dmhub.GetSettingValue("heightmap:gradient") == "slope"
    end

    --The brush strip is owned by DMHub Core Panels/Brush.lua; that module
    --exports it as a global for us (mod.shared is per-module). rawget: reading
    --an undeclared global errors in the DMHub Lua runtime.
    local elevationBrushPanel = nil
    local brushEditorPanel = rawget(_G, "BrushEditorPanel")
    if brushEditorPanel ~= nil then
        elevationBrushPanel = gui.Panel{
            classes = {cond(dmhub.GetSettingValue("heightmaptool") ~= "brush", "collapsed")},
            width = "auto",
            height = "auto",
            halign = "center",
            monitor = "heightmaptool",
            events = {
                monitor = function(element)
                    element:SetClass("collapsed", dmhub.GetSettingValue("heightmaptool") ~= "brush")
                end,
            },
            brushEditorPanel("heightmapbrush"),
        }
    end

    --The heightmaptool selector as the same icon-over-caption chips the other
    --tabs use, driving the shared setting - the real Elevation Editor stays
    --in sync through its own monitor. Options come from the setting's enum so
    --a new engine tool appears here automatically (with its value as the
    --label until one is curated).
    local ELEVATION_TOOL_LABELS = {
        rectangle = "Rect",
        oval = "Oval",
        shape = "Poly",
        brush = "Brush",
        picker = "Picker",
    }

    local elevationToolsPanel = gui.Panel{
        width = "96%",
        height = 48,
        halign = "center",
        flow = "horizontal",

        monitor = "heightmaptool",

        events = {
            monitor = function(element)
                local current = dmhub.GetSettingValue("heightmaptool")
                for _,child in ipairs(element.children) do
                    child:SetClass("selected", child.data.toolvalue == current)
                end
            end,
        },

        children = (function()
            local result = {}
            local settingInfo = Settings["heightmaptool"]
            local enum = {}
            if settingInfo ~= nil and settingInfo.enum ~= nil then
                enum = settingInfo.enum
            end
            local current = dmhub.GetSettingValue("heightmaptool")
            for _,option in ipairs(enum) do
                local chipClasses = {"markupToolChip"}
                if option.value == current then
                    chipClasses[#chipClasses+1] = "selected"
                end
                result[#result+1] = gui.Panel{
                    classes = chipClasses,
                    width = 44,
                    height = 42,
                    flow = "vertical",
                    bgimage = true,
                    borderBox = true,
                    valign = "center",
                    hmargin = 1,
                    hover = SideTooltip(option.help),
                    data = {
                        toolvalue = option.value,
                    },
                    press = function(element)
                        dmhub.SetSettingValue("heightmaptool", element.data.toolvalue)
                        --focus arms the height-editing poll (the
                        --GetHeightEditingInfo chain is focus-gated).
                        TakeMarkupFocus()
                    end,

                    gui.Panel{
                        classes = {"markupToolIcon"},
                        bgimage = option.icon,
                        width = 18,
                        height = 18,
                        halign = "center",
                        vmargin = 3,
                    },

                    gui.Label{
                        classes = {"markupToolLabel"},
                        text = ELEVATION_TOOL_LABELS[option.value] or option.value,
                        width = "100%",
                        height = "auto",
                        textAlignment = "center",
                    },
                }
            end
            return result
        end)(),
    }

    --The editors themselves, hidden wholesale for non-patrons.
    --Built into an explicit list rather than a table literal: the brush strip
    --is nil when the Brush.lua export is missing, and a nil in the array part
    --of a literal would silently truncate every child after it.
    local elevationChildren = {}
    local AddElevationChild = function(child)
        if child ~= nil then
            elevationChildren[#elevationChildren+1] = child
        end
    end

    AddElevationChild(SectionHeader("Tool"))

    AddElevationChild(elevationToolsPanel)
    AddElevationChild(elevationBrushPanel)
    AddElevationChild(CreateSettingsEditor("heightmap:height", elevationStackedOpts))
    AddElevationChild(CreateSettingsEditor("heightmap:blend", elevationStackedOpts))
    AddElevationChild(CreateSettingsEditor("heightmap:opacity", elevationStackedOpts))
    AddElevationChild(CreateSettingsEditor("heightmap:gradient", elevationStackedOpts))

    AddElevationChild(gui.Label{
        classes = {"fgMuted", cond(not SlopeHintVisible(), "collapsed")},
        text = "Right-click while drawing to change direction",
        width = "90%",
        height = "auto",
        halign = "left",
        textAlignment = "center",
        fontSize = 12,
        italics = true,
        vmargin = 0,
        multimonitor = {"heightmap:gradient", "heightmaptool"},
        monitor = function(element)
            element:SetClass("collapsed", not SlopeHintVisible())
        end,
    })

    --The overlay controls are about READING heights, not painting them, so
    --they get their own section.
    AddElevationChild(SectionHeader("Overlay"))
    AddElevationChild(CreateSettingsEditor("heightmap:overlaytype", elevationStackedOpts))
    AddElevationChild(CreateSettingsEditor("heightmap:opacitysetting", elevationStackedOpts))

    local elevationEditorsPanel = gui.Panel{
        classes = {cond(not ElevationSupported(), "collapsed")},
        width = "100%",
        height = "auto",
        flow = "vertical",

        children = elevationChildren,
    }

    local elevationPanel = gui.Panel{
        classes = {cond(m_mode ~= "elevation", "collapsed")},
        width = "100%",
        height = "auto",
        flow = "vertical",

        markupmode = function(element)
            element:SetClass("collapsed", m_mode ~= "elevation")
        end,

        gui.Label{
            classes = {"fgMuted", cond(ElevationSupported(), "collapsed")},
            text = "Elevation editing is a patron feature.",
            width = "90%",
            height = "auto",
            halign = "center",
            vmargin = 8,
            textAlignment = "center",
        },

        elevationEditorsPanel,
    }

    --========================================================================
    --Props mode UI: the prop-type palette (object assets tagged "markup"),
    --component-aware property editors (bound to the map-selected prop when
    --there is one, else to the selected type's defaults), and click-to-place
    --via map focus. Moving/selecting placed props is the engine object tool,
    --scoped by the object-editing filter to markup props.
    --========================================================================

    local propPalettePanel
    local propPropertiesPanel
    local propsPanel

    --All placed markup props on the current floor; pass an assetid to
    --restrict to one prop type, nil for every markup prop.
    local PropsOnCurrentFloor = function(assetid)
        local result = {}
        local floor = game.currentFloor
        if floor == nil then
            return result
        end
        for _,obj in pairs(floor.objects) do
            local kw = obj.keywords
            if kw ~= nil and kw[MARKUP_PROP_KEYWORD] ~= nil
                and (assetid == nil or obj.assetid == assetid) then
                result[#result+1] = obj
            end
        end
        return result
    end

    --The placed prop bound to the property editors, if it still exists. Any
    --markup prop binds, even one whose asset left the palette - the editors
    --key off the INSTANCE's components, so deletion and light editing keep
    --working for legacy props.
    local GetEditingProp = function()
        if m_props.editingId == nil then
            return nil
        end
        local floor = game.currentFloor
        if floor == nil then
            return nil
        end
        local obj = floor:GetObject(m_props.editingId)
        if obj == nil then
            return nil
        end
        local kw = obj.keywords
        if kw == nil or kw[MARKUP_PROP_KEYWORD] == nil then
            return nil
        end
        return obj
    end

    --Every prop bound to the editors (shift+click multi-selects), still
    --alive and markup-tagged. Property edits apply to all of these.
    local GetEditingProps = function()
        local result = {}
        local ids = m_props.editingIds
        if ids == nil then
            return result
        end
        local floor = game.currentFloor
        if floor == nil then
            return result
        end
        for _,objid in ipairs(ids) do
            local obj = floor:GetObject(objid)
            if obj ~= nil and obj.valid then
                local kw = obj.keywords
                if kw ~= nil and kw[MARKUP_PROP_KEYWORD] ~= nil then
                    result[#result+1] = obj
                end
            end
        end
        return result
    end

    --Component property writes want color userdata, not hex strings; the
    --defaults store whatever the picker last produced, so normalize on write.
    local ToColorValue = function(val)
        if type(val) == "string" then
            local ok, result = pcall(function() return core.Color(val) end)
            if ok and result ~= nil then
                return result
            end
            return core.Color("#ffffff")
        end
        return val
    end

    local RefreshPropUI = function()
        if propsPanel ~= nil and propsPanel.valid then
            propsPanel:FireEventTree("refreshprops")
        end
    end

    --Session light defaults for one palette asset, seeded lazily from the
    --asset's own Light component so a "Torch" chip starts at the torch's
    --authored color/radius rather than a generic white light.
    local LightDefaultsFor = function(assetid)
        if assetid == nil then
            return nil
        end
        local d = m_props.defaults[assetid]
        if d == nil then
            d = { color = "#ffffff", intensity = 0.5, radius = 4, flicker = 0 }
            local node = assets:GetObjectNode(assetid)
            if node ~= nil then
                local comp = NodeGetComponent(node, "Light")
                if comp ~= nil then
                    local v = GetComponentFieldValue(comp, "color")
                    if v ~= nil then
                        d.color = v
                    end
                    v = tonumber(GetComponentFieldValue(comp, "intensity"))
                    if v ~= nil then
                        d.intensity = v
                    end
                    v = tonumber(GetComponentFieldValue(comp, "radius"))
                    if v ~= nil then
                        d.radius = v
                    end
                    v = tonumber(GetComponentFieldValue(comp, "flicker"))
                    if v ~= nil then
                        d.flicker = v
                    end
                end
            end
            m_props.defaults[assetid] = d
        end
        return d
    end

    --Component awareness: the light editors show when ANY bound prop has a
    --Light component, or (with nothing bound) when the selected palette
    --asset does.
    local LightEditorVisible = function()
        local editing = GetEditingProps()
        if #editing > 0 then
            for _,obj in ipairs(editing) do
                if obj:GetComponent("Light") ~= nil then
                    return true
                end
            end
            return false
        end
        if m_props.selected == nil then
            return false
        end
        local node = assets:GetObjectNode(m_props.selected)
        return node ~= nil and NodeGetComponent(node, "Light") ~= nil
    end

    --Apply a light property: onto EVERY bound prop that has a Light
    --component (shift+click selections edit together), updating each one's
    --asset defaults; with nothing bound, into the session defaults for the
    --selected asset (the next placement inherits them).
    local ApplyLightProperty = function(id, value)
        local applied = false
        for _,obj in ipairs(GetEditingProps()) do
            local light = obj:GetComponent("Light")
            if light ~= nil then
                light:SetAndUploadProperties{ [id] = value }
                local d = LightDefaultsFor(obj.assetid)
                if d ~= nil then
                    d[id] = value
                end
                applied = true
            end
        end
        if applied then
            return
        end
        local d = LightDefaultsFor(m_props.selected)
        if d ~= nil then
            d[id] = value
        end
    end

    --The value feeding a light editor: the first bound light's, else the
    --session default for the selected asset.
    local ReadLightProperty = function(id)
        for _,obj in ipairs(GetEditingProps()) do
            local light = obj:GetComponent("Light")
            if light ~= nil then
                local value = GetComponentFieldValue(light, id)
                if value ~= nil then
                    return value
                end
                local d = LightDefaultsFor(obj.assetid)
                if d ~= nil then
                    return d[id]
                end
                return nil
            end
        end
        local d = LightDefaultsFor(m_props.selected)
        if d ~= nil then
            return d[id]
        end
        return nil
    end

    --Session text defaults for one palette asset, seeded lazily from the
    --asset's own Text component so a "Label" chip starts at the font, size
    --and color it was authored with. Like the light defaults these then
    --track the last values edited, so consecutive labels inherit the look
    --(and the wording, which is usually a small edit of the last one).
    local TextDefaultsFor = function(assetid)
        if assetid == nil then
            return nil
        end
        local d = m_props.textDefaults[assetid]
        if d == nil then
            d = { text = "", font = "", fontSize = 40, color = "#ffffff" }
            local node = assets:GetObjectNode(assetid)
            if node ~= nil then
                local comp = NodeGetComponent(node, "Text")
                if comp ~= nil then
                    local v = GetComponentFieldValue(comp, "text")
                    if v ~= nil then
                        d.text = tostring(v)
                    end
                    v = GetComponentFieldValue(comp, "font")
                    if v ~= nil then
                        d.font = tostring(v)
                    end
                    v = tonumber(GetComponentFieldValue(comp, "fontSize"))
                    if v ~= nil then
                        d.fontSize = v
                    end
                    v = GetComponentFieldValue(comp, "color")
                    if v ~= nil then
                        d.color = v
                    end
                end
            end
            m_props.textDefaults[assetid] = d
        end
        return d
    end

    --Component awareness for text, mirroring the light editors: shown when
    --ANY bound prop has a Text component, or (with nothing bound) when the
    --selected palette asset does.
    local TextEditorVisible = function()
        local editing = GetEditingProps()
        if #editing > 0 then
            for _,obj in ipairs(editing) do
                if obj:GetComponent("Text") ~= nil then
                    return true
                end
            end
            return false
        end
        if m_props.selected == nil then
            return false
        end
        local node = assets:GetObjectNode(m_props.selected)
        return node ~= nil and NodeGetComponent(node, "Text") ~= nil
    end

    --Apply a text property onto EVERY bound prop that has a Text component,
    --updating each one's asset defaults; with nothing bound, into the
    --session defaults for the selected asset (the next placement inherits
    --them).
    local ApplyTextProperty = function(id, value)
        local applied = false
        for _,obj in ipairs(GetEditingProps()) do
            local comp = obj:GetComponent("Text")
            if comp ~= nil then
                comp:SetAndUploadProperties{ [id] = value }
                local d = TextDefaultsFor(obj.assetid)
                if d ~= nil then
                    d[id] = value
                end
                applied = true
            end
        end
        if applied then
            return
        end
        local d = TextDefaultsFor(m_props.selected)
        if d ~= nil then
            d[id] = value
        end
    end

    --The value feeding a text editor: the first bound Text component's, else
    --the session default for the selected asset.
    local ReadTextProperty = function(id)
        for _,obj in ipairs(GetEditingProps()) do
            local comp = obj:GetComponent("Text")
            if comp ~= nil then
                local value = GetComponentFieldValue(comp, id)
                if value ~= nil then
                    return value
                end
                local d = TextDefaultsFor(obj.assetid)
                if d ~= nil then
                    return d[id]
                end
                return nil
            end
        end
        local d = TextDefaultsFor(m_props.selected)
        if d ~= nil then
            return d[id]
        end
        return nil
    end

    --Every bound prop with a Teleporter component: {obj, comp, link} each.
    local EditingTeleporters = function()
        local result = {}
        for _,obj in ipairs(GetEditingProps()) do
            local comp = obj:GetComponent("Teleporter")
            if comp ~= nil then
                result[#result+1] = {
                    obj = obj,
                    comp = comp,
                    link = tostring(GetComponentFieldValue(comp, "linkName") or ""),
                }
            end
        end
        return result
    end

    --The distinct link names among the bound teleporters (a set of link
    --keys plus a count). Renaming is only offered when there is exactly one
    --distinct link - renaming a mixed selection would merge separate pairs
    --into one link group.
    local EditingTeleporterLinks = function()
        local links = {}
        local count = 0
        for _,entry in ipairs(EditingTeleporters()) do
            local key = LinkKey(entry.link)
            if key ~= "" and links[key] == nil then
                links[key] = entry.link
                count = count + 1
            end
        end
        return links, count
    end

    --Component awareness for teleporters, mirroring the light editors.
    local TeleporterEditorVisible = function()
        local editing = GetEditingProps()
        if #editing > 0 then
            for _,obj in ipairs(editing) do
                if obj:GetComponent("Teleporter") ~= nil then
                    return true
                end
            end
            return false
        end
        if m_props.selected == nil then
            return false
        end
        local node = assets:GetObjectNode(m_props.selected)
        return node ~= nil and NodeGetComponent(node, "Teleporter") ~= nil
    end

    --The link name the editors show: the first bound teleporter's, else the
    --half-placed pair's, else the name the next pair will use.
    local ReadTeleporterLink = function()
        local teleporters = EditingTeleporters()
        if #teleporters > 0 then
            return teleporters[1].link
        end
        if m_props.pendingPartnerId ~= nil and m_props.pendingLink ~= nil then
            return m_props.pendingLink
        end
        return CurrentTeleporterLinkName()
    end

    --Rename every markup teleporter on the map that carries oldLink - both
    --ends of a pair rename together, so editing the name never breaks the
    --pairing. Also carries the half-placed pair's name along.
    local RenameTeleporterLink = function(oldLink, newLink)
        newLink = trim(tostring(newLink or ""))
        if newLink == "" or LinkKey(newLink) == LinkKey(oldLink) then
            return
        end
        for _,entry in ipairs(MarkupTeleportersOnMap()) do
            if LinkKey(entry.link) == LinkKey(oldLink) then
                entry.comp:SetAndUploadProperties{ linkName = newLink }
            end
        end
        if m_props.pendingLink ~= nil and LinkKey(m_props.pendingLink) == LinkKey(oldLink) then
            m_props.pendingLink = newLink
        end
    end

    --Everything a delete of the current selection should remove: every
    --bound prop, plus the whole pair of every bound teleporter (every
    --markup teleporter sharing its link name, on any floor).
    local GetDeletionSet = function()
        local result = {}
        local byId = {}
        local links = {}
        for _,obj in ipairs(GetEditingProps()) do
            if byId[obj.objid] == nil then
                byId[obj.objid] = true
                result[#result+1] = obj
            end
            local comp = obj:GetComponent("Teleporter")
            if comp ~= nil then
                local link = GetComponentFieldValue(comp, "linkName")
                if link ~= nil and trim(tostring(link)) ~= "" then
                    links[LinkKey(link)] = true
                end
            end
        end
        if next(links) ~= nil then
            for _,entry in ipairs(MarkupTeleportersOnMap()) do
                if links[LinkKey(entry.link)] and byId[entry.obj.objid] == nil then
                    byId[entry.obj.objid] = true
                    result[#result+1] = entry.obj
                end
            end
        end
        return result
    end

    --The style ("teleport"/"stairwell") the editors show: the first bound
    --teleporter's, else the default stamped on new pairs.
    local ReadTeleporterStyle = function()
        local teleporters = EditingTeleporters()
        if #teleporters > 0 then
            local v = GetComponentFieldValue(teleporters[1].comp, "style")
            if v ~= nil and v ~= "" then
                return tostring(v)
            end
        end
        return m_props.teleStyle
    end

    --Apply a style choice: remember it for new pairs, and write it to EVERY
    --markup teleporter sharing any bound teleporter's link name - the ends
    --of a pair always keep the same styling, and a shift+click multi
    --selection styles all its pairs together.
    local ApplyTeleporterStyle = function(value)
        m_props.teleStyle = value

        local links = {}
        local haveLink = false
        for _,entry in ipairs(EditingTeleporters()) do
            local key = LinkKey(entry.link)
            if key ~= "" then
                links[key] = true
                haveLink = true
            else
                --an unlinked teleporter has no pair: style just it.
                entry.comp:SetAndUploadProperties{ style = value }
            end
        end

        if not haveLink and m_props.pendingPartnerId ~= nil and m_props.pendingLink ~= nil then
            links[LinkKey(m_props.pendingLink)] = true
            haveLink = true
        end

        if haveLink then
            for _,entry in ipairs(MarkupTeleportersOnMap()) do
                if links[LinkKey(entry.link)] then
                    entry.comp:SetAndUploadProperties{ style = value }
                end
            end
        end
    end

    --Place a new prop of the given palette asset at a map point. One upload:
    --spawn the asset locally, configure the components, then MarkUndo +
    --Upload. The instance keeps the asset's own name.
    local PlaceProp = function(assetid, point)
        local floor = game.currentFloor
        if floor == nil then
            return
        end

        local node = assets:GetObjectNode(assetid)
        if node == nil then
            return
        end

        --Hard gate: without the engine's object-editing filter a placed prop
        --is invisible AND unselectable, i.e. unremovable through the UI.
        if not PropsSupported() then
            return
        end

        local obj = floor:SpawnObjectLocal(assetid, { posx = point.x, posy = point.y })
        if obj == nil then
            dmhub.Debug("MARKUP:: could not spawn prop object " .. tostring(assetid))
            return
        end

        --The engine filter and the selection handler match the INSTANCE's
        --Core-component keywords, but the palette tag lives on the asset's
        --search keywords - a different store. Stamp "markup" onto the
        --instance, preserving any Core keywords cloned from the asset.
        local coreComponent = obj:GetComponent("Core")
        if coreComponent ~= nil then
            local kws = {}
            local hasMarkup = false
            local existing = obj.keywords
            if existing ~= nil then
                for kw,_ in pairs(existing) do
                    kws[#kws+1] = kw
                    if string.lower(kw) == MARKUP_PROP_KEYWORD then
                        hasMarkup = true
                    end
                end
            end
            if not hasMarkup then
                kws[#kws+1] = MARKUP_PROP_KEYWORD
            end
            coreComponent:SetProperty("keywords", kws)
        end

        --locked: inert to the object tool everywhere except this tab (the
        --object-editing filter treats matching props as unlocked).
        obj.locked = true

        local light = obj:GetComponent("Light")
        if light ~= nil then
            local d = LightDefaultsFor(assetid)
            if d ~= nil then
                light:SetProperty("color", ToColorValue(d.color))
                light:SetProperty("intensity", d.intensity)
                light:SetProperty("radius", d.radius)
                light:SetProperty("flicker", d.flicker)
            end
        end

        --the wording typed into the editors is what the new label says: for
        --text props the panel doubles as the compose field, so a click on
        --the map drops a finished label rather than a blank one to go back
        --and fill in.
        local textcomp = obj:GetComponent("Text")
        if textcomp ~= nil then
            local d = TextDefaultsFor(assetid)
            if d ~= nil then
                textcomp:SetProperty("text", tostring(d.text or ""))
                if d.font ~= nil and tostring(d.font) ~= "" then
                    textcomp:SetProperty("font", tostring(d.font))
                end
                local size = tonumber(d.fontSize)
                if size ~= nil then
                    textcomp:SetProperty("fontSize", size)
                end
                textcomp:SetProperty("color", ToColorValue(d.color))
            end
        end

        --Teleporters place as a PAIR sharing one link name and style: the
        --first placement arms the pending-partner state, the second completes
        --the pair and retires the link name so the next pair generates a
        --fresh one.
        local teleporter = obj:GetComponent("Teleporter")
        local completedPair = false
        if teleporter ~= nil then
            local link
            if m_props.pendingPartnerId ~= nil then
                link = m_props.pendingLink or CurrentTeleporterLinkName()
                completedPair = true
            else
                link = CurrentTeleporterLinkName()
            end
            teleporter:SetProperty("linkName", link)
            teleporter:SetProperty("style", m_props.teleStyle)
        end

        obj:MarkUndo()
        obj:Upload()

        if teleporter ~= nil then
            if completedPair then
                m_props.pendingPartnerId = nil
                m_props.pendingLink = nil
                m_props.pendingFloorId = nil
                --this name is taken now; the next pair generates a new one.
                m_props.teleLink = nil
            else
                m_props.pendingPartnerId = obj.objid
                m_props.pendingLink = m_props.teleLink
                m_props.pendingFloorId = obj.floorid
            end
        end

        track("markup_prop_place", { prop = tostring(node.description) })

        RefreshPropUI()
    end

    local CreatePropChip = function(node)
        local tip = tostring(node.description) .. ": click the map to place one."
        if NodeGetComponent(node, "Light") ~= nil then
            tip = tip .. " An invisible light source: players see the light it casts, never the marker."
        end
        if NodeGetComponent(node, "Text") ~= nil then
            tip = tip .. " Type the wording below before placing it; every placed one can be re-edited by clicking it."
        end

        return gui.Panel{
            classes = {"markupChip", cond(node.id == m_props.selected, "selected")},
            width = "48%",
            height = 34,
            flow = "horizontal",
            bgimage = true,
            pad = 6,
            borderBox = true,
            hmargin = 2,
            vmargin = 2,

            data = {
                propid = node.id,
            },

            hover = gui.Tooltip(tip),

            press = function(element)
                --switching type abandons a half-placed teleporter pair;
                --re-pressing the already-selected chip does not.
                if element.data.propid ~= m_props.selected then
                    AbortPendingTeleporterPair()
                end
                m_props.selected = element.data.propid
                m_props.editingId = nil
                m_props.editingIds = nil
                dmhub.ClearSelectedObjects()
                RefreshPropUI()
                --panel focus is what turns the object-editing filter on, and
                --map focus must be taken NOW rather than up to thinkTime
                --(0.3s) later: without it, a click on the map in the moment
                --right after picking a type lands with no map focus and
                --silently does nothing.
                TakeMarkupFocus()
            end,

            gui.Panel{
                width = 18,
                height = 18,
                valign = "center",
                bgimageStreamed = node.thumbnailId,
                bgcolor = "white",
            },

            gui.Label{
                classes = {"bold", "sizeXs"},
                text = tostring(node.description),
                width = "100%-26",
                height = "auto",
                hmargin = 4,
                valign = "center",
            },
        }
    end

    --A cheap identity for the current palette roster: rebuild the chips only
    --when the set of tagged assets (or a name) actually changes, never on
    --the routine refreshprops that follows every selection or placement -
    --rebuilding mid-press would destroy the pressed chip under its own
    --handler.
    local PropRosterSignature = function(nodes)
        local parts = {}
        for _,node in ipairs(nodes) do
            parts[#parts+1] = node.id .. "=" .. tostring(node.description)
        end
        return table.concat(parts, ";")
    end

    --NOTE the palette and the property editors render even when the engine
    --half is missing (PropsSupported false) - only PLACEMENT is gated. What a
    --stale engine breaks is showing/selecting/dragging placed props, so
    --placing would strand them; browsing the types and setting defaults is
    --harmless, and keeps the tab legible instead of a bare error line.
    propPalettePanel = gui.Panel{
        width = "96%",
        height = "auto",
        halign = "center",
        flow = "horizontal",
        wrap = true,

        --the roster is data-driven, so tagging/untagging/renaming an object
        --shows up here live.
        monitorAssets = true,

        data = {
            signature = nil,
        },

        events = {
            refreshAssets = function(element)
                element:FireEvent("syncchips")
            end,

            refreshprops = function(element)
                element:FireEvent("syncchips")
            end,

            syncchips = function(element)
                local nodes = MarkupPropAssets()
                local sig = PropRosterSignature(nodes)
                if sig ~= element.data.signature then
                    element.data.signature = sig

                    --heal a dead selection (asset untagged or deleted) to
                    --the first chip.
                    local found = false
                    for _,node in ipairs(nodes) do
                        if node.id == m_props.selected then
                            found = true
                            break
                        end
                    end
                    if not found then
                        local first = nodes[1]
                        if first ~= nil then
                            m_props.selected = first.id
                        else
                            m_props.selected = nil
                        end
                    end

                    local chips = {}
                    for _,node in ipairs(nodes) do
                        chips[#chips+1] = CreatePropChip(node)
                    end
                    if #chips == 0 then
                        chips[1] = gui.Label{
                            classes = {"fgMuted", "sizeXs"},
                            text = "No prop objects found. Add the keyword \"markup\" to an object in the Objects panel and it will appear here as a placeable prop type.",
                            width = "96%",
                            height = "auto",
                            halign = "center",
                            vmargin = 6,
                            textAlignment = "center",
                        }
                    end
                    element.children = chips
                else
                    for _,chip in ipairs(element.children) do
                        if chip.data ~= nil and chip.data.propid ~= nil then
                            chip:SetClass("selected", chip.data.propid == m_props.selected)
                        end
                    end
                end
            end,
        },

        create = function(element)
            element:FireEvent("syncchips")
        end,
    }

    local CreateLightSliderRow = function(labelText, fieldId, minValue, maxValue)
        return gui.Panel{
            width = "96%",
            height = 26,
            halign = "center",
            flow = "horizontal",
            vmargin = 2,

            gui.Label{
                classes = {"sizeXs"},
                text = labelText,
                width = 80,
                height = "auto",
                valign = "center",
            },

            gui.Slider{
                value = tonumber(ReadLightProperty(fieldId)) or minValue,
                minValue = minValue,
                maxValue = maxValue,
                sliderWidth = 150,
                labelWidth = 40,
                valign = "center",
                data = {
                    refreshing = false,
                },
                events = {
                    --programmatically setting .value fires change; guard so
                    --refreshes don't echo back into uploads.
                    refreshprops = function(element)
                        element.data.refreshing = true
                        element.value = tonumber(ReadLightProperty(fieldId)) or minValue
                        element.data.refreshing = false
                    end,
                    change = function(element)
                        if element.data.refreshing then
                            return
                        end
                        ApplyLightProperty(fieldId, element.value)
                    end,
                },
            },
        }
    end

    --Which prop the editors are bound to: the selected placed prop when one
    --is bound, else the selected palette type's defaults. Standalone (not
    --inside the light editors) so it reads correctly for props with no Light
    --component too.
    local propStatusLabel = gui.Label{
        classes = {"fgMuted", "sizeXs"},
        text = "",
        width = "96%",
        height = "auto",
        halign = "center",
        vmargin = 4,

        refreshprops = function(element)
            if m_props.pendingPartnerId ~= nil then
                element:SetClass("collapsed", false)
                element.text = string.format(
                    "Now place the partner for '%s': click the map where the second teleporter should go (any floor). Press Escape to cancel and remove the first one.",
                    tostring(m_props.pendingLink or ""))
                return
            end
            local editing = GetEditingProps()
            if #editing > 0 then
                element:SetClass("collapsed", false)
                local teleporters = EditingTeleporters()
                local _, linkCount = EditingTeleporterLinks()
                if #editing >= 2 and #teleporters == #editing and linkCount == 1 then
                    element.text = string.format(
                        "Editing the teleporter pair '%s': changes and deletion apply to both ends.",
                        tostring(ReadTeleporterLink()))
                elseif #editing >= 2 then
                    element.text = string.format(
                        "Editing %d selected props: property changes apply to all of them.",
                        #editing)
                elseif #teleporters == 1 then
                    --the partner may be on another floor (not co-selected),
                    --so check the map before calling it unpaired.
                    local pairSize = 0
                    local key = LinkKey(teleporters[1].link)
                    if key ~= "" then
                        for _,entry in ipairs(MarkupTeleportersOnMap()) do
                            if LinkKey(entry.link) == key then
                                pairSize = pairSize + 1
                            end
                        end
                    end
                    if pairSize >= 2 then
                        element.text = string.format(
                            "Editing the teleporter pair '%s': changes and deletion apply to both ends.",
                            tostring(ReadTeleporterLink()))
                    else
                        element.text = string.format(
                            "Editing the selected %s. It has no partner - place or rename another teleporter to '%s' to pair it.",
                            tostring(editing[1].name), tostring(ReadTeleporterLink()))
                    end
                else
                    element.text = string.format("Editing the selected %s.", tostring(editing[1].name))
                end
                return
            end
            if m_props.selected == nil then
                element:SetClass("collapsed", true)
                return
            end
            local node = assets:GetObjectNode(m_props.selected)
            if node == nil then
                element:SetClass("collapsed", true)
                return
            end
            element:SetClass("collapsed", false)
            element.text = string.format("Defaults for new %s placements. Click a placed prop on the map to edit it.", tostring(node.description))
        end,
    }

    --The light editors: shown when the bound prop - or, unbound, the
    --selected palette asset - has a Light component.
    propPropertiesPanel = gui.Panel{
        classes = {cond(not LightEditorVisible(), "collapsed")},
        width = "96%",
        height = "auto",
        halign = "center",
        flow = "vertical",

        events = {
            refreshprops = function(element)
                element:SetClass("collapsed", not LightEditorVisible())
            end,
        },

        gui.Panel{
            width = "96%",
            height = 26,
            halign = "center",
            flow = "horizontal",
            vmargin = 2,

            gui.Label{
                classes = {"sizeXs"},
                text = "Color:",
                width = 80,
                height = "auto",
                valign = "center",
            },

            gui.ColorPicker{
                width = 24,
                height = 18,
                valign = "center",
                borderWidth = 1,
                borderColor = "@border",
                value = ReadLightProperty("color") or "#ffffff",
                data = {
                    refreshing = false,
                },
                events = {
                    refreshprops = function(element)
                        local v = ReadLightProperty("color")
                        if v ~= nil then
                            element.data.refreshing = true
                            element.value = v
                            element.data.refreshing = false
                        end
                    end,
                    change = function(element)
                        if element.data.refreshing then
                            return
                        end
                        ApplyLightProperty("color", ToColorValue(element.value))
                    end,
                },
            },
        },

        CreateLightSliderRow("Brightness:", "intensity", 0, 2),
        CreateLightSliderRow("Radius:", "radius", 0, 25),
        CreateLightSliderRow("Flicker:", "flicker", 0, 1),
    }

    --The font picker's options. The ids gui.availableFonts hands back are
    --lowercase while a component stores whatever case the asset was authored
    --with ("Berling"); GameConfig.GetFont lowercases before looking up, so a
    --lowercase id resolves to exactly the same face - just compare
    --case-insensitively when reading the current value back.
    --
    --A font the build does not ship (the white-label font lists differ, so
    --e.g. an asset authored as "Cambria" has no face here and renders in the
    --fallback) gets a synthetic entry at the top rather than leaving the
    --picker blank on a value that IS set.
    local m_textFontOptions = nil
    local TextFontOptions = function(current)
        if m_textFontOptions == nil then
            m_textFontOptions = {}
            for _,f in ipairs(gui.availableFonts or {}) do
                local name = tostring(f)
                if name ~= "" then
                    m_textFontOptions[#m_textFontOptions+1] = {
                        id = string.lower(name),
                        text = string.upper(string.sub(name, 1, 1)) .. string.sub(name, 2),
                    }
                end
            end
        end

        current = string.lower(tostring(current or ""))
        if current == "" then
            return m_textFontOptions
        end
        for _,opt in ipairs(m_textFontOptions) do
            if opt.id == current then
                return m_textFontOptions
            end
        end

        local result = { { id = current, text = current .. " (missing)" } }
        for _,opt in ipairs(m_textFontOptions) do
            result[#result+1] = opt
        end
        return result
    end

    --Commit the text field. Enter submits and focus loss changes, so both
    --events land here - lastApplied makes one edit upload once, and stops a
    --refresh-driven re-push of the same wording from writing at all.
    local ApplyEditedText = function(element)
        local typed = tostring(element.text or "")
        if element.data.lastApplied == typed then
            return
        end
        element.data.lastApplied = typed
        ApplyTextProperty("text", typed)
        RefreshPropUI()
    end

    --The text editors: what the label actually says, plus the three fields
    --that decide whether it reads at all on the map - font, size and color.
    --Shown when the bound prop - or, unbound, the selected palette asset -
    --has a Text component. Unbound the fields ARE the next placement: what
    --is typed here is what the label says when it lands.
    local propTextPanel = gui.Panel{
        classes = {cond(not TextEditorVisible(), "collapsed")},
        width = "96%",
        height = "auto",
        halign = "center",
        flow = "vertical",

        events = {
            refreshprops = function(element)
                element:SetClass("collapsed", not TextEditorVisible())
            end,
        },

        gui.Panel{
            width = "96%",
            height = "auto",
            halign = "center",
            flow = "horizontal",
            vmargin = 2,

            gui.Label{
                classes = {"sizeXs"},
                text = "Text:",
                width = 80,
                height = "auto",
                valign = "center",
                hover = gui.Tooltip("What this label says on the map. Enter applies it; shift+Enter starts a new line."),
            },

            gui.Input{
                classes = {"sizeXs"},
                text = "",
                width = "100%-84",
                height = 44,
                valign = "center",
                multiline = true,
                lineType = "MultiLineSubmit",
                textAlignment = "topleft",
                characterLimit = 400,
                placeholderText = "Label text",

                data = {
                    lastApplied = "",
                },

                refreshprops = function(element)
                    --don't stomp the field while the user is typing in it.
                    if element.hasInputFocus then
                        return
                    end
                    --textNoNotify, NOT text: a plain assignment fires change,
                    --and change re-refreshes, so the refresh that follows
                    --every edit would bounce back into another upload.
                    local value = tostring(ReadTextProperty("text") or "")
                    element.textNoNotify = value
                    element.data.lastApplied = value
                end,

                change = function(element)
                    ApplyEditedText(element)
                end,

                submit = function(element)
                    ApplyEditedText(element)
                end,
            },
        },

        gui.Panel{
            width = "96%",
            height = 26,
            halign = "center",
            flow = "horizontal",
            vmargin = 2,

            gui.Label{
                classes = {"sizeXs"},
                text = "Font:",
                width = 80,
                height = "auto",
                valign = "center",
            },

            gui.Dropdown{
                --wider than the panel's other 150px controls: font names run
                --long, and a wrapped two-line name in a 26px row is unreadable.
                width = "100%-84",
                height = 26,
                valign = "center",
                options = TextFontOptions(ReadTextProperty("font")),
                idChosen = string.lower(tostring(ReadTextProperty("font") or "")),
                data = {
                    refreshing = false,
                    optionsFor = string.lower(tostring(ReadTextProperty("font") or "")),
                },

                refreshprops = function(element)
                    local font = string.lower(tostring(ReadTextProperty("font") or ""))
                    if font ~= "" and element.idChosen ~= font then
                        element.data.refreshing = true
                        --a rebuild only when the list would actually differ:
                        --reassigning options on every refresh churns the
                        --dropdown for nothing.
                        if element.data.optionsFor ~= font then
                            element.data.optionsFor = font
                            element.options = TextFontOptions(font)
                        end
                        element.idChosen = font
                        element.data.refreshing = false
                    end
                end,

                change = function(element)
                    if element.data.refreshing then
                        return
                    end
                    ApplyTextProperty("font", element.idChosen)
                    RefreshPropUI()
                end,
            },
        },

        gui.Panel{
            width = "96%",
            height = 26,
            halign = "center",
            flow = "horizontal",
            vmargin = 2,

            gui.Label{
                classes = {"sizeXs"},
                text = "Font Size:",
                width = 80,
                height = "auto",
                valign = "center",
            },

            gui.Slider{
                value = tonumber(ReadTextProperty("fontSize")) or 40,
                minValue = 8,
                maxValue = 160,
                sliderWidth = 150,
                labelWidth = 40,
                --whole points: the default "%.2f" readout ("40.00") is noise
                --at this range, and a fractional point size buys nothing.
                labelFormat = "%d",
                valign = "center",
                data = {
                    refreshing = false,
                },
                events = {
                    --programmatically setting .value fires change; guard so
                    --refreshes don't echo back into uploads.
                    refreshprops = function(element)
                        element.data.refreshing = true
                        element.value = tonumber(ReadTextProperty("fontSize")) or 40
                        element.data.refreshing = false
                    end,
                    change = function(element)
                        if element.data.refreshing then
                            return
                        end
                        ApplyTextProperty("fontSize", math.floor((tonumber(element.value) or 40) + 0.5))
                    end,
                },
            },
        },

        gui.Panel{
            width = "96%",
            height = 26,
            halign = "center",
            flow = "horizontal",
            vmargin = 2,

            gui.Label{
                classes = {"sizeXs"},
                text = "Color:",
                width = 80,
                height = "auto",
                valign = "center",
            },

            gui.ColorPicker{
                width = 24,
                height = 18,
                valign = "center",
                borderWidth = 1,
                borderColor = "@border",
                value = ReadTextProperty("color") or "#ffffff",
                data = {
                    refreshing = false,
                },
                events = {
                    refreshprops = function(element)
                        local v = ReadTextProperty("color")
                        if v ~= nil then
                            element.data.refreshing = true
                            element.value = v
                            element.data.refreshing = false
                        end
                    end,
                    change = function(element)
                        if element.data.refreshing then
                            return
                        end
                        ApplyTextProperty("color", ToColorValue(element.value))
                        RefreshPropUI()
                    end,
                },
            },
        },
    }

    --The teleporter editors: link name + trip styling. Shown when the bound
    --prop - or, unbound, the selected palette asset - has a Teleporter
    --component. Edits to either field keep both ends of a pair identical.
    local propTeleporterPanel = gui.Panel{
        classes = {cond(not TeleporterEditorVisible(), "collapsed")},
        width = "96%",
        height = "auto",
        halign = "center",
        flow = "vertical",

        events = {
            refreshprops = function(element)
                element:SetClass("collapsed", not TeleporterEditorVisible())
            end,
        },

        gui.Panel{
            width = "96%",
            height = 26,
            halign = "center",
            flow = "horizontal",
            vmargin = 2,

            events = {
                --renaming a selection that spans SEVERAL links would merge
                --separate pairs into one link group; offer the rename only
                --when the bound teleporters share a single link.
                refreshprops = function(element)
                    local _, linkCount = EditingTeleporterLinks()
                    element:SetClass("collapsed", linkCount > 1)
                end,
            },

            gui.Label{
                classes = {"sizeXs"},
                text = "Link Name:",
                width = 80,
                height = "auto",
                valign = "center",
                hover = gui.Tooltip("Teleporters with the same link name are a pair; a creature entering one comes out at the other. Renaming here renames both ends together."),
            },

            gui.Input{
                classes = {"sizeXs"},
                text = "",
                width = 150,
                height = 20,
                valign = "center",
                characterLimit = 40,
                selectAllOnFocus = true,

                refreshprops = function(element)
                    --don't stomp the field while the user is typing in it.
                    if element.hasInputFocus then
                        return
                    end
                    element.text = ReadTeleporterLink()
                end,

                change = function(element)
                    local typed = trim(tostring(element.text or ""))
                    if typed == "" then
                        element.text = ReadTeleporterLink()
                        return
                    end

                    local teleporters = EditingTeleporters()
                    if #teleporters > 0 then
                        RenameTeleporterLink(teleporters[1].link, typed)
                    elseif m_props.pendingPartnerId ~= nil then
                        RenameTeleporterLink(m_props.pendingLink, typed)
                    else
                        m_props.teleLink = typed
                    end
                    RefreshPropUI()
                end,
            },
        },

        gui.Panel{
            width = "96%",
            height = 26,
            halign = "center",
            flow = "horizontal",
            vmargin = 2,

            gui.Label{
                classes = {"sizeXs"},
                text = "Style:",
                width = 80,
                height = "auto",
                valign = "center",
                hover = gui.Tooltip("How the trip looks and sounds. Teleport plays the token's teleport effect; Stairwell just moves the token with a footsteps sound. Both ends of a pair always share the style."),
            },

            gui.Dropdown{
                width = 150,
                height = 26,
                valign = "center",
                idChosen = "teleport",
                options = {
                    { id = "teleport", text = "Teleport" },
                    { id = "stairwell", text = "Stairwell" },
                },
                data = {
                    refreshing = false,
                },

                refreshprops = function(element)
                    local style = ReadTeleporterStyle()
                    if element.idChosen ~= style then
                        element.data.refreshing = true
                        element.idChosen = style
                        element.data.refreshing = false
                    end
                end,

                change = function(element)
                    if element.data.refreshing then
                        return
                    end
                    ApplyTeleporterStyle(element.idChosen)
                    RefreshPropUI()
                end,
            },
        },
    }

    --Standalone (outside the light editors) so any bound prop can be
    --deleted, whatever components it carries. Teleporters delete as a PAIR:
    --both ends go together, whatever floor the partner is on.
    local propDeleteButton = gui.Button{
        classes = {"sizeM", "collapsed"},
        text = "Delete Prop",
        halign = "center",
        vmargin = 4,

        refreshprops = function(element)
            local toDelete = GetDeletionSet()
            element:SetClass("collapsed", #toDelete == 0)
            if #toDelete == 0 then
                return
            end
            local teleporters = EditingTeleporters()
            local _, linkCount = EditingTeleporterLinks()
            if #toDelete >= 2 and #teleporters == #GetEditingProps() and linkCount == 1 then
                element.text = "Delete Teleporter Pair"
            elseif #toDelete >= 2 then
                element.text = string.format("Delete %d Props", #toDelete)
            else
                element.text = "Delete Prop"
            end
        end,

        click = function(element)
            local toDelete = GetDeletionSet()
            if #toDelete == 0 then
                return
            end
            local propName = tostring(toDelete[1].name)

            --deleting the half-placed first teleporter IS the abort; just
            --clear the pending state rather than double-destroying.
            for _,d in ipairs(toDelete) do
                if d.objid == m_props.pendingPartnerId then
                    m_props.pendingPartnerId = nil
                    m_props.pendingLink = nil
                    m_props.pendingFloorId = nil
                end
            end

            dmhub.ClearSelectedObjects()
            m_props.editingId = nil
            m_props.editingIds = nil
            for _,d in ipairs(toDelete) do
                if d.valid then
                    d:Destroy()
                end
            end
            track("markup_prop_delete", { prop = propName, count = #toDelete })
            RefreshPropUI()
        end,
    }

    --Rough map location for a prop row ("NE Corner", "Center", ...): the
    --same 3x3 cut of the map extent the zone list uses. obj positions are
    --continuous world coordinates, so no half-tile centroid shift.
    local PropAreaDescription = function(x, y)
        local dims = nil
        pcall(function()
            local map = game.currentMap
            if map ~= nil then
                dims = map.dimensions
            end
        end)
        if dims == nil then
            return nil
        end
        local w = dims.z - dims.x
        local h = dims.w - dims.y
        if w <= 0 or h <= 0 then
            return nil
        end
        local col = 1 + math.floor(((x - dims.x) / w) * 3)
        local row = 1 + math.floor(((y - dims.y) / h) * 3)
        if col < 1 then col = 1 elseif col > 3 then col = 3 end
        if row < 1 then row = 1 elseif row > 3 then row = 3 end
        return ZONE_AREA_NAMES[row][col]
    end

    --Pan the camera to the first of a list of props and flash a highlight
    --box around each of them for a moment (a teleporter-pair row flashes
    --both ends). The scheduled cleanup deliberately has NO mod.unloaded
    --guard: HighlightLine markers are engine objects that outlive a Lua
    --reload, so the stale closure destroying them is exactly what we want.
    local propFlashHandles = nil
    local JumpToProps = function(objs)
        if #objs == 0 then
            return
        end

        pcall(function()
            dmhub.CenterOnLoc{
                x = math.floor(objs[1].x + 0.5),
                y = math.floor(objs[1].y + 0.5),
                floorid = objs[1].floorid,
                smooth = true,
            }
        end)

        if propFlashHandles ~= nil then
            for _,h in ipairs(propFlashHandles) do
                pcall(function() h:Destroy() end)
            end
            propFlashHandles = nil
        end

        local floorIndex = game.currentFloorIndex
        local handles = {}
        for _,obj in ipairs(objs) do
            local x, y = obj.x, obj.y
            local R = 0.55
            local corners = {
                { x - R, y - R, x + R, y - R },
                { x + R, y - R, x + R, y + R },
                { x + R, y + R, x - R, y + R },
                { x - R, y + R, x - R, y - R },
            }
            for _,c in ipairs(corners) do
                local ok, handle = pcall(function()
                    return dmhub.HighlightLine{
                        color = "#7fd4ff",
                        a = core.Vector2(c[1], c[2]),
                        b = core.Vector2(c[3], c[4]),
                        floorIndex = floorIndex,
                        terrainParallax = true,
                    }
                end)
                if ok and handle ~= nil then
                    handles[#handles+1] = handle
                end
            end
        end
        propFlashHandles = handles

        dmhub.Schedule(1.0, function()
            --double-destroy of an already-replaced flash is pcall-safe.
            for _,h in ipairs(handles) do
                pcall(function() h:Destroy() end)
            end
        end)
    end

    --The wording a placed text prop shows, flattened to one line and cut to
    --a row-sized length; nil for a prop with no Text component, "" for one
    --whose text is blank. The cut backs off any UTF-8 continuation bytes so
    --a multi-byte character never gets sliced in half into a garbage glyph.
    local PropDisplayText = function(obj)
        local comp = obj:GetComponent("Text")
        if comp == nil then
            return nil
        end
        local raw = tostring(GetComponentFieldValue(comp, "text") or "")
        raw = trim((string.gsub(raw, "%s+", " ")))
        if #raw > 40 then
            local cut = 40
            while cut > 1 do
                local b = string.byte(raw, cut + 1)
                if b == nil or b < 128 or b >= 192 then
                    break
                end
                cut = cut - 1
            end
            raw = string.sub(raw, 1, cut) .. "..."
        end
        return raw
    end

    --One row in the placed-props list. An entry is ONE prop - or one whole
    --TELEPORTER PAIR: both ends of a pair share a single row (entry.objs
    --holds each end on this floor, entry.link the pair's link name).
    --Click: select the entry's props (the editors bind through the engine
    --selection callback) and pan the camera to them. Shift+click: toggle
    --the whole entry in or out of the selection without clearing the rest,
    --to edit several entries together.
    local CreatePropRow = function(entry, node)
        local objs = entry.objs
        local first = objs[1]

        local title = tostring(first.name)
        if entry.link ~= nil then
            title = string.format("%s '%s'", title, entry.link)
        end

        --a text prop is identified by WHAT IT SAYS: every one of them carries
        --the same asset name (and the header above already names the type),
        --so the wording replaces it as the row's label. A linked prop keeps
        --its name+link and merely gains the wording, since the link is what
        --identifies it there.
        local shownText = PropDisplayText(first)
        if shownText ~= nil then
            if shownText == "" then
                title = title .. " (blank)"
            elseif entry.link ~= nil then
                title = string.format("%s \"%s\"", title, shownText)
            else
                title = string.format("\"%s\"", shownText)
            end
        end

        local areas = {}
        for _,obj in ipairs(objs) do
            local area = PropAreaDescription(obj.x, obj.y)
            if area ~= nil then
                areas[#areas+1] = area
            end
        end
        if #areas >= 2 then
            if areas[1] == areas[2] then
                title = title .. " -- " .. areas[1]
            else
                title = title .. " -- " .. areas[1] .. " to " .. areas[2]
            end
        elseif #areas == 1 then
            title = title .. " -- " .. areas[1]
        end

        --a linked teleporter with only one end on this floor: say where the
        --rest of the pair is rather than listing a confusing lone end.
        if entry.link ~= nil and #objs == 1 then
            if (entry.pairSize or 1) >= 2 then
                title = title .. " (partner on another floor)"
            else
                title = title .. " (unpaired)"
            end
        end

        local swatch
        local light = first:GetComponent("Light")
        local swatchColor = nil
        if light ~= nil then
            swatchColor = GetComponentFieldValue(light, "color")
        end
        if swatchColor == nil then
            --a text prop's color is the one thing distinguishing it at a
            --glance; the thumbnail is identical across all of them.
            local textcomp = first:GetComponent("Text")
            if textcomp ~= nil then
                swatchColor = GetComponentFieldValue(textcomp, "color")
            end
        end
        if swatchColor ~= nil then
            swatch = gui.Panel{
                width = 14,
                height = 14,
                valign = "center",
                bgimage = true,
                bgcolor = swatchColor,
                borderWidth = 1,
                borderColor = "@border",
            }
        else
            local thumb = nil
            if node ~= nil then
                thumb = node.thumbnailId
            end
            swatch = gui.Panel{
                width = 14,
                height = 14,
                valign = "center",
                bgimageStreamed = thumb,
                bgcolor = "white",
            }
        end

        local ids = {}
        for _,obj in ipairs(objs) do
            ids[#ids+1] = obj.objid
        end

        local what = "this prop"
        if entry.link ~= nil then
            what = "this teleporter pair"
        end

        return gui.Panel{
            classes = {"markupChip"},
            width = "96%",
            height = 26,
            halign = "center",
            flow = "horizontal",
            bgimage = true,
            pad = 4,
            borderBox = true,
            vmargin = 1,

            data = {
                propRowIds = ids,
            },

            hover = gui.Tooltip(string.format("Click to select %s and pan to it. Shift+click to add it to the selection and edit several together.", what)),

            press = function(element)
                --focus FIRST: the selection callback binds selections to
                --this panel's editors only while the panel holds focus.
                TakeMarkupFocus()

                local floor = game.currentFloor
                if floor == nil then
                    return
                end

                local rowObjs = {}
                local inRow = {}
                for _,objid in ipairs(element.data.propRowIds) do
                    local o = floor:GetObject(objid)
                    if o ~= nil and o.valid then
                        rowObjs[#rowObjs+1] = o
                        inRow[objid] = true
                    end
                end
                if #rowObjs == 0 then
                    RefreshPropUI()
                    return
                end

                local shift = false
                pcall(function()
                    shift = dmhub.modKeys.shift == true
                end)

                if shift then
                    --toggle the WHOLE entry: any end selected = deselect
                    --both, else select both. The selection callback rebinds
                    --the editors to whatever remains selected.
                    local anySelected = false
                    for _,o in ipairs(rowObjs) do
                        if o.editorSelection then
                            anySelected = true
                            break
                        end
                    end
                    for _,o in ipairs(rowObjs) do
                        o.editorSelection = not anySelected
                    end
                else
                    --deselect the previous binding per-object, NOT via
                    --dmhub.ClearSelectedObjects: the global clear dispatches
                    --the selection callback INLINE, so the panel renders one
                    --unbound frame (delete button collapsing, status/link
                    --text swapping to placement defaults) before next
                    --frame's re-bind - a whole-panel flicker on every click.
                    --Individual editorSelection writes only bump the
                    --selection seq, batching everything into ONE callback
                    --next frame: the panel transitions straight from the old
                    --binding to the new one.
                    for _,objid in ipairs(m_props.editingIds or {}) do
                        if not inRow[objid] then
                            local prev = floor:GetObject(objid)
                            if prev ~= nil and prev.valid then
                                prev.editorSelection = false
                            end
                        end
                    end
                    for _,o in ipairs(rowObjs) do
                        o.editorSelection = true
                    end
                    JumpToProps(rowObjs)
                end
            end,

            swatch,

            gui.Label{
                classes = {"bold", "sizeXs"},
                text = title,
                width = "100%-20",
                height = "auto",
                hmargin = 4,
                valign = "center",
            },
        }
    end

    local propListHeader = gui.Label{
        classes = {"bold"},
        text = "",
        width = "96%",
        height = "auto",
        halign = "center",
        vmargin = 2,
    }

    local propListRows = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
    }

    local propListHint = gui.Label{
        classes = {"fgMuted", "sizeXs"},
        text = "Click the map to place one; drag a placed prop to move it; Delete removes it.",
        width = "90%",
        height = "auto",
        halign = "center",
        vmargin = 4,
        textAlignment = "center",
    }

    --The placed props of the selected type on this floor, replacing the old
    --bare count line. Rows rebuild only when the roster/positions/labels
    --actually change (a rebuild mid-press would destroy the pressed row);
    --selection highlights sync on every refresh. The slow think keeps the
    --list fresh as props are added/moved/removed, including by other
    --clients.
    local propListPanel = gui.Panel{
        classes = {cond(not PropsSupported(), "collapsed")},
        width = "96%",
        height = "auto",
        halign = "center",
        flow = "vertical",
        vmargin = 4,

        thinkTime = 1,

        data = {
            signature = nil,
        },

        events = {
            think = function(element)
                if m_mode == "props" then
                    element:FireEvent("syncrows")
                end
            end,

            refreshprops = function(element)
                local show = PropsSupported() and m_props.selected ~= nil
                element:SetClass("collapsed", not show)
                if show then
                    element:FireEvent("syncrows")
                end
            end,

            syncrows = function(element)
                if m_props.selected == nil then
                    return
                end
                local node = assets:GetObjectNode(m_props.selected)
                if node == nil then
                    return
                end

                local props = PropsOnCurrentFloor(m_props.selected)
                table.sort(props, function(a, b)
                    return tostring(a.objid) < tostring(b.objid)
                end)

                --group into list ENTRIES: a teleporter pair is one entry
                --holding both of its ends on this floor; everything else is
                --one entry per prop. entry = {objs, link, pairSize} where
                --pairSize counts the pair's ends map-WIDE, so a lone end
                --here can say "partner on another floor" vs "(unpaired)".
                local entries = {}
                local groups = {}
                local mapPairSizes = nil
                for _,obj in ipairs(props) do
                    local link = nil
                    local teleporter = obj:GetComponent("Teleporter")
                    if teleporter ~= nil then
                        local raw = trim(tostring(GetComponentFieldValue(teleporter, "linkName") or ""))
                        if raw ~= "" then
                            link = raw
                        end
                    end

                    if link ~= nil then
                        if mapPairSizes == nil then
                            mapPairSizes = {}
                            for _,tp in ipairs(MarkupTeleportersOnMap()) do
                                local key = LinkKey(tp.link)
                                if key ~= "" then
                                    mapPairSizes[key] = (mapPairSizes[key] or 0) + 1
                                end
                            end
                        end
                        local key = LinkKey(link)
                        local group = groups[key]
                        if group == nil then
                            group = { objs = {}, link = link, pairSize = mapPairSizes[key] or 1 }
                            groups[key] = group
                            entries[#entries+1] = group
                        end
                        group.objs[#group.objs+1] = obj
                    else
                        entries[#entries+1] = { objs = { obj } }
                    end
                end

                local name = tostring(node.description)
                propListHeader.text = string.format("%s%s on This Floor (%d)",
                    name, cond(#entries == 1, "", "s"), #entries)

                --signature includes position and the label-feeding fields so
                --drags, renames, recolors and cross-floor partner changes
                --refresh the rows too.
                local parts = { tostring(m_props.selected), tostring(game.currentFloorId) }
                for _,entry in ipairs(entries) do
                    for _,obj in ipairs(entry.objs) do
                        local extra = ""
                        local light = obj:GetComponent("Light")
                        if light ~= nil then
                            --NOT tostring(color): global tostring of a
                            --LuaColor is a constant ("LuaColor{}"), blind to
                            --the actual value. The .tostring PROPERTY is the
                            --real "#RRGGBBAA" string.
                            local c = GetComponentFieldValue(light, "color")
                            if c ~= nil then
                                pcall(function()
                                    extra = tostring(c.tostring)
                                end)
                            end
                        end
                        --the wording and its color feed the row label and
                        --swatch, so retyping a label rebuilds the rows.
                        local textcomp = obj:GetComponent("Text")
                        if textcomp ~= nil then
                            extra = extra .. "|" .. tostring(GetComponentFieldValue(textcomp, "text") or "")
                            local c = GetComponentFieldValue(textcomp, "color")
                            if c ~= nil then
                                pcall(function()
                                    extra = extra .. "|" .. tostring(c.tostring)
                                end)
                            end
                        end
                        parts[#parts+1] = string.format("%s:%.1f,%.1f:%s", tostring(obj.objid), obj.x, obj.y, extra)
                    end
                    if entry.link ~= nil then
                        parts[#parts+1] = string.format("L:%s=%d", LinkKey(entry.link), entry.pairSize or 1)
                    end
                end
                local sig = table.concat(parts, ";")

                if sig ~= element.data.signature then
                    element.data.signature = sig
                    local rows = {}
                    for _,entry in ipairs(entries) do
                        rows[#rows+1] = CreatePropRow(entry, node)
                    end
                    if #rows == 0 then
                        rows[1] = gui.Label{
                            classes = {"fgMuted", "sizeXs"},
                            text = string.format("No %ss on this floor yet. Click the map to place one.", name),
                            width = "90%",
                            height = "auto",
                            halign = "center",
                            vmargin = 4,
                            textAlignment = "center",
                        }
                    end
                    propListRows.children = rows
                end

                --selection highlight follows the bound multi-selection: a
                --row highlights when ANY of its props is bound (a pair row
                --lights up whichever end was selected).
                local selectedSet = {}
                for _,objid in ipairs(m_props.editingIds or {}) do
                    selectedSet[objid] = true
                end
                for _,row in ipairs(propListRows.children) do
                    if row.data ~= nil and row.data.propRowIds ~= nil then
                        local anySelected = false
                        for _,objid in ipairs(row.data.propRowIds) do
                            if selectedSet[objid] then
                                anySelected = true
                                break
                            end
                        end
                        row:SetClass("selected", anySelected)
                    end
                end
            end,
        },

        propListHeader,
        propListRows,
        propListHint,
    }

    propsPanel = gui.Panel{
        classes = {cond(m_mode ~= "props", "collapsed")},
        width = "100%",
        height = "auto",
        flow = "vertical",

        --keeps map focus in sync with mode/focus/type; map focus is the
        --placement input surface (mappress) and suppresses token selection
        --while the tab is armed. The engine object tool is NOT suppressed by
        --map focus, which is exactly what lets placed props drag normally.
        thinkTime = 0.3,

        events = {
            markupmode = function(element)
                --leaving the Props tab abandons a half-placed teleporter pair.
                if m_mode ~= "props" then
                    AbortPendingTeleporterPair()
                end
                element:SetClass("collapsed", m_mode ~= "props")
                if m_mode == "props" then
                    element:FireEventTree("refreshprops")
                end
                --grab (or release) map focus on the mode switch itself, so the
                --first map click after switching tabs is not swallowed by the
                --think interval. Also releases promptly when switching away.
                element:FireEvent("think")
            end,

            think = function(element)
                local want = m_mode == "props" and PropsSupported()
                    and m_props.selected ~= nil
                    and m_arm.Armed()

                if m_props.pendingPartnerId ~= nil then
                    if not want then
                        --disarmed (focus lost, tab left, panel closed) with a
                        --pair half-placed: abort, deleting the first one.
                        AbortPendingTeleporterPair()
                    else
                        --the first teleporter can also die under us (another
                        --client, undo): quietly stop waiting for a partner.
                        local floor = nil
                        if m_props.pendingFloorId ~= nil then
                            floor = game.GetFloor(m_props.pendingFloorId)
                        end
                        local pendingObj = nil
                        if floor ~= nil then
                            pendingObj = floor:GetObject(m_props.pendingPartnerId)
                        end
                        if pendingObj == nil or not pendingObj.valid then
                            m_props.pendingPartnerId = nil
                            m_props.pendingLink = nil
                            m_props.pendingFloorId = nil
                            RefreshPropUI()
                        end
                    end
                end

                if want then
                    if not element.mapfocus then
                        element.mapfocus = true
                    end
                else
                    if element.mapfocus then
                        element.mapfocus = false
                    end
                end
            end,

            mappress = function(element, loc, point)
                if m_mode ~= "props" or m_props.selected == nil then
                    return
                end

                --clicks on or near ANY existing markup prop are select/drag
                --(the engine object tool owns those, and every markup prop
                --matches the editing filter); only place on empty ground.
                for _,obj in ipairs(PropsOnCurrentFloor(nil)) do
                    local dx = obj.x - point.x
                    local dy = obj.y - point.y
                    if dx*dx + dy*dy < 0.36 then
                        return
                    end
                end

                local placePoint = point
                if GhostSupported() then
                    --the ghost is the source of truth for "this click
                    --places": while a prop is bound the ghost is not
                    --published (the click unbinds via the engine's
                    --selection-clear instead), and a nil preview position
                    --means the engine is in select/drag stance (hovering a
                    --prop) even when the 0.6-tile check above missed it.
                    --When it IS showing, place at exactly the previewed
                    --(snapped) position so the prop lands under the ghost.
                    if m_props.editingId ~= nil then
                        return
                    end
                    local ghostPos = nil
                    pcall(function()
                        ghostPos = editor.objectPlacementPreviewPos
                    end)
                    if ghostPos == nil then
                        return
                    end
                    placePoint = ghostPos
                end

                PlaceProp(m_props.selected, placePoint)
            end,

            create = function(element)
                --a Lua reload can rebuild the panel with props already the
                --active mode; the editors then get no markupmode event, so
                --sync them here.
                if m_mode == "props" then
                    element:FireEventTree("refreshprops")
                end
            end,

            destroy = function(element)
                if element.mapfocus then
                    element.mapfocus = false
                end
            end,
        },

        children = {
            --NOT muted: this explains why clicking the map does nothing, and
            --muted small text got missed in exactly that situation.
            gui.Label{
                classes = {"bold", "sizeXs", cond(PropsSupported(), "collapsed")},
                text = "Placing props is DISABLED: this build cannot show or move placed props yet, so they would be stranded invisibly. Rebuild the app to enable it. The settings below still work.",
                width = "90%",
                height = "auto",
                halign = "center",
                vmargin = 8,
                textAlignment = "center",
            },

            propPalettePanel,
            propStatusLabel,
            propPropertiesPanel,
            propTextPanel,
            propTeleporterPanel,
            propDeleteButton,
            propListPanel,
        },
    }

    --Placeholder for the modes that are not implemented yet.
    local placeholderPanel = gui.Label{
        classes = {"fgMuted", cond(m_mode == "walls" or m_mode == "zones" or m_mode == "surfaces" or m_mode == "elevation" or m_mode == "props", "collapsed")},
        text = "",
        width = "90%",
        height = "auto",
        halign = "center",
        vmargin = 16,
        textAlignment = "center",

        markupmode = function(element)
            local implemented = m_mode == "walls" or m_mode == "zones" or m_mode == "surfaces" or m_mode == "elevation" or m_mode == "props"
            element:SetClass("collapsed", implemented)
            if not implemented then
                local modeName = m_mode
                for _,modeInfo in ipairs(MODES) do
                    if modeInfo.id == m_mode then
                        modeName = modeInfo.text
                    end
                end
                element.text = string.format("The %s mode is not implemented yet.", modeName)
            end
        end,
    }

    --The old "Show Map Overlay" checkbox lived here; the overlay is now split
    --into per-layer settings (mapoverlay:walls / elevation / terrain plus
    --per-zone-type toggles) managed from the title bar's map overlay menu and
    --the Settings screen. The panel needs no toggle of its own any more: an
    --open markup tab force-renders its own readout regardless of those
    --settings (walls + solid interiors on Walls, zones on Zones, contours +
    --height numbers on Elevation; see dmhub.GetMarkupZones).
    --
    --The Fade Map slider stays: it is live in every mode (fading the art
    --helps just as much when placing props).
    local overlayPanel = gui.Panel{
        width = "96%",
        height = "auto",
        halign = "center",
        flow = "vertical",
        vmargin = 4,

        --stacked: the default horizontal settings row gives its label width "60%",
        --which in a dock this narrow leaves the 160px slider hanging off the right
        --edge - the top of its range was literally unreachable. Stacked puts the
        --label on its own line and the slider below it, fully in view.
        CreateSettingsEditor("markup:fade", {stacked = true}),
    }

    --Take GUI focus for the panel and immediately (re-)register the current
    --mode's map tool, instead of waiting up to thinkTime (0.3s) for the next
    --tick. Called from every press that selects what gets drawn - mode tabs,
    --type/surface chips, list rows - so the panel is armed the instant the
    --user picks something, without them having to click a tool first.
    --
    --Focus goes on contentPanel, NOT on the pressed element. This matters:
    --chips and list rows are TRANSIENT - the palette rebuilds its children
    --whole on refreshzonepalette/refreshprops (which `monitorAssets` fires on
    --any asset-table change) and the zone/footstep lists rebuild theirs on
    --refreshzones. Parking focus on a chip meant the first stroke that
    --materialized a preset keyword wrote the keyword table, rebuilt the chips,
    --destroyed the focused chip, and left focus nil - so exactly one stroke
    --landed and every later one silently did nothing. contentPanel lives as
    --long as the panel does, and gui.ChildHasFocus counts the element itself.
    TakeMarkupFocus = function()
        if contentPanel ~= nil and contentPanel.valid then
            gui.SetFocus(contentPanel)
        end

        local toolPanel = nil
        if m_mode == "walls" then
            toolPanel = toolsPanel
        elseif m_mode == "zones" then
            toolPanel = zoneToolsPanel
        elseif m_mode == "surfaces" then
            toolPanel = footstepToolsPanel
        elseif m_mode == "props" then
            toolPanel = propsPanel
        end

        --must run after SetFocus: the think handlers gate on panel focus.
        if toolPanel ~= nil and toolPanel.valid then
            toolPanel:FireEvent("think")
        end
    end

    --(ReassertMarkupFocus lived here. It existed for one reason: presses that
    --wrote the SHARED building-tool settings made the Building editor's
    --palette re-press and refocus its own chip on the next polled monitor
    --pass, one frame after our own TakeMarkupFocus -- and because focus WAS
    --the armed state, that steal silently stopped wall drawing until the user
    --clicked a wall type again. It scheduled a re-grab 0.1s later to paper
    --over the race.
    --
    --Arming is explicit now and a focus steal changes nothing, so the race has
    --no consequence to paper over and the workaround is gone.)

    contentPanel = gui.Panel{
        id = "MapMarkupPanel",
        width = "100%",
        height = "auto",
        flow = "vertical",
        styles = GetPanelStyles(),

        --The host (dock container or rail window) fires this on a
        --user-initiated OPEN of the panel and when a press lands anywhere
        --on the panel that its own controls did not handle -- the
        --background, the title bar. It has already put focus on this
        --element. Opening or clicking the panel is asking to use it, so it
        --ARMS (agreed 2026-08-15: the explicit-arming rework first shipped
        --arrive-disarmed, walked back so opening arms like the other
        --map-mode panels; Escape and hiding still disarm, focus loss still
        --does not). TakeMarkupFocus additionally re-fires the current
        --mode's tool think, without which the very next click can land
        --before the 0.3s poll re-registers the map tool and silently do
        --nothing.
        panelFocused = function(element)
            m_arm.Set(true)
            TakeMarkupFocus()
        end,

        --ESCAPE, first refusal. The host window offers the press to its
        --active panel before closing itself (see DocumentSystem's escape
        --handler): while a tool is live, Escape means "put it down", and
        --claiming the press is what stops the same keystroke also closing
        --the window. Disarmed, we do not claim it and Escape closes as
        --usual.
        --
        --This is the path that actually runs for rail windows. The
        --dmhub.CancelEditing chain lower down is a DIFFERENT route (sticky
        --map focus) and never sees the press while the window has it.
        panelEscape = function(element, claim)
            if not m_arm.Armed() then
                return
            end
            m_arm.Set(false)
            --give up focus with the tool: both hosts skip the panelFocused
            --nudge while focus is already here (ClaimTabFocus /
            --FocusPanelContent guard on it), so keeping focus would mean
            --the next click on the panel does NOT re-arm. Dropping it also
            --puts the host's focus highlight out, which is the visible
            --"tool down".
            if gui.ChildHasFocus(element) then
                gui.SetFocus(nil)
            end
            if claim ~= nil then
                claim.claimed = true
            end
        end,

        --openness is NOT tracked from these events -- MarkupPanelIsOpen reads
        --it from the live panel (see its comment); these manage focus and
        --arming. Showing the panel ARMS it: switching to this panel is
        --asking to draw, matching the other map-mode panels (agreed
        --2026-08-15 -- the explicit-arming rework first shipped
        --arrive-disarmed and it was walked back). The rest of explicit
        --arming stands: Escape and hiding disarm, focus loss does not.
        showpanel = function(element)
            m_arm.Set(true)
            if not gui.ChildHasFocus(element) then
                gui.SetFocus(element)
            end
        end,

        --Hiding it DOES disarm: a tool you cannot see must not keep eating
        --map clicks.
        hidepanel = function(element)
            m_arm.Set(false)
            if gui.ChildHasFocus(element) then
                gui.SetFocus(nil)
            end
        end,

        --The dockablePanel ancestor can be nil: content can be hosted outside
        --the dock (PanelDocument bridge), and focus events can fire while the
        --panel is detached. Guard like Objects.lua does.
        --
        --These now only drive the host's focus HIGHLIGHT. They no longer
        --touch `markuparmed`: focus is not the armed state any more, so a
        --focus steal must not put the armed dot out while the tool is still
        --live. m_arm.Set owns that event.
        childfocus = function(element)
            local dockPanel = element:FindParentWithClass("dockablePanel")
            if dockPanel ~= nil then
                dockPanel:SetClass("highlightPanel", true)
            end
        end,

        childdefocus = function(element)
            local dockPanel = element:FindParentWithClass("dockablePanel")
            if dockPanel ~= nil then
                dockPanel:SetClass("highlightPanel", false)
            end
        end,

        children = {
            modeTabs,
            wallsPanel,
            zonesPanel,
            footstepsPanel,
            elevationPanel,
            propsPanel,
            placeholderPanel,
            overlayPanel,
        },
    }

    ThemeEngine.OnThemeChanged(mod, function()
        if contentPanel ~= nil and contentPanel.valid then
            contentPanel.styles = GetPanelStyles()
        end
    end)

    --NOTE: openness is not flagged here. A saved dock layout builds this
    --content at startup without showing it; MarkupPanelIsOpen derives
    --visibility from the live panel's ancestor chain.
    m_markupHud = contentPanel

    palettePanel:FireEvent("refreshpalette")
    zonePalettePanel:FireEvent("refreshzonepalette")
    zoneListPanel:FireEvent("refreshzones")
    footstepListPanel:FireEvent("refreshfootsteps")
    propsPanel:FireEventTree("refreshprops")
    contentPanel:FireEventTree("markupmode")

    return contentPanel
end

--============================================================================
--Engine hook chaining. The Building editor (Terrain.lua, loaded before this
--module) assigns dmhub.GetSelectedWall / dmhub.GetBuildingSolid; we wrap
--them so whichever panel has focus wins. dmhub.GetWallHeight needs no wrap:
--it reads the building:specifywallheight settings, which our height stepper
--drives directly.
--============================================================================

--MapMarkupHooks survives reloads of this file. If dmhub.GetSelectedWall is
--already our own wrapper (this file reloaded without Terrain.lua reloading),
--unwrap to the function we chained to instead of chaining a stale wrapper.
--rawget: reading an undeclared global errors in the DMHub Lua runtime.
--
--GOTCHA: each hook read can also be NIL on reload, even though the base half
--(Terrain.lua etc.) was never unloaded. The engine's hook slots record the
--mod that last wrote them, and unloading a mod nulls every slot it last
--wrote (CodeMod.OnUnload -> LuaInterface.UnloadMod). Chaining makes THIS mod
--the last writer of every hook it wraps, so reloading this file first nulls
--the whole chain - including the base half owned by another mod. When a
--hook reads nil, resurrect the remembered prior instead of chaining to nil
--(and never overwrite a remembered prior with nil): the base closure from
--the original load is still live and correct, since its own file was not
--reloaded.
MapMarkupHooks = rawget(_G, "MapMarkupHooks") or {}

local g_priorGetSelectedWall = dmhub.GetSelectedWall
if g_priorGetSelectedWall == MapMarkupHooks.getSelectedWallWrapper or g_priorGetSelectedWall == nil then
    g_priorGetSelectedWall = MapMarkupHooks.priorGetSelectedWall
end
MapMarkupHooks.priorGetSelectedWall = g_priorGetSelectedWall
MapMarkupHooks.getSelectedWallWrapper = function()
    local result = nil
    if g_priorGetSelectedWall ~= nil then
        result = g_priorGetSelectedWall()
    end
    if result ~= nil then
        return result
    end
    return GetMarkupSelectedWall()
end
dmhub.GetSelectedWall = MapMarkupHooks.getSelectedWallWrapper

local g_priorGetBuildingSolid = dmhub.GetBuildingSolid
if g_priorGetBuildingSolid == MapMarkupHooks.getBuildingSolidWrapper or g_priorGetBuildingSolid == nil then
    g_priorGetBuildingSolid = MapMarkupHooks.priorGetBuildingSolid
end
MapMarkupHooks.priorGetBuildingSolid = g_priorGetBuildingSolid
MapMarkupHooks.getBuildingSolidWrapper = function()
    --When the markup panel is driving wall drawing, never draw solid blocks,
    --even if the Building editor was left in Solid mode. (The Building
    --editor's solid flag is not focus-gated.)
    if GetMarkupSelectedWall() ~= nil then
        return false
    end
    if g_priorGetBuildingSolid ~= nil then
        return g_priorGetBuildingSolid()
    end
    return false
end
dmhub.GetBuildingSolid = MapMarkupHooks.getBuildingSolidWrapper

--Height editing. ElevationPanel.lua (DMHub Core Panels, loaded before this
--module) assigns dmhub.GetHeightEditingInfo, gated on its own dock panel
--having focus; we chain so whichever of the two panels has focus wins. Our
--half is nil unless this panel is focused AND in Elevation mode, so the
--Elevation Editor keeps working exactly as before.
local g_priorGetHeightEditingInfo = dmhub.GetHeightEditingInfo
if g_priorGetHeightEditingInfo == MapMarkupHooks.getHeightEditingInfoWrapper or g_priorGetHeightEditingInfo == nil then
    g_priorGetHeightEditingInfo = MapMarkupHooks.priorGetHeightEditingInfo
end
MapMarkupHooks.priorGetHeightEditingInfo = g_priorGetHeightEditingInfo
MapMarkupHooks.getHeightEditingInfoWrapper = function()
    local result = GetMarkupHeightEditingInfo()
    if result ~= nil then
        return result
    end
    if g_priorGetHeightEditingInfo ~= nil then
        return g_priorGetHeightEditingInfo()
    end
    return nil
end
dmhub.GetHeightEditingInfo = MapMarkupHooks.getHeightEditingInfoWrapper

--Invisible-only scoping for the Edit Points tool. The engine polls
--dmhub.GetWallPointsInvisibleOnly while the points tool is active; returning
--true restricts the tool to walls with invisible assets, so vertex editing
--driven from this panel cannot disturb visible art walls (those belong to
--the Building editor - design ledger #11, same rule as erasing).
--pcall on read AND write: this hook needs an engine build. On a stale engine
--the property doesn't exist, reads/assignments raise, and the tool simply
--edits all walls like the Building editor's version does.
local g_priorGetWallPointsInvisibleOnly = nil
pcall(function()
    g_priorGetWallPointsInvisibleOnly = dmhub.GetWallPointsInvisibleOnly
end)
if g_priorGetWallPointsInvisibleOnly == MapMarkupHooks.getWallPointsInvisibleOnlyWrapper or g_priorGetWallPointsInvisibleOnly == nil then
    g_priorGetWallPointsInvisibleOnly = MapMarkupHooks.priorGetWallPointsInvisibleOnly
end
MapMarkupHooks.priorGetWallPointsInvisibleOnly = g_priorGetWallPointsInvisibleOnly
MapMarkupHooks.getWallPointsInvisibleOnlyWrapper = function()
    --true only while THIS panel is the reason the points tool is active: the
    --shared tool setting is "points" and our (focus-gated) wall selection is
    --published. When the Building editor drives the tool instead, its own
    --selection wins the GetSelectedWall chain and we defer.
    if dmhub.GetSettingValue("buildingtool") == "points" and GetMarkupSelectedWall() ~= nil then
        return true
    end
    if g_priorGetWallPointsInvisibleOnly ~= nil then
        return g_priorGetWallPointsInvisibleOnly()
    end
    return false
end
pcall(function()
    dmhub.GetWallPointsInvisibleOnly = MapMarkupHooks.getWallPointsInvisibleOnlyWrapper
end)

--Object-editing filter for Props mode. The engine polls
--dmhub.GetObjectEditingFilter every frame; a non-nil keyword makes only
--matching (markup prop) objects visible/selectable/draggable and everything
--else inert to object selection. This hook is owned solely by this panel, so
--no chaining - but it needs an engine build: pcall on assignment so a stale
--engine (property does not exist -> assignment raises) leaves Props gated
--off (see PropsSupported).
MapMarkupHooks.getObjectEditingFilterWrapper = function()
    return GetMarkupObjectEditingFilter()
end
pcall(function()
    dmhub.GetObjectEditingFilter = MapMarkupHooks.getObjectEditingFilterWrapper
end)

--Object selection. ObjectPropertiesDialog (DMHub Core Panels, loaded before
--this module) assigns dmhub.ObjectsSelected to pop the generic object
--properties dialog; chain so markup props selected while the Props tab is
--focused bind to this panel's editors instead of opening that dialog.
local g_priorObjectsSelected = dmhub.ObjectsSelected
if g_priorObjectsSelected == MapMarkupHooks.objectsSelectedWrapper or g_priorObjectsSelected == nil then
    g_priorObjectsSelected = MapMarkupHooks.priorObjectsSelected
end
MapMarkupHooks.priorObjectsSelected = g_priorObjectsSelected
MapMarkupHooks.objectsSelectedWrapper = function(objects)
    if MarkupHandleObjectsSelected(objects) then
        return
    end
    if g_priorObjectsSelected ~= nil then
        g_priorObjectsSelected(objects)
    end
end
dmhub.ObjectsSelected = MapMarkupHooks.objectsSelectedWrapper

--Escape. SheetHud.CancelFocus routes Escape on a sticky-focused panel into
--dmhub.CancelEditing; chain so Escape aborts a half-placed teleporter pair
--(deleting the first teleporter) and consumes the press. Objects.lua (loaded
--before this module) assigns the base handler, which clears object selection.
--Focus loss is the fallback abort (the props think loop), so nothing is lost
--if some other escape consumer wins.
local g_priorCancelEditing = dmhub.CancelEditing
if g_priorCancelEditing == MapMarkupHooks.cancelEditingWrapper or g_priorCancelEditing == nil then
    g_priorCancelEditing = MapMarkupHooks.priorCancelEditing
end
MapMarkupHooks.priorCancelEditing = g_priorCancelEditing
MapMarkupHooks.cancelEditingWrapper = function(sheet)
    if m_props.pendingPartnerId ~= nil and m_mode == "props" and m_arm.Armed() then
        AbortPendingTeleporterPair()
        return true
    end
    --ESCAPE PUTS THE TOOL DOWN. Ordered after the teleporter abort (that is
    --the more specific half-finished thing to back out of) and before every
    --other consumer: while a markup tool is live, Escape means "stop
    --drawing", not "clear the selection" or "close the window". Consuming it
    --is what stops the window's own escape handler closing the panel out from
    --under a single keypress.
    if m_arm.Armed() then
        --m_arm.Set repaints the strip and unregisters the map tools.
        m_arm.Set(false)
        return true
    end
    if g_priorCancelEditing ~= nil then
        return g_priorCancelEditing(sheet)
    end
    return false
end
dmhub.CancelEditing = MapMarkupHooks.cancelEditingWrapper

--Palette selection for the placement ghost. Objects.lua (loaded before this
--module) assigns dmhub.GetSelectedObject for the Objects panel's palette;
--the engine polls it every frame and shows a placement preview for the
--returned object assetid. Chain so the props tab's armed type publishes its
--asset; our half is focus- and mode-gated, so the Objects panel keeps
--working exactly as before.
local g_priorGetSelectedObject = dmhub.GetSelectedObject
if g_priorGetSelectedObject == MapMarkupHooks.getSelectedObjectWrapper or g_priorGetSelectedObject == nil then
    g_priorGetSelectedObject = MapMarkupHooks.priorGetSelectedObject
end
MapMarkupHooks.priorGetSelectedObject = g_priorGetSelectedObject
MapMarkupHooks.getSelectedObjectWrapper = function()
    local result = GetMarkupSelectedObject()
    if result ~= nil then
        return result
    end
    if g_priorGetSelectedObject ~= nil then
        return g_priorGetSelectedObject()
    end
    return nil
end
dmhub.GetSelectedObject = MapMarkupHooks.getSelectedObjectWrapper

--============================================================================
--Teleporter pair arrows: whenever the Props tab is armed (same gate as the
--object-editing filter, so arrows show exactly when the teleporter markers
--themselves are visible), every markup teleporter pair with both ends on the
--current floor gets a double-headed arrow drawn between them out of
--HighlightLine markers (shaft + two head strokes per end). Driven by a
--self-rescheduling poll rather than panel think so the arrows reliably clear
--when the panel is defocused, hidden, or closed - and so dragging an end
--re-routes the arrow within half a second.
--============================================================================

--Reload safety: HighlightLine markers are engine objects that survive a Lua
--reload, so the live handles are shared through MapMarkupHooks and stale
--ones from a previous load of this file are destroyed here.
if MapMarkupHooks.teleporterArrowHandles ~= nil then
    for _,handle in ipairs(MapMarkupHooks.teleporterArrowHandles) do
        pcall(function() handle:Destroy() end)
    end
end
local m_teleporterArrowHandles = {}
MapMarkupHooks.teleporterArrowHandles = m_teleporterArrowHandles
local m_teleporterArrowKey = nil

--The object pairs currently drawn as arrows ({aObjid, bObjid, key=linkkey}
--each) plus the floor they were computed for: the FAST poll re-reads just
--these objects' positions so a dragged end re-routes its arrow in real time,
--while the slow poll owns membership (pairs appearing/disappearing).
local m_teleporterArrowPairIds = {}
local m_teleporterArrowFloorId = nil
local m_teleporterArrowFastActive = false

local function ClearTeleporterArrows()
    for _,handle in ipairs(m_teleporterArrowHandles) do
        pcall(function() handle:Destroy() end)
    end
    for i = #m_teleporterArrowHandles, 1, -1 do
        m_teleporterArrowHandles[i] = nil
    end
    m_teleporterArrowKey = nil
end

local ARROW_COLOR = "#7fd4ff"
local ARROW_HEAD_LENGTH = 0.45
local ARROW_HEAD_ANGLE = 0.45  --radians, ~26 degrees off the shaft
local ARROW_END_INSET = 0.35   --pull the ends off the teleporter markers

local function AddArrowLine(floorIndex, x1, y1, x2, y2)
    local handle = dmhub.HighlightLine{
        color = ARROW_COLOR,
        a = core.Vector2(x1, y1),
        b = core.Vector2(x2, y2),
        floorIndex = floorIndex,
        terrainParallax = true,
    }
    if handle ~= nil then
        m_teleporterArrowHandles[#m_teleporterArrowHandles+1] = handle
    end
end

local function RotateVec(x, y, cosA, sinA)
    return x*cosA - y*sinA, x*sinA + y*cosA
end

--A double-headed arrow between two teleporters (both directions work).
local function AddPairArrow(floorIndex, x1, y1, x2, y2)
    local dx = x2 - x1
    local dy = y2 - y1
    local len = math.sqrt(dx*dx + dy*dy)
    if len < 0.6 then
        --ends on top of each other: an arrow would be unreadable scribble.
        return
    end
    local ux = dx/len
    local uy = dy/len
    if len > 2*ARROW_END_INSET + 0.5 then
        x1 = x1 + ux*ARROW_END_INSET
        y1 = y1 + uy*ARROW_END_INSET
        x2 = x2 - ux*ARROW_END_INSET
        y2 = y2 - uy*ARROW_END_INSET
    end

    AddArrowLine(floorIndex, x1, y1, x2, y2)

    local cosA = math.cos(ARROW_HEAD_ANGLE)
    local sinA = math.sin(ARROW_HEAD_ANGLE)
    --head at (x2,y2): strokes angled back along the shaft.
    local hx, hy = RotateVec(-ux, -uy, cosA, sinA)
    AddArrowLine(floorIndex, x2, y2, x2 + hx*ARROW_HEAD_LENGTH, y2 + hy*ARROW_HEAD_LENGTH)
    hx, hy = RotateVec(-ux, -uy, cosA, -sinA)
    AddArrowLine(floorIndex, x2, y2, x2 + hx*ARROW_HEAD_LENGTH, y2 + hy*ARROW_HEAD_LENGTH)
    --head at (x1,y1): strokes angled forward along the shaft.
    hx, hy = RotateVec(ux, uy, cosA, sinA)
    AddArrowLine(floorIndex, x1, y1, x1 + hx*ARROW_HEAD_LENGTH, y1 + hy*ARROW_HEAD_LENGTH)
    hx, hy = RotateVec(ux, uy, cosA, -sinA)
    AddArrowLine(floorIndex, x1, y1, x1 + hx*ARROW_HEAD_LENGTH, y1 + hy*ARROW_HEAD_LENGTH)
end

local function UpdateTeleporterArrows()
    --same gate as the engine filter: props tab focused. When it goes nil the
    --teleporter markers themselves disappear, so the arrows must too.
    local show = GetMarkupObjectEditingFilter() ~= nil and game.currentFloor ~= nil
    if not show then
        if #m_teleporterArrowHandles > 0 or m_teleporterArrowKey ~= nil then
            ClearTeleporterArrows()
        end
        m_teleporterArrowPairIds = {}
        return
    end

    --group markup teleporters on the CURRENT floor by link key; a group of
    --two or more gets an arrow between consecutive members (normal case: a
    --pair and one arrow). Cross-floor pairs draw nothing - there is no
    --sensible line to draw to another floor.
    local currentFloorId = game.currentFloorId
    local groups = {}
    local order = {}
    for _,entry in ipairs(MarkupTeleportersOnMap()) do
        local key = LinkKey(entry.link)
        if key ~= "" and entry.floorid == currentFloorId then
            local group = groups[key]
            if group == nil then
                group = {}
                groups[key] = group
                order[#order+1] = key
            end
            group[#group+1] = entry
        end
    end
    table.sort(order)

    local floorIndex = game.currentFloorIndex
    local arrows = {}
    local pairIds = {}
    local keyParts = { tostring(floorIndex) }
    for _,key in ipairs(order) do
        local group = groups[key]
        if #group >= 2 then
            table.sort(group, function(a, b)
                return tostring(a.obj.objid) < tostring(b.obj.objid)
            end)
            for i = 1, #group - 1 do
                local a = group[i].obj
                local b = group[i+1].obj
                arrows[#arrows+1] = { a.x, a.y, b.x, b.y }
                pairIds[#pairIds+1] = { a.objid, b.objid, key = key }
                keyParts[#keyParts+1] = string.format("%s:%.2f,%.2f-%.2f,%.2f", key, a.x, a.y, b.x, b.y)
            end
        end
    end

    --hand the drawn membership to the fast poll (position tracking during
    --drags); recorded even when nothing changed so the first slow pass after
    --arming primes it.
    m_teleporterArrowPairIds = pairIds
    m_teleporterArrowFloorId = game.currentFloorId

    --rebuild only when an endpoint/pair actually changed; the markers are
    --parallax-baked so camera movement needs no rebuild.
    local arrowKey = table.concat(keyParts, ";")
    if arrowKey == m_teleporterArrowKey then
        return
    end

    ClearTeleporterArrows()
    for _,arrow in ipairs(arrows) do
        AddPairArrow(floorIndex, arrow[1], arrow[2], arrow[3], arrow[4])
    end
    m_teleporterArrowKey = arrowKey
end

--The FAST poll: while the Props tab is armed and arrows are on screen, track
--the drawn pairs' positions at 20Hz so dragging a teleporter end re-routes
--its arrow in real time (the engine updates the dragged object's data pos
--every frame mid-drag). Membership is the slow poll's job - this only moves
--EXISTING arrows, and hands back to the slow poll (which restarts it) the
--moment the tab disarms, the floor changes, or the arrows empty.
local function TeleporterArrowFastPoll()
    if mod.unloaded then
        m_teleporterArrowFastActive = false
        return
    end

    local keepRunning = false
    local ok, err = pcall(function()
        if #m_teleporterArrowPairIds == 0 or GetMarkupObjectEditingFilter() == nil then
            return
        end
        if game.currentFloorId ~= m_teleporterArrowFloorId then
            return
        end
        local floor = game.currentFloor
        if floor == nil then
            return
        end
        keepRunning = true

        local floorIndex = game.currentFloorIndex
        local arrows = {}
        local keyParts = { tostring(floorIndex) }
        for _,pair in ipairs(m_teleporterArrowPairIds) do
            local a = floor:GetObject(pair[1])
            local b = floor:GetObject(pair[2])
            if a ~= nil and a.valid and b ~= nil and b.valid then
                arrows[#arrows+1] = { a.x, a.y, b.x, b.y }
                --EXACT same key format as the slow poll, so neither loop
                --rebuilds arrows the other just drew.
                keyParts[#keyParts+1] = string.format("%s:%.2f,%.2f-%.2f,%.2f", pair.key, a.x, a.y, b.x, b.y)
            end
        end

        local arrowKey = table.concat(keyParts, ";")
        if arrowKey ~= m_teleporterArrowKey then
            ClearTeleporterArrows()
            for _,arrow in ipairs(arrows) do
                AddPairArrow(floorIndex, arrow[1], arrow[2], arrow[3], arrow[4])
            end
            m_teleporterArrowKey = arrowKey
        end
    end)
    if not ok then
        dmhub.Debug("MARKUP:: teleporter arrow fast poll error: " .. tostring(err))
    end

    if keepRunning then
        dmhub.Schedule(0.05, TeleporterArrowFastPoll)
    else
        m_teleporterArrowFastActive = false
    end
end

local function TeleporterArrowPoll()
    if mod.unloaded then
        --a newer load of this file owns the shared handles now and has
        --already destroyed any we left behind.
        return
    end
    local ok, err = pcall(UpdateTeleporterArrows)
    if not ok then
        dmhub.Debug("MARKUP:: teleporter arrows error: " .. tostring(err))
    end

    --spin up the fast tracker whenever arrows exist and the tab is armed;
    --it shuts itself down (and this restarts it) as conditions change.
    if not m_teleporterArrowFastActive and #m_teleporterArrowPairIds > 0
        and GetMarkupObjectEditingFilter() ~= nil then
        m_teleporterArrowFastActive = true
        dmhub.Schedule(0.05, TeleporterArrowFastPoll)
    end

    dmhub.Schedule(0.4, TeleporterArrowPoll)
end
dmhub.Schedule(0.4, TeleporterArrowPoll)
