-- GuildTab.lua: a "Guild Bank" tab on the guild window, under Blizzard's
-- own side tabs (Chat, Roster, Guild Info...). Its subtabs:
--   - Bank: what the guild's bank characters hold (BankView.lua);
--   - Requests: the members' withdrawal requests (RequestList.lua).
--
-- It only hooks and reads Blizzard's frames, as Guild Professions & Recipes
-- does with its own tab. It never changes the guild window's display mode,
-- which would taint the window. Instead, it makes Blizzard's view invisible
-- while its panel is open, and closes as soon as one of Blizzard's tabs is
-- clicked.
--
-- Other addons' panels on the guild window. Every addon that adds a side
-- tab with a panel like this one registers in the shared list
-- GuildWindowAddonPanels: { { id, order, tab, Close }... }. Opening a
-- panel closes the others (Close returns the Blizzard tab that was
-- selected before them), and each tab goes under those of a lower order
-- (Guild Professions & Recipes is 10, this addon 20). Neither addon needs
-- the other: alone, each works the same.
local _, ns = ...
local L = ns.L

local GuildTab = {}
ns.GuildTab = GuildTab

local ID, ORDER = "GuildBankAlts", 20
local PANELS = "GuildWindowAddonPanels"
local ICON = "Interface\\Icons\\INV_Misc_Bag_10"
local TAB_GAP = 20          -- between Blizzard's tabs
local TAB_LEVEL = 510       -- Blizzard's tabs' frame level
local PAGE_LEVEL = 1250     -- over everything in the content (the chat's edit box is at 1200)
-- Blizzard's tabs, top to bottom.
local BLIZZARD_TABS = { "ChatTab", "RosterTab", "GuildBenefitsTab", "GuildInfoTab", "GuildPreferredPlaySettingsTab" }
-- Guild Professions & Recipes before 0.9.1 adds its tab without registering.
local OLD_TABS = { { name = "GuildProfessionsRecipesGuildTab", order = 10 } }

local communities, tab, page
local remembered     -- the Blizzard tab that was selected when our panel opened
local hiddenChatBar  -- the chat's scroll bar, while our panel hides it
local faded = {}     -- [Blizzard frame] = its alpha, while our panel hides it
local SUBTABS = { "bank", "requests" }
local selected = 1
-- The request list's filters.
local onlyOpen, onlyMine = false, false

-- The shared list -------------------------------------------------------------------

local function Panels()
    local panels = _G[PANELS]
    if type(panels) ~= "table" then
        panels = {}
        _G[PANELS] = panels
    end
    return panels
end

local function Registered(frame)
    for _, entry in ipairs(Panels()) do
        if entry.tab == frame then
            return true
        end
    end
    return false
end

-- The tab ours goes under: the lowest of Blizzard's shown, or another
-- addon's of a lower order.
local function TabAbove()
    local above, aboveOrder
    for _, entry in ipairs(Panels()) do
        if entry.id ~= ID and type(entry.order) == "number" and entry.order < ORDER and entry.tab
                and (not aboveOrder or entry.order > aboveOrder) then
            above, aboveOrder = entry.tab, entry.order
        end
    end
    for _, old in ipairs(OLD_TABS) do
        local frame = _G[old.name]
        if frame and not Registered(frame) and old.order < ORDER and (not aboveOrder or old.order > aboveOrder) then
            above, aboveOrder = frame, old.order
        end
    end
    return above
end

-- Subtabs ---------------------------------------------------------------------------

local function UpdateSubTabs()
    local waiting = ns.RequestList.WaitingForMe()
    local texts = {
        L["Bank"],
        waiting > 0 and ("%s (%d)"):format(L["Requests"], waiting) or L["Requests"],
    }
    for i, subtab in ipairs(page.SubTabs.Tabs) do
        subtab:SetText(texts[i])
        PanelTemplates_TabResize(subtab, 0)
    end
    PanelTemplates_SetTab(page.SubTabs, selected)
end

local function RefreshPage()
    if not page or not page:IsShown() then
        return
    end
    UpdateSubTabs()
    local bank = SUBTABS[selected] == "bank"
    page.Bank:SetShown(bank)
    page.Hint:SetShown(bank)
    page.Requests:SetShown(not bank)
    for _, check in ipairs({ page.OnlyOpen, page.OnlyMine }) do
        check:SetShown(not bank)
        check.Label:SetShown(not bank)
    end
    if bank then
        ns.BankView.Refresh(page.Bank)
    else
        ns.RequestList.Show(page.Requests, onlyOpen, onlyMine)
    end
end
GuildTab.Refresh = RefreshPage

local function SelectSubTab(index)
    if SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_TAB then
        PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
    end
    selected = index
    RefreshPage()
end

-- A filter of the request list: a checkbox whose label takes clicks too.
local function FilterCheck(text, checked, onClick)
    local check = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")
    check:SetSize(22, 22)
    check:SetChecked(checked)
    check.Label = page:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    check.Label:SetPoint("LEFT", check, "RIGHT", 2, 0)
    check.Label:SetText(text)
    check:SetHitRectInsets(0, -(check.Label:GetStringWidth() + 2), 0, 0)
    check:SetScript("OnClick", function(self)
        onClick(self:GetChecked() == true)
        RefreshPage()
    end)
    return check
end

-- Above the window's inset, where Guild Info has its headings.
local function CreateSubTabs()
    local holder = CreateFrame("Frame", nil, page)
    holder:SetAllPoints(page.Content)
    local tabs = {}
    for i in ipairs(SUBTABS) do
        local subtab = CreateFrame("Button", nil, holder, "PanelTopTabButtonTemplate")
        subtab:SetID(i)
        if i == 1 then
            subtab:SetPoint("BOTTOMLEFT", page.Content, "TOPLEFT", 4, -2)
        else
            subtab:SetPoint("LEFT", tabs[i - 1], "RIGHT", 2, 0)
        end
        subtab:SetScript("OnClick", function(self)
            SelectSubTab(self:GetID())
        end)
        tabs[i] = subtab
    end
    holder.Tabs = tabs
    PanelTemplates_SetNumTabs(holder, #tabs)
    page.SubTabs = holder
end

-- The panel ------------------------------------------------------------------------

-- Blizzard's view is made invisible while our panel is open (SetAlpha runs
-- none of its code), so the window's own background, inset and borders show
-- around our panel exactly as in its other tabs. These are every piece its
-- views show, but the communities list.
local function ContentFrames()
    local names = { PostingExpirationText = true }
    for _, mode in pairs(COMMUNITIES_FRAME_DISPLAY_MODES or {}) do
        for _, name in ipairs(mode) do
            names[name] = true
        end
    end
    names.CommunitiesList, names.CommunitiesListDropdown = nil, nil
    local list = {}
    for name in pairs(names) do
        local subframe = communities[name]
        if type(subframe) == "table" and subframe.SetAlpha then
            list[#list + 1] = subframe
        end
    end
    return list
end

local function FadeContent()
    for _, subframe in ipairs(ContentFrames()) do
        if faded[subframe] == nil then
            faded[subframe] = subframe:GetAlpha()
            subframe:SetAlpha(0)
        end
    end
end

local function RestoreContent()
    for subframe, alpha in pairs(faded) do
        subframe:SetAlpha(alpha)
    end
    wipe(faded)
end

-- restore: put back the selection on Blizzard's tab that was selected; not
-- when one of Blizzard's tabs was just clicked, which marks itself, nor
-- when another addon's panel takes over.
local function HidePage(restore)
    if not page:IsShown() then
        return
    end
    page:Hide()
    tab:SetChecked(false)
    if restore and remembered then
        remembered:SetChecked(true)
    end
    remembered = nil
    if hiddenChatBar then
        hiddenChatBar:Show()
        hiddenChatBar = nil
    end
    RestoreContent()
end

-- For the shared list: closes our panel for another addon's, and gives it
-- the Blizzard tab that was selected before ours.
local function Close()
    if not page or not page:IsShown() then
        return nil
    end
    local before = remembered
    HidePage(false)
    return before
end

local function ShowPage()
    if page:IsShown() then
        return
    end
    remembered = nil
    for _, entry in ipairs(Panels()) do
        if entry.id ~= ID and type(entry.Close) == "function" then
            local ok, before = pcall(entry.Close)
            remembered = remembered or (ok and before or nil)
        end
    end
    for _, key in ipairs(BLIZZARD_TABS) do
        local other = communities[key]
        if other then
            if other:GetChecked() then
                remembered = remembered or other
            end
            other:SetChecked(false)
        end
    end
    tab:SetChecked(true)
    FadeContent()
    -- The chat's scroll bar is on a higher layer (HIGH strata) than the
    -- whole window: invisible with the chat, it would still take clicks.
    local chatBar = communities.Chat and communities.Chat.ScrollBar
    if chatBar and chatBar:IsShown() then
        chatBar:Hide()
        hiddenChatBar = chatBar
    end
    page:Show()
    RefreshPage()
end

local function CreatePage()
    -- It draws nothing of its own: it holds our frames and keeps the mouse
    -- off Blizzard's invisible view, from right of the communities list's
    -- scroll bar to the window's edges.
    page = CreateFrame("Frame", "GuildBankAltsGuildPanel", communities)
    page:SetFrameLevel(PAGE_LEVEL)
    page:SetPoint("TOPLEFT", communities.CommunitiesList, "TOPRIGHT", 18, 0)
    page:SetPoint("BOTTOMRIGHT", communities, "BOTTOMRIGHT", -4, 4)
    page:EnableMouse(true)

    -- Inside the window's inset, where the game puts its Guild Info panel.
    page.Content = CreateFrame("Frame", nil, page)
    page.Content:SetPoint("TOPLEFT", communities.CommunitiesList, "TOPRIGHT", 24, -40)
    page.Content:SetPoint("BOTTOMRIGHT", communities, "BOTTOMRIGHT", -12, 30)

    page.Bank = ns.BankView.Create(page.Content)
    page.Requests = ns.RequestList.Create(page.Content)
    ns.RequestList.onChange = RefreshPage
    CreateSubTabs()

    -- Under the inset, where Guild Info has its buttons: a hint, with what
    -- the mail costs, or the request list's filters.
    page.Hint = page:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    page.Hint:SetPoint("LEFT", page.Content, "BOTTOMLEFT", 4, -15)
    page.Hint:SetPoint("RIGHT", page.Content, "BOTTOMRIGHT", -4, -15)
    page.Hint:SetJustifyH("LEFT")
    page.Hint:SetText(L["Right-click an item to request it."] .. "\n"
        .. L["By mail: %s per stack, cash on delivery. In person: free."]
            :format(ns.BankView.Coin(ns.Requests.MAIL_FEE, "Copper")))
    page.OnlyOpen = FilterCheck(L["Only open requests"], onlyOpen, function(checked)
        onlyOpen = checked
    end)
    page.OnlyOpen:SetPoint("LEFT", page.Content, "BOTTOMLEFT", 0, -15)
    page.OnlyMine = FilterCheck(L["Only mine"], onlyMine, function(checked)
        onlyMine = checked
    end)
    page.OnlyMine:SetPoint("LEFT", page.OnlyOpen.Label, "RIGHT", 16, 0)
    page:Hide()
end

-- The tab ---------------------------------------------------------------------------

-- Blizzard's notification mark, as its Roster tab shows for applicants:
-- while requests wait for us, as a bank character.
local function UpdateBadge()
    if tab then
        tab.Badge:SetShown(ns.RequestList.WaitingForMe() > 0)
    end
end

-- Runs after Blizzard lays out its tabs. Ours goes under the lowest one
-- (or another addon's), and only while Guild Info shows: on the guild, in
-- the views with tabs.
local function Update()
    local last
    for _, key in ipairs(BLIZZARD_TABS) do
        local other = communities[key]
        if other and other:IsShown() then
            last = other
        end
    end
    local guildInfo = communities.GuildInfoTab
    local show = last ~= nil and guildInfo ~= nil and guildInfo:IsShown()
    tab:SetShown(show)
    if show then
        tab:ClearAllPoints()
        tab:SetPoint("TOPLEFT", TabAbove() or last, "BOTTOMLEFT", 0, -TAB_GAP)
    else
        HidePage(true)
    end
end

local function Setup()
    communities = CommunitiesFrame
    if tab or not (communities and communities.UpdateCommunitiesTabs and communities.CommunitiesList) then
        return
    end
    CreatePage()
    tab = CreateFrame("CheckButton", "GuildBankAltsGuildTab", communities, "RightSideTabTemplate")
    tab:SetFrameLevel(TAB_LEVEL)
    tab.Icon:SetTexture(ICON)
    tab.tooltip = L["Guild Bank"]
    tab.Badge = tab:CreateTexture(nil, "OVERLAY")
    tab.Badge:SetAtlas("communities-icon-notification", true)
    tab.Badge:SetPoint("CENTER", tab, "TOPRIGHT", 0, 0)
    tab.Badge:Hide()
    -- After the template's own click (its sound, and marking itself).
    tab:HookScript("OnClick", ShowPage)
    tab:Hide()
    table.insert(Panels(), { id = ID, order = ORDER, tab = tab, Close = Close })
    hooksecurefunc(communities, "UpdateCommunitiesTabs", Update)
    -- One of Blizzard's tabs was clicked (or the window changed its view).
    hooksecurefunc(communities, "SetDisplayMode", function()
        HidePage(false)
    end)
    communities:HookScript("OnHide", function()
        HidePage(true)
    end)
    ns.On("DataChanged", function()
        ns.Debounce("GuildTabRefresh", 0.3, function()
            UpdateBadge()
            RefreshPage()
        end)
    end)
    ns.On("RosterUpdated", function()
        ns.Debounce("GuildTabRefresh", 0.3, function()
            UpdateBadge()
            RefreshPage()
        end)
    end)
    Update()
    UpdateBadge()
end

function GuildTab.Init()
    EventUtil.ContinueOnAddOnLoaded("Blizzard_Communities", Setup)
end
