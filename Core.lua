-- Guild Bank Alts: characters of the guild used as its bank, by hand. Every
-- member with the addon sees what they hold (bags, bank, money) in a tab of
-- the guild window, and asks them for items; the requests are approved once
-- the bank characters hand the items over, by trade or by mail.
--
-- The addon messages, the guild roster, the saved database and the sync
-- are LibGuildSync's (a separate addon this one depends on), attached
-- below. Core.lua holds the startup and the slash commands.
local ADDON_NAME, ns = ...
local L = ns.L
local Lib = LibGuildSync

ns.ADDON_NAME = ADDON_NAME

-- While a version with a new protocol is tried in game before its release,
-- set trial = true: it then talks on trialPrefix (see LibGuildSync's
-- Core.lua). Turn it off for the release.
Lib.Attach(ns, {
    title = "Guild Bank Alts",
    tag = "GBA",
    prefix = "GuildBankAlts",
    trialPrefix = "GuildBankAltsDev",
    trial = false,
    protocol = "1",
    savedVariable = "GuildBankAltsDB",
})

-- While a version that keeps the protocol is tried in game before its
-- release, it tells the guild it runs the last release (ANNOUNCE_AS): it
-- keeps sharing with the members on it, who are not told to update to a
-- version they cannot get yet. Set it to nil for the release.
local ANNOUNCE_AS = nil
if ANNOUNCE_AS then
    ns.VERSION_NUM = Lib.VersionNumber(ANNOUNCE_AS)
end

-- Startup ------------------------------------------------------------------

local events = CreateFrame("Frame")
ns.RegisterEvents(events, "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_LOGOUT")
events:SetScript("OnEvent", function(self, event, name)
    if event == "PLAYER_LOGOUT" then
        ns.Data.PackForSave(ns.db)
    elseif event == "ADDON_LOADED" and name == ADDON_NAME then
        self:UnregisterEvent("ADDON_LOADED")
        ns.Data.Load()
        if ns.db.settings.locale then
            ns.SetLocale(ns.db.settings.locale)
        end
    elseif event == "PLAYER_LOGIN" then
        -- The library first: our name, the roster, the messages and the sync.
        Lib.Start(ns)
        -- Each part starts on its own, so a failure in one (reported as a normal
        -- Lua error) does not stop the others.
        for _, init in ipairs({ ns.Bank.Init, ns.Requests.Init, ns.Log.Init, ns.Deliveries.Init, ns.BankView.Init,
                ns.MailToBank.Init, ns.Prepare.Init, ns.BagLocks.Init, ns.RequestList.Init, ns.GuildTab.Init, ns.Options.Init }) do
            xpcall(init, geterrorhandler())
        end
    end
end)

-- Slash commands -------------------------------------------------------------

local function PrintHelp()
    ns.Print(L["/gbalts status - what the addon knows and is doing"])
    ns.Print(L["/gbalts options - the addon's options, and the guild's: bank ranks and permissions"])
    ns.Print(L["/gbalts sync - ask the guild for missing data now"])
    ns.Print(L["/gbalts language [code|auto] - language of the addon's texts"])
    ns.Print(L["/gbalts debug - show the sync log in the chat"])
    ns.Print(L["/gbalts reset - forget the data of your current guild"])
end

local function PrintStatus()
    ns.Print(L["version %s. Saved data loaded by the client: %s."], ns.VERSION, ns.loadInfo.native and YES or NO)

    local guildKey = ns.Roster.guildKey
    if not guildKey then
        ns.Print(L["you are not in a guild (or the guild has not loaded yet)."])
    else
        local guild = ns.Data.GetGuild(guildKey)
        local count = 0
        for _ in pairs(guild and guild.members or {}) do
            count = count + 1
        end
        ns.Print(L["guild %s: data on %d |4character:characters; with the addon, %d |4member:members; in the roster."], guildKey, count, ns.Roster.total)
    end
    ns.Print(L["sync: %s"], ns.Sync.Describe())
end

SLASH_GUILDBANKALTS1 = "/gbalts"
SLASH_GUILDBANKALTS2 = "/guildbankalts"
SlashCmdList.GUILDBANKALTS = function(message)
    message = strtrim(message or "")
    local command, rest = message:match("^(%S*)%s*(.-)$")
    local lower = command:lower()
    if lower == "" or lower == "status" then
        PrintStatus()
    elseif lower == "sync" then
        ns.Sync.SendHello(true)
    elseif lower == "options" or lower == "config" then
        ns.Options.Open()
    elseif lower == "debug" then
        ns.debugEnabled = not ns.debugEnabled
        ns.Print(ns.debugEnabled and L["sync log on."] or L["sync log off."])
    elseif lower == "language" or lower == "lang" then
        -- A language code in any case ("dede" is deDE), or auto.
        local code
        for _, known in ipairs(ns.LOCALES) do
            if known:lower() == rest:lower() then
                code = known
            end
        end
        if not code and rest:lower() ~= "auto" then
            ns.Print(L["languages: %s, or auto for the client's."], table.concat(ns.LOCALES, ", "))
            return
        end
        ns.db.settings.locale = code
        ns.SetLocale(code)
        ns.Print(L["language set to %s."], ns.LOCALE)
    elseif lower == "reset" then
        if rest:lower() ~= "confirm" then
            ns.Print(L["this forgets what you know about your current guild. Type /gbalts reset confirm to do it."])
        else
            ns.Data.ResetGuild(ns.Roster.guildKey)
            ns.Print(L["data of your current guild forgotten."])
        end
    else
        PrintHelp()
    end
end
