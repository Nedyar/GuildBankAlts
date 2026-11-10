-- RequestForm.lua: the dialog that makes a withdrawal request, opened by
-- right-clicking an item of a guild bank character (BankView.lua): how
-- many, how the items are to be delivered (in person, or by mail with the
-- postage charged cash on delivery), and an optional note for the bank.
local _, ns = ...
local L = ns.L

local RequestForm = {}
ns.RequestForm = RequestForm

local WIDTH, HEIGHT = 380, 342
local DESCRIPTION_WIDTH = 300

local form
local current       -- { bank, itemString, available, delivery }
local lastDelivery  -- the last delivery chosen, the next form's default

local function Close()
    if form then
        form:Hide()
    end
end

local function SetDelivery(delivery)
    current.delivery = delivery
    form.InPerson:SetChecked(delivery == ns.Requests.IN_PERSON)
    form.ByMail:SetChecked(delivery == ns.Requests.BY_MAIL)
end

local function Submit()
    local quantity = tonumber(form.Quantity:GetText() or "")
    if not quantity or quantity < 1 or quantity ~= math.floor(quantity) then
        form.Error:SetText(L["Enter how many you want."])
        return
    elseif quantity > current.available then
        form.Error:SetText(L["The bank holds only %d."]:format(current.available))
        return
    end
    local id, reason = ns.Requests.Create(current.bank, current.itemString, quantity, form.Note:GetText(), current.delivery)
    if not id then
        local reasons = {
            guild = L["you are not in a guild (or the guild has not loaded yet)."],
            bank = L["That character is no longer a guild bank character."],
            quantity = L["Enter how many you want."],
            delivery = L["Choose how you want the items."],
            full = L["You have too many requests: delete some first."],
        }
        form.Error:SetText(reasons[reason] or "")
        return
    end
    lastDelivery = current.delivery
    ns.Print(L["request sent: %s x%d."], ns.BankView.ItemName(current.itemString), quantity)
    Close()
    if ns.GuildTab.Refresh then
        ns.GuildTab.Refresh()
    end
end

local function Label(text, anchor, y)
    local label = form:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    label:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, y)
    label:SetText(text)
    return label
end

-- A delivery choice: a radio button, its name, and what it means below.
local function Choice(text, description, delivery)
    local button = CreateFrame("CheckButton", nil, form, "UIRadioButtonTemplate")
    button:SetSize(24, 24)
    button.Label = form:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    button.Label:SetPoint("LEFT", button, "RIGHT", 2, 0)
    button.Label:SetText(text)
    button:SetHitRectInsets(0, -(button.Label:GetStringWidth() + 2), 0, 0)
    button.Description = form:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    button.Description:SetPoint("TOPLEFT", button.Label, "BOTTOMLEFT", 0, -2)
    button.Description:SetWidth(DESCRIPTION_WIDTH)
    button.Description:SetJustifyH("LEFT")
    button.Description:SetText(description)
    button:SetScript("OnClick", function()
        SetDelivery(delivery)
    end)
    return button
end

local function Create()
    form = CreateFrame("Frame", "GuildBankAltsRequestForm", UIParent, "PortraitFrameTemplate")
    form:SetSize(WIDTH, HEIGHT)
    form:SetPoint("CENTER")
    form:SetFrameStrata("DIALOG")
    form:SetMovable(true)
    form:EnableMouse(true)
    form:RegisterForDrag("LeftButton")
    form:SetScript("OnDragStart", form.StartMoving)
    form:SetScript("OnDragStop", form.StopMovingOrSizing)
    form:SetPortraitToAsset("Interface\\Icons\\INV_Misc_Bag_10")
    form:SetTitle(L["Request from the guild bank"])
    tinsert(UISpecialFrames, form:GetName())

    -- The item, pointable and linkable.
    form.Item = CreateFrame("Button", nil, form)
    form.Item:SetSize(36, 36)
    form.Item:SetPoint("TOPLEFT", 62, -32)
    form.Item.Icon = form.Item:CreateTexture(nil, "ARTWORK")
    form.Item.Icon:SetAllPoints()
    form.Item:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if not pcall(GameTooltip.SetHyperlink, GameTooltip, current.itemString) then
            GameTooltip:SetText(ns.BankView.ItemName(current.itemString), 1, 1, 1)
        end
        GameTooltip:Show()
    end)
    form.Item:SetScript("OnLeave", GameTooltip_Hide)
    form.ItemName = form:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    form.ItemName:SetPoint("TOPLEFT", form.Item, "TOPRIGHT", 8, -1)
    form.ItemName:SetPoint("RIGHT", -12, 0)
    form.ItemName:SetJustifyH("LEFT")
    form.ItemName:SetWordWrap(false)
    form.From = form:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    form.From:SetPoint("TOPLEFT", form.ItemName, "BOTTOMLEFT", 0, -4)
    form.From:SetJustifyH("LEFT")

    local quantityLabel = Label(L["Quantity"], form.Item, -16)
    quantityLabel:SetPoint("LEFT", form, "LEFT", 20, 0)
    form.Quantity = CreateFrame("EditBox", nil, form, "InputBoxTemplate")
    form.Quantity:SetSize(70, 22)
    form.Quantity:SetPoint("LEFT", quantityLabel, "RIGHT", 12, 0)
    form.Quantity:SetAutoFocus(false)
    form.Quantity:SetNumeric(true)
    form.Quantity:SetMaxLetters(5)
    form.Quantity:SetTextInsets(0, 6, 0, 0)
    form.Available = form:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    form.Available:SetPoint("LEFT", form.Quantity, "RIGHT", 8, 0)

    local noteLabel = Label(L["Note (optional)"], quantityLabel, -16)
    form.Note = CreateFrame("EditBox", nil, form, "InputBoxTemplate")
    form.Note:SetHeight(22)
    form.Note:SetPoint("TOPLEFT", noteLabel, "BOTTOMLEFT", 6, -4)
    form.Note:SetPoint("RIGHT", -20, 0)
    form.Note:SetAutoFocus(false)
    form.Note:SetMaxBytes(ns.Pack.LIMITS.note + 1)

    -- How the items are to be delivered.
    local deliveryLabel = Label(L["Delivery"], noteLabel, -40)
    form.InPerson = Choice(L["In person"],
        L["You go to the bank of the city where the bank character is to collect them. Free."],
        ns.Requests.IN_PERSON)
    form.InPerson:SetPoint("TOPLEFT", deliveryLabel, "BOTTOMLEFT", -2, -4)
    form.ByMail = Choice(L["By mail"],
        L["The bank character mails them to you: %s per stack, charged cash on delivery."]
            :format(ns.BankView.Coin(ns.Requests.MAIL_FEE, "Copper")),
        ns.Requests.BY_MAIL)
    form.ByMail:SetPoint("TOPLEFT", form.InPerson, "BOTTOMLEFT", 0, -26)

    form.Error = form:CreateFontString(nil, "ARTWORK", "GameFontRedSmall")
    form.Error:SetPoint("BOTTOMLEFT", 20, 40)
    form.Error:SetPoint("RIGHT", -20, 0)
    form.Error:SetJustifyH("LEFT")

    form.Cancel = CreateFrame("Button", nil, form, "UIPanelButtonTemplate")
    form.Cancel:SetSize(100, 22)
    form.Cancel:SetPoint("BOTTOMRIGHT", -12, 12)
    form.Cancel:SetText(CANCEL or "Cancel")
    form.Cancel:SetScript("OnClick", Close)
    form.Submit = CreateFrame("Button", nil, form, "UIPanelButtonTemplate")
    form.Submit:SetSize(100, 22)
    form.Submit:SetPoint("RIGHT", form.Cancel, "LEFT", -6, 0)
    form.Submit:SetText(L["Request"])
    form.Submit:SetScript("OnClick", Submit)
    for _, box in ipairs({ form.Quantity, form.Note }) do
        box:SetScript("OnEnterPressed", Submit)
        box:SetScript("OnEscapePressed", Close)
    end
end

-- Opens the form for an item a bank character holds (available of it).
function RequestForm.Open(bank, itemString, available)
    if not form then
        Create()
    end
    current = { bank = bank, itemString = itemString, available = math.max(available or 0, 1) }
    SetDelivery(lastDelivery or ns.Requests.IN_PERSON)
    local name, _, quality, icon = ns.BankView.ItemInfo(itemString)
    form.Item.Icon:SetTexture(icon)
    form.ItemName:SetText(name)
    local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    if color then
        form.ItemName:SetTextColor(color.r, color.g, color.b)
    else
        form.ItemName:SetTextColor(1, 1, 1)
    end
    local guild = ns.Data.CurrentGuild(false)
    form.From:SetText(L["From the bank of %s"]:format(ns.Data.NameOf(bank, guild and guild.members[bank])))
    form.Available:SetText(L["of %d"]:format(current.available))
    form.Quantity:SetText("1")
    form.Note:SetText("")
    form.Error:SetText("")
    form:Show()
    form.Quantity:SetFocus()
    form.Quantity:HighlightText()
end

-- The form's state, for the tests.
function RequestForm.Frame()
    return form
end
