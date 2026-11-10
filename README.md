<p align="center"><img src=".github/logo.png" alt="Guild Bank Alts logo" width="160"></p>

# Guild Bank Alts

An addon for WoW Forever (the `_forever_` client, 1.60.x) for guilds that
keep their bank on ordinary characters, the guild's bank alts. Every guild
member with the addon sees what those characters hold in a tab of the guild
window, and asks them for items.

- **Bank characters.** A character with the guild rank `Banco` (or `Bank`,
  in any case) shares its money and its bags, slot by slot with the bag in
  each bag slot, whenever they change. The game only lets an addon read the
  bank while it is open, so its bank (its own slots and its bank bag slots,
  bought or not) is shared each time it opens the bank, and the last read
  is kept. Any other character shares nothing of this.
- **The Guild Bank tab.** A tab on the guild window, under the game's own.
  In its Bank subtab, choose a bank character in the dropdown. Next to it,
  its bag slots: the backpack, its bags, the bank and the bank bag slots
  (locked, empty or with their bag); pointing at one lights up its slots.
  Below, all its slots at once on slots like the game's guild bank (scaled
  down to fit), a search box, then the money of the game's guild bank (as
  last seen by any member who opened it) and the character's, in gold,
  silver and copper. The clock between them tells when each was last seen.
- **Requests.** Right-click an item to request it: how many, how you want
  it, and an optional note. **In person**: you collect the items at the bank
  of the city where the bank character is, for free. **By mail**: the bank
  character mails them, and the postage, 30 copper per stack, is charged
  cash on delivery. The Requests subtab lists every request, with where it
  stands and how it is to be delivered.
  - Its maker can delete a request until it is approved.
  - A bank character, an officer (rank `Oficial` or `Officer`) or the guild
    master can reject it while it is open.
  - A request is **approved** once the bank characters have handed over all
    its items, by trade or by mail, in as many goes as it takes (until
    then it shows "10/20 delivered"). The bank character's addon counts
    what it gives to whoever asked for it; nothing else is needed. From
    then on, the request can neither be deleted nor rejected.
  - Approved and rejected requests stay listed for a week.
- **Notices.** A bank character is told in the chat of new requests and how
  to deliver them, and its tab shows the notification mark while requests
  wait for it. A member is told when their request is delivered, in part or
  in full, or rejected.
- **Automatic sharing.** Everything goes to the rest of the guild through
  hidden addon messages, which never appear in any chat window. When you
  log in, a guild member who is online sends you whatever you are missing,
  so as long as someone with the addon is online, everyone ends up with the
  same data.
- **Other addons' tabs.** Guild Professions & Recipes adds a tab to the
  guild window too. The two take turns: opening one closes the other, and
  they line up one under the other. Neither needs the other.
- **Every client language.** The addon's texts are in English, German,
  Spanish, French, Italian, Korean, Portuguese (Brazil, also used by
  Portugal's client), Russian and Chinese (simplified and traditional).

## Installing

Copy the `GuildBankAlts` folder into
`World of Warcraft\_forever_\Interface\AddOns\`. Give the bank characters
the guild rank `Banco` (or `Bank`), and log in with each of them once with
the addon; open each one's bank once so its bank is shared too.

## Commands

| Command | What it does |
|---|---|
| `/gbalts` or `/gbalts status` | What the addon knows and is doing |
| `/gbalts sync` | Ask the guild for missing data now |
| `/gbalts language <code>\|auto` | The language of the addon's own texts |
| `/gbalts debug` | Show the sync log in the chat |
| `/gbalts reset` | Forget the data of your current guild |

## Tests

The tests run outside the game with Lua 5.1, from the addon folder:

```
lua5.1 Tests\run.lua . Tests
```

They load the addon's real files into simulated clients that talk through a
simulated server, with bags, banks, trades and mail, and check the sync, the
saved data, the requests and the guild window tab.

## Releasing

Once the addon has a CurseForge project with this repository's webhook,
CurseForge packages every tagged commit pushed here.

1. Raise `## Version` in `GuildBankAlts.toc` and add that version's entry
   at the top of `CHANGELOG.md`. The tests check that both match. If
   `ns.TRIAL` is on in `Core.lua` (a new protocol tried in game on a prefix
   of its own), turn it off: the tests print a note while it is on.
2. Commit, tag the commit `v<version>` and push the tag:
   `git push origin v<version>`. A tag containing `beta` or `alpha` makes a
   beta or alpha file instead of a release.
3. CurseForge builds the zip as `.pkgmeta` says: the `GuildBankAlts` folder
   without the tests, with `CHANGELOG.md` as the file's changelog.

## License

MIT. See [LICENSE](LICENSE).
