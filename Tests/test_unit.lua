local H = ...

-- A single client gives access to the addon's modules.
local world = H.NewWorld({ seed = 1 })
local solo = world:NewClient("Solo Name")
world:Login(solo)
world:RunFor(30)
local ns = solo.ns
local Pack, Data = ns.Pack, ns.Data
local now = ns.Now()

H.section("Loading")
H.eq(#world.errors, 0, "no errors while loading and starting")
for _, err in ipairs(world.errors) do
    print("   " .. err)
end

H.section("Pack: records")
local GUID, OTHER = "Player-1-0000000A", "Player-1-0000000B"
local record = {
    n = "Solo Name", rl = "TestRealm", t = now, av = 100,
    bk = {
        m = 1234, bt = now, kt = now,
        b = { { id = 0, z = 16, s = { [1] = { i = 2589, n = 20 } } } },
        k = { { id = 6, z = 48, s = {} } },
    },
    gb = { m = 99999, t = now },
    rq = { [3] = { b = OTHER, i = 2589, q = 5, c = now, nt = "please", d = 1 } },
    ra = { [OTHER .. ":2"] = { s = 1, n = 0, u = now } },
}
local key, back = Pack.ReadRecord(Pack.Reader(Pack.RecordString(GUID, record)))
H.eq(key, GUID, "record key (the GUID)")
H.check(ns.Same(back, record), "record round trip, every field")
local bare = { t = now }
_, back = Pack.ReadRecord(Pack.Reader(Pack.RecordString(GUID, bare)))
H.check(back.bk == nil and back.gb == nil and back.rq == nil and back.ra == nil and back.n == nil and back.rl == nil,
    "a member's record with nothing yet: every part stays unknown")

-- A later version's extra fields are skipped, and the next record still reads.
local body = Pack.RecordString(GUID, record)
local reader = Pack.Reader(body)
local length = reader:UInt()
local longer = Pack.Writer()
longer:Str(body:sub(reader.pos, reader.pos + length - 1) .. "\1\2\3")
longer:Raw(Pack.RecordString(OTHER, bare))
reader = Pack.Reader(longer:Result())
key = Pack.ReadRecord(reader)
H.eq(key, GUID, "a record with fields from a later version reads")
H.eq((Pack.ReadRecord(reader)), OTHER, "the record after it reads too")
H.check(reader:AtEnd(), "batch fully read")
local huge = Pack.Writer()
huge:UInt(30000)
H.check(not pcall(Pack.ReadRecord, Pack.Reader(huge:Result() .. ("x"):rep(30000))), "oversized record refused")

H.section("Data: checking records")
H.check(Data.CleanRecord(record) ~= nil, "a good record passes")
local function Broken(change)
    local copy = H.DeepCopy(record)
    change(copy)
    return Data.CleanRecord(copy, now) == nil
end
H.check(Broken(function(r) r.t = now + 3600 end), "record from the future refused")
H.check(Broken(function(r) r.t = 1000 end), "record from before 2020 refused")
H.check(Broken(function(r) r.bk = "x" end), "bad bank data refused")
H.check(Broken(function(r) r.rq = { [0] = r.rq[3] } end), "a request with a bad ID refused")
local copy = H.DeepCopy(record)
copy.n = "Evil|cffff0000Name"
H.eq(Data.CleanRecord(copy, now).n, "Evilcffff0000Name", "escape sequences stripped from names")

H.section("Data: merging")
local guild = { members = {} }
local function Rec(t, extra)
    local r = { t = t }
    for k, v in pairs(extra or {}) do
        r[k] = v
    end
    return r
end
Data.MergeRecord(guild, OTHER, Rec(now - 100, { rq = { [1] = { b = GUID, i = 1, q = 1, c = now - 100, nt = "" } } }), false)
H.check(not Data.MergeRecord(guild, OTHER, Rec(now - 200), false), "an older copy loses")
Data.MergeRecord(guild, OTHER, Rec(now - 50), true)
H.eq(guild.members[OTHER].t, now - 50, "a newer copy wins")
H.check(guild.members[OTHER].rq ~= nil, "it keeps the requests only the older copy knew")
H.check(Data.MergeRecord(guild, OTHER, Rec(now - 50, { gb = { m = 1, t = now }, rq = {} }), false), "at the same time, the more complete copy wins")
H.check(not Data.MergeRecord(guild, OTHER, Rec(now - 50), false), "and a less complete one loses")

H.section("Data: saved form")
local db = ns.db
local savedGuild = Data.GetGuild("Test Guild", true)
savedGuild.members[GUID] = Data.CleanRecord(record)
local packed = H.DeepCopy(db)
Data.PackForSave(packed)
H.eq(type(packed.guilds["Test Guild"].members[GUID].b), "string", "records are saved packed")
local loaded = Data.Sanitize(packed)
H.check(ns.Same(loaded.guilds["Test Guild"].members[GUID].bk, record.bk), "bank data survives saving")
H.check(ns.Same(loaded.guilds["Test Guild"].members[GUID].rq, record.rq), "requests survive saving")
local garbage = H.DeepCopy(packed)
garbage.guilds["Test Guild"].members[GUID] = { b = "!!!" }
garbage.guilds["Test Guild"].members["Player-1-0000000F"] = packed.guilds["Test Guild"].members[GUID]
loaded = Data.Sanitize(garbage)
H.check(loaded.guilds["Test Guild"].members[GUID] == nil, "an unreadable saved record is dropped")
H.check(loaded.guilds["Test Guild"].members["Player-1-0000000F"] == nil, "a record saved under another GUID is dropped")
H.check(next(Data.Sanitize("nonsense").guilds) == nil, "a broken database starts empty")

H.section("Own record")
local own = Data.GetOwnRecord(false)
H.check(own ~= nil and Data.IsShareable(own), "a member's record is stamped at login, though it has nothing to share yet")
H.eq(own and own.av, ns.VERSION_NUM, "with the addon's version")
H.eq(own and own.n, "Solo Name", "and the character's name")
H.eq(own and own.bk, nil, "a member who is not a bank character shares no bank data")
H.check(ns.Bank.ready, "our record is ready to be announced")

H.section("Locales")
local function ReadKeys(path)
    local keys = {}
    for _, file in ipairs(path) do
        local handle = io.open(H.ADDON .. "/" .. file, "rb")
        local text = handle:read("*a")
        handle:close()
        for k in text:gmatch('L%["(.-)"%]') do
            keys[k] = true
        end
    end
    return keys
end
local codeFiles = {}
for _, file in ipairs(H.FILES) do
    if not file:find("^Locales/") then
        codeFiles[#codeFiles + 1] = file
    end
end
local codeKeys = ReadKeys(codeFiles)
local function Specifiers(text)
    local list = {}
    for spec in text:gmatch("%%[%d%.]*[sdf]") do
        list[#list + 1] = spec
    end
    return table.concat(list, " ")
end
for _, locale in ipairs({ "deDE", "esES", "frFR", "itIT", "koKR", "ptBR", "ruRU", "zhCN", "zhTW" }) do
    local texts = {}
    local env = setmetatable({}, { __index = _G })
    local chunk = assert(loadfile(H.ADDON .. "/Locales/" .. locale .. ".lua"))
    setfenv(chunk, env)
    chunk("GuildBankAlts", { RegisterLocale = function(_, fill) fill(texts) end })
    local missing, extra, badSpecs = {}, {}, {}
    for k in pairs(codeKeys) do
        if texts[k] == nil then
            missing[#missing + 1] = k
        end
    end
    for k, v in pairs(texts) do
        if not codeKeys[k] then
            extra[#extra + 1] = k
        elseif Specifiers(k) ~= Specifiers(v) then
            badSpecs[#badSpecs + 1] = k
        end
    end
    H.check(#missing == 0, locale .. " has every text" .. (#missing > 0 and (": missing " .. table.concat(missing, " | ")) or ""))
    H.check(#extra == 0, locale .. " has no unused text" .. (#extra > 0 and (": " .. table.concat(extra, " | ")) or ""))
    H.check(#badSpecs == 0, locale .. " keeps the format specifiers" .. (#badSpecs > 0 and (": " .. table.concat(badSpecs, " | ")) or ""))
end

H.section("Release files")
local function Read(path)
    local handle = io.open(H.ADDON .. "/" .. path, "rb")
    if not handle then
        return nil
    end
    local text = handle:read("*a")
    handle:close()
    return text
end
local toc = Read("GuildBankAlts.toc")
local changelog = Read("CHANGELOG.md")
local tocVersion = toc:match("## Version: ([%d%.]+)")
H.check(changelog ~= nil and changelog:match("## ([%d%.]+)") == tocVersion, "the TOC version is the changelog's newest")
local pkgmeta = Read(".pkgmeta")
H.check(pkgmeta ~= nil and pkgmeta:find("package%-as: GuildBankAlts") ~= nil, ".pkgmeta packages the folder as GuildBankAlts")
H.check(pkgmeta ~= nil and pkgmeta:find("\n    %- Tests\n") ~= nil, ".pkgmeta leaves the tests out of the package")
H.check(pkgmeta ~= nil and pkgmeta:find("required%-dependencies:\n    %- lib%-guild%-sync\n") ~= nil,
    ".pkgmeta makes LibGuildSync a required relation on CurseForge")
H.check(toc:find("## SavedVariables: GuildBankAltsDB", 1, true) ~= nil, "the saved variables are declared")
H.check(toc:find("## Dependencies: LibGuildSync", 1, true) ~= nil, "LibGuildSync is a dependency")
for _, file in ipairs(H.FILES) do
    H.check(Read(file) ~= nil, "the TOC's file exists: " .. file)
end
local announced = Read("Core.lua"):match('\nlocal ANNOUNCE_AS = "([%d%.]+)"')
if announced then
    print(("  NOTE: Core.lua tells the guild this is %s: set ANNOUNCE_AS to nil before tagging a release"):format(announced))
end
if Read("Core.lua"):find("\n    trial = true,", 1, true) then
    print("  NOTE: trial is on in Core.lua: turn it off before tagging a release")
end
