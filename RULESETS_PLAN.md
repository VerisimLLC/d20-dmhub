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

**Progress 2026-11-12 (uncommitted, needs a DMHub build to test):**
- Engine option chosen: `lobby:CreateGame{gameSystem = ...}` writes `GameInfo.gameSystem` before the first save (`Assets/GamesMonitor.cs`, edited in `C:\dev\dmhub`).
- The New Game panel has a Game System dropdown over `AvailableGameSystems`, with the chosen system's description under it. It is shown to everyone, not only in dev mode.
- Renamed "D&D 5e" to "5e" (and the theme description in `Styles.lua`).
- Added `dmhub-dnd2024` as "5.5e" with the SRD 5.2.1 attribution. **Visible to everyone, not dev-only** (David 2026-11-12), although the module is not published yet: a game created with it gets no content until the first publish.
- Not done: the Campaign Settings lock (D5).

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

**Phase 6, round 1 (2026-11-12).** Six agents in parallel, then backgrounds once the feat ids existed; every batch reviewed, spot-checked in the authoring game and committed separately in `dmhub-dnd2024`: spells 4-5 (`347f3bb`), feats and the 2024 ASI/Fighting Style prefabs (`bdc4b13`), species with lineages as subraces (`658425a`), spells 6-9 (`515f2b3`), spells 2-3 (`c00f5d1`), backgrounds (`35b902b`), spells 0-1 (`ec96c57`), spell lists and checker spell references (`c8ba0ba`). All 339 spells, 17 feats, 4 backgrounds and 9 species are authored. Insight and Investigation lost their 5.1 passive scores (`238363d`). **Coverage:** 1,403 entries; 14 tested, 553 authored, 836 todo (remaining: classes 247 entries, magic items 258, monsters 235, animals 95).

**Phase 6, round 2: classes (2026-11-12).** Twelve agents in two waves, one class each (class + its SRD subclass, levels 1-20), each checked in the authoring game with a level 5 test character (HP, slots, resources, key abilities) before its commit: Fighter `7c52948`, Barbarian `8bfb202`, Cleric to 20 `c519402`, Bard `1231f64`, Druid `b463282`, Monk `31c97e0`, Ranger `5d69bc1`, Paladin `da65641`, Rogue `f11f7b4`, Wizard `c369eee`, Sorcerer `dfbec01`, Warlock `97f26c2`. Shared records changed to the 2024 rules on the way: Bardic Inspiration d8-d12, Focus Points and Warlock slots now refresh on a Short Rest. A class added while the game runs needs a game reload before its `<Class> Level` symbol exists (now in the skill). **Known data follow-ups:** the Bard's Superior Inspiration formula reads `Resources.BardicInspirationd12`, which GoblinScript can't parse (confirmed in the app); Foe Slayer needs the Hunter's Mark die to come from an attribute. **Coverage:** 1,403 entries; 14 tested, 800 authored, 589 todo -- the character side is complete; what remains is magic items (258), monsters (235), animals (95) and Two-Handed (a code builtin).

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
   **Authored 2026-11-12, committed 2026-11-13:** all 330 stat blocks (235 Monsters A-Z + 95 Animals) in `dmhub-dnd2024/monsters/`, generated by `tools/authoring/monsters.py` (parser: `monstergen.py`). Stats, saves, skills, senses, resistances/immunities, languages, CR, gear (inventory) and AC/initiative overrides are data. Attacks, saves with damage, conditions, pushes, recharge, uses per day, innate spellcasting and legendary actions that reuse an action are mechanics; everything else is the SRD text on the ability. Per-ability grades (388 full, 281 partial, 142 text) are in `MONSTER_AUTOMATION.md`. Folders reuse the engine's core creature-type folder ids, copied into `monsterFolders/`. Checked in the authoring game: all 330 load, sheets render, rolls parse, innate spells and charges appear; a scripted combat test (2026-11-13) passed attacks with mixed damage, a hit rider condition, save-for-half area damage, damage resistance/immunity, condition immunity, a save-or-be-Charmed with per-day charges, innate spell DCs, a legendary action reusing an attack, and Recharge.
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

Decided (user, 2026-11-12): Insight and Investigation no longer have passive scores in 5.5e; SRD 5.2.1 defines only Passive Perception (p. 186). Data-only change in `dmhub-dnd2024`, 5e unchanged.

**Found in Phase 6, round 1 (spells, feats, species, backgrounds; 2026-11-12).** Grouped by the batch that found them; several recur across batches (lingering areas, repeat saves, effects ending on damage, "creatures of your choice"), which makes them the highest-value code work. Page numbers are SRD 5.2.1.

#### Spells 4-5 (347f3bb)
- Lingering/moving areas: save/damage on enter, end turn in, or moved into (Black Tentacles p.113, Cloudkill p.116, Insect Plague p.143, Wall of Fire p.172, Conjure Woodland Beings p.118, Guardian of Faith p.137, Conjure Elemental p.118)
- Repeat save that deals damage on failure; effect triggers can't read the caster's spell save DC (Phantasmal Killer p.152, Conjure Elemental p.118); counting successes/failures (Contagion p.119)
- Saves repeated when damaged / effects ending on damage (Dominate Beast p.125, Dominate Person p.126, Charm Monster p.114, Modify Memory p.150)
- Advantage on the save if you or allies are fighting it (Charm Monster, Dominate Beast/Person, Modify Memory)
- Unlimited "each creature of your choice" targeting; "up to six in a sphere" (Compulsion p.117, Mass Cure Wounds p.147)
- Upcast growing area (Confusion p.117, Private Sanctum p.156, Creation p.121) or duration (Dominate, Geas p.135, Planar Binding p.152, Modify Memory)
- Reusing a spell's action on later turns without a slot (Arcane Hand p.110, Telekinesis p.167, Compulsion, Control Water p.119, Arcane Eye p.110)
- Long-rest timing: penalty -1 per Long Rest (Raise Dead p.157); "until you finish a Long Rest" (Contact Other Plane p.119)
- Invisibility ending on attack/damage/spell (Mislead p.150)
- Condition immunity against magical sources only (Freedom of Movement p.134)
- Remove one Exhaustion level / curse / ability or HP-max reduction (Greater Restoration p.137)
- HP max can't be reduced; ally at 0 HP regains 1 at turn start (Aura of Life p.111)

#### Feats
- Ability score caps (20; 30 for boons) not enforced (p. 87-88)
- Repeatable feats: CharacterFeatChoice marks every feat unique; a feat's inner choices are keyed by fixed guid (p. 87)
- Per-die damage minimum (Great Weapon Fighting p. 88); roll damage twice keep either (Savage Attacker p. 87)
- "Grappled by you" symbol (Grappler p. 87); ignore Resistance (Boon of Irresistible Offense p. 88); light-level conditions (Night Spirit p. 88)
- Prerequisite "has Fighting Style / Spellcasting feature" not expressible (p. 87-88)

#### Species
- Breath Weapon replaces one attack of the Attack action (Dragonborn p. 84) -- same as 7.14
- Innate species spells can't also be cast with spell slots (usesSpellSlots false) (Elf p. 84, Gnome p. 85, Tiefling p. 86)
- Heroic Inspiration granted on a Long Rest (Human Resourceful p. 86)
- Powerful Build: carrying capacity multiply, Advantage on checks to end Grappled (Goliath p. 86)
- Trance: sleep immunity, 4-hour Long Rest (Elf p. 84); Halfling Nimbleness (p. 86)
- Goliath boons "after you hit": no on-hit trigger that doesn't loop on its own damage (p. 85)
- Checker: validate the `spell` key of innate spell modifiers (TODO in check.py)

#### Spells 6-9 (see commit message)
- Repeat save only on an apply-effect behavior with its own first save (Sunburst p.167, Weird p.174, Power Word Stun p.154); three-successes counting (Flesh to Stone p.133, Prismatic Spray p.154, Prismatic Wall p.155); repeat on damage (Dominate Monster p.125); end-with-action save uses fixed DC (Irresistible Dance p.143)
- Duration not GoblinScript, so not slot-dependent (Mass Suggestion p.148, Dominate Monster p.125)
- Walls/persistent zones (Blade Barrier p.113, Wall of Ice p.172, Wall of Thorns p.173, Incendiary Cloud p.142, Earthquake p.127, Storm of Vengeance p.165, Tsunami p.171)
- Several areas per cast (Meteor Swarm p.149); per-target random table (Prismatic Spray p.154); delayed detonation (Delayed Blast Fireball p.122)
- "Dies" only sets HP 0 (Power Word Kill p.154, Divine Word p.125); "can't cast spells" (Befuddlement p.112)
- Spell-level immunity, antimagic (Globe of Invulnerability p.136, Antimagic Field p.109); aura retaliation save (Holy Aura p.141); HP max floor 1 (Harm p.139)
- Re-trigger/move a spell effect on later turns (Arcane Sword, Conjure Fey, Sunbeam, Conjure Celestial, Eyebite)

#### Spells 2-3
- DATA TODO: lingering areas need map objects (ActivatedAbilityAuraBehavior needs objectid); dmhub-dnd5e/objects has 8 -- consider copying the aura objects (Darkness p.122, Daylight p.122, Web p.174, Spike Growth p.164, Sleet Storm p.163, Stinking Cloud p.165, Flaming Sphere p.132, Wind Wall p.174, Plant Growth p.153, Magic Circle p.145, Tiny Hut p.169, Moonbeam p.150)
- Aura triggers only on enter: no start/end-of-turn-in-area, no once-per-turn (Moonbeam, Spirit Guardians p.164, Web, Sleet Storm, Stinking Cloud, Conjure Animals p.117, Gust of Wind p.138)
- Effect-granted abilities don't carry caster's DC/upcast (Spirit Guardians p.164, Dragon's Breath p.126)
- Repeatable action tied to an active spell (Flame Blade p.132, Vampiric Touch p.171, Call Lightning p.114, Heat Metal p.139, Moonbeam, Detect Thoughts p.123)
- No walking-Speed symbol (Alter Self p.107, Spider Climb p.164)
- Heal equal to damage dealt (Vampiric Touch); half damage on a miss (Acid Arrow p.107)
- "Any number of creatures of your choice" (Enthrall p.128, Beacon of Hope p.112)
- Save Disadvantage by creature type (Shatter p.161); "regains max from healing" (Beacon of Hope)
- One endTrigger per effect; no spell-cast trigger (Invisibility p.143); no on-spell-end effect (Haste p.139)
- Weapon enchantment (Magic Weapon p.146); action economy: extra limited action (Haste), no reactions/action-or-bonus (Slow p.163)
- Save only for unwilling targets (Enlarge/Reduce p.127, Levitate p.144)
- Counterspell p.120, Dispel Magic p.124, Revivify p.159 behaviors
- Two casting times (Plant Growth p.153)

#### Backgrounds
- Soldier's equipment Gaming Set can't be tied to the Gaming Set chosen for the tool proficiency ("same as above", p. 83).

#### Spells 0-1
- Marker-only effects: can't regain HP (Chill Touch p.115), no Opportunity Attacks (Shocking Grasp p.162), no benefit from Invisible (Faerie Fire p.129, Starry Wisp p.165)
- Light emitted by a spell or effect (Dancing Lights p.121, Produce Flame p.156)
- Damage-dice triggers: exploding 8s (Sorcerous Burst p.163), doubles leap (Chromatic Orb p.115)
- Smites as part of the hit, doubled on a Critical Hit (Divine Smite p.125, Searing Smite p.160, Ensnaring Strike p.128)
- Start-of-turn save with no initial save (Searing Smite); two-stage save (Sleep p.163); save triggered by damage, with Advantage (Hideous Laughter p.140)
- Escape by Strength (Athletics) check against the spell save DC (Ensnaring Strike, Entangle p.128); ends when you or allies damage it (Animal Friendship p.107, Charm Person p.115)
- Secondary area centered on the target (Ice Knife p.141); forced Reaction movement (Dissonant Whispers p.124)
- Hex/Hunter's Mark: upcast Concentration duration, moving the mark (p.140-141)
- Caster-based recurring benefit on the target (Heroism p.140)
- Weapon attacks with the spellcasting ability and a changed damage die (Shillelagh p.162, True Strike p.171)
- Shield's +5 can't change the triggering hit; per-spell damage immunity (Magic Missile) (p.161)
- Bug: `armorclasscalculation` filterCondition is never honored (`CharacterModifier.lua` ~1467 compares a boolean with 0)

#### SRD inconsistency (not code)
- Phantasmal Force's header lists Bard, Sorcerer and Wizard, and Mind Spike's lists Sorcerer, but the class spell-list tables (and the PDF) omit them. The module's lists follow the spell headers.

#### Data still to add
- Map objects for placed areas: the 5e module ships aura objects in `objects/`; copying them would let Darkness, Web, Spike Growth, Moonbeam and other placed areas work.
- Goodberry item (Goodberry p.137); monsters for summons (Find Familiar, Find Steed, Animate Dead, Conjure spells).

**Found in Phase 6, round 2 (classes; 2026-11-12).** Recurring across classes, so highest value: once-per-turn limits (everything uses once per round), adding a die after seeing a failed roll, regaining one use on a Short Rest, Short Rest triggers, Extra Attack (a marker; nothing counts attacks), Weapon Mastery, reactions that change another creature's roll, re-picking choices on a rest, and GoblinScript's letters-only identifiers.

#### Fighter
- Add to a check after it fails, refund if still failed (Tactical Mind p. 48)
- Reroll a failed save and have it count (Indomitable p. 48)
- Move half Speed without provoking OAs (Tactical Shift p. 48, Remarkable Athlete p. 49)
- One-shot Advantage on next attack vs that creature (Studied Attacks p. 48)
- Grant Heroic Inspiration from data (Heroic Warrior p. 49; also Human Resourceful)
- Extra Attack: the `multiattack` modifier is a marker; nothing counts attacks (p. 48)
- Engine quirk: a class added mid-session has no <Class> Level symbol until reload

#### Barbarian
- Reaction attack with your own weapon (Retaliation p. 30)
- DC that rises per use and resets on a rest (Relentless Rage p. 30)
- Rage lapsing when not extended; Rage blocking spells and Concentration (p. 29)
- Skill check made with a different ability (Primal Knowledge p. 29)
- Regain uses on rolling Initiative (Persistent Rage p. 30)
- Replace a roll total with an ability score (Indomitable Might p. 30)
- Brutal Strike: forgo Advantage for extra dice and effects (p. 29-30)
- Movement granted as part of an ability (Instinctive Pounce p. 29)

#### Cleric
- Maximize healing dice (Supreme Healing p. 40-41)
- Whom a spell targeted ("cast on others": Blessed Healer p. 40)
- An ability's source class/spell list (Potent Spellcasting p. 38)
- Trigger on "a cantrip dealt damage" + choose a creature for THP (Improved Blessed Strikes p. 38)
- Once on each of your turns (vs per round) (Divine Strike p. 38)
- Unavailable for 2d4 Long Rests (Greater Divine Intervention p. 38)

#### Bard
- Add a die after seeing a failed roll (Bardic Inspiration p. 32; same timing gap as Guidance, Peerless Skill p. 35)
- Reaction to another creature's failed save + reroll with Advantage (Countercharm p. 33)
- Reaction that subtracts from an enemy's roll (Cutting Words p. 35)
- "Not expended if the roll still fails" refund (Peerless Skill p. 35)
- Combined cantrip-or-leveled-spell count (Magical Discoveries p. 35)
- One Bardic Inspiration die per creature across die sizes (p. 32)

#### Druid
- Wild Shape: known forms (4/6/8), duration half Druid level hours, ends on Incapacitated, the Beast's senses, worn equipment, THP from the transform (p. 42-43)
- Beast Spells: costly/consumed Material components (p. 43)
- Re-pick the land after a Long Rest (p. 46)
- Recover spell slots up to a total-level budget (Natural Recovery p. 46; Wizard Arcane Recovery too)
- Movable cube with Half Cover and ally Resistance (Nature's Sanctuary p. 46)
- DATA: Beasts (Animals chapter) needed for Wild Shape and Find Familiar

#### Monk
- Swap a weapon's damage die (Martial Arts on Monk weapons p. 50); Dex for Grapple/Shove DC
- Roll a die into a damage reduction from a reaction (Deflect Attacks p. 51)
- Reduce falling damage (Slow Fall p. 51)
- Choose damage type per hit (Empowered Strikes p. 51)
- Optional triggers fire without asking the player (so paid features are manual abilities)
- Stunning Strike tied to a hit, once per turn (p. 51)

#### Ranger
- Exempt one spell from Concentration checks on damage (Relentless Hunter p. 59)
- DATA follow-up: Foe Slayer (p. 59) needs Hunter's Mark's die from an attribute
- Extra attack against a nearby target (Horde Breaker p. 61); OA filter (Escape the Horde p. 61); Disadvantage tied to one attacker (Multiattack Defense p. 61)
- Hunter's Mark damage spilling over (Superior Hunter's Prey p. 61); Reaction granting Resistance before damage (Superior Hunter's Defense p. 61)
- Decrease Exhaustion on a Short Rest (Tireless p. 59)

#### Paladin
- Channel Divinity uses per class when multiclassed (shared resource) (p. 54)
- Only one Paladin aura benefits a creature (p. 55)
- Effect ending on damage + one-thing-per-turn limit (Abjure Foes p. 55)
- Imbue one specific weapon; Radiant instead; light; ends if not carried (Sacred Weapon p. 56)
- "Who forced this save" symbol (Holy Nimbus p. 57)

#### Rogue
- d20 floor on the die (treat 9 or lower as 10), not the total (Reliable Talent p. 63; 5e's minroll 10 is wrong too)
- Turn a d20 into a 20 after rolling (Stroke of Luck p. 63)
- Two Cunning Strike effects per hit (Improved Cunning Strike p. 63)
- "Once per turn" approximated as once per round everywhere (Sneak Attack p. 62 and many others)

#### Wizard
- Half damage on a miss or successful save (Potent Cantrip p. 82)
- Choose creatures that auto-succeed in an area (Sculpt Spells p. 82; Careful Spell)
- Maximize spell damage dice + escalating backlash (Overchannel p. 82)
- Short Rest trigger; resource maximum/expended symbol (Arcane Recovery p. 78)
- Choices limited to spells in the spellbook (Spell Mastery, Signature Spells p. 79); free spellbook entries limited to a school (Evocation Savant p. 82)
- DATA: no Spellbook item in SRD equipment

#### Sorcerer
- BUG/limit: GoblinScript identifiers are letters only, so resources with digits (spell slots, "Bardic Inspiration (d12)") can't be read. DATA follow-up: Bard Superior Inspiration formula `Resources.BardicInspirationd12` does not evaluate (confirmed in app).
- Per-class spell save DC / spell attack bonus (Innate Sorcery p. 66)
- Metamagic changing dice, duration, components, damage type, level; one option per spell (p. 67)
- Effect lasting for "saves against this spell" (Heightened p. 67)
- Created spell slots above the maximum (p. 66)
- Free cast without Material/Concentration (Dragon Companion p. 70)
- One damage roll per spell (Elemental Affinity p. 70)

#### Warlock
- Class-level prerequisites (only character level exists); "has invocation X", "knows a damaging cantrip" (p. 72-74)
- Formula ranges in Modify Abilities (Eldritch Spear 30 x level p. 73)
- Modify only a feature's free cast of a spell (maximized False Life, Find Familiar as Magic action, "on yourself" p. 73-74)
- Restore a per-feature use by spending a slot (Hurl Through Hell p. 76; also Holy Nimbus done as a separate ability)
- Bonded pact weapon tracking (Pact of the Blade, Thirsting/Devouring Blade, Eldritch Smite, Lifedrinker p. 72-74)
- Ritual-tag filter; re-pick on each rest (Book of Shadows p. 74; Fiendish Resilience p. 76; Circle of the Land)
- Repeatable choices (Lessons of the First Ones p. 73; feats)

**Found in Phase 6, round 3 (monsters; 2026-11-12).** From `dmhub-dnd2024/MONSTER_AUTOMATION.md`, which lists every case by monster. Highest value first:
- **Recharge was display-only** (nothing rolled it; ~80 abilities). Implemented 2026-11-13, verified in the authoring game (Adult Red Dragon: blocked after Fire Breath, a failed roll keeps it spent, a 5-6 restores it, a Short Rest restores it): `ActivatedAbility:RechargeResourceId` + a "Recharge X-6" cost entry in `GetCost` (one use, refresh type `short`, so a Short or Long Rest also restores it, SRD p. 254), and `creature:RollRecharges` from `BeginTurn` rolls a GM-only 1d6 per spent Recharge ability. Applies to the 5e module's Recharge abilities too.
- "Per day" usage limits never reset on their own (`GetResourceRefreshId("day")` is a constant); fine for one-encounter monsters.
- Size-gated riders ("If the target is a Large or smaller creature, it has the Grappled/Prone condition"; 66 abilities). Needs a reliable target-size symbol for `filterTarget` (the `size` symbol bug in 7.24 blocks it).
- Multiattack: no engine routine; it is a note (177 monsters).
- Grappled with an escape DC; "swallowed" creatures (Behir, Purple Worm, Tarrasque ...).
- Repeat save after a damaging save (the repeat save lives on the effect, which then rolls its own first save).
- Durations on the target's turn ("until the end of its next turn"): `ApplyOngoingEffect` counts on the caster's turn. Set to the monster's turn and flagged.
- Legendary action uses: hardcoded 3 (`dnd5e.lua:115`); 2024 has "3 (4 in Lair)". Legendary Resistance (N/Day, more in lair) is only a note.
- Innate spells cast at a higher level ("*Fireball* (level 4 version)", 54 abilities with a spell note) and legendary actions that cast a spell: innate spellcasting has no upcast field, and a spell cannot be a legendary action.
- Reaction triggers (21), area targets limited to enemies or with a type filter, "Failure or Success" clauses, Melee-or-Ranged attacks (split into two abilities), hover (speed note only), "Medium or Small" sizes (first one used), darkvision "unimpeded by magical Darkness".

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
