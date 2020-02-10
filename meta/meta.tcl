# meta.tcl --
#
#       This file handles the essential procedures for a discord bot.
#
# Copyright (c) 2018, Jerry Yong
#
# See the file "LICENSE" for information on usage and redistribution of this
# file.

namespace eval meta {
    sqlite3 metadb "${scriptDir}/meta/metadb.sqlite3"
    metadb eval {
        CREATE TABLE IF NOT EXISTS banned(
            userId text
        )
    }
    metadb eval {
        CREATE TABLE IF NOT EXISTS config(
            guildId text,
            type text,
            channelId text
        )
    }
    
    set botstats(order) {
        UPTIME RESUMED READY CHANNEL_CREATE CHANNEL_UPDATE CHANNEL_DELETE
        GUILD_CREATE GUILD_UPDATE GUILD_DELETE GUILD_BAN_ADD GUILD_BAN_REMOVE
        GUILD_MEMBER_ADD GUILD_MEMBER_REMOVE GUILD_MEMBER_UPDATE 
        GUILD_EMOJI_UPDATE GUILD_INTEGRATIONS_UPDATE GUILD_ROLE_CREATE 
        GUILD_ROLE_UPDATE GUILD_ROLE_DELETE MESSAGE_CREATE MESSAGE_UPDATE 
        MESSAGE_DELETE MESSAGE_DELETE_BULK PRESENCE_UPDATE TYPING_START 
        USER_UPDATE MESSAGE_REACTION_ADD MESSAGE_REACTION_REMOVE 
        CHANNEL_PINS_UPDATE PRESENCES_REPLACE MESSAGE_ACK CHANNEL_PINS_ACK 
        CHANNEL_PINS_UPDATE PRESENCES_REPLACE   
    }
    set botstats(UPTIME)                    [clock seconds]
    set botstats(READY)                     0
    set botstats(RESUMED)                   0
    set botstats(CHANNEL_CREATE)            0
    set botstats(CHANNEL_UPDATE)            0
    set botstats(CHANNEL_DELETE)            0
    set botstats(GUILD_CREATE)              0
    set botstats(GUILD_UPDATE)              0
    set botstats(GUILD_DELETE)              0
    set botstats(GUILD_BAN_ADD)             0
    set botstats(GUILD_BAN_REMOVE)          0
    set botstats(GUILD_MEMBER_ADD)          0
    set botstats(GUILD_MEMBER_REMOVE)       0
    set botstats(GUILD_MEMBER_UPDATE)       0
    set botstats(GUILD_EMOJI_UPDATE)        0
    set botstats(GUILD_INTEGRATIONS_UPDATE) 0
    set botstats(GUILD_ROLE_CREATE)         0
    set botstats(GUILD_ROLE_UPDATE)         0
    set botstats(GUILD_ROLE_DELETE)         0
    set botstats(MESSAGE_CREATE)            0
    set botstats(MESSAGE_UPDATE)            0
    set botstats(MESSAGE_DELETE)            0
    set botstats(MESSAGE_DELETE_BULK)       0
    set botstats(PRESENCE_UPDATE)           0
    set botstats(TYPING_START)              0
    set botstats(USER_UPDATE)               0
    set botstats(MESSAGE_REACTION_ADD)      0
    set botstats(MESSAGE_REACTION_REMOVE)   0
    set botstats(CHANNEL_PINS_UPDATE)       0
    set botstats(PRESENCES_REPLACE)         0
    set botstats(MESSAGE_ACK)               0
    set botstats(CHANNEL_PINS_ACK)          0
    set botstats(CHANNEL_PINS_UPDATE)       0
    set botstats(PRESENCES_REPLACE)         0
    
    set localLimits {}
}

# meta::build_logs --
#
#   Creates chatlog tables for each guild the bot is present in if they do
#   not exist yet
#
# Arguments:
#   guildId  (optional) If provided, attempts to create one table named 
#            chatlog_$guildId. If not provided, will attempt to create a table
#            for each guild the bot is in.
#
# Results:
#   None

proc meta::build_logs {{guildId {}}} {
    if {$guildId == ""} {
        set guilds [guild eval {SELECT * FROM guild}]
        foreach {guildId data} $guilds {
            metadb eval "
                CREATE TABLE IF NOT EXISTS chatlog_${guildId}(
                    msgId text,
                    userId text,
                    content text,
                    embed text,
                    attachment text,
                    pinned text
                )
            "
        }
    } else {
        metadb eval "
            CREATE TABLE IF NOT EXISTS chatlog_${guildId}(
                msgId text,
                userId text,
                content text,
                embed text,
                attachment text,
                pinned text
            )
        "
    }
}

# meta::command --
#
#   Checks if a CREATE_MESSAGE event matches any commands in this namespace or
#   from a sourced file.
#
# Arguments:
#   data       dictionary of the message (converted from JSON response)
#   text       content of the message
#   channelId  channel ID from which the message was received from
#   guildId    guild ID from which the message was received from
#   userId     user ID from whom the message was received from
#
# Results:
#   None

proc meta::command {data text channelId guildId userId} {
    set banned [metadb eval {SELECT userId FROM banned WHERE userId = :userId}]
    if {$userId in $banned} {return}
    switch [lindex $text 0] {
        "!setup" {
            if {
                [has_perm $userId {ADMINISTRATOR MANAGE_CHANNELS MANAGE_GUILD}]
            } {
                setup [regsub {!setup *} $text {}]
            }
        }
        "!ban" {
            if {
                [has_perm $userId {ADMINISTRATOR MANAGE_CHANNELS MANAGE_GUILD}] 
                || $userId == $::ownerId
            } {
                ban [regsub {!ban *} $text {}]
            }
        }
        "!unban" {
            if {
                [has_perm $userId {ADMINISTRATOR MANAGE_CHANNELS MANAGE_GUILD}]
                || $userId == $::ownerId
            } {
                unban [regsub {!unban *} $text {}]
            }
        }
        "!botstats" {
            put_bot_stats
        }
        "!delete" {
            if {
                [has_perm $userId {MANAGE_MESSAGES}]
                || $userId == $::ownerId
            } {
                deletedc [regsub {!delete *} $text {}] $channelId
            }
        }
        "!bulkdelete" {
            if {
                [has_perm $userId {ADMINISTRATOR MANAGE_CHANNELS MANAGE_GUILD}] 
                || $userId == $::ownerId
            } {
                set option [lassign [regsub {!bulkdelete *} $text {}] n]
                bulk_delete $n $option
            }
        }
        "!help" {
            help
        }
        "!about" {
            about
        }
        default {
            # Other commands
            if {[::custom::command]} {
                return
            } elseif {[::pokebattle::command]} {
                return
            } elseif {[::pokedex::command]} {
                return
            } elseif {[::stats::command]} {
                return
            } elseif {[::pogo::command]} {
                return
            } elseif {[::anime::command]} {
                return
            } elseif {[::fgo::command]} {
                return
            }
        }
    }
}

#############################
##### Public procedures #####
#############################

# meta::setup --
#
#   Manage the settings for automatic messages. Currently for logs, serebii 
#   articles and anime subs. Saves the settings per guild in the config sqlite3 
#   table
#
# Arguments:
#   arg    arg must be two words:
#             type - type of setting (log, serebii, anime
#             channel - channel ID, object or name
#
# Results:
#   Posts a message informaing whether the action was successful or not.

proc meta::setup {arg} {
    if {[llength [split $arg { }]] != 2} {
        set msg "Incorrect number of parameters.\nUsage: "
        append msg "!setup **type** **channel**"
        putdc [dict create content $msg] 0
        return
    }
    lassign [split $arg { }] type channel
    if {$type ni [list log anime serebii]} {
        putdc [dict create content \
                "Invalid setup type. Should be log, serebii or anime"] 0
        return
    }
    
    upvar guildId guildId
    set guildData [guild eval {SELECT data FROM guild WHERE guildId = :guildId}]
    set guildData {*}$guildData
    set channels [dict get $guildData channels]

    if {[regexp {^(?:<#([0-9]+)>|([0-9]+))$} $channel - m1 m2]} {
        set channelId $m1$m2
    } else {
        set chanNames [lmap x $channels {dict get $x name}]
        if {$channel ni $chanNames} {
            putdc [dict create content "Invalid channel."] 0
            return
        }
        set idx [lsearch $chanNames $channel]
        set channelId [dict get [lindex $channels $idx] id]
    }
    
    set channelIds [lmap x $channels {dict get $x id}]
    if {$channelId ni $channelIds} {
        putdc [dict create content "Invalid channel."] 0
        return
    }
    set res [metadb eval {
        SELECT channelId FROM config
        WHERE guildId = :guildId AND
        type = :type
    }]
    if {$res eq ""} {
        metadb eval {INSERT INTO config VALUES(:guildId, :type, :channelId)}
        set msg "<#$channelId> has been set as $type."
    } elseif {$res eq $channelId} {
        set msg "<#$channelId> is already set as $type!"
    } else {
        metadb eval {
            UPDATE config SET channelId = :channelId
            WHERE guildId = :guildId AND type = :type
        }
        set msg "$type was changed from <#$res> to <#$channelId>"
    }
    putdc [dict create content $msg] 0
}

# meta::ban --
#
#   Ban a user from using this bot's commands
#
# Arguments:
#   text   User object or user ID of the user to be banned
#
# Results:
#   Posts whether the ban was successful or not

proc meta::ban {text} {
    set users [guild eval {SELECT userId FROM users}]
    if {[regexp {<@!?([0-9]+)>} $text - userId] && $userId in $users} {
        set result [metadb eval {
            SELECT userId FROM banned WHERE userId = :userId
        }]
        if {$result != ""} {
            set msg "<@$userId> is already banned from my commands!"
        } else {
            metadb eval {INSERT INTO banned VALUES(@userId)}
            set msg "<@$userId> was banned from all my commands!"
        }
    } else {
        set msg "No such user found."
    }
    putdc [dict create content $msg] 0
}


# meta::unban --
#
#   Unban a user from using this bot's commands
#
# Arguments:
#   text   User object or user ID of the user to be unbanned
#
# Results:
#   Posts whether the unban was successful or not

proc meta::unban {text} {
    if {[regexp {<@!?([0-9]+)>} $text - userId]} {
        set result [metadb eval {
            SELECT userId FROM banned WHERE userId = :userId
        }]
        if {$result != ""} {
            metadb eval {DELETE FROM banned WHERE userId = :userId}
            set msg "<@$userId>'s ban from my commands was lifted!"
        } else {
            set msg "No ban for <@$userId> was found!"
        }
    } else {
        set msg "No such user found."
    }
    putdc [dict create content $msg] 0
}

# meta::put_bot_stats --
#
#   Posts the count for all registered events the bot has gone through in the
#   channel the command was invoked
#
# Arguments:
#   None
#
# Results:
#   None

proc meta::put_bot_stats {} {
    variable botstats
    set msg [list]
    set kmax 8
    set vmax 0
    
    lappend msg [list SERVERS [guild eval {SELECT COUNT(*) FROM guild}]]
    lappend msg [list CHANNELS [guild eval {SELECT COUNT(*) FROM chan}]]
    lappend msg ""
    foreach k $botstats(order) {
        if {$k eq "UPTIME"} {
            set v [formatTime [expr {[clock seconds]-$botstats($k)}]]
            lappend msg [list $k $v]
        } else {
            if {$botstats($k) > 0} {
                if {$botstats($k) > 1000} {
                    regsub -all {[0-9](?=(?:\d{3})+$)} $botstats($k) {\0,} v
                } else {
                    set v $botstats($k)
                }
                lappend msg [list $k $v]
            } else {
                continue
            }
        }
        set kmax [expr {[string len $k] > $kmax ? [string len $k] : $kmax}]
        set vmax [expr {[string len $v] > $vmax ? [string len $v] : $vmax}]
    }
    set msg [lmap x $msg {
        if {$x == ""} {
            set x
        } else {
            format "%-${kmax}s %${vmax}s" {*}$x
        }
    }]
    putdc [dict create content "```[join $msg \n]```"] 0
}

# meta::delete --
#
#   Deletes a message - WIP
#
# Arguments:
#   msgId    The ID of the message to be deleted
#
# Results:
#   None

proc meta::delete {msgId} {
    if {![has_perm [dict get [set ${sessionNs}::self] id] MANAGE_MESSAGES]} {
        set msg "I don't have the permission (Manage Messages) to execute this."
        putdc [dict create content $msg] 0
        return
    }

}

# meta::bulk_delete --
#
#   Deletes the previous messages in the current channel. 
#
# Arguments:
#   n        Number of messages to be deleted
#   options  Options for messages to be deleted (only one option will be 
#            considered):
#               before msgID
#               after  msgID
#               around msgID
#
# Results:
#   None

proc meta::bulk_delete {n option} {
    upvar guildId guildId
    if {![has_perm [dict get [set ${::session}::self] id] MANAGE_MESSAGES]} {
        set msg "I don't have the permission (Manage Messages) to execute this."
        putdc [dict create content $msg] 0
        return
    }
    upvar channelId channelId
    if {![string is integer -strict $n] && $n < 2 && $n > 100} {
        set msg {Invalid number of message supplied. Usage: **!bulkdelete }
        append msg {_number\_of\_messages option -force_**. __**option**__ can }
        append msg {be one of: __**before** msgId__, __**after** msgId__, }
        append msg {__**around** msgId__. Between 2 and 100 messages inclusive }
        append msg {can be bulk deleted.}
        putdc [dict create content $msg] 0
        return
    }
    set force 0
    set idx [lsearch $option "-force"]
    if {$idx > -1} {
        incr force
        set option [lreplace $option $idx $idx]
    }
    set options [lassign $option type value]
    set params [dict create limit $n]
    if {$type != ""} {
        if {
            $type in {before after around} && [string is integer -strict $value]
            && $value < 0
        } {
            dict set params $type $value
        } else {
            set msg {Invalid options. Usage: **!bulkdelete }
            append msg {_number\_of\_messages option -force_**. __**option**__ }
            append msg {can be one of: __**before** msgId__, __**after** }
            append msg {msgId__, __**around** msgId__.}
            putdc [dict create content $msg] 0
            return
        }
    }
    if {[catch {discord getMessages $::session $channelId $params 1} resCoro]} {
        return
    }
    if {$resCoro eq {}} {return}
    yield $resCoro
    set response [$resCoro]
    set data [lindex $response 0]
    if {$data eq {}} {
        set msg "An error occurred. Could not find messages to delete."
        putdc [dict create content $msg] 0
        return
    }
    set lMsg [list]
    set oMsg [list]
    set back [clock add [clock seconds] -14 days]
    set total [llength $data]
    foreach msg $data {
        set msgId [dict get $msg id]
        set msgDate [expr {
            [getSnowflakeUnixTime $msgId $::discord::Epoch]/1000
        }]
        if {$back < $msgDate} {
            lappend lMsg $msgId
        } elseif {$force} {
            lappend oMsg $msgId
        }
    }
    set cmd [expr {[llength $lMsg] < 2 ? deleteMessage : bulkDeleteMessages}]
    if {[catch {discord $cmd $::session $channelId $lMsg 1} resCoro]} {
        return
    }
    if {$resCoro eq {}} {return}
    yield $resCoro
    set response [$resCoro]
    if {[dict get [lindex $response 1] http] != "HTTP/1.1 204 NO CONTENT"} {
        set body [dict get [lindex $response 1] body]
        if {$body ne {} && [catch {json::json2dict $body} body]} {
            set msg [dict get $body message]
        } else {
            set msg "An error occurred. Could not delete messages."
        }
    } else {
        set del [llength $lMsg]
        if {$del != $n} {
            if {$total == $del} {
                set msg "Successfully deleted $del messages (only $del messages"
                append msg " had been posted to this channel)."
            } elseif {$force} {
                set msg "Successfully bulk deleted $del messages. The remaining"
                append msg " [expr {$n-$del}] messages will be individually "
                append msg "deleted within the next few moments."
                after idle [list coroutine ::meta::deletedc[::id] \
                        ::meta::deletedc $oMsg $channelId]
            } else {
                set msg "Successfully deleted $del messages ([expr {$n-$del}] "
                append msg "messages did not get deleted due to being too old -"
                append msg " bulk delete cannot be used for messages older than"
                append msg " 14 days)."
            }
        } else {
            set msg "Successfully deleted $n messages."
        }
    }
    after idle [list coroutine ::meta::putdc[::id] ::meta::putdc \
            [dict create content $msg] 0 $channelId]
}

# meta::help --
#
#   Posts a pastebin link to the help documents
#
# Arguments:
#   None
#
# Results:
#   None

proc meta::help {} {
    set msg "Available commands are listed here: "
    append msg "https://github.com/Unknown008/MarshtompBot/blob/master/help.md"
    putdc [dict create content $msg] 0
}

# meta::about --
#
#   Gives information about the bot
#
# Arguments:
#   None
#
# Results:
#   None

proc meta::about {} {
    set msg "Marshtomp is a bot managed by Unknown008#4135 created by "
    append msg "qwename#5406. The bot is a multipurpose bot with various "
    append msg "modules ranging from server management, anime torrent feed, "
    append msg "Pok\u00E9dex resource, Pok\u00E9mon news feed from serebii.net,"
    append msg " Fate Grand Order resource to various silly 'fun' modules like "
    append msg "classic 8ball. More features might have been implemented when "
    append msg "you see this message."

    putdc [dict create content $msg] 1
}

#############################
##### Private procedures ####
#############################

# meta::putdc --
#
#   Posts a message into a certain channel ID
#
# Arguments:
#   data       dictionary of the message (to be converted to JSON format)
#   encode     boolean, specifies whether the message contents should be html
#              encoded or not
#   channelId  (optional) channel ID to which the message should be posted to.
#              Defaults to the channel ID from meta::command (the channel the
#              command was posted in
#   cmdlist    (optional) list of commands to be executed after the message has
#              been successfully posted
#
# Results:
#   None

proc meta::putdc {data encode {channelId {}} {cmdlist {}}} {
    variable localLimits
    puts "meta::putdc called from [info level 1] with data $data"
    if {$channelId eq ""} {
        set channelId [uplevel #2 {set channelId}]
    } elseif {$channelId eq "test"} {
        set channelId 236097944158208000
    }
    
    set rateLimits $::discord::rest::RateLimits
    set route "/channels/$channelId"
    if {[dict exists $rateLimits $::token $route X-RateLimit-Remaining]} {
        dict for {k v} [dict get $rateLimits $::token $route] {
            dict set localLimits $route $k $v
        }
        set reset [dict get $localLimits $route X-RateLimit-Reset]
        if {
            [clock seconds] > $reset
            || [catch {dict get $localLimits $route sent} sent]
        } {
            set sent 0
        }
        set rem [dict get $localLimits $route X-RateLimit-Remaining]
        dict set localLimits $route sent [incr sent]
    } else {
        set rem 5
        if {![dict exists $localLimits $route sent]} {
            dict set localLimits $route sent 1
            set sent 1
        } else {
            set sent [dict get $localLimits $route sent]
            dict set localLimits $route sent [incr sent]
        }
    }
    
    if {$sent >= $rem && [info exists reset]} {
        set secsRemain [expr {$reset - [clock seconds]}]
        if {$secsRemain >= -3} {
            after [expr {(abs($secsRemain)+3)*1000}] [list coroutine \
                    ::meta::putdc[::id] ::meta::putdc $data $encode $channelId \
                    $cmdlist]
            return
        }
    }
    
    if {$encode && [dict exists $data content]} {
        set text [dict get $data content]
        set text [encoding convertto utf-8 $text]
        dict set data content $text
    }
    if {[catch {discord sendMessage $::session $channelId $data 1} resCoro]} {
        return
    }
    if {$resCoro eq {}} {return}
    yield $resCoro
    set response [$resCoro]
    set data [lindex $response 0]
    if {$data ne {} && $cmdlist != {}} {
        set cmdlist [lassign $cmdlist cmd]
        {*}$cmd $cmdlist
    }
}

# meta::putdcPM --
#
#   Posts a message into a certain private channel ID. If the channel does not
#   exist yet, create it then post the message.
#
# Arguments:
#   userId     user ID to whom the private message is directed to
#   msgdata    dictionary of the message (to be converted to JSON format)
#   encode     boolean, specifies whether the message contents should be html
#              encoded or not
#   cmdlist    (optional) list of commands to be executed after the message has
#              been successfully posted
#
# Results:
#   None

proc meta::putdcPM {userId msgdata encode {cmdlist {}}} {
    variable localLimits
    puts "meta::putdcPM called from [info level 1] with data $msgdata for $userId"
    if {$encode && [dict exists $msgdata content]} {
        set text [dict get $msgdata content]
        set text [encoding convertto utf-8 $text]
        dict set msgdata content $text
    }
    set channelId ""
    dict for {channelId dmChan} [set ${::session}::dmChannels] {
        set recipients [dict get $dmChan recipients]
        if {[llength $recipients] > 1} {continue}
        if {[dict get [lindex $recipients 0] id] eq $userId} {break}
    }
    
    set rateLimits $::discord::rest::RateLimits
    set route "/channels/$channelId"
    if {[dict exists $rateLimits $::token $route X-RateLimit-Remaining]} {
        dict for {k v} [dict get $rateLimits $::token $route] {
            dict set localLimits $route $k $v
        }
        set reset [dict get $localLimits $route X-RateLimit-Reset]
        if {[dict exists $localLimits $userId sent]} {
            set sent [dict get $localLimits $userId sent]
            dict unset localLimits $userId
            dict set localLimits $route sent $sent
        }
        if {
            [clock seconds] > $reset
            || [catch {dict get $localLimits $route sent} sent]
        } {
            set sent 0
        }
        set rem [dict get $localLimits $route X-RateLimit-Remaining]
        dict set localLimits $route sent [incr sent]
    } else {
        set rem 5
        if {![dict exists $localLimits $userId sent]} {
            dict set localLimits $userId sent 1
            set sent 1
        } else {
            set sent [dict get $localLimits $userId sent]
            dict set localLimits $userId sent [incr sent]
        }
    }

    if {$sent >= $rem && [info exists reset]} {
        set secsRemain [expr {$reset - [clock seconds]}]
        if {$secsRemain >= -3} {
            after [expr {(abs($secsRemain)+3)*1000}] [list coroutine \
                    ::meta::putdcPM[::id] ::meta::putdcPM $userId $msgdata \
                    $encode $cmdlist]
            return
        }
    }
    
    if {[catch {discord sendDM $::session $userId $msgdata 1} resCoro]} {
        set resCoro [discord createDM $::session $userId 1]
        if {$resCoro eq {}} {return}
        yield $resCoro
        set response [$resCoro]
        set data [lindex $response 0]
        if {$data ne {} && [dict exists $data recipients]} {
            dict set ${::session}::dmChannels [dict get $data id] $data
            set resCoro [discord sendDM $::session $userId $msgdata 1]
            yield $resCoro
            set response [$resCoro]
            set data [lindex $response 0]
            if {$data ne {} && $cmdlist != {}} {
                set cmdlist [lassign $cmdlist cmd]
                {*}$cmd $cmdlist
            }
        }
    } else {
        if {$resCoro eq {}} {return}
        yield $resCoro
        set response [$resCoro]
        set data [lindex $response 0]
        if {$data ne {} && $cmdlist != {}} {
            set cmdlist [lassign $cmdlist cmd]
            {*}$cmd $cmdlist
        }
    }
}

# meta::editdc --
#
#   Posts an edit to a message posted previously
#
# Arguments:
#   data       dictionary of the new message (to be converted to JSON format)
#   encode     boolean, specifies whether the message contents should be html
#              encoded or not
#   msgId      message ID of the message to be edited
#   channelId  channel ID the message was previously posted to
#   cmdlist    (optional) list of commands to be executed after the edit has
#              been successfully posted
#
# Results:
#   None

proc meta::editdc {data encode msgId channelId {cmdlist {}}} {
    if {
        $encode
        && [dict exists $data content] 
        && [dict get $data content] ne ""
    } {
        set text [dict get $data content]
        set text [encoding convertto utf-8 $text]
        dict set data content $text
    }
    if {
        [catch {
            discord editMessage $::session $channelId $msgId $data 1
        } resCoro]
    } {
        return
    }
    if {$resCoro eq {}} {return}
    yield $resCoro
    set response [$resCoro]
    set data [lindex $response 0]
    if {$data ne {} && $cmdlist != {}} {
        set cmdlist [lassign $cmdlist cmd]
        {*}$cmd $cmdlist
    }
}

# meta::deletedc --
#
#   Deletes a message with specified IDs
#
# Arguments:
#   msgId      list of message IDs to be deleted
#
# Results:
#   None

proc meta::deletedc {msgId {channelId {}}} {
    if {![string is wideinteger -strict [lindex $msgId 0]]} {
        putdc [dict create content "Invalid message ID"] 0
        return
    }
    
    variable localLimits
    
    if {$channelId eq ""} {
        set channelId [uplevel #2 {set channelId}]
    }
    
    set rateLimits $::discord::rest::RateLimits
    set route "/channels/$channelId"
    if {[dict exists $rateLimits $::token $route X-RateLimit-Remaining]} {
        dict for {k v} [dict get $rateLimits $::token $route] {
            dict set localLimits $route $k $v
        }
        set reset [dict get $localLimits $route X-RateLimit-Reset]
        if {
            [clock seconds] > $reset
            || [catch {dict get $localLimits $route sent} sent]
        } {
            set sent 0
        }
        set rem [dict get $localLimits $route X-RateLimit-Remaining]
        dict set localLimits $route sent [incr sent]
    } else {
        set rem 5
        if {![dict exists $localLimits $route sent]} {
            dict set localLimits $route sent 3
            set sent 3
        } else {
            set sent [dict get $localLimits $route sent]
            dict set localLimits $route sent [incr sent]
        }
    }
    
    if {$sent >= $rem} {
        set secsRemain [expr {$reset - [clock seconds]}]
        if {$secsRemain >= -3} {
            after [expr {(abs($secsRemain)+3)*1000}] [list coroutine \
                    ::meta::deletedc[::id] ::meta::deletedc $msgId $channelId]
            return
        }
    }
    set msgId [lassign $msgId id]
    if {[catch {discord deleteMessage $::session $channelId $id 1} resCoro]} {
        return
    }
    if {$resCoro eq {}} {return}
    yield $resCoro
    set response [$resCoro]
    if {[dict get [lindex $response 1] http] == "HTTP/1.1 204 NO CONTENT"} {
        if {$msgId != ""} {
            deletedc $msgId $channelId
        }
    }
}

# meta::update_members --
#
#   Update the guilds database with the actual members. GIULD_CREATE might have
#   sent an incomplete list for various reasons
#
# Arguments:
#   None
#
# Results:
#   None

proc meta::update_members {} {
    set guilds [guild eval {SELECT * FROM guild}]
    foreach {guildId data} $guilds {
        set members [dict get $data members]
        set memCount [llength $members]
        set member_count [dict get $data member_count]
        if {$memCount != $member_count} {
            set members [list]
            set lastId 0
            set limit 1000
            while {$member_count > 0} {
                set range [expr {min($member_count, $limit)}]
                incr member_count -$range
                set resCoro [discord getMembers $::session $guildId $range \
                        $lastId 1]
                if {$resCoro eq {}} {return}
                
                yield $resCoro
                set response [$resCoro]
                set data [lindex $response 0]
                
                if {$data ne {}} {
                    foreach member $data {
                        set user [dict get $member user]
                        set userId [dict get $user id]
                        set userData [guild eval {
                            SELECT data FROM users WHERE userId = :userId
                        }]
                        set exists $userData
                        if {$userData == ""} {
                            dict for {k v} $user {
                                dict set userData $k $v
                            }
                            if {[dict exists $member nick]} {
                                dict set userData nick $guildId \
                                        [dict get $member nick]
                            }
                            guild eval {
                                INSERT INTO users VALUES (:userId, :userData)
                            }
                        } else {
                            set userData {*}$userData
                            if {[dict exists $member nick]} {
                                dict set userData nick $guildId \
                                        [dict get $member nick]
                            }
                            guild eval {
                                UPDATE users SET data = :userData
                                WHERE userId = :userId
                            }
                        }
                    }
                }
            }
        }
    }
}

# meta::log_delete --
#
#   Triggered when a message is deleted and posts the deleted message and the 
#   original author in the channel set as log through meta::setup
#
# Arguments:
#   guildId     guild ID from which the message was received
#   id          ID of the message
#   sourceId    channel from which the message was originally posted
#
# Results:
#   None

proc meta::log_delete {guildId id sourceId} {
    set channelId [metadb eval {
        SELECT channelId FROM config WHERE guildId = :guildId AND type = 'log'
    }]
    lassign [metadb eval "
        SELECT userId, content, attachment FROM chatlog_$guildId 
        WHERE msgId = :id 
    "] targetId content attachment
    
    set targetName [getUsernameNick $targetId $guildId {%s (%s)}]
    
    if {$channelId eq ""} {set channelId test}
    set callback [discord getAuditLog $::session $guildId {limit 10} 1]
    # No callback generated. Shouldn't really happen
    if {$callback eq "" || $targetId eq ""} {
        putdc [dict create content "Message #$id deleted from <#$sourceId>" \
            embed [dict create \
                color red \
        ]] 0 $channelId
    } else {
        yield $callback
        set response [$callback]
        set data [lindex $response 0]
        # Delete is in recent logs, logically always non-empty
        if {$data ne ""} {
            set auditObj ""
            foreach x [dict get $data audit_log_entries] {
                if {
                    [dict get $x id] > $id 
                    && [dict get $x action_type] == 72
                    && [dict get $x target_id] == $targetId
                    && [dict get $x options channel_id] == $sourceId
                    && [dict get $x options count] >= 1
                } {
                    set auditObj $x
                    break
                }
            }
            # Match found - user deleted someone else's message
            if {$auditObj != ""} {
                set userId [dict get $auditObj user_id]
                set userName [getUsernameNick $userId $guildId]
                set msg "Message #$id by *$targetName* deleted "
                append msg "from <#$sourceId> by *$userName*."
            # Match not found - user deleted own message
            } else {
                set msg "Message #$id by *$targetName* deleted "
                append msg "from <#$sourceId>."
            }
            set delMsg [dict create content $msg embed [dict create \
                description $content \
                color red \
            ]]
            if {$attachment ne ""} {
                set links [lmap x $attachment {dict get $x url}]
                dict set delMsg embed description \
                        "$content\nAttachments: [join $links {,}]"
            }
            putdc $delMsg 0 $channelId
        # Delete is not in recent logs, shouldn't happen
        } else {
            set msg "Message #$id deleted from <#$sourceId>"
            putdc [dict create content $msg \
                embed [dict create color red]
            ] 0 $channelId
        }
    }
    if {[info exists userId]} {
        ::stats::bump deleteMsg $guildId $sourceId $userId $content
    }
}

# meta::log_chat --
#
#   Triggered when a message is created and saves the message in 
#   chatlog_$guildId table.
#
# Arguments:
#   guildId     guild ID from which the message was received
#   msgId       message ID of the received message
#   userId      user ID from whom the message was received from
#   content     content of the message
#   embed       any message embeds
#   attachment  any attachments to the message
#
# Results:
#   None

proc meta::log_chat {guildId msgId userId content embed attachment} {
    metadb eval "
        INSERT INTO chatlog_$guildId VALUES (
            :msgId,:userId,:content,:embed,:attachment,'false'
        )
    "
    set len [metadb eval "SELECT COUNT(*) FROM chatlog_$guildId"]
    if {
        $::custom::say(state) == 1 
        && $content != "!say end"
        && $userId != [dict get [set ${::session}::self] id]
    } {
        upvar channelId channelId
        ::custom::say say [dict create content $content attachment $attachment]
    }
    while {$len > 1000} {
        set earliest [metadb eval "SELECT MIN(msgId) FROM chatlog_$guildId"]
        metadb eval "DELETE FROM chatlog_$guildId WHERE msgId = :earliest"
        set len [metadb eval "SELECT COUNT(*) FROM chatlog_$guildId"]
    }
    if {$content ne ""} {
        upvar channelId channelId
        after idle [list ::stats::bump createMsg $guildId $channelId $userId \
                $content]
    }
}

# meta::log_presence --
#
#   Logs change in user status (online, offline), game change
#
# Arguments:
#   guildId   Guild ID from which the event was received
#   userId    User ID for whom the event is for
#   data      dictionary from which the event was received (converted from JSON)
#
# Results:
#   None

proc meta::log_presence {guildId userId data} {
    set channelId [metadb eval {
        SELECT channelId FROM config WHERE guildId = :guildId AND type = 'log'
    }]
    if {$channelId eq ""} {set channelId test}
    if {![catch {dict get $data user username} newUsername]} {
        set userData [guild eval {
            SELECT data FROM users WHERE userId = :userId
        }]
        if {$userData == ""} {
            set userData [dict get $data user]
            guild eval {INSERT INTO users VALUES (:userId, :userData)}
        } else {
            set userData {*}$userData
            set prevUsername [dict get $userData username]
            if {$newUsername ne $prevUsername} {
                if {![catch {dict get $userData nick $guildId} nick]} {
                    set old "$old ($nick)"
                }
                if {![catch {dict get $data nick} nick]} {
                    set new "$new ($nick)"
                }
                dict set userData $userId username $new
                guild eval {UPDATE users SET data = :userData}
                set msg "$prevUsername changed their username to $newUsername."
                putdc [dict create content $msg] 1 $channelId
                after idle \
                        [list ::stats::bump nameChange $guildId "" $userId ""]
            }
        }
    }
    # Else check for game change or status change (log in/out)
}

# meta::log_member --
#
#   Logs change in nicknames and roles
#
# Arguments:
#   guildId   Guild ID from which the event was received
#   userId    User ID for whom the event is for
#   data      dictionary from which the event was received (converted from JSON)
#
# Results:
#   None

proc meta::log_member {guildId userId data} {
    set channelId [metadb eval {
        SELECT channelId FROM config WHERE guildId = :guildId AND type = 'log'
    }]
    if {$channelId eq ""} {set channelId test}
    set username [dict get $data user username]
    if {[catch {dict get $data nick} newNick]} {
        set newNick ""
    }
    set userData [guild eval {SELECT data FROM users WHERE userId = :userId}]
    set userData {*}$userData
    if {[catch {dict get $userData nick $guildId} prevNick]} {
        set prevNick ""
    }
    if {$newNick ne $prevNick} {
        if {$newNick ne "" && $prevNick ne ""} {
            dict set userData nick $guildId $newNick
            set msg "$username's nickname was changed "
            append msg "from $prevNick to $newNick."
        } elseif {$newNick eq ""} {
            dict set userData nick $guildId {}
            set msg "$username dropped their nickname: $prevNick."
        } else {
            dict set userData $userId nick $guildId $newNick
            set msg "$username has a new nickname: $newNick."
        }
        guild eval {UPDATE users SET data = :userData WHERE userId = :userId}
        putdc [dict create content $msg] 1 $channelId
    }
    
    # Else check for role change
}

# meta::log_msg_edit --
#
#   Logs message edits to the chatlog_$guildId and post them to the channel set
#   as log through meta::setup
#
# Arguments:
#   body    dictionary containing the event data (converted from JSON)
#
# Results:
#   None

proc meta::log_msg_edit {body} {
    set guildId [dict get $body guild_id]
    set channelId [metadb eval {
        SELECT channelId FROM config WHERE guildId = :guildId AND type = 'log'
    }]
    set userId [dict get $body author id]
    if {$userId eq [dict get [set ${::session}::self] id]} {return}
    if {$channelId eq ""} {
        set channelId test
    }
    set msgId [dict get $body id]
    set pinned [dict get $body pinned]
    lassign [metadb eval "
        SELECT userId, content, attachment, pinned FROM chatlog_$guildId
        WHERE msgId = :msgId 
    "] targetId content attachment oldpinned
    if {$oldpinned != $pinned} {
        metadb eval "
            UPDATE chatlog_$guildId SET pinned = :pinned WHERE msgId = :msgId
        "
        return
    }
    
    set sourceId [dict get $body channel_id]
    set userName [getUsernameNick $userId $guildId]
    set oldMsg ""
    set newMsg ""
    set msg "$userName edited message with ID $msgId."
    
    if {$content ne ""} {
        set oldMsg $content
        if {$attachment ne ""} {
            set links [lmap x $attachment {dict get $x url}]
            set oldMsg "$content\nAttachments: [join $links {,}]"
        }
    }
    
    set callback [discord getMessage $::session $sourceId $msgId 1]
    if {$callback eq ""} {
        if {$oldMsg eq ""} {
            putdc [dict create content $msg embed [dict create \
                description "*Could not retrieve message contents*." \
                color blue \
            ]] 1
        } else {
            set newMsg "*Could not retrieve message contents*."
            putdc [dict create content $msg embed [dict create \
                description "From: $oldMsg\nTo: $newMsg" \
                color blue \
            ]] 0 $channelId
        }
    } else {
        yield $callback
        set response [$callback]
        set data [lindex $response 0]
        if {$data ne ""} {
            set content [dict get $data content]
            set newMsg $content
            if {$oldMsg eq ""} {
                putdc [dict create content $msg embed [dict create \
                    description "To: $newMsg" \
                ]] 0 $channelId
            } else {
                putdc [dict create content $msg embed [dict create \
                    description "From: $oldMsg\nTo: $newMsg" \
                    color blue \
                ]] 0 $channelId
            }
        } else {
            if {$oldMsg eq ""} {
                putdc [dict create embed [dict create \
                    title $msg \
                    description "*Could not retrieve message contents*." \
                    color blue \
                ]] 0 $channelId
            } else {
                set newMsg "To: *Could not retrieve message contents*."
                putdc [dict create content $msg embed [dict create \
                    description "From: $oldMsg\nTo: $newMsg" \
                    color blue \
                ]] 0 $channelId
            }
        }
    }

    after idle [list ::stats::bump editMsg $guildId $channelId $userId ""]
}

# meta::welcome_msg --
#
#   Post member joins to the channel set as log through meta::setup
#
# Arguments:
#   guildId    Guild ID from which the event was received
#   userId     User ID from whom the event was received
#
# Results:
#   None

proc meta::welcome_msg {guildId userId} {
    set channelId [metadb eval {
        SELECT channelId FROM config WHERE guildId = :guildId AND type = 'log'
    }]
    if {$channelId != ""} {
        set msg "<@$userId> joined the server."
    } else {
        set guildData [guild eval {
            SELECT data FROM guild WHERE guildId = :guildId
        }]
        set guildData {*}$guildData
        set servername [dict get $guildData name]
        set msg "<@$userId> joined $servername."
        set channelId "test"
    }
    putdc [dict create content $msg] 0 $channelId
}

# meta::part_msg --
#
#   Post member parts to the channel set as log through meta::setup
#
# Arguments:
#   guildId    Guild ID from which the event was received
#   userId     User ID from whom the event was received
#
# Results:
#   None

proc meta::part_msg {guildId userId} {
    set channelId [metadb eval {
        SELECT channelId FROM config WHERE guildId = :guildId AND type = 'log'
    }]
    if {$channelId != ""} {
        set name [getUsernameNick $userId $guildId {%s @ %s}]
        if {$name eq ""} {
            set msg "<@$userId> left the server."
        } else {
            set msg "<@$userId> ($name) left the server."
        }
        set callback [discord getAuditLog $::session $guildId {limit 10} 1]
        if {$callback ne ""} {
            yield $callback
            set response [$callback]
            set data [lindex $response 0]

            if {$data ne ""} {
                set auditObj ""
                foreach x [dict get $data audit_log_entries] {
                    if {
                        [dict get $x action_type] in {20 22}
                        && [dict get $x target_id] == $userId
                    } {
                        set auditObj $x
                        break
                    }
                }
                
                if {$auditObj != ""} {
                    set actionId [dict get $auditObj user_id]
                    set userName [getUsernameNick $actionId $guildId]
                    if {$actionId == 20} {
                        set msg "<@$userId> ($name) was kicked from the server "
                        append msg "by *$userName*."
                    } else {
                        set msg "<@$userId> ($name) was kickbanned from the "
                        append "server by *$userName*."
                    }
                    if {
                        ![catch {dict get $auditObj reason} reason]
                        && $reason ne ""
                    } {
                        set msg "$msg (Reason: $reason)."
                    } else {
                        set msg "$msg (*No reason provided*)."
                    }
                    after idle [list ::stats::bump userKick $guildId "" \
                            $actionId $userId]
                }
            }
        }
        putdc [dict create content $msg] 0 $channelId
    } else {
        set guildData [guild eval {
            SELECT data FROM guild WHERE guildId = :guildId
        }]
        set guildData {*}$guildData
        set serverName [dict get $guildData name]
        set userName [getUsernameNick $userId $guildId {%s @ %s}]
        if {$userName eq ""} {
            putdc [dict create content "<@$userId> left $serverName."] 0 \
                    $channelId
        } else {
            set msg "<@$userId> ($userName) left $serverName."
            putdc [dict create content $msg] 0 test
        }
    }
}

# meta::log_ban_remove --
#
#   Post ban removals to the channel set as log through meta::setup
#
# Arguments:
#   guildId    Guild ID from which the event was received
#   userId     User ID from whom the event was received
#
# Results:
#   None

proc meta::log_ban_remove {guildId userId} {
    set channelId [metadb eval {
        SELECT channelId FROM config WHERE guildId = :guildId AND type = 'log'
    }]
    if {$channelId != ""} {
        set msg "The ban on <@$userId> has been lifted."
        set callback [discord getAuditLog $::session $guildId {limit 10} 1]
        if {$callback != ""} {
            yield $callback
            set response [$callback]
            set data [lindex $response 0]
            
            if {$data ne ""} {
                set auditObj ""
                foreach x [dict get $data audit_log_entries] {
                    if {
                        [dict get $x action_type] == 23
                        && [dict get $x target_id] == $userId
                    } {
                        set auditObj $x
                        break
                    }
                }
                
                if {$auditObj != ""} {
                    set actionId [dict get $auditObj user_id]
                    set userName [getUsernameNick $actionId $guildId]
                    set msg "The ban on <@$userId> has been lifted by "
                    append msg "*$userName*."
                }
            }
        }
        putdc [dict create content $msg] 0 $channelId
    } else {
        set guildData [guild eval {
            SELECT data FROM guild WHERE guildId = :guildId
        }]
        set guildData {*}$guildData
        set servername [dict get $guildData name]
        set userData [guild eval {
            SELECT data FROM users WHERE userId = :userId
        }]
        set userData {*}$userData
        if {![catch {dict get $userData username} name] && $name ne ""} {
            set msg "The ban on <@$userId> (*$name*) has been lifted."
        } else {
            set msg "The ban on <@$userId> has been lifted."
        }
        putdc [dict create content $msg] 1 test
    }
}

# meta::bump --
#
#   Increments events from discord
#
# Arguments:
#   event   Event that was triggered
#
# Results:
#   None

proc meta::bump {event} {
    variable botstats
    if {[info exists botstats($event)]} {
        incr botstats($event)
    }
}

# meta::formatTime --
#
#   Formats time to how long ago the provided time is to the present time
#
# Arguments:
#   duration   Unix time to be formatted
#
# Results:
#   Time formatted. E.g. +1 day(s) 2h3m4s

proc meta::formatTime {duration} {
    set s [expr {$duration % 60}]
    set i [expr {$duration / 60}]
    set m [expr {$i % 60}]
    set i [expr {$i / 60}]
    set h [expr {$i % 24}]
    set d [expr {$i / 24}]
    return [format "%+d day(s) %02dh%02dm%02ds" $d $h $m $s]
}

# meta::has_perm --
#
#   Checks if a user has any one of the specified permissions or is owner
#
# Arguments:
#   userId       User ID for whom the permission test has to be performed
#   permissions  List of permissions to be checked for
#
# Results:
#   Boolean      True if the user has any one of the specified permissions or is
#                owner

proc meta::has_perm {userId permissions} {
    upvar guildId guildId
    
    if {$guildId == ""} {return 0}
    set guildData [guild eval {SELECT data FROM guild WHERE guildId = :guildId}]
    set guildData {*}$guildData
    if {$userId == [dict get $guildData owner_id]} {
        return 1
    }
    
    set members [dict get $guildData members]
    set memObj [lsearch -inline -index {1 3} $members $userId]
    set mRoles [dict get $memObj roles]
    
    set guildRoles [dict get $guildData roles]
    
    set permTotal 0
    dict for {perm value} $::discord::PermissionValues {
        if {$perm in $permissions} {
            incr permTotal $value
        }
    }
    
    foreach role $mRoles {
        set roleObj [lsearch -inline -index 11 $guildRoles $role]
        set permValue [dict get $roleObj permissions]
        if {$permValue & $permTotal} {
            return 1
        }
    }
    return 0
}

# meta::getUsernameNick --
#
#   Retrieves the user's nickname in a specific format from a specified guild
#
# Arguments:
#   userId     User ID for whom the nickname has to be retrieved
#   guildId    Guild ID from which the user's nick is to be retrieved
#   fmt        (optional) Format in which the result needs to be returned in. 
#              Defaults to $username ($nick). Must contain two %s
#
# Results:
#   username   If a nickname is present, returns the nickname together as per
#              specified format

proc meta::getUsernameNick {userId guildId {fmt {}}} {
    set userData [guild eval {SELECT data FROM users WHERE userId = :userId}]
    set userData {*}$userData
    if {[catch {dict get $userData username} username]} {
        set username ""
    } else {
        if {
            ![catch {dict get $userData nick $guildId} nick] 
            && $nick ni {"" null}
        } {
            if {$fmt eq ""} {
                set username "$username ($nick)"
            } else {
                set username [format $fmt $username $nick]
            }
        }
    }
    return $username
}

# meta::cleanDebug --
#
#   Delete old debug files if there are more than 2 debug files. Executes every
#   hour
#
# Arguments:
#   None
#
# Results:
#   None

proc meta::cleanDebug {} {
    set files [lsort -increasing [glob -nocomplain debug.*]]
    set id 0
    while {[llength $files] > 2} {
        if {[catch {file delete -force [lindex $files $id]} res err]} {
            incr id
        }
        set files [glob -nocomplain debug.*]
    }
    after 360000 [list ::meta::cleanDebug]
}

# meta::shuffle --
#
#   Shuffles a list. Based on shuffle10a see shuffle10a
#   https://wiki.tcl-lang.org/page/Shuffle+a+list
#
# Arguments:
#   items     List to be shuffled
#
# Results:
#   items     Shuffled list

proc meta::shuffle {items} {   
    set len [llength $items]
    while {$len} {
        set n [expr {int($len*rand())}]
        set tmp [lindex $items $n]
        lset items $n [lindex $items [incr len -1]]
        lset items $len $tmp
    }
    return $items
}

# meta::channame_clean --
#
#   Returns a valid Discord channel name. Discord requires a channel name to
#   consist of letters, underscores and dashes only
#
# Arguments:
#   name     Name of the channel to be created
#
# Results:
#   name     Valid discord channel name

proc meta::channame_clean {name} {
    set name [string tolower [regsub -all -nocase -- {[^a-z0-9_-]} $name {}]]
    if {$name == ""} {
        return -code error "Invalid channel name"
    } else {
        return $name
    }
}

# meta::get_user_id --
#
#   Returns the user ID out from a string that can be a highlight, a username or
#   a nickname
#
# Arguments:
#   text     Text containing the userId, username or nickname
#
# Results:
#   userId   User ID of the user. If no results are found or more than one
#            result is found, an empty string is returned.

proc meta::get_user_id {guildId text} {
    set guildData [guild eval {SELECT data FROM guild WHERE guildId = :guildId}]
    set guildData {*}$guildData
    set members [dict get $guildData members]
    
    if {[regexp {^<@!?([0-9]+)>$} $text - userId]} {
        return $userId
    } else {
        set data [lsearch -all -inline $members "*$text*"]
        if {[llength $data] == 1} {
            return [dict get $data user id]
        } else {
            return ""
        }
    }
}

after idle [list ::meta::cleanDebug]

puts "meta.tcl loaded"