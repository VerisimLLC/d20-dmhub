local mod = dmhub.GetModLoading()

local Importers
local MatchSignature

local g_attackIcons = {}
import.Register{
    id = "5etools",
    description = "5etools Format Files",
    input = "files",
    priority = 5,
    json = function(importer, doc)
        if importer.init == false then
            importer.init = true
            importer.initImporter(importer)
        end

        local found = false
        for k,items in pairs(doc) do
            if Importers[k] ~= nil and type(items) == "table" then
                local importer = Importers[k]
                for _,item in ipairs(items) do
                    if type(item) == "table" then
                        importer(item)
                        found = true
                    end
                end
            end
        end

        if not found then
            for _,item in ipairs(doc) do
                if importer.json(importer, item) then
                    found = true
                end
            end
        end

        if not found then
            local sig = MatchSignature(doc)
            if sig ~= nil then
                local importer = Importers[sig]
                found = importer(doc)
            end
        end

        return found
    end,

    init = false,

    initImporter = function(importer)
        for k,monster in pairs(assets.monsters) do
            for j,attack in ipairs(monster.properties:try_get("innateAttacks", {})) do
                if attack.iconid ~= "" then
                    g_attackIcons[attack.name] = attack.iconid
                end
            end
            for j,attack in ipairs(monster.properties:try_get("innateActivatedAbilities", {})) do
                if attack.iconid ~= "" then
                    g_attackIcons[attack.name] = attack.iconid
                end
            end
        end
    end,
}

local function AppendDescription(description, entry)
    if type(entry) == "string" then
        if description == "" then
            description = entry
        else
            description = string.format("%s\n%s", description, entry)
        end

    elseif type(entry) == "table" then
        if entry.type == "list" and type(entry.items) == "table" then
            if entry.style == "list-hang-notitle" then
                for _,item in ipairs(entry.items) do
                    local itemDesc = ""
                    for _,subentry in ipairs(item.entries or {}) do
                        itemDesc = AppendDescription(itemDesc, subentry)
                    end
                    description = AppendDescription(description, string.format(" %s <b>%s.</b> %s", Styles.bullet, item.name, itemDesc))
                end

            end
        end
    end

    return description
end

local function ParseResistanceType(c, doc, srcType, dstType)
    for _,entry in ipairs(doc[srcType] or {}) do
        if type(entry) == "table" then
            local note = entry.note or ""
            local nonmagic = nil
            if string.find(note, "nonmagic") then
                nonmagic = true
            end
            for _,damageType in ipairs(entry[srcType] or {}) do
                c.resistances[#c.resistances+1] = ResistanceEntry.new{
                    apply = dstType,
                    damageType = damageType,
                    nonmagic = nonmagic,
                }
            end
        else
            local damageType = entry
            c.resistances[#c.resistances+1] = ResistanceEntry.new{
                apply = dstType,
                damageType = damageType,
            }
        end
    end
end

local g_Signatures = {
    monster = {
        keys = {"size", "type", "alignment", "ac", "hp", "str", "cr"},
        requirement = 4,
    },
    spell = {
        keys = {"school", "components", "entriesHigherLevel"},
        requirement = 2,
    }
}


MatchSignature = function(doc)
    if doc.name == nil then
        return nil
    end

    for sigkey,entry in pairs(g_Signatures) do
        local score = 0
        for _,key in ipairs(entry.keys) do
            if doc[key] ~= nil then
                score = score+1
            end
        end

        if score >= entry.requirement then
            return sigkey
        end
    end

    return nil
end

Importers = {
    spell = function(spell)

        local bookmark = import:BookmarkLog()

        local school
        if Spell.schoolsByChar[spell.school] ~= nil then
            school = Spell.schoolsByChar[spell.school].id
        end

        local description = ""

        for i,entry in ipairs(spell.entries or {}) do
            description = AppendDescription(description, entry)
        end

        if type(spell.entriesHigherLevel) == "table" then
            for i,higherLevelEntry in ipairs(spell.entriesHigherLevel) do
                if higherLevelEntry.type == "entries" and type(higherLevelEntry.entries) == "table" then
                    for n,entry in ipairs(higherLevelEntry.entries) do
                        description = AppendDescription(description, entry)
                    end
                end
            end
        end

        local range
        local radius
        local targetType

        if type(spell.range) == "table" then
            local t = spell.range.type
            if t == "cone" then
                targetType = "cone"
            elseif t == "point" then
                targetType = "target"
            elseif t == "line" then
                targetType = "line"
            elseif t == "radius" then
                targetType = "self"
            elseif t == "sphere" then
                targetType = "self"
            elseif t == "cube" then
                targetType = "cube"
            else
                import:Log(string.format("Unimplemented range type: %s", tostring(t)))
            end

            if type(spell.range.distance) == "table" then
                local units = spell.range.distance.type
                if units == "self" then
                    targetType = "self"
                elseif units == "feet" then
                    range = spell.range.distance.amount
                elseif units == "touch" then
                    range = 5
                else
                    import:Log(string.format("Unimplemented unit type: %s", tostring(units)))
                end
            end
        end

        if targetType == "cube" then
            radius = range
            range = 5
        end

        local componentCost = nil
        local components = {}
        if type(spell.components) == "table" then
            for k,v in pairs(spell.components) do
                if type(v) == "table" then
                    components[k] = v.text
                    if type(v.cost) == "number" then
                        componentCost = v.cost*0.01
                    end
                else
                    components[k] = v
                end
            end

        end

        local newSpell = Spell.Create{
            name = spell.name,
            level = tonumber(spell.level),
            school = school,
            description = description,
            components = components,
            componentCost = componentCost,
            range = range,
            radius = radius,
            targetType = targetType,
        }

        if type(spell.duration) == "table" then
            for _,entry in ipairs(spell.duration) do
                if entry.type == "instant" then
                    newSpell.durationType = "instant"
                    
                elseif entry.type == "timed" then
                    local duration = entry.duration
                    if type(duration) == "table" then
                        if duration.type == "round" then
                            newSpell.durationType = "rounds"
                        elseif duration.type == "minute" then
                            newSpell.durationType = "minutes"
                        elseif duration.type == "hour" then
                            newSpell.durationType = "hours"
                        elseif duration.type == "day" then
                            newSpell.durationType = "days"
                        else
                            import:Log(string.format("Unimplemented duration type: %s", duration.type))
                        end

                        newSpell.durationLength = duration.amount
                    else
                        import:Log(string.format("Could not find duration on timed spell"))
                    end

                elseif entry.type == "permanent" or entry.type == "special" then
                    newSpell.durationType = "indefinite"
                else
                    import:Log(string.format("Unimplemented duration entry type: %s", entry.type))
                end
            end
        end



        if type(spell.time) == "table" then
            for _,entry in ipairs(spell.time) do
                if entry.unit == "action" then
                    newSpell.actionResourceId = "standardAction"
                elseif entry.unit == "bonus" then
                    newSpell.actionResourceId = "bonusAction"
                elseif entry.unit == "reaction" then
                    newSpell.actionResourceId = "bonusAction"
                elseif entry.unit == "movement" then
                    newSpell.actionResourceId = "movementAction"
                elseif entry.unit == "minute" then
                    newSpell.castingTimeDuration = string.format("%d %s", entry.number, entry.unit)
                elseif entry.unit == "hour" then
                    newSpell.castingTimeDuration = string.format("%d %s", entry.number, entry.unit)
                else
                    import:Log(string.format("Unknown time unit: %s", tostring(entry.unit)))
                end
            end
        end

        import:StoreLogFromBookmark(bookmark, newSpell)

        import:ImportAsset("Spells", newSpell)
    end,

    monster = function(doc)
        local bookmark = import:BookmarkLog()

        local is_character = doc.isNamedCreature

        local m

        if is_character then
            local token = import:CreateCharacter()
            token.properties = monster.CreateNew()

            local partiesTable = dmhub.GetTable(Party.tableName)
            local targetParty = nil
            for partyid,partyInfo in pairs(partiesTable) do
                if partyInfo:try_get("hidden", false) == false and partyid ~= GetDefaultPartyID() and (targetParty == nil or string.find(partyInfo.name, "NPC")) then
                    targetParty = partyid

                end
            end

            if targetParty ~= nil then
                token.partyId = targetParty
            else
                token.partyId = GetDefaultPartyID()
            end

            m = token
        else
            m = import:GetExistingItem("monster", doc.name)
            if m == nil then
                m = import:CreateMonster()
                m.properties = monster.CreateNew()
            end
        end


        local c = m.properties

        m.name = doc.name
        c.monster_type = doc.name

        for _,attrid in ipairs(creature.attributeIds) do
            if doc[attrid] ~= nil then
                c.attributes[attrid] = { baseValue = doc[attrid] }
            else
                c.attributes[attrid] = { baseValue = 10 }
                import:Log(string.format("Could not find attribute %s", attrid))
            end
        end

        if type(doc.hp) == "table" then
            c.max_hitpoints = doc.hp.average
            c.max_hitpoints_roll = doc.hp.formula or tostring(c.max_hitpoints)
        else
            import:Log("Could not find hitpoints")
        end

        for _,entry in ipairs(doc.ac or {}) do
            if type(entry) == "number" then
                c.armorClassOverride = entry
            elseif type(entry) == "table" then
                c.armorClassOverride = entry.ac
            else
                import:Log(string.format("Unrecognized armor class: %s", json(entry)))
            end
        end

        for _,sizeStr in ipairs(doc.size or {}) do
            for _,size in ipairs(creature.sizes) do
                if string.starts_with(size, sizeStr) then
                    c.creatureSize = size
                end
            end
        end

        if doc.type ~= nil then
            c.monster_category = doc.type
        else
            import:Log("No monster type found")
        end

        for k,v in pairs(doc.speed or {}) do
            if type(v) == "number" then
                c:SetSpeed(k, v)
            elseif type(v) == "table" and type(v.number) == "number" then
                c:SetSpeed(k, v.number)
            else
                --can also have properties like canHover: true -- not sure if we want to handle in some way.
            end
        end

        --alignment
        if doc.alignment == nil or #doc.alignment ~= 2 then
            c.alignment = "unknown"
        else
            local alignmentTables = {
                C = "chaotic",
                L = "lawful",
                N = "neutral",
                G = "good",
                E = "evil",
            }

            c.alignment = ""
            for _,align in ipairs(doc.alignment) do
                if alignmentTables[align] == nil then
                    import:Log("Unrecognized alignment")
                    c.alignment = "unknown"
                    break
                else
                    if c.alignment ~= "" then
                        c.alignment = c.alignment .. " "
                    end

                    c.alignment = c.alignment .. alignmentTables[align]
                end
            end

            if c.alignment == "neutral neutral" then
                c.alignment = "true neutral"
            end
        end

        c.resistances = {}

        ParseResistanceType(c, doc, "resist", "Resistant")
        ParseResistanceType(c, doc, "vulnerable", "Vulnerable")
        ParseResistanceType(c, doc, "immune", "Immune")

        local conditionTable = dmhub.GetTable(CharacterCondition.tableName)
        
        for i,condid in ipairs(doc.conditionImmune or {}) do
            if type(condid) ~= "string" then
                import:Log(string.format("Unrecognized condition format instead of id: %s", json(condid)))
            else
                local found = false
                for k,v in pairs(conditionTable) do
                    if condid == string.lower(v.name) then
                        if c:try_get("innateConditionImmunities") == nil then
                            c.innateConditionImmunities = {}
                        end

                        c.innateConditionImmunities[k] = true
                        found = true
                        break
                    end
                end

                if not found then
                    import:Log(string.format("Unknown condition: %s", condid))
                end
            end
        end

        local innateActivatedAbilities = {}

        --a list of abilities to process. Each item in the list is a {name: string, text: string, recharge: number?}
        local rawAbilities = {}

        for _,action in ipairs(doc.action or {}) do
            local name = action.name
            local i1,i2,rechargeStr = string.find(name, " {@recharge (%d)}")
            local recharge = nil
            if rechargeStr then
                recharge = tonumber(rechargeStr)
                name = string.sub(name, 1, i1-1)
            end


            local foundList = false
            local text = ""
            for j,entry in ipairs(action.entries or {}) do
                if type(entry) == "string" then
                    if text ~= "" then
                        text = text .. "\n"
                    end
                    text = text .. entry
                elseif type(entry) == "table" and entry.type == "list" and type(entry.items) == "table" then
                    foundList = true

                    for _,listEntry in ipairs(entry.items) do
                        if type(listEntry.name) == "string" and type(listEntry.entry) == "string" then
                            rawAbilities[#rawAbilities+1] = {
                                name = name,
                                recharge = recharge,
                                text = listEntry.entry,
                            }
                        else
                            import:Log("Unrecognized action format in sub-list for " .. name)
                        end
                    end

                else
                    import:Log("Unrecognized action format for " .. name)
                end
            end

            if text ~= "" and foundList == false then
                rawAbilities[#rawAbilities+1] = {
                    name = name,
                    recharge = recharge,
                    text = text,
                }
            end
        end
        
        for _,action in ipairs(rawAbilities) do
            local name = action.name

            local entry = action.text

            if string.starts_with(entry, "{@atk") then
                local i,j = string.find(entry, "{@atk [,a-z ]+}")
                if i == nil then
                    i,j = string.find(entry, "{@atkr [,a-z ]+}")
                    
                end

                if i == nil then
                    import:Log("Could not recognize attack: " .. entry)
                else
                    local attackTypes = {"rw", "mw", "rs", "ms", " m", " r"}
                    local foundAttackType = nil
                    local atk = string.sub(entry, i,j)
                    for _,attackType in ipairs(attackTypes) do
                        if string.find(atk, attackType) then
                            foundAttackType = attackType
                            break
                        end
                    end

                    --new rules just have 'melee' and 'ranged' so map them to melee weapon and ranged weapon
                    if foundAttackType == " m" then
                        foundAttackType = "mw"
                    elseif foundAttackType == " r" then
                        foundAttackType = "rw"
                    end

                    if foundAttackType == nil then
                        import:Log("Could not find attack type: " .. entry)
                        foundAttackType = "mw"
                    end

                    local _,_,hit_bonus = string.find(entry, "{@hit (%d+)}")
                    if hit_bonus == nil then
                        import:Log("Could not find hit bonus in attack: " .. entry)
                        hit_bonus = 0
                    end

                    local range
                    local rangeDisadvantage

                    if foundAttackType == "rs" then
                        _,_,range = string.find(entry, "range (%d+) ft")
                        if range == nil then
                            import:Log("Could not find range in attack: " .. entry)
                            range = 30
                        end
                        range = tonumber(range)
                    elseif foundAttackType == "rw" then
                        _,_,range,rangeDisadvantage = string.find(entry, "range (%d+)/(%d+) ft")
                        if range == nil then
                            import:Log("Could not find range in attack: " .. entry)
                            range = 30
                            rangeDisadvantage = 120
                        end
                        range = tonumber(range)
                        rangeDisadvantage = tonumber(rangeDisadvantage)
                    else
                        _,_,range = string.find(entry, "reach (%d+) ft")
                        if range == nil then
                            import:Log("Could not find reach in attack: " .. entry)
                            range = 5
                        end
                        range = tonumber(range)
                    end

                    local damageEntries = {}
                    for dmg, dmgType in entry:gmatch("%{@damage ([%d+d%s%p]+)%}%) (%w+) damage") do
                        table.insert(damageEntries, {damageRoll = dmg, damageType = dmgType})
                    end

                    if #damageEntries == 0 then
                        local _,_,damageRoll,damageType = string.find(entry, ".{@damage (.+)}. (%a+) damage")
                        if damageRoll == nil then
                            --backup for damage, just literally one damage specified bare.
                            _,_,damageRoll,damageType = string.find(entry, "{@h}(1) (%a+) damage")
                        end

                        if damageRoll == nil then
                            import:Log("Could not find damage roll in attack2: " .. entry)
                            damageRoll = "1"
                            damageType = "piercing"
                        end

                        damageEntries[#damageEntries+1] = {
                            damageRoll = damageRoll,
                            damageType = damageType,
                        }
                    end

                    local damageRoll = damageEntries[1].damageRoll
                    local damageType = damageEntries[1].damageType

                    local magicalDamage = (foundAttackType == "ms" or foundAttackType == "rs")

                    if #damageEntries > 1 then
                        local magical = cond(magicalDamage, "Magical ", "")
                        damageRoll = ""
                        for i,entry in ipairs(damageEntries) do
                            if i ~= 1 then
                                damageRoll = damageRoll .. " "
                            end

                            damageRoll = string.format("%s%s [%s%s]", damageRoll, entry.damageRoll, magical, entry.damageType)
                        end
                    end

                    local attackBehavior = ActivatedAbilityAttackBehavior.new{
                        attackType = cond(foundAttackType == "mw" or foundAttackType == "ms", "Melee", "Ranged"),
                        hit = hit_bonus,
                        roll = damageRoll,
                        damageType = damageType,
                        magicalDamage = magicalDamage
                    }

                    local formatAttack = function(s)
                        -- Replace the attack type abbreviations
                        s = s:gsub("{@atk mw}", "Melee Weapon Attack")
                        s = s:gsub("{@atk rw}", "Ranged Weapon Attack")
                        s = s:gsub("{@atk ms}", "Melee Spell Attack")
                        s = s:gsub("{@atk rs}", "Ranged Spell Attack")
                        
                        -- Format the hit bonus
                        s = s:gsub("{@hit (%d+)}", "+%1 to hit")
                        
                        -- Remove the health/hit point tag (assuming it's not required in the output)
                        s = s:gsub("{@h}%d+ ", "")
                        
                        -- Format the damage entries
                        s = s:gsub("{@damage ([%d+d%s%p]+)}", "%1")
                        
                        return s
                    end
                    

                    local abilityArgs = {
                        name = name,
                        iconid = g_attackIcons[name] or "",
                        description = formatAttack(entry),
                        targetType = "target",
                        range = range,
                        rangeDisadvantage = rangeDisadvantage,
                        behaviors = {attackBehavior},
                    }

                    local ability
                    if foundAttackType == "ms" or foundAttackType == "rs" then
                        ability = Spell.Create(abilityArgs)
                    else
                        ability = ActivatedAbility.Create(abilityArgs)
                    end

                    innateActivatedAbilities[#innateActivatedAbilities+1] = ability
                end
            else
                --not an attack action.
                local abilityArgs = {
                    name = name,
                    iconid = "",
                    description = entry,
                }

                local ability = ActivatedAbility.Create(abilityArgs)
                innateActivatedAbilities[#innateActivatedAbilities+1] = ability
            end
        end
        
        c.innateActivatedAbilities = innateActivatedAbilities

        import:StoreLogFromBookmark(bookmark, m)

        if is_character then
            import:ImportCharacter(m)
        else
            import:ImportMonster(m)
        end
    end,
}
