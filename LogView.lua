-- LogView.lua: the Log subtab of the Guild Bank tab (GuildTab.lua): what came
-- into the guild's bank and went out of it (Log.lua), newest first, one line
-- per entry like the game's guild bank log, in its words: "Name deposited
-- [Item] x 5 ( 3 hours ago )". A tag in front tells where each entry
-- belongs: the bank character, in blue, or the guild vault (the game's own
-- guild bank), in green; after it, how the items went (by trade, by
-- mail...) or the vault's tab.
local _, ns = ...
local L = ns.L

local LogView = {}
ns.LogView = LogView

local ROW_HEIGHT = 18
local EMPTY  -- what the list says while it has no lines (LogView.Create)
local BANK_COLOR, VAULT_COLOR, NOTE_COLOR = "ff66bbff", "ff40ff40", "ff808080"

-- The game's texts (GlobalStrings), in the client's language as in its own
-- log; these stand in where the client lacks one.
local FALLBACK = {
    GUILDBANK_DEPOSIT_FORMAT = "%s deposited %s",
    GUILDBANK_WITHDRAW_FORMAT = "%s |cffff2020withdrew|r %s",
    GUILDBANK_MOVE_FORMAT = "%s moved %s x %d from %s to %s",
    GUILDBANK_LOG_QUANTITY = " x %d",
    GUILDBANK_DEPOSIT_MONEY_FORMAT = "%s deposited %s",
    GUILDBANK_WITHDRAW_MONEY_FORMAT = "%s |cffff2020withdrew|r %s",
    GUILDBANK_REPAIR_MONEY_FORMAT = "%s withdrew %s for repairs",
    GUILDBANK_WITHDRAWFORTAB_MONEY_FORMAT = "%s withdrew %s to purchase a guild bank tab",
    GUILDBANK_BUYTAB_MONEY_FORMAT = "%s purchased a guild bank tab for %s",
    GUILDBANK_UNLOCKTAB_FORMAT = "%s unlocked a guild bank tab",
    GUILDBANK_AWARD_MONEY_SUMMARY_FORMAT = "A total of %s was deposited last week",
    GUILDBANK_GUILD_RENAME_PURCHASE = "%s purchased a guild rename for %s",
    GUILDBANK_GUILD_RENAME_REFUND = "%s was refunded %s for a guild rename",
    GUILD_BANK_LOG_TIME = "( %s ago )",
    LASTONLINE_MINS = "< an hour",
    LASTONLINE_HOURS = "%d hours",
    LASTONLINE_DAYS = "%d days",
    LASTONLINE_MONTHS = "%d months",
    LASTONLINE_YEARS = "%d years",
    UNKNOWN = "Unknown",
}

local function Text(name, ...)
    local format = _G[name]
    if type(format) == "string" then
        local ok, text = pcall(string.format, format, ...)
        if ok then
            return text
        end
    end
    return FALLBACK[name]:format(...)
end

local function Color(color, text)
    return ("|c%s%s|r"):format(color, text)
end

-- How long ago, as the game's log says it: in hours, days, months or years.
local function Ago(t)
    local hours = math.floor(math.max(ns.Now() - t, 0) / 3600)
    local days = math.floor(hours / 24)
    if days >= 365 then
        return Text("LASTONLINE_YEARS", math.floor(days / 365))
    elseif days >= 30 then
        return Text("LASTONLINE_MONTHS", math.floor(days / 30))
    elseif days > 0 then
        return Text("LASTONLINE_DAYS", days)
    elseif hours > 0 then
        return Text("LASTONLINE_HOURS", hours)
    end
    return Text("LASTONLINE_MINS")
end

-- Money with only the coins it has (all three in the bank's footer).
local function Money(copper)
    local gold, silver, coins = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local parts = {}
    if gold > 0 then
        parts[#parts + 1] = ns.BankView.Coin(BreakUpLargeNumbers and BreakUpLargeNumbers(gold) or gold, "Gold")
    end
    if silver > 0 then
        parts[#parts + 1] = ns.BankView.Coin(silver, "Silver")
    end
    if coins > 0 or #parts == 0 then
        parts[#parts + 1] = ns.BankView.Coin(coins, "Copper")
    end
    return table.concat(parts, " ")
end
LogView.Money = Money

local function ItemString(entry)
    return entry.s or ("item:" .. entry.i)
end

-- The item's link, or its name in brackets until the client has it.
local function ItemText(entry)
    local name, link = ns.BankView.ItemInfo(ItemString(entry))
    return link or ("[" .. name .. "]")
end

local function Who(entry)
    local name = entry.w ~= "" and entry.w or Text("UNKNOWN")
    return (NORMAL_FONT_COLOR_CODE or "|cffffd200") .. name .. (FONT_COLOR_CODE_CLOSE or "|r")
end

local function Via(entry)
    local via = entry.v
    if via == ns.Log.TRADE then
        return L["by trade"]
    elseif via == ns.Log.MAIL then
        return L["by mail"]
    elseif via == ns.Log.COD then
        return L["cash on delivery"]
    elseif via == ns.Log.RETURNED then
        return L["returned mail"]
    elseif via == ns.Log.VAULT then
        return L["at the guild vault"]
    elseif via == ns.Log.POSTAGE then
        return L["postage of a mail to %s"]:format(entry.w ~= "" and entry.w or Text("UNKNOWN"))
    end
end

-- A bank character's entry: what it got (deposited) or gave (withdrew).
-- Money it took from the guild vault, or put into it, is told as the
-- vault's own log does: the bank character withdrew or deposited it.
local function BankText(line)
    local entry = line.entry
    local deposit = entry.a == ns.Log.IN
    local text
    local own = (NORMAL_FONT_COLOR_CODE or "|cffffd200") .. ns.Data.NameOf(line.bank, line.record) .. (FONT_COLOR_CODE_CLOSE or "|r")
    if entry.v == ns.Log.VAULT and entry.m then
        text = Text(deposit and "GUILDBANK_WITHDRAW_MONEY_FORMAT" or "GUILDBANK_DEPOSIT_MONEY_FORMAT", own, Money(entry.m))
    elseif entry.v == ns.Log.POSTAGE and entry.m then
        -- The postage goes to the game, paid by the bank character.
        text = Text("GUILDBANK_WITHDRAW_MONEY_FORMAT", own, Money(entry.m))
    elseif entry.i then
        local what = ItemText(entry) .. (entry.n > 1 and Text("GUILDBANK_LOG_QUANTITY", entry.n) or "")
        text = Text(deposit and "GUILDBANK_DEPOSIT_FORMAT" or "GUILDBANK_WITHDRAW_FORMAT", Who(entry), what)
    else
        text = Text(deposit and "GUILDBANK_DEPOSIT_MONEY_FORMAT" or "GUILDBANK_WITHDRAW_MONEY_FORMAT", Who(entry), Money(entry.m))
    end
    return text, Via(entry)
end

local TYPES = ns.Pack.VAULT_TYPES
local MONEY_FORMATS = {
    [TYPES.deposit] = "GUILDBANK_DEPOSIT_MONEY_FORMAT",
    [TYPES.withdraw] = "GUILDBANK_WITHDRAW_MONEY_FORMAT",
    [TYPES.repair] = "GUILDBANK_REPAIR_MONEY_FORMAT",
    [TYPES.withdrawForTab] = "GUILDBANK_WITHDRAWFORTAB_MONEY_FORMAT",
    [TYPES.buyTab] = "GUILDBANK_BUYTAB_MONEY_FORMAT",
    [TYPES.buyRename] = "GUILDBANK_GUILD_RENAME_PURCHASE",
    [TYPES.refundRename] = "GUILDBANK_GUILD_RENAME_REFUND",
}

local function TabName(tabs, tab)
    local name = tab and tabs[tab]
    if name and name ~= "" then
        return name
    end
    return tab and ("#" .. tab) or "?"
end

-- A guild vault entry, as the game's own log words it.
local function VaultText(entry, tabs)
    if entry.i then
        if entry.y == TYPES.move then
            return Text("GUILDBANK_MOVE_FORMAT", Who(entry), ItemText(entry), entry.n, TabName(tabs, entry.b), TabName(tabs, entry.d))
        end
        local what = ItemText(entry) .. (entry.n > 1 and Text("GUILDBANK_LOG_QUANTITY", entry.n) or "")
        local text = Text(entry.y == TYPES.withdraw and "GUILDBANK_WITHDRAW_FORMAT" or "GUILDBANK_DEPOSIT_FORMAT", Who(entry), what)
        -- The tab, when the vault has more than one.
        return text, #tabs > 1 and TabName(tabs, entry.b) or nil
    end
    if entry.y == TYPES.buyTab and entry.m == 0 then
        return Text("GUILDBANK_UNLOCKTAB_FORMAT", Who(entry))
    elseif entry.y == TYPES.depositSummary then
        return Text("GUILDBANK_AWARD_MONEY_SUMMARY_FORMAT", Money(entry.m))
    end
    return Text(MONEY_FORMATS[entry.y] or "GUILDBANK_DEPOSIT_MONEY_FORMAT", Who(entry), Money(entry.m))
end

-- Where a line belongs: its bank character's name, or the guild vault; and
-- its tag's color.
local function Source(line)
    if line.source == "bank" then
        return ns.Data.NameOf(line.bank, line.record), BANK_COLOR
    end
    return L["Guild vault"], VAULT_COLOR
end

-- A line of the log (see Log.Lines), as shown; withoutTime: without how
-- long ago.
function LogView.LineText(line, withoutTime)
    local name, color = Source(line)
    local tag = Color(color, "[" .. name .. "]")
    local text, note
    if line.source == "bank" then
        text, note = BankText(line)
    else
        text, note = VaultText(line.entry, line.tabs)
    end
    local parts = { tag, text }
    if note then
        parts[#parts + 1] = Color(NOTE_COLOR, "(" .. note .. ")")
    end
    if not withoutTime then
        parts[#parts + 1] = Text("GUILD_BANK_LOG_TIME", Ago(line.at or line.entry.t))
    end
    return table.concat(parts, " ")
end

-- What a money line's bank character, or the vault, had before and after
-- it: two amounts of copper, or nil when unknown.
function LogView.Balance(line)
    local entry = line.entry
    if not entry.m or not entry.r then
        return nil
    end
    local into
    if line.source == "bank" then
        into = entry.a == ns.Log.IN
    else
        into = ns.Log.IsVaultIn(entry.y)
    end
    return math.max(entry.r + (into and -entry.m or entry.m), 0), entry.r
end

-- When it happened, as a date and time in the client's way. The vault's
-- log only tells the hour, roughly, unless its bank character told it.
function LogView.When(line)
    local vault = line.source == "vault" and not line.pair
    local at = date("*t", line.at or line.entry.t)
    local minute = vault and 0 or at.min
    local ok, day = pcall(FormatShortDate, at.day, at.month, at.year)
    if not ok or type(day) ~= "string" then
        day = ("%02d/%02d/%d"):format(at.day, at.month, at.year)
    end
    local clock
    ok, clock = pcall(GameTime_GetFormattedTime, at.hour, minute, true)
    if not ok or type(clock) ~= "string" then
        clock = ("%02d:%02d"):format(at.hour, minute)
    end
    return (vault and "~" or "") .. day .. " " .. clock
end

-- Rows ---------------------------------------------------------------------------------

local function AddBalance(line)
    local before, after = LogView.Balance(line)
    if after then
        GameTooltip:AddDoubleLine(L["Balance before"], ns.BankView.Money(before), 1, 0.82, 0, 1, 1, 1)
        GameTooltip:AddDoubleLine(L["Balance after"], ns.BankView.Money(after), 1, 0.82, 0, 1, 1, 1)
    end
end

-- An item's line: the item's tooltip. A money line: where it belongs, and
-- the money before and after; for a bank character's money put into the
-- guild vault or taken from it, both the vault's and the bank character's;
-- for money one bank character gave another, both bank characters'. Not a
-- bank character's whose money we may not see (LogView.Visible). Then
-- when it happened (for a mail taken later, when each did its part). If
-- the row cuts the line short, the whole line, without how long ago: unless
-- that is all it cuts, as when it happened tells it.
local function WholeLine(row)
    if not row.Text:IsTruncated() then
        return nil
    end
    local text = LogView.LineText(row.line, true)
    row.Measure:SetText(text)
    if row.Measure:GetStringWidth() > row.Text:GetWidth() then
        return text
    end
end

local function RowOnEnter(row)
    local line = row.line
    if not line then
        return
    end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    if line.entry.i and pcall(GameTooltip.SetHyperlink, GameTooltip, ItemString(line.entry)) then
        GameTooltip:AddLine(" ")
    else
        local name, color = Source(line)
        GameTooltip:SetText(Color(color, name))
    end
    local whole = WholeLine(row)
    if whole then
        GameTooltip:AddLine(whole, 1, 1, 1, true)
    end
    -- Not the other bank character's money, if we may not see it.
    local pair = line.pair
    if pair and not LogView.Visible(pair) then
        pair = nil
    end
    local apart = pair and pair.source == "bank" and line.source == "bank" and math.abs(pair.entry.t - line.entry.t) >= 60
    AddBalance(line)
    if apart then
        GameTooltip:AddLine(LogView.When(line), 0.6, 0.6, 0.6)
    end
    if pair then
        local name, color = Source(pair)
        GameTooltip:AddLine(Color(color, name))
        AddBalance(pair)
    end
    GameTooltip:AddLine(LogView.When(apart and pair or line), 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

-- Shift-click links the item in the chat. Nothing changes an entry: the log
-- is only ever added to.
local function RowOnMouseUp(row)
    local line = row.line
    if line and line.entry.i and IsModifiedClick("CHATLINK") then
        local _, link = ns.BankView.ItemInfo(ItemString(line.entry))
        if link then
            ChatFrameUtil.InsertLink(link)
        end
    end
end

local function CreateRow(row)
    row.Text = row:CreateFontString(nil, "ARTWORK")
    row.Text:SetFontObject(ChatFontNormal)
    row.Text:SetPoint("LEFT", 4, 0)
    row.Text:SetPoint("RIGHT", -4, 0)
    row.Text:SetJustifyH("LEFT")
    row.Text:SetWordWrap(false)
    -- Not anchored, so never drawn: it measures a line unbounded.
    row.Measure = row:CreateFontString(nil, "ARTWORK")
    row.Measure:SetFontObject(ChatFontNormal)
    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAtlas("PetList-ButtonHighlight")
    highlight:SetAllPoints()
    highlight:SetBlendMode("ADD")
    row:EnableMouse(true)
    row:SetScript("OnEnter", RowOnEnter)
    row:SetScript("OnLeave", GameTooltip_Hide)
    row:SetScript("OnMouseUp", RowOnMouseUp)
end

local function InitRow(row, data)
    if not row.Text then
        CreateRow(row)
    end
    row.line = data.line
    row.Text:SetText(LogView.LineText(data.line))
end

-- The list --------------------------------------------------------------------------

-- A list in parent, filling it.
function LogView.Create(parent)
    local list = CreateFrame("Frame", nil, parent)
    list:SetAllPoints()
    local scrollBox = CreateFrame("Frame", nil, list, "WowScrollBoxList")
    scrollBox:SetPoint("TOPLEFT", 4, -4)
    scrollBox:SetPoint("BOTTOMRIGHT", -20, 4)
    local scrollBar = CreateFrame("EventFrame", nil, list, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 4, 0)
    scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 4, 0)
    local view = CreateScrollBoxListLinearView(0, 0, 0, 0, 0)
    view:SetElementExtent(ROW_HEIGHT)
    view:SetElementInitializer("Frame", InitRow)
    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)
    list.ScrollBox = scrollBox
    list.Empty = list:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    list.Empty:SetPoint("CENTER")
    list.Empty:SetWidth(420)
    EMPTY = L["Nothing in the log yet. It shows what the bank characters trade and mail, and the guild vault's own log once a member opens it."]
    list.Empty:SetText(EMPTY)
    return list
end

-- Whether our rank may see a line (Ranks.lua): a bank character's entry of
-- items if it may see its items, one of money if it may see its money. The
-- guild vault's, all of them: its own log shows them to the guild.
function LogView.Visible(line)
    if line.source ~= "bank" then
        return true
    end
    local Ranks = ns.Ranks
    return ns.playerGUID ~= nil and Ranks.CanSee(ns.playerGUID, line.bank, line.entry.i and Ranks.ITEMS or Ranks.MONEY)
end

-- The lines the list shows: those we may see (LogView.Visible). filters:
-- items, money (entries of each kind), banks, vault (entries of each
-- source), true to show them.
function LogView.Lines(filters)
    local lines = {}
    for _, line in ipairs(ns.Log.Lines(ns.Data.CurrentGuild(false))) do
        local kind = line.entry.i and filters.items or (not line.entry.i and filters.money)
        local source = line.source == "bank" and filters.banks or (line.source == "vault" and filters.vault)
        -- A bank character's money at the vault shows as the vault's line,
        -- unless the vault's lines are hidden; money one bank character gave
        -- another, as the giver's line, unless we may not see the giver's.
        local pair = line.pair
        local shown = LogView.Visible(line) and not (line.source == "bank" and pair
            and (pair.source == "vault" and filters.vault
                or pair.source == "bank" and line.entry.a == ns.Log.IN and LogView.Visible(pair)))
        if kind and source and shown then
            lines[#lines + 1] = line
        end
    end
    return lines
end

-- The log's lines, if our rank may see the log (Ranks.lua).
function LogView.Show(list, filters)
    local elements = {}
    local allowed = ns.Ranks.Can(ns.playerGUID, ns.Ranks.LOG)
    if allowed then
        for _, line in ipairs(LogView.Lines(filters)) do
            elements[#elements + 1] = { line = line }
        end
    end
    list.ScrollBox:SetDataProvider(CreateDataProvider(elements), ScrollBoxConstants and ScrollBoxConstants.RetainScrollPosition)
    list.Empty:SetText(allowed and EMPTY or L["Your rank may not see the log."])
    list.Empty:SetShown(#elements == 0)
end
