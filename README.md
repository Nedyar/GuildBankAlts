<p align="center"><img src=".github/logo.png" alt="Guild Bank Alts logo" width="160"></p>

# Guild Bank Alts

An addon for WoW Forever (the `_forever_` client, 1.60.x) for guilds that
keep their bank on ordinary characters, the guild's bank alts. Every guild
member with the addon sees what those characters hold in a tab of the guild
window, and asks them for items.

> **The players do the delivering.** The bank characters are managed by
> the players who log in with them. The addon never trades, never sends a
> mail and never accepts anything on its own. It shows what the bank
> characters hold, keeps the list of requests, and notices the trades and
> mails their players make, to count them toward the requests and write
> them in the bank's log. At their player's click it only gets things ready:
> a request's items from the bank to the bags, or into a mail with its
> recipient and cash on delivery, and the Send items button's mail to a
> bank character. The player checks the mail and sends it.

- **Bank characters.** A character with the guild rank `Banco` (or `Bank`,
  in any case) shares its money and its bags, slot by slot with the bag in
  each bag slot, whenever they change. The game only lets an addon read the
  bank while it is open, so its bank (its own slots and its bank bag slots,
  bought or not) is shared each time it opens the bank, and the last read
  is kept. Any other character shares nothing of this.
- **The Guild Bank tab.** A tab on the guild window, under the game's own.
  In its Bank subtab, choose a bank character in the dropdown (one that
  has not shared what it holds yet, not having logged in with the addon
  since it got the rank, is greyed out until it does). Next to it,
  its bag slots: the backpack, its bags, the bank and the bank bag slots
  (locked, empty or with their bag); pointing at one lights up its slots.
  Below, all its slots at once on slots like the game's guild bank (scaled
  down to fit), a search box, then the money of the game's guild bank (as
  last seen by any member who opened it) and the character's, in gold,
  silver and copper. The clock between them tells when each was last seen.
  Under it, **Send items** gets a mail to that bank character ready: the
  mailbox's Send tab with its name as the recipient, for you to attach what
  you send to the bank. The game lets no addon open a mailbox, so with none
  open the button waits a few minutes for you to open one (with your
  Interact key, or a right-click on it).
- **Requests.** Right-click an item to request it: how many, how you want
  it, and an optional note. You can ask for no more than the bank
  character holds, less what the accepted requests made to it still await
  of that item: those are set aside, and the form says how many. **In person**: you go to the bank of the city
  where the bank character is, and its player trades you the items, for
  free. **By mail**: the bank character's player sends you the items by
  mail, setting the cash on delivery by hand: the postage, 30 copper per
  stack. A request is only a note for the bank character's player: nothing
  is delivered until that player does it by hand. The Requests subtab lists
  every request, oldest first, with where it stands and how it is to be
  delivered.
  - A bank character, an officer (rank `Oficial` or `Officer`) or the guild
    master can **accept** a request, pending or partly delivered, only if
    the bank character it was made to has enough of the item to spare:
    what it holds (bags and bank, as it last shared them), less what the
    other accepted requests made to it still await of that item. Otherwise
    the Accept button is off, and its tooltip says how many it has to
    spare. An accepted request's row is green; a rejected one's, red.
  - They can also **reject** a request while it is open, accepted or not.
    **Reject short of stock**, under the list, rejects at once every
    request pending or partly delivered that its bank character has not
    enough to spare for (as the Accept button counts it), after asking;
    its tooltip lists them. Accepted requests are left alone.
  - Its maker can delete a request pending, partly delivered or rejected,
    but not once accepted. A rejected request stays until its maker
    deletes it, or for a week: then it goes by itself, and for everyone,
    even if its maker no longer plays (the same for a delivered request
    whose maker has not logged in to see it). **Delete my rejected**,
    under the list, deletes all of one's rejected requests at once.
  - A request is **delivered** once the bank character's player has handed
    over all its items, by trade or by mail, in as many goes as it takes
    (until then it shows "10/20 delivered"): the bank character's addon
    notices what its player gives to whoever asked for it and counts it.
    Once its maker's addon has told them, the request goes from the list:
    the log keeps what was handed over.
  - **Which request a delivery counts towards**, when its maker has several
    for the same item: the one a mail was made ready for with the Mail
    button, if it was; then the accepted ones; then the others still open;
    then the rejected ones; the oldest first among each.
  - **Getting a request ready.** Logged in with the bank character, its
    accepted requests have two more buttons: **Prepare**, and
    **Mail** for those by mail. Each is enabled only when it can do its
    part; its tooltip says what it does, or why it cannot (bank closed, not
    enough items, no room, a mail already holding items...).
    - **Prepare** keeps for the request in the bags the stacks it still
      lacks, in the fewest stacks: stacks already in the bags and kept for
      no request, as they are or split, and, with the bank open, the rest
      from the bank, each into an empty slot, so every request's items stay
      in stacks of their own. When no stack holds what one is to hold,
      several are put together into one: onto a stack of the bags, where
      it is, or onto one the request already keeps that is not full (for
      35, with 1 and 20 in the bags and 14 in the bank: the 20, and the
      bank's 14 put onto the 1). Without the bank, it is enabled when the bags
      hold enough kept for no request. If the bags lack the empty slots it
      takes, it is not enabled. It never takes another request's kept
      stacks, nor brings what another request lacks. Once the request keeps
      stacks and Prepare can add no more (it is ready, or the rest is not
      to be had now), the button is **Release**: it lets go of them, for
      other requests to take; nothing moves.
    - **Mail**, at a mailbox, makes a mail ready on the Send tab: the items
      in the fewest stacks (partial stacks merged, the rest split off), as
      many as one mail takes (12 stacks), the requester as the recipient,
      "Request: [item] x[count]" as the subject (the item's name cut to fit
      the subject box if need be; the body is left alone), and cash on
      delivery of 30 copper per stack; press it again once it is sent for
      the rest. It takes the stacks kept for the request or for
      none, never another request's. Then check the mail and send it.
  - **Kept stacks.** A stack kept for a request shows a padlock in the top
    right corner of its icon in the game's bags; the padlock's tooltip says
    for which request. Moved within the bags, the stack stays kept and the
    padlock goes with it. Split, added to (by hand, or by the game stacking
    loot or mail onto it) or taken out of the bags (traded, mailed, back in
    the bank), it is let go and the padlock goes away; so are the stacks of
    a request once it is no longer accepted (rejected, delivered or
    deleted). Press Prepare again to keep what it lacks once more.
- **The log.** The Log subtab lists what came into the bank and what went
  out of it, newest first, one line per entry in the words of the game's
  own guild bank log ("Name deposited [Item] x 5 ( 3 hours ago )"). It
  joins two logs, told apart by a tag at the start of each line:
  - **the bank characters'** (blue tag, with the character's name): every
    item and every coin a bank character trades or mails, both ways, and
    with whom: by trade, by mail (sent, or taken from its mailbox, the
    auction house's mail too), the cash on delivery and the postage it
    pays, its mail that comes back, and the money it puts into the guild vault or takes from
    it. Its own client writes them down as they happen;
  - **the guild vault's** (green tag): the game's own guild bank. When any
    member opens it, its log, items (the tabs they may see) and money, is
    read and shared. The game only keeps its last entries; the guild keeps
    what its members read before, so the log reaches further back. The same
    entry read by several members shows once.

  Pointing at a money line shows how much the bank character, or the
  guild vault, had before and after it (the vault's is worked out from
  what it holds when its log is read). A bank character's money put into
  the vault or taken from it shows once, as the vault's line, with both:
  the vault's money and the bank character's. So does money one bank
  character gives another, by trade or mail: once, as the giver's line,
  with both bank characters' money (and, for a mail taken later, when it
  was sent and when it was taken); its postage stays a line of its own, as
  money that left the bank. At an item line, the item.
  Both tell the date and time it happened (the vault's only roughly, to
  the hour, unless a bank character told it). Nobody can change or delete
  an entry, not even the bank character that wrote it: the log is only
  ever added to. Under the list, filters show or hide items, money, the
  bank characters' entries and the guild vault's.
- **Notices.** A bank character is told in the chat of new requests and how
  to deliver them, and its tab shows the notification mark while requests
  wait for it, until they are delivered or rejected. A member is told in
  the chat when their request is accepted, rejected, or delivered, in part
  or in full. Their accepted and rejected requests are also counted on the
  Requests subtab ("Requests (1)") and show the notification mark on the
  tab: an accepted one until they point at it in the list (its row or its
  item), a rejected one until they delete it or it goes after a week. The
  mark shows on the Requests subtab too, on the icon of each request it is
  for, and on the micro menu's button that opens the guild window, as the
  game marks it for unread messages.
- **Sharing in the background.** Everything goes to the rest of the guild
  through hidden addon messages, which never appear in any chat window.
  When you log in, a guild member who is online sends you whatever you are
  missing, so as long as someone with the addon is online, everyone ends up
  with the same data.
- **Other addons' tabs.** Guild Professions & Recipes adds a tab to the
  guild window too. The two take turns: opening one closes the other, and
  they line up one under the other. Neither needs the other.
- **Every client language.** The addon's texts are in English, German,
  Spanish, French, Italian, Korean, Portuguese (Brazil, also used by
  Portugal's client), Russian and Chinese (simplified and traditional).

## Installing

The addon needs **LibGuildSync**, the shared code of the guild addons; the
CurseForge app installs it with Guild Bank Alts. By hand, copy both the
`GuildBankAlts` and `LibGuildSync` folders into
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

The tests run outside the game with Lua 5.1, from the addon folder, with
LibGuildSync's folder next to it (its harness and its files are used):

```
lua5.1 Tests\run.lua . Tests
```

They load LibGuildSync's and the addon's real files into simulated clients
that talk through a simulated server, with bags, banks, trades, mail and the
guild vault's log, and check the sync, the saved data, the requests, the
bank's log and the guild window tab. One
test puts members on the last release (taken from its git tag) in the same
guild as members on this version.

## Releasing

Once the addon has a CurseForge project with this repository's webhook,
CurseForge packages every tagged commit pushed here.

1. Raise `## Version` in `GuildBankAlts.toc` and add that version's entry
   at the top of `CHANGELOG.md`. The tests check that both match. If
   `trial = true` is in `Core.lua`'s configuration (a new protocol tried in
   game on a prefix of its own), turn it off; if `ANNOUNCE_AS` is set (a
   version tried in game while telling the guild it is the last release),
   set it to nil. The tests print a note while either is on.
2. Commit, tag the commit `v<version>` and push the tag:
   `git push origin v<version>`. A tag containing `beta` or `alpha` makes a
   beta or alpha file instead of a release.
3. CurseForge builds the zip as `.pkgmeta` says: the `GuildBankAlts` folder
   without the tests, with `CHANGELOG.md` as the file's changelog.

## License

MIT. See [LICENSE](LICENSE).
