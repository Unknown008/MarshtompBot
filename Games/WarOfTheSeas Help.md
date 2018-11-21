**!host**
Host and create a game of War of the Seas. Can be used in any channel. Other commands below can only be used in the default game channel.

**!join**
Join a game of War of the Seas (up to 4 players can play the game)

**!in**
Same as **!join**

**!drop ?user?**
Quit the current game. Only the host can specify a user.

**!out**
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

**!wotsset cmd**
It is the only other command that can be used in any channel. Available to users with the Manage Guild role or higher. Sub commands are as follow:
     **guild on|off**
     By default, the game is enabled on a server. Use **!wotsset guild off** to disable it.
     
     **channel on|off channel**
     By default, the game is enabled on all channels. Use **!wotsset channel off #channel** to disable it on the specified channel. Multiple channels can be specified by enclosing the channels between braces e.g. {#chan1 #chan2}.
     
     **ban on|off user**
     Bans the user from all War of the Seas commands. Multiple users can be specified by enclosing the users between braces e.g. {@user1 @user2}
     
     **category**
     Sets the category name where the War of the Seas channels will be managed by the bot. The default category name is "games".
     
     **default_channel**
     Sets the name of the channel where the War of the Seas commands can be used and where I will put the game highlights. The default channel name is "waroftheseas-sepctator"
