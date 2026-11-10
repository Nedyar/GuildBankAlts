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
--       n = items delivered, u = when it last changed } }.
-- rq and ra are nil until known: a client that lost its data does not tell
-- the guild it has none.
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
    return writer:Result()
end

function Pack.WriteRecord(writer, guid, record)
    writer:Str(RecordBody(guid, record))
end

local MAX_RECORD = 20000

-- Returns guid, record. The record still has to be checked (Data.CleanRecord).
function Pack.ReadRecord(reader)
    local length = reader:UInt()
    if length > MAX_RECORD then
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
    -- Anything left was added by a later version.
    return guid, record
end

