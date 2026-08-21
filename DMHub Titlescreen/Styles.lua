local mod = dmhub.GetModLoading()

--- ThemeEngine: lets the whole UI change colors by swapping 'color schemes'
--- and 'themes' instead of hardcoding colors everywhere. Ported from the
--- Draw Steel Codex.
---
--- The idea: style rules can put '@name' strings in color, fontFace, and
--- gradient properties (for example bgcolor = '@bg'). When a panel asks for
--- styles with ThemeEngine.GetStyles(), each '@name' is swapped for the real
--- value from the active color scheme. Results are cached per theme+scheme
--- pair, so repeated calls are cheap.
---
--- This file is only the machinery. The actual schemes, themes, and style
--- rules are registered in DefaultStyles.lua (DMHub Core UI), and players
--- pick a look in the 'Theme & Color Scheme...' dialog (SettingsGui.lua).
--- @class ThemeEngine
ThemeEngine = {} --RegisterGameType("ThemeEngine")

-- =============================================================================
-- Private state
-- =============================================================================

local _colorSchemes = {}         -- schemeId -> stored color-scheme spec
local _themes = {}               -- themeId -> stored theme spec

local _activeThemeId = nil
local _activeSchemeId = nil

-- Persistent storage for the user's active theme and color scheme
-- selections. No section/editor/description, so they don't appear in
-- the settings UI. storage = "preference" -- per-user, persists across
-- games on this machine.
local _activeThemeSetting = setting{
    id = "themeengine.activetheme",
    storage = "preference",
    default = "default",
}
local _activeSchemeSetting = setting{
    id = "themeengine.activecolorscheme",
    storage = "preference",
    default = "default",
}

-- User-created color schemes are persisted (as a JSON array) on the user's
-- account, so they follow the user across machines, separate from the built-in
-- schemes registered by DefaultStyles.lua. The account object (and thus this
-- setting) loads as a unit before this mod runs, so LoadUserColorSchemes()
-- at load time sees them. The creator UI is only reachable when logged in, so
-- there is always an account to read from / write to.
local _userSchemesSetting = setting{
    id = "themeengine_userschemes",
    storage = "account",
    default = "[]",
}

-- Reserved scheme id used by the theme-creator UI for its live preview while
-- the user is still editing (before they save).
local PREVIEW_SCHEME_ID = "__usercreate_preview__"

local _cache = {}                -- "themeId|schemeId" -> resolved styles array
local _loggedUnresolved = {}     -- set of "domain:name" keys already logged

-- =============================================================================
-- Constants
-- =============================================================================

local COLOR_PROPS = {
    color = true,
    bgcolor = true,
    borderColor = true,
    scrollHandleColor = true
}
local FONT_PROPS = { fontFace = true }
local GRADIENT_PROPS = { gradient = true }

local UNRESOLVED_COLOR = "#FF00FF"  -- magenta, loud in UI
local UNRESOLVED_FONT = "LiberationSans"     -- known safe fallback

local DEFAULT_THEME_ID = "default"
local DEFAULT_SCHEME_ID = "default"

local THEME_CHANGED_EVENT = "ThemeEngine.ThemeChanged"

-- =============================================================================
-- Available fonts (engine-supplied)
-- =============================================================================

-- Lazy-built case-insensitive set of font names from gui.availableFonts.
-- Built on first access so we don't depend on engine load order at module init.
local _availableFontsLower = nil

local function _buildAvailableFontsSet()
    local set = {}
    local list = gui.availableFonts
    if type(list) == "table" then
        for _, name in ipairs(list) do
            if type(name) == "string" then
                set[string.lower(name)] = true
            end
        end
    end
    return set
end

-- =============================================================================
-- Logging
-- =============================================================================

local function _log(msg)
    print("THEME_ENGINE::", msg)
end

--- Log an unresolved reference once per (domain, name) pair per session.
--- @param domain string "color" | "font" | "theme" | "colorScheme"
--- @param name string The unresolved id or token name
local function _logUnresolved(domain, name)
    local key = domain .. ":" .. tostring(name)
    if _loggedUnresolved[key] then return end
    _loggedUnresolved[key] = true
    _log("unresolved " .. domain .. " reference: " .. tostring(name))
end

--- Validate a font name against gui.availableFonts. Case-insensitive.
--- Unknown names log once and return UNRESOLVED_FONT (LiberationSans).
--- Non-strings pass through unchanged.
--- @param name any
--- @return any
local function _validateFontFace(name)
    if type(name) ~= "string" then return name end
    if _availableFontsLower == nil then
        _availableFontsLower = _buildAvailableFontsSet()
    end
    if _availableFontsLower[string.lower(name)] then
        return name
    end
    _logUnresolved("fontFace", name)
    return UNRESOLVED_FONT
end

--- Coerce a theme id to a registered one. Nil and unknown ids both
--- become DEFAULT_THEME_ID. Unknown ids are logged once.
--- @param id string|nil
--- @return string
local function _normalizeThemeId(id)
    if id == nil then return DEFAULT_THEME_ID end
    if _themes[id] then return id end
    if id ~= DEFAULT_THEME_ID then
        _logUnresolved("theme", id)
    end
    return DEFAULT_THEME_ID
end

--- Coerce a color scheme id to a registered one. Nil and unknown ids
--- both become DEFAULT_SCHEME_ID. Unknown ids are logged once.
--- @param id string|nil
--- @return string
local function _normalizeSchemeId(id)
    if id == nil then return DEFAULT_SCHEME_ID end
    if _colorSchemes[id] then return id end
    if id ~= DEFAULT_SCHEME_ID then
        _logUnresolved("colorScheme", id)
    end
    return DEFAULT_SCHEME_ID
end

-- =============================================================================
-- Resolver helpers
-- =============================================================================

--- Build the effective theme chain for resolution.
--- Every non-default theme inherits only from default, so the chain is
--- at most two entries: [default] (if effective IS default or no
--- effective was given) or [default, effective] otherwise.
--- @param themeId string|nil
--- @return table[] chain
local function _buildChain(themeId)
    local chain = {}

    local default = _themes[DEFAULT_THEME_ID]
    if default then
        chain[#chain + 1] = default
    end

    if themeId == nil or themeId == DEFAULT_THEME_ID then
        return chain
    end

    local effective = _themes[themeId]
    if not effective then
        _logUnresolved("theme", themeId)
        return chain
    end

    chain[#chain + 1] = effective
    return chain
end

--- Resolve a value, substituting @name references based on the active property domain.
--- Recurses into tables (gradient stops, border sub-tables, etc.) and preserves metatables.
--- Never mutates the input.
--- @param value any
--- @param domain string|nil "colors" | "fonts" | "gradients" | nil
--- @param tables table { colors = {...}, fonts = {...}, gradients = {...} }
--- @return any
local function _resolveValue(value, domain, tables)
    if type(value) == "string" then
        if value:sub(1, 1) == "@" then
            local name = value:sub(2)
            if domain == "colors" then
                local v = tables.colors[name]
                if v == nil then
                    _logUnresolved("color", name)
                    return UNRESOLVED_COLOR
                end
                return v
            elseif domain == "fonts" then
                local v = tables.fonts[name]
                if v == nil then
                    _logUnresolved("font", name)
                    return UNRESOLVED_FONT
                end
                return _validateFontFace(v)
            elseif domain == "gradients" then
                local spec = tables.gradients[name]
                if spec == nil then
                    _logUnresolved("gradient", name)
                    return nil
                end
                -- Resolve @name refs inside the spec (stops' color keys, etc.),
                -- then build the framework's Gradient object from the plain table.
                return gui.Gradient(_resolveValue(spec, nil, tables))
            else
                -- Not a themable property; leave the literal in place.
                return value
            end
        end
        if domain == "fonts" then
            return _validateFontFace(value)
        end
        return value
    elseif type(value) == "table" then
        local cloned = {}
        for k, v in pairs(value) do
            local nextDomain
            if COLOR_PROPS[k] then
                nextDomain = "colors"
            elseif FONT_PROPS[k] then
                nextDomain = "fonts"
            elseif GRADIENT_PROPS[k] then
                nextDomain = "gradients"
            else
                nextDomain = domain
            end
            cloned[k] = _resolveValue(v, nextDomain, tables)
        end
        local mt = getmetatable(value)
        if mt then setmetatable(cloned, mt) end
        return cloned
    end
    return value
end

--- Walk a raw styles array, cloning each rule and substituting @name references.
--- The `selectors` array is treated as literal -- never substituted.
--- @param rawStyles table[]
--- @param tables table { colors, fonts, gradients }
--- @return table[]
local function _buildResolvedStyles(rawStyles, tables)
    local out = {}
    local function addRule(rule)
        if type(rule) ~= "table" then
            --gui.Style objects are engine userdata we cannot iterate, so
            --they pass through untouched. Any "@" tokens inside them will
            --NOT resolve -- author such rules as plain tables instead.
            out[#out + 1] = rule
            return
        end
        if rule[1] ~= nil then
            --A nested list of rules (array entries instead of properties)
            --is flattened, so callers can compose style sets freely.
            for _, sub in ipairs(rule) do
                addRule(sub)
            end
            return
        end
        local cloned = {}
        for k, v in pairs(rule) do
            if k == "selectors" then
                cloned.selectors = v
            else
                local domain
                if COLOR_PROPS[k] then
                    domain = "colors"
                elseif FONT_PROPS[k] then
                    domain = "fonts"
                elseif GRADIENT_PROPS[k] then
                    domain = "gradients"
                end
                cloned[k] = _resolveValue(v, domain, tables)
            end
        end
        out[#out + 1] = cloned
    end
    for _, rule in ipairs(rawStyles) do
        addRule(rule)
    end
    return out
end

--- Merge color tables: default scheme first, then effective scheme overrides.
--- @param schemeId string|nil
--- @return table
local function _buildColorTable(schemeId)
    local out = {}

    local default = _colorSchemes[DEFAULT_SCHEME_ID]
    if default and default.colors then
        for k, v in pairs(default.colors) do
            out[k] = v
        end
    end

    if schemeId == nil then
        return out
    end

    local effective = _colorSchemes[schemeId]
    if not effective then
        if schemeId ~= DEFAULT_SCHEME_ID then
            _logUnresolved("colorScheme", schemeId)
        end
        return out
    end

    if effective.colors then
        for k, v in pairs(effective.colors) do
            out[k] = v
        end
    end

    return out
end

--- Merge gradient specs: default scheme first, then effective scheme overrides.
--- Unresolved-scheme logging is handled by `_buildColorTable`; this function stays silent.
--- @param schemeId string|nil
--- @return table
local function _buildGradientTable(schemeId)
    local out = {}

    local default = _colorSchemes[DEFAULT_SCHEME_ID]
    if default and default.gradients then
        for k, v in pairs(default.gradients) do
            out[k] = v
        end
    end

    if schemeId == nil then
        return out
    end

    local effective = _colorSchemes[schemeId]
    if not effective or not effective.gradients then
        return out
    end

    for k, v in pairs(effective.gradients) do
        out[k] = v
    end

    return out
end

--- Merge fonts tables: default theme's fonts first, then effective theme's
--- fonts overlaid on top. The chain passed in is always [default, effective]
--- (or just [default] if effective IS default).
--- @param chain table[]
--- @return table
local function _buildFontsTable(chain)
    local out = {}
    for _, theme in ipairs(chain) do
        if theme.fonts then
            for k, v in pairs(theme.fonts) do
                out[k] = v
            end
        end
    end
    return out
end

--- Resolve explicit arguments + active state into an effective (themeId, schemeId) pair.
--- Explicit overrides bypass the user's active color scheme selection. When nothing
--- is selected at any layer, falls back to the default theme and default color scheme
--- so callers always get a deterministic, renderable pair.
--- @param themeIdArg string|nil
--- @param schemeIdArg string|nil
--- @return string themeId
--- @return string schemeId
local function _resolveEffectivePair(themeIdArg, schemeIdArg)

    local themeId = themeIdArg or _activeThemeId
    local schemeId

    if themeIdArg ~= nil then
        -- Explicit theme override: use theme's colorScheme unless schemeId also given.
        if schemeIdArg ~= nil then
            schemeId = schemeIdArg
        else
            local theme = _themes[themeId]
            schemeId = theme and theme.colorScheme or nil
        end
    else
        -- No theme override: respect user's active scheme, else theme's colorScheme.
        if schemeIdArg ~= nil then
            schemeId = schemeIdArg
        elseif _activeSchemeId ~= nil then
            schemeId = _activeSchemeId
        else
            local theme = themeId and _themes[themeId] or nil
            schemeId = theme and theme.colorScheme or nil
        end
    end

    return _normalizeThemeId(themeId), _normalizeSchemeId(schemeId)
end

local function _cacheKey(themeId, schemeId)
    return (themeId or "_") .. "|" .. (schemeId or "_")
end

--Subscriptions made before EventUtils (DMHub Utils) has loaded -- possible
--at the cold-boot lobby, where the engine loads ONLY this module (the
--title bar at the end of this file subscribes during that phase). Each
--entry becomes a real EventUtils registration on flush.
local _pendingThemeListeners = {}

local function _flushPendingThemeListeners()
    if #_pendingThemeListeners == 0 then
        return
    end
    local eu = rawget(_G, "EventUtils")
    if eu == nil then
        return
    end
    local pending = _pendingThemeListeners
    _pendingThemeListeners = {}
    for _, p in ipairs(pending) do
        if not p.deregistered then
            p.listener = eu.RegisterGlobalEventHandler(p.mod, THEME_CHANGED_EVENT, p.callback)
        end
    end
end

local function _fireThemeChanged()
    --late-loading listeners first, so a registration queued before
    --EventUtils existed still receives this very event.
    _flushPendingThemeListeners()
    local eu = rawget(_G, "EventUtils")
    if eu then
        eu.FireGlobalEvent(THEME_CHANGED_EVENT)
    end
end

--- Return true if the given color scheme id is currently referenced by active state:
--- either the user's active override or the active theme's `colorScheme` field.
--- @param id string
--- @return boolean
local function _isColorSchemeInUse(id)
    if id == _activeSchemeId then
        return true
    end
    if _activeThemeId ~= nil then
        local theme = _themes[_activeThemeId]
        if theme and theme.colorScheme == id then
            return true
        end
    end
    return false
end

--- Return true if the given theme id is the currently-active theme.
--- (After flattening, the "active chain" is just [default, active]; the
--- default theme is handled separately in DeregisterTheme.)
--- @param id string
--- @return boolean
local function _isThemeInActiveChain(id)
    return _activeThemeId ~= nil and id == _activeThemeId
end

-- =============================================================================
-- Public API -- Registration
-- =============================================================================

--- Register a color scheme. Returns false if the id is already registered; the
--- existing registration is left untouched.
---
--- `gradients` is an optional map of gradient specs keyed by name. Each spec is a
--- plain table (not a `gui.Gradient`); the engine wraps it with `gui.Gradient` at
--- resolve time. Stops inside the spec may use `@name` refs to colors in the same
--- scheme -- those resolve during style resolution against the merged color table.
--- @param spec table { id, name, description, colors = { name = hex, ... }, gradients? = { name = spec, ... } }
--- @return boolean registered
function ThemeEngine.RegisterColorScheme(spec)
    if _colorSchemes[spec.id] then
        return false
    end
    _colorSchemes[spec.id] = {
        id = spec.id,
        name = spec.name,
        description = spec.description,
        colors = spec.colors or {},
        gradients = spec.gradients or {},
    }
    --clear the resolved-styles cache, mirroring DeregisterColorScheme: a
    --consumer that resolved styles BEFORE this registration (e.g. the title
    --bar, which loads with this module, ahead of DefaultStyles) memoized a
    --result missing these colors; without this, that stale entry would be
    --returned forever for the same theme/scheme pair.
    _cache = {}
    return true
end

--- Register a color scheme from a small set of anchor colors.
--- Current implementation: treats anchors as the full color table. Derivation rules
--- will be filled in once the canonical color key set is settled.
--- @param spec table { id, name, description, colors = { <anchors> }, gradients? = { name = spec, ... } }
--- @return boolean registered
function ThemeEngine.RegisterSimpleColorScheme(spec)
    -- TODO: Map the simple colors into the full scheme
    return ThemeEngine.RegisterColorScheme({
        id = spec.id,
        name = spec.name,
        description = spec.description,
        colors = spec.colors,
        gradients = spec.gradients,
    })
end

--- Deregister a color scheme by id. Silent no-op if the id isn't registered.
---
--- Refuses (with a log) to remove:
---   * the default color scheme -- it's the ultimate fallback and must remain present;
---   * any scheme currently in use -- the user's active override or the scheme
---     referenced by the active theme's `colorScheme` field.
---
--- Because removal can only affect entries that aren't on-screen, nothing visible
--- changes and OnThemeChanged is not fired. The resolved-styles cache is still
--- cleared so a later re-registration of the same id can't return stale content.
--- @param id string
--- @return boolean removed
function ThemeEngine.DeregisterColorScheme(id)
    if id == DEFAULT_SCHEME_ID then
        _log("refused to deregister the default color scheme")
        return false
    end
    if _isColorSchemeInUse(id) then
        _log("refused to deregister color scheme in use: " .. tostring(id))
        return false
    end
    if not _colorSchemes[id] then
        return false
    end
    _colorSchemes[id] = nil
    _cache = {}
    return true
end

--- Register a theme. Returns false if the id is already registered; the existing
--- registration is left untouched.
---
--- Every non-default theme inherits implicitly from the default theme. There is
--- no `inherit` chain -- the resolution chain is always [default, effective].
---
--- Font values in the `fonts` map are validated against the hardcoded font catalog.
--- Unknown names are logged once per unique name but do not prevent registration --
--- this matches the engine's "loud but non-fatal" policy for missing references.
--- @param spec table { id, name, description, colorScheme, fonts?, styles }
--- @return boolean registered
function ThemeEngine.RegisterTheme(spec)
    if _themes[spec.id] then
        return false
    end

    _themes[spec.id] = {
        id = spec.id,
        name = spec.name,
        description = spec.description,
        colorScheme = spec.colorScheme,
        fonts = spec.fonts or {},
        styles = spec.styles or {},
    }
    --clear the resolved-styles cache, mirroring DeregisterTheme (see the
    --note in RegisterColorScheme).
    _cache = {}
    return true
end

--- Deregister a theme by id. Silent no-op if the id isn't registered.
---
--- Refuses (with a log) to remove:
---   * the default theme -- it's the ultimate fallback and must remain present;
---   * the currently active theme -- removing it while it's rendering would
---     visibly break the UI.
---
--- Because removal can only affect entries that aren't on-screen, nothing visible
--- changes and OnThemeChanged is not fired. The resolved-styles cache is still
--- cleared so a later re-registration of the same id can't return stale content.
--- @param id string
--- @return boolean removed
function ThemeEngine.DeregisterTheme(id)
    if id == DEFAULT_THEME_ID then
        _log("refused to deregister the default theme")
        return false
    end
    if _isThemeInActiveChain(id) then
        _log("refused to deregister theme in active chain: " .. tostring(id))
        return false
    end
    if not _themes[id] then
        return false
    end
    _themes[id] = nil
    _cache = {}
    return true
end

-- =============================================================================
-- Public API -- Activation & inspection
-- =============================================================================

--- Set the active theme. Stores the id as given without validation; resolution
--- happens at read time (GetActiveTheme / GetStyles fall back to default for
--- unknown or nil ids). Fires OnThemeChanged if the stored value actually changed.
--- @param themeId string|nil
function ThemeEngine.SetActiveTheme(themeId)
    if _activeThemeId == themeId then return end
    _activeThemeId = themeId
    _activeThemeSetting:Set(themeId or "default")
    _fireThemeChanged()
end

--- Set the active color scheme. Stores the id as given without validation;
--- resolution happens at read time (GetActiveColorScheme / GetStyles fall back
--- to default for unknown or nil ids). Fires OnThemeChanged if the stored value
--- actually changed.
--- @param schemeId string|nil
function ThemeEngine.SetActiveColorScheme(schemeId)
    if _activeSchemeId == schemeId then return end
    _activeSchemeId = schemeId
    _activeSchemeSetting:Set(schemeId or "default")
    _fireThemeChanged()
end

--- Returns the active theme id, guaranteed to be a registered id.
--- @return string
function ThemeEngine.GetActiveTheme()
    return _normalizeThemeId(_activeThemeId)
end

--- Returns the active color scheme id, guaranteed to be a registered id.
--- @return string
function ThemeEngine.GetActiveColorScheme()
    return _normalizeSchemeId(_activeSchemeId)
end

--- Restore the persisted active theme / scheme ids verbatim. Unknown ids are
--- preserved here -- the read path coerces them to default at resolution time,
--- which means the user's stored preference survives even when the registering
--- mod isn't loaded yet (or at all in the current session).
function ThemeEngine.RestoreActiveSelection()
    _activeThemeId = _activeThemeSetting:Get()
    _activeSchemeId = _activeSchemeSetting:Get()
    _fireThemeChanged()
end

-- =============================================================================
-- Public API -- User-created color schemes (persisted per-user)
-- =============================================================================

-- The color tokens the theme-creator UI exposes for editing. Status colors
-- (success / info / warning / danger) and implStatus* are intentionally left
-- out so they stay semantically consistent across schemes.
ThemeEngine.userColorKeys = {
    "bg", "bgAlt", "bgInverse",
    "fg", "fgStrong", "fgMuted", "fgInverse",
    "border", "borderInverse",
    "accent", "accentHover",
    "disabled",
}

-- Hard cap on how many custom color schemes a user may create. Enforced as a
-- backstop in SaveUserColorScheme and gated in the creator UI (the "Create
-- New..." entry is hidden once the user is at the cap).
ThemeEngine.maxUserColorSchemes = 6

-- Upsert a user color scheme directly into the registry, bypassing the
-- duplicate-id guard and the in-use deregister refusal so an existing custom
-- scheme can be edited in place. Clears the resolved-styles cache.
local function _upsertUserDef(def)
    _colorSchemes[def.id] = {
        id = def.id,
        name = def.name,
        description = def.description or "Custom color scheme.",
        colors = def.colors or {},
        gradients = {},
    }
    _cache = {}
end

--- Returns the array of persisted user color-scheme defs ({id, name, colors}).
--- Guarded against missing / malformed stored data.
--- @return table[]
function ThemeEngine.GetUserColorSchemes()
    local raw = _userSchemesSetting:Get()
    if type(raw) ~= "string" or raw == "" then
        return {}
    end
    local parsed = dmhub.FromJson(raw)
    if not parsed.success or type(parsed.result) ~= "table" then
        return {}
    end
    return parsed.result
end

--- True if id names a user-created (deletable) scheme, as opposed to a built-in.
--- @param id string
--- @return boolean
function ThemeEngine.IsUserColorScheme(id)
    for _, d in ipairs(ThemeEngine.GetUserColorSchemes()) do
        if d.id == id then
            return true
        end
    end
    return false
end

--- Returns the fully-resolved color table for a scheme (the merged
--- [default, scheme] colors). Used to seed a new custom theme from the
--- currently-chosen palette. Unknown / nil ids resolve to the default palette.
--- @param schemeId string|nil
--- @return table map of token -> hex
function ThemeEngine.GetColorSchemeColors(schemeId)
    return _buildColorTable(schemeId)
end

--- Persist and (re-)register a user color scheme. If a def with the same id
--- already exists it is overwritten (edit in place, always allowed). Adding a
--- NEW scheme beyond ThemeEngine.maxUserColorSchemes is refused. Fires the
--- theme-changed event so any open UI reflects the new colors immediately.
--- @param def table { id, name, description?, colors }
--- @return boolean saved -- false if the per-user cap was hit (new schemes only)
function ThemeEngine.SaveUserColorScheme(def)
    local list = ThemeEngine.GetUserColorSchemes()
    local replaced = false
    for i, d in ipairs(list) do
        if d.id == def.id then
            list[i] = def
            replaced = true
            break
        end
    end
    if not replaced then
        if #list >= ThemeEngine.maxUserColorSchemes then
            -- At the cap; refuse to add a new scheme. Editing an existing one
            -- (the replaced branch above) is always allowed.
            return false
        end
        list[#list + 1] = def
    end
    _userSchemesSetting:Set(dmhub.ToJson(list))
    _upsertUserDef(def)
    _fireThemeChanged()
    return true
end

--- Remove a user color scheme. If it was the active scheme, the active
--- selection falls back to default. No-op for the default scheme.
--- @param id string
function ThemeEngine.DeleteUserColorScheme(id)
    if id == DEFAULT_SCHEME_ID then
        return
    end
    local list = ThemeEngine.GetUserColorSchemes()
    local out = {}
    for _, d in ipairs(list) do
        if d.id ~= id then
            out[#out + 1] = d
        end
    end
    _userSchemesSetting:Set(dmhub.ToJson(out))

    _colorSchemes[id] = nil
    _cache = {}

    if _activeSchemeId == id then
        ThemeEngine.SetActiveColorScheme(DEFAULT_SCHEME_ID)
    end
    _fireThemeChanged()
end

--- Register every persisted user color scheme. Called once at load (from
--- DefaultStyles.lua) before RestoreActiveSelection so a saved active scheme
--- pick resolves to the real scheme rather than falling back to default.
function ThemeEngine.LoadUserColorSchemes()
    for _, def in ipairs(ThemeEngine.GetUserColorSchemes()) do
        if type(def) == "table" and type(def.id) == "string" then
            _upsertUserDef(def)
        end
    end
end

-- =============================================================================
-- Public API -- Live preview scheme (used by the theme-creator UI)
-- =============================================================================

--- Register / update a transient color scheme used only for previewing
--- in-progress edits. Returns its reserved id so the caller can pass it to
--- GetStyles(themeId, schemeId). Clears the cache so the preview re-resolves.
--- @param colors table map of token -> hex
--- @return string previewSchemeId
function ThemeEngine.SetPreviewColorScheme(colors)
    _colorSchemes[PREVIEW_SCHEME_ID] = {
        id = PREVIEW_SCHEME_ID,
        name = "Preview",
        description = "Transient preview scheme.",
        colors = colors or {},
        gradients = {},
    }
    _cache = {}
    return PREVIEW_SCHEME_ID
end

--- Remove the transient preview scheme. Safe to call when none exists.
function ThemeEngine.ClearPreviewColorScheme()
    if _colorSchemes[PREVIEW_SCHEME_ID] ~= nil then
        _colorSchemes[PREVIEW_SCHEME_ID] = nil
        _cache = {}
    end
end

--- Register a callback to run whenever the active theme or active color scheme changes.
--- The callback receives no arguments. The returned entry has a `Deregister()` method
--- for explicit unsubscribe; the handler is also automatically removed when the caller's
--- mod unloads.
---
--- Safe to call before DMHub Utils has loaded (the cold-boot lobby, where the
--- engine loads only this module): the registration is queued and flushed into
--- EventUtils by the next OnThemeChanged call or theme-changed fire after Utils
--- loads. The returned handle's Deregister works in either state.
--- @param callingMod table The caller's mod object, from `dmhub.GetModLoading()`
--- @param callback fun()
--- @return table entry { Deregister, ... }
function ThemeEngine.OnThemeChanged(callingMod, callback)
    _flushPendingThemeListeners()

    local eu = rawget(_G, "EventUtils")
    if eu ~= nil then
        return eu.RegisterGlobalEventHandler(callingMod, THEME_CHANGED_EVENT, callback)
    end

    local p = { mod = callingMod, callback = callback, listener = nil, deregistered = false }
    _pendingThemeListeners[#_pendingThemeListeners + 1] = p
    return {
        Deregister = function()
            p.deregistered = true
            if p.listener ~= nil then
                p.listener:Deregister()
            end
        end,
    }
end

-- Ids beginning with "__" are reserved for internal / transient registrations
-- (e.g. the creator's live-preview scheme) and must never surface in UI pickers.
local function _isInternalId(id)
    return type(id) == "string" and string.sub(id, 1, 2) == "__"
end

--- List registered themes for UI pickers. Internal "__"-prefixed ids are skipped.
--- @return table[] themes Array of { id, name, description }
function ThemeEngine.ListThemes()
    local out = {}
    for _, theme in pairs(_themes) do
        if not _isInternalId(theme.id) then
            out[#out + 1] = {
                id = theme.id,
                name = theme.name,
                description = theme.description,
            }
        end
    end
    return out
end

--- List registered color schemes for UI pickers. Internal "__"-prefixed ids are skipped.
--- @return table[] schemes Array of { id, name, description }
function ThemeEngine.ListColorSchemes()
    local out = {}
    for _, scheme in pairs(_colorSchemes) do
        if not _isInternalId(scheme.id) then
            out[#out + 1] = {
                id = scheme.id,
                name = scheme.name,
                description = scheme.description,
            }
        end
    end
    return out
end

-- =============================================================================
-- Public API -- Resolution
-- =============================================================================

local _getStylesHits = 0
local _getStylesMisses = 0
local _getStylesReportEvery = 50

-- MergeStyles measurement (identity-only). Each call's customStyles table
-- address is the hash key. Tells us whether callers reuse styles tables
-- (cacheable cheaply by identity) vs. rebuild them every call (caching by
-- identity is moot; would need content hashing or caller refactoring).
local _mergeStylesCalls = 0
local _mergeStylesHashCounts = {}
local _mergeStylesHashIds = {}
local _mergeStylesNextId = 1

local function _reportGetStylesCache()
    if true then return end
    local total = _getStylesHits + _getStylesMisses
    if total > 0 and total % _getStylesReportEvery == 0 then
        print(string.format(
            "THC:: GETSTYLECACHE:: total=%d hits=%d misses=%d (hit rate %.1f%%)",
            total, _getStylesHits, _getStylesMisses,
            100 * _getStylesHits / total
        ))
    end
end

--- Get the resolved styles array for the current (or overridden) theme/scheme pair.
---
--- With no arguments, uses the active theme and active color scheme (falling back
--- to the theme's declared colorScheme when no user override is set).
---
--- Supplying themeIdOverride switches to deterministic rendering: the user's active
--- color scheme override is ignored, and the scheme comes from that theme's own
--- colorScheme field unless schemeIdOverride is also supplied. This is the
--- intended path for "Reset" buttons that must always render readably.
---
--- Results are memoized per resolved (theme, scheme) pair. Registrations are
--- immutable (duplicate ids are rejected), so cached entries remain valid across
--- SetActive* calls.
--- @param themeIdOverride? string|nil
--- @param schemeIdOverride? string|nil
--- @return table[] styles
function ThemeEngine.GetStyles(themeIdOverride, schemeIdOverride)
    local themeId, schemeId = _resolveEffectivePair(themeIdOverride, schemeIdOverride)

    local key = _cacheKey(themeId, schemeId)
    local cached = _cache[key]
    if cached then
        _getStylesHits = _getStylesHits + 1
        _reportGetStylesCache()
        return cached
    end

    _getStylesMisses = _getStylesMisses + 1
    _reportGetStylesCache()

    local chain = _buildChain(themeId)

    local rawStyles = {}
    for _, theme in ipairs(chain) do
        if theme.styles then
            for _, rule in ipairs(theme.styles) do
                rawStyles[#rawStyles + 1] = rule
            end
        end
    end

    local tables = {
        colors = _buildColorTable(schemeId),
        gradients = _buildGradientTable(schemeId),
        fonts = _buildFontsTable(chain),
    }

    local resolved = _buildResolvedStyles(rawStyles, tables)
    _cache[key] = resolved
    return resolved
end

--- Merge a caller-supplied styles array on top of the active theme's resolved styles.
---
--- The custom rules are run through the same @name resolver the engine uses for
--- registered theme rules, so they can reference @fg / @success / @accentHover /
--- @surfaceRadial / etc. and follow scheme switches when the caller re-invokes
--- MergeStyles after an OnThemeChanged event.
---
--- The base (theme) styles come first, custom rules are appended last, so on
--- equal-specificity selector matches the custom rule wins. For finer control,
--- callers can still set `priority = N` on individual custom rules.
---
--- The base styles array is the same memoized array returned by GetStyles().
--- The custom resolution is recomputed each call (uncached) -- typical custom
--- arrays are small and the @name resolver is cheap.
---
--- Always uses the active theme/scheme pair; no overrides. Callers needing
--- override semantics can compose manually via GetStyles(theme, scheme) plus
--- their own resolution loop, but no caller has needed that yet.
--- @param customStyles table[]|nil Array of rule tables (selectors + properties).
--- @return table[] styles
function ThemeEngine.MergeStyles(customStyles)
    local base = ThemeEngine.GetStyles()
    if customStyles == nil or #customStyles == 0 then
        return base
    end

    _mergeStylesCalls = _mergeStylesCalls + 1
    -- Identity key. Using the table reference directly avoids a tostring()
    -- call that would otherwise hit any __tostring metamethod the engine
    -- installs on style tables (which serializes the whole structure).
    _mergeStylesHashCounts[customStyles] = (_mergeStylesHashCounts[customStyles] or 0) + 1
    if _mergeStylesHashIds[customStyles] == nil then
        _mergeStylesHashIds[customStyles] = _mergeStylesNextId
        _mergeStylesNextId = _mergeStylesNextId + 1
    end

    local themeId, schemeId = _resolveEffectivePair(nil, nil)
    local chain = _buildChain(themeId)
    local tables = {
        colors = _buildColorTable(schemeId),
        gradients = _buildGradientTable(schemeId),
        fonts = _buildFontsTable(chain),
    }

    local resolvedCustom = _buildResolvedStyles(customStyles, tables)

    local merged = {}
    for _, r in ipairs(base) do
        merged[#merged + 1] = r
    end
    for _, r in ipairs(resolvedCustom) do
        merged[#merged + 1] = r
    end
    return merged
end

--- Resolve `@`-token references in a caller-supplied styles array against the
--- active scheme, without bundling the base theme. Use this when a panel just
--- needs its own local rules to follow the active scheme, and the panel sits
--- downstream of an ancestor that already owns the full theme cascade via
--- `ThemeEngine.MergeStyles`.
---
--- Difference vs. MergeStyles:
---   * MergeStyles   -> base theme + resolved custom (for cascade roots)
---   * MergeTokens -> resolved custom only (for downstream extras)
---
--- Callers that need scheme switches to recolor live should subscribe to
--- OnThemeChanged and reassign their panel.styles after re-resolving.
--- @param customStyles table[]|nil Array of rule tables (selectors + properties).
--- @return table[]|nil resolved
function ThemeEngine.MergeTokens(customStyles)
    if customStyles == nil or #customStyles == 0 then
        return customStyles
    end

    local themeId, schemeId = _resolveEffectivePair(nil, nil)
    local chain = _buildChain(themeId)
    local tables = {
        colors = _buildColorTable(schemeId),
        gradients = _buildGradientTable(schemeId),
        fonts = _buildFontsTable(chain),
    }

    return _buildResolvedStyles(customStyles, tables)
end

--- Answer "what value would the theme cascade give property P to an element
--- with these classes?" without there being such an element.
---
--- The cascade is the normal way to get a themed value, so reach for this only
--- when a value has to be known in Lua rather than merely applied: chrome that
--- paints an opaque child OVER a themed surface has to match that surface's
--- number by hand. The icon-rail panel window is the case that motivated it --
--- the window root gets the theme's `framedPanel` cornerRadius from the cascade,
--- but its own opaque header strip sits square across the rounded top corners,
--- so the header rule has to state the same radius.
---
--- Matching mirrors the engine's (`SheetPanel.StyleSelected`): a rule applies
--- when every one of its selectors is satisfied, `~name` meaning the class is
--- absent. `parent:` selectors are unanswerable without a real element, so any
--- rule using one is skipped. The winner is the highest
--- `priority*1000 + specificity` (id selectors count 10, class selectors 1),
--- ties going to the rule declared later -- the engine's sortOrder exactly.
--- @param classes string[] Classes the hypothetical element carries.
--- @param property string Style property to read, e.g. "cornerRadius".
--- @param default? any Returned when no rule matches. Defaults to nil.
--- @return any value
function ThemeEngine.ResolveStyleProperty(classes, property, default)
    local present = {}
    for _, c in ipairs(classes or {}) do
        present[c] = true
    end

    local bestValue = default
    local bestOrder = nil

    for _, rule in ipairs(ThemeEngine.GetStyles()) do
        local value = rule[property]
        if value ~= nil then
            local specificity = 0
            local matches = true

            for _, selector in ipairs(rule.selectors or {}) do
                local invert = false
                local name = selector

                if string.sub(name, 1, 1) == "~" then
                    invert = true
                    name = string.sub(name, 2)
                end

                if string.sub(name, 1, 1) == "#" then
                    --an id selector: our hypothetical element has no id, so it
                    --can only be satisfied by inversion.
                    specificity = specificity + 10
                    if not invert then
                        matches = false
                        break
                    end
                elseif string.find(name, "parent:", 1, true) == 1 then
                    matches = false
                    break
                else
                    specificity = specificity + 1
                    if (present[name] == true) == invert then
                        matches = false
                        break
                    end
                end
            end

            if matches then
                local order = (rule.priority or 0) * 1000 + specificity
                --`>=` so a later rule wins an exact tie, as it does in the engine.
                if bestOrder == nil or order >= bestOrder then
                    bestOrder = order
                    bestValue = value
                end
            end
        end
    end

    return bestValue
end

--- Resolve `@tokenName` color references embedded in an arbitrary string
--- against the active scheme. Useful for TextMeshPro markup like
--- `"<color=@danger>warning</color>"` where the property-level resolver
--- doesn't reach (it only walks rule tables, not strings inside text).
---
--- Each `@<name>` is replaced with the active scheme's resolved hex for that
--- color token. Unknown tokens log a warning and substitute UNRESOLVED_COLOR.
--- Non-string inputs pass through unchanged.
---
--- Only color tokens are substituted. Fonts and gradients aren't useful in
--- text markup, so they're not handled here.
--- @param text string|any The string to resolve. Non-strings return unchanged.
--- @return string|any resolved
function ThemeEngine.ResolveTokens(text)
    if type(text) ~= "string" then
        return text
    end
    local _, schemeId = _resolveEffectivePair(nil, nil)
    local colors = _buildColorTable(schemeId)
    return (string.gsub(text, "@([%a][%w]*)", function(name)
        local v = colors[name]
        if v == nil then
            _logUnresolved("color", name)
            return UNRESOLVED_COLOR
        end
        return v
    end))
end

-- =============================================================================
-- Theme safety enforcement
-- Hidden preference (no name / description / editor, so it does not show up in
-- the settings dialog). Toggle from chat with `/safetheme true|false`; the
-- macro with no argument prints the current value. Default: true.
-- =============================================================================

local _enforceSafetySetting = setting{
    id = "themeengine.enforcesafety",
    storage = "preference",
    default = false,
}

--- Returns true if theme safety enforcement is currently on.
--- @return boolean
function ThemeEngine.ForceSafety()
    return _enforceSafetySetting:Get()
end

-- Commands.RegisterMacro does not exist yet when this file loads (Utils
-- defines it later), so register the chat command after a short delay.
dmhub.Schedule(0.1, function()
    if mod.unloaded then return end
    if not devmode() then return end
    local commands = rawget(_G, "Commands")
    if commands == nil or commands.RegisterMacro == nil then return end
    commands.RegisterMacro{
        name = "themecache",
        summary = "dump GetStyles + MergeStyles measurement counters",
        doc = "Usage: /themecache\nPrints GetStyles cache hit/miss counters plus MergeStyles call distribution by customStyles table identity (top 5). Devmode only.",
        command = function(str)
            local total = _getStylesHits + _getStylesMisses
            local rate = total > 0 and (100 * _getStylesHits / total) or 0
            print(string.format(
                "THC:: GETSTYLECACHE:: total=%d hits=%d misses=%d (hit rate %.1f%%)",
                total, _getStylesHits, _getStylesMisses, rate
            ))

            local uniqueHashes = 0
            local entries = {}
            for hash, count in pairs(_mergeStylesHashCounts) do
                uniqueHashes = uniqueHashes + 1
                entries[#entries + 1] = { hash = hash, count = count }
            end
            table.sort(entries, function(a, b) return a.count > b.count end)

            local repeatRate = _mergeStylesCalls > 0
                and (100 * (_mergeStylesCalls - uniqueHashes) / _mergeStylesCalls) or 0
            print(string.format(
                "THC:: MERGESTYLES:: total=%d unique=%d (repeat rate %.1f%%)",
                _mergeStylesCalls, uniqueHashes, repeatRate
            ))

            local topN = math.min(5, #entries)
            for i = 1, topN do
                print(string.format(
                    "THC:: MERGESTYLES:: top %d count=%d id=#%d",
                    i, entries[i].count, _mergeStylesHashIds[entries[i].hash] or -1
                ))
            end
        end,
    }
end)

-- Commands.RegisterMacro does not exist yet when this file loads (Utils
-- defines it later), so register the chat command after a short delay.
dmhub.Schedule(0.1, function()
    if mod.unloaded then return end
    local commands = rawget(_G, "Commands")
    if commands == nil or commands.RegisterMacro == nil then return end
    commands.RegisterMacro{
        name = "safetheme",
        summary = "toggle theme safety enforcement",
        doc = "Usage: /safetheme [true|false]\nWith no argument, prints the current value. With true or false, sets it.",
        command = function(str)
            -- SendTitledChatMessage is not defined in the legacy environment;
            -- fall back to print.
            local sendChat = rawget(_G, "SendTitledChatMessage") or function(message, title, color, userid)
                print(tostring(title) .. ":: " .. tostring(message))
            end
            local arg = (str or ""):match("^%s*(%S+)%s*$")
            if arg == nil then
                sendChat(tostring(_enforceSafetySetting:Get()), "safetheme", "#ccccff", dmhub.userid)
                return
            end
            local lower = arg:lower()
            if lower == "true" then
                _enforceSafetySetting:Set(true)
                sendChat("true", "safetheme", "#ccccff", dmhub.userid)
            elseif lower == "false" then
                _enforceSafetySetting:Set(false)
                sendChat("false", "safetheme", "#ccccff", dmhub.userid)
            else
                sendChat(string.format("unknown value '%s' (expected true or false). Current: %s", arg, tostring(_enforceSafetySetting:Get())), "safetheme", "#cc4444", dmhub.userid)
            end
        end,
    }
end)

-- =============================================================================
-- Legacy 5e DMHub stylesheet (original content of this file) follows.
-- =============================================================================


--This file controls much of the default styling that DMHub uses for panels.

local textColor = "srgb:#C09571"
local textPendingColor = "#999999"
local backgroundColor = "#161616"

@if MCDM
textColor = "white"
@end

local dialogGradient = gui.Gradient{
	point_a = {x = 0, y = 0},
	point_b = {x = 1, y = 1},
	stops = {
		{
			position = 0,
@if MCDM
			color = "#000000",
@else
			color = "#060606",
@end
		},
		{
			position = 1,
@if MCDM
			color = "#060606",
@else
			color = "#1c1c1c",
@end
		},
	},
}

Styles = {
	textColor = textColor,
	backgroundColor = backgroundColor,
	bullet = "\u{2022}",
	emdash = "\u{2014}",
	multiplySign = "\u{00D7}",

	dialogGradient = dialogGradient,

    healthGradient = gui.Gradient{
        point_a = {x = 0, y = 0},
        point_b = {x = 1, y = 0},
        stops = {
            {
                position = 0,
                color = "#004d52",
            },
            {
                position = 1,
                color = "#00b8c4",
            },
        },
    },

    bloodiedGradient = gui.Gradient{
        point_a = {x = 0, y = 0},
        point_b = {x = 1, y = 0},
        stops = {
            {
                position = 0,
                color = "#a15102",
            },
            {
                position = 1,
                color = "#fa9a00",
            },
        },
    },


    damagedGradient = gui.Gradient{
        point_a = {x = 0, y = 0},
        point_b = {x = 1, y = 0},
        stops = {
            {
                position = 0,
                color = "#440000",
            },
            {
                position = 1,
                color = "#bb0000",
            },
        },
    },

	conditionGradient = gui.Gradient{
        point_a = {x = 0, y = 0},
        point_b = {x = 1, y = 0},
        stops = {
            {
                position = 0,
                color = "#000000",
            },
            {
                position = 1,
                color = textColor,
            },
        },
	},


	Default = {
		gui.Style{
			scrollHandleColor = textColor,
		},

		--make it so the hidden class hides things.
		gui.Style({
			selectors = { 'hidden' },
			hidden = 1,
		}),

		gui.Style({
			selectors = { 'collapsed' },
			collapsed = 1,
		}),

		gui.Style{
			selectors = {"hideForPlayers", "player"},
			hidden = 1,
		},

		gui.Style{
			selectors = {"collapsedForPlayers", "player"},
			collapsed = 1,
		},

		gui.Style({
			priority = 100,
			selectors = { 'collapsed-anim' },
			collapsed = 1,
			transitionTime = 0.2,
			uiscale = { x = 1, y = 0.001 },
		}),

		--make sure dockable panels are interactable.
		gui.Style{
			selectors = {"dockablePanel"},
			bgimage = "panels/square.png",
		},

		--dropdowns.

		gui.Style{
			selectors = {"dropdown"},
			width = 200,
			height = 28,
			flow = "none",
			borderColor = textColor,
			bgcolor = "black",
			border = {x1 = 2, x2 = 2, y1 = 2, y2 = 2},
		},
		gui.Style{
			selectors = {"dropdown", "expandedBottom"},
			border = {x1 = 2, x2 = 2, y1 = 0, y2 = 2},
		},
		gui.Style{
			selectors = {"dropdown", "expandedTop"},
			border = {x1 = 2, x2 = 2, y1 = 2, y2 = 0},
		},
		gui.Style{
			selectors = {"dropdown", "hover", "~search"},
			bgcolor = textColor,
		},
		gui.Style{
			selectors = {"label", "dropdownLabel"},
			fontSize = 18,
			minFontSize = 10,
			color = textColor,
			halign = "left",
			valign = "center",
			width = "100%-40",
			height = "100%",
			hmargin = 6,
		},
		gui.Style{
			selectors = {"label", "dropdownLabel", "parent:hover"},
			color = "black",
		},
		gui.Style{
			selectors = {"dropdownTriangle"},
			height = "30%",
			width = "160% height",
			bgcolor = textColor,
			halign = "right",
			valign = "center",
			hmargin = 6,
	 
		},
		gui.Style{
			selectors = {"dropdownTriangle", "parent:hover"},
			bgcolor = "black",
		},

		--sliders
		gui.Style{
			selectors = {"sliderHandleBorder"},
			borderWidth = 2,
			borderColor = Styles.textColor,
			bgcolor = "black",
			bgimage = "panels/square.png",
			width = "60%",
			height = "60%",
			halign = "center",
			valign = "center",
		},

		gui.Style{
			selectors = {"sliderHandleInner"},
			bgimage = "panels/square.png",
			bgcolor = Styles.textColor,
			width = "30%",
			height = "30%",
			halign = "center",
			valign = "center",
		},

		--input.

		gui.Style{
			id = 'input-main',
			selectors = {'input'},
			fontSize = 12,
			height = 16,
			width = 240,
			pad = 4,
			hpad = 10,
			borderColor = "#999999",
			borderWidth = 2,
			selectedColor = '#444444',
			bgcolor = 'black',
		},

        gui.Style{
            selectors = {'input', 'focus'},
			borderColor = "white",
        },

        gui.Style{
            selectors = {"inputFaded"},
			borderColor = "black",
			borderWidth = 7,
			borderFade = true,
			bgcolor = 'black',
        },

		gui.Style{
			selectors = {'searchInput'},
			hpad = 6,
			fontSize = 16,
			bold = true,
			borderWidth = 0,
			borderFade = false,

@if MCDM
            color = "white",
            borderWidth = 1,
            borderColor = "white",

@else
			bgcolor = "srgb:#C09571",
			color = "black",
@end
		},

		--labels.
		gui.Style{
			selectors = {"label"},
			selectedColor = '#999944',
			color = textColor,
			highlightedColor = '#9999ffff',
		},

        gui.Style{
            selectors = {"label", "pending"},
            color = textPendingColor,
        },

		gui.Style{
			selectors = {'label', 'dialogTitle'},
			fontSize = 24,
			halign = "center",
			width = "auto",
			height = "auto",
			valign = "top",
			tmargin = 12,
			bmargin = 0,
		},

		gui.Style({
			selectors = {'label','link'},
			priority = 5,
			color = '#9999ffff',
		}),

		gui.Style({
			selectors = {'label','link','hover'},
			priority = 5,
			color = '#ff99ffff',
		}),

		gui.Style({
			selectors = {'label','link','press'},
			priority = 5,
			color = '#99ffffff',
		}),

		--highlighting good/bad ongoingEffects.
		gui.Style({
			selectors = {'highlight_good'},
			priority = 5,
			transitionTime = 1,
			bgcolor = 'green',
		}),

		gui.Style({
			selectors = {'highlight_bad'},
			priority = 5,
			transitionTime = 1,
			bgcolor = 'red',
		}),

		--clickable icons.
		gui.Style{
			selectors = {"clickableIcon"},
			bgcolor = textColor,
			width = 16,
			height = 16,
		},

		gui.Style{
			selectors = {"clickableIcon", "hover"},
			brightness = 1.5,
		},

		gui.Style{
			selectors = {"dice", "parent:clickableIcon", "parent:hover"},
			brightness = 1.5,
		},

		--buttons
		gui.Style({
			selectors = {'label', 'button'},
			textAlignment = 'center',
			fontSize = 16,
			fontWeight = "bold",
			color = textColor,
			borderColor = textColor,
			borderWidth = 2,
			width = "120% auto",
			height = "120% auto",

			hmargin = 8,
			vmargin = 8,

			bgcolor = "#222222",
			bgimage = "panels/square.png",
		}),

		gui.Style{
			selectors = {'label', 'button', 'tiny'},
			fontSize = 12,
			fontWeight = "thin",
			borderWidth = 1,
			hmargin = 2,
			vmargin = 2,
		},

		gui.Style({
			selectors = {'label', 'button', 'hover'},
			transitionTime = 0.1,
			color = "#222222",
			bgcolor = textColor,
			textAlignment = "center",
			fontWeight = "bold",
		}),

		gui.Style({
			selectors = {'label', 'button', 'press'},
			transitionTime = 0.1,
			brightness = 0.7,
		}),

		gui.Style({
			selectors = {'label', 'button', 'selected'},
			color = "#222222",
			bgcolor = textColor,
			textAlignment = "center",
			fontWeight = "bold",
		}),


		gui.Style{
			selectors = {'label', "button", "prettyButton"},
			fontSize = 24,
			hmargin = 16,
			vmargin = 16,
			width = "130% auto",
			height = "130% auto",
			borderWidth = 3,
		},

		gui.Style{
			selectors = {"label", "button", "focus"},
			borderColor = "white",
		},

		--rollable styles.
		gui.Style({
			selectors = {'rollable'},
			color = '#ffaaaa',
			textAlignment = 'center',

			borderWidth = 0,
			priority = 10,
		}),
		gui.Style({
			selectors = {'rollable', 'hover'},
			bgcolor = 'black',
			borderWidth = 2,
			color = '#ffcccc',
			borderColor = '#ffcccc',
			priority = 10,
		}),
		gui.Style({
			selectors = {'rollable', 'hover', 'press'},
			borderWidth = 4,
			color = '#ffdddd',
			borderColor = '#ffdddd',
			priority = 10,
		}),

		--dialog
		gui.Style{
			priority = 5,
			classes = {"dialog-panel"},
			bgimage = 'panels/hud/button_09_frame_custom.png',
			bgcolor = 'white',
			bgslice = 20,
			border = 10,
		},
		gui.Style{
			priority = 5,
			classes = {"dialog-panel", "fadein"},
			opacity = 0,
			uiscale = {x = 0.01, y = 0.01},
			transitionTime = 0.2,
		},


		gui.Style({
			priority = 5,
			selectors = {'dialog-panel'},
			bgimage = 'panels/InventorySlot_Background.png',
			bgcolor = 'white',
		}),

		--border of a dialog.
		gui.Style{
			priority = 20,
			selectors = {'dialog-border'},
			hidden = 1,
		},

		--a close button
		gui.Style{
			priority = 5,
			selectors = {'close-button'},
			width = 24,
			height = 24,
			margin = 6,
			halign = 'right',
			valign = 'top',
			bgcolor = Styles.textColor,
		},

		gui.Style{
			priority = 5,
			selectors = {'close-button', 'hover'},
			brightness = 2,
		},

		gui.Style{
			priority = 5,
			selectors = {'close-button', 'press'},
			brightness = 0.5,
		},

		--a delete item button
		gui.Style {
			priority = 5,
			selectors = {'delete-item-button'},
			width = 24,
			height = 24,
		},

		--generic icons that act as buttons.
		gui.Style {
			selectors = {'iconButton'},
			bgcolor = textColor,
			width = 24,
			height = 24,
		},

		gui.Style {
			selectors = {'iconButton', 'hover'},
			brightness = 2,
		},

		gui.Style{
			selectors = {"iconButton", "settingsButton"},
			blend = "add",
		},



		--add button
		gui.Style{
			priority = 5,
			selectors = {'plus-button'},
			width = 24,
			height = 24,
			bgcolor = "white",
		},

		gui.Style{
			priority = 5,
			selectors = {'plus-button', 'hover'},
			brightness = 1.4,
		},

		gui.Style{
			priority = 5,
			selectors = {'plus-button', 'hover'},
			brightness = 0.8,
		},

		gui.Style{
			selectors = {'modal-dialog'},
			priority = 10,
			bgimage = 'panels/square.png',
			bgcolor = '#888888ff',
			borderWidth = 2,
			borderColor = 'black',
			cornerRadius = 8,
		},

		gui.Style{
			selectors = {'modal-button-panel'},
			priority = 10,
			width = '100%-50',
			height = 100,
			valign = 'bottom',
			halign = 'center',
			flow = 'horizontal',
		},

		gui.Style{
			selectors = {'pretty-button'},
			priority = 10,
			width = 140,
			height = 60,
		},
		gui.Style{
			selectors = {'pretty-button-label'},
			priority = 2,
			fontSize = 20,
			bold = true,
			textAlignment = 'center',
			width = 'auto',
			height = 'auto',
		},

		--tokens
		gui.Style{
			classes = {'token-image'},
			halign = 'center',
			valign = 'center',
			width = 60,
			height = 60,
		},

		gui.Style{
			classes = {'token-image-portrait'},
			bgcolor = 'white',
			width = "100%",
			height = "100%",
		},
		gui.Style{
			classes = {'token-image-frame'},
			width = "100%",
			height = "100%",
		},

		--checkboxes

		gui.Style{
			classes = {'check-mark'},
			bgimage = 'panels/square.png',
			bgcolor = textColor,
			halign = 'center',
			valign = 'center',
			width = '50%',
			height = '50%',
		},

		gui.Style{
			classes = {'check-background'},
			bgimage = 'panels/square.png',
			bgcolor = backgroundColor,
			halign = 'left',
			valign = 'center',
			height = '70%',
			width = '100% height',
			rmargin = 6,
			borderColor = textColor,
			borderWidth = 2,
		},

		gui.Style{
			classes = {'checkbox-label'},
			halign = 'left',
			valign = 'center',
			textAlignment = 'left',
			borderWidth = 0,
			fontSize = 18,
			width = 'auto',
			height = 'auto',
		},
		gui.Style{
			classes = {'checkbox-label', "rightAlign"},
			rmargin = 8,
		},

		gui.Style{
			classes = {'checkbox'},
			bgimage = 'panels/square.png',
			flow = 'horizontal',
			bgcolor = 'clear',
			height = 30,
			width = 'auto',
			hpad = 4,
		},

		gui.Style{
			classes = {'checkbox', 'hover', '~disabled'},
			bgcolor = '#ffffff44',
			borderWidth = 1,
			borderColor = 'white',
		},

		gui.Style{
			classes = {'check-background', 'disabled'},
			saturation = 0,
		},

		gui.Style{
			classes = {'check-mark', 'disabled'},
			saturation = 0,
		},

		gui.Style{
			classes = {'checkbox-label', 'disabled'},
			color = "#777777ff",
		},

		gui.Style{
			classes = {'hidden-unless-parent-hover'},
			hidden = 1,
		},

		gui.Style{
			classes = {'hidden-unless-parent-hover', 'parent:hover'},
			hidden = 0,
		},

		gui.Style{
			classes = {"hudIconButton"},
			width = 58,
			height = 58,
			--bgimage = "panels/hud/button_09_frame_custom.png",
			bgimage = "panels/square.png",
			bgcolor = backgroundColor,
			borderColor = textColor,
			borderWidth = 1,
		},

		gui.Style{
			classes = {"hudIconButton", "hover"},
			brightness = 2.5,
			transitionTime = 0.1,
		},

		gui.Style{
			classes = {"hudIconButton", "press"},
			brightness = 0.8,
			transitionTime = 0.1,
		},

		gui.Style{
			classes = {"hudIconButton", "disabled"},
			brightness = 0.5,
			saturation = 0.2,
		},
		
		gui.Style{
			classes = {"hudIconButton", "selected"},
			brightness = 3.0,
			saturation = 1.4,
			--y = -5,
		},

		gui.Style{
			classes = {"hudIconButton", "selected", "tab"},
			brightness = 1,
			saturation = 1,
			bgcolor = "#0d0d0d",
			border = {x1 = 1, x2 = 1, y1 = 0, y2 = 1},
		},

		gui.Style{
			classes = {"hudIconButtonIcon"},
			width = "75%",
			height = "75%",
			halign = "center",
			valign = "center",
			bgcolor = textColor,
		},

		gui.Style{
			classes = {"hudIconButtonIcon", "parent:hover"},
			brightness = 1.5,
			transitionTime = 0.1,
			scale = 1.15,
		},

		gui.Style{
			classes = {"hudIconButtonIcon", "parent:press"},
			brightness = 0.8,
			transitionTime = 0.1,
		},

		gui.Style{
			classes = {"hudIconButtonIcon", "parent:deselected"},
			saturation = 0.0,
			brightness = 0.8,
		},

		gui.Style{
			classes = {"hudIconButtonIcon", "parent:disabled"},
			saturation = 0.2,
			brightness = 0.5,
			scale = 1,
		},

		gui.Style{
			classes = {"hudIconButtonIcon", "parent:selected"},
			saturation = 1.5,
			brightness = 1.5,
		},
	},

	ItemTooltip = {
		gui.Style{
			selectors = {"label"},
			color = "white",
			fontSize = 16,
			width = "auto",
			height = "auto",
			halign = "left",
		},

		gui.Style{
			selectors = {"label", "title"},
			bold = true,
			width = "100%",
			fontSize = 24,
		},
		gui.Style{
			selectors = {"icon"},
			halign = "right",
			valign = "top",
			width = 32,
			height = 32,
			bgcolor = "white",
		},

		gui.Style{
			selectors = {"hasTooltip"},
			color = "#aaaaff",
		},
		gui.Style{
			selectors = {"hasTooltip", "hover"},
			color = "#ffaaff",
		},
	},

	Panel = {
		gui.Style{
			classes = {"framedPanel"},
			bgimage = "panels/square.png",
			bgcolor = 'white',
			cornerRadius = 4,
			gradient = dialogGradient,
			borderWidth = 2.2,
			borderColor = textColor,
		},
		gui.Style{
			classes = {"framedPanel", "fadein"},
			opacity = 0,
			uiscale = {x = 0.01, y = 0.01},
			transitionTime = 0.2,
		},
	},

	Table = {
		gui.Style{
			selectors = {"label"},
			pad = 6,
			fontSize = 16,
			width = "auto",
			height = "auto",
			color = "white",
		},
		gui.Style{
			selectors = {"row"},
			width = "auto",
			height = "auto",
			bgimage = "panels/square.png",
		},
		gui.Style{
			selectors = {"row", "oddRow"},
			bgcolor = "#222222ff",
		},
		gui.Style{
			selectors = {"row", "evenRow"},
			bgcolor = "#444444ff",
		},
	},

	ContextMenu = {
		gui.Style({
			selectors = {'context-menu-label'},
			fontSize = 20,
			color = '#ffffff',
		}),
		gui.Style({
			selectors = {'context-menu-label', 'disabled'},
			fontSize = 20,
			color = '#777777',
		}),
		gui.Style({
			selectors = {'context-menu-item'},
			fontSize = 20,
			color = '#ffffff',
			height = "auto",
			width = "100%",
			bgcolor = '#994444',
			color = '#ffffff',
			borderColor = '#000000',
			borderWidth = 1,
		}),
		gui.Style({
			selectors = {'context-menu-item','hover'},
			borderColor = '#ffffff',
			borderWidth = 1,
			transitionTime = 0.2,
		}),
		gui.Style({
			selectors = {'context-menu-item','press'},
			brightness = 1.2,
			transitionTime = 0.2,
		}),
	},

	InventorySlot = {
		gui.Style{
			classes = 'inventory-slot-highlight',
			bgimage = 'panels/InventorySlot_Focus.png',
			bgcolor = 'white',
			width = 90,
			height = 90,
			halign = 'center',
			valign = 'center',
			opacity = 0,
		},
		gui.Style{
			classes = {'inventory-slot-highlight', 'hover'},
			opacity = 1,
		},
		gui.Style{
			classes = {'inventory-slot-highlight', 'press'},
			bgcolor = 'red',
		},

		gui.Style{
			classes = 'inventory-slot-background',
			bgimage = 'panels/InventorySlot_Background.png',
			bgcolor = 'white',
			width = 72,
			height = 72,
			margin = 0,
			pad = 0,
		},

		gui.Style{
			classes = 'inventory-slot-icon',
			bgcolor = 'white',
			halign = 'center',
			valign = 'center',
			width = "100%",
			height = "100%",
			hmargin = 0,
		},
	},

	AdvantageBar = {

		gui.Style{
			selectors = {'advantage-bar'},
			halign = 'center',
			height = 30,
			width = 340,
			flow = 'horizontal',
		},

		gui.Style{
			selectors = {'advantage-element-lock-icon'},
			hidden = 1,
		},

		gui.Style{
			selectors = {'advantage-element-lock-icon', 'parent:locked'},
			hidden = 0,
			margin = 2,
			bgcolor = 'white',
			width = 16,
			height = 16,
			halign = 'right',
			valign = 'center',
		},

		gui.Style{
			selectors = {'advantage-element'},
			bgimage = "panels/square.png",
			bgcolor = '#ffffff00',
			color = 'white',
			width = 140,
			height = 22,
			fontSize = 14,
			textAlignment = 'center',
			halign = 'center',
		},

		gui.Style{
			selectors = {'advantage-element', 'hover', '~selected'},
			bgcolor = '#ffffff66',
		},

@if MCDM
		gui.Style{
			selectors = {'advantage-element', 'selected', '~press'},
			borderWidth = 2,
			borderColor = "white",
			bgcolor = "white",
			gradient = gui.Gradient{
				point_a = {x = 0, y = 0},
				point_b = {x = 1, y = 1},
				stops = {
					{
						position = 0,
						color = '#111111',
					},
					{
						position = 1,
						color = '#222222',
					},
				}

			},
		},
@else
		gui.Style{
			selectors = {'advantage-element', 'selected'},
			bgcolor = '#ff9999aa',
		},
@end

		gui.Style{
			selectors = {'advantage-element', 'locked'},
			bgcolor = '#ff7777ff',
		},

@if MCDM
		gui.Style{
			selectors = {'advantage-element', 'press'},
			bgcolor = "white",
			color = "black",
		},
@else
		gui.Style{
			selectors = {'advantage-element', 'press'},
			bgcolor = '#ff9999cc',
		},
@end

		gui.Style{
			selectors = {'advantage-rules-panel'},
			bgcolor = '#000000aa',
			width = 'auto',
			height = 'auto',
			pad = 8,
			flow = 'vertical',
		},
		gui.Style{
			selectors = {'advantage-rules-label'},
			color = 'white',
			width = 'auto',
			height = 'auto',
			fontSize = 14,
		},
		gui.Style{
			selectors = {'advantage'},
			color = '#aaffaa',
		},
		gui.Style{
			selectors = {'disadvantage'},
			color = '#ffaaaa',
		},

	},

	Form = {
		gui.Style{
			classes = "formPanel",
			flow = "horizontal",
			width = "100%",
			height = "auto",
			valign = "top",
			vmargin = 4,
		},
		gui.Style{
			classes = "formLabel",
			fontSize = 16,
			color = "white",
			width = "auto",
			height = "auto",
			minWidth = 140,
			halign = "right",
			valign = "center",
			hmargin = 8,
		},
		gui.Style{
			classes = "formInput",
			fontSize = 16,
			width = 180,
			height = 26,
			color = "white",
			halign = "right",
			valign = "center",
			textAlignment = "left",
		},
		gui.Style{
			classes = {"formInput", "multiline"},
			textAlignment = "topleft",
		},
		gui.Style{
			classes = "formDropdown",
			halign = 'right',
			vmargin = 4,
			width = 240,
			height = 30,
		},
		gui.Style{
			classes = "formValue",
			halign = 'right',
			vmargin = 4,
			width = 180,
			height = 30,
			fontSize = 14,
		},
	},

	Triangle = {
		gui.Style{
			selectors = {"triangle"},
			bgimage = "panels/triangle.png",
			bgcolor = textColor,
			width = 12,
			height = 12,
			hmargin = 4,
			valign = "center",
			halign = "center",
		},
		gui.Style{
			selectors = {"triangle", "hover"},
			brightness = 1.5,
		},
	},

	FolderLibrary = {
		{
			width = '100%',
			height = 500,
			valign = 'center',
			halign = 'right',
			flow = 'vertical',
		},

		gui.Style{
			selectors = {"folderContainer"},
			flow = "vertical",
			width = "100%",
			height = "auto",
			valign = "top",
		},

		gui.Style{
			selectors = {"folderHeader"},
			width = "100%",
			flow = "horizontal",
			height = 24,
			bgimage = "panels/square.png",
			bgcolor = textColor,
		},

		gui.Style{
			selectors = {"folderHeader", "hover"},
			brightness = 1.5,
		},

		gui.Style{
			selectors = {"triangle"},
			bgimage = "panels/triangle.png",
			bgcolor = "black",
			width = 16,
			height = 12,
			hmargin = 4,
			valign = "center",
			halign = "left",
		},

		gui.Style{
			selectors = {"triangle", "parent:expanded"},
			scale = {x = 1, y = -1},
			transitionTime = 0.1,
		},

		gui.Style{
			selectors = {"folderLabel"},
			color = "black",
			fontSize = 18,
			width = "80%",
			height = "100%",
			halign = "left",
			textAlignment = "left",

		},

		gui.Style{
			selectors = {"folderHeader", "parent:drag-target"},
			brightness = 1.5,
		},
		gui.Style{
			selectors = {"folderHeader", "parent:drag-target-hover"},
			brightness = 3,
		},
	},

	ImplementationIcon = {
		{
			selectors = {"spellImplementationIcon"},
			width = 16,
			height = 16,
			hmargin = 4,
		},
		{
			selectors = {"spellImplementationIcon", "partial"},
			bgimage = "icons/icon_common/icon_common_29.png",
			bgcolor = "yellow",
		},
		{
			selectors = {"spellImplementationIcon", "full"},
			bgimage = "icons/icon_common/icon_common_29.png",
			bgcolor = "#77ff77",
		},
		{
			selectors = {"spellImplementationIcon", "wontimplement"},
			bgimage = "icons/icon_common/icon_common_29.png",
			bgcolor = "#ff77ff",
		},
	},

	triangleStyles = {
		gui.Style{
			classes = {'triangle'},
			rotate = 90,
			transitionTime = 0.2,
			bgimage = "panels/triangle.png",
			bgcolor = "white",
			halign = "left",
			hmargin = 4,
			width = "100% height",
			valign = "center",
		},
		gui.Style{
			classes = {'triangle', 'expanded'},
			rotate = 0,
			transitionTime = 0.2,
		},
	},

	horizontalGradient = gui.Gradient{
		point_a = {x = 0, y = 0},
		point_b = {x = 1, y = 0},
		stops = {
			{
				position = 0,
				color = "#ffffff00",
			},
			{
				position = 0.2,
				color = "#ffffffff",
			},
			{
				position = 0.8,
				color = "#ffffffff",
			},
			{
				position = 1,
				color = "#ffffff00",
			},

		},
	},

	verticalGradient = gui.Gradient{
		point_a = {x = 0, y = 0},
		point_b = {x = 0, y = 1},
		stops = {
			{
				position = 0,
				color = "#ffffff00",
			},
			{
				position = 0.2,
				color = "#ffffffff",
			},
			{
				position = 0.8,
				color = "#ffffffff",
			},
			{
				position = 1,
				color = "#ffffff00",
			},
		},
	},
}



--============================================================================
--The title bar: a 32px menu strip across the very top of the screen with
--the DMHub / Game / Tools / Panels / Developer menus, plus Settings and
--Quit to Desktop on the main menu. The Draw Steel Codex (DMHub's sibling
--system) ships the same bar; this brings it to 5e.
--
--Why it lives at the END OF THIS FILE instead of its own file: the engine
--loads code mods one at a time over several seconds at boot, and the
--titlescreen appears almost immediately. This module is one of the first
--to load, so the bar shows up while the user is still on the lobby. (It
--originally lived in DMHub Game Hud, which loads so late that users
--always entered a game before the bar existed.) It sits below ThemeEngine
--because that is the only thing it needs at load time.
--
--The bar's panel is attached to dmhub.titleBarContainer, an engine-owned
--layer drawn over the top of the screen. The rest of the UI still spans
--the full screen behind it, so panels near the top must leave a
--TitleBar.Reserve()-sized gap to avoid being covered.
--============================================================================

TitleBar = {}

--The bar's height. The hud and dock system read it through
--TitleBar.Reserve() rather than hardcoding it.
TitleBar.Height = 32

local g_mounted = false

--True when the bar mounted into the engine's titleBarContainer. The hud
--(GameHud:CreateTopLeftButtonPanel) keeps the engine's Tools/Main menus
--when this is false; the dock system (GameHud:CreateDocks) reserves space
--on every dock when it is true.
function TitleBar.IsMounted()
    return g_mounted
end

--Vertical space the rest of the UI should leave for the bar: Height when
--mounted, 0 otherwise.
function TitleBar.Reserve()
    return cond(g_mounted, TitleBar.Height, 0)
end

--Collects the entries for one title-bar menu (the DMHub, Game, or Tools
--menu) from both panel registries.
--
--A panel chooses its menu by declaring `menu = "codex"|"game"|"tools"`
--when it registers. "codex" is the key for the DMHub menu -- the name is
--historical (both systems share this registration API) and kept so
--registrations work unchanged across systems. A dockable panel with no
--`menu` is listed in the Panels menu instead; a launchable panel with no
--`menu` defaults to the DMHub menu.
--
--rawget guards: at a cold-boot lobby only this module is loaded, so
--neither registry exists yet. The menus that call this are in-game only,
--but the guards keep a stray click from erroring.
local function WindowMenuItems(menuName)
    local result = {}

    if rawget(_G, "DockablePanel") ~= nil then
        for _,item in ipairs(DockablePanel.GetMenuItems()) do
            if item.menu == menuName then
                result[#result+1] = item
            end
        end
    end

    if rawget(_G, "LaunchablePanel") ~= nil then
        for _,item in ipairs(LaunchablePanel.GetMenuItems()) do
            if (item.menu or "codex") == menuName and item.text ~= "Development Tools" then
                result[#result+1] = item
            end
        end
    end

    return result
end

--Minimal dropdown for the cold-boot lobby, where Core UI's
--gui.ContextMenu is not loaded yet: a plain vertical list of clickable
--text rows. Handles only text + click, which is all the lobby-visible
--menus (DMHub: Settings / Log Out / Quit to Desktop) carry.
local function CreateFallbackMenu(element, menuItems)
    local rows = {}
    for _,item in ipairs(menuItems) do
        rows[#rows+1] = gui.Label{
            classes = {"titleBarFallbackRow"},
            bgimage = true,
            text = item.text or "",
            width = 220,
            height = 28,
            valign = "center",
            textAlignment = "left",
            pad = 6,
            press = function()
                element.popup = nil
                if item.click ~= nil then
                    item.click()
                end
            end,
        }
    end

    return gui.Panel{
        width = "auto",
        height = "auto",
        flow = "vertical",
        x = -element.renderedWidth,
        styles = {
            {
                selectors = {"titleBarFallbackRow"},
                bgcolor = "#161616f7",
                fontSize = 16,
                color = "srgb:#C09571",
                borderWidth = 1,
                borderColor = "srgb:#C09571",
            },
            {
                selectors = {"titleBarFallbackRow", "hover"},
                bgcolor = "srgb:#C09571",
                color = "#161616",
            },
        },
        children = rows,
    }
end

--One item on the menu strip: an icon+label that shows a dropdown of
--menuItems() when pressed. menuItems is called fresh on every press so
--entries always reflect current state.
local function CreateTitleBarMenuItem(args)
    local iconPanel

    local m_mainmenu = args.mainmenu
    args.mainmenu = nil

    local name = args.name
    args.name = nil
    local menuItems = args.menuItems
    args.menuItems = nil

    if args.icon then
        iconPanel = gui.Panel{
            classes = {"menuItemIcon"},
            width = 24,
            height = 24,
            bgimage = args.icon,
            valign = "center",
            interactable = false,
            seticon = function(element, icon)
                element.bgimage = icon
            end,
        }
        args.icon = nil
    end

    local CollectMenuItems
    CollectMenuItems = function(menuItems, result)
        for _,item in ipairs(menuItems) do
            if item.submenu then
                CollectMenuItems(item.submenu, result)
            else
                result[#result+1] = item
            end
        end
    end

    --mainmenu = true shows the item only on the main menu; mainmenu = "always"
    --shows it both on the main menu and in-game; otherwise in-game only.
    local visibilityClass
    if m_mainmenu == "always" then
        visibilityClass = nil
    elseif m_mainmenu then
        visibilityClass = "mainmenuOnly"
    else
        visibilityClass = "ingameOnly"
    end

    local resultPanel = {

        classes = {"menuItem", visibilityClass},
        popupPositioning = 'panel',

        width = "auto",
        height = "100%",
        flow = "horizontal",

        iconPanel,

        gui.Label{
            classes = {"menuLabel"},
            text = name,
            setname = function(element, newname)
                name = newname
                element.text = newname
            end,
            interactable = false,
        },

        --appends this menu's entries (submenus flattened) to result. A
        --global search feature could fire this event across the strip to
        --gather every menu command; nothing calls it yet.
        collectMenuItems = function(element, result)
            CollectMenuItems(menuItems(), result)
        end,

        hover = function(element)
            --see if a sibling menu is shown; if so, hover-follow into this one.
            for _,sibling in ipairs(element.parent.children) do
                if sibling ~= element and sibling.popup ~= nil then
                    sibling.popup = nil
                    element:FireEvent("press")
                    return
                end
            end
        end,

        press = function(element)

            if element.popup ~= nil then
                element.popup = nil
                return
            end

            local menuItems = menuItems()

            --gui.ContextMenu is defined by DMHub Core UI's Gui.lua, which
            --is not loaded at the cold-boot lobby (only this module is);
            --fall back to the minimal dropdown there. rawget: ContextMenu
            --is a plain Lua assignment onto the gui table when present.
            local menuPanel
            if rawget(gui, "ContextMenu") ~= nil then
                menuPanel = gui.ContextMenu{
                    width = 300,
                    x = -element.renderedWidth,
                    entries = menuItems,
                    click = function()
                        element.popup = nil
                    end,
                }
            else
                menuPanel = CreateFallbackMenu(element, menuItems)
            end

            element.popup = gui.Panel{
                width = "auto",
                height = "auto",
                halign = "right",
                valign = "bottom",
                menuPanel,
            }

        end,
    }

    for k,v in pairs(args) do
        resultPanel[k] = v
    end

    return gui.Panel(resultPanel)
end

--flipped whenever the theme changes; SetClassTree with the new value
--forces every descendant to re-cascade styles (reassigning .styles alone
--updates the rule array but does not mark descendants dirty).
local themeRefreshTick = false

local function CreateTopBar(container)

    local m_inGame = nil

    local menuBar = gui.Panel{
        id = "menuBarPanel",
        classes = {"titleBarSurface"},
        width = "100%",
        height = TitleBar.Height,
        floating = true,
        valign = "top",
        bgimage = true,
        flow = "horizontal",

        styles = {
            {
                selectors = {"mainmenuOnly", "ingame"},
                collapsed = 1,
            },
            {
                selectors = {"ingameOnly", "~ingame"},
                collapsed = 1,
            },
        },

        thinkTime = 0.2,
        think = function(element)
            --toggle the "ingame" class on the whole strip when the player
            --enters or leaves a game; the style rules above show/hide the
            --menu items from it. isLobbyGame covers transitional "lobby
            --game" states some engine flows use -- those still count as
            --the main menu.
            if (dmhub.inGame and not dmhub.isLobbyGame) ~= m_inGame then
                m_inGame = (dmhub.inGame and not dmhub.isLobbyGame)
                element:SetClassTree("ingame", m_inGame)
            end
            element:FireEventTree("calculateVisibility")
        end,

        --main-menu variant of the DMHub menu: Settings, Log Out, and Quit
        --to Desktop as hardcoded entries. In-game the equivalents arrive
        --through registered commands instead (see the in-game variant
        --below).
        CreateTitleBarMenuItem{
            name = "DMHub",
            icon = "ui-icons/DMHubLogo.png",
            mainmenu = true,
            menuItems = function()
                return {
                    {
                        text = "Settings",
                        icon = "panels/hud/gear.png",
                        click = function()
                            dmhub.ShowPlayerSettings()
                        end,
                    },
                    {
                        --same flow as the engine titlescreen's corner Log Out
                        --button (which the engine destroys once this bar
                        --mounts): hide the main screen, log out, show login.
                        --The titlescreen instance is the engine-core global
                        --`titlescreen`; rawget-guarded in case a future
                        --engine build renames it.
                        text = "Log Out",
                        icon = "game-icons/exit-door.png",
                        click = function()
                            local ts = rawget(_G, "titlescreen")
                            if ts == nil then
                                return
                            end
                            local mainScreen = ts:try_get("mainScreen")
                            if mainScreen ~= nil and mainScreen.valid then
                                mainScreen:SetClass("hidden", true)
                            end
                            dmhub.Logout()
                            ts:ShowLoginScreen()
                        end,
                    },
                    {
                        text = "Quit to Desktop",
                        icon = "game-icons/power-button.png",
                        click = function()
                            dmhub.QuitApplication()
                        end,
                    },
                }
            end,
        },

        CreateTitleBarMenuItem{
            name = "DMHub",
            icon = "ui-icons/DMHubLogo.png",
            menuItems = function()
                return WindowMenuItems("codex")
            end,
        },

        CreateTitleBarMenuItem{
            name = "Game",
            menuItems = function()
                return WindowMenuItems("game")
            end,
        },

        CreateTitleBarMenuItem{
            name = "Tools",
            menuItems = function()
                return WindowMenuItems("tools")
            end,
        },

        CreateTitleBarMenuItem{
            name = "Panels",
            menuItems = function()
                local dockablePanels = DockablePanel.GetMenuItems()
                --a dockable panel that declared `menu` is listed in that
                --title-bar menu (DMHub/Game/Tools) instead of here --
                --listing it in both would just be clutter.
                dockablePanels = table.filter(dockablePanels, function(item) return item.text ~= "Development Tools" and item.menu == nil end)

                --folder submenus are a different kind of row than the
                --panel toggles; giving them their own group makes the
                --context menu insert a divider before them.
                for _,p in ipairs(dockablePanels) do
                    if p.submenu ~= nil then
                        p.group = "folder"
                    end
                end

                local locked = dmhub.GetSettingValue("uilocked")
                local railMode = rawget(_G, "RailModeActive") ~= nil and RailModeActive()

                --rail mode has no Lock Panels row (see below), so it must not
                --honour the lock either -- a user who locked in dock mode and
                --then switched would find every row disabled with nothing left
                --to unlock it. Locking is a dock concept; the rail ignores it.
                if locked and not railMode then
                    for _,p in ipairs(gui.FlattenContextMenuItems(dockablePanels)) do
                        p.disabled = true
                    end
                end

                --In rail mode the rows keep their DEFAULT click: it routes
                --through the rail's open handler. Only the check needs
                --overriding: the default tracks the DOCK instance, which is
                --slid away in rail mode, so light the row while the panel
                --is shown anywhere on the rail surface instead.
                if railMode then
                    for _,p in ipairs(gui.FlattenContextMenuItems(dockablePanels)) do
                        local panelName = p.text
                        if panelName ~= nil and p.submenu == nil then
                            p.check = PanelDocument.IsPanelShown(string.lower(panelName))
                        end
                    end
                end

                --Dock/lock rows are dock-mode only: in rail mode the docks are
                --slid off screen and the rail owns placement, so toggling a
                --dock or resetting the dock layout does nothing visible, and
                --the lock has no meaning.
                if not railMode then
                    --icons so the dock rows align with the panel rows below,
                    --which all carry check gutter + icon + text.
                    table.insert(dockablePanels, 1, {
                        text = "Left Dock",
                        icon = "phosphor/sidebar-simple.png",
                        check = not dmhub.GetSettingValue("leftdockoffscreen"),
                        group = "panel",

                        click = function()
                            dmhub.SetSettingValue("leftdockoffscreen", not dmhub.GetSettingValue("leftdockoffscreen"))
                        end,
                    })

                    table.insert(dockablePanels, 1, {
                        text = "Right Dock",
                        icon = "phosphor/sidebar-simple.png",
                        check = not dmhub.GetSettingValue("rightdockoffscreen"),
                        group = "panel",

                        click = function()
                            dmhub.SetSettingValue("rightdockoffscreen", not dmhub.GetSettingValue("rightdockoffscreen"))
                        end,
                    })

                    table.insert(dockablePanels, 1, {
                        text = "Reset Panels",
                        icon = "icons/icon_tool/icon_power.png",
                        group = "panel",

                        click = function()
                            dmhub.ResetSetting(GetDockablePanelsSetting())
                            InitDockablePanels()
                        end,
                    })

                    table.insert(dockablePanels, 1, {
                        text = cond(locked, "Unlock Panels", "Lock Panels"),
                        icon = cond(locked, "icons/icon_tool/icon_tool_30.png", "icons/icon_tool/icon_tool_30_unlocked.png"),
                        check = locked,
                        group = "panel",
                        click = function()
                            dmhub.SetSettingValue("uilocked", not locked)
                        end,
                    })
                end

                --Workspace Views: the Panels menu is the only switcher UI,
                --so it carries the full verb set: switch, save, save-as,
                --reset, manage. Only in rail mode.
                if rawget(_G, "ViewsListForUser") ~= nil and railMode then
                    local active = ViewsActiveId()
                    local drift = ViewsIsDrifted()
                    local viewItems = {}
                    viewItems[#viewItems + 1] = {
                        text = "Custom",
                        check = active == nil,
                        group = "views",
                        click = function()
                            ViewsSwitchTo(nil)
                        end,
                    }
                    for _, v in ipairs(ViewsListForUser()) do
                        local vid = v.id
                        local text = v.name
                        if vid == active and drift then
                            text = text .. "  (unsaved changes)"
                        end
                        --a newer built-in version of this view exists;
                        --switching to it prompts the user to take the
                        --update or keep their copy.
                        if v.updated then
                            text = text .. "  (updated)"
                        end
                        viewItems[#viewItems + 1] = {
                            text = text,
                            check = vid == active,
                            group = "views",
                            click = function()
                                local skipped = ViewsSwitchTo(vid)
                                if rawget(_G, "ViewsPostApplyNotices") ~= nil then
                                    ViewsPostApplyNotices(vid, skipped)
                                end
                            end,
                        }
                    end
                    if active ~= nil and drift then
                        viewItems[#viewItems + 1] = {
                            text = "Save view",
                            group = "views",
                            click = function()
                                if ViewsSave() and rawget(_G, "ViewsToast") ~= nil then
                                    ViewsToast("View updated", function()
                                        ViewsUndoSave()
                                    end)
                                end
                            end,
                        }
                    end
                    viewItems[#viewItems + 1] = {
                        text = "Save as new view...",
                        group = "views",
                        click = function()
                            if rawget(_G, "ViewsSaveAsDialog") ~= nil then
                                ViewsSaveAsDialog()
                            end
                        end,
                    }
                    if active ~= nil then
                        viewItems[#viewItems + 1] = {
                            text = "Reset view to saved",
                            group = "views",
                            click = function()
                                ViewsResetToSaved()
                            end,
                        }
                    end
                    viewItems[#viewItems + 1] = {
                        text = "Manage views...",
                        group = "views",
                        click = function()
                            if rawget(_G, "ViewsManageDialog") ~= nil then
                                ViewsManageDialog()
                            end
                        end,
                    }
                    --one "Views" folder row rather than five-plus rows inline:
                    --the switcher is the least-used half of this menu and
                    --would push the panel toggles off the top.
                    table.insert(dockablePanels, 1, {
                        id = "FolderViews",
                        text = "Views",
                        group = "views",
                        submenu = viewItems,
                    })
                end

                return dockablePanels
            end,
        },

        CreateTitleBarMenuItem{
            name = "Developer",
            calculateVisibility = function(element)
                element.selfStyle.collapsed = cond(devmode(), 0, 1)
            end,
            menuItems = function()
                if not devmode() then
                    return {}
                end
                --collect the entries of every "Development Tools" folder
                --from both panel registries into one flat menu.
                --(rawget: at the lobby the registries are not loaded yet.)
                local registries = {}
                if rawget(_G, "DockablePanel") ~= nil then
                    registries[#registries+1] = DockablePanel.GetMenuItems()
                end
                if rawget(_G, "LaunchablePanel") ~= nil then
                    registries[#registries+1] = LaunchablePanel.GetMenuItems()
                end
                local menuItems = {}
                for i,items in ipairs(registries) do
                    for j,item in ipairs(items) do
                        if item.submenu and item.text == "Development Tools" then
                            for _,entry in ipairs(item.submenu) do
                                menuItems[#menuItems+1] = entry
                            end
                        end
                    end
                end
                return menuItems
            end,
        },
    }

    local titleBarStyleExtras = {
        -- Title-bar surface paints with the scheme's barTrack gradient.
        -- bgcolor = "white" is the image-tint multiplier: without it the
        -- cascade's @bg tints the gradient down to near-black on dark
        -- schemes.
        {
            selectors = {"titleBarSurface"},
            bgimage = true,
            bgcolor = "white",
            gradient = "@barTrack",
        },
    }

    --At the cold-boot lobby the engine has loaded ONLY this module (mods
    --load one at a time and the rest arrive on game entry), so ThemeEngine
    --has no themes or color schemes registered and @tokens cannot resolve.
    --These literal rules copy the default scheme's menuItem/menuLabel/
    --menuItemIcon values so the bar still paints correctly on the lobby;
    --the think below upgrades to the real merged theme styles the moment
    --the themes register. The surface is plain black rather than the
    --default scheme's teal barTrack gradient -- neutral against the
    --classic titlescreen art.
    local fallbackStyles = {
        {
            selectors = {"titleBarSurface"},
            bgimage = true,
            bgcolor = "#000000ff",
        },
        {
            selectors = {"menuItem"},
            bgimage = true,
            bgcolor = "clear",
            hpad = 8,
        },
        {
            selectors = {"menuItem", "hover"},
            bgcolor = "srgb:#C09571",
        },
        {
            selectors = {"menuLabel"},
            fontSize = 16,
            width = "auto",
            height = "auto",
            valign = "center",
            hmargin = 4,
            color = "srgb:#C09571",
        },
        {
            selectors = {"menuLabel", "parent:hover"},
            color = "#161616",
        },
        {
            selectors = {"menuItemIcon"},
            bgcolor = "srgb:#C09571",
        },
        {
            selectors = {"menuItemIcon", "parent:hover"},
            bgcolor = "#161616",
        },
    }

    local function ResolveTitleBarStyles()
        if #ThemeEngine.ListThemes() > 0 then
            return ThemeEngine.MergeStyles(titleBarStyleExtras)
        end
        return fallbackStyles
    end

    local m_themed = #ThemeEngine.ListThemes() > 0

    local topBarPanel = gui.Panel{
        id = "topBar",
        width = container.width,
        height = container.height,
        flow = "horizontal",

        screenResized = function(element)
            element.selfStyle.width = container.width
            element.selfStyle.height = container.height
        end,

        thinkTime = 0.5,
        think = function(element)
            if element.selfStyle.width ~= container.width then
                element.selfStyle.width = container.width
            end

            if element.selfStyle.height ~= container.height then
                element.selfStyle.height = container.height
            end

            --one-shot upgrade from the fallback styles to the real theme
            --once DefaultStyles has registered it (game entry); see
            --ResolveTitleBarStyles.
            if (not m_themed) and #ThemeEngine.ListThemes() > 0 then
                m_themed = true
                element.styles = ThemeEngine.MergeStyles(titleBarStyleExtras)
                themeRefreshTick = not themeRefreshTick
                element:SetClassTree("themeRefreshTick", themeRefreshTick)
            end
        end,

        styles = ResolveTitleBarStyles(),

        menuBar,
    }

    -- Force a re-cascade once the engine signals the game is fully loaded
    -- (and therefore every mod's color schemes are registered). The cascade
    -- computed at construction time may resolve before custom-scheme mods
    -- have finished registering, leaving the bar painted with the wrong
    -- scheme until something else invalidates the tree.
    dmhub.RegisterEventHandler("EnterGame", function()
        if topBarPanel and topBarPanel.valid then
            topBarPanel.styles = ThemeEngine.MergeStyles(titleBarStyleExtras)
            themeRefreshTick = not themeRefreshTick
            topBarPanel:SetClassTree("themeRefreshTick", themeRefreshTick)
        end
    end)

    -- Subscribe to theme changes so the bar repaints live when the user
    -- switches scheme via Settings instead of waiting for the next reload.
    ThemeEngine.OnThemeChanged(mod, function()
        if topBarPanel and topBarPanel.valid then
            topBarPanel.styles = ThemeEngine.MergeStyles(titleBarStyleExtras)
            themeRefreshTick = not themeRefreshTick
            topBarPanel:SetClassTree("themeRefreshTick", themeRefreshTick)
        end
    end)

    return topBarPanel
end

--Mount immediately, engine permitting. The container arrived after the
--0.526 engine this repo's stubs describe, so probe under pcall: on an
--older engine the bar simply does not exist and the hud keeps its default
--menus. The mount must NOT wait for anything else to load: at the
--cold-boot lobby this module is the only one the engine loads, so any
--"wait for X" gate here waits forever (the styling handles the missing
--theme registry via fallbackStyles in CreateTopBar).
local ok, container = pcall(function() return dmhub.titleBarContainer end)
if ok and container ~= nil then
    container.sheet = CreateTopBar(container)
    g_mounted = true
    print("TitleBar:: mounted into the engine's titleBarContainer")
else
    print("TitleBar:: dmhub.titleBarContainer not available on this engine build; title bar disabled")
end
