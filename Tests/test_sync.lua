local H = ...

local function Errors(world, label)
    H.eq(#world.errors, 0, "no errors: " .. label)
    for _, err in ipairs(world.errors) do
        print("   " .. err)
    end
    world.errors = {}
end

local function RecordOf(client, other)
    local guild = client.ns.Data.GetGuild("Test Guild")
    return guild and guild.members[other.guid]
end

local CLOTH = 2589

H.section("Sync: two members online")
local world = H.NewWorld({ seed = 7, senderFormat = "short", strictWhispers = true })
local bank = world:NewClient("Bank Holder", {
    rank = "Banco", rankIndex = 4, money = 5000,
    containers = { [0] = { size = 16, [1] = { CLOTH, 20 } } },
})
local alice = world:NewClient("Alice Smith")
local bob = world:NewClient("Bob Jones")
local carol = world:NewClient("Carol White")
world:AddMember("Dan Brown", nil, { class = "PRIEST", level = 42 })
world:Login(bank)
world:RunFor(5)
world:Login(alice)
world:RunFor(120)
Errors(world, "two members online")
local bankAtAlice = RecordOf(alice, bank)
H.check(bankAtAlice ~= nil and bankAtAlice.bk ~= nil, "Alice has what the bank character holds")
H.eq(bankAtAlice and bankAtAlice.bk and bankAtAlice.bk.b[1].s[1].n, 20, "slot by slot")
H.check(RecordOf(bank, alice) ~= nil and alice.ns.Data.IsShareable(RecordOf(bank, alice)),
    "the bank character has Alice's record, though she has nothing to share yet")

H.section("Sync: a member logs in later")
world:Logout(bank)
world:RunFor(10)
world:Login(carol)
world:RunUntil(function()
    return RecordOf(carol, bank) ~= nil and RecordOf(carol, alice) ~= nil
end, 180)
Errors(world, "later login")
H.check(RecordOf(carol, bank) ~= nil and RecordOf(carol, bank).bk ~= nil, "Carol gets the bank character's record from Alice, though it is offline")
H.check(RecordOf(carol, bank) and not RecordOf(carol, bank).fh, "marked as relayed")

H.section("Sync: changes are announced")
local before = RecordOf(carol, alice).t
local id = alice.ns.Requests.Create(bank.guid, "item:" .. CLOTH, 5, "", alice.ns.Requests.IN_PERSON)
H.check(id ~= nil, "Alice makes a request")
world:RunFor(150)
Errors(world, "a change")
local updated = RecordOf(carol, alice)
H.check(updated.t > before, "Carol gets Alice's newer record")
H.check(updated.rq and updated.rq[id] and updated.rq[id].q == 5, "with the request")
local sent = world.stats.guild
world:RunFor(600)
H.check(world.stats.guild - sent <= 2, "quiet when nothing changes (" .. (world.stats.guild - sent) .. " guild messages in 10 min)")

H.section("Sync: saved data")
world:Logout(carol)
world:RunFor(5)
H.eq(type(carol.saved.GuildBankAltsDB.guilds["Test Guild"].members[alice.guid].b), "string", "records are saved packed")
world:Login(carol)
world:RunFor(5)
H.check(RecordOf(carol, bank) ~= nil and RecordOf(carol, bank).bk ~= nil, "records come back after logging in again")
Errors(world, "saved data")

-- A member whose saved data was lost gets their requests back.
world:Logout(alice)
world:RunFor(5)
world:Login(alice, { brokenSavedVariables = true })
world:RunUntil(function()
    local own = alice.ns.Data.GetOwnRecord(false)
    return own and own.rq and own.rq[id] ~= nil
end, 240)
local own = alice.ns.Data.GetOwnRecord(false)
H.check(own and own.rq and own.rq[id] ~= nil, "lost requests come back from the guild")
Errors(world, "lost data")

H.section("Sync: members who leave")
world:Login(bob)
world:RunFor(60)
world:Logout(bob)
world:RemoveMember(bob.key)
world:RosterChanged()
world:RunFor(150)
local guild = carol.ns.Data.GetGuild("Test Guild")
H.check(guild.members[bob.guid] ~= nil, "Bob's record stays for a while, in case the roster read was partial")
H.check(not carol.ns.Roster.IsKnownGUID(bob.guid), "but he is no longer in the roster")
Errors(world, "a member leaves")

H.section("Sync: /gbalts sync")
local printed = #carol.printed
carol.env.SlashCmdList.GUILDBANKALTS("sync")
world:RunFor(30)
local lines = {}
for i = printed + 1, #carol.printed do
    lines[#lines + 1] = carol.printed[i]
end
local text = table.concat(lines, "\n")
H.check(text:find("asking the guild", 1, true) ~= nil, "manual sync says it is asking")
H.check(text:find("nobody online has data you are missing", 1, true) ~= nil or text:find("sync finished", 1, true) ~= nil, "and how it ended")
Errors(world, "manual sync")
