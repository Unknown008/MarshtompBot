#!/bin/sh
# This line and the trailing backslash  is required so that tclsh ignores the next line \
exec tclsh8.6 "$0" "${1+"$@"}"

# tclqBot.tcl --
#
#       This file implements the Tcl code for a Discord bot written with the
#       discord.tcl library.
#
# Copyright (c) 2016, Yixin Zhang
#
# See the file "LICENSE" for information on usage and redistribution of this
# file.

package require Tcl 8.6
package require sqlite3

set scriptDir [file dirname [info script]]
# Add parent directory to auto_path so that Tcl can find the discord package.
lappend ::auto_path "${scriptDir}/../"
package require discord

# Open sqlite3 database
sqlite3 procsDb "${scriptDir}/procs.sqlite3"
procsDb eval { CREATE TABLE IF NOT EXISTS
    procs(guildId text, name text, args text, body text)
}

proc procSave { sandbox guildId name args body } {
    set validName {^[a-zA-Z0-9_\-]+$}
    if {![regexp $validName $name]} {
        return -code error "proc name must match the regex '$validName': $name"
    }
    if {![catch {$sandbox invokehidden -global proc $name $args $body} res]} {
        procsDb eval {INSERT OR REPLACE INTO procs
            VALUES($guildId, $name, $args, $body)
        }
        return
    } else {
        return -code error $res
    }
}

# Set ownerId and token variables
source "${scriptDir}/private.tcl"

# Ad-hoc log file size limiting follows
set debugFile "${scriptDir}/debug"
set debugLog {}
set maxSize [expr {4 * 1024**2}]
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
    puts $debugLog \
            "[clock format [clock seconds] -format {[%Y-%m-%d %T]}] $text"
    flush $debugLog
}

if {[catch {open $debugFile "a"} debugLog]} {
    puts stderr $debugLog
} else {
    ${discord::log}::logproc debug ::logDebug
}

# Set to 0 for a cleaner debug log.
discord::gateway logWsMsg 1
${discord::log}::setlevel debug

proc handlePlease { sessionNs data text } {
    set channelId [dict get $data channel_id]
    switch -regexp -matchvar match -- $text {
        {^eval ```(.*)```$} -
        {^eval `(.*)`$} -
        {^eval (.*)$} {
            set code [lindex $match 1]
            set guildId [dict get [set ${sessionNs}::channels] $channelId]
            set sandbox [dict get $::guildInterps $guildId]
            $sandbox limit time -seconds [expr {[clock seconds] + 2}]
            catch {
                $sandbox eval [list set data $data]
                $sandbox eval [list uplevel #0 $code]
            } res
            if {[string length $res] > 0} {
                discord sendMessage $::session $channelId $res
            }
        }
    }
}

proc messageCreate { sessionNs event data } {
    set id [dict get $data author id]
    if {$id eq [dict get [set ${sessionNs}::self] id]} {
        return
    }
    if {[dict exists $data bot] && [dict get $data bot] eq "true"} {
        return
    }
    if {![catch {dict get [set ${sessionNs}::users] $id} user]} {
        if {[dict exists $user bot] && [dict get $user bot] eq "true"} {
            return
        }
    }
    set content [dict get $data content]
    if {[regexp {^Please (.*)$} $content -> text]} {
        handlePlease $sessionNs $data $text
    }
}

proc guildCreate { sessionNs event data } {
    # Setup safe interp for "Please eval"
    set guildId [dict get $data id]
    dict set ::guildInterps $guildId [interp create -safe]
    set sandbox [dict get $::guildInterps $guildId]

    # Restore saved procs
    set savedProcs \
            [procsDb eval {SELECT * FROM procs WHERE guildId IS $guildId}]
    foreach {- name args body} $savedProcs {
        $sandbox eval [list proc $name $args $body]
    }
    # Use procSave to save proc by guildId
    $sandbox hide proc
    $sandbox alias proc procSave $sandbox $guildId

    $sandbox alias self getSession self
    $sandbox alias guilds getSession guilds
    $sandbox alias users getSession users
    $sandbox alias dmChannels getSession dmChannels
    $sandbox alias send discord sendMessage $sessionNs
    #$sandbox limit command -value 100
}

proc registerCallbacks { sessionNs } {
    discord setCallback $sessionNs GUILD_CREATE ::guildCreate
    discord setCallback $sessionNs MESSAGE_CREATE ::messageCreate
}

proc getSession { varName } {
    return [set ${::session}::${varName}]
}

set guildInterps [dict create]
set session [discord connect $token ::registerCallbacks]

# For console stdin eval
proc asyncGets {chan {callback ""}} {
    if {[gets $chan line] >= 0} {
        if {[string trim $line] ne ""} {
            catch {uplevel #0 $line} out
            puts $out
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

vwait forever

if {[catch {discord disconnect $session} res]} {
    puts stderr $res
}
close $debugLog
procsDb close
