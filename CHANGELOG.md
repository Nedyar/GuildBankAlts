# Changelog

## 0.4.1 - Mail button paused

- **The Mail button is off for now.** On the server, sending the mail it got ready failed ("Internal mail database error"), and for a while the bank character could not send items by mail by hand either. Until that is understood, bank characters send a request's mail by hand; the button stays in its place, greyed out, its tooltip saying so. Prepare works as before.

## 0.4.0 - Options and permissions

- **Options**, under Options > AddOns > Guild Bank Alts (or `/gbalts options`): the language of the addon's texts, this client's own, and the guild's options, shared with every member. Only the guild master changes the guild's; the others see them greyed out.
- **Bank ranks**: the guild ranks whose characters are bank characters, a list the guild master edits. By default, `Banco`, in every client language (`Bank` no longer is one by default).
- **Permissions, by guild rank**: whether it may see the log, make requests, accept them and reject them. By default, as before: every rank sees the log and makes requests; the bank ranks and the rank `Oficial` (or `Officer`) answer them. The guild master may do everything. An answer counts only if its author's rank may give it, and may see the bank character's items, also for answers given before a change.
- **Who sees each bank character**, by guild rank: its items and its money, apart. By default, every rank sees everything. The guild master sees all of them, and a bank character its own. A bank character none of whose things one may see is not in the dropdown.
- **A rank that may not see a bank character's items does not see the requests made to it either** (but its members' own), nor may answer them, nor sees its items in the log. One that may not see its money does not see its money in the log, nor in a tooltip of another line (money it gave another bank character then shows as the other's line).
- These rights are kept by the addon: what a member may not see still reaches their client with the sync (no addon can keep it from them); the addon does not show it.
- **Members on 0.3.2 and older keep working** with members on 0.4.0, but follow the old rules: the rank `Banco` (or `Bank`), and the old rights. They pass the guild master's record on, without the options; a member on 0.4.0 keeps the options it knew.

## 0.3.2 - Accepted requests

- **Requests can be accepted**: an Accept button, beside Reject, for bank characters, officers and the guild master, on requests pending or partly delivered. It is enabled only if the bank character has enough of the item to spare: what it holds, less what its other accepted requests still await of it; else its tooltip says how many it has to spare. An accepted request can still be rejected. Its maker is told in the chat and cannot delete it. Its row in the list is green.
- **Two buttons under the request list act on several requests at once**: Delete my rejected, for everyone, deletes all of one's rejected requests; Reject short of stock, for bank characters, officers and the guild master, rejects every request pending or partly delivered that its bank character has not enough to spare for (as Accept counts it), after asking. Their tooltips say how many and list them. Accepted requests are left alone.
- **The request form sets aside what accepted requests still await**: you can ask for what the bank character holds less that, and the text by the quantity says how many are set aside ("of 14 available (6 set aside for accepted requests)"), as does the error when you ask for more. With all of it set aside, the form says at once that none can be asked for.
- **Prepare and Mail only on accepted requests**: a bank character accepts a request (or an officer does) before getting it ready. Stacks kept for a request are let go once it is no longer accepted.
- **Which request a delivery counts towards**, when the same member has several for the same item: the one a mail was made ready for with the Mail button, then the accepted ones, then the others still open, then the rejected ones; the oldest first among each.
- **A delivered request goes from the list** once its maker's addon has told them (the log keeps what was handed over), instead of staying a week. A rejected request still goes after a week, or when its maker deletes it.
- **Closed requests of a member who no longer plays go too**: a rejected or delivered request a week old is no longer listed, though its maker's addon, not run since, could not drop it.
- **A rejected request's row is red**, as an accepted one's is green.
- **The notification mark** shows, for the maker of a request, once it is accepted, until they point at it in the list, and while it is rejected, until they delete it (or a week passes), no longer only until the list is seen; on the Requests subtab too, on the icon of each request it is for, the bank character's waiting ones included, and on the micro menu's button that opens the guild window, as the game marks it for unread messages (from logging in, before the guild window is first opened).
- **Members on 0.3.1 and older keep working with members on 0.3.2**: the acceptance travels where they skip it, so to them an accepted request is pending.
- **Fixed: Prepare kept a request's items in more stacks than it takes.** When no stack held what one was to hold, it took several, each kept as a stack of its own (for 35, with 1 and 20 in the bags and 14 in the bank: the 20, the 14 and the 1). Now it puts them together into one (the bank's 14 onto the 1, a 15), onto a stack of the bags where it is, or onto one the request already keeps that is not full.
- **A bigger padlock on kept stacks**, all within the item's icon (it was small, and stood out of the icon's corner).
- **Fixed: the guild tab's selection glow covered its notification mark.** The mark now sits on a frame of its own over the tab, as the game's Roster tab has it.
- **Fixed: choosing a bank character that had not shared what it holds yet** (just given the bank's rank, not logged in with the addon since) gave a Lua error and left the Bank subtab stuck. Such a bank character is now greyed out in the dropdown, its tooltip saying why, and the subtab shows one it knows.

## 0.3.1 - Rejected requests told

- **A rejected request is told to whoever made it** as a bank character is told of the requests waiting for it: the Requests subtab counts it ("Requests (1)") and the guild window's tab shows the notification mark, until its maker sees it listed in the Requests subtab (with "Only open requests" off, which hides it). The chat line it already got stays.
- **Money one bank character gives another shows once in the log**, by trade or mail: as the giver's line, whose tooltip has both bank characters' money before and after (for a mail taken later, when it was sent and when it was taken), as a bank character's money at the guild vault already did. The postage stays a line of its own: money that left the bank. Money mailed and not taken yet shows alone until it is.
- **Fixed: entries of the same time out of order in the log**: a mail's postage showed below its money, as if paid before it. Newest first now holds for them too.
- **A log line too long for its row** is repeated in its tooltip only when the row cuts more than how long ago it was (which the tooltip's date already tells), and without it.
- **Fixed: the postage of a mail carrying money** was logged with that money added (a mail with 1 copper logged 31 copper of postage instead of 30), so the money left after it came out short. The game's price of a mail counts the money it carries; the postage is the rest.

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
