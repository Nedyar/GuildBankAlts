-- Pack.lua: the compact binary form records travel in, Base64, and hashing.
-- Plain Lua with no game API, so it can be tested outside the game.
local _, ns = ...

local Pack = {}
ns.Pack = Pack

local byte, char, floor, sub = string.byte, string.char, math.floor, string.sub
local concat = table.concat

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

local TWO_32 = 4294967296
local TWO_53 = 9007199254740992

-- Writer ---------------------------------------------------------------------

local Writer = {}
Writer.__index = Writer

function Pack.Writer()
    return setmetatable({ n = 0 }, Writer)
end

function Writer:Byte(value)
    self.n = self.n + 1
    self[self.n] = char(value)
end

-- Unsigned integers take 7 bits per byte (LEB128): 1 byte below 128, 2
-- below 16384, 3 below about two million (item IDs, for one).
function Writer:UInt(value)
    value = floor(value)
    if value < 0 or value >= TWO_53 then
        error("number out of range: " .. tostring(value), 2)
    end
    while value >= 128 do
        self:Byte(value % 128 + 128)
        value = floor(value / 128)
    end
    self:Byte(value)
end

-- Signed integers: 0, -1, 1, -2... become 0, 1, 2, 3...
function Writer:Int(value)
    value = floor(value)
    self:UInt(value >= 0 and value * 2 or -value * 2 - 1)
end

function Writer:Str(text)
    self:UInt(#text)
    self:Raw(text)
end

-- Appends bytes that are already packed.
function Writer:Raw(text)
    self.n = self.n + 1
    self[self.n] = text
end

function Writer:Size()
    local size = 0
    for i = 1, self.n do
        size = size + #self[i]
    end
    return size
end

function Writer:Result()
    return concat(self, "", 1, self.n)
end

-- Reader ---------------------------------------------------------------------

-- Every read raises on malformed input; callers read under pcall.
local Reader = {}
Reader.__index = Reader

function Pack.Reader(text)
    return setmetatable({ s = text, pos = 1, len = #text }, Reader)
end

function Reader:Byte()
    local value = byte(self.s, self.pos)
    if not value or self.pos > self.len then
        error("truncated message", 0)
    end
    self.pos = self.pos + 1
    return value
end

function Reader:UInt()
    local value, scale = 0, 1
    for _ = 1, 8 do
        local b = self:Byte()
        if b < 128 then
            return value + b * scale
        end
        value = value + (b - 128) * scale
        scale = scale * 128
    end
    error("malformed number", 0)
end

function Reader:Int()
    local value = self:UInt()
    if value % 2 == 0 then
        return value / 2
    end
    return -(value + 1) / 2
end

function Reader:Str(maxLength)
    local length = self:UInt()
    if length > (maxLength or Pack.LIMITS.text) then
        error("text too long", 0)
    end
    if self.pos + length - 1 > self.len then
        error("truncated message", 0)
    end
    local text = sub(self.s, self.pos, self.pos + length - 1)
    self.pos = self.pos + length
    return text
end

-- A reader over the next length bytes, which this reader skips.
function Reader:Sub(length)
    if self.pos + length - 1 > self.len then
        error("truncated message", 0)
    end
    local inner = Pack.Reader(sub(self.s, self.pos, self.pos + length - 1))
    self.pos = self.pos + length
    return inner
end

function Reader:AtEnd()
    return self.pos > self.len
end

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

function Pack.RecordString(key, record)
    local writer = Pack.Writer()
    Pack.WriteRecord(writer, key, record)
    return writer:Result()
end

-- Hashing --------------------------------------------------------------------

-- djb2, kept to 32 bits. Exact with Lua's doubles, so no bit library is needed.
function Pack.Hash(text, seed)
    local hash = seed or 5381
    for i = 1, #text do
        hash = (hash * 33 + byte(text, i)) % TWO_32
    end
    return hash
end

function Pack.AddHash(a, b)
    return (a + b) % TWO_32
end

-- Base64 ---------------------------------------------------------------------

-- The client's C_EncodingUtil does this natively; this version is the
-- fallback, and the digits are reused for the message headers.
local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local DIGIT, VALUE = {}, {}
for i = 1, 64 do
    local c = sub(ALPHABET, i, i)
    DIGIT[i - 1] = c
    VALUE[c] = i - 1
end

-- A single Base64 digit: 0..63 <-> one character.
function Pack.Digit(value)
    return DIGIT[value]
end

function Pack.DigitValue(c)
    return VALUE[c]
end

function Pack.ToBase64(text)
    local out = {}
    for i = 1, #text, 3 do
        local a, b, c = byte(text, i, i + 2)
        local n = a * 65536 + (b or 0) * 256 + (c or 0)
        out[#out + 1] = DIGIT[floor(n / 262144)] .. DIGIT[floor(n / 4096) % 64]
            .. (b and DIGIT[floor(n / 64) % 64] or "=") .. (c and DIGIT[n % 64] or "=")
    end
    return concat(out)
end

function Pack.FromBase64(text)
    if #text % 4 ~= 0 then
        return nil
    end
    local out = {}
    for i = 1, #text, 4 do
        local c1, c2, c3, c4 = sub(text, i, i), sub(text, i + 1, i + 1), sub(text, i + 2, i + 2), sub(text, i + 3, i + 3)
        local v1, v2 = VALUE[c1], VALUE[c2]
        local v3, v4 = VALUE[c3], VALUE[c4]
        if not v1 or not v2 or (not v3 and c3 ~= "=") or (not v4 and c4 ~= "=") then
            return nil
        end
        -- Padding only at the very end, and "x=y" is never valid.
        if (not v4 and i + 3 < #text) or (not v3 and v4) then
            return nil
        end
        local n = v1 * 262144 + v2 * 4096 + (v3 or 0) * 64 + (v4 or 0)
        out[#out + 1] = char(floor(n / 65536))
        if v3 then
            out[#out + 1] = char(floor(n / 256) % 256)
        end
        if v4 then
            out[#out + 1] = char(n % 256)
        end
    end
    return concat(out)
end
