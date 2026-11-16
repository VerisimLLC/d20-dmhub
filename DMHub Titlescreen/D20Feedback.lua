local mod = dmhub.GetModLoading()

--D20Feedback: the title bar's Feedback menu -- Bug Report, Feature Request,
--General Feedback and Your Tickets. d20's own file, ported from the Codex's
--CodexTitleBar.lua (CreateBugReportDialog / CreateTicketsDialog); Styles.lua
--adds the menu to the title bar from D20Feedback.MenuItems().
--
--The engine does the work (BugReportManager.cs, exposed as
--dmhub.BeginBugReport and the dmhub.*Ticket* calls). It writes to the white
--label's own backend: for DMHub that is /BugReports and /Tickets in the
--dmtool-cad62 Firebase, and the DMHub R2 blob server for logs, screenshots
--and attachments. The database rules for those paths are in the engine
--repo's cloud-functions/database.rules.dmhub.json.
--
--Registered last in the d20 Titlescreen mod, which depends on Core UI
--(gui.Check, gui.NewContentAlert, ThemeEngine), so all of that exists here.
--Styles.lua reaches D20Feedback only through rawget when the menu opens or
--the bar ticks, so file order does not matter. Only the new mod set
--registers this file; under the legacy set D20Feedback is nil and Styles.lua
--keeps the Feedback menu collapsed.

D20Feedback = {}

local g_discordLink = "https://discord.gg/DNW8T3BZkD"

--------------------------------------------------------------------------------
--Ticket state (Feedback > Your Tickets).
--
--Submitting a bug report also opens a ticket at /Tickets/{userid}/{reportId}:
--the conversation where developers respond. This caches the local user's
--tickets so the title bar can show a marker when a developer has responded
--to a ticket the user has not viewed yet (lastDevMessageAt > userSeenAt).
--
--The ticket bridge (dmhub.GetMyTickets and friends) may be missing on older
--engines, so access goes through pcall and the feature quietly disappears.
--------------------------------------------------------------------------------

local g_ticketsState = {
    tickets = nil,     --map of reportId -> ticket record; nil before any fetch.
    hasUnseen = false, --true when any ticket has an unviewed developer response.
}

--marker panels (registered by the title bar) that receive a "refreshAlert"
--event whenever the ticket state changes.
local g_menuAlertPanels = {}

--Tickets viewed this session: reportId -> seen-through timestamp.
--MarkTicketSeen's server write is fire-and-forget, so a fetch that lands
--before it would bring back the marker for a ticket the user just read; this
--floor makes locally-viewed always win over stale server data.
local g_localTicketSeenFloor = {}

local function TicketBridgeAvailable()
    local ok, fn = pcall(function() return dmhub.GetMyTickets end)
    return ok and fn ~= nil
end

local function TicketStatusBridgeAvailable()
    local ok, fn = pcall(function() return dmhub.SetTicketStatus end)
    return ok and fn ~= nil
end

local function BugReportBridgeAvailable()
    local ok, fn = pcall(function() return dmhub.BeginBugReport end)
    return ok and fn ~= nil
end

local function TicketHasUnseenResponse(t)
    if type(t) ~= "table" then
        return false
    end
    local lastDev = t.lastDevMessageAt
    if lastDev == nil then
        return false
    end
    local seen = t.userSeenAt
    if t.reportId ~= nil then
        local floor = g_localTicketSeenFloor[t.reportId]
        if floor ~= nil and (seen == nil or floor > seen) then
            seen = floor
        end
    end
    return seen == nil or lastDev > seen
end

local function RefreshTicketAlerts()
    local unseen = 0
    if g_ticketsState.tickets ~= nil then
        for _,t in pairs(g_ticketsState.tickets) do
            if TicketHasUnseenResponse(t) then
                unseen = unseen + 1
            end
        end
    end
    g_ticketsState.hasUnseen = (unseen > 0)

    --notify the markers, pruning any belonging to a destroyed title bar.
    local live = {}
    for _,panel in ipairs(g_menuAlertPanels) do
        if panel.valid then
            live[#live+1] = panel
            panel:FireEvent("refreshAlert")
        end
    end
    g_menuAlertPanels = live
end

--Fetches the user's tickets, refreshes the marker state, then calls
--callback(tickets, error) if given. Without the ticket bridge this reports
--no tickets and no error.
local function FetchTickets(callback)
    if not TicketBridgeAvailable() then
        if callback ~= nil then
            callback(nil, nil)
        end
        return
    end
    dmhub.GetMyTickets(function(tickets, error)
        if mod.unloaded then
            return
        end
        if error == nil then
            g_ticketsState.tickets = tickets or {}
            RefreshTicketAlerts()
        end
        if callback ~= nil then
            callback(tickets, error)
        end
    end)
end

--The engine fires "ticketAlert" when the account monitor (which streams
--/users/{userid}) sees the dashboard bump the ticketAlert field, i.e. a
--developer just responded to one of our tickets. Refetch so the marker
--appears at once, with no polling.
dmhub.RegisterEventHandler("ticketAlert", function()
    if mod.unloaded then
        return
    end
    FetchTickets()
end)

--------------------------------------------------------------------------------
--Hosting. In a real game the gamehud modal stack owns a dialog; on the title
--screen it floats on the titlescreen's root sheet. The gamehud is the
--fallback when the title screen can't host it.
--------------------------------------------------------------------------------

local function TitlescreenHostSheet()
    local ts = rawget(_G, "titlescreen")
    if ts == nil then
        return nil
    end
    local ok, sheet = pcall(function() return ts.dialog.sheet end)
    if ok and sheet ~= nil and sheet.valid then
        return sheet
    end
    return nil
end

local function InRealGame()
    return dmhub.inGame and not dmhub.isLobbyGame
end

--1px hairline in the theme's border color.
local function Hairline(args)
    local panel = {
        bgimage = "panels/square.png",
        bgcolor = "@border",
        width = "100%",
        height = 1,
    }
    for k,v in pairs(args or {}) do
        panel[k] = v
    end
    return gui.Panel(panel)
end

--------------------------------------------------------------------------------
--The feedback dialog for a report begun with dmhub.BeginBugReport. The report
--already holds a screenshot captured before the dialog appeared.
--feedbackType is "bug", "feature" or "feedback"; the log file is only offered
--on bug reports.
--------------------------------------------------------------------------------

local function CreateBugReportDialog(report, feedbackType)
    local kinds = {
        bug = {
            title = "Report a Bug",
            intro = "Describe the bug below and submit it directly to the DMHub developers. Please make a separate report for each bug.",
            --input placeholders do not wrap, so the line break is explicit.
            placeholder = "Describe the bug: what happened, and what you expected to happen instead.\nIf you can, include exact steps to reproduce it.",
            thanks = "Your bug report has been submitted. Thank you!",
            --shown alongside thanks when the ticket bridge exists: a bug
            --report also opens a ticket the user can follow up on.
            ticketInfo = "A ticket has been opened for your report. You can find it under Feedback -> Your Tickets. Our developers will review it soon. We may respond to your ticket if we need more information or when we close it, but not every report gets a reply. If your issue is urgent or you would like a response, asking about it on the DMHub Discord is the best way to reach a person. You can safely post your ticket ID there.",
        },
        feature = {
            title = "Request a Feature",
            intro = "Describe the feature you would like below and it will be submitted directly to the DMHub developers.",
            placeholder = "Describe the feature you would like, and the problem it would solve for you.",
            thanks = "Your feature request has been submitted. Thank you!",
        },
        feedback = {
            title = "Send Feedback",
            intro = "Share your feedback below and it will be submitted directly to the DMHub developers.",
            placeholder = "Tell us what you think: what is working well, and what could be better?",
            thanks = "Your feedback has been submitted. Thank you!",
        },
    }

    local kindInfo = kinds[feedbackType]
    if kindInfo == nil then
        feedbackType = "bug"
        kindInfo = kinds.bug
    end

    local isBugReport = (feedbackType == "bug")

    local m_dialog = nil
    local m_titlescreenModal = nil
    local m_attachments = {}
    local m_submitting = false
    local m_submitted = false

    local m_includeLog = isBugReport
    local m_includeScreenshot = true
    local m_allowGameEntry = true
    local m_mood = nil

    local function CloseDialog()
        if m_titlescreenModal ~= nil then
            if m_titlescreenModal.valid then
                m_titlescreenModal:DestroySelf()
            end
        elseif m_dialog ~= nil and m_dialog.valid then
            m_dialog:FireEvent("close")
        end
    end

    --Two-pane layout: the description on the left, a side panel down the
    --right edge with the screenshot, the opt-in checks and attachments, and a
    --footer across the bottom.
    local DIALOG_WIDTH = 1024
    --content inset so the side panel's fill does not cover the frame's border.
    local FRAME_INSET = 2
    local SIDE_WIDTH = 340
    local SIDE_PAD = 20
    local LEFT_WIDTH = DIALOG_WIDTH - FRAME_INSET * 2 - SIDE_WIDTH - 1
    local MAIN_HEIGHT = 560
    local FOOTER_HEIGHT = 72

    --bordered: the theme's inputs are frameless and would vanish on the
    --dialog's dark surface without it.
    local descriptionInput = gui.Input{
        classes = {"bordered"},
        width = "100%",
        height = 330,
        fontSize = 16,
        multiline = true,
        textWrap = true,
        characterLimit = 10000,
        textAlignment = "topleft",
        halign = "left",
        tmargin = 14,
        placeholderText = kindInfo.placeholder,
    }

    local screenshotSection = nil
    if report.screenshotImage ~= nil then
        local aspect = 9 / 16
        if report.screenshotWidth > 0 then
            aspect = report.screenshotHeight / report.screenshotWidth
        end

        local imageWidth = SIDE_WIDTH - SIDE_PAD * 2
        screenshotSection = gui.Panel{
            width = "100%",
            height = "auto",
            flow = "vertical",
            halign = "left",

            gui.Panel{
                classes = {"bordered"},
                bgimage = report.screenshotImage,
                bgcolor = "white",
                width = imageWidth,
                height = math.floor(imageWidth * aspect),
                halign = "left",
            },

            gui.Check{
                text = "Include this screenshot of your screen",
                placement = "right",
                colon = false,
                value = m_includeScreenshot,
                halign = "left",
                tmargin = 8,
                change = function(element)
                    m_includeScreenshot = element.value
                end,
            },
        }
    end

    --the log file is only relevant to bug reports.
    local logCheck = nil
    if isBugReport then
        logCheck = gui.Check{
            text = "Include my log file (recommended)",
            placement = "right",
            colon = false,
            tooltip = "Your log file helps developers diagnose the problem. If a log from your previous session exists (for example after a crash and restart), it is included too. Logs contain a small amount of personal data, such as your system username, and are compressed before uploading.",
            value = m_includeLog,
            halign = "left",
            change = function(element)
                m_includeLog = element.value
            end,
        }
    end

    local gameEntryCheck = gui.Check{
        text = "Allow DMHub developers to enter my game if needed",
        placement = "right",
        colon = false,
        value = m_allowGameEntry,
        halign = "left",
        tmargin = cond(isBugReport, 8, 0),
        change = function(element)
            m_allowGameEntry = element.value
        end,
    }

    local m_attachmentsList = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        halign = "left",
    }

    local function RefreshAttachments()
        local children = {}
        for i,path in ipairs(m_attachments) do
            local index = i
            local fileName = path
            for j = #path, 1, -1 do
                local c = path:sub(j, j)
                if c == "/" or c == "\\" then
                    fileName = path:sub(j + 1)
                    break
                end
            end

            children[#children + 1] = gui.Panel{
                width = "auto",
                height = "auto",
                flow = "horizontal",
                halign = "left",
                vmargin = 2,

                gui.Label{
                    fontSize = 15,
                    width = SIDE_WIDTH - SIDE_PAD * 2 - 72,
                    height = "auto",
                    textWrap = true,
                    valign = "center",
                    text = fileName,
                },

                gui.Button{
                    classes = {"sizeXs"},
                    text = "Remove",
                    valign = "center",
                    lmargin = 12,
                    width = 60,
                    click = function(element)
                        if m_submitting or m_submitted then
                            return
                        end
                        table.remove(m_attachments, index)
                        RefreshAttachments()
                    end,
                },
            }
        end

        m_attachmentsList.children = children
    end

    local attachButton = gui.Button{
        classes = {"sizeM"},
        text = "Attach File...",
        halign = "left",
        width = "100%",
        height = 64,
        click = function(element)
            if m_submitting or m_submitted then
                return
            end
            dmhub.OpenFileDialog{
                id = "bugreportattachment",
                prompt = "Choose files to attach to your bug report",
                extensions = {},
                multiFiles = true,
                openFiles = function(paths)
                    for _,path in ipairs(paths) do
                        local alreadyAdded = false
                        for _,existing in ipairs(m_attachments) do
                            if existing == path then
                                alreadyAdded = true
                            end
                        end
                        if not alreadyAdded then
                            m_attachments[#m_attachments + 1] = path
                        end
                    end
                    RefreshAttachments()
                end,
            }
        end,
    }

    local statusLabel = gui.Label{
        fontSize = 16,
        width = "100%",
        height = "auto",
        halign = "left",
        textWrap = true,
        tmargin = 8,
        text = "",
    }

    --The form. Hidden once the report is sent.
    local formPanel = gui.Panel{
        width = "100%",
        height = MAIN_HEIGHT,
        flow = "horizontal",
        halign = "left",
    }

    --Shown in place of the form once the report is sent, so the user can't
    --miss that it worked. Filled in by ShowConfirmation.
    local confirmationPanel = gui.Panel{
        classes = {"collapsed"},
        width = "100%",
        height = MAIN_HEIGHT,
        flow = "vertical",
        halign = "center",
    }

    local SUCCESS_COLOR = "#5cb85c"

    local function ShowConfirmation(reportid)
        local children = {
            gui.Panel{
                width = 96,
                height = 96,
                halign = "center",
                tmargin = 24,
                bgimage = "ui-icons/module-checkmark.png",
                bgcolor = SUCCESS_COLOR,
                interactable = false,
            },

            gui.Label{
                fontSize = 32,
                bold = true,
                width = "auto",
                height = "auto",
                halign = "center",
                tmargin = 16,
                color = SUCCESS_COLOR,
                text = "Sent!",
            },

            gui.Label{
                fontSize = 18,
                width = 760,
                height = "auto",
                halign = "center",
                textAlignment = "center",
                textWrap = true,
                tmargin = 16,
                text = kindInfo.thanks,
            },
        }

        if kindInfo.ticketInfo ~= nil and TicketBridgeAvailable() then
            children[#children + 1] = gui.Label{
                fontSize = 16,
                width = 760,
                height = "auto",
                halign = "center",
                textAlignment = "center",
                textWrap = true,
                tmargin = 12,
                text = kindInfo.ticketInfo,
            }
        end

        if reportid ~= nil and reportid ~= "" then
            --click to copy, so the user can quote the id back to us.
            children[#children + 1] = gui.Label{
                fontSize = 20,
                width = "auto",
                height = "auto",
                halign = "center",
                tmargin = 20,
                text = string.format("Your ticket ID is <b>%s</b> (click to copy)", reportid),
                click = function(element)
                    gui.Tooltip{ text = "Copied to Clipboard", valign = "top", borderWidth = 0 }(element)
                    dmhub.CopyToClipboard(reportid)
                end,
            }
        end

        confirmationPanel.children = children
        formPanel:SetClass("collapsed", true)
        confirmationPanel:SetClass("collapsed", false)
    end

    local submitButton

    submitButton = gui.Button{
        classes = {"sizeL", "primary"},
        text = "Submit Report",
        halign = "right",
        valign = "center",
        click = function(element)
            --after a successful send this is the Close button.
            if m_submitted then
                CloseDialog()
                return
            end
            if m_submitting then
                return
            end

            local description = descriptionInput.text
            if description == nil or description == "" then
                statusLabel.text = "Please enter a description before submitting."
                return
            end

            m_submitting = true
            statusLabel.text = "Submitting..."

            report:Submit{
                description = description,
                type = feedbackType,
                includeLog = m_includeLog,
                includeScreenshot = m_includeScreenshot,
                allowGameEntry = m_allowGameEntry,
                mood = m_mood,
                attachments = m_attachments,
                progress = function(ratio)
                    if statusLabel.valid and not m_submitted then
                        --uploads stop at 95%. The rest is saving the report,
                        --which sends no progress, so say so instead of
                        --sitting on a number that looks stuck.
                        if ratio >= 0.95 then
                            statusLabel.text = "Upload complete. Saving your report..."
                        else
                            statusLabel.text = string.format("Submitting... %d%%", math.floor(ratio * 100 + 0.5))
                        end
                    end
                end,
                complete = function(reportid)
                    m_submitting = false
                    m_submitted = true
                    if statusLabel.valid then
                        statusLabel.text = ""
                        ShowConfirmation(reportid)
                        submitButton.text = "Close"
                    end

                    --pick up the new ticket so Your Tickets and the menu
                    --marker reflect it at once.
                    FetchTickets()
                end,
                error = function(message)
                    m_submitting = false
                    if statusLabel.valid then
                        statusLabel.text = "Could not submit: " .. message
                    end
                end,
            }
        end,
    }

    --X close button in the dialog's top-right corner. It doubles as cancel:
    --cancels the in-flight report (unless it already submitted) and closes.
    local closeButton = gui.Button{
        classes = {"closeButton"},
        floating = true,
        halign = "right",
        valign = "top",
        escapeActivates = true,
        escapePriority = EscapePriority.EXIT_MODAL_DIALOG,
        click = function(element)
            if not m_submitted then
                report:Cancel()
            end
            CloseDialog()
        end,
    }

    --Optional mood picker: five outline faces (angry -> delighted); the id is
    --stored on the report as `mood`.
    local m_moodButtons = {}
    local function RefreshMoodSelection()
        for _,entry in ipairs(m_moodButtons) do
            entry.panel:SetClass("selected", entry.id == m_mood)
        end
    end

    local moodOrder = {
        { id = "angry", label = "Angry", icon = "phosphor/smiley-angry.png" },
        { id = "frustrated", label = "Frustrated", icon = "phosphor/smiley-meh.png" },
        { id = "sad", label = "Sad", icon = "phosphor/smiley-sad.png" },
        { id = "happy", label = "Happy", icon = "phosphor/smiley.png" },
        { id = "delighted", label = "Delighted", icon = "phosphor/smiley-wink.png" },
    }

    local moodButtonPanels = {}
    for _,opt in ipairs(moodOrder) do
        local optid = opt.id
        local btn = gui.Panel{
            classes = {"moodButton"},
            bgimage = opt.icon,
            --a raw gui.Panel does not wrap a string tooltip the way
            --gui.Check/Button do, so attach the hover handler directly.
            hover = gui.Tooltip(opt.label),
            press = function(element)
                m_mood = cond(m_mood == optid, nil, optid)
                RefreshMoodSelection()
            end,
        }
        m_moodButtons[#m_moodButtons + 1] = { panel = btn, id = optid }
        moodButtonPanels[#moodButtonPanels + 1] = btn
    end

    local moodPickerSection = gui.Panel{
        width = "auto",
        height = "auto",
        flow = "horizontal",
        halign = "left",
        tmargin = 12,

        --MergeStyles resolves the @fg / @accent tokens in these rules.
        styles = ThemeEngine.MergeStyles{
            { selectors = {"moodButton"}, width = 34, height = 34, hmargin = 5, valign = "center", bgcolor = "@fg", opacity = 0.7 },
            { selectors = {"moodButton", "hover"}, opacity = 1 },
            { selectors = {"moodButton", "selected"}, bgcolor = "@accent", opacity = 1, scale = 1.15 },
        },

        gui.Label{
            fontSize = 15,
            width = "auto",
            height = "auto",
            halign = "left",
            valign = "center",
            rmargin = 6,
            text = "How are you feeling? (optional)",
        },

        gui.Panel{
            width = "auto",
            height = "auto",
            flow = "horizontal",
            halign = "left",
            valign = "center",
            children = moodButtonPanels,
        },
    }

    local leftColumn = gui.Panel{
        width = LEFT_WIDTH,
        height = "100%",
        flow = "vertical",
        halign = "left",
        borderBox = true,
        hpad = 28,
        tpad = 22,
        bpad = 16,

        gui.Label{
            classes = {"dialogTitle"},
            width = "100%",
            halign = "left",
            textAlignment = "left",
            text = kindInfo.title,
        },

        gui.Label{
            width = "100%",
            height = "auto",
            fontSize = 15,
            textWrap = true,
            halign = "left",
            tmargin = 6,
            text = kindInfo.intro,
        },

        descriptionInput,

        moodPickerSection,

        statusLabel,
    }

    local function SideSeparator()
        return Hairline{ vmargin = 14 }
    end

    --assembled explicitly: screenshotSection and logCheck may be nil, and a
    --nil hole in a positional children list would truncate it.
    local sideChildren = {}
    if screenshotSection ~= nil then
        sideChildren[#sideChildren + 1] = screenshotSection
        sideChildren[#sideChildren + 1] = SideSeparator()
    end
    if logCheck ~= nil then
        sideChildren[#sideChildren + 1] = logCheck
    end
    sideChildren[#sideChildren + 1] = gameEntryCheck
    sideChildren[#sideChildren + 1] = SideSeparator()
    sideChildren[#sideChildren + 1] = attachButton
    sideChildren[#sideChildren + 1] = m_attachmentsList

    --vscroll is a safety net for a long attachment list. The top pad leaves
    --room for the close button, which sits over this panel.
    local sidePanel = gui.Panel{
        width = SIDE_WIDTH,
        height = "100%",
        halign = "right",
        flow = "vertical",
        vscroll = true,
        borderBox = true,
        hpad = SIDE_PAD,
        tpad = 56,
        bpad = SIDE_PAD,
        bgimage = true,
        bgcolor = "@bgAlt",

        --tick boxes read as settings rows: the label wraps on the left and
        --the box sits at the right edge.
        styles = {
            { selectors = {"checkbox"}, width = "100%", height = "auto", minWidth = 0, vpad = 6, hpad = 0, priority = 5 },
            { selectors = {"checkBackground"}, width = 22, height = 22, valign = "center", rmargin = 0, priority = 5 },
            { selectors = {"checkboxLabel"}, width = "100%-34", rmargin = 12, halign = "left", textWrap = true, fontSize = 16, priority = 5 },
        },

        children = sideChildren,
    }

    formPanel.children = {
        leftColumn,
        Hairline{ width = 1, height = "100%" },
        sidePanel,
    }

    --Footer: the DMHub Discord on the left, Submit Report on the right.
    local footer = gui.Panel{
        width = "100%",
        height = FOOTER_HEIGHT,
        flow = "horizontal",
        borderBox = true,
        hpad = 28,

        gui.Panel{
            width = "auto",
            height = "auto",
            flow = "horizontal",
            halign = "left",
            valign = "center",

            gui.Label{
                fontSize = 14,
                width = "auto",
                height = "auto",
                valign = "center",
                text = "You can also talk to us about bugs on the DMHub Discord:",
            },

            gui.Button{
                classes = {"sizeS"},
                text = "Open Discord",
                valign = "center",
                lmargin = 8,
                width = 180,
                click = function(element)
                    dmhub.OpenURL(g_discordLink)
                end,
            },
        },

        submitButton,
    }

    --The dialog frame, built here rather than with gamehud:ModalDialog so the
    --side panel can run to the frame's edges and there is no empty button
    --strip. The confirmation panel swaps in for the form at the same height,
    --so the frame never changes size.
    local function CreateFrame(extra)
        local args = {
            classes = {"framedPanel"},
            width = DIALOG_WIDTH,
            height = MAIN_HEIGHT + 1 + FOOTER_HEIGHT + FRAME_INSET * 2,
            borderBox = true,
            pad = FRAME_INSET,
            flow = "vertical",
            styles = ThemeEngine.GetStyles(),

            formPanel,
            confirmationPanel,
            Hairline(),
            footer,
        }
        for k,v in pairs(extra) do
            args[k] = v
        end
        local frame = gui.Panel(args)
        frame:AddChild(closeButton)
        return frame
    end

    local host = nil
    if not InRealGame() then
        host = TitlescreenHostSheet()
    end

    if host ~= nil then
        m_titlescreenModal = CreateFrame{
            floating = true,
            halign = "center",
            valign = "center",
        }
        host:AddChild(m_titlescreenModal)
    else
        local gh = rawget(_G, "gamehud")
        if gh == nil then
            report:Cancel()
            return
        end
        m_dialog = CreateFrame{
            close = function(element)
                gh:CloseModal()
            end,
        }
        gh:ShowModal(m_dialog)
    end
end

--------------------------------------------------------------------------------
--Tickets dialog (Feedback > Your Tickets): lists the user's bug tickets, open
--and closed, and shows the conversation on each so the user can read
--developer responses and add messages of their own. Opening a ticket marks
--it seen, clearing the "developer responded" marker on the Feedback menu.
--------------------------------------------------------------------------------

local function CreateTicketsDialog()
    local m_dialog = nil
    local m_titlescreenModal = nil

    local m_tickets = {}      --sorted array of ticket records.
    local m_page = "loading"  --"loading", "error", "list" or "detail".
    local m_errorMessage = nil
    local m_selected = nil    --reportId of the ticket shown in detail view.
    local m_sending = false
    local m_localMessageCounter = 0

    local function CloseDialog()
        if m_titlescreenModal ~= nil then
            if m_titlescreenModal.valid then
                m_titlescreenModal:DestroySelf()
            end
        elseif m_dialog ~= nil and m_dialog.valid then
            m_dialog:FireEvent("close")
        end
    end

    --forward declared; assigned below and captured by the page builders.
    local contentPanel
    local RefreshPage
    local OpenDetail

    local function SortedTickets()
        local result = {}
        for _,t in pairs(g_ticketsState.tickets or {}) do
            if type(t) == "table" then
                result[#result+1] = t
            end
        end
        table.sort(result, function(a, b)
            return (a.updatedAt or a.createdAt or 0) > (b.updatedAt or b.createdAt or 0)
        end)
        return result
    end

    local function TicketById(reportId)
        for _,t in ipairs(m_tickets) do
            if t.reportId == reportId then
                return t
            end
        end
        return nil
    end

    local function FormatDay(ms)
        if type(ms) ~= "number" then
            return ""
        end
        return os.date("%b %d, %Y", math.floor(ms / 1000)) --[[@as string]]
    end

    local function FormatTime(ms)
        if type(ms) ~= "number" then
            return ""
        end
        return os.date("%b %d, %Y %H:%M", math.floor(ms / 1000)) --[[@as string]]
    end

    --messages arrive as a map keyed by chronologically sortable strings;
    --sort by timestamp with the key as a tiebreak.
    local function SortedMessages(ticket)
        local result = {}
        for key,msg in pairs(ticket.messages or {}) do
            if type(msg) == "table" then
                result[#result+1] = { key = key, msg = msg }
            end
        end
        table.sort(result, function(a, b)
            local ta = a.msg.timestamp or 0
            local tb = b.msg.timestamp or 0
            if ta == tb then
                return a.key < b.key
            end
            return ta < tb
        end)
        return result
    end

    local function BuildMessagePage(text)
        return gui.Panel{
            width = "100%",
            height = "100%",
            flow = "vertical",

            gui.Label{
                fontSize = 18,
                width = 700,
                height = "auto",
                halign = "center",
                valign = "center",
                textAlignment = "center",
                textWrap = true,
                text = text,
            },
        }
    end

    local function StatusChip(ticket)
        local closed = (ticket.status == "closed")
        return gui.Label{
            fontSize = 13,
            bold = true,
            width = 70,
            height = "auto",
            valign = "center",
            textAlignment = "center",
            color = cond(closed, "#999999", "#86c06c"),
            text = cond(closed, "CLOSED", "OPEN"),
        }
    end

    local function BuildListPage()
        if #m_tickets == 0 then
            return BuildMessagePage("You have not filed any bug reports yet.\n\nWhen you report a bug from the Feedback menu, a ticket is opened here where the developers can follow up with you.")
        end

        local rows = {}
        for _,t in ipairs(m_tickets) do
            local ticket = t
            local unseen = TicketHasUnseenResponse(ticket)

            local markerPanel = nil
            if unseen then
                markerPanel = gui.NewContentAlert{
                    floating = false,
                    x = 0,
                    halign = "center",
                    valign = "center",
                }
            end

            rows[#rows+1] = gui.Panel{
                classes = {"ticketRow"},
                bgimage = "panels/square.png",
                width = "100%",
                height = "auto",
                valign = "top",
                flow = "horizontal",
                borderBox = true,
                pad = 6,
                vmargin = 2,

                press = function(element)
                    OpenDetail(ticket.reportId)
                end,

                --fixed-width marker slot so titles align whether or not the
                --unseen-response dot is present.
                gui.Panel{
                    width = 16,
                    height = 20,
                    halign = "left",
                    valign = "center",
                    interactable = false,
                    markerPanel,
                },

                StatusChip(ticket),

                gui.Label{
                    fontSize = 16,
                    width = 500,
                    height = "auto",
                    halign = "left",
                    valign = "center",
                    lmargin = 8,
                    textWrap = true,
                    interactable = false,
                    text = ticket.title or "(no title)",
                },

                gui.Label{
                    fontSize = 14,
                    color = "#aaaaaa",
                    width = 110,
                    height = "auto",
                    halign = "right",
                    valign = "center",
                    interactable = false,
                    text = ticket.reportId or "",
                },

                gui.Label{
                    fontSize = 14,
                    color = "#aaaaaa",
                    width = 130,
                    height = "auto",
                    halign = "right",
                    valign = "center",
                    textAlignment = "right",
                    interactable = false,
                    text = FormatDay(ticket.updatedAt or ticket.createdAt),
                },
            }
        end

        return gui.Panel{
            width = "100%",
            height = "100%",
            flow = "vertical",

            gui.Label{
                fontSize = 15,
                width = "100%",
                height = "auto",
                halign = "left",
                textWrap = true,
                vmargin = 4,
                text = "Your bug report tickets. Click a ticket to read developer responses and add more information.",
            },

            gui.Panel{
                width = "100%",
                height = 660,
                vscroll = true,
                flow = "vertical",
                children = rows,
            },
        }
    end

    local function BuildDetailPage()
        local ticket = TicketById(m_selected)
        if ticket == nil then
            return BuildMessagePage("This ticket could not be found.")
        end

        local messagePanels = {}
        for _,entry in ipairs(SortedMessages(ticket)) do
            local msg = entry.msg
            local fromDev = (msg.from == "dev")
            local who = "You"
            if fromDev then
                who = "DMHub Team"
                if type(msg.name) == "string" and msg.name ~= "" then
                    who = string.format("DMHub Team (%s)", msg.name)
                end
            end

            messagePanels[#messagePanels+1] = gui.Panel{
                width = "100%-16",
                height = "auto",
                flow = "vertical",
                halign = "left",
                valign = "top",
                vmargin = 6,

                gui.Panel{
                    width = "100%",
                    height = "auto",
                    flow = "horizontal",

                    gui.Label{
                        fontSize = 14,
                        bold = true,
                        width = "auto",
                        height = "auto",
                        halign = "left",
                        color = cond(fromDev, "#86b4e0", "#d0c3a5"),
                        text = who,
                    },

                    gui.Label{
                        fontSize = 12,
                        width = "auto",
                        height = "auto",
                        halign = "right",
                        color = "#999999",
                        text = FormatTime(msg.timestamp),
                    },
                },

                gui.Label{
                    fontSize = 15,
                    width = "100%",
                    height = "auto",
                    halign = "left",
                    tmargin = 2,
                    textWrap = true,
                    text = msg.text or "",
                },
            }
        end

        local replyInput = gui.Input{
            classes = {"bordered"},
            width = "100%",
            height = 80,
            fontSize = 15,
            multiline = true,
            characterLimit = 10000,
            textAlignment = "topleft",
            halign = "left",
            tmargin = 8,
            placeholderText = "Add a message to this ticket...",
        }

        local sendStatus = gui.Label{
            fontSize = 14,
            width = "auto",
            height = "auto",
            halign = "left",
            valign = "center",
            text = "",
        }

        local sendButton = gui.Button{
            classes = {"sizeM"},
            text = "Send",
            halign = "right",
            valign = "center",
            click = function(element)
                if m_sending then
                    return
                end
                local text = replyInput.text
                if text == nil or text == "" then
                    sendStatus.text = "Enter a message first."
                    return
                end

                m_sending = true
                sendStatus.text = "Sending..."

                local ok = pcall(function()
                    dmhub.AddTicketMessage{
                        reportId = ticket.reportId,
                        text = text,
                        complete = function()
                            m_sending = false
                            --record the message locally so the thread
                            --updates without waiting for a refetch.
                            m_localMessageCounter = m_localMessageCounter + 1
                            ticket.messages = ticket.messages or {}
                            ticket.messages[string.format("zlocal%04d", m_localMessageCounter)] = {
                                from = "user",
                                text = text,
                                timestamp = os.time() * 1000,
                            }
                            ticket.updatedAt = os.time() * 1000
                            RefreshPage()
                        end,
                        error = function(message)
                            m_sending = false
                            if sendStatus.valid then
                                sendStatus.text = "Could not send: " .. message
                            end
                        end,
                    }
                end)

                if not ok then
                    m_sending = false
                    sendStatus.text = "Could not send the message."
                end
            end,
        }

        local closed = (ticket.status == "closed")

        local closedNotice = nil
        if closed then
            local noticeText = "This ticket has been closed by the developers. You can still add a message if you have more information."
            if ticket.closedBy == "user" then
                noticeText = "You closed this ticket. You can reopen it if the problem comes back, or add a message with more information."
            end
            closedNotice = gui.Label{
                fontSize = 14,
                color = "#999999",
                width = "100%",
                height = "auto",
                halign = "left",
                tmargin = 6,
                textWrap = true,
                text = noticeText,
            }
        end

        --The reporter can resolve their own ticket and reopen it if the
        --problem comes back. Both go through the same bridge call, which
        --stamps closedBy so the dashboard can tell the two apart.
        local statusButton = nil
        if TicketStatusBridgeAvailable() then
            statusButton = gui.Button{
                classes = {"sizeM"},
                text = cond(closed, "Reopen Ticket", "Close Ticket"),
                width = 160,
                halign = "right",
                valign = "center",
                rmargin = 8,
                hover = gui.Tooltip(cond(closed,
                    "Reopen this ticket if the problem is still happening.",
                    "Close this ticket if you no longer need help with it. You can reopen it later.")),
                click = function(element)
                    if m_sending then
                        return
                    end

                    local newStatus = cond(closed, "open", "closed")

                    m_sending = true
                    sendStatus.text = cond(closed, "Reopening...", "Closing...")

                    local ok = pcall(function()
                        dmhub.SetTicketStatus{
                            reportId = ticket.reportId,
                            status = newStatus,
                            complete = function()
                                m_sending = false
                                --mirror the server write locally so the chip
                                --and notice update without a refetch.
                                ticket.status = newStatus
                                ticket.closedBy = cond(newStatus == "closed", "user", nil)
                                ticket.updatedAt = os.time() * 1000
                                RefreshPage()
                            end,
                            error = function(message)
                                m_sending = false
                                if sendStatus.valid then
                                    sendStatus.text = "Could not update the ticket: " .. message
                                end
                            end,
                        }
                    end)

                    if not ok then
                        m_sending = false
                        sendStatus.text = "Could not update the ticket."
                    end
                end,
            }
        end

        --explicit list: statusButton is nil on older engines, and a nil
        --positional child would swallow the Send button after it.
        local buttons = {}
        if statusButton ~= nil then
            buttons[#buttons+1] = statusButton
        end
        buttons[#buttons+1] = sendButton

        --same reason: closedNotice is nil on an open ticket.
        local detailChildren = {
            gui.Panel{
                width = "100%",
                height = "auto",
                flow = "horizontal",

                gui.Button{
                    classes = {"sizeS"},
                    text = "Back",
                    width = 90,
                    halign = "left",
                    valign = "center",
                    click = function(element)
                        m_page = "list"
                        m_selected = nil
                        RefreshPage()
                    end,
                },

                gui.Label{
                    fontSize = 20,
                    width = 540,
                    height = "auto",
                    halign = "left",
                    valign = "center",
                    lmargin = 12,
                    textWrap = true,
                    text = ticket.title or "(no title)",
                },

                StatusChip(ticket),

                gui.Label{
                    fontSize = 14,
                    color = "#aaaaaa",
                    width = "auto",
                    height = "auto",
                    halign = "right",
                    valign = "center",
                    text = ticket.reportId or "",
                    hover = gui.Tooltip("Click to copy the ticket ID"),
                    click = function(element)
                        if ticket.reportId ~= nil then
                            gui.Tooltip{ text = "Copied to Clipboard", valign = "top", borderWidth = 0 }(element)
                            dmhub.CopyToClipboard(ticket.reportId)
                        end
                    end,
                },
            },

            gui.Panel{
                classes = {"bordered"},
                width = "100%",
                height = 440,
                vscroll = true,
                flow = "vertical",
                tmargin = 8,
                borderBox = true,
                pad = 8,
                children = messagePanels,
            },
        }
        if closedNotice ~= nil then
            detailChildren[#detailChildren+1] = closedNotice
        end
        detailChildren[#detailChildren+1] = replyInput
        detailChildren[#detailChildren+1] = gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            tmargin = 6,

            sendStatus,

            gui.Panel{
                width = "auto",
                height = "auto",
                flow = "horizontal",
                halign = "right",
                valign = "center",
                children = buttons,
            },
        }

        return gui.Panel{
            width = "100%",
            height = "100%",
            flow = "vertical",
            children = detailChildren,
        }
    end

    OpenDetail = function(reportId)
        m_selected = reportId
        m_page = "detail"

        local ticket = TicketById(reportId)
        if ticket ~= nil then
            --viewing the ticket clears the developer-responded marker: tell
            --the server, and raise the local seen floor so a fetch racing the
            --(fire-and-forget) server write cannot bring the marker back.
            pcall(function() dmhub.MarkTicketSeen(reportId) end)
            g_localTicketSeenFloor[reportId] = (ticket.lastDevMessageAt or 0) + 1
            RefreshTicketAlerts()
        end

        RefreshPage()
    end

    RefreshPage = function()
        if contentPanel == nil or not contentPanel.valid then
            return
        end

        local page
        if m_page == "loading" then
            page = BuildMessagePage("Loading your tickets...")
        elseif m_page == "error" then
            page = BuildMessagePage(m_errorMessage or "Could not load your tickets.")
        elseif m_page == "detail" then
            page = BuildDetailPage()
        else
            page = BuildListPage()
        end

        contentPanel.children = { page }
    end

    contentPanel = gui.Panel{
        width = "100%",
        height = "100%",
        flow = "vertical",

        styles = {
            { selectors = {"ticketRow"}, bgcolor = "#00000000", transitionTime = 0.1 },
            { selectors = {"ticketRow", "hover"}, bgcolor = "#ffffff26" },
        },
    }

    local bodyPanel = gui.Panel{
        width = 940,
        height = 740,
        flow = "vertical",
        halign = "center",

        contentPanel,
    }

    local closeButton = gui.Button{
        classes = {"closeButton"},
        floating = true,
        halign = "right",
        valign = "top",
        escapeActivates = true,
        escapePriority = EscapePriority.EXIT_MODAL_DIALOG,
        click = function(element)
            CloseDialog()
        end,
    }

    local host = nil
    if not InRealGame() then
        host = TitlescreenHostSheet()
    end

    if host ~= nil then
        m_titlescreenModal = gui.Panel{
            classes = {"framedPanel"},
            floating = true,
            width = 1024,
            height = 900,
            halign = "center",
            valign = "center",
            styles = ThemeEngine.GetStyles(),

            gui.Panel{
                width = "100%-32",
                height = "100%-32",
                flow = "vertical",
                halign = "center",
                valign = "top",

                gui.Label{
                    classes = {"dialogTitle"},
                    text = "Your Tickets",
                },

                bodyPanel,
            },
        }
        host:AddChild(m_titlescreenModal)
        m_titlescreenModal:AddChild(closeButton)
    else
        local gh = rawget(_G, "gamehud")
        if gh == nil then
            return
        end
        m_dialog = gh:ModalDialog{
            title = "Your Tickets",
            --taller than the default 768: the body is 740 plus title and strip.
            width = 1024,
            height = 900,
            buttons = {},
            bodyPanel,
        }
        m_dialog:AddChild(closeButton)
    end

    RefreshPage()

    FetchTickets(function(tickets, error)
        if error ~= nil then
            m_page = "error"
            m_errorMessage = "Could not load your tickets: " .. error
        else
            m_tickets = SortedTickets()
            m_page = "list"
        end
        RefreshPage()
    end)
end

--------------------------------------------------------------------------------
--Public API, used by the title bar (Styles.lua).
--------------------------------------------------------------------------------

--Captures the screenshot first, then shows the dialog for that kind.
function D20Feedback.ShowReportDialog(feedbackType)
    if not BugReportBridgeAvailable() then
        return
    end
    dmhub.BeginBugReport(function(report)
        if mod.unloaded then
            report:Cancel()
            return
        end
        CreateBugReportDialog(report, feedbackType)
    end)
end

function D20Feedback.ShowTicketsDialog()
    CreateTicketsDialog()
end

function D20Feedback.FetchTickets()
    FetchTickets()
end

function D20Feedback.HasUnseen()
    return g_ticketsState.hasUnseen
end

--A marker panel that wants a "refreshAlert" event whenever ticket state changes.
function D20Feedback.RegisterAlertPanel(panel)
    g_menuAlertPanels[#g_menuAlertPanels+1] = panel
end

--The Feedback menu's entries, built fresh each time the menu opens.
function D20Feedback.MenuItems()
    --refresh ticket state whenever the menu opens so the markers stay current.
    FetchTickets()

    if not BugReportBridgeAvailable() then
        return {{text = "Feedback needs a newer DMHub build", disabled = true}}
    end

    local function FeedbackMenuItem(text, feedbackType)
        return {
            text = text,
            click = function()
                D20Feedback.ShowReportDialog(feedbackType)
            end,
        }
    end

    local items = {
        FeedbackMenuItem("Bug Report", "bug"),
        FeedbackMenuItem("Feature Request", "feature"),
        FeedbackMenuItem("General Feedback", "feedback"),
    }

    if TicketBridgeAvailable() then
        items[#items+1] = {
            text = "Your Tickets",
            hasNewContent = function()
                return g_ticketsState.hasUnseen
            end,
            click = function()
                CreateTicketsDialog()
            end,
        }
    end

    return items
end

--F3 is bound to the "bugreport" command (InputController.ResetBinds): open
--Report a Bug directly. Commands.RegisterMacro comes from Core Utils, which
--this mod depends on.
if rawget(_G, "Commands") ~= nil and Commands.RegisterMacro ~= nil then
    Commands.RegisterMacro{
        name = "bugreport",
        summary = "report a bug",
        doc = "Opens the Report a Bug dialog.",
        command = function()
            D20Feedback.ShowReportDialog("bug")
        end,
    }
end

--fetch once at load so the Feedback marker can appear without the menu ever
--being opened.
FetchTickets()
