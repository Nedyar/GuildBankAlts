-- RequestList.lua: the Requests subtab of the Guild Bank tab (GuildTab.lua):
-- every withdrawal request of the guild, oldest first, with where it stands
-- and the buttons that apply to us: Delete (our own, unless accepted or
-- approved), and, for a bank character, an officer or the guild master,
-- Reject (while open) and Accept (pending or partly delivered; enabled when
-- the bank character has enough to spare, else its tooltip says why). A
-- bank character's accepted requests also have Prepare, and Mail for those
-- by mail (Prepare.lua): beside Reject, enabled when they can do their
-- part, with a tooltip saying what they do or why they cannot.
-- Under the list (GuildTab.lua), buttons acting on several requests at
-- once: Delete my rejected, and Reject short of stock (RequestList.BulkState).
-- The notification mark shows on the rows of the requests for us: waiting
-- for us, as a bank character; ours rejected, until we delete them or a
-- week passes; ours accepted, until we point at their row. Also the chat
-- notices about requests that concern us.
local _, ns = ...
local L = ns.L

local RequestList = {}
ns.RequestList = RequestList

local ROW_HEIGHT = 56
local BUTTON_WIDTH, BUTTON_HEIGHT, BUTTON_GAP = 84, 22, 4
local NOTE_PREVIEW = 60  -- bytes of the note shown in a row; all of it in the tooltip
-- The tint of a row, by the request's state: red, green, blue, alpha.
local TINTS = { accepted = { 0.1, 0.75, 0.1, 0.22 }, rejected = { 0.85, 0.1, 0.1, 0.22 } }

local function Name(guid)
    local guild = ns.Data.CurrentGuild(false)
    return ns.Data.NameOf(guid, guild and guild.members[guid])
end

local function ItemString(request)
    return request.s or ("item:" .. request.i)
end

local function ItemText(request)
    return ("%s x%d"):format(ns.BankView.ItemName(ItemString(request)), request.q)
end

-- Our accepted requests whose notice we saw, pointing at their row:
-- OwnState().acceptedSeen = { [request key] = true }.
local function AcceptedSeen()
    local own = ns.Data.OwnState()
    own.acceptedSeen = own.acceptedSeen or {}
    return own.acceptedSeen
end

-- Whether a request is ours, accepted, and its notice not seen yet.
local function AcceptedUnseen(view)
    return ns.playerGUID ~= nil and ns.db ~= nil and view.requester == ns.playerGUID and view.state == "accepted"
        and not AcceptedSeen()[view.key]
end

-- Pointing at a row, or at its item: the notice of our accepted request in
-- it is seen. Its mark goes, and the count and the tabs' marks are told
-- again, the list left as it is.
local function SeeRow(row)
    local view = row.view
    if view and AcceptedUnseen(view) then
        AcceptedSeen()[view.key] = true
        row.Mark:Hide()
        if ns.GuildTab.UpdateMarks then
            ns.GuildTab.UpdateMarks()
        end
    end
end

-- Where a request stands.
local function StateText(view)
    local state = view.state
    if state == "approved" then
        return L["Approved: delivered"]
    elseif state == "rejected" then
        local text = L["Rejected by %s"]:format(Name(view.rejecter))
        if view.delivered > 0 then
            text = ("%s · %s"):format(text, L["%d/%d delivered"]:format(view.delivered, view.request.q))
        end
        return text
    elseif state == "accepted" then
        local text = L["Accepted by %s"]:format(Name(view.accepter))
        if view.delivered > 0 then
            text = ("%s · %s"):format(text, L["%d/%d delivered"]:format(view.delivered, view.request.q))
        end
        return text
    elseif state == "partial" then
        return L["%d/%d delivered"]:format(view.delivered, view.request.q)
    end
    return L["Pending"]
end

local function NotePreview(note)
    note = note:gsub("\n", " ")
    if #note > NOTE_PREVIEW then
        note = note:sub(1, NOTE_PREVIEW):gsub("[\128-\191]*$", ""):gsub("[\192-\255]$", "") .. "..."
    end
    return "\"" .. note .. "\""
end

-- How the requester wants the items, or nil for requests made before it
-- could be chosen.
local function DeliveryText(request)
    if request.d == ns.Requests.IN_PERSON then
        return L["In person"]
    elseif request.d == ns.Requests.BY_MAIL then
        return L["By mail"]
    end
end

-- The same, with what the mail costs, for the tooltip.
local function DeliveryLine(request)
    if request.d == ns.Requests.BY_MAIL then
        return L["By mail: %s per stack, cash on delivery"]:format(ns.BankView.Coin(ns.Requests.MAIL_FEE, "Copper"))
    end
    return DeliveryText(request)
end

local function DetailText(view)
    local parts = { L["%s ago"]:format(ns.Ago(view.request.c)) }
    parts[#parts + 1] = DeliveryText(view.request)
    if view.request.nt ~= "" then
        parts[#parts + 1] = NotePreview(view.request.nt)
    end
    return table.concat(parts, " · ")
end

-- Actions ---------------------------------------------------------------------------

-- Why Accept is off, or nil when it is on: the bank character's stock.
local function AcceptReason(view)
    local spare, needed = ns.Requests.Spare(ns.Data.CurrentGuild(false), view)
    if not spare then
        return L["%s has not shared what it holds yet: log in with it with this addon."]:format(Name(view.request.b))
    elseif spare < needed then
        return L["Not enough in the bank: %d to spare, %d asked. What other accepted requests still await is set aside."]
            :format(spare, needed)
    end
end

local function Run(action, view)
    local ok, why
    if action == "delete" then
        ok = ns.Requests.Delete(view.id)
    elseif action == "reject" then
        ok = ns.Requests.Reject(view.requester, view.id)
    elseif action == "accept" then
        ok, why = ns.Requests.Accept(view.requester, view.id)
    end
    if why == "stock" then
        ns.Print(AcceptReason(view) or L["this request changed meanwhile."])
    elseif not ok then
        ns.Print(L["this request changed meanwhile."])
    end
    if RequestList.onChange then
        RequestList.onChange()
    end
end

-- The buttons a request has, but Prepare and Mail: { action, text,
-- enabled, reason }, from the right: Delete or Reject, then Accept.
local function Actions(view)
    if ns.Requests.CanDelete(view) then
        return { { "delete", DELETE or "Delete", true } }
    elseif not ns.Requests.CanReject(view) then
        return {}
    end
    local actions = { { "reject", L["Reject"], true } }
    if ns.Requests.MayAccept(view) then
        local reason = AcceptReason(view)
        actions[2] = { "accept", L["Accept"], reason == nil, reason }
    end
    return actions
end

-- Buttons under the list ---------------------------------------------------------------

local LISTED = 10  -- requests a button's tooltip names; the rest are counted

-- What a button under the list does now, by its action: { shown,
-- enabled, tip, views (the requests it acts on) }.
--   "deleteRejected", everyone's: deletes our rejected requests;
--   "rejectShort", for those who may reject requests: rejects those short
--     of stock (Requests.Short), which Accept refuses. Not accepted ones.
function RequestList.BulkState(action)
    local guild = ns.Data.CurrentGuild(false)
    if action == "deleteRejected" then
        local views = ns.Requests.OwnRejected(guild)
        return {
            shown = true, enabled = #views > 0, views = views,
            tip = #views > 0 and L["Deletes your rejected requests (%d)."]:format(#views)
                or L["You have no rejected requests."],
        }
    end
    local mayReject = ns.playerGUID ~= nil and ns.Ranks.CanReject(ns.playerGUID)
    local views = {}
    if mayReject and guild then
        for _, view in ipairs(ns.Requests.Short(guild)) do
            if ns.Requests.CanReject(view) then
                views[#views + 1] = view
            end
        end
    end
    return {
        shown = mayReject, enabled = #views > 0, views = views,
        tip = #views > 0 and L["Rejects the requests that cannot be met because the bank does not hold enough for them."]
            or L["No request is short of stock."],
    }
end

-- A button under the list: what it does, and the requests it acts on.
function RequestList.BulkOnEnter(button)
    local state = RequestList.BulkState(button.action)
    GameTooltip:SetOwner(button, "ANCHOR_TOP")
    GameTooltip:SetText(button:GetText(), 1, 1, 1)
    local r, g, b = NORMAL_FONT_COLOR:GetRGB()
    GameTooltip:AddLine(state.tip, r, g, b, true)
    for index, view in ipairs(state.views) do
        if index > LISTED then
            GameTooltip:AddLine(L["and %d more"]:format(#state.views - LISTED), 0.7, 0.7, 0.7)
            break
        end
        GameTooltip:AddDoubleLine(ItemText(view.request), Name(view.requester), 1, 1, 1, 0.7, 0.7, 0.7)
    end
    GameTooltip:Show()
end

-- Runs a button under the list. Rejecting asks first: it cannot be undone,
-- and it answers other members.
function RequestList.BulkRun(action)
    local function Done()
        if RequestList.onChange then
            RequestList.onChange()
        end
    end
    if action == "deleteRejected" then
        local count = ns.Requests.DeleteRejected()
        if count > 0 then
            ns.Print(L["Rejected requests deleted: %d."], count)
        end
        Done()
        return
    end
    local count = #RequestList.BulkState(action).views
    if count == 0 then
        return
    end
    StaticPopup_ShowCustomGenericConfirmation({
        text = "%s",
        text_arg1 = L["Reject the requests short of stock (%d)? Their makers are told."]:format(count),
        showAlert = true,
        callback = function()
            local rejected = ns.Requests.RejectShort()
            if rejected > 0 then
                ns.Print(L["Requests short of stock rejected: %d."], rejected)
            end
            Done()
        end,
    })
end

-- Rows -------------------------------------------------------------------------------

local function RowOnEnter(row)
    local view = row.view
    if not view then
        return
    end
    SeeRow(row)
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetText(ItemText(view.request), 1, 1, 1)
    GameTooltip:AddLine(L["Requested by %s from the bank of %s"]:format(Name(view.requester), Name(view.request.b)), NORMAL_FONT_COLOR:GetRGB())
    GameTooltip:AddLine(StateText(view), 1, 1, 1, true)
    local delivery = DeliveryLine(view.request)
    if delivery then
        GameTooltip:AddLine(L["Delivery: %s"]:format(delivery), 1, 1, 1, true)
    end
    if view.request.nt ~= "" then
        GameTooltip:AddLine(view.request.nt, 0.9, 0.9, 0.9, true)
    end
    GameTooltip:Show()
end

local function ButtonOnEnter(button)
    if button.reason then
        GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
        GameTooltip:SetText(button.reason, 1, 1, 1, 1, true)
        GameTooltip:Show()
    end
end

local function CreateButton(row, onClick)
    local button = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    button:SetSize(BUTTON_WIDTH, BUTTON_HEIGHT)
    button:SetMotionScriptsWhileDisabled(true)
    button:SetScript("OnClick", onClick)
    button:SetScript("OnEnter", ButtonOnEnter)
    button:SetScript("OnLeave", GameTooltip_Hide)
    return button
end

local function CreateRow(row)
    -- An accepted request's row is green, a rejected one's red.
    row.Tints = {}
    for state, color in pairs(TINTS) do
        local tint = row:CreateTexture(nil, "BACKGROUND")
        tint:SetAllPoints()
        tint:SetColorTexture(unpack(color))
        tint:Hide()
        row.Tints[state] = tint
    end
    row.Icon = row:CreateTexture(nil, "ARTWORK")
    row.Icon:SetSize(36, 36)
    row.Icon:SetPoint("LEFT", 8, 0)
    -- Over the icon, the item: its tooltip, and shift-click links it.
    row.Item = CreateFrame("Button", nil, row)
    row.Item:SetAllPoints(row.Icon)
    row.Item:SetScript("OnEnter", function(self)
        SeeRow(row)
        if row.view then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if not pcall(GameTooltip.SetHyperlink, GameTooltip, ItemString(row.view.request)) then
                GameTooltip:SetText(ItemText(row.view.request), 1, 1, 1)
            end
            GameTooltip:Show()
        end
    end)
    row.Item:SetScript("OnLeave", GameTooltip_Hide)
    -- On the icon's corner, the notification mark: a request that waits
    -- for us, or ours rejected (RequestList.IsForMe).
    row.Mark = ns.GuildTab.NewMark(row.Item, -4, -4)
    row.Item:SetScript("OnClick", function()
        if row.view and IsModifiedClick("CHATLINK") then
            local _, link = ns.BankView.ItemInfo(ItemString(row.view.request))
            if link then
                ChatFrameUtil.InsertLink(link)
            end
        end
    end)
    row.Title = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    row.Title:SetPoint("TOPLEFT", row.Icon, "TOPRIGHT", 8, -1)
    row.Title:SetJustifyH("LEFT")
    row.Title:SetWordWrap(false)
    row.State = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.State:SetPoint("TOPLEFT", row.Title, "BOTTOMLEFT", 0, -3)
    row.State:SetJustifyH("LEFT")
    row.State:SetWordWrap(false)
    row.Detail = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    row.Detail:SetPoint("TOPLEFT", row.State, "BOTTOMLEFT", 0, -3)
    row.Detail:SetJustifyH("LEFT")
    row.Detail:SetWordWrap(false)
    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAtlas("PetList-ButtonHighlight")
    highlight:SetAllPoints()
    highlight:SetBlendMode("ADD")
    row.Button = CreateButton(row, function(self)
        Run(self.action, row.view)
    end)
    row.Accept = CreateButton(row, function(self)
        Run(self.action, row.view)
    end)
    row.Prepare = CreateButton(row, function(self)
        ns.Prepare.Run(row.view, self.action)
    end)
    row.Mail = CreateButton(row, function()
        ns.Prepare.Run(row.view, "mail")
    end)
    row:EnableMouse(true)
    row:SetScript("OnEnter", RowOnEnter)
    row:SetScript("OnLeave", GameTooltip_Hide)
end

-- A Prepare (or Release) or Mail button: { action, text, enabled, tip }
-- (Prepare.Actions).
local function SetUp(button, action)
    button.action = action.action
    button:SetText(action.text)
    button:SetEnabled(action.enabled == true)
    button.reason = action.tip
    button:Show()
end

-- Where the button in place index (1: the rightmost) goes, from the row's
-- right edge.
local function Place(index)
    return -(8 + (index - 1) * (BUTTON_WIDTH + BUTTON_GAP))
end

-- A button of Actions: { action, text, enabled, reason }, or nil to hide it.
local function SetAction(button, action)
    button.action = action and action[1]
    button.reason = action and action[4]
    if action then
        button:SetText(action[2])
        button:SetEnabled(action[3])
    end
    button:SetShown(action ~= nil)
end

-- The buttons at the right of the row, side by side, each in a place of
-- its own so they line up from row to row: from the right, Delete or
-- Reject; then Accept (a request not accepted yet) or Mail (one accepted,
-- left empty for a request in person) and Prepare. The texts stop before
-- the leftmost place in use.
local function LayOut(row, actions, ready)
    row.Prepare:Hide()
    row.Mail:Hide()
    SetAction(row.Button, actions[1])
    SetAction(row.Accept, actions[2])
    row.Button:ClearAllPoints()
    row.Button:SetPoint("RIGHT", row, "RIGHT", Place(1), 0)
    row.Accept:ClearAllPoints()
    row.Accept:SetPoint("RIGHT", row, "RIGHT", Place(2), 0)
    local used = #actions
    if ready then
        row.Prepare:ClearAllPoints()
        row.Prepare:SetPoint("RIGHT", row, "RIGHT", Place(3), 0)
        SetUp(row.Prepare, ready[1])
        if ready[2] then
            row.Mail:ClearAllPoints()
            row.Mail:SetPoint("RIGHT", row, "RIGHT", Place(2), 0)
            SetUp(row.Mail, ready[2])
        end
        used = 3
    end
    for _, text in ipairs({ row.Title, row.State, row.Detail }) do
        text:SetPoint("RIGHT", row, "RIGHT", used > 0 and Place(used) - BUTTON_WIDTH - 8 or -8, 0)
    end
end

local function InitRow(row, data)
    if not row.Title then
        CreateRow(row)
    end
    local view = data.view
    row.view = view
    local _, _, _, icon = ns.BankView.ItemInfo(ItemString(view.request))
    row.Icon:SetTexture(icon)
    row.Icon:SetDesaturated(view.state == "rejected")
    for state, tint in pairs(row.Tints) do
        tint:SetShown(view.state == state)
    end
    row.Mark:SetShown(RequestList.IsForMe(view))
    row.Title:SetText(ItemText(view.request))
    row.State:SetText(("%s · %s"):format(L["%s, from the bank of %s"]:format(Name(view.requester), Name(view.request.b)), StateText(view)))
    row.Detail:SetText(DetailText(view))
    LayOut(row, Actions(view), ns.Prepare.Actions(view))
end

-- The list --------------------------------------------------------------------------

-- A list in parent, filling it.
function RequestList.Create(parent)
    local list = CreateFrame("Frame", nil, parent)
    list:SetAllPoints()
    local scrollBox = CreateFrame("Frame", nil, list, "WowScrollBoxList")
    scrollBox:SetPoint("TOPLEFT", 4, -4)
    scrollBox:SetPoint("BOTTOMRIGHT", -20, 4)
    local scrollBar = CreateFrame("EventFrame", nil, list, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 4, 0)
    scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 4, 0)
    local view = CreateScrollBoxListLinearView(0, 0, 0, 0, 2)
    view:SetElementExtent(ROW_HEIGHT)
    view:SetElementInitializer("Frame", InitRow)
    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)
    list.ScrollBox = scrollBox
    list.Empty = list:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    list.Empty:SetPoint("CENTER")
    list.Empty:SetText(L["No requests here."])
    return list
end

-- The requests the list shows, oldest first (in the order they are to be
-- seen to). onlyOpen: those not approved nor rejected; onlyMine: ours.
function RequestList.Views(onlyOpen, onlyMine)
    local list = {}
    for _, view in ipairs(ns.Requests.List(ns.Data.CurrentGuild(false))) do
        if (not onlyOpen or not ns.Requests.IsClosed(view.state)) and (not onlyMine or view.requester == ns.playerGUID) then
            list[#list + 1] = view
        end
    end
    table.sort(list, function(a, b)
        if a.request.c ~= b.request.c then
            return a.request.c < b.request.c
        end
        return a.key < b.key
    end)
    return list
end

function RequestList.Show(list, onlyOpen, onlyMine)
    local elements = {}
    for _, view in ipairs(RequestList.Views(onlyOpen, onlyMine)) do
        elements[#elements + 1] = { view = view }
    end
    list.ScrollBox:SetDataProvider(CreateDataProvider(elements), ScrollBoxConstants and ScrollBoxConstants.RetainScrollPosition)
    list.Empty:SetShown(#elements == 0)
end

-- How many requests wait for us: made to us, as a bank character.
function RequestList.WaitingForMe()
    if not ns.playerGUID or not ns.Ranks.IsBank(ns.playerGUID) then
        return 0
    end
    return ns.Requests.WaitingFor(ns.Data.CurrentGuild(false), ns.playerGUID)
end

-- How many of our requests are answered, their notice not done with:
-- rejected (until we delete them, or for a week) or accepted (until we
-- point at their row).
function RequestList.AnsweredForMe()
    local count = 0
    if ns.playerGUID then
        for _, view in ipairs(ns.Requests.List(ns.Data.CurrentGuild(false))) do
            if view.requester == ns.playerGUID and (view.state == "rejected" or AcceptedUnseen(view)) then
                count = count + 1
            end
        end
    end
    return count
end

-- What the Requests subtab counts and the guild tab's mark shows: the
-- requests waiting for us, as a bank character, and ours answered.
function RequestList.ForMe()
    return RequestList.WaitingForMe() + RequestList.AnsweredForMe()
end

-- Whether a request's row has the notification mark: it waits for us, as a
-- bank character (RequestList.WaitingForMe), or it is ours, rejected or
-- accepted and not pointed at yet (RequestList.AnsweredForMe).
function RequestList.IsForMe(view)
    if not ns.playerGUID then
        return false
    end
    if view.requester == ns.playerGUID then
        return view.state == "rejected" or AcceptedUnseen(view)
    end
    return view.request.b == ns.playerGUID and ns.Ranks.IsBank(ns.playerGUID) and not ns.Requests.IsClosed(view.state)
end

-- Notices ---------------------------------------------------------------------------

-- How a request that concerns us stood, as CheckNotices notes it: its
-- state, and for one partly delivered or accepted, how many were
-- delivered ("partial:3", "accepted:0").
local function Noted(view)
    if view.state == "partial" or view.state == "accepted" then
        return view.state .. ":" .. view.delivered
    end
    return view.state
end

local function DeliveredIn(noted)
    return tonumber(noted and noted:match(":(%d+)$")) or 0
end

-- What a change of state means for us, as a chat line only we see. Our own
-- deliveries are told by Deliveries.lua.
local function Announce(view, before)
    local item = ItemText(view.request)
    if view.requester == ns.playerGUID then
        if view.state == "approved" then
            ns.Print(L["your request was delivered: %s."], item)
        elseif view.state == "rejected" then
            ns.Print(L["%s rejected your request: %s."], Name(view.rejecter), item)
        else
            if view.state == "accepted" and not (before and before:find("^accepted")) then
                ns.Print(L["%s accepted your request: %s."], Name(view.accepter), item)
            end
            if view.delivered > DeliveredIn(before) then
                ns.Print(L["%d of %d delivered for your request: %s."], view.delivered, view.request.q, item)
            end
        end
    elseif before == nil and not ns.Requests.IsClosed(view.state) then
        local delivery = DeliveryLine(view.request)
        if delivery then
            ns.Print(L["%s requests from your bank: %s. Delivery: %s."], Name(view.requester), item, delivery)
        else
            ns.Print(L["%s requests from your bank: %s."], Name(view.requester), item)
        end
    end
end

-- Compares the requests that concern us (ours, and those made to us as a
-- bank character) with how they stood last time, saved per character so
-- changes made while we were away are told at login too. The very first
-- time, nothing is told. Our requests all delivered go once noted here
-- (Requests.Prune).
function RequestList.CheckNotices()
    local guild = ns.Data.CurrentGuild(false)
    if not guild or not ns.playerGUID or not ns.Roster.ready then
        return
    end
    local own = ns.Data.OwnState()
    local before = own.requestStates
    local now = {}
    local isBank = ns.Ranks.IsBank(ns.playerGUID)
    for _, view in ipairs(ns.Requests.List(guild)) do
        if view.requester == ns.playerGUID or (isBank and view.request.b == ns.playerGUID) then
            local state = Noted(view)
            now[view.key] = state
            if before and before[view.key] ~= state then
                Announce(view, before[view.key])
            end
        end
    end
    own.requestStates = now
    -- The notices seen of requests no longer accepted are forgotten.
    for key in pairs(own.acceptedSeen or {}) do
        if not (now[key] and now[key]:find("^accepted")) then
            own.acceptedSeen[key] = nil
        end
    end
end

function RequestList.Init()
    -- Kept by 0.3.1, no longer used.
    local own = ns.Data.OwnState()
    own.requestsSeen = nil
    ns.On("DataChanged", function()
        ns.Debounce("RequestNotices", 1, RequestList.CheckNotices)
    end)
end
