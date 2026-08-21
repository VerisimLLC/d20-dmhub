local mod = dmhub.GetModLoading()

function table.contains(table, element)
    for _, value in pairs(table) do
        if value == element then
            return true
        end
    end
    return false
end

function table.count_elements(t)
    local count = 0
    for _, _ in pairs(t) do
        count = count + 1
    end
    return count
end

function table.remove_value(t, element)
    for i=#t, 1, -1 do
        if t[i] == element then
            table.remove(t, i)
        end
    end
end

function table.empty(t)
    return next(t) == nil
end

function table.keys(t)
    local keys = {}
    for k, _ in pairs(t) do
        keys[#keys+1] = k
    end
    return keys
end

function table.values(t)
    local values = {}
    for _, v in pairs(t) do
        values[#values+1] = v
    end
    return values
end

function table.shallow_copy(t)
    local result = {}
    for k,v in pairs(t) do
        result[k] = v
    end

    return result
end

function sorted_pairs(t)
    local keys = table.keys(t)
    table.sort(keys)
    local nextKey = {}
    for i, key in ipairs(keys) do
        nextKey[key] = keys[i+1]
    end
    nextKey[0] = keys[1]
    return function(a, key)
        key = nextKey[key]
        if key ~= nil then
            local value = t[key]
            return key, value
        end
    end, t, 0
end

local next_unhidden = function(t, key)
    local val
    key, val = next(t, key)
    while val ~= nil and rawget(val, "hidden") do
        key, val = next(t, key)
    end

    return key, val
end

function unhidden_pairs(t)
    return next_unhidden, t, nil
end

---@param s string
---@return string
function string.trim(s)
    if type(s) ~= "string" then
        return s
    end
    local a = s:match('^%s*()')
    local b = s:match('()%s*$', a)
    return s:sub(a,b-1)
 end
 
function string.starts_with(String,Start)
	return string.sub(String,1,string.len(Start)) == Start
end

function string.ends_with(str, ending)
    return ending == "" or str:sub(-#ending) == ending
end

function math.clamp(x, a, b)
    if x < a then
        return a
    end

    if x > b then
        return b
    end

    return x
end

function math.clamp01(x)
    if x < 0 then
        return 0
    end

    if x > 1 then
        return 1
    end

    return x
end


function MatchesSearchRecursive(obj, search)
    if type(obj) == "table" then
        for k,v in pairs(obj) do
            if MatchesSearchRecursive(k, search) or MatchesSearchRecursive(v, search) then
                return true
            end
        end
    elseif type(obj) == "string" then
        if string.find(string.lower(obj), search) ~= nil then
            return true
        end
    end

    return false
end

function SearchTableForText(t, search)
    local results = {}
    for k,v in pairs(t) do
        if MatchesSearchRecursive(v, search) then
            results[#results+1] = k
        end
    end

    return results
end

-- =============================================================================
-- Macro registration infrastructure (ported from the Draw Steel Codex).
-- The Commands table is created by the engine's core Lua (commands.txt) before
-- mods load; create it defensively in case the load order ever changes.
-- =============================================================================

if rawget(_G, "Commands") == nil then
    Commands = {}
end

Commands._macros = Commands._macros or {}

function Commands.RegisterMacro(args)
    local name = args.name
    local fn = args.command
    local doc = args.doc
    local summary = args.summary

    if doc ~= nil then
        Commands[name] = function(str)
            if str == "help" then
                dmhub.Log(doc)
                return
            end
            return fn(str)
        end
    else
        Commands[name] = fn
    end

    Commands._macros[name] = {
        doc = doc,
        summary = summary,
        completions = args.completions,
    }
end

--Splits a macro argument string into an array of arguments. Arguments are
--separated by whitespace; double-quoted sections become a single argument
--with the quotes removed.
if Commands.SplitArgs == nil then
    function Commands.SplitArgs(str)
        local args = {}
        local i = 1
        str = str or ""
        while i <= #str do
            local c = str:sub(i, i)
            if c:match("%s") then
                i = i + 1
            elseif c == '"' then
                local closing = str:find('"', i + 1, true)
                if closing == nil then
                    args[#args+1] = str:sub(i + 1)
                    i = #str + 1
                else
                    args[#args+1] = str:sub(i + 1, closing - 1)
                    i = closing + 1
                end
            else
                local spacePos = str:find("%s", i)
                local last = (spacePos or (#str + 1)) - 1
                args[#args+1] = str:sub(i, last)
                i = last + 1
            end
        end
        return args
    end
end

-- =============================================================================
-- EventUtils (ported from the Draw Steel Codex). The legacy DMHub_Core_UI mod's
-- Utils.lua also defines an identical EventUtils; redefining it here would
-- reset the handler registry and strand any handlers registered against the
-- earlier table, so only define it when it is absent.
-- =============================================================================

if rawget(_G, "EventUtils") == nil then

    local g_globalEventHandlers = {}

    EventUtils = {
        FireGlobalEvent = function(eventName, ...)
            local eventList = g_globalEventHandlers[eventName]
            if eventList ~= nil then
                for _,entry in ipairs(eventList) do
                    entry.handlerfn(...)
                end
            end
        end,

        RegisterGlobalEventHandler = function(mod, eventName, handlerfn)
            local guid = dmhub.GenerateGuid()
            g_globalEventHandlers[eventName] = g_globalEventHandlers[eventName] or {}
            local eventList = g_globalEventHandlers[eventName]
            local entry = {
                guid = guid,
                handlerfn = handlerfn,
            }

            eventList[#eventList+1] = entry

            local unloadfn = function()
                local eventList = g_globalEventHandlers[eventName]
                if eventList == nil then
                    return
                end
                local newEventList = {}
                for _,entry in ipairs(eventList) do
                    if entry.guid ~= guid then
                        newEventList[#newEventList+1] = entry
                    end
                end

                g_globalEventHandlers[eventName] = newEventList
            end

            mod.unloadHandlers[#mod.unloadHandlers+1] = unloadfn
            entry.Deregister = unloadfn
            return entry
        end,
    }

end

--split that keeps empty entries ("a||b" -> {"a", "", "b"}), unlike
--string.split which drops them. Ported from the codex utils for the
--markdown document system.
function string.split_allow_duplicates(inputstr, sep)
        if sep == nil then
                sep = "%s"
        end
        local t={}
        for str in string.gmatch(inputstr, "([^"..sep.."]*)") do
                table.insert(t, str)
        end
        return t
end

--split on sep, but ignore separators inside [square brackets] so markdown
--table cells can contain [[links|with pipes]]. Ported from the codex utils.
function string.split_with_square_brackets(inputstr, sep)
    local result = {}
    local chars = {}
    local depth = 0
    for i = 1, #inputstr do
        local c = inputstr:sub(i,i)
        if depth <= 0 and c == sep then
            result[#result+1] = table.concat(chars)
            chars = {}
        else
            if c == "[" then
                depth = depth+1
            elseif c == "]" then
                depth = depth-1
            end

            chars[#chars+1] = c
        end
    end

    result[#result+1] = table.concat(chars)
    return result
end

--keep only the elements of array t for which f returns true. (Used by
--the title bar's Panels menu.)
function table.filter(t, f)
    local result = {}
    for _, v in ipairs(t or {}) do
        if f(v) then
            result[#result+1] = v
        end
    end
    return result
end

--stable sort: equal elements keep their original order, which table.sort
--does not guarantee. Ported from the codex utils.
function table.stable_sort(t, cmp)
    -- decorate with original indices
    local decorated = {}
    for i, v in ipairs(t) do
        decorated[i] = { value = v, index = i }
    end

    -- sort with index tie-breaker
    table.sort(decorated, function(a, b)
        if cmp(a.value, b.value) then
            return true
        elseif cmp(b.value, a.value) then
            return false
        else
            return a.index < b.index
        end
    end)

    -- write back
    for i, d in ipairs(decorated) do
        t[i] = d.value
    end
end
