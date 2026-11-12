local mod = dmhub.GetModLoading()

--ThemeEngine used to be defined here; it now lives in ThemeEngine.lua in this
--mod (the Codex's file, loaded just before this one). See CODEX_SYNC.md.

-- =============================================================================
-- The 5e palette.
--
-- DefaultStyles.lua (DMHub Core UI) is synced from the Codex, whose "default"
-- color scheme is Draw Steel's parchment-on-black. DMHub keeps the classic 5e
-- gold-on-dark look: these values are merged over the Codex's "default" scheme
-- as DefaultStyles registers it, so any token the Codex adds later still
-- resolves (to the Codex value) instead of showing magenta. ThemeEngine refuses
-- a second registration of an id, hence the hook rather than a re-register.
-- =============================================================================

local g_d20DefaultScheme = {
    description = "The classic D&D 5e gold-on-dark palette.",
    colors = {
        bg            = "#161616",
        bgAlt         = "#222222",
        bgRaised      = "#2E2E2E", --text-field hover/focus lift
        bgInverse     = "srgb:#C09571", --gold "primary by value" fill
        fg            = "srgb:#C09571",
        fgStrong      = "#d0c3a5",
        fgMuted       = "#777777",
        fgPending     = "#999999",
        fgInverse     = "#222222", --text on a gold fill
        border        = "srgb:#C09571",
        --the quiet frame for rounded borders (the frame shader ignores alpha).
        borderSolid   = "#3A3A3A",
        borderInverse = "#666666",
        accent        = "srgb:#C09571",
        accentHover   = "#d0c3a5",
        success       = "#77ff77",
        info          = "#E9C868",
        warning       = "#fa9a00",
        danger        = "#bb0000",
    },
    gradients = {
        surfaceRadial = {
            type = "radial",
            point_a = {x = 0.5, y = 0.5},
            point_b = {x = 0.5, y = 1.0},
            stops = {
                {position = -0.01, color = "#1c1c1c"},
                {position = 0.00,  color = "#1c1c1c"},
                {position = 0.12,  color = "#191919"},
                {position = 0.25,  color = "#161616"},
                {position = 0.37,  color = "#131313"},
                {position = 0.50,  color = "#101010"},
                {position = 0.62,  color = "#0d0d0d"},
                {position = 0.75,  color = "#0b0b0b"},
                {position = 0.87,  color = "#080808"},
                {position = 1.00,  color = "#060606"},
            },
        },
        surfaceLinear = {
            point_a = {x = 0, y = 0},
            point_b = {x = 1, y = 1},
            stops = {
                {position = 0, color = "#060606"},
                {position = 1, color = "#1c1c1c"},
            },
        },
        barTrack = {
            point_a = {x = -0.02, y = 0},
            point_b = {x = 1.02,  y = 0},
            stops = {
                {position = 0, color = "#161616"},
                {position = 1, color = "#2A2A2A"},
            },
        },
    },
}

--Rounded corners on the default theme (DMHub only; the Codex has no such theme).
--Registered when DefaultStyles registers the default scheme: the title bar
--takes "a color scheme is registered" to mean the themes are ready.
local function RegisterRoundedTheme()
ThemeEngine.RegisterTheme{
    id          = "default-rounded",
    name        = "Default Rounded",
    description = "Default theme with rounded corners on bordered surfaces.",
    colorScheme = "default",

    styles = {
        -- Panel surfaces
        { selectors = {"panel", "bordered"},   cornerRadius = 10 },
        { selectors = {"panel", "dialog"},     cornerRadius = 10 },
        { selectors = {"modalDialog"},         cornerRadius = 10 },
        { selectors = {"framedPanel"},         cornerRadius = 10 },
        { selectors = {"contextMenu"},         cornerRadius = 10 },
        -- the card root paints the @bgAlt fill (and any accent border), so
        -- it must round along with its header/body children or its square
        -- corners peek out from behind them.
        { selectors = {"featureCard"},         cornerRadius = 10 },
        { selectors = {"featureCardHeader"},   cornerRadius = 10 },
        {
            selectors = {"featureCardHeader", "expanded"},
            cornerRadius = {x1 = 10, x2 = 0, y1 = 10, y2 = 0},
        },
        { selectors = {"featureCardBody"},     cornerRadius = {x1 = 0, x2 = 10, y1 = 0, y2 = 10} },

        -- Interactive controls
        { selectors = {"label", "button"},        cornerRadius = 5 },
        { selectors = {"iconButton"},             cornerRadius = 5 },
        { selectors = {"input"},                  cornerRadius = 5 },
        { selectors = {"searchInput"},            cornerRadius = 5 },
        { selectors = {"dropdown"},               cornerRadius = 5 },
        { selectors = {"dropdownBorder"},         cornerRadius = 5 },
        { selectors = {"dropdownMenuSub"},        cornerRadius = 5 },
        { selectors = {"colorPicker"},            cornerRadius = 5 },
        { selectors = {"label", "bordered"},      cornerRadius = 5 },
        { selectors = {"input", "bordered"},      cornerRadius = 5 },
        { selectors = {"multiselectChip"},        cornerRadius = 5 },
        { selectors = {"multiselectChipRemove"},  cornerRadius = 5 },
        -- Enum slider: round only the outer ends so the row reads as one pill.
        -- x1=top-left, y1=top-right, x2=bottom-right, y2=bottom-left.
        { selectors = {"enumSliderOption"},       cornerRadius = 0 },
        { selectors = {"enumSliderOption", "enumSliderFirst"},                     cornerRadius = {x1 = 5, y1 = 0, x2 = 0, y2 = 5} },
        { selectors = {"enumSliderOption", "enumSliderLast"},                      cornerRadius = {x1 = 0, y1 = 5, x2 = 5, y2 = 0} },
        { selectors = {"enumSliderOption", "enumSliderFirst", "enumSliderLast"},   cornerRadius = 5 },
        { selectors = {"checkBackground"},        cornerRadius = 5 },
        { selectors = {"tab"},                    cornerRadius = {x1 = 5, x2 = 0, y1 = 5, y2 = 0} },
    },
}
end

do
    local baseRegister = ThemeEngine.RegisterColorScheme
    ThemeEngine.RegisterColorScheme = function(spec)
        --the Codex's MCDM-branded scheme is not offered in DMHub.
        if type(spec) == "table" and spec.id == "mcdm" then
            return false
        end
        if type(spec) == "table" and spec.id == "default" then
            local merged = {}
            for k, v in pairs(spec) do merged[k] = v end
            merged.description = g_d20DefaultScheme.description
            merged.colors = {}
            for k, v in pairs(spec.colors or {}) do merged.colors[k] = v end
            for k, v in pairs(g_d20DefaultScheme.colors) do merged.colors[k] = v end
            merged.gradients = {}
            for k, v in pairs(spec.gradients or {}) do merged.gradients[k] = v end
            for k, v in pairs(g_d20DefaultScheme.gradients) do merged.gradients[k] = v end
            spec = merged
        end
        local registered = baseRegister(spec)
        if registered and type(spec) == "table" and spec.id == "default" then
            RegisterRoundedTheme()
        end
        return registered
    end
end

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

		--the open dropdown menu. The synced gui.Dropdown no longer styles its
		--own popup: the popup inherits the control's cascade, and upstream
		--the open-menu rules live only in the ThemeEngine theme. Surfaces
		--whose cascade has Styles.Default but not the theme (the character
		--sheet, the title screen's dialogs) got bare, unframed option lists.
		--These mirror DefaultStyles' rules in the gold-on-dark palette; where
		--the theme IS in the cascade it sits nearer the popup and wins.
		gui.Style{
			selectors = {"dropdownBorder"},
			bgimage = true,
			bgcolor = "#161616",
			border = 2,
			borderColor = textColor,
			vpad = 2,
			hpad = 0,
			priority = 55,
		},
		gui.Style{
			selectors = {"dropdownBorder", "vcenter"},
			border = 2,
			vpad = 4,
		},
		gui.Style{
			selectors = {"dropdownBorder", "top"},
			border = 2,
		},
		gui.Style{
			selectors = {"dropdownBorder", "detached"},
			border = 2,
		},
		gui.Style{
			selectors = {"dropdownMenuSub"},
			bgimage = true,
			bgcolor = "#161616",
			border = 2,
			borderColor = textColor,
			pad = 2,
			flow = "vertical",
			width = "auto",
			height = "auto",
			valign = "top",
			hidden = 1,
		},
		gui.Style{
			selectors = {"dropdownMenuSub", "parent:hover"},
			hidden = 0,
		},
		gui.Style{
			selectors = {"dropdownOption"},
			bgimage = true,
			width = "100%-4",
			height = "auto",
			halign = "center",
			textAlignment = "left",
			hpad = 6,
			fontSize = 18,
			color = textColor,
			bgcolor = "#161616",
			--beat the generic label rules surfaces add after Styles.Default
			--(the character sheet centers its labels); stays below the
			--hover rule's 5 so the hover fill still shows.
			priority = 4,
		},
		gui.Style{
			selectors = {"dropdownOption", "hover"},
			color = "black",
			bgcolor = textColor,
			priority = 5,
		},
		gui.Style{
			selectors = {"dropdownOption", "searchfocus"},
			color = "black",
			bgcolor = textColor,
		},
		gui.Style{
			selectors = {"dropdownOption", "disabled"},
			color = "#777777",
		},
		gui.Style{
			selectors = {"dropdownSearch"},
			border = 0,
		},
		gui.Style{
			selectors = {"submenuArrow"},
			bgcolor = textColor,
		},
		gui.Style{
			selectors = {"submenuArrow", "parent:hover"},
			bgcolor = "#161616",
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

--Styles fields the shared code synced from the Draw Steel Codex uses (see
--CODEX_SYNC.md), copied from the Codex's DMHub Titlescreen/Styles.lua. Only
--fields this stylesheet does not define itself; d20's own stay as they are.
Styles.portraitWidthPercentOfHeight = Styles.portraitWidthPercentOfHeight or 100*3/4
Styles.portraitHeightPercentOfWidth = Styles.portraitHeightPercentOfWidth or 100*4/3
Styles.forbiddenColor = Styles.forbiddenColor or "#C73131"
Styles.RichBlackGradient = Styles.RichBlackGradient or gui.Gradient{
	point_a = {x = -0.02, y = 0},
	point_b = {x = 1.02, y = 0},
	stops = {
		{position = 0, color = "#060605"},
		{position = 1, color = "#191A18"},
	},
}
Styles.ImplementationStatusColors = Styles.ImplementationStatusColors or {
    [0] = "#f82fcd",  -- won't implement (pink)
    [1] = "#ff0000",  -- unimplemented (red)
    [2] = "#cd7f32",  -- bronze
    [3] = "#c0c0c0",  -- silver
    [4] = "#ffd700",  -- gold
}
Styles.RichBlack02 = Styles.RichBlack02 or "#10110F"
Styles.RichBlack03 = Styles.RichBlack03 or "#191A18"
Styles.RichBlack04 = Styles.RichBlack04 or "#343432"
Styles.Grey02 = Styles.Grey02 or "srgb:#666666"
Styles.Grey01 = Styles.Grey01 or "srgb:#9F9F9B"
Styles.Cream01 = Styles.Cream01 or "srgb:#F3EDE7"
Styles.Cream02 = Styles.Cream02 or "srgb:#DFCFC0"
Styles.Cream03 = Styles.Cream03 or "srgb:#BC9B7B"
Styles.Gold04 = Styles.Gold04 or "srgb:#E9B86F"
Styles.Gold03 = Styles.Gold03 or "srgb:#F1D3A5"
Styles.Gold02 = Styles.Gold02 or "srgb:#49362C"
Styles.ModifierBuffColor = Styles.ModifierBuffColor or "srgb:#2A4DFF"
Styles.ModifierDebuffColor = Styles.ModifierDebuffColor or "red"
Styles.icons = Styles.icons or {
        visible = "icons/standard/Icon_App_Visible.png",
        hidden = "icons/standard/Icon_App_Hidden.png",
        locked = "icons/standard/Icon_App_Lock.png",
        unlocked = "icons/standard/Icon_App_Unlock.png",
    }
Styles.tempGradient = Styles.tempGradient or gui.Gradient {
        point_a = {x = 0, y = 0},
        point_b = {x = 1, y = 0},
        stops = {
            {
                position = 0,
                color = "#6666aa",
            },
            {
                position = 1,
                color = "#6666ff",
            },
        },
    }
Styles.grayscaleGradient = Styles.grayscaleGradient or gui.Gradient{
        point_a = {x = 0, y = 0},
        point_b = {x = 1, y = 0},
        stops = {
            {
                position = 0,
                color = "#484848",
            },
            {
                position = 1,
                color = "#C1C1C1",
            },
        },
    }
Styles.Triggers = Styles.Triggers or {
        textColor = "white",
        triggerColor = "#cccc00",
        freeColor = "#9999ff",
		passiveColor = "#006300",
		hostileColor = "#bb2222",

        triggerColorAgainstText = "#aaaa00",
        freeColorAgainstText = "#7777ee",
		passiveColorAgainstText = "#006300",
		hostileColorAgainstText = "#992020",
    }
Styles.TriggerStyles = Styles.TriggerStyles or {
        gui.Style{
            selectors = {"triggeredActionPanel"},
            bgcolor = "#cccc00",
            color = "white",
            bold = true,
            textAlignment = "center",
        },
        gui.Style{
            selectors = {"triggeredActionPanel", "free"},
            bgcolor = "#9999ff",
            color = "white",
        },
		gui.Style{
			selectors = {"triggeredActionPanel", "passive"},
			bgcolor = "#006300",
			color = "white",
		},
		--hostile sits after free/passive so it wins when both classes apply.
		gui.Style{
			selectors = {"triggeredActionPanel", "hostile"},
			bgcolor = "#bb2222",
			color = "white",
		},
        gui.Style{
            selectors = {"triggeredActionPanel", "expended"},
            saturation = 0.3,
            brightness = 0.3,
            color = "black",
        },
    }
Styles.Tabs = Styles.Tabs or {
        gui.Style{
            selectors = { "tab" },

            bgimage = true,
            borderWidth = 1,
            borderColor = "#cccccc",
            width = 100,
            height = 40,
            fontSize = 18,
            bgcolor = backgroundColor,
            color = "#666666",
            hpad = 6,
        },
        gui.Style{
            selectors = { "tab", "selected" },
            bold = true,
            color = "white",
            borderColor = "white",
            borderWidth = 2,
        },
        gui.Style{
            selectors = { "tab", "hover" },
            brightness = 1.2,
        }
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

--============================================================================
--Window controls (merged title bar)
--
--On Windows the engine removes the native caption bar, so this bar must
--provide dragging and the minimize / maximize / close buttons, and send a
--heartbeat; if the heartbeat stops, the engine restores the native caption.
--============================================================================

--True on platforms that support the merged title bar (Windows builds, not the editor).
local g_windowChromeAvailable = nil
local function WindowChromeBridgeAvailable()
    if g_windowChromeAvailable == nil then
        local ok, avail = pcall(function() return dmhub.mergedTitleBarAvailable end)
        g_windowChromeAvailable = (ok and avail == true)
    end
    return g_windowChromeAvailable
end

local function MergedTitleBarActive()
    return WindowChromeBridgeAvailable() and dmhub.GetSettingValue("mergedtitlebar") == true
end

local function ApplyMergedTitleBar()
    if WindowChromeBridgeAvailable() then
        dmhub.SetMergedTitleBar(dmhub.GetSettingValue("mergedtitlebar") == true)
    end
end

--The engine reads this preference at boot, so the id and default must match its own.
setting{
    id = "mergedtitlebar",
    description = "Merge window title bar",
    storage = "preference",
    editor = "check",
    default = true,
    onchange = function()
        ApplyMergedTitleBar()
    end,
}

--safe to repeat on a reload.
ApplyMergedTitleBar()

--The bar's root panel, set when it is created.
local g_menuBarPanel = nil

--The maximize button. The engine treats it as Windows' own maximize button (for the
--Snap Layouts flyout), so its clicks arrive via the windowMaxButtonClick event below.
local m_maximizeControl = nil

--Hides the bar while the window is resizing (maximize, snap) so it doesn't flash
--half-laid-out; shows it again once the size holds still, or after a timeout.
local g_transitionToken = 0
local g_transitionActive = false

local function StartWindowTransitionGuard(stableSamples, timeout)
    local bar = g_menuBarPanel
    if bar == nil or not bar.valid or not MergedTitleBarActive() then
        return
    end

    stableSamples = stableSamples or 6
    timeout = timeout or 2.5

    --a newer call replaces one still running.
    g_transitionToken = g_transitionToken + 1
    local token = g_transitionToken

    if not g_transitionActive then
        g_transitionActive = true
        bar:SetClassTree("windowTransition", true)
    end

    local dims = dmhub.screenDimensions
    local lastW, lastH = dims.x, dims.y
    local stable = 0
    local started = dmhub.Time()

    local function poll()
        if mod.unloaded or token ~= g_transitionToken then
            return
        end
        if not bar.valid then
            g_transitionActive = false
            return
        end

        local d = dmhub.screenDimensions
        if d.x == lastW and d.y == lastH then
            stable = stable + 1
        else
            stable = 0
            lastW = d.x
            lastH = d.y
        end

        if stable >= stableSamples or dmhub.Time() - started > timeout then
            g_transitionActive = false
            bar:SetClassTree("windowTransition", false)
            return
        end

        dmhub.Schedule(0.05, poll)
    end

    dmhub.Schedule(0.05, poll)
end

--Maximize or restore. The bar hides first and the resize follows a beat later.
local function ToggleMaximize()
    StartWindowTransitionGuard()
    dmhub.Schedule(0.05, function()
        if not mod.unloaded then
            dmhub.ToggleMaximizeWindow()
        end
    end)
end

--Tells the engine where the bar's buttons are; the rest of the bar acts as the
--window caption. Re-sent from the bar's think so it follows layout changes.
local function UpdateTitleBarHitRegions()
    local bar = g_menuBarPanel
    if bar == nil or not bar.valid or not MergedTitleBarActive() then
        return
    end
    pcall(function()
        if dmhub.titleBarChromeMode ~= "nccalcsize" then
            return
        end
        local exclusions = {}
        for _,child in ipairs(bar.children) do
            --the drag surface and hidden children are not buttons.
            if child.valid and child.id ~= "titleBarDragSurface"
                    and not child:HasClass("collapsed") and not child:HasClass("hidden") then
                exclusions[#exclusions+1] = child
            end
        end
        --maximize is disabled while fullscreen.
        local maxControl = nil
        if m_maximizeControl ~= nil and m_maximizeControl.valid
                and dmhub.GetSettingValue("fullscreen") ~= true then
            maxControl = m_maximizeControl
        end
        dmhub.SetTitleBarHitRegions{
            bar = bar,
            exclusions = exclusions,
            maximizeButton = maxControl,
        }
    end)
end

--One window button: a full-height hover zone with a centered icon, like the
--native Windows buttons. The window-chrome/* icons come from the engine.
local function CreateWindowControl(args)
    return gui.Panel{
        classes = {"windowControl", cond(args.danger, "windowControlDanger")},
        bgimage = true,
        width = 42,
        height = "100%",
        valign = "center",
        data = { maximized = nil },
        calculateVisibility = args.calculateVisibility,
        click = args.click,
        hover = args.hover,

        gui.Panel{
            classes = {"windowControlIcon", cond(args.danger, "windowControlIconDanger")},
            bgimage = args.icon,
            width = 16,
            height = 16,
            halign = "center",
            valign = "center",
            interactable = false,
            setIcon = function(element, icon)
                element.bgimage = icon
            end,
        },
    }
end

--Close button. In a game it asks first, since a stray click would end the
--session; on the main menu it closes right away.
local m_quitConfirmDialog = nil
local function ConfirmCloseWindow()
    if (not dmhub.inGame) or dmhub.isLobbyGame then
        dmhub.CloseWindow()
        return
    end

    --no hud to show the prompt in: just close.
    local gh = rawget(_G, "gamehud")
    if gh == nil then
        dmhub.CloseWindow()
        return
    end

    --don't stack prompts on repeated clicks.
    if m_quitConfirmDialog ~= nil and m_quitConfirmDialog.valid then
        return
    end

    m_quitConfirmDialog = gh:ModalDialog{
        title = "Quit to Desktop?",
        width = 760,
        height = 340,
        buttonsHalign = "center",
        buttons = {
            {
                text = "Cancel",
                escapeActivates = true,
                click = function()
                    m_quitConfirmDialog = nil
                end,
            },
            {
                text = "Quit",
                click = function()
                    m_quitConfirmDialog = nil
                    dmhub.CloseWindow()
                end,
            },
        },

        gui.Panel{
            width = 640,
            height = 120,
            halign = "center",
            valign = "center",
            flow = "vertical",

            gui.Label{
                classes = {"modalMessage"},
                text = "You are in a game. Quitting will close DMHub and leave the session.",
            },
        },
    }
end

--Window button styles. Plain colors, not theme @tokens: the bar also paints at
--the lobby, before themes are registered. Close turns Windows red on hover.
local windowControlStyles = {
    {
        selectors = {"windowControl"},
        bgcolor = "clear",
    },
    {
        selectors = {"windowControl", "hover"},
        bgcolor = "#ffffff1f",
    },
    {
        selectors = {"windowControl", "press"},
        bgcolor = "#ffffff33",
    },
    {
        selectors = {"windowControlDanger", "hover"},
        bgcolor = "#c42b1c",
    },
    {
        selectors = {"windowControlDanger", "press"},
        bgcolor = "#b3271a",
    },
    {
        selectors = {"windowControlIcon"},
        bgcolor = "#d4d4d4",
    },
    {
        selectors = {"windowControlIconDanger", "parent:hover"},
        bgcolor = "#ffffff",
    },
    --disabled maximize (fullscreen); after the hover rules so it wins.
    {
        selectors = {"windowControl", "windowControlDisabled"},
        bgcolor = "clear",
    },
    {
        selectors = {"windowControlIcon", "parent:windowControlDisabled"},
        opacity = 0.35,
    },
}

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
            --window buttons only show while the title bar is merged.
            {
                selectors = {"windowButtonsOff"},
                collapsed = 1,
            },
            --set by StartWindowTransitionGuard.
            {
                selectors = {"windowTransition"},
                opacity = 0,
            },
        },

        data = { lastScreenDims = nil },

        create = function(element)
            g_menuBarPanel = element
            --the window resizes a few times at startup; stay hidden until it settles.
            StartWindowTransitionGuard(12, 6)
        end,

        destroy = function(element)
            --clear the button rects so the engine doesn't keep using a stale layout.
            pcall(function() dmhub.SetTitleBarHitRegions(nil) end)
        end,

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

            if MergedTitleBarActive() then
                --heartbeat (see the Window controls section). pcall: older engines lack it.
                pcall(function() dmhub.WindowChromeHeartbeat() end)

                --also hide during resizes we didn't start (edge snap, Win+arrow).
                local d = dmhub.screenDimensions
                local prev = element.data.lastScreenDims
                if prev ~= nil and (d.x ~= prev.x or d.y ~= prev.y) and not g_transitionActive then
                    StartWindowTransitionGuard()
                end
                element.data.lastScreenDims = {x = d.x, y = d.y}

                UpdateTitleBarHitRegions()
            end
        end,

        --Drag surface: empty bar space drags the window; a second press within
        --0.4s maximizes. First child, so it sits under everything and only gets
        --presses on empty bar (a handler on the bar itself would eat button clicks).
        gui.Panel{
            --UpdateTitleBarHitRegions looks for this id.
            id = "titleBarDragSurface",
            floating = true,
            width = "100%",
            height = "100%",
            bgimage = true,
            bgcolor = "clear",
            data = { lastBarPress = nil },
            press = function(element)
                if not MergedTitleBarActive() then
                    return
                end
                local now = dmhub.Time()
                if element.data.lastBarPress ~= nil and now - element.data.lastBarPress < 0.4 then
                    element.data.lastBarPress = nil
                    ToggleMaximize()
                else
                    element.data.lastBarPress = now
                    --no drag while maximized: Windows would restore it mid-drag
                    --and the window ends up at a broken size.
                    if not dmhub.windowMaximized then
                        local before = dmhub.screenDimensions
                        --returns when the user lets go.
                        dmhub.BeginWindowDrag()
                        --a snap resizes the window; the new size shows a frame later.
                        dmhub.Schedule(0.1, function()
                            if mod.unloaded then
                                return
                            end
                            local after = dmhub.screenDimensions
                            if after.x ~= before.x or after.y ~= before.y then
                                StartWindowTransitionGuard()
                            end
                        end)
                    end
                end
            end,
        },

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

        --Every window and item on this user's table (Tabletop.lua), as the
        --Codex title bar's Windows menu. Only where there is a table (a real
        --game, not the lobby). Tabletop is rawget-checked for its functions:
        --Audio.lua makes a bare Tabletop table before Tabletop.lua loads.
        CreateTitleBarMenuItem{
            name = "Windows",
            calculateVisibility = function(element)
                local tabletop = rawget(_G, "Tabletop")
                local active = tabletop ~= nil and tabletop.IsActive ~= nil and tabletop.IsActive()
                element.selfStyle.collapsed = cond(active, 0, 1)
            end,
            menuItems = function()
                local tabletop = rawget(_G, "Tabletop")
                local items = {}
                if tabletop ~= nil and tabletop.WindowsMenuEntries ~= nil then
                    items = tabletop.WindowsMenuEntries()
                end
                if #items == 0 then
                    items = {{text = "No windows on the table", disabled = true}}
                end
                return items
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

        --Window buttons, right-aligned. Hidden when the title bar isn't merged,
        --since the native caption has its own.
        gui.Panel{
            classes = {"windowButtons", "windowButtonsOff"},
            flow = "horizontal",
            width = "auto",
            height = "100%",
            halign = "right",
            valign = "center",
            calculateVisibility = function(element)
                element:SetClass("windowButtonsOff", not MergedTitleBarActive())
            end,

            CreateWindowControl{
                icon = "window-chrome/chrome-minimize.png",
                click = function()
                    dmhub.MinimizeWindow()
                end,
            },

            --kept in m_maximizeControl for UpdateTitleBarHitRegions.
            (function()
                m_maximizeControl = CreateWindowControl{
                    icon = "window-chrome/chrome-maximize.png",
                    calculateVisibility = function(element)
                        --gray out maximize while fullscreen.
                        local fullscreen = dmhub.GetSettingValue("fullscreen") == true
                        if fullscreen ~= element.data.fullscreenDisabled then
                            element.data.fullscreenDisabled = fullscreen
                            element:SetClass("windowControlDisabled", fullscreen)
                        end
                        if not WindowChromeBridgeAvailable() then
                            return
                        end
                        --show the restore icon while maximized.
                        local maximized = dmhub.windowMaximized
                        if maximized ~= element.data.maximized then
                            element.data.maximized = maximized
                            element:FireEventTree("setIcon", cond(maximized, "window-chrome/chrome-restore.png", "window-chrome/chrome-maximize.png"))
                        end
                    end,
                    hover = function(element)
                        --gui.Tooltip (Core UI) isn't loaded at the lobby.
                        if dmhub.GetSettingValue("fullscreen") == true and rawget(gui, "Tooltip") ~= nil then
                            gui.Tooltip("Fullscreen mode: Press F11 to enter Windowed mode")(element)
                        end
                    end,
                    click = function()
                        if dmhub.GetSettingValue("fullscreen") == true then
                            return
                        end
                        ToggleMaximize()
                    end,
                }
                return m_maximizeControl
            end)(),

            CreateWindowControl{
                danger = true,
                icon = "window-chrome/chrome-close.png",
                click = function()
                    ConfirmCloseWindow()
                end,
            },
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
    --default scheme's barTrack gradient -- neutral against the
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

    --window buttons look the same with or without a theme.
    for _,rule in ipairs(windowControlStyles) do
        titleBarStyleExtras[#titleBarStyleExtras+1] = rule
        fallbackStyles[#fallbackStyles+1] = rule
    end

    local function ResolveTitleBarStyles()
        if #ThemeEngine.ListColorSchemes() > 0 then
            return ThemeEngine.MergeStyles(titleBarStyleExtras)
        end
        return fallbackStyles
    end

    local m_themed = #ThemeEngine.ListColorSchemes() > 0

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
            if (not m_themed) and #ThemeEngine.ListColorSchemes() > 0 then
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
    -- Subscribe to theme changes so the bar repaints live when the user
    -- switches scheme via Settings instead of waiting for the next reload.
    -- ThemeEngine.OnThemeChanged needs EventUtils (DMHub Core UI), which the
    -- cold-boot title screen has not loaded, so subscribe once it exists
    -- (at load when it already does, else on entering a game).
    local m_themeListening = false
    local ListenForThemeChanges

    dmhub.RegisterEventHandler("EnterGame", function()
        if topBarPanel and topBarPanel.valid then
            topBarPanel.styles = ThemeEngine.MergeStyles(titleBarStyleExtras)
            themeRefreshTick = not themeRefreshTick
            topBarPanel:SetClassTree("themeRefreshTick", themeRefreshTick)
        end
        ListenForThemeChanges()
    end)

    ListenForThemeChanges = function()
        if m_themeListening or rawget(_G, "EventUtils") == nil then
            return
        end
        m_themeListening = true
        ThemeEngine.OnThemeChanged(mod, function()
            if topBarPanel and topBarPanel.valid then
                topBarPanel.styles = ThemeEngine.MergeStyles(titleBarStyleExtras)
                themeRefreshTick = not themeRefreshTick
                topBarPanel:SetClassTree("themeRefreshTick", themeRefreshTick)
            end
        end)
    end
    ListenForThemeChanges()

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

--Windows owns the maximize button's area (see m_maximizeControl), so the engine
--forwards its hover state and clicks through these two events.
dmhub.RegisterEventHandler("windowMaxButtonState", function()
    if mod.unloaded then
        return
    end
    local control = m_maximizeControl
    if control == nil or not control.valid then
        return
    end
    --disabled while fullscreen.
    if dmhub.GetSettingValue("fullscreen") == true then
        control:SetClass("hover", false)
        control:SetClass("press", false)
        return
    end
    local state = "none"
    pcall(function() state = dmhub.windowMaxButtonState end)
    control:SetClass("hover", state == "hover" or state == "pressed")
    control:SetClass("press", state == "pressed")
end)

dmhub.RegisterEventHandler("windowMaxButtonClick", function()
    if mod.unloaded then
        return
    end
    --disabled while fullscreen.
    if dmhub.GetSettingValue("fullscreen") == true then
        return true
    end
    ToggleMaximize()
    --true = handled. Otherwise the engine toggles maximize too, undoing ours.
    return true
end)
