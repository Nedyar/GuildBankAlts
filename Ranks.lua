-- Ranks.lua: who may do what with the guild bank, from the guild roster and
-- the guild's options (Options.lua).
--
-- The guild's options are its guild master's: they travel in the record of
-- the member the roster shows as guild master (rank index 0), cf (see
-- Pack.lua), and any other member's are ignored, so nobody else can set
-- them. They reach every member with the sync. Until the guild master sets
-- them, the defaults apply:
--   - bank characters: the characters with the rank "Banco";
--   - every rank may see the log and make requests, and the bank ranks and
--     the ranks named "Oficial" (or "Officer") may accept and reject them;
--   - every rank sees every bank character's items and money.
-- The guild master may do everything, and a bank character always sees
-- its own bank. A rank that may not see a bank character's items does not
-- see the requests made to it either, nor answers them, nor sees its items'
-- entries in the log; one that may not see its money, its money's entries.
-- Rank names are compared without regard to case or surrounding spaces.
--
-- These rights are the addon's own: what a member may not see still
-- reaches their client with the sync (no addon can keep it from them); the
-- addon does not show it, nor lets them do what they may not. Every client
-- decides from its own copy of the roster and of the options, so a change
-- of rank or of the options takes effect everywhere at the next roster read,
-- or once the guild master's record arrives. It applies to what was done
-- before too: an acceptance by a rank that may no longer accept no longer
-- counts.
local _, ns = ...

local Ranks = {}
ns.Ranks = Ranks

-- What a rank may do: flags added up (Ranks.RankFlags).
Ranks.LOG, Ranks.MAKE, Ranks.ACCEPT, Ranks.REJECT = 1, 2, 4, 8
Ranks.ALL = 15
-- What a rank may see of a bank character: flags added up (Ranks.BankFlags).
Ranks.ITEMS, Ranks.MONEY = 1, 2
Ranks.SEE_ALL = 3

Ranks.DEFAULT_BANK_RANKS = { "Banco" }
-- The ranks that may accept and reject requests by default, besides the
-- bank ranks.
local DEFAULT_ANSWERING = { oficial = true, officer = true }

function Ranks.Has(flags, flag)
    return math.floor(flags / flag) % 2 == 1
end

-- flags with flag on or off.
function Ranks.With(flags, flag, on)
    if Ranks.Has(flags, flag) == on then
        return flags
    end
    return on and flags + flag or flags - flag
end

-- A rank's name as the options compare it.
function Ranks.Key(name)
    return type(name) == "string" and strtrim(name):lower() or nil
end

local function RankKey(guid)
    local entry = guid and ns.Roster.members[guid]
    return entry and Ranks.Key(entry.rk)
end

-- The guild master ------------------------------------------------------------------------

local gm   -- the guild master's GUID, while the roster still says so

function Ranks.GM()
    local members = ns.Roster.members
    local entry = gm and members[gm]
    if entry and entry.ri == 0 then
        return gm
    end
    gm = nil
    for guid, member in pairs(members) do
        if member.ri == 0 then
            gm = guid
            break
        end
    end
    return gm
end

function Ranks.IsGM(guid)
    local entry = guid and ns.Roster.members[guid]
    return entry ~= nil and entry.ri == 0
end

-- The guild's options: { t, bn = bank rank names, rp = { [rank] = flags },
-- bv = { [bank character] = { [rank] = flags } } }, as the guild master
-- set them; nil while they have not (the defaults apply).
function Ranks.Options()
    local guid = Ranks.GM()
    local guild = guid and ns.Data.CurrentGuild(false)
    local record = guild and guild.members[guid]
    return record and record.cf or nil
end

-- Bank characters -------------------------------------------------------------------------

local bankSets = setmetatable({}, { __mode = "k" })
local defaultSet

local function BankSet(options)
    if not options then
        if not defaultSet then
            defaultSet = {}
            for _, name in ipairs(Ranks.DEFAULT_BANK_RANKS) do
                defaultSet[Ranks.Key(name)] = true
            end
        end
        return defaultSet
    end
    local set = bankSets[options]
    if not set then
        set = {}
        for _, name in ipairs(options.bn or {}) do
            set[Ranks.Key(name)] = true
        end
        bankSets[options] = set
    end
    return set
end

-- The bank ranks' names, as the options list them.
function Ranks.BankRanks()
    local options = Ranks.Options()
    local list = {}
    for index, name in ipairs(options and options.bn or Ranks.DEFAULT_BANK_RANKS) do
        list[index] = name
    end
    return list
end

-- A guild bank character.
function Ranks.IsBank(guid)
    local key = RankKey(guid)
    return key ~= nil and BankSet(Ranks.Options())[key] == true
end

-- What ranks may do --------------------------------------------------------------------------

local function RankFlagsIn(options, key)
    local flags = options and options.rp and options.rp[key]
    if flags then
        return flags
    end
    local answering = BankSet(options)[key] or DEFAULT_ANSWERING[key]
    return Ranks.LOG + Ranks.MAKE + (answering and Ranks.ACCEPT + Ranks.REJECT or 0)
end

-- What a rank may do (Ranks.LOG...).
function Ranks.RankFlags(name)
    return RankFlagsIn(Ranks.Options(), Ranks.Key(name))
end

-- Whether a member may do something (Ranks.LOG, MAKE, ACCEPT or REJECT).
function Ranks.Can(guid, flag)
    if Ranks.IsGM(guid) then
        return true
    end
    local key = RankKey(guid)
    return key ~= nil and Ranks.Has(RankFlagsIn(Ranks.Options(), key), flag)
end

function Ranks.CanAccept(guid)
    return Ranks.Can(guid, Ranks.ACCEPT)
end

function Ranks.CanReject(guid)
    return Ranks.Can(guid, Ranks.REJECT)
end

local function BankFlagsIn(options, bank, key)
    local byRank = options and options.bv and options.bv[bank]
    return byRank and byRank[key] or Ranks.SEE_ALL
end

-- What a rank may see of a bank character (Ranks.ITEMS, MONEY).
function Ranks.BankFlags(bank, name)
    return BankFlagsIn(Ranks.Options(), bank, Ranks.Key(name))
end

-- Whether a member may see a bank character's items (Ranks.ITEMS) or money
-- (Ranks.MONEY).
function Ranks.CanSee(guid, bank, flag)
    if guid == bank or Ranks.IsGM(guid) then
        return true
    end
    local key = RankKey(guid)
    return key ~= nil and Ranks.Has(BankFlagsIn(Ranks.Options(), bank, key), flag)
end

-- Whether a member may answer (Ranks.ACCEPT or REJECT) the requests made to
-- a bank character: their rank may give that answer, and see its items,
-- which the requests are for.
function Ranks.MayAnswer(guid, bank, flag)
    return Ranks.Can(guid, flag) and Ranks.CanSee(guid, bank, Ranks.ITEMS)
end

-- The guild's ranks, from the top: { { index (0: guild master), name, key } }.
-- From the game's guild control; without it, from the roster (the ranks
-- someone has).
function Ranks.GuildRanks()
    local list = {}
    local count = GuildControlGetNumRanks and ns.Number(ns.Try(GuildControlGetNumRanks)) or 0
    for index = 1, count do
        local name = ns.Plain(ns.Try(GuildControlGetRankName, index))
        if type(name) == "string" and name ~= "" then
            list[#list + 1] = { index = index - 1, name = name, key = Ranks.Key(name) }
        end
    end
    if #list > 0 then
        return list
    end
    local seen = {}
    for _, member in pairs(ns.Roster.members) do
        if type(member.ri) == "number" and type(member.rk) == "string" and not seen[member.ri] then
            seen[member.ri] = true
            list[#list + 1] = { index = member.ri, name = member.rk, key = Ranks.Key(member.rk) }
        end
    end
    table.sort(list, function(a, b)
        return a.index < b.index
    end)
    return list
end

-- Changing the options (the guild master only) -----------------------------------------------

function Ranks.MayEdit()
    return ns.playerGUID ~= nil and Ranks.IsGM(ns.playerGUID)
end

-- A copy of the options in force, all of it explicit but the ranks'
-- defaults: what an edit starts from. Not the ranks the guild no longer
-- has, nor the bank characters no longer in it.
local function Copy(options)
    local copy = { bn = {}, rp = {}, bv = {} }
    for index, name in ipairs(options and options.bn or Ranks.DEFAULT_BANK_RANKS) do
        copy.bn[index] = name
    end
    local ranks = {}
    for _, rank in ipairs(Ranks.GuildRanks()) do
        ranks[rank.key] = true
    end
    local known = next(ranks) ~= nil
    for key, flags in pairs(options and options.rp or {}) do
        if not known or ranks[key] then
            copy.rp[key] = flags
        end
    end
    for bank, byRank in pairs(options and options.bv or {}) do
        if ns.Roster.members[bank] then
            copy.bv[bank] = {}
            for key, flags in pairs(byRank) do
                if not known or ranks[key] then
                    copy.bv[bank][key] = flags
                end
            end
        end
    end
    return copy
end

-- Changes the guild's options, as its guild master: change(options) edits
-- a copy of them, which replaces them in our record, shared with the guild.
-- Returns whether it could.
function Ranks.Edit(change)
    if not Ranks.MayEdit() then
        return false
    end
    local record = ns.Data.GetOwnRecord(true)
    if not record then
        return false
    end
    local options = Copy(Ranks.Options())
    change(options)
    options.t = math.max(ns.Now(), (record.cf and record.cf.t or 0) + 1)
    record.cf = options
    ns.Data.TouchOwn(record)
    return true
end

function Ranks.SetRankFlag(name, flag, on)
    local key = Ranks.Key(name)
    return Ranks.Edit(function(options)
        options.rp[key] = Ranks.With(RankFlagsIn(options, key), flag, on)
    end)
end

function Ranks.SetBankFlag(bank, name, flag, on)
    local key = Ranks.Key(name)
    return Ranks.Edit(function(options)
        options.bv[bank] = options.bv[bank] or {}
        options.bv[bank][key] = Ranks.With(BankFlagsIn(options, bank, key), flag, on)
    end)
end

-- A bank rank's name as typed: trimmed. Returns it, or nil and why:
-- "empty", "invalid" (too long, or with escape sequences), "duplicate" or
-- "full".
function Ranks.CheckBankRank(name)
    name = type(name) == "string" and strtrim(name) or ""
    if name == "" then
        return nil, "empty"
    elseif #name > ns.Pack.LIMITS.rankName or name:find("[|%c]") then
        return nil, "invalid"
    end
    local names = Ranks.BankRanks()
    for _, other in ipairs(names) do
        if Ranks.Key(other) == Ranks.Key(name) then
            return nil, "duplicate"
        end
    end
    if #names >= ns.Pack.LIMITS.bankRanks then
        return nil, "full"
    end
    return name
end

-- Returns true, or false and why (Ranks.CheckBankRank's, or "guildmaster").
function Ranks.AddBankRank(name)
    if not Ranks.MayEdit() then
        return false, "guildmaster"
    end
    local checked, why = Ranks.CheckBankRank(name)
    if not checked then
        return false, why
    end
    return Ranks.Edit(function(options)
        options.bn[#options.bn + 1] = checked
    end)
end

-- The last one stays: without a bank rank there would be no bank.
function Ranks.RemoveBankRank(name)
    local key = Ranks.Key(name)
    if #Ranks.BankRanks() <= 1 then
        return false
    end
    return Ranks.Edit(function(options)
        for index, other in ipairs(options.bn) do
            if Ranks.Key(other) == key then
                table.remove(options.bn, index)
                break
            end
        end
    end)
end
