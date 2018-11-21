# Commands
**!host**

Host and create a game of War of the Seas. Can be used in any channel. Other commands below can only be used in the default game channel.

**!join**

Join a game of War of the Seas (up to 4 players can play the game)

**!in**

Same as **!join**

**!drop ?_user_?**

Quit the current game. Only the host can specify a user.

**!out ?_user_?**

Same as **!drop**

**!start**

Cancel the waiting time for players and start the game immediately.

**!stop**

Stop the current game.

**!cancel**

Same as **!stop**

**!abort**

Same as **!stop**

**!pause**

Pause the current game.

**!resume**

Resume the current game.

**!wotshelp**

Display the link to this page.

**!wotsset _cmd_**

It is the only other command that can be used in any channel. Available to users with the Manage Guild role or higher. Sub commands are as follow:

- **guild _on|off_**

  By default, the game is enabled on a server. Use **!wotsset guild off** to disable it.
     
- **channel _on|off_ _channel_**

  By default, the game is enabled on all channels. Use **!wotsset channel off #channel** to disable it on the specified channel. Multiple channels can be specified by enclosing the channels between braces e.g. **!wotsset channel off {#chan1 #chan2}**.
     
- **ban _on|off_ _user_**

  Bans the user from all War of the Seas commands. Multiple users can be specified by enclosing the users between braces e.g. **!wotsset ban on {@user1 @user2}**
     
- **category _categoryName_**

  Sets the category name where the War of the Seas channels will be managed by the bot. The default category name is "games".
     
- **default_channel _channelName_**

  Sets the name of the channel where the War of the Seas commands can be used and where I will put the game highlights. The default channel name is "waroftheseas-sepctator"
  
# Gameplay
When a game has begun, use numbers to tell the bot what you want to do. For example, the bot will first decide on the attacker randomly and ask the player who they want to attack. In this situation, post a number which will correspond to one of the players. At other times, the bot will ask a player which card to play. Post a number and the bot will understand that you have played a card with the corresponding number.

1. Each player gets dealt out seven cards, this forms their crew. The rest of the cards are placed in the middle of the table, this is the card pile.
2. One of the players will be randomly chosen to be the attacker on the first turn.
3. The attacker will pick a player (called defender) against whom to battle.
4. Both the attacker and the defender will set a card in front of them.
5. The defender can choose to activate the ability of their card if the card has a value between 1 and 4 inclusive. Before the ability revolves, the attacker may choose to block the ability by calling its value (calling type is not allowed here).
   1. If the attacker calls the right value, the ability is blocked and the game resumes with the next step.
   2. If the attacker calls a wrong value, the defender will act according to the effect of the ability.
6. The attacker can choose to activate the ability of their card if the card has a value between 1 and 4 inclusive. Before the ability resolves, the defender may choose to block the ability by calling its value (calling type is not allowed here).
   1. If the defender calls the right value, the ability is blocked and the game resumes with the next step.
   2. If the attacker calls a wrong value, the attacker will act according to the effect of the ability.
7. The defender can choose to make a Recon Call (call either the value or the type of the attacker’s card – if the attacker activated their card’s ability during this battle, the defender cannot make a type call).
   1. If the defender calls a value call, 
      1. and guesses correctly, the attacker loses the battle and the defender draws a card from the card pile.
      2. and guesses incorrectly, the game resumes with the next step.
   2. If the defender calls a type call,
      1. and guesses correctly, the attacker loses 3 points to their card
      2. and guesses incorrectly, the defender loses the battle and the attacker draws a card from the card pile.
8. The attacker can choose to make a Recon Call (call either the value or the type of the defender’s card - if the defender activated their card’s ability during this battle, the attacker cannot make a type call).
   1. If the attacker calls a value call, 
      1. and guesses correctly, the defender loses the battle and the attacker draws a card from the card pile.
      2. and guesses incorrectly, the game resumes with the next step.
   2. If the attacker calls a type call,
      1. and guesses correctly, the defender loses 3 points to their card
      2. and guesses incorrectly, the attacker loses the battle and the defender draws a card from the card pile.   
9. At this point if neither the attacker nor defender lost, the player with the highest total score on their cards wins the battle.
10. The winner draws a card from the card pile.
11. The person to the left of the attacker then becomes the new attacker.
12. Steps 3 through 11 will be repeated until only one player stands with a crew.

## Ability Cards
There are 4 Ability Cards (value 1-4)- 
- Mutiny - Skull

  Steal a played card from you opponent. The opponent must play another card from his hand into battle. If they are unable to (no cards in hand), the opponent loses. The opponent’s new card has to set. If the opponent already activated the ability of a card during this battle, they cannot activate the new card’s ability. The stolen card is played on the player’s side.

- Reinforcements - Ship

  Draw a card one from the card pile and play a new card from the hand. This additional card’s ability cannot be activated and is played face up. Do not draw if there are no more cards in the card pile.

- Steal - Sword

  Steal a card from the opponent’s hand. If the opponent has no cards in hand, this ability does nothing. The stolen card is played on the player’s side.

- Trade - Coin

  Discard one card from your hand and draw a new one from the card pile. If you have no cards in hand, draw a card from the card pile. Do not draw if there are no more cards in the card pile.

