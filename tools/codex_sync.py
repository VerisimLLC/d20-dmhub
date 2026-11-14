"""Sync the shared, game-system-neutral Lua layer from the Draw Steel Codex into d20.

See CODEX_SYNC.md (repo root) for what this is and why. In short: the Codex is
upstream for the DMHub UI modules (Core UI, Core Panels, Game Hud, Utils) and
the DocumentSystem/ChatPanel mods; d20 keeps its own 5e rules and the files
listed in KEEP_D20. Running this is a plain copy plus a few recorded patches,
so a sync is reviewable as a git diff.

usage (from anywhere):
    python tools/codex_sync.py <codex checkout or export> [--apply]

<codex> is a draw-steel-codex tree at the commit the engine pins, e.g.
    git -C <engine> ls-tree HEAD draw-steel-codex      # -> the pinned sha
    git -C <codex repo> archive <sha> | tar -x -C <empty dir>
Without --apply it only reports. Every patch must apply exactly once; a patch
that no longer matches stops the sync so a human can look at the new upstream.
"""
import os
import sys
from collections import Counter

D20 = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

# (codex dir, d20 dir): every .lua in the first is copied into the second,
# except SKIP / KEEP_D20 and RELOCATE (which sends a file somewhere else).
MAPPINGS = [
    ("DMHub Core UI", "DMHub Core UI"),
    ("DMHub Core Panels", "DMHub Core Panels"),
    ("DMHub Game Hud", "DMHub Game Hud"),
    ("DMHub Utils", "DMHub Utils"),
    # The Codex split these into mods of their own. d20 keeps them in existing
    # mods, so a sync never needs a new cloud mod. DocumentSystem goes at the
    # END of Game Hud's file list: in the Codex it is a separate mod loading
    # right after Game Hud, and it uses Game Hud's globals while it loads.
    ("DocumentSystem", "DMHub Game Hud"),
    ("ChatPanel", "DMHub Core Panels"),
]

# d20 files that are still registered in the cloud but whose code moved (a
# file cannot be unregistered), written as one-line stubs, as the Codex does
# for its own moved files. path -> where the code went.
STUBS = {
    "DMHub Core UI/" + name + ".lua": "DMHub Game Hud/" + name + ".lua"
    for name in [
        "DocumentSystem", "MarkdownDocument", "DocumentImport", "TextStorage",
        "LinkResolution", "Bar", "RichImage", "RichAudio", "RichVideo", "RichDice",
        "RichCheckbox", "RichCounter", "RichTimer", "RichSetting", "RichScene",
        "RichReminder", "RichMacro", "RichItemLink", "MarkdownDocCreate",
        "MarkdownDisplay", "DocumentNewUser",
    ]
}

# A d20-only file that holds a verbatim copy of a function from a synced file
# (see the file's header). The sync stops if the upstream function changes.
# (d20 file, synced file, first line of the function)
VERBATIM_COPIES = [
    ("DMHub Core UI/D20LoadOrder.lua", "DMHub Utils/Utils.lua", "function Commands.RegisterMacro(args)\n"),
    ("DMHub Core UI/D20LoadOrder.lua", "DMHub Utils/Utils.lua", "function Commands.RegisterBuiltinDoc(args)\n"),
]

# Single files from outside MAPPINGS.
EXTRA = [
    # A strict superset of d20's: adds the world-map / hex-map settings that
    # MapSettings.lua and RulerTool.lua use. No 5e content in either version.
    ("DMHub Game Rules/MeasurementSystem.lua", "DMHub Game Rules/MeasurementSystem.lua"),
]

# codex path -> d20 path, for files that must live elsewhere in d20.
RELOCATE = {
    # At cold boot only DMHub Titlescreen loads, and d20's title bar
    # (Titlescreen/Styles.lua) uses ThemeEngine while it loads.
    "DMHub Core UI/ThemeEngine.lua": "DMHub Titlescreen/ThemeEngine.lua",
}

# d20 paths whose d20 version stays: the Codex hollowed these out into Draw
# Steel mods, or its version hard-depends on Draw Steel rules hooks.
KEEP_D20 = {
    "DMHub Core Panels/AIPanel.lua",               # Codex: stub (moved to Development Utilities)
    "DMHub Core Panels/Devtools.lua",              # Codex: stub
    "DMHub Core Panels/DicePanel.lua",             # Codex: stub
    "DMHub Core Panels/GoblinScriptDebugger.lua",  # Codex: moved to Development Utilities
    "DMHub Core Panels/CharacterPanel.lua",        # Codex needs Draw Steel's SingleCharacterDisplaySidePanel; d20 has the 5e side panel
    "DMHub Game Hud/ActionBar.lua",                # 5e action bar (Codex: DrawSteelActionBar)
    "DMHub Game Hud/InitiativeBar.lua",            # 5e initiative bar
    "DMHub Game Hud/RollDialog.lua",               # 5e roll dialog (Codex: Draw Steel UI)
    "DMHub Game Hud/RestDialog.lua",               # 5e short/long rest (Codex: Draw Steel respite)
    "DMHub Game Hud/RequireDCDialog.lua",          # Codex uses Draw Steel's RollCheck.Checks
    "DMHub Game Hud/RollOnTableDialog.lua",        # Codex indexes Draw Steel's RollDialog
}

# codex paths not brought over at all.
SKIP = {
    # empty / one-line stubs that exist only in the Codex
    "DMHub Core UI/UISettings.lua", "DMHub Core UI/Unused2.lua",
    "DMHub Core Panels/New File2.lua", "DMHub Core Panels/Questboard.lua",
    "DMHub Core Panels/TriggersPanel.lua", "DMHub Game Hud/GameHudMenu.lua",
    "DocumentSystem/RichDrawsteel.lua", "DocumentSystem/RichFishing.lua",
    # Draw Steel rules content in the document system
    "DocumentSystem/RichEncounter.lua", "DocumentSystem/RichFollower.lua",
    "DocumentSystem/HeroicTestDocument.lua", "DocumentSystem/MontageDocument.lua",
    "DocumentSystem/CampaignTrackerPanel.lua", "DocumentSystem/RichParty.lua",
    "DocumentSystem/RichResource.lua", "DocumentSystem/GameOfChance.lua",
    "DocumentSystem/ShellGame.lua",
    # puzzles: a separate feature, not yet ported
    "DocumentSystem/PuzzleFramework.lua", "DocumentSystem/PuzzleList.lua",
    "DocumentSystem/PuzzleLock.lua", "DocumentSystem/PuzzleTerminal.lua",
    "DocumentSystem/RichPuzzle.lua", "DocumentSystem/RichTornPuzzle.lua",
    "DocumentSystem/TornPuzzleShapes.lua", "DocumentSystem/RichSliderPuzzle.lua",
}

# Recorded patches to synced files: d20 path -> [(old, new, count)].
# Strings are matched with LF line ends (files are compared and written with
# their own line ends; see apply_patches).
PATCHES = {
    "DMHub Titlescreen/ThemeEngine.lua": [
        ("if devmode() then\n    Commands.RegisterMacro{\n        name = \"themecache\",",
         "--d20 patch (see CODEX_SYNC.md): in d20 this file loads with DMHub Titlescreen,\n"
         "--before Commands.RegisterMacro exists (DMHub Utils), so both macros register\n"
         "--a moment later.\n"
         "dmhub.Schedule(0.1, function()\n"
         "if mod.unloaded or rawget(_G, \"Commands\") == nil or Commands.RegisterMacro == nil then return end\n"
         "if devmode() then\n    Commands.RegisterMacro{\n        name = \"themecache\",", 1),
        ("tostring(_enforceSafetySetting:Get())), \"safetheme\", \"#cc4444\", dmhub.userid)\n        end\n    end,\n}\n",
         "tostring(_enforceSafetySetting:Get())), \"safetheme\", \"#cc4444\", dmhub.userid)\n        end\n    end,\n}\nend) --d20 patch\n", 1),
        # Registering a scheme or theme must drop the resolved-styles cache. In
        # d20 this file loads with DMHub Titlescreen, long before Core UI's
        # DefaultStyles registers the default theme, so a GetStyles() in that
        # window (the title screen's dropdowns) cached an empty result for the
        # whole session and the in-game title bar merged against it.
        ("        highContrast = spec.highContrast == true,\n    }\n    return true\nend\n",
         "        highContrast = spec.highContrast == true,\n    }\n"
         "    _cache = {} --d20 patch: drop styles resolved before this scheme existed\n"
         "    return true\nend\n", 1),
        ("        styles = spec.styles or {},\n    }\n    return true\nend\n",
         "        styles = spec.styles or {},\n    }\n"
         "    _cache = {} --d20 patch: drop styles resolved before this theme existed\n"
         "    return true\nend\n", 1),
    ],
    # "Director" is Draw Steel's word for the game master; DMHub says DM.
    "DMHub Game Hud/DirectorScreen.lua": [
        ('text = "Director\'s Screen"', 'text = "DM\'s Screen"', 1),
        # The cover art is an image in the Codex's cloud, not DMHub's: it shows
        # as a grey slab. Without an image the screen is its plain dark band.
        ('{id = "vasloria", image = "e83e6ea1-6212-4baf-8f26-a11bf7b85c6e", width = 2000, height = 633, left = 0, tint = "#ffffffff", veil = "#16171bf2"},',
         '{id = "plain", width = 2000, height = 633, left = 0, veil = "#16171bf2"}, --d20 patch: no Codex cover art', 1),
        # A new table (no saved layout) starts with the screen shut, not open
        # at DEFAULT_FRACTION (David, 2026-11-14). The first click on the tab
        # still opens it to DEFAULT_FRACTION; saved layouts keep their size.
        ("    g.fraction = DEFAULT_FRACTION\n    g.lastFraction = DEFAULT_FRACTION\n    if type(saved) == \"table\" then",
         "    g.fraction = 0 --d20 patch: a new table starts with the screen shut (the tab opens it to DEFAULT_FRACTION)\n"
         "    g.lastFraction = DEFAULT_FRACTION\n    if type(saved) == \"table\" then", 1),
    ],
    "DMHub Game Hud/Tabletop.lua": [
        ("Close this to return to being the Director.", "Close this to return to being the DM.", 1),
        ('"Shared by the Director"', '"Shared by the DM"', 1),
        ('Entry("Director Controlled"', 'Entry("DM Controlled"', 1),
        ("so the Director's moves no longer reach it. Click to put it back where the Director has",
         "so the DM's moves no longer reach it. Click to put it back where the DM has", 1),
    ],
    "DMHub Game Hud/SceneElements.lua": [
        ('text = "Only the Director"', 'text = "Only the DM"', 1),
    ],
    "DMHub Game Hud/Keybinds.lua": [
        ('tr("Toggle Broadcast Director Mouse Cursor")', 'tr("Toggle Broadcast DM Mouse Cursor")', 1),
    ],
    "DMHub Core Panels/Commands.lua": [
        ('name = "Director Darkvision"', 'name = "DM Darkvision"', 1),
        ('name = "New Director Window"', 'name = "New DM Window"', 1),
    ],
    "DMHub Core Panels/DrawingPanel.lua": [
        ("the Director can erase anyone's.", "the DM can erase anyone's.", 1),
    ],
    "DMHub Core UI/DockablePanel.lua": [
        ('"Dockable Panels set up for Director view."', '"Dockable Panels set up for DM view."', 1),
    ],
    "DMHub Game Hud/DocumentSystem.lua": [
        ('" (Director only)"', '" (DM only)"', 1),
        ('text = "Director only"', 'text = "DM only"', 1),
        ('reason = "Director only"', 'reason = "DM only"', 1),
        ('s.reason == "Director only"', 's.reason == "DM only"', 1),
        ('id = "builtin:director",\n        name = "Director",', 'id = "builtin:director",\n        name = "DM",', 1),
    ],
}


def ascii_fix(data):
    # d20 is ASCII-only; the Codex's few non-ASCII bytes are in comments.
    return data.replace(b"\xe2\x80\x94", b"--").replace(b"\xc3\xa4", b"a")


def apply_patches(dst, data):
    crlf = b"\r\n" in data
    text = data.replace(b"\r\n", b"\n").decode("ascii")
    for old, new, count in PATCHES.get(dst, []):
        n = text.count(old)
        if n != count:
            raise SystemExit(f"PATCH MISMATCH in {dst}: expected {count} of {old[:70]!r}, found {n}")
        text = text.replace(old, new)
    out = text.encode("ascii")
    return out.replace(b"\n", b"\r\n") if crlf else out


def plan(codex):
    items = []  # (action, codex path, d20 path)
    for src, dst in MAPPINGS:
        for f in sorted(os.listdir(os.path.join(codex, src))):
            if f.endswith(".lua"):
                items.append((f"{src}/{f}", f"{dst}/{f}"))
    items += EXTRA
    out = []
    for key, dkey in items:
        dkey = RELOCATE.get(key, dkey)
        if key in SKIP:
            out.append(("skip", key, dkey))
        elif dkey in KEEP_D20:
            out.append(("keep-d20", key, dkey))
        else:
            out.append(("copy", key, dkey))
    return out


def main():
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    codex = sys.argv[1]
    apply = "--apply" in sys.argv
    for p in PATCHES:
        if p not in {d for a, _, d in plan(codex) if a == "copy"}:
            raise SystemExit(f"patch target is not a synced file: {p}")
    results = []
    for action, key, dkey in plan(codex):
        if action != "copy":
            results.append((action, key, dkey))
            continue
        data = ascii_fix(open(os.path.join(codex, key), "rb").read())
        if any(b > 127 for b in data):
            raise SystemExit(f"non-ASCII bytes left in {key}")
        data = apply_patches(dkey, data)
        dpath = os.path.join(D20, dkey)
        if os.path.exists(dpath):
            if open(dpath, "rb").read() == data:
                results.append(("same", key, dkey))
                continue
            results.append(("overwrite", key, dkey))
        else:
            results.append(("NEW", key, dkey))
        if apply:
            with open(dpath, "wb") as h:
                h.write(data)
    for stub, moved_to in sorted(STUBS.items()):
        data = ("local mod = dmhub.GetModLoading()\r\n\r\n"
                f"--Moved to {moved_to} (see CODEX_SYNC.md).\r\n").encode("ascii")
        spath = os.path.join(D20, stub)
        if os.path.exists(spath) and open(spath, "rb").read() == data:
            results.append(("same", "(stub)", stub))
            continue
        results.append(("stub", "(stub)", stub))
        if apply:
            with open(spath, "wb") as h:
                h.write(data)

    for copy_path, synced_path, first_line in VERBATIM_COPIES:
        def function_text(path):
            text = open(os.path.join(D20, path), "rb").read().decode("ascii").replace("\r\n", "\n")
            start = text.index(first_line)
            return text[start:text.index("\nend\n", start) + len("\nend\n")]
        if function_text(copy_path) != function_text(synced_path):
            raise SystemExit(f"VERBATIM COPY OUT OF DATE: {copy_path} no longer matches "
                             f"{first_line.strip()} in {synced_path}; re-copy it.")

    for a, k, d in results:
        if a != "same":
            print(f"{a:10s} {k:52s} -> {d}")
    print(dict(Counter(a for a, _, _ in results)))
    if not apply:
        print("(dry run; pass --apply to write)")


main()
