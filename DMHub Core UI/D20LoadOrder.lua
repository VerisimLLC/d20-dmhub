local mod = dmhub.GetModLoading()

--D20LoadOrder: loads first in DMHub Core UI.
--
--The Codex loads DMHub Utils before DMHub Core UI; d20's mod graph happens to
--load it after DMHub Core Panels (neither Core UI nor Core Panels depends on
--Utils here). The synced Core UI and Core Panels files register chat macros
--while they load, with Commands.RegisterMacro from DMHub Utils/Utils.lua. So it
--is defined here first, with RegisterBuiltinDoc: both are copied verbatim from that file
--(tools/codex_sync.py checks the copy still matches), and Utils.lua redefines
--it identically when it loads, keeping every macro registered before then.
--
--The lasting fix is a mod dependency (DMHub Core UI depends on DMHub Utils, as
--in the Codex); see CODEX_SYNC.md.

if rawget(_G, "Commands") == nil then
    Commands = {}
end

Commands._macros = Commands._macros or {}

if Commands.RegisterMacro == nil then

-- BEGIN copy of Commands.RegisterMacro from DMHub Utils/Utils.lua
function Commands.RegisterMacro(args)
    local name = args.name
    local fn = args.command
    local doc = args.doc
    local summary = args.summary

    if doc ~= nil then
        Commands[name] = function(str)
            if str == "help" then
                dmhub.Log(doc)
                return
            end
            return fn(str)
        end
    else
        Commands[name] = fn
    end

    Commands._macros[name] = {
        doc = doc,
        summary = summary,
        completions = args.completions,

        -- Optional: surface this macro in the no-code command builder's
        -- browsable command list (CommandBuilder.lua). Shape:
        --   commandInfo = {
        --     name = "Screen Shake",       -- display name shown to the user
        --     description = "...",         -- one-line description for the list
        --     params = {                   -- optional; ordered arguments
        --       { name = "Duration", min = 0.1, max = 3, default = 0.3,
        --         round = 0.05, labelFormat = "%.2f" },
        --       ...
        --     },
        --     dmonly = true,               -- optional; hide from non-directors
        --     broadcast = "always",        -- optional; see below
        --   }
        --
        -- Params are baked into the recorded command as arguments in params
        -- order. Three kinds, by the param's `type`:
        --   (none)    a number on a slider. min/max/default/round/labelFormat.
        --   "choices" a dropdown. `options` ({{id=,text=}, ...}) if given,
        --             otherwise the macro's OWN `completions` function is
        --             reused -- the same list the chat input offers. Values
        --             must be single-token ids; nothing is quoted.
        --   "audio"   the app's sound picker (gui.AudioEditor). Bakes the
        --             audio asset id. Prefer this over a "choices" list of
        --             sounds: it names and previews them, and can upload a
        --             new sound in place.
        --   "text"    a free-text input. `placeholder` for the empty hint.
        --             Text params must come last: everything after the
        --             positional args belongs to them. A blank one is
        --             dropped. A `joiner` (e.g. "|") is emitted just before
        --             the value, which is how a macro that takes one
        --             free-form line with an internal separator is split
        --             into several labelled fields.
        -- `required = true` on any param keeps Add Step / Apply disabled
        -- until it has a value.
        --
        -- dmonly: set when the command's own body bails out on
        -- `not dmhub.isDM`. The browser omits the row entirely for players so
        -- they cannot record a step that would silently do nothing for them.
        --
        -- broadcast: set when the command only affects the client that runs
        -- it. A journal command button executes on the presser's machine
        -- alone (RichMacro.press -> dmhub.Execute), so a purely local effect
        -- -- a screen shake, a sound, a banner -- never reaches the table
        -- unless the step is wrapped in /broadcast. Values:
        --   "always" -- always recorded as "broadcast <command>"; no choice.
        --   "on"     -- offer a "Send to all players" check, checked.
        --   "off"    -- offer it unchecked.
        --   nil      -- no option; the command already networks its effect.
        commandInfo = args.commandInfo,
    }
end
-- END copy

end

if Commands.RegisterBuiltinDoc == nil then

-- BEGIN copy of Commands.RegisterBuiltinDoc from DMHub Utils/Utils.lua
function Commands.RegisterBuiltinDoc(args)
    Commands._macros[string.lower(args.name)] = {
        doc = args.doc,
        summary = args.summary,
        completions = args.completions,

        --optional no-code command builder surfacing; same shape as in
        --Commands.RegisterMacro above.
        commandInfo = args.commandInfo,
    }
end
-- END copy

end
