-- Ranks.lua: who may do what with the guild bank, from the guild roster.
--
-- The guild keeps its bank on ordinary characters with the rank "Banco"
-- (or "Bank"). Those characters share their bags, bank and money, deliver
-- what members request, and may reject requests. The guild master and the
-- rank "Oficial" (or "Officer") may reject requests too. Rank names are
-- compared without regard to case or surrounding spaces.
--
-- Every client decides from its own copy of the roster, so a member whose
-- rank changes gains or loses these rights everywhere at the next roster
-- read.
local _, ns = ...

local Ranks = {}
ns.Ranks = Ranks

Ranks.BANK = { banco = true, bank = true }
Ranks.OFFICER = { oficial = true, officer = true }

local function RankName(guid)
    local entry = guid and ns.Roster.members[guid]
    local name = entry and entry.rk
    if type(name) ~= "string" then
        return nil
    end
    return strtrim(name):lower()
end

-- A guild bank character.
function Ranks.IsBank(guid)
    local name = RankName(guid)
    return name ~= nil and Ranks.BANK[name] == true
end

-- The guild master, or an officer.
function Ranks.IsOfficer(guid)
    local entry = guid and ns.Roster.members[guid]
    if entry and entry.ri == 0 then
        return true
    end
    local name = RankName(guid)
    return name ~= nil and Ranks.OFFICER[name] == true
end

-- Whether a member may reject other members' requests.
function Ranks.CanReject(guid)
    return Ranks.IsBank(guid) or Ranks.IsOfficer(guid)
end
