"""DMHub smoke test for the new CodeMod set (SHARED_UI_LAYER_PLAN.md, step 6).

Launches a DMHub dev build (DMHub white label) into one test game per game
system, with the new set's root mods, and drives it through its MCP bridge.
Fails on any console error. Run it before checking the new mods in, and after
a Codex change that touches the shared mods.

  python tools/smoke_test.py                  every game in the games file
  python tools/smoke_test.py --only 5e        one system
  python tools/smoke_test.py --no-launch      the game DMHub is in now (no relaunch)
  python tools/smoke_test.py --list-games     the lobby's games, to fill in the games file

Per game it checks:
  - the game's system id, and that its system root (and no other root, and no
    legacy DMHub mod) is loaded
  - no console errors while loading
  - every registered dockable panel (DockablePanel.GetMenuItems) opens and
    closes without an error
  - the DM's Screen opens and closes, and a /roll in chat resolves
  - a second map window opens and closes on the table
  - a journal document and a character card open, when the game has one
    (reported as skipped otherwise: give the test games a document and a
    token on their current map to cover them)

The runs change the test games a little (a chat roll, window and panel
layout), so use games kept for testing.

The test games are local to this machine, so their ids live in
tools/smoke_games.local.json (not checked in):
  {"5e": "<gameid>", "5.5e": "<gameid>", "none": "<gameid>"}

A launch kills any running DMHub.exe first (never Codex.exe). The engine repo's
build-output.json names the player.
"""

import argparse
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

D20 = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
ENGINE = os.path.normpath(os.path.join(D20, ".."))
SPEC_PATH = os.path.join(D20, "tools", "modset.json")
GAMES_PATH = os.path.join(D20, "tools", "smoke_games.local.json")

PORT = 19877

#system key -> (game system id, modset.json key of its root mod)
SYSTEMS = {
    "5e": ("dmhub-legacy", "sys5e"),
    "5.5e": ("dmhub-dnd2024", "sys55"),
    "none": ("dmhub-tabularasa", "sysnone"),
}

#Console errors that are not the code's fault. Each is still printed, marked
#"ignored". Keep this list short and say why each entry is here.
NOISE = [
    #the deprecated-module index download fails when offline or rate-limited.
    "ModuleDeprecated: could not download index",
]

#seconds to let a panel build (and its first refresh run) before reading errors.
PANEL_SETTLE = 1.5


def bridge_get(path, timeout=10):
    try:
        with urllib.request.urlopen(f"http://localhost:{PORT}{path}", timeout=timeout) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except (urllib.error.URLError, OSError):
        return None


def lua(code, timeout=60):
    body = json.dumps({"code": code}).encode("utf-8")
    req = urllib.request.Request(f"http://localhost:{PORT}/execute", data=body, method="POST",
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        r = json.loads(resp.read().decode("utf-8"))
    if not r.get("success"):
        raise RuntimeError(str(r.get("error")) + "\n" + "\n".join(r.get("output", [])))
    return r.get("result", "")


def lua_json(code):
    return json.loads(lua(code))


def errors_since(seq):
    """(new errors, newest sequence) from the console, oldest first."""
    q = "level=error&last=500"
    if seq >= 0:
        q += f"&since={seq}"
    r = bridge_get("/console?" + q) or {}
    return r.get("entries", []), r.get("sequence", seq)


def checkpoint():
    r = bridge_get("/console?level=error&last=1") or {}
    return r.get("sequence", -1)


def is_noise(entry):
    msg = entry.get("message", "")
    return any(n in msg for n in NOISE)


def player_exe():
    with open(os.path.join(ENGINE, "build-output.json"), encoding="utf-8") as f:
        out = json.load(f)
    if out.get("whiteLabel") != "DMHub":
        sys.exit(f"build-output.json is for white label {out.get('whiteLabel')}, not DMHub.")
    return os.path.join(ENGINE, out["windowsExe"])


def root_args(spec):
    by_key = {m["key"]: m for m in spec["mods"]}
    r = spec["roots"]
    return ["--base-mod", by_key[r["base"]]["guid"], "--official-mod", by_key[r["official"]]["guid"],
            "--admin-mod", by_key[r["admin"]]["guid"]]


def launch(spec, gameid):
    subprocess.run(["taskkill", "/f", "/im", "DMHub.exe"], capture_output=True)
    deadline = time.time() + 15
    while bridge_get("/health", timeout=2) is not None and time.time() < deadline:
        time.sleep(1)
    exe = player_exe()
    args = [exe, "--gameid", gameid, "--mcp-port", str(PORT)] + root_args(spec)
    subprocess.Popen(args, close_fds=True, cwd=os.path.dirname(exe))
    deadline = time.time() + 240
    while time.time() < deadline:
        h = bridge_get("/health", timeout=3)
        if h and h.get("status") == "ok" and h.get("inGame") and not h.get("loading", True) and h.get("gameId") == gameid:
            return
        time.sleep(2)
    raise RuntimeError(f"DMHub did not finish loading game {gameid} within 240 s")


class Result:
    def __init__(self, system):
        self.system = system
        self.failures = []
        self.notes = []

    def fail(self, what, detail=""):
        self.failures.append((what, detail))
        print(f"    FAIL {what}" + (f": {detail}" if detail else ""))

    def ok(self, what):
        print(f"    ok   {what}")

    def skip(self, what, why):
        self.notes.append(f"{what} skipped: {why}")
        print(f"    skip {what}: {why}")


def report_errors(res, what, entries):
    """Records a check's console errors; returns True if there were real ones."""
    real = [e for e in entries if not is_noise(e)]
    for e in entries:
        if is_noise(e):
            print(f"         ignored: {e.get('message', '')[:160]}")
    if real:
        first = real[0].get("message", "")
        res.fail(what, f"{len(real)} console error(s); first: {first[:600]}")
        for e in real[1:5]:
            print(f"         also: {e.get('message', '')[:300]}")
        return True
    res.ok(what)
    return False


def check_mods(spec, res, system_key):
    system_id, root_key = SYSTEMS[system_key]
    by_key = {m["key"]: m for m in spec["mods"]}
    got = lua("return tostring(dmhub.gameSystem)")
    if got != system_id:
        res.fail("game system", f"expected {system_id}, got {got}")
    else:
        res.ok(f"game system is {system_id}")
    raw = lua_json("return dmhub.ToJson(code.loadedMods)") or []
    #dmhub.ToJson writes a Lua array as an object keyed "1", "2", ...
    loaded = set(v for k, v in raw.items() if k != "_luaTable") if isinstance(raw, dict) else set(raw)
    root = by_key[root_key]["guid"]
    others = [by_key[k]["guid"] for _, k in SYSTEMS.values() if k != root_key]
    legacy = {lm["guid"]: lm["name"] for lm in spec["legacy"]["mods"]}
    if root not in loaded:
        res.fail("system root loaded", f"{by_key[root_key]['name']} ({root}) is not loaded")
    else:
        res.ok(f"{by_key[root_key]['name']} loaded")
    wrong = [g for g in others if g in loaded]
    if wrong:
        res.fail("other system roots", "also loaded: " + ", ".join(wrong))
    leaked = [legacy[g] for g in loaded if g in legacy]
    if leaked:
        res.fail("legacy mods", "loaded: " + ", ".join(sorted(leaked)))
    else:
        res.ok(f"no legacy mods among {len(loaded)} loaded")
    missing = [m["name"] for m in spec["mods"]
               if m.get("deps") != "all" and m["guid"] not in loaded]
    if missing:
        res.fail("set complete", "not loaded: " + ", ".join(missing))
    else:
        res.ok("every shared and d20 mod loaded")


PANEL_LIST = """
local out = {}
for _, item in ipairs(DockablePanel.GetMenuItems(true, true)) do
  local reg = DockablePanel.GetRegistration(item.name)
  if reg ~= nil and reg.launch == nil then out[#out+1] = item.name end
end
table.sort(out)
return dmhub.ToJson(out)
"""

PANEL_OP = """
local name, op = %s, %s
for _, item in ipairs(DockablePanel.GetMenuItems(true, true)) do
  if item.name == name then item.click(op); return "done" end
end
return "missing"
"""


def check_panels(res):
    names = lua_json(PANEL_LIST)
    if isinstance(names, dict):
        names = [names[k] for k in sorted((k for k in names if k != "_luaTable"), key=int)]
    print(f"    ..   {len(names)} dockable panels")
    for name in names:
        seq = checkpoint()
        try:
            if lua(PANEL_OP % (json.dumps(name), json.dumps("show"))) == "missing":
                res.fail(f"panel {name}", "no longer registered")
                continue
            time.sleep(PANEL_SETTLE)
            lua(PANEL_OP % (json.dumps(name), json.dumps("hide")))
            time.sleep(0.5)
        except Exception as exc:
            res.fail(f"panel {name}", str(exc)[:600])
            continue
        report_errors(res, f"panel {name}", errors_since(seq)[0])


def check_extras(res):
    #DM's Screen (Game Hud/DirectorScreen.lua).
    seq = checkpoint()
    try:
        r = lua("if DirectorScreen == nil or DirectorScreen.SetOpen == nil then return 'absent' end\n"
                "local was = DirectorScreen.IsOpen()\nDirectorScreen.SetOpen(true)\nreturn tostring(was)")
        if r == "absent":
            res.fail("DM's Screen", "DirectorScreen.SetOpen is not defined")
        else:
            time.sleep(PANEL_SETTLE)
            if r != "true":
                lua("DirectorScreen.SetOpen(false); return 'ok'")
            time.sleep(0.5)
            report_errors(res, "DM's Screen", errors_since(seq)[0])
    except Exception as exc:
        res.fail("DM's Screen", str(exc)[:600])

    #A chat roll (chat panel, dice, the Action Log).
    seq = checkpoint()
    try:
        lua("chat.Send('/roll 1d20+1'); return 'ok'")
        time.sleep(4)
        report_errors(res, "chat /roll", errors_since(seq)[0])
    except Exception as exc:
        res.fail("chat /roll", str(exc)[:600])

    #A second map window on the table (Game Hud/Tabletop.lua), then closed.
    seq = checkpoint()
    try:
        mapid = lua("""
if Tabletop == nil or not Tabletop.IsActive() then return "absent" end
for _, m in ipairs(game.maps) do
  if m.id ~= game.currentMapId and not Tabletop.HasMapWindow(m.id) then
    Tabletop.OpenMap(m.id, {newWindow = true})
    return m.id
  end
end
return "none"
""")
        if mapid == "absent":
            res.fail("map window", "the Tabletop is not active")
        elif mapid == "none":
            res.skip("map window", "the game has only one map")
        else:
            time.sleep(PANEL_SETTLE)
            lua("Tabletop.CloseMapWindow(%s); return 'ok'" % json.dumps(mapid))
            time.sleep(0.5)
            report_errors(res, "map window", errors_since(seq)[0])
    except Exception as exc:
        res.fail("map window", str(exc)[:600])

    #A journal document, if the game has one (DocumentSystem).
    seq = checkpoint()
    try:
        r = lua("""
for id, doc in unhidden_pairs(dmhub.GetTable(CustomDocument.tableName) or {}) do
  doc:ShowDocument()
  return tostring(doc.typeName)
end
return "none"
""")
        if r == "none":
            res.skip("document", "the game has no journal documents")
        else:
            time.sleep(PANEL_SETTLE)
            report_errors(res, f"document ({r})", errors_since(seq)[0])
    except Exception as exc:
        res.fail("document", str(exc)[:600])

    #A character card on the table, if the current map has a token.
    seq = checkpoint()
    try:
        r = lua("""
for _, tok in pairs(dmhub.GetTokens() or {}) do
  if tok.charid ~= nil then
    Tabletop.OpenCard(tok.charid)
    return tostring(tok.name)
  end
end
return "none"
""")
        if r == "none":
            res.skip("character card", "the current map has no tokens")
        else:
            time.sleep(PANEL_SETTLE)
            report_errors(res, f"character card ({r})", errors_since(seq)[0])
    except Exception as exc:
        res.fail("character card", str(exc)[:600])


def run_game(spec, system_key, gameid, no_launch):
    res = Result(system_key)
    print(f"\n== {system_key} ({SYSTEMS[system_key][0]}) game {gameid or '(current)'}")
    if not no_launch:
        try:
            launch(spec, gameid)
        except Exception as exc:
            res.fail("launch", str(exc))
            return res
        time.sleep(5)  #first-frame refreshes and late module loads
        report_errors(res, "load", errors_since(-1)[0])
    check_mods(spec, res, system_key)
    check_panels(res)
    check_extras(res)
    return res


def list_games():
    rows = lua_json("""
local out = {}
for k, g in pairs(lobby.games or {}) do
  out[#out+1] = {id = tostring(g.gameid or k), name = tostring(g.description), system = tostring(g.gameSystem), storage = tostring(g.storage)}
end
return dmhub.ToJson(out)""")
    if isinstance(rows, dict):
        rows = [rows[k] for k in rows if k != "_luaTable"]
    for r in sorted(rows, key=lambda r: (r["system"], r["name"])):
        print(f"  {r['system']:22s} {r['id']:40s} storage={r['storage']}  {r['name']}")


def main():
    global PORT
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--port", type=int, default=PORT)
    p.add_argument("--only", help="comma-separated systems: " + ",".join(SYSTEMS))
    p.add_argument("--no-launch", action="store_true", help="test the game DMHub is in now")
    p.add_argument("--list-games", action="store_true")
    args = p.parse_args()
    PORT = args.port

    if args.list_games:
        list_games()
        return

    with open(SPEC_PATH, encoding="utf-8") as f:
        spec = json.load(f)

    results = []
    if args.no_launch:
        system_id = lua("return tostring(dmhub.gameSystem)")
        key = next((k for k, (sid, _) in SYSTEMS.items() if sid == system_id), None)
        if key is None:
            sys.exit(f"The current game's system {system_id} is not one the smoke test knows.")
        results.append(run_game(spec, key, "", True))
    else:
        if not os.path.exists(GAMES_PATH):
            sys.exit(f"No {GAMES_PATH}. Write it as {{\"5e\": id, \"5.5e\": id, \"none\": id}}; "
                     "--list-games (with DMHub running) shows the candidates.")
        with open(GAMES_PATH, encoding="utf-8") as f:
            games = json.load(f)
        keys = args.only.split(",") if args.only else list(SYSTEMS)
        for key in keys:
            if key not in SYSTEMS:
                sys.exit(f"Unknown system {key}")
            if not games.get(key):
                print(f"\n== {key}: no game in {os.path.basename(GAMES_PATH)}, skipped")
                continue
            results.append(run_game(spec, key, games[key], False))

    print("\n== Summary")
    failed = False
    for r in results:
        print(f"  {r.system:6s} {'PASS' if not r.failures else 'FAIL (%d)' % len(r.failures)}")
        for what, detail in r.failures:
            print(f"         {what}: {detail[:200]}")
        for note in r.notes:
            print(f"         ({note})")
        failed = failed or bool(r.failures)
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
