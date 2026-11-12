-- RequestList.lua: the Requests subtab of the Guild Bank tab (GuildTab.lua):
-- every withdrawal request of the guild, oldest first, with where it stands
-- and the buttons that apply to us: Delete (our own, until approved) and
-- Reject (a bank character, an officer or the guild master, while open).
-- A bank character's open requests also have Prepare, and Mail for those by
-- mail (Prepare.lua): beside the other button, enabled when they can do
-- their part, with a tooltip saying what they do or why they cannot.
-- Also the chat notices about requests that concern us.
local _, ns = ...
local L = ns.L

local RequestList = {}
ns.RequestList = RequestList

local ROW_HEIGHT = 56
local BUTTON_WIDTH, BUTTON_HEIGHT, BUTTON_GAP = 84, 22, 4
local NOTE_PREVIEW = 60  -- bytes of the note shown in a row; all of it in the tooltip

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

local function Run(action, view)
    local ok
    if action == "delete" then
        ok = ns.Requests.Delete(view.id)
    elseif action == "reject" then
        ok = ns.Requests.Reject(view.requester, view.id)
    end
    if not ok then
        ns.Print(L["this request changed meanwhile."])
    end
    if RequestList.onChange then
        RequestList.onChange()
    end
end

-- The buttons a request has: { action, text, enabled, reason }.
local function Actions(view)
    if view.requester == ns.playerGUID then
        if view.state == "approved" then
            return {}
        end
        return { { "delete", DELETE or "Delete", true } }
    elseif ns.Requests.IsClosed(view.state) then
        return {}
    elseif ns.Ranks.CanReject(ns.playerGUID) then
        return { { "reject", L["Reject"], true } }
    end
    return {}
end

-- Rows -------------------------------------------------------------------------------

local function RowOnEnter(row)
    local view = row.view
    if not view then
        return
    end
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
    row.Icon = row:CreateTexture(nil, "ARTWORK")
    row.Icon:SetSize(36, 36)
    row.Icon:SetPoint("LEFT", 8, 0)
    -- Over the icon, the item: its tooltip, and shift-click links it.
    row.Item = CreateFrame("Button", nil, row)
    row.Item:SetAllPoints(row.Icon)
    row.Item:SetScript("OnEnter", function(self)
        if row.view then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if not pcall(GameTooltip.SetHyperlink, GameTooltip, ItemString(row.view.request)) then
                GameTooltip:SetText(ItemText(row.view.request), 1, 1, 1)
            end
            GameTooltip:Show()
        end
    end)
    row.Item:SetScript("OnLeave", GameTooltip_Hide)
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

-- The buttons at the right of the row, side by side, each in a place of
-- its own so they line up from row to row: from the right, the other
-- button (Delete or Reject), Mail (left empty for a request in person) and
-- Prepare. The texts stop before the leftmost place in use.
local function LayOut(row, other, ready)
    row.Prepare:Hide()
    row.Mail:Hide()
    row.Button:ClearAllPoints()
    row.Button:SetPoint("RIGHT", row, "RIGHT", Place(1), 0)
    local used = other and 1 or 0
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
    row.Title:SetText(ItemText(view.request))
    row.State:SetText(("%s · %s"):format(L["%s, from the bank of %s"]:format(Name(view.requester), Name(view.request.b)), StateText(view)))
    row.Detail:SetText(DetailText(view))
    local action = Actions(view)[1]
    row.Button.action = action and action[1]
    row.Button.reason = action and action[4]
    if action then
        row.Button:SetText(action[2])
        row.Button:SetEnabled(action[3])
    end
    row.Button:SetShown(action ~= nil)
    LayOut(row, action, ns.Prepare.Actions(view))
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

-- Notices ---------------------------------------------------------------------------

-- What a change of state means for us, as a chat line only we see. Our own
-- deliveries are told by Deliveries.lua.
local function Announce(view, before)
    local item = ItemText(view.request)
    if view.requester == ns.playerGUID then
        if view.state == "approved" then
            ns.Print(L["your request was delivered: %s."], item)
        elseif view.state == "rejected" then
            ns.Print(L["%s rejected your request: %s."], Name(view.rejecter), item)
        elseif view.state == "partial" then
            ns.Print(L["%d of %d delivered for your request: %s."], view.delivered, view.request.q, item)
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
-- time, nothing is told.
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
            local state = view.state == "partial" and ("partial:" .. view.delivered) or view.state
            now[view.key] = state
            if before and before[view.key] ~= state then
                Announce(view, before[view.key])
            end
        end
    end
    own.requestStates = now
end

function RequestList.Init()
    ns.On("DataChanged", function()
        ns.Debounce("RequestNotices", 1, RequestList.CheckNotices)
    end)
end
