local mod = dmhub.GetModLoading()

local GetSettingEnum = function(var)
	if var.enumCalc ~= nil then
		return var.enumCalc()
	end

	return var.enum
end

local CreateEditorPanel = function(var, editor, changeFunction, args)
	args = args or {}

	local label = nil
	if not var.hidelabel then
		label = gui.Label{
			text = string.format("%s:", var.description),
			style = {
				width = "auto",
				height = "auto",
				fontSize = '50%',
				halign = 'left',
				valign = 'center',
				textAlignment = 'center',
			},
		}
	end

	return gui.Panel{
		styles = {
			{
				width = "90%",
				height = 48,
				flow = 'horizontal',
				hmargin = 2,
			},
			args.panelStyle,
		},

		monitor = var.id,
		events = {
			monitor = function(element)
				if changeFunction ~= nil then
					changeFunction(dmhub.GetSettingValue(var.id))
				end
			end,
		},

		children = {
			label,
			editor,
		}
	}
end

local SettingsEditors = {

	input = function(var)
		local input = gui.Input{
			text = dmhub.GetSettingValue(var.id),

			characterLimit = var.characterLimit,

			halign = 'right',
			valign = "center",
			height = 20,
			width = 200,

			events = {
				change = function(element)
					dmhub.SetSettingValue(var.id, element.text)
					if var.onchange then
						var.onchange()
					end
				end
			}
		}

		return CreateEditorPanel(var, input)
	end,

	sliderexponential = function(var)

		local sign = var.sign or 1

		local formatFunction = nil
		local deformatFunction = nil
		if var.percent ~= false then
			formatFunction = function(num)
				return string.format('%d%%', round((2^num)*100))
			end
			deformatFunction = function(num)
				local n = num*0.01
				return math.log(n)/math.log(2)
			end
		else
			formatFunction = function(num)
				return string.format('%d', round((2^num)))
			end
			deformatFunction = function(num)
				local n = num
				return math.log(n)/math.log(2)
			end
		end

		local sliderElement = gui.Slider{
			minValue = var.min,
			maxValue = var.max,
			value = dmhub.GetSettingValue(var.id),
			round = var.round,

			sliderWidth = 110,
			labelWidth = 40,

			formatFunction = formatFunction,
			deformatFunction = deformatFunction,

			labelFormat = var.labelFormat or '%.1f',
			events = {
				
				change = function(element)
					dmhub.SetSettingValue(var.id, element.data.getValue())
					if var.onchange then
						var.onchange()
					end

					element:FireEventOnParents("childsetting", var.id)
				end,
			},
			style = {
				halign = 'right',
				valign = 'center',
				fontSize = '30%',
				height = 28,
				width = 160,
			}
		}

		return CreateEditorPanel(var, sliderElement, function(newValue) sliderElement.data.setValueNoEvent(newValue) end)
	end,

	slider = function(var, options)
		options = options or {}

		local formatFunction = nil
		local deformatFunction = nil
		if var.percent then
			formatFunction = function(num)
				return string.format('%d%%', round(num*100))
			end
			deformatFunction = function(num)
				local n = num*0.01
				return n
			end
		end

		local sliderElement = gui.Slider{
			minValue = var.min,
			maxValue = var.max,
			value = dmhub.GetSettingValue(var.id),
			round = var.round,

			formatFunction = formatFunction,
			deformatFunction = deformatFunction,

			sliderWidth = 110,
			labelWidth = 40,
			labelFormat = var.labelFormat or '%.1f',
			events = {
				
				change = function(element)
					dmhub.PreviewSettingValue(var.id, element.data.getValue())
				end,

				confirm = function(element)
					dmhub.SetSettingValue(var.id, element.data.getValue())
					if var.onchange then
						var.onchange()
					end

					element:FireEventOnParents("childsetting", var.id)
				end,
			},
			styles = {
				{
					halign = 'right',
					valign = 'center',
					fontSize = 12,
					height = 28,
					width = 160,
				},
				options.style,
			},
		}

		return CreateEditorPanel(var, sliderElement, function(newValue) sliderElement.data.setValueNoEvent(newValue) end, options)

	end,

	check = function(var, options)
		options = options or {}

		local keybinds = nil

		if var.bind ~= nil then
			keybinds = {
				{
					id = var.id,
					defaultBind = var.bind,
				}
			}
		end

		return 
		gui.Panel{
			width = "90%",
			height = "auto",
			gui.Check{
				value = dmhub.GetSettingValue(var.id),
				text = var.description,
				halign = options.halign or "left",
				keybinds = keybinds,

				style = {
					width = options.width or "100%",
					height = options.height or 40,
					fontSize = options.fontSize or 14,
					hpad = 0,
				},

				monitor = var.id,

				events = {
					monitor = function(element)
						element.value = dmhub.GetSettingValue(var.id)
					end,

					change = function(element)
						dmhub.SetSettingValue(var.id, element.value)
						if var.onchange then
							var.onchange()
						end

						element:FireEventOnParents("childsetting", var.id)
					end,
				},
			}
		}
	end,

	dropdown = function(var, args)
		local value = dmhub.GetSettingValue(var.id)

		args = args or {}

		local options = {}

		if var.getOptions ~= nil then
			options = var.getOptions()
		else
			for i,item in ipairs(GetSettingEnum(var)) do
				options[#options+1] = {
					id = item.value,
					text = item.text or item.value,
					keybind = cond(item.bind, item.bind),
				}

				if item.bind ~= nil then
					print("BIND:: DROPDOWN: ", options[#options])
				end
			end
		end

		local editor = gui.Dropdown{
					options = options,
					idChosen = value,
					styles = {
						{
							fontSize = 18,
							width = 180,
							height = 48,
							halign = 'right',
							valign = 'center',
						},
						args.style,
					},
					monitor = var.id,
					events = {
						monitor = function(element)
							value = dmhub.GetSettingValue(var.id)
							element.idChosen = value
						end,
						change = function(element)
							dmhub.SetSettingValue(var.id, element.idChosen)
							if var.onchange then
								var.onchange()
							end
						end,
						refreshAssets = function(element)
							if var.getOptions ~= nil then
								element.options = var.getOptions()
							end
						end,
					}
				}
		
		return CreateEditorPanel(var, editor, nil, args)

	end,

	iconlibrary = function(var)
		local iconPanel = gui.IconEditor{
			library = var.library,
			categoriesHidden = true,
			searchHidden = true,
			bgcolor = "white",
			width = 32,
			height = 32,
			hideButton = true,
			value = dmhub.GetSettingValue(var.id),
			valign = "center",

			monitor = var.id,
			events = {
				change = function(element)
					dmhub.SetSettingValue(var.id, element.value)
					element:FireEventOnParents("childsetting", var.id)
				end,

				monitor = function(element)
					element.value = dmhub.GetSettingValue(var.id)
				end,
			}
		}

		return gui.Panel{
			style = {
				width = "100%",
				height = 48,
				flow = 'horizontal',
				hmargin = 2,
			},

			children = {
				gui.Label({
					text = string.format("%s:", var.description),
					style = {
						width = "auto",
						height = "auto",
						fontSize = '50%',
						valign = 'center',
						textAlignment = 'center',
					},
				}),

				iconPanel,
			},
		}
	end,

	iconbuttons = function(var)

		local buttons = {}
		local value = dmhub.GetSettingValue(var.id)
		local selectedIndex = nil
		local valueToIndex = {}

		for i,item in ipairs(GetSettingEnum(var)) do
			local enumItem = item
			local currentIndex = i
			local classes = {"hudIconButton"}
			if item.value == value then
				classes[#classes+1] = 'selected'
				selectedIndex = i
			end

			valueToIndex[enumItem.value] = i

			buttons[#buttons+1] = gui.Panel({
				bgimage = 'panels/square.png',
				classes = classes,

				events = {
					press = function(element)
						if selectedIndex ~= nil then
							buttons[selectedIndex]:RemoveClass('selected')
						end
						
						gui.SetFocus(element)

						selectedIndex = currentIndex
						element:AddClass('selected')
						dmhub.SetSettingValue(var.id, enumItem.value)
						if var.onchange then
							var.onchange()
						end

					end,
					hover = function(element)
						if enumItem.help ~= nil then
							gui.Tooltip(enumItem.help)(element)
						end
					end,
				},

				children = {
					gui.Panel({
						classes = {"hudIconButtonIcon"},
						bgimage = enumItem.icon,
					})
				},
			})
		end

		return gui.Panel({
			styles = {
				{
					width = "100%",
					height = 48,
					flow = 'horizontal',
					hmargin = 2,
				},
				{
					selectors = {"hudIconButton"},
					width = 32,
					height = 32,
                    halign = "center",
					valign = 'center',
				},
			},

			monitor = var.id,
			events = {
				monitor = function(element)
					local index = valueToIndex[element.monitorValue]
					if index ~= nil and index ~= selectedIndex then
						buttons[index]:FireEvent('press')
					end
				end,

				--event which selects the first button.
				pressfirst = function(element)
					buttons[1]:FireEvent("press")
				end,
			},

			children = {
			--gui.Label({
			--	text = string.format("%s:", var.description),
			--	style = {
			--		width = "auto",
			--		height = "auto",
			--		fontSize = '50%',
			--		valign = 'center',
			--		textAlignment = 'center',
			--	},
			--}),

				buttons,
			},
		})

	end,

	color = function(var)
		local picker = gui.ColorPicker{
					value = dmhub.GetSettingValue(var.id),
					popupAlignment = 'left',

					hasAlpha = var.hasAlpha,

					monitor = var.id,

					events = {
						confirm = function(element)
							dmhub.SetSettingValue(var.id, element.value) --now we are confirmed we will set, unlocking the value.
							if var.onchange then
								var.onchange()
							end
						end,

						change = function(element)
							dmhub.SetSettingValue(var.id, element.value, true) --set the value and lock it until we confirm.
						end,

						monitor = function(element)
							local newValue = dmhub.GetSettingValue(var.id)

							if element.value == newValue then
								return
							end

							element.value = newValue
						end,
					},
					styles = {
						{
							halign = 'right',
							valign = 'center',
							fontSize = '30%',
							height = 24,
							width = 24,
							borderWidth = 2,
							borderColor = '#ffffff77',
						},
						{
							selectors = 'hover',
							borderColor = '#ffffffbb',
						},
						{
							selectors = 'press',
							borderColor = '#ffffffdd',
						},

					}

				}

		return CreateEditorPanel(var, picker)
	end,

	buttonincrement = function(var)
		local button = gui.PrettyButton{
			text = var.description,
			width = 260,
			height = 48,
			events = {
				click = function(element)
					dmhub.SetSettingValue(var.id, dmhub.GetSettingValue(var.id)+1)
					if var.onchange then
						var.onchange()
					end
				end
			},
		}

		return button
	end,
}

function CreateSettingsDisplay(var, options)
	local setting = Settings[var]
	if setting == nil then
		dmhub.Error('Unknown setting: ' .. var)
		return nil
	end

	options = options or {}

	local args = {
		width = 'auto',
		height = 'auto',
		text = GetSettingPrettyValue(setting),
		multimonitor = var.monitorVisible,
		monitor = function(element)
			if setting.visible ~= nil then
				panel:SetClass('collapsed', not setting.visible())
			end

			element.text = GetSettingPrettyValue(setting)
		end,
	}

	for k,option in pairs(options) do
		args[k] = option
	end

	return gui.Label(args)
end

function CreateSettingsEditor(var, options)
	if type(var) == 'string' then
		local setting = Settings[var]
		if setting == nil then
			dmhub.Error('Unknown setting: ' .. var)
			return nil
		end

		var = setting
	end

	if var.editor ~= nil then
		local panel = SettingsEditors[var.editor](var, options)
		if panel ~= nil then
			local container = gui.Panel({
				classes = var.classes,
				halign = "center",
				selfStyle = {
					width = 'auto',
					height = 'auto',
					pad = 0,
					margin = 0,
				},

				multimonitor = var.monitorVisible,
				events = {
					monitor = function(element)
						if var.visible ~= nil then
							panel:SetClass('collapsed', not var.visible())
						end
					end,
				},

				children = {
					panel
				}
			})

			if var.assetsRefresh then
				container.events.refreshAssets = function(element)
					panel = SettingsEditors[var.editor](var, options)
					container.children = {panel}
				end
			end

			if var.visible ~= nil then
				container:FireEvent('monitor')
			end

			return container
		end
	end

	return nil
end

function CreateSettingsEditorsForSection(section)
	local result = {}
	for i,setting in ipairs(SettingsOrdered) do
		if setting.section == section then
			result[#result+1] = CreateSettingsEditor(setting)
		end
	end
	return result
end

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
	id = "playervisionoverlay",
	description = "Player Vision Overlay",
	classes = {"dmonly"},
	section = "General",
	default = false,
	editor = "check",
	storage = "preference",
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
	id = "buildingbrushsize",
	default = 1,
	storage = "preference",
}

setting{
	id = "effectsbrushsize",
	default = 1,
	storage = "preference",
}

--The roll dialog's DM preroll checkbox reads this. It was never registered
--anywhere, so register it here to make the value save properly.
setting{
	id = "preroll",
	default = false,
	storage = "preference",
}

--------------------------------------------------------------------------------
-- Theme & Color Scheme picker dialog, ported from the Draw Steel codex.
-- Lets the player pick a theme and color scheme, preview them, and create
-- custom schemes. If the ThemeEngine global is missing, the menu entry hides
-- itself and the dialog shows a notice instead.
--
-- Differences from the codex original (widgets the 5e gui does not have):
--   * gui.Multiselect does not exist here: the "Sample Tags" preview row is
--     omitted.
--   * gui.MCDMDivider does not exist here: gui.Divider is used instead.
--   * The class-styled icon buttons (addButton/copyButton/...) are replaced by
--     the legacy constructors gui.AddButton / gui.CopyButton /
--     gui.SettingsButton / gui.DeleteItemButton / gui.CloseButton.
--   * gui.Button has no requireConfirm here: the picker's Delete uses a
--     two-click confirm instead.
--   * The legacy dropdown cannot display a chosen id that lives inside a
--     submenu, so user schemes are flattened into the top-level option list
--     rather than nested under a "My Schemes" submenu.
--------------------------------------------------------------------------------

-- Analytics helper. Wrapped in pcall so a missing telemetry setting or
-- analytics surface can never cause an error.
local function themeDialogTrack(eventType, fields)
	pcall(function()
		if dmhub.GetSettingValue("telemetry_enabled") == false then
			return
		end
		fields.type = eventType
		fields.userid = dmhub.userid
		fields.gameid = dmhub.gameid
		fields.version = dmhub.version
		analytics.Event(fields)
	end)
end

-- Sound events may not exist in the 5e content set; never let them error.
local function themeDialogSound(eventName)
	pcall(function()
		audio.FireSoundEvent(eventName)
	end)
end

local CreateThemeSettingsDialog

LaunchablePanel.Register{
	name = "Theme & Color Scheme...",
	icon = "game-icons/paint-brush.png",
	halign = "center",
	valign = "center",
	filtered = function()
		--ThemeEngine is provided by game-system mods; hide the menu item when
		--no loaded mod supplies it.
		return rawget(_G, "ThemeEngine") == nil
	end,
	content = function()
		return CreateThemeSettingsDialog()
	end,
}

-- Build dropdown options with "Default" pinned to the top, the rest
-- sorted alphabetically (case-insensitive).
local function buildSortedThemeOptions(list)
	local defaultOpt
	local rest = {}
	for _, item in ipairs(list) do
		local opt = { id = item.id, text = item.name }
		if item.id == "default" then
			defaultOpt = opt
		else
			rest[#rest+1] = opt
		end
	end
	table.sort(rest, function(a, b)
		return string.lower(a.text) < string.lower(b.text)
	end)
	if defaultOpt then
		table.insert(rest, 1, defaultOpt)
	end
	return rest
end

-- Resolve a registered id to its display name; falls back to the id itself
-- if no match (defensive -- selected ids come from these same lists).
local function themeNameForId(list, id)
	for _, item in ipairs(list) do
		if item.id == id then
			return item.name
		end
	end
	return id
end

local function buildThemePreviewBody()
	return {
		gui.Label{
			classes = {"sizeL", "bold"},
			text = "Sample Heading",
		},
		gui.Panel{
			classes = {"formRow"},
			gui.Label{
				classes = {"form"},
				text = "Sample Field:",
			},
			gui.Input{
				classes = {"form"},
				text = "type here...",
			},
		},
		gui.Panel{
			classes = {"formRow"},
			gui.Check{
				classes = {"form"},
				text = "Enabled",
				value = true,
			},
		},
		gui.Panel{
			classes = {"formRow"},
			gui.Label{
				classes = {"form"},
				text = "Sample Dropdown:",
			},
			gui.Dropdown{
				classes = {"form"},
				idChosen = "a",
				options = {
					{ id = "a", text = "Option A" },
					{ id = "b", text = "Option B" },
					{ id = "c", text = "Option C" },
				},
			},
		},
		--The codex original has a "Sample Tags" gui.Multiselect row here;
		--gui.Multiselect does not exist in the legacy gui surface, so it is
		--omitted from the preview.
		gui.Panel{
			classes = {"formRow"},
			gui.Label{
				classes = {"form"},
				text = "Icon Buttons:",
			},
			gui.Button{
				icon = "game-icons/paint-brush.png",
				width = 24,
				height = 24,
				valign = "center",
			},
			gui.AddButton{
				valign = "center",
			},
			gui.CopyButton{
				valign = "center",
			},
			gui.SettingsButton{
				width = 24,
				height = 24,
				valign = "center",
			},
			gui.DeleteItemButton{
				valign = "center",
			},
			gui.CloseButton{
				valign = "center",
			},
		},
		gui.Panel{
			classes = {"formRow"},
			gui.Label{
				classes = {"form"},
				text = "Sample Slider:",
			},
			gui.Slider{
				minValue = 0,
				maxValue = 100,
				value = 60,
				sliderWidth = 200,
				labelWidth = 40,
				labelFormat = "%d",
				height = 24,
				valign = "center",
			},
		},
		gui.Panel{
			classes = {"formRow"},
			gui.Label{
				classes = {"form"},
				text = "Sample Table:",
				valign = "top",
			},
			gui.Panel{
				width = "auto",
				height = "auto",
				flow = "vertical",
				gui.Panel{
					classes = {"row", "headerRow"},
					width = 300,
					flow = "horizontal",
					gui.Label{ classes = {"tableLabel"}, width = "33%", text = "Name" },
					gui.Label{ classes = {"tableLabel"}, width = "33%", text = "Class" },
					gui.Label{ classes = {"tableLabel"}, width = "33%", text = "Level" },
				},
				gui.Panel{
					classes = {"row", "evenRow"},
					width = 300,
					flow = "horizontal",
					gui.Label{ classes = {"tableLabel"}, width = "33%", text = "Aldric" },
					gui.Label{ classes = {"tableLabel"}, width = "33%", text = "Fighter" },
					gui.Label{ classes = {"tableLabel"}, width = "33%", text = "5" },
				},
				gui.Panel{
					classes = {"row", "oddRow"},
					width = 300,
					flow = "horizontal",
					gui.Label{ classes = {"tableLabel"}, width = "33%", text = "Brenna" },
					gui.Label{ classes = {"tableLabel"}, width = "33%", text = "Wizard" },
					gui.Label{ classes = {"tableLabel"}, width = "33%", text = "5" },
				},
				gui.Panel{
					classes = {"row", "evenRow"},
					width = 300,
					flow = "horizontal",
					gui.Label{ classes = {"tableLabel"}, width = "33%", text = "Caedrik" },
					gui.Label{ classes = {"tableLabel"}, width = "33%", text = "Rogue" },
					gui.Label{ classes = {"tableLabel"}, width = "33%", text = "5" },
				},
			},
		},
		gui.Button{
			classes = {"sizeL"},
			halign = "center",
			valign = "bottom",
			text = "Sample Button",
		},
	}
end

-- Drive a CrossFade from 1 -> 0 over `duration` seconds. Caller hands us a
-- transition handle that has already captured the snapshot; we just animate
-- the dissolve and Destroy() when done.
local function themeDialogFadeOut(transition, duration)
	local startTime = dmhub.Time()
	local tick
	tick = function()
		if mod.unloaded then
			transition:Destroy()
			return
		end
		local t = (dmhub.Time() - startTime) / duration
		if t >= 1 then
			transition:CrossFade(0)
			transition:Destroy()
			return
		end
		transition:CrossFade(1 - t)
		dmhub.Schedule(0.01, tick)
	end
	dmhub.Schedule(0.01, tick)
end

-- Run fn under a screen-transition crossfade when the engine supports it,
-- falling back to an instant swap otherwise.
local function themeDialogTransition(fn, duration)
	if dmhub.StartScreenTransition == nil then
		fn()
		return
	end
	local transition
	transition = dmhub.StartScreenTransition(function()
		if mod.unloaded then return end
		fn()
		themeDialogFadeOut(transition, duration)
	end)
end

-- Human-readable labels for the editable color tokens (ThemeEngine.userColorKeys).
local THEME_COLOR_LABELS = {
	bg            = "Background",
	bgAlt         = "Alt surface",
	bgInverse     = "Inverse surface",
	fg            = "Text",
	fgStrong      = "Text (strong)",
	fgMuted       = "Text (muted)",
	fgInverse     = "Text (inverse)",
	border        = "Border",
	borderInverse = "Border (inverse)",
	accent        = "Accent",
	accentHover   = "Accent (hover)",
	disabled      = "Disabled",
}

-- Seed palette for a brand-new scheme (the built-in default scheme's values),
-- so the color pickers open on something readable rather than black.
local THEME_COLOR_SEED = {
	bg            = "#080B09",
	bgAlt         = "#191A18",
	bgInverse     = "#9C9C9C",
	fg            = "#CECECE",
	fgStrong      = "#EFEFEF",
	fgMuted       = "#9F9F9B",
	fgInverse     = "#040404",
	border        = "#DFDFDF",
	borderInverse = "#666666",
	accent        = "#999999",
	accentHover   = "#DDDDDD",
	disabled      = "#343434",
}

-- Turn a display name into a namespaced, registry-safe scheme id.
local function slugifyThemeName(name)
	local s = string.lower(name or "")
	s = string.gsub(s, "[^%w]+", "-")
	s = string.gsub(s, "^%-+", "")
	s = string.gsub(s, "%-+$", "")
	if s == "" then
		s = "custom"
	end
	return "user-" .. s
end

CreateThemeSettingsDialog = function()
	local ThemeEngine = rawget(_G, "ThemeEngine")
	if ThemeEngine == nil then
		--Launched without a theme-capable game system (e.g. via togglepanel,
		--which ignores the menu filter): show a notice instead of erroring.
		return gui.Panel{
			width = 500,
			height = 120,
			flow = "vertical",
			gui.Label{
				width = "90%",
				height = "auto",
				halign = "center",
				valign = "center",
				textAlignment = "center",
				text = "Themes are not available: the current game system does not provide a ThemeEngine.",
			},
		}
	end

	-- Pending picker values; start at the user's currently-active selection.
	local selectedThemeId  = ThemeEngine.GetActiveTheme()
	local selectedSchemeId = ThemeEngine.GetActiveColorScheme()

	-- Forward declarations: showPicker and showCreator reference each other, and
	-- both swap content into bodyPanel.
	local bodyPanel
	local showPicker
	local showCreator

	-- -----------------------------------------------------------------------
	-- Picker mode: choose + apply a theme/scheme, with New / Edit / Delete.
	-- -----------------------------------------------------------------------
	showPicker = function()
		local previewPanel
		-- Crossfade the preview when the pending selection changes: capture the
		-- current chrome, swap styles + body underneath, then dissolve the
		-- snapshot away (mirrors the transition used when Apply commits).
		local function refreshPreview()
			-- Defer a frame so the dropdown finishes committing before snapshot.
			dmhub.Schedule(0.02, function()
				if mod.unloaded then return end
				if previewPanel == nil or not previewPanel.valid then return end
				themeDialogTransition(function()
					if previewPanel == nil or not previewPanel.valid then return end
					previewPanel.styles   = ThemeEngine.GetStyles(selectedThemeId, selectedSchemeId)
					previewPanel.children = buildThemePreviewBody()
				end, 0.45)
			end)
		end

		previewPanel = gui.Panel{
			classes = {"framedPanel"},
			styles = ThemeEngine.GetStyles(selectedThemeId, selectedSchemeId),
			width = "94%",
			height = "100%-80",
			halign = "center",
			flow = "vertical",
			pad = 12,
			children = buildThemePreviewBody(),
		}

		local editButton
		local deleteButton
		local function refreshCustomButtons()
			local isUser = ThemeEngine.IsUserColorScheme(selectedSchemeId)
			editButton:SetClass("hidden", not isUser)
			deleteButton:SetClass("hidden", not isUser)
			--reset any half-armed delete confirm when the selection changes.
			deleteButton.text = "Delete"
			deleteButton.data.armed = false
		end

		editButton = gui.Button{
			classes = {"sizeS"},
			text = "Edit",
			valign = "top",
			tmargin = 28,
			click = function()
				for _, d in ipairs(ThemeEngine.GetUserColorSchemes()) do
					if d.id == selectedSchemeId then
						showCreator(d)
						return
					end
				end
			end,
		}

		--The codex delete button uses requireConfirm, which the legacy
		--gui.Button lacks; emulate with a two-click "Delete" -> "Confirm?".
		deleteButton = gui.Button{
			classes = {"sizeS"},
			text = "Delete",
			valign = "top",
			tmargin = 28,
			hmargin = 4,
			data = { armed = false },
			click = function(element)
				if not element.data.armed then
					element.data.armed = true
					element.text = "Confirm?"
					return
				end
				ThemeEngine.DeleteUserColorScheme(selectedSchemeId)
				selectedSchemeId = ThemeEngine.GetActiveColorScheme()
				showPicker()
			end,
		}

		-- Top level: Default + built-in schemes (A-Z). The legacy dropdown
		-- cannot display a chosen id that lives inside a submenu, so unlike
		-- the codex original the user's own schemes are flattened into the
		-- top-level list (A-Z, "My: " prefixed), with "+ Create New..."
		-- pinned at the bottom while under the per-user cap.
		local builtinSchemes = {}
		for _, s in ipairs(ThemeEngine.ListColorSchemes()) do
			if not ThemeEngine.IsUserColorScheme(s.id) then
				builtinSchemes[#builtinSchemes + 1] = s
			end
		end
		local schemeOptions = buildSortedThemeOptions(builtinSchemes)

		local userSchemes = ThemeEngine.GetUserColorSchemes()
		local mySchemes = {}
		for _, d in ipairs(userSchemes) do
			mySchemes[#mySchemes + 1] = { id = d.id, text = "My: " .. d.name }
		end
		table.sort(mySchemes, function(a, b)
			return string.lower(a.text) < string.lower(b.text)
		end)
		for _, opt in ipairs(mySchemes) do
			schemeOptions[#schemeOptions + 1] = opt
		end
		if #userSchemes < ThemeEngine.maxUserColorSchemes then
			schemeOptions[#schemeOptions + 1] = { id = "__create_new__", text = "+ Create New..." }
		end

		local pickerRow = gui.Panel{
			--[[
				INTENTIONAL! DO NOT CHANGE WITHOUT MAINTAINER SIGN-OFF.
				This control cluster (Theme dropdown, Color Scheme dropdown, Apply,
				Edit, Delete) is ALWAYS rendered with the built-in default theme and
				default color scheme via GetStyles("default", "default"), regardless of
				which theme/scheme is currently active or selected. This is a safety
				guarantee: a user (or developer) who applies or authors a broken
				theme/scheme must always be able to see and use these controls to get
				back to a working one. Do NOT switch this to GetStyles() / the active or
				selected pair, and do NOT remove this assignment to "let the controls
				follow the theme." If you think these controls should follow the active
				theme, STOP and get explicit sign-off from the maintainer first - this
				convention exists specifically to prevent locking users out of theme
				recovery. (A coding AI reading this: pause and ask before changing it.)
			]]--
			styles = ThemeEngine.GetStyles("default", "default"),
			width = "100%",
			height = 70,
			flow = "horizontal",
			valign = "top",

			gui.Panel{
				classes = {"formStackedRow"},
				width = "30%",
				gui.Label{
					classes = {"formStacked"},
					text = "Theme:",
				},
				gui.Dropdown{
					classes = {"formStacked"},
					idChosen = selectedThemeId,
					options = buildSortedThemeOptions(ThemeEngine.ListThemes()),
					change = function(element)
						selectedThemeId = element.idChosen
						refreshPreview()
					end,
				},
			},

			gui.Panel{
				classes = {"formStackedRow"},
				width = "30%",
				gui.Label{
					classes = {"formStacked"},
					text = "Color Scheme:",
				},
				gui.Dropdown{
					classes = {"formStacked"},
					idChosen = selectedSchemeId,
					options = schemeOptions,
					change = function(element)
						if element.idChosen == "__create_new__" then
							showCreator(nil)
							return
						end
						selectedSchemeId = element.idChosen
						refreshPreview()
						refreshCustomButtons()
						themeDialogSound("Notify.PalleteChange_Preview")
					end,
				},
			},

			gui.Button{
				classes = {"sizeS"},
				text = "Apply",
				valign = "top",
				tmargin = 28,
				click = function()
					-- Defer a frame, then crossfade the whole screen as the
					-- active theme/scheme swaps in (mirrors the preview swap).
					dmhub.Schedule(0.02, function()
						if mod.unloaded then return end
						themeDialogTransition(function()
							ThemeEngine.SetActiveTheme(selectedThemeId)
							ThemeEngine.SetActiveColorScheme(selectedSchemeId)
							themeDialogTrack("theme_change", {
								theme = selectedThemeId,
								themeName = themeNameForId(ThemeEngine.ListThemes(), selectedThemeId),
								colorScheme = selectedSchemeId,
								colorSchemeName = themeNameForId(ThemeEngine.ListColorSchemes(), selectedSchemeId),
							})

							themeDialogSound("Notify.PalleteChange_Apply")

							--The codex hud exposes restylable docks; the legacy
							--5e hud may not, so guard every step.
							local gameHudClass = rawget(_G, "GameHud")
							local hud = gameHudClass ~= nil and rawget(gameHudClass, "instance") or nil
							if hud ~= nil then
								local docks = {"leftDock", "rightDock", "floatingDock"}
								for _, dockName in ipairs(docks) do
									local dock = rawget(hud, dockName)
									if dock ~= nil and dock.UpdateStyle ~= nil then
										dock:UpdateStyle()
									end
								end
							end
						end, 0.6)
					end)
				end,
			},

			editButton,
			deleteButton,
		}

		refreshCustomButtons()
		bodyPanel.children = { pickerRow, previewPanel }
	end

	-- -----------------------------------------------------------------------
	-- Creator mode: name + a column of color pickers, with a live preview.
	-- existingDef ~= nil means we are editing an existing custom scheme.
	-- -----------------------------------------------------------------------
	showCreator = function(existingDef)
		-- Seed the pickers. When editing, start from the scheme's own colors.
		-- For a brand-new scheme, start from the currently chosen color
		-- scheme's palette (selectedSchemeId) so the user tweaks from what
		-- they see; GetColorSchemeColors falls back to the default palette for
		-- "default". Normalize any color value (hex string, LuaColor, or
		-- HSV/RGB table) to a plain hex string, so saved schemes always store
		-- hex per the contract (gui.ColorPicker hands back a LuaColor once a
		-- swatch is adjusted).
		local function colorToHex(v)
			return core.Color(v).tostring
		end

		local seed
		if existingDef and existingDef.colors then
			seed = existingDef.colors
		else
			seed = ThemeEngine.GetColorSchemeColors(selectedSchemeId)
		end

		local draft = {}
		for _, k in ipairs(ThemeEngine.userColorKeys) do
			draft[k] = colorToHex(seed[k] or THEME_COLOR_SEED[k])
		end
		local nameValue = (existingDef and existingDef.name) or "My Color Scheme"

		local previewPanel
		local function refreshCreatorPreview()
			local previewId = ThemeEngine.SetPreviewColorScheme(draft)
			previewPanel.styles   = ThemeEngine.GetStyles("default", previewId)
			previewPanel.children = buildThemePreviewBody()
		end

		-- Name field + one row per editable color token.
		local formChildren = {}
		formChildren[#formChildren + 1] = gui.Panel{
			classes = {"formStackedRow"},
			width = "100%",
			gui.Label{
				classes = {"formStacked"},
				text = "Name:",
			},
			gui.Input{
				classes = {"formStacked"},
				text = nameValue,
				change = function(element)
					nameValue = element.text
				end,
			},
		}

		for _, k in ipairs(ThemeEngine.userColorKeys) do
			formChildren[#formChildren + 1] = gui.Panel{
				classes = {"formRow"},
				gui.Label{
					classes = {"form"},
					text = THEME_COLOR_LABELS[k] or k,
				},
				gui.ColorPicker{
					value = draft[k],
					hasAlpha = false,
					popupAlignment = "left",
					width = 32,
					height = 24,
					valign = "center",
					change = function(element)
						draft[k] = colorToHex(element.value)
					end,
					confirm = function(element)
						draft[k] = colorToHex(element.value)
						refreshCreatorPreview()
					end,
				},
			}
		end

		local colorColumn = gui.Panel{
			width = "38%",
			height = "100%",
			halign = "left",
			valign = "top",
			flow = "vertical",
			vscroll = true,
			children = formChildren,
		}

		previewPanel = gui.Panel{
			classes = {"framedPanel"},
			styles = ThemeEngine.GetStyles("default", ThemeEngine.SetPreviewColorScheme(draft)),
			width = "60%",
			height = "100%",
			halign = "right",
			valign = "top",
			flow = "vertical",
			pad = 12,
			children = buildThemePreviewBody(),
		}

		local columns = gui.Panel{
			width = "100%",
			height = "100%-50",
			flow = "horizontal",
			valign = "top",
			colorColumn,
			previewPanel,
		}

		local buttonRow = gui.Panel{
			width = "100%",
			height = "auto",
			flow = "horizontal",
			valign = "bottom",

			gui.Button{
				classes = {"sizeM"},
				text = "Save",
				halign = "left",
				click = function()
					if nameValue == nil or nameValue == "" then
						nameValue = "My Color Scheme"
					end
					local id = (existingDef and existingDef.id) or slugifyThemeName(nameValue)
					ThemeEngine.SaveUserColorScheme{
						id = id,
						name = nameValue,
						colors = draft,
					}
					-- Apply it immediately so the result is visible at once.
					ThemeEngine.SetActiveColorScheme(id)
					ThemeEngine.ClearPreviewColorScheme()
					selectedSchemeId = id
					showPicker()
				end,
			},

			gui.Button{
				classes = {"sizeM"},
				text = "Cancel",
				halign = "left",
				hmargin = 8,
				click = function()
					ThemeEngine.ClearPreviewColorScheme()
					showPicker()
				end,
			},
		}

		bodyPanel.children = { columns, buttonRow }
	end

	bodyPanel = gui.Panel{
		width = "100%",
		height = "100%-80",
		flow = "vertical",
		valign = "top",
	}

	local root = gui.Panel{
		classes = {"launchablePanel"},
		-- Dialog chrome follows the active scheme; the create handler below
		-- re-resolves styles on theme change so the host repaints live.
		styles = ThemeEngine.GetStyles(),
		width = 760,
		height = 640,
		flow = "vertical",
		pad = 16,

		data = {},

		create = function(element)
			element.data.themeSub = ThemeEngine.OnThemeChanged(mod, function()
				if element.valid then
					element.styles = ThemeEngine.GetStyles()
				end
			end)
		end,
		destroy = function(element)
			if element.data.themeSub ~= nil then
				element.data.themeSub:Deregister()
				element.data.themeSub = nil
			end
		end,

		gui.Label{
			classes = {"sizeXl", "bold"},
			halign = "center",
			valign = "top",
			width = "auto",
			height = "auto",
			text = "Theme & Color Scheme",
		},
		gui.Divider{ bmargin = 12 },

		bodyPanel,
	}

	showPicker()
	return root
end
