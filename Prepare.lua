-- Prepare.lua: a bank character gets the requests made to it ready, once
-- accepted, with the buttons of their rows in the Requests subtab
-- (RequestList.lua):
--   - Prepare keeps in the bags the stacks the request still lacks, in the
--     fewest stacks: stacks of the item already there and kept for no
--     request, as they are or split, and, with the bank open, stacks
--     brought from it, each into an empty slot; when no stack holds what
--     one is to hold, several are put together into one (onto one of the
--     bags, as it is, or onto one it already keeps that is not full).
--     Without the bank, the bags must hold enough kept for no request;
--     without the empty slots it takes, nothing moves. Once the request keeps stacks and Prepare can
--     add no more (it is ready, or the rest is not to be had now), the
--     button is Release instead: it lets go of them;
--   - Mail, for a request by mail, at a mailbox: a mail on the Send tab
--     with its items in the fewest stacks (partial stacks merged, the rest
--     split off), as many as one mail takes, the requester as the recipient,
--     and cash on delivery of the postage the requester pays: 30 copper per
--     stack. It takes the stacks kept for the request and those kept for
--     none, never those kept for another request. Once sent, its items
--     count towards that request first (Deliveries.MailReadyFor).
-- Each button is enabled only when it can do its part, and its tooltip says
-- what it does or why it cannot (Prepare.Actions). The player sends the
-- mail, or trades the items, by hand.
--
-- Kept stacks (OwnState().prepared = { [request] = { [stack] = count } })
-- are known by the item's GUID, which stays with a stack when it moves. A
-- stack kept for a request shows a padlock in the bags (BagLocks.lua). It
-- stays kept while it is in the bags with the count it was kept with: moved
-- to another slot, it still is; split, added to (by hand, or by the game
-- stacking loot or mail onto it) or out of the bags (traded, mailed, back
-- in the bank), it is let go. So are the stacks of requests no longer
-- accepted (rejected, all delivered, or deleted).
--
-- Items move one at a time: a move is the server's, and the slots look as
-- they were until it answers (their locks may even clear before the items
-- show where they went). So each move says where the items are to end up,
-- and the next step waits until they show there. What the request lacks is
-- counted once, before the first move, and what each step keeps for it is
-- added up: the steps never bring more. Stacks attached to the mail may
-- stay locked in the bags until it is sent: they are left alone, as are
-- other locked stacks. A preparation the server does not answer in time
-- stops.
local _, ns = ...
local L = ns.L

local Prepare = {}
ns.Prepare = Prepare

local STEP = 0.25      -- seconds between steps
local TIMEOUT = 15     -- seconds a preparation waits for the server to carry out a move
local MAX_STEPS = 400

-- The preparation under way: a context (see Context) and how it runs.
local job

-- Tells the request list its buttons may have changed.
local function Changed()
    ns.Debounce("PrepareChanged", 0.2, function()
        ns.Fire("PrepareChanged")
    end)
end

-- Items ---------------------------------------------------------------------------------

-- An item as requests name it: its item string, or "item:<ID>" when that
-- says no more than the ID (see Bank.Meaningful).
local function KeyOf(link, itemID)
    local itemString = ns.Bank.ItemString(ns.Plain(link))
    if not itemString then
        itemID = ns.Number(itemID)
        if not itemID then
            return nil
        end
        itemString = "item:" .. itemID
    end
    return ns.Bank.Meaningful(itemString) or ("item:" .. itemString:match("^item:(%d+)"))
end

local function RequestKey(request)
    return request.s or ("item:" .. request.i)
end

-- A stack of the bags as kept stacks know it: the item's GUID; without it
-- (an older client), its slot.
local function Identity(bag, slot)
    local location = ItemLocation and ns.Try(ItemLocation.CreateFromBagAndSlot, ItemLocation, bag, slot)
    local guid = location and C_Item and ns.Plain(ns.Try(C_Item.GetItemGUID, location))
    if type(guid) == "string" and guid ~= "" then
        return guid
    end
    return "@" .. bag .. ":" .. slot
end

-- The stacks of an item in the containers given: { bag, slot, count,
-- locked, id (with identities) }.
local function Stacks(bags, key, identities)
    local list = {}
    for _, bag in ipairs(bags) do
        local size = ns.Number(ns.Try(C_Container.GetContainerNumSlots, bag)) or 0
        for slot = 1, size do
            local info = ns.Try(C_Container.GetContainerItemInfo, bag, slot)
            if ns.CanRead(info) and KeyOf(info.hyperlink, info.itemID) == key then
                list[#list + 1] = {
                    bag = bag, slot = slot, count = ns.Number(info.stackCount) or 0, locked = ns.Plain(info.isLocked) == true,
                    id = identities and Identity(bag, slot) or nil,
                }
            end
        end
    end
    return list
end

local function Total(stacks)
    local total = 0
    for _, stack in ipairs(stacks) do
        total = total + stack.count
    end
    return total
end

local function Place(stack)
    return stack.bag .. ":" .. stack.slot
end

-- The stacks a step may move: not locked, nor attached to the mail.
local function Usable(ctx, stacks)
    local list = {}
    for _, stack in ipairs(stacks) do
        if not stack.locked and not ctx.used[Place(stack)] then
            list[#list + 1] = stack
        end
    end
    return list
end

-- Smallest first; of the same count, those kept for the request first,
-- then those in the bags, then the bank's.
local function Rank(stack)
    return stack.own and 0 or stack.inBags and 1 or 2
end

local function BySize(stacks)
    table.sort(stacks, function(a, b)
        if a.count ~= b.count then
            return a.count < b.count
        elseif Rank(a) ~= Rank(b) then
            return Rank(a) < Rank(b)
        elseif a.bag ~= b.bag then
            return a.bag < b.bag
        end
        return a.slot < b.slot
    end)
    return stacks
end

local function MaxStack(itemID, seen)
    local size = ns.Number(ns.Try(C_Item.GetItemMaxStackSizeByID, itemID))
    if not size then
        size = ns.Number((select(8, ns.Try(C_Item.GetItemInfo, itemID))))
    end
    return size and size > 0 and size or math.max(seen, 1)
end

-- The bags items may be put in: not the reagent bag, nor a bag only for
-- some kind of items the item is not.
local function TargetBags(itemID)
    local bags = {}
    local family = ns.Number(ns.Try(C_Item.GetItemFamily, itemID)) or 0
    for bag = BACKPACK_CONTAINER or 0, NUM_BAG_SLOTS or 4 do
        local _, bagFamily = ns.Try(C_Container.GetContainerNumFreeSlots, bag)
        bagFamily = ns.Number(bagFamily) or 0
        if bagFamily == 0 or (bit and bit.band(family, bagFamily) ~= 0) then
            bags[#bags + 1] = bag
        end
    end
    return bags
end

-- The empty slots of our bags the item may go in: each request's items go
-- in stacks of their own, never onto another stack. Not those of stacks
-- attached to the mail, if they look empty.
local function EmptySlots(ctx)
    local slots = {}
    for _, bag in ipairs(TargetBags(ctx.itemID)) do
        for slot = 1, ns.Number(ns.Try(C_Container.GetContainerNumSlots, bag)) or 0 do
            if not ns.Try(C_Container.GetContainerItemInfo, bag, slot) and not ctx.used[bag .. ":" .. slot] then
                slots[#slots + 1] = { bag = bag, slot = slot }
            end
        end
    end
    return slots
end

-- How many stacks count of the item takes at least.
local function StacksFor(count, size)
    return math.ceil(math.max(count, 0) / size)
end

-- Up to need of the item, from stacks sorted BySize: the stack, and how
-- many of it (fewer than it holds: split). A stack of just that many; else
-- that many split off the smallest bigger one; else the biggest there is,
-- whole.
local function Pick(stacks, need)
    for _, stack in ipairs(stacks) do
        if stack.count == need then
            return stack, need
        end
    end
    for _, stack in ipairs(stacks) do
        if stack.count > need then
            return stack, need
        end
    end
    local biggest = stacks[#stacks].count
    for _, stack in ipairs(stacks) do
        if stack.count == biggest then
            return stack, biggest
        end
    end
end

-- Prepare's next move, in the fewest stacks: from the stacks it may take,
-- sorted BySize, towards left, the count the request still lacks, with base
-- the stack being made up for it, if one is ({ count, target }). Returns
-- the stack, how many of it, and how:
--   "take": a stack of its own for the request: kept where it is (a whole
--     stack of the bags), or moved or split off into an empty slot. Of the
--     size of a full one, or of what is left; else the biggest there is,
--     if the rest takes no more stacks than it would anyway;
--   "start": no stack will do on its own: one is made up of several,
--     starting with this one, whole (the biggest of the bags, kept where
--     it is; else the biggest, moved into an empty slot), to hold target
--     (the 4th value);
--   "onto": put onto the base, whole or split off.
local function NextMove(stacks, left, size, base)
    if base then
        local stack, count = Pick(stacks, math.min(left, base.target - base.count))
        return stack, count, "onto"
    end
    local want = math.min(left, size)
    local stack, count = Pick(stacks, want)
    if count == want or StacksFor(left - count, size) < StacksFor(left, size) then
        return stack, count, "take"
    end
    local start = stacks[#stacks]
    for _, other in ipairs(stacks) do
        if other.inBags then
            start = other
        end
    end
    return start, start.count, "start", want
end

-- Whether taking count of a stack keeps it as it is (no move).
local function InPlace(stack, count)
    return stack.inBags and count == stack.count
end

-- Whether a move takes an empty slot: a stack of its own, moved or split
-- off, or the start of one moved.
local function TakesSlot(stack, count, how)
    return how == "take" and not InPlace(stack, count) or how == "start" and not stack.inBags
end

-- The stack being made up for the request when Prepare starts: the biggest
-- of its own not full (kept before, as when Prepare ran without the bank),
-- to be filled up with what it lacks, if that takes fewer stacks than what
-- it lacks would on its own; or nil.
local function OwnBase(own, missing, size)
    local base
    for _, stack in ipairs(own) do
        if stack.count < size and (not base or stack.count > base.count) then
            base = stack
        end
    end
    if not base or StacksFor(missing - (size - base.count), size) >= StacksFor(missing, size) then
        return nil
    end
    return { bag = base.bag, slot = base.slot, count = base.count, target = math.min(size, base.count + missing) }
end

-- How many empty slots getting what is missing takes, step by step as the
-- prepare step will (NextMove).
local function SlotsNeeded(stacks, missing, size, base)
    local copies = {}
    for index, stack in ipairs(stacks) do
        copies[index] = { count = stack.count, inBags = stack.inBags, bag = stack.bag, slot = stack.slot }
    end
    base = base and { count = base.count, target = base.target }
    local slots = 0
    while missing > 0 and #copies > 0 do
        BySize(copies)
        local stack, count, how, target = NextMove(copies, missing, size, base)
        if TakesSlot(stack, count, how) then
            slots = slots + 1
        end
        if how == "start" then
            base = { count = count, target = target }
        elseif how == "onto" then
            base.count = base.count + count
            if base.count >= base.target then
                base = nil
            end
        end
        stack.count = stack.count - count
        if stack.count <= 0 then
            for index, other in ipairs(copies) do
                if other == stack then
                    table.remove(copies, index)
                    break
                end
            end
        end
        missing = missing - count
    end
    return slots
end

-- The mail being written: how many of the item are attached, in how many
-- stacks, how many other attachments there are, and free slots.
local function Attachments(key)
    local count, stacks, others, free = 0, 0, 0, 0
    for index = 1, ATTACHMENTS_MAX_SEND or 12 do
        local _, itemID, _, itemCount = GetSendMailItem(index)
        itemID = ns.Number(itemID)
        if not itemID then
            free = free + 1
        elseif KeyOf(GetSendMailItemLink and GetSendMailItemLink(index), itemID) == key then
            count, stacks = count + (ns.Number(itemCount) or 0), stacks + 1
        else
            others = others + 1
        end
    end
    return count, stacks, others, free
end

-- Kept stacks -----------------------------------------------------------------------------

local function Prepared()
    local own = ns.Data.OwnState()
    own.prepared = own.prepared or {}
    return own.prepared
end

-- Keeps a stack of the bags for a request.
local function Keep(requestKey, id, count)
    local prepared = Prepared()
    if type(prepared[requestKey]) ~= "table" then
        prepared[requestKey] = {}
    end
    prepared[requestKey][id] = count
    ns.Fire("KeptChanged")
    Changed()
end

-- Which request keeps each stack: identity -> request.
local function Keepers()
    local keepers = {}
    for requestKey, stacks in pairs(Prepared()) do
        if type(stacks) == "table" then
            for id in pairs(stacks) do
                keepers[id] = requestKey
            end
        end
    end
    return keepers
end

-- The accepted requests made to us, the only ones stacks are kept for:
-- request -> its view.
local function OpenRequests()
    local guild = ns.Data.CurrentGuild(false)
    if not guild or not ns.playerGUID then
        return nil
    end
    local open = {}
    for _, view in ipairs(ns.Requests.List(guild)) do
        if view.request.b == ns.playerGUID and view.state == "accepted" then
            open[view.key] = view
        end
    end
    return open, guild
end

-- Lets go of the stacks no longer kept: those of requests no longer open,
-- and those gone from the bags or of another count than they were kept
-- with (see the top of this file).
function Prepare.Validate()
    if not ns.playerGUID or not ns.db then
        return
    end
    local prepared = Prepared()
    if next(prepared) == nil then
        return
    end
    local open = OpenRequests()
    if not open then
        return
    end
    local held, any = {}, false
    for _, bag in ipairs(ns.Bank.BagIDs()) do
        for slot = 1, ns.Number(ns.Try(C_Container.GetContainerNumSlots, bag)) or 0 do
            local info = ns.Try(C_Container.GetContainerItemInfo, bag, slot)
            if ns.CanRead(info) then
                any = true
                held[Identity(bag, slot)] = { count = ns.Number(info.stackCount), key = KeyOf(info.hyperlink, info.itemID) }
            end
        end
    end
    if not any then
        -- The bags not read yet (at login): nothing to tell.
        return
    end
    local changed, seen = false, {}
    for requestKey, stacks in pairs(prepared) do
        local view = open[requestKey]
        if type(stacks) ~= "table" or not view then
            prepared[requestKey], changed = nil, true
        else
            local key = RequestKey(view.request)
            for id, count in pairs(stacks) do
                local stack = held[id]
                if not stack or stack.count ~= count or stack.key ~= key or seen[id] then
                    stacks[id], changed = nil, true
                else
                    seen[id] = true
                end
            end
            if next(stacks) == nil then
                prepared[requestKey] = nil
            end
        end
    end
    if changed then
        ns.Fire("KeptChanged")
    end
end

-- The request a stack of our bags is kept for (its key), or nil.
function Prepare.KeptAt(bag, slot)
    if not ns.playerGUID or not ns.db then
        return nil
    end
    local prepared = Prepared()
    if next(prepared) == nil then
        return nil
    end
    local info = ns.Try(C_Container.GetContainerItemInfo, bag, slot)
    if not ns.CanRead(info) then
        return nil
    end
    local id, count = Identity(bag, slot), ns.Number(info.stackCount)
    for requestKey, stacks in pairs(prepared) do
        if type(stacks) == "table" and stacks[id] and stacks[id] == count then
            return requestKey
        end
    end
    return nil
end

-- An accepted request made to us, by its key: its view and the guild, or
-- nil.
function Prepare.ViewOf(requestKey)
    local open, guild = OpenRequests()
    return open and open[requestKey], guild
end

-- The stacks of the item in the bags kept for the request.
local function OwnStacks(ctx)
    local kept = Prepared()[ctx.request]
    local list = {}
    if type(kept) == "table" then
        for _, stack in ipairs(Usable(ctx, Stacks(ns.Bank.BagIDs(), ctx.key, true))) do
            if kept[stack.id] == stack.count then
                stack.own = true
                list[#list + 1] = stack
            end
        end
    end
    return list
end

-- The stacks of the item the request may take: in the bags, those kept for
-- no request; with withBank, the bank's too.
local function FreeStacks(ctx, withBank)
    local keepers = Keepers()
    local list = {}
    for _, stack in ipairs(Usable(ctx, Stacks(ns.Bank.BagIDs(), ctx.key, true))) do
        if not keepers[stack.id] then
            stack.inBags = true
            list[#list + 1] = stack
        end
    end
    if withBank then
        for _, stack in ipairs(Usable(ctx, Stacks(ns.Bank.BankIDs(), ctx.key))) do
            list[#list + 1] = stack
        end
    end
    return list
end

-- How many of the item in the bags are kept for other requests.
local function KeptForOthers(ctx)
    local keepers = Keepers()
    local count = 0
    for _, stack in ipairs(Stacks(ns.Bank.BagIDs(), ctx.key, true)) do
        if keepers[stack.id] and keepers[stack.id] ~= ctx.request then
            count = count + stack.count
        end
    end
    return count
end

-- Waiting for the server ---------------------------------------------------------------

-- Where the last move is to leave the item: { bag, slot, count, keep } (0:
-- none left there; keep: the stack there is to be kept for the request),
-- or { mail = count } for the count attached to the mail.
local function Expect(...)
    job.expected = { ... }
end

local function Shows(place)
    if place.mail then
        return (Attachments(job.key)) == place.mail
    end
    local info = ns.Try(C_Container.GetContainerItemInfo, place.bag, place.slot)
    if not info then
        return place.count == 0
    elseif not ns.CanRead(info) then
        return false
    elseif KeyOf(info.hyperlink, info.itemID) ~= job.key then
        return place.count == 0
    end
    return ns.Number(info.stackCount) == place.count and ns.Plain(info.isLocked) ~= true
end

-- Whether the last move shows done (the server carried it out). The stacks
-- it brought for the request are then kept for it.
local function Arrived()
    for _, place in ipairs(job.expected or {}) do
        if not Shows(place) then
            return false
        end
    end
    for _, place in ipairs(job.expected or {}) do
        if place.keep and place.count > 0 then
            Keep(job.request, Identity(place.bag, place.slot), place.count)
        end
    end
    job.expected, job.since = nil, GetTime()
    return true
end

-- Moves ------------------------------------------------------------------------------------

-- A whole stack into an empty slot.
local function MoveTo(stack, empty, keep)
    C_Container.PickupContainerItem(stack.bag, stack.slot)
    C_Container.PickupContainerItem(empty.bag, empty.slot)
    Expect({ bag = empty.bag, slot = empty.slot, count = stack.count, keep = keep },
        { bag = stack.bag, slot = stack.slot, count = 0 })
end

-- One stack onto another, as much as fits.
local function Merge(from, to, keep)
    local moved = math.min(from.count, job.size - to.count)
    C_Container.PickupContainerItem(from.bag, from.slot)
    C_Container.PickupContainerItem(to.bag, to.slot)
    Expect({ bag = to.bag, slot = to.slot, count = to.count + moved, keep = keep },
        { bag = from.bag, slot = from.slot, count = from.count - moved, keep = keep and from.own })
end

-- Part of a stack, into an empty slot or onto a stack of the item (to,
-- with its count): split off now, put down next step.
local function Split(stack, count, to, keep)
    C_Container.SplitContainerItem(stack.bag, stack.slot, count)
    job.cursor = { from = stack, to = to, count = count, keep = keep }
end

local function PutDown()
    local split = job.cursor
    job.cursor = nil
    C_Container.PickupContainerItem(split.to.bag, split.to.slot)
    Expect({ bag = split.to.bag, slot = split.to.slot, count = (split.to.count or 0) + split.count, keep = split.keep },
        { bag = split.from.bag, slot = split.from.slot, count = split.from.count - split.count, keep = split.from.own })
end

local function Attach(stack, attached)
    C_Container.PickupContainerItem(stack.bag, stack.slot)
    ClickSendMailItemButton()
    job.used[Place(stack)] = true
    Expect({ mail = attached + stack.count })
end

-- Steps: each returns true when it moved something or waits, nil when its
-- part is done.

-- Prepare: what the request lacks, kept for it in the bags, in the fewest
-- stacks (NextMove). Before the first move, the bags must have room for
-- all of it: else nothing moves.
local function PrepareStep()
    if not Arrived() then
        return true
    elseif job.cursor then
        PutDown()
        return true
    end
    if not job.missing then
        Prepare.Validate()
        local own = OwnStacks(job)
        job.mine = Total(own)
        job.missing, job.brought = job.needed - job.mine, 0
        if job.missing > 0 then
            job.base = OwnBase(own, job.missing, job.size)
            job.slotsNeeded = SlotsNeeded(FreeStacks(job, job.withBank), job.missing, job.size, job.base)
            if job.slotsNeeded > #EmptySlots(job) then
                job.full = true
                return nil
            end
        end
    end
    local left = job.missing - job.brought
    if left <= 0 then
        return nil
    end
    local base = job.base
    if base and not Shows({ bag = base.bag, slot = base.slot, count = base.count }) then
        -- The stack being made up is no longer as it was left (moved by
        -- hand): the rest goes in stacks of its own.
        job.base, base = nil, nil
    end
    local stacks = BySize(FreeStacks(job, job.withBank))
    if #stacks == 0 then
        job.short = true
        return nil
    end
    local stack, count, how, target = NextMove(stacks, left, job.size, base)
    if how == "onto" then
        if count < stack.count then
            Split(stack, count, { bag = base.bag, slot = base.slot, count = base.count }, true)
        else
            Merge(stack, base, true)
        end
        base.count = base.count + count
        if base.count >= base.target then
            job.base = nil
        end
    elseif InPlace(stack, count) then
        Keep(job.request, stack.id, count)
        if how == "start" then
            job.base = { bag = stack.bag, slot = stack.slot, count = count, target = target }
        end
    else
        local empty = EmptySlots(job)[1]
        if not empty then
            job.full = true
            return nil
        elseif count < stack.count then
            Split(stack, count, empty, true)
        else
            MoveTo(stack, empty, true)
        end
        if how == "start" then
            job.base = { bag = empty.bag, slot = empty.slot, count = count, target = target }
        end
    end
    job.brought = job.brought + count
    return true
end

-- Mail: what is still to deliver, as many as fit, in the fewest stacks,
-- from those kept for the request or for none. Only whole stacks go into a
-- mail: a part is split off into an empty slot first.
local function MailStep()
    if not Arrived() then
        return true
    elseif job.cursor then
        PutDown()
        return true
    end
    local size = job.size
    local stacks = FreeStacks(job, false)
    for _, stack in ipairs(OwnStacks(job)) do
        stacks[#stacks + 1] = stack
    end
    BySize(stacks)
    local attached, _, _, free = Attachments(job.key)
    local left = job.target - attached
    local counts = {}
    for _, stack in ipairs(stacks) do
        counts[#counts + 1] = stack.count .. (stack.own and "*" or "")
    end
    ns.Debug("prepare mail: %d attached of %d, %d free, stacks %s", attached, job.target, free, table.concat(counts, " "))
    if left <= 0 or free == 0 or #stacks == 0 then
        return nil
    end
    local want = math.min(left, size)
    for _, stack in ipairs(stacks) do
        if stack.count == want then
            Attach(stack, attached)
            return true
        end
    end
    if want < size then
        for _, stack in ipairs(stacks) do
            if stack.count > want then
                local empty = EmptySlots(job)[1]
                if not empty then
                    job.full = true
                    return nil
                end
                Split(stack, want, empty, stack.own)
                return true
            end
        end
    end
    -- No stack of the size wanted, nor a bigger one to split it off: two
    -- partial stacks become one, or the biggest left goes as it is.
    local partial = {}
    for _, stack in ipairs(stacks) do
        if stack.count < size then
            partial[#partial + 1] = stack
        end
    end
    if #partial >= 2 then
        local from, to = partial[1], partial[#partial]
        Merge(from, to, from.own or to.own)
        return true
    end
    local biggest = stacks[#stacks]
    for _, stack in ipairs(stacks) do
        if stack.count == biggest.count then
            Attach(stack, attached)
            return true
        end
    end
end

-- Running --------------------------------------------------------------------------------

local Advance

local function Stop(message, ...)
    if job and job.cursor then
        ClearCursor()
    end
    job = nil
    if message then
        ns.Print(message, ...)
    end
    Changed()
end

local function ItemText()
    return ns.BankView.ItemName(job.key)
end

local function Continue()
    job.steps = job.steps + 1
    C_Timer.After(STEP, Advance)
end

local function NoRoom()
    ns.Print(L["not enough room in your bags: %d free |4slot:slots; needed. Free some and try again."],
        job.slotsNeeded or 1)
end

-- The request's items are kept for it in the bags (or as many as there
-- are). With no room in the bags for them, nothing moved.
local function PrepareDone()
    if job.full then
        NoRoom()
    elseif job.short then
        ns.Print(L["your bank and bags hold only %d of %d."], math.min(job.needed, job.mine + job.brought), job.needed)
    else
        ns.Print(L["%s x%d ready in your bags."], ItemText(), job.needed)
    end
end

local function StartMail()
    local count, _, others = Attachments(job.key)
    ns.Debug("prepare mail: %d of the item and %d other items already attached", count, others)
    if count > 0 or others > 0 then
        Stop(L["the mail already has items attached: send it or take them out first."])
        return false
    end
    Prepare.Validate()
    MailFrameTab_OnClick(nil, 2)
    job.target = math.min(job.needed, (ATTACHMENTS_MAX_SEND or 12) * job.size)
    job.kept = KeptForOthers(job)
    return true
end

local SUBJECT_LETTERS = 64  -- the mail subject's length, when its box does not say

-- How many characters (UTF-8) a text has.
local function Letters(text)
    return (select(2, text:gsub("[^\128-\191]", "")))
end

-- The start of a text that fits in letters characters and bytes.
local function Cut(text, letters, bytes)
    local kept, count, size = {}, 0, 0
    for char in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        if count + 1 > letters or size + #char > bytes then
            break
        end
        kept[#kept + 1] = char
        count, size = count + 1, size + #char
    end
    return table.concat(kept)
end

-- The mail's subject: the item and how many go in it. Longer than the
-- subject box takes, the item's name is cut to what fits, so the count
-- stays.
local function Subject(count)
    local box = SendMailSubjectEditBox
    local letters = ns.Number(box.GetMaxLetters and ns.Try(box.GetMaxLetters, box))
    letters = letters and letters > 0 and letters or SUBJECT_LETTERS
    local bytes = ns.Number(box.GetMaxBytes and ns.Try(box.GetMaxBytes, box))
    -- The box's bytes count the text's end too.
    bytes = bytes and bytes > 1 and bytes - 1 or math.huge
    local format = L["Request: %s x%d"]
    local subject = format:format(ItemText(), count)
    if Letters(subject) > letters or #subject > bytes then
        local rest = format:format("", count)
        subject = format:format(Cut(ItemText(), letters - Letters(rest), bytes - #rest), count)
    end
    return Cut(subject, letters, bytes)
end

-- The mail with what is attached, its recipient, subject and cash on
-- delivery; its body is left alone. Without an empty slot to split a stack
-- into, it lacks that part; without the stacks kept for other requests, it
-- may lack some too: it says so.
local function FinishMail()
    local count, stacks = Attachments(job.key)
    ns.Debug("prepare mail: done, %d in %d stacks (room %s)", count, stacks, tostring(not job.full))
    local function Kept()
        if job.kept > 0 then
            ns.Print(L["%s x%d in your bags are kept for other requests you got ready."], ItemText(), job.kept)
        end
    end
    if job.full then
        NoRoom()
    end
    if stacks == 0 then
        if not job.full then
            ns.Print(L["no %s in your bags to mail."], ItemText())
        end
        Kept()
        Stop()
        return
    end
    SendMailNameEditBox:SetText(job.name)
    if SendMailSubjectEditBox then
        SendMailSubjectEditBox:SetText(Subject(count))
    end
    local cod = ns.Requests.MAIL_FEE * stacks
    SendMailRadioButton_OnClick(2)
    MoneyInputFrame_SetCopper(SendMailMoney, cod)
    -- Sent, its items count towards this request first.
    ns.Deliveries.MailReadyFor(job.requester, job.request)
    ns.Print(L["mail ready for %s: %s x%d in %d |4stack:stacks;, %s cash on delivery. Check it and send it."], job.name, ItemText(),
        count, stacks, ns.BankView.Coin(cod, "Copper"))
    if count < job.target and not job.full then
        ns.Print(L["only %d of %d in your bags: the mail takes those."], count, job.needed)
        Kept()
    elseif job.needed > count then
        ns.Print(L["%d more do not fit in one mail: press Mail again once this one is sent."], job.needed - count)
    end
    Stop()
end

Advance = function()
    if not job then
        return
    end
    -- The server too slow, or the bank (or mailbox) closed before the end.
    local closed = (job.phase == "prepare" and job.withBank and not ns.Bank.IsBankOpen())
        or (job.phase == "mail" and not ns.MailToBank.MailboxOpen())
    if GetTime() - job.since > TIMEOUT or job.steps > MAX_STEPS or closed then
        ns.Debug("prepare: stopped (%d steps, expecting %d places)", job.steps, #(job.expected or {}))
        Stop(L["the items did not move in time: try again."])
        return
    end
    if job.phase == "prepare" then
        if PrepareStep() then
            Continue()
            return
        end
        PrepareDone()
        Stop()
        return
    end
    if not job.target and not StartMail() then
        return
    end
    if MailStep() then
        Continue()
        return
    end
    FinishMail()
end

-- Buttons ------------------------------------------------------------------------------------

-- Whether a request is one of ours to get ready: a bank character's
-- accepted request made to it, with something still to deliver.
local function Ours(view)
    return view ~= nil and ns.playerGUID ~= nil and view.request.b == ns.playerGUID and ns.Ranks.IsBank(ns.playerGUID)
        and view.state == "accepted" and view.request.q - view.delivered > 0
end

-- What getting a request ready works with: the request, its item and how
-- many it still lacks.
local function Context(view)
    local itemID = view.request.i
    local key = RequestKey(view.request)
    local seen = 0
    for _, stack in ipairs(Stacks(ns.Bank.BagIDs(), key)) do
        seen = math.max(seen, stack.count)
    end
    return {
        request = view.key, key = key, itemID = itemID, needed = view.request.q - view.delivered,
        size = MaxStack(itemID, seen), used = {},
    }
end

-- Prepare; or, once the request keeps stacks and Prepare can add no more
-- to them (it is ready, or the rest is not to be had now), Release.
local function PrepareAction(ctx)
    local action = { action = "prepare", text = L["Prepare"] }
    local withBank = ns.Bank.IsBankOpen()
    local own = OwnStacks(ctx)
    local kept = Total(own)
    local missing = ctx.needed - kept
    local free = FreeStacks(ctx, withBank)
    local held = Total(free)
    if job then
        action.tip = L["Another request is being got ready: wait a moment."]
        return action
    elseif missing <= 0 then
        -- Ready: Release, below.
    elseif held == 0 then
        action.tip = withBank and L["Your bank and bags hold none of it kept for no request."]
            or L["Your bags hold none of it kept for no request: open your bank to bring it."]
    elseif not withBank and held < missing then
        action.tip = L["Your bags hold %d of the %d it still lacks, kept for no request: open your bank to bring the rest."]:format(held, missing)
    else
        local slots = SlotsNeeded(free, missing, ctx.size, OwnBase(own, missing, ctx.size))
        if slots > #EmptySlots(ctx) then
            action.tip = L["Not enough room in your bags: %d free |4slot:slots; needed."]:format(slots)
        else
            action.enabled = true
            action.tip = (withBank and L["Keeps in your bags the %d it still lacks, from stacks kept for no request and from your bank."]
                or L["Keeps in your bags the %d it still lacks, from stacks kept for no request."]):format(missing)
            if held < missing then
                action.tip = action.tip .. "\n" .. L["Your bank and bags hold only %d of them."]:format(held)
            end
        end
    end
    if action.enabled or kept == 0 then
        return action
    end
    local release = {
        action = "release", text = L["Release"], enabled = true,
        tip = L["Lets go of the %d kept for it in your bags, for other requests to take."]:format(kept),
    }
    if action.tip then
        -- Not all of it: why Prepare cannot get the rest.
        release.tip = release.tip .. "\n" .. action.tip
    end
    return release
end

-- Lets go of the stacks kept for a request.
local function Release(view)
    Prepare.Validate()
    local prepared = Prepared()
    local kept = 0
    for _, count in pairs(type(prepared[view.key]) == "table" and prepared[view.key] or {}) do
        kept = kept + count
    end
    prepared[view.key] = nil
    ns.Fire("KeptChanged")
    if kept > 0 then
        ns.Print(L["%s x%d no longer kept in your bags."], ns.BankView.ItemName(RequestKey(view.request)), kept)
    end
end

-- The Mail button is off for now: on the server, sending the mails it got
-- ready failed ("Internal mail database error"), and for a while the bank
-- character's mail failed by hand too. Until that is understood, bank
-- characters send the mail by hand. The tests turn it on, to keep the rest
-- of it working.
Prepare.mailPaused = true

local function MailAction(view, ctx)
    local action = { action = "mail", text = L["Mail"] }
    if Prepare.mailPaused then
        action.tip = L["Temporarily unavailable, under review. Send the mail by hand."]
    elseif job then
        action.tip = L["Another request is being got ready: wait a moment."]
    elseif not ns.MailToBank.MailboxOpen() then
        action.tip = L["Open a mailbox to get its mail ready."]
    else
        local count, _, others = Attachments(ctx.key)
        local held = Total(OwnStacks(ctx)) + Total(FreeStacks(ctx, false))
        if count > 0 or others > 0 then
            action.tip = L["The mail already has items attached: send it or take them out first."]
        elseif held == 0 then
            action.tip = L["Your bags hold none of it for this request: prepare it first."]
        else
            local guild = ns.Data.CurrentGuild(false)
            action.enabled = true
            action.tip = L["Gets the mail to %s ready: its items, and %s cash on delivery per stack."]:format(
                ns.Data.NameOf(view.requester, guild and guild.members[view.requester]), ns.BankView.Coin(ns.Requests.MAIL_FEE, "Copper"))
            local target = math.min(ctx.needed, (ATTACHMENTS_MAX_SEND or 12) * ctx.size)
            if held < target then
                action.tip = action.tip .. "\n" .. L["Your bags hold %d of the %d it lacks: the mail takes those."]:format(held, ctx.needed)
            end
        end
    end
    return action
end

-- The buttons of a request for us: { action, text, enabled, tip } for
-- Prepare (or Release), and Mail for a request by mail; nil when it is not
-- ours to get ready.
function Prepare.Actions(view)
    if not Ours(view) then
        return nil
    end
    local ctx = Context(view)
    local actions = { PrepareAction(ctx) }
    if view.request.d == ns.Requests.BY_MAIL then
        actions[2] = MailAction(view, ctx)
    end
    return actions
end

function Prepare.Busy()
    return job ~= nil
end

-- Runs a button's action ("prepare", "release" or "mail") on a request.
-- Returns true if it started (or, Release, was done).
function Prepare.Run(view, action)
    if not Ours(view) or (action == "mail" and (Prepare.mailPaused or view.request.d ~= ns.Requests.BY_MAIL
            or not ns.MailToBank.MailboxOpen())) then
        return false
    elseif job then
        ns.Print(L["still getting the last request ready."])
        return false
    elseif action == "release" then
        Release(view)
        return true
    elseif CursorHasItem() then
        ns.Print(L["put down what you hold on the cursor first."])
        return false
    end
    local guild = ns.Data.CurrentGuild(false)
    job = Context(view)
    job.requester = view.requester
    job.name = ns.Data.NameOf(view.requester, guild and guild.members[view.requester])
    job.phase = action == "mail" and "mail" or "prepare"
    job.withBank = job.phase == "prepare" and ns.Bank.IsBankOpen()
    job.since, job.steps = GetTime(), 0
    ns.Debug("prepare %s: %s x%d (stacks of %d), %s%s", view.key, job.key, job.needed, job.size, job.phase,
        job.withBank and " with the bank" or "")
    Changed()
    Advance()
    return true
end

-- Kept stacks are checked again whenever the bags change, and when requests
-- may have closed (a record changed). The buttons change with the bags,
-- the bank, the mailbox and the mail being written.
function Prepare.Init()
    local events = CreateFrame("Frame")
    ns.RegisterEvents(events, "BAG_UPDATE_DELAYED", "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "MAIL_SHOW", "MAIL_CLOSED",
        "MAIL_SEND_INFO_UPDATE", "MAIL_SEND_SUCCESS", "PLAYER_INTERACTION_MANAGER_FRAME_SHOW",
        "PLAYER_INTERACTION_MANAGER_FRAME_HIDE")
    events:SetScript("OnEvent", function(_, event)
        if event == "BAG_UPDATE_DELAYED" then
            Prepare.Validate()
        end
        Changed()
    end)
    ns.On("RecordChanged", function()
        ns.Debounce("PrepareValidate", 2, Prepare.Validate)
    end)
    ns.On("KeptChanged", Changed)
end
