local mod = dmhub.GetModLoading()

--d20 System 5e: the root code mod for the "dmhub-legacy" (5e, SRD 5.1) game
--system in DMHub's new mod set. It depends on every other mod in the set, so
--it loads last.
--
--The rules themselves live in d20 Rules (DMHub Game Rules/), shared with 5.5e,
--with 5e behavior as the default. Put code here only where 5e must differ from
--that shared default: set a GameSystem switch or replace a rules function.
--See SHARED_UI_LAYER_PLAN.md ("How 5e and 5.5e share the rules").
