# General guide

The general syntax for any command is as follows:

**!command _parameter1_ ?_parameter2_?**

**_parameter1_**   Required parameter

**?_parameter2_?**   Optional parameter

# Meta Commands
**!setup _type_ ?_channel_?**

Assigns a channel for the bot to post new events. Channel is the discord channel (preceded by a hash) or the channel ID. Omitting the channel will set the current channel to the requested setting (command synonyms: 'chanset', 'guildset', 'serverset', 'config').

 - **!setup _log_ ?_channel_?**
  
   The bot will log message deletes, joins, parts and such in this channel.

 - **!setup _anime_ ?_channel_?**
 
   The bot will log new anime releases from nyaa.si in this channel.

 - **!setup _serebii_ ?_channel_?**
 
   The bot will log daily news from serebii.net in this channel.
   
**!botstats**

Displays some stats of the bot across all servers.

**!help**

Links to this page.

**!about**

Posts a few lines about the bot.

# Moderation Commands

**!ban _user_ ?_duration_? ?_reason_?**

Bans a user from the bot's commands. **This does not ban the user from the server, you should do that through discord itself**. Only users with the Admin, Manage Guild and Manage Channels permissions can use this command. _user_ can be the actual user ID on discord, the username of the user or the user's tag (e.g. @Username). Duration is optional (by default, bans are permanent) and can be denoted in minutes, hours, days, etc. A duration of 1y2M3w4d5h6m7s will impose a ban of 1 year, 2 months, 3 weeks, 4 days, 5 hours, 6 minutes and 7 seconds. Only positive integers are accepted. Reason is also optional and can be any text.

**!unban _user_**

Unbans a user from the bot's commands. **This does not ban the user from the server, you should do that through discord itself**. Only users with the Admin, Manage Guild and Manage Channels permissions can use this command. _user_ can be the actual user ID on discord, the username of the user or the user's tag (e.g. @Username).

**!delete _messageId_**

Deletes the message with the corresponding message ID in this guild. Only users with the Manage Messages permissions can use this command. If you enable developer mode in your discord settings, you should get a new option under the three dots for hovering over a message named 'Copy ID'. That's the message ID.

**!bulkdelete _number_**

Deletes the past _number_ messages in the current channel. Only users with the Admin, Manage Guild and Manage Channels permissions can use this command.

# Custom Commands

**!8ball _question_**

Ask the Magic 8-Ball for advice. Questions should end with a question mark. Supported questions include 'where', 'who', 'when', 'why', 'how many/much' and 'yes/no' questions. 'what', 'how' and 'which' questions are not supported.

**!whois ?_user_?**

Gives the information about a specific _user_. _user_ can be the actual user ID on discord, the username of the user or the user's tag (e.g. @Username). If _user_ is omitted or is supplied as **me**, it will return the whois for the user who used the command.

**!snowflake _snowflake_**

Returns the datetimestamp of the snowflake.

# Anime-Manga Commands

**!subscribe _animename_ ?_-format from > to_?**

Adds a subscription for an anime. The bot will additionally DM you when the anime is added to the www.gogoanime.to website. The optional format option will take a regular expression _from_ and substitute with _to_. The result of substitution is the link sent via DM.

**!unsubscribe _animename_**

Removes subscription for an anime, or use 'all' to remove all subscriptions.

**!viewsubs**

Displays the user's current anime subscriptions.

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
 
   Returns a list of random Pokemon. The number of Pokemon returned is specified by *number* (must be an integer). Options include: **-region _kanto|johto|hoenn|sinnoh|unova|kalos|alola|galar_**, **-final _0|1_** and **-legend _0|1_**. Example usage:
   
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

# Fage/Grand Order commands

**!fgoservant _mode_ ?_options_?**

Manages the servants registed under your account. Note this is not linked to the actual Fate/Grand Order game server so you have to manage this data yourself. The following options exist:

  - **!fgoservant add _options_**

    Adds one or more servants to your account. Creates an account for you if you don't already have one. The following options exist:
      - **!fgoservant add _servantName|servantId_ _servantLvl_ _servantAscension_ _servantSkill1Lvl_ _servantSkill2Lvl_ _servantSkill3Lvl_**
      - **!fgoservant add -name _servantName_|-id _servantId_ -level _servantLvl_ -ascension _servantAscension_ -skill1 _servantSkill1Lvl_ -skill2 _servantSkill2Lvl_ -skill3 _servantSkill3Lvl**

        The above are synonymous, the only difference being that the second form specifies the data being inserted and can thus be entered in any order. Use skill level 1 if it is still locked.

      - **!fgoservant add -url url**

        This command is used to bulk add servants, from a csv format from any online file hosting website. (e.g. https://gist.githubusercontent.com/Unknown008/d836d6ab1e9ba3f1be79e74d539f0c12/raw/9cdfbba92dc16ea1e38d5b2533b5a27d37e63d8c/fatego where the columns are from left to right, the servant ID, the level, the ascension level, the skill levels 1, 2 and 3)

**!fgolookup**

Fetches the information about a Pokemon from the Bot's database. The current information is outdated. The following options exist:

 - **!fgolookup _servantName_**
 
   Fetches details about the servant