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

local function Printed(client, text, since)
    for i = (since or 0) + 1, #client.printed do
        if client.printed[i]:find(text, 1, true) then
            return true
        end
    end
    return false
end

local function Link(itemID, enchant)
    return ("|cffffffff|Hitem:%d:%s::::::12345:60:::::|h[Item%d]|h|r"):format(itemID, enchant or "", itemID)
end

local CLOTH, ORE, HERB, SWORD = 2589, 2771, 8545, 12345

local world = H.NewWorld({ seed = 11, senderFormat = "short", strictWhispers = true, communities = H.FakeCommunities })
world.maxStacks = { [SWORD] = 1 }
local SMALL_BAG, BANK_BAG = 4240, 4500
-- The backpack (16 slots), a bag of 10 in bag slot 1, bag slots 2 to 5
-- empty; the bank's 48 slots, bank bag slot 2 with a bag of 12, slot 3
-- bought but empty, slot 4 not bought.
local bank = world:NewClient("Bank Holder", {
    rank = "Banco", rankIndex = 4, money = 1234567,
    containers = {
        [0] = { size = 16, [1] = { CLOTH, 20 }, [2] = { CLOTH, 15 }, [3] = { ORE, 5 }, [4] = { SWORD, 1, Link(SWORD, "1900") } },
        [1] = { size = 10, [1] = { CLOTH, 5 } },
        [6] = { size = 48, [1] = { ORE, 40 }, [2] = { HERB, 10 } },
        [7] = { size = 12, [3] = { HERB, 2 } },
    },
    bagItems = { [1] = SMALL_BAG },
    bankTabs = { 6, 7, 8 }, maxBankTabs = 4, bankBags = { [2] = BANK_BAG },
})
local alice = world:NewClient("Alice Smith", { rank = "Miembro", rankIndex = 3 })
local olga = world:NewClient("Olga Price", { rank = "Oficial", rankIndex = 1 })
local mike = world:NewClient("Mike Stone", { rank = "Miembro", rankIndex = 3 })
local gus = world:NewClient("Gus Hall", { rank = "GM", rankIndex = 0 })

H.section("Bank: what a bank character holds")
world:Login(bank)
world:RunFor(10)
Errors(world, "bank login")
local record = bank.ns.Data.GetOwnRecord(false)
local bk = record and record.bk
H.check(bk ~= nil, "a bank character shares what it holds")
if bk then
    H.eq(bk.m, 1234567, "its money")
    H.eq(#bk.b, 6, "the backpack and the five bag slots")
    local backpack = bk.b[1]
    H.check(backpack.id == 0 and backpack.z == 16 and backpack.bi == nil, "the backpack, with its slots")
    H.check(backpack.s[1].i == CLOTH and backpack.s[1].n == 20 and backpack.s[2].n == 15, "stacks as they are, slot by slot")
    H.check(backpack.s[1].s == nil, "a plain item keeps no item string")
    H.check(backpack.s[4].s and backpack.s[4].s:find("^item:12345:1900:") ~= nil, "an enchanted item keeps its item string")
    H.eq(backpack.s[5], nil, "an empty slot stays empty")
    H.check(bk.b[2].z == 10 and bk.b[2].bi and bk.b[2].bi:find("^item:4240") ~= nil, "a bag slot with its bag")
    H.check(bk.b[3].z == 0 and bk.b[3].bi == nil, "an empty bag slot")
    H.eq(bk.k, nil, "the bank is unknown until it is opened")
    H.eq(type(bk.bt), "number", "when the bags were read")
end
world:OpenBank(bank)
world:RunFor(3)
bk = bank.ns.Data.GetOwnRecord(false).bk
H.eq(bk.k and #bk.k, 4, "the bank and its three bank bag slots, read while open")
H.check(bk.k[1].id == 6 and bk.k[1].z == 48 and bk.k[1].s[1].n == 40, "the bank's own slots")
H.check(bk.k[2].id == 7 and bk.k[2].z == 12 and bk.k[2].bi and bk.k[2].bi:find("^item:4500") ~= nil and bk.k[2].s[3].i == HERB,
    "a bank bag slot with its bag and its items")
H.check(bk.k[3].z == 0 and not bk.k[3].lk and bk.k[3].bi == nil, "a bank bag slot bought, but empty")
H.check(bk.k[4].lk == true, "a bank bag slot not bought")
H.eq(type(bk.kt), "number", "when the bank was read")
world:CloseBank(bank)
world:SetContainer(bank, 0, { size = 16, [1] = { CLOTH, 20 } })
world:RunFor(3)
bk = bank.ns.Data.GetOwnRecord(false).bk
H.check(bk.b[1].s[2] == nil and bk.b[1].s[1].n == 20, "a change in the bags is read")
H.eq(bk.k and #bk.k, 4, "the bank, closed, keeps its last read")
-- Opened before the game has loaded the bank tabs (no slots): the last
-- read stays.
local loadedTabs = { bank.containers[6], bank.containers[7] }
bank.containers[6], bank.containers[7] = nil, nil
world:OpenBank(bank)
world:RunFor(3)
bk = bank.ns.Data.GetOwnRecord(false).bk
H.check(bk.k and bk.k[1].z == 48, "a bank not loaded yet keeps its last read")
world:CloseBank(bank)
bank.containers[6], bank.containers[7] = loadedTabs[1], loadedTabs[2]
world:SetMoney(bank, 500)
world:RunFor(3)
H.eq(bank.ns.Data.GetOwnRecord(false).bk.m, 500, "a change of money is read")
-- The bank opened through the game's player interactions, as on Retail.
bank.containers[6][3] = { HERB, 7 }
bank.atBank = true
world:FireEvent(bank, "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", H.BANKER)
world:RunFor(3)
world:FireEvent(bank, "PLAYER_INTERACTION_MANAGER_FRAME_HIDE", H.BANKER)
bank.atBank = false
H.eq(bank.ns.Data.GetOwnRecord(false).bk.k[1].s[3] and bank.ns.Data.GetOwnRecord(false).bk.k[1].s[3].n, 7,
    "a bank opened through the player interactions is read too")
bank.containers[6][3] = nil
-- Back to the first bags for the rest.
world:SetContainer(bank, 0, { size = 16, [1] = { CLOTH, 20 }, [2] = { CLOTH, 15 }, [3] = { ORE, 5 }, [4] = { SWORD, 1, Link(SWORD, "1900") } })
world:RunFor(3)

H.section("Bank: other characters")
world:Login(alice)
world:Login(olga)
world:Login(mike)
world:Login(gus)
world:RunFor(150)
Errors(world, "members login")
H.eq(alice.ns.Data.GetOwnRecord(false).bk, nil, "a member who is not a bank character shares nothing")
local banks = alice.ns.BankView.Banks(alice.ns.Data.CurrentGuild(false))
H.eq(#banks, 1, "one bank character in the guild")
H.check(banks[1] and banks[1].bank and banks[1].bank.k ~= nil, "others see its bags and bank")
H.eq(alice.ns.BankView.Holding(banks[1].bank, CLOTH), 40, "how many of an item it holds")
H.check(alice.ns.Ranks.IsBank(bank.guid) and not alice.ns.Ranks.IsBank(alice.guid), "the bank rank, by name")
H.check(alice.ns.Ranks.IsOfficer(olga.guid) and alice.ns.Ranks.IsOfficer(gus.guid) and not alice.ns.Ranks.IsOfficer(mike.guid),
    "officers: the rank Oficial and the guild master")

H.section("Requests: making them")
local Requests = alice.ns.Requests
local IN_PERSON, BY_MAIL = Requests.IN_PERSON, Requests.BY_MAIL
local id, reason = Requests.Create(bank.guid, "item:" .. CLOTH, 0, "", IN_PERSON)
H.check(not id and reason == "quantity", "a quantity of 0 is refused")
id, reason = Requests.Create(mike.guid, "item:" .. CLOTH, 1, "", IN_PERSON)
H.check(not id and reason == "bank", "a request to someone who is not a bank character is refused")
id, reason = Requests.Create(bank.guid, "item:" .. CLOTH, 1, "")
H.check(not id and reason == "delivery", "a request without a delivery is refused")
id, reason = Requests.Create(bank.guid, "item:" .. CLOTH, 1, "", 3)
H.check(not id and reason == "delivery", "and with an unknown one")
local first = Requests.Create(bank.guid, "item:" .. CLOTH, 20, "For the cloak", BY_MAIL)
H.check(first ~= nil, "a request is made")
local view = Requests.Find(alice.ns.Data.CurrentGuild(false), alice.guid, first)
H.eq(view and view.state, "pending", "it is pending")
H.eq(view and view.request.nt, "For the cloak", "with its note")
H.eq(view and view.request.d, BY_MAIL, "and how it is to be delivered")
world:RunFor(150)
local atBank = bank.ns.Requests.Find(bank.ns.Data.CurrentGuild(false), alice.guid, first)
H.eq(atBank and atBank.state, "pending", "the bank character sees it")
H.eq(atBank and atBank.request.d, BY_MAIL, "by mail, for the bank character too")
H.check(Printed(bank, "Alice Smith requests from your bank"), "and is told")
H.check(Printed(bank, "Delivery: By mail: 30|TInterface\\MoneyFrame\\UI-CopperIcon"), "how to deliver it, and the fee")
H.eq(bank.ns.RequestList.WaitingForMe(), 1, "one request waits for the bank character")
H.eq(alice.ns.RequestList.WaitingForMe(), 0, "none waits for a member")
Errors(world, "request made")

H.section("Requests: rejecting and deleting")
local second = Requests.Create(bank.guid, "item:" .. HERB, 5, "", IN_PERSON)
world:RunFor(150)
local function ViewAt(client, requesterGUID, requestID)
    return client.ns.Requests.Find(client.ns.Data.CurrentGuild(false), requesterGUID, requestID)
end
H.eq(ViewAt(olga, alice.guid, second).request.d, IN_PERSON, "in person, for everyone")
H.check(not mike.ns.Requests.Reject(alice.guid, second), "a member cannot reject")
H.check(not alice.ns.Requests.Reject(alice.guid, second), "nobody rejects their own request")
H.check(olga.ns.Requests.Reject(alice.guid, second), "an officer rejects it")
world:RunFor(150)
H.eq(ViewAt(alice, alice.guid, second).state, "rejected", "rejected for its requester")
H.eq(ViewAt(bank, alice.guid, second).rejecter, olga.guid, "and for the bank, by the officer")
H.check(Printed(alice, "Olga Price rejected your request"), "the requester is told")
H.check(alice.ns.Requests.Delete(second), "a rejected request can be deleted")
world:RunFor(150)
H.eq(ViewAt(bank, alice.guid, second), nil, "deleted everywhere")
local third = Requests.Create(bank.guid, "item:" .. ORE, 2, "", IN_PERSON)
world:RunFor(150)
H.check(gus.ns.Requests.Reject(alice.guid, third), "the guild master rejects")
world:RunFor(150)
H.eq(ViewAt(alice, alice.guid, third).state, "rejected", "rejected by the guild master")
Errors(world, "reject and delete")

H.section("Requests: deliveries")
-- A trade of part of it: partial.
world:Trade(bank, alice, { [1] = { CLOTH, 10 } }, {})
world:RunFor(150)
H.eq(ViewAt(alice, alice.guid, first).state, "partial", "half delivered by trade: partial")
H.eq(ViewAt(olga, alice.guid, first).delivered, 10, "10 delivered, for everyone")
H.check(Printed(bank, "10 of 20 delivered to Alice Smith"), "the bank character is told")
H.check(Printed(alice, "10 of 20 delivered for your request"), "and so is the requester")
-- The rest by mail: approved.
world:Mail(bank, "Alice Smith", { [1] = { CLOTH, 10 } })
world:RunFor(150)
H.eq(ViewAt(alice, alice.guid, first).state, "approved", "the rest by mail: approved")
H.eq(ViewAt(mike, alice.guid, first).state, "approved", "approved for everyone")
H.check(Printed(alice, "your request was delivered"), "the requester is told")
H.check(not alice.ns.Requests.Delete(first), "an approved request cannot be deleted")
H.check(not olga.ns.Requests.Reject(alice.guid, first), "nor rejected")
H.eq(bank.ns.RequestList.WaitingForMe(), 0, "nothing waits for the bank any more")
-- A rejected request delivered anyway is approved.
world:Trade(bank, alice, { [1] = { ORE, 2 } }, {})
world:RunFor(150)
H.eq(ViewAt(alice, alice.guid, third).state, "approved", "a rejected request delivered anyway is approved")
Errors(world, "deliveries")

H.section("Requests: deliveries count oldest first, and only from a bank")
local older = Requests.Create(bank.guid, "item:" .. HERB, 3, "", IN_PERSON)
world:RunFor(5)
local newer = Requests.Create(bank.guid, "item:" .. HERB, 4, "", IN_PERSON)
world:RunFor(150)
world:Mail(bank, "Alice Smith", { [1] = { HERB, 5 } })
world:RunFor(150)
H.eq(ViewAt(alice, alice.guid, older).state, "approved", "the older request is served first")
H.eq(ViewAt(alice, alice.guid, newer).delivered, 2, "the rest goes to the newer one")
world:Trade(mike, alice, { [1] = { HERB, 2 } }, {})
world:RunFor(150)
H.eq(ViewAt(alice, alice.guid, newer).delivered, 2, "a member who is not a bank character delivers nothing")
world:Trade(bank, alice, { [1] = { HERB, 2 } }, {}, { cancel = true })
world:RunFor(150)
H.eq(ViewAt(alice, alice.guid, newer).delivered, 2, "a cancelled trade delivers nothing")
world:Mail(bank, "Alice Smith", { [1] = { HERB, 2 } }, { fail = true })
world:RunFor(150)
H.eq(ViewAt(alice, alice.guid, newer).delivered, 2, "a mail the game refuses delivers nothing")
Errors(world, "oldest first")

H.section("Requests: limits")
local made = 0
for _ = 1, 40 do
    if alice.ns.Requests.Create(bank.guid, "item:" .. CLOTH, 1, "", IN_PERSON) then
        made = made + 1
    end
end
local own = alice.ns.Data.GetOwnRecord(false)
local count = 0
for _ in pairs(own.rq) do
    count = count + 1
end
H.eq(count, alice.ns.Pack.LIMITS.requests, "no more requests than the limit")
local _, full = alice.ns.Requests.Create(bank.guid, "item:" .. CLOTH, 1, "", IN_PERSON)
H.eq(full, "full", "and it says so")
for requestID, request in pairs(own.rq) do
    if request.i == CLOTH and requestID ~= first then
        alice.ns.Requests.Delete(requestID)
    end
end
world:RunFor(150)
Errors(world, "limits")

H.section("Requests: closed ones are dropped after a week")
local beforeKey = alice.ns.Requests.Key(alice.guid, first)
H.check(bank.ns.Data.GetOwnRecord(false).ra[beforeKey] ~= nil, "the bank's answer is there")
world.base = world.base + 8 * 86400
world:FireEvent(alice, "GUILD_ROSTER_UPDATE", false)
world:RunFor(200)
H.eq(alice.ns.Data.GetOwnRecord(false).rq[first], nil, "an approved request is dropped after a week")
world:RunFor(200)
H.eq(bank.ns.Data.GetOwnRecord(false).ra[beforeKey], nil, "and then the answer to it")
Errors(world, "pruning")

H.section("Bank: a bank character who loses the rank")
for _, member in ipairs(world.roster) do
    if member.guid == bank.guid then
        member.rank, member.rankIndex = "Miembro", 3
    end
end
world:RosterChanged()
world:FireEvent(bank, "GUILD_ROSTER_UPDATE", true)
world:RunFor(150)
H.eq(bank.ns.Data.GetOwnRecord(false).bk, nil, "its bank data is dropped")
H.eq(#alice.ns.BankView.Banks(alice.ns.Data.CurrentGuild(false)), 0, "and others no longer list it")
local _, gone = alice.ns.Requests.Create(bank.guid, "item:" .. CLOTH, 1, "", IN_PERSON)
H.eq(gone, "bank", "requests to it are refused")
for _, member in ipairs(world.roster) do
    if member.guid == bank.guid then
        member.rank, member.rankIndex = "Banco", 4
    end
end
world:RosterChanged()
world:FireEvent(bank, "GUILD_ROSTER_UPDATE", true)
world:RunFor(150)
H.check(bank.ns.Data.GetOwnRecord(false).bk ~= nil, "given the rank back, it shares again")
H.eq(bank.ns.Data.GetOwnRecord(false).bk.k, nil, "its bank, once it opens it again")
world:OpenBank(bank)
world:RunFor(3)
world:CloseBank(bank)
world:RunFor(150)
H.check(bank.ns.Data.GetOwnRecord(false).bk.k ~= nil, "which it does")
Errors(world, "rank lost")

H.section("Pack: bank, requests and answers")
local ns = alice.ns
local now = ns.Now()
local sample = {
    t = now,
    bk = {
        m = 99, bt = now, kt = now,
        b = { { id = 0, z = 16, s = { [1] = { i = 1, n = 2 }, [5] = { i = 3, n = 4, s = "item:3:1900::" } } },
              { id = 1, z = 10, bi = "item:4240::", s = {} } },
        k = { { id = 6, z = 48, s = { [48] = { i = 5, n = 6 } } }, { id = 7, z = 0, s = {}, lk = true } },
    },
    rq = { [7] = { b = bank.guid, i = 8, q = 9, c = now, nt = "note" },
           [8] = { b = bank.guid, i = 8, q = 1, c = now, nt = "", d = 2 } },
    ra = { [alice.guid .. ":7"] = { s = 2, n = 3, u = now } },
    gb = { m = 123456, t = now },
}
local _, back = ns.Pack.ReadRecord(ns.Pack.Reader(ns.Pack.RecordString(alice.guid, sample)))
H.check(ns.Same(back.bk, sample.bk), "bank data round trip, slot by slot")
H.check(ns.Same(back.rq, sample.rq), "requests round trip, with how they are to be delivered")
H.check(ns.Same(back.ra, sample.ra), "answers round trip")
H.check(ns.Same(back.gb, sample.gb), "the guild bank's money round trip")
local empty = { t = now, rq = {}, ra = {} }
_, back = ns.Pack.ReadRecord(ns.Pack.Reader(ns.Pack.RecordString(alice.guid, empty)))
H.check(back.rq ~= nil and next(back.rq) == nil and back.ra ~= nil and back.bk == nil, "no requests is told apart from unknown")
local function Bad(change)
    local copy = H.DeepCopy(sample)
    change(copy)
    return ns.Data.CleanRecord(copy, now) == nil
end
H.check(ns.Data.CleanRecord(H.DeepCopy(sample), now) ~= nil, "a good record passes")
H.check(Bad(function(r) r.rq[7].q = 0 end), "a request for 0 is refused")
H.check(Bad(function(r) r.rq[7].b = "nobody" end), "a request to a bad GUID is refused")
H.check(Bad(function(r) r.ra["bad key"] = { s = 1, u = now } end), "an answer with a bad key is refused")
H.check(Bad(function(r) r.ra[alice.guid .. ":7"].s = 9 end), "an answer of an unknown kind is refused")
H.check(Bad(function(r) r.bk.b[1].s[1].s = "|Hitem:1|h" end), "an item string with escapes is refused")
H.check(Bad(function(r) r.bk.b[1].s[17] = { i = 1, n = 1 } end), "an item past a container's last slot is refused")
H.check(Bad(function(r) r.bk.b[2].bi = "|Hitem:1|h" end), "a bag with escapes is refused")
H.check(Bad(function(r) r.gb.m = -1 end), "a bad guild bank money is refused")
local unknownDelivery = H.DeepCopy(sample)
unknownDelivery.rq[8].d = 7
H.eq(ns.Data.CleanRecord(unknownDelivery, now).rq[8].d, nil, "an unknown delivery is dropped, the request kept")
local noted = H.DeepCopy(sample)
noted.rq[7].nt = ("ñ"):rep(100) .. "|cffff0000"
local cleaned = ns.Data.CleanRecord(noted, now)
H.check(cleaned and #cleaned.rq[7].nt <= ns.Pack.LIMITS.note and not cleaned.rq[7].nt:find("|", 1, true),
    "a long note is cut, without escape sequences")
H.check(cleaned and (cleaned.rq[7].nt:gsub("ñ", "")) == "", "and cut at a character boundary")
H.eq(ns.Bank.Meaningful("item:2589:::::::::::::"), nil, "a plain item string says nothing more than the ID")
H.check(ns.Bank.Meaningful("item:4314:::::::::::::::::Player-1-00000001:") ~= nil, "a crafted item's does")
H.check(ns.Bank.Meaningful("item:15309::::::::::::1:12734::::::") ~= nil, "and so do bonus IDs")

H.section("The guild window tab")
local env = alice.env
local frame = env.CommunitiesFrame
local tab = env.GuildBankAltsGuildTab
H.check(tab ~= nil, "a tab on the guild window")
H.eq(tab._point and tab._point[2], frame.GuildInfoTab, "under Guild Info")
H.check(type(env.GuildWindowAddonPanels) == "table" and #env.GuildWindowAddonPanels == 1, "registered in the shared list")
-- Another addon's panel, open: ours closes it, and takes its remembered tab.
local closed = 0
local otherTab = H.NewObject(alice, "CheckButton")
table.insert(env.GuildWindowAddonPanels, 1, { id = "Other", order = 10, tab = otherTab, Close = function()
    closed = closed + 1
    return frame.RosterTab
end })
frame.UpdateCommunitiesTabs(frame)
H.eq(tab._point and tab._point[2], otherTab, "under another addon's tab of a lower order")
frame.RosterTab:SetChecked(false)
tab._scripts.OnClick(tab)
local page = env.GuildBankAltsGuildPanel
H.check(page:IsShown(), "the panel opens")
H.eq(closed, 1, "and closes the other addon's")
H.eq(frame.MemberList:GetAlpha(), 0, "Blizzard's view is made invisible")
-- The other addon opens its panel: ours closes, and gives back the tab.
local ourEntry = Find(env.GuildWindowAddonPanels, function(entry) return entry.id == "GuildBankAlts" end)
H.eq(ourEntry.Close(), frame.RosterTab, "closing for another addon gives back the tab selected before")
H.check(not page:IsShown(), "our panel is closed")
H.eq(frame.MemberList:GetAlpha(), 1, "and Blizzard's view shown again")
table.remove(env.GuildWindowAddonPanels, 1)
-- An older Guild Professions & Recipes, not registered: under its tab.
env.GuildProfessionsRecipesGuildTab = H.NewObject(alice, "CheckButton")
frame.UpdateCommunitiesTabs(frame)
H.eq(tab._point and tab._point[2], env.GuildProfessionsRecipesGuildTab, "under an older Guild Professions & Recipes tab")
env.GuildProfessionsRecipesGuildTab = nil
-- Blizzard's tab clicked: closed.
tab._scripts.OnClick(tab)
frame:SetDisplayMode("Chat")
H.check(not page:IsShown(), "a Blizzard tab closes the panel")
Errors(world, "tab")

H.section("The Bank subtab and the request form")
tab._scripts.OnClick(tab)
local view = page.Bank
-- The bank character, chosen in a dropdown.
H.eq(view.Dropdown._text, "Bank Holder", "the dropdown shows the bank character")
H.check(#view.Dropdown._menu == 1 and view.Dropdown._menu[1].kind == "radio", "and lists the bank characters to choose from")
-- Its slots, one by one: the backpack's 16, the bag's 10, the bank's 48
-- and the bank bag's 12 (the empty bag slots have none): 86, in columns
-- of 14 like the guild bank's: 7 columns, the last with 2 slots.
local bankEntry = alice.ns.BankView.Banks(alice.ns.Data.CurrentGuild(false))[1]
local cells = alice.ns.BankView.Cells(bankEntry.bank)
H.eq(#cells, 86, "as many slots as it has, bags and bank")
H.check(cells[1].item.i == CLOTH and cells[1].item.n == 20 and cells[2].item.n == 15, "stacks as they are, in their slots")
H.check(cells[5].item == nil and cells[17].item and cells[17].item.n == 5 and cells[17].container == 1, "empty slots too, then the next bag")
H.check(cells[27].item and cells[27].item.n == 40 and cells[27].container == 6, "then the bank")
H.check(cells[77].item and cells[77].item.i == HERB and cells[77].container == 7, "then the bank bag")
-- In the room the tests give (536 x 288 inside the frame), one row of 7 at
-- about 0.75 beats two rows of 4.
local layout = view.layout
H.eq(layout.columns, 7, "seven columns of 14 slots")
H.eq(layout.across, 7, "all in one row")
H.eq(layout.rows, 1, "no second row")
H.check(layout.scale > 0.74 and layout.scale < 0.75, "scaled down to fit, not scrolled (" .. layout.scale .. ")")
H.eq(view.Canvas._scale, layout.scale, "the slots are drawn at that scale")
local lastColumn = view.Columns[7]
H.check(not lastColumn.Slots[2].Blocked:IsShown() and lastColumn.Slots[3].Blocked:IsShown() and lastColumn.Slots[14].Blocked:IsShown(),
    "the slots past the 86th are blocked")
H.eq(view.Columns[2]._point and view.Columns[2]._point[4], 103, "side by side, 3 px apart, as in the guild bank")
local slot = view.Columns[1].Slots[1]
H.check(slot.item ~= nil and slot.item.i == CLOTH and slot.Count:GetText() == 20, "a stack in the first slot")
H.check(view.Columns[1].Slots[5].item == nil and not view.Columns[1].Slots[5].Blocked:IsShown(), "an empty slot")
-- Its bag slots, at the top.
local bagKinds = {}
for i, button in ipairs(view.Bags) do
    if button:IsShown() then
        bagKinds[i] = button.entry.kind
    end
end
H.eq(table.concat(bagKinds, ","), "backpack,bag,bag,bag,bag,bag,bank,bankbag,bankbag,bankbag",
    "the backpack, the bag slots, the bank and its bank bag slots")
H.check(view.Bags[2].Icon:IsShown() and view.Bags[2].entry.container.bi ~= nil, "a bag slot shows its bag")
H.check(view.Bags[3].Icon:IsShown() and view.Bags[3].entry.container.bi == nil, "an empty bag slot shows the empty slot")
H.check(view.Bags[8].entry.container.bi ~= nil and not view.Bags[8].Lock:IsShown(), "a bank bag slot with its bag")
H.check(not view.Bags[9].Icon:IsShown() and not view.Bags[9].Lock:IsShown(), "a bank bag slot bought, but empty")
H.check(view.Bags[10].Lock:IsShown(), "a bank bag slot not bought, locked")
-- Pointing at a bag lights up its slots, as the game's bank does.
view.Bags[2]._scripts.OnEnter(view.Bags[2])
H.check(view.Columns[2].Slots[3].Glow:IsShown() and view.Columns[2].Slots[12].Glow:IsShown(), "pointing at a bag lights up its slots")
H.check(not view.Columns[1].Slots[1].Glow:IsShown() and not view.Columns[2].Slots[13].Glow:IsShown(), "and only those")
view.Bags[2]._scripts.OnLeave(view.Bags[2])
H.check(not view.Columns[2].Slots[3].Glow:IsShown(), "until the pointer leaves")
-- At the bottom: the guild bank's money (not seen yet), the character's,
-- and the clock telling when each was seen.
local function Coins(gold, silver, copper)
    local icon = "|TInterface\\MoneyFrame\\UI-%sIcon:0:0:2:0|t"
    return ("%s%s %s%s %s%s"):format(gold, icon:format("Gold"), silver, icon:format("Silver"), copper, icon:format("Copper"))
end
H.eq(alice.ns.BankView.Money(0), Coins(0, 0, 0), "money shows every coin, a plain 0 when there is none")
H.eq(alice.ns.BankView.Money(1234567), Coins(123, 45, 67), "gold, silver and copper")
H.eq(alice.ns.BankView.Money(10000), Coins(1, 0, 0), "silver and copper at 0 are still shown")
H.eq(view.GuildMoney:GetText(), "In the bank: -", "the guild bank's money, not seen yet")
H.eq(view.Money:GetText(), "On the character: " .. Coins(0, 5, 0), "the character's money")
H.check(view.Footer:IsShown(), "both in the gold frame under the slots")
local tooltipLines = {}
local addLine = rawget(env.GameTooltip, "AddLine")
rawset(env.GameTooltip, "AddLine", function(_, text)
    tooltipLines[#tooltipLines + 1] = text
end)
view.Clock._scripts.OnEnter(view.Clock)
H.check(tooltipLines[1] and tooltipLines[1]:find("^Bags seen ") and tooltipLines[2]:find("^Bank seen ")
    and tooltipLines[3]:find("^Guild money not seen yet"), "the clock tells when each was seen")
world:OpenGuildBank(olga, 1234)
world:RunFor(150)
world:CloseGuildBank(olga)
tab._scripts.OnClick(tab)
ns.GuildTab.Refresh()
H.eq(view.GuildMoney:GetText(), "In the bank: " .. Coins(0, 12, 34), "whoever opens the guild bank shares its money")
tooltipLines = {}
view.Clock._scripts.OnEnter(view.Clock)
H.check(tooltipLines[3] and tooltipLines[3]:find("^Guild money seen ") ~= nil, "and when it was seen")
-- The money may come from the server a few seconds after the window opens.
world:OpenGuildBank(mike, 99999, 3)
world:RunFor(150)
world:CloseGuildBank(mike)
world:RunFor(150)
ns.GuildTab.Refresh()
H.eq(view.GuildMoney:GetText(), "In the bank: " .. Coins(9, 99, 99), "money that comes late is read too")
rawset(env.GameTooltip, "AddLine", addLine)
-- How columns fit a room: the largest scale, never above 1, every column shown.
local Fit = alice.ns.BankView.Fit
local across, rows, scale = Fit(2, 1000, 1000)
H.check(across == 2 and rows == 1 and scale == 1, "room to spare: full size, never larger")
for _, case in ipairs({ { 5, 536, 258 }, { 6, 536, 288 }, { 11, 536, 288 }, { 14, 536, 400 }, { 1, 50, 50 } }) do
    local count, width, height = case[1], case[2], case[3]
    across, rows, scale = Fit(count, width, height)
    local fits = across * rows >= count and (across * 103 - 3) * scale <= width + 1e-6 and (rows * 311 + (rows - 1) * 6) * scale <= height + 1e-6
    local best = true
    for other = 1, count do
        local otherRows = math.ceil(count / other)
        local otherScale = math.min(width / (other * 103 - 3), height / (otherRows * 311 + (otherRows - 1) * 6), 1)
        if otherScale > scale + 1e-9 then
            best = false
        end
    end
    H.check(fits and best, ("%d columns in %dx%d: %d across, %d rows, scale %.2f, the best that fits"):format(count, width, height, across, rows, scale))
end
-- The search dims what does not match, as the game's does.
view.Search:SetText("12345")
view.Search._scripts.OnTextChanged(view.Search)
local swordSlot
for _, column in ipairs(view.Columns) do
    for _, s in ipairs(column.Slots) do
        if s.item and s.item.i == SWORD then
            swordSlot = s
        end
    end
end
H.check(swordSlot and not swordSlot.SearchOverlay:IsShown(), "a match stays bright")
H.check(view.Columns[1].Slots[1].SearchOverlay:IsShown(), "the rest is dimmed")
view.Search:SetText("")
view.Search._scripts.OnTextChanged(view.Search)
H.check(not view.Columns[1].Slots[1].SearchOverlay:IsShown(), "an empty search dims nothing")
slot._scripts.OnClick(slot, "RightButton")
local form = env.GuildBankAltsRequestForm
H.check(form ~= nil and form:IsShown(), "right-click opens the request form")
H.check(form.InPerson:GetChecked() and not form.ByMail:GetChecked(), "in person, unless chosen otherwise")
H.check(form.InPerson.Description:GetText():find("bank of the city", 1, true) ~= nil, "in person: where to go")
H.check(form.ByMail.Description:GetText():find("30|TInterface\\MoneyFrame\\UI-CopperIcon", 1, true) ~= nil
    and form.ByMail.Description:GetText():find("cash on delivery", 1, true) ~= nil, "by mail: the fee, cash on delivery")
form.ByMail._scripts.OnClick(form.ByMail)
H.check(form.ByMail:GetChecked() and not form.InPerson:GetChecked(), "one choice at a time")
form.Quantity:SetText("999")
form.Submit._scripts.OnClick(form.Submit)
H.check(form.Error:GetText():find("holds only", 1, true) ~= nil, "more than the bank holds is refused")
form.Quantity:SetText("3")
form.Note:SetText("Thanks")
local before = #alice.printed
form.Submit._scripts.OnClick(form.Submit)
H.check(not form:IsShown(), "the form closes once sent")
H.check(Printed(alice, "request sent", before), "and says it was sent")
local mine = Find(alice.ns.Requests.List(alice.ns.Data.CurrentGuild(false)), function(v)
    return v.requester == alice.guid and v.request.q == 3 and v.request.nt == "Thanks"
end)
H.check(mine ~= nil, "the request is made")
H.eq(mine and mine.request.d, BY_MAIL, "by mail, as chosen")
slot._scripts.OnClick(slot, "RightButton")
H.check(form.ByMail:GetChecked(), "the next form starts with the last choice")
form.Cancel._scripts.OnClick(form.Cancel)
H.check(page.Hint:GetText():find("Right-click an item to request it.", 1, true) ~= nil
    and page.Hint:GetText():find("By mail: 30|TInterface\\MoneyFrame\\UI-CopperIcon", 1, true) ~= nil
    and page.Hint:GetText():find("In person: free.", 1, true) ~= nil, "the hint tells what the mail costs")
-- Under the window's inset there is room for two lines: each line of the
-- hint must fit on one, in every language (Spanish once took three).
for _, locale in ipairs({ "deDE", "esES", "frFR", "itIT", "koKR", "ptBR", "ruRU", "zhCN", "zhTW" }) do
    local texts = {}
    local chunk = assert(loadfile(H.ADDON .. "/Locales/" .. locale .. ".lua"))
    chunk("GuildBankAlts", { RegisterLocale = function(_, fill) fill(texts) end })
    for _, key in ipairs({ "Right-click an item to request it.", "By mail: %s per stack, cash on delivery. In person: free." }) do
        local characters = select(2, (texts[key] or ""):gsub("[^\128-\191]", ""))
        H.check(texts[key] ~= nil and characters <= 75, ("%s: the hint line is short (%d characters): %s"):format(locale, characters, key))
    end
end
-- Our own bank cannot be requested from.
world:RunFor(150)
local bankEnv = bank.env
bankEnv.GuildBankAltsGuildTab._scripts.OnClick(bankEnv.GuildBankAltsGuildTab)
local bankPage = bankEnv.GuildBankAltsGuildPanel
local bankSlot = bankPage.Bank.Columns[1].Slots[1]
bankSlot._scripts.OnClick(bankSlot, "RightButton")
H.check(bankEnv.GuildBankAltsRequestForm == nil or not bankEnv.GuildBankAltsRequestForm:IsShown(), "a bank character cannot request from itself")
H.check(bankEnv.GuildBankAltsGuildTab.Badge:IsShown(), "the bank character's tab shows the notification mark")
Errors(world, "bank subtab")

H.section("The Requests subtab")
page.SubTabs.Tabs[2]._scripts.OnClick(page.SubTabs.Tabs[2])
H.check(page.Requests:IsShown() and not page.Bank:IsShown(), "the request list shows")
local elements = page.Requests.ScrollBox._provider.elements
local mineElement = Find(elements, function(e) return e.view.key == mine.key end)
H.check(mineElement ~= nil, "our request is listed")
local requestRow = H.NewObject(alice, "Frame")
page.Requests.ScrollBox._view.init(requestRow, mineElement)
H.check(requestRow.Button:IsShown() and requestRow.Button:GetText() == "Delete", "our own pending request has Delete")
H.check(requestRow.Detail:GetText():find(" · By mail · \"Thanks\"", 1, true) ~= nil, "the row tells how it is to be delivered")
local olgaEnv = olga.env
olgaEnv.GuildBankAltsGuildTab._scripts.OnClick(olgaEnv.GuildBankAltsGuildTab)
local olgaPage = olgaEnv.GuildBankAltsGuildPanel
olgaPage.SubTabs.Tabs[2]._scripts.OnClick(olgaPage.SubTabs.Tabs[2])
local olgaElement = Find(olgaPage.Requests.ScrollBox._provider.elements, function(e) return e.view.key == mine.key end)
local olgaRow = H.NewObject(olga, "Frame")
olgaPage.Requests.ScrollBox._view.init(olgaRow, olgaElement)
H.check(olgaRow.Button:IsShown() and olgaRow.Button:GetText() == "Reject", "an officer sees Reject")
olgaRow.Button._scripts.OnClick(olgaRow.Button)
H.eq(ViewAt(olga, alice.guid, mine.id).state, "rejected", "and rejects with it")
local mikeEnv = mike.env
mikeEnv.GuildBankAltsGuildTab._scripts.OnClick(mikeEnv.GuildBankAltsGuildTab)
local mikePage = mikeEnv.GuildBankAltsGuildPanel
mikePage.SubTabs.Tabs[2]._scripts.OnClick(mikePage.SubTabs.Tabs[2])
world:RunFor(150)
local mikeElement = Find(mikePage.Requests.ScrollBox._provider.elements, function(e) return e.view.key == mine.key end)
local mikeRow = H.NewObject(mike, "Frame")
mikePage.Requests.ScrollBox._view.init(mikeRow, mikeElement)
H.check(not mikeRow.Button:IsShown(), "a member has no button on another's request")
-- The filters.
page.OnlyOpen:SetChecked(true)
page.OnlyOpen._scripts.OnClick(page.OnlyOpen)
H.check(Find(page.Requests.ScrollBox._provider.elements, function(e) return ns.Requests.IsClosed(e.view.state) end) == nil,
    "Only open requests hides the closed ones")
Errors(world, "requests subtab")

H.section("A rejected request's notice")
-- The requester looks at the Bank subtab while an officer rejects a
-- request of hers.
local function RequestsLabel()
    return page.SubTabs.Tabs[2]:GetText()
end
world:RunFor(150)
page.SubTabs.Tabs[1]._scripts.OnClick(page.SubTabs.Tabs[1])
H.check(RequestsLabel() == "Requests" and not tab.Badge:IsShown(), "nothing to tell the requester yet")
local turnedDown = ns.Requests.Create(bank.guid, "item:2589", 3, "", ns.Requests.IN_PERSON)
world:RunFor(150)
local printed = #alice.printed
H.check(olga.ns.Requests.Reject(alice.guid, turnedDown), "an officer rejects it")
world:RunFor(150)
H.eq(RequestsLabel(), "Requests (1)", "the requester's Requests subtab counts it")
H.check(tab.Badge:IsShown(), "and the guild tab shows the notification mark")
H.check(Printed(alice, "rejected your request", printed), "besides the chat line")
-- Seen only with the rejected requests listed: not while only open ones are.
H.check(page.OnlyOpen:GetChecked(), "(only open requests listed)")
page.SubTabs.Tabs[2]._scripts.OnClick(page.SubTabs.Tabs[2])
H.check(RequestsLabel() == "Requests (1)" and tab.Badge:IsShown(), "with only open requests listed, it is still to be seen")
page.OnlyOpen:SetChecked(false)
page.OnlyOpen._scripts.OnClick(page.OnlyOpen)
H.check(RequestsLabel() == "Requests" and not tab.Badge:IsShown(), "listed, it is seen: the count and the mark go away")
world:RunFor(150)
H.check(RequestsLabel() == "Requests" and not tab.Badge:IsShown(), "and stay away")
-- Rejected while the requester looks at the list: seen at once.
local seenAtOnce = ns.Requests.Create(bank.guid, "item:2589", 2, "", ns.Requests.IN_PERSON)
world:RunFor(150)
olga.ns.Requests.Reject(alice.guid, seenAtOnce)
world:RunFor(150)
H.check(RequestsLabel() == "Requests" and not tab.Badge:IsShown(), "rejected while the list shows, there is nothing more to tell")
Errors(world, "rejected notice")

H.section("The Send items button")
-- The game's mailbox: closed, with its Send tab and recipient box.
env.MailFrame = H.NewObject(alice, "Frame")
env.MailFrame:Hide()
env.MailFrameTab_OnClick = function(_, tab)
    alice.mailTab = tab
end
env.SendMailNameEditBox = H.NewObject(alice, "EditBox")
local function OpenMailbox()
    env.MailFrame:Show()
    alice.mailTab = 1
    world:FireEvent(alice, "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 17)
    world:RunFor(1)
end
local function CloseMailbox()
    env.MailFrame:Hide()
    env.SendMailNameEditBox:SetText("")
    alice.mailTab = nil
end
page.SubTabs.Tabs[1]._scripts.OnClick(page.SubTabs.Tabs[1])
local send = page.Send
H.check(send:IsShown() and send:IsEnabled() and send:GetText() == "Send items", "the Bank subtab has a Send items button")
send._scripts.OnEnter(send)
local tip = env.GameTooltip._lines
H.check(tip[2]:find("A mail to Bank Holder", 1, true) and tip[3]:find("open a mailbox", 1, true),
    "its tooltip: a mail to the bank character shown, once a mailbox is open")
-- No mailbox open: it waits for one.
local printed = #alice.printed
send._scripts.OnClick(send)
H.check(Printed(alice, "open a mailbox: a mail to Bank Holder will be ready.", printed), "without a mailbox, it says to open one")
H.eq(alice.mailTab, nil, "and opens nothing itself")
send._scripts.OnEnter(send)
tip = env.GameTooltip._lines
H.eq(tip[3], "Waiting for you to open a mailbox.", "it waits for one")
OpenMailbox()
H.eq(alice.mailTab, 2, "a mailbox opened: its Send tab")
H.eq(env.SendMailNameEditBox:GetText(), "Bank Holder", "with the bank character as the recipient")
-- A mailbox open: at once.
alice.mailTab = 1
env.SendMailNameEditBox:SetText("")
send._scripts.OnClick(send)
H.check(alice.mailTab == 2 and env.SendMailNameEditBox:GetText() == "Bank Holder", "with a mailbox open, at once")
CloseMailbox()
OpenMailbox()
H.eq(env.SendMailNameEditBox:GetText(), "", "a mailbox opened later, without a click, is left as the game opens it")
CloseMailbox()
-- Waiting does not last.
send._scripts.OnClick(send)
world:RunFor(400)
OpenMailbox()
H.eq(env.SendMailNameEditBox:GetText(), "", "a mailbox opened long after the click is left alone")
CloseMailbox()
-- Not on the other subtabs, and not to oneself.
page.SubTabs.Tabs[2]._scripts.OnClick(page.SubTabs.Tabs[2])
H.check(not send:IsShown(), "the other subtabs have no Send items button")
bankPage.SubTabs.Tabs[1]._scripts.OnClick(bankPage.SubTabs.Tabs[1])
H.check(bankPage.Send:IsShown() and not bankPage.Send:IsEnabled(), "a bank character cannot mail its own bank")
bankPage.Send._scripts.OnEnter(bankPage.Send)
H.eq(bankEnv.GameTooltip._lines[2], "This is your own bank.", "and is told why")
Errors(world, "send items")

H.section("Version")
H.eq(alice.ns.PREFIX, alice.ns.TRIAL and "GuildBankAltsDev" or "GuildBankAlts", "the prefix")
H.check(#alice.ns.PREFIX <= 16, "the prefix fits the game's limit of 16 characters")
H.check(alice.ns.LISTEN["GuildBankAlts"] and alice.ns.LISTEN[alice.ns.PREFIX], "the usual prefix is heard, and ours")
