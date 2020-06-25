# meta.tcl --
#
#       This file handles the essential procedures for a discord bot.
#
# Copyright (c) 2018-2020, Jerry Yong
#
# See the file "LICENSE" for information on usage and redistribution of this
# file.

package require sqlite3
package require http
package require json

namespace eval meta {
    sqlite3 metadb "${scriptDir}/meta/metadb.sqlite3"

    set botstats(order) [list UPTIME {*}[lmap x $::discord::defCallbacks {
        lindex x 0
    }]]
    foreach stat $botstats(order) {
        set botstats($stat) [expr {$stat eq "UPTIME" ? [clock seconds] : 0}]
    }

    variable meta
    set meta(ver)     "0.2"
    set meta(message) [file join ${::scriptDir} "meta" "messages.json"]

    # Rate limits for API requests
    variable localLimits {}

    # Commands made to be made visible to global via channel commands
    set publicCommands {
        set setup chanset guildset serverset config ban unban baninfo botstats
    }

    # Dictionary containing command parameter definitions:
    #     cmdName {-paramName {paramPattern paramType required options}}
    # For param types:
    #     string options is a list of valid values
    #     channel options is a list of required permissions
    #     user options is a list of valid users, where !bot means it cannot be
    #         a bot
    variable pubCmdArgs {
        setup {
            -type     {{^-t(?:ype)?$}         string  1 {
                help log announcement announcements tablesize banexpiry
                banduration
            }}
            -value    {{^-v(?:al(?:ue)?)?$}   string  0 {}}
        }
        ban {
            -user     {{^-u(?:ser)?$}          user     1 {!bot}}
            -duration {{^-d(?:ur(?:ation)?)?$} duration 0 {}}
            -scope    {{^-s(?:cope)?$}         string   0 {guild bot}}
            -reason   {{^-r(?:eason)?$}        text     0 {}}
        }
        unban {
            -user     {{^-u(?:ser)?$}          user     1 {}}
        }
        banInfo {
            -user     {{^-u(?:ser)?$}          user     0 {}}
            -scope    {{^-s(?:cope)?$}         string   0 {
                user server guild bot
            }}
            -view     {{^-v(?:iew)?$}}         view     0 {
                user reason by date expiry guild size
            }}
        }
    }

    variable setupTypes {
        log           {channel SEND_MESSAGES}
        announcement  {channel SEND_MESSAGES}
        announcements {channel SEND_MESSAGES}
        tablesize     {value int       {>=70}}
        banexpiry     {value duration  {}}
        banduration   {value duration  {}}
    }
    variable setupTypeAlias {
        announcements announcement banduration banexpiry
    }

    lappend ::allEventExec {::meta::bump $event}
    lappend ::eventExecute(MESSAGE_CREATE) {::meta::logChat $data}

    foreach command $publicCommands {
        if {![info exists ::bindings($command)]} {
            set ::bindings($command) ::meta
        } else {
            set msg "Error while loading meta module: Binding for command "
            append msg "$command unsuccessful; $command has already been bound "
            append msg "to $::bindings($command) module."
            puts $msg
            unset msg
        }
    }

    # putGc putDm editGc deleteGc update_members log_presence log_member
    # welcome_msg part_msg log_ban_remove 
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
    if {[isBot "" $data] || [isBanned $userId $guildId]} return

    switch [lindex $text 0] {
        "set" -
        "chanset" -
        "guildset" - 
        "serverset" -
        "config" -
        "setup" {
            if {
                [hasPerm $userId {ADMINISTRATOR MANAGE_CHANNELS MANAGE_GUILD}]
            } {
                setup [lrange $text 1 end]
            }
        }
        "ban" {
            if {
                $userId == $::ownerId ||
                [hasPerm $userId {ADMINISTRATOR MANAGE_CHANNELS MANAGE_GUILD}] 
            } {
                ban [lrange $text 1 end]
            }
        }
        "unban" {
            if {
                $userId == $::ownerId ||
                [hasPerm $userId {ADMINISTRATOR MANAGE_CHANNELS MANAGE_GUILD}]
            } {
                unban [lrange $text 1 end]
            }
        }
        "botstats" {
            putBotStats
        }
        "delete" {
            if {
                [hasPerm $userId {MANAGE_MESSAGES}]
                || $userId == $::ownerId
            } {
                deleteGc [regsub {!delete *} $text {}] $channelId
            }
        }
        "bulkdelete" {
            if {
                [hasPerm $userId {ADMINISTRATOR MANAGE_CHANNELS MANAGE_GUILD}] 
                || $userId == $::ownerId
            } {
                set option [lassign [regsub {!bulkdelete *} $text {}] n]
                bulkDelete $n $option
            }
        }
        "help" {
            help
        }
        "about" {
            about
        }
        default {
            puts "::meta::command Error: Unknown command [lindex $text 0]"
        }
    }
}

################################################################################
### Public procedures                                                        ###
################################################################################

# meta::setup --
#
#   Manage the settings for automatic messages. Saves the settings per guild in 
#   the config sqlite3 table
#
# Arguments:
#   data    parameters for the setup command, see setupHelp syntax in 
#           messages.json
#
# Results:
#   Posts a message informing whether the action was successful or not.
#
# To do:
#   Add other things like configure ban duration, bot command prefix

proc meta::setup {data} {
    variable pubCmdArgs setupTypes setupTypeAlias
    
    if {$data eq ""} {
        sendMsg setupHelp
        return
    } elseif {
        [catch {::util::parseArgs [dict get $pubCmdArgs setup] $data} arg err]
    } {
        puts "meta::setup Error: $err"
        sendMsg setupHelp $arg
        return
    } elseif {$arg eq ""} {
        sendMsg setupHelp
        return
    }
    
    set type [dict get $arg -type]
    set value [dict get $arg -value]

    set category [lindex [dict get $setupTypes $type] 0]
    switch $category {
        "help" {
            sendMsg [format {setup%sHelp} [string totitle $value]]
            return
        }
        "channel" {
            set options [lindex [dict get $setupTypes $type] 1]
            if {$value eq ""} {
                set channelId [uplevel {set channelId}]
            } elseif {[string tolower $value] eq "null"} {
                upvar guildId guildId
                set res [metadb eval {
                    SELECT channel_id FROM config
                    WHERE 
                        guild_id = :guildId AND
                        channel_id = :channelId AND
                        type = :type
                }]
                if {$res eq ""} {
                    set msg "No channel was previously set to $type."
                } else {
                    metadb eval {
                        DELETE FROM config
                        WHERE guild_id = :guildId AND type = :type
                    }
                    set msg "$type channel was unset."
                }
            } elseif {
                [catch {::util::validateChannel $value $options} channelId]
            } {
                puts "meta::setup Error: $err"
                sendMsg setupHelp $arg
                return
            } else {
                upvar guildId guildId
                set res [metadb eval {
                    SELECT channel_id FROM config
                    WHERE 
                        guild_id = :guildId AND
                        channel_id = :channelId AND
                        type = :type
                }]
                if {$res eq ""} {
                    metadb eval {
                        INSERT INTO config 
                        VALUES(:guildId, :channelId, :type, null)
                    }
                    set msg "<#$channelId> has been set as $type."
                } elseif {$res eq $channelId} {
                    set msg "<#$channelId> is already set as $type."
                } else {
                    metadb eval {
                        UPDATE config SET channel_id = :channelId
                        WHERE guild_id = :guildId AND type = :type
                    }
                    set msg "$type was changed from <#$res> to <#$channelId>"
                }
            }
        }
        "value" {
            lassign [dict get $setupTypes $type] - dataType options

            if {$value eq ""} {
                set type [string map $setupTypeAlias $type]
                sendMsg [format {setup%sHelp} [string totitle $type]]
                return
            } elseif {[string tolower $value] eq "null"} {
                upvar guildId guildId
                set res [metadb eval {
                    SELECT value FROM config
                    WHERE 
                        guild_id = :guildId AND
                        type = :type
                }]

                if {$res eq ""} {
                    set msg "Setting for $type has not been previously "
                    append msg "configured as $value."
                } else {
                    metadb eval {
                        DELETE FROM config
                        WHERE guild_id = :guildId AND type = :type
                    }
                    set msg "$type setting was unset."
                }
            } else {
                set dataTypeCheck [format "::util::validate%s" \
                    [string totitle $dataType]]
                if {
                    [catch {$dataTypeCheck $value $options} value]
                } {
                    puts "meta::setup Error: $err"
                    sendMsg [format {setup%sHelp} [string totitle $value]] $arg
                    return
                }

                upvar guildId guildId
                set res [metadb eval {
                    SELECT value FROM config
                    WHERE 
                        guild_id = :guildId AND
                        type = :type
                }]

                if {$res eq ""} {
                    metadb eval {
                        INSERT INTO config VALUES(:guildId, null, :type, :value)
                    }
                    set msg "Setting for $type has been set as $value."
                } elseif {$res eq $value} {
                    set msg "Setting for $type is already set to $value."
                } else {
                    metadb eval {
                        UPDATE config SET value = :value
                        WHERE guild_id = :guildId AND type = :type
                    }
                    set msg "Setting for $type was changed from $res to $value."
                }
            }
        }
    }
    
    putGc [dict create content $msg] 0
}

# meta::ban --
#
#   Ban a user from using this bot's commands
#
# Arguments:
#   data   Parameters for the ban command, see banHelp syntax in messages.json
#
# Results:
#   Posts whether the ban was successful or not

proc meta::ban {data} {
    variable pubCmdArgs

    if {$data eq ""} {
        sendMsg banHelp
        return
    } elseif {
        [catch {::util::parseArgs [dict get $pubCmdArgs ban] $data} arg err]
    } {
        puts "meta::ban Error: $err"
        sendMsg banHelp $arg
        return
    } elseif {$arg eq ""} {
        sendMsg banHelp
        return
    }

    set targetId [dict get $arg -user]
    set duration [dict get $arg -duration]
    set scope [dict get $arg -scope]
    set reason [dict get $arg -reason]

    upvar userId userId
    if {$scope == "bot"} {    
        if {![isBotAdmin $userId]} {
            set msg "You are not allowed to ban a user from the bot. Contact "
            append msg "one of the bot admins ([join [getBotAdmins] {, }]) to "
            append msg "explain why you need a user ban beyond guild level."
            putGc [dict create content $msg] 0
            return
        }
        set guildId ""
    } else {
        set guildId [uplevel {set guildId}]
    }
    
    if {[isBanned $targetId $guildId]} {
        set msg "<@$targetId> is already banned from my commands!"
    } else {
        set now [clock seconds]
        if {$duration eq "perm"} {
            set expiry ""
        } elseif {$duration eq ""} {
            set duration [metadb eval {
                SELECT value FROM config 
                WHERE guild_id = :guildId AND type = 'banexpiry'
            }]
            if {$duration eq ""} {
                # Set duration to 4 weeks
                set duration 2419200‬
            }
            set expiry [expr {$now + $duration}]
        } else {
            set expiry [expr {$now + $duration}]
        }
        
        metadb eval {INSERT INTO banned VALUES(
            :targetId,
            :guildId,
            :reason,
            :userId,
            :now,
            :expiry
        )}
        set msg "<@$targetId> was banned from all my commands!"
    }

    putGc [dict create content $msg] 0
}

# meta::unban --
#
#   Unban a user from using this bot's commands
#
# Arguments:
#   data   Parameters for the ban command, see unbanHelp syntax in messages.json
#
# Results:
#   Posts whether the unban was successful or not

proc meta::unban {data} {
    variable pubCmdArgs

    if {$data eq ""} {
        sendMsg unbanHelp
        return
    } elseif {
        [catch {::util::parseArgs [dict get $pubCmdArgs unban] $data} arg err]
    } {
        puts "meta::unban Error: $err"
        sendMsg unbanHelp $arg
        return
    } elseif {$arg eq ""} {
        sendMsg unbanHelp
        return
    }

    set targetId [dict get $arg -user]

    upvar userId userId
    set bans [metadb eval {
        SELECT guildId FROM banned
        WHERE user_id = :targetId AND 
        (date_ban_lifted > :now OR date_ban_lifted = '') AND
        (guildId = '' OR guildId = :guildId)
    }]
    
    switch [llength $bans] {
        0 {
            set msg "No ban for <@$targetId> was found."
        }
        1 {
            if {$bans == "" && ![isBotAdmin $userId]} {
                set msg "You are not allowed to unban a user from the bot. "
                append msg "Contact one of the bot admins ("
                append msg "[join [getBotAdmins] {, }]) to explain why you "
                append msg "need a user unban beyond guild level."
            } else {
                metadb eval {DELETE FROM banned WHERE userId = :userId}
                set msg "<@$targetId>'s ban has been lifted."
            }
        }
        2 {
            if {$guildId in $bans} {
                metadb eval {
                    DELETE FROM banned
                    WHERE userId = :userId AND guildId = :guildId
                }
                set msg "<@$targetId>'s ban for this server has been lifted."
            } else {
                if {![isBotAdmin $userId]} {
                    set msg "You are not allowed to unban a user from the bot. "
                    append msg "Contact one of the bot admins ("
                    append msg "[join [getBotAdmins] {, }]) to explain why you "
                    append msg "need a user unban beyond guild level."
                } else {
                    metadb eval {
                        DELETE FROM banned 
                        WHERE userId = :userId AND guildId = ''
                    }
                    set msg "<@$targetId>'s global ban has been lifted."
                }
            }
        }
    }
    
    putGc [dict create content $msg] 0
}

# meta::banInfo --
#
#   Posts information on a user's ban.
#
# Arguments:
#   data   Parameters for the ban command, see banInfoHelp syntax in 
#          messages.json
#
# Results:
#   Posts information about the user's ban

proc meta::banInfo {data} {
    variable pubCmdArgs

    if {$data eq ""} {
        sendMsg banInfoHelp
        return
    } elseif {
        [catch {::util::parseArgs [dict get $pubCmdArgs banInfo] $data} arg err]
    } {
        puts "meta::banInfo Error: $err"
        sendMsg banInfoHelp $arg
        return
    } elseif {$arg eq ""} {
        sendMsg banInfoHelp
        return
    }

    set targetId [dict get $arg -user]
    set scope [dict get $arg -scope]
    set view [dict get $arg -view]

    upvar guildId guildId
    switch $scope {
        "user" {
            set fields {}
            metadb eval {
                SELECT reason, banned_by, date_created, date_ban_lifted
                FROM banned
                WHERE user_id = :targetId AND 
                (date_ban_lifted > :now OR date_ban_lifted = '') AND
                (guildId = '' OR guildId = :guildId)
            } arr {
                lappend fields [dict create \
                    name "Date:" \
                    value [clock format $arr(date_created) \
                        -format "%a %d %b %Y %T UTC" -timezone UTC] \
                    inline true
                ] [dict create \
                    name "By:" \
                    value $arr(banned_by) \
                    inline true
                ] [dict create \
                    name "Expires:" \
                    value [expr {
                        $arr(date_ban_lifted) eq "" ? 
                        "Does not expire" : 
                        [clock format $arr(date_ban_lifted) \
                            -format "%a %d %b %Y %T UTC" -timezone UTC]
                    }] \
                    inline true
                ] [dict create \
                    name "Reason:" \
                    value $arr(reason) \
                ]
            }

            if {[llength $fields] == 0} {
                set msg "No ban for <@$targetId> was found."
            } else {
                set msg [dict create embed [dict create \
                    title "Bans for <@$targetId>" \
                    fields $fields \
                ]]
            }
        }
        "server" -
        "guild" {
            set userId [uplevel {set userId}]
            set header {
                User user By user Date date Expiry date Reason text
            }
            set rows {}
            metadb eval {
                SELECT 
                    user_id AS User,
                    reason AS Reason,
                    banned_by AS By,
                    date_created AS Date,
                    date_ban_lifted AS Expiry
                FROM banned
                WHERE (date_ban_lifted > :now OR date_ban_lifted = '') AND
                guildId = :guildId
            } arr {
                lappend rows [array get arr]
            }

            if {$view == ""} {
                set size [metadb eval {
                    SELECT value FROM config 
                    WHERE guld_id = :guildId AND type = 'tablesize'
                }]
                if {$size == ""} {set size 70}
                set view [list \
                    [dict create column User filter {} sort {}] \
                    [dict create column By filter {} sort {}] \
                    [dict create column Date filter {} sort {}] \
                    [dict create column Expiry filter {} sort {}] \
                    [dict create column Reason filter {} sort {}] \
                    [dict create column Size filter $size sort {}] \
                ]
            }
            
            set msg [::util::formatTable $header $rows $view]
        }
        "bot" {
            set userId [uplevel {set userId}]
            if {![isBotAdmin $userId]} {
                set msg "You must be a bot admin to use this option."
            } else {
                set header {
                    User user Guild guild By user Date date Expiry date Reason
                    text
                }
                set rows {}
                metadb eval {
                    SELECT 
                        user_id AS User, 
                        reason AS Reason, 
                        banned_by AS By, 
                        date_created AS Date, 
                        date_ban_lifted AS Expiry,
                        guild_id AS Guild
                    FROM banned
                    WHERE (date_ban_lifted > :now OR date_ban_lifted = '')
                } arr {
                    lappend rows [array get arr]
                }

                if {$view == ""} {
                    set size [metadb eval {
                        SELECT value FROM config 
                        WHERE guld_id = :guildId AND type = 'tablesize'
                    }]
                    if {$size == ""} {set size 70}
                    set view [list \
                        [dict create column User filter {} sort {}] \
                        [dict create column Guild filter {} sort {}] \
                        [dict create column By filter {} sort {}] \
                        [dict create column Date filter {} sort {}] \
                        [dict create column Expiry filter {} sort {}] \
                        [dict create column Reason filter {} sort {}] \
                        [dict create column Size filter $size sort {}] \
                    ]
                }
                
                set msg [::util::formatTable $header $rows $view]
            }
        }
    }

    putGc [dict create content $msg] 0
}

# meta::putBotStats --
#
#   Posts the count for all registered events the bot has gone through in the
#   channel the command was invoked
#
# Arguments:
#   None
#
# Results:
#   None

proc meta::putBotStats {} {
    variable botstats
    set msg [list]
    set kmax 8
    set vmax 0
    
    lappend msg [list SERVERS [guild eval {SELECT COUNT(*) FROM guild}]]
    lappend msg [list CHANNELS [guild eval {SELECT COUNT(*) FROM chan}]]
    lappend msg ""
    foreach k $botstats(order) {
        if {$k eq "UPTIME"} {
            set v [::util::formatTime [expr {[clock seconds]-$botstats($k)}]]
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
        set kmax [expr {max([string length $k], $kmax)}]
        set vmax [expr {max([string length $v], $vmax)}]
    }
    set msg [lmap x $msg {
        if {$x == ""} {
            set x
        } else {
            format "%-${kmax}s %${vmax}s" {*}$x
        }
    }]
    putGc [dict create content "```[join $msg \n]```"] 0
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
    if {![hasPerm [dict get [set ${::session}::self] id] MANAGE_MESSAGES]} {
        set msg "I don't have the permission (Manage Messages) to execute this."
        putGc [dict create content $msg] 0
        return
    }
}

# meta::bulkDelete --
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

proc meta::bulkDelete {n option} {
    upvar guildId guildId
    if {![hasPerm [dict get [set ${::session}::self] id] MANAGE_MESSAGES]} {
        set msg "I don't have the permission (Manage Messages) to execute this."
        putGc [dict create content $msg] 0
        return
    }
    upvar channelId channelId
    if {![string is integer -strict $n] && $n < 2 && $n > 100} {
        set msg {Invalid number of message supplied. Usage: **!bulkdelete }
        append msg {_number\_of\_messages option -force_**. __**option**__ can }
        append msg {be one of: __**before** msgId__, __**after** msgId__, }
        append msg {__**around** msgId__. Between 2 and 100 messages inclusive }
        append msg {can be bulk deleted.}
        putGc [dict create content $msg] 0
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
            putGc [dict create content $msg] 0
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
        putGc [dict create content $msg] 0
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
    if {[catch {discord $cmd $::session $channelId $lMsg 1} resCoro]} return
    if {$resCoro eq {}} return
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
                after idle [list coroutine ::meta::deleteGc[::id] \
                    ::meta::deleteGc $oMsg $channelId]
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
    after idle [list coroutine ::meta::putGc[::id] ::meta::putGc \
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
    putGc [dict create content $msg] 0
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
    set msg [join [list "Marshtomp is a bot managed by Unknown008#4135 " \
        "created by qwename#5406. The bot is a multipurpose bot with various " \
        "modules ranging from server management, anime torrent feed, " \
        "Pok\u00E9dex resource, Pok\u00E9mon news feed from serebii.net, " \
        "Fate/Grand Order resource to various silly 'fun' modules like" \
        "classic 8ball. More features might have been implemented when you " \
        "see this message."] " "]

    putGc [dict create content $msg] 1
}

#############################
##### Private procedures ####
#############################

# meta::putGc --
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
#   cmdList    (optional) list of commands to be executed after the message has
#              been successfully posted
#
# Results:
#   None

proc meta::putGc {data encode {channelId {}} {cmdList {}}} {
    variable localLimits
    puts "meta::putGc called from [info level 1] with data $data"
    if {$channelId eq ""} {
        set channelId [uplevel #2 {set channelId}]
    } elseif {$channelId in {test default}} {
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
                ::meta::putGc[::id] ::meta::putGc $data $encode $channelId \
                $cmdList]
            set msg "::meta::putGc Error: Rate limited"
            puts "[clock format [clock seconds] -format {[%Y-%m-%d %T]}] $msg"
            return
        }
    }
    
    if {$encode && [dict exists $data content]} {
        set text [dict get $data content]
        set text [encoding convertto utf-8 $text]
        dict set data content $text
    }
    if {[catch {discord sendMessage $::session $channelId $data 1} resCoro]} {
        set msg "::meta::putGc Error: Failed to send ($resCoro)"
        puts "[clock format [clock seconds] -format {[%Y-%m-%d %T]}] $msg"
        return
    }
    if {$resCoro eq {}} {return}
    yield $resCoro
    set response [$resCoro]
    set data [lindex $response 0]
    if {$data ne {} && $cmdList != {}} {
        set cmdList [lassign $cmdList cmd]
        {*}$cmd $cmdList
    }
}

# meta::putDm --
#
#   Posts a message into a certain private channel ID. If the channel does not
#   exist yet, create it then post the message.
#
# Arguments:
#   userId     user ID to whom the private message is directed to
#   msgdata    dictionary of the message (to be converted to JSON format)
#   encode     boolean, specifies whether the message contents should be html
#              encoded or not
#   cmdList    (optional) list of commands to be executed after the message has
#              been successfully posted
#
# Results:
#   None

proc meta::putDm {userId msgdata encode {cmdList {}}} {
    variable localLimits
    puts "meta::putDm called from [info level 1] with data $msgdata for $userId"
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
                    ::meta::putDm[::id] ::meta::putDm $userId $msgdata \
                    $encode $cmdList]
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
            if {$data ne {} && $cmdList != {}} {
                set cmdList [lassign $cmdList cmd]
                {*}$cmd $cmdList
            }
        }
    } else {
        if {$resCoro eq {}} {return}
        yield $resCoro
        set response [$resCoro]
        set data [lindex $response 0]
        if {$data ne {} && $cmdList != {}} {
            set cmdList [lassign $cmdList cmd]
            {*}$cmd $cmdList
        }
    }
}

# meta::editGc --
#
#   Posts an edit to a message posted previously
#
# Arguments:
#   data       dictionary of the new message (to be converted to JSON format)
#   encode     boolean, specifies whether the message contents should be html
#              encoded or not
#   msgId      message ID of the message to be edited
#   channelId  channel ID the message was previously posted to
#   cmdList    (optional) list of commands to be executed after the edit has
#              been successfully posted
#
# Results:
#   None

proc meta::editGc {data encode msgId channelId {cmdList {}}} {
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
    if {$data ne {} && $cmdList != {}} {
        set cmdList [lassign $cmdList cmd]
        {*}$cmd $cmdList
    }
}

# meta::deleteGc --
#
#   Deletes a message with specified IDs
#
# Arguments:
#   msgId      list of message IDs to be deleted
#
# Results:
#   None

proc meta::deleteGc {msgId {channelId {}}} {
    if {![string is wideinteger -strict [lindex $msgId 0]]} {
        putGc [dict create content "Invalid message ID"] 0
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
                    ::meta::deleteGc[::id] ::meta::deleteGc $msgId $channelId]
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
            deleteGc $msgId $channelId
        }
    }
}

# meta::update_members --
#
#   Update the guilds database with the actual members. GUILD_CREATE might have
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

# meta::logDelete --
#
#   Triggered when a message is deleted and posts the deleted message and the 
#   original author in the channel set as log through meta::setup
#
# Arguments:
#   body        dictionary containing the event data from the message delete 
#               event
#
# Results:
#   None

proc meta::logDelete {guildId msgId sourceId} {
    set guildId [dict get $data guild_id]
    set msgId [dict get $data id]
    set sourceId [dict get $data channel_id]
    set channelId [metadb eval {
        SELECT channelId FROM config WHERE guildId = :guildId AND type = 'log'
    }]
    lassign [metadb eval {
        SELECT user_id, content, embed, attachment FROM chatlog
        WHERE msg_id = :msgId 
    }] targetId content attachment
    
    set targetName [getUsernameNick $targetId $guildId {%s (%s)}]
    
    if {$channelId eq ""} {set channelId test}
    set callback [discord getAuditLog $::session $guildId {limit 10} 1]
    # No callback generated. Shouldn't really happen
    if {$callback eq "" || $targetId eq ""} {
        putGc [dict create content "Message #$msgId deleted from <#$sourceId>" \
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
                    [dict get $x id] > $msgId 
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
                set msg "Message #$msgId by *$targetName* deleted "
                append msg "from <#$sourceId> by *$userName*."
            # Match not found - user deleted own message
            } else {
                set msg "Message #$msgId by *$targetName* deleted "
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
            putGc $delMsg 0 $channelId
        # Delete is not in recent logs, shouldn't happen
        } else {
            set msg "Message #$msgId deleted from <#$sourceId>"
            putGc [dict create content $msg \
                embed [dict create color red]
            ] 0 $channelId
        }
    }
    # if {[info exists userId]} {
    #     ::stats::bump deleteMsg $guildId $sourceId $userId $content
    # }
}

# meta::logChat --
#
#   Triggered when a message is created and saves the message in 
#   chatlog table.
#
# Arguments:
#   None
#
# Results:
#   None

proc meta::logChat {data} {
    set guildId [dict get $data guildId]
    set channelId [dict get $data channelId]
    set msgId [dict get $data id]
    set userId [dict get $data author id]
    set content [dict get $data content]
    set embed [dict get $data embeds]
    set attachments [dict get $data attachments]

    # Saving data
    set now [clock seconds]
    metadb eval {
        INSERT INTO chatlog VALUES (
            :guildId, :channelId, :msgId, :userId, :content, :embed,
            :attachments, 'false', :now
        )
    }

    set re {([^/]+)/([^/]+)$}
    if {[llength $attachments] > 0} {
        foreach attachment $attachments {
            set url [dict get $attachment url]
            if {![regexp $re $url - msgId fileName]} {
                set msg "::meta::saveAttachment Error: Could not extract msgId "
                append msg "and file name"
                puts $msg
                continue
            }
            set fileName "${msgId}_$fileName"
            ::http::geturl $url -command [list ::util::saveAttachment $fileName]
        }
    }

    # Deleting old data
    set timestamps [metadb eval {
        SELECT timestamp FROM chatlog
        WHERE guild_id = :guildId AND channel_id = :channelId
        ORDER BY timestamp DESC
    }]

    set limit [metadb eval {
        SELECT value FROM config 
        WHERE channel_id = :channelId AND type = 'chat history'
    }]
    if {$limit eq ""} {
        set limit 500
    }

    if {[llength $timestamps] > $limit} {
        set cutOff [lindex $timestamps $limit-1]

        set attachments [metadb eval {
            SELECT attachment FROM chatlog
            WHERE
                guild_id = :guildId AND 
                channel_id = :channelId AND
                timestamp < :cutOff AND
                attachment <> ''
        }]

        if {[llength $attachments] > 0} {
            set paths [lmap x $attachments {
                set url [dict get $x url]
                regexp $re $url - msgId fileName
                set x "${msgId}_$fileName"
            }]
            ::util::deleteFiles $paths
        }

        metadb eval {
            DELETE FROM chatlog 
            WHERE 
                guild_id = :guildId AND 
                channel_id = :channelId AND
                timestamp < :cutOff
        }
    }
    
    # if {$content ne ""} {
    #     after idle [list ::stats::bump createMsg $guildId $channelId $userId \
    #         $content]
    # }
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
                putGc [dict create content $msg] 1 $channelId
                # after idle \
                #     [list ::stats::bump nameChange $guildId "" $userId ""]
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
        putGc [dict create content $msg] 1 $channelId
    }
    
    # Else check for role change
}

# meta::logEdit --
#
#   Logs message edits to the chatlog and post them to the channel set
#   as log through meta::setup
#
# Arguments:
#   body        dictionary containing the event data from the message delete 
#               event
#
# Results:
#   None

proc meta::logEdit {body} {
    if {![dict exists $body type] || [dict get $body type] != 0} return
    set userId [dict get $body author id]
    if {$userId eq [dict get [set ${::session}::self] id]} return

    set guildId [dict get $body guild_id]
    set channelId [metadb eval {
        SELECT channelId FROM config WHERE guildId = :guildId AND type = 'log'
    }]
    if {$channelId eq ""} {
        set channelId default
    }
    set msgId [dict get $body id]
    set oldMsg [metadb eval {
        SELECT user_id, content, embed, attachment FROM chatlog
        WHERE msg_id = :msgId
    }]

    set sourceId [dict get $body channel_id]
    set userName [getUsernameNick $userId $guildId]
    set msg \
        [encoding convertto utf-8 "$userName edited message with ID $msgId:"]
    
    set oldContent ""
    set newContent ""
    set oldEmbed ""
    set newEmbed ""
    
    if {$oldMsg ne ""} {
        set oldContent [lindex $oldMsg 1]
        set oldEmbed [lindex $oldMsg 2]
    }
    
    set callback [discord getMessage $::session $sourceId $msgId 1]

    set data ""
    if {$callback ne ""} {
        yield $callback
        set response [$callback]
        set data [lindex $response 0]
    }

    if {$data eq ""} {
        if {$oldMsg eq ""} {
            putGc [dict create content $msg embed [dict create \
                description "*Could not retrieve message contents*." \
                color blue \
            ]] 1
        } elseif {$oldEmbed eq ""} {
            set newContent "*Could not retrieve message contents*."
            putGc [dict create content $msg embed [dict create \
                description "From: $oldContent\nTo: $newContent" \
                color blue \
            ]] 0 $channelId
        } else {
            set newContent "*Could not retrieve message contents*."
            set cmdList {}
            lappend cmdList [list ::meta::putGc [dict create content \
                "To: $newContent" \
            ] 0 $channelId]
            putGc [dict create content "$msg\nFrom: $oldContent" embed \
                $oldEmbed \
            ] 0 $channelId $cmdList
        }
    } else {
        set newContent [dict get $data content]
        set newEmbed [dict get $data embed]

        if {$newEmbed ne ""} {
            if {$oldEmbed eq "" && $oldContent eq ""} {
                set oldContent "*Could not retrieve message contents*."
                set cmdList {}
                lappend cmdList [list ::meta::putGc [dict create content \
                    "To: $newContent" embed $newEmbed \
                ] 0 $channelId]
                putGc [dict create content "$msg\nFrom: $oldContent"] 0 \
                    $channelId $cmdList
            } else {
                set cmdList {}
                lappend cmdList [list ::meta::putGc [dict create content \
                    "To: $newContent" embed $newEmbed \
                ] 0 $channelId]
                putGc [dict create content "$msg\nFrom: $oldContent" embed \
                    $oldEmbed \
                ] 0 $channelId $cmdList
            }
        } else {
            if {$oldEmbed eq "" && $oldContent eq ""} {
                set oldContent "*Could not retrieve message contents*."
                set cmdList {}
                lappend cmdList [list ::meta::putGc [dict create content \
                    "To: $newContent" \
                ] 0 $channelId]
                putGc [dict create content "$msg\nFrom: $oldContent"] 0 \
                    $channelId $cmdList
            } else {
                set cmdList {}
                lappend cmdList [list ::meta::putGc [dict create content \
                    "To: $newContent" \
                ] 0 $channelId]
                putGc [dict create content "$msg\nFrom: $oldContent" embed \
                    $oldEmbed \
                ] 0 $channelId $cmdList
            }
        }
    }

    # after idle [list ::stats::bump editMsg $guildId $channelId $userId ""]
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
    putGc [dict create content $msg] 0 $channelId
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
                    # after idle [list ::stats::bump userKick $guildId "" \
                    #         $actionId $userId]
                }
            }
        }
        putGc [dict create content $msg] 0 $channelId
    } else {
        set guildData [guild eval {
            SELECT data FROM guild WHERE guildId = :guildId
        }]
        set guildData {*}$guildData
        set serverName [dict get $guildData name]
        set userName [getUsernameNick $userId $guildId {%s @ %s}]
        if {$userName eq ""} {
            putGc [dict create content "<@$userId> left $serverName."] 0 \
                    $channelId
        } else {
            set msg "<@$userId> ($userName) left $serverName."
            putGc [dict create content $msg] 0 test
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
        putGc [dict create content $msg] 0 $channelId
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
        putGc [dict create content $msg] 1 test
    }
}

# meta::setupDatabase --
#
#   Sets up the meta database and upgrades it if needed based on meta(ver)
#
# Arguments:
#   None
#
# Results:
#   None

proc meta::setupDatabase {} {
    variable meta

    set metaVersion [metadb eval {
        SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'version'
    }]

    if {$metaVersion eq ""} {
        # Either first setup or v0.1
        set configExists [metadb eval {
            SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'config'
        }]

        if {$configExists} {
            # v0.1
            # Update config first
            metadb eval {CREATE TABLE tempconfig AS SELECT * FROM config}
            metadb eval {DROP TABLE config}
            metadb eval {
                CREATE TABLE config(
                    guild_id text,
                    channel_id text,
                    type text,
                    value text
                )
            }
            metadb eval {
                INSERT INTO config(guild_id, channel_id, type)
                SELECT guildId, channelId, type FROM tempconfig
            }
            metadb eval {DROP TABLE tempconfig}

            # Update banned
            metadb eval {CREATE TABLE tempbanned AS SELECT * FROM banned}
            metadb eval {DROP TABLE banned}
            metadb eval {
                CREATE TABLE banned(
                    user_id text,
                    guild_id text,
                    reason text,
                    banned_by text,
                    date_created text,
                    date_ban_lifted text
                )
            }
            metadb eval {
                INSERT INTO banned(user_id)
                SELECT userId FROM tempbanned
            }
            metadb eval {DROP TABLE tempbanned}

            # Delete old chatlogs
            set oldChatLogs [metadb eval {
                SELECT name FROM sqlite_master 
                WHERE type = 'table' AND name LIKE 'chatlog_%'
            }]
            foreach table $oldChatLogs {
                metadb eval "DROP TABLE $table"
            }
        } else {
            # New setup
            # Create config
            metadb eval {
                CREATE TABLE config(
                    guild_id text,
                    channel_id text,
                    type text,
                    value text
                )
            }

            # Create banned
            metadb eval {
                CREATE TABLE banned(
                    user_id text,
                    reason text,
                    banned_by text,
                    date_created text,
                    date_ban_lifted text
                )
            }
        }

        # Create chatlog
        metadb eval {
            CREATE TABLE chatlog(
                guild_id text,
                channel_id text,
                msg_id text,
                user_id text,
                content text,
                embed text,
                attachment text,
                pinned text,
                timestamp int
            )
        }

        # Create messages table
        metadb eval {
            CREATE TABLE messages(
                key text,
                message text
            )
        }

        # Create version table
        metadb eval {
            CREATE TABLE version(
                version text
            )
        }

        metadb eval {INSERT INTO version VALUES(:meta(ver))}
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

# meta::hasPerm --
#
#   Checks if a user has any one of the specified permissions or is owner
#   TODO: Check perm hierarchy (guild perm, cat perm, chan perm and member perm)
#
# Arguments:
#   userId       User ID for whom the permission test has to be performed
#   permissions  List of permissions to be checked for
#
# Results:
#   Boolean      True if the user has any one of the specified permissions or is
#                owner

proc meta::hasPerm {userId permissions} {
    upvar guildId guildId

    if {$guildId == ""} {return 0}
    set guildData [guild eval {SELECT data FROM guild WHERE guildId = :guildId}]
    set guildData {*}$guildData
    if {$userId == [dict get $guildData owner_id]} {
        return 1
    }
    
    set members [dict get $guildData members]
    foreach member $members {
        set user [dict get $member user]
        if {[dict get $user id] == $userId} break
    }
    set mRoles [dict get $member roles]
    set guildRoles [dict get $guildData roles]
    
    set permTotal 0
    foreach perm $permissions {
        incr permTotal [dict get $::discord::PermissionValues $perm]
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
    set userData {*}[guild eval {SELECT data FROM users WHERE userId = :userId}]
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

# meta::getUserId --
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

proc meta::getUserId {guildId text} {
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

# meta::isBanned --
#
#   Returns 1 or 0 depending of whether a user is banned or not
#
# Arguments:
#   userId   The user's id.
#   guildId  The guild id.
#
# Results:
#   bool   1 if the user is banned, 0 otherwise

proc meta::isBanned {userId guildId} {
    set now [clock seconds]
    set banned [metadb eval {
        SELECT 1 FROM banned
        WHERE user_id = :userId AND 
        (date_ban_lifted > :now OR date_ban_lifted = '') AND
        (guildId = '' OR guildId = :guildId)
        LIMIT 1
    }]
    return [expr {$banned == 1}]
}

# meta::isBot --
#
#   Returns 1 or 0 depending of whether a user is a bot or not
#
# Arguments:
#   userId   The user's id.
#   data     Optional object containing discord information
#
# Results:
#   bool   1 if the user is a bot, 0 otherwise

proc meta::isBot {userId {data {}}} {
    if {$data == ""} {
        upvar guildId guildId
        set guildData {*}[guild eval {
            SELECT data FROM guild WHERE guildId = :guildId
        }]
        set users [dict get $guildData members]
        if {[catch {dict get $data user bot} bot]} {set bot false}
    } else {
        if {[catch {dict get $data author bot} bot]} {set bot false}
    }
    return $bot
}

# meta::isBotAdmin --
#
#   Returns 1 or 0 depending of whether a user is a bot admin or not
#
# Arguments:
#   userId   The user's id.
#
# Results:
#   bool   1 if the user is a bot admin, 0 otherwise

proc meta::isBotAdmin {userId} {
    metadb eval {SELECT value WHERE }
    return $bot
}

# meta::sendMsg --
#
#   Sends a help or error message to the channel.
#
# Arguments:
#   type   The type of message to send.
#   param  Optional. Any other informations to include in the message.
#
# Results:
#   None

proc meta::sendMsg {type {param {}}} {
    variable meta pubCmdArgs
    set modDate [file mtime $meta(message)]
    set dbModDate [metadb eval {SELECT value FROM config WHERE type = 'msg'}]
    set updateMsg 0

    if {$dbModDate != $modDate} {
        if {$dbModDate == ""} {
            metadb eval {INSERT INTO config(type, value) VALUES('msg', :mtime)}
        } else {
            metadb eval {UPDATE config SET value = :modDate WHERE type = 'msg'}
        }
        set f [open $meta(message) r]
        set msgDict [::json::json2dict [read $f]]
        close $f
        
        metadb eval {DELETE FROM messages}
        dict for {msgType msg} $msgDict {
            metadb eval {INSERT INTO messages VALUES(:msgType, :msg)}
        }
    }

    set msgBody {*}[metadb eval {
        SELECT message FROM messages WHERE key = :type
    }]

    if {$param == ""} {
        set fields {}
        switch $type {
            "setupHelp" {
                set typeConstraints [dict get $pubCmdArgs setup -type]
                lappend fields [dict create \
                    name "Valid types" \
                    value [join [lindex $typeConstraints 3] {, }] \
                ]
            }
            "banHelp" {
                set scopeConstraints [dict get $pubCmdArgs ban -scope]
                lappend fields [dict create \
                    name "Valid scopes" \
                    value [join [lindex $scopeConstraints 3] {, }] \
                ]
            }
            "banInfoHelp" {
                set scopeConstraints [dict get $pubCmdArgs banInfo -scope]
                lappend fields [dict create \
                    name "Valid scopes" \
                    value [join [lindex $scopeConstraints 3] {, }] \
                ]
                set viewConstraints [dict get $pubCmdArgs banInfo -view]
                lappend fields [dict create \
                    name "Valid columns for view" \
                    value [join [lindex $viewConstraints 3] {, }] \
                ]
            }
        }

        lappend fields [dict create \
            name "Synonyms" value [dict get $msgBody synonyms] \
        ]
        lappend fields [dict create \
            name "Example" value [dict get $msgBody example] \
        ]
        lappend fields [dict create \
            name "Required permissions" value [dict get $msgBody required] \
        ]

        set msg [dict create embed [dict create \
            title [dict get $msgBody syntax] \
            description [dict get $msgBody desc] \
            fields $fields \
        ]]
    } else {
        set msg [dict create embed [dict create \
            title "Error" \
            description [join $param "\n"] \
        ]]
    }
    
    putGc $msg 0
}

::meta::setupDatabase
puts "meta.tcl $::meta::meta(ver) loaded"