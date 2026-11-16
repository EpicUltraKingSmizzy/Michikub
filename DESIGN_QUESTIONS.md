# Michikub design questions (v0.1.0)

These are the non-coding questions that came up while building the first version. Each one has the answer I picked for this build and a one-line reason. Change any answer you like and the code will follow.

Most numbers live in a small set of constants: `BotTuning` (lib/engine/bot.dart), `LayoutTuning` (lib/engine/board.dart), `TableTuning` (lib/ui/game_screen.dart) and `HouseRules` (lib/engine/rules.dart).

## A. Rules and scoring

1. **How is a round scored?** Each loser scores minus the value of the tiles left in their rack (number value, jokers 30), and the winner scores plus the sum of those. *Why:* it's the standard scoring, and everyone already knows it.
2. **What happens when the draw pile runs out?** Play goes on. Passing with an empty pile draws nothing. When every player passes in a row with the pile empty, the round ends, the lowest rack wins, and each loser's penalty is the difference between their rack and the winner's. *Why:* this is the classic rule, and it guarantees that a round always ends.
3. **Is there a target score that ends the whole game?** No. Rounds continue with a running total until you leave. *Why:* game nights vary in length, and a target can be a house rule later.
4. **Who starts?** Round 1 starts with the first seat (you in Practice, the host online, or player 1 in Pass-and-play), and the first player rotates every round. *Why:* it's simpler than the classic "everyone draws a tile" ritual and still fair over several rounds.
5. **Which way do runs go?** Runs must ascend from left to right, for example 4 5 6. *Why:* a joker's value then comes from its position alone, so it's never ambiguous.
6. **Is a joker's value shown on the tile?** No. Its value comes from where it sits: its position in a run, or the number in a group. *Why:* it keeps the mascot art clean. A small value hint could come later if people get confused.
7. **Can a set be all jokers (for example 3 jokers with 3 or 4 jokers in play)?** No. Every set needs at least one numbered tile. *Why:* otherwise the set has no defined value.
8. **How does a set like `5 joker joker` count?** It counts as the higher-scoring valid reading: the run 5 6 7 (18) beats the group 5 5 5 (15). *Why:* this matters for reaching the first-meld minimum and favours the player.
9. **What does the first meld allow?** It may use only tiles from your own rack, it must reach the minimum (30 by default), and you can't touch the table that turn. Once you have melded, you can rearrange freely on later turns. With the first-meld rule set to Off, there's no minimum and you can rearrange from turn 1. *Why:* these are the classic rules, and Off is the simplest house variant.
10. **Can you take a joker back off the table?** You can move a table joker anywhere, like any table tile, as long as the board ends the turn valid. Table tiles can never go back into a rack. *Why:* the board-validity check already covers the classic "replace the joker" rule without a special case.
11. **Can you draw after putting tiles down?** No. The button says Draw only while you haven't played anything this turn. Undo or reset first if you want to draw instead. *Why:* this matches the classic rules (play or draw, not both).
12. **What happens on timeout?** As agreed: a valid board ends the turn normally. Otherwise the board resets, the tiles return to the rack, the player draws as if passing, and a message says "*Name* ran out of time." *Why:* this follows your spec, and the message explains the sudden change.
13. **What does Pass do when the pile is empty?** The button reads "Pass" and draws nothing. *Why:* it makes it clear that nothing will be drawn.

## B. Table, rack and gestures

14. **Where do dropped tiles land when dropped on top of a set?** The tile is inserted into that set. Dropping on the left half of a tile puts it before that tile, and the right half puts it after. *Why:* it lets you fill a gap or extend at the right edge of the board by dragging alone.
15. **When does a dropped tile join a neighbouring set versus push it aside?** It joins when the result could still become a valid run or group ("compatible", so partial sets of 1 or 2 tiles count). Otherwise the neighbour moves 1 space aside. *Why:* you can build new sets tile by tile, and a wrong tile never merges by accident.
16. **Tap a tile, then tap a 1 or 2 tile partial set?** It joins if it's compatible. With a full set (3 or more), the result must be a valid set or the glow flashes red. *Why:* it keeps tap-building consistent with dragging.
17. **Tap a tile, then tap an empty spot on the table?** The tile goes there. Tapping the rack while a tile you played this turn is selected sends it back. *Why:* tapping can do everything dragging does, which is easier on small screens.
18. **How many rows does the table start with?** 5. It grows when something needs room (the never-blocked rule, or Make space), and extra empty rows at the bottom are trimmed at the end of each turn. *Why:* phones in landscape are short, and fewer rows mean bigger tiles.
19. **Should the table shrink when the rack slides up, or should the rack cover the table?** The table shrinks (zooms out) so no row ever hides behind the rack. *Why:* hidden rows would let tiles disappear behind the rack. The trade-off is smaller table tiles while you hold more than 10.
20. **What does the rack do past 20 tiles?** It stays at 2 rows, which share the tiles evenly, and the tiles get narrower. *Why:* a third row would squeeze the table too much.
21. **Should invalid sets be marked during your turn?** Yes: a red outline on sets that aren't valid yet, plus a gold shine when a placement makes a valid set. It can be turned off in Options under Tile highlighting. *Why:* you see problems before you press End turn.
22. **What does Undo do?** It steps back one move within your turn. Reset this turn (in the menu) returns the whole table to the start of the turn. *Why:* there's a small step back and a big one.
23. **Can you drag or long-press table sets before your first meld?** No. The tiles flash red and a message explains why. *Why:* the move would be refused at End turn anyway.
24. **Do other players watch your moves live?** Yes. Every change you make is shown on the other phones as you make it, with tiles flying from your face-down indicator. *Why:* it's more social, and the host needs your latest board to judge a timeout.
25. **Where do opponents sit?** With 2 players the opponent sits at the top. With 3 they sit left and right, and with 4 they sit left, top and right, in turn order going clockwise from you. *Why:* it matches the mockup and keeps the side columns balanced.
26. **Orientation?** Landscape only. *Why:* the 27-space rows need the width.
27. **Where is the draw pile?** In the top-right corner, with the tile count. *Why:* the right column is taken by the right-hand seat's indicator tiles, and the corner keeps draws visible.
28. **Where does Make space sit?** To the left of the rack, level with its top row. *Why:* that's what you asked for, and it stays clear of your name and timer.

## C. Computer players (Practice, and bots in online lobbies)

29. **Difficulty numbers?** Easy places at most 3 tiles a turn and overlooks 40% of the plays it finds. Medium places at most 6 and overlooks 15%. Hard has no limit and plays everything it finds. All of these are in `BotTuning`. *Why:* this follows your request.
30. **How fast do bots play?** A bot decides its whole turn instantly, with no thinking delay, then carries it out one action at a time. Each action shows on the table and is followed by a pause: 0.5 s for a single tile (a rack tile extending a set, or a tile moved on the table), 1 s for a split or a whole set moved on the table, and 2 s for a new set put down from the rack (all its tiles fly in together). The turn ends after the last pause. A bot that draws does so at once. The constants are `singleTileMs`, `splitOrSetMoveMs` and `newSetMs` in `BotTuning`. *Why:* this follows your pacing spec. Today's bots never split or move sets, so the 1 s pause is ready for smarter bots.
31. **What can bots do on the table?** They put down new sets and extend the ends of existing sets. They don't rearrange or split sets. *Why:* it's simple, legal, and beatable. Hard bots that rearrange could come later.
32. **What if a bot's tile cap stops it reaching the first-meld minimum?** It draws. *Why:* an Easy bot should sometimes struggle to get started.
33. **Bot names?** Rosa, Theo and Juno, with the difficulty shown, for example "Rosa (Medium)". *Why:* it's friendly, and you can see at a glance who is who.
34. **Can bots fill empty seats online?** Yes, the host can add Easy, Medium or Hard bots in the lobby. *Why:* a 2-person online game can become a 4-player table.

## D. Online play

35. **What format is the room code?** 6 characters with no look-alikes (no 0/O or 1/I/L). *Why:* it's easy to read out loud.
36. **What if the host leaves?** The game ends for everyone with "The host closed the game." There's no host migration. *Why:* the host's phone holds the game, so moving it is a bigger feature.
37. **What if a guest drops?** Their seat shows "(offline)", their turns pass automatically after 5 seconds, and joining again with the same code and name gets the seat back. *Why:* one bad signal shouldn't stop the game.
38. **Can someone join a game in progress?** Only to take back their own seat. New players wait for the next game. *Why:* there are no extra tiles to deal mid-round.
39. **How many friends per message invite?** One invite per friend. The host taps "Invite by message" again for each one. *Why:* each phone-to-phone link needs its own invite and reply.
40. **Who edits the house rules?** The host only. Guests see a summary in the lobby and in the game menu. *Why:* it gives one source of truth.
41. **Do Test tools affect online games?** No, only Practice and Pass-and-play. *Why:* so nobody gets a joker handed to them in a real game.
42. **Is an unfinished game saved if the app closes?** Not in v0.1. *Why:* it's planned for the polish step, and the engine state is already plain data that can be saved.

## E. Look, sound and wording

43. **Sounds?** None in v0.1. Vibration (light taps on pick-up and drop) is on by default and can be switched off in Options. *Why:* sound needs real assets, and silent play suits game nights.
44. **Avatars?** A coloured circle with the player's initial, and a robot icon for bots. *Why:* there's nothing to upload or store, and it matches the mockup.
45. **Default name?** "Player", changeable in Options or on the Join screen. *Why:* there's no sign-up.
46. **What does the main button say?** "Draw" when you haven't played, "End turn" once you have, "Pass" when the pile is empty, and a greyed "Draw / End turn" on others' turns. *Why:* it always says exactly what will happen.
47. **What does the Pass-and-play cover screen say?** "Pass the phone to *Name*" and "Everyone else, look away from the rack", with the button "I'm *Name*, start my turn". Your turn timer starts only when you tap the button. *Why:* nobody loses time while the phone changes hands.
48. **What does the results screen show?** The winner, why the round ended, each player's leftover tiles, the round score and the running total, plus Next round and Home. *Why:* the leftover tiles make the scoring easy to check.
49. **Is there a pause?** Opening the menu in Practice or Pass-and-play pauses the timer and the bots. Online games can't be paused. *Why:* you can't pause other people's phones fairly.
50. **What's the home screen tagline?** "Tiles with friends. No ads, no servers." *Why:* it says what makes Michikub different.
51. **Should the joker art be thicker?** The line art was thickened for tile size (a bolder version of your 4-colour drawing). *Why:* the original lines vanish at about 30 px.
