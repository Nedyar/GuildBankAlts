-- BankView.lua: the Bank subtab of the Guild Bank tab (GuildTab.lua): what
-- each guild bank character holds, as they last shared it (Bank.lua).
--
-- At the top: a dropdown to choose the bank character, its bag slots (the
-- backpack, each bag slot with its bag or empty, the bank, and each bank
-- bag slot: locked, empty or with its bag), and a search box.
-- Below: its slots, one by one as they are in its bags and bank, stacks as
-- they are, looking like the game's guild bank (Blizzard_GuildBankUI):
-- columns of 2 x 7 slots on the guild bank's own slot art, inside its inner
-- frame, all at once: the slots are scaled down when they would not fit,
-- never scrolled. The search box dims the items whose name does not match,
-- as the game's does. Pointing at a bag lights up its slots. Pointing at an
-- item shows it; right-clicking it opens a withdrawal request
-- (RequestForm.lua).
-- At the bottom, in a thin gold frame like the guild bank's money: the
-- guild bank's money on the left, the character's on the right, and a
-- clock in the middle whose tooltip tells when each was last seen.
local _, ns = ...
local L = ns.L

local BankView = {}
ns.BankView = BankView

-- The guild bank's column (GuildBankFrameColumnTemplate): 100 x 311, two
-- rows of 7 slots of 37 px, 7 px apart, the second 12 px right of the first.
local COLUMN_TEXTURE = "Interface\\GuildBankFrame\\UI-GuildBankFrame-Slots"
local COLUMN_TEXCOORDS = { 0, 0.78125, 0, 0.607421875 }
local COLUMN_WIDTH, COLUMN_HEIGHT, COLUMN_GAP = 100, 311, 3
local SLOTS_PER_COLUMN, ROWS = 14, 7
local SLOT, ROW_GAP, TOP = 37, 7, 3
local SUBCOLUMN_X = { 7, 7 + 37 + 12 }
local BAND_GAP = 6             -- between rows of columns
-- The guild bank's inner frame: 32 px corners, its edges tiled between
-- them, black inside; the first column sits 6 px in from its corner.
local CORNERS = "Interface\\GuildBankFrame\\Corners"
local CORNER_COORDS = {
    BOTTOMLEFT = { 0.015625, 0.515625, 0.00390625, 0.12890625 },
    BOTTOMRIGHT = { 0.015625, 0.515625, 0.13671875, 0.26171875 },
    TOPRIGHT = { 0.015625, 0.515625, 0.26953125, 0.39453125 },
    TOPLEFT = { 0.015625, 0.515625, 0.40234375, 0.52734375 },
}
local INSET = 6
-- The thin gold frame of the guild bank's money (ThinGoldEdgeTemplate).
local MONEY_FRAME = "Interface\\Common\\Moneyframe"
local TOP_HEIGHT = 22
local DROPDOWN_WIDTH = 140
local SEARCH_WIDTH, SEARCH_HEIGHT = 120, 20
local FOOTER_HEIGHT = 22
-- Bag slots, as Blizzard's Camelot bank frame draws its bank bag slots.
local BAG_BACKGROUND, BAG_FRAME, BAG_LOCK = "bank-frame-bag-slot-bg", "bank-frame-bag-slotframe", "bankslot-icon-lock"
local BAG_GAP, BAG_GROUP_GAP, BAG_MIN, BAG_MAX = 2, 8, 14, TOP_HEIGHT + 4
local BACKPACK_ICON = "Interface\\Buttons\\Button-Backpack-Up"
local BANK_ICON = "Interface\\Icons\\INV_SideTab_Bank_c60"
local EMPTY_BAG_ICON = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Bag"
local CLOCK_ICON = "Interface\\Icons\\INV_Misc_PocketWatch_01"
-- The room the slots and bags get in the tests, where frames have no size.
local DEFAULT_WIDTH, DEFAULT_HEIGHT, DEFAULT_BAR_WIDTH = 548, 300, 260

local selectedBank  -- the GUID of the bank character shown
local requested = {} -- item data asked from the server, to name items

-- Items ---------------------------------------------------------------------------------

-- A coin, as the game's GetCoinTextureString draws it: the amount, then its
-- icon at the font's size.
local COIN = "%s|TInterface\\MoneyFrame\\UI-%sIcon:0:0:2:0|t"

function BankView.Coin(amount, kind)
    return COIN:format(amount, kind)
end

-- Money with all three coins, even those at 0 (the game's own leaves them
-- out); gold with thousands separators.
local function Money(copper)
    copper = math.max(0, math.floor(copper or 0))
    local gold = math.floor(copper / 10000)
    local goldText = BreakUpLargeNumbers and BreakUpLargeNumbers(gold) or tostring(gold)
    return ("%s %s %s"):format(COIN:format(goldText, "Gold"), COIN:format(math.floor(copper / 100) % 100, "Silver"),
        COIN:format(copper % 100, "Copper"))
end
BankView.Money = Money

local function ItemID(itemString)
    return tonumber(itemString:match("^item:(%d+)"))
end

-- An item's name, link, quality and icon, and whether the client has it
-- loaded; the name is the item string until then (it is then asked for).
function BankView.ItemInfo(itemString)
    local name, link, quality, _, _, _, _, _, _, icon = ns.Try(C_Item.GetItemInfo, itemString)
    local itemID = ItemID(itemString)
    if not name and itemID and not requested[itemID] then
        requested[itemID] = true
        ns.Try(C_Item.RequestLoadItemDataByID, itemID)
    end
    if not icon and itemID then
        icon = ns.Try(C_Item.GetItemIconByID, itemID)
    end
    return ns.Plain(name) or itemString, ns.Plain(link), ns.Plain(quality), ns.Plain(icon) or 134400, ns.Plain(name) ~= nil
end

function BankView.ItemName(itemString)
    return (BankView.ItemInfo(itemString))
end

-- The item string of an item as a bank character holds it.
local function ItemString(item)
    return item.s or ("item:" .. item.i)
end
BankView.ItemString = ItemString

-- Bank characters -------------------------------------------------------------------

-- The guild's bank characters, by name: { { guid, name, record, bank }... },
-- record and bank being nil for one that has not shared what it holds.
function BankView.Banks(guild)
    local list = {}
    for guid, member in pairs(ns.Roster.members) do
        if ns.Ranks.IsBank(guid) then
            local record = guild and guild.members[guid]
            if record and not ns.Data.IsShareable(record) then
                record = nil
            end
            list[#list + 1] = { guid = guid, name = member.n, record = record, bank = record and record.bk }
        end
    end
    table.sort(list, function(a, b)
        if a.name ~= b.name then
            return a.name < b.name
        end
        return a.guid < b.guid
    end)
    return list
end

-- Every container of a bank character, bags then bank.
local function Containers(bank)
    local list = {}
    for _, group in ipairs({ bank and bank.b or {}, bank and bank.k or {} }) do
        for _, container in ipairs(group) do
            list[#list + 1] = container
        end
    end
    return list
end

-- How many of an item a bank character holds, bags and bank together.
function BankView.Holding(bank, itemID)
    local count = 0
    for _, container in ipairs(Containers(bank)) do
        for _, item in pairs(container.s or {}) do
            if item.i == itemID then
                count = count + item.n
            end
        end
    end
    return count
end

-- Its slots, in order, as the character has them: { { item, container }... }
-- (item nil for an empty slot).
function BankView.Cells(bank)
    local cells = {}
    for _, container in ipairs(Containers(bank)) do
        if not container.lk then
            for slot = 1, container.z do
                cells[#cells + 1] = { item = container.s[slot], container = container.id }
            end
        end
    end
    return cells
end

-- Its bag slots: { { kind, container }... }, kind being "backpack", "bag"
-- (one of the bag slots), "bank" (its own slots) or "bankbag" (one of the
-- bank bag slots). Without a bank read, the bank alone, unknown.
function BankView.BagSlots(bank)
    local list = {}
    for _, container in ipairs(bank.b or {}) do
        list[#list + 1] = { kind = container.id == 0 and "backpack" or "bag", container = container }
    end
    if not bank.k then
        list[#list + 1] = { kind = "bank" }
        return list
    end
    for index, container in ipairs(bank.k) do
        list[#list + 1] = { kind = index == 1 and "bank" or "bankbag", container = container }
    end
    return list
end

-- How to lay out columns in a room of width x height: as many across as
-- give the largest scale (never above 1) with every column shown. Returns
-- the columns across, the rows, and the scale.
function BankView.Fit(columns, width, height)
    local best, bestAcross, bestRows = -1, 1, columns
    for across = math.max(columns, 1), 1, -1 do
        local rows = math.ceil(columns / across)
        local needWidth = across * COLUMN_WIDTH + (across - 1) * COLUMN_GAP
        local needHeight = rows * COLUMN_HEIGHT + (rows - 1) * BAND_GAP
        local scale = math.min(width / needWidth, height / needHeight, 1)
        if scale > best then
            best, bestAcross, bestRows = scale, across, rows
        end
    end
    return bestAcross, bestRows, best
end

-- Slots ----------------------------------------------------------------------------------

local function Matches(view, item)
    if not view.search or view.search == "" then
        return true
    end
    local name, _, _, _, loaded = BankView.ItemInfo(ItemString(item))
    return loaded and name:lower():find(view.search, 1, true) ~= nil
end

local function SlotOnEnter(slot)
    local item, owner = slot.item, slot.owner
    if not item then
        return
    end
    GameTooltip:SetOwner(slot, "ANCHOR_RIGHT")
    local itemString = ItemString(item)
    if not pcall(GameTooltip.SetHyperlink, GameTooltip, itemString) then
        GameTooltip:SetText(BankView.ItemName(itemString), 1, 1, 1)
    end
    GameTooltip:AddLine(L["%d in this bank"]:format(BankView.Holding(owner.bank, item.i)), NORMAL_FONT_COLOR:GetRGB())
    if owner.guid == ns.playerGUID then
        GameTooltip:AddLine(L["This is your own bank."], 0.7, 0.7, 0.7)
    else
        GameTooltip:AddLine(L["Right-click to request it."], GREEN_FONT_COLOR:GetRGB())
    end
    GameTooltip:Show()
end

local function SlotOnClick(slot, mouseButton)
    local item, owner = slot.item, slot.owner
    if not item then
        return
    end
    local itemString = ItemString(item)
    if mouseButton == "RightButton" then
        if owner.guid ~= ns.playerGUID then
            ns.RequestForm.Open(owner.guid, itemString, BankView.Holding(owner.bank, item.i))
        end
    elseif IsModifiedClick("CHATLINK") then
        local _, link = BankView.ItemInfo(itemString)
        if link then
            ChatFrameUtil.InsertLink(link)
        end
    end
end

local function CreateSlot(parent)
    local slot = CreateFrame("Button", nil, parent)
    slot:SetSize(SLOT, SLOT)
    slot.Icon = slot:CreateTexture(nil, "ARTWORK")
    slot.Icon:SetAllPoints()
    slot.Border = slot:CreateTexture(nil, "OVERLAY")
    slot.Border:SetTexture("Interface\\Common\\WhiteIconFrame")
    slot.Border:SetAllPoints()
    slot.Count = slot:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    slot.Count:SetPoint("BOTTOMRIGHT", -2, 2)
    slot.Count:SetJustifyH("RIGHT")
    -- Dims an item the search leaves out, as the game's bags do.
    slot.SearchOverlay = slot:CreateTexture(nil, "OVERLAY", nil, 2)
    slot.SearchOverlay:SetColorTexture(0, 0, 0, 0.8)
    slot.SearchOverlay:SetAllPoints()
    -- Covers a slot past the character's last (the last column's).
    slot.Blocked = slot:CreateTexture(nil, "OVERLAY", nil, 3)
    slot.Blocked:SetColorTexture(0, 0, 0, 0.75)
    slot.Blocked:SetAllPoints()
    -- Lights up while its bag is pointed at, as the game's bank does.
    slot.Glow = slot:CreateTexture(nil, "OVERLAY", nil, 4)
    slot.Glow:SetTexture("Interface\\Buttons\\CheckButtonHilight")
    slot.Glow:SetBlendMode("ADD")
    slot.Glow:SetAllPoints()
    slot.Glow:Hide()
    local highlight = slot:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    highlight:SetAllPoints()
    highlight:SetBlendMode("ADD")
    slot:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    slot:SetScript("OnEnter", SlotOnEnter)
    slot:SetScript("OnLeave", GameTooltip_Hide)
    slot:SetScript("OnClick", SlotOnClick)
    return slot
end

-- cell: { item, container } for a slot of the character (item nil when
-- empty), nil for one past its last.
local function SetSlot(slot, cell, owner, view)
    slot.item, slot.owner, slot.container = cell and cell.item, owner, cell and cell.container
    slot.Blocked:SetShown(cell == nil)
    slot.Glow:SetShown(cell ~= nil and view.glow ~= nil and cell.container == view.glow)
    local item = cell and cell.item
    if not item then
        slot.Icon:Hide()
        slot.Count:SetText("")
        slot.Border:Hide()
        slot.SearchOverlay:Hide()
        return
    end
    local _, _, quality, icon = BankView.ItemInfo(ItemString(item))
    slot.Icon:SetTexture(icon)
    slot.Icon:Show()
    slot.Count:SetText(item.n > 1 and item.n or "")
    local color = quality and quality >= 2 and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    if color then
        slot.Border:SetVertexColor(color.r, color.g, color.b)
        slot.Border:Show()
    else
        slot.Border:Hide()
    end
    slot.SearchOverlay:SetShown(not Matches(view, item))
end

local function CreateColumn(parent)
    local column = CreateFrame("Frame", nil, parent)
    column:SetSize(COLUMN_WIDTH, COLUMN_HEIGHT)
    column.Background = column:CreateTexture(nil, "BACKGROUND")
    column.Background:SetTexture(COLUMN_TEXTURE)
    column.Background:SetTexCoord(unpack(COLUMN_TEXCOORDS))
    column.Background:SetAllPoints()
    column.Slots = {}
    for i = 1, SLOTS_PER_COLUMN do
        local slot = CreateSlot(column)
        local sub, row = i <= ROWS and 1 or 2, (i - 1) % ROWS
        slot:SetPoint("TOPLEFT", SUBCOLUMN_X[sub], -(TOP + row * (SLOT + ROW_GAP)))
        column.Slots[i] = slot
    end
    return column
end

-- Lights up the slots of a container (nil: none).
local function Glow(view, container)
    view.glow = container
    for _, column in ipairs(view.Columns) do
        for _, slot in ipairs(column.Slots) do
            slot.Glow:SetShown(container ~= nil and slot.container == container and not slot.Blocked:IsShown())
        end
    end
end

-- Bag slots ------------------------------------------------------------------------------

local function SlotsText(count)
    return L["%d |4slot:slots;"]:format(count)
end

local function BagOnEnter(button)
    local entry = button.entry
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    local container = entry.container
    if entry.kind == "backpack" then
        GameTooltip:SetText(L["Backpack"], 1, 1, 1)
    elseif entry.kind == "bank" then
        GameTooltip:SetText(L["Bank"], 1, 1, 1)
        if not container then
            GameTooltip:AddLine(L["Bank not seen yet"], 0.7, 0.7, 0.7)
        end
    elseif container.lk then
        GameTooltip:SetText(L["Bank bag slot not bought yet"], 1, 1, 1)
    elseif container.bi then
        if not pcall(GameTooltip.SetHyperlink, GameTooltip, container.bi) then
            GameTooltip:SetText(BankView.ItemName(container.bi), 1, 1, 1)
        end
    else
        GameTooltip:SetText(entry.kind == "bankbag" and L["Empty bank bag slot"] or L["Empty bag slot"], 1, 1, 1)
    end
    if container and not container.lk and container.z > 0 then
        GameTooltip:AddLine(SlotsText(container.z), NORMAL_FONT_COLOR:GetRGB())
    end
    GameTooltip:Show()
    if container and not container.lk then
        Glow(button.view, container.id)
    end
end

local function BagOnLeave(button)
    GameTooltip_Hide()
    Glow(button.view, nil)
end

local function CreateBagButton(view)
    local button = CreateFrame("Button", nil, view.Bar)
    button.view = view
    button.Background = button:CreateTexture(nil, "BACKGROUND")
    button.Background:SetAtlas(BAG_BACKGROUND)
    button.Background:SetAllPoints()
    button.Icon = button:CreateTexture(nil, "ARTWORK")
    button.Icon:SetAllPoints()
    button.Lock = button:CreateTexture(nil, "ARTWORK", nil, 1)
    button.Lock:SetAtlas(BAG_LOCK)
    button.Lock:SetAllPoints()
    button.Frame = button:CreateTexture(nil, "OVERLAY")
    button.Frame:SetAtlas(BAG_FRAME)
    button.Frame:SetAllPoints()
    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    highlight:SetAllPoints()
    highlight:SetBlendMode("ADD")
    button:SetScript("OnEnter", BagOnEnter)
    button:SetScript("OnLeave", BagOnLeave)
    return button
end

local function SetBagButton(button, entry)
    button.entry = entry
    local container = entry.container
    local icon
    if entry.kind == "backpack" then
        icon = BACKPACK_ICON
    elseif entry.kind == "bank" then
        icon = BANK_ICON
    elseif container and container.bi then
        local _, _, _, bagIcon = BankView.ItemInfo(container.bi)
        icon = bagIcon
    elseif entry.kind == "bag" then
        icon = EMPTY_BAG_ICON
    end
    button.Icon:SetTexture(icon)
    button.Icon:SetShown(icon ~= nil)
    button.Icon:SetDesaturated(entry.kind == "bank" and not container)
    button.Lock:SetShown(container ~= nil and container.lk == true)
    button:Show()
end

-- Lays out the bag slots between the dropdown and the search box, as large
-- as fit; the bank's start a little apart from the bags'.
local function LayOutBags(view, entries)
    local width = view.Bar:GetWidth() or 0
    if width <= 0 then
        width = DEFAULT_BAR_WIDTH
    end
    local count = #entries
    local size = count > 0 and math.floor((width - BAG_GROUP_GAP + BAG_GAP) / count) - BAG_GAP or BAG_MAX
    size = math.max(BAG_MIN, math.min(BAG_MAX, size))
    view.bagSize = size
    local x = 0
    for i, entry in ipairs(entries) do
        local button = view.Bags[i]
        if not button then
            button = CreateBagButton(view)
            view.Bags[i] = button
        end
        if entry.kind == "bank" and i > 1 then
            x = x + BAG_GROUP_GAP
        end
        button:SetSize(size, size)
        button:ClearAllPoints()
        button:SetPoint("LEFT", view.Bar, "LEFT", x, 0)
        x = x + size + BAG_GAP
        SetBagButton(button, entry)
    end
    for i = #entries + 1, #view.Bags do
        view.Bags[i]:Hide()
    end
end

-- Frames -------------------------------------------------------------------------------

-- The guild bank's inner frame around a frame (as GuildBankFrame draws it).
local function GuildBankBorder(frame)
    local corners = {}
    for point, coords in pairs(CORNER_COORDS) do
        local corner = frame:CreateTexture(nil, "BORDER")
        corner:SetTexture(CORNERS)
        corner:SetSize(32, 32)
        corner:SetPoint(point)
        corner:SetTexCoord(unpack(coords))
        corners[point] = corner
    end
    -- Left and right, between the corners; top and bottom, likewise.
    local left = frame:CreateTexture(nil, "BORDER")
    left:SetTexture("Interface\\GuildBankFrame\\VertTile", nil, "REPEAT")
    left:SetVertTile(true)
    left:SetPoint("TOPLEFT", corners.TOPLEFT, "BOTTOMLEFT", -3, 0)
    left:SetPoint("BOTTOMLEFT", corners.BOTTOMLEFT, "TOPLEFT", -3, 0)
    local right = frame:CreateTexture(nil, "BORDER")
    right:SetTexture("Interface\\GuildBankFrame\\VertTile", nil, "REPEAT")
    right:SetVertTile(true)
    right:SetPoint("TOPRIGHT", corners.TOPRIGHT, "BOTTOMRIGHT", 4, 0)
    right:SetPoint("BOTTOMRIGHT", corners.BOTTOMRIGHT, "TOPRIGHT", 4, 0)
    local top = frame:CreateTexture(nil, "BORDER")
    top:SetTexture("Interface\\GuildBankFrame\\HorizTile", "REPEAT", nil)
    top:SetHorizTile(true)
    top:SetPoint("TOPLEFT", corners.TOPLEFT, "TOPRIGHT", 0, 3)
    top:SetPoint("TOPRIGHT", corners.TOPRIGHT, "TOPLEFT", 0, 3)
    local bottom = frame:CreateTexture(nil, "BORDER")
    bottom:SetTexture("Interface\\GuildBankFrame\\HorizTile", "REPEAT", nil)
    bottom:SetHorizTile(true)
    bottom:SetPoint("BOTTOMLEFT", corners.BOTTOMLEFT, "BOTTOMRIGHT", 0, -5)
    bottom:SetPoint("BOTTOMRIGHT", corners.BOTTOMRIGHT, "BOTTOMLEFT", 0, -5)
    local black = frame:CreateTexture(nil, "BACKGROUND")
    black:SetColorTexture(0, 0, 0, 1)
    black:SetPoint("TOPLEFT", corners.TOPLEFT, 4, -4)
    black:SetPoint("BOTTOMRIGHT", corners.BOTTOMRIGHT, -4, 3)
end

-- The thin gold frame of the guild bank's money (ThinGoldEdgeTemplate).
local function ThinGoldEdge(frame)
    local left = frame:CreateTexture(nil, "BACKGROUND")
    left:SetTexture(MONEY_FRAME)
    left:SetWidth(7)
    left:SetPoint("TOPLEFT")
    left:SetPoint("BOTTOMLEFT")
    left:SetTexCoord(0.953125, 0.9921875, 0, 0.296875)
    local right = frame:CreateTexture(nil, "BACKGROUND")
    right:SetTexture(MONEY_FRAME)
    right:SetWidth(7)
    right:SetPoint("TOPRIGHT")
    right:SetPoint("BOTTOMRIGHT")
    right:SetTexCoord(0, 0.0546875, 0, 0.296875)
    local middle = frame:CreateTexture(nil, "BACKGROUND")
    middle:SetTexture(MONEY_FRAME)
    middle:SetPoint("TOPLEFT", left, "TOPRIGHT")
    middle:SetPoint("BOTTOMRIGHT", right, "BOTTOMLEFT")
    middle:SetTexCoord(0, 0.9921875, 0.3125, 0.609375)
end

-- The clock's tooltip: when each thing was last seen.
local function ClockOnEnter(clock)
    local view = clock.view
    local bank = view.entry and view.entry.bank
    GameTooltip:SetOwner(clock, "ANCHOR_TOP")
    if not bank then
        return
    end
    if bank.bt then
        GameTooltip:AddLine(L["Bags seen %s ago"]:format(ns.Ago(bank.bt)), 1, 1, 1)
    end
    GameTooltip:AddLine(bank.kt and L["Bank seen %s ago"]:format(ns.Ago(bank.kt)) or L["Bank not seen yet"], 1, 1, 1)
    GameTooltip:AddLine(view.guildMoneyTime and L["Guild money seen %s ago"]:format(ns.Ago(view.guildMoneyTime))
        or L["Guild money not seen yet: open the guild bank once."], 1, 1, 1)
    GameTooltip:Show()
end

-- The view ----------------------------------------------------------------------------

local function SetupDropdown(dropdown, root)
    local view = dropdown.view
    for _, entry in ipairs(view.banks or {}) do
        root:CreateRadio(entry.name, function(guid)
            return guid == selectedBank
        end, function(guid)
            selectedBank = guid
            BankView.Refresh(view)
        end, entry.guid)
    end
end

function BankView.Create(parent)
    local view = CreateFrame("Frame", nil, parent)
    view:SetAllPoints()
    view.search = ""
    view.Columns, view.Bags = {}, {}

    -- At the top: the bank character, its bags, the search box.
    view.Dropdown = CreateFrame("DropdownButton", nil, view, "WowStyle1DropdownTemplate")
    view.Dropdown.view = view
    view.Dropdown:SetWidth(DROPDOWN_WIDTH)
    view.Dropdown:SetPoint("TOPLEFT", 4, -4)
    view.Search = CreateFrame("EditBox", nil, view, "SearchBoxTemplate")
    view.Search:SetSize(SEARCH_WIDTH, SEARCH_HEIGHT)
    view.Search:SetPoint("TOPRIGHT", -6, -5)
    view.Search:SetAutoFocus(false)
    view.Search:SetMaxLetters(30)
    view.Search:HookScript("OnTextChanged", function(box)
        view.search = strtrim(box:GetText() or ""):lower()
        BankView.Refresh(view)
    end)
    view.Bar = CreateFrame("Frame", nil, view)
    view.Bar:SetHeight(TOP_HEIGHT)
    view.Bar:SetPoint("LEFT", view.Dropdown, "RIGHT", 10, 0)
    view.Bar:SetPoint("RIGHT", view.Search, "LEFT", -12, 0)

    -- The slots, inside the guild bank's frame; they are laid out on Canvas,
    -- which is scaled so they all fit.
    view.Items = CreateFrame("Frame", nil, view)
    view.Items:SetPoint("TOPLEFT", 2, -(TOP_HEIGHT + 12))
    view.Items:SetPoint("BOTTOMRIGHT", -2, FOOTER_HEIGHT + 6)
    GuildBankBorder(view.Items)
    view.Items:SetScript("OnSizeChanged", function()
        BankView.Refresh(view)
    end)
    view.Canvas = CreateFrame("Frame", nil, view.Items)
    view.Canvas:SetSize(COLUMN_WIDTH, COLUMN_HEIGHT)

    -- At the bottom, in a thin gold frame: the guild bank's money, the
    -- clock, the character's money.
    view.Footer = CreateFrame("Frame", nil, view)
    view.Footer:SetPoint("BOTTOMLEFT", 2, 2)
    view.Footer:SetPoint("BOTTOMRIGHT", -2, 2)
    view.Footer:SetHeight(FOOTER_HEIGHT)
    ThinGoldEdge(view.Footer)
    view.GuildMoney = view.Footer:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    view.GuildMoney:SetPoint("LEFT", 8, 0)
    view.GuildMoney:SetJustifyH("LEFT")
    view.Money = view.Footer:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    view.Money:SetPoint("RIGHT", -8, 0)
    view.Money:SetJustifyH("RIGHT")
    view.Clock = CreateFrame("Button", nil, view.Footer)
    view.Clock.view = view
    view.Clock:SetSize(16, 16)
    view.Clock:SetPoint("CENTER")
    view.Clock.Icon = view.Clock:CreateTexture(nil, "ARTWORK")
    view.Clock.Icon:SetTexture(CLOCK_ICON)
    view.Clock.Icon:SetAllPoints()
    view.Clock:SetScript("OnEnter", ClockOnEnter)
    view.Clock:SetScript("OnLeave", GameTooltip_Hide)

    view.Empty = view:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    view.Empty:SetPoint("CENTER", view.Items, "CENTER")
    view.Empty:SetWidth(420)
    view.Empty:SetWordWrap(true)

    view.Dropdown:SetupMenu(SetupDropdown)
    return view
end

-- Lays out every column on the canvas, scaled so they all fit the frame.
local function LayOut(view, entry, cells)
    local count = entry and entry.bank and math.ceil(#cells / SLOTS_PER_COLUMN) or 0
    local width = (view.Items:GetWidth() or 0) - 2 * INSET
    local height = (view.Items:GetHeight() or 0) - 2 * INSET
    if width <= 0 or height <= 0 then
        width, height = DEFAULT_WIDTH - 2 * INSET, DEFAULT_HEIGHT - 2 * INSET
    end
    local across, rows, scale = BankView.Fit(count, width, height)
    local needWidth = across * COLUMN_WIDTH + (across - 1) * COLUMN_GAP
    view.layout = { across = across, rows = rows, scale = scale, columns = count, cells = cells }
    view.Canvas:SetScale(scale)
    view.Canvas:ClearAllPoints()
    -- Centred across, at the top; offsets are in the canvas's own scale.
    view.Canvas:SetPoint("TOPLEFT", view.Items, "TOPLEFT", (INSET + (width - needWidth * scale) / 2) / scale, -INSET / scale)
    for i = 1, count do
        local column = view.Columns[i]
        if not column then
            column = CreateColumn(view.Canvas)
            view.Columns[i] = column
        end
        local row, col = math.floor((i - 1) / across), (i - 1) % across
        column:ClearAllPoints()
        column:SetPoint("TOPLEFT", view.Canvas, "TOPLEFT", col * (COLUMN_WIDTH + COLUMN_GAP), -row * (COLUMN_HEIGHT + BAND_GAP))
        for slotIndex, slot in ipairs(column.Slots) do
            SetSlot(slot, cells[(i - 1) * SLOTS_PER_COLUMN + slotIndex], entry, view)
        end
        column:Show()
    end
    for i = count + 1, #view.Columns do
        view.Columns[i]:Hide()
    end
end

function BankView.Refresh(view)
    if view.refreshing then
        return
    end
    view.refreshing = true
    local guild = ns.Data.CurrentGuild(false)
    local banks = BankView.Banks(guild)
    local entry
    for _, bank in ipairs(banks) do
        if bank.guid == selectedBank then
            entry = bank
        end
    end
    entry = entry or banks[1]
    selectedBank = entry and entry.guid
    view.banks, view.entry = banks, entry
    view.Dropdown:GenerateMenu()
    view.Dropdown:SetEnabled(#banks > 0)

    local bank = entry and entry.bank
    if not entry then
        view.Empty:SetText(L["The guild has no bank characters: give a character the rank Banco, and log in with it with this addon."])
    elseif not bank then
        view.Empty:SetText(L["%s has not shared what it holds yet: log in with it with this addon."]:format(entry.name))
    else
        view.Empty:SetText("")
    end
    LayOut(view, entry, bank and BankView.Cells(bank) or {})
    LayOutBags(view, bank and BankView.BagSlots(bank) or {})

    local guildMoney, guildMoneyTime = ns.Bank.GuildMoney(guild)
    view.guildMoneyTime = guildMoneyTime
    view.GuildMoney:SetText(L["In the bank: %s"]:format(guildMoney and Money(guildMoney) or "-"))
    view.Money:SetText(bank and L["On the character: %s"]:format(Money(bank.m or 0)) or "")
    view.Search:SetShown(bank ~= nil)
    view.Footer:SetShown(bank ~= nil)
    view.Empty:SetShown(bank == nil)
    view.refreshing = false
end

function BankView.Init()
    -- Names and icons of items that were not loaded yet.
    local frame = CreateFrame("Frame")
    ns.RegisterEvents(frame, "ITEM_DATA_LOAD_RESULT", "GET_ITEM_INFO_RECEIVED")
    frame:SetScript("OnEvent", function()
        ns.Debounce("BankViewItems", 0.3, function()
            if ns.GuildTab.Refresh then
                ns.GuildTab.Refresh()
            end
        end)
    end)
end
