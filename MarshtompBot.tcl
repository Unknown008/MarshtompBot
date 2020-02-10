#!/bin/sh
# This line and the trailing backslash is required so that tclsh ignores the 
# next line \
exec tclsh8.6 "$0" "${1+"$@"}"

# tclqBot.tcl --
#
#       This file implements the Tcl code for a Discord bot written with the
#       discord.tcl library.
#
# Copyright (c) 2019, Jerry Yong
#
# See the file "LICENSE" for information on usage and redistribution of this
# file.

package require Tcl 8.6
package require sqlite3
package require logger

set scriptDir [file dirname [info script]]
# Add parent directory to auto_path so that Tcl can find the discord package.
switch $tcl_platform(os) {
    {Windows NT} {
        lappend ::auto_path "${scriptDir}/../discord.tcl/"
    }
    {Linux} {
        lappend ::auto_path "$scriptDir/../discord/" "$scriptDir/../tls1.6.7"
        source "$scriptDir/../tls1.6.7/http-2.8.11.tm"
    }
}
package require discord
# Set ownerId and token variables
source "${scriptDir}/private.tcl"

# https://discordapp.com/developers/applications/me
# Prod
# https://stillwaters.page.link/marshtomp-bot-invite
# Dev
# https://stillwaters.page.link/marshtomp-beta-bot-invite

###### Custom stuff here ######
source [file join $scriptDir meta/meta.tcl]
set modules {
    custom/custom.tcl           custom
    pokedex/pokedex.tcl         pokedex
    pokebattle/pokebattle.tcl   pokebattle
    stats/stats.tcl             stats
    pogo/pogo.tcl               pogo
    anime-manga/anime-manga.tcl anime
    FateGO/FateGrandOrder.tcl   fgo
}

foreach {module namespace} $modules {
    source [file join $scriptDir $module]
}

# Set to 1 if bot is expecting an answer (excluding commands)
set ::listener 0

###### End custom stuff ######

set log [logger::init tclqBot]
${log}::setlevel debug

# Open sqlite3 database
sqlite3 infoDb "${scriptDir}/info.sqlite3"
infoDb eval {
    CREATE TABLE IF NOT EXISTS procs(
        guildId TEXT,
        name BLOB,
        args BLOB,
        body BLOB,
        UNIQUE(guildId, name) ON CONFLICT REPLACE
    )
}
infoDb eval {
    CREATE TABLE IF NOT EXISTS vars(
        guildId TEXT PRIMARY KEY,
        list BLOB
    )
}
infoDb eval {
    CREATE TABLE IF NOT EXISTS bot(
        guildId TEXT PRIMARY KEY,
        trigger BLOB
    )
}
infoDb eval {
    CREATE TABLE IF NOT EXISTS perms(
        guildId TEXT,
        userId TEXT PRIMARY KEY,
        allow BLOB
    )
}
infoDb eval {
    CREATE TABLE IF NOT EXISTS callbacks(
        guildId TEXT PRIMARY KEY,
        dict BLOB
    )
}
infoDb eval {
    CREATE INDEX IF NOT EXISTS procsGuildIdIdx ON procs(guildId)
}

proc logDebug { text } {
    variable debugFile
    variable debugLog
    variable maxSize
    if {[file size $debugFile] >= $maxSize} {
        close $debugLog
        set fileName "${debugFile}.[clock milliseconds]"
        if {[catch {file copy $debugFile $fileName} res]} {
            puts stderr $res
            set suffix 0
            while {$suffix < 10} {
                if {[catch {file copy $debugFile ${fileName}.${suffix}} res]} {
                    puts stderr $res
                } else {
                    break
                }
            }
        }
        if {[catch {open $debugFile "w"} debugLog]} {
            puts stderr $debugLog
            set debugLog {}
        }
    }
    if {$debugLog eq {}} {
        return
    }
    puts $debugLog "[clock format [clock seconds] -format {[%Y-%m-%d %T]}] $text"
    flush $debugLog
}

# Lambda for "unique" number
coroutine id apply {{} {
    set x 0
    while 1 {
        yield $x
        incr x
    }
}}

proc handleDMEvnt {sessionNs data text} {
    set channelId [dict get $data channel_id]
    set userId [dict get $data author id]
    ::meta::command $data $text $channelId "" $userId
}

proc handleChanEvnt {sessionNs data text} {
    set channelId [dict get $data channel_id]
    set guildId [dict get $data guild_id]
    set userId [dict get $data author id]
    switch -regexp -nocase -- $text {
        {^o/} {
            if {$userId == $::ownerId} {::custom::wave $channelId}
        }
        {^@delete} {
            set msg_id [dict get $data id]
            ::meta::log_delete $guildId $msg_id $channelId
        }
        {^@msgedit} {
            ::meta::log_msg_edit $data
        }
        default {
            if {$text == "!reboot"} {
                reboot $userId $channelId
                return
            }
            ::meta::command $data $text $channelId $guildId $userId
        }
    }
}

proc handleGuildEvnt {sessionNs data text} {
    set guildId [dict get $data guild_id]
    set userId [dict get $data user id]
    switch -regexp -- $text {
        {join} {
            ::meta::welcome_msg $guildId $userId
        }
        {part} {
            ::meta::part_msg $guildId $userId
        }
        {presence} {
            ::meta::log_presence $guildId $userId $data
        }
        {member} {
            ::meta::log_member $guildId $userId $data
        }
        {banremove} {
            ::meta::log_ban_remove $guildId $userId
        }
    }
}

proc messageCreate { sessionNs event data } {
    set content [dict get $data content]
    set channelId [dict get $data channel_id]
    if {$channelId in [dict keys [set ${sessionNs}::dmChannels]]} {
        coroutine handleDMEvnt[::id] handleDMEvnt $sessionNs $data $content
        return
    }
    set guildId [guild eval {
        SELECT guildId FROM chan WHERE channelId = :channelId
    }]

    if {[string match "!*" $content] || $content eq "o/" || $::listener > 0} {
        coroutine handleChanEvnt[::id] handleChanEvnt $sessionNs $data $content
    }
}

proc ::mainCallbackHandler {sessionNs event data} {
    ::meta::bump $event
     switch $event {
        GUILD_CREATE {
            ::meta::build_logs
            after idle [list coroutine ::meta::update_members[::id] \
                ::meta::update_members]
        }
        CHANNEL_CREATE {
            ::meta::build_logs [dict get $data id]
        }
        MESSAGE_CREATE {
            set channelId [dict get $data channel_id]
            if {$channelId in [dict keys [set ${sessionNs}::dmChannels]]} {
                set guildId $channelId
            } else {
                set guildId [guild eval {
                    SELECT guildId FROM chan WHERE channelId = :channelId
                }]
            }
            set content [dict get $data content]
            set id [dict get $data author id]
            ::meta::log_chat $guildId [dict get $data id] $id $content \
                [dict get $data embeds] [dict get $data attachments]
            
            if {$id eq [dict get [set ${sessionNs}::self] id]} {
                return
            } else {
                set userData [guild eval {
                    SELECT data FROM users WHERE userId = :id
                }]
                if {
                    $userData != "" 
                    && ![catch {dict get $user bot} bot] 
                    && $bot
                } {return}
                ::messageCreate $sessionNs $event $data
            }
        }
        MESSAGE_UPDATE {
            if {![dict exists $data type] || [dict get $data type] != 0} {
                return
            }
            coroutine handleChanEvnt[::id] handleChanEvnt $sessionNs $data \
                    "@msgedit"
        }
        MESSAGE_DELETE {
            dict set data author id ""
            coroutine handleChanEvnt[::id] handleChanEvnt $sessionNs $data \
                    "@delete"
        }
        READY -
        RESUMED -
        MESSAGE_DELETE_BULK -
        TYPING_START -
        USER_SETTINGS_UPDATE -
        USER_UPDATE {}
        GUILD_MEMBER_UPDATE {
            coroutine handleGuildEvnt[::id] handleGuildEvnt $sessionNs $data \
                    "member"
        }
        PRESENCE_UPDATE {
            coroutine handleGuildEvnt[::id] handleGuildEvnt $sessionNs $data \
                    "presence"
        }
        GUILD_UPDATE -
        GUILD_DELETE {
            # handle guild delete
        }
        GUILD_MEMBER_ADD -
        GUILD_MEMBER_REMOVE {
            set userId [dict get $data user id]
            if {$userId ne [dict get [set ${sessionNs}::self] id]} {
                set userData [guild eval {
                    SELECT data FROM users WHERE userId = :id
                }]
                if {
                    $userData != "" 
                    && ![catch {dict get $user bot} bot]
                    && $bot
                } {return}
                switch $event {
                    GUILD_MEMBER_ADD     {set action "join"}
                    GUILD_MEMBER_REMOVE  {set action "part"}
                }
                coroutine handleGuildEvnt[::id] handleGuildEvnt $sessionNs \
                        $data $action
            }
        }
        GUILD_BAN_ADD {}
        GUILD_BAN_REMOVE {
            coroutine handleGuildEvnt[::id] handleGuildEvnt $sessionNs $data \
                    banremove
        }
        default {}
    }
}

proc reboot {userId channelId} {
    global modules
    if {$userId != $::ownerId} {return}
    foreach {module namespace} $modules {
        ${namespace}::pre_rehash
        namespace delete $namespace
        source [file join $::scriptDir $module]
    }
    ::meta::putdc [dict create content "Reboot complete!"] 0 $channelId
}

proc registerCallbacks {sessionNs} {
    discord setCallback $sessionNs READY                   ::mainCallbackHandler
    discord setCallback $sessionNs RESUMED                 ::mainCallbackHandler
    discord setCallback $sessionNs CHANNEL_CREATE          ::mainCallbackHandler
    discord setCallback $sessionNs CHANNEL_UPDATE          ::mainCallbackHandler
    discord setCallback $sessionNs CHANNEL_DELETE          ::mainCallbackHandler
    discord setCallback $sessionNs GUILD_CREATE            ::mainCallbackHandler
    discord setCallback $sessionNs GUILD_UPDATE            ::mainCallbackHandler
    discord setCallback $sessionNs GUILD_DELETE            ::mainCallbackHandler
    discord setCallback $sessionNs GUILD_BAN_ADD           ::mainCallbackHandler
    discord setCallback $sessionNs GUILD_BAN_REMOVE        ::mainCallbackHandler
    discord setCallback $sessionNs GUILD_EMOJIS_UPDATE     ::mainCallbackHandler
    discord setCallback $sessionNs GUILD_INTEGRATIONS_UPDATE \
            ::mainCallbackHandler
    discord setCallback $sessionNs GUILD_MEMBER_ADD        ::mainCallbackHandler
    discord setCallback $sessionNs GUILD_MEMBER_REMOVE     ::mainCallbackHandler
    discord setCallback $sessionNs GUILD_MEMBER_UPDATE     ::mainCallbackHandler
    discord setCallback $sessionNs GUILD_MEMBERS_CHUNK     ::mainCallbackHandler
    discord setCallback $sessionNs GUILD_ROLE_CREATE       ::mainCallbackHandler
    discord setCallback $sessionNs GUILD_ROLE_UPDATE       ::mainCallbackHandler
    discord setCallback $sessionNs GUILD_ROLE_DELETE       ::mainCallbackHandler
    discord setCallback $sessionNs MESSAGE_CREATE          ::mainCallbackHandler
    discord setCallback $sessionNs MESSAGE_UPDATE          ::mainCallbackHandler
    discord setCallback $sessionNs MESSAGE_DELETE          ::mainCallbackHandler
    discord setCallback $sessionNs MESSAGE_DELETE_BULK     ::mainCallbackHandler
    discord setCallback $sessionNs PRESENCE_UPDATE         ::mainCallbackHandler
    discord setCallback $sessionNs TYPING_START            ::mainCallbackHandler
    discord setCallback $sessionNs USER_SETTINGS_UPDATE    ::mainCallbackHandler
    discord setCallback $sessionNs USER_UPDATE             ::mainCallbackHandler
    discord setCallback $sessionNs VOICE_STATE_UPDATE      ::mainCallbackHandler
    discord setCallback $sessionNs VOICE_SERVER_UPDATE     ::mainCallbackHandler
    discord setCallback $sessionNs MESSAGE_REACTION_ADD    ::mainCallbackHandler
    discord setCallback $sessionNs MESSAGE_REACTION_REMOVE ::mainCallbackHandler
    discord setCallback $sessionNs MESSAGE_ACK             ::mainCallbackHandler
    discord setCallback $sessionNs CHANNEL_PINS_ACK        ::mainCallbackHandler
    discord setCallback $sessionNs CHANNEL_PINS_UPDATE     ::mainCallbackHandler
}

# For console stdin eval
proc asyncGets {chan {callback ""}} {
    if {[gets $chan line] >= 0} {
        if {[string trim $line] ne ""} {
            if {[catch {uplevel #0 $line} out options]} {
                puts "$out\n$options"
            } else {
                puts $out
            }
        }
    }
    if [eof $chan] { 
        set ::forever 0
        return
    }
    puts -nonewline "% "
    flush stdout
}

# Ad-hoc log file size limiting follows
set debugFile "${scriptDir}/debug"
set debugLog {}
set maxSize [expr {4 * 1024**2}]

if {[catch {open $debugFile "a"} debugLog]} {
    puts stderr $debugLog
} else {
    ${discord::log}::logproc debug ::logDebug
}

# Set to 0 for a cleaner debug log.
discord::gateway logWsMsg 1
${discord::log}::setlevel debug

puts -nonewline "% "
flush stdout
fconfigure stdin -blocking 0 -buffering line
fileevent stdin readable [list asyncGets stdin]

#trace add execution discord::gateway::Handler enter TraceExeTime::Enter
#trace add execution discord::gateway::Handler leave TraceExeTime::Leave
#trace add execution discord::ManageEvents enter TraceExeTime::Enter
#trace add execution discord::ManageEvents leave TraceExeTime::Leave

set startTime [clock seconds]

set session [discord connect $token ::registerCallbacks]

vwait forever

if {[catch {discord disconnect $session} res]} {
    puts stderr $res
}

close $debugLog
${log}::delete
infoDb close