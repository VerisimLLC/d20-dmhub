"""DMHub's new CodeMod set: create, map, register and check in.

The set is described in tools/modset.json (see its _doc fields and
SHARED_UI_LAYER_PLAN.md in the engine repo). Its shared mods take their files
live from the Draw Steel Codex checkout; its d20 mods take theirs from this
repo, several of them from folders the legacy mods also use (an "only" list).

Every command talks to a running DMHub (DMHub white label, dev build) through
its MCP bridge (default port 19877, DMHub's; --port to change).

  python tools/modset.py legacy       read the legacy mods (guids, file orders,
                                      dependencies) from the running app into
                                      modset.json
  python tools/modset.py create       create cloud records for mods with no guid
  python tools/modset.py manifest     write codemods.json (restart DMHub after)
  python tools/modset.py register     register each mod's files, in order
  python tools/modset.py resources    copy the mod.images resources each mod's
                                      files use from the legacy mods, by name
  python tools/modset.py deps         set each mod's dependencies
  python tools/modset.py status       list the new mods: files, local changes
  python tools/modset.py checkin --notes "..." [--engine 0.0.881] [--only key,key]
                                      check in the new mods with local changes
  python tools/modset.py args         print the DMHub launch arguments that run
                                      the new set (--base-mod/--official-mod/--admin-mod)

Order of a first setup: legacy, create, manifest, (restart DMHub with the
'args' arguments and the codex git root configured), register, deps, checkin.
Re-running any command is safe: each skips what is already done.
"""

import argparse
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

D20 = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
SPEC_PATH = os.path.join(D20, "tools", "modset.json")
MANIFEST_PATH = os.path.join(D20, "codemods.json")

#The legacy DMHub root mods (CodeMod.BaseMod / OfficialMod before the new set).
LEGACY_ROOTS = ["cd79da1c-4faa-4811-81c6-8da029136089", "b2f58995-4b34-40ab-9dba-5ae0ec387c33"]

#McpBridge.DefaultPort for the DMHub white label (the Codex's is 19876).
PORT = 19877


def load_spec():
    with open(SPEC_PATH, "r", encoding="utf-8") as f:
        return json.load(f)


def save_spec(spec):
    with open(SPEC_PATH, "w", encoding="utf-8", newline="\n") as f:
        json.dump(spec, f, indent=2)
        f.write("\n")


def bridge(path, data=None, timeout=120):
    url = f"http://localhost:{PORT}{path}"
    body = data if data is not None else b""
    req = urllib.request.Request(url, data=body, method="POST",
                                 headers={"Content-Type": "application/json", "Content-Length": str(len(body))})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        try:
            return json.loads(exc.read().decode("utf-8"))
        except Exception:
            return {"success": False, "error": f"HTTP {exc.code}"}
    except urllib.error.URLError as exc:
        sys.exit(f"Cannot reach DMHub's MCP bridge on port {PORT}: {exc.reason}")


def lua(code):
    """Run Lua in the app; returns the 'result' string. Exits on a Lua error."""
    r = bridge("/execute", json.dumps({"code": code}).encode("utf-8"))
    if not r.get("success"):
        sys.exit("Lua error: " + str(r.get("error")) + "\n" + "\n".join(r.get("output", [])))
    return r.get("result", "")


def as_list(v):
    """dmhub.ToJson writes a Lua array as an object keyed "1", "2", ...
    (plus a "_luaTable" marker). Returns a Python list either way."""
    if isinstance(v, dict):
        keys = [k for k in v if k != "_luaTable"]
        return [v[k] for k in sorted(keys, key=lambda k: int(k))]
    return v if v is not None else []


def lua_json(code):
    return json.loads(lua(code))


def require_dmhub():
    wl = lua("return dmhub.whiteLabel")
    if wl != "dmhub":
        sys.exit(f"The app on port {PORT} is white label '{wl}', not DMHub. Stop.")


def mod_by_key(spec):
    return {m["key"]: m for m in spec["mods"]}


def dep_keys(spec, m):
    if m["deps"] == "all":
        return [o["key"] for o in spec["mods"] if o.get("deps") != "all"]
    return m["deps"]


def mod_root_path(spec, m):
    if m["root"] == "codex":
        return spec["engineRepoCodex"]
    return D20


def mod_folder_path(spec, m):
    return os.path.join(mod_root_path(spec, m), m["folder"])


def files_on_disk(folder):
    if not os.path.isdir(folder):
        return []
    return sorted(f[:-4] for f in os.listdir(folder) if f.endswith(".lua"))


def mod_files(spec, m):
    """The files this mod registers, in load order: the spec's order (or the
    legacy mod's), then any other file on disk that it does not exclude."""
    on_disk = files_on_disk(mod_folder_path(spec, m))
    lower = {f.lower(): f for f in on_disk}
    only = [f.lower() for f in m.get("only", [])]
    exclude = set(f.lower() for f in m.get("exclude", []))

    def wanted(name):
        n = name.lower()
        if n not in lower:
            return False
        if only and n not in only:
            return False
        return n not in exclude

    order = m.get("order")
    if order is None and m.get("orderFrom") == "legacy":
        for lm in spec["legacy"]["mods"]:
            if lm["folder"].lower() == m["folder"].lower():
                order = lm["files"]
    order = order or []
    result = []
    seen = set()
    for name in order:
        if wanted(name) and name.lower() not in seen:
            result.append(lower[name.lower()])
            seen.add(name.lower())
    for name in on_disk:
        if wanted(name) and name.lower() not in seen:
            result.append(name)
            seen.add(name.lower())
    return result


#------------------------------------------------------------------------------

def cmd_legacy(spec, args):
    require_dmhub()
    roots = json.dumps(LEGACY_ROOTS)
    code = """
local seen, order = {}, {}
local function visit(id)
  if seen[id] then return end
  seen[id] = true
  local m = code.GetMod(id)
  if m == nil then return end
  if type(m.dependencies) == "table" then
    for _, v in pairs(m.dependencies) do if type(v) == "string" then visit(v) end end
  end
  order[#order+1] = id
end
for _, id in ipairs(dmhub.FromJson(ROOTS).result) do visit(id) end
local out = {}
for _, id in ipairs(order) do
  local m = code.GetMod(id)
  local files, deps = {}, {}
  for _, f in ipairs(m.files or {}) do files[#files+1] = f.name end
  if type(m.dependencies) == "table" then for _, v in pairs(m.dependencies) do deps[#deps+1] = v end end
  out[#out+1] = {guid = id, name = m.name, files = files, deps = deps, git = m.gitFolderPath or ""}
end
return dmhub.ToJson(out)
""".replace("ROOTS", json.dumps(roots))
    mods = as_list(lua_json(code))
    legacy = []
    for m in mods:
        m["files"] = as_list(m["files"])
        m["deps"] = as_list(m["deps"])
        folder = m["name"]
        if not os.path.isdir(os.path.join(D20, folder)):
            print(f"  legacy {m['name']} ({m['guid']}): no d20 folder, not mapped")
            continue
        legacy.append({"guid": m["guid"], "name": m["name"], "folder": folder, "files": m["files"], "deps": m["deps"]})
    spec["legacy"]["mods"] = legacy
    save_spec(spec)
    print(f"{len(legacy)} legacy mods with d20 folders recorded.")


def cmd_create(spec, args):
    require_dmhub()
    created = 0
    for m in spec["mods"]:
        if m.get("guid"):
            continue
        guid = lua("return code.CreateModRecord{ name = %s, description = %s }" % (
            json.dumps(m["name"]), json.dumps("DMHub new mod set: " + m["key"])))
        if not guid:
            sys.exit(f"CreateModRecord returned nothing for {m['name']}")
        m["guid"] = guid
        save_spec(spec)
        created += 1
        print(f"  created {m['name']}: {guid}")
    print(f"{created} mods created.")


def cmd_manifest(spec, args):
    entries = []
    new_only_by_folder = {}
    for m in spec["mods"]:
        if not m.get("guid"):
            sys.exit(f"{m['name']} has no guid yet: run 'create' first.")
        e = {"guid": m["guid"], "root": m["root"], "folder": m["folder"]}
        if m.get("only"):
            e["only"] = m["only"]
            if m["root"] == "":
                new_only_by_folder.setdefault(m["folder"].lower(), set()).update(m["only"])
        if m.get("exclude"):
            e["exclude"] = m["exclude"]
        e["_name"] = m["name"]
        entries.append(e)

    for lm in spec["legacy"]["mods"]:
        registered = set(f.lower() for f in lm["files"])
        extra = sorted(f for f in new_only_by_folder.get(lm["folder"].lower(), set()) if f.lower() not in registered)
        e = {"guid": lm["guid"], "root": "", "folder": lm["folder"], "_name": lm["name"] + " (legacy)"}
        if extra:
            e["exclude"] = extra
        entries.append(e)

    manifest = {
        "_doc": "Generated by tools/modset.py manifest from tools/modset.json: maps each CodeMod, by guid, to its folder. Read by the engine (GitModManager) at startup. Root 'codex' = gitroots.codex in mods/settings.json.",
        "mods": entries,
    }
    with open(MANIFEST_PATH, "w", encoding="utf-8", newline="\n") as f:
        json.dump(manifest, f, indent=2)
        f.write("\n")
    print(f"Wrote {MANIFEST_PATH}: {len(entries)} mods. Restart DMHub to load it.")


def ensure_synced(guids):
    """Downloads mod records the app has not loaded (code.SyncMod), waiting up to 30 s."""
    import time
    missing = [g for g in guids if lua("local m = code.GetMod(%s); return tostring(m ~= nil and m.valid)" % json.dumps(g)) != "true"]
    for g in missing:
        lua("code.SyncMod(%s); return 'ok'" % json.dumps(g))
    deadline = time.time() + 30
    while missing and time.time() < deadline:
        time.sleep(1)
        missing = [g for g in missing if lua("local m = code.GetMod(%s); return tostring(m ~= nil and m.valid)" % json.dumps(g)) != "true"]
    if missing:
        print("  could not sync: " + ", ".join(missing))


def cmd_register(spec, args):
    require_dmhub()
    keys = args.only.split(",") if args.only else None
    ensure_synced([m["guid"] for m in spec["mods"] if keys is None or m["key"] in keys])
    for m in spec["mods"]:
        if keys and m["key"] not in keys:
            continue
        current = lua_json("""
local m = code.GetMod(%s)
if m == nil or not m.valid then return "null" end
local out = {}
for _, f in ipairs(m.files or {}) do out[#out+1] = f.name end
return dmhub.ToJson({files = out, git = m.gitFolderPath or ""})
""" % json.dumps(m["guid"]))
        if current is None:
            print(f"  {m['name']}: not loaded in the app, skipped")
            continue
        if not current["git"]:
            print(f"  {m['name']}: not git-mapped (is codemods.json loaded?), skipped")
            continue
        have = set(f.lower() for f in as_list(current["files"]))
        files = mod_files(spec, m)
        prev = None
        added = 0
        for name in files:
            if name.lower() not in have:
                #mod= names the target: several mods may share a folder.
                params = {"path": os.path.join(mod_folder_path(spec, m), name + ".lua"), "mod": m["guid"]}
                if prev is not None:
                    params["after"] = prev
                r = bridge("/codemod/register?" + urllib.parse.urlencode(params))
                if not r.get("success"):
                    sys.exit(f"  {m['name']}/{name}: {r.get('error')}")
                added += 1
            prev = name
        print(f"  {m['name']}: {len(files)} files, {added} newly registered")


def image_names_used(spec, m):
    """The mod.images.<name> resources the mod's files read."""
    import re
    names = set()
    folder = mod_folder_path(spec, m)
    for f in mod_files(spec, m):
        try:
            text = open(os.path.join(folder, f + ".lua"), encoding="utf-8", errors="replace").read()
        except OSError:
            continue
        names.update(re.findall(r"mod\.images\.([A-Za-z_][A-Za-z0-9_]*)", text))
    return names


def cmd_resources(spec, args):
    """Copies each new mod's image resources from the legacy mods, by name."""
    require_dmhub()
    legacy = spec["legacy"]["mods"]
    ensure_synced([lm["guid"] for lm in legacy] + [m["guid"] for m in spec["mods"]])
    by_guid = {}
    for lm in legacy:
        rows = as_list(lua_json("""
local m = code.GetMod(%s)
local out = {}
if m ~= nil and m.valid then
  for _, r in ipairs(m.resources) do out[#out+1] = {name = r.name, assetGuid = r.assetGuid or "", imageid = r.imageid or ""} end
end
return dmhub.ToJson(out)
""" % json.dumps(lm["guid"])))
        by_guid[lm["guid"]] = {r["name"]: r for r in rows}
    unresolved = {}
    for m in spec["mods"]:
        needed = image_names_used(spec, m)
        if not needed:
            continue
        have = set(as_list(lua_json("""
local m = code.GetMod(%s)
local out = {}
for _, r in ipairs(m.resources) do out[#out+1] = r.name end
return dmhub.ToJson(out)
""" % json.dumps(m["guid"]))))
        #prefer the legacy mod that uses the same d20 folder, then any legacy mod.
        sources = [lm for lm in legacy if lm["folder"].lower() == m["folder"].lower()] + legacy
        added = []
        for name in sorted(needed - have):
            res = next((by_guid[lm["guid"]][name] for lm in sources if name in by_guid[lm["guid"]]), None)
            if res is None:
                unresolved.setdefault(m["name"], []).append(name)
                continue
            def luastr(v):
                return json.dumps(v) if v else "nil"
            lua("code.GetMod(%s):AddResource{ name = %s, assetGuid = %s, imageid = %s }; return 'ok'" % (
                json.dumps(m["guid"]), json.dumps(name), luastr(res["assetGuid"]), luastr(res["imageid"])))
            added.append(name)
        if added:
            lua("code.GetMod(%s):Upload(); return 'ok'" % json.dumps(m["guid"]))
        print(f"  {m['name']}: uses {len(needed)} images, added {len(added)}")
    for name, missing in unresolved.items():
        print(f"  NOT FOUND in any legacy mod, for {name}: {', '.join(missing)}")


def cmd_deps(spec, args):
    require_dmhub()
    by_key = mod_by_key(spec)
    keys = args.only.split(",") if args.only else None
    #a session only has the records its own game's roots reach; the other
    #system roots must be downloaded before they can be changed.
    ensure_synced([m["guid"] for m in spec["mods"] if keys is None or m["key"] in keys])
    for m in spec["mods"]:
        if keys and m["key"] not in keys:
            continue
        deps = [by_key[k]["guid"] for k in dep_keys(spec, m) if k != m["key"]]
        lua("""
local m = code.GetMod(%s)
m.dependencies = dmhub.FromJson(%s).result
m:Upload()
return "ok"
""" % (json.dumps(m["guid"]), json.dumps(json.dumps(deps))))
        print(f"  {m['name']}: {len(deps)} dependencies")


def cmd_status(spec, args):
    require_dmhub()
    for m in spec["mods"]:
        r = lua_json("""
local m = code.GetMod(%s)
if m == nil or not m.valid then return "null" end
local changed = {}
for _, f in ipairs(m.files or {}) do if f.hasLocalChanges then changed[#changed+1] = f.name end end
return dmhub.ToJson({n = #(m.files or {}), changed = changed, git = m.gitFolderPath or "", unmanaged = m.unmanagedGitFiles or {}, missing = m.filesMissingFromGit or {}})
""" % json.dumps(m.get("guid", "")))
        if r is None:
            print(f"  {m['name']:28s} (not loaded)")
            continue
        print(f"  {m['name']:28s} files={r['n']:3d} changed={len(as_list(r['changed'])):3d} unmanaged={as_list(r['unmanaged'])} missing={as_list(r['missing'])} {r['git']}")


def cmd_checkin(spec, args):
    require_dmhub()
    keys = args.only.split(",") if args.only else None
    engine = args.engine or lua("return dmhub.version")
    ids = [m["guid"] for m in spec["mods"] if (keys is None or m["key"] in keys)]
    ensure_synced(ids)
    code = """
local ids = dmhub.FromJson(IDS).result
local pending = {}
for _, id in ipairs(ids) do
  local m = code.GetMod(id)
  if m ~= nil and m.hasLocalChanges then pending[#pending+1] = id end
end
local i = 0
local function nextCommit()
  i = i + 1
  local id = pending[i]
  if id == nil then print("MODSET COMMIT ALL DONE"); return end
  local m = code.GetMod(id)
  if not m.checkedout then m.checkedout = true end
  m:CommitChanges(NOTES, ENGINE, function(err)
    print("MODSET COMMIT " .. m.name .. ": " .. (err or "OK"))
    if err == nil then nextCommit() else print("MODSET COMMIT STOPPED") end
  end)
end
nextCommit()
return tostring(#pending)
""".replace("IDS", json.dumps(json.dumps(ids))).replace("NOTES", json.dumps(args.notes)).replace("ENGINE", json.dumps(engine))
    n = lua(code)
    print(f"Started checking in {n} mods at engine {engine}; watch the console for 'MODSET COMMIT'.")


def cmd_args(spec, args):
    by_key = mod_by_key(spec)
    r = spec["roots"]
    print(f"--base-mod {by_key[r['base']]['guid']} --official-mod {by_key[r['official']]['guid']} --admin-mod {by_key[r['admin']]['guid']}")


def main():
    global PORT
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("command", choices=["legacy", "create", "manifest", "register", "resources", "deps", "status", "checkin", "args"])
    p.add_argument("--port", type=int, default=PORT)
    p.add_argument("--only", help="comma-separated mod keys")
    p.add_argument("--notes", default="")
    p.add_argument("--engine", default="")
    args = p.parse_args()
    PORT = args.port
    spec = load_spec()
    {"legacy": cmd_legacy, "create": cmd_create, "manifest": cmd_manifest, "register": cmd_register,
     "resources": cmd_resources, "deps": cmd_deps, "status": cmd_status, "checkin": cmd_checkin, "args": cmd_args}[args.command](spec, args)


if __name__ == "__main__":
    main()
