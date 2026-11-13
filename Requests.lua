-- Requests.lua: requests to take items out of the guild bank.
--
-- Requests live in their members' records, so they travel and merge like
-- the rest of the data, and each record is only ever changed by its owner
-- (see Pack.lua for the fields):
--   - the requester's record holds the request (rq); only the requester
--     makes or deletes it;
--   - the record of whoever answers holds the answer (ra): a rejection, or
--     how many of the items a bank character delivered; and, apart (ac),
--     its acceptance.
-- Every client works out a request's state from them, in the same way. A
-- member whose rank may (Ranks.lua: by default bank characters, officers
-- and the guild master) accepts a request, if the bank character it was
-- made to has enough of the item to spare (what it holds, less what the
-- other accepted requests still await of it), or rejects it, accepted or
-- not; an answer counts only if its author's rank may give it, and may see
-- the bank character's items. Only a
-- member whose rank may make requests makes one. A request is approved once its items are
-- all delivered, by trade or mail, in as many goes as it takes
-- (Deliveries.lua counts them on the bank character's client); its maker's
-- client then drops it, once it has told so. Its maker may delete it
-- pending, partly delivered or rejected, not accepted; a rejected one its
-- maker's client drops a week after. A closed request (approved or
-- rejected) a week old is listed no more, though its maker, gone from the
-- game, has not dropped it from their record; the answers to it are kept
-- while it is there, so that it stays closed.
local _, ns = ...
local Data, Ranks = ns.Data, ns.Ranks
local LIMITS = ns.Pack.LIMITS

local Requests = {}
ns.Requests = Requests

local DAY = 86400
Requests.KEEP_CLOSED = 7 * DAY  -- closed (approved or rejected) requests are listed this long
local KEEP_ANSWERS = 30 * DAY   -- answers to requests whose maker we do not know are dropped after this
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

-- Every answer given to each request: [key] = { { guid, answer }... }; an
-- acceptance is { guid, at }.
local function AnswersByKey(guild)
    local byKey = {}
    local function Add(key, entry)
        local list = byKey[key]
        if not list then
            list = {}
            byKey[key] = list
        end
        list[#list + 1] = entry
    end
    for guid, record in pairs(guild and guild.members or {}) do
        for key, answer in pairs(record.ra or {}) do
            Add(key, { guid = guid, answer = answer })
        end
        for key, at in pairs(record.ac or {}) do
            Add(key, { guid = guid, at = at })
        end
    end
    return byKey
end

-- The earliest of several (guid, when) by those who may give that answer
-- (flag: Ranks.ACCEPT or REJECT) to the requests made to bank
-- (Ranks.MayAnswer); the lowest GUID among those of the same time.
local function Earliest(flag, bank, guid, at, bestGuid, bestAt)
    if Ranks.MayAnswer(guid, bank, flag) and (not bestAt or at < bestAt or (at == bestAt and guid < bestGuid)) then
        return guid, at
    end
    return bestGuid, bestAt
end

-- A request's state, worked out the same way on every client:
--   "approved": all its items were delivered;
--   "rejected": a bank character, an officer or the guild master rejected
--     it (the earliest rejection counts), accepted or not;
--   "accepted": one of them accepted it (the earliest acceptance counts),
--     and its items may be partly delivered;
--   "partial": some of its items were delivered;
--   "pending".
-- Also returns how many items were delivered, who rejected it, when it
-- closed (approved or rejected), who accepted it and when.
function Requests.State(request, answers)
    local delivered, lastDelivery = 0, 0
    local rejecter, rejectedAt, accepter, acceptedAt
    for _, entry in ipairs(answers or {}) do
        local answer = entry.answer
        if not answer then
            accepter, acceptedAt = Earliest(Ranks.ACCEPT, request.b, entry.guid, entry.at, accepter, acceptedAt)
        else
            if (answer.n or 0) > 0 then
                delivered = delivered + answer.n
                lastDelivery = math.max(lastDelivery, answer.u)
            end
            if answer.s == REJECTED then
                rejecter, rejectedAt = Earliest(Ranks.REJECT, request.b, entry.guid, answer.u, rejecter, rejectedAt)
            end
        end
    end
    if delivered >= request.q then
        return "approved", delivered, nil, lastDelivery, accepter, acceptedAt
    elseif rejecter then
        return "rejected", delivered, rejecter, rejectedAt, accepter, acceptedAt
    elseif accepter then
        return "accepted", delivered, nil, nil, accepter, acceptedAt
    elseif delivered > 0 then
        return "partial", delivered
    end
    return "pending", 0
end

-- Whether a request closed (approved or rejected, at closedAt) is over a
-- week old.
local function Expired(state, closedAt, now)
    return CLOSED[state] == true and closedAt ~= nil and closedAt + Requests.KEEP_CLOSED < now
end

-- Every request of the guild's members, newest first, as views:
-- { key, requester, id, request, state, delivered, rejecter, closedAt,
-- accepter, acceptedAt }. Not those closed over a week ago.
function Requests.List(guild)
    local answers = AnswersByKey(guild)
    local list, now = {}, ns.Now()
    for guid, record in pairs(guild and guild.members or {}) do
        if record.rq and Data.IsShareable(record) and ns.Roster.IsKnownGUID(guid) then
            for id, request in pairs(record.rq) do
                local key = Requests.Key(guid, id)
                local state, delivered, rejecter, closedAt, accepter, acceptedAt = Requests.State(request, answers[key])
                if not Expired(state, closedAt, now) then
                    list[#list + 1] = { key = key, requester = guid, id = id, request = request, state = state,
                        delivered = delivered, rejecter = rejecter, closedAt = closedAt, accepter = accepter, acceptedAt = acceptedAt }
                end
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

-- Whether we see a request: our own, or one made to a bank character whose
-- items our rank may see (Ranks.lua).
function Requests.Visible(view)
    return view.requester == ns.playerGUID
        or (ns.playerGUID ~= nil and Ranks.CanSee(ns.playerGUID, view.request.b, Ranks.ITEMS))
end

-- What the buttons may do ---------------------------------------------------------

-- Whether we may delete a request: our own, unless it is accepted or
-- approved.
function Requests.CanDelete(view)
    return view.requester == ns.playerGUID and view.state ~= "approved" and view.state ~= "accepted"
end

-- Whether we may reject a request: someone else's, still open (accepted
-- too), and our rank may reject the requests made to its bank character
-- (Ranks.MayAnswer).
function Requests.CanReject(view)
    return view.requester ~= ns.playerGUID and not CLOSED[view.state]
        and Ranks.MayAnswer(ns.playerGUID, view.request.b, Ranks.REJECT)
end

-- Whether we may accept a request, stock aside (Requests.Spare): someone
-- else's, pending or partly delivered, and our rank may accept the requests
-- made to its bank character (Ranks.MayAnswer).
function Requests.MayAccept(view)
    return view.requester ~= ns.playerGUID and (view.state == "pending" or view.state == "partial")
        and Ranks.MayAnswer(ns.playerGUID, view.request.b, Ranks.ACCEPT)
end

-- How many of a request's item its bank character has to spare: what it
-- holds (bags and bank, as it last shared them), less what the other
-- accepted requests made to it still await of that item; and how many the
-- request still awaits. nil when what the bank character holds is not
-- known.
function Requests.Spare(guild, view)
    local record = guild and guild.members[view.request.b]
    local bank = record and Data.IsShareable(record) and record.bk
    if not bank then
        return nil
    end
    local itemID = view.request.i
    local spare = ns.BankView.Holding(bank, itemID) - Requests.Reserved(guild, view.request.b, itemID, view.key)
    return math.max(spare, 0), view.request.q - view.delivered
end

-- How many of an item the accepted requests made to a bank character still
-- await: set aside for them, not to be asked for again. But the request
-- except (its key), if given.
function Requests.Reserved(guild, bank, itemID, except)
    local reserved = 0
    for _, view in ipairs(Requests.List(guild)) do
        if view.key ~= except and view.state == "accepted" and view.request.b == bank and view.request.i == itemID then
            reserved = reserved + math.max(view.request.q - view.delivered, 0)
        end
    end
    return reserved
end

-- The open requests not accepted (pending or partly delivered) whose bank
-- character has not enough of the item to spare for them, as Accept
-- refuses them (Requests.Spare): it holds less than they still await, once
-- what the accepted requests made to it still await is set aside. Not
-- those of a bank character whose bank is not known. Oldest first.
function Requests.Short(guild)
    local views = Requests.List(guild)
    local reserved = {}
    for _, view in ipairs(views) do
        if view.state == "accepted" then
            local key = view.request.b .. ":" .. view.request.i
            reserved[key] = (reserved[key] or 0) + math.max(view.request.q - view.delivered, 0)
        end
    end
    local short = {}
    for _, view in ipairs(views) do
        if view.state == "pending" or view.state == "partial" then
            local record = guild.members[view.request.b]
            local bank = record and Data.IsShareable(record) and record.bk
            if bank then
                local spare = ns.BankView.Holding(bank, view.request.i) - (reserved[view.request.b .. ":" .. view.request.i] or 0)
                if spare < view.request.q - view.delivered then
                    short[#short + 1] = view
                end
            end
        end
    end
    table.sort(short, function(a, b)
        if a.request.c ~= b.request.c then
            return a.request.c < b.request.c
        end
        return a.key < b.key
    end)
    return short
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
-- why: "guild", "rank" (ours may not make requests), "bank", "quantity",
-- "delivery" or "full".
function Requests.Create(bank, itemString, quantity, note, delivery)
    local record = Own()
    if not record then
        return nil, "guild"
    elseif not Ranks.Can(ns.playerGUID, Ranks.MAKE) then
        return nil, "rank"
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

-- Room for one more in a map of ours (ra, ac) at its limit: the oldest
-- goes (when of each: at(value)), as every version refuses a record over
-- it.
local function MakeRoom(map, at)
    if Count(map) < LIMITS.answers then
        return
    end
    local oldestKey, oldest
    for key, value in pairs(map) do
        if not oldest or at(value) < oldest then
            oldestKey, oldest = key, at(value)
        end
    end
    map[oldestKey] = nil
end

local function Answer(record, key)
    record.ra = record.ra or {}
    local answer = record.ra[key]
    if not answer then
        MakeRoom(record.ra, function(value) return value.u or 0 end)
        answer = { s = DELIVERING, n = 0 }
        record.ra[key] = answer
    end
    return answer
end

-- Accepts another member's request, if its bank character has enough to
-- spare. Returns true, or false and why: "changed" (it is no longer to be
-- accepted, or we may not) or "stock".
function Requests.Accept(requester, id)
    local record = Own()
    local guild = Data.CurrentGuild(false)
    local view = record and Requests.Find(guild, requester, id)
    if not view or not Requests.MayAccept(view) then
        return false, "changed"
    end
    local spare, needed = Requests.Spare(guild, view)
    if not spare or spare < needed then
        return false, "stock"
    end
    record.ac = record.ac or {}
    MakeRoom(record.ac, function(value) return value end)
    record.ac[view.key] = ns.Now()
    Data.TouchOwn(record)
    return true
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

-- Rejects, at once, the requests short of stock (Requests.Short) we may
-- reject. Returns how many.
function Requests.RejectShort()
    local record = Own()
    local guild = Data.CurrentGuild(false)
    if not record or not guild then
        return 0
    end
    local count, now = 0, ns.Now()
    for _, view in ipairs(Requests.Short(guild)) do
        if Requests.CanReject(view) then
            local answer = Answer(record, view.key)
            answer.s, answer.u = REJECTED, now
            count = count + 1
        end
    end
    if count > 0 then
        Data.TouchOwn(record)
    end
    return count
end

-- Our rejected requests, which we may delete. Oldest first.
function Requests.OwnRejected(guild)
    local list = {}
    for _, view in ipairs(Requests.List(guild)) do
        if view.requester == ns.playerGUID and view.state == "rejected" and Requests.CanDelete(view) then
            list[#list + 1] = view
        end
    end
    table.sort(list, function(a, b)
        return a.request.c < b.request.c or (a.request.c == b.request.c and a.id < b.id)
    end)
    return list
end

-- Deletes, at once, our rejected requests. Returns how many.
function Requests.DeleteRejected()
    local record = Own()
    local guild = Data.CurrentGuild(false)
    if not record or not guild or not record.rq then
        return 0
    end
    local count = 0
    for _, view in ipairs(Requests.OwnRejected(guild)) do
        record.rq[view.id] = nil
        count = count + 1
    end
    if count > 0 then
        Data.TouchOwn(record)
    end
    return count
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

-- Whether an answer of ours (given at when) no longer matters: its request
-- is gone, or, its maker unknown to us, it is old.
local function Stale(guild, key, when, now)
    local requester, id = key:match("^(.+):(%d+)$")
    local theirs = guild.members[requester]
    if theirs and Data.IsShareable(theirs) and theirs.rq then
        return not theirs.rq[tonumber(id)]
    end
    return when + KEEP_ANSWERS < now
end

-- Drops our requests all delivered, once the chat told us so (their state
-- noted by RequestList.CheckNotices), and those closed over a week ago
-- (rejected ones); and our answers to requests that are gone.
function Requests.Prune()
    local guild = Data.CurrentGuild(false)
    local record = guild and ns.playerGUID and guild.members[ns.playerGUID]
    if not record then
        return
    end
    local now, changed = ns.Now(), false
    if record.rq then
        local answers = AnswersByKey(guild)
        local told = ns.db and Data.OwnState().requestStates or {}
        for id, request in pairs(record.rq) do
            local key = Requests.Key(ns.playerGUID, id)
            local state, _, _, closedAt = Requests.State(request, answers[key])
            if (state == "approved" and told[key] == "approved") or Expired(state, closedAt, now) then
                record.rq[id] = nil
                changed = true
            end
        end
    end
    for key, answer in pairs(record.ra or {}) do
        if Stale(guild, key, answer.u, now) then
            record.ra[key] = nil
            changed = true
        end
    end
    for key, at in pairs(record.ac or {}) do
        if Stale(guild, key, at, now) then
            record.ac[key] = nil
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
