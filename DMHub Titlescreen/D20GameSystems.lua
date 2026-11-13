local mod = dmhub.GetModLoading()

--D20GameSystems: points each game system at its root code mod in DMHub's new
--mod set (tools/modset.json). Loads after Titlescreen.lua, which builds the
--list with the legacy mod ids; dmhub.availableGameSystems is that same table,
--so the entries are changed in place and the title screen's pickers see them.
--
--Only the new set's title screen (d20 Titlescreen) registers this file; the
--legacy DMHub Titlescreen mod does not, so legacy DMHub is unchanged.
--
--A game system the new set has no root for is left out of the list, for now
--Pathfinder 2e: its community code mod depends on the legacy mods, and loading
--those under the new set would load two copies of the UI.

local g_systemRoots = {
    ["dmhub-legacy"] = "4c2963bc-ac89-4d35-8ef3-1e6967e03978",     --d20 System 5e
    ["dmhub-dnd2024"] = "b98e1ee2-aa34-45fb-b48b-92021af8fbf0",    --d20 System 5.5e
    ["dmhub-tabularasa"] = "2b85082f-ccfd-4240-8522-733f30e5dd28", --d20 System None
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
end
