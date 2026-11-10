-- Data.lua: the saved database and the rules that merge what different
-- clients know into one view.
--
-- GuildBankAltsDB = {
--   schema = 1,
--   guilds = { ["Guild Name"] = {
--       seen = time,
--       members = { ["Player-1234-0ABCDEF0"] = record (see Pack.lua; on disk
--           it is packed, see Data.PackForSave) plus two local fields:
--               seen = last time the member was in the roster,
--               fh = true when the copy came from the member themselves } } },
--   settings = { locale },
--   own = { [GUID] = { sentFP, sentGuild, lastRequest, requestStates } },
-- }
--
-- Members are known by GUID: WoW Forever names have spaces, the guild roster
-- gives them without a realm, and members of one guild live on different
-- realms. Guilds are known by name alone, because the realm the client gives
-- for a guild changes while the login loads.
--
-- Only a record's owner ever changes its contents, and the owner stamps each
-- change with a time (t) that always grows. Every client therefore keeps,
-- for each member, the copy that is newest (then the most complete), and
-- all clients end up with the same one.
local _, ns = ...
local Pack = ns.Pack

local Data = {}
ns.Data = Data

Data.SCHEMA = 1
Data.BUCKETS = 16

local DAY = 86400
local MEMBER_TTL = 30 * DAY   -- members unseen in the roster this long are dropped
local GUILD_TTL = 180 * DAY   -- guilds not visited this long are dropped
local MIN_TIME = 1600000000   -- September 2020: older times are bogus
local FUTURE_SLACK = 300      -- how far a record's time may run ahead of ours

local LIMITS = Pack.LIMITS

local floor = math.floor

-- Checks -------------------------------------------------------------------

local function IsCount(value, max)
    return type(value) == "number" and value >= 0 and value <= max and value == floor(value)
end

local function IsID(value)
    return type(value) == "number" and value > 0 and value < 2147483648 and value == floor(value)
end

function Data.IsGUID(guid)
    return type(guid) == "string" and #guid <= LIMITS.text and guid:find("^Player%-%d+%-%x+$") ~= nil
end

local function IsGuildKey(key)
    return type(key) == "string" and key ~= "" and #key <= LIMITS.text and not key:find("|", 1, true)
end

-- A name as given by another client, safe to show: no escape sequences.
function Data.CleanName(name)
    if type(name) ~= "string" then
        return nil
    end
    name = name:gsub("[|%c]", "")
    if name == "" or #name > LIMITS.text then
        return nil
    end
    return name
end

-- Records whose owner never stamped them are not shared or compared.
function Data.IsShareable(record)
    return record ~= nil and record.t >= MIN_TIME
end

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

local function IsTime(value)
    return type(value) == "number" and value == floor(value) and value >= MIN_TIME and value < 1e12
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

-- A checked copy of a record, or nil when it cannot be trusted. now is given
-- for records from other clients, which may not be dated in the future.
function Data.CleanRecord(record, now)
    if type(record) ~= "table" then
        return nil
    end
    local t = record.t
    if type(t) ~= "number" or t ~= t or t < MIN_TIME or t >= 1e12 or (now and t > now + FUTURE_SLACK) then
        return nil
    end
    local clean = {
        t = floor(t),
        av = IsCount(record.av, 999999) and record.av or 0,
        n = Data.CleanName(record.n),
        rl = Data.CleanName(record.rl),
    }
    for field, cleaner in pairs({ bk = CleanBank, rq = CleanRequests, ra = CleanAnswers, gb = CleanGuildMoney }) do
        if record[field] ~= nil then
            clean[field] = cleaner(record[field])
            if not clean[field] then
                return nil
            end
        end
    end
    if type(record.seen) == "number" then
        clean.seen = record.seen
    end
    if record.fh == true then
        clean.fh = true
    end
    return clean
end

-- Comparing and merging --------------------------------------------------------

-- The parts of a record a copy may lack: one point each.
local PARTS = { "bk", "gb", "rq", "ra" }

-- How complete a record is: how many of its parts are known.
function Data.Stats(record)
    local parts = 0
    for _, field in ipairs(PARTS) do
        if record[field] ~= nil then
            parts = parts + 1
        end
    end
    return parts
end

-- Positive when the first copy is the one to keep: the newer one, then the
-- more complete. Each side is t and parts.
function Data.CompareStats(t1, parts1, t2, parts2)
    if t1 ~= t2 then
        return t1 > t2 and 1 or -1
    end
    if parts1 ~= parts2 then
        return parts1 > parts2 and 1 or -1
    end
    return 0
end

function Data.Compare(a, b)
    return Data.CompareStats(a.t, Data.Stats(a), b.t, Data.Stats(b))
end

-- The copy kept of a member takes the requests and answers only the other
-- copy knows: the owner lost its data and has not seen the guild's copy
-- yet. Returns true if it took any.
local function CarryMissing(kept, other)
    local changed = false
    for _, field in ipairs({ "rq", "ra" }) do
        if kept[field] == nil and other[field] ~= nil then
            kept[field] = other[field]
            changed = true
        end
    end
    kept.n = kept.n or other.n
    kept.rl = kept.rl or other.rl
    return changed
end

-- Our own record is only ever changed by us, but if we lost our requests
-- and answers, a copy coming back from the guild fills them in.
local function AdoptOwnLists(own, record)
    local changed = false
    for _, field in ipairs({ "rq", "ra" }) do
        if own[field] == nil and record[field] ~= nil then
            own[field] = record[field]
            changed = true
        end
    end
    return changed
end

-- Stores a cleaned record. firsthand: it came from its owner, so it replaces
-- any older copy. Returns true when the stored data changed.
function Data.MergeRecord(guild, guid, record, firsthand)
    local old = guild.members[guid]
    if old and guid == ns.playerGUID then
        return AdoptOwnLists(old, record)
    end
    if old then
        local wins
        if firsthand then
            wins = record.t >= old.t
        else
            wins = Data.Compare(record, old) > 0
        end
        if not wins then
            return CarryMissing(old, record)
        end
        CarryMissing(record, old)
    end
    record.seen = math.max(record.seen or 0, old and old.seen or 0, ns.Now())
    record.fh = firsthand or nil
    guild.members[guid] = record
    return true
end

-- The guild database ----------------------------------------------------------

local function NewDB()
    return { schema = Data.SCHEMA, guilds = {}, settings = {}, own = {} }
end

-- Keeps the better of two copies of a member (both cleaned).
local function MergeCopies(members, guid, record)
    local old = members[guid]
    if not old or Data.Compare(record, old) > 0 then
        if old then
            CarryMissing(record, old)
            record.seen = math.max(record.seen or 0, old.seen or 0)
        end
        members[guid] = record
    else
        CarryMissing(old, record)
        old.seen = math.max(old.seen or 0, record.seen or 0)
    end
end

-- Records are saved packed (see Data.PackForSave): the client
-- writes each number of a plain table on its own line, ten times the size.
local function UnpackRecord(saved)
    if type(saved) ~= "table" or type(saved.b) ~= "string" then
        return nil
    end
    local raw = Pack.FromBase64(saved.b)
    if not raw then
        return nil
    end
    local ok, guid, record = pcall(Pack.ReadRecord, Pack.Reader(raw))
    if not ok or type(record) ~= "table" then
        return nil
    end
    record.seen, record.fh = saved.seen, saved.fh
    return guid, record
end


-- Checks a database read from disk and returns a clean copy.
function Data.Sanitize(db)
    local clean = NewDB()
    if type(db) ~= "table" then
        return clean
    end
    if type(db.guilds) == "table" then
        for guildKey, guild in pairs(db.guilds) do
            if IsGuildKey(guildKey) and type(guild) == "table" then
                local cleanGuild = { seen = type(guild.seen) == "number" and guild.seen or 0, members = {} }
                if type(guild.members) == "table" then
                    for key, saved in pairs(guild.members) do
                        local guid, record = UnpackRecord(saved)
                        local cleanRecord = guid == key and Data.IsGUID(guid) and Data.CleanRecord(record)
                        if cleanRecord then
                            MergeCopies(cleanGuild.members, guid, cleanRecord)
                        end
                    end
                end
                clean.guilds[guildKey] = cleanGuild
            end
        end
    end
    if type(db.settings) == "table" then
        clean.settings = db.settings
    end
    if type(db.own) == "table" then
        for guid, state in pairs(db.own) do
            if Data.IsGUID(guid) and type(state) == "table" then
                clean.own[guid] = state
            end
        end
    end
    return clean
end

-- Runs at ADDON_LOADED, once the client has loaded the saved variables.
function Data.Load()
    local native = GuildBankAltsDB
    ns.loadInfo = { native = type(native) == "table" }
    local db = Data.Sanitize(native)
    GuildBankAltsDB = db
    ns.db = db
end

-- Runs at logout, right before the client writes the saved variables.
function Data.PackForSave(db)
    for _, guild in pairs(db.guilds) do
        for guid, record in pairs(guild.members) do
            if record.b == nil then
                guild.members[guid] = { b = Pack.ToBase64(Pack.RecordString(guid, record)), seen = record.seen, fh = record.fh }
            end
        end
    end
end

function Data.GetGuild(guildKey, create)
    if not guildKey then
        return nil
    end
    local guild = ns.db.guilds[guildKey]
    if not guild and create then
        guild = { seen = ns.Now(), members = {} }
        ns.db.guilds[guildKey] = guild
    end
    return guild
end

function Data.CurrentGuild(create)
    return Data.GetGuild(ns.Roster.guildKey, create)
end

function Data.ResetGuild(guildKey)
    local guild = Data.GetGuild(guildKey)
    if not guild then
        return
    end
    -- Our own record stays: only we can tell our requests and answers.
    local own = ns.playerGUID and guild.members[ns.playerGUID]
    wipe(guild.members)
    if own then
        guild.members[ns.playerGUID] = own
    end
    Data.Changed(guild)
end

-- Lookups that are rebuilt whenever the data changes (never saved).
local digestCache = setmetatable({}, { __mode = "k" })

-- Every change to a guild's data ends here.
function Data.Changed(guild)
    if guild then
        digestCache[guild] = nil
    end
    ns.Debounce("DataChanged", 0.2, function()
        ns.Fire("DataChanged")
    end)
end

function Data.ForgetDigests()
    wipe(digestCache)
end

-- A record received from another client. firsthand: sent by its owner.
function Data.Accept(guildKey, guid, record, firsthand)
    if not Data.IsGUID(guid) then
        return false
    end
    record = Data.CleanRecord(record, ns.Now())
    if not record then
        ns.Debug("rejected the record of %s", guid)
        return false
    end
    local guild = Data.GetGuild(guildKey, true)
    local changed = Data.MergeRecord(guild, guid, record, firsthand)
    if changed then
        Data.Changed(guild)
        ns.Fire("RecordChanged", guid, guild.members[guid])
        if guid == ns.playerGUID then
            ns.Fire("OwnChanged")
        end
    end
    return changed
end

-- The name to show for a member: the roster's, else the one they shared.
function Data.NameOf(guid, record)
    return ns.Roster.NameOf(guid) or (record and record.n) or guid
end

-- Finds a member by what the user typed ("Name", "name", "Name-Realm"):
-- the roster's names first, then the names members shared. Returns the GUID.
function Data.FindByName(guild, text)
    local wanted = strtrim(text):match("^([^%-]+)") or text
    wanted = strtrim(wanted):lower()
    for guid, member in pairs(ns.Roster.members) do
        if member.n and member.n:lower() == wanted then
            return guid
        end
    end
    for guid, record in pairs(guild and guild.members or {}) do
        if record.n and record.n:lower() == wanted then
            return guid
        end
    end
end

-- After a complete roster read: members present are marked as seen,
-- members gone for a month are dropped, and so are guilds unvisited for
-- half a year.
function Data.Prune(guildKey, present)
    local guild = Data.GetGuild(guildKey, true)
    local now = ns.Now()
    local changed = false
    guild.seen = now
    for guid, record in pairs(guild.members) do
        if present[guid] then
            record.seen = now
        elseif (record.seen or record.t) < now - MEMBER_TTL then
            guild.members[guid] = nil
            changed = true
        end
    end
    for otherKey, other in pairs(ns.db.guilds) do
        if otherKey ~= guildKey and other.seen < now - GUILD_TTL then
            ns.db.guilds[otherKey] = nil
        end
    end
    if changed then
        Data.Changed(guild)
    end
end

-- Our own record ----------------------------------------------------------------

-- The current character's record in the current guild. create: make it when
-- missing (requests and answers belong to one guild, so nothing is taken
-- from another guild's copy).
function Data.GetOwnRecord(create)
    local guild = Data.CurrentGuild(create)
    if not guild or not ns.playerGUID then
        return nil
    end
    local record = guild.members[ns.playerGUID]
    if not record and create then
        record = { t = 0 }
        guild.members[ns.playerGUID] = record
    end
    return record
end

-- Stamps a change to our own record.
function Data.TouchOwn(record)
    local now = ns.Now()
    record.t = math.max(now, (record.t or 0) + 1)
    record.av = ns.VERSION_NUM
    record.n = Data.CleanName(ns.playerName) or record.n
    record.rl = Data.CleanName(ns.realm) or record.rl
    record.fh = true
    record.seen = now
    local guild = Data.CurrentGuild()
    Data.Changed(guild)
    ns.Fire("RecordChanged", ns.playerGUID, record)
    ns.Fire("OwnChanged")
end

function Data.OwnState()
    local state = ns.db.own[ns.playerGUID]
    if not state then
        state = {}
        ns.db.own[ns.playerGUID] = state
    end
    return state
end


-- Sync helpers ----------------------------------------------------------------

function Data.BucketOf(guid)
    return Pack.Hash(guid) % Data.BUCKETS + 1
end

-- Identifies one version of a member's record.
function Data.VersionHash(guid, t, parts)
    return Pack.Hash(guid .. "|" .. t .. "|" .. parts)
end

function Data.Fingerprint(guid, record)
    return Pack.Hash(Pack.RecordString(guid, record))
end

-- The records worth comparing with other clients: shareable ones of members
-- who are still in the guild.
function Data.ForEachShared(guild, callback)
    for guid, record in pairs(guild.members) do
        if Data.IsShareable(record) and ns.Roster.IsKnownGUID(guid) then
            callback(guid, record)
        end
    end
end

-- One number per bucket summing up the versions of the records in it. Two
-- clients with the same digests hold the same data.
function Data.Digests(guild)
    local cached = digestCache[guild]
    if cached then
        return cached.digests, cached.count
    end
    local digests, count = {}, 0
    for i = 1, Data.BUCKETS do
        digests[i] = 0
    end
    Data.ForEachShared(guild, function(guid, record)
        local bucket = Data.BucketOf(guid)
        digests[bucket] = Pack.AddHash(digests[bucket], Data.VersionHash(guid, record.t, Data.Stats(record)))
        count = count + 1
    end)
    digestCache[guild] = { digests = digests, count = count }
    return digests, count
end
