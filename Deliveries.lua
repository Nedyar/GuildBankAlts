-- Deliveries.lua: what a guild bank character trades and mails, read from
-- the game. Two uses:
--   - what it hands over to the members who requested it, by trade or by
--     mail: each item given counts towards the giver's requests from that
--     member for that item, until each has its quantity: it is then
--     approved (Requests.Deliver). First the request a mail was made ready
--     for with its Mail button (Prepare.lua), then the accepted ones, then
--     the other open ones, then the rejected ones (delivered anyway, they
--     are approved too); the oldest first among each. Deliveries in several
--     goes add up, by trade and mail alike;
--   - the bank's log (Log.lua): every item and every coin it gives or gets,
--     by trade, by mail (sent, or taken from the mailbox), the cash on
--     delivery and the postage it pays, and the money it puts into the guild
--     vault or takes from it.
--
-- Trade and mail are read as in Guild Professions & Recipes 0.9, whose
-- crafting orders count deliveries the same way.
local _, ns = ...
local L = ns.L
local Data, Requests = ns.Data, ns.Requests

local Deliveries = {}
ns.Deliveries = Deliveries

local TRADE_SLOTS = 6               -- the slots that change hands (the 7th is not traded)
local TRADE_COMPLETE_WINDOW = 5     -- seconds from the window closing to the game's "Trade complete."

local function Name(guid)
    local guild = Data.CurrentGuild(false)
    return Data.NameOf(guid, guild and guild.members[guid])
end

-- Counting ---------------------------------------------------------------------------

-- Which requests a delivery counts towards first (see the top of this file).
local ORDER = { accepted = 1, pending = 2, partial = 2, rejected = 3 }

-- What we gave a guildmate (partner, a GUID): given is { [itemID] = count }.
-- first: the key of the request it counts towards first (a mail made ready
-- with the Mail button), or nil. Only a bank character's deliveries count.
function Deliveries.Exchanged(partner, given, first)
    local guild = Data.CurrentGuild(false)
    if not guild or not partner or partner == ns.playerGUID or not ns.Ranks.IsBank(ns.playerGUID) then
        return
    end
    local left = {}
    for itemID, count in pairs(given or {}) do
        left[itemID] = count
    end
    local views = {}
    for _, view in ipairs(Requests.List(guild)) do
        if view.requester == partner and view.state ~= "approved" then
            views[#views + 1] = view
        end
    end
    local function Rank(view)
        return view.key == first and 0 or ORDER[view.state] or 2
    end
    table.sort(views, function(a, b)
        if Rank(a) ~= Rank(b) then
            return Rank(a) < Rank(b)
        elseif a.request.c ~= b.request.c then
            return a.request.c < b.request.c
        end
        return a.id < b.id
    end)
    for _, view in ipairs(views) do
        local itemID = view.request.i
        local have = left[itemID] or 0
        local count = math.min(have, view.request.q - view.delivered)
        if count > 0 then
            local delivered, approved = Requests.Deliver(partner, view.id, count)
            if delivered then
                left[itemID] = have - count
                local item = ns.BankView and ns.BankView.ItemName(view.request.s or ("item:" .. itemID)) or ("item:" .. itemID)
                if approved then
                    ns.Print(L["delivered to %s, request approved: %s x%d."], Name(partner), item, view.request.q)
                else
                    ns.Print(L["%d of %d delivered to %s: %s."], delivered, view.request.q, Name(partner), item)
                end
            end
        end
    end
end

-- The game ---------------------------------------------------------------------------

-- Items are counted by item string: { [item string] = count }, the string
-- as the bank shares it (Bank.ItemString), or "item:<ID>" when it says no
-- more than the ID.
local function ItemKey(link, itemID)
    local itemString = ns.Bank.ItemString(ns.Plain(link))
    if not itemString then
        itemID = ns.Plain(itemID)
        if type(itemID) ~= "number" or itemID < 1 then
            return nil
        end
        itemString = "item:" .. math.floor(itemID)
    end
    return ns.Bank.Meaningful(itemString) or ("item:" .. itemString:match("^item:(%d+)"))
end

local function Add(items, key, count)
    count = ns.Plain(count)
    if key and type(count) == "number" and count > 0 then
        items[key] = (items[key] or 0) + count
    end
end

-- The same by item ID, as requests count them.
local function ByID(items)
    local byID = {}
    for key, count in pairs(items or {}) do
        local itemID = tonumber(key:match("^item:(%d+)"))
        byID[itemID] = (byID[itemID] or 0) + count
    end
    return byID
end

local function Describe(items)
    local parts = {}
    for key, count in pairs(items or {}) do
        parts[#parts + 1] = count .. "x" .. key
    end
    table.sort(parts)
    return #parts > 0 and table.concat(parts, " ") or "-"
end

local function Copper(value)
    value = ns.Plain(value)
    return type(value) == "number" and value > 0 and math.floor(value) or 0
end

-- A guildmate by name, as mail gives it ("Name Surname", maybe with a realm).
local function ByName(name)
    name = ns.Plain(name)
    if type(name) ~= "string" or name == "" then
        return nil
    end
    return Data.FindByName(Data.CurrentGuild(false), name)
end

-- How the log names the other side: a guildmate as the roster does, anyone
-- else (the auction house's mail, say) as the game gave the name.
local function ShownName(partner, name)
    local known = partner and ns.Roster.NameOf(partner)
    if known then
        return known
    end
    name = ns.Plain(name)
    return type(name) == "string" and strtrim(name) or ""
end

-- what: "trade", "mail to <name>"..., for the debug log. via: how, for the
-- bank's log (Log.TRADE...). partner: the GUID of the guildmate, if it is
-- one; name: as the game gave it. before: our money before (see
-- Log.Record).
-- first: the request the items count towards first (Deliveries.Exchanged).
local function Exchanged(what, via, partner, name, given, received, moneyGiven, moneyReceived, before, first)
    ns.Debug("%s, %s: gave %s and %d copper, got %s and %d copper", what, tostring(name), Describe(given), moneyGiven or 0,
        Describe(received), moneyReceived or 0)
    if given and next(given) ~= nil then
        ns.SafeCall(Deliveries.Exchanged, partner, ByID(given), first)
    end
    ns.SafeCall(ns.Log.Record, via, ShownName(partner, name), given, received, moneyGiven, moneyReceived, before)
end

-- Trade: what each side puts in is read as it changes, since the window is
-- empty by the time the game says the trade is complete.
local trade

local function TradeName()
    local first, second = UnitName("NPC")
    first, second = ns.Plain(first), ns.Plain(second)
    if type(first) ~= "string" then
        return nil
    end
    return type(second) == "string" and second ~= "" and (first .. " " .. second) or first
end

local function TradePartner(name)
    local guid = ns.Plain(UnitGUID("NPC"))
    if Data.IsGUID(guid) then
        return guid
    end
    return ByName(name)
end

local function ReadTrade()
    if not trade or trade.closed then
        return
    end
    local given, received = {}, {}
    for slot = 1, TRADE_SLOTS do
        Add(given, ItemKey(GetTradePlayerItemLink(slot)), (select(3, GetTradePlayerItemInfo(slot))))
        Add(received, ItemKey(GetTradeTargetItemLink(slot)), (select(3, GetTradeTargetItemInfo(slot))))
    end
    trade.given, trade.received = given, received
    trade.moneyGiven = Copper(GetPlayerTradeMoney and GetPlayerTradeMoney())
    trade.moneyReceived = Copper(GetTargetTradeMoney and GetTargetTradeMoney())
    -- Our money, before the trade moves any.
    trade.before = ns.Number(GetMoney())
end

local function TradeComplete(message)
    if not trade or not ERR_TRADE_COMPLETE or message ~= ERR_TRADE_COMPLETE then
        return
    end
    if trade.closed and GetTime() - trade.closedAt > TRADE_COMPLETE_WINDOW then
        trade = nil
        return
    end
    local done = trade
    trade = nil
    Exchanged("trade", ns.Log.TRADE, done.partner, done.name, done.given, done.received, done.moneyGiven, done.moneyReceived,
        done.before)
end

-- Mail sent: what is attached when it goes, counted once the game says it
-- went. Attachments are also read as they change, in case the game has
-- emptied them by then.
local attached, attachedPostage, outgoing = {}, 0, nil

local function SentMoney()
    return Copper(GetSendMailMoney and GetSendMailMoney())
end

-- The postage of the mail (per item attached). The game's price of a mail
-- counts the money it carries too (a mail with 1 copper costs 31): that is
-- not postage.
local function Postage()
    return math.max(Copper(GetSendMailPrice and GetSendMailPrice()) - SentMoney(), 0)
end

local function Attached()
    local items = {}
    for slot = 1, ATTACHMENTS_MAX_SEND or 12 do
        local _, itemID, _, count = GetSendMailItem(slot)
        Add(items, ItemKey(GetSendMailItemLink and GetSendMailItemLink(slot), itemID), count)
    end
    return items
end

-- The request the last mail made ready with the Mail button was for:
-- { requester = GUID, key }, until a mail is sent or the mailbox closes.
local readyFor

-- Prepare.lua: a mail was made ready for the request key of requester.
function Deliveries.MailReadyFor(requester, key)
    readyFor = { requester = requester, key = key }
end

local function OnSendMail(recipient)
    local items, postage = Attached(), Postage()
    if next(items) == nil then
        items, postage = attached, math.max(postage, attachedPostage)
    end
    -- Our money is read before the game takes what the mail carries.
    outgoing = {
        to = ns.Plain(recipient), items = items, money = SentMoney(), postage = postage, before = ns.Number(GetMoney()),
    }
    -- Sent to whom it was made ready for: its items count towards that
    -- request first.
    if readyFor and ByName(outgoing.to) == readyFor.requester then
        outgoing.first = readyFor.key
    end
end

-- Mail taken: the items and money of a mail as they are taken from it,
-- counted once the inbox changes, or dropped if the game refuses (bags
-- full...). Taking the items of a mail sent cash on delivery pays it.
local taking = {}
local TAKE_ERRORS = { "ERR_INV_FULL", "ERR_ITEM_MAX_COUNT", "ERR_MAIL_DATABASE_ERROR" }

-- what: "item" (one slot), "money", or "all" (items and money).
local function OnTake(index, slot, what)
    index, slot = ns.Plain(index), ns.Plain(slot)
    if type(index) ~= "number" then
        return
    end
    -- The same thing taken twice before the game answers counts once, and
    -- so does a mail's cash on delivery.
    -- Our money before it: what we have, and what takes still waiting for
    -- the game's answer will bring or cost.
    local paying, before = false, ns.Number(GetMoney())
    for _, take in ipairs(taking) do
        if take.index == index and (take.what == "all" or what == "all" or take.what == what and take.slot == slot) then
            return
        end
        paying = paying or (take.index == index and take.cod > 0)
        before = before and (before + take.money - take.cod)
    end
    local _, _, sender, _, money, cod, _, _, _, wasReturned = GetInboxHeaderInfo(index)
    local items = {}
    if what ~= "money" then
        for i = slot or 1, slot or ATTACHMENTS_MAX_RECEIVE or 16 do
            local _, itemID, _, count = GetInboxItem(index, i)
            Add(items, ItemKey(GetInboxItemLink and GetInboxItemLink(index, i), itemID), count)
        end
    end
    local copper = what ~= "item" and Copper(money) or 0
    if next(items) ~= nil or copper > 0 then
        taking[#taking + 1] = {
            index = index, slot = slot, what = what, from = ns.Plain(sender), returned = ns.Plain(wasReturned) == true,
            items = items, money = copper, cod = (next(items) ~= nil and not paying) and Copper(cod) or 0, before = before,
        }
    end
end

-- Money put into the guild vault or taken from it, however the game's
-- window does it: counted once our money shows it, or dropped if it does
-- not in a while (the vault refused).
local VAULT_WAIT = 10
local vaultMoney

local function OnVaultMoney(sign, amount)
    amount = Copper(amount)
    local before = ns.Number(GetMoney())
    if amount > 0 and before then
        vaultMoney = { sign = sign, amount = amount, before = before, at = GetTime() }
    end
end

local function VaultMoneyMoved()
    local pending = vaultMoney
    if not pending then
        return
    end
    if GetTime() - pending.at > VAULT_WAIT then
        vaultMoney = nil
        return
    end
    if ns.Number(GetMoney()) ~= pending.before + pending.sign * pending.amount then
        return
    end
    vaultMoney = nil
    local taken = pending.sign > 0
    Exchanged(taken and "taken from the guild vault" or "put into the guild vault", ns.Log.VAULT, nil, "", nil, nil,
        not taken and pending.amount or nil, taken and pending.amount or nil, pending.before)
end

-- UI_INFO_MESSAGE and UI_ERROR_MESSAGE give (type, message).
local function MessageOf(...)
    local first, second = ...
    second = ns.Plain(second)
    if type(second) == "string" then
        return second
    end
    return ns.Plain(first)
end

local function OnEvent(_, event, ...)
    if event == "TRADE_SHOW" then
        local name = TradeName()
        trade = {
            partner = TradePartner(name), name = name, given = {}, received = {}, moneyGiven = 0, moneyReceived = 0,
            before = ns.Number(GetMoney()),
        }
    elseif event == "TRADE_CLOSED" then
        if trade and not trade.closed then
            trade.closed, trade.closedAt = true, GetTime()
        end
    elseif event == "TRADE_PLAYER_ITEM_CHANGED" or event == "TRADE_TARGET_ITEM_CHANGED" or event == "TRADE_ACCEPT_UPDATE"
            or event == "TRADE_MONEY_CHANGED" then
        ReadTrade()
    elseif event == "UI_INFO_MESSAGE" then
        TradeComplete(MessageOf(...))
    elseif event == "MAIL_SEND_INFO_UPDATE" then
        attached, attachedPostage = Attached(), Postage()
    elseif event == "MAIL_SEND_SUCCESS" then
        local sent = outgoing
        outgoing, attached, attachedPostage, readyFor = nil, {}, 0, nil
        if sent then
            local partner = ByName(sent.to)
            Exchanged("mail to " .. tostring(sent.to), ns.Log.MAIL, partner, sent.to, sent.items, nil, sent.money, nil,
                sent.before, sent.first)
            if sent.postage > 0 then
                Exchanged("postage of a mail to " .. tostring(sent.to), ns.Log.POSTAGE, partner, sent.to, nil, nil, sent.postage, nil,
                    sent.before and (sent.before - sent.money))
            end
        end
    elseif event == "MAIL_FAILED" then
        outgoing = nil
    elseif event == "MAIL_CLOSED" then
        readyFor = nil
    elseif event == "MAIL_INBOX_UPDATE" then
        local taken = taking
        taking = {}
        for _, take in ipairs(taken) do
            local partner = ByName(take.from)
            local via = take.returned and ns.Log.RETURNED or ns.Log.MAIL
            Exchanged("mail from " .. tostring(take.from), via, partner, take.from, nil, take.items, nil, take.money, take.before)
            if take.cod > 0 then
                Exchanged("cash on delivery to " .. tostring(take.from), ns.Log.COD, partner, take.from, nil, nil, take.cod, nil,
                    take.before and (take.before + take.money))
            end
        end
    elseif event == "PLAYER_MONEY" then
        VaultMoneyMoved()
    elseif event == "UI_ERROR_MESSAGE" then
        local message = MessageOf(...)
        for _, name in ipairs(TAKE_ERRORS) do
            if message ~= nil and message == _G[name] then
                taking = {}
            end
        end
    end
end

local function Hook(target, name, fn)
    local safe = function(...)
        ns.SafeCall(fn, ...)
    end
    if target and type(target[name]) == "function" then
        hooksecurefunc(target, name, safe)
    end
end

function Deliveries.Init()
    local frame = CreateFrame("Frame")
    ns.RegisterEvents(frame, "TRADE_SHOW", "TRADE_CLOSED", "TRADE_PLAYER_ITEM_CHANGED", "TRADE_TARGET_ITEM_CHANGED",
        "TRADE_MONEY_CHANGED", "TRADE_ACCEPT_UPDATE", "UI_INFO_MESSAGE", "UI_ERROR_MESSAGE", "MAIL_SEND_INFO_UPDATE",
        "MAIL_SEND_SUCCESS", "MAIL_FAILED", "MAIL_CLOSED", "MAIL_INBOX_UPDATE", "PLAYER_MONEY")
    frame:SetScript("OnEvent", OnEvent)
    Hook(_G, "SendMail", OnSendMail)
    Hook(C_Mail, "SendMail", OnSendMail)
    Hook(_G, "TakeInboxItem", function(index, slot)
        OnTake(index, slot, "item")
    end)
    Hook(_G, "TakeInboxMoney", function(index)
        OnTake(index, nil, "money")
    end)
    Hook(_G, "AutoLootMailItem", function(index)
        OnTake(index, nil, "all")
    end)
    Hook(_G, "WithdrawGuildBankMoney", function(amount)
        OnVaultMoney(1, amount)
    end)
    Hook(_G, "DepositGuildBankMoney", function(amount)
        OnVaultMoney(-1, amount)
    end)
end
