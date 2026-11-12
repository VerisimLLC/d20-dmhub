# Codex sync: the shared UI layer comes from the Draw Steel Codex

DMHub (this repo, the D&D 5e system) and the Draw Steel Codex run on the same
engine and share the same game-system-neutral Lua mods (same mod ids:
`DMHub_Core_UI_752e`, `DMHub_Core_Panels_65a9`, `DMHub_Game_Hud_efeb`,
`DMHub_Utils_5b73`, ...). The Codex develops that layer much faster, so it is
the **upstream** for it: d20 takes the Codex's files as they are and keeps only
the 5e rules and a few 5e-specific UI files of its own.

First sync: 2026-11-11, from Codex commit `39890461` (the commit the engine at
`3e4609f36` pins), to bring over the tabletop (map windows, Scenes, the DM's
Screen, desktop media drops). Decisions (David, 2026-11-11): re-sync the
shared layer rather than transplant the tabletop alone; take the Codex's
versions of what Shwayguy had ported by hand, keeping 5e-specific pieces;
keep d20's own DMHub Game Rules and add shims for what the new UI calls.

## Running a sync

```bash
# the Codex commit this engine pins
git -C C:/dev/d20-dmhub ls-tree HEAD draw-steel-codex
# export it somewhere empty (never sync from a working copy with local edits)
git -C <draw-steel-codex repo> archive <sha> | tar -x -C <empty dir>
python tools/codex_sync.py <empty dir>            # dry run: what would change
python tools/codex_sync.py <empty dir> --apply
```

Then syntax-check (`luac -p`, see the engine tree's CLAUDE.md), review the git
diff, register any file the report marks `NEW` in the DMHub cloud (in-app Code
Mods editor, or the MCP `register_lua_file` tool, placing it where the Codex
loads it), and test in a DMHub build. A sync stops if a recorded patch no
longer matches upstream, or if a verbatim copy (below) has gone stale; that is
the point to look at what changed in the Codex.

`tools/codex_sync.py` is the manifest. Everything below is what it encodes.

## What is synced

| Codex | d20 |
|---|---|
| `DMHub Core UI/*` | `DMHub Core UI/` (except `ThemeEngine.lua`, see below) |
| `DMHub Core Panels/*` | `DMHub Core Panels/` |
| `DMHub Game Hud/*` | `DMHub Game Hud/` |
| `DMHub Utils/*` | `DMHub Utils/` |
| `DocumentSystem/*` (its own mod in the Codex) | end of `DMHub Game Hud/` |
| `ChatPanel/*` (its own mod in the Codex) | `DMHub Core Panels/` |
| `DMHub Core UI/ThemeEngine.lua` | `DMHub Titlescreen/ThemeEngine.lua` |
| `DMHub Game Rules/MeasurementSystem.lua` | same (a strict superset of d20's: world/hex map settings) |

d20 does not create new cloud mods for DocumentSystem and ChatPanel; their
files live in existing mods, ordered as the Codex loads them. DocumentSystem
must load **after** Game Hud (it uses Game Hud while it loads), which is why it
sits at the end of Game Hud's file list. Its files' old copies in
`DMHub Core UI/` are still registered there (a file cannot be unregistered), so
the sync writes them as one-line "Moved to ..." stubs.

ThemeEngine lives in Titlescreen because at the cold-boot title screen only
DMHub Titlescreen is loaded, and d20's title bar (`Styles.lua`) uses it.

## What d20 keeps (not synced)

- **Mods:** DMHub Game Rules (except MeasurementSystem.lua), DMHub 5e System,
  DMHub CharacterSheet Base / 5e, DMHub Compendium, DMHub Import Framework,
  DMHub Token UI, DMHub Map Markup, 5eTools Importer, DMHub Titlescreen
  (except ThemeEngine.lua).
- **Files in synced mods** (`KEEP_D20`): the 5e action bar, initiative bar,
  roll dialog, rest dialog, DC dialog and roll-on-table dialog; the 5e
  character panel side panel (`CharacterPanel.lua`); and the dev panels and
  dice panel the Codex has emptied out (`AIPanel`, `Devtools`, `DicePanel`,
  `GoblinScriptDebugger`).
- **Not brought over** (`SKIP`): Draw Steel journal content (encounters,
  followers, montages, heroic tests, campaign tracker, games of chance, party
  and resource widgets), puzzles (a feature not ported yet), and empty stubs.

DMHub Token UI was not synced: the Codex's version needs the Codex rules'
damage-entry records, which the 5e rules do not have.

## The d20 side

Synced files stay byte-identical to the Codex where possible. What d20 needs
on top lives in d20-only files:

| File | What it does |
|---|---|
| `DMHub Game Hud/D20CodexCompat.lua` | First in Game Hud. Stand-ins for Codex-only modules the synced code calls: `CodexTitleBar` (map position readout in a map window's titlebar), `TopBar`, `DSVictoryScreen`, `EotwHeroCard` (the character/creature card on the table, 5e hit points instead of Draw Steel stamina), `MonsterKnowledge`/`MonsterInfoDialog`, `RollOnTableProperties`, `SendTitledChatMessage` (to the log), `Commands.SplitArgs`, `ActivatedAbilityPowerRollBehavior` (edges/banes: always zero in 5e), and rules methods the 5e rules lack (`IsHero`, `IsMonster`, `Language:DisplayName`, ...). Each is defined only when the real one is missing. |
| `DMHub Core UI/D20LoadOrder.lua` | First in Core UI. d20 loads DMHub Utils after Core UI and Core Panels (the Codex loads it first), but synced files register chat macros while they load. Holds verbatim copies of `Commands.RegisterMacro` and `Commands.RegisterBuiltinDoc` from `DMHub Utils/Utils.lua`; the sync checks they still match. |
| `DMHub Titlescreen/D20Settings.lua` | Settings the shared code reads that the Codex defines in its own `DMHub Titlescreen/Settings.lua` (not synced) or that d20 used to define in the old `SettingsGui.lua`. |
| `DMHub Titlescreen/Styles.lua` (d20's own) | The 5e gold-on-dark palette, merged over the Codex's `"default"` color scheme as it registers (so new Codex tokens still resolve); the "Default Rounded" theme; the Codex's MCDM-branded scheme left out; the `Styles` fields the synced code uses; the title bar's **Windows** menu (every window on the table). |

### Recorded patches to synced files

In `PATCHES` in the sync tool. "Director" (Draw Steel's game master) reads
"DM" in every user-facing string; ThemeEngine's two chat macros register a
moment after load; the DM's Screen has no cover art (the Codex's is an image
in the Codex's cloud, which shows as a grey slab in DMHub).

## Known gaps

- **The leather table says "DRAW STEEL"**: the playmat's embossed logo is an
  engine resource (`Assets/Resources/Tabletop/TabletopLogo.png`, used by
  `UICompositeCamera.cs`), the same for both white labels. Needs a DMHub logo
  and a white-label switch in the engine. The marble and stars surfaces have
  logos of their own to check.
- **Chat and rolls are split**, as in the Codex: the Chat panel shows talk,
  the Action Log shows rolls (both in one rail group). d20 used to show rolls
  inline in chat.
- **Table Dice** (3D dice on the table) carries Draw Steel trackers (Malice,
  heroic resources, victories); not reviewed for 5e.
- **Not yet exercised in DMHub:** a second client (sharing, forced maximize,
  pings), placing a dropped file as a map/scene/image (stopped at the dialog
  to avoid uploading), UVTT, document and audio drops, character cards,
  several map windows.
- **Lasting fix for the load order:** make DMHub Core UI depend on DMHub Utils
  in the cloud mod graph, as in the Codex; then `D20LoadOrder.lua` can go.
- The LuaLS stubs in `Definitions/` predate the engine APIs the synced code
  uses; regenerate them from the current engine.
