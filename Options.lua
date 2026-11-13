-- Options.lua: the addon's options, under Options > AddOns > Guild Bank
-- Alts (or /gbalts options):
--   - Guild Bank Alts: this client's own, the language of the addon's texts;
--   - Bank ranks, Permissions and Bank characters: the guild's (Ranks.lua),
--     shared with every member. Only the guild master changes them; the
--     others see them greyed out.
-- Each change of the guild's options is shared at once.
local _, ns = ...
local L = ns.L

local Options = {}
ns.Options = Options

local PAGE_WIDTH = 620
local ROW_HEIGHT = 26
local HEADER_HEIGHT = 34  -- a grid's column titles, on two lines if they must
local NAME_WIDTH = 170    -- the ranks' names, at the left of a grid
local COLUMN_WIDTH = 110  -- each of a grid's columns
local NATIVE_NAMES = {
    enUS = "English", deDE = "Deutsch", esES = "Español (España)", esMX = "Español (México)", frFR = "Français",
    itIT = "Italiano", koKR = "한국어", ptBR = "Português", ruRU = "Русский", zhCN = "简体中文", zhTW = "繁體中文",
}

local category
local pages = {}

-- Widgets -------------------------------------------------------------------------------

local function SetTooltip(widget, title, text)
    widget:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(title, 1, 1, 1)
        if text then
            GameTooltip:AddLine(text, 1, 0.82, 0, true)
        end
        GameTooltip:Show()
    end)
    widget:SetScript("OnLeave", GameTooltip_Hide)
end

local function Button(parent, text, onClick)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetText(text)
    button:SetSize(math.max(button:GetTextWidth() + 32, 90), 22)
    button:SetScript("OnClick", onClick)
    return button
end

-- A page: its heading and what it is about. page.Refresh copies the
-- options into its widgets; the settings panel calls it on showing it.
local function CreatePage(name, title, intro)
    local page = CreateFrame("Frame")
    page:Hide()
    page.Title = page:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    page.Title:SetPoint("TOPLEFT", 16, -16)
    page.Title:SetText(title)
    page.Intro = page:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    page.Intro:SetPoint("TOPLEFT", page.Title, "BOTTOMLEFT", 0, -8)
    page.Intro:SetWidth(PAGE_WIDTH)
    page.Intro:SetJustifyH("LEFT")
    page.Intro:SetText(intro)
    page.name = name
    function page:OnRefresh()
        self:Refresh()
    end
    pages[#pages + 1] = page
    return page
end

-- Under a guild page's intro: who may change the options, and when they
-- were last changed.
local function CreateStatus(page)
    page.Status = page:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    page.Status:SetPoint("TOPLEFT", page.Intro, "BOTTOMLEFT", 0, -10)
    page.Status:SetWidth(PAGE_WIDTH)
    page.Status:SetJustifyH("LEFT")
    return page.Status
end

local function StatusText()
    local options = ns.Ranks.Options()
    local who = ns.Ranks.MayEdit() and L["You are the guild master: your changes reach every member."]
        or L["Shared with the whole guild: only the guild master can change them."]
    local when = options and L["Last changed %s ago."]:format(ns.Ago(options.t))
        or L["The guild master has not changed them: the defaults apply."]
    return who .. " " .. when
end

-- A grid of check boxes: a row per guild rank (from the guild master's
-- down), a column per flag. columns: { { title, flag } }; get(rank) gives
-- the rank's flags, set(rank, flag, on) changes one.
local function CreateGrid(page, anchor, columns, get, set)
    local grid = CreateFrame("Frame", nil, page)
    grid:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -16)
    grid:SetSize(NAME_WIDTH + #columns * COLUMN_WIDTH, HEADER_HEIGHT)
    grid.Headers = {}
    local rankHeader = grid:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    rankHeader:SetPoint("BOTTOMLEFT", grid, "TOPLEFT", 0, -HEADER_HEIGHT + 4)
    rankHeader:SetText(L["Rank"])
    for index, column in ipairs(columns) do
        -- Bottom-aligned over its column, so one or two lines end alike.
        local header = grid:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        header:SetPoint("BOTTOMLEFT", grid, "TOPLEFT", NAME_WIDTH + (index - 1) * COLUMN_WIDTH, -HEADER_HEIGHT + 4)
        header:SetWidth(COLUMN_WIDTH - 8)
        header:SetJustifyH("LEFT")
        header:SetText(column[1])
        grid.Headers[index] = header
    end
    grid.Rows = {}
    function grid:Refresh()
        local ranks = ns.Ranks.GuildRanks()
        local editable = ns.Ranks.MayEdit()
        for index, rank in ipairs(ranks) do
            local row = self.Rows[index]
            if not row then
                row = { Checks = {} }
                row.Name = self:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
                row.Name:SetPoint("TOPLEFT", 0, -HEADER_HEIGHT - (index - 1) * ROW_HEIGHT - 4)
                row.Name:SetWidth(NAME_WIDTH - 8)
                row.Name:SetJustifyH("LEFT")
                row.Name:SetWordWrap(false)
                for column, spec in ipairs(columns) do
                    local check = CreateFrame("CheckButton", nil, self, "UICheckButtonTemplate")
                    check:SetSize(24, 24)
                    check:SetPoint("TOPLEFT", NAME_WIDTH + (column - 1) * COLUMN_WIDTH, -HEADER_HEIGHT - (index - 1) * ROW_HEIGHT)
                    check:SetMotionScriptsWhileDisabled(true)
                    check.flag = spec[2]
                    check:SetScript("OnClick", function(box)
                        set(row.rank, box.flag, box:GetChecked() == true)
                        Options.Refresh()
                    end)
                    row.Checks[column] = check
                end
                self.Rows[index] = row
            end
            row.rank = rank
            row.Name:SetText(rank.name)
            row.Name:Show()
            local master = rank.index == 0
            local flags = master and ns.Ranks.ALL or get(rank)
            for _, check in ipairs(row.Checks) do
                check:SetChecked(master or ns.Ranks.Has(flags, check.flag))
                check:SetEnabled(editable and not master)
                check:Show()
                if master then
                    SetTooltip(check, rank.name, L["The guild master may do everything."])
                else
                    check:SetScript("OnEnter", nil)
                end
            end
        end
        for index = #ranks + 1, #self.Rows do
            self.Rows[index].Name:Hide()
            for _, check in ipairs(self.Rows[index].Checks) do
                check:Hide()
            end
        end
        self:SetHeight(HEADER_HEIGHT + #ranks * ROW_HEIGHT)
    end
    return grid
end

-- Guild Bank Alts: the language ----------------------------------------------------------

local function CreateMainPage()
    local page = CreatePage("main", "Guild Bank Alts",
        L["The language of the addon's texts is this client's own. The guild's options (its bank ranks, what each rank may do, and who sees each bank character) are shared with every member, and only the guild master changes them."])
    local label = page:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    label:SetPoint("TOPLEFT", page.Intro, "BOTTOMLEFT", 0, -20)
    label:SetText(L["Language"])
    page.Language = CreateFrame("DropdownButton", nil, page, "WowStyle1DropdownTemplate")
    page.Language:SetWidth(220)
    page.Language:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -6)
    page.Language:SetupMenu(function(_, root)
        local function IsSelected(code)
            return code == (ns.db.settings.locale or "auto")
        end
        local function SetSelected(code)
            ns.db.settings.locale = code ~= "auto" and code or nil
            ns.SetLocale(ns.db.settings.locale)
            ns.Print(L["language set to %s."], ns.LOCALE)
        end
        root:CreateRadio(L["The client's language"], IsSelected, SetSelected, "auto")
        for _, code in ipairs(ns.LOCALES) do
            root:CreateRadio(NATIVE_NAMES[code] or code, IsSelected, SetSelected, code)
        end
    end)
    local note = page:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    note:SetPoint("TOPLEFT", page.Language, "BOTTOMLEFT", 0, -6)
    note:SetText(L["Texts already on screen change once shown again, or after /reload."])
    function page:Refresh()
        self.Language:GenerateMenu()
    end
    return page
end

-- Bank ranks ---------------------------------------------------------------------------------

-- Why a bank rank could not be added (Ranks.AddBankRank).
local function AddError(why)
    if why == "empty" then
        return L["Type a rank's name."]
    elseif why == "duplicate" then
        return L["That rank is already in the list."]
    elseif why == "full" then
        return L["The list is full: remove one first."]
    elseif why == "guildmaster" then
        return L["Only the guild master can change them."]
    end
    return L["That name is too long, or has characters a rank's name cannot have."]
end

local function CreateBankRanksPage()
    local page = CreatePage("ranks", L["Bank ranks"],
        L["Characters with one of these guild ranks are the guild's bank characters: they share what they hold, and members make requests to them. Names are compared ignoring case."])
    CreateStatus(page)
    page.Rows = {}
    page.List = CreateFrame("Frame", nil, page)
    page.List:SetPoint("TOPLEFT", page.Status, "BOTTOMLEFT", 0, -12)
    page.List:SetSize(PAGE_WIDTH, ROW_HEIGHT)
    page.Input = CreateFrame("EditBox", nil, page, "InputBoxTemplate")
    page.Input:SetSize(200, 22)
    page.Input:SetAutoFocus(false)
    page.Input:SetMaxBytes(ns.Pack.LIMITS.rankName + 1)
    page.Input:SetPoint("TOPLEFT", page.List, "BOTTOMLEFT", 6, -8)
    local function Add()
        local ok, why = ns.Ranks.AddBankRank(page.Input:GetText())
        page.Error:SetText(ok and "" or AddError(why))
        if ok then
            page.Input:SetText("")
            page.Input:ClearFocus()
        end
        Options.Refresh()
    end
    page.Add = Button(page, L["Add"], Add)
    page.Add:SetPoint("LEFT", page.Input, "RIGHT", 8, 0)
    page.Input:SetScript("OnEnterPressed", Add)
    page.Input:SetScript("OnEscapePressed", page.Input.ClearFocus)
    page.Error = page:CreateFontString(nil, "ARTWORK", "GameFontRedSmall")
    page.Error:SetPoint("TOPLEFT", page.Input, "BOTTOMLEFT", -6, -6)
    page.Error:SetWidth(PAGE_WIDTH)
    page.Error:SetJustifyH("LEFT")
    page.Ranks = page:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    page.Ranks:SetPoint("TOPLEFT", page.Error, "BOTTOMLEFT", 0, -10)
    page.Ranks:SetWidth(PAGE_WIDTH)
    page.Ranks:SetJustifyH("LEFT")
    function page:Refresh()
        self.Status:SetText(StatusText())
        local editable = ns.Ranks.MayEdit()
        local names = ns.Ranks.BankRanks()
        for index, name in ipairs(names) do
            local row = self.Rows[index]
            if not row then
                row = {}
                row.Name = self.List:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
                row.Name:SetPoint("TOPLEFT", 4, -(index - 1) * ROW_HEIGHT - 6)
                row.Name:SetWidth(240)
                row.Name:SetJustifyH("LEFT")
                row.Remove = Button(self.List, L["Remove"], function()
                    ns.Ranks.RemoveBankRank(row.name)
                    Options.Refresh()
                end)
                row.Remove:SetPoint("TOPLEFT", 260, -(index - 1) * ROW_HEIGHT)
                row.Remove:SetMotionScriptsWhileDisabled(true)
                self.Rows[index] = row
            end
            row.name = name
            row.Name:SetText(name)
            row.Name:Show()
            row.Remove:Show()
            row.Remove:SetEnabled(editable and #names > 1)
            if #names <= 1 then
                SetTooltip(row.Remove, L["Remove"], L["The guild needs at least one bank rank."])
            else
                row.Remove:SetScript("OnEnter", nil)
            end
        end
        for index = #names + 1, #self.Rows do
            self.Rows[index].Name:Hide()
            self.Rows[index].Remove:Hide()
        end
        self.List:SetHeight(math.max(#names, 1) * ROW_HEIGHT)
        self.Input:SetEnabled(editable)
        self.Add:SetEnabled(editable)
        local guildRanks = {}
        for _, rank in ipairs(ns.Ranks.GuildRanks()) do
            guildRanks[#guildRanks + 1] = rank.name
        end
        self.Ranks:SetText(#guildRanks > 0 and L["The guild's ranks: %s."]:format(table.concat(guildRanks, ", ")) or "")
    end
    return page
end

-- Permissions -------------------------------------------------------------------------------

local function CreatePermissionsPage()
    local Ranks = ns.Ranks
    local page = CreatePage("permissions", L["Permissions"],
        L["What each guild rank may do. The guild master may do everything. A request counts as accepted or rejected only if made by a rank that may."])
    CreateStatus(page)
    page.Grid = CreateGrid(page, page.Status, {
        { L["See the log"], Ranks.LOG },
        { L["Make requests"], Ranks.MAKE },
        { L["Accept requests"], Ranks.ACCEPT },
        { L["Reject requests"], Ranks.REJECT },
    }, function(rank)
        return Ranks.RankFlags(rank.name)
    end, function(rank, flag, on)
        Ranks.SetRankFlag(rank.name, flag, on)
    end)
    function page:Refresh()
        self.Status:SetText(StatusText())
        self.Grid:Refresh()
    end
    return page
end

-- Bank characters ---------------------------------------------------------------------------

local selectedBank   -- the bank character the page shows

local function BankCharacters()
    local list = {}
    for guid, member in pairs(ns.Roster.members) do
        if ns.Ranks.IsBank(guid) then
            list[#list + 1] = { guid = guid, name = member.n }
        end
    end
    table.sort(list, function(a, b)
        return a.name < b.name or (a.name == b.name and a.guid < b.guid)
    end)
    return list
end

local function CreateBanksPage()
    local Ranks = ns.Ranks
    local page = CreatePage("banks", L["Bank characters"],
        L["Which ranks see each bank character's items and money. A rank that may not see its items does not see the requests made to it either, nor its items in the log; one that may not see its money, nor its money in the log. The guild master sees all of them, and a bank character its own."])
    CreateStatus(page)
    page.Bank = CreateFrame("DropdownButton", nil, page, "WowStyle1DropdownTemplate")
    page.Bank:SetWidth(220)
    page.Bank:SetPoint("TOPLEFT", page.Status, "BOTTOMLEFT", 0, -12)
    page.Bank:SetupMenu(function(_, root)
        for _, entry in ipairs(page.banks or {}) do
            root:CreateRadio(entry.name, function(guid)
                return guid == selectedBank
            end, function(guid)
                selectedBank = guid
                page:Refresh()
            end, entry.guid)
        end
    end)
    page.None = page:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    page.None:SetPoint("TOPLEFT", page.Bank, "BOTTOMLEFT", 0, -12)
    page.None:SetText(L["The guild has no bank characters."])
    page.Grid = CreateGrid(page, page.Bank, {
        { L["Its items"], Ranks.ITEMS },
        { L["Its money"], Ranks.MONEY },
    }, function(rank)
        return Ranks.BankFlags(selectedBank, rank.name)
    end, function(rank, flag, on)
        Ranks.SetBankFlag(selectedBank, rank.name, flag, on)
    end)
    function page:Refresh()
        self.Status:SetText(StatusText())
        self.banks = BankCharacters()
        local found = false
        for _, entry in ipairs(self.banks) do
            found = found or entry.guid == selectedBank
        end
        if not found then
            selectedBank = self.banks[1] and self.banks[1].guid
        end
        self.Bank:GenerateMenu()
        self.Bank:SetShown(selectedBank ~= nil)
        self.None:SetShown(selectedBank == nil)
        self.Grid:SetShown(selectedBank ~= nil)
        if selectedBank then
            self.Grid:Refresh()
        end
    end
    return page
end

-- The panel ------------------------------------------------------------------------------

-- Copies the options into every page shown.
function Options.Refresh()
    for _, page in ipairs(pages) do
        if page:IsShown() then
            page:Refresh()
        end
    end
end

-- The pages, by name, for the tests.
function Options.Page(name)
    for _, page in ipairs(pages) do
        if page.name == name then
            return page
        end
    end
end

function Options.Init()
    if category or not Settings or not Settings.RegisterCanvasLayoutCategory then
        return
    end
    local main = CreateMainPage()
    category = Settings.RegisterCanvasLayoutCategory(main, "Guild Bank Alts")
    Settings.RegisterCanvasLayoutSubcategory(category, CreateBankRanksPage(), L["Bank ranks"])
    Settings.RegisterCanvasLayoutSubcategory(category, CreatePermissionsPage(), L["Permissions"])
    Settings.RegisterCanvasLayoutSubcategory(category, CreateBanksPage(), L["Bank characters"])
    Settings.RegisterAddOnCategory(category)
    -- The guild master's changes, or a new roster, while a page shows.
    ns.On("DataChanged", function()
        ns.Debounce("OptionsRefresh", 0.3, Options.Refresh)
    end)
    ns.On("RosterUpdated", function()
        ns.Debounce("OptionsRefresh", 0.3, Options.Refresh)
    end)
end

function Options.Open()
    -- Settings.OpenToCategory may go through a restricted call on this
    -- client, so success is checked a moment later.
    local ok = category and pcall(Settings.OpenToCategory, category:GetID())
    C_Timer.After(0.3, function()
        if not ok or not (SettingsPanel and SettingsPanel:IsShown()) then
            ns.Print(L["open the game menu, then Options > AddOns > Guild Bank Alts."])
        end
    end)
end
