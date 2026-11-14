local mod = dmhub.GetModLoading()

--A RollCheck instance has the following fields:
-- type = "attribute"/"save"/"skill"/"initiative"/"flat"/"table"/"custom"
-- id = the attribute, save, or skill being tested
-- tableRef = a RollTableReference if type is "table".
-- info = (optional) a table of additional information about the roll.
-- dc = (optional) the dc to meet on the check
-- roll = (optional) the actual roll to make. Only valid if "custom" is the type of roll.
-- text = a textual description.
-- explanation = (optional) an explanation of why the roll is taking place.
-- consequences = (optional) a description to the requester of the roll of consequences based on the roll.
-- options = (optional) a table of options. All optional.
--           casterid: ID of the character requiring this roll.
--           nocover: if true, cover can't benefit this check.
--           magic: if present and true, this is a magical effect.
--           condition: if present, the id of a condition that is being tested. Can use "concentration" for concentration checks.
--           specializations: if present, a {k -> true} map of specialization ID's for this check.
--           forcedmodifiers: if present, forces a list of modifiers on character for roll 
RegisterGameType("RollCheck")

--A RollRequest instance has the following fields:
-- checks = a list of RollChecks that the token can choose from. Most often this will just have one option.
-- tokens = map of token id -> result table. Result table begins empty and is filled by the target. May have a checks list which is a list of indexes into checks that are available to this token.
-- contest = (optional) if true this is a contested roll between the tokens. The tokens map will have a "team" identifier to signal which side of the contest they are on.
RegisterGameType("RollRequest")

RollCheck.consequences = ''
RollCheck.explanation = ''

RollRequest.contest = false

RollCheck.customChecks = {}

--register a custom check. options = {
--	id = string,
--	Describe = function(RollCheck, bool isplayer),
--	GetRoll = function(RollCheck, creature),
--	GetModifiers = (optional) function(RollCheck, creature),
--	ShowDialog = (optional) function(RollCheck, dialogOptions)
--}
function RollCheck.RegisterCustom(options)
	RollCheck.customChecks[options.id] = options
end

function RollCheck:CustomInfo()
	return RollCheck.customChecks[self.id]
end

function RollRequest:GetTokenOutcome(tokenid, checkNumber)
	local tokenInfo = self.tokens[tokenid]
	if tokenInfo == nil then
		return nil
	end

	return tokenInfo.outcome
end

function RollRequest:GetTokenResult(tokenid, checkNumber)
	local tokenInfo = self.tokens[tokenid]
	if tokenInfo == nil then
		return nil
	end

	if tokenInfo.forcedResult ~= nil then
		return tokenInfo.forcedResult
	end

	if tokenInfo.result == nil then
		return nil
	end

	return tokenInfo.result >= self.checks[checkNumber or 1].dc
end


function RollRequest:Describe(isplayer)
	return self.checks[1]:Describe(isplayer)
end

function RollCheck:Describe(isplayer)
	local dc = ""
	if (not isplayer) and self:has_key('dc') then
		dc = string.format("DC %d ", self.dc)
	end

	if self:CustomInfo() ~= nil then
		return self:CustomInfo().Describe(self, isplayer)
	end
	
	if self.type == "attribute" then
		return string.format("%s%s check", dc, self.text)
	elseif self.type == "save" then
		local conditionStr = ""
		local options = self:try_get("options", {})
		if options.condition then
			local conditionsTable = dmhub.GetTable(CharacterCondition.tableName)
			local condition = conditionsTable[options.condition]
			if condition ~= nil then
				conditionStr = string.format(" against %s", condition.name)
			end
		end
		return string.format("%s%s save%s", dc, self.text, conditionStr)
	elseif self.type == "initiative" then
		return "Roll for Initiative"
	elseif self.type == "flat" then
		return "Flat Check"
	elseif self.type == "table" then
		return "Roll on Table"
	elseif self.type == "custom" then
		return self:try_get("text", "Custom Roll")
	else
		local specializationText = ""
		if self:has_key("options") and self.options.specializations ~= nil then
			local skillsTable = dmhub.GetTable(Skill.tableName)
			local skill = skillsTable[self.id]
			if skill ~= nil then
				for k,_ in pairs(self.options.specializations) do
					local s = Skill.GetSpecializationById(skill, k)
					if s ~= nil then
						if specializationText ~= "" then
							specializationText = specializationText .. ", "
						end
						specializationText = specializationText .. s.text
					end
				end
			end
		end

		if specializationText ~= "" then
			specializationText = string.format(" (%s)", specializationText)
		end

		return string.format("%s%s%s check", dc, self.text, specializationText)
	end
end

function RollCheck:GetRoll(creature)
	if self:CustomInfo() ~= nil then
		return self:CustomInfo().GetRoll(self, creature)
	end

	if self.type == "attribute" then
		return string.format("%s+%d", GameSystem.BaseSkillRoll, creature:AttributeMod(self.id))
	elseif self.type == "save" then
		return string.format("%s+%d", GameSystem.BaseSavingThrowRoll, creature:SavingThrowMod(self.id))
	elseif self.type == "initiative" then
		return string.format("%s+%d", GameSystem.BaseInitiativeRoll, creature:InitiativeBonus())
	elseif self.type == "flat" then
		return GameSystem.FlatRoll
	elseif self.type == "table" then
		if self:has_key("tableRef") == false then
			return "1d100"
		end

		local rollInfo = self.tableRef:GetTable():CalculateRollInfo()
		if rollInfo == nil then
			return "1d100"
		end
		return rollInfo.roll
	elseif self.type == "custom" then
		return self:try_get("roll", "1d6")
	else
		return string.format("%s+%d", GameSystem.BaseSkillRoll, creature:SkillMod(Skill.SkillsById[self.id]))
	end
end

function RollCheck:GetModifiers(creature)
	if self:CustomInfo() ~= nil then
		if self:CustomInfo().GetModifiers then
			return self:CustomInfo().GetModifiers(self, creature)
		else
			return {}
		end
	end

	if self.type == "attribute" then
		return creature:GetModifiersForAttributeRoll(self.id)
	elseif self.type == "save" then
		return creature:GetModifiersForSavingThrowRoll(self.id, self:try_get("options"))
	elseif self.type == "initiative" then
		return creature:GetModifiersForD20Roll('initiative', {})
	elseif self.type == "table" then
		return {}
	elseif self.type == "flat" then
		return {}
	elseif self.type == "custom" then
		return {}
	else
		return creature:GetModifiersForSkillCheckRoll(Skill.SkillsById[self.id], self:try_get("options"))
	end
	
end

local initiativeChecks = {
	{
		type = 'initiative',
		id = 'initiative',
		text = 'Initiative',
	}
}

local g_tableGroupSetting = setting{
	id = "rollTableGroup",
	text = "Table Group",
	default = "lootTables",
	storage = "preference",
}

--called by skills once the skills are loaded.
function RollCheck.LoadSkills()

	local attributeRollChecks = {}
	local saveChecks = {}

	for i,attr in ipairs(creature.attributeIds) do
		local info = creature.attributesInfo[attr]
		attributeRollChecks[#attributeRollChecks+1] = {
			type = 'attribute',
			id = info.id,
			text = info.description,
		}
	end

	for key,info in pairs(creature.savingThrowInfo) do
		saveChecks[#saveChecks+1] = {
			type = 'save',
			id = key,
			text = info.description,
			order = info.order,
		}
	end

	table.sort(saveChecks, function(a,b) return a.order < b.order end)

	local skillRollChecks = {}
	for i,skillInfo in ipairs(Skill.SkillsInfo) do
		skillRollChecks[#skillRollChecks+1] = {
			type = 'skill',
			id = skillInfo.id,
			text = skillInfo.name,
			specializations = Skill.GetSpecializations(skillInfo),
		}
	end

	local tableGroups = {}
	local tableChecks = {}
	for tableid,info in pairs(Compendium.rollableTables) do
		tableGroups[#tableGroups+1] = {
			id = tableid,
			text = info.text,
		}
		local t = dmhub.GetTable(tableid) or {}
		for k,v in pairs(t) do
			if not v:try_get("hidden", false) then
				tableChecks[#tableChecks+1] = {
					type = 'table',
					id = tableid,
					group = tableid,
					tableRef = RollTableReference.CreateRef(tableid, k),
					text = v.name,
				}
			end
		end
	end

	table.sort(tableGroups, function(a,b) return a.text < b.text end)
	print("TABLE CHECKS::", json(tableChecks))
	print("TABLE CHECKS:: GROUPS", json(tableGroups))

	RollCheck.Checks = {
		{
			name = 'Attribute',
			checks = attributeRollChecks,
		},
		{
			name = 'Skill',
			checks = skillRollChecks,
		},
		{
			name = 'Save',
			checks = saveChecks,
		},
		{
			name = 'Initiative',
			checks = initiativeChecks,
		},
		{
			name = 'Table',
			group = g_tableGroupSetting,
			groups = tableGroups,
			checks = tableChecks,
		},
	}
end


--this is a hidden panel which just listens for required rolls.
function GameHud:RequireRollListenerPanel()

	local autoRollId = nil
	local autoCancelId = nil

	--tracks the ID of the roll dialog we are showing. This way we can cancel that dialog
	--if needed due to the roll request being retracted.
	local showingRollId = nil
	local rollRequestId = nil

	--track rolls we currently have ongoing
	local currentRolls = {}

	local resultPanel = gui.Panel{
		floating = true,
		width = 0,
		height = 0,

		monitorGame = "/actionRequests",

		refreshGame = function(element)
			if self.rollDialog.data.IsShown() then
				if showingRollId == gamehud.rollDialog.data.rollid then
					--we requested the current roll dialog that is shown. See if our reason
					--for doing so has been canceled, in which case we want to close that dialog.
					if dmhub.GetPlayerActionRequest(rollRequestId) == nil then
						self.rollDialog.data.Cancel()
					end
				end

				--we are currently blocked by the roll dialog. Try again in a little while.
				element:ScheduleEvent("refreshGame", 0.2)

				return
			end

			local requests = dmhub.GetPlayerActionRequests()
			for k,request in pairs(requests) do
				if request.info.typeName == 'RestRequest' then
					--request for resting, see if we want to handle it and if we do go over to that.
					if self:TryHandleRestRequest(k, request) then
						return
					end

				elseif request.info.typeName == 'RollRequest' then
					local numPrompts = 0

					local havePlayersOnline = false
					if #dmhub.users > 1 then
						for _,userid in ipairs(dmhub.users) do
							local session = dmhub.GetSessionInfo(userid)
							if session ~= nil and session.dm == false and session.loggedOut == false then
								havePlayersOnline = true
							end
						end
					end

					for tokid_tmp,info_tmp in pairs(request.info.tokens) do
						local tokid = tokid_tmp
						local info = info_tmp
						if info.status == nil then
							local tok = dmhub.GetTokenById(tokid)
							local rollid = k .. tokid
							if tok ~= nil and tok.properties and ((info.forceuserid == nil and tok.canControl and (dmhub.isDM == false or tok.playerControlled == false or not havePlayersOnline)) or info.forceuserid == dmhub.loginUserid) and not currentRolls[rollid] then
								numPrompts = numPrompts+1
							end
						end
					end


					for tokid_tmp,info_tmp in pairs(request.info.tokens) do
						local tokid = tokid_tmp
						local info = info_tmp
						if info.status == nil then
							local tok = dmhub.GetTokenById(tokid)
							local rollid = k .. tokid
							if tok ~= nil and tok.properties and ((info.forceuserid == nil and tok.canControl and (dmhub.isDM == false or tok.playerControlled == false or not havePlayersOnline)) or info.forceuserid == dmhub.loginUserid) and not currentRolls[rollid] then

								local checks = {}

								for index,c in ipairs(request.info.checks) do
									local canUseThisCheck = true
									if info.checks ~= nil then
										canUseThisCheck = false
										for _,checkIndex in ipairs(info.checks) do
											if checkIndex == index then
												canUseThisCheck = true
											end
										end
									end

									if canUseThisCheck then
										checks[#checks+1] = c
									end
								end

								local rollProperties = nil

								local ShowPromptDialog
								ShowPromptDialog = function(checkIndex, nofadein)
									local check = checks[checkIndex]

									--build a list of alternate options.
									local alternateOptions = {}
									for _,c in ipairs(checks) do
										alternateOptions[#alternateOptions+1] = {
											text = c.text,
										}
									end
									
									if check:has_key("tableRef") then
										rollProperties = RollProperties.new{}
										rollProperties.tableRef = check.tableRef
									elseif check:has_key('dc') then
										rollProperties = GameSystem.GetRollProperties(check.type, check.dc)

										if check.type == "save" then
											rollProperties.displayType = "save"
										end
									end

									local autoroll = nil
									if autoRollId == k then
										autoroll = true
										if autoCancelId == k then
											autoroll = "cancel"
										end
									elseif dmhub.isDM and tok.playerControlled == false then
										if check.type == "save" then
											autoroll = {
												id = "monsterSaves",
												text = "monster saves",
											}
											dmhub.Debug("AUTOROLL SAVE")
										end
									end

									local rollType = "d20"
									if check.type == "table" then
										rollType = "table"
									elseif check:CustomInfo() ~= nil then
										rollType = check:CustomInfo().rollType or rollType
									end

									local rollAllPromptsSet = false

									currentRolls[rollid] = true

									rollRequestId = k

									local dialogParams = {
										title = string.format("%s for %s", check:Describe(not dmhub.isDM), tok.description),
										description = check:Describe(not dmhub.isDM),
										explanation = check.explanation,
										roll = check:GetRoll(tok.properties),
										modifiers = check:GetModifiers(tok.properties),
										rollProperties = rollProperties,
										creature = tok.properties,
										tableRef = check:try_get("tableRef"),
										type = rollType,
										subtype = check.type,
										nofadein = nofadein,

										alternateOptions = alternateOptions,
										alternateChosen = checkIndex,
										chooseAlternate = function(alternateIndex)
											ShowPromptDialog(alternateIndex, true)
										end,

										numPrompts = numPrompts,
										rollAllPrompts = function()
											rollAllPromptsSet = true
											autoRollId = k
											dmhub.Debug("ROLL:: ALL PROMPTS")
										end,
										autoroll = autoroll,
										beginRoll = function()
											local req = dmhub.GetPlayerActionRequest(k)
											if req ~= nil and req.info.tokens[tokid] ~= nil then
												req:BeginChanges()
												req.info.tokens[tokid].status = 'rolling'
												req:CompleteChanges("Begin roll")
											end
										end,
										completeRoll = function(rollInfo)
											local req = dmhub.GetPlayerActionRequest(k)
											if req ~= nil and req.info.tokens[tokid] ~= nil then
												req:BeginChanges()
												req.info.tokens[tokid].status = 'complete'
												req.info.tokens[tokid].result = rollInfo.total
												req.info.tokens[tokid].boons = rollInfo.boons
												req.info.tokens[tokid].banes = rollInfo.banes

												if rollInfo.forcedResult then
													req.info.tokens[tokid].forcedResult = rollInfo.autosuccess
												end
												
												if rollInfo.properties then
													local matchingOutcome = rollInfo.properties:GetOutcome(rollInfo)
													if matchingOutcome then
														req.info.tokens[tokid].outcome = matchingOutcome
													end
												end

												req:CompleteChanges("Complete roll")


												if check.type == "initiative" then
													creature.CompleteInitiative(tok.properties, rollInfo)
												end


											end

											currentRolls[rollid] = nil
										end,
										cancelRoll = function()
											if rollAllPromptsSet then
												autoCancelId = k
											end

											local req = dmhub.GetPlayerActionRequest(k)
											if req ~= nil and req.info.tokens[tokid] ~= nil then
												req:BeginChanges()
												req.info.tokens[tokid].status = 'cancel'
												req:CompleteChanges("Cancel roll dialog")
											end

											currentRolls[rollid] = nil
										end,
									}

									if check:CustomInfo() ~= nil and check:CustomInfo().ShowDialog ~= nil then
										showingRollId = check:CustomInfo().ShowDialog(check, dialogParams)
									else
										showingRollId = gamehud.rollDialog.data.ShowDialog(dialogParams)
									end
								end

								ShowPromptDialog(1)

								--if we didn't kick off an auto roll set us to dialog status now.
								request = dmhub.GetPlayerActionRequest(k)
								if request.info.tokens[tokid].status == nil then
									request:BeginChanges()
									request.info.tokens[tokid].status = 'dialog'
									request.info.tokens[tokid].userid = dmhub.userid
									request:CompleteChanges("Show roll dialog")
								end

								return
							end
						end
					end
				end
			end
		end,
	}

	return resultPanel
end

local g_requireRollDialog = nil

local function CloseRequireRollDialog()
	if g_requireRollDialog ~= nil then
		g_requireRollDialog.parent:FireEvent("close")
	end
end

function GameHud:CreatePartyTokenPoolSelector(args)
	local initiative = args.initiative
	args.initiative = nil
	local resultPanel
	local tokenPanels = {}

	local selection = args.selection
	args.selection = nil

	local GetSelectedTokens = function()
		local result = {}
		for i,panel in ipairs(tokenPanels) do
			if panel:HasClass('selected') then
				result[#result+1] = panel.data.token.id
			end
		end
		return result
	end


	local candidateTokens = dmhub.GetTokens{ playerControlled = true, haveProperties = true }

	local selectedTokens = dmhub.selectedTokens
	for _,tok in ipairs(selectedTokens) do
		local found = false
		for _,existing in ipairs(candidateTokens) do
			if existing == tok then
				found = true
			end

			--for initiative, don't duplicate monsters of the same type.
			if initiative and InitiativeQueue.GetInitiativeId(tok) == InitiativeQueue.GetInitiativeId(existing) then
				found = true
			end
		end

		if not found then
			candidateTokens[#candidateTokens+1] = tok
		end
	end

	local CreateTokenPanel = function(token)

		return gui.Panel{
			bgimage = 'panels/square.png',
			classes = 'token-panel',
			data = {
				token = token,
			},

			gui.CreateTokenImage(token),

			press = function(element)
				element:SetClass('selected', not element:HasClass('selected'))
				resultPanel:FireEventTree('changeSelection', GetSelectedTokens())
			end,
		}

	end

	local startingSelection = {}

	for i,tok in ipairs(candidateTokens) do
		tokenPanels[#tokenPanels+1] = CreateTokenPanel(tok)
		for i,selectedTok in ipairs(selectedTokens) do
			if selectedTok == tok then
				startingSelection[#startingSelection+1] = tokenPanels[#tokenPanels]
			end
		end
	end

	local tokenPool = gui.Panel{
		bgimage = 'panels/square.png',
		bgcolor = 'black',
		cornerRadius = 8,
		border = 2,
		borderColor = '#888888',
		width = 210,
		height = 210,
		pad = 4,
		vscroll = true,
		vmargin = 8,
		flow = 'horizontal',
		wrap = true,

		styles = {
			{
				classes = {'token-panel'},
				bgcolor = 'black',
				cornerRadius = 8,
				width = 64,
				height = 64,
				halign = 'left',
			},
			{
				classes = {'token-panel', 'hover'},
				borderColor = 'grey',
				borderWidth = 2,
				bgcolor = '#441111',
			},
			{
				classes = {'token-panel', 'selected'},
				borderColor = 'white',
				borderWidth = 2,
				bgcolor = '#882222',
			},

		},

		children = tokenPanels
	}

	local tokenPoolSelection = gui.Panel{
		flow = 'horizontal',
		halign = 'center',
		width = 'auto',
		height = 'auto',

		styles = {
			{
				classes = {'token-pool-shortcut'},
				color = '#aaaaaa',
				fontSize = 16,
				width = 'auto',
				height = 'auto',
				valign = 'center',
				halign = 'center',
			},
			{
				classes = {'token-pool-shortcut', 'hover'},
				color = 'white',
			},
			{
				classes = {'shortcut-divider'},
				bgimage = 'panels/square.png',
				halign = 'center',
				valign = 'center',
				margin = 4,
				width = 2,
				height = 16,
				bgcolor = '#aaaaaa',
			},

		},

		gui.Label{
			classes = 'token-pool-shortcut',
			text = 'All',
			create = function(element)
				if selection == 'All' then
					element:FireEvent("click")
				else
					element:FireEvent("selectStarting")
				end
			end,
			click = function(element)
				for i,tokenPanel in ipairs(tokenPanels) do
					tokenPanel:SetClass('selected', true)
				end
				resultPanel:FireEventTree('changeSelection', GetSelectedTokens())
			end,
			selectStarting = function(element)
				for i,tokenPanel in ipairs(startingSelection) do
					tokenPanel:SetClass('selected', true)
				end
				resultPanel:FireEventTree('changeSelection', GetSelectedTokens())
			end,
		},
		gui.Panel{
			classes = {'shortcut-divider'},
		},
		gui.Label{
			classes = 'token-pool-shortcut',
			text = 'Party',
			create = function(element)
				if selection == 'Party' then
					element:FireEvent("click")
				end
			end,
			click = function(element)
				for i,tokenPanel in ipairs(tokenPanels) do
					tokenPanel:SetClass('selected', tokenPanel.data.token.valid and tokenPanel.data.token.playerControlledNotShared and tokenPanel.data.token.properties ~= nil and tokenPanel.data.token.properties.typeName == 'character')
				end
				resultPanel:FireEventTree('changeSelection', GetSelectedTokens())
			end,
		},
		gui.Panel{
			classes = {'shortcut-divider'},
		},
		gui.Label{
			classes = 'token-pool-shortcut',
			text = 'None',
			click = function(element)
				for i,tokenPanel in ipairs(tokenPanels) do
					tokenPanel:SetClass('selected', false)
				end
				resultPanel:FireEventTree('changeSelection', GetSelectedTokens())
			end,
		},
	}

	local options = {
		width = 'auto',
		height = 'auto',
		flow = "vertical",

		tokenPool,
		tokenPoolSelection,
	}

	for k,v in pairs(args) do
		options[k] = v
	end

	resultPanel = gui.Panel(options)

	return resultPanel
end

function ShowRequireRollDialog(args)

	args = args or {}
	
	local tokenIdsSelected = {}

	local checkSelectedIndex = -1
	local checkTypeIndex = 1
	local checkTypeName = ''
	local checkTypeIndexes = {checkTypeIndex} --the actual multi-selection of which items we have selected.

	local specializationChecks = {}

	local CreateRollTypeOption = function(options)
		return gui.Label{
			classes = {'roll-type-option', cond(options.selected, 'selected', nil)},
			bgimage = 'panels/square.png',
			text = options.text,
			press = function(element)
				local siblings = element.parent:GetChildrenWithClass('roll-type-option')
				for i,item in ipairs(siblings) do
					item:SetClass('selected', item == element)
				end

				checkSelectedIndex = options.index
				g_requireRollDialog:FireEventTree('refreshDiceCheck')
			end,
		}
	end

	local dcInput = gui.Input{
		placeholderText = 'Enter DC...',
		text = "",
	}

	local rollTypes = {}

	for i,check in ipairs(RollCheck.Checks) do
		if args.checkType == nil or args.checkType == check.name then
			if checkSelectedIndex == -1 then
				checkSelectedIndex = i
			end
			if #rollTypes ~= 0 then

				rollTypes[#rollTypes+1] = gui.Panel{
					bgimage = 'panels/square.png',
					bgcolor = '#aaaaaa',
					hmargin = 8,
					width = 2,
					height = 20,
					valign = 'center',
					halign = 'center',
				}
			end
			rollTypes[#rollTypes+1] = CreateRollTypeOption{ index = i, text = check.name, selected = (i == checkSelectedIndex) }
		end
	end

	dmhub.Debug(string.format("CREATE REQUIRE ROLLS: %s", json(g_requireRollDialog ~= nil)))

	g_requireRollDialog = gui.Panel{
		id = 'require-roll-dialog',

		destroy = function(element)
			if g_requireRollDialog == element then
				g_requireRollDialog = nil
			end
		end,

		styles = {
			{
				classes = {'formLabel'},
				fontSize = 18,
				color = 'white',
				width = 'auto',
				height = 'auto',
			},

			{
				classes = {'input'},
				width = 140,
				height = 20,
				fontSize = 18,
			},

			{
				classes = {'check-summary'},
				width = '100%',
				height = 80,
				valign = 'top',
				textAlignment = 'center',
				fontSize = 28,
				color = 'white',
			},

			{
				classes = {'result-panel'},
				flow = "horizontal",
				width = "100%",
				height = 70,
				valign = 'top',
			},

			{
				classes = {'result-panel-scroll'},
				width = '94%',
				height = 340,
				valign = 'center',
				flow = 'vertical',
			},

			{
				classes = {'result-status-label'},
				fontSize = 18,
				color = 'white',
				width = 80,
				textAlignment = 'left',
				height = 'auto',
				halign = 'left',
				valign = 'center',
			},
			{
				classes = {'result-outcome-label'},
				fontSize = 14,
				color = 'white',
				width = 100,
				textAlignment = 'left',
				height = 'auto',
				halign = 'left',
				valign = 'center',
			},
			{
				classes = {'result-consequences-table'},
				width = 140,
				flow = "vertical",
				height = "auto",
				valign = "center",
			},
			{
				classes = {'consequenceLabel'},
				width = 140,
				fontSize = 14,
				color = 'red',
				height = "auto",
			},
			{
				classes = {'consequenceLabel', 'avoided'},
				color = 'grey',
			},
		},

		halign = 'center',
		valign = 'center',

		width = 760,
		height = 600,

		flow = 'vertical',
		
		gui.Panel{
			id = 'roll-type-panel',
			flow = 'horizontal',
			halign = 'center',
			valign = 'top',
			vmargin = 6,
			flow = 'horizontal',
			width = 'auto',
			height = 'auto',

			styles = {
				{
					classes = 'roll-type-option',
					fontSize = 24,
					width = 'auto',
					height = 'auto',
					color = '#aaaaaa',
					bgcolor = 'clear',
				},
				{
					classes = {'roll-type-option', 'hover'},
					color = '#ffffff',
					transitionTime = 0.1,
				},
				{
					classes = {'roll-type-option', 'selected'},
					color = '#ffffff',
					border = { x1 = 0, x2 = 0, y2 = 0, y1 = 2 },
					borderColor = '#ffffff',
					transitionTime = 0.2,
				},
			},

			children = rollTypes,
		},

		gui.Panel{
			id = 'main-check-panel',
			flow = 'horizontal',

			vmargin = 10,
			width = '90%',
			height = '85%',
			halign = 'center',
			valign = 'top',

			gui.Panel{
				height = "100%",
				width = 200,
				pad = 4,
				halign = "left",
				flow = "vertical",

				gui.Panel{
					width = "auto",
					height = "auto",
					classes = {"collapsed"},
					refreshDiceCheck = function(element)
						local checkInfo = RollCheck.Checks[checkSelectedIndex]
						if checkInfo.group == nil then
							element:SetClass("collapsed", true)
							return
						end

						element:SetClass("collapsed", false)

						element.children = {
							gui.Dropdown{
								options = checkInfo.groups,
								idChosen = checkInfo.group:Get(),
								width = 160,
								change = function(element)
									checkInfo.group:Set(element.idChosen)
									g_requireRollDialog:FireEventTree('refreshDiceCheck')
								end,
							}
						}

					end,
				},

				gui.Panel{
					id = 'check-type-list',
					height = '100% available',
					width = 210,
					flow = 'vertical',
					vscroll = true,
					styles = {
						{
							classes = 'check-type-item',
							bgimage = 'panels/square.png',
							bgcolor = 'clear',
							fontSize = 16,
							minFontSize = 12,
							textAlignment = 'left',
							hpad = 3,
							halign = 'left',
							valign = 'top',
							width = 200,
							minHeight = 22,
							height = "auto",
						},
						{
							classes = {'check-type-item', 'selected'},
							bgcolor = '#660000',
						},
						{
							classes = {'check-type-item', 'hover'},
							bgcolor = '#660000',
						},
					},
					

					refreshDiceCheck = function(element)
						local children = {}

						local checkInfo = RollCheck.Checks[checkSelectedIndex]

						if #checkInfo.checks > 0 and (checkTypeIndex > #checkInfo.checks or checkInfo.checks[checkTypeIndex].text ~= checkTypeName) then
							checkTypeIndex = 1
							checkTypeName = checkInfo.checks[checkTypeIndex].text
							checkTypeIndexes = {checkTypeIndex}
						end

						for i,check in ipairs(checkInfo.checks) do
							children[#children+1] = gui.Label{
								classes = {'check-type-item', cond(i == checkTypeIndex, 'selected'), cond(checkInfo.group ~= nil and checkInfo.group:Get() ~= check.group, 'collapsed')},
								text = check.text,
								press = function(element)
									local multiselect = dmhub.modKeys.ctrl or dmhub.modKeys.shift

									if multiselect then
										element:SetClass('selected', not element:HasClass('selected'))

										--make sure at least one item is selected.
										local hasSelection = false
										for _,el in ipairs(element.parent.children) do
											if el:HasClass("selected") then
												hasSelection = true
											end
										end

										if not hasSelection then
											element:SetClass('selected', true)
										end
									else
										for j,item in ipairs(element.parent.children) do
											item:SetClass('selected', j == i)
										end
									end

									if element:HasClass("selected") then
										checkTypeIndex = i
										checkTypeName = checkInfo.checks[checkTypeIndex].text
									end

									--refresh which indexes we have selected, since we support multi-selection.
									checkTypeIndexes = {}
									for index,el in ipairs(element.parent.children) do
										if el:HasClass("selected") then
											checkTypeIndexes[#checkTypeIndexes+1] = index
										end
									end

									g_requireRollDialog:FireEventTree("refreshSkill")
								end,
							}
						end

						element.children = children

						g_requireRollDialog:FireEventTree("refreshSkill")
					end,
				},
			},

			gui.Panel{
				flow = 'vertical',
				width = 220,
				height = '80%',
				valign = "top",
				vscroll = true,
				gui.Panel{
					halign = "left",
					width = 200,
					height = "auto",
					flow = "vertical",
					hpad = 4,

					refreshSkill = function(element)

						specializationChecks = {}
						
						local checkInfo = RollCheck.Checks[checkSelectedIndex]
						local skillInfo = checkInfo.checks[checkTypeIndex]
						if skillInfo == nil then
							element.children = {}
							return
						end

						if rawget(skillInfo, "specializations") == nil or #skillInfo.specializations == 0 then
							element.children = {}
							return
						end

						local children = {}
						for _,s in ipairs(skillInfo.specializations) do
							local check = gui.Check{
								data = {
									key = s.id,
								},
								text = s.text,
								fontSize = 16,
								value = false,
								height = 20,
								halign = "left",
								valign = "top",
							}
							children[#children+1] = check
						end

						element.children = children
						specializationChecks = children
					end,
				},
			},

			gui.Panel{
				flow = 'vertical',
				width = 260,
				height = 'auto',
				valign = 'top',

				gui.Panel{
					flow = 'horizontal',
					height = 'auto',
					width = '100%',
					valign = 'top',
					gui.Label{
						classes = {'formLabel'},
						text = "DC:",
					},

					dcInput,
				},

				gamehud:CreatePartyTokenPoolSelector{
					initiative = (args.checkType == "Initiative"),
					changeSelection = function(element, tokenids)
						tokenIdsSelected = tokenids
						g_requireRollDialog:FireEventTree('changePartySelection', tokenids)
					end
				}
			},
		},

		gui.PrettyButton{
			text = 'Submit',
			floating = true,
			halign = 'right',
			valign = 'bottom',
			margin = 18,
			create = function(element)
				element:SetClass('hidden', #tokenIdsSelected == 0)
			end,
			changePartySelection = function(element)
				element:FireEvent('create')
			end,

			click = function(element)

				local ensureInitiativeShown = false

				local checks = {}
				for _,n in ipairs(checkTypeIndexes) do
					local checkInfo = RollCheck.Checks[checkSelectedIndex]
					local check = RollCheck.new(checkInfo.checks[n])
					check.dc = tonumber(dcInput.text)

					local specializations = {}
					for _,check in ipairs(specializationChecks) do
						if check.value then
							specializations[check.data.key] = true
						end
					end

					check:get_or_add("options", {})
					check.options.specializations = specializations

					checks[#checks+1] = check

					if check.type == "initiative" then
						ensureInitiativeShown = true
					end
				end

				if ensureInitiativeShown then
					local info = gamehud.initiativeInterface
					if info.initiativeQueue == nil or info.initiativeQueue.hidden then
						UploadDayNightInfo()
						info.initiativeQueue = InitiativeQueue.Create()
						info.UploadInitiative()
					end
				end
			
				local tokensSelected = {}
				for i,tok in ipairs(tokenIdsSelected) do
					tokensSelected[tok] = {}
				end
				local actionid = dmhub.SendActionRequest(RollRequest.new{
					checks = checks,
					tokens = tokensSelected,
				})

				gamehud:ShowRollSummaryDialog(actionid)
			end,
		},

	}

	g_requireRollDialog:FireEventTree('refreshDiceCheck')
	return g_requireRollDialog
end

--Group roll board -----------------------------------------------------------
--
--The d20 port of the Codex's group roll board (Draw Steel UI\DSRequestRollsDialog.lua).
--While a group of creatures rolls -- Roll Initiative, the DM's Request Rolls, or
--the saving throws an ability asks for -- every client shows ONE shared board,
--parked on the left beside the icon rail, with each creature's portrait landing
--as its roll comes in. It is drawn entirely from the RollRequest, which every
--client already sees under /actionRequests.
--
--Draw Steel drops portraits onto power-roll tiers. d20 has no tiers, so:
--  * a check with a DC gets a Success row and a Failure row, each showing what
--    that outcome means (the consequences of a saving throw, else the DC);
--  * a check with no DC (initiative, a plain check) gets one strip, ranked by
--    total, highest first.
--
--Rolling is unchanged: whoever controls a creature still rolls it in the roll
--dialog (the RequireRollListenerPanel above). On the requester's client the
--board replaces the old summary view: Proceed / Cancel, and right-click a
--portrait for Re-roll / Take Roll / Remove.
--
--A request goes on the board only when its requester showed it there
--(ShowRollSummaryDialog sets info.groupRollBoard), so the silent requests
--(AwaitRequestedActionCoroutine) and Monster AI waits stay off it, as they
--stayed out of the old summary.

RollRequest.groupRollBoard = false

--After the last roll is in and the request closes, the board stays up this
--long so the final result can be read.
local GROUP_ROLL_LINGER_SECONDS = 4

--actionid -> resultTable for the requests this client is waiting on (it is
--the requester). Read by the board to show the requester's controls.
local g_groupRollAwaiting = {}

--actionid -> true for boards this client closed or cancelled.
local g_groupRollDismissed = {}

--- @type Panel?
local g_groupRollLayer = nil

--The board's check for a request, or nil if the request does not go on it.
--- @param info table|nil the request's info (a RollRequest)
--- @return RollCheck|nil
local function GroupRollCheck(info)
	if info == nil or info.typeName ~= "RollRequest" or info.groupRollBoard ~= true then
		return nil
	end
	local check = info.checks ~= nil and info.checks[1] or nil
	return check
end

--Same presence rule as RequireRollListenerPanel.
local function GroupRollHavePlayersOnline()
	if #dmhub.users <= 1 then
		return false
	end
	for _,userid in ipairs(dmhub.users) do
		local session = dmhub.GetSessionInfo(userid)
		if session ~= nil and session.dm == false and session.loggedOut == false then
			return true
		end
	end
	return false
end

--Whether this client is the one prompted to roll for the token: the same rule
--as RequireRollListenerPanel.
local function GroupRollPromptsHere(tok, info, havePlayersOnline)
	if tok == nil or tok.properties == nil then
		return false
	end
	if info.forceuserid ~= nil then
		return info.forceuserid == dmhub.loginUserid
	end
	return tok.canControl and (dmhub.isDM == false or tok.playerControlled == false or not havePlayersOnline)
end

--" with advantage", " with disadvantage", or "" for a straight roll.
local function DescribeAdvantage(boons, banes)
	local net = (boons or 0) - (banes or 0)
	if net > 0 then
		return " with advantage"
	elseif net < 0 then
		return " with disadvantage"
	end
	return ""
end

--"success" or "failure" for a finished roll against a DC, read the way
--RollRequest:GetTokenResult reads it.
local function GroupRollOutcomeRow(info, dc)
	if info.outcome ~= nil then
		if info.outcome.success then
			return "success"
		elseif info.outcome.failure then
			return "failure"
		end
	end
	if info.forcedResult ~= nil then
		return cond(info.forcedResult, "success", "failure")
	end
	return cond(info.result >= dc, "success", "failure")
end

--What each outcome row says: the saving throw's consequences when the check
--has them, else the DC (for the DM; players are not shown the DC).
--- @param check RollCheck
--- @return string successText, string failureText
local function GroupRollOutcomeTexts(check)
	local consequences = check.consequences
	if type(consequences) == "table" then
		local failed = {}
		for _,damage in ipairs(consequences.damage or {}) do
			failed[#failed+1] = string.format("%s %s damage", damage.amount, damage.damageType)
		end
		local ongoingEffects = dmhub.GetTable("characterOngoingEffects") or {}
		for _,entry in ipairs(consequences.conditions or {}) do
			local ongoingEffect = ongoingEffects[entry.conditionid]
			if ongoingEffect ~= nil then
				failed[#failed+1] = ongoingEffect.name
			end
		end
		for _,entry in ipairs(consequences.text or {}) do
			failed[#failed+1] = entry.text
		end

		local successText = "Avoids the effect"
		local firstDamage = consequences.damage ~= nil and consequences.damage[1] or nil
		if firstDamage ~= nil then
			successText = cond(firstDamage.success == "half", "Half damage", "No damage")
		end

		if #failed > 0 then
			return successText, table.concat(failed, ", ")
		end
	end

	if dmhub.isDM and check:has_key("dc") then
		return string.format("DC %d or higher", check.dc), string.format("Below DC %d", check.dc)
	end
	return "", ""
end

--Snapshot of a request for drawing. Plain data, so the board can keep drawing
--it after the request has closed.
--- @param actionid string
--- @param request LuaPlayerActionRequest
--- @param check RollCheck
--- @return table
local function BuildGroupRollModel(actionid, request, check)
	local hasDC = check:has_key("dc")
	local title = check:Describe(not dmhub.isDM)
	local subtitle = ""
	if check.explanation ~= nil and check.explanation ~= "" then
		subtitle = check.explanation
	end

	local model = {
		actionid = actionid,
		title = title,
		subtitle = subtitle,
		hasDC = hasDC,
		entries = {},
		total = 0,
		rolled = 0,
		localCount = 0,
		allRolled = true,
	}

	if hasDC then
		model.successText, model.failureText = GroupRollOutcomeTexts(check)
	end

	local havePlayersOnline = GroupRollHavePlayersOnline()

	for tokid,info in pairs(request.info.tokens) do
		local tok = dmhub.GetCharacterById(tokid)
		model.total = model.total + 1
		local rolled = info.status == 'complete' and info.result ~= nil
		if rolled then
			model.rolled = model.rolled + 1
		else
			model.allRolled = false
		end
		if GroupRollPromptsHere(tok, info, havePlayersOnline) then
			model.localCount = model.localCount + 1
		end

		--A creature the DM has hidden stays off the players' boards.
		if tok ~= nil and (dmhub.isDM or not tok.invisibleToPlayers) then
			local name = "A creature"
			if dmhub.isDM or tok.canLocalPlayerSeeName then
				name = creature.GetTokenDescription(tok)
			end
			local row = nil
			if rolled then
				row = cond(hasDC, GroupRollOutcomeRow(info, check:try_get("dc", 0)), "ranked")
			end
			model.entries[#model.entries+1] = {
				tokid = tokid,
				token = tok,
				name = name,
				status = info.status,
				userid = info.userid,
				forceuserid = info.forceuserid,
				row = row,
				result = info.result,
				boons = info.boons,
				banes = info.banes,
			}
		end
	end

	--Stable order: by name, so portraits do not shuffle as rolls come in.
	table.sort(model.entries, function(a,b)
		if a.name ~= b.name then
			return a.name < b.name
		end
		return a.tokid < b.tokid
	end)

	return model
end

local function BuildGroupRollStyles()
	return {
		{
			selectors = {"groupRollBoard"},
			width = "100%",
			height = "auto",
			flow = "vertical",
			pad = 12,
			borderBox = true,
		},
		{
			selectors = {"groupRollTitle"},
			width = 400,
			height = "auto",
			fontSize = 18,
			bold = true,
			color = "@fgStrong",
			textAlignment = "left",
			halign = "left",
		},
		{
			selectors = {"groupRollSubtitle"},
			width = 400,
			height = "auto",
			fontSize = 13,
			color = "@fgMuted",
			textAlignment = "left",
			halign = "left",
		},
		{
			selectors = {"groupRollRows"},
			width = "100%",
			height = "auto",
			flow = "vertical",
			tmargin = 8,
		},
		{
			selectors = {"groupRollRow"},
			width = "100%",
			height = "auto",
			minHeight = 48,
			flow = "horizontal",
			hpad = 6,
			vpad = 4,
			borderBox = true,
			bgcolor = "clear",
		},
		{
			--A row someone landed in: the style guide's "current row" fill and edge.
			selectors = {"groupRollRow", "occupied"},
			bgcolor = "@bgAlt",
			borderColor = "@accent",
			--Every side must be given: a side left out draws a frame.
			border = {x1 = 3, x2 = 0, y1 = 0, y2 = 0},
		},
		{
			selectors = {"groupRollRow", "flash"},
			brightness = 2,
			transitionTime = 1,
		},
		{
			selectors = {"groupRollSeam"},
			width = "100%",
			height = 1,
			bgcolor = "@border",
			opacity = 0.2,
		},
		{
			selectors = {"groupRollOutcome"},
			width = 70,
			height = "auto",
			rmargin = 8,
			fontSize = 15,
			bold = true,
			color = "@fg",
			textAlignment = "left",
			halign = "left",
			valign = "center",
		},
		{
			selectors = {"groupRollOutcome", "success"},
			color = "#6fcf6f",
		},
		{
			selectors = {"groupRollOutcome", "failure"},
			color = "#e06060",
		},
		{
			selectors = {"groupRollRowText"},
			width = 186,
			height = "auto",
			fontSize = 14,
			color = "@fg",
			textAlignment = "left",
			halign = "left",
			valign = "center",
		},
		{
			--Fixed size: one line of cells (placed by x in BuildStrip), so a
			--row is as tall empty as full.
			selectors = {"groupRollIcons"},
			width = 190,
			height = 66,
			halign = "right",
			valign = "center",
		},
		{
			--The no-DC strip, ranked by total. It wraps rather than overlapping,
			--so every total stays readable however many creatures roll.
			selectors = {"groupRollRanked"},
			width = "100%",
			height = "auto",
			minHeight = 66,
			flow = "horizontal",
			wrap = true,
			halign = "left",
		},
		{
			--vpad leaves room for pop-out portraits, which draw past their frame.
			selectors = {"groupRollIconCell"},
			width = 42,
			height = "auto",
			flow = "vertical",
			vpad = 7,
			bgcolor = "clear",
		},
		{
			--Wide enough for a status caption ("Preparing") under the portrait.
			selectors = {"groupRollIconCell", "waiting"},
			width = 64,
		},
		{
			selectors = {"groupRollIconCell", "hover"},
			brightness = 1.4,
		},
		{
			selectors = {"groupRollIconCell", "landed"},
			brightness = 2.5,
			transitionTime = 0.8,
		},
		{
			selectors = {"groupRollIconCaption"},
			width = "auto",
			height = "auto",
			fontSize = 11,
			color = "@fgMuted",
			halign = "center",
			textAlignment = "center",
		},
		{
			selectors = {"groupRollIconCaption", "total"},
			fontSize = 13,
			bold = true,
			color = "@fg",
		},
		{
			selectors = {"groupRollWaiting"},
			width = "100%",
			height = "auto",
			flow = "vertical",
			tmargin = 10,
		},
		{
			selectors = {"groupRollSectionLabel"},
			width = "auto",
			height = "auto",
			fontSize = 12,
			bold = true,
			color = "@fgMuted",
			halign = "left",
			bmargin = 2,
		},
		{
			selectors = {"groupRollWaitingIcons"},
			width = "100%",
			height = 66,
			halign = "left",
		},
		{
			selectors = {"groupRollWaitingEmpty"},
			width = "auto",
			height = "auto",
			fontSize = 13,
			color = "@fgMuted",
			halign = "left",
			valign = "center",
		},
		{
			--Fixed height, so the requester's buttons coming and going (they
			--drop when the board lingers) do not resize the board.
			selectors = {"groupRollFooter"},
			width = "100%",
			height = 30,
			flow = "horizontal",
			tmargin = 10,
		},
		{
			selectors = {"groupRollStatus"},
			width = 200,
			height = "auto",
			fontSize = 13,
			color = "@fgMuted",
			textAlignment = "left",
			halign = "left",
			valign = "center",
		},
		{
			selectors = {"groupRollButton"},
			halign = "right",
			valign = "center",
			lmargin = 6,
		},
	}
end

--The outcome rows a board with a DC draws, best first.
local g_groupRollOutcomeRows = {
	{ id = "success", text = "Success", textField = "successText" },
	{ id = "failure", text = "Failure", textField = "failureText" },
}

--The layer holding the board. Mounted once in the HUD (GameHud.lua, which
--carries a stub of this), beside the roll hosts, so it draws over floating
--windows and under modals, and parked on the left beside the icon rail.
function GameHud:CreateGroupRollBoardLayer()
	--The request on the board, and the snapshot drawn for it. The snapshot
	--outlives the request while the board lingers.
	local m_actionid = nil
	local m_model = nil
	--Bumped whenever the board is shown or hidden, so a stale linger timer
	--cannot hide a board that has moved on.
	local m_serial = 0
	--tokid -> row drawn last time, to flash newly landed portraits.
	local m_landed = {}
	--Built per request: row id -> {row, icons}.
	local m_rows = {}
	local m_rowsFor = nil

	local layer
	local board

	local titleLabel = gui.Label{ classes = {"groupRollTitle"}, text = "" }
	local subtitleLabel = gui.Label{ classes = {"groupRollSubtitle"}, text = "" }
	local rowTable = gui.Panel{ classes = {"groupRollRows"} }
	local waitingEmptyLabel = gui.Label{ classes = {"groupRollWaitingEmpty"}, text = "Everyone has rolled." }
	local waitingIcons = gui.Panel{ classes = {"groupRollWaitingIcons"}, children = { waitingEmptyLabel } }
	local waitingPanel = gui.Panel{
		classes = {"groupRollWaiting"},
		children = {
			gui.Label{ classes = {"groupRollSectionLabel"}, text = "Still to roll" },
			waitingIcons,
		},
	}
	local statusLabel = gui.Label{ classes = {"groupRollStatus"}, text = "" }

	--Strip geometry. Cells are sized for their caption: a total under a
	--landed portrait, a status word ("Preparing") under a waiting one.
	local GROUP_ROLL_ROW_CELL_WIDTH = 42
	local GROUP_ROLL_ROW_STRIP_WIDTH = 190
	local GROUP_ROLL_WAITING_CELL_WIDTH = 64
	local GROUP_ROLL_WAITING_STRIP_WIDTH = 476

	local function Hide()
		m_serial = m_serial + 1
		m_actionid = nil
		m_model = nil
		m_landed = {}
		board:SetClass("collapsed", true)
	end

	--The requester's answer: accepted (Proceed) or not (Cancel). Closing the
	--request clears it from every client's board.
	local function Finish(accepted)
		local actionid = m_actionid
		local resultTable = actionid ~= nil and g_groupRollAwaiting[actionid] or nil
		if resultTable == nil then
			return
		end
		---@cast actionid string
		g_groupRollAwaiting[actionid] = nil
		resultTable.action = dmhub.GetPlayerActionRequest(actionid)
		resultTable.result = accepted and resultTable.action ~= nil
		if not accepted then
			--Our own Cancel closes our board at once; others still linger.
			g_groupRollDismissed[actionid] = true
		end
		dmhub.CancelActionRequest(actionid)
	end

	--Rewrite one creature's entry in the request (the old summary's per-row buttons).
	local function EditEntry(actionid, tokid, description, newEntry)
		local action = dmhub.GetPlayerActionRequest(actionid)
		if action == nil or action.info.tokens[tokid] == nil then
			return
		end
		action:BeginChanges()
		action.info.tokens[tokid] = newEntry
		action:CompleteChanges(description)
	end

	--Right-click menu on a portrait, for the requester only.
	local function EntryMenu(entry)
		local actionid = m_actionid
		if actionid == nil or g_groupRollAwaiting[actionid] == nil then
			return nil
		end
		local entries = {}
		if dmhub.isDM and (entry.status == nil or entry.status == 'dialog') and entry.forceuserid ~= dmhub.loginUserid then
			entries[#entries+1] = {
				text = "Take Roll",
				click = function()
					EditEntry(actionid, entry.tokid, "Request roll again", { forceuserid = dmhub.loginUserid })
				end,
			}
		end
		if dmhub.isDM and (entry.status == 'complete' or entry.status == 'cancel') then
			entries[#entries+1] = {
				text = "Re-roll",
				click = function()
					EditEntry(actionid, entry.tokid, "Request roll again", {})
				end,
			}
		end
		if entry.status == 'cancel' then
			entries[#entries+1] = {
				text = "Remove",
				click = function()
					EditEntry(actionid, entry.tokid, "Removed roll", nil)
				end,
			}
		end
		if #entries == 0 then
			return nil
		end
		return entries
	end

	local function EntryStatusText(entry)
		if entry.status == 'dialog' then
			if entry.userid ~= nil then
				return string.format("%s is preparing to roll", dmhub.GetDisplayName(entry.userid)), "Preparing"
			end
			return "Preparing to roll", "Preparing"
		elseif entry.status == 'rolling' then
			return "Rolling", "Rolling"
		elseif entry.status == 'cancel' then
			return "Declined to roll", "Declined"
		elseif entry.forceuserid == dmhub.loginUserid then
			return "Waiting for you to roll", "Waiting"
		end
		return "Waiting to roll", "Waiting"
	end

	--One portrait. x places it within an overlapping strip; nil leaves it to
	--the parent's flow (the wrapping ranked strip). Landed ones show the total
	--under the portrait; waiting ones show their status.
	local function CreateEntryCell(entry, x)
		local tooltip
		local caption
		local captionClasses = {"groupRollIconCaption"}
		if entry.row ~= nil then
			tooltip = string.format("%s rolled %d%s", entry.name, entry.result, DescribeAdvantage(entry.boons, entry.banes))
			caption = tostring(entry.result)
			captionClasses[#captionClasses+1] = "total"
		else
			local statusText
			statusText, caption = EntryStatusText(entry)
			tooltip = string.format("%s: %s", entry.name, statusText)
		end

		local menu = EntryMenu(entry)
		if menu ~= nil then
			tooltip = tooltip .. "\nRight-click for options."
		end

		return gui.Panel{
			classes = {"groupRollIconCell", cond(entry.row == nil, "waiting", nil)},
			bgimage = "panels/square.png",
			floating = x ~= nil,
			halign = "left",
			valign = "top",
			x = x or 0,
			hover = gui.Tooltip(tooltip),
			rightClick = function(element)
				local items = EntryMenu(entry)
				if items == nil then
					return
				end
				for _,item in ipairs(items) do
					local click = item.click
					item.click = function()
						element.popup = nil
						click()
					end
				end
				element.popup = gui.ContextMenu{ entries = items }
			end,
			children = {
				gui.CreateTokenImage(entry.token, {
					width = 34,
					height = 34,
					halign = "center",
					valign = "top",
				}),
				gui.Label{ classes = captionClasses, text = caption },
			},
		}
	end

	--A strip of portraits that is always one line, so the board keeps its
	--size as rolls come in: past what fits side by side, the portraits overlap.
	local function BuildStrip(entries, cellWidth, stripWidth)
		local step = cellWidth
		if #entries > 1 and #entries * cellWidth > stripWidth then
			step = (stripWidth - cellWidth) / (#entries - 1)
		end
		local cells = {}
		for i,entry in ipairs(entries) do
			cells[i] = CreateEntryCell(entry, (i - 1) * step)
		end
		return cells
	end

	--The rows depend only on whether the request has a DC, so they are built
	--once per request; each render just refills their portraits.
	local function EnsureRows(model)
		if m_rowsFor == model.actionid then
			return
		end
		m_rowsFor = model.actionid
		m_rows = {}

		local children = {}
		if model.hasDC then
			for i,rowInfo in ipairs(g_groupRollOutcomeRows) do
				if i > 1 then
					children[#children+1] = gui.Panel{ classes = {"groupRollSeam"}, bgimage = true }
				end
				local icons = gui.Panel{ classes = {"groupRollIcons"} }
				local row = gui.Panel{
					classes = {"groupRollRow"},
					bgimage = "panels/square.png",
					children = {
						gui.Label{ classes = {"groupRollOutcome", rowInfo.id}, text = rowInfo.text },
						gui.Label{ classes = {"groupRollRowText"}, text = model[rowInfo.textField] or "" },
						icons,
					},
				}
				children[#children+1] = row
				m_rows[rowInfo.id] = { row = row, icons = icons }
			end
		else
			local icons = gui.Panel{ classes = {"groupRollRanked"} }
			local row = gui.Panel{
				classes = {"groupRollRow"},
				bgimage = "panels/square.png",
				children = { icons },
			}
			children[#children+1] = row
			m_rows.ranked = { row = row, icons = icons, ranked = true }
		end
		rowTable.children = children
	end

	local cancelButton = gui.Button{
		classes = {"sizeS", "groupRollButton"},
		text = "Cancel",
		click = function(element)
			Finish(false)
		end,
	}

	local proceedButton = gui.Button{
		classes = {"sizeS", "groupRollButton"},
		text = "Proceed",
		click = function(element)
			if m_model ~= nil and m_model.allRolled then
				Finish(true)
			end
		end,
	}

	local closeButton = gui.Button{
		classes = {"closeButton"},
		floating = true,
		halign = "right",
		valign = "top",
		click = function(element)
			if m_actionid ~= nil then
				g_groupRollDismissed[m_actionid] = true
			end
			Hide()
		end,
	}

	--finished: the request has closed and this is its last snapshot.
	local function Render(model, finished)
		local newRequest = m_rowsFor ~= model.actionid
		EnsureRows(model)

		titleLabel.text = model.title
		subtitleLabel.text = model.subtitle
		subtitleLabel:SetClass("collapsed", model.subtitle == "")

		local perRow = {}
		local waiting = {}
		local landedNow = {}
		for _,entry in ipairs(model.entries) do
			if entry.row ~= nil then
				perRow[entry.row] = perRow[entry.row] or {}
				table.insert(perRow[entry.row], entry)
				landedNow[entry.tokid] = entry.row
			elseif not finished then
				waiting[#waiting+1] = entry
			end
		end

		--Portraits that just landed; flashed once they are in their rows.
		local justLanded = {}
		for rowid,rowInfo in pairs(m_rows) do
			local entries = perRow[rowid] or {}
			local cells
			if rowInfo.ranked then
				--Highest total first; ties keep the name order.
				local order = {}
				for i,entry in ipairs(entries) do
					order[entry.tokid] = i
				end
				table.sort(entries, function(a,b)
					if a.result ~= b.result then
						return a.result > b.result
					end
					return order[a.tokid] < order[b.tokid]
				end)
				cells = {}
				for i,entry in ipairs(entries) do
					cells[i] = CreateEntryCell(entry, nil)
				end
			else
				cells = BuildStrip(entries, GROUP_ROLL_ROW_CELL_WIDTH, GROUP_ROLL_ROW_STRIP_WIDTH)
			end
			for n,entry in ipairs(entries) do
				if (not newRequest) and m_landed[entry.tokid] ~= entry.row then
					justLanded[#justLanded+1] = { cell = cells[n], row = rowInfo.row }
				end
			end
			rowInfo.icons.children = cells
			rowInfo.row:SetClass("occupied", #cells > 0)
		end
		m_landed = landedNow

		for _,landed in ipairs(justLanded) do
			landed.cell:PulseClass("landed")
			landed.row:PulseClass("flash")
		end

		--The strip keeps its space when empty, so the board does not shrink
		--as the last creature rolls.
		--The label stays a child throughout; a label first parented into an
		--already laid-out panel is never laid out.
		local waitingChildren = BuildStrip(waiting, GROUP_ROLL_WAITING_CELL_WIDTH, GROUP_ROLL_WAITING_STRIP_WIDTH)
		table.insert(waitingChildren, 1, waitingEmptyLabel)
		waitingEmptyLabel:SetClass("hidden", #waiting > 0)
		waitingIcons.children = waitingChildren

		--The footer has a fixed height, so showing or dropping the buttons
		--does not resize the board.
		local isRequester = (not finished) and g_groupRollAwaiting[model.actionid] ~= nil
		cancelButton:SetClass("collapsed", not isRequester)
		proceedButton:SetClass("collapsed", not isRequester)
		proceedButton:SetClass("disabled", not model.allRolled)
		closeButton:SetClass("collapsed", isRequester)

		statusLabel.text = string.format("%d of %d rolled", model.rolled, model.total)
	end

	--Pick the request to show: one this client is waiting on first, then the
	--one already on the board, then any other.
	local function ChooseRequest()
		local best = nil
		local bestRank = nil
		for k,request in pairs(dmhub.GetPlayerActionRequests() or {}) do
			if not g_groupRollDismissed[k] and GroupRollCheck(request.info) ~= nil then
				local rank = 3
				if g_groupRollAwaiting[k] ~= nil then
					rank = 1
				elseif k == m_actionid then
					rank = 2
				end
				if best == nil or rank < bestRank or (rank == bestRank and k < best) then
					best = k
					bestRank = rank
				end
			end
		end
		if best == nil then
			return nil, nil
		end
		return best, dmhub.GetPlayerActionRequest(best)
	end

	local function Refresh()
		--A request we were waiting on that closed without our answer (someone
		--else cancelled it): the requester reads that as cancelled, as it did
		--with the summary view.
		for actionid,resultTable in pairs(g_groupRollAwaiting) do
			if dmhub.GetPlayerActionRequest(actionid) == nil then
				g_groupRollAwaiting[actionid] = nil
				if resultTable.result == nil then
					resultTable.result = false
				end
			end
		end

		local actionid, request = ChooseRequest()
		if request == nil then
			if m_actionid ~= nil and m_model ~= nil and m_model.allRolled and not g_groupRollDismissed[m_actionid] then
				--The request closed with every roll in. Keep the final board up
				--for a moment.
				local model = m_model
				m_actionid = nil
				m_serial = m_serial + 1
				local serial = m_serial
				Render(model, true)
				dmhub.Schedule(GROUP_ROLL_LINGER_SECONDS, function()
					if mod.unloaded or serial ~= m_serial or board == nil or not board.valid then
						return
					end
					Hide()
				end)
			elseif m_actionid ~= nil then
				Hide()
			end
			return
		end
		---@cast actionid string

		local check = GroupRollCheck(request.info)
		---@cast check -nil
		local model = BuildGroupRollModel(actionid, request, check)

		if actionid ~= m_actionid then
			m_serial = m_serial + 1
		end
		m_actionid = actionid
		m_model = model
		Render(model, false)
		board:SetClass("collapsed", false)

		--One creature, rolled right here: nothing for the requester to review,
		--so answer as soon as it is rolled or declined.
		if g_groupRollAwaiting[actionid] ~= nil and model.total == 1 and model.localCount == 1 then
			local entry = request.info.tokens[next(request.info.tokens)]
			if entry ~= nil and entry.status == 'complete' then
				Finish(true)
			elseif entry ~= nil and entry.status == 'cancel' then
				Finish(false)
			end
		end
	end

	board = gui.Panel{
		classes = {"framedPanel", "groupRollBoard", "collapsed"},
		bgimage = true,
		children = {
			titleLabel,
			subtitleLabel,
			rowTable,
			waitingPanel,
			gui.Panel{
				classes = {"groupRollFooter"},
				children = {
					statusLabel,
					cancelButton,
					proceedButton,
				},
			},
			closeButton,
		},
	}

	layer = gui.Panel{
		styles = ThemeEngine.MergeStyles(BuildGroupRollStyles()),
		width = 500,
		height = "auto",
		halign = "left",
		--Anchored by its top edge: the board grows and shrinks as rolls come
		--in, and a centred board would jump each time.
		valign = "top",
		tmargin = 200,
		lmargin = 76,
		interactable = false,
		children = { board },

		monitorGame = "/actionRequests",
		refreshGame = function(element)
			Refresh()
		end,

		--A request already open when the HUD is built (a rebuild mid-roll).
		create = function(element)
			Refresh()
		end,

		destroy = function(element)
			--A HUD rebuild mid-wait: the requester reads it as cancelled, as it
			--did when the summary view was torn down.
			for _,resultTable in pairs(g_groupRollAwaiting) do
				if resultTable.result == nil then
					resultTable.result = false
				end
			end
			g_groupRollAwaiting = {}
			if g_groupRollLayer == element then
				g_groupRollLayer = nil
			end
		end,
	}

	ThemeEngine.OnThemeChanged(mod, function()
		if layer ~= nil and layer.valid then
			layer.styles = ThemeEngine.MergeStyles(BuildGroupRollStyles())
		end
	end)

	g_groupRollLayer = layer
	return layer
end

--Wait for a request's rolls on the group roll board. Marks the request so every
--client shows it there. Returns false (and does nothing) when the board is not
--mounted, so the caller shows the summary view instead.
--- @param actionid string
--- @param resultTable table
--- @return boolean
local function AwaitOnGroupRollBoard(actionid, resultTable)
	local action = dmhub.GetPlayerActionRequest(actionid)
	if action == nil or action.info.typeName ~= "RollRequest" then
		return false
	end
	if g_groupRollLayer == nil or not g_groupRollLayer.valid then
		return false
	end

	if action.info.groupRollBoard ~= true then
		action:BeginChanges()
		action.info.groupRollBoard = true
		action:CompleteChanges("Show on group roll board")
	end

	g_groupRollAwaiting[actionid] = resultTable
	g_groupRollDismissed[actionid] = nil

	--The board replaces the summary that used to take over the Request Rolls
	--dialog, so that dialog has nothing left to show.
	CloseRequireRollDialog()

	g_groupRollLayer:FireEvent("refreshGame")
	return true
end

--resultTable gets marked with a 'result' = true/false for completion or cancel.
function GameHud:ShowRollSummaryDialog(actionid, resultTable)
	if resultTable == nil then
		resultTable = {}
	end

	if AwaitOnGroupRollBoard(actionid, resultTable) then
		return
	end

	local iscomplete = false

	local closeButton = gui.PrettyButton{
			text = 'Cancel',
			floating = true,
			halign = 'right',
			valign = 'bottom',
			margin = 24,
			click = function(element)
				resultTable.result = iscomplete
				resultTable.action = dmhub.GetPlayerActionRequest(actionid)
				dmhub.CancelActionRequest(actionid)
				CloseRequireRollDialog()
			end,
		}

	local action = dmhub.GetPlayerActionRequest(actionid)
	if action == nil then
		CloseRequireRollDialog()
		resultTable.result = false
		return
	end

	--ensure the request rolls dialog exists.
	LaunchablePanel.GetOrLaunchPanel("Request Rolls")


	local summaryPanel = gui.Label{
		text = string.format("Requested a %s", action.info:Describe()),
		classes = {'check-summary'},
		interactable = false,
	}

	local resultsPanels = {}

	for k,v in pairs(action.info.tokens) do
		local tok = dmhub.GetCharacterById(k)
		if tok ~= nil then

			local checkInfo = action.info.checks[1]

			local outcomeLabel = gui.Label{
				classes = {'result-outcome-label'},
				text = '',
			}

			local consequencesTable = gui.Panel{
				classes = {'result-consequences-table'},
			}

			local againButton = nil
			
			if dmhub.isDM then
				againButton = gui.Button{
					text = 'Re-roll',
					halign = 'right',
					width = 80,
					height = 24,
					fontSize = 16,
					margin = 16,
					data = {
						takeroll = false,
					},
					takeroll = function(element, take)
						element.data.takeroll = take
						element.text = cond(take, "Take Roll", "Re-roll")
						element:SetClass("hidden", false)
					end,
					click = function(element)
						local actionInfo = action.info.tokens[k]
						if actionInfo ~= nil then
							outcomeLabel.text = ''
							action:BeginChanges()

							if element.data.takeroll and dmhub.isDM then
								action.info.tokens[k] = { forceuserid = dmhub.loginUserid }
							else
								action.info.tokens[k] = {}
							end
							action:CompleteChanges("Request roll again")
						end
						
					end,
				}
			end

			local panel

			local removeButton = gui.Button{
				classes = {"hidden"},
				text = 'Remove',
				halign = "right",
				width = 80,
				height = 24,
				fontSize = 14,
				margin = 16,
				click = function(element)
					action:BeginChanges()
					action.info.tokens[k] = nil
					action:CompleteChanges("Removed roll")
					panel:DestroySelf()
				end,

			}

			panel = gui.Panel{
				classes = {'result-panel'},

				gui.CreateTokenImage(tok),

				gui.Label{
					classes = {'result-status-label'},
					create = function(element)
						element:FireEvent('refreshAction')
					end,

					refreshAction = function(element)
						local actionInfo = action.info.tokens[k]
						if actionInfo ~= nil then
							removeButton:SetClass("hidden", true)
							if actionInfo.status == 'dialog' then
								if actionInfo.userid ~= nil then
									element.text = string.format("%s is preparing to roll...", dmhub.GetDisplayName(actionInfo.userid))
								else
									element.text = 'Reviewing Prompt'
								end

								if againButton ~= nil then
									againButton:FireEvent("takeroll", true)
								end
							elseif actionInfo.status == 'rolling' then
								element.text = 'Rolling'
								if againButton ~= nil then
									againButton:FireEvent("takeroll", false)
								end
							elseif actionInfo.status == 'complete' then
								element.text = 'Rolled'

								local text = string.format("<b>%d</b>", actionInfo.result)
								if actionInfo.outcome then
									text = string.format("<color=%s>%s (%s)</color>", actionInfo.outcome.color, text, actionInfo.outcome.outcome)
								end

								outcomeLabel.text = text
								if againButton ~= nil then
									againButton:FireEvent("takeroll", false)
								end

							elseif actionInfo.status == 'cancel' then
								element.text = 'Declined'
								removeButton:SetClass("hidden", false)
								if againButton ~= nil then
									againButton:SetClass("hidden", false)
									againButton:FireEvent("takeroll", false)
								end
							else
								element.text = 'Waiting...'
								if againButton ~= nil then
									againButton:FireEvent("takeroll", true)
								end
							end
						end

						if actionInfo ~= nil and actionInfo.status == 'complete' and actionInfo.outcome and checkInfo.consequences ~= nil then
							local children = {}
							local success = string.lower(actionInfo.outcome.outcome) == "success"

							local damageCalc = nil
							local damageEntry = nil
							for _,entry in ipairs(checkInfo.consequences.damage or {}) do
								if entry.tokens == nil or entry.tokens[k] then
									damageCalc = GameSystem.SavingThrowDamageCalculation(actionInfo.outcome, entry.success)
									damageEntry = entry
								end
							end

							if success then

								if damageCalc ~= nil then
									children[#children+1] = gui.Label{
										classes = {"consequenceLabel", "avoided"},
										text = string.format("%s %s (%s)", damageEntry.amount, damageEntry.damageType, damageCalc.summary or "saved"),
										color = damageCalc.color,
									}
								else
									children[#children+1] = gui.Label{
										classes = {"consequenceLabel", "avoided"},
										text = "Avoided",
									}
								end
							else
								if damageCalc ~= nil then
									children[#children+1] = gui.Label{
										classes = {"consequenceLabel"},
										text = string.format("%s %s (%s)", damageEntry.amount, damageEntry.damageType, damageCalc.summary or "full damage"),
										color = damageCalc.color,
									}
								else
									for _,entry in ipairs(checkInfo.consequences.conditions or {}) do
										local characterOngoingEffects = dmhub.GetTable("characterOngoingEffects")
										local ongoingEffect = characterOngoingEffects[entry.conditionid]
										if ongoingEffect ~= nil then
											if entry.tokens == nil or entry.tokens[k] then
												children[#children+1] = gui.Label{
													classes = {"consequenceLabel"},
													text = string.format("%s", ongoingEffect.name),
												}
											end
										end
									end

									for _,entry in ipairs(checkInfo.consequences.text or {}) do
										if entry.tokens == nil or entry.tokens[k] then
											children[#children+1] = gui.Label{
												classes = {"consequenceLabel"},
												text = entry.text,
											}
										end
									end
								end
							end

							consequencesTable.children = children
						else
							consequencesTable.children = {}
						end
					end
				},

				outcomeLabel,

				consequencesTable,

				againButton,

				removeButton,
			}

			resultsPanels[#resultsPanels+1] = panel
		end
	end

	local resultPanelScroll = gui.Panel{
		classes = {'result-panel-scroll'},
		vscroll = true,
		children = resultsPanels,

		monitorGame = "/actionRequests",

		refreshGame = function(element)
			action = dmhub.GetPlayerActionRequest(actionid)
			if action == nil then
				CloseRequireRollDialog()
				return
			elseif g_requireRollDialog ~= nil then
				g_requireRollDialog:FireEventTree("refreshAction")

				local hasIncomplete = false
				for k,v in pairs(action.info.tokens) do
					if v.status ~= 'complete' then
						hasIncomplete = true
					end
				end


				iscomplete = not hasIncomplete

				closeButton.text = cond(hasIncomplete, 'Cancel', 'Proceed')
			end
		end,

	}

	local consequencesLabel = gui.Label{
		width = "55%",
		height = "auto",
		fontSize = 14,
		halign = "left",
		hmargin = 80,
		text = "",
		refreshAction = function(element)
			local checkInfo = action.info.checks[1]
			if checkInfo ~= nil and checkInfo.consequences ~= '' then
				element.text = ActivatedAbility.DescribeSavingThrowConsquences(checkInfo.consequences)
			else
				element.text = ""
			end
		end
	}

	g_requireRollDialog.children = {

		summaryPanel,

		resultPanelScroll,

		consequencesLabel,

		closeButton,

	}
end

--this is a silent/non-gui version of GameHud:ShowRollSummaryDialog that monitors an actionid for completion.
--designed to be run in a coroutine. Will cancel the request and time out eventually.
function AwaitRequestedActionCoroutine(actionid, resultTable)
	resultTable = resultTable or {}

	local delay = 0.2
	local iterations = 60*5/delay
	local action = dmhub.GetPlayerActionRequest(actionid)
	while action ~= nil and iterations > 0 do
		local incomplete = false
		for k,actionInfo in pairs(action.info.tokens) do
			if actionInfo.status ~= 'complete' and actionInfo.status ~= 'cancel' then
				incomplete = true
			end
		end

		if incomplete == false then
			resultTable.result = true
			resultTable.action = action
			dmhub.CancelActionRequest(actionid)
			return resultTable
		end

		coroutine.yield(delay)
		action = dmhub.GetPlayerActionRequest(actionid)

		iterations = iterations - 1
	end
	
	if action ~= nil then
		dmhub.CancelActionRequest(actionid)
	end
	resultTable.result = false

	return resultTable
end


LaunchablePanel.Register{
	name = "Request Rolls",
	menu = "game",
	icon = "game-icons/dice-twenty-faces-twenty.png",
	halign = "center",
	valign = "center",
	hidden = function()
		return not dmhub.isDM
	end,
	content = function(args)
		g_requireRollDialog = ShowRequireRollDialog(args)
		return g_requireRollDialog
	end,
}
