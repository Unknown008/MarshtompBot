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

################################################################################
### Begin imports                                                            ###
################################################################################
package require Tcl 8.6
package require sqlite3
package require logger
package require json

# Add parent directory to auto_path to load the discord package.
set scriptDir [file dirname [info script]]
lappend ::auto_path [file join $scriptDir .. discord.tcl]
package require discord

# https://discordapp.com/developers/applications/me
# Prod
# https://stillwaters.page.link/marshtomp-bot-invite
# Dev
# https://stillwaters.page.link/marshtomp-beta-bot-invite

if {![file exists [file join $scriptDir meta meta.tcl]]} {
    puts "Error booting up: ./meta/meta.tcl file missing."
    exit
}
source [file join $scriptDir meta meta.tcl]

if {![file exists [file join $scriptDir meta util.tcl]]} {
    puts "Error booting up: ./meta/util.tcl file missing."
    exit
}
source [file join $scriptDir meta util.tcl]

################################################################################
### Global variables                                                         ###
################################################################################

if {![file exists "settings.json"]} {
    puts "Error booting up: settings.json file missing."
    exit
}
set settingsFile [open "settings.json" r]
set settingsJson [read $settingsFile]
close $settingsFile
regsub -all -line {^ *//.*$} $settingsJson {} settingsJson
if {[catch {json::json2dict $settingsJson} settings]} {
    puts "Settings file could not be parsed; json structure broken"
    exit
}

set ownerId [dict get $settings owner_id]
set ownerTag [dict get $settings owner_tag]
set token [dict get $settings token]
# Variable controlling user response
set listener 0
# Array containing module imported public commands
array set bindings {}
# Array containing guild prefixes
array set prefix {}
# Array containing commands to be executed on specific gateway events
array set eventExecute {}
# List of special commands not following usual command prefix
set specialCmds {!reboot !shutdown}
# List of commands to execute for any and all events
set allEventExec {}

unset -nocomplain settingsFile settingsJson

################################################################################
### Loading additional modules                                               ###
################################################################################

foreach module [dict get $settings modules] {
    set path [file join $scriptDir {*}[file split [dict get $module path]]]
    if {![file exists $path]} {
        set msg "Error loading modules: $path file missing and thus module "
        append msg "[dict get $module module_name] will not be loaded."
        puts $msg
        continue
    }
    source $path
}

unset -nocomplain module path msg

################################################################################
### Setting up logs                                                          ###
################################################################################

set log [logger::init tclqBot]
${log}::setlevel [dict get $settings log_level]

# logToFile --
#
#   Called whenever discord::log is called at and above the set log level and 
#   writes the message to discord.log
#
# Arguments:
#   text      The log message
#
# Results:
#   None

proc logToFile {text} {
    variable debugFile
    variable debugLog
    variable maxLogSize

    regexp {([^:]+)$} [lindex [info level -1] 0] caller
    set namespace "::[string trimleft [uplevel 1 {namespace current}] {:}]"
    set caller "${namespace}::$caller"

    set type ""
    if {![catch {dict get [info frame -1] proc} type]} {
        regexp {([^:]+)cmd} $type - type
    } else {
        puts "logToFile Error: frame doesn't contain proc: $type"
        return
    }
    if {$type ni $::discord::logLevels} {
        puts "logToFile Error: '$type' not recognised"
        return
    }
    if {[file size $debugFile] >= $maxLogSize} {
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

        set files [lsort -increasing [glob -nocomplain discord.log.*]]
        set id 0
        while {[llength $files] > 2 && $id < [llength $files]} {
            if {[catch {file delete -force [lindex $files $id]} res err]} {
                incr id
            }
            set files [glob -nocomplain debug.*]
        }
    }
    if {$debugLog eq {}} {
        return
    }
    regsub {^(?:-_logger::service \S+ )+\{(.+)\}} $text {\1} text
    set text "\[$type\] \[$caller\] $text"
    puts $debugLog \
        "[clock format [clock seconds] -format {[%Y-%m-%d %T]}] $text"
    flush $debugLog
}

set debugFile [file join $scriptDir discord.log]
set debugLog {}
set maxLogSize [expr {[dict get $settings max_log_size] * 1024**2}]

if {[catch {open $debugFile "a"} debugLog]} {
    puts stderr $debugLog
} else {
    foreach level $::discord::logLevels {
        ${discord::log}::logproc $level ::logToFile
    }
}

discord::gateway logWsMsg [dict get $settings log_websocket] \
    [dict get $settings websocket_log_level]
${discord::log}::setlevel [dict get $settings log_level]

################################################################################
### The gory stuff                                                           ###
################################################################################

# Lambda for "unique" number
coroutine id apply {{} {
    set x 0
    while 1 {
        yield $x
        if {$x >= 1000} {
            set x 0
        } else {
            incr x
        }
    }
}}

proc handleDMEvnt {data text} {
    set channelId [dict get $data channel_id]
    set userId [dict get $data author id]
    ::meta::command $data $text $channelId "" $userId
}

proc handleChanEvnt {data text cmd} {
    set channelId [dict get $data channel_id]
    set guildId [dict get $data guild_id]
    set userId [dict get $data author id]

    switch $text {
        "!reboot" {
            reboot $userId $channelId
        }
        "!shutdown" {
            shutdown $userId $channelId [lindex $text 1]
        }
        default {
            if {[info exists ::bindings($cmd)]} {
                set ns $::bindings($cmd)
                ${ns}::command $data [lreplace $text 0 0 $cmd] $channelId \
                    $guildId $userId
            }
        }
    }
}

proc handleGuildEvnt {data text} {
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

proc messageCreate {guildId channelId event data} {
    set content [dict get $data content]
    set channelId [dict get $data channel_id]
    if {$guildId eq ""} {
        coroutine handleDMEvnt[::id] handleDMEvnt $data $content
        return
    }

    if {$content in $::specialCmds} {
        coroutine handleChanEvnt[::id] handleChanEvnt $data $content ""
        return
    }

    set cmds [lmap b [array names ::bindings] {
        if {![info exists ::prefix($guildId)]} {
            set ::prefix($guildId) "!"
        }
        set b $::prefix($guildId)$b
    }]
    set cmd [lindex $content 0]

    if {$cmd in $cmds || $::listener > 0} {
        set cmd [string range $cmd [string length $::prefix($guildId)] end]
        coroutine handleChanEvnt[::id] handleChanEvnt $data $content $cmd
    }
}

proc mainCallbackHandler {sessionNs event data} {
    foreach cmd $::allEventExec {
        {*}[subst $cmd]
    }
    switch $event {
        GUILD_CREATE {
            after idle [list coroutine ::meta::update_members[::id] \
                ::meta::update_members]
            puts "Ready"
            # welcome msg & helpful things
        }
        CHANNEL_CREATE {}
        MESSAGE_CREATE {
            foreach cmd $::eventExecute($event) {
                {*}[subst $cmd]
            }
            set channelId [dict get $data channel_id]
            if {[catch {dict get $data guild_id} guildId]} {
                set guildId ""
            }
            
            ::messageCreate $guildId $channelId $event $data
        }
        MESSAGE_UPDATE {
            coroutine ::meta::logEdit[::id] ::meta::logEdit $data
        }
        MESSAGE_DELETE {
            coroutine ::meta::logDelete[::id] ::meta::logDelete $data
        }
        READY -
        RESUMED -
        MESSAGE_DELETE_BULK -
        TYPING_START -
        INVITE_CREATE -
        INVITE_DELETE -
        USER_UPDATE {}
        GUILD_MEMBER_UPDATE -
        GUILD_BAN_ADD {}
        GUILD_BAN_REMOVE -
        CHANNEL_UPDATE -
        PRESENCE_UPDATE {
            coroutine handleGuildEvnt[::id] handleGuildEvnt $data \
                $event
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
                coroutine handleGuildEvnt[::id] handleGuildEvnt $data $action
            }
        }
        default {
            puts "mainCallbackHandler: Unknown event $event"
        }
    }
}

proc reboot {userId channelId} {
    if {$userId != $::ownerId} {return}
    foreach module [dict get $::settings modules] {
        [dict get $module module_name]::pre_reboot
        namespace delete [dict get $module module_name]
        source [file join $::scriptDir [dict get $module path]]
    }
    ::meta::putGc [dict create content "Reboot complete!"] 0 $channelId
}

proc shutdown {userId channelId {delay 10}} {
    if {$userId != $::ownerId} {return}
    if {$delay == "now"} {
        exit
    } else {
        ::meta::putGc [dict create content "Shutting down in $delay seconds"] \
            0 $channelId
        after [expr {$delay*1000}] {exit}
    }
}

proc registerCallbacks {sessionNs} {
    foreach event [dict keys $::discord::gateway::EventCallbacks] {
        discord setCallback $sessionNs $event ::mainCallbackHandler
        set ::eventExecute($event) {}
    }
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

puts -nonewline "% "
flush stdout
fconfigure stdin -blocking 0 -buffering line
fileevent stdin readable [list asyncGets stdin]

set startTime [clock seconds]
set session [discord connect $token ::registerCallbacks]

vwait forever

################################################################################
### Shutting down                                                            ###
################################################################################
if {[catch {discord disconnect $session} res]} {
    puts stderr $res
}

close $debugLog
${log}::delete