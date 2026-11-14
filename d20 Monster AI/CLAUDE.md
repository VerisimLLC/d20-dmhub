# d20 Monster AI

Plays monsters automatically under D&D 5.5e (2024) rules: movement, attacks,
Multiattack, spells and areas, saving throws, opportunity attacks, legendary
actions, Nimble Escape-style bonus actions, healing, retreat, and in-character
speech. It is the d20 counterpart of the Codex's Draw Steel `Monster AI` mod
and follows its shape: a DockablePanel "Monster AI" with Start/Stop, a
background thread, a move registry, a decision log, speech bands.

Cloud mod guid `3d12f7c0-bbe1-4e3f-a1c8-a8a71d96a963` (entry `monsterai` in
`tools/modset.json`; depends on hud, tokenui, chatpanel, charsheet). Files load
in this order; new files must be registered through the mod system (MCP
`register_lua_file`) and added to `modset.json`, never just dropped here.

| File | What it holds |
|---|---|
| `MonsterAI.lua` | Core: the `MonsterAI` class, registries (`RegisterMove`, `RegisterSpeech`, `RegisterTactic`, `RegisterPrompt`), settings (`monsterai:*`), decision log (`LogDecision`, prints `AI::`), coroutine helpers, waiting-for-player notice, speech, movement (`CalculateMovementPaths`, `MoveToken`), `ExecuteAbility`, `AwaitRollRequest`, `PlayTurn`, the Creature.lua hook overrides. |
| `MonsterAIRules.lua` | `MonsterAIRules`: the 5e rules reading. Conditions, resources/action economy, `ProfileAbility` (what an ability does, in numbers), hit/save odds, expected damage, Multiattack text parsing, loadout switching. |
| `MonsterAIGeneric.lua` | `MonsterAIGeneric`: the generic planner every monster uses. Builds a context, scores routines (single attacks and Multiattack) from each reachable square, aims areas, and registers the generic moves (action, bonus, heal, escape, advance, reposition, flee, dodge). Legendary planning and opportunity attacks. |
| `MonsterAIPreview.lua` | Plan preview: before each move, show the plan (arrow, targets, area) and wait for the DM's Proceed / Skip / Play Entire Turn. Shared through the `monsterAIPreview` document so every client draws it. |
| `MonsterAIPanel.lua` | The DockablePanel, and the AI thread (`StartAI`/`StopAI`): opportunity-attack watch, legendary windows at turn changes, playing AI initiative entries and ending their turn. |
| `MonsterAIPrompts.lua` | Fallback answers when an ability asks for targets mid-cast. |
| `MonsterAITactics.lua` | Per-monster tactics (focus, flee threshold, preferred/avoided abilities), defaults by Intelligence. |
| `MonsterAISupport.lua` | `MonsterAI.AssessSupport(token)`: how much of a stat block the AI plays, shown per monster type in the panel. |
| `MonsterAIBands.lua` | Hand-written tactics and speech for monster families (goblins, kobolds, wolves, dragons, ...) plus band moves (Nimble Escape hit-and-run, dragon Breath Weapon). |

## Rules hooks outside this mod

All are no-ops unless the AI runs. In `DMHub Game Rules/Creature.lua`:
`BeginAIControl`/`EndAIControl`/`IsTokenAIControlled`/`ClearAIControl`,
`Get/SetTokenAIActivity`, `Get/SetAIActivityInProgress`,
`AIRollsForCreature`, `AIAwaitRollRequest`, `AIPromptCallbackForToken`,
`CharacterSpeech`/`GetAndRemoveSpeech`. `ActivatedAbility.AwaitCastRollRequest`
and `ActivatedAbility.PromptTargets` (`ActivatedAbility.lua`, used by
`AbilityInvokeAbility.lua`). The roll dialog autorolls for AI creatures
(`DMHub Game Hud/RollDialog.lua`, a d20-kept file). Speech balloons draw in
`DMHub Token UI/TokenUI.lua`.

## How a turn is decided

`PlayTurn` loops up to 8 cycles: build a context (`BuildContext`), score every
registered move whose category is open (`ScoreMoves`), run the best
(`FindAndExecuteMove`), repeat until nothing scores. Scores are 0..1-ish;
`generic-action` turns expected damage into a score, tactic moves can outbid it
(Breath Weapon 1.05 with two or more enemies caught). Limited resources carry a
cost in expected damage (`UseCost`: spell slot `1 + 2*level`, recharge `+4`).

Testing: `MonsterAI.log` holds the last 300 decisions; the console shows them
with pattern `AI::`. A dry run that scores without acting:

```lua
local ai = MonsterAI.new{}; ai.turn = {}
local ctx = MonsterAIGeneric.BuildContext(ai, token)
for _,s in ipairs(ai:ScoreMoves(token, ctx, MonsterAI.turnCategories)) do print(s.score, s.move.id, s.plan and s.plan.description) end
```

## Gotchas

- **`MonsterAI.X` and `MonsterAI:X` are the same field.** Defining both
  `function MonsterAI.RunYieldingFunction(fn)` and
  `function MonsterAI:RunYieldingFunction(fn) return MonsterAI.RunYieldingFunction(fn) end`
  made the method replace the static one and call itself as a *tail call*: an
  infinite loop with no stack growth, which froze the whole app on the AI's
  first tick with no error. One function now accepts both call styles.
- **`token:Move` caps the path at 30 decis (3 squares) by default.** Pass
  `maxCost` (MoveToken defaults it to 10000, as the Codex does).
- **`GameHud.instance` is `false`, not nil, while the HUD rebuilds** (just after
  a Lua reload). Guard with `if not hud`.
- Reading an unknown field on a creature or ability throws; use `try_get` or
  existing methods. `_tmp_` fields get wiped, so AI control state lives in
  Creature.lua locals. `print` stops at the first nil argument; wrap in
  `tostring`.
- Spawned bestiary tokens have no `name`; use `MonsterAI.DisplayName`.
- A Lua reload ends the AI thread (`mod.unloaded`); press Start again.

## Not played (by design or not yet)

Legendary Resistance (left to the DM), reactions other than opportunity
attacks (Shield, Counterspell, Redirect Attack), buffs/utility spells, abilities
whose effect is only text (e.g. Fiery Rays, Commanding Presence). Opportunity
attacks resolve after the mover's move rather than interrupting it. The panel's
per-monster support summary lists exactly what each stat block loses.
