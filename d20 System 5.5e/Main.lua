local mod = dmhub.GetModLoading()

--d20 System 5.5e: the root code mod for the "dmhub-dnd2024" (2024 rules, SRD
--5.2.1) game system in DMHub's new mod set. It depends on every other mod in
--the set, so it loads last.
--
--The rules themselves live in d20 Rules (DMHub Game Rules/), shared with 5e,
--with 5e behavior as the default. Put the 2024 differences here: set a
--GameSystem switch the shared rules read, or replace a rules function. The
--list of known differences is RULESETS_PLAN.md, Phase 7.
--
--This root loads after the shared UI, so a difference the shared code needs
--while it loads must instead branch on dmhub.gameSystem at load time.
