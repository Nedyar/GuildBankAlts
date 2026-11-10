-- Deliveries.lua: what a guild bank character hands over to the members
-- who requested it, by trade or by mail. Each item given counts towards
-- the giver's requests from that member for that item, the oldest first,
-- until each has its quantity: it is then approved (Requests.Deliver).
-- Deliveries in several goes add up, by trade and mail alike. A rejected
-- request whose items are delivered anyway is approved too.
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

-- What we gave a guildmate (partner, a GUID): given is { [itemID] = count }.
-- Only a bank character's deliveries count.
function Deliveries.Exchanged(partner, given)
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
    -- The oldest first.
    table.sort(views, function(a, b)
        if a.request.c ~= b.request.c then
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

local function ItemID(link)
    return type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
end

local function Add(items, itemID, count)
    itemID, count = ns.Plain(itemID), ns.Plain(count)
    if type(itemID) == "number" and type(count) == "number" and count > 0 then
        items[itemID] = (items[itemID] or 0) + count
    end
end

local function Describe(items)
    local parts = {}
    for itemID, count in pairs(items or {}) do
        parts[#parts + 1] = count .. "x" .. itemID
    end
    return #parts > 0 and table.concat(parts, " ") or "-"
end

-- A guildmate by name, as mail gives it ("Name Surname", maybe with a realm).
local function ByName(name)
    name = ns.Plain(name)
    if type(name) ~= "string" or name == "" then
        return nil
    end
    return Data.FindByName(Data.CurrentGuild(false), name)
end

local function Exchanged(how, partner, given)
    ns.Debug("%s, %s: gave %s", how, tostring(partner), Describe(given))
    ns.SafeCall(Deliveries.Exchanged, partner, given)
end

-- Trade: what we put in is read as it changes, since the window is empty
-- by the time the game says the trade is complete.
local trade

local function TradePartner()
    local guid = ns.Plain(UnitGUID("NPC"))
    if Data.IsGUID(guid) then
        return guid
    end
    local first, second = UnitName("NPC")
    first, second = ns.Plain(first), ns.Plain(second)
    return ByName(second and second ~= "" and first and (first .. " " .. second) or first)
end

local function ReadTrade()
    if not trade or trade.closed then
        return
    end
    local given = {}
    for slot = 1, TRADE_SLOTS do
        Add(given, ItemID(ns.Plain(GetTradePlayerItemLink(slot))), (select(3, GetTradePlayerItemInfo(slot))))
    end
    trade.given = given
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
    Exchanged("trade", done.partner, done.given)
end

-- Mail sent: what is attached when it goes, counted once the game says it
-- went. Attachments are also read as they change, in case the game has
-- emptied them by then.
local attached, outgoing = {}, nil

local function Attached()
    local items = {}
    for slot = 1, ATTACHMENTS_MAX_SEND or 12 do
        local _, itemID, _, count = GetSendMailItem(slot)
        itemID = ns.Plain(itemID)
        if type(itemID) ~= "number" and GetSendMailItemLink then
            itemID = ItemID(ns.Plain(GetSendMailItemLink(slot)))
        end
        Add(items, itemID, count)
    end
    return items
end

local function OnSendMail(recipient)
    local items = Attached()
    if next(items) == nil then
        items = attached
    end
    outgoing = { to = recipient, items = items }
end

-- UI_INFO_MESSAGE gives (type, message).
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
        trade = { partner = TradePartner(), given = {} }
    elseif event == "TRADE_CLOSED" then
        if trade and not trade.closed then
            trade.closed, trade.closedAt = true, GetTime()
        end
    elseif event == "TRADE_PLAYER_ITEM_CHANGED" or event == "TRADE_ACCEPT_UPDATE" then
        ReadTrade()
    elseif event == "UI_INFO_MESSAGE" then
        TradeComplete(MessageOf(...))
    elseif event == "MAIL_SEND_INFO_UPDATE" then
        attached = Attached()
    elseif event == "MAIL_SEND_SUCCESS" then
        local sent = outgoing
        outgoing, attached = nil, {}
        if sent then
            Exchanged("mail to " .. tostring(sent.to), ByName(sent.to), sent.items)
        end
    elseif event == "MAIL_FAILED" then
        outgoing = nil
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
    ns.RegisterEvents(frame, "TRADE_SHOW", "TRADE_CLOSED", "TRADE_PLAYER_ITEM_CHANGED", "TRADE_ACCEPT_UPDATE",
        "UI_INFO_MESSAGE", "MAIL_SEND_INFO_UPDATE", "MAIL_SEND_SUCCESS", "MAIL_FAILED")
    frame:SetScript("OnEvent", OnEvent)
    Hook(_G, "SendMail", OnSendMail)
    Hook(C_Mail, "SendMail", OnSendMail)
end
