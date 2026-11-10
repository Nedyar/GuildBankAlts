local H = ...

-- Members on the last release and members on this version share one guild:
-- both must keep talking, whoever holds the bank character. The release is
-- taken from its git tag (H.Release).
local RELEASE = "v0.1.0"

H.section("Versions: against " .. RELEASE)
local old = H.Release(RELEASE)
if not old then
    print("   NOTE: " .. RELEASE .. " could not be extracted with git: skipped")
    return
end
local OLD = { old }

local function Errors(world, label)
    H.eq(#world.errors, 0, "no errors: " .. label)
    for _, err in ipairs(world.errors) do
        print("   " .. err)
    end
    world.errors = {}
end

local function Link(itemID, enchant, suffix)
    return ("|cff1eff00|Hitem:%d:%s:::::%s:12345:60:::::|h[Item%d]|h|r"):format(itemID, enchant or "", suffix or "", itemID)
end

-- Bags 1 to 4 and bank bags 7 to 9 of 18 slots, the bank's 48: every slot
-- filled, a third of them with enchanted or suffixed items.
local function FullContainers()
    local containers, n = {}, 0
    local function Fill(bag, size)
        local container = { size = size }
        for slot = 1, size do
            n = n + 1
            if n % 3 == 0 then
                container[slot] = { 20000 + n, 1, Link(20000 + n, tostring(1000 + n), tostring(-(n * 7))) }
            else
                container[slot] = { 2000 + n, (n % 20) + 1 }
            end
        end
        containers[bag] = container
    end
    Fill(0, 16)
    for bag = 1, 4 do
        Fill(bag, 18)
    end
    Fill(6, 48)
    for bag = 7, 9 do
        Fill(bag, 18)
    end
    return containers
end

local function NewWorld(seed, bankAddons, memberAddons)
    local world = H.NewWorld({ seed = seed, senderFormat = "short", strictWhispers = true })
    local bank = world:NewClient("Bank Holder", {
        rank = "Banco", rankIndex = 4, money = 5000, addons = bankAddons,
        containers = FullContainers(),
        bagItems = { [1] = 4240, [2] = 4240, [3] = 4240, [4] = 4240 },
        bankTabs = { 6, 7, 8, 9 }, maxBankTabs = 4, bankBags = { [2] = 4500, [3] = 4500, [4] = 4500 },
    })
    local member = world:NewClient("Member Name", { rank = "Miembro", rankIndex = 3, addons = memberAddons })
    return world, bank, member
end

local function BankAt(client, bank)
    local guild = client.ns.Data.GetGuild("Test Guild")
    local record = guild and guild.members[bank.guid]
    return record and record.bk
end

for _, case in ipairs({
    { "a bank character on this version, a member on " .. RELEASE, nil, OLD },
    { "a bank character on " .. RELEASE .. ", a member on this version", OLD, nil },
}) do
    local label, bankAddons, memberAddons = case[1], case[2], case[3]
    local world, bank, member = NewWorld(#label, bankAddons, memberAddons)
    world:Login(bank)
    world:RunFor(10)
    world:OpenBank(bank)
    world:RunFor(5)
    world:CloseBank(bank)
    world:Login(member)
    world:RunFor(300)
    local bk = BankAt(member, bank)
    H.check(bk ~= nil and bk.b ~= nil and bk.k ~= nil, label .. ": the member gets the bags and the bank")
    H.check(bk ~= nil and #bk.k == 4 and bk.k[1].s[48] ~= nil, label .. ": slot by slot")
    H.check(member.ns.Data.GetGuild("Test Guild").members[bank.guid].av == bank.ns.VERSION_NUM, label .. ": with the bank character's version")
    H.check(bank.ns.Data.GetGuild("Test Guild").members[member.guid] ~= nil, label .. ": and the bank character gets the member's record")
    world:SetContainer(bank, 0, { size = 16, [1] = { 2589, 7 } })
    world:RunFor(200)
    bk = BankAt(member, bank)
    H.check(bk and bk.b[1].s[1] and bk.b[1].s[1].i == 2589, label .. ": a change in the bags reaches the member")
    Errors(world, label)
end

-- The bank character offline: its owner's other character, on this version,
-- passes its data on to a member on the release who has none.
local world, bank, member = NewWorld(41, nil, OLD)
world:Login(bank)
world:RunFor(30)
world:Logout(bank)
world:RunFor(10)
local main = world:NewClient("Owner Main", { rank = "Miembro", rankIndex = 3, saved = H.DeepCopy(bank.saved) })
world:Login(main)
world:RunFor(60)
world:Login(member)
world:RunFor(300)
local bk = BankAt(member, bank)
H.check(bk ~= nil and bk.b ~= nil, "a member on " .. RELEASE .. " gets an offline bank character's bags from another character")
Errors(world, "relayed")
