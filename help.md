# General guide

**!command _parameter1_ ?_parameter2_?**

**_parameter1_**   Required parameter

**?_parameter2_?**   Optional parameter

# Meta Commands
**!setup _type_ _channel_**

Assign a channel for the bot to post new events. Channel is the discord channel (preceded by a hash) or the channel ID.

 - **!setup _log_ _channel_**
  
   The bot will log message deletes, joins, parts and such in this channel.

 - **!setup _anime_ _channel_**
 
   The bot will log new anime releases from www.gogoanime.to in this channel.
   
**!botstats**

Displays some stats of the bot across all servers.

**!help**

Links to this page.

# Moderation Commands

**!ban _user_**

Bans a user from the bot's commands. **This does not ban the user from the server, you should do that through discord itself**. Only users with the Admin, Manage Guild and Manage Channels permissions can use this command. _user_ can be the actual user ID on discord, the username of the user or the user's tag (e.g. @Username).


**!unban _user_**

Unbans a user from the bot's commands. **This does not ban the user from the server, you should do that through discord itself**. Only users with the Admin, Manage Guild and Manage Channels permissions can use this command. _user_ can be the actual user ID on discord, the username of the user or the user's tag (e.g. @Username).

**!bulkdelete _number_**

Deletes the past _number_ messages in the current channel. Only users with the Admin, Manage Guild and Manage Channels permissions can use this command.

# Custom Commands

**!8ball _question_**

Ask the Magic 8-Ball for advice. Questions should end with a question mark. Supported questions include 'where', 'who', 'when', 'why', 'how many/much' and 'yes/no' questions. 'what', 'how' and 'which' questions are not supported.

**!subscribe _animename_ ?_-format from > to_?**

Adds a subscription for an anime. The bot will additionally DM you when the anime is added to the www.gogoanime.to website. The optional format option will take a regular expression _from_ and substitute with _to_. The result of substitution is the link sent via DM.

**!unsubscribe _animename_**

Removes subscription for an anime, or use 'all' to remove all subscriptions.

**!viewsubs**

Displays the user's current anime subscriptions.

**!whois _user_**

Gives the information about a specific _user_. _user_ can be the actual user ID on discord, the username of the user or the user's tag (e.g. @Username).

**!snowflake _snowflake_**

Returns the datetimestamp of the snowflake.

# Pokemon related commands

**!hp _IVs_**

Gives the Hidden Power type from a set of IVs of a Pokemon separated by a space. The order of the IVs are: HP Atk Def Spd SpA SpD and range between 1 and 31.

**!pokedex ?_mode_? ?_options_?**

Fetches the information about a Pokemon from the Bot's database. The current information is outdated. The following options exist:

 - **!pokedex _pokemon_**
 
   Fetches details about the Pokemon
 
 - **!pokedex next _pokemon_**
 
   Fetches additional details about the Pokemon
 
 - **!pokedex search _text_**
 
   Looks into the database for any Pokemon matching the text in any way. Returns a list of Pokemon.
   
 - **!pokedex random _number_ ?_options_?**
 
   Returns a list of random Pokemon. The number of Pokemon returned is specified by *number*. Options include: **-region _kanto|johto|hoenn|sinnoh|unova|kalos|alola_**, **-final _0|1_** and **-legend _0|1_**. Example usage:
   
       !pokedex random 6 -region kanto|johto -final 1 -legend 0
       
   will give a list of random 6 Pokemon which are from either the Kanto or the Johto region that are in their final evolution state and that are not legendary.
   
**!ability ?_mode_? _ability_**

Fetches the information about an ability from the Bot's database. The current information is outdated. The following options exist:
 - **!ability _ability_**
 
   Fetches details about the ability
 
 - **!ability search _text_**
 
   Looks into the database for any ability matching the text in any way. Returns a list of abilities.
   
**!move ?_mode_? _move_**

Fetches the information about a move from the Bot's database. The current information is outdated. The following options exist:
 - **!move _move_**
 
   Fetches details about the move
   
 - **!move search _text_**
 
   Looks into the database for any move matching the text in any way. Returns a list of moves.
   
**!item ?_mode_? _item_**

Fetches the information about an item from the Bot's database. The current information is outdated. The following options exist:

 - **!item _item_**
 
   Fetches details about the item.
   
 - **!item search _text_**
 
   Looks into the database for any item matching the text in any way. Returns a list of items.
