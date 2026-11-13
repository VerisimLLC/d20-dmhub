local mod = dmhub.GetModLoading()


--These are more correctly called "EquipmentProperty"! We call them weapon properties for historical reasons.
RegisterGameType("WeaponProperty")

WeaponProperty.tableName = "weaponProperties"
function WeaponProperty.GetTable()
    return dmhub.GetTable(WeaponProperty.tableName) or {}
end

WeaponProperty.name = "Property"
WeaponProperty.details = ""
WeaponProperty.hasValue = false
WeaponProperty.hidden = false

WeaponProperty.builtins = {}

WeaponProperty.modifiesAttacks = false

WeaponProperty.itemType = "weapon"

WeaponProperty.itemTypes = {
    {
        id = "weapon",
        text = "Weapon",
    },
    {
        id = "armor",
        text = "Armor",
    },
    {
        id = "shield",
        text = "Shield",
    },
    {
        id = "other",
        text = "Other",
    },
    {
        id = "all",
        text = "All",
    },
}

function WeaponProperty.CreateNew(args)
    args = args or {}

    args.features = args.features or {}

    return WeaponProperty.new(args)
end

function WeaponProperty.Get(key)
    return WeaponProperty.builtins[key] or WeaponProperty.GetTable()[key]
end

function WeaponProperty.DropdownOptions(item)
    local result = {}

    local itemType = "other"
    if item.isWeapon then
        itemType = "weapon"
    elseif item.isShield then
        itemType = "shield"
    elseif item.isArmor then
        itemType = "armor"
    end


    for k,v in pairs(WeaponProperty.GetTable()) do
        if (not v.hidden) and (v.itemType == "all" or v.itemType == itemType) then
            result[#result+1] = {
                id = k,
                text = v.name,
            }
        end
    end

    table.sort(result, function(a,b) return a.text < b.text end)

    return result
end


function WeaponProperty.CreateEditor()
    local resultPanel
    local m_item = nil
    local m_itemOriginal = nil

    local Upload = function()
        printf("UPLOAD:: %s", traceback())
        dmhub.SetAndUploadTableItem(WeaponProperty.tableName, m_item)
        m_itemOriginal = DeepCopy(m_item)
    end

    local OnChange = function()
        Upload()
        resultPanel:FireEventTree("editItem", m_item)
    end


    resultPanel = gui.Panel{
        classes = {"hidden"},
        styles = {
            Styles.Form,
            {
                selectors = {"formPanel"},
                width = 400,
            },
        },

        flow = "vertical",
        width = 1000,
        maxHeight = 1000,
        height = "auto",
        vscroll = true,

        destroy = function(element)
            if m_item ~= nil and not dmhub.DeepEqual(m_item, m_itemOriginal) then
                Upload()
            end
        end,

        editItem = function(element, item)
            if item == m_item then
                return
            end

            if m_item ~= nil and not dmhub.DeepEqual(m_item, m_itemOriginal) then
                Upload()
            end

            m_item = item
            m_itemOriginal = DeepCopy(m_item)
            element:SetClass("hidden", false)
        end,

        gui.Label{
            text = "This is a built-in property.",
            fontSize = 16,
            width = "auto",
            height = "auto",
            halign = "left",
            editItem = function(element, item)
                element:SetClass("hidden", WeaponProperty.builtins[item.id] == nil)
            end,
        },

        gui.Panel{
            classes = {"formPanel"},
            gui.Label{
                classes = {"formLabel"},
                text = "Equipment Type:",
            },

            gui.Panel{
                width = 500,
                height = "auto",
                gui.Dropdown{
                    options = WeaponProperty.itemTypes,
                    editItem = function(element, item)
                        element.idChosen = item.itemType
                    end,
                    change = function(element)
                        m_item.itemType = element.idChosen
                        OnChange()
                    end,
                },
            },
        },

        gui.Panel{
            classes = {"formPanel"},
            gui.Label{
                classes = {"formLabel"},
                text = "Name:",
            },

            gui.Input{
                classes = {"formInput"},
                width = 500,
                editItem = function(element, item)
                    element.text = item.name
                end,
                change = function(element)
                    m_item.name = element.text
                    OnChange()
                end,
            }
        },

        gui.Panel{
            classes = {"formPanel"},
            gui.Label{
                classes = {"formLabel"},
                text = "Details:",
            },

            gui.Input{
                classes = {"formInput"},
                multiline = true,
                height = "auto",
                width = 500,
                maxHeight = 60,
                placeholderText = "Enter rules text...",
                editItem = function(element, item)
                    element.text = item.details
                end,
                change = function(element)
                    m_item.details = element.text
                end,
            },
        },

        gui.Check{
            text = "Has Value",
            editItem = function(element, item)
                element.value = item.hasValue
            end,
            change = function(element)
                m_item.hasValue = element.value
            end,
        },



        gui.Check{
            text = "Modifies Attacks",
            editItem = function(element, item)
                element:SetClass("collapsed", item.itemType ~= "weapon")
                element.value = item.modifiesAttacks
            end,
            change = function(element)
                if m_item.modifiesAttacks == element.value then
                    return
                end

                m_item.modifiesAttacks = element.value

                if m_item.modifiesAttacks and m_item:try_get("attackModifier") == nil then

					local augmentation = CharacterModifier.new{
						behavior = 'modifyability',
						guid = dmhub.GenerateGuid(),
						name = "Weapon Modification",
						source = "Weapon Property",
						description = "Weapon modifiers",
						unconditional = true,
					}

					CharacterModifier.TypeInfo.modifyability.init(augmentation)
					m_item.attackModifier = augmentation
                end

                OnChange()
            end,
        },

		gui.Panel{
			id = "weaponBehaviorPanel",
			styles = {
				CharacterFeature.ModifierStyles,
				{
					classes = {"formLabel"},
					halign = "left",
					width = 180,
				},
				{
					classes = {"formPanel"},
					width = "100%",
				},
			},
			width = 700,
			height = "auto",
			halign = "left",
			flow = "vertical",
			bgimage = "panels/square.png",
			bgcolor = "clear",
			borderWidth = 1,
			borderColor = "white",
			pad = 4,

            editItem = function(element, item)
                element:SetClass("collapsed", (not item.modifiesAttacks) or item.itemType ~= "weapon")

                if item.modifiesAttacks then
				    CharacterModifier.TypeInfo.modifyability.createEditor(item.attackModifier, element.children[2])
                end
            end,

			gui.Label{
				classes = {"form-heading"},
				text = "Modify Attacks",
				bold = true,
				halign = "left",
				hmargin = 2,
			},

			gui.Panel{
				width = "100%",
				height = "auto",
				flow = "vertical",
			},
		},

		gui.Panel{
			width = "auto",
			height = "auto",
			halign = "right",
			editItem = function(element, item)
                element.children = {
                    CharacterFeature.ListEditor(item, "features", {
                        dialog = resultPanel.root,
                        createOptions = {
                            addText = "Add Special Properties",
                            itemAttached = true,
                            name = "Item Feature",
                            source = "Item",
                        }
                    }),
                }
			end,

		},


    }

    return resultPanel
end

dmhub.RegisterEventHandler("refreshTables", function()
    local tbl = WeaponProperty.GetTable()

    for _,p in ipairs(weapon.builtinWeaponProperties) do
        if tbl[p.attr] == nil then
            local entry = WeaponProperty.CreateNew{
                id = p.attr,
                name = p.text,
            }
            dmhub.SetAndUploadTableItem(WeaponProperty.tableName, entry)
        end
    end
end)


--------------------------------------------------------------------------------
--Weapon Mastery (SRD 5.2.1 p. 90).
--
--Active only when GameSystem.WeaponMastery is set (the 5.5e system root sets it),
--so 5e never changes. A creature gets mastery slots from "Weapon Mastery"
--modifiers (class features) and fills them on the character sheet with kinds of
--weapons (creature.weaponMasteries, a list of base weapon item ids; a magic or
--unique weapon counts as the kind of its baseid item). An attack with a mastered
--weapon carries attack.mastery = the weapon's mastery property id.
--
--A mastery property record (weaponProperties, mastery = true) may hold:
--  masteryAbility: an ActivatedAbility cast on the target when the attack hits
--                  (Push, Sap, Slow, Topple). Its GoblinScript can use the symbol
--                  "Mastery Modifier": the ability modifier used for the attack.
--  masteryRequiresDamage: cast masteryAbility only if the hit dealt damage (Slow).
--  masteryEffect: an ongoing effect id the code below uses (Vex).
--Cleave, Graze, Nick and Vex are code, keyed by their property ids.
--------------------------------------------------------------------------------

WeaponProperty.mastery = false
WeaponProperty.masteryRequiresDamage = false

WeaponMastery = {}

--the weapon's mastery property: returns id, WeaponProperty or nil.
function WeaponMastery.PropertyOfWeapon(weapon)
    for k,_ in pairs(weapon:try_get("properties", {})) do
        local info = WeaponProperty.Get(k)
        if info ~= nil and info.mastery then
            return k, info
        end
    end

    return nil
end

--the kind of weapon an item is: the item id of its base weapon.
function WeaponMastery.KindOf(weapon)
    local gearTable = dmhub.GetTable("tbl_Gear") or {}
    local count = 0
    while weapon:has_key("baseid") and gearTable[weapon.baseid] ~= nil and count < 8 do
        weapon = gearTable[weapon.baseid]
        count = count + 1
    end

    return weapon.id
end

--the ability modifier used to make an attack roll, or 0.
function WeaponMastery.AbilityModifier(c, attack)
    local attrid = attack:try_get("attrid")
    if type(attrid) == "string" and attrid ~= "none" then
        return c:GetAttribute(attrid):Modifier()
    end

    return 0
end

--"Sap" for the property named "Mastery: Sap".
function WeaponMastery.MasteryName(propInfo)
    local name = propInfo.name
    local short = string.match(name, "^[Mm]astery:%s*(.+)$")
    return short or name
end

WeaponMastery.weaponKindOptions = {
    {
        id = "proficient",
        text = "Weapons you are proficient with",
    },
    {
        id = "melee",
        text = "Melee weapons you are proficient with",
    },
}

CharacterModifier.RegisterType('weaponmastery', "Weapon Mastery")

--a 'weaponmastery' modifier has these properties:
--  num: GoblinScript, how many kinds of weapons the creature can master.
--  weaponKinds: which weapons can be chosen, an id from WeaponMastery.weaponKindOptions.
CharacterModifier.TypeInfo.weaponmastery = {
    init = function(modifier)
        modifier.num = 1
        modifier.weaponKinds = "proficient"
    end,

    createEditor = function(modifier, element)
        local Refresh
        Refresh = function()
            local children = {}

            children[#children+1] = gui.Panel{
                classes = {'formPanel'},
                gui.Label{
                    text = 'Kinds of Weapons:',
                    classes = {'formLabel'},
                },
                gui.GoblinScriptInput{
                    value = modifier:try_get("num", 1),
                    change = function(element)
                        modifier.num = element.value
                        if tonumber(modifier.num) ~= nil and tostring(tonumber(modifier.num)) == modifier.num then
                            modifier.num = tonumber(modifier.num)
                        end
                    end,
                    documentation = {
                        domains = modifier:Domains(),
                        help = "This GoblinScript is the number of kinds of weapons whose mastery properties the creature can use.",
                        output = "number",
                        examples = {
                            {
                                script = "3",
                                text = "The creature can master three kinds of weapons.",
                            },
                        },
                        subject = creature.helpSymbols,
                        subjectDescription = "The creature affected by this modifier",
                        symbols = modifier:HelpAdditionalSymbols(),
                    },
                },
            }

            children[#children+1] = gui.Panel{
                classes = {'formPanel'},
                gui.Label{
                    text = 'Choose From:',
                    classes = {'formLabel'},
                },
                gui.Dropdown{
                    options = WeaponMastery.weaponKindOptions,
                    idChosen = modifier:try_get("weaponKinds", "proficient"),
                    change = function(element)
                        modifier.weaponKinds = element.idChosen
                        Refresh()
                    end,
                },
            }

            element.children = children
        end

        Refresh()
    end,
}

--the creature's mastery slots: total number, and a list of
--{ num = number, weaponKinds = string } per Weapon Mastery modifier.
function creature:WeaponMasterySlots()
    local total = 0
    local groups = {}
    if not GameSystem.WeaponMastery then
        return total, groups
    end

    for _,mod in ipairs(self:GetActiveModifiers()) do
        if mod.mod.behavior == "weaponmastery" then
            local n = dmhub.EvalGoblinScriptDeterministic(mod.mod:try_get("num", 1), self:LookupSymbol(mod.mod:try_get("_tmp_symbols", {})), 0, string.format("Weapon Mastery count for %s", mod.mod.name))
            n = math.max(0, math.floor(tonumber(n) or 0))
            if n > 0 then
                total = total + n
                groups[#groups+1] = {
                    num = n,
                    weaponKinds = mod.mod:try_get("weaponKinds", "proficient"),
                }
            end
        end
    end

    return total, groups
end

--set of weapon kind ids (base item ids) the creature has mastered. Choices beyond
--the creature's current number of slots don't count.
function creature:GetWeaponMasteries()
    local result = {}
    local total = self:WeaponMasterySlots()
    for i,itemid in ipairs(self:try_get("weaponMasteries", {})) do
        if i > total then
            break
        end
        result[itemid] = true
    end
    return result
end

--the mastery property id this creature can use with this weapon, or nil.
function creature:GetWeaponMasteryProperty(weapon)
    if not GameSystem.WeaponMastery then
        return nil
    end

    local propid = WeaponMastery.PropertyOfWeapon(weapon)
    if propid == nil then
        return nil
    end

    if self:GetWeaponMasteries()[WeaponMastery.KindOf(weapon)] then
        return propid
    end

    return nil
end

--the kinds of weapons this creature could choose for its masteries, as dropdown
--options sorted by name. weaponKinds: an id from WeaponMastery.weaponKindOptions.
function creature:WeaponMasteryOptions(weaponKinds)
    local result = {}
    for k,item in pairs(dmhub.GetTable("tbl_Gear") or {}) do
        if item.type == "Weapon" and (not item:try_get("hidden", false)) and (not item:has_key("baseid")) and (not item:has_key("magicalItem")) then
            local propid, propInfo = WeaponMastery.PropertyOfWeapon(item)
            if propid ~= nil and self:ProficientWithItem(item) then
                local melee = EquipmentCategory.meleeWeaponCategories[item:try_get("equipmentCategory", "")] == true
                if weaponKinds ~= "melee" or melee then
                    result[#result+1] = {
                        id = k,
                        text = string.format("%s (%s)", item.name, WeaponMastery.MasteryName(propInfo)),
                    }
                end
            end
        end
    end

    table.sort(result, function(a,b) return a.text < b.text end)
    return result
end

--------------------------------------------------------------------------------
--Effects of masteries during an attack.
--------------------------------------------------------------------------------

--called by ActivatedAbilityAttackBehavior:Cast, in its coroutine, after an attack
--with a mastered weapon has resolved against one target.
--args: { ability, attack, casterToken, targetToken, hit = bool, damageDealt = number, keywords }
function WeaponMastery.AfterAttack(args)
    local propid = args.attack:try_get("mastery")
    if propid == nil or args.targetToken == nil or args.targetToken.properties == nil then
        return
    end

    local propInfo = WeaponProperty.Get(propid)
    if propInfo == nil then
        return
    end

    if args.hit then
        if propInfo:has_key("masteryAbility") and ((not propInfo.masteryRequiresDamage) or (args.damageDealt or 0) > 0) then
            local ability = DeepCopy(propInfo.masteryAbility)
            ability:Cast(args.casterToken, {
                {
                    loc = args.targetToken.loc,
                    token = args.targetToken,
                }
            }, {
                alreadyInCoroutine = true,
                symbols = {
                    masterymodifier = WeaponMastery.AbilityModifier(args.casterToken.properties, args.attack),
                },
            })
        end

        if propid == "mastery-vex" and (args.damageDealt or 0) > 0 then
            WeaponMastery.ApplyVex(args, propInfo)
        end

        if propid == "mastery-cleave" and args.attack:try_get("melee") then
            WeaponMastery.ReadyCleave(args)
        end
    elseif propid == "mastery-graze" then
        WeaponMastery.ApplyGraze(args)
    end
end

--Graze: on a miss, damage equal to the attack's ability modifier, of the weapon's type.
function WeaponMastery.ApplyGraze(args)
    local caster = args.casterToken.properties
    local amount = WeaponMastery.AbilityModifier(caster, args.attack)
    if amount <= 0 then
        return
    end

    local damageType = "slashing"
    local instances = args.attack:try_get("damageInstances", {})
    if instances[1] ~= nil then
        damageType = instances[1].damageType
    end

    local targetCreature = args.targetToken.properties
    local description = string.format("%s's %s (Graze)", creature.GetTokenDescription(args.casterToken), args.attack.name)
    args.targetToken:ModifyProperties{
        description = "Graze",
        execute = function()
            targetCreature:InflictDamageInstance(amount, damageType, args.keywords, description, { attacker = caster })
        end,
    }
end

--Vex: Advantage on your next attack roll against that creature before the end of
--your next turn. Kept as an instance of the masteryEffect ongoing effect on the
--attacker, which remembers the target.
function WeaponMastery.ApplyVex(args, propInfo)
    local effectid = propInfo:try_get("masteryEffect")
    if effectid == nil then
        return
    end

    local caster = args.casterToken.properties
    local targetid = args.targetToken.id
    args.casterToken:ModifyProperties{
        description = "Vex",
        execute = function()
            WeaponMastery.RemoveVex(caster, targetid)
            local instance = caster:ApplyOngoingEffect(effectid, 1, { tokenid = args.casterToken.id }, { untilEndOfTurn = true })
            if instance ~= nil then
                instance.vexTargetId = targetid
            end
        end,
    }
end

--removes the creature's Vex against a target token id.
function WeaponMastery.RemoveVex(c, targetid)
    local effects = c:try_get("ongoingEffects")
    if effects == nil then
        return false
    end

    local newEffects = {}
    local removed = false
    for _,effectInstance in ipairs(effects) do
        if effectInstance:try_get("vexTargetId") == targetid then
            removed = true
        else
            newEffects[#newEffects+1] = effectInstance
        end
    end

    if removed then
        c.ongoingEffects = newEffects
    end

    return removed
end

local function VexInstanceAgainst(c, targetCreature)
    if targetCreature == nil or not c:has_key("ongoingEffects") then
        return nil
    end

    local targetToken = dmhub.LookupToken(targetCreature)
    if targetToken == nil then
        return nil
    end

    for _,effectInstance in ipairs(c:ActiveOngoingEffects()) do
        if effectInstance:try_get("vexTargetId") == targetToken.id then
            return effectInstance
        end
    end

    return nil
end

--a d20 modifier giving Advantage on an attack roll against targetCreature, or nil.
function WeaponMastery.VexModifier(c, targetCreature)
    if not GameSystem.WeaponMastery then
        return nil
    end

    if VexInstanceAgainst(c, targetCreature) == nil then
        return nil
    end

    return CharacterModifier.new{
        behavior = "d20",
        guid = "weapon-mastery-vex",
        name = "Vex",
        source = "Weapon Mastery",
        description = "Advantage on your next attack roll against this creature.",
        subtype = "attack",
        modifyType = "advantage",
        modifyRoll = "",
        skill = "all",
        save = "all",
        activationCondition = true,
    }
end

--after the creature makes an attack roll against targetCreature: that roll used up its Vex.
function WeaponMastery.ConsumeVex(c, targetCreature)
    if VexInstanceAgainst(c, targetCreature) == nil then
        return
    end

    local token = dmhub.LookupToken(c)
    local targetToken = dmhub.LookupToken(targetCreature)
    if token == nil or targetToken == nil then
        return
    end

    token:ModifyProperties{
        description = "Vex used",
        execute = function()
            WeaponMastery.RemoveVex(c, targetToken.id)
        end,
    }
end

local function CurrentTurnId()
    if dmhub.initiativeQueue ~= nil then
        return dmhub.initiativeQueue:GetTurnId() or "none"
    end
    return "none"
end

--the resource ids that limit Cleave and Nick to once per turn.
WeaponMastery.cleaveResourceId = "mastery-cleave"
WeaponMastery.nickResourceId = "mastery-nick"

--Cleave: after a melee hit, you can make one more attack with the weapon against
--a second creature within 5 feet of the first, once per turn. Recorded here and
--offered as a "Cleave" ability (WeaponMastery.FillCleaveAbilities).
function WeaponMastery.ReadyCleave(args)
    local caster = args.casterToken.properties
    local info = {
        weaponid = args.attack:try_get("weaponid"),
        targetid = args.targetToken.id,
        turnid = CurrentTurnId(),
    }

    args.casterToken:ModifyProperties{
        description = "Cleave",
        execute = function()
            caster.cleaveReady = info
        end,
    }
end

--adds a Cleave ability for the attack the creature's last melee hit readied.
--attacks: the creature's attacks (creature:GetAttackActions); result: list of abilities.
function WeaponMastery.FillCleaveAbilities(c, attacks, result)
    local ready = c:try_get("cleaveReady")
    if ready == nil or ready.turnid ~= CurrentTurnId() then
        return
    end

    if c:GetResourceUsage(WeaponMastery.cleaveResourceId, "turn") > 0 then
        return
    end

    for _,attack in pairs(attacks) do
        if attack:try_get("mastery") == "mastery-cleave" and attack:try_get("weaponid") == ready.weaponid and attack:try_get("melee") then
            local cleaveAttack = DeepCopy(attack)
            cleaveAttack.mastery = nil
            cleaveAttack.name = string.format("Cleave (%s)", attack.name)

            --the weapon's damage, without the ability modifier unless it is negative.
            local bonus = attack:try_get("damageAttrBonus", 0)
            local damage = attack:try_get("baseDamage")
            if damage ~= nil and cleaveAttack.damageInstances ~= nil and cleaveAttack.damageInstances[1] ~= nil then
                if bonus < 0 then
                    damage = string.format("%s%d", damage, bonus)
                end
                cleaveAttack.damageInstances[1].damage = damage
            end

            local firstTargetId = ready.targetid
            result[#result+1] = ActivatedAbility.Create{
                name = cleaveAttack.name,
                iconid = attack.iconid,
                temporaryClone = true,
                attackOverride = cleaveAttack,
                description = "Cleave: make a melee attack with this weapon against a second creature within 5 feet of the first that is also within your reach. On a hit it takes the weapon's damage, without your ability modifier unless that modifier is negative. Once per turn.",
                targetType = 'target',
                range = attack:RangeNormal(),
                actionResourceId = 'none',
                usageLimitOptions = {
                    charges = 1,
                    resourceRefreshType = "turn",
                    resourceid = WeaponMastery.cleaveResourceId,
                },
                _tmp_targetFilterFn = function(casterToken, targetToken)
                    if targetToken.id == firstTargetId or targetToken.id == casterToken.id then
                        return false
                    end
                    local firstToken = dmhub.GetTokenById(firstTargetId)
                    if firstToken == nil then
                        return false
                    end
                    return (firstToken:DistanceInFeet(targetToken) - 2.5) <= 5
                end,
                behaviors = {
                    ActivatedAbilityAttackBehavior.new{
                        roll = "",
                    }
                },
            }
        end
    end
end
