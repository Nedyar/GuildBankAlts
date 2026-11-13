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

-- The notification mark on a client's micro menu button that opens the
-- guild window: of the game's template for it, on that button.
local function MicroMark(client)
    return Find(client.created, function(frame)
        return frame._template == "MainMenuBarMicroButtonNotificationTemplate" and frame._parent == client.env.GuildMicroButton
    end)
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

H.section("Requests: accepting, rejecting and deleting")
local function ViewAt(client, requesterGUID, requestID)
    return client.ns.Requests.Find(client.ns.Data.CurrentGuild(false), requesterGUID, requestID)
end
-- Accepted by a bank character, an officer or the guild master, if the
-- bank character has enough to spare.
H.check(not mike.ns.Requests.Accept(alice.guid, first), "a member cannot accept")
H.check(not alice.ns.Requests.Accept(alice.guid, first), "nobody accepts their own request")
H.check(olga.ns.Requests.Accept(alice.guid, first), "an officer accepts it")
world:RunFor(150)
local accepted = ViewAt(alice, alice.guid, first)
H.check(accepted.state == "accepted" and accepted.accepter == olga.guid, "accepted for its requester, by the officer")
H.eq(ViewAt(bank, alice.guid, first).state, "accepted", "and for the bank character")
H.check(Printed(alice, "Olga Price accepted your request"), "the requester is told")
H.check(not alice.ns.Requests.Delete(first), "its maker cannot delete an accepted request")
H.check(not gus.ns.Requests.Accept(alice.guid, first), "nor is it accepted twice")
H.eq(bank.ns.RequestList.WaitingForMe(), 1, "it still waits for the bank character")
-- The bank character holds 40 cloth, 20 of them awaited by the accepted
-- request: 20 to spare.
local tooMany = Requests.Create(bank.guid, "item:" .. CLOTH, 25, "", IN_PERSON)
world:RunFor(150)
local spare, needed = olga.ns.Requests.Spare(olga.ns.Data.CurrentGuild(false), ViewAt(olga, alice.guid, tooMany))
H.check(spare == 20 and needed == 25, ("to spare: what it holds, less what accepted requests await (%s of %s)"):format(tostring(spare),
    tostring(needed)))
local ok, why = olga.ns.Requests.Accept(alice.guid, tooMany)
H.check(not ok and why == "stock", "more than it has to spare cannot be accepted")
H.check(alice.ns.Requests.Delete(tooMany), "a pending request can be deleted")
world:RunFor(150)
-- Rejected, and deleted.
local second = Requests.Create(bank.guid, "item:" .. HERB, 5, "", IN_PERSON)
world:RunFor(150)
H.eq(ViewAt(olga, alice.guid, second).request.d, IN_PERSON, "in person, for everyone")
H.check(not mike.ns.Requests.Reject(alice.guid, second), "a member cannot reject")
H.check(not alice.ns.Requests.Reject(alice.guid, second), "nobody rejects their own request")
H.check(olga.ns.Requests.Reject(alice.guid, second), "an officer rejects it")
world:RunFor(150)
H.eq(ViewAt(alice, alice.guid, second).state, "rejected", "rejected for its requester")
H.eq(ViewAt(bank, alice.guid, second).rejecter, olga.guid, "and for the bank, by the officer")
H.check(Printed(alice, "Olga Price rejected your request"), "the requester is told")
H.check(not olga.ns.Requests.Accept(alice.guid, second), "a rejected request cannot be accepted")
H.check(alice.ns.Requests.Delete(second), "its maker can delete a rejected request")
world:RunFor(150)
H.eq(ViewAt(bank, alice.guid, second), nil, "deleted everywhere")
local third = Requests.Create(bank.guid, "item:" .. ORE, 2, "", IN_PERSON)
world:RunFor(150)
H.check(gus.ns.Requests.Reject(alice.guid, third), "the guild master rejects")
world:RunFor(150)
H.eq(ViewAt(alice, alice.guid, third).state, "rejected", "rejected by the guild master")
-- Accepted, then rejected: say the bank character can no longer deliver it.
local fourth = Requests.Create(bank.guid, "item:" .. HERB, 2, "", IN_PERSON)
world:RunFor(150)
H.check(gus.ns.Requests.Accept(alice.guid, fourth), "the guild master accepts")
world:RunFor(150)
H.check(bank.ns.Requests.Reject(alice.guid, fourth), "an accepted request can still be rejected")
world:RunFor(150)
H.eq(ViewAt(alice, alice.guid, fourth).state, "rejected", "it is rejected")
H.check(Printed(alice, "Bank Holder rejected your request"), "and its requester told")
Errors(world, "accept, reject and delete")

H.section("Requests: deliveries")
-- A trade of part of it: still accepted, 10 delivered.
world:Trade(bank, alice, { [1] = { CLOTH, 10 } }, {})
world:RunFor(150)
H.check(ViewAt(alice, alice.guid, first).state == "accepted" and ViewAt(olga, alice.guid, first).delivered == 10,
    "half delivered by trade: 10 delivered, for everyone")
H.check(Printed(bank, "10 of 20 delivered to Alice Smith"), "the bank character is told")
H.check(Printed(alice, "10 of 20 delivered for your request"), "and so is the requester")
-- The rest by mail: all delivered, the request goes once its maker is told.
local firstKey = alice.ns.Requests.Key(alice.guid, first)
local told = #alice.printed
world:Mail(bank, "Alice Smith", { [1] = { CLOTH, 10 } })
world:RunFor(150)
H.check(Printed(alice, "your request was delivered", told), "the rest by mail: the requester is told it is delivered")
H.check(ViewAt(alice, alice.guid, first) == nil and ViewAt(mike, alice.guid, first) == nil, "and the request goes, for everyone")
world:RunFor(150)
H.eq(bank.ns.Data.GetOwnRecord(false).ra[firstKey], nil, "and so does the bank character's answer to it")
H.eq(olga.ns.Data.GetOwnRecord(false).ac[firstKey], nil, "and the officer's acceptance")
H.check(not alice.ns.Requests.CanDelete({ requester = alice.guid, state = "approved" }), "a delivered request cannot be deleted")
H.check(not olga.ns.Requests.CanReject({ requester = alice.guid, state = "approved" }), "nor rejected")
H.eq(bank.ns.RequestList.WaitingForMe(), 0, "nothing waits for the bank any more")
-- A rejected request delivered anyway is delivered too.
told = #alice.printed
world:Trade(bank, alice, { [1] = { ORE, 2 } }, {})
world:RunFor(150)
H.check(Printed(alice, "your request was delivered", told) and ViewAt(alice, alice.guid, third) == nil,
    "a rejected request delivered anyway is delivered, and goes")
Errors(world, "deliveries")

H.section("Requests: which a delivery counts towards")
local older = Requests.Create(bank.guid, "item:" .. HERB, 3, "", IN_PERSON)
world:RunFor(5)
local newer = Requests.Create(bank.guid, "item:" .. HERB, 4, "", IN_PERSON)
world:RunFor(150)
H.check(olga.ns.Requests.Accept(alice.guid, newer), "(the newer one accepted)")
world:RunFor(150)
world:Mail(bank, "Alice Smith", { [1] = { HERB, 5 } })
world:RunFor(150)
H.eq(ViewAt(alice, alice.guid, newer), nil, "the accepted request first, though newer: delivered, it goes")
H.eq(ViewAt(alice, alice.guid, older).delivered, 1, "the rest to the one not accepted")
H.eq(ViewAt(alice, alice.guid, fourth).delivered, 0, "none to the rejected one")
local newest = Requests.Create(bank.guid, "item:" .. HERB, 3, "", IN_PERSON)
world:RunFor(150)
world:Mail(bank, "Alice Smith", { [1] = { HERB, 2 } })
world:RunFor(150)
H.check(ViewAt(alice, alice.guid, older) == nil and ViewAt(alice, alice.guid, newest).delivered == 0,
    "among those not accepted, the oldest first")
world:Trade(mike, alice, { [1] = { HERB, 2 } }, {})
world:RunFor(150)
H.eq(ViewAt(alice, alice.guid, newest).delivered, 0, "a member who is not a bank character delivers nothing")
world:Trade(bank, alice, { [1] = { HERB, 2 } }, {}, { cancel = true })
world:RunFor(150)
H.eq(ViewAt(alice, alice.guid, newest).delivered, 0, "a cancelled trade delivers nothing")
world:Mail(bank, "Alice Smith", { [1] = { HERB, 2 } }, { fail = true })
world:RunFor(150)
H.eq(ViewAt(alice, alice.guid, newest).delivered, 0, "a mail the game refuses delivers nothing")
Errors(world, "which first")

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
    if request.i == CLOTH then
        alice.ns.Requests.Delete(requestID)
    end
end
world:RunFor(150)
Errors(world, "limits")

H.section("Requests: a rejected one goes after a week")
local fourthKey = alice.ns.Requests.Key(alice.guid, fourth)
-- Mike's request, rejected; then Mike no longer logs in.
local mikes = mike.ns.Requests.Create(bank.guid, "item:" .. ORE, 1, "", IN_PERSON)
world:RunFor(150)
H.check(olga.ns.Requests.Reject(mike.guid, mikes), "(another member's request rejected)")
world:RunFor(150)
local mikesKey = mike.ns.Requests.Key(mike.guid, mikes)
world:Logout(mike)
world.base = world.base + 6 * 86400
world:FireEvent(alice, "GUILD_ROSTER_UPDATE", false)
world:RunFor(200)
H.eq(ViewAt(alice, alice.guid, fourth).state, "rejected", "six days later, a rejected request is still there")
world.base = world.base + 2 * 86400
world:FireEvent(alice, "GUILD_ROSTER_UPDATE", false)
world:RunFor(200)
H.eq(alice.ns.Data.GetOwnRecord(false).rq[fourth], nil, "after a week, its maker's addon drops it")
world:RunFor(200)
H.eq(bank.ns.Data.GetOwnRecord(false).ra[fourthKey], nil, "then the answer to it goes")
H.eq(gus.ns.Data.GetOwnRecord(false).ac[fourthKey], nil, "and the acceptance")
-- Mike's, though still in his record, is no longer listed; the answer that
-- rejected it stays, so it does not come back pending.
H.check(olga.ns.Data.CurrentGuild(false).members[mike.guid].rq[mikes] ~= nil, "(a member who no longer logs in keeps it in their record)")
H.eq(ViewAt(olga, mike.guid, mikes), nil, "but it is no longer listed")
H.check(olga.ns.Data.GetOwnRecord(false).ra[mikesKey] ~= nil, "and the answer that rejected it stays, so it does not come back pending")
world:Login(mike)
world:RunFor(200)
H.eq(mike.ns.Data.GetOwnRecord(false).rq[mikes], nil, "back in the game, their addon drops it")
world:RunFor(200)
H.eq(olga.ns.Data.GetOwnRecord(false).ra[mikesKey], nil, "and then the answer to it goes")
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
    ac = { [alice.guid .. ":8"] = now - 5 },
}
local _, back = ns.Pack.ReadRecord(ns.Pack.Reader(ns.Pack.RecordString(alice.guid, sample)))
H.check(ns.Same(back.bk, sample.bk), "bank data round trip, slot by slot")
H.check(ns.Same(back.rq, sample.rq), "requests round trip, with how they are to be delivered")
H.check(ns.Same(back.ra, sample.ra), "answers round trip")
H.check(ns.Same(back.ac, sample.ac), "accepted requests round trip")
local noneAccepted = H.DeepCopy(sample)
noneAccepted.ac = {}
_, back = ns.Pack.ReadRecord(ns.Pack.Reader(ns.Pack.RecordString(alice.guid, noneAccepted)))
H.check(back.ac ~= nil and next(back.ac) == nil, "none accepted is told apart from unknown")
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
H.check(Bad(function(r) r.ac["bad key"] = now end), "an acceptance with a bad key is refused")
H.check(Bad(function(r) r.ac[alice.guid .. ":8"] = "now" end), "an acceptance without a time is refused")
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
across, rows, scale = Fit(0, 536, 288)
H.check(rows == 0 and scale > 0, "no columns: nothing to fit, at a scale the game takes")
-- A character just given the bank's rank, whose client has not shared what
-- it holds yet: listed greyed out, its tooltip saying why; the view keeps
-- the bank character it knows.
local _, newGuid = world:AddMember("Zoe Newbank", nil, { rank = "Banco", rankIndex = 4 })
world:RosterChanged()
world:RunFor(2)
alice.ns.GuildTab.Refresh()
local menu = view.Dropdown._menu
H.check(#menu == 2 and menu[1].text == "Bank Holder" and menu[1].enabled == nil and menu[2].text == "Zoe Newbank",
    "a new bank character is listed")
H.check(menu[2].enabled == false and menu[2].tooltipTitle == "Zoe Newbank"
    and menu[2].tooltip == "Zoe Newbank has not shared what it holds yet: log in with it with this addon.", "greyed out, saying why")
menu[2].setSelected(menu[2].data)
Errors(world, "a bank character not known yet, chosen")
H.check(view.Dropdown._text == "Bank Holder" and view.layout.columns == 7, "the view keeps the one it knows")
-- With no bank character known, the one not known shows, saying so.
local guildData = alice.ns.Data.CurrentGuild(false)
local known = guildData.members[bank.guid]
guildData.members[bank.guid] = nil
alice.ns.BankView.Refresh(view)
H.check(view.Empty:IsShown() and view.Empty:GetText():find("has not shared what it holds yet", 1, true)
    and view.layout.columns == 0 and view.Canvas._scale > 0, "with none known: why nothing shows")
guildData.members[bank.guid] = known
for index, member in ipairs(world.roster) do
    if member.guid == newGuid then
        table.remove(world.roster, index)
    end
end
world:RosterChanged()
world:RunFor(2)
alice.ns.BankView.Refresh(view)
H.check(#view.Dropdown._menu == 1 and view.Dropdown._text == "Bank Holder" and view.layout.columns == 7, "back as it was")
Errors(world, "a bank character not known yet")
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
H.check(MicroMark(bank):IsShown(), "so does the micro menu's button that opens the guild window")
H.check(not MicroMark(alice):IsShown(), "(not the requester's)")
local badge = bankEnv.GuildBankAltsGuildTab.Badge
H.check(badge._type == "Frame" and badge._parent == bankEnv.GuildBankAltsGuildTab and badge.Icon ~= nil,
    "on a frame of its own over the tab, which the tab's selection glow does not cover")
local requestsTab = bankPage.SubTabs.Tabs[2]
H.check(requestsTab.Mark:IsShown() and not bankPage.SubTabs.Tabs[1].Mark, "so does its Requests subtab")
H.check(requestsTab.Mark._point[2] == requestsTab.Middle and requestsTab.Mark._point[3] == "TOPRIGHT",
    "on the corner of its art, lower than its frame's top")
requestsTab._scripts.OnClick(requestsTab)
H.check(requestsTab.Mark:IsShown() and requestsTab.Mark._point[2] == requestsTab.MiddleActive,
    "selected, on the corner of its taller art")
local waitingElement = Find(bankPage.Requests.ScrollBox._provider.elements, function(e) return e.view.key == mine.key end)
local waitingRow = H.NewObject(bank, "Frame")
bankPage.Requests.ScrollBox._view.init(waitingRow, waitingElement)
H.check(waitingRow.Mark:IsShown() and waitingRow.Mark._parent == waitingRow.Item, "and the row of the request waiting for it, on its icon")
H.check(waitingRow.Accept:IsShown() and waitingRow.Accept:IsEnabled() and not waitingRow.Prepare:IsShown()
    and not waitingRow.Mail:IsShown(), "not accepted yet: Accept, and no Prepare nor Mail")
bankPage.SubTabs.Tabs[1]._scripts.OnClick(bankPage.SubTabs.Tabs[1])
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
H.check(not requestRow.Mark:IsShown(), "our own request, waiting for the bank character, has no mark for us")
local olgaEnv = olga.env
olgaEnv.GuildBankAltsGuildTab._scripts.OnClick(olgaEnv.GuildBankAltsGuildTab)
local olgaPage = olgaEnv.GuildBankAltsGuildPanel
olgaPage.SubTabs.Tabs[2]._scripts.OnClick(olgaPage.SubTabs.Tabs[2])
local olgaElement = Find(olgaPage.Requests.ScrollBox._provider.elements, function(e) return e.view.key == mine.key end)
local olgaRow = H.NewObject(olga, "Frame")
olgaPage.Requests.ScrollBox._view.init(olgaRow, olgaElement)
H.check(olgaRow.Button:IsShown() and olgaRow.Button:GetText() == "Reject", "an officer sees Reject")
H.check(olgaRow.Accept:IsShown() and olgaRow.Accept:GetText() == "Accept" and olgaRow.Accept:IsEnabled()
    and olgaRow.Accept._point[4] < olgaRow.Button._point[4], "and Accept, left of it")
-- More than the bank character has: Accept is off, and says why.
local swords = ns.Requests.Create(bank.guid, "item:" .. SWORD, 5, "", ns.Requests.IN_PERSON)
world:RunFor(150)
olgaPage.SubTabs.Tabs[2]._scripts.OnClick(olgaPage.SubTabs.Tabs[2])
local swordElement = Find(olgaPage.Requests.ScrollBox._provider.elements, function(e)
    return e.view.key == ns.Requests.Key(alice.guid, swords)
end)
local swordRow = H.NewObject(olga, "Frame")
olgaPage.Requests.ScrollBox._view.init(swordRow, swordElement)
H.check(swordRow.Accept:IsShown() and not swordRow.Accept:IsEnabled(), "more than the bank character has: Accept is off")
swordRow.Accept._scripts.OnEnter(swordRow.Accept)
H.eq(olgaEnv.GameTooltip._lines and olgaEnv.GameTooltip._lines[1],
    "Not enough in the bank: 1 to spare, 5 asked. What other accepted requests still await is set aside.", "and says why")
H.check(ns.Requests.Delete(swords), "(deleted)")
world:RunFor(150)
olgaRow.Accept._scripts.OnClick(olgaRow.Accept)
H.eq(ViewAt(olga, alice.guid, mine.id).state, "accepted", "Accept accepts it")
olgaPage.Requests.ScrollBox._view.init(olgaRow, Find(olgaPage.Requests.ScrollBox._provider.elements, function(e)
    return e.view.key == mine.key
end))
H.check(olgaRow.Button:GetText() == "Reject" and not olgaRow.Accept:IsShown(), "accepted, it can still be rejected")
olgaRow.Button._scripts.OnClick(olgaRow.Button)
H.eq(ViewAt(olga, alice.guid, mine.id).state, "rejected", "and Reject rejects it")
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

H.section("Notices of answered requests")
local function RequestsLabel()
    return page.SubTabs.Tabs[2]:GetText()
end
local function Marks()
    return tab.Badge:IsShown() and page.SubTabs.Tabs[2].Mark:IsShown() and MicroMark(alice):IsShown()
end
-- The row of a request: true or false, its mark; nil, not listed.
local function Marked(id)
    local element = Find(page.Requests.ScrollBox._provider.elements, function(e)
        return e.view.key == ns.Requests.Key(alice.guid, id)
    end)
    if not element then
        return nil
    end
    local row = H.NewObject(alice, "Frame")
    page.Requests.ScrollBox._view.init(row, element)
    return row.Mark:IsShown()
end
-- The row of a request, as the list shows it now.
local function RowOf(id)
    local element = Find(page.Requests.ScrollBox._provider.elements, function(e)
        return e.view.key == ns.Requests.Key(alice.guid, id)
    end)
    local row = H.NewObject(alice, "Frame")
    page.Requests.ScrollBox._view.init(row, element)
    return row
end
world:RunFor(150)
-- Our request rejected in the Requests subtab section: told until we
-- delete it, looked at or not.
page.SubTabs.Tabs[1]._scripts.OnClick(page.SubTabs.Tabs[1])
H.check(RequestsLabel() == "Requests (1)" and Marks(), "a rejected request is counted, with the marks on the tab and subtab")
page.SubTabs.Tabs[2]._scripts.OnClick(page.SubTabs.Tabs[2])
page.OnlyOpen:SetChecked(false)
page.OnlyOpen._scripts.OnClick(page.OnlyOpen)
H.eq(Marked(mine.id), true, "and on its row")
H.check(RowOf(mine.id).Tints.rejected:IsShown() and not RowOf(mine.id).Tints.accepted:IsShown(), "a rejected request's row is red")
page.SubTabs.Tabs[1]._scripts.OnClick(page.SubTabs.Tabs[1])
page.SubTabs.Tabs[2]._scripts.OnClick(page.SubTabs.Tabs[2])
H.check(RequestsLabel() == "Requests (1)" and Marks() and Marked(mine.id), "seen, it is still told")
H.check(ns.Requests.Delete(mine.id), "until it is deleted")
world:RunFor(150)
H.check(RequestsLabel() == "Requests" and not tab.Badge:IsShown() and not page.SubTabs.Tabs[2].Mark:IsShown()
    and not MicroMark(alice):IsShown() and Marked(mine.id) == nil, "then the count and the marks go")
-- Accepted: told until its maker points at its row.
local acceptedNow = ns.Requests.Create(bank.guid, "item:2589", 3, "", ns.Requests.IN_PERSON)
world:RunFor(150)
H.check(olga.ns.Requests.Accept(alice.guid, acceptedNow), "an officer accepts a request")
world:RunFor(150)
H.check(RequestsLabel() == "Requests (1)" and Marks() and Marked(acceptedNow), "it is told, on its row too")
H.check(RowOf(acceptedNow).Tints.accepted:IsShown() and not RowOf(acceptedNow).Tints.rejected:IsShown(),
    "an accepted request's row is green")
H.check(not RowOf(newest).Tints.accepted:IsShown() and not RowOf(newest).Tints.rejected:IsShown(), "a pending one's has no tint")
world:Trade(bank, alice, { [1] = { CLOTH, 1 } }, {})
world:RunFor(150)
H.check(RequestsLabel() == "Requests (1)" and Marks() and Marked(acceptedNow), "partly delivered, still told")
local acceptedRow = RowOf(acceptedNow)
acceptedRow._scripts.OnEnter(acceptedRow)
H.check(not acceptedRow.Mark:IsShown() and RequestsLabel() == "Requests" and not tab.Badge:IsShown()
    and not page.SubTabs.Tabs[2].Mark:IsShown(), "pointed at, its notice is seen: its mark, the count and the tabs' marks go")
H.check(env.GameTooltip:IsShown(), "(its tooltip shows)")
world:RunFor(150)
H.check(Marked(acceptedNow) == false and RowOf(acceptedNow).Tints.accepted:IsShown() and RequestsLabel() == "Requests",
    "it stays listed, accepted, its notice seen")
-- Another, seen by pointing at its item's icon.
local another = ns.Requests.Create(bank.guid, "item:2589", 1, "", ns.Requests.IN_PERSON)
world:RunFor(150)
H.check(olga.ns.Requests.Accept(alice.guid, another), "(another accepted)")
world:RunFor(150)
H.check(RequestsLabel() == "Requests (1)" and Marked(another), "told")
local anotherRow = RowOf(another)
anotherRow.Item._scripts.OnEnter(anotherRow.Item)
H.check(not anotherRow.Mark:IsShown() and RequestsLabel() == "Requests", "pointing at its item seen it too")
-- Pointing at someone else's or a rejected request changes nothing.
H.check(not ns.Data.OwnState().acceptedSeen[ns.Requests.Key(alice.guid, newest)], "(only accepted ones are noted)")
world:Trade(bank, alice, { [1] = { CLOTH, 3 } }, {})
world:RunFor(150)
H.check(Marked(acceptedNow) == nil and Marked(another) == nil and RequestsLabel() == "Requests",
    "all delivered, they go")
H.check(next(ns.Data.OwnState().acceptedSeen) == nil, "and what was seen of them is forgotten")
Errors(world, "answered notices")

H.section("The request form: what accepted requests set aside")
do
    page.SubTabs.Tabs[1]._scripts.OnClick(page.SubTabs.Tabs[1])
    world:RunFor(1)
    local function ClothSlot()
        for _, column in ipairs(page.Bank.Columns) do
            for _, s in ipairs(column.Slots) do
                if s.item and s.item.i == CLOTH then
                    return s
                end
            end
        end
    end
    local function Ask()
        local s = ClothSlot()
        s._scripts.OnClick(s, "RightButton")
        return form.Available:GetText()
    end
    local held = ns.BankView.Holding(ns.Data.CurrentGuild(false).members[bank.guid].bk, CLOTH)
    H.check(held > 4, "(the bank holds some cloth: " .. held .. ")")
    H.eq(Ask(), ("of %d"):format(held), "with no request accepted, all the bank holds may be asked for")
    form.Cancel._scripts.OnClick(form.Cancel)
    -- Mike's request for 3 accepted: set aside.
    local mikes = mike.ns.Requests.Create(bank.guid, "item:" .. CLOTH, 3, "", Requests.IN_PERSON)
    world:RunFor(150)
    H.check(olga.ns.Requests.Accept(mike.guid, mikes), "(Mike's request for 3 accepted)")
    world:RunFor(150)
    H.eq(Ask(), ("of %d available (3 set aside for accepted requests)"):format(held - 3),
        "an accepted request's items are set aside: the text says so")
    H.eq(form.Error:GetText(), "", "(no error yet)")
    form.Quantity:SetText(tostring(held - 2))
    form.Submit._scripts.OnClick(form.Submit)
    H.eq(form.Error:GetText(), ("Only %d can be requested: the bank holds %d, 3 of them set aside for accepted requests."):format(held - 3, held),
        "asking for more than is left is refused, saying why")
    H.check(form:IsShown(), "(the form stays open)")
    form.Quantity:SetText(tostring(held - 3))
    form.Submit._scripts.OnClick(form.Submit)
    H.check(not form:IsShown(), "what is left may be asked for")
    world:RunFor(150)
    local rest = Find(Requests.List(ns.Data.CurrentGuild(false)), function(v)
        return v.requester == alice.guid and v.request.i == CLOTH and v.request.q == held - 3
    end)
    H.check(rest ~= nil and rest.state == "pending", "(made, pending)")
    H.eq(Ask(), ("of %d available (3 set aside for accepted requests)"):format(held - 3), "a pending request sets nothing aside")
    form.Cancel._scripts.OnClick(form.Cancel)
    -- Accepted too: nothing is left.
    H.check(olga.ns.Requests.Accept(alice.guid, rest.id), "(that one accepted as well)")
    world:RunFor(150)
    H.eq(Ask(), ("of 0 available (%d set aside for accepted requests)"):format(held), "all set aside")
    H.eq(form.Error:GetText(), ("None can be requested: all %d the bank holds are set aside for accepted requests."):format(held),
        "the form says at once that none can be asked for")
    form.Submit._scripts.OnClick(form.Submit)
    H.check(form:IsShown(), "and asks for none")
    form.Cancel._scripts.OnClick(form.Cancel)
    -- Partly delivered, an accepted request sets aside only what it still awaits.
    world:Trade(bank, mike, { [1] = { CLOTH, 2 } }, {})
    world:RunFor(150)
    local now = ns.BankView.Holding(ns.Data.CurrentGuild(false).members[bank.guid].bk, CLOTH)
    H.eq(Ask(), ("of %d available (%d set aside for accepted requests)"):format(math.max(now - (held - 2), 0), math.min(held - 2, now)),
        "partly delivered, only what it still awaits stays set aside")
    form.Cancel._scripts.OnClick(form.Cancel)
    -- As it was: both rejected, Alice's deleted.
    H.check(olga.ns.Requests.Reject(mike.guid, mikes) and olga.ns.Requests.Reject(alice.guid, rest.id), "(both rejected)")
    world:RunFor(150)
    H.check(Requests.Delete(rest.id), "(Alice's deleted)")
    world:RunFor(150)
    H.eq(Ask(), ("of %d"):format(now), "rejected, they set nothing aside")
    form.Cancel._scripts.OnClick(form.Cancel)
end
Errors(world, "form and accepted requests")

H.section("The Requests subtab: buttons for several requests at once")
do
    local guild = ns.Data.CurrentGuild(false)
    local held = ns.BankView.Holding(guild.members[bank.guid].bk, CLOTH)
    -- Mike's request for 2, accepted, sets 2 aside; Alice asks for more
    -- than is left twice, and for 1; Mike for more than the bank holds.
    local mikeAccepted = mike.ns.Requests.Create(bank.guid, "item:" .. CLOTH, 2, "", Requests.IN_PERSON)
    local aliceBig = Requests.Create(bank.guid, "item:" .. CLOTH, held + 5, "", Requests.IN_PERSON)
    local aliceMid = Requests.Create(bank.guid, "item:" .. CLOTH, held - 1, "", Requests.IN_PERSON)
    local aliceSmall = Requests.Create(bank.guid, "item:" .. CLOTH, 1, "", Requests.IN_PERSON)
    local mikeBig = mike.ns.Requests.Create(bank.guid, "item:" .. CLOTH, held + 1, "", Requests.IN_PERSON)
    world:RunFor(150)
    H.check(olga.ns.Requests.Accept(mike.guid, mikeAccepted), "(Mike's request for 2 accepted)")
    world:RunFor(150)
    local short = {}
    for _, view in ipairs(olga.ns.Requests.Short(olga.ns.Data.CurrentGuild(false))) do
        short[#short + 1] = view.key
    end
    H.eq(table.concat(short, " "), table.concat({ Requests.Key(alice.guid, aliceBig), Requests.Key(alice.guid, aliceMid),
        Requests.Key(mike.guid, mikeBig) }, " "),
        "short of stock: those asking for more than the bank holds less what accepted requests await, oldest first")
    -- A member: Delete my rejected, not Reject short of stock.
    page.SubTabs.Tabs[2]._scripts.OnClick(page.SubTabs.Tabs[2])
    H.check(page.DeleteRejected:IsShown() and not page.RejectShort:IsShown(), "a member has Delete my rejected only")
    local rejectedBefore = #Requests.OwnRejected(ns.Data.CurrentGuild(false))
    -- An officer: Reject short of stock, on.
    olgaPage.SubTabs.Tabs[2]._scripts.OnClick(olgaPage.SubTabs.Tabs[2])
    local rejectShort = olgaPage.RejectShort
    H.check(rejectShort:IsShown() and rejectShort:IsEnabled() and rejectShort:GetText() == "Reject short of stock",
        "an officer has Reject short of stock, on")
    rejectShort._scripts.OnEnter(rejectShort)
    local tip = table.concat(olgaEnv.GameTooltip._lines, "\n")
    H.check(olgaEnv.GameTooltip._lines[2] == "Rejects the requests that cannot be met because the bank does not hold enough for them."
        and #olgaEnv.GameTooltip._lines == 5 and select(2, tip:gsub("Alice Smith", "")) == 2 and tip:find("Mike Stone", 1, true),
        "its tooltip says in a line what it does, and lists them: " .. tip)
    rejectShort._scripts.OnClick(rejectShort)
    H.check(olga.confirm and olga.confirm.text_arg1 == "Reject the requests short of stock (3)? Their makers are told.",
        "it asks first")
    H.check(ViewAt(olga, alice.guid, aliceBig).state == "pending", "(nothing rejected until confirmed)")
    local printed = #olga.printed
    olga.confirm.callback()
    H.check(Printed(olga, "Requests short of stock rejected: 3.", printed), "confirmed, it rejects them, and says so")
    world:RunFor(150)
    H.check(ViewAt(alice, alice.guid, aliceBig).state == "rejected" and ViewAt(alice, alice.guid, aliceMid).state == "rejected"
        and ViewAt(alice, mike.guid, mikeBig).state == "rejected", "the three are rejected, for everyone")
    H.check(ViewAt(alice, alice.guid, aliceSmall).state == "pending" and ViewAt(alice, mike.guid, mikeAccepted).state == "accepted",
        "the others stay as they were")
    olgaPage.SubTabs.Tabs[2]._scripts.OnClick(olgaPage.SubTabs.Tabs[2])
    H.check(olgaPage.RejectShort:IsShown() and not olgaPage.RejectShort:IsEnabled(), "none left: the button is off")
    olgaPage.RejectShort._scripts.OnEnter(olgaPage.RejectShort)
    H.eq(olgaEnv.GameTooltip._lines[2], "No request is short of stock.", "and says why")
    -- A bank character has it too.
    local bankRequests = bankEnv.GuildBankAltsGuildPanel
    bankRequests.SubTabs.Tabs[2]._scripts.OnClick(bankRequests.SubTabs.Tabs[2])
    H.check(bankRequests.RejectShort:IsShown(), "a bank character has Reject short of stock too")
    -- Alice deletes her rejected requests at once.
    page.SubTabs.Tabs[2]._scripts.OnClick(page.SubTabs.Tabs[2])
    local deleteRejected = page.DeleteRejected
    H.check(deleteRejected:IsEnabled(), "with rejected requests, Delete my rejected is on")
    deleteRejected._scripts.OnEnter(deleteRejected)
    H.eq(env.GameTooltip._lines[2], ("Deletes your rejected requests (%d)."):format(rejectedBefore + 2), "its tooltip says how many")
    printed = #alice.printed
    deleteRejected._scripts.OnClick(deleteRejected)
    H.check(Printed(alice, ("Rejected requests deleted: %d."):format(rejectedBefore + 2), printed), "it deletes them, and says so")
    world:RunFor(150)
    H.check(ViewAt(olga, alice.guid, aliceBig) == nil and ViewAt(olga, alice.guid, aliceMid) == nil
        and ViewAt(olga, alice.guid, aliceSmall).state == "pending" and ViewAt(olga, mike.guid, mikeBig).state == "rejected",
        "only hers rejected go, for everyone")
    page.SubTabs.Tabs[2]._scripts.OnClick(page.SubTabs.Tabs[2])
    H.check(not page.DeleteRejected:IsEnabled(), "none left: the button is off")
    page.DeleteRejected._scripts.OnEnter(page.DeleteRejected)
    H.eq(env.GameTooltip._lines[2], "You have no rejected requests.", "and says why")
    -- As it was.
    H.check(Requests.Delete(aliceSmall) and olga.ns.Requests.Reject(mike.guid, mikeAccepted), "(cleaned up)")
    world:RunFor(150)
end
Errors(world, "buttons for several requests")

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
