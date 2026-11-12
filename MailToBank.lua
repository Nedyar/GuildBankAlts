-- MailToBank.lua: the Send items button under the Bank subtab (GuildTab.lua):
-- a mail to the bank character shown in the subtab, on the mailbox's Send
-- tab with its name as the recipient, for the player to attach what they
-- send to the bank and send it by hand.
--
-- Only the player can open a mailbox: the game lets no addon interact with
-- one, with or without its Interact key option. So with no mailbox open,
-- the button waits for the next one the player opens (with their Interact
-- key, or a right-click on it), for a while, and readies the mail then.
local _, ns = ...
local L = ns.L

local MailToBank = {}
ns.MailToBank = MailToBank

local WAIT = 300              -- seconds the button waits for a mailbox
local SEND_TAB = 2            -- the mailbox's Send Mail tab
local MAILBOX = Enum.PlayerInteractionType and Enum.PlayerInteractionType.MailInfo or 17

local button
local waiting  -- { name, at }: a mail to ready when a mailbox opens

local function MailboxOpen()
    return MailFrame ~= nil and MailFrame:IsShown() == true
end
MailToBank.MailboxOpen = MailboxOpen

-- The bank character to send to (the one the Bank subtab shows): its GUID
-- and name, or nil and why not ("none", "own").
function MailToBank.Target()
    local guid = ns.BankView.SelectedBank()
    if not guid then
        return nil, nil, "none"
    elseif guid == ns.playerGUID then
        return nil, nil, "own"
    end
    local guild = ns.Data.CurrentGuild(false)
    return guid, ns.Data.NameOf(guid, guild and guild.members[guid])
end

-- The mailbox's Send tab, with the bank character as the recipient.
local function Ready(name)
    if not MailboxOpen() or not SendMailNameEditBox then
        return false
    end
    MailFrameTab_OnClick(nil, SEND_TAB)
    SendMailNameEditBox:SetText(name)
    return true
end

local function IsWaiting()
    return waiting ~= nil and GetTime() - waiting.at <= WAIT
end

function MailToBank.Update()
    if not button then
        return
    end
    button:SetEnabled(MailToBank.Target() ~= nil)
end

function MailToBank.Click()
    local guid, name = MailToBank.Target()
    if not guid then
        return
    end
    if Ready(name) then
        waiting = nil
    else
        waiting = { name = name, at = GetTime() }
        ns.Print(L["open a mailbox: a mail to %s will be ready."], name)
    end
end

-- A mailbox opened: the mail waited for, once the game has shown its Inbox
-- tab (it does as the mailbox opens).
local function MailboxOpened()
    if not IsWaiting() then
        waiting = nil
        return
    end
    local name = waiting.name
    C_Timer.After(0.1, function()
        if waiting and waiting.name == name and Ready(name) then
            waiting = nil
        end
    end)
end

local function OnEnter(self)
    local _, name, why = MailToBank.Target()
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(L["Send items"], 1, 1, 1)
    if why == "own" then
        GameTooltip:AddLine(L["This is your own bank."], 0.7, 0.7, 0.7, true)
    elseif name then
        GameTooltip:AddLine(L["A mail to %s, ready for you to attach what you send to the bank."]:format(name), nil, nil, nil, true)
        if IsWaiting() then
            GameTooltip:AddLine(L["Waiting for you to open a mailbox."], 0, 1, 0, true)
        elseif not MailboxOpen() then
            GameTooltip:AddLine(L["After clicking, open a mailbox with your Interact key or a right-click: the mail will be ready."],
                0.7, 0.7, 0.7, true)
        end
    end
    GameTooltip:Show()
end

-- The button, in parent: its size fits its text.
function MailToBank.CreateButton(parent)
    button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetText(L["Send items"])
    button:SetSize(math.max(button:GetTextWidth() + 32, 110), 22)
    button:SetMotionScriptsWhileDisabled(true)
    button:SetScript("OnClick", MailToBank.Click)
    button:SetScript("OnEnter", OnEnter)
    button:SetScript("OnLeave", GameTooltip_Hide)
    MailToBank.Update()
    return button
end

function MailToBank.Init()
    local frame = CreateFrame("Frame")
    ns.RegisterEvents(frame, "MAIL_SHOW", "PLAYER_INTERACTION_MANAGER_FRAME_SHOW")
    frame:SetScript("OnEvent", function(_, event, kind)
        if event == "MAIL_SHOW" or ns.Plain(kind) == MAILBOX then
            MailboxOpened()
        end
    end)
end
