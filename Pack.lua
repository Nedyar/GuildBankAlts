-- Pack.lua: the packed form of the bank's records (LibGuildSync's Pack.lua
-- has the numbers, texts, Base64 and hashing they are made of). Plain Lua
-- with no game API, so it can be tested outside the game.
local _, ns = ...

local Pack = ns.Pack

-- The most a record may hold. Anything bigger is refused when read.
Pack.LIMITS = {
    text = 64,
    item = 255,      -- length of an item string
    containers = 20, -- a bank character's bags, or its bank's
    slotsPerContainer = 200,
    requests = 30,   -- open and recent requests of one member
    answers = 150,   -- requests one member answered
    quantity = 10000,
    note = 120,      -- bytes of a request's note
    log = 100,       -- entries of a bank character's log
    guildLog = 100,  -- entries of the guild vault's log a member keeps
    logCount = 1000000, -- items of one kind in a log entry
    tabs = 8,        -- the guild vault's tabs
    rankName = 32,   -- bytes of a rank's name in the guild's options
    bankRanks = 10,  -- bank ranks in the guild's options
    optionRanks = 20, -- ranks the guild's options name, at one place
    optionBanks = 30, -- bank characters the guild's options name
    options = 8000,  -- bytes of the guild's options, packed
}

-- The types of the guild vault's log entries (gl), by the names the game
-- gives them.
Pack.VAULT_TYPES = {
    deposit = 1, withdraw = 2, move = 3, repair = 4, withdrawForTab = 5, buyTab = 6, depositSummary = 7, buyRename = 8,
    refundRename = 9,
}

-- Records --------------------------------------------------------------------

-- A record is what one character shares, under its GUID:
--   n = name, rl = realm, t = time of its last change, av = addon version,
--   bk = what a guild bank character holds (see Bank.lua), nil for other
--       characters: { m = money in copper, bt = when its bags were read,
--       b = its bags, kt = when its bank was read (nil: never), k = its
--       bank }. Bags and bank are lists of containers, in the game's order:
--       { id = container ID, z = its slots, bi = the item string of the bag
--       in it (nil: none, or the backpack's or bank's own), lk = true for
--       a bank bag slot not bought yet, s = { [slot] = { i = item ID,
--       n = count, s = item string when it says more than the ID } } },
--   gb = the guild bank's money, as the member last saw it:
--       { m = copper, t = when },
--   rq = the withdrawal requests the member made (see Requests.lua):
--       { [id] = { b = the bank character's GUID, i = item ID, s = item
--       string or nil, q = quantity, c = when it was made, nt = note,
--       d = 1 in person / 2 by mail } },
--   ra = the member's answers to other members' requests:
--       { ["<requester GUID>:<id>"] = { s = 1 rejected / 2 delivering,
--       n = items delivered, u = when it last changed } },
--   lg = a bank character's log: what it traded and mailed (see Log.lua),
--       oldest first: { { t = when, a = 1 in / 2 out, v = 1 by trade /
--       2 by mail / 3 cash on delivery / 4 returned mail / 5 at the guild
--       vault (money it put in or took out; w = "") / 6 postage it
--       paid (w = the mail's recipient), w = the other
--       side's name ("" when unknown), then either i = item ID, n = count,
--       s = item string or nil, or m = copper, r = the copper the bank
--       character had left after it (nil: unknown) }... },
--   gl = the guild vault's own log, as the member last read it at a guild
--       vault, together with what the guild knew of it then: { t = when it
--       was read, tn = { the vault's tab names }, e = { { t = when (to the
--       hour), y = type (Log.VAULT_TYPES), w = name, then either i, n, s,
--       b = tab (the tab moved from), d = the tab moved to, or
--       m = copper, r = the vault's copper after it (nil: unknown) }... } },
--       oldest first,
--   ac = the requests the member accepted (a bank character, an officer or
--       the guild master): { ["<requester GUID>:<id>"] = when }. Apart
--       from ra, which older versions read to the letter, at the end of the
--       record, which they skip: to them an accepted request is pending.
--   cf = the guild's options, in the guild master's record (any other
--       member's are ignored; see Ranks.lua): { t = when they were set,
--       bn = { bank rank names }, rp = { [rank] = what it may do (flags
--       of Ranks.LOG, MAKE, ACCEPT, REJECT) }, bv = { [bank character's
--       GUID] = { [rank] = what it may see of it (Ranks.ITEMS, MONEY) } } },
--       ranks by their names in lower case. Packed apart, with a format
--       number of its own: a later format is skipped, not refused.
-- rq, ra, lg and ac are nil until known: a client that lost its data does
-- not tell the guild it has none.
-- A packed record is prefixed by its length, so fields added later are
-- skipped by older readers.
local ABSENT, PRESENT = 0, 1

local LIMITS = Pack.LIMITS

local function SortedKeys(map)
    local keys = {}
    for key in pairs(map) do
        keys[#keys + 1] = key
    end
    table.sort(keys)
    return keys
end

local function WriteContainers(writer, containers)
    writer:UInt(#containers)
    for _, container in ipairs(containers) do
        writer:UInt(container.id)
        writer:UInt(container.z or 0)
        writer:Str(container.bi or "")
        writer:Byte(container.lk and 1 or 0)
        local slots = SortedKeys(container.s or {})
        writer:UInt(#slots)
        for _, slot in ipairs(slots) do
            local item = container.s[slot]
            writer:UInt(slot)
            writer:UInt(item.i)
            writer:UInt(item.n)
            writer:Str(item.s or "")
        end
    end
end

local function ReadContainers(reader)
    local count = reader:UInt()
    if count > LIMITS.containers then
        error("too many containers", 0)
    end
    local containers = {}
    for c = 1, count do
        local container = { id = reader:UInt(), z = reader:UInt(), s = {} }
        local bagItem = reader:Str(LIMITS.item)
        container.bi = bagItem ~= "" and bagItem or nil
        container.lk = reader:Byte() == 1 or nil
        local filled = reader:UInt()
        if container.z > LIMITS.slotsPerContainer or filled > container.z then
            error("too many slots", 0)
        end
        for _ = 1, filled do
            local slot = reader:UInt()
            local item = { i = reader:UInt(), n = reader:UInt() }
            local text = reader:Str(LIMITS.item)
            item.s = text ~= "" and text or nil
            container.s[slot] = item
        end
        containers[c] = container
    end
    return containers
end

local function WriteBank(writer, bank)
    if not bank then
        writer:Byte(ABSENT)
        return
    end
    writer:Byte(PRESENT)
    writer:UInt(bank.m or 0)
    writer:UInt(bank.bt or 0)
    WriteContainers(writer, bank.b or {})
    writer:UInt(bank.kt or 0)
    if bank.kt then
        WriteContainers(writer, bank.k or {})
    end
end

local function ReadBank(reader)
    local present = reader:Byte()
    if present == ABSENT then
        return nil
    elseif present ~= PRESENT then
        error("unknown bank data", 0)
    end
    local bank = { m = reader:UInt(), bt = reader:UInt(), b = ReadContainers(reader) }
    local bankTime = reader:UInt()
    if bankTime > 0 then
        bank.kt, bank.k = bankTime, ReadContainers(reader)
    end
    return bank
end

local function WriteGuildMoney(writer, money)
    if not money then
        writer:Byte(ABSENT)
        return
    end
    writer:Byte(PRESENT)
    writer:UInt(money.m)
    writer:UInt(money.t)
end

local function ReadGuildMoney(reader)
    if reader:Byte() == ABSENT then
        return nil
    end
    return { m = reader:UInt(), t = reader:UInt() }
end

-- Maps are written as their count plus one: 0 is "unknown" (nil).
local function WriteRequests(writer, requests)
    if not requests then
        writer:UInt(0)
        return
    end
    local ids = SortedKeys(requests)
    writer:UInt(#ids + 1)
    for _, id in ipairs(ids) do
        local request = requests[id]
        writer:UInt(id)
        writer:Str(request.b)
        writer:UInt(request.i)
        writer:Str(request.s or "")
        writer:UInt(request.q)
        writer:UInt(request.c)
        writer:Str(request.nt or "")
        writer:UInt(request.d or 0)
    end
end

local function ReadRequests(reader)
    local count = reader:UInt()
    if count == 0 then
        return nil
    elseif count - 1 > LIMITS.requests then
        error("too many requests", 0)
    end
    local requests = {}
    for _ = 1, count - 1 do
        local id = reader:UInt()
        local request = { b = reader:Str(), i = reader:UInt() }
        local text = reader:Str(LIMITS.item)
        request.s = text ~= "" and text or nil
        request.q, request.c = reader:UInt(), reader:UInt()
        request.nt = reader:Str(LIMITS.note)
        local delivery = reader:UInt()
        request.d = delivery > 0 and delivery or nil
        requests[id] = request
    end
    return requests
end

local function WriteAnswers(writer, answers)
    if not answers then
        writer:UInt(0)
        return
    end
    local keys = SortedKeys(answers)
    writer:UInt(#keys + 1)
    for _, key in ipairs(keys) do
        local requester, id = key:match("^(.+):(%d+)$")
        local answer = answers[key]
        writer:Str(requester)
        writer:UInt(tonumber(id))
        writer:UInt(answer.s)
        writer:UInt(answer.n or 0)
        writer:UInt(answer.u)
    end
end

local function ReadAnswers(reader)
    local count = reader:UInt()
    if count == 0 then
        return nil
    elseif count - 1 > LIMITS.answers then
        error("too many answers", 0)
    end
    local answers = {}
    for _ = 1, count - 1 do
        local key = reader:Str() .. ":" .. reader:UInt()
        answers[key] = { s = reader:UInt(), n = reader:UInt(), u = reader:UInt() }
    end
    return answers
end

local function WriteAccepted(writer, accepted)
    if not accepted then
        writer:UInt(0)
        return
    end
    local keys = SortedKeys(accepted)
    writer:UInt(#keys + 1)
    for _, key in ipairs(keys) do
        local requester, id = key:match("^(.+):(%d+)$")
        writer:Str(requester)
        writer:UInt(tonumber(id))
        writer:UInt(accepted[key])
    end
end

local function ReadAccepted(reader)
    local count = reader:UInt()
    if count == 0 then
        return nil
    elseif count - 1 > LIMITS.answers then
        error("too many accepted requests", 0)
    end
    local accepted = {}
    for _ = 1, count - 1 do
        local key = reader:Str() .. ":" .. reader:UInt()
        accepted[key] = reader:UInt()
    end
    return accepted
end

-- The guild's options (cf): a text of their own, empty for none (a field
-- after it, in a later version, would need it written), which starts with
-- the format's number.
local OPTIONS_FORMAT = 1

local function WriteFlags(writer, map)
    local keys = SortedKeys(map)
    writer:UInt(#keys)
    for _, key in ipairs(keys) do
        writer:Str(key)
        writer:UInt(map[key])
    end
end

local function ReadFlags(reader)
    local count = reader:UInt()
    if count > LIMITS.optionRanks then
        error("too many ranks", 0)
    end
    local map = {}
    for _ = 1, count do
        local key = reader:Str(LIMITS.rankName)
        map[key] = reader:UInt()
    end
    return map
end

local function WriteOptions(writer, options)
    if not options then
        writer:Str("")
        return
    end
    local inner = Pack.Writer()
    inner:UInt(OPTIONS_FORMAT)
    inner:UInt(options.t)
    inner:UInt(#options.bn)
    for _, name in ipairs(options.bn) do
        inner:Str(name)
    end
    WriteFlags(inner, options.rp)
    local banks = SortedKeys(options.bv)
    inner:UInt(#banks)
    for _, bank in ipairs(banks) do
        inner:Str(bank)
        WriteFlags(inner, options.bv[bank])
    end
    writer:Str(inner:Result())
end

local function ReadOptions(reader)
    local text = reader:Str(LIMITS.options)
    if text == "" then
        return nil
    end
    reader = Pack.Reader(text)
    if reader:UInt() ~= OPTIONS_FORMAT then
        -- Set by a later version, in a form this one does not know.
        return nil
    end
    local options = { t = reader:UInt(), bn = {}, bv = {} }
    local count = reader:UInt()
    if count > LIMITS.bankRanks then
        error("too many bank ranks", 0)
    end
    for index = 1, count do
        options.bn[index] = reader:Str(LIMITS.rankName)
    end
    options.rp = ReadFlags(reader)
    count = reader:UInt()
    if count > LIMITS.optionBanks then
        error("too many bank characters", 0)
    end
    for _ = 1, count do
        local bank = reader:Str()
        options.bv[bank] = ReadFlags(reader)
    end
    return options
end

-- Logs: oldest first, each time written as the gap from the one before,
-- which most often fits in one or two bytes.
local function WriteWhat(writer, entry)
    writer:UInt(entry.i or 0)
    if entry.i then
        writer:UInt(entry.n)
        writer:Str(entry.s or "")
    else
        writer:UInt(entry.m)
        -- The money left, plus one: 0 is unknown.
        writer:UInt(entry.r and entry.r + 1 or 0)
    end
end

local function ReadWhat(reader, entry)
    local itemID = reader:UInt()
    if itemID > 0 then
        entry.i, entry.n = itemID, reader:UInt()
        local text = reader:Str(LIMITS.item)
        entry.s = text ~= "" and text or nil
    else
        entry.m = reader:UInt()
        local left = reader:UInt()
        entry.r = left > 0 and left - 1 or nil
    end
end

local function WriteLog(writer, log)
    if not log then
        writer:UInt(0)
        return
    end
    writer:UInt(#log + 1)
    local previous = 0
    for _, entry in ipairs(log) do
        writer:UInt(math.max(entry.t - previous, 0))
        previous = math.max(entry.t, previous)
        writer:Byte(entry.a)
        writer:Byte(entry.v)
        writer:Str(entry.w or "")
        WriteWhat(writer, entry)
    end
end

local function ReadLog(reader)
    local count = reader:UInt()
    if count == 0 then
        return nil
    elseif count - 1 > LIMITS.log then
        error("too many log entries", 0)
    end
    local log, previous = {}, 0
    for i = 1, count - 1 do
        local entry = { t = previous + reader:UInt(), a = reader:Byte(), v = reader:Byte(), w = reader:Str(LIMITS.text) }
        previous = entry.t
        ReadWhat(reader, entry)
        log[i] = entry
    end
    return log
end

local function WriteGuildLog(writer, log)
    if not log then
        writer:Byte(ABSENT)
        return
    end
    writer:Byte(PRESENT)
    writer:UInt(log.t)
    writer:UInt(#log.tn)
    for _, name in ipairs(log.tn) do
        writer:Str(name)
    end
    writer:UInt(#log.e)
    local previous = 0
    for _, entry in ipairs(log.e) do
        writer:UInt(math.max(entry.t - previous, 0))
        previous = math.max(entry.t, previous)
        writer:Byte(entry.y)
        writer:Str(entry.w or "")
        WriteWhat(writer, entry)
        if entry.i then
            writer:Byte(entry.b or 0)
            writer:Byte(entry.d or 0)
        end
    end
end

local function ReadGuildLog(reader)
    local present = reader:Byte()
    if present == ABSENT then
        return nil
    elseif present ~= PRESENT then
        error("unknown guild log", 0)
    end
    local log = { t = reader:UInt(), tn = {}, e = {} }
    local tabs = reader:UInt()
    if tabs > LIMITS.tabs then
        error("too many tabs", 0)
    end
    for i = 1, tabs do
        log.tn[i] = reader:Str(LIMITS.text)
    end
    local count = reader:UInt()
    if count > LIMITS.guildLog then
        error("too many log entries", 0)
    end
    local previous = 0
    for i = 1, count do
        local entry = { t = previous + reader:UInt(), y = reader:Byte(), w = reader:Str(LIMITS.text) }
        previous = entry.t
        ReadWhat(reader, entry)
        if entry.i then
            local from, to = reader:Byte(), reader:Byte()
            entry.b = from > 0 and from or nil
            entry.d = to > 0 and to or nil
        end
        log.e[i] = entry
    end
    return log
end

-- The record's own bytes, without the length prefix.
local function RecordBody(guid, record)
    local writer = Pack.Writer()
    writer:Str(guid)
    writer:Str(record.n or "")
    writer:UInt(record.t)
    writer:UInt(record.av or 0)
    writer:Str(record.rl or "")
    WriteBank(writer, record.bk)
    WriteGuildMoney(writer, record.gb)
    WriteRequests(writer, record.rq)
    WriteAnswers(writer, record.ra)
    -- Since 0.3.0: older readers skip them.
    WriteLog(writer, record.lg)
    WriteGuildLog(writer, record.gl)
    -- Since 0.3.2: older readers skip it.
    WriteAccepted(writer, record.ac)
    -- Since 0.4.0: older readers skip it. Only when there are options (the
    -- guild master's record), so the others pack as they did before.
    if record.cf then
        WriteOptions(writer, record.cf)
    end
    return writer:Result()
end

function Pack.WriteRecord(writer, guid, record)
    writer:Str(RecordBody(guid, record))
end

-- The most a packed record may weigh, in bytes. Every version refuses
-- bigger ones, so it cannot grow.
Pack.MAX_RECORD = 20000

function Pack.RecordSize(guid, record)
    return #RecordBody(guid, record)
end

-- Returns guid, record. The record still has to be checked (Data.CleanRecord).
function Pack.ReadRecord(reader)
    local length = reader:UInt()
    if length > Pack.MAX_RECORD then
        error("record too long", 0)
    end
    reader = reader:Sub(length)
    local guid = reader:Str()
    local name = reader:Str()
    local record = { t = reader:UInt(), av = reader:UInt() }
    local realm = reader:Str()
    record.n = name ~= "" and name or nil
    record.rl = realm ~= "" and realm or nil
    record.bk = ReadBank(reader)
    record.gb = ReadGuildMoney(reader)
    record.rq = ReadRequests(reader)
    record.ra = ReadAnswers(reader)
    -- Records packed before 0.3.0 end here.
    if not reader:AtEnd() then
        record.lg = ReadLog(reader)
        record.gl = ReadGuildLog(reader)
    end
    -- Records packed before 0.3.2 end here.
    if not reader:AtEnd() then
        record.ac = ReadAccepted(reader)
    end
    -- Records packed before 0.4.0 end here.
    if not reader:AtEnd() then
        record.cf = ReadOptions(reader)
    end
    -- Anything left was added by a later version.
    return guid, record
end

