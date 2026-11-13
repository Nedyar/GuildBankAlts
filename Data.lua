-- Data.lua: what the bank's records hold and how they are checked and
-- merged. The saved database itself (GuildBankAltsDB), the merge rules and
-- the sync are LibGuildSync's (its Store.lua); this file teaches it the
-- bank's records (see Pack.lua for the fields).
--
-- GuildBankAltsDB.own[GUID] keeps, for each character of the account:
-- sentFP, sentGuild (the sync's), lastRequest, requestStates (how the
-- requests that concern us stood, for the chat notices, RequestList.lua),
-- acceptedSeen (our accepted requests whose notice we saw, pointing at
-- their row, RequestList.lua) and prepared (the stacks kept for requests,
-- Prepare.lua). 0.3.1 also
-- kept requestsSeen, no longer used.
local _, ns = ...
local Lib = ns.Lib
local Pack, Data = ns.Pack, ns.Data

local LIMITS = Pack.LIMITS
local IsCount, IsID, IsTime = Lib.IsCount, Lib.IsID, Lib.IsTime

-- An item string as the addon shares it (see Bank.lua): "item:",
-- the item ID, then letters, digits, colons or dashes, nothing that could
-- be a link or an escape sequence.
local function IsItemString(text)
    return type(text) == "string" and #text <= LIMITS.item and text:find("^item:%d+[%w:%-]*$") ~= nil
end

-- A note as given by another client: no escape sequences, at most
-- LIMITS.note bytes, cut at a character boundary.
function Data.CleanNote(text)
    if type(text) ~= "string" then
        return ""
    end
    text = text:gsub("[|%c]", " ")
    if #text > LIMITS.note then
        text = text:sub(1, LIMITS.note):gsub("[\192-\255][\128-\191]*$", "")
    end
    return strtrim and strtrim(text) or (text:match("^%s*(.-)%s*$"))
end

-- A bank character's bags or bank: a list of containers, or nil when
-- unusable.
local function CleanContainers(containers)
    if type(containers) ~= "table" or #containers > LIMITS.containers then
        return nil
    end
    local clean = {}
    for _, container in ipairs(containers) do
        if type(container) ~= "table" or not IsCount(container.id, 1000) or not IsCount(container.z, LIMITS.slotsPerContainer)
            or (container.bi ~= nil and not IsItemString(container.bi)) or type(container.s or {}) ~= "table" then
            return nil
        end
        local slots = {}
        for slot, item in pairs(container.s or {}) do
            if not IsID(slot) or slot > container.z or type(item) ~= "table" or not IsID(item.i)
                or not IsCount(item.n, 1000000) or item.n == 0 or (item.s ~= nil and not IsItemString(item.s)) then
                return nil
            end
            slots[slot] = { i = item.i, n = item.n, s = item.s }
        end
        clean[#clean + 1] = { id = container.id, z = container.z, bi = container.bi, lk = container.lk == true or nil, s = slots }
    end
    return clean
end

local function CleanBank(bank)
    if type(bank) ~= "table" or not IsCount(bank.m, 2 ^ 52) then
        return nil
    end
    local clean = { m = bank.m, bt = IsTime(bank.bt) and bank.bt or nil, b = CleanContainers(bank.b or {}) }
    if not clean.b then
        return nil
    end
    if bank.kt ~= nil then
        clean.kt, clean.k = IsTime(bank.kt) and bank.kt or nil, CleanContainers(bank.k or {})
        if not clean.kt or not clean.k then
            return nil
        end
    end
    return clean
end

local function CleanGuildMoney(money)
    if type(money) ~= "table" or not IsCount(money.m, 2 ^ 52) or not IsTime(money.t) then
        return nil
    end
    return { m = money.m, t = money.t }
end

local function CleanRequests(requests)
    if type(requests) ~= "table" then
        return nil
    end
    local clean, count = {}, 0
    for id, request in pairs(requests) do
        if not IsID(id) or type(request) ~= "table" or not Data.IsGUID(request.b) or not IsID(request.i)
            or not IsCount(request.q, LIMITS.quantity) or request.q == 0 or not IsTime(request.c)
            or (request.s ~= nil and not IsItemString(request.s)) then
            return nil
        end
        clean[id] = { b = request.b, i = request.i, s = request.s, q = request.q, c = request.c, nt = Data.CleanNote(request.nt),
            d = (request.d == 1 or request.d == 2) and request.d or nil }
        count = count + 1
        if count > LIMITS.requests then
            return nil
        end
    end
    return clean
end

local function CleanAnswers(answers)
    if type(answers) ~= "table" then
        return nil
    end
    local clean, count = {}, 0
    for key, answer in pairs(answers) do
        local requester, id
        if type(key) == "string" then
            requester, id = key:match("^(.+):(%d+)$")
        end
        if not requester or not Data.IsGUID(requester) or not IsID(tonumber(id)) or type(answer) ~= "table"
            or (answer.s ~= 1 and answer.s ~= 2) or not IsCount(answer.n or 0, LIMITS.quantity) or not IsTime(answer.u) then
            return nil
        end
        clean[key] = { s = answer.s, n = answer.n or 0, u = answer.u }
        count = count + 1
        if count > LIMITS.answers then
            return nil
        end
    end
    return clean
end

local function CleanAccepted(accepted)
    if type(accepted) ~= "table" then
        return nil
    end
    local clean, count = {}, 0
    for key, at in pairs(accepted) do
        local requester, id
        if type(key) == "string" then
            requester, id = key:match("^(.+):(%d+)$")
        end
        if not requester or not Data.IsGUID(requester) or not IsID(tonumber(id)) or not IsTime(at) then
            return nil
        end
        clean[key] = at
        count = count + 1
        if count > LIMITS.answers then
            return nil
        end
    end
    return clean
end

-- Logs (see Log.lua) ------------------------------------------------------------

-- A name in a log: who items or money came from or went to, or a tab of the
-- guild vault. "" when the game gave none; nil when it cannot be shown.
local function CleanLogName(name)
    if name == nil or name == "" then
        return ""
    end
    return Data.CleanName(name, LIMITS.text)
end

-- What changed hands, copied into clean: an item (i, n and maybe s) or
-- money (m, and maybe r, the money left after it). False when it cannot be
-- trusted.
local function CleanWhat(entry, clean)
    if entry.i ~= nil then
        if not IsID(entry.i) or not IsCount(entry.n, LIMITS.logCount) or entry.n == 0
            or (entry.s ~= nil and not IsItemString(entry.s)) or entry.m ~= nil then
            return false
        end
        clean.i, clean.n, clean.s = entry.i, entry.n, entry.s
        return true
    end
    if not IsCount(entry.m, 2 ^ 52) or (entry.r ~= nil and not IsCount(entry.r, 2 ^ 52)) then
        return false
    end
    clean.m, clean.r = entry.m, entry.r
    return true
end

local ACTIONS = { [1] = true, [2] = true }
local VIAS = { [1] = true, [2] = true, [3] = true, [4] = true, [5] = true, [6] = true }
local VAULT_TYPES = {}
for _, code in pairs(Pack.VAULT_TYPES) do
    VAULT_TYPES[code] = true
end

-- Entries go oldest first, none later than newest (the record's time).
local function CleanLog(log, newest)
    if type(log) ~= "table" or #log > LIMITS.log then
        return nil
    end
    local clean, previous = {}, 0
    for index, entry in ipairs(log) do
        if type(entry) ~= "table" or not IsTime(entry.t) or entry.t < previous or entry.t > newest
            or not ACTIONS[entry.a] or not VIAS[entry.v] then
            return nil
        end
        local item = { t = entry.t, a = entry.a, v = entry.v, w = CleanLogName(entry.w) }
        if not item.w or not CleanWhat(entry, item) then
            return nil
        end
        previous = entry.t
        clean[index] = item
    end
    return clean
end

local function IsTab(tab)
    return tab == nil or (IsID(tab) and tab <= LIMITS.tabs)
end

local function CleanGuildLog(log, newest)
    if type(log) ~= "table" or not IsTime(log.t) or log.t > newest or type(log.tn) ~= "table" or #log.tn > LIMITS.tabs
        or type(log.e) ~= "table" or #log.e > LIMITS.guildLog then
        return nil
    end
    local clean, previous = { t = log.t, tn = {}, e = {} }, 0
    for index, name in ipairs(log.tn) do
        clean.tn[index] = CleanLogName(name)
        if not clean.tn[index] then
            return nil
        end
    end
    for index, entry in ipairs(log.e) do
        if type(entry) ~= "table" or not IsTime(entry.t) or entry.t < previous or entry.t > log.t
            or not VAULT_TYPES[entry.y] then
            return nil
        end
        local item = { t = entry.t, y = entry.y, w = CleanLogName(entry.w) }
        if not item.w or not CleanWhat(entry, item) then
            return nil
        end
        if item.i then
            if not IsTab(entry.b) or not IsTab(entry.d) then
                return nil
            end
            item.b, item.d = entry.b, entry.d
        end
        previous = entry.t
        clean.e[index] = item
    end
    return clean
end

-- A checked copy of a record, or nil when it cannot be trusted. now is given
-- for records from other clients, which may not be dated in the future.
function Data.CleanRecord(record, now)
    local clean = Data.CleanBase(record, now)
    if not clean then
        return nil
    end
    for field, cleaner in pairs({ bk = CleanBank, rq = CleanRequests, ra = CleanAnswers, gb = CleanGuildMoney,
            lg = CleanLog, gl = CleanGuildLog, ac = CleanAccepted }) do
        if record[field] ~= nil then
            clean[field] = cleaner(record[field], clean.t)
            if not clean[field] then
                return nil
            end
        end
    end
    return clean
end

-- Comparing and merging --------------------------------------------------------

-- The parts of a record a copy may lack: one point each. Not the accepted
-- requests (ac): members on older versions cannot keep them, so copies of
-- the same time would never count alike and be sent back and forth.
local PARTS = { "bk", "gb", "rq", "ra", "lg", "gl" }

-- How complete a record is: how many of its parts are known.
Data.STATS = 1

function Data.Stats(record)
    local parts = 0
    for _, field in ipairs(PARTS) do
        if record[field] ~= nil then
            parts = parts + 1
        end
    end
    return parts
end

-- The copy kept of a member takes the requests, answers, logs and accepted
-- requests only the other copy knows: the owner lost its data and has not
-- seen the guild's copy yet, or (accepted requests) the copy came through a
-- member on an older version, which drops them. Returns true if it took any.
function Data.CarryMissing(kept, other)
    local changed = false
    for _, field in ipairs({ "rq", "ra", "lg", "gl", "ac" }) do
        if kept[field] == nil and other[field] ~= nil then
            kept[field] = other[field]
            changed = true
        end
    end
    return changed
end

-- Our own record is only ever changed by us, but if we lost our requests,
-- answers and logs, a copy coming back from the guild fills them in.
function Data.AdoptOwn(own, record)
    return Data.CarryMissing(own, record)
end
