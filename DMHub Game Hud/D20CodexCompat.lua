local mod = dmhub.GetModLoading()

--D20CodexCompat: what the shared UI layer synced from the Draw Steel Codex
--(see CODEX_SYNC.md at the root of this repo) expects from mods that exist
--only in the Codex, provided here for DMHub / 5e. The synced files are kept
--byte-identical to the Codex's where possible, so this file absorbs the
--differences instead of patching them.
--
--Everything here is defined only when the real thing is absent, so a future
--sync that brings the real module over simply takes precedence.
--
--Loads first in DMHub Game Hud: after DMHub Game Rules (whose types it
--extends) and before GameHud.lua builds the hud.

local function Missing(name)
    return rawget(_G, name) == nil
end

--True when t.key is not defined. Reading a field a game type does not have
--raises an error rather than returning nil, hence the pcall.
local function MissingField(t, key)
    if t == nil then
        return false
    end
    local ok, value = pcall(function() return t[key] end)
    return (not ok) or value == nil
end

-----------------------------------------------------------------------
--Codex Titlescreen: CodexTitleBar. Tabletop.lua puts the live map's
--position readout in a map window's titlebar and moves the Round panel
--there. DMHub's title bar (DMHub Titlescreen/Styles.lua) shows neither, so
--only the readout is real here; the rest have nothing to move.

if Missing("CodexTitleBar") then
    CodexTitleBar = {}

    --Where the mouse is on the live map (the tile coordinates), for a map
    --window's titlebar. Dimmed while the mouse is off the map, keeping the
    --last position so the bar does not jump.
    function CodexTitleBar.CreateMapPosition(options)
        options = options or {}
        return gui.Panel{
            classes = {"menuItem"},
            flow = "horizontal",
            width = "auto",
            height = "100%",
            valign = "center",
            hpad = 8,
            gui.Label{
                classes = {"menuLabel"},
                fontSize = 13,
                minFontSize = 10,
                width = options.width or 96,
                height = "100%",
                hmargin = 0,
                textAlignment = "left",
                textWrap = false,
                textOverflow = "ellipsis",
                interactable = false,
                text = "--",
                data = {offMap = nil},
                thinkTime = 0.1,
                think = function(element)
                    local text = element.text
                    local offMap = dmhub.mouseOutsideMapView == true
                    if (not dmhub.inGame) or dmhub.isLobbyGame then
                        text = ""
                    elseif not offMap then
                        text = dmhub.status or ""
                    end
                    if element.text ~= text then
                        element.text = text
                    end
                    if element.data.offMap ~= offMap then
                        element.data.offMap = offMap
                        element.selfStyle.opacity = cond(offMap, 0.4, 1)
                    end
                end,
            },
        }
    end

    function CodexTitleBar.SetMapStatusInWindow(inWindow) end
    function CodexTitleBar.SetInitiativeStatusHost(host) end
    function CodexTitleBar.MountInitiativeStatusPanel(panel) end
end

--Codex Titlescreen: TopBar (the Codex's app title bar). GameHud.lua and
--FullscreenDisplay.lua report the adventure documents and what is being
--presented to it; DMHub's title bar has no place for either.
if Missing("TopBar") then
    TopBar = {}
    function TopBar.SetAdventureDocuments(meta, documentids) end
    function TopBar.SetPresentationInfo(info) end
    function TopBar.ClearPresentationInfo(id) end
end

-----------------------------------------------------------------------
--Draw Steel UI / Draw Steel V panels that GameHud.lua lists among its
--children. A child list stops at the first nil, so each returns an empty,
--collapsed panel rather than nil.

local function NothingPanel()
    return gui.Panel{
        classes = {"collapsed"},
        width = 0,
        height = 0,
        interactable = false,
    }
end

if Missing("DSVictoryScreen") then
    DSVictoryScreen = {
        Create = NothingPanel,
    }
end

if MissingField(GameHud, "CreateEncounterPrepBar") then
    function GameHud:CreateEncounterPrepBar()
        return NothingPanel()
    end
end

--Timeline\AbilitySidebar.lua in the Codex; its GameHud.lua default is an
--empty function commented out as dead code.
if MissingField(GameHud, "InitAbilityDisplayPanel") then
    function GameHud:InitAbilityDisplayPanel(abilityDisplayPanel) end
end

-----------------------------------------------------------------------
--Draw Steel Core Rules: ActivatedAbilityPowerRollBehavior. The Action Log's
--roll card (ActionLogPanel.lua) adjusts a roll's total for Draw Steel edges
--and banes. 5e rolls carry none, so the adjustment is always zero.

if Missing("ActivatedAbilityPowerRollBehavior") then
    ActivatedAbilityPowerRollBehavior = {}
    function ActivatedAbilityPowerRollBehavior.GetRollModFromEdgesAndBanes(boons, banes)
        return 0
    end
end

-----------------------------------------------------------------------
--Chat Enhancements: SendTitledChatMessage. The synced code uses it for
--developer notices (deprecated gui calls) and the /safetheme reply. DMHub
--has no titled chat message, so it goes to the log, never to the players.

if Missing("SendTitledChatMessage") then
    function SendTitledChatMessage(text, title, titleColor, recipients)
        print(string.format("%s:: %s", tostring(title or "chat"), tostring(text)))
    end
end

-----------------------------------------------------------------------
--Codex Macros: Commands.SplitArgs (the Journal's adventure macros).
--Copied from Codex Macros/Macros.lua.

if rawget(_G, "Commands") ~= nil and MissingField(Commands, "SplitArgs") then
    Commands.SplitArgs = function(str)
        local result = {}

        if string.find(str, "(", 1, true) then
            local currentStr = {}
            local stack = {}
            --handle nested parentheses
            local len = #str
            local i = 1
            while i <= len do
                local char = string.sub(str, i, i)
                if char == "(" or char == '"' then
                    if #currentStr > 0 then
                        result[#result + 1] = trim(table.concat(currentStr, ""))
                        currentStr = {}
                    end

                    stack[#stack + 1] = cond(char == "(", ")", char)
                    --find matching )
                    local j = i + 1
                    while j <= #str do
                        local c = string.sub(str, j, j)
                        if (c == "(" or c == '"') and c ~= stack[#stack] then
                            stack[#stack + 1] = cond(c == "(", ")", c)
                        elseif c == stack[#stack] then
                            stack[#stack] = nil
                            if #stack == 0 then
                                break
                            end
                        end
                        j = j + 1
                    end

                    if #stack == 0 then
                        --found matching )
                        local arg = string.sub(str, i + 1, j - 1)
                        result[#result + 1] = arg
                        i = j+1
                    else
                        local arg = string.sub(str, i + 1, j)
                        result[#result + 1] = arg
                        break
                    end
                elseif char == " " then
                    if #currentStr > 0 then
                        result[#result + 1] = trim(table.concat(currentStr, ""))
                        currentStr = {}
                    end
                    i = i+1
                else
                    currentStr[#currentStr + 1] = char
                    i = i+1
                end
            end

            if #currentStr > 0 then
                result[#result + 1] = trim(table.concat(currentStr, ""))
            end
            return result
        end

        while str ~= nil and str ~= "" do
            local match = regex.MatchGroups(str, "^\\s*((?<arg>[^\" ]+)|\"(?<arg>[^\"]+)\")(?<suffix>.*)$")
            if match == nil then
                break
            end

            result[#result + 1] = match.arg
            str = match.suffix
        end

        return result
    end
end

-----------------------------------------------------------------------
--Codex RollOnTableDialog.lua: RollOnTableProperties, the roll properties of
--a roll on a table started from a journal document (MarkdownDocument.lua).
--d20 keeps its own RollOnTableDialog.lua, so the type is defined here,
--without the Codex's custom chat panel.

if Missing("RollOnTableProperties") then
    RollOnTableProperties = RegisterGameType("RollOnTableProperties", "RollProperties")

    function RollOnTableProperties:GetOutcome(rollInfo)
        local total = self:try_get("overrideRollTotal") or rollInfo.total
        local tableRef = self:try_get("tableRef")
        if tableRef == nil then
            return nil
        end

        local t = tableRef:GetTable()
        if t == nil then
            return nil
        end

        local rowIndex = t:RowIndexFromDiceResult(total)
        if rowIndex == nil or rowIndex < 1 or rowIndex > #t.rows then
            return nil
        end

        local str = nil
        for _,item in ipairs(t.rows[rowIndex].value.items) do
            str = item:ToString()
            if str ~= nil then
                break
            end
        end
        if str == nil then
            return nil
        end

        return {
            outcome = str,
            color = "white",
        }
    end
end

-----------------------------------------------------------------------
--Rules methods the synced UI calls that the 5e rules do not define. The
--Codex's generic versions are in its DMHub Game Rules; the Draw Steel-only
--ones (companions, mentors) have no 5e meaning and answer "none".

--A hero is a player character (Tabletop's character cards, Table Dice).
if MissingField(creature, "IsHero") then
    function creature:IsHero()
        return false
    end
    function character:IsHero()
        return true
    end
end

if MissingField(creature, "IsMonster") then
    function creature:IsMonster()
        return false
    end
    function monster:IsMonster()
        return true
    end
end

--GameHud.lua's light-source tutorial step. 5e has no equipped-light slot.
if MissingField(creature, "GetEquippedLightSource") then
    function creature:GetEquippedLightSource()
        return nil
    end
end

--Draw Steel's Beastheart companion and the party mentor.
if MissingField(creature, "GetCompanionType") then
    function creature:GetCompanionType()
        return nil
    end
end
if MissingField(creature, "GetCompanionToken") then
    function creature:GetCompanionToken()
        return nil
    end
end
if MissingField(creature, "GetMentor") then
    function creature:GetMentor()
        return nil
    end
end

--Language names (ChatPanel.lua, InCharacterChat.lua, MarkdownDocument.lua).
--The Codex has optional "plain" language names and per-language scripts;
--5e languages have neither, so these return the name and the default font.
if rawget(_G, "Language") ~= nil then
    if MissingField(Language, "DisplayName") then
        function Language:DisplayName()
            return self.name
        end
    end
    if MissingField(Language, "DisplayNameWithDetail") then
        function Language:DisplayNameWithDetail()
            local speakers = self:try_get("speakers")
            if speakers ~= nil and speakers ~= "" then
                return string.format("%s (%s)", self.name, speakers)
            end
            return self.name
        end
    end
    if MissingField(Language, "TooltipHover") then
        function Language.TooltipHover(language)
            return nil
        end
    end
    if MissingField(Language, "UnreadableFont") then
        function Language:UnreadableFont()
            return "Berling"
        end
    end
    if MissingField(Language, "UnreadableFontForId") then
        function Language.UnreadableFontForId(langid)
            return "Berling"
        end
    end
end

--Gui.lua's currency editor. Copied from the Codex's Currency.lua.
if rawget(_G, "Currency") ~= nil and MissingField(Currency, "CalculatePayment") then
    function Currency.CalculatePayment(amount, standard, noWholeUnit)
        return Currency.CalculateSpend(nil, amount, standard, noWholeUnit) or {}
    end
end

-----------------------------------------------------------------------
--Draw Steel monster knowledge (ChatItemLinks.lua): a chat link to a
--creature opens the Draw Steel monster info dialog when the viewer has
--learned about it. 5e has no monster knowledge, so a link opens the
--creature's sheet.

if Missing("MonsterKnowledge") then
    MonsterKnowledge = {}
    function MonsterKnowledge.KeyForToken(token)
        return nil
    end
end

if Missing("MonsterInfoDialog") then
    MonsterInfoDialog = {}
    function MonsterInfoDialog.Show(subject)
        if subject ~= nil and not MissingField(subject, "ShowSheet") then
            subject:ShowSheet()
            return
        end
        --a bestiary entry (no token): DMHub has no sheet view for one yet.
        print("MonsterInfoDialog:: no sheet view for a bestiary monster in DMHub")
    end
end

-----------------------------------------------------------------------
--Codex Titlescreen: EotwHeroCard, the card face Tabletop.lua uses for
--character and creature cards on the table. The Codex's card shows Draw
--Steel stamina, recoveries, surges and the heroic resource; this one shows
--the portrait, the name, a subtitle line and the 5e hit points.

if Missing("EotwHeroCard") then
    local CARD_WIDTH = 132
    local PLAYER_HEIGHT = 12
    local CARD_HEIGHT = 176 + PLAYER_HEIGHT
    local OVERLAY_HEIGHT = 44 + PLAYER_HEIGHT

    local g_rules = {
        {
            selectors = {"eotwHeroCard"},
            bgcolor = "#151515",
            border = 1,
            borderColor = "#000000cc",
            transitionTime = 0.15,
        },
        {
            selectors = {"eotwHeroCard", "hover"},
            brightness = 1.15,
            borderColor = "#ffffff88",
        },
        {
            selectors = {"eotwHeroCard", "mine"},
            border = 2,
            borderColor = "#6fa8ffcc",
        },
        {
            selectors = {"eotwHeroCard", "dead"},
            saturation = 0,
            brightness = 0.7,
            borderColor = "#000000ff",
        },
        {
            selectors = {"eotwCardOverlay"},
            bgcolor = "#000000c0",
        },
        {
            selectors = {"eotwCardOverlay", "mine"},
            bgcolor = "#0d1e31d0",
        },
        {
            selectors = {"eotwHeroName"},
            fontSize = 12,
            bold = true,
            color = "#ffffff",
            width = "100%",
            height = 15,
            textAlignment = "left",
            textWrap = false,
            minFontSize = 8,
            textOverflow = "ellipsis",
            bmargin = 3,
        },
        {
            selectors = {"eotwHeroPlayer"},
            fontSize = 10,
            color = "#c8c8c8",
            width = "100%",
            height = PLAYER_HEIGHT,
            textAlignment = "left",
            textWrap = false,
            minFontSize = 7,
            textOverflow = "ellipsis",
        },
        {
            selectors = {"eotwHpTrack"},
            bgimage = "panels/square.png",
            bgcolor = "#00000099",
            width = "100%",
            height = 10,
            tmargin = 5,
            cornerRadius = 3,
        },
        {
            selectors = {"eotwHpFill"},
            bgimage = "panels/square.png",
            bgcolor = "#3fa34d",
            halign = "left",
            height = "100%",
            cornerRadius = 3,
        },
        {
            selectors = {"eotwHpFill", "bloodied"},
            bgcolor = "#c9a227",
        },
        {
            selectors = {"eotwHpFill", "down"},
            bgcolor = "#a32828",
        },
        {
            selectors = {"eotwHpText"},
            fontSize = 9,
            color = "#ffffff",
            width = "100%",
            height = "100%",
            textAlignment = "center",
        },
    }

    local function HeroDisplayName(tok)
        local name = nil
        pcall(function() name = tok.name end)
        if name == nil or name == "" then
            return "Unnamed"
        end
        return name
    end

    local function PlayerName(tok)
        local owner = nil
        pcall(function() owner = tok.ownerId end)
        if owner == nil or owner == "" then
            return ""
        end
        if owner == "PARTY" then
            return "Party"
        end
        local name = owner
        pcall(function() name = dmhub.GetDisplayName(owner) or owner end)
        return name
    end

    local function IsUnregisteredAssetId(id)
        if type(id) ~= "string" then
            return false
        end
        if string.match(id, "^%x+%-%x+%-%x+%-%x+%-%x+$") == nil then
            return false
        end
        local known = false
        pcall(function() known = assets.allAssets[id] ~= nil end)
        return not known
    end

    local ApplyPortrait

    local function SchedulePortraitRetry(element)
        dmhub.Schedule(0.25, function()
            if mod.unloaded or not element.valid then
                return
            end
            local wait = element.data.eotwPortraitWait
            if wait == nil then
                return
            end
            if IsUnregisteredAssetId(wait.portrait) then
                SchedulePortraitRetry(element)
                return
            end
            element.data.eotwPortraitWait = nil
            pcall(ApplyPortrait, element, wait.tok, wait.aspect)
        end)
    end

    --Paints the creature's portrait as the panel's full-bleed background,
    --cropped to the panel's shape (as the Codex card does).
    ApplyPortrait = function(element, tok, aspect)
        local portrait = nil
        pcall(function() portrait = tok.offTokenPortrait end)
        local waiting = element.data.eotwPortraitWait
        if IsUnregisteredAssetId(portrait) then
            element.data.eotwPortraitWait = { tok = tok, aspect = aspect, portrait = portrait }
            if waiting == nil then
                SchedulePortraitRetry(element)
            end
            return false
        end
        element.data.eotwPortraitWait = nil
        if portrait == nil or portrait == "" then
            return false
        end
        element.bgimage = portrait
        element.selfStyle.bgcolor = "white"
        local rect = nil
        pcall(function() rect = CardPortraitRect(tok, aspect, portrait) end)
        element.selfStyle.imageRect = rect
        return true
    end

    --The 5e hit point bar: current / max, plus temporary hit points.
    local function CreateHitpointsBar(charid)
        local fill = gui.Panel{
            classes = {"eotwHpFill"},
            width = "100%",
            interactable = false,
        }
        local text = gui.Label{
            classes = {"eotwHpText"},
            floating = true,
            text = "",
            interactable = false,
        }
        return gui.Panel{
            classes = {"eotwHpTrack"},
            interactable = false,
            data = { sig = nil },
            refreshCard = function(element)
                local tok = dmhub.GetCharacterById(charid)
                if tok == nil or not tok.valid or tok.properties == nil then
                    return
                end
                local cur, max, temp = 0, 0, 0
                pcall(function()
                    cur = tok.properties:CurrentHitpoints() or 0
                    max = tok.properties:MaxHitpoints() or 0
                    temp = tok.properties:TemporaryHitpoints() or 0
                end)
                local sig = string.format("%d/%d/%d", cur, max, temp)
                if sig == element.data.sig then
                    return
                end
                element.data.sig = sig
                local ratio = 0
                if max > 0 then
                    ratio = math.max(0, math.min(1, cur / max))
                end
                fill.selfStyle.width = string.format("%d%%", math.floor(ratio * 100 + 0.5))
                fill:SetClass("bloodied", max > 0 and cur > 0 and cur <= max / 2)
                fill:SetClass("down", cur <= 0)
                if temp > 0 then
                    text.text = string.format("%d/%d (+%d)", cur, max, temp)
                else
                    text.text = string.format("%d/%d", cur, max)
                end
            end,
            fill,
            text,
        }
    end

    --entry: {charid, mine, name}. opts as the Codex's CreateHeroCard; this
    --card honours halign, valign, passPress, click, useClick, displayName,
    --subtitle, dismiss, draggable (and its drag callbacks) and dragTarget.
    --The Draw Steel ones (showStats, showResources, noRecoveries,
    --spendRecovery, showDowntime, extraChips) have nothing to show.
    local function CreateHeroCard(entry, opts)
        opts = opts or {}
        local charid = entry.charid
        local mineClass = cond(entry.mine, "mine", nil)

        local nameLabel = gui.Label{
            classes = {"eotwHeroName"},
            text = entry.name or "",
            interactable = false,
        }
        local playerLabel = gui.Label{
            classes = {"eotwHeroPlayer"},
            text = "",
            interactable = false,
        }

        local overlay = gui.Panel{
            classes = {"eotwCardOverlay", mineClass},
            floating = true,
            halign = "center",
            valign = "bottom",
            width = "100%",
            height = OVERLAY_HEIGHT,
            flow = "vertical",
            bgimage = "panels/square.png",
            cornerRadius = 8,
            hpad = 6,
            vpad = 4,
            borderBox = true,
            interactable = false,
            nameLabel,
            playerLabel,
            CreateHitpointsBar(charid),
        }

        local function OpenCharacterPanel(element)
            audio.FireSoundEvent("Mouse.Click")
            local toggle = rawget(_G, "ToggleCharacterPanelDocument")
            if toggle ~= nil then
                toggle(charid, nil, element)
                return
            end
            local tok = dmhub.GetCharacterById(charid)
            if tok ~= nil and tok.valid then
                tok:ShowSheet()
            end
        end

        local cardClasses = {"eotwHeroCard"}
        if mineClass ~= nil then
            cardClasses[#cardClasses+1] = mineClass
        end

        local cardArgs = {
            classes = cardClasses,
            width = CARD_WIDTH,
            height = CARD_HEIGHT,
            halign = opts.halign or "right",
            valign = opts.valign,
            cornerRadius = 8,
            bgimage = "panels/square.png",
            swallowPress = opts.passPress ~= true,

            data = { charid = charid, mine = entry.mine },

            refreshCard = function(element)
                local tok = dmhub.GetCharacterById(charid)
                if tok == nil or not tok.valid then
                    return
                end
                local dead = false
                pcall(function() dead = tok.properties:IsDead() == true end)
                element:SetClass("dead", dead)
                if opts.displayName ~= nil then
                    nameLabel.text = opts.displayName(tok) or ""
                else
                    nameLabel.text = HeroDisplayName(tok)
                end
                if opts.subtitle ~= nil then
                    playerLabel.text = opts.subtitle(tok) or ""
                else
                    playerLabel.text = PlayerName(tok)
                end
                ApplyPortrait(element, tok, CARD_WIDTH / CARD_HEIGHT)
            end,

            create = function(element)
                element:FireEventTree("refreshCard")
            end,

            thinkTime = 0.5,
            think = function(element)
                element:FireEventTree("refreshCard")
            end,

            overlay,
        }

        if opts.dismiss ~= nil then
            cardArgs[#cardArgs+1] = gui.Panel{
                classes = {"eotwCardDismiss"},
                floating = true,
                halign = "right",
                valign = "top",
                x = -4,
                y = 4,
                width = 18,
                height = 18,
                bgimage = "phosphor/x-bold.png",
                bgcolor = "#ffffffcc",
                swallowPress = true,
                styles = {
                    {
                        selectors = {"eotwCardDismiss"},
                        hidden = 1,
                    },
                    {
                        selectors = {"eotwCardDismiss", "parent:hover"},
                        hidden = 0,
                    },
                    {
                        selectors = {"eotwCardDismiss", "hover"},
                        hidden = 0,
                        bgcolor = "#ff7a6aff",
                        scale = 1.15,
                    },
                },
                hover = gui.Tooltip(opts.dismiss.tooltip or "Remove"),
                click = function(element)
                    audio.FireSoundEvent("Mouse.Click")
                    opts.dismiss.click(element)
                end,
            }
        end

        if opts.click ~= nil then
            cardArgs.click = function(element)
                opts.click(element, OpenCharacterPanel)
            end
        elseif opts.useClick then
            cardArgs.click = OpenCharacterPanel
        else
            cardArgs.press = OpenCharacterPanel
        end
        if opts.draggable ~= nil then
            cardArgs.draggable = opts.draggable == true
            cardArgs.canDragOnto = opts.canDragOnto
            cardArgs.drag = opts.drag
            cardArgs.beginDrag = opts.beginDrag
            cardArgs.dragging = opts.dragging
        end
        if opts.dragTarget then
            cardArgs.dragTarget = true
            cardArgs.dragTargetPriority = opts.dragTargetPriority
            cardArgs.dragTargets = opts.dragTargets
        end
        return gui.Panel(cardArgs)
    end

    EotwHeroCard = {
        CreateHeroCard = CreateHeroCard,
        ApplyPortrait = ApplyPortrait,
        HeroDisplayName = HeroDisplayName,
        rules = g_rules,
        CARD_WIDTH = CARD_WIDTH,
        CARD_HEIGHT = CARD_HEIGHT,
    }
end
