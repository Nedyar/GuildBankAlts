-- Log.lua: what comes into the guild's bank and what goes out of it, as a
-- log like the game's own guild bank log (its Log and Money Log tabs). The
-- Log subtab shows it (LogView.lua). It has two sources, told apart:
--   - the bank characters: each one's client writes down the items and
--     money it trades and mails, both ways, and with whom, in its record
--     (lg, see Pack.lua). Deliveries.lua reads the trades and the mail;
--   - the guild vault, the game's own guild bank: any member at a guild
--     vault reads its log as the game gives it (the last entries of each
--     tab and of its money, with how long ago to the hour) and keeps it in
--     their record (gl), together with what the guild knew of it before,
--     so the log reaches further back than the game's.
-- The same vault entry read by several members, or twice, is told once:
-- entries alike (same type, name, item or money, tabs) whose times are close
-- are the same entry.
-- A bank character that puts money into the vault or takes it out writes it
-- down too (via Log.VAULT), with the money it had: the vault's line then
-- tells both, and the bank character's is not listed apart (see Log.Lines).
local _, ns = ...
local Data, Pack = ns.Data, ns.Pack
local LIMITS = Pack.LIMITS

local Log = {}
ns.Log = Log

Log.IN, Log.OUT = 1, 2
Log.TRADE, Log.MAIL, Log.COD, Log.RETURNED, Log.VAULT, Log.POSTAGE = 1, 2, 3, 4, 5, 6
Log.VAULT_TYPES = Pack.VAULT_TYPES

local HOUR, DAY = 3600, 86400
-- How far apart two reads of the same vault entry may place it: the game
-- gives its age in whole hours, and in months for old ones.
local SAME_ENTRY, SAME_OLD_ENTRY, OLD = 2 * HOUR, 3 * DAY, 30 * DAY
-- How far a bank character's own time of its money at the vault may be from
-- the vault's: the vault's is off by half an hour at most.
local PAIR_GAP = HOUR
-- Our record may be filled up to this many bytes; the oldest entries go
-- first (see Pack.MAX_RECORD).
local RECORD_BUDGET = 16000
local QUERY_DELAY = 2       -- seconds after the vault opens, when its tabs are known
local READ_DELAY = 1        -- seconds after the game's last answer

-- Keeping our record within its size ------------------------------------------

-- Drops the oldest entries of our logs beyond their limits, then beyond
-- what our record may weigh.
function Log.Trim(record, guid)
    local bank = record.lg
    local vault = record.gl and record.gl.e
    while bank and #bank > LIMITS.log do
        table.remove(bank, 1)
    end
    while vault and #vault > LIMITS.guildLog do
        table.remove(vault, 1)
    end
    while (bank and bank[1] or vault and vault[1]) and Pack.RecordSize(guid or ns.playerGUID, record) > RECORD_BUDGET do
        if bank and bank[1] and not (vault and vault[1] and vault[1].t < bank[1].t) then
            table.remove(bank, 1)
        else
            table.remove(vault, 1)
        end
    end
end

-- The bank characters' log ------------------------------------------------------------------

local function ItemID(itemString)
    return tonumber(itemString:match("^item:(%d+)"))
end

-- items: { [item string] = count }, the item strings as Bank.ItemString
-- gives them. balance: the money we had before (nil: unknown). Returns the
-- money we have after.
local function Append(list, now, action, via, name, items, money, balance)
    local keys = {}
    for itemString, count in pairs(items or {}) do
        if type(itemString) == "string" and ItemID(itemString) and type(count) == "number" and count > 0 then
            keys[#keys + 1] = itemString
        end
    end
    table.sort(keys)
    for _, itemString in ipairs(keys) do
        list[#list + 1] = {
            t = now, a = action, v = via, w = name, i = ItemID(itemString),
            n = math.min(math.floor(items[itemString]), LIMITS.logCount), s = ns.Bank.Meaningful(itemString),
        }
    end
    if type(money) == "number" and money >= 1 then
        money = math.floor(money)
        if balance then
            balance = math.max(balance + (action == Log.IN and money or -money), 0)
        end
        list[#list + 1] = { t = now, a = action, v = via, w = name, m = money, r = balance }
    end
    return balance
end

-- As a bank character: writes down what we gave (given, moneyGiven) and got
-- (received, moneyReceived) from someone (name, as the log shows them), by
-- trade or mail (via: Log.TRADE, Log.MAIL, Log.COD, Log.RETURNED). Items
-- are { [item string] = count }, money is copper; before is the money we
-- had before (nil: unknown), so each money entry tells what was left.
function Log.Record(via, name, given, received, moneyGiven, moneyReceived, before)
    if not ns.playerGUID or not ns.Ranks.IsBank(ns.playerGUID) then
        return
    end
    local record = Data.GetOwnRecord(true)
    if not record or not Data.IsShareable(record) then
        return
    end
    local list = record.lg or {}
    local last = list[#list]
    local now = math.max(ns.Now(), last and last.t or 0)
    local count = #list
    name = Data.CleanName(name, LIMITS.text) or ""
    local balance = type(before) == "number" and before >= 0 and math.floor(before) or nil
    balance = Append(list, now, Log.IN, via, name, received, moneyReceived, balance)
    Append(list, now, Log.OUT, via, name, given, moneyGiven, balance)
    if #list == count then
        return
    end
    record.lg = list
    Log.Trim(record)
    Data.TouchOwn(record)
    ns.Debug("bank log: %d entries", #list - count)
end

-- The guild vault's log --------------------------------------------------------------------

local function VaultKey(entry)
    return table.concat({ entry.y, entry.w, entry.i or 0, entry.s or "", entry.n or 0, entry.m or 0, entry.b or 0, entry.d or 0 }, "|")
end

local function Close(a, b, now)
    local slack = (now - math.min(a.t, b.t) > OLD) and SAME_OLD_ENTRY or SAME_ENTRY
    return math.abs(a.t - b.t) <= slack
end

-- The log an entry is in: the money's, or a tab's.
local function Stream(entry)
    return entry.i and (entry.b or 0) or "money"
end

-- The entry of base that entry is, if any: alike, the closest in time, not
-- taken yet, and not before position from.
local function Match(byKey, entry, now, from)
    local best
    for _, candidate in ipairs(byKey[VaultKey(entry)] or {}) do
        if not candidate.used and candidate.index >= from and Close(candidate.entry, entry, now)
                and (not best or math.abs(candidate.entry.t - entry.t) < math.abs(best.entry.t - entry.t)) then
            best = candidate
        end
    end
    return best
end

-- base and more: vault entries, oldest first. Returns base with the entries
-- only more has, oldest first: an entry of more alike one of base and close
-- in time is the same entry (and keeps base's time, and its money left if
-- base's does not know it).
-- read: more is what the game just gave, the last entries of each of its
-- logs. The game gives their age only to the hour, so a new entry alike one
-- that is older than what it gave could be taken for it: in each log, the
-- entries of base before the one the oldest given matches are not looked
-- at (the oldest that base has, if base lost the very oldest to its limit).
function Log.MergeVault(base, more, now, read)
    local byKey, result = {}, {}
    for index, entry in ipairs(base) do
        local key = VaultKey(entry)
        byKey[key] = byKey[key] or {}
        table.insert(byKey[key], { entry = entry, index = index })
        result[index] = { entry = entry, order = index }
    end
    local from = {}
    if read then
        for _, entry in ipairs(more) do
            local stream = Stream(entry)
            if not from[stream] then
                local anchor = Match(byKey, entry, now, 1)
                from[stream] = anchor and anchor.index
            end
        end
    end
    for index, entry in ipairs(more) do
        local best = Match(byKey, entry, now, from[Stream(entry)] or 1)
        if best then
            best.used = true
            if best.entry.r == nil and entry.r ~= nil then
                local copy = {}
                for field, value in pairs(best.entry) do
                    copy[field] = value
                end
                copy.r = entry.r
                result[best.index].entry = copy
            end
        else
            result[#result + 1] = { entry = entry, order = #base + index }
        end
    end
    table.sort(result, function(a, b)
        if a.entry.t ~= b.entry.t then
            return a.entry.t < b.entry.t
        end
        return a.order < b.order
    end)
    for index, item in ipairs(result) do
        result[index] = item.entry
    end
    return result
end

-- Every member's reads, merged: the vault's entries, oldest first, and the
-- names of its tabs as last read.
function Log.VaultEntries(guild)
    local reads = {}
    for guid, record in pairs(guild and guild.members or {}) do
        if record.gl and Data.IsShareable(record) and ns.Roster.IsKnownGUID(guid) then
            reads[#reads + 1] = record.gl
        end
    end
    table.sort(reads, function(a, b)
        return a.t > b.t
    end)
    local now, entries = ns.Now(), {}
    for _, read in ipairs(reads) do
        entries = Log.MergeVault(entries, read.e, now)
    end
    return entries, reads[1] and reads[1].tn or {}
end

local vaultTypes = Pack.VAULT_TYPES

-- The game asks for the vault's money log as the tab after its last.
local function MoneyTab()
    return (ns.Number(MAX_GUILDBANK_TABS) or LIMITS.tabs) + 1
end

-- How long ago the game says an entry is, in seconds: it gives years,
-- months, days and hours; half an hour is added, as it rounds down.
local function Age(years, months, days, hours)
    local function Count(value)
        value = ns.Number(value)
        return value and value > 0 and value or 0
    end
    return ((Count(years) * 365 + Count(months) * 30 + Count(days)) * 24 + Count(hours)) * HOUR + HOUR / 2
end

local function Name(name)
    return Data.CleanName(ns.Plain(name), LIMITS.text) or ""
end

-- The vault's tabs: { { name, viewable }... } (none until the game knows them).
local function VaultTabs()
    local tabs = {}
    local count = ns.Number(ns.Try(GetNumGuildBankTabs)) or 0
    for tab = 1, math.min(count, LIMITS.tabs) do
        local name, _, viewable = ns.Try(GetGuildBankTabInfo, tab)
        tabs[tab] = { name = Name(name), viewable = ns.Plain(viewable) == true }
    end
    return tabs
end

-- Asks the game for the vault's log: its money, and each tab we may see.
function Log.QueryVault()
    for tab, info in ipairs(VaultTabs()) do
        if info.viewable then
            ns.Try(QueryGuildBankLog, tab)
        end
    end
    ns.Try(QueryGuildBankLog, MoneyTab())
end

-- The money entries that put money into the vault; the others take it out.
local VAULT_IN = { [vaultTypes.deposit] = true, [vaultTypes.depositSummary] = true, [vaultTypes.refundRename] = true }

function Log.IsVaultIn(y)
    return VAULT_IN[y] == true
end

-- The vault's money after each of its money entries (the game's, oldest
-- first), worked out backwards from what it holds now (money). Left unknown
-- when it does not add up: the money not known yet, say.
local function Balances(entries, money)
    if not money or money < 0 then
        return
    end
    local after, balance = {}, money
    for index = #entries, 1, -1 do
        local entry = entries[index]
        after[index] = balance
        balance = balance + (VAULT_IN[entry.y] and -entry.m or entry.m)
        if balance < 0 then
            return
        end
    end
    for index, entry in ipairs(entries) do
        entry.r = after[index]
    end
end

-- What the game told us of the vault's log, oldest first, and its tab names.
local function ReadVaultEntries(now)
    local entries = {}
    local tabs = VaultTabs()
    local names = {}
    for tab, info in ipairs(tabs) do
        names[tab] = info.name
        local count = info.viewable and ns.Number(ns.Try(GetNumGuildBankTransactions, tab)) or 0
        for index = 1, math.min(count, LIMITS.guildLog) do
            local kind, name, link, quantity, from, to, years, months, days, hours = ns.Try(GetGuildBankTransaction, tab, index)
            local y = vaultTypes[ns.Plain(kind)]
            local itemString = ns.Bank.ItemString(ns.Plain(link))
            quantity, from, to = ns.Number(quantity), ns.Number(from), ns.Number(to)
            local move = y == vaultTypes.move
            -- A move shows in the log of both its tabs: it is taken from
            -- the one it left, if we may see it.
            local keep
            if move then
                keep = tabs[from] and tabs[to] and (from == tab or not tabs[from].viewable)
            else
                keep = y == vaultTypes.deposit or y == vaultTypes.withdraw
            end
            if keep and itemString and quantity and quantity > 0 then
                entries[#entries + 1] = {
                    t = now - Age(years, months, days, hours), y = y, w = Name(name), i = ItemID(itemString),
                    n = math.min(math.floor(quantity), LIMITS.logCount), s = ns.Bank.Meaningful(itemString),
                    b = move and from or tab, d = move and to or nil,
                }
            end
        end
    end
    local count = ns.Number(ns.Try(GetNumGuildBankMoneyTransactions)) or 0
    local money, complete = {}, true
    for index = math.max(count - LIMITS.guildLog, 0) + 1, count do
        local kind, name, amount, years, months, days, hours = ns.Try(GetGuildBankMoneyTransaction, index)
        local y = vaultTypes[ns.Plain(kind)]
        amount = ns.Number(amount)
        if y and y ~= vaultTypes.move and amount and amount >= 0 then
            money[#money + 1] = { t = now - Age(years, months, days, hours), y = y, w = Name(name), m = math.floor(amount) }
            entries[#entries + 1] = money[#money]
        else
            complete = false
        end
    end
    if complete then
        Balances(money, ns.Number(ns.Try(GetGuildBankMoney)))
    end
    -- Oldest first, the game's order kept for entries of the same time.
    for index, entry in ipairs(entries) do
        entries[index] = { entry = entry, order = index }
    end
    table.sort(entries, function(a, b)
        if a.entry.t ~= b.entry.t then
            return a.entry.t < b.entry.t
        end
        return a.order < b.order
    end)
    for index, item in ipairs(entries) do
        entries[index] = item.entry
    end
    return entries, names
end

-- Reads the vault's log the game gave us into our record, merged with what
-- the guild knew of it.
function Log.ReadVault()
    local record = Data.GetOwnRecord(true)
    if not record or not Data.IsShareable(record) then
        return
    end
    local now = ns.Now()
    local entries, names = ReadVaultEntries(now)
    if #entries == 0 and #names == 0 then
        return
    end
    local known = Log.VaultEntries(Data.CurrentGuild(false))
    local merged = Log.MergeVault(known, entries, now, true)
    while #merged > LIMITS.guildLog do
        table.remove(merged, 1)
    end
    local old = record.gl
    if old and ns.Same(old.e, merged) and ns.Same(old.tn, names) then
        return
    end
    record.gl = { t = now, tn = names, e = merged }
    Log.Trim(record)
    Data.TouchOwn(record)
    ns.Debug("guild vault log: %d entries read, %d kept", #entries, #record.gl.e)
end

-- A name as the vault's log gives it (maybe with a realm) against a
-- member's.
local function SameName(vaultName, name)
    vaultName = vaultName:match("^([^%-]+)") or vaultName
    return name ~= nil and vaultName:lower() == name:lower()
end

-- What the Log subtab shows: every entry, newest first, as { source =
-- "bank" (bank = its bank character's GUID, record = its record) or
-- "vault" (tabs = the vault's tab names), entry, at = its time }.
-- A bank character's money put into the vault or taken from it, and the
-- vault's entry for it, are paired: each line has the other as pair, and
-- the vault's takes the bank character's time, which is exact.
function Log.Lines(guild)
    local lines, atVault = {}, {}
    for guid, record in pairs(guild and guild.members or {}) do
        if record.lg and Data.IsShareable(record) and ns.Roster.IsKnownGUID(guid) then
            local name = Data.NameOf(guid, record)
            for _, entry in ipairs(record.lg) do
                local line = { source = "bank", bank = guid, record = record, entry = entry, at = entry.t, order = #lines }
                lines[#lines + 1] = line
                if entry.v == Log.VAULT and entry.m then
                    atVault[#atVault + 1] = { line = line, name = name }
                end
            end
        end
    end
    local types = Pack.VAULT_TYPES
    local vault, tabs = Log.VaultEntries(guild)
    -- Every vault entry a bank character's could be, then the closest in
    -- time first: the bank character's time is exact, the vault's is off by
    -- half an hour at most.
    local candidates = {}
    for _, entry in ipairs(vault) do
        local line = { source = "vault", tabs = tabs, entry = entry, at = entry.t, order = #lines }
        lines[#lines + 1] = line
        local taken = entry.y == types.withdraw
        if entry.m and (taken or entry.y == types.deposit) then
            for _, own in ipairs(atVault) do
                local mine = own.line.entry
                local gap = math.abs(mine.t - entry.t)
                if mine.m == entry.m and mine.a == (taken and Log.IN or Log.OUT) and SameName(entry.w, own.name)
                        and gap <= PAIR_GAP then
                    candidates[#candidates + 1] = { vault = line, bank = own.line, gap = gap, order = #candidates }
                end
            end
        end
    end
    table.sort(candidates, function(a, b)
        if a.gap ~= b.gap then
            return a.gap < b.gap
        end
        return a.order < b.order
    end)
    for _, pair in ipairs(candidates) do
        if not pair.vault.pair and not pair.bank.pair then
            pair.vault.pair, pair.bank.pair = pair.bank, pair.vault
            pair.vault.at = pair.bank.entry.t
        end
    end
    table.sort(lines, function(a, b)
        if a.at ~= b.at then
            return a.at > b.at
        end
        if a.source ~= b.source then
            return a.source < b.source
        end
        if a.bank ~= b.bank then
            return (a.bank or "") < (b.bank or "")
        end
        return a.order < b.order
    end)
    return lines
end

function Log.Init()
    local vaultOpen = false
    local frame = CreateFrame("Frame")
    ns.RegisterEvents(frame, "GUILDBANKLOG_UPDATE", "GUILDBANK_UPDATE_MONEY")
    frame:SetScript("OnEvent", function(_, event)
        if event == "GUILDBANKLOG_UPDATE" then
            ns.Debounce("GuildVaultLog", READ_DELAY, Log.ReadVault)
        elseif vaultOpen then
            -- The vault's money changed while we are at it: its money log
            -- has a new entry, which the game only gives when asked.
            ns.Debounce("GuildVaultMoney", READ_DELAY, function()
                ns.Try(QueryGuildBankLog, MoneyTab())
            end)
        end
    end)
    ns.On("GuildBankOpened", function()
        vaultOpen = true
        C_Timer.After(QUERY_DELAY, Log.QueryVault)
    end)
    ns.On("GuildBankClosed", function()
        vaultOpen = false
    end)
end
