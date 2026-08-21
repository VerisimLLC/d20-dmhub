local mod = dmhub.GetModLoading()

--This file is intentionally empty (the live dockable-panel fork is in
--DMHub Core UI). The title bar briefly lived here, but this module loads
--too late in the boot wave for the bar to exist while the user is on the
--lobby; it now lives at the end of DMHub Titlescreen's Styles.lua, which
--loads near the front of the wave.
