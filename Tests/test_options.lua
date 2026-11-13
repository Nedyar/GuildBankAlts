local H = ...

-- The options (Options.lua) and the guild's rights they set (Ranks.lua).

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

local CLOTH = 2589

local world = H.NewWorld({ seed = 23, senderFormat = "short", strictWhispers = true, communities = H.FakeCommunities })
local master = world:NewClient("Guild Master", { rank = "GM", rankIndex = 0 })
local olga = world:NewClient("Olga Price", { rank = "Oficial", rankIndex = 1 })
local treasurer = world:NewClient("Tess Keeper", {
    rank = "Tesorero", rankIndex = 2, containers = { [0] = { size = 16, [1] = { CLOTH, 7 } } },
})
local alice = world:NewClient("Alice Smith", { rank = "Miembro", rankIndex = 3 })
local bank = world:NewClient("Bank Holder", {
    rank = "Banco", rankIndex = 4, money = 5000, containers = { [0] = { size = 16, [1] = { CLOTH, 20 } } },
})
local oldBank = world:NewClient("Old Bank", { rank = "Bank", rankIndex = 5 })
for _, client in ipairs({ master, olga, treasurer, alice, bank, oldBank }) do
    world:Login(client)
end
world:RunFor(120)

-- A client's options page, shown and filled in.
local function Page(client, name)
    local page = client.ns.Options.Page(name)
    page:Show()
    page:Refresh()
    return page
end

-- A grid's row for a rank, by its name.
local function RowFor(grid, name)
    return Find(grid.Rows, function(row)
        return row.rank and row.rank.name == name and row.Name:IsShown()
    end)
end

local function Click(check, on)
    check:SetChecked(on)
    check._scripts.OnClick(check)
end

H.section("Options: the defaults")
local Ranks = alice.ns.Ranks
H.eq(Ranks.Options(), nil, "no options until the guild master sets them")
H.eq(table.concat(Ranks.BankRanks(), ","), "Banco", "the bank rank: Banco")
H.check(Ranks.IsBank(bank.guid) and not Ranks.IsBank(oldBank.guid) and not Ranks.IsBank(treasurer.guid),
    "Bank is no longer a bank rank by default")
H.check(Ranks.Can(alice.guid, Ranks.LOG) and Ranks.Can(alice.guid, Ranks.MAKE) and not Ranks.CanAccept(alice.guid),
    "a member sees the log and makes requests, and does not answer them")
H.check(Ranks.CanAccept(olga.guid) and Ranks.CanReject(olga.guid) and Ranks.CanAccept(bank.guid),
    "the rank Oficial and the bank ranks answer requests")
H.check(Ranks.CanSee(alice.guid, bank.guid, Ranks.ITEMS) and Ranks.CanSee(alice.guid, bank.guid, Ranks.MONEY),
    "every rank sees each bank character's items and money")
local settings = alice.settings and alice.settings[1]
H.check(settings and settings.name == "Guild Bank Alts" and settings.registered and #settings.subcategories == 3,
    "the options are under Options > AddOns, with three pages for the guild's")
alice.env.SlashCmdList.GUILDBANKALTS("options")
world:RunFor(1)
H.eq(alice.openedSettings, "Guild Bank Alts", "/gbalts options opens them")
Errors(world, "defaults")

H.section("Options: only the guild master changes the guild's")
local aliceRanks = Page(alice, "ranks")
H.check(not aliceRanks.Add:IsEnabled() and not aliceRanks.Input:IsEnabled() and not aliceRanks.Rows[1].Remove:IsEnabled(),
    "a member sees the bank ranks greyed out")
H.check(aliceRanks.Status:GetText():find("only the guild master can change them", 1, true)
    and aliceRanks.Status:GetText():find("the defaults apply", 1, true), "and is told why, and that the defaults apply")
local aliceGrid = Page(alice, "permissions").Grid
H.check(not RowFor(aliceGrid, "Miembro").Checks[1]:IsEnabled(), "and the permissions too")
local added, why = Ranks.AddBankRank("Tesorero")
H.check(not added and why == "guildmaster" and not Ranks.SetRankFlag("Miembro", Ranks.MAKE, false),
    "nor can a member change them otherwise")
-- Options in another member's record count for nothing.
local olgaRecord = olga.ns.Data.GetOwnRecord(false)
olgaRecord.cf = { t = olga.ns.Now(), bn = { "Miembro" }, rp = {}, bv = {} }
olga.ns.Data.TouchOwn(olgaRecord)
world:RunFor(150)
H.check(alice.ns.Data.CurrentGuild(false).members[olga.guid].cf ~= nil and Ranks.Options() == nil and not Ranks.IsBank(alice.guid),
    "options in an officer's record are ignored")
Errors(world, "only the guild master")

H.section("Options: bank ranks")
local masterRanks = Page(master, "ranks")
H.check(masterRanks.Add:IsEnabled() and masterRanks.Status:GetText():find("You are the guild master", 1, true),
    "the guild master may change them")
H.check(masterRanks.Ranks:GetText():find("GM, Oficial, Tesorero, Miembro, Banco, Bank", 1, true), "the page lists the guild's ranks")
masterRanks.Input:SetText(" ")
masterRanks.Add._scripts.OnClick(masterRanks.Add)
H.eq(masterRanks.Error:GetText(), "Type a rank's name.", "a name is needed")
masterRanks.Input:SetText("banco")
masterRanks.Add._scripts.OnClick(masterRanks.Add)
H.eq(masterRanks.Error:GetText(), "That rank is already in the list.", "names are compared ignoring case")
H.check(not masterRanks.Rows[1].Remove:IsEnabled(), "the only bank rank cannot be removed")
masterRanks.Input:SetText(" Tesorero ")
masterRanks.Add._scripts.OnClick(masterRanks.Add)
H.check(masterRanks.Error:GetText() == "" and masterRanks.Rows[2].Name:GetText() == "Tesorero" and masterRanks.Input:GetText() == "",
    "added, trimmed")
world:RunFor(200)
H.check(Ranks.Options() ~= nil and Ranks.IsBank(treasurer.guid) and table.concat(Ranks.BankRanks(), ",") == "Banco,Tesorero",
    "every member sees it: the treasurer is a bank character")
H.check(aliceRanks:Refresh() == nil and aliceRanks.Status:GetText():find("Last changed", 1, true) ~= nil, "when they were changed shows")
local treasurerRecord = alice.ns.Data.CurrentGuild(false).members[treasurer.guid]
H.check(treasurerRecord and treasurerRecord.bk ~= nil, "and it shares what it holds")
H.check(Ranks.CanAccept(treasurer.guid), "a bank rank answers requests by default")
-- Removed again.
local tesorero = Find(masterRanks.Rows, function(row) return row.name == "Tesorero" end)
tesorero.Remove._scripts.OnClick(tesorero.Remove)
world:RunFor(200)
H.check(not Ranks.IsBank(treasurer.guid) and alice.ns.Data.CurrentGuild(false).members[treasurer.guid].bk == nil,
    "removed: no longer a bank character, it drops what it shared")
Errors(world, "bank ranks")

H.section("Options: permissions")
local grid = Page(master, "permissions").Grid
local masterRow = RowFor(grid, "GM")
H.check(masterRow.Checks[1]:GetChecked() and not masterRow.Checks[1]:IsEnabled(), "the guild master may do everything, always")
local memberRow = RowFor(grid, "Miembro")
H.check(memberRow.Checks[1]:GetChecked() and memberRow.Checks[2]:GetChecked() and not memberRow.Checks[3]:GetChecked()
    and memberRow.Checks[1]:IsEnabled(), "the grid shows each rank's: a member sees the log and makes requests")
-- An officer accepts a request; then the guild master takes accepting away.
local request = alice.ns.Requests.Create(bank.guid, "item:" .. CLOTH, 2, "", alice.ns.Requests.IN_PERSON)
world:RunFor(150)
H.check(olga.ns.Requests.Accept(alice.guid, request), "(an officer accepts a request)")
world:RunFor(150)
local function StateOf(client)
    local view = client.ns.Requests.Find(client.ns.Data.CurrentGuild(false), alice.guid, request)
    return view and view.state
end
H.eq(StateOf(alice), "accepted", "(accepted)")
Click(RowFor(grid, "Oficial").Checks[3], false)
world:RunFor(200)
H.check(not Ranks.CanAccept(olga.guid) and Ranks.CanReject(olga.guid), "the rank Oficial may no longer accept")
H.eq(StateOf(alice), "pending", "its acceptance no longer counts")
H.check(not olga.ns.Requests.MayAccept(olga.ns.Requests.Find(olga.ns.Data.CurrentGuild(false), alice.guid, request)),
    "nor may it accept again")
-- Members may no longer make requests.
Click(memberRow.Checks[2], false)
world:RunFor(200)
local id, reason = alice.ns.Requests.Create(bank.guid, "item:" .. CLOTH, 1, "", alice.ns.Requests.IN_PERSON)
H.check(id == nil and reason == "rank", "a member may no longer make requests")
local env = alice.env
env.GuildBankAltsGuildTab._scripts.OnClick(env.GuildBankAltsGuildTab)
local page = env.GuildBankAltsGuildPanel
local slot = page.Bank.Columns[1].Slots[1]
slot._scripts.OnEnter(slot)
H.check(table.concat(env.GameTooltip._lines, "\n"):find("Your rank may not make requests.", 1, true), "the item's tooltip says so")
slot._scripts.OnClick(slot, "RightButton")
H.check(env.GuildBankAltsRequestForm == nil or not env.GuildBankAltsRequestForm:IsShown(), "and right-clicking it opens no form")
-- Nor see the log.
Click(memberRow.Checks[1], false)
world:RunFor(200)
page.SubTabs.Tabs[3]._scripts.OnClick(page.SubTabs.Tabs[3])
H.check(#page.Log.ScrollBox._provider.elements == 0 and page.Log.Empty:IsShown()
    and page.Log.Empty:GetText() == "Your rank may not see the log.", "a member may no longer see the log")
H.check(bank.ns.Ranks.Can(bank.guid, Ranks.LOG), "(other ranks still do)")
-- As it was.
for column = 1, 3 do
    Click(memberRow.Checks[column], column <= 2)
end
Click(RowFor(grid, "Oficial").Checks[3], true)
world:RunFor(200)
H.check(Ranks.Can(alice.guid, Ranks.MAKE) and Ranks.Can(alice.guid, Ranks.LOG) and StateOf(alice) == "accepted",
    "given back, all is as it was")
Errors(world, "permissions")

H.section("Options: who sees each bank character")
local banksPage = Page(master, "banks")
H.check(banksPage.Bank:IsShown() and banksPage.Bank._text == "Bank Holder", "the page shows a bank character")
local bankRow = RowFor(banksPage.Grid, "Miembro")
H.check(bankRow.Checks[1]:GetChecked() and bankRow.Checks[2]:GetChecked(), "by default, members see its items and money")
Click(bankRow.Checks[1], false)
world:RunFor(200)
page.SubTabs.Tabs[1]._scripts.OnClick(page.SubTabs.Tabs[1])
local view = page.Bank
H.check(#view.banks == 1 and view.Empty:IsShown() and view.Empty:GetText() == "Your rank may not see what Bank Holder holds."
    and view.layout.columns == 0, "without its items, a member sees no slot, and is told why")
H.check(view.Money:GetText():find("On the character", 1, true) ~= nil, "but its money")
Click(bankRow.Checks[2], false)
world:RunFor(200)
alice.ns.BankView.Refresh(view)
H.check(#view.banks == 0 and view.Empty:GetText() == "Your rank may not see any bank character.",
    "without its money either, it is not in the dropdown")
H.check(bank.ns.Ranks.CanSee(bank.guid, bank.guid, Ranks.ITEMS) and master.ns.Ranks.CanSee(master.guid, bank.guid, Ranks.ITEMS)
    and olga.ns.Ranks.CanSee(olga.guid, bank.guid, Ranks.ITEMS), "a bank character sees its own, the guild master and other ranks all")
Click(bankRow.Checks[1], true)
Click(bankRow.Checks[2], true)
world:RunFor(200)
alice.ns.BankView.Refresh(view)
H.check(#view.banks == 1 and not view.Empty:IsShown() and view.layout.columns > 0, "given back, a member sees it all again")
Errors(world, "bank characters")

H.section("Options: a bank character hidden, its requests and log too")
-- A second bank character; the first gives the treasurer items (not Alice:
-- that would be a delivery for her request), and the second money; then
-- the treasurer asks the first for items.
H.check(master.ns.Ranks.AddBankRank("Bank"), "(the rank Bank made a bank rank)")
world:RunFor(200)
H.check(oldBank.ns.Ranks.IsBank(oldBank.guid), "(Old Bank is a bank character)")
world:Trade(bank, treasurer, { [1] = { CLOTH, 1 } }, {})
world:Trade(bank, oldBank, {}, {}, { aMoney = 701 })
local theirs = treasurer.ns.Requests.Create(bank.guid, "item:" .. CLOTH, 1, "", treasurer.ns.Requests.IN_PERSON)
world:RunFor(200)
local function Shown(client)
    local shown = {}
    for _, each in ipairs(client.ns.RequestList.Views(false, false)) do
        shown[each.key] = true
    end
    return shown
end
local mineKey, theirsKey = alice.ns.Requests.Key(alice.guid, request), alice.ns.Requests.Key(treasurer.guid, theirs)
H.check(theirs and Shown(alice)[mineKey] and Shown(alice)[theirsKey], "(a member sees every request)")
local function LogLines()
    page.SubTabs.Tabs[3]._scripts.OnClick(page.SubTabs.Tabs[3])
    return page.Log.ScrollBox._provider.elements
end
-- A bank character's line among the list's elements (or LogView.Lines').
local function BankLine(elements, owner, fn)
    return Find(elements, function(e)
        local line = e.line or e
        return line.source == "bank" and line.bank == owner.guid and fn(line.entry)
    end)
end
local function ItemOut(entry) return entry.i == CLOTH and entry.w == "Tess Keeper" end
local function Money701(entry) return entry.m == 701 end
local elements = LogLines()
local given = BankLine(elements, bank, Money701)
H.check(BankLine(elements, bank, ItemOut) and given and given.line.pair and not BankLine(elements, oldBank, Money701),
    "(a member sees the items given, and the money as the giver's line)")
-- Its items hidden from members.
H.check(master.ns.Ranks.SetBankFlag(bank.guid, "Miembro", Ranks.ITEMS, false), "(members may not see Bank Holder's items)")
world:RunFor(200)
H.check(not Shown(alice)[theirsKey], "a member no longer sees the requests made to it")
H.check(Shown(alice)[mineKey], "but their own")
elements = LogLines()
H.check(not BankLine(elements, bank, ItemOut), "nor its items in the log")
H.check(BankLine(elements, bank, Money701) ~= nil, "but its money, which they may see")
H.check(Shown(olga)[theirsKey] and BankLine(olga.ns.LogView.Lines({ items = true, money = true, banks = true, vault = true }), bank, ItemOut),
    "other ranks still see them")
-- Its money too.
H.check(master.ns.Ranks.SetBankFlag(bank.guid, "Miembro", Ranks.MONEY, false), "(nor its money)")
world:RunFor(200)
elements = LogLines()
local taken = BankLine(elements, oldBank, Money701)
H.check(not BankLine(elements, bank, Money701) and taken ~= nil,
    "without its money, the money it gave shows as the other bank character's line")
local row = H.NewObject(alice, "Frame")
page.Log.ScrollBox._view.init(row, taken)
row._scripts.OnEnter(row)
local tip = table.concat(alice.env.GameTooltip._lines, "\n")
local _, balances = tip:gsub("Balance before", "")
H.check(balances == 1 and not tip:find("Bank Holder", 1, true), "whose tooltip leaves out Bank Holder's money")
-- Answers: an officer who may not see its items may not answer its
-- requests, and their answers no longer count.
H.eq(StateOf(alice), "accepted", "(the officer's acceptance counts)")
H.check(master.ns.Ranks.SetBankFlag(bank.guid, "Oficial", Ranks.ITEMS, false), "(officers may not see Bank Holder's items)")
world:RunFor(200)
H.eq(StateOf(alice), "pending", "an officer's acceptance no longer counts")
H.check(not Shown(olga)[theirsKey], "the officer no longer sees its requests")
local olgaView = olga.ns.Requests.Find(olga.ns.Data.CurrentGuild(false), treasurer.guid, theirs)
H.check(not olga.ns.Requests.CanReject(olgaView) and not olga.ns.Requests.MayAccept(olgaView)
    and not olga.ns.Requests.Reject(treasurer.guid, theirs), "nor may answer them")
H.check(Shown(master)[theirsKey] and Shown(bank)[theirsKey] and bank.ns.Requests.CanReject(
    bank.ns.Requests.Find(bank.ns.Data.CurrentGuild(false), treasurer.guid, theirs)),
    "the guild master and the bank character itself still see and answer them")
-- As it was.
for _, rank in ipairs({ "Miembro", "Oficial" }) do
    master.ns.Ranks.SetBankFlag(bank.guid, rank, Ranks.ITEMS, true)
    master.ns.Ranks.SetBankFlag(bank.guid, rank, Ranks.MONEY, true)
end
H.check(master.ns.Ranks.RemoveBankRank("Bank"), "(the rank Bank a bank rank no more)")
treasurer.ns.Requests.Delete(theirs)
world:RunFor(200)
H.check(StateOf(alice) == "accepted" and Shown(alice)[mineKey] and BankLine(LogLines(), bank, ItemOut) ~= nil,
    "given back, all is as it was")
Errors(world, "a bank character hidden")

H.section("Options: the language")
local main = Page(alice, "main")
local menu = main.Language._menu
H.eq(main.Language._text, "The client's language", "the client's language at first")
Find(menu, function(entry) return entry.data == "esES" end).setSelected("esES")
H.check(alice.ns.db.settings.locale == "esES" and alice.ns.LOCALE == "esES", "a language is chosen")
Find(menu, function(entry) return entry.data == "auto" end).setSelected("auto")
H.check(alice.ns.db.settings.locale == nil and alice.ns.LOCALE == alice.ns.CLIENT_LOCALE, "and the client's again")
Errors(world, "language")

H.section("Options: packed")
local Pack = master.ns.Pack
local own = master.ns.Data.GetOwnRecord(false)
H.check(own.cf and own.cf.bn and own.cf.rp.miembro ~= nil and own.cf.bv[bank.guid] ~= nil, "(the guild master's record has them)")
local _, back = Pack.ReadRecord(Pack.Reader(Pack.RecordString(master.guid, own)))
local clean = master.ns.Data.CleanRecord(back, master.ns.Now())
H.check(clean and master.ns.Same(clean.cf, own.cf), "they pack and read back as they were")
local bad = H.DeepCopy(own)
bad.cf.rp.miembro = 99
_, back = Pack.ReadRecord(Pack.Reader(Pack.RecordString(master.guid, bad)))
H.eq(master.ns.Data.CleanRecord(back, master.ns.Now()), nil, "options that cannot be trusted make the record refused")
-- Options in a later format: skipped, the record kept.
local plain = H.DeepCopy(own)
plain.cf = nil
local reader = Pack.Reader(Pack.RecordString(master.guid, plain))
reader:UInt()
local body = reader.s:sub(reader.pos)
local later = Pack.Writer()
later:UInt(2)
later:Str("something new")
local field = Pack.Writer()
field:Str(later:Result())
local whole = Pack.Writer()
whole:Str(body .. field:Result())
_, back = Pack.ReadRecord(Pack.Reader(whole:Result()))
clean = master.ns.Data.CleanRecord(back, master.ns.Now())
H.check(clean ~= nil and clean.cf == nil, "options in a later format are skipped, the record kept")
H.check(Pack.RecordString(alice.guid, alice.ns.Data.GetOwnRecord(false)) ~= nil
    and alice.ns.Data.GetOwnRecord(false).cf == nil, "(other records pack as before)")
Errors(world, "packed")
