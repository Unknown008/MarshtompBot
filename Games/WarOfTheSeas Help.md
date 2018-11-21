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
