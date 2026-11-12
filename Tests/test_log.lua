-- The bank's log (Log.lua, the log part of Deliveries.lua, LogView.lua):
-- what bank characters trade and mail, and the guild vault's own log.
local H = ...

local function Errors(world, label)
    H.eq(#world.errors, 0, "no errors: " .. label)
    for _, err in ipairs(world.errors) do
        print("   " .. err)
    end
    world.errors = {}
end

local function Find(list, fn)
    for _, item in ipairs(list or {}) do
        if fn(item) then
            return item
        end
    end
end

local function FindLast(list, fn)
    for index = #(list or {}), 1, -1 do
        if fn(list[index]) then
            return list[index]
        end
    end
end

local function Count(list, fn)
    local count = 0
    for _, item in ipairs(list or {}) do
        if fn(item) then
            count = count + 1
        end
    end
    return count
end

local CLOTH, ORE, HERB, SWORD = 2589, 2771, 8545, 12345
local HOUR = 3600

local world = H.NewWorld({ seed = 21, senderFormat = "short", strictWhispers = true, communities = H.FakeCommunities })
local bank = world:NewClient("Bank Holder", { rank = "Banco", rankIndex = 4, money = 100000 })
local second = world:NewClient("Second Bank", { rank = "Banco", rankIndex = 4 })
local alice = world:NewClient("Alice Smith", { rank = "Miembro", rankIndex = 3, money = 50000 })
local olga = world:NewClient("Olga Price", { rank = "Oficial", rankIndex = 1 })
for _, client in ipairs({ bank, second, alice, olga }) do
    world:Login(client)
end
world:RunFor(60)
Errors(world, "login")

local ns = bank.ns
local Log = ns.Log

local function Record(client, of)
    return client.ns.Data.GetGuild("Test Guild").members[of.guid]
end

local function LogOf(client, of)
    local record = Record(client, of)
    return record and record.lg or {}
end

-- The entries of a bank log alike the one given (fields left out match any).
local function Entries(log, want)
    local found = {}
    for _, entry in ipairs(log) do
        local same = true
        for key, value in pairs(want) do
            if entry[key] ~= value then
                same = false
            end
        end
        if same then
            found[#found + 1] = entry
        end
    end
    return found
end

local function Has(log, want)
    return #Entries(log, want) == 1
end

H.section("Log: trades")
world:Trade(bank, alice, { [1] = { ORE, 5 } }, { [1] = { CLOTH, 10 }, [2] = { HERB, 3 } }, { bMoney = 1500 })
world:RunFor(2)
local log = LogOf(bank, bank)
H.eq(#log, 4, "a trade: what came in and what went out, one entry each")
H.check(Has(log, { a = Log.IN, v = Log.TRADE, w = "Alice Smith", i = CLOTH, n = 10 }), "the items received, with whom")
H.check(Has(log, { a = Log.IN, v = Log.TRADE, i = HERB, n = 3 }), "each kind of item")
H.check(Has(log, { a = Log.IN, v = Log.TRADE, m = 1500 }), "the money received")
H.check(Has(log, { m = 1500, r = 100000 + 1500 }), "with the money the bank character had left after it")
H.check(Has(log, { a = Log.OUT, v = Log.TRADE, w = "Alice Smith", i = ORE, n = 5 }), "the items given")
H.check(log[1].t == log[4].t and log[1].t <= Record(bank, bank).t, "all at the trade's time")
H.eq(Record(alice, alice).lg, nil, "a member who is not a bank character writes nothing down")
world:Trade(alice, olga, { [1] = { CLOTH, 1 } }, {}, { bMoney = 10 })
world:RunFor(2)
H.eq(Record(alice, alice).lg, nil, "not even trading among themselves")
world:Trade(bank, alice, { [1] = { ORE, 1 } }, {}, { cancel = true })
world:RunFor(2)
H.eq(#LogOf(bank, bank), 4, "a cancelled trade is not written down")
world:RunFor(120)
H.eq(#LogOf(olga, bank), 4, "the guild gets the bank character's log")
Errors(world, "trades")

H.section("Log: mail")
world:Mail(bank, "Alice Smith", { [1] = { CLOTH, 5 } }, { cod = 30 })
world:Mail(bank, "alice smith", {}, { money = 2000 })
world:RunFor(2)
log = LogOf(bank, bank)
H.check(Has(log, { a = Log.OUT, v = Log.MAIL, w = "Alice Smith", i = CLOTH, n = 5 }), "items sent by mail")
H.check(Has(log, { a = Log.OUT, v = Log.MAIL, w = "Alice Smith", m = 2000, r = bank.money - 2000 }),
    "money sent, to the guildmate however typed, and what was left")
H.eq(#Entries(log, { a = Log.OUT, v = Log.POSTAGE, w = "Alice Smith", m = 30 }), 2, "the postage of each mail, to whom")
H.check(Has(log, { v = Log.POSTAGE, r = bank.money - 2000 - 30 }), "and what was left after it")
world:Mail(bank, "Nobody Here", { [1] = { ORE, 1 } }, { fail = true })
world:RunFor(2)
H.eq(#LogOf(bank, bank), 8, "mail the game refuses to send is not written down")
world:Mail(bank, "Olga Price", { [1] = { CLOTH, 1 }, [2] = { CLOTH, 1 }, [3] = { ORE, 1 } })
world:RunFor(2)
H.check(Has(LogOf(bank, bank), { v = Log.POSTAGE, w = "Olga Price", m = 90 }), "postage per item attached")

-- Alice sends items and money; the bank character takes them.
world:Mail(alice, "Bank Holder", { [1] = { HERB, 4 }, [2] = { ORE, 2 } }, { money = 700 })
local had = bank.money
world:TakeMail(bank, 1)
log = LogOf(bank, bank)
H.check(Has(log, { a = Log.IN, v = Log.MAIL, w = "Alice Smith", i = HERB, n = 4 })
    and Has(log, { a = Log.IN, v = Log.MAIL, i = ORE, n = 2 }), "items taken from the mailbox")
H.check(Has(log, { a = Log.IN, v = Log.MAIL, w = "Alice Smith", m = 700, r = had + 700 }), "and the money, and what was left")
H.eq(bank.money, had + 700, "(as the game has it)")
-- Bags full: the game refuses the items.
world:Mail(alice, "Bank Holder", { [1] = { HERB, 9 } })
bank.bagsFull = true
world:TakeMail(bank, 1)
H.eq(#Entries(LogOf(bank, bank), { i = HERB, n = 9 }), 0, "items the game refuses are not written down")
bank.bagsFull = false
world:TakeMail(bank, 1, 1)
H.eq(#Entries(LogOf(bank, bank), { i = HERB, n = 9 }), 1, "until they are taken")
-- Cash on delivery: taking the item pays it.
world:Mail(alice, "Bank Holder", { [1] = { SWORD, 1 } }, { cod = 5000 })
had = bank.money
world:TakeMail(bank, 1, 1)
log = LogOf(bank, bank)
H.check(Has(log, { a = Log.IN, v = Log.MAIL, i = SWORD, n = 1 }), "an item sent cash on delivery")
H.check(Has(log, { a = Log.OUT, v = Log.COD, w = "Alice Smith", m = 5000, r = had - 5000 }), "and the cash on delivery paid for it")
-- Mail coming back, and mail from the auction house.
bank.inbox[#bank.inbox + 1] = { from = "Alice Smith", items = { { CLOTH, 6 } }, returned = true }
bank.inbox[#bank.inbox + 1] = { from = "Auction House", items = {}, money = 12345 }
world:TakeMail(bank, 1)
had = bank.money
world:TakeMail(bank, 1, "money")
log = LogOf(bank, bank)
H.check(Has(log, { a = Log.IN, v = Log.RETURNED, w = "Alice Smith", i = CLOTH, n = 6 }), "a mail that came back")
H.check(Has(log, { a = Log.IN, v = Log.MAIL, w = "Auction House", m = 12345, r = had + 12345 }),
    "the auction house's mail, by the name it gives")
-- Mail between bank characters: each writes down its side.
world:Mail(bank, "Second Bank", { [1] = { ORE, 7 } })
world:TakeMail(second, 1)
H.check(Has(LogOf(bank, bank), { a = Log.OUT, w = "Second Bank", i = ORE, n = 7 })
    and Has(LogOf(second, second), { a = Log.IN, w = "Bank Holder", i = ORE, n = 7 }), "between bank characters, both sides")
-- A member who is not a bank character takes mail: nothing.
world:Mail(bank, "Olga Price", { [1] = { HERB, 1 } })
world:TakeMail(olga, 1)
H.eq(Record(olga, olga).lg, nil, "a member taking mail writes nothing down")
Errors(world, "mail")

H.section("Log: the guild vault")
world:VaultTab("Main")
world:VaultTab("Officers", false)
world:VaultMoney("deposit", "Alice Smith", 10000)
world:VaultItem(1, "deposit", "Alice Smith", CLOTH, 20)
world:VaultItem(2, "withdraw", "Olga Price", SWORD, 1)
world.base = world.base + 5 * HOUR
world:VaultMoney("repair", "Olga Price", 250)
world.base = world.base + 2 * HOUR
olga.ns.Data.GetOwnRecord(true)
world:OpenGuildBank(olga, 9750)
world:RunFor(10)
world:CloseGuildBank(olga)
local vault = Record(olga, olga).gl
H.check(vault ~= nil and #vault.e == 3, "a member at the vault reads its log: its money and the tabs it may see")
H.check(vault and vault.tn[1] == "Main" and vault.tn[2] == "Officers", "with the tabs' names")
local types = ns.Pack.VAULT_TYPES
local deposit = vault and Find(vault.e, function(e) return e.m == 10000 end)
local now = world:ServerTime()
H.check(deposit and deposit.y == types.deposit and deposit.w == "Alice Smith"
    and math.abs((now - 7 * HOUR) - deposit.t) <= HOUR, "a deposit, with who and about when")
local repair = vault and Find(vault.e, function(e) return e.y == types.repair end)
H.check(repair and repair.m == 250 and math.abs((now - 2 * HOUR) - repair.t) <= HOUR, "repairs")
H.check(deposit and deposit.r == 10000 and repair and repair.r == 9750,
    "the vault's money after each, worked out back from what it holds")
local cloth = vault and Find(vault.e, function(e) return e.i == CLOTH end)
H.check(cloth and cloth.n == 20 and cloth.b == 1 and cloth.y == types.deposit, "items, with their tab")
H.eq(vault and Find(vault.e, function(e) return e.i == SWORD end), nil, "not the tabs the member may not see")
world:RunFor(120)
local lines = alice.ns.Log.Lines(alice.ns.Data.CurrentGuild(false))
H.eq(Count(lines, function(line) return line.source == "vault" end), 3, "the guild gets it")

-- Later, another member reads it again, with one more entry: the same
-- entries are not told twice, though the game gives their age to the hour.
world.base = world.base + 3 * HOUR + 1700
world:VaultMoney("withdraw", "Bank Holder", 5000)
world:OpenGuildBank(alice, 4750)
world:RunFor(10)
H.eq(#Record(alice, alice).gl.e, 4, "a second read adds only what is new")
world:RunFor(120)
local entries = olga.ns.Log.VaultEntries(olga.ns.Data.CurrentGuild(false))
H.eq(#entries, 4, "and the guild has each entry once")
-- More than the game keeps (its last 25 money entries): what the guild read
-- before stays. The 5 entries nobody read in time are lost.
for i = 1, 30 do
    world:VaultMoney("deposit", "Mike Stone", i)
end
world.base = world.base + HOUR
world:OpenGuildBank(olga, 5000)
world:RunFor(10)
vault = Record(olga, olga).gl
H.eq(#vault.e, 4 + 25, "the log reaches further back than the game's")
H.check(Find(vault.e, function(e) return e.m == 10000 end) and not Find(vault.e, function(e) return e.m == 5 end),
    "with the older entries the guild read before")
-- A move between tabs is in the log of both: it is told once.
world:VaultTab("Third")
world:VaultItem(1, "move", "Olga Price", ORE, 3, 3)
local moved = world.vault.tabs[1].log[#world.vault.tabs[1].log]
table.insert(world.vault.tabs[3].log, { kind = "move", name = "Olga Price", itemID = ORE, count = 3, tab1 = 1, tab2 = 3, at = moved.at })
world:OpenGuildBank(olga, 5000)
world:RunFor(10)
vault = Record(olga, olga).gl
H.eq(Count(vault.e, function(e) return e.y == types.move end), 1, "a move between tabs, once")
local move = Find(vault.e, function(e) return e.y == types.move end)
H.check(move and move.b == 1 and move.d == 3 and move.n == 3, "from one tab to the other")
-- Nothing new: our record is not stamped again.
local stamped = Record(olga, olga).t
world:OpenGuildBank(olga, 5000)
world:RunFor(10)
H.eq(Record(olga, olga).t, stamped, "reading the same log again changes nothing")
-- The vault's money not known yet (it does not add up): no money left made up.
world:VaultMoney("deposit", "Alice Smith", 777)
world:OpenGuildBank(olga, 0)
world:RunFor(10)
local unknown = Find(Record(olga, olga).gl.e, function(e) return e.m == 777 end)
H.check(unknown and unknown.r == nil, "when the vault's money does not add up, what was left stays unknown")
H.check(Find(Record(olga, olga).gl.e, function(e) return e.m == 250 end).r == 9750, "what was known stays")
world:RunFor(150)
Errors(world, "vault")

H.section("Log: merging reads of the vault")
local base = world:ServerTime()
local function V(t, y, w, m)
    return { t = base - t, y = y, w = w, m = m }
end
local merged = Log.MergeVault({ V(10 * HOUR, 1, "A", 5), V(9 * HOUR, 1, "A", 5) }, { V(10 * HOUR - 1800, 1, "A", 5),
    V(9 * HOUR + 1800, 1, "A", 5), V(HOUR, 1, "A", 5) }, base)
H.eq(#merged, 3, "alike entries close in time are the same, each once; a new one is added")
merged = Log.MergeVault({ V(10 * HOUR, 1, "A", 5) }, { V(5 * HOUR, 1, "A", 5) }, base)
H.eq(#merged, 2, "alike entries far apart are two")
merged = Log.MergeVault({ V(10 * HOUR, 1, "A", 5) }, { V(10 * HOUR, 2, "A", 5), V(10 * HOUR, 1, "B", 5), V(10 * HOUR, 1, "A", 6) }, base)
H.eq(#merged, 4, "entries that differ in anything are different")
merged = Log.MergeVault({ V(60 * 86400, 1, "A", 5) }, { V(62 * 86400, 1, "A", 5) }, base)
H.eq(#merged, 1, "old entries, whose age the game gives in months, may be further apart")
merged = Log.MergeVault({ V(3 * HOUR, 1, "A", 5) }, { V(9 * HOUR, 1, "B", 1) }, base)
H.check(merged[1].w == "B" and merged[2].w == "A", "oldest first")
local known = V(3 * HOUR, 1, "A", 5)
local read = V(3 * HOUR, 1, "A", 5)
read.r = 800
merged = Log.MergeVault({ known }, { read }, base)
H.check(#merged == 1 and merged[1].r == 800 and known.r == nil, "the money left, when only the new read knows it")
-- A fresh read: the last entries of each of the game's logs. An entry alike
-- one older than the oldest it gave is new, though close in time.
local older = V(2 * HOUR, 2, "A", 5)
local window = { V(2 * HOUR - 60, 1, "B", 1), V(HOUR + 1200, 2, "A", 5) }
merged = Log.MergeVault({ older, V(2 * HOUR - 60, 1, "B", 1) }, window, base, true)
H.eq(#merged, 3, "a fresh read: what is older than what the game gave is not taken for a new entry")
merged = Log.MergeVault({ older, V(2 * HOUR - 60, 1, "B", 1) }, window, base)
H.eq(#merged, 2, "(merging what members keep, it would be)")
merged = Log.MergeVault({ V(2 * HOUR - 60, 1, "B", 1), V(HOUR + 1000, 2, "A", 5) }, window, base, true)
H.eq(#merged, 2, "the same entries read again are still the same")

H.section("Log: the Log subtab")
local env = alice.env
env.GuildBankAltsGuildTab._scripts.OnClick(env.GuildBankAltsGuildTab)
local page = env.GuildBankAltsGuildPanel
H.eq(page.SubTabs.Tabs[3]:GetText(), "Log", "a third subtab")
page.SubTabs.Tabs[3]._scripts.OnClick(page.SubTabs.Tabs[3])
H.check(page.Log:IsShown() and not page.Requests:IsShown() and not page.Bank:IsShown(), "the log shows")
H.check(page.LogFilters[1]:IsShown() and not page.OnlyOpen:IsShown() and not page.Hint:IsShown(), "with its filters only")
local elements = page.Log.ScrollBox._provider.elements
local all = #elements
H.check(all > 20, "every entry is listed")
H.check(elements[1].line.entry.t >= elements[all].line.entry.t, "newest first")
local function TextOf(element)
    local row = H.NewObject(alice, "Frame")
    page.Log.ScrollBox._view.init(row, element)
    return row.Text:GetText(), row
end
local tradeLine = Find(elements, function(e)
    return e.line.source == "bank" and e.line.entry.v == Log.TRADE and e.line.entry.i == CLOTH
end)
local text, row = TextOf(tradeLine)
H.check(text:find("[Bank Holder]", 1, true) and text:find("Alice Smith", 1, true) and text:find("deposited", 1, true)
    and text:find(" x 10", 1, true) and text:find("(by trade)", 1, true) and text:find("ago )", 1, true), "a bank character's line: " .. text)
row._scripts.OnEnter(row)
H.check(env.GameTooltip:IsShown(), "it has a tooltip")
local tip = env.GameTooltip._lines
H.check(tip[#tip]:find("^%d%d/%d%d/%d%d%d%d %d%d:%d%d$") ~= nil, "telling when: " .. tostring(tip[#tip]))
-- An item's line: the item's tooltip, then when.
env.GameTooltip.SetHyperlink = function(self, link)
    self._lines = { link }
end
row._scripts.OnEnter(row)
tip = env.GameTooltip._lines
H.check(tip[1] == "item:" .. CLOTH and #tip == 3 and tip[3]:find("^%d%d/") ~= nil, "an item's line shows the item's tooltip and when")
env.GameTooltip.SetHyperlink = nil
local Money = alice.ns.BankView.Money
local moneyLine = Find(elements, function(e)
    return e.line.source == "bank" and e.line.entry.v == Log.TRADE and e.line.entry.m == 1500
end)
local _, moneyRow = TextOf(moneyLine)
moneyRow._scripts.OnEnter(moneyRow)
tip = env.GameTooltip._lines
H.check(tip[1]:find("Bank Holder", 1, true) ~= nil, "a money line's tooltip tells whose money it is")
H.eq(tip[2], "Balance before | " .. Money(100000), "the bank character's money before")
H.eq(tip[3], "Balance after | " .. Money(101500), "and after")
H.check(#tip == 4 and not tip[1]:find("deposited", 1, true), "not the line again")
local postageLine = Find(elements, function(e) return e.line.entry.v == Log.POSTAGE end)
text = TextOf(postageLine)
H.check(text:find("Bank Holder|r |cffff2020withdrew|r", 1, true) and text:find("(postage of a mail to ", 1, true),
    "the postage, paid by the bank character: " .. text)
local codLine = Find(elements, function(e) return e.line.entry.v == Log.COD end)
text = TextOf(codLine)
H.check(text:find("withdrew", 1, true) and text:find("(cash on delivery)", 1, true), "the cash on delivery paid: " .. text)
local vaultLine = Find(elements, function(e) return e.line.source == "vault" and e.line.entry.y == types.repair end)
text, row = TextOf(vaultLine)
H.check(text:find("[Guild vault]", 1, true) and text:find("Olga Price|r withdrew", 1, true) and text:find("for repairs", 1, true),
    "a guild vault line, told apart: " .. text)
row._scripts.OnEnter(row)
tip = env.GameTooltip._lines
H.check(tip[1]:find("Guild vault", 1, true) and tip[2] == "Balance before | " .. Money(10000)
    and tip[3] == "Balance after | " .. Money(9750), "the vault's money before and after")
H.check(tip[4]:find("^~%d%d/%d%d/%d%d%d%d %d%d:00$") ~= nil, "and about when: " .. tostring(tip[4]))
local tabLine = Find(elements, function(e) return e.line.source == "vault" and e.line.entry.i == CLOTH end)
H.check(TextOf(tabLine):find("(Main)", 1, true), "with its tab, as the vault has several")
local moveLine = Find(elements, function(e) return e.line.entry.y == types.move end)
H.check(TextOf(moveLine):find("from Main to Third", 1, true), "a move, from tab to tab")
-- The filters.
local function Filter(index, checked)
    page.LogFilters[index]:SetChecked(checked)
    page.LogFilters[index]._scripts.OnClick(page.LogFilters[index])
    return page.Log.ScrollBox._provider.elements
end
elements = Filter(1, false)
H.check(#elements > 0 and Find(elements, function(e) return e.line.entry.i end) == nil, "without items: money only")
elements = Filter(2, false)
H.check(#elements == 0 and page.Log.Empty:IsShown(), "without money either: nothing")
Filter(1, true)
Filter(2, true)
elements = Filter(4, false)
H.check(Find(elements, function(e) return e.line.source == "vault" end) == nil, "without the guild vault")
elements = Filter(3, false)
H.eq(#elements, 0, "without the bank characters either: nothing")
Filter(3, true)
elements = Filter(4, true)
H.eq(#elements, all, "all of it again")
Errors(world, "subtab")

H.section("Log: words")
H.eq(alice.ns.LogView.Money(15030), "1|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t 50|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t "
    .. "30|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t", "money with its coins")
H.eq(alice.ns.LogView.Money(30), "30|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t", "only the coins it has")
-- The game's own words when the client has them.
env.GUILDBANK_DEPOSIT_FORMAT = "%s ha depositado %s"
H.check(TextOf(tradeLine):find("Alice Smith|r ha depositado", 1, true) ~= nil, "the game's texts, in the client's language")
env.GUILDBANK_DEPOSIT_FORMAT = "%d broken"
H.check(TextOf(tradeLine):find("deposited", 1, true) ~= nil, "and English if the client's text does not fit")
env.GUILDBANK_DEPOSIT_FORMAT = nil

H.section("Log: a bank character at the guild vault")
world:OpenGuildBank(bank, 20000)
world:RunFor(10)
local had = bank.money
bank.env.WithdrawGuildBankMoney(5000)
world:RunFor(10)
bank.env.DepositGuildBankMoney(2000)
world:RunFor(10)
bank.env.WithdrawGuildBankMoney(1000000000)
world:RunFor(15)
world:CloseGuildBank(bank)
log = LogOf(bank, bank)
H.check(Has(log, { a = Log.IN, v = Log.VAULT, w = "", m = 5000, r = had + 5000 }),
    "money it takes from the vault, with the money it had left after")
H.check(Has(log, { a = Log.OUT, v = Log.VAULT, m = 2000, r = had + 3000 }), "money it puts in")
H.eq(#Entries(log, { m = 1000000000 }), 0, "not what the vault refused")
-- The vault already had the same withdrawal by the same character, a bit
-- over an hour before, which the game no longer gives: this one is new.
local vaultLog = Record(bank, bank).gl.e
H.eq(Count(vaultLog, function(e) return e.y == types.withdraw and e.m == 5000 and e.w == "Bank Holder" end), 2,
    "a withdrawal alike an older one the game no longer gives is a new one")
local taken = FindLast(vaultLog, function(e) return e.y == types.withdraw and e.m == 5000 end)
local put = FindLast(vaultLog, function(e) return e.y == types.deposit and e.m == 2000 end)
H.check(taken and taken.w == "Bank Holder" and taken.r == 15000 and put and put.r == 17000,
    "the vault's log is asked for again as its money changes, so the moves show at once")
world:RunFor(150)
elements = page.Log.ScrollBox._provider.elements
local vaultTaken = Find(elements, function(e) return e.line.source == "vault" and e.line.entry.m == 5000 and e.line.pair end)
H.check(vaultTaken and vaultTaken.line.pair and vaultTaken.line.pair.source == "bank", "the vault's line has the bank character's")
H.eq(Find(elements, function(e) return e.line.source == "bank" and e.line.entry.v == Log.VAULT end), nil,
    "which is not listed apart")
H.eq(vaultTaken.line.at, vaultTaken.line.pair.entry.t, "and its time is the bank character's, exact")
text, row = TextOf(vaultTaken)
row._scripts.OnEnter(row)
tip = env.GameTooltip._lines
H.check(tip[1]:find("Guild vault", 1, true) and tip[2] == "Balance before | " .. Money(20000)
    and tip[3] == "Balance after | " .. Money(15000), "its tooltip: the vault's money before and after")
H.check(tip[4]:find("Bank Holder", 1, true) and tip[5] == "Balance before | " .. Money(had)
    and tip[6] == "Balance after | " .. Money(had + 5000), "and the bank character's")
H.check(tip[7]:find("^%d%d/") ~= nil and #tip == 7, "when, exactly: " .. tostring(tip[7]))
-- With the vault's lines hidden, the bank character's shows, with both too.
elements = Filter(4, false)
local own = Find(elements, function(e) return e.line.entry.v == Log.VAULT and e.line.entry.m == 2000 end)
text, row = TextOf(own)
H.check(text:find("[Bank Holder]", 1, true) and text:find("Bank Holder|r deposited", 1, true)
    and text:find("(at the guild vault)", 1, true), "the bank character's line: " .. text)
row._scripts.OnEnter(row)
tip = env.GameTooltip._lines
H.check(tip[1]:find("Bank Holder", 1, true) and tip[2] == "Balance before | " .. Money(had + 5000)
    and tip[4]:find("Guild vault", 1, true) and tip[6] == "Balance after | " .. Money(17000), "its tooltip, both again")
Filter(4, true)
Errors(world, "bank character at the vault")

H.section("Log: nobody changes it")
-- Not even a bank character its own entries: the log is only added to.
world:Mail(bank, "Olga Price", {}, { money = 4321 })
world:RunFor(150)
local bankEnv = bank.env
bankEnv.GuildBankAltsGuildTab._scripts.OnClick(bankEnv.GuildBankAltsGuildTab)
local bankPage = bankEnv.GuildBankAltsGuildPanel
bankPage.SubTabs.Tabs[3]._scripts.OnClick(bankPage.SubTabs.Tabs[3])
local own = Find(bankPage.Log.ScrollBox._provider.elements, function(e) return e.line.entry.m == 4321 end)
local ownRow = H.NewObject(bank, "Frame")
bankPage.Log.ScrollBox._view.init(ownRow, own)
local kept = H.DeepCopy(LogOf(bank, bank))
ownRow._scripts.OnEnter(ownRow)
ownRow._scripts.OnMouseUp(ownRow, "RightButton")
ownRow._scripts.OnMouseUp(ownRow, "LeftButton")
H.check(ns.Same(LogOf(bank, bank), kept), "clicking its own lines changes nothing")
H.eq(Log.Delete, nil, "there is no way to delete an entry")
world:RunFor(150)
H.check(ns.Same(LogOf(alice, bank), kept), "and the guild has it as it was")
Errors(world, "unchanged")

H.section("Log: limits")
local before = #LogOf(bank, bank)
for i = 1, 100 do
    world:Trade(bank, alice, {}, { [1] = { CLOTH, i } })
end
world:RunFor(2)
log = LogOf(bank, bank)
H.eq(#log, ns.Pack.LIMITS.log, "the log keeps its newest entries, up to its limit")
H.eq(log[#log].n, 100, "the newest last")
H.check(log[1].v == Log.TRADE and log[1].i == CLOTH and log[1].n == 1, "the older entries went")
-- Items with long item strings: the record stays within its size.
local record = Record(bank, bank)
for i = 1, 100 do
    record.lg[i].s = ("item:%d:%s"):format(record.lg[i].i, string.rep("1:", 100) .. i)
end
world:Trade(bank, alice, {}, { [1] = { HERB, 1 } })
world:RunFor(2)
record = Record(bank, bank)
H.check(ns.Pack.RecordSize(bank.guid, record) <= 16000 and #record.lg < 100, "the oldest entries go first to keep the record small enough")
H.check(record.lg[#record.lg].i == HERB, "the newest stays")
Errors(world, "limits")

H.section("Log: records")
local Pack, Data = ns.Pack, ns.Data
local t = ns.Now()
local full = {
    t = t, n = "Bank Holder", av = 300,
    lg = {
        { t = t - 100, a = 1, v = 1, w = "Alice Smith", i = CLOTH, n = 10 },
        { t = t - 100, a = 2, v = 2, w = "", m = 50, r = 1000 },
        { t = t - 5, a = 1, v = 4, w = "Auction House", i = SWORD, n = 1, s = "item:12345:1900" },
    },
    gl = { t = t - 1, tn = { "Main", "" }, e = {
        { t = t - 9000, y = 3, w = "Olga Price", i = ORE, n = 3, b = 1, d = 2 },
        { t = t - 5000, y = 4, w = "Olga Price", m = 250, r = 0 },
        { t = t - 5000, y = 6, w = "", m = 0 },
    } },
}
local _, back = Pack.ReadRecord(Pack.Reader(Pack.RecordString(bank.guid, full)))
H.check(ns.Same(back, full), "both logs, packed and read back")
H.check(ns.Same(Data.CleanRecord(back, t), back), "and checked")
local function Bad(label, change)
    local copy = H.DeepCopy(full)
    change(copy)
    H.eq(Data.CleanRecord(copy, t), nil, "refused: " .. label)
end
Bad("entries out of order", function(r) r.lg[1].t = t end)
Bad("an entry later than the record", function(r) r.lg[3].t = t + 10 end)
Bad("an unknown way", function(r) r.lg[1].v = 9 end)
Bad("both an item and money", function(r) r.lg[1].m = 5 end)
Bad("no count", function(r) r.lg[1].n = 0 end)
Bad("money left that cannot be", function(r) r.lg[2].r = -1 end)
Bad("an escape sequence in a name", function(r) r.lg[1].w = "|" end)
Bad("an unknown vault entry", function(r) r.gl.e[2].y = 42 end)
Bad("a tab that cannot be", function(r) r.gl.e[1].d = 9 end)
Bad("a vault entry later than its read", function(r) r.gl.e[3].t = t end)
local stats = Data.Stats(full)
local without = H.DeepCopy(full)
without.lg, without.gl = nil, nil
H.check(stats > Data.Stats(without), "a copy without the logs counts as less complete")

H.section("Log: a bank character who loses the rank")
before = #LogOf(bank, bank)
for _, member in ipairs(world.roster) do
    if member.guid == bank.guid then
        member.rank, member.rankIndex = "Miembro", 3
    end
end
world:RosterChanged()
world:FireEvent(bank, "GUILD_ROSTER_UPDATE", true)
world:RunFor(150)
world:Trade(bank, alice, {}, { [1] = { HERB, 2 } })
world:RunFor(2)
H.eq(#LogOf(bank, bank), before, "writes nothing more down")
world:RunFor(120)
H.check(#LogOf(alice, bank) > 0, "and its log stays")
Errors(world, "rank")
