-- A bank character's click on a request made to it gets its items ready,
-- at its bank or at a mailbox (Prepare.lua).
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

local CLOTH, ORE = 2589, 2771

local world = H.NewWorld({ seed = 31, senderFormat = "short", strictWhispers = true, communities = H.FakeCommunities })
-- Cloth (stacks of 20) in the bags, split up, and in the bank.
local bank = world:NewClient("Bank Holder", {
    rank = "Banco", rankIndex = 4, money = 100000,
    containers = {
        [0] = { size = 16, [1] = { CLOTH, 15 }, [2] = { CLOTH, 10 }, [3] = { ORE, 7 } },
        [6] = { size = 48, [1] = { CLOTH, 20 }, [2] = { CLOTH, 20 }, [3] = { CLOTH, 8 } },
    },
    bankTabs = { 6 }, maxBankTabs = 1,
})
local alice = world:NewClient("Alice Smith", { rank = "Miembro", rankIndex = 3 })
local mike = world:NewClient("Mike Stone", { rank = "Miembro", rankIndex = 3 })
for _, client in ipairs({ bank, alice, mike }) do
    world:Login(client)
end
world:RunFor(60)
local Requests = alice.ns.Requests
-- A request accepted, as the bank character would accept it, the stock
-- aside: these tests are about getting accepted requests ready (Prepare
-- and Mail are only for them). Once the bank character sees it, as it
-- would to accept it (else it drops its answer to a request it does not
-- know).
local function Accept(requesterGUID, id)
    if not bank.ns.Requests.Find(bank.ns.Data.CurrentGuild(false), requesterGUID, id) then
        world:RunFor(150)
    end
    local record = bank.ns.Data.GetOwnRecord(true)
    record.ac = record.ac or {}
    record.ac[bank.ns.Requests.Key(requesterGUID, id)] = bank.ns.Now()
    bank.ns.Data.TouchOwn(record)
end
local byMail = Requests.Create(bank.guid, "item:" .. CLOTH, 48, "", Requests.BY_MAIL)
local inPerson = mike.ns.Requests.Create(bank.guid, "item:" .. CLOTH, 5, "", Requests.IN_PERSON)
Accept(alice.guid, byMail)
Accept(mike.guid, inPerson)
world:RunFor(150)
Errors(world, "requests")

local env = bank.env
local ns = bank.ns
-- The game's mailbox, closed: its Send tab, recipient, cash on delivery.
env.MailFrame = H.NewObject(bank, "Frame")
env.MailFrame:Hide()
env.MailFrameTab_OnClick = function(_, tab)
    bank.mailTab = tab
end
env.SendMailNameEditBox = H.NewObject(bank, "EditBox")
env.SendMailSubjectEditBox = H.NewObject(bank, "EditBox")
env.SendMailMoney = H.NewObject(bank, "Frame")
env.SendMailRadioButton_OnClick = function(index)
    bank.mailRadio = index
end
env.MoneyInputFrame_SetCopper = function(frame, copper)
    frame._copper = copper
end
local function OpenMailbox()
    env.MailFrame:Show()
    world:FireEvent(bank, "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 17)
    world:RunFor(1)
end
local function CloseMailbox()
    env.MailFrame:Hide()
    bank.sendMail, bank.mailTab, bank.mailRadio, env.SendMailMoney._copper = nil, nil, nil, nil
    env.SendMailNameEditBox:SetText("")
    env.SendMailSubjectEditBox:SetText("")
end

local function BagCount(itemID)
    local count = 0
    for bag = 0, 5 do
        for slot, item in pairs(bank.containers[bag] or {}) do
            if type(slot) == "number" and item[1] == itemID then
                count = count + item[2]
            end
        end
    end
    return count
end

-- The bag stacks of an item, smallest first: "5 10 20".
local function BagStacks(itemID)
    local list = {}
    for bag = 0, 5 do
        for slot, item in pairs(bank.containers[bag] or {}) do
            if type(slot) == "number" and item[1] == itemID then
                list[#list + 1] = item[2]
            end
        end
    end
    table.sort(list)
    return table.concat(list, " ")
end

local function BankStacks(itemID)
    local list = {}
    for slot, item in pairs(bank.containers[6] or {}) do
        if type(slot) == "number" and item[1] == itemID then
            list[#list + 1] = item[2]
        end
    end
    table.sort(list)
    return table.concat(list, " ")
end

-- The counts of the stacks kept for a request, smallest first: "5 20".
local function KeptCounts(row)
    local list = {}
    for _, count in pairs(ns.Data.OwnState().prepared[row.view.key] or {}) do
        list[#list + 1] = count
    end
    table.sort(list)
    return table.concat(list, " ")
end

-- Keeps the stack in a slot of the bags for a request.
local function KeepFor(row, bag, slot)
    local guid = env.C_Item.GetItemGUID(env.ItemLocation:CreateFromBagAndSlot(bag, slot))
    local prepared = ns.Data.OwnState().prepared or {}
    ns.Data.OwnState().prepared = prepared
    prepared[row.view.key] = { [guid] = bank.containers[bag][slot][2] }
end

local function Mail()
    local stacks, count = {}, 0
    for _, item in pairs(bank.sendMail or {}) do
        stacks[#stacks + 1] = item[2]
        count = count + item[2]
    end
    table.sort(stacks)
    return count, table.concat(stacks, " ")
end

-- The bank character's request list.
env.GuildBankAltsGuildTab._scripts.OnClick(env.GuildBankAltsGuildTab)
local page = env.GuildBankAltsGuildPanel
page.SubTabs.Tabs[2]._scripts.OnClick(page.SubTabs.Tabs[2])
local function Row(requester, id)
    local element = Find(page.Requests.ScrollBox._provider.elements, function(e)
        return e.view.requester == requester.guid and e.view.id == id
    end)
    local row = H.NewObject(bank, "Frame")
    page.Requests.ScrollBox._view.init(row, element)
    return row
end
-- A request's Prepare (or Release) or Mail button, as its row shows it now.
local function Button(row, action)
    local element = Find(page.Requests.ScrollBox._provider.elements, function(e)
        return e.view.key == row.view.key
    end)
    page.Requests.ScrollBox._view.init(row, element)
    return action == "mail" and row.Mail or row.Prepare
end
-- What the Prepare button is now: "prepare" or "release".
local function PrepareIs(row)
    return Button(row, "prepare").action
end
-- Its tooltip.
local function Tip(row, action)
    local button = Button(row, action)
    button._scripts.OnEnter(button)
    return table.concat(env.GameTooltip._lines, "\n")
end
-- Presses it, if it is shown, enabled and for that action, and waits for
-- it to finish. Returns whether it could be pressed.
local function Press(row, action)
    local button = Button(row, action)
    if not button:IsShown() or not button:IsEnabled() or button.action ~= action then
        return false
    end
    button._scripts.OnClick(button)
    for _ = 1, 60 do
        world:RunFor(1)
        if not ns.Prepare.Busy() then
            break
        end
    end
    world:RunFor(1)
    return true
end

H.section("Prepare: the buttons")
-- Mail is off for now (Prepare.mailPaused, see "at a mailbox"); on, to
-- test it.
ns.Prepare.mailPaused = false
local mailRow = Row(alice, byMail)
local personRow = Row(mike, inPerson)
-- The list, oldest first: a request made a minute later comes after.
local later = mike.ns.Requests.Create(bank.guid, "item:" .. ORE, 2, "", Requests.IN_PERSON)
world:RunFor(150)
page.SubTabs.Tabs[2]._scripts.OnClick(page.SubTabs.Tabs[2])
local listed = page.Requests.ScrollBox._provider.elements
H.check(#listed == 3 and listed[3].view.id == later and listed[3].view.requester == mike.guid
    and listed[1].view.request.c <= listed[2].view.request.c, "the list shows the oldest requests first")
mike.ns.Requests.Delete(later)
world:RunFor(150)
page.SubTabs.Tabs[2]._scripts.OnClick(page.SubTabs.Tabs[2])
H.check(Button(mailRow, "prepare"):IsShown() and Button(mailRow, "mail"):IsShown(), "a request by mail has Prepare and Mail")
H.check(Button(personRow, "prepare"):IsShown() and not Button(personRow, "mail"):IsShown(), "one in person, only Prepare")
H.check(Button(personRow, "prepare"):GetText() == "Prepare" and Button(mailRow, "mail"):GetText() == "Mail", "named so")
-- Neither the bank nor a mailbox open; the bags hold 15 and 10, kept for none.
H.check(not Button(mailRow, "prepare"):IsEnabled() and Tip(mailRow, "prepare"):find(
    "Your bags hold 25 of the 48 it still lacks, kept for no request: open your bank to bring the rest.", 1, true),
    "without the bank, Prepare is off when the bags lack some, and says why")
H.check(not Button(mailRow, "mail"):IsEnabled() and Tip(mailRow, "mail"):find("Open a mailbox to get its mail ready.", 1, true),
    "Mail is off without a mailbox, and says why")
H.check(not Press(mailRow, "prepare") and bank.moves == nil, "pressing a button that is off does nothing")

H.section("Prepare: from the bags alone")
H.check(Button(personRow, "prepare"):IsEnabled() and Tip(personRow, "prepare"):find(
    "Keeps in your bags the 5 it still lacks, from stacks kept for no request.", 1, true),
    "the bags holding enough kept for none, Prepare is on without the bank")
local printed = #bank.printed
Press(personRow, "prepare")
H.eq(BagStacks(CLOTH), "5 5 15", "it keeps 5 split off the bags' 10")
H.eq(KeptCounts(personRow), "5", "kept for the request")
H.check(Printed(bank, "x5 ready in your bags.", printed), "it says so")
H.check(PrepareIs(personRow) == "release" and Button(personRow, "prepare"):GetText() == "Release"
    and Button(personRow, "prepare"):IsEnabled(), "ready, its Prepare becomes Release")
H.eq(Tip(personRow, "prepare"), "Lets go of the 5 kept for it in your bags, for other requests to take.", "which says what it does")
-- Released: kept no more, and Prepare again.
printed = #bank.printed
H.check(Press(personRow, "release"), "Release can be pressed")
H.eq(KeptCounts(personRow), "", "it lets go of the request's stacks")
H.check(Printed(bank, "x5 no longer kept in your bags.", printed), "it says so")
H.eq(PrepareIs(personRow), "prepare", "and the button is Prepare again")
H.eq(BagStacks(CLOTH), "5 5 15", "nothing moves: the stacks stay where they are, kept for none")
Press(personRow, "prepare")
H.check(KeptCounts(personRow) == "5" and BagStacks(CLOTH) == "5 5 15", "prepared again, it keeps a 5 as it is: no move")
Errors(world, "bags alone")

H.section("Prepare: at the bank")
world:OpenBank(bank)
world:RunFor(3)
H.check(Button(mailRow, "prepare"):IsEnabled() and Tip(mailRow, "prepare"):find("from stacks kept for no request and from your bank", 1, true),
    "with the bank open, Prepare is on, and says it brings from the bank")
printed = #bank.printed
Press(mailRow, "prepare")
H.eq(BankStacks(CLOTH), "", "it takes the stacks that make the fewest: the bank's 20, 20 and 8")
H.eq(BagStacks(CLOTH), "5 5 8 15 20 20", "each into an empty slot: the bags' 15 and the 5 left of the 10 stay as they were")
H.eq(KeptCounts(mailRow) .. " / " .. KeptCounts(personRow), "8 20 20 / 5", "each request keeps its own")
H.check(Printed(bank, "x48 ready in your bags.", printed), "it says so")
local moves = bank.moves
H.check(not Press(personRow, "prepare") and PrepareIs(personRow) == "release" and bank.moves == moves,
    "a request ready has Release, not Prepare: nothing more comes")
world:CloseBank(bank)
Errors(world, "at the bank")

H.section("Prepare: at a mailbox")
OpenMailbox()
H.check(not Button(personRow, "mail"):IsShown(), "an in-person request has no Mail")
-- Mail is off for now, as the addon comes (Prepare.mailPaused): the mail is
-- sent by hand.
ns.Prepare.mailPaused = true
H.check(Button(mailRow, "mail"):IsShown() and not Button(mailRow, "mail"):IsEnabled(), "for now, Mail is shown but off")
H.eq(Tip(mailRow, "mail"), "Temporarily unavailable, under review. Send the mail by hand.", "and says so")
H.check(not ns.Prepare.Run(mailRow.view, "mail") and Mail() == 0, "nor does it run otherwise")
-- On again, to test the rest of it.
ns.Prepare.mailPaused = false
H.check(Button(mailRow, "mail"):IsEnabled() and Tip(mailRow, "mail"):find("Gets the mail to Alice Smith ready", 1, true),
    "at a mailbox, Mail is on, and says for whom")
printed = #bank.printed
Press(mailRow, "mail")
local count, stacks = Mail()
H.eq(count, 48, "the mail takes what is still to deliver")
H.eq(stacks, "8 20 20", "in the fewest stacks: partial stacks merged, the rest split off")
H.eq(bank.mailTab, 2, "on the Send tab")
H.eq(env.SendMailNameEditBox:GetText(), "Alice Smith", "to the requester")
local clothName = ns.BankView.ItemName("item:" .. CLOTH)
H.eq(env.SendMailSubjectEditBox:GetText(), "Request: " .. clothName .. " x48", "with the item and its count as the subject")
H.check(bank.mailRadio == 2 and env.SendMailMoney._copper == 90, "cash on delivery: 30 copper per stack")
H.check(Printed(bank, "mail ready for Alice Smith", printed), "it says so")
H.eq(BagStacks(CLOTH), "5 5 15", "the mail takes the stacks kept for the request: the bags keep the rest")
H.eq(KeptCounts(personRow), "5", "and the other request's 5")
-- The bank character sends it: the request is delivered.
local attached = {}
for slot, item in pairs(bank.sendMail) do
    attached[slot] = { item[1], item[2] }
end
local aliceTold = #alice.printed
world:Mail(bank, "Alice Smith", attached, { cod = 90 })
world:RunFor(150)
local view = Find(alice.ns.Requests.List(alice.ns.Data.CurrentGuild(false)), function(v) return v.id == byMail and v.requester == alice.guid end)
H.check(view == nil and Printed(alice, "your request was delivered", aliceTold), "once sent, the request is delivered: it goes")
local log = bank.ns.Data.GetOwnRecord(false).lg
H.check(Find(log, function(e) return e.v == bank.ns.Log.POSTAGE and e.m == 90 end) ~= nil, "and its postage is in the log")
CloseMailbox()
Errors(world, "at a mailbox")

H.section("Prepare: more than one mail takes")
local big = { size = 16 }
for slot = 1, 15 do
    big[slot] = { CLOTH, 20 }
end
world:SetContainer(bank, 1, big)
local many = Requests.Create(bank.guid, "item:" .. CLOTH, 290, "", Requests.BY_MAIL)
Accept(alice.guid, many)
world:RunFor(150)
page.SubTabs.Tabs[2]._scripts.OnClick(page.SubTabs.Tabs[2])
OpenMailbox()
printed = #bank.printed
local manyRow = Row(alice, many)
Press(manyRow, "mail")
count, stacks = Mail()
H.check(count == 240 and env.SendMailMoney._copper == 360, "12 stacks at most: " .. count)
H.check(Printed(bank, "50 more do not fit in one mail: press Mail again once this one is sent.", printed), "the rest is for another mail")
-- A mail with items already attached is left alone.
H.check(not Button(manyRow, "mail"):IsEnabled() and Tip(manyRow, "mail"):find("The mail already has items attached", 1, true),
    "with a mail already holding items, Mail is off, and says why")
CloseMailbox()
Errors(world, "many")

H.section("Prepare: not enough")
world:SetContainer(bank, 0, { size = 16, [3] = { ORE, 7 } })
world:SetContainer(bank, 1, { size = 16, [1] = { CLOTH, 20 }, [2] = { CLOTH, 6 } })
OpenMailbox()
printed = #bank.printed
H.check(Tip(manyRow, "mail"):find("Your bags hold 26 of the 290 it lacks: the mail takes those.", 1, true), "Mail says it takes what there is")
Press(manyRow, "mail")
count, stacks = Mail()
H.check(count == 26 and stacks == "6 20", "what the bags hold: " .. stacks)
H.check(Printed(bank, "only 26 of 290 in your bags", printed), "and it says so")
CloseMailbox()
Errors(world, "not enough")

H.section("Prepare: a stack split off into the mail")
world:SetContainer(bank, 1, { size = 16, [1] = { CLOTH, 20 }, [2] = { CLOTH, 20 } })
local split = Requests.Create(bank.guid, "item:" .. CLOTH, 25, "", Requests.BY_MAIL)
Accept(alice.guid, split)
world:RunFor(150)
page.SubTabs.Tabs[2]._scripts.OnClick(page.SubTabs.Tabs[2])
OpenMailbox()
-- A subject box taking 16 characters: the item's name is cut, the count stays.
env.SendMailSubjectEditBox.GetMaxLetters = function()
    return 16
end
Press(Row(alice, split), "mail")
count, stacks = Mail()
H.check(count == 25 and stacks == "5 20" and env.SendMailMoney._copper == 60, "a full stack and 5 split off: " .. stacks)
H.eq(env.SendMailSubjectEditBox:GetText(), "Request: " .. clothName:sub(1, 3) .. " x25", "a subject too long: the name cut to what fits")
env.SendMailSubjectEditBox.GetMaxLetters = nil
H.eq(BagCount(CLOTH), 15, "the rest of the split stack stays in the bags")
CloseMailbox()
Errors(world, "split")

H.section("Prepare: bank and mailbox both open")
world:SetContainer(bank, 1, { size = 16 })
world:SetContainer(bank, 6, { size = 48, [1] = { CLOTH, 20 }, [2] = { CLOTH, 20 } })
local both = Requests.Create(bank.guid, "item:" .. CLOTH, 30, "", Requests.BY_MAIL)
Accept(alice.guid, both)
world:RunFor(150)
page.SubTabs.Tabs[2]._scripts.OnClick(page.SubTabs.Tabs[2])
world:OpenBank(bank)
OpenMailbox()
local bothRow = Row(alice, both)
H.check(Button(bothRow, "prepare"):IsEnabled() and not Button(bothRow, "mail"):IsEnabled()
    and Tip(bothRow, "mail"):find("prepare it first", 1, true), "both open, nothing in the bags yet: Prepare on, Mail off until then")
Press(bothRow, "prepare")
H.check(Button(bothRow, "mail"):IsEnabled(), "once prepared, Mail is on")
Press(bothRow, "mail")
count, stacks = Mail()
H.check(count == 30 and stacks == "10 20", "Prepare brings the items from the bank, Mail puts them in the mail: " .. stacks)
world:CloseBank(bank)
CloseMailbox()
Errors(world, "both")

H.section("Prepare: no room in the bags")
-- Nothing set aside for the earlier requests, still open.
bank.ns.Data.OwnState().prepared = {}
local full = { size = 16 }
for slot = 1, 16 do
    full[slot] = { ORE, 1 }
end
world:SetContainer(bank, 0, full)
world:SetContainer(bank, 1, { size = 1, [1] = { ORE, 1 } })
world:SetContainer(bank, 6, { size = 48, [1] = { CLOTH, 20 }, [2] = { CLOTH, 20 } })
local roomless = Requests.Create(bank.guid, "item:" .. CLOTH, 30, "", Requests.BY_MAIL)
Accept(alice.guid, roomless)
world:RunFor(150)
page.SubTabs.Tabs[2]._scripts.OnClick(page.SubTabs.Tabs[2])
world:OpenBank(bank)
moves = bank.moves
local roomlessRow = Row(alice, roomless)
H.check(not Button(roomlessRow, "prepare"):IsEnabled() and Tip(roomlessRow, "prepare"):find("Not enough room in your bags: 2 free", 1, true),
    "with no room in the bags for the 2 stacks it takes, Prepare is off, and says how many free slots it takes")
H.check(not Press(roomlessRow, "prepare") and bank.moves == moves and BagCount(CLOTH) == 0, "nothing moves")
H.check(not bank.ns.Data.OwnState().prepared[roomlessRow.view.key], "and nothing is kept for it")
world:SetContainer(bank, 1, { size = 2, [1] = { ORE, 1 } })
world:RunFor(1)
H.check(not Button(roomlessRow, "prepare"):IsEnabled() and Tip(roomlessRow, "prepare"):find("2 free", 1, true),
    "with room for 1 of the 2 stacks, it stays off")
world:SetContainer(bank, 1, { size = 2 })
world:RunFor(1)
Press(roomlessRow, "prepare")
H.eq(BagStacks(CLOTH), "10 20", "with the room it takes, it comes")
world:CloseBank(bank)
Errors(world, "no room")

H.section("Prepare: the server answers late")
-- A request for 21 and another for the same item, of 1, got ready before:
-- its unit is in the bags. The bank holds the item in small stacks. The
-- server carries out each move a while after it is asked, and may unlock
-- the slots before the items show where they went: whatever the timing,
-- exactly 21 come, in two stacks (a 7, and a 14 made up of several).
local HERB = 2447
local herbs = Requests.Create(bank.guid, "item:" .. HERB, 21, "", Requests.IN_PERSON)
local herb = mike.ns.Requests.Create(bank.guid, "item:" .. HERB, 1, "", Requests.IN_PERSON)
Accept(alice.guid, herbs)
Accept(mike.guid, herb)
world:RunFor(150)
page.SubTabs.Tabs[2]._scripts.OnClick(page.SubTabs.Tabs[2])
local herbsRow = Row(alice, herbs)
local herbRow = Row(mike, herb)
world:SetContainer(bank, 1, { size = 16 })
world:OpenBank(bank)
for _, case in ipairs({
    { unlock = 0.1, move = 0.05, bags = 1, bank = { 2, 3, 4, 5, 6, 7 }, brings = 21, stacks = "1 7 14" },
    { unlock = 0.2, move = 0.4, bags = 1, bank = { 2, 3, 4, 5, 6, 7 }, brings = 21, stacks = "1 7 14" },
    { unlock = 0.1, move = 1.5, bags = 1, bank = { 2, 3, 4, 5, 6, 7 }, brings = 21, stacks = "1 7 14" },
    { unlock = 1, move = 0.6, bags = 1, bank = { 2, 3, 4, 5, 6, 7 }, brings = 21, stacks = "1 7 14" },
    -- The other request's unit back in the bank: it stays there, that
    -- request's to bring.
    { unlock = 0.1, move = 0.8, bags = 0, bank = { 1, 2, 3, 4, 5, 6, 7 }, brings = 21, stacks = "7 14" },
    -- A full stack, and 1 split off another.
    { unlock = 0.1, move = 0.8, bags = 1, bank = { 20, 20 }, brings = 21, stacks = "1 1 20" },
}) do
    local label = ("server %.2fs, unlock %.2fs, %s in the bank"):format(case.move, case.unlock, table.concat(case.bank, " "))
    world.moveDelay, world.unlockDelay = case.move, case.unlock
    world:SetContainer(bank, 0, { size = 16, [16] = case.bags > 0 and { HERB, case.bags } or nil })
    local container = { size = 48 }
    for slot, count in ipairs(case.bank) do
        container[slot] = { HERB, count }
    end
    world:SetContainer(bank, 6, container)
    ns.Data.OwnState().prepared = {}
    if case.bags > 0 then
        KeepFor(herbRow, 0, 16)
    end
    world:RunFor(1)
    Press(herbsRow, "prepare")
    H.eq(BagCount(HERB) - case.bags, case.brings, label .. ": brings exactly what is missing")
    H.eq(BagStacks(HERB), case.stacks, label .. ": in its own stacks")
end
world:CloseBank(bank)
-- At a mailbox, as late: a full stack, and a part split off into the bags
-- before it goes into the mail.
world.moveDelay, world.unlockDelay = 1.5, 0.1
world:SetContainer(bank, 0, { size = 16, [1] = { CLOTH, 4 }, [2] = { CLOTH, 9 }, [3] = { CLOTH, 20 } })
world:SetContainer(bank, 1, { size = 16 })
OpenMailbox()
Press(Row(alice, split), "mail")
count, stacks = Mail()
H.check(count == 25 and stacks == "5 20" and env.SendMailMoney._copper == 60, "at a mailbox, the mail takes exactly what is asked: " .. stacks)
H.eq(BagStacks(CLOTH), "4 4", "the rest stays in the bags")
CloseMailbox()
world.moveDelay, world.unlockDelay = nil, nil
Errors(world, "late")

H.section("Prepare: each request keeps its own")
-- A request for 21 and one for 1 of the same item, got ready before, their
-- items put back in the bank (so no longer kept): each click brings only
-- its own request's, in stacks of its own.
world:SetContainer(bank, 0, { size = 16 })
world:SetContainer(bank, 6, { size = 48, [1] = { HERB, 20 }, [2] = { HERB, 20 } })
ns.Data.OwnState().prepared = {}
world:OpenBank(bank)
world:RunFor(1)
printed = #bank.printed
Press(herbRow, "prepare")
H.eq(BagStacks(HERB), "1", "the request for 1 brings 1, not the other one's 21 too")
H.check(Printed(bank, "x1 ready in your bags.", printed), "it says so")
Press(herbsRow, "prepare")
H.eq(BagStacks(HERB), "1 1 20", "the request for 21 brings its 21, leaving the other one's 1 alone")
H.eq(KeptCounts(herbsRow) .. " / " .. KeptCounts(herbRow), "1 20 / 1", "each keeps its own stacks")
moves = bank.moves
H.check(not Press(herbRow, "prepare") and not Press(herbsRow, "prepare") and bank.moves == moves,
    "both ready, neither Prepare is on: nothing more comes")
-- Stacks already in the bags, kept for none, are kept as they are when
-- they fit; the next request splits its own off what is left.
world:SetContainer(bank, 0, { size = 16, [1] = { HERB, 20 }, [2] = { HERB, 10 } })
world:SetContainer(bank, 6, { size = 48 })
ns.Data.OwnState().prepared = {}
moves = bank.moves
Press(herbsRow, "prepare")
H.eq(bank.moves - moves, 1, "the request for 21 keeps the bags' 20 as it is, and splits 1 off the 10")
Press(herbRow, "prepare")
H.eq(BagStacks(HERB), "1 1 8 20", "the request for 1 splits its own off what is kept for none")
H.eq(KeptCounts(herbsRow) .. " / " .. KeptCounts(herbRow), "1 20 / 1", "each keeps its own")
-- Not enough for both: the first keeps what there is, the second gets none of it.
world:SetContainer(bank, 0, { size = 16 })
world:SetContainer(bank, 6, { size = 48, [1] = { HERB, 10 } })
ns.Data.OwnState().prepared = {}
printed = #bank.printed
H.check(Tip(herbsRow, "prepare"):find("Your bank and bags hold only 10 of them.", 1, true), "Prepare says there are only 10")
Press(herbsRow, "prepare")
H.check(BagStacks(HERB) == "10" and Printed(bank, "hold only 10 of 21", printed), "the request for 21 gets the 10 there are")
H.check(not Press(herbRow, "prepare") and Tip(herbRow, "prepare"):find("Your bank and bags hold none of it kept for no request.", 1, true),
    "the request for 1 can take none of them: its Prepare is off, and says why")
local herbsTip = Tip(herbsRow, "prepare")
H.check(PrepareIs(herbsRow) == "release" and herbsTip:find("Lets go of the 10 kept for it", 1, true)
    and herbsTip:find("Your bank and bags hold none of it kept for no request.", 1, true),
    "the request for 21, keeping 10 with no more to be had, has Release, saying why it cannot get the rest: " .. herbsTip)
world:CloseBank(bank)
H.check(Tip(herbRow, "prepare"):find("Your bags hold none of it kept for no request: open your bank to bring it.", 1, true),
    "with the bank closed, it says to open it")
-- At a mailbox, the mail leaves out the items kept for other requests.
world:SetContainer(bank, 0, { size = 16, [1] = { CLOTH, 5 } })
world:SetContainer(bank, 1, { size = 16 })
ns.Data.OwnState().prepared = {}
KeepFor(personRow, 0, 1)
OpenMailbox()
local splitRow = Row(alice, split)
H.check(not Press(splitRow, "mail") and Mail() == 0 and BagCount(CLOTH) == 5,
    "with only another request's items in the bags, Mail is off: the mail takes none")
H.check(Tip(splitRow, "mail"):find("Your bags hold none of it for this request: prepare it first.", 1, true), "it says why")
CloseMailbox()
bank.containers[0][2] = { CLOTH, 20 }
OpenMailbox()
printed = #bank.printed
Press(Row(alice, split), "mail")
count, stacks = Mail()
H.check(count == 20 and BagStacks(CLOTH) == "5", "with more, the mail takes only the rest: " .. stacks)
H.check(Printed(bank, "only 20 of 25", printed) and Printed(bank, "x5 in your bags are kept", printed), "and says so")
CloseMailbox()
Errors(world, "keeps its own")

H.section("Prepare: the padlock")
-- The game's backpack window: its item buttons, redrawn by UpdateItems.
local buttons = {}
for slot = 1, 16 do
    local button = H.NewObject(bank, "ItemButton")
    button.GetBagID = function()
        return 0
    end
    button.GetID = function()
        return slot
    end
    buttons[slot] = button
end
env.ContainerFrame1 = H.NewObject(bank, "Frame")
env.ContainerFrame1.UpdateItems = function() end
env.ContainerFrame1.EnumerateValidItems = function()
    return ipairs(buttons)
end
ns.BagLocks.Init()
-- The slots with a padlock shown, once the game redraws the window.
local function Padlocks()
    env.ContainerFrame1:UpdateItems()
    local list = {}
    for slot, button in ipairs(buttons) do
        local lock = ns.BagLocks.LockOf(button)
        if lock and lock:IsShown() then
            list[#list + 1] = slot
        end
    end
    return table.concat(list, " ")
end
world:SetContainer(bank, 0, { size = 16 })
world:SetContainer(bank, 6, { size = 48, [1] = { HERB, 20 }, [2] = { HERB, 20 } })
ns.Data.OwnState().prepared = {}
world:OpenBank(bank)
world:RunFor(1)
H.eq(Padlocks(), "", "no padlock while nothing is kept")
Press(herbsRow, "prepare")
H.eq(Padlocks(), "1 2", "a padlock on each stack kept: the 20 and the 1")
local lock = ns.BagLocks.LockOf(buttons[1])
H.check(lock._point and lock._point[1] == "TOPRIGHT" and lock._point[2] == buttons[1] and lock._point[4] < 0 and lock._point[5] < 0,
    "in the icon's top right corner, all within it")
lock._scripts.OnEnter(lock)
local tip = table.concat(env.GameTooltip._lines, "\n")
H.check(tip:find("Kept for a request", 1, true) and tip:find("Alice Smith asked for", 1, true) and tip:find("x21.", 1, true)
    and tip:find("lets it go", 1, true), "the padlock's tooltip says for which request, and what lets it go: " .. tip)
-- The player moves the stack of 20 to another slot: still kept.
env.C_Container.PickupContainerItem(0, 1)
env.C_Container.PickupContainerItem(0, 9)
world:RunFor(2)
H.eq(Padlocks(), "2 9", "moved within the bags, the stack is still kept: its padlock goes with it")
-- The player splits it: let go.
env.C_Container.SplitContainerItem(0, 9, 5)
env.C_Container.PickupContainerItem(0, 12)
world:RunFor(2)
H.eq(Padlocks(), "2", "split, it is let go: its padlock goes away")
H.eq(KeptCounts(herbsRow), "1", "only the stack left as it was stays kept")
-- The player adds to the other one: let go too.
env.C_Container.SplitContainerItem(0, 12, 1)
env.C_Container.PickupContainerItem(0, 2)
world:RunFor(2)
H.eq(Padlocks(), "", "added to, it is let go too")
-- Clicked again, the request gets what it lacks kept again.
Press(herbsRow, "prepare")
-- Bags 2, 4 and 15, kept for none; the bank 19: the fewest stacks are the
-- bank's 19 and the bags' 2, as it is.
H.eq(KeptCounts(herbsRow), "2 19", "a click keeps what the request lacks again: " .. BagStacks(HERB))
world:CloseBank(bank)
-- The request rejected: its stacks are let go.
H.check(bank.ns.Requests.Reject(alice.guid, herbs), "(the request rejected)")
world:RunFor(150)
H.eq(Padlocks(), "", "once the request is no longer open, its padlocks go away")
H.eq(KeptCounts(herbsRow), "", "and nothing is kept for it")
Errors(world, "padlock")

H.section("Prepare: two requests by mail for the same item")
local ROOT = 2449
local root21 = Requests.Create(bank.guid, "item:" .. ROOT, 21, "", Requests.BY_MAIL)
local root1 = mike.ns.Requests.Create(bank.guid, "item:" .. ROOT, 1, "", Requests.BY_MAIL)
Accept(alice.guid, root21)
Accept(mike.guid, root1)
world:RunFor(150)
page.SubTabs.Tabs[2]._scripts.OnClick(page.SubTabs.Tabs[2])
local root21Row, root1Row = Row(alice, root21), Row(mike, root1)
for _, case in ipairs({
    { label = "nothing kept, the bags with stacks of 20", bags = { 20, 20 } },
    { label = "nothing kept, the bags with 21 and 1 apart", bags = { 20, 1, 1 } },
    { label = "kept at the bank first", bags = {}, bank = { 20, 20 } },
}) do
    world:SetContainer(bank, 1, { size = 16 })
    local bags = { size = 16 }
    for slot, n in ipairs(case.bags) do
        bags[slot] = { ROOT, n }
    end
    world:SetContainer(bank, 0, bags)
    ns.Data.OwnState().prepared = {}
    if case.bank then
        local container = { size = 48 }
        for slot, n in ipairs(case.bank) do
            container[slot] = { ROOT, n }
        end
        world:SetContainer(bank, 6, container)
        world:OpenBank(bank)
        world:RunFor(1)
        Press(root1Row, "prepare")
        Press(root21Row, "prepare")
        world:CloseBank(bank)
    end
    for _, which in ipairs({ { root1Row, 1, "Mike Stone" }, { root21Row, 21, "Alice Smith" } }) do
        local row, n, name = which[1], which[2], which[3]
        local before = H.DeepCopy(bank.containers[0])
        OpenMailbox()
        H.check(Button(row, "mail"):IsEnabled() and Tip(row, "mail"):find("Gets the mail to " .. name .. " ready", 1, true),
            case.label .. ": the request for " .. n .. " has Mail on")
        printed = #bank.printed
        Press(row, "mail")
        count, stacks = Mail()
        H.check(count == n and env.SendMailNameEditBox:GetText() == name, case.label .. ": the request for " .. n .. " gets its mail: "
            .. count .. " to " .. tostring(env.SendMailNameEditBox:GetText()) .. " / " .. table.concat(bank.printed, " | ", printed + 1))
        CloseMailbox()
        -- The mail not sent: its items are back in the bags, as they were.
        world:SetContainer(bank, 0, before)
        world:RunFor(1)
    end
end
Errors(world, "two by mail")

H.section("Prepare: a mail made ready counts towards its request first")
-- Two requests alike, both accepted: Mail on the newer one, then sent.
local SILK = 4306
world:SetContainer(bank, 2, { size = 16, [1] = { SILK, 20 }, [2] = { SILK, 20 } })
local olderSilk = Requests.Create(bank.guid, "item:" .. SILK, 20, "", Requests.BY_MAIL)
world:RunFor(5)
local newerSilk = Requests.Create(bank.guid, "item:" .. SILK, 20, "", Requests.BY_MAIL)
Accept(alice.guid, olderSilk)
Accept(alice.guid, newerSilk)
world:RunFor(150)
page.SubTabs.Tabs[2]._scripts.OnClick(page.SubTabs.Tabs[2])
OpenMailbox()
H.check(Press(Row(alice, newerSilk), "mail"), "Mail on the newer of two requests alike, both accepted")
local silkMail = {}
for slot, item in pairs(bank.sendMail or {}) do
    silkMail[slot] = { item[1], item[2] }
end
world:Mail(bank, "Alice Smith", silkMail, { cod = 30 })
world:RunFor(150)
local function SilkView(id)
    return Find(alice.ns.Requests.List(alice.ns.Data.CurrentGuild(false)), function(v)
        return v.requester == alice.guid and v.id == id
    end)
end
H.check(SilkView(newerSilk) == nil and SilkView(olderSilk) ~= nil and SilkView(olderSilk).delivered == 0,
    "sent, it counts towards that request, though the other is older")
CloseMailbox()
Errors(world, "mail made ready")

H.section("Prepare: stacks put together")
do
    -- A request for 35: the bags hold 1 and 20, the bank 14. The fewest
    -- stacks are the 20, as it is, and a 15 made up of the 1, where it is,
    -- and the bank's 14 put onto it: one move.
    local BAR = 2840
    local bars = Requests.Create(bank.guid, "item:" .. BAR, 35, "", Requests.IN_PERSON)
    Accept(alice.guid, bars)
    world:RunFor(150)
    page.SubTabs.Tabs[2]._scripts.OnClick(page.SubTabs.Tabs[2])
    local barsRow = Row(alice, bars)
    world:SetContainer(bank, 0, { size = 16, [3] = { BAR, 1 }, [7] = { BAR, 20 } })
    world:SetContainer(bank, 1, { size = 16 })
    world:SetContainer(bank, 6, { size = 48, [5] = { BAR, 14 } })
    world:OpenBank(bank)
    world:RunFor(1)
    local before = bank.moves or 0
    H.check(Press(barsRow, "prepare"), "(Prepare pressed)")
    H.eq(BagStacks(BAR), "15 20", "the bags' 1 and the bank's 14 are put together")
    H.eq(KeptCounts(barsRow), "15 20", "both stacks kept for the request")
    H.eq(bank.moves - before, 1, "in one move: the bank's 14 onto the 1")
    H.eq(BankStacks(BAR), "", "(none left in the bank)")
    -- Got ready with less than it lacks, so one of its stacks is not full;
    -- once the rest is to be had, it goes onto that stack.
    H.check(Press(barsRow, "release"), "(let go)")
    world:SetContainer(bank, 0, { size = 16, [3] = { BAR, 1 }, [7] = { BAR, 20 } })
    world:SetContainer(bank, 6, { size = 48 })
    world:RunFor(1)
    H.check(Press(barsRow, "prepare"), "(Prepare pressed, the bank without any)")
    H.eq(KeptCounts(barsRow), "1 20", "with only 21 to be had, the 20 and the 1 are kept")
    world:SetContainer(bank, 6, { size = 48, [5] = { BAR, 14 } })
    world:RunFor(1)
    before = bank.moves
    H.check(Press(barsRow, "prepare"), "(Prepare pressed again, the bank with 14)")
    H.eq(KeptCounts(barsRow), "15 20", "the rest goes onto the 1 kept before")
    H.eq(BagStacks(BAR) .. " / " .. (bank.moves - before), "15 20 / 1", "(in the bags, in one move)")
    -- Two full stacks and a remainder made up of three small ones.
    H.check(Press(barsRow, "release"), "(let go again)")
    world:SetContainer(bank, 0, { size = 16, [1] = { BAR, 4 }, [2] = { BAR, 20 } })
    world:SetContainer(bank, 6, { size = 48, [1] = { BAR, 6 }, [2] = { BAR, 3 }, [3] = { BAR, 9 } })
    world:RunFor(1)
    H.check(Press(barsRow, "prepare"), "(Prepare pressed on other stacks)")
    H.eq(KeptCounts(barsRow), "15 20", "a 15 made up of the bags' 4 and the bank's 9, and 2 of its 3")
    H.eq(BagStacks(BAR) .. " / " .. BankStacks(BAR), "15 20 / 1 6", "the rest stays in the bank")
    world:CloseBank(bank)
end
Errors(world, "put together")

H.section("Prepare: only the bank character's own requests")
world:OpenBank(alice)
local aliceEnv = alice.env
aliceEnv.GuildBankAltsGuildTab._scripts.OnClick(aliceEnv.GuildBankAltsGuildTab)
local alicePage = aliceEnv.GuildBankAltsGuildPanel
alicePage.SubTabs.Tabs[2]._scripts.OnClick(alicePage.SubTabs.Tabs[2])
local aliceElement = Find(alicePage.Requests.ScrollBox._provider.elements, function(e) return e.view.id == both end)
H.eq(alice.ns.Prepare.Actions(aliceElement.view), nil, "a member has no Prepare nor Mail on a request")
local aliceRow = H.NewObject(alice, "Frame")
alicePage.Requests.ScrollBox._view.init(aliceRow, aliceElement)
H.check(not aliceRow.Prepare:IsShown() and not aliceRow.Mail:IsShown(), "none shown in the row")
world:CloseBank(alice)
Errors(world, "members")
