# Changelog

## 0.3.0 - The bank's log

- **A Log subtab** in the Guild Bank tab: what came into the bank and what went out of it, newest first, worded like the game's own guild bank log ("Name deposited [Item] x 5 ( 3 hours ago )").
- **The bank characters' log**: every item and every coin a bank character trades or mails, both ways, with whom: by trade, by mail (sent, or taken from the mailbox, auction house mail included), cash on delivery and postage paid, and mail returned to it. Each bank character's own client writes it down and shares it with the guild.
- **The guild vault's log too**, told apart by a green tag: when any member opens the game's guild bank, its log (items and money) is read and shared, and kept further back than the game keeps it. While the guild bank is open, its money log is read again each time its money changes, so new moves show at once.
- **A bank character's money at the guild vault**: what it puts in or takes out is written down with the money it had, and shows as the guild vault's line.
- **Tooltips**: on a money line, whose money it is and how much there was before and after it (for a bank character's money at the guild vault, both the vault's and the bank character's); on an item line, the item. Both tell the date and time it happened.
- **Filters** under the log: items, money, the bank characters, the guild vault.
- **A Send items button** under the Bank subtab: the mailbox's Send tab, with the bank character shown as the recipient. With no mailbox open, it waits a few minutes for you to open one (the game lets no addon open it).
- **A bank character gets its requests ready with the Prepare and Mail buttons** of the Requests subtab, each enabled only when it can do its part, with a tooltip saying what it does or why it cannot. Prepare keeps the stacks still to deliver for the request in its bags, in the fewest stacks of their own: stacks already there and kept for none, and, with the bank open, stacks brought from it (without the bank, the bags must hold enough; it needs room for all of it). No other request's Prepare or Mail takes them. Once ready, Prepare becomes Release, which lets go of them. Kept stacks show a padlock in the game's bags, with a tooltip saying for which request; moved within the bags they stay kept, split, added to or taken out they are let go. Mail, at a mailbox, for a request by mail: a mail with the items in the fewest stacks (merged and split as needed, 12 at most), the requester as the recipient, the item and its count as the subject (cut to fit) and cash on delivery of 30 copper per stack. The player checks it and sends it.
- **The Requests subtab lists the oldest requests first**, in the order they are to be seen to.
- **Members on 0.2.0 keep working** with members on 0.3.0; they just do not see the log.

## 0.2.0 - On the guild addons' shared library

- **Now needs LibGuildSync**, the shared code of the guild addons: hidden addon messages, the guild roster, the saved data and the sync. The CurseForge app installs it with Guild Bank Alts; by hand, copy its folder too.
- **Nobody has to update at once**: members on 0.1.0 and on 0.2.0 keep sharing everything.
- **A shorter hint under the Guild Bank tab**: in some languages it took three lines and spilled out of the window.

## 0.1.0 - First release

- **A guild bank on characters**: characters with the guild rank `Banco` (or `Bank`) share their money, bags and bank, slot by slot, with every guild member who runs the addon.
- **A Guild Bank tab on the guild window**: each bank character's slots laid out like the game's guild bank, its bag slots, a search box, its money and the guild bank's.
- **Requests**: right-click an item to ask for it, to be collected in person (free) or sent by mail (30 copper per stack, cash on delivery). Requests are approved by themselves once the bank characters hand the items over, by trade or mail; bank characters, officers and the guild master can reject them.
- **Chat notices** for bank characters (new requests) and for members (deliveries and rejections).
- **Translated into every client language**: English, German, Spanish, French, Italian, Korean, Portuguese, Russian and Chinese.
