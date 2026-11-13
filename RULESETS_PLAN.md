# Rulesets Plan: 5e to YAML, and a new 5.5e (SRD 5.2.1) module

Status: Written 2026-11-12. Decisions D1, D2, D5, D6 and D7 recorded 2026-11-12. **Phase 0 done 2026-11-12. Phase 1 in progress:** local repo `C:\dev\dmhub-dnd5e` holds the exact-v14 baseline and the drift commit, and the round trip has been run (see Phase 1). **Phase 5 in progress (2026-11-12):** authoring game created, scaffolding and the first vertical slice (Dwarf Acolyte Cleric 1-3) committed in `C:\dev\dmhub-dnd2024` and checked in the app; see "Phase 5 progress". Nothing has been published.

Goals:

1. Move the 5e compendium (the `dmhub-legacy` module) out of the cloud and into a git repo of YAML files, with git as the source of truth.
2. Download SRD 5.2.1 (the 2024 rules, called "5.5e" here) and give it its own module and its own repo.
3. Let a DM choose 5e or 5.5e when creating a campaign. The choice picks the matching module.
4. Start building 5.5e from the SRD. Use only what YAML data can express at first, and keep a backlog of what needs code.

---

## 1. What exists today

These are verified facts, with references.

**How rules reach players.**
- Every DMHub game implicitly depends on a system module.
- `GameController.GetDependencies` (`Assets/Scripts/GameController.cs:9370`) injects `gameInfo.gameSystem`, or `dmhub-legacy` when it is empty. The dependency uses `versionid = "none"` and `autoUpdate = true`, so every game gets the latest published version.
- `dmhub-tabularasa` injects nothing.
- **`dmhub-legacy` is only a wrapper** (found in Phase 0). Its 80 KB content is a dependency on a second module, **`dmhub-5e`** ("5e", about 105 MB), which holds the actual content (the Rogue and the rest).
- `dmhub-legacy` v21 pins `dmhub-5e` v14 with `autoUpdate=false`.
- Neither git repo holds the content.

**A ruleset picker already exists.**
- `AvailableGameSystems` (`DMHub Titlescreen/Titlescreen.lua:60`) lists three systems:
  - `dmhub-legacy`: "D&D 5e", SRD 5.1 terms.
  - `shwayguy-pathfinder2e`: a community module.
  - `dmhub-tabularasa`: "No System".
- Each entry names a system **code mod**.
- `GameInfo.systemCodeMod` (`Assets/Scripts/AccountInfo.cs:715`) maps the game's `gameSystem` to that code mod. So `gameSystem` selects both the data module and the Lua.
- The dropdown is only in **Campaign Settings** for an existing game (`Titlescreen.lua:731`).
- `lobby:CreateGame` (`Titlescreen.lua:1373`, `Assets/GamesMonitor.cs` around line 300) has no `gameSystem` option. New games therefore get the default, `dmhub-legacy`.

**Module ids.**
- A module's `fullid` is `{authorid}-{moduleid}`, lowercased, using only `[a-zA-Z0-9_-]` (`Assets/Scripts/Module.cs:4713`).
- So `dmhub-legacy` is author `dmhub` + module `legacy`.
- A 5.5e id cannot contain a `.`.

**YAML tooling already in the engine.**
- Local Assets mode (`Assets/Scripts/LocalAssetDirectory.cs`) is dev-only and per game. It replaces the game's own cloud assets with a YAML tree on disk.
- It writes in-game edits back to the files and hot-reloads edits made outside the app.
- "Populate Directory" exports the game's cloud assets to YAML.
- It is gated on the `dev` setting, not the white label. **Verified 2026-11-12: it works in DMHub build 13 on the Firebase GreatLibrary game.**
- d20 has no UI for it. The `localassets:dirs` setting is declared only in the Codex's own `DMHub Titlescreen/Settings.lua` and `/localassets` macro. Phase 1 set it by declaring the setting at runtime over MCP.

**How the Codex does it** (reference implementation):
- Repo: `VerisimLLC/draw-steel-data`. It is an export of the "Great Library" authoring game, which publishes `mcdm-drawsteel`.
- Layout:
  - Top-level directories are named after the `CloudAssetInfo` fields (`objectTables/`, `monsters/`, `images/`, ...).
  - `objectTables/<table>/` holds a `_meta.yaml` (`id: classes`) plus one file per item.
  - The `id:` inside each file is the authoritative id.
- Deploy: `D:\dev\dmhub-deploy\drawsteel-deploy.py` with `plan` / `apply` / `verify` / `status` / `revert`.
  - It reads a git ref with `git archive`, mirrors `LocalAssetDirectory.LoadTree`, and applies `publish-exclude.yaml`.
  - It uploads a gzip snapshot blob (to R2 and GCS), appends `/Module/<id>/versions` with `minEngineVersion`, and writes an audit node.
  - The design doc is `C:\dev\dmhub\DATA_MODULE_DEPLOY_PLAN.md`.
  - **It is hardcoded to `MODULE_ID = "mcdm-drawsteel"` and the MCDM Firebase project.**
- The Lua code mods are deployed separately, not bundled in the data module.

**DMHub uses a different Firebase project.**
- DMHub uses `dmtool-cad62`; the Codex uses `mcdm-385cf` (`Assets/Scripts/DataStore.cs:929`).
- The Codex deploy script cannot be pointed at DMHub as-is.

**The d20 Lua: what is data and what is code.**
- The content tables are data, and they are the natural YAML scope:
  - `classes`/`subclasses`, `races`/`subraces`, `backgrounds`, `feats`
  - `Spells`, `SpellLists`, `tbl_Gear`, `weaponProperties`, `charConditions`
  - `Skills`, `damageTypes`, `languages`, `currency`, `characterResources`
  - `customAttributes`, `globalRuleMods`, `featurePrefabs`, `glossaryTerms`
  - the `monsters` bestiary
- Content can define its own mechanics: features are modifier lists with GoblinScript filters and values, and abilities are built from behavior types.
- The core 5e rules are **code** in `DMHub Game Rules/dnd5e.lua`, which loads unconditionally:
  - the six ability scores and the modifier formula
  - the proficiency bonus
  - the spell slot table (`dnd5e.lua:133`)
  - attack and crit math, cover, the concentration DC, death saves, the action economy and sizes
  - `GameSystem.RaceName = "Race"`
- The multiclass caster-level rounding is in `ModifierSpellcasting.lua:72-88`.
- **No in-game Lua reads `gameSystem`.** Both rulesets would run the same rules code unless that changes.

---

## 2. Decisions

| # | Decision | Status |
|---|---|---|
| D1 | Repo names and visibility | **Decided:** two **private** repos. `dmhub-dnd5e` (SRD 5.1) holds the content of module `dmhub-5e`; the `dmhub-legacy` wrapper is republished alongside it (Phase 0). `dmhub-dnd2024` (SRD 5.2.1) publishes `dmhub-dnd2024`. *Assumed to live in the `VerisimLLC` org, next to `d20-dmhub`; not confirmed.* |
| D2 | 5.5e module id | **Decided:** `dmhub-dnd2024`. It is permanent once games depend on it, and it cannot contain `.`. **The `dmhub-legacy` id stays forever**, because every existing game depends on it implicitly. Display names are set by D7. |
| D3 | How YAML becomes a published module | **Direction given:** both modules will get frequent updates and must be on Cloudflare R2. So a scripted, repeatable deploy is the target, not a stopgap. Generalize `drawsteel-deploy.py` (module id, Firebase project, credentials and blob buckets as parameters) so DMHub gets the same `plan`/`apply`/`verify`/`revert`. In-app publishing from the authoring game is only for the first publish, or for use before the script exists. **R2:** module snapshots already go to R2 on current engines; see Phase 2. |
| D4 | How the Lua knows which ruleset it is running | *Recommended, not yet confirmed:* use a **data** flag inside each module (e.g. a ruleset record in an existing table) rather than reading the `gameSystem` id. The rules then follow the content. Only needed once Phase 7 code work starts. |
| D5 | Switching an existing game from one ruleset to the other (5e <-> 5.5e) | **Decided: lock once the game has characters.** The ruleset is chosen at creation and can still be changed in Campaign Settings while the game has no characters. Once any character exists, the dropdown is locked. Swapping the module under existing characters would break their class, species and feat references. Content updates within a ruleset are unaffected: they reach every game through `autoUpdate`. |
| D6 | The lobby game | **Decided: not a concern.** DMHub does not allow characters in the lobby. |
| D7 | Licensing and trademarks | **Decided: follow WotC's trademark guidelines.** See section 2a. |

## 2a. Trademark and licensing rules (D7)

What the sources say, checked 2026-11-12:

- **The CC-BY-4.0 license covers SRD text only. It grants no trademark rights.**
  - The [SRD page](https://www.dndbeyond.com/srd) footer lists WotC's trademarks: "Dungeons & Dragons", "D&D", the dragon ampersand, product names, campaign settings, logos and "The World's Greatest Roleplaying Game".
  - SRD 5.2 renamed some items specifically to avoid protected trademarks.
- **Attribution is the license's one requirement.** The [Creator FAQ](https://www.dndbeyond.com/creator-faq) says to attribute the source but gives no wording. The exact statement is in the SRD's legal page.
- **The SRD 5.2.1 legal page (page 1 of the PDF), read 2026-11-12:**
  - The required attribution statement, exactly: "This work includes material from the System Reference Document 5.2.1 ("SRD 5.2.1") by Wizards of the Coast LLC, available at https://www.dndbeyond.com/srd. The SRD 5.2.1 is licensed under the Creative Commons Attribution 4.0 International License, available at https://creativecommons.org/licenses/by/4.0/legalcode." The PDF uses curly quotes around "SRD 5.2.1". The exact text is in `dmhub-dnd2024/source/srd-5.2.1/00-legal-information.md`.
  - It asks for no other attribution to Wizards or its parent or affiliates.
  - It allows a statement that the work is "compatible with fifth edition" or "5E compatible". This is now confirmed for 5.2.1. The SRD 5.1 wording is still only known second-hand.
- WotC has published no specific guidance for software or VTTs. The conservative reading is: describe compatibility, never imply an official or endorsed product. *This is my reading of public sources, not legal advice.*

Rules for both modules:

1. **No WotC trademarks in user-facing names or descriptions.** No "D&D", "Dungeons & Dragons", dragon-ampersand art or WotC logos. Proposed display names:
   - "5e (2014 rules)" for `dmhub-legacy`
   - "5.5e (2024 rules)" for `dmhub-dnd2024`

   Descriptions may say "5E compatible". WotC's own SRD page calls the 2024 rules "5.5e". *Proposed, not confirmed.*
2. **Attribution:** each system's `terms` carries its SRD's exact attribution statement (5.1 or 5.2.1), and nothing more about Wizards.
3. **SRD content only.**
   - Nothing from the 2024 Player's Handbook, Monster Manual or DMG beyond the SRD, and no 5eTools or D&D Beyond imports of non-SRD material.
   - Use the SRD's own names, including the renamed items.
   - The Phase 0 audit found non-SRD material in `dmhub-5e`: 8 subclasses, 49 spells including two with WotC character names, and a gear list that needs a manual pass (details in Phase 0). It is removed in Phase 1.
4. **Clean-up of current strings:**
   - User-facing:
     - `DMHub Titlescreen/Titlescreen.lua:64` (`text = "D&D 5e"`)
     - `DMHub Titlescreen/Styles.lua:18` (theme description "The classic D&D 5e gold-on-dark palette.")
     - module records (checked in Phase 0): "DMHub Legacy Content" and "5e" contain no trademarks.
   - Not user-facing:
     - `DMHub Core Panels/AIPanel.lua:366-372` and `JournalPDFViewer.lua:340` mention D&D in prompts sent to an AI service, not shown to players.
     - They are Codex-synced files, so leave them unless you want them changed upstream.
5. Internal identifiers (`dmhub-dnd5e` / `dmhub-dnd2024` repo names, the `dmhub-dnd2024` module id) are not user-facing. Revisit them if the repos ever go public or the id shows up in UI.

---

## 3. Phases

The order matters. Phase 1 can break every existing DMHub game if it goes wrong, so it comes first and is done carefully. The 5.5e work (Phases 4-6) can run alongside Phases 2-3.

### Phase 0 -- Discovery in the live app: DONE 2026-11-12

Run against DMHub build 13 (`dmtool-win/DMHub.exe`) over MCP. Read-only, apart from opening the authoring game as DM and writing a name list to `%USERPROFILE%\AppData\LocalLow\Sodapods\DMHub\compendium\phase0\dmhub-5e-content.json`.

**Modules and rights.**
- `dmhub-legacy`:
  - name "DMHub Legacy Content", author `dmhub`, no org, 21 versions
  - versions 4-9 were 164-327 MB (the content used to live here); since v10 it is an 80 KB wrapper
  - its only content is the module `dmhub-5e`
- `dmhub-5e`:
  - name "5e", author `dmhub`, 14 versions, about 105 MB
  - its description says SRD and never says "D&D"
- The signed-in account (author id `dmhub`) owns both, so **we have publish rights**.

**Version pinning.**
- Traced in the authoring game: `dmhub-legacy` v21 (`autoUpdate=true`, `ord=-1000`) depends on `dmhub-5e` v14, versionid `e53dbca1-...`, with **`autoUpdate=false`**.
- So **shipping a 5e content update takes two publishes:**
  1. a new `dmhub-5e` version
  2. a new `dmhub-legacy` version that points at it
- Without step 2, games stay on `dmhub-5e` v14.
- *This is how the engine resolved the dependency in that one game; I have not read the stored records directly.*

**Authoring game: found.**
- It is **"GreatLibrary"**, game id `LittleIndispensableGorgeousCell`. Owner Denivarius, **Firebase** storage, `gameSystem = dmhub-legacy`.
- `module.GetModulesPublishedFromThisGame()` there returns both `dmhub-5e` and `dmhub-legacy`. Both were last published **2024-04-03**.
- Its own content: 9 races, 12 classes, 323 monsters, 1,571 other entries.
- It also imports 33 art and token packs (`premium-tc_*`, `premium-bruni_*`, `dmhub-storetc_*`, `ricky-lvl20goblintokens`). These are imports, not its own content. **Populate should leave them out**: it exports only the game's own assets. Check this in Phase 1.

**Drift since the last publish.**
- All 1,962 guids in `dmhub-5e` v14 still exist in the game's own content.
- The game has **27 more that were never published**:
  - an "Animated Shield" ongoing effect
  - two placeholder "New Ongoing Effect" records
  - a "Falling Damage" global rule mod
  - two parties
  - 21 non-table assets I could not name (likely images, folders or objects)
- Edits made since 2024-04-03 to entries that *are* published are not yet measured. The Phase 1 round-trip will show them.

**Content inventory** (`dmhub-5e` v14, 1,970 entries):

| Content | Count | Content | Count |
|---|---|---|---|
| tbl_Gear (items) | 774 | Spells | 366 |
| Monster (bestiary) | 340 | characterOngoingEffects | 149 |
| equipmentCategories | 45 | nameGenerators | 39 |
| lootTables | 33 | characterResources | 32 |
| charConditions | 22 | subclasses | 20 |
| Skills | 18 | languages | 17 |
| damageTypes | 13 | GenericImage | 13 |
| classes | 12 | races | 9 |
| weaponProperties | 9 | SpellLists | 8 |
| Object (map objects) | 8 | globalRuleMods | 7 |
| characteristicsTable | 6 | subraces | 4 |
| attributeGenerator | 4 | currency | 4 |
| parties | 3 | customAttributes, VisionType, image library, Emoji | 2 each |
| backgrounds, feats, featurePrefabs, characterTypes, creatureTemplates, damageFlags, aiassistant | 1 each | | |

**SRD 5.1 audit.** Names compared against the repo's `Assets/CoreAssets/JsonData/5e-SRD-*.json`:
- **Matches SRD:** all 12 classes, 9 races and 4 subraces; the 1 background (Acolyte); the 12 SRD subclasses, under their full names.
- **Monsters:** all SRD monsters are present. The lycanthropes (one entry each, where the SRD lists one per form) differ only in naming. "Magical Beast" and "Monster" look like template entries.
- **Not in SRD 5.1 (to remove or exclude):**
  - **8 subclasses:** Battle Master, and the Schools of Abjuration, Conjuration, Divination, Enchantment, Illusion, Necromancy and Transmutation. Evocation is the only SRD school.
  - **49 spells**, among them Hex, Armor of Agathys, Chromatic Orb, Toll the Dead and Green-Flame Blade. Two of them, **"Mordenkainen's Faithful Hound" and "Rary's Telepathic Bond"**, use WotC-owned character names and *duplicate* the SRD entries "Faithful Hound" and "Telepathic Bond", which are also present.
  - **2 SRD spells are missing:** Find the Path, Legend Lore.
  - **Needs a manual pass:** 417 of the 774 gear names don't match the SRD list. Most are expansions of SRD entries ("+1/+2/+3" variants, per-color dragon scale mail, arcane focus types). Some look like non-SRD treasure (gems, art objects).
- **Homebrew helpers, not WotC content:** 7 conditions (Clunky Armor, Disease, Dodging, Sleep, Surprised, Turned, Vulnerable) and the language Druidic, which the SRD druid references.
- **Junk to clean up:** a placeholder feat "New Feat" and "(Dup.)" duplicates in gear.

**Still unknown:**
- whether module versions carry a `minEngineVersion` (the Lua view returns nil for it, but also for `ctime`, so that view can't be trusted)
- which engine versions still load these modules (retail 0.5x builds do, per `d20/README.md`)
- ~~whether Local Assets works on a **Firebase** game in DMHub~~ It does (Phase 1).

### Phase 1 -- Extract `dmhub-legacy` to YAML (`dmhub-dnd5e` repo)

- **Path A applies:** the authoring game exists (GreatLibrary, `LittleIndispensableGorgeousCell`).
  1. Open it.
  2. Point Local Assets at a new, **empty** folder.
  3. Run Populate Directory.
  4. Commit the result as the baseline.
- **Decide what the baseline is.** Populate exports the game *as it is now*. That includes the 27 unpublished items and any edits made since 2024-04-03. Options:
  - **(a)** commit the game as-is, and review the unpublished changes in the round-trip before the first publish
  - **(b)** first make a baseline that matches v14 exactly, then commit the drift as a second commit

  (b) gives a clean history. Recommended.
- **Path B (fallback only):** convert the published v14 snapshot straight to the YAML layout. Use it if Local Assets fails on this Firebase game, or to build (b)'s exact-v14 baseline.
- **SRD clean-up (D7):** in a separate commit after the baseline, remove or exclude the non-SRD content found in Phase 0. Restore the 2 missing SRD spells, and do the gear manual pass. Keep it separate so the audit trail is clear.
- **Round-trip check before anything is ever published:** build the deploy payload from the YAML and compare it with the current live snapshot. The Codex did this in DATA_MODULE_DEPLOY_PLAN section 2. Any difference has to be explained, because old retail builds will load whatever we publish.
- Add the repo docs:
  - README: how to point a game at it, and the "never Populate onto the repo" warning
  - `DATA_REFERENCE.md`
  - an empty `publish-exclude.yaml`
  - a `CLAUDE.md`
- From then on, 5e edits happen in the authoring game with Local Assets pointed at the clone, and are committed to git.

Exit: git is the source of truth, and a publish from it reproduces today's module.

#### Phase 1 progress (2026-11-12)

Baseline choice: **(b), exact v14 first** (user decision).

**How the exact-v14 export was made (no engine change, no Path B).**
- In GreatLibrary, `dmhub.RunWithModuleAssets("dmhub-5e", fn)` temporarily swaps the merged asset view for the loaded `dmhub-5e` module store.
- Inside it, `dmhub.ExportAllAssets{directory = <abs path>, merged = true}` writes that store through `LocalAssetDirectory.ExportAll`, the same code Populate uses. So the layout and the serialization are the engine's own.
- The game's own content was exported the same way with `merged = false`.
- The `dmhub-legacy` store exported the same way has 32 assets: 13 images, 17 image-library entries, and the Squeezed and Versatile records. All 32 are **byte-identical** to their `dmhub-5e` copies, so the repo stores only `dmhub-5e`.

**Repo: `C:\dev\dmhub-dnd5e`, branch `main`, local only (no remote yet).**
- `.gitattributes` is `* -text`. The engine writes YAML with **CRLF** endings, the same as the Codex data repo, and the files are stored byte-for-byte.
- **Both commits were rebuilt on 2026-11-12 with the fixed GWYaml writer (see the round trip below).** The originals, `a66fd33` and `fe14dd6`, were written by the old writer. They differ from the rebuilt ones only in the style of 87 strings in 63 items, plus `_manifest.yaml`, and stay in the local reflog.
- Commit `cb273a9`, "Baseline: module dmhub-5e v14, exactly as published":
  - 2018 files in 6 categories plus `_manifest.yaml`
  - 340 monsters, 1605 object-table items in 31 tables, 13 images, 17 image-library entries, 8 objects, 2 emoji
- Commit `4ff2774`, "Authoring-game drift since the v14 publish": the game as it is now. 341 files modified, 37 added, none deleted.
  - **Content edits:**
    - about 20 tbl_Gear magic items, A-B alphabetically
    - armor and weapon `domains`
    - new portraits for Gnome, Half-Orc and Halfling
    - Blinded (condition and effect), Antitoxin, Immunity to Non-Magical Damage
  - **Mechanical, no content change:**
    - 254 monsters gain `levelChoices: []` and 5 gain `equipment: []`
    - some items gain auto-filled `domains`
    - 42 items differ only in `ctime`
  - **New, never published (37):**
    - Animated Shield effect, two "New Ongoing Effect" placeholders, Falling Damage rule
    - 16 avatar image-library entries and their 16 images
    - a map thumbnail
  - **To decide before the first publish:** which of the 37 ship. Unshipped ones go in `publish-exclude.yaml`.

**Round trip (YAML -> engine -> YAML), run 2026-11-12.**
- Commit `a66fd33` (the original baseline, written by the old writer and since replaced) was extracted to a scratch folder and GreatLibrary's `localassets:dirs` was pointed at it. The game reloaded from the YAML and was re-exported. GreatLibrary was then set back to cloud assets, and that was checked.
- Of 2018 items:
  - **1727 byte-identical**
  - **0 content differences**
  - **263 load-time normalizations**: the same empty `levelChoices`/`equipment` lists and auto-filled `domains` seen in the drift. These are things the engine or Lua adds to any object it loads, and they are harmless.
  - **Strings lose characters in 278 items, not just the 28 that the text comparison showed.** Re-checked later the same day. Every string was pulled out of the loaded module (179,075 strings in 1,945 items) and each was round-tripped through the real `GWYaml.cs` in a .NET harness:
    - **319 strings in 221 items lose only the `\r` of `\r\n` pairs.** The old writer puts them in a literal block (`|`). On Windows that file text is identical to the `\n`-only version, so a text diff can never show the loss. The reader returns `\n`.
    - **66 strings in 44 items have a lone `\r`**, mostly a stray one at the start or end of a spell description. The reader turns it into `\n`, or folds it to a space.
    - **21 strings in 19 items end in a tab that the reader strips.** Example: Calm Emotions `targetFilter`, `"type is humanoid\t"`.
    - In all, 63 items lose something other than the `\r` of a `\r\n` pair.
    - **So commit `a66fd33` is exact as text, but not as data.** Its text is what the engine wrote for v14, but that text cannot carry those `\r` characters and trailing tabs.
    - Not checked yet: whether a lone `\r` or a `\r\n` pair renders differently from `\n` in the UI.
  - **16 files swap names** between colliding items (`bond.yaml` / `bond-<hash>.yaml`). Filename collisions are resolved in iteration order on a full export. Cosmetic only: ids inside the files are authoritative, and Local Assets never renames an assigned file.
- **Root cause: `GWYaml.EmitStringScalar` (`Assets/Scripts/GWYaml.cs`)**, the engine code shared with the Codex.
  - YamlDotNet's emitter treats `\r` as a line break, and every YAML reader turns a line break into `\n`.
  - It does not treat a tab as whitespace, so it writes a string with a trailing tab as a plain scalar, and the reader strips the tab.
  - The full lossy set, found with the harness: any `\r`, NEL (U+0085), a trailing tab on a one-line string, and the exact string `"\n"`.
  - Trailing spaces, leading whitespace, `\v` and the other control characters already round-trip.
- **Fixed 2026-11-12 in engine commit `47f8f6b3f`, pushed to `origin/master`** (merged in `6da3d869b`). `LosesDataUnlessEscaped` sends these strings to double-quoted style, which escapes their characters: a lone `\r`, NEL, a trailing tab on a one-line string, and `"\n"` or `"\r\n"` on its own. Every other string keeps the style it had.
  - **Decision (user): a `\r\n` pair is normalized, not escaped.** It stays in a literal block and reads back as `\n`, which is how the YAML spec defines a line break.
    - This keeps text with Windows line endings readable, both in this repo and for text pasted in-app in the Codex.
    - Escaping every `\r` instead would have written about 340 v14 descriptions as single double-quoted lines.
  - **Tested with a throwaway .NET harness** that compiles the real `GWYaml.cs` against `Assets/Plugins/YamlDotNet.dll`.
    - All 69 edge cases round-trip, with `\r\n` coming back as `\n`.
    - All 461 lossy v14 strings round-trip the same way. With the old writer, 87 of them lose more than that.
    - 87 strings in 63 items change style to double-quoted, 51 of them multi-line.
    - 319 strings in 221 items stay in literal blocks and lose only the `\r` of their `\r\n` pairs.
  - **No churn in existing YAML.** Re-writing YAML that has already been loaded gives output byte-identical to the old writer for 2,019 v14 files and for the 7,881 files in `C:\dev\draw-steel-data-deploy`.
  - **Consequence for publishing.** A publish built from the YAML differs from v14 in those 221 items by the `\r` characters alone. Not checked: whether that changes how any text renders.
  - **Built and verified in the app, 2026-11-12** (`build.ps1 windows -DevKey`, built before the merge with 7 upstream commits; none of them touch `GWYaml.cs`).
    - **Fresh export:** v14 exported with the new writer to a scratch folder (`v14-fixed`) differs from commit `a66fd33` in exactly the 63 predicted items. All are object-table items: 41 spells, 8 ongoing effects, 6 gear and 8 others. No filenames changed.
    - **Data-level round trip:** `v14-fixed` was loaded through Local Assets, and every string in the game store was compared in memory with the same path in the `dmhub-5e` module store.
      - Of 61,763 module strings, 59,935 are identical, 319 (in 221 items) differ only by `\r\n` -> `\n`, and **0 differ in any other way**.
      - The 1,509 paths missing from the game are all `_fork`, module bookkeeping that the exporter leaves out.
      - The extra strings in the game are the game's runtime `_tmp_` caches.
      - The walker's cycle guard must cover only the current path. A global "seen" set makes tables shared by a cache key show up under the wrong path.
    - **Text-level round trip:** re-exporting that game gives 1,751 byte-identical items, 263 load-time normalizations, 0 real differences, and the same 16 cosmetic filename swaps.
      - 4 items (Dominate Person, Acolyte, Druid, Ranger) change only the block marker from `|+` to `|`. A string ending in `\r\n` is first written "keep trailing breaks", then settles to `|` after one reload. The data does not change.
    - GreatLibrary was set back to cloud assets afterwards, and that was checked.
- **The Codex deploy reader already differs from the engine reader.** `drawsteel-deploy.py` (`load_yaml`) swaps tabs for a placeholder before PyYAML parses, so it *keeps* the trailing tabs the engine drops. A deploy and a Local Assets session can therefore read the same file differently. The writer fix removes that divergence.

**Still to do in Phase 1:**
1. Create the private GitHub repo and push. The org (VerisimLLC assumed) is unconfirmed.
2. ~~Add the `localassets:dirs` setting to d20~~ **Done 2026-11-12, not yet committed.** `DMHub Titlescreen/D20Settings.lua` now declares `localassets:dir`, `localassets:dirs`, `localassets:eotwdirs` and `localassets:gitpath` (same ids, storage and defaults as the Codex) and registers `/localassets <path>|off` and `/exportassets [dir]` (dev mode only). d20 has no text editor for settings, so the macro is the UI. It is uncommitted because the same file also holds someone's uncommitted Patreon account section.
3. Repo docs: README, `CLAUDE.md`, empty `publish-exclude.yaml`, `DATA_REFERENCE.md`.
4. Decide which of the 37 new items ship.
5. The SRD clean-up commit (D7).

(The GWYaml writer fix is done: engine commit `47f8f6b3f`, pushed 2026-11-12. The `dmhub-dnd5e` commits were rebuilt with it.)

### Phase 2 -- A deploy pipeline for DMHub data modules

Both modules will be updated often (D3), so this phase is core work, not a nice-to-have.

**5e is a two-module deploy.** `dmhub-legacy` pins its `dmhub-5e` version (Phase 0), so the deploy has to:
1. publish `dmhub-5e`
2. publish a new `dmhub-legacy` whose dependency points at the new `dmhub-5e` version

Both steps belong in the same `apply` run. `verify` checks that the chain resolves.

Alternative: republish `dmhub-legacy` once with `autoUpdate=true` on its `dmhub-5e` dependency, so later deploys need only step 1. That is simpler, but it would also let a bad `dmhub-5e` publish reach every game at once. *Not recommended without `revert` in place.*

5.5e needs no wrapper: its `AvailableGameSystems` entry points straight at `dmhub-dnd2024`.

**R2 is already the storage backend on current engines** (checked in code 2026-11-12):
- `ImageManager.UploadDataBlobToGoogleCloud` (`Assets/Scripts/ImageManager.cs:2063`) writes each module snapshot to **R2 and GCS**.
  - On the DMHub white label, R2 is the `dmhub-images` bucket, written via `blob-server.dmhub-servers.com` and read from `images.dmhub-servers.com` (`Assets/Scripts/CloudBlobStorageManager.cs:67-81`).
- Downloads try R2 first and fall back to GCS (`dmhub_images`).
- **The GCS copy exists only for older engines, which read GCS alone.**
  - `dmhub-legacy` is loaded by old retail 0.5x builds, so its deploys must keep writing GCS until those builds are retired.
  - `dmhub-dnd2024` could be R2-only if it is only offered on engines that read R2. Recommendation: dual-write both anyway (the cost is negligible) and decide on dropping GCS later.

Work:
- Generalize `drawsteel-deploy.py` into a shared tool, or a sibling script, that takes as parameters:
  - the module id
  - the Firebase project (`dmtool-cad62` for DMHub)
  - the credentials
  - the R2 bucket and blob server (`dmhub-images`)
- To find out:
  - service-account credentials for `dmtool-cad62`
  - the auth the script needs for the DMHub blob server
  - whether DMHub module versions honor `minEngineVersion`
- Add `plan` / `apply` / `verify` to the `/dmhub-release` skill, as the Codex release skill does. Consider a standalone data-only deploy as well, since content updates will be more frequent than builds.
- Until this exists, use the in-app publish (D3).

### Phase 3 -- Choose the ruleset when creating a campaign

- Add `dmhub-dnd2024` to `AvailableGameSystems`:
  - `codeMod = codeMod5e` (the same Lua for now)
  - the SRD 5.2.1 attribution in `terms`
  - a trademark-free name (section 2a)
  - **dev-only** (filtered on the `dev` setting) until the content is playable
- Rename the existing entry's text from "D&D 5e" to its trademark-free name (section 2a).
- Add a "Rules" dropdown to the New Game panel (`Titlescreen.lua`, around 1300-1380), next to Storage.
- Pass the choice when the game is created. Two ways to do it:
  - **Engine (recommended):**
    - What: a `gameSystem` option in `GamesMonitor.CreateGame`, written into `GameInfo` before the first save.
    - Pros: atomic; no window in which the game exists with the wrong system.
    - Cons: needs a DMHub build. Per CLAUDE.md it should be committed from `C:\dev\dmhub`, since the engine is shared with the Codex.
  - **Lua only:**
    - What: set `game.gameSystem` from the `create` callback (the setter writes `/games/{id}/gameSystem`).
    - Pros: no build needed.
    - Cons: a second write that could race with entering the game. *Unverified.*
- Lock the Campaign Settings ruleset dropdown once the game has characters (D5).
  - When locked, show the ruleset as read-only text with a short reason ("This campaign has characters, so its ruleset can no longer change").
  - **Detecting characters (answered in Phase 0):** `LuaGameInfo.characterIndex` (`d20/Definitions/LuaGameInfo.lua:17`) lists a game's important characters from cached metadata, without connecting to the game. A non-empty index means locked.
  - Caveat: the index covers characters assigned to a player or party. Unassigned characters, and games last saved by older clients, may be missing from it. Decide whether to also lock when `characterIndex` is nil, or when `contentSummary` is nil (the game was never opened by a new client).
- The first publish of the 5.5e authoring game creates `/Module/dmhub-dnd2024`.

### Phase 4 -- Get the SRD 5.2.1: DONE 2026-11-12

**Result.** Everything is in `C:\dev\dmhub-dnd2024`. It is a local git repo on branch `main`, with first commit `8c6d173` and no remote yet. `source/srd-5.2.1/README.md` has the details.
- **PDFs:** both were downloaded to `source/srd-5.2.1/pdf/` and are git-ignored.
  - `SRD_CC_v5.2.1.pdf`: 364 pages, 6.0 MB.
  - `converting-to-srd-5.2.1.pdf`: 15 pages, 2.5 MB.
  - The README records their URLs and SHA-256 hashes.
- **Attribution:** the legal page was read. Its exact statement and the "5E compatible" allowance are now in section 2a.
- **Markdown:** one file per SRD chapter (14 files, `00-legal-information.md` to `13-animals.md`), plus `converting-to-srd-5.2.1.md`.
  - `tools/srd2md.py` (PyMuPDF) regenerates them deterministically.
  - It reads both columns and rebuilds tables, including captions, header rows, unshaded rows and spell-slot group headers.
  - It writes monster ability grids as `| | Score | Mod | Save |` and sidebars as blockquotes.
  - It joins line-end hyphens, checking each against the SRD's own spellings, and marks each PDF page with `<!-- p. N -->`.
- **Checks:**
  - Every text line on every page is written exactly once; the tool checks this on each run.
  - All 330 stat blocks have their ability table.
  - No paragraph starts mid-sentence, which would mean a break across a column or page went wrong.
  - 12 SRD pages and guide page 1 were compared by eye against the PDF.
- **SRD 5.2.1 sizes, counted from the extraction:**
  - 339 spells, 258 magic items, 17 feats;
  - 12 classes, each with 1 subclass;
  - 4 backgrounds and 9 species;
  - 235 stat blocks in Monsters A-Z, plus 95 in Animals.
- **Known limits:**
  - A short list set in several columns comes out read across the rows.
  - 3 line-end hyphens were judged by hand (`KEEP_HYPHEN`).

Original plan:
- Download from https://www.dndbeyond.com/srd (CC-BY-4.0):
  - `SRD_CC_v5.2.1.pdf`, the English SRD 5.2.1, published 2025-05-01
  - `converting-to-srd-5.2.1.pdf`, the official SRD 5.1 -> 5.2.1 conversion guide, published 2025-05-27. It is the best map of what changed from our 5e data.

  Localized versions (DE, ES, FR, IT) also exist. *These downloads need your OK when we get there.*
- Read the SRD 5.2.1 legal page and copy its exact attribution statement into section 2a and the `terms` field. Confirm whether it allows "compatible with fifth edition" / "5E compatible", as SRD 5.1 does.
- Extract it into the 5.5e repo as `source/srd-5.2.1/`, one markdown file per chapter (classes, species, backgrounds, feats, equipment, spells, magic items, monsters, rules glossary). Check the extraction against the PDF.
- Keep the PDF out of git, or put it in LFS; the markdown is the working reference.

### Phase 5 -- Set up the 5.5e repo and authoring game (`dmhub-dnd2024` repo)

- **Authoring game:** a new DMHub game with `gameSystem = dmhub-tabularasa`, so the 5e module does not load into it. Point Local Assets at the `dmhub-dnd2024` clone. Mark it as the publisher of `dmhub-dnd2024`.
- **Copy the scaffolding tables from `dmhub-dnd5e` with the same ids:**
  - `Skills`, `damageTypes`, `damageFlags`, `proficiencyLevel`
  - `characterResources` (spell slots, hit dice), `customAttributes`, `attributeGenerator`
  - `characterTypes`, `VisionType`, `equipmentCategories`, `currency`, `languages`
  - `featurePrefabs`, `globalRuleMods`, `standardAbilities`

  Same ids keep these tables compatible with the shared Lua. The two modules never load together, so the ids never collide.
- **Do not copy SRD 5.1 content.** Old 5.1 entries may be used as *structural templates* (how a feature or spell is modeled). Text and numbers are always re-authored from 5.2.1, so no stale 5.1 wording ships as 5.5e.
- **Repo tooling:**
  - `SRD_COVERAGE.md`: every SRD 5.2.1 entry with its status (todo / authored / tested).
  - A checker script that checks:
    - ids are unique, and `_table` matches `_meta`
    - required fields are present
    - **references resolve**: spell list -> spell ids, class -> subclass, background -> feat, item -> weapon property
  - A content-authoring skill for 5e YAML, like the Codex's `/implement-content`, written once the first few entries have set the patterns.

#### Phase 5 progress (2026-11-12)

**Authoring game: "Library 5.5e (SRD 5.2.1)", game id `ImmortalObnoxiousIckyIQ`.** Created from the title screen with `lobby:CreateGame{backend = "durableobjects"}` (Cloudflare, so it is not tied to one machine), then `gameSystem` set to `dmhub-tabularasa`. Local Assets points at `C:\dev\dmhub-dnd2024`. Not yet marked as the publisher of `dmhub-dnd2024` (that happens at the first publish, which needs your OK).

**Repo `C:\dev\dmhub-dnd2024`, branch `main`, local only.** Commits:
- `341477e` scaffolding: the 13 tables copied with their ids, then checked against 5.2.1 (details in the commit). `proficiencyLevel` and `standardAbilities` are not in the 5e module at all, so there was nothing to copy; the code treats both as optional. Conditions (15) and weapon properties were done in the same batch.
- `783445d` the vertical slice (below).

**Tools** (all in the repo, documented in its `README.md`): `srd_lookup.py` (SRD sections as DMHub text), `check.py` (the checker), `coverage.py` (writes `SRD_COVERAGE.md`; in-app checks are recorded in `tools/tested.yaml`), `yamlio.py` (writes YAML in the engine's exact style: 1,816 of 1,980 `dmhub-dnd5e` files re-emit byte-identical, the rest differ only in string style), `authoring/spellgen.py` (builds any SRD spell's text and metadata; all 339 parse), and one re-runnable script per batch.

**Decisions taken while authoring** (say if you want any changed):
- **Ids and art are reused from the same-named `dmhub-dnd5e` record** (spell, class, species, item, effect). Text and numbers never are. This keeps the scaffolding's references resolving (Wild Shape CR -> Druid, the Fighting Style prefab -> Fighter) and reuses the 5e portraits and icons. New records get fresh ids, kept stable in `tools/authoring/*_ids.yaml`.
- **Magic Initiate is one feat per spell list** (`Magic Initiate (Cleric)` now; Druid and Wizard later). A background grants its version with `CharacterSingleFeat`, and the SRD's "a different list each time" falls out naturally.
- **Languages** moved to character creation as in 2024: the `Character` global rule mod grants Common plus a choice of two Standard languages. Species and backgrounds grant none.
- **"A or B" starting equipment** is one equipment choice with two options; B is a currency item (110 GP for the Cleric).
- **The engine-seeded audio** (`audio/`) is git-ignored: every new game gets it, it is not module content.

**Vertical slice: Dwarf, Acolyte, Cleric 1-3 with the Life Domain.** Checked in the authoring game with a level 3 test character, "Test Cleric (SRD 5.2.1)" (standard array, +2 Wis/+1 Cha, Thaumaturge, Medicine and Persuasion). Matches the SRD on: HP 27 (8/5/5 + Con, +3 Dwarven Toughness), AC 15 in Chain Shirt and Shield, Wis/Cha saves, the four skills, Dwarvish/Elvish/Common, spell slots 4/2, 4 cantrips (3 + Thaumaturge) and 6 prepared, spell DC 13 / +5, the four Life Domain spells always prepared, Magic Initiate's own DC 13 with 2 cantrips and 1 level 1 spell, Channel Divinity 2 uses with DC 13, Preserve Life 15, Mace +3 / 1d6+1, Darkvision 120, poison resistance, Stonecunning uses = PB. Exhaustion at 2 levels gives Speed 20 and -4 on D20 Tests.

**Coverage after the slice:** 1,403 SRD entries; 14 tested, 83 authored, 1,306 todo.

**Batches after the slice (2026-11-12).** The `srd-content` authoring skill is in the repo (`.claude/skills/srd-content/SKILL.md`). Four subagents authored in parallel, each owning separate files, and each batch was reviewed and checked in the authoring game before it was committed:
- tools, 36 items (`a07706b`, `e3bb881`);
- weapons, armor and ammunition, plus new ammunition categories (`930f689`). Review found and fixed: Chain Shirt's category, sidebar text in two weapon properties, the missing "Clunky Armor" helper condition, and the top-level weapon fields the code reads (now in the skill);
- adventuring gear, 76 items with Acid, Alchemist's Fire, Antitoxin, Potion of Healing, Net and the lights automated (`7b1280d`). Review added Holy Water's ability and the Lamp's light;
- core rules: the 2024 actions, Unarmed Strike and Grapple as global rule mods, and damage type text (`efb7d34`).

**Coverage after these batches:** 1,403 entries; 14 tested, 226 authored, 1,163 todo. Equipment is 157 of 157 authored. Core rules are 32 of 33; the exception, Two-Handed, is a code builtin and cannot be a record.

**Engine fix:** a new table folder now gets its id from `_meta.yaml` or the items' `_table` (`LocalAssetDirectory.ResolveTableIdFromFolder`). Committed in `C:\dev\dmhub` as `4d095a90e`, not pushed; tested in a DMHub dev build from `C:\dev\d20-dmhub`, which has the same change uncommitted.

**Gotchas found** (also in the repo README):
- **A new table folder could register under its folder name** (fixed by `4d095a90e`) (`spelllists`, `tbl-gear`) instead of its `_meta.yaml` id when the hot-reload watcher sees the folder before the `_meta`. A game reload fixes it. Worth an engine fix (C#, commit from `C:\dev\dmhub`).
- The 5e Lua seeds the nine standard weapon properties into an empty game, and Local Assets writes them out without a `_meta.yaml`. Their ids (`ammo`, `finesse`, ...) are read by code, so they were kept.
- `sed -i` strips the CRs from these CRLF files. Use the Python tools.
- Dice formulas: `(2*Upcast) d8` adds 2d8 per slot level; `2*Upcast d8` doubles a roll instead.
- A non-spell ability's save DC uses no ability unless `attributeOverride` names one (Channel Divinity showed DC 10 until it was set to `wis`).

### Phase 6 -- Author 5.5e in YAML (the long part)

Ordered so that a level-1 character becomes buildable as early as possible. The counts below were first estimated from memory. The exact counts from the Phase 4 extraction are 339 spells, 258 magic items, 17 feats, and 235 + 95 stat blocks.

1. **Core:**
   - conditions, including 2024 Exhaustion as a stacking ongoing effect (d20 tests -2 and speed -5 ft per level)
   - damage types, skills, languages
   - weapon properties, with the 8 mastery properties as properties: Cleave, Graze, Nick, Push, Sap, Slow, Topple, Vex
2. **Equipment:** weapons (each tagged with its mastery), armor, adventuring gear, tools.
3. **Feats** (about 17):
   - origin feats, tagged `origin` so backgrounds can filter on them
   - general feats
   - fighting style feats
   - epic boons
4. **Backgrounds** (4: Acolyte, Criminal, Sage, Soldier). Each has:
   - ability increases as **explicit option lists**: +2/+1 or +1/+1/+1 across its three listed abilities. The point-cost mode would wrongly allow +2/+1 on the same ability.
   - its Origin feat, two skills, a tool and equipment.
5. **Species** (9: Dragonborn, Dwarf, Elf, Gnome, Goliath, Halfling, Human, Orc, Tiefling). They have no ability increases. Lineages (elf, tiefling, gnome, dragonborn ancestry) become subraces or choices.
6. **Spells** (about 340) and per-class spell lists.
7. **Classes** (12, each with its one SRD subclass), levels 1-20. 2024 half-casters get spell slots at level 1. Check that their caster-level formula can express that in data.
8. **Monsters** (300+ stat blocks): the biggest single job. Do it after the character side is playable.
9. **Magic items.**
10. **Rules glossary**, as `glossaryTerms` and documents.

Quality gate for each batch: it hot-reloads cleanly in the authoring game, the checker passes, and the coverage file is updated. For classes and species, build a test character at levels 1, 5 and 11 and check the sheet against the SRD. This batch-by-batch work suits parallel agents once the checker and the skill exist.

### Phase 7 -- Backlog of things that need code

Out of scope for the YAML-only start. Every one of these must be gated on the D4 ruleset flag so 5e does not change.

- The ruleset flag itself (D4), readable from Lua.
- "Species" instead of "Race":
  - `GameSystem.RaceName` / `RaceNamePlural` (`dnd5e.lua:18`)
  - the literal strings at `CharacterSheet.lua:2675`, `Compendium.lua:5372`, `RaceEditor.lua:82`, `Race.lua:17,123`, `ModShare.lua:671-701`, `Tutorial.lua:120`
- Multiclass half-caster rounding (`ModifierSpellcasting.lua:72-88`).
- Weapon Mastery as a mechanic:
  - which weapons a character has mastered, and swapping them on a long rest
  - a GoblinScript check for "mastered"
  - Graze (damage on a miss) and Nick (extra attack), which sit outside the attack-modifier flow
- Any 2024 class feature that needs a new trigger event or behavior type, found during Phase 6.
- Note: `DMHub Game Rules` and `DMHub CharacterSheet 5e` are d20-only (not synced from the Codex), so they can be edited directly.

**Found while building the vertical slice (2026-11-12).** Each is either worked around nowhere (the data does the SRD-correct part and is marked partial with `implementation: 2`), or the data simply leaves it to the GM.

| # | Rule (SRD 5.2.1 page) | What the code lacks | Where it shows now |
|---|---|---|---|
| 7.1 | "Species" (p. 83) | Confirmed: the builder tab and record type still say "Race". | Builder, compendium |
| 7.2 | Half-caster slots at level 1 (Paladin p. 53, Ranger p. 57; multiclass "round up", p. 25) | Confirmed: `ModifierSpellcasting.lua:72-88` returns no caster level when `lvl < 1`, so a level 1 Paladin gets no slots. | Not hit yet (no half-caster authored) |
| 7.3 | Weapon Mastery (p. 90) | Mastery properties now exist as records (`mastery-*`, the Mace carries Sap), but nothing applies them, tracks which weapons are mastered, or handles Graze/Nick. | Mace on the test sheet |
| 7.4 | A save where the **target chooses** Str or Dex: Unarmed Strike Grapple and Shove (p. 191) | `ActivatedAbilitySavingThrowBehavior` takes one ability. | Shove saves with Strength only (`implementation: 2`); there is no Grapple yet |
| 7.5 | A resource that regains **one use on a Short Rest** and all on a Long Rest: Channel Divinity (p. 37); also Wild Shape (p. 42) and others to come | Refresh types are all-or-nothing per rest. | Channel Divinity refreshes on a Long Rest only |
| 7.6 | Exhaustion: a Long Rest removes **one** level; death at level 6 (p. 181) | `removeOnLongRest` removes the whole effect; nothing kills at 6. | Exhaustion stacks correctly; the GM removes levels |
| 7.7 | Magic Initiate: cast the chosen level 1 spell **once per Long Rest without a slot** (p. 87) | The innate `spell` modifier needs a fixed spell id; nothing gives a free cast of a spell chosen through a spellcasting feature. | Cantrips and the always-prepared spell work; the free cast does not |
| 7.8 | Ritual casting (p. 104 "Rituals"; glossary p. 187) | `Spell` has no ritual field. The generator stores `ritual: true`, which nothing reads yet. | Spell records |
| 7.9 | Preserve Life: **divide** 5 x level HP among Bloodied creatures, max half their HP (p. 40) | No "heal pool split among targets" behavior, no Bloodied target filter or half-max cap. | Heals one target for the full amount (`implementation: 2`) |
| 7.10 | 2024 wording in code: "Hit Point Dice", "Fixed Hit Points" (p. 23) | The builder's class panel prints "Hit Dice" and "1d8 (or 5)". | Builder |
| 7.11 | Not 2024-specific, a display bug: the sheet's spell summary evaluates `modifyability` formulas without `ability`/`upcast` symbols | Cure Wounds with Disciple of Life shows "2d8+13 Healing"; the cast itself gets the symbols. The 5e Life Domain has the same formula, so 5e shows it too. | Sheet, Spells list on the Character tab |

**Found while authoring core rules and equipment (2026-11-12).**

| # | Rule (SRD 5.2.1 page) | What the code lacks | Where it shows now |
|---|---|---|---|
| 7.12 | Armor Strength requirement: Speed -10 ft below the score (p. 92) | Not applied. | Heavy armor and the other Strength-requirement armor are implementation 2 |
| 7.13 | Tool proficiency + a related skill proficiency gives Advantage (p. 93) | Not modelled; Utilize DCs and Craft lists are text. | Tool items |
| 7.14 | "Replace one of your attacks" with an item (Acid, Alchemist's Fire, Holy Water, Net, Oil, p. 94-98) | No way to spend one attack of the Attack action. | Each costs a full action |
| 7.15 | Area hazards placed by items: Caltrops, Ball Bearings, Hunting Trap (p. 96-98) | The 5e aura pattern has no `objectid`, so `ActivatedAbilityAuraBehavior:Cast` spawns object "none" and fails; "first time on a turn" tracking is missing. | Text only |
| 7.16 | Stabilizing (Healer's Kit p. 97, Spare the Dying) | No behavior makes a creature Stable. | Text only |
| 7.17 | Spell Scroll (p. 99): a chosen spell at fixed DC 13 / +5 | No way to attach a chosen spell to an item. | Text only |
| 7.18 | Spellcasting Focus (holy symbols, arcane and druidic foci) | Foci are not modelled at all. | Items are implementation 1 |
| 7.19 | Opportunity Attacks (p. 185), so also Disengage (p. 181) | The Lua has no Opportunity Attacks. | Disengage is a marker effect |
| 7.20 | Escaping a grapple: Athletics or Acrobatics check vs the escape DC (p. 182) | "End with action" only supports saving throws. | Grappled has no escape action |
| 7.21 | Benefits used up by one roll: Help (p. 182-183) | Per-effect charges aren't consumed by rolls from the roll dialog. | Help lasts until your next turn |
| 7.22 | Hide records its Stealth total as the DC to find you (p. 183); Influence DC is 15 or the monster's Intelligence (p. 184) | No way to keep a roll's total; the skill-check behavior makes the targets roll, not the caster. | Hide works without the DC; Influence is text |
| 7.23 | An Unarmed Strike counts as one attack of the Attack action / Extra Attack | Not modelled. | Separate action |
| 7.24 | Bugs, not 2024 rules (affect 5e too): `WeaponProperty.Get` returns the code builtin before the table record, so property `details` text never shows in tooltips (`Equipment.lua` ~788); the GoblinScript `size` symbol calls `creature:GetBaseCreatureSizeNumber()` on the class instead of `c` (`Creature.lua:6292`), so off-map creatures read size 0; the sheet's DC column ignores a behavior's `dcvalue` (Hide shows DC 10, rolls against 15). | | |

Decision for you: Insight and Investigation keep `hasPassive: true` from SRD 5.1. SRD 5.2.1 defines only Passive Perception (p. 185). Removing the flags changes the sheet, so they were left.

To check, not yet known to need code: whether Thaumaturge's bonus to Arcana/Religion (a d20 roll modifier) is applied when the check is rolled (the sheet's static skill bonus leaves it out), and whether Turn Undead's "ends early if it takes damage" can be expressed on the effect.

---

## 4. Risks and unknowns

- **Republishing `dmhub-legacy` reaches every DMHub user, old retail builds included.** No publish until the Phase 1 round-trip matches. *We don't yet know whether old builds respect `minEngineVersion`.*
- Settled in Phase 0: the authoring game exists and we have publish rights.
- New risk: the authoring game has unpublished edits since 2024-04-03. These would ship with the first YAML publish unless they are reviewed (Phase 1).
- Blob storage is known: R2 `dmhub-images`, with a GCS copy for old engines. What is not known is the credentials a scripted deploy needs for `dmtool-cad62` and the DMHub blob server (Phase 2).
- Non-SRD material may already be in `dmhub-legacy`. If so, it must be excluded before we republish under the D7 rules (Phase 0 audit).
- Images and audio stay in cloud storage. YAML records only hold ids. Copying a record to the 5.5e repo reuses the same image, which is fine.
- In-app saves rewrite YAML in canonical form, so comments are lost and diffs are noisy. Commit only what you meant to change, as the draw-steel-data README warns.
- Local Assets works on DMHub (verified in Phase 1). Builds older than engine commit `47f8f6b3f` have a YAML writer that loses `\r`, NEL and trailing tabs in 278 of the v14 items (Phase 1 round trip). Export with a build that includes the fix. Even with the fix, a `\r\n` pair reads back as `\n` by design.
- Scale: Phase 6 is weeks to months of content work. The SRD has roughly 12 classes x 20 levels, ~340 spells and 300+ monsters.

## 5. Suggested next step

Phase 4 (the SRD 5.2.1 source) is done, ahead of order, so that 5.5e work can start alongside Phase 1.

Finish Phase 1 (see "Still to do in Phase 1" above). The order:
1. Create both private GitHub repos and push:
   - `C:\dev\dmhub-dnd5e`, which has 2 commits;
   - `C:\dev\dmhub-dnd2024`, which has 1 commit (`8c6d173`): the SRD Markdown and `tools/srd2md.py`.

   The org (VerisimLLC assumed) is unconfirmed.
2. Wire Local Assets into d20.
3. Then the SRD clean-up.

Phase 5 (the 5.5e authoring game, scaffolding tables, `SRD_COVERAGE.md` and the checker) can then start from `source/srd-5.2.1/`.

Nothing is published in Phase 1.
