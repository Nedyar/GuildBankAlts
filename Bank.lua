-- Bank.lua: what a guild bank character holds, read on its own client and
-- shared in its record (bk, see Pack.lua): its money, and its bags and bank
-- slot by slot, with the bag in each bag slot. Also the guild bank's money,
-- which any member shares when they see it (gb).
--
-- Only characters with the bank rank (Ranks.lua) share what they hold; any
-- other character drops it from its record. On WoW Forever, as Blizzard's
-- Camelot bags and bank frame show them:
--   - the bags are the backpack (container 0), the four bag slots (1 to 4)
--     and the reagent bag slot (5);
--   - the bank is its first tab (container 6, the bank's own slots) and its
--     bank bag slots: slot N (2 and up, to C_Bank.FetchMaxNumBankTabs)
--     holds a bag that makes container 5 + N, once the slot is bought
--     (C_Bank.FetchPurchasedBankTabData); the bag itself sits in container
--     Enum.BagIndex.Characterbanktab, slot N.
-- The bank can only be read while it is open, so the last read is kept
-- until the bank is opened again. The guild bank's money is only known
-- while its window is open.
local _, ns = ...
local Data = ns.Data
local LIMITS = ns.Pack.LIMITS

local Bank = {}
ns.Bank = Bank

local SCAN_DELAY = 2
local RESTAMP = 3600   -- an unchanged read is stamped again after this long

local bankOpen, guildBankOpen = false, false
Bank.ready = false  -- our record is up to date (see Bank.Update)

-- Reading ------------------------------------------------------------------------------

-- "item:19019:1900:0:0:0:0:0:1234567:60:0:..." -> the same without the
-- fields that change on their own (unique ID, the player's level and spec),
-- which would make an unchanged item look new. Fields are numbers, except
-- the crafter's GUID that crafted items carry ("Player-4613-010B766A");
-- a field with anything else is left blank. nil for anything that is not
-- an item.
function Bank.ItemString(link)
    if type(link) ~= "string" then
        return nil
    end
    local text = link:match("|H(item:[^|]+)|h") or link:match("^(item:[^|]+)$")
    if not text then
        return nil
    end
    local fields = {}
    for field in (text .. ":"):gmatch("([^:]*):") do
        fields[#fields + 1] = field
    end
    if not (fields[2] and fields[2]:find("^%d+$")) then
        return nil
    end
    for i = 3, #fields do
        -- 9, 10 and 11 are the unique ID, link level and spec.
        if (i >= 9 and i <= 11) or not fields[i]:find("^[%w%-]*$") then
            fields[i] = ""
        end
    end
    local itemString = table.concat(fields, ":")
    if #itemString > LIMITS.item then
        return "item:" .. fields[2]
    end
    return itemString
end

-- An item string worth keeping: one that says more than the item ID (an
-- enchant, gems, a random suffix, bonus IDs, its crafter). nil otherwise.
function Bank.Meaningful(itemString)
    if type(itemString) ~= "string" then
        return nil
    end
    local fields = {}
    for field in (itemString .. ":"):gmatch("([^:]*):") do
        fields[#fields + 1] = field
    end
    local function Set(value)
        return value ~= nil and value ~= "" and value ~= "0"
    end
    for i = 3, 8 do  -- enchant, four gems, suffix
        if Set(fields[i]) then
            return itemString
        end
    end
    if Set(fields[14]) then  -- how many bonus IDs
        return itemString
    end
    for i = 9, #fields do
        if fields[i]:find("%a") then  -- a crafter's GUID
            return itemString
        end
    end
    return nil
end

-- An item as shared: { i, n, s }, or nil for an empty slot.
local function ReadSlot(bag, slot)
    local info = ns.Try(C_Container.GetContainerItemInfo, bag, slot)
    local itemID = ns.CanRead(info) and ns.Number(info.itemID)
    local count = itemID and ns.Number(info.stackCount)
    if not itemID or not count or count <= 0 then
        return nil
    end
    return { i = itemID, n = count, s = Bank.Meaningful(Bank.ItemString(ns.Plain(info.hyperlink))) }
end

-- A container, slot by slot: { id, z, s }.
local function ReadContainer(bag)
    local size = ns.Number(ns.Try(C_Container.GetContainerNumSlots, bag)) or 0
    local container = { id = bag, z = math.min(size, LIMITS.slotsPerContainer), s = {} }
    for slot = 1, container.z do
        container.s[slot] = ReadSlot(bag, slot)
    end
    return container
end

-- The item string of the bag in a bag slot of ours (bag 1 to 5), or nil.
local function EquippedBag(bag)
    local inventorySlot = ns.Number(ns.Try(C_Container.ContainerIDToInventoryID, bag))
    local link = inventorySlot and ns.Plain(ns.Try(GetInventoryItemLink, "player", inventorySlot))
    return Bank.ItemString(link)
end

local function ReadBags()
    local containers, slots = {}, 0
    local last = (NUM_BAG_SLOTS or 4) + (NUM_REAGENTBAG_SLOTS or 0)
    for bag = BACKPACK_CONTAINER or 0, last do
        local container = ReadContainer(bag)
        if bag > 0 then
            container.bi = EquippedBag(bag)
        end
        containers[#containers + 1] = container
        slots = slots + container.z
    end
    return containers, slots
end

-- The bank: its own slots, then each bank bag slot, bought or not.
local function ReadBank()
    local bankType = Enum.BankType and Enum.BankType.Character or 0
    local bought = {}
    local tabs = C_Bank and ns.Try(C_Bank.FetchPurchasedBankTabData, bankType)
    if ns.CanRead(tabs) then
        for index, tab in ipairs(tabs) do
            bought[index] = ns.CanRead(tab) and ns.Number(tab.ID) or nil
        end
    end
    local first = (ITEM_INVENTORY_BANK_BAG_OFFSET or 5) + 1
    local maxTabs = C_Bank and ns.Number(ns.Try(C_Bank.FetchMaxNumBankTabs, bankType)) or NUM_CHARACTER_BANK_SLOTS or 9
    local bagHolder = Enum.BagIndex and Enum.BagIndex.Characterbanktab or -2
    local containers, slots = {}, 0
    for index = 1, math.min(maxTabs, LIMITS.containers) do
        local bag = bought[index] or (first + index - 1)
        local container
        if index == 1 or bought[index] then
            container = ReadContainer(bag)
            slots = slots + container.z
        else
            container = { id = bag, z = 0, s = {}, lk = true }
        end
        if index > 1 and not container.lk then
            local holder = ns.Try(C_Container.GetContainerItemInfo, bagHolder, index)
            container.bi = ns.CanRead(holder) and Bank.ItemString(ns.Plain(holder.hyperlink)) or nil
        end
        containers[#containers + 1] = container
    end
    return containers, slots
end

-- Our record ---------------------------------------------------------------------------

-- Brings our record up to date: stamped once the guild is known, so the
-- guild sees we run the addon (and which version) before we ask for
-- anything; then its bank data, dropped unless we are a bank character,
-- else our money and bags, and our bank while it is open.
function Bank.Update()
    local record = Data.GetOwnRecord(true)
    if not record or not ns.Roster.ready then
        return
    end
    if not Data.IsShareable(record) or record.av ~= ns.VERSION_NUM then
        Data.TouchOwn(record)
    end
    Bank.ready = true
    if not ns.Ranks.IsBank(ns.playerGUID) then
        if record.bk then
            record.bk = nil
            Data.TouchOwn(record)
            ns.Debug("not a bank character: bank data dropped")
        end
        return
    end
    local now = ns.Now()
    local old = record.bk or {}
    local bags = ReadBags()
    local bank = { m = ns.Number(GetMoney()) or old.m or 0, bt = old.bt, b = bags, kt = old.kt, k = old.k }
    if bankOpen then
        local containers, slots = ReadBank()
        -- A bank with no slots at all is not loaded yet: the last read stays.
        if slots > 0 then
            bank.k = containers
        end
    end
    local changed = old.m ~= bank.m or not ns.Same(old.b, bank.b)
    local bankChanged = bank.k ~= old.k and not ns.Same(old.k, bank.k)
    if changed or not bank.bt or now - bank.bt > RESTAMP then
        bank.bt = now
        changed = true
    end
    if bank.k and (bankChanged or not bank.kt or (bankOpen and now - bank.kt > RESTAMP)) then
        bank.kt = now
        changed = true
    end
    if changed or bankChanged then
        record.bk = bank
        Data.TouchOwn(record)
        ns.Debug("bank data updated")
    end
end

-- The guild bank's money, while its window is open (any member).
function Bank.UpdateGuildMoney()
    local record = Data.GetOwnRecord(true)
    if not record or not guildBankOpen or not Data.IsShareable(record) then
        return
    end
    local money = ns.Number(ns.Try(GetGuildBankMoney))
    if not money or money < 0 then
        return
    end
    local now = ns.Now()
    local old = record.gb
    if not old or old.m ~= money or now - old.t > RESTAMP then
        record.gb = { m = math.floor(money), t = now }
        Data.TouchOwn(record)
        ns.Debug("guild bank money: %d", money)
    end
end

-- The newest guild bank money any member saw: copper and when, or nil.
function Bank.GuildMoney(guild)
    local newest
    for guid, record in pairs(guild and guild.members or {}) do
        if record.gb and Data.IsShareable(record) and ns.Roster.IsKnownGUID(guid) and (not newest or record.gb.t > newest.t) then
            newest = record.gb
        end
    end
    if newest then
        return newest.m, newest.t
    end
end

local function Schedule()
    ns.Debounce("BankUpdate", SCAN_DELAY, Bank.Update)
end

-- The windows the game opens through its player interactions (on WoW
-- Forever, as on Retail, the guild bank and the bank open this way; the
-- older BANKFRAME_* and GUILDBANKFRAME_* events are listened to as well).
local INTERACTION = Enum.PlayerInteractionType or {}
local GUILD_BANKER = INTERACTION.GuildBanker or 10
local BANKERS = { [INTERACTION.Banker or 8] = true, [INTERACTION.CharacterBanker or 67] = true }
-- The guild bank's money may come from the server a moment after its
-- window opens: it is read again after these delays.
local GUILD_MONEY_READS = { 1.5, 5 }

local function OpenBank()
    bankOpen = true
    Schedule()
end

local function CloseBank()
    if bankOpen then
        -- What changed in the bank before it closed is read first.
        Bank.Update()
        bankOpen = false
    end
end

local function OpenGuildBank()
    guildBankOpen = true
    for _, delay in ipairs(GUILD_MONEY_READS) do
        C_Timer.After(delay, Bank.UpdateGuildMoney)
    end
end

local function CloseGuildBank()
    if guildBankOpen then
        Bank.UpdateGuildMoney()
        guildBankOpen = false
    end
end

function Bank.Init()
    local events = CreateFrame("Frame")
    ns.RegisterEvents(events, "BAG_UPDATE_DELAYED", "PLAYER_MONEY", "BANKFRAME_OPENED", "BANKFRAME_CLOSED",
        "PLAYERBANKSLOTS_CHANGED", "BAG_CONTAINER_UPDATE", "BANK_TABS_CHANGED",
        "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "PLAYER_INTERACTION_MANAGER_FRAME_HIDE",
        "GUILDBANKFRAME_OPENED", "GUILDBANKFRAME_CLOSED", "GUILDBANK_UPDATE_MONEY")
    events:SetScript("OnEvent", function(_, event, kind)
        kind = ns.Plain(kind)
        if event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" then
            if kind == GUILD_BANKER then
                OpenGuildBank()
            elseif BANKERS[kind] then
                OpenBank()
            end
        elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then
            if kind == GUILD_BANKER then
                CloseGuildBank()
            elseif BANKERS[kind] then
                CloseBank()
            end
        elseif event == "BANKFRAME_OPENED" then
            OpenBank()
        elseif event == "BANKFRAME_CLOSED" then
            CloseBank()
        elseif event == "GUILDBANKFRAME_OPENED" then
            OpenGuildBank()
        elseif event == "GUILDBANKFRAME_CLOSED" then
            CloseGuildBank()
        elseif event == "GUILDBANK_UPDATE_MONEY" then
            -- The money changed or came in: the window is open.
            guildBankOpen = true
            ns.Debounce("GuildMoney", 0.5, Bank.UpdateGuildMoney)
        else
            Schedule()
        end
    end)
    ns.On("RosterUpdated", Schedule)
    ns.On("GuildChanged", Schedule)
    Schedule()
end
