-- Requests.lua: requests to take items out of the guild bank.
--
-- Requests live in their members' records, so they travel and merge like
-- the rest of the data, and each record is only ever changed by its owner
-- (see Pack.lua for the fields):
--   - the requester's record holds the request (rq); only the requester
--     makes or deletes it;
--   - the record of whoever answers holds the answer (ra): a rejection, or
--     how many of the items a bank character delivered.
-- Every client works out a request's state from both, in the same way. A
-- request is approved once its items are all delivered, by trade or mail,
-- in as many goes as it takes (Deliveries.lua counts them on the bank
-- character's client); from then on it can neither be deleted nor
-- rejected. Approved and rejected requests stay listed for a week.
local _, ns = ...
local Data, Ranks = ns.Data, ns.Ranks
local LIMITS = ns.Pack.LIMITS

local Requests = {}
ns.Requests = Requests

local DAY = 86400
Requests.KEEP_CLOSED = 7 * DAY  -- approved and rejected requests stay listed this long
local KEEP_ANSWERS = 30 * DAY   -- answers to requests we no longer see are dropped after this
local PRUNE_INTERVAL = 3600

-- An answer's kind (answer.s).
local REJECTED, DELIVERING = 1, 2
Requests.REJECTED, Requests.DELIVERING = REJECTED, DELIVERING

-- How the requester wants the items (request.d): in person, at the bank of
-- the city where the bank character is, or by mail, the postage charged
-- cash on delivery (MAIL_FEE copper per stack, the game's postage).
Requests.IN_PERSON, Requests.BY_MAIL = 1, 2
Requests.MAIL_FEE = 30

local CLOSED = { approved = true, rejected = true }

function Requests.IsClosed(state)
    return CLOSED[state] == true
end

function Requests.Key(requester, id)
    return requester .. ":" .. id
end

-- Every answer given to each request: [key] = { { guid, answer }... }.
local function AnswersByKey(guild)
    local byKey = {}
    for guid, record in pairs(guild and guild.members or {}) do
        for key, answer in pairs(record.ra or {}) do
            local list = byKey[key]
            if not list then
                list = {}
                byKey[key] = list
            end
            list[#list + 1] = { guid = guid, answer = answer }
        end
    end
    return byKey
end

-- A request's state, worked out the same way on every client:
--   "approved": all its items were delivered;
--   "rejected": a bank character, an officer or the guild master rejected
--     it (the earliest rejection counts);
--   "partial": some of its items were delivered;
--   "pending".
-- Also returns how many items were delivered, who rejected it, and when it
-- closed (approved or rejected).
function Requests.State(request, answers)
    local delivered, lastDelivery = 0, 0
    local rejecter, rejectedAt
    for _, entry in ipairs(answers or {}) do
        local answer = entry.answer
        if (answer.n or 0) > 0 then
            delivered = delivered + answer.n
            lastDelivery = math.max(lastDelivery, answer.u)
        end
        if answer.s == REJECTED and Ranks.CanReject(entry.guid)
                and (not rejectedAt or answer.u < rejectedAt or (answer.u == rejectedAt and entry.guid < rejecter)) then
            rejecter, rejectedAt = entry.guid, answer.u
        end
    end
    if delivered >= request.q then
        return "approved", delivered, nil, lastDelivery
    elseif rejecter then
        return "rejected", delivered, rejecter, rejectedAt
    elseif delivered > 0 then
        return "partial", delivered
    end
    return "pending", 0
end

-- Every request of the guild's members, newest first, as views:
-- { key, requester, id, request, state, delivered, rejecter, closedAt }.
function Requests.List(guild)
    local answers = AnswersByKey(guild)
    local list = {}
    for guid, record in pairs(guild and guild.members or {}) do
        if record.rq and Data.IsShareable(record) and ns.Roster.IsKnownGUID(guid) then
            for id, request in pairs(record.rq) do
                local key = Requests.Key(guid, id)
                local state, delivered, rejecter, closedAt = Requests.State(request, answers[key])
                list[#list + 1] = { key = key, requester = guid, id = id, request = request, state = state,
                    delivered = delivered, rejecter = rejecter, closedAt = closedAt }
            end
        end
    end
    table.sort(list, function(a, b)
        if a.request.c ~= b.request.c then
            return a.request.c > b.request.c
        end
        return a.key < b.key
    end)
    return list
end

-- One request's view, or nil.
function Requests.Find(guild, requester, id)
    for _, view in ipairs(Requests.List(guild)) do
        if view.requester == requester and view.id == id then
            return view
        end
    end
end

-- The requests still waiting for a bank character: those made to it.
function Requests.WaitingFor(guild, bank)
    local count = 0
    for _, view in ipairs(Requests.List(guild)) do
        if view.request.b == bank and not CLOSED[view.state] then
            count = count + 1
        end
    end
    return count
end

-- What the buttons may do ---------------------------------------------------------

-- Whether we may delete a request: our own, while it is not approved.
function Requests.CanDelete(view)
    return view.requester == ns.playerGUID and view.state ~= "approved"
end

-- Whether we may reject a request: someone else's, still open, and we are
-- a bank character, an officer or the guild master.
function Requests.CanReject(view)
    return view.requester ~= ns.playerGUID and not CLOSED[view.state] and Ranks.CanReject(ns.playerGUID)
end

-- Changes -----------------------------------------------------------------------------

local function Own()
    local record = Data.GetOwnRecord(true)
    if not record then
        return nil
    end
    return record
end

local function Count(map)
    local count = 0
    for _ in pairs(map or {}) do
        count = count + 1
    end
    return count
end

-- Makes a request to a bank character for quantity of an item (its item
-- string, as the bank character holds it), to be delivered in person or by
-- mail (Requests.IN_PERSON, Requests.BY_MAIL). Returns its id, or nil and
-- why: "guild", "bank", "quantity", "delivery" or "full".
function Requests.Create(bank, itemString, quantity, note, delivery)
    local record = Own()
    if not record then
        return nil, "guild"
    end
    local itemID = tonumber(type(itemString) == "string" and itemString:match("^item:(%d+)") or nil)
    if not itemID or not Ranks.IsBank(bank) or bank == ns.playerGUID then
        return nil, "bank"
    end
    quantity = tonumber(quantity)
    if not quantity or quantity < 1 or quantity > LIMITS.quantity or quantity ~= math.floor(quantity) then
        return nil, "quantity"
    end
    if delivery ~= Requests.IN_PERSON and delivery ~= Requests.BY_MAIL then
        return nil, "delivery"
    end
    Requests.Prune()
    if Count(record.rq) >= LIMITS.requests then
        return nil, "full"
    end
    local state = Data.OwnState()
    local id = (state.lastRequest or 0) + 1
    while record.rq and record.rq[id] do
        id = id + 1
    end
    state.lastRequest = id
    record.rq = record.rq or {}
    record.rq[id] = {
        b = bank, i = itemID, s = itemString ~= ("item:" .. itemID) and itemString or nil,
        q = quantity, c = ns.Now(), nt = Data.CleanNote(note), d = delivery,
    }
    Data.TouchOwn(record)
    return id
end

-- Deletes one of our requests, unless it is approved.
function Requests.Delete(id)
    local record = Own()
    local view = record and Requests.Find(Data.CurrentGuild(false), ns.playerGUID, id)
    if not view or not Requests.CanDelete(view) then
        return false
    end
    record.rq[id] = nil
    Data.TouchOwn(record)
    return true
end

local function Answer(record, key)
    record.ra = record.ra or {}
    local answer = record.ra[key]
    if not answer then
        answer = { s = DELIVERING, n = 0 }
        record.ra[key] = answer
    end
    return answer
end

-- Rejects another member's request.
function Requests.Reject(requester, id)
    local record = Own()
    local view = record and Requests.Find(Data.CurrentGuild(false), requester, id)
    if not view or not Requests.CanReject(view) then
        return false
    end
    local answer = Answer(record, view.key)
    answer.s, answer.u = REJECTED, ns.Now()
    Data.TouchOwn(record)
    return true
end

-- As a bank character: count items of a request delivered to its
-- requester. Returns how many are delivered in all and whether that
-- approves it, or nil when the request takes none.
function Requests.Deliver(requester, id, count)
    local record = Own()
    local view = record and Ranks.IsBank(ns.playerGUID) and Requests.Find(Data.CurrentGuild(false), requester, id)
    if not view or view.state == "approved" then
        return nil
    end
    count = math.min(count, view.request.q - view.delivered)
    if count <= 0 then
        return nil
    end
    local answer = Answer(record, view.key)
    answer.n = (answer.n or 0) + count
    answer.u = ns.Now()
    Data.TouchOwn(record)
    local delivered = view.delivered + count
    return delivered, delivered >= view.request.q
end

-- Cleanup -----------------------------------------------------------------------------

-- Drops our requests closed more than a week ago, and our answers to
-- requests that are gone (or too old to matter).
function Requests.Prune()
    local guild = Data.CurrentGuild(false)
    local record = guild and ns.playerGUID and guild.members[ns.playerGUID]
    if not record then
        return
    end
    local now, changed = ns.Now(), false
    if record.rq then
        local answers = AnswersByKey(guild)
        for id, request in pairs(record.rq) do
            local state, _, _, closedAt = Requests.State(request, answers[Requests.Key(ns.playerGUID, id)])
            if CLOSED[state] and closedAt and closedAt + Requests.KEEP_CLOSED < now then
                record.rq[id] = nil
                changed = true
            end
        end
    end
    for key, answer in pairs(record.ra or {}) do
        local requester, id = key:match("^(.+):(%d+)$")
        local theirs = guild.members[requester]
        local gone = theirs and Data.IsShareable(theirs) and theirs.rq and not theirs.rq[tonumber(id)]
        if gone or answer.u + KEEP_ANSWERS < now then
            record.ra[key] = nil
            changed = true
        end
    end
    if changed and Data.IsShareable(record) then
        Data.TouchOwn(record)
    end
end

function Requests.Init()
    ns.On("DataChanged", function()
        ns.Debounce("RequestsPrune", 5, Requests.Prune)
    end)
    C_Timer.NewTicker(PRUNE_INTERVAL, Requests.Prune)
end
