local mod = dmhub.GetModLoading()

--D20GameSystems: points each game system at its root code mod in DMHub's new
--mod set (tools/modset.json). Loads after Titlescreen.lua, which builds the
--list with the legacy mod ids; dmhub.availableGameSystems is that same table,
--so the entries are changed in place and the title screen's pickers see them.
--
--Only the new set's title screen (d20 Titlescreen) registers this file; the
--legacy DMHub Titlescreen mod does not, so legacy DMHub is unchanged.
--
--A game system the new set has no root for is left out of the list.
--
--Pathfinder 2e is an official mod in its own repo (dmhub-pf2e) with its own
--root, "Pathfinder 2e System". The legacy community record (a13c3073) that
--Titlescreen.lua names depends on the legacy mods, so the new set never loads it.

local g_systemRoots = {
    ["dmhub-legacy"] = "4c2963bc-ac89-4d35-8ef3-1e6967e03978",     --d20 System 5e
    ["dmhub-dnd2024"] = "b98e1ee2-aa34-45fb-b48b-92021af8fbf0",    --d20 System 5.5e
    ["dmhub-tabularasa"] = "2b85082f-ccfd-4240-8522-733f30e5dd28", --d20 System None
    ["shwayguy-pathfinder2e"] = "dd40258f-0f2f-45d5-b51c-12cdebcba311", --Pathfinder 2e System (dmhub-pf2e repo)
}

local systems = dmhub.availableGameSystems
if type(systems) == "table" then
    local i = 1
    while i <= #systems do
        local root = g_systemRoots[systems[i].id]
        if root ~= nil then
            systems[i].codeMod = root
            i = i + 1
        else
            table.remove(systems, i)
        end
    end

    --5.5e is the default for new games: the New Game panel preselects the
    --first entry. (A game record with no gameSystem still reads as
    --dmhub-legacy in the engine, so existing games stay 5e.)
    for j,system in ipairs(systems) do
        if system.id == "dmhub-dnd2024" then
            table.remove(systems, j)
            table.insert(systems, 1, system)
            break
        end
    end
end
