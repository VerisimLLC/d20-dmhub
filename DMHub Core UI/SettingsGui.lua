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

--Settings the 0.7xx engine reads unconditionally but which are registered by
--newer companion modules this game system does not include. Defaults match
--the values those modules use.
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

--Brush radii read by the engine's brushRadius property while map editing
--tools are active. Registered without editors; the editing UI adjusts them.
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

--Read by the roll dialog's DM preroll checkbox; was never registered anywhere,
--so old engines silently returned nil. Registered here so the value persists.
setting{
	id = "preroll",
	default = false,
	storage = "preference",
}
