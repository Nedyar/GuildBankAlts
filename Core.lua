-- Guild Bank Alts: characters of the guild used as its bank, by hand. Every
-- member with the addon sees what they hold (bags, bank, money) in a tab of
-- the guild window, and asks them for items; the requests are approved once
-- the bank characters hand the items over, by trade or by mail.
-- Core.lua holds the shared helpers, the startup and the slash commands.
local ADDON_NAME, ns = ...
local L = ns.L

ns.ADDON_NAME = ADDON_NAME
ns.TITLE = "Guild Bank Alts"
ns.VERSION = C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version") or "0.0.0"

-- Addon messages go out on PREFIX and are heard on every prefix in LISTEN.
-- While a version with a new protocol is tried in game before its release
-- (TRIAL), it talks on a prefix of its own: members on the released
-- version do not hear it, so they are not asked to update to a version
-- they cannot get yet, and their own messages are still heard. TRIAL is
-- turned off for the release. Prefixes hold at most 16 characters.
ns.TRIAL = false
local RELEASE_PREFIX = "GuildBankAlts"
ns.PREFIX = ns.TRIAL and "GuildBankAltsDev" or RELEASE_PREFIX
ns.LISTEN = { [ns.PREFIX] = true, [RELEASE_PREFIX] = true }

-- "1.2.3" -> 10203. Records carry it so a newer client in the guild is noticed.
function ns.VersionNumber(version)
    local major, minor, patch = tostring(version):match("^(%d+)%.(%d+)%.?(%d*)")
    if not major then
        return 0
    end
    return tonumber(major) * 10000 + tonumber(minor) * 100 + (tonumber(patch) or 0)
end

function ns.VersionString(number)
    return ("%d.%d.%d"):format(math.floor(number / 10000), math.floor(number / 100) % 100, number % 100)
end

ns.VERSION_NUM = ns.VersionNumber(ns.VERSION)

-- WoW Forever runs the Midnight addon API, where some results are "secret":
-- using one in a condition, or even comparing it with nil, raises an error.
-- Anything that might be secret goes through Plain() before it is looked at.
local issecretvalue = issecretvalue or function() return false end

function ns.Plain(value)
    if issecretvalue(value) then
        return nil
    end
    return value
end

-- A plain number, or nil.
function ns.Number(value)
    value = ns.Plain(value)
    return type(value) == "number" and value or nil
end

-- True when two values hold the same data (tables compared field by field).
function ns.Same(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then
        return a == b
    end
    for key, value in pairs(a) do
        if not ns.Same(value, b[key]) then
            return false
        end
    end
    for key in pairs(b) do
        if a[key] == nil then
            return false
        end
    end
    return true
end

-- Tables from the API can be secret as a whole during a lockdown, and
-- reading their fields then raises.
local canaccesstable = canaccesstable

function ns.CanRead(tbl)
    if type(tbl) ~= "table" then
        return false
    end
    -- Called directly: it answers for the function that calls it.
    return not canaccesstable or canaccesstable(tbl) ~= false
end

function ns.Print(message, ...)
    if select("#", ...) > 0 then
        message = message:format(...)
    end
    print("|cff33ccffGuild Bank Alts|r: " .. message)
end

-- RegisterEvent raises for an event this client does not have, which would
-- abort the rest of the file, so every registration is wrapped.
function ns.RegisterEvents(frame, ...)
    for i = 1, select("#", ...) do
        pcall(frame.RegisterEvent, frame, (select(i, ...)))
    end
end

-- Calls fn, returning nothing instead of raising when the client lacks it or
-- it fails. For the undocumented API the addon cannot be sure of.
function ns.Try(fn, ...)
    if type(fn) ~= "function" then
        return nil
    end
    local results = { pcall(fn, ...) }
    if not results[1] then
        ns.Debug("call failed: %s", tostring(results[2]))
        return nil
    end
    return unpack(results, 2, table.maxn(results))
end

function ns.Now()
    return GetServerTime()
end

-- Debug log: kept in memory only, printed while /gbalts debug is on.
ns.debugLog = {}

function ns.Debug(message, ...)
    if select("#", ...) > 0 then
        local ok, text = pcall(string.format, message, ...)
        message = ok and text or message
    end
    local line = date("%H:%M:%S ") .. message
    local log = ns.debugLog
    log[#log + 1] = line
    if #log > 300 then
        table.remove(log, 1)
    end
    if ns.debugEnabled then
        print("|cff888888GBA|r " .. line)
    end
end

-- Calls fn(...), reporting an error as a normal Lua error instead of
-- stopping the caller. (Arguments are not passed through xpcall itself,
-- which plain Lua 5.1 does not support.)
function ns.SafeCall(fn, ...)
    local args, count = { ... }, select("#", ...)
    xpcall(function()
        fn(unpack(args, 1, count))
    end, geterrorhandler())
end

-- Callbacks between the parts of the addon. Each listener runs on its own,
-- so an error in one is reported without stopping the others.
local listeners = {}

function ns.On(event, callback)
    listeners[event] = listeners[event] or {}
    table.insert(listeners[event], callback)
end

function ns.Fire(event, ...)
    for _, callback in ipairs(listeners[event] or {}) do
        ns.SafeCall(callback, ...)
    end
end

-- Runs fn once things have been quiet for delay seconds. With maxWait, it
-- runs at the latest maxWait seconds after the first call.
local debounced = {}

function ns.Debounce(key, delay, fn, maxWait)
    local now = GetTime()
    local entry = debounced[key]
    if entry then
        entry.timer:Cancel()
    else
        entry = { first = now }
        debounced[key] = entry
    end
    local wait = delay
    if maxWait then
        wait = math.min(delay, entry.first + maxWait - now)
    end
    entry.timer = C_Timer.NewTimer(math.max(wait, 0), function()
        debounced[key] = nil
        fn()
    end)
end

-- Names -------------------------------------------------------------------

-- Our name ("Alice Smith") and how our addon messages are signed
-- ("Alice Smith-Realm").
function ns.SetPlayerName(name)
    ns.playerName = name
    ns.playerKey = name .. "-" .. ns.realm
end

-- True when a message sender is ourselves ("Name Surname", or with a realm).
function ns.IsMe(sender)
    return sender == ns.playerName or sender == ns.playerKey
        or (ns.playerGUID ~= nil and ns.Roster.GUIDOfSender(sender) == ns.playerGUID)
end

-- Realm names as they appear in "Name-Realm": no spaces or dashes.
function ns.NormalizeRealm(realm)
    return (realm:gsub("[%s%-]", ""))
end

function ns.ShortName(fullName)
    return Ambiguate(fullName, "guild")
end

-- "3 days", "5 min"... in the client's language.
function ns.Ago(timestamp)
    local seconds = math.max(ns.Now() - timestamp, 0)
    if seconds < 60 then
        return L["a moment"]
    end
    -- Limited to one unit, SecondsToTime only uses a unit from 1.5 of it, so
    -- from 60 to 89 seconds it gives nothing.
    local text = SecondsToTime(seconds, true, true, 1)
    if text == "" then
        text = SecondsToTime(seconds, true, true, 2)
    end
    return text
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
        ns.realm = ns.Plain(GetNormalizedRealmName()) or ns.NormalizeRealm(GetRealmName())
        ns.playerGUID = ns.Plain(UnitGUID("player"))
        -- WoW Forever names have two parts, and UnitName gives them apart
        -- ("Alice", "Smith"). The roster's spelling replaces this once it
        -- is read (see Roster.lua).
        local first, second = UnitName("player")
        first, second = ns.Plain(first), ns.Plain(second)
        ns.SetPlayerName(second and second ~= "" and (first .. " " .. second) or first)
        ns.loginTime = GetTime()
        -- Each part starts on its own, so a failure in one (reported as a normal
        -- Lua error) does not stop the others.
        for _, init in ipairs({ ns.Comm.Init, ns.Roster.Init, ns.Bank.Init, ns.Requests.Init, ns.Deliveries.Init,
                ns.Sync.Init, ns.BankView.Init, ns.RequestList.Init, ns.GuildTab.Init }) do
            xpcall(init, geterrorhandler())
        end
    end
end)

-- Slash commands -------------------------------------------------------------

local function PrintHelp()
    ns.Print(L["/gbalts status - what the addon knows and is doing"])
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
