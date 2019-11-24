# pokebattle.tcl --
#
#       This file implements the Tcl code for Pokemon Battle simulator for
#       discord
#
# Copyright (c) 2018, Jerry Yong
#
# See the file "LICENSE" for information on usage and redistribution of this
# file.

package require sqlite3
package require http
    
if {![namespace exists meta]} {
    puts "Failed to load pokebattle.tcl: Requires meta.tcl to be loaded."
    return
}

if {![file exists "pokedexdb"]} {
    puts "Failed to load pokedex.tcl: Requires pokedexdb to be loaded."
    return
}

namespace eval pokebattle {
    sqlite3 pokedb "${scriptDir}/pokedb.sqlite3"
    
    set afterIds            [list]
    
    set battle(sessions)    [list]
    set battle(help)        ""
    set battle(title)       "Pok\u00E9mon Battles"
    set battle(defaultChan) "pokemon-battles-spectator"
    set battle(defaultCat)  "games"
    set battle(sessionMap)  {}
    set battle(gen)         7
    
    # sessionMap is a dictionary with the following key/value pair:
    #   guildId
    #     userId
    #       roomId - roomId is a list of roomIds.
    #                - it is preceded by & if the user has a pending challenge
    #                - it is preceded by ^ if the user has been challenged
    
    pokedb eval {
        CREATE TABLE IF NOT EXISTS config(
            param text,
            value text
        )
    }
    
    pokedb eval {
        CREATE TABLE IF NOT EXISTS preferences(
            guildId text,
            category text,
            categoryId text,
            channel text,
            channelId text
        )
    }
    
    pokedb eval {
        CREATE TABLE IF NOT EXISTS teams(
            userId text,
            teamId text,
            teamName text,
            pokemonId text,
            pokemonName text,
            nature text,
            ability text,
            gender text,
            item text,
            hpIV int,
            atkIV int,
            defIV int,
            spaIV int,
            spdIV int,
            speIV int,
            hpEV int,
            atkEV int,
            defEV int,
            spaEV int,
            spdEV int,
            speEV int,
            happy int
        )
    }
    
    if {![pokedb exists {SELECT 1 FROM config}]} {
        pokedb eval {
            INSERT INTO config VALUES
                ('disabledGuilds', ''),
                ('disabledChans', ''),
                ('bannedUsers', ''),
                ('jointimeout', '120000'),
                ('playwarning', '540000'),
                ('playtimeout', '600000')
        }
        set battle(jointimeout) 120000
        set battle(playwarning) 540000
        set battle(playtimeout) 600000
    } else {
        set battle(jointimeout) [pokedb eval {
            SELECT value FROM config WHERE param = 'jointimeout'
        }]
        set battle(playwarning) [pokedb eval {
            SELECT value FROM config WHERE param = 'playwarning'
        }]
        set battle(playtimeout) [pokedb eval {
            SELECT value FROM config WHERE param = 'playtimeout'
        }]
    }
    
    coroutine get_room_id apply {{} {
        set x 0
        while 1 {
            yield $x
            incr x
        }
    }}
}

proc pokebattle::command {} {
    variable battle
    upvar data data text text channelId channelId guildId guildId userId userId
    
    set banned \
        [pokedb eval {SELECT value FROM config WHERE param = 'bannedUsers'}]
    set disabledG \
        [pokedb eval {SELECT value FROM config WHERE param = 'disabledGuilds'}]
    set disabledC \
        [pokedb eval {SELECT value FROM config WHERE param = 'disabledChans'}]
    if {$userId in $banned} {
        return 0
    } elseif {
        ($guildId != "" && $guildId in $disabledG) || $channelId in $disabledC
    } {
        if {[lindex $text 0] != "!pokebattleset" } {return 0}
    }
    
    switch [lindex $text 0] {
        "!challenge" {
            if {
                ![::meta::has_perm [dict get \
                        [set ${::session}::self] id] {MANAGE_CHANNELS}]
            } {
                set msg "Sorry, I don't have the permissions on this server to "
                append msg "manage channels. I cannot host a $battle(title)."
                ::meta::putdc [dict create content $msg] 0
                return
            }
            challenge [regsub {!challenge *} $text ""]
        }
        "!accept" {accept [regsub {!accept *} $text ""]}
        "!decline" {decline [regsub {!decline *} $text ""]}
        "!surrender" -
        "!forfeit" {forfeit $guildId $channelId $userId}
        "!ppause" {pause $guildId $channelId $userId}
        "!presume" {resume $guildId $channelId $userId}
        
        "!pokebattleset" {
            if {![::meta::has_perm $userId {ADMINISTRATOR MANAGE_GUILD}]} {
                return
            }
            settings $guildId $channelId $userId \
                    {*}[regsub {!pokebattleset } $text ""]

        }
        default {
            set found 0
            foreach {room data} $battle(sessions) {
                set cListeners [dict get $data listeners]
                set pause [dict get $data pause]
                if {[llength $cListeners] > 0 && $::listener > 0 && !$pause} {
                    for {set i 0} {$i < [llength $cListeners]} {incr i} {
                        set cmd [lindex $cListeners $i]
                        if {
                            $userId == [dict get $cmd id]  &&
                            [string toupper $text] in [dict get $cmd word]
                        } {
                            set cListeners [lreplace $cListeners $i $i]
                            dict set battle(sessions) $room listeners \
                                    $cListeners
                            {*}[dict get $cmd cmd] $text
                            incr i -1
                            incr ::listener -1
                            set found 1
                            break
                        }
                    }
                    if {$found} {break}
                }
            }
            return $found
        }
    }
    return 1
}

proc pokebattle::challenge {text} {
    upvar guildId guildId channelId channelId userId userId
    variable battle
    variable afterIds
    lassign [pokedb eval {
        SELECT guildId, category, categoryId, channel, channelId
        FROM preferences
        WHERE guildId = :guildId LIMIT 1
    }] guild categoryName categoryId channelNames channelIds
    
    set guildData {*}[guild eval {
        SELECT data FROM guild WHERE guildId = :guildId
    }]
    set channels [dict get $guildData channels]
    
    if {$guild == ""} {
        set exists ""
        foreach chan $channels {
            if {
                [dict get $chan type] == 0
                && [dict get $chan name] eq $battle(defaultChan)
            } {
                set exists [dict get $chan id]
            }
        }
        
        if {$exists != ""} {
            pokedb eval {UPDATE preferences SET channelId = :exists}
            if {$channelId != $exists} {
                set msg "Please use <#exists> to create a $battle(title) "
                append msg "challenge."
                ::meta::putdc [dict create content $msg] 1
                return
            }
        } else {
            create_channels $guild $guildId $categoryName $categoryId \
                    $channels $channelNames $channelIds
        }
    } else {
        
        
    }
    
    
    
    if {
        ![correct_channel $guildId $channelId $channels $channelNames \
                $channelIds]
    } {
        create_channels $guild $guildId $categoryName $categoryId $channels \
                $channelNames $channelIds
    }
    
    return
    set currentChanIds [lmap chan $channels {
        if {[dict get $chan type] == 0} {
            set chan [dict get $chan id]
        } else {
            continue
        }
    }]
    set currentCatIds [lmap chan $channels {
        if {[dict get $chan type] == 4} {
            set chan [dict get $chan id]
        } else {
            continue
        }
    }]
    
    foreach id $channelIds {
        if {$id ni $currentChanIds} {
            set channelIds ""
            break
        }
    }
    if {$categoryId ni $currentCatIds} {set categoryId ""}
    
    if {$channelIds == ""} {
        set channelIds [lrepeat [llength $channelnames] {}]
        foreach channel $channels {
            set idx [lsearch $channelnames [dict get $channel name]]
            if {$idx > -1} {
                if {
                    [catch {dict get $channel parent_id} parentId] && 
                    ($categoryId == "" || $categoryId == $parentId)
                } {
                    lset channelIds $idx [dict get $channel id]
                    set categoryId $parentId
                }
            }
        }
    }
    
    
    
    
    
    
    
    
    
    set gen $battle(gen)
    
    if {$text != ""} {
        if {$text eq "help"} {
            set msg "Instructions for $battle(title) can be found here: "
            append msg $battle(help)
            ::meta::putdc [dict create content $msg] 0
            return
        }
        
        if {$text eq "remove"} {
            set room [dict get $battle(sessionMap) $guildId $userId]
            regexp {[0-9]+} [lsearch -inline $room "&*"] room
            if {$room == ""} {
                set msg "You do not have any pending challenges!"
                ::meta::putdc [dict create content $msg] 0
                return
            }
            set cmd \
                    [list ::pokebattle::end_battle $guildId $channelId $userId \
                    $room 0]
            set listeners [dict get $battle(sessions) $room listeners]
            lappend listeners [dict create id $userId cmd $cmd word {Y N}]
            dict set battle(sessions) $room listeners $listeners
            set msg "Are you sure you want to remove your current challenge? "
            append msg "(Y/N)"
            incr ::listener
            ::meta::putdc [dict create content $msg] 0
            return
        }
        
        regexp -- { -gen +([0-9])\y} $text - gen
        if {$gen != "" && $gen >= 8} {
            set msg "Error: Unsupported generation. Generations supported range"
            append msg " from 1 to $battle(gen)."
            ::meta::putdc [dict create content $msg] 0
            return
        }
        
        set targetId [::meta::get_user_id $guildId $text]
        if {$targetId == ""} {
            set msg "This user could not be found or too many users were matched"
            ::meta::putdc [dict create content $msg] 0
            return
        }
    }
    
    set catExists 0
    set chanExists 0
    set parentId ""
    

    
    set chanCreate $channelnames
    foreach channel $channels {
        if {
            [string equal -nocase [dict get $channel name] $categoryname]
            && [dict get $channel type] == 4
        } {
            set parentId [dict get $channel id]
            set catExists 1
        }
        for {set i 0} {[llength $chanCreate] > $i} {incr i} {
            set channelname [lindex $chanCreate $i]
            if {
                [string equal -nocase [dict get $channel name] $channelname]
                && [dict get $channel type] == 0
            } {
                set chanCreate [lreplace $chanCreate $i $i]
                incr i -1
            }
        }
    }
    
    if {!$chanExists} {
        if {!$catExists} {
            if {
                [catch {
                    discord createChannel $::session $guildId $categoryname \
                        [dict create type 4] 1
                    } resCoro]
            } {
                return
            }
            if {$resCoro eq {}} {return}
            yield $resCoro
            set response [$resCoro]
            set data [lindex $response 0]
            set parentId [dict get $data id]
        } 
        set topic "Spectator room for $battle(title) (basic commands: "
        append topic "!challenge !accept !surrender !pause !resume)"
        set channelnames [lassign $channelnames channelname]
        if {
            [catch {
                discord createChannel $::session $guildId $channelname \
                    [dict create type 0 topic $topic parent_id $parentId] 1
                } resCoro]
        } {
            return
        }
        foreach channelname $channelnames {
            discord createChannel $::session $guildId $channelname \
                [dict create type 0 topic $topic parent_id $parentId]
        }
        if {$resCoro eq {}} {return}
        yield $resCoro
        set response [$resCoro]
        set data [lindex $response 0]
        set channelId [dict get $data id]
    } else {
        if {
            [dict exists $chanData parent_id]
            && $parentId != [dict get $chanData parent_id]
        } {
            set parentId [dict get $chanData parent_id]
        }
    }
    pokedb eval {
        UPDATE preferences SET channelId = :channelId WHERE guildId = :guildId
    }
    
    
    if {[dict exists $battle(sessionMap) $guildId $userId]} {
        set msg "You cannot create a new challenge when you have a pending "
        append msg "challenge or are in a battle!"
    } else {
        set room [get_room_id]
        dict set battle(sessionMap) $guildId $userId "&$room"
        
        set afterId [after $battle(jointimeout) [list ::pokebattle::end_battle \
            $guildId $channelId $userId $room]]
        lappend afterIds $afterId
        if {$targetId == ""} {
            dict set battle(sessions) $room [dict create mode 1 chan \
                $channelId players [list [dict create trainer $userId chan {} \
                team {} field {}]] guild $guildId parent $parentId after \
                $afterId playerlist [list $userId] responses "" activated "" \
                pause 0 listeners "" pending "" gen $gen \
            ]
            
            set msg "<@$userId> has an open challenge for a $battle(title). "
            append msg "Type `!accept` to accept the challenge and battle. The "
            append msg "challenge will expire in "
            append msg "[expr {$battle(jointimeout)/1000}] seconds."
        } else {
            dict set battle(sessionMap) $guildId $targetId "^$room"
            dict set battle(sessions) $room [dict create mode 1 chan \
                $channelId players [list [dict create trainer $userId chan {} \
                team {} field {}] [dict create trainer $targetId chan {} team \
                {} field {}]] guild $guildId parent $parentId after $afterId \
                playerlist [list $userId $targetId] responses "" activated "" \
                pause 0 listeners "" pending "" gen $gen \
            ]
            
            set msg "<@$userId> has challenged <@$targetId> for a match of "
            append msg "$battle(title). Type `!accept` to accept the challenge "
            append msg "or `!decline` to decline. The challenge will expire in "
            append msg "[expr {$battle(jointimeout)/1000}] seconds."
        }
    }
    ::meta::putdc [dict create content $msg] 0 $channelId
}

proc pokebattle::accept {text} {
    upvar guildId guildId channelId channelId userId userId
    variable battle
    
    # No game running on this guild or wrong channel
    if {![dict exists $battle(sessionMap) $guildId]} {
        return
    }
    
    set chan [pokedb eval {
        SELECT channelId FROM preferences WHERE guildId = :guildId
    }]
    if {$channelId ni $chan} {return}
    
    if {$text == ""} {
        if {[dict exists $battle(sessionMap) $guildId $userId]} {
            set rooms [dict get $battle(sessionMap) $guildId $userId]
            
            if {[lsearch -not $rooms {[&^]*}] > -1} {
                set msg "You are already in a battle!"
                ::meta::putdc [dict create content $msg] 0
                return
            } elseif {[llength [lsearch -all $rooms {^*}]] == 1} {
                set roomId [string map {^ &} [lsearch -inline $rooms {^*}]]
            } elseif {[llength [lsearch -all $rooms {^*}]] > 1} {
                set msg "There are multiple pending challenges. Please specify "
                append msg "which one you are accepting (use `!accept @user`)."
                ::meta::putdc [dict create content $msg] 0
                return
            } elseif {[lsearch $rooms {&*}] > -1} {
                set msg "You cannot accept your own challenge!"
                ::meta::putdc [dict create content $msg] 0
                return
            }
        } else {
            set rooms [lsearch -all [concat \
                {*}[dict values [dict get $battle(sessionMap) $guildId]]] {&*}]
            foreach room $rooms {
                if {[catch {dict get $unique $room} count]} {
                    set count 0
                }
                dict set unique $room [incr count]
            }
            set unique [dict keys [dict filter $unique values 1]]
            
            if {[llength $unique] > 1} {
                set msg "There are multiple pending challenges. Please specify "
                append msg "which one you are accepting (use `!accept @user`)."
                ::meta::putdc [dict create content $msg] 0
                return
            } elseif {[llength $unique] == 1} {
                set roomId [lindex $unique 0]
            } else {
                set msg "There are no free pending challenge requests."
                ::meta::putdc [dict create content $msg] 0
                return
            }
        }
        
        set found 0
        dict for {targetId rooms} [dict get $battle(sessionMap) $guildId] {
            if {$roomId in $rooms} {
                set found 1
                break
            }
        }
        if {!$found} {
            ::meta::putdc [dicr create content "Oops, something went wrong."] 0
            return
        }
        set room [string range $roomId 1 end]
        dict set battle(sessionMap) $guildId $userId $room
        dict set battle(sessionMap) $guildId $targetId $room
        
        set cplayers [dict get $battle(sessions) $room players]
        lappend cplayers [dict create trainer $userId chan {} team {} field {}]
        dict set battle(sessions) $room players $cplayers
        
        set playerlist [dict get $battle(sessions) $room playerlist]
        lappend playerlist $userId
        dict set battle(sessions) $room playerlist $playerlist
        
        set msg "<@$userId> has accepted <@targetId>'s challenge!"
        ::meta::putdc [dict create content $msg] 0
        
        start_battle $guildId $channelId [lindex $playerlist 0]
    } else {
        
    }
}

proc pokebattle::decline {text} {
    upvar guildId guildId channelId channelId userId userId
    variable battle
    
    # No game running on this guild or wrong channel
    if {![dict exists $battle(sessionMap) $guildId]} {
        return
    }
    lassign [dict get $battle(sessionMap) $guildId] - room
    if {[dict get $battle(sessions) $room chan] != $channelId} {
        return
    }
    
    if {[dict exists $battle(sessionMap) $guildId $userId]} {
        ::meta::putdc \
            [dict create content "You cannot decline your own challenge!"] 0
        return
    }
    
    dict unset battle(sessions) $room
    dict unset battle(sessionMap) $guildId $userId
    
    ::meta::putdc \
            [dict create content "<@$userId> has declined the challenge!"] 0
}

proc pokebattle::end_battle {guildId channelId userId room {auto 1} {arg "Y"}} {
    variable battle
    variable afterIds
    if {$arg eq "Y" && [dict exists $battle(sessions) $room]} {
        set afterId [dict get $battle(sessions) $room after]
        if {$afterId in $afterIds} {
            set id [lsearch $afterIds $afterId]
            set afterIds [lreplace $afterIds $id $id]
        }
        catch {after cancel $afterId}
        
        set mode [dict get $battle(sessions) $room mode]
        set players [dict get $battle(sessions) $room players]
        if {$mode == 1} {
            if {$auto == 1} {
                set msg "No one took the challenge. The challenge was removed."
            } elseif {$auto == 0} {
                set msg "Your challenge has been removed."
            }
        } elseif {$mode >= 2} {
            set playerlist [dict get $batte(sessions) $room playerlist]
            set idx [lsearch $playerlist $userId]
            set idx [expr {1-$idx}]
            set targetId [lindex $playerlist $idx]
            if {$auto == 1} {
                set msg "<@$userId> was timed out. <@$targetId> wins this"
                append msg " battle by default."
            } elseif {$auto == 0} {
                set msg "<@$userId> has forfeited the battle. <@$targetId> wins."
            }
        }
        
        set listeners [dict get $battle(sessions) $room listeners]
        set cListeners [llength $listeners]
        incr ::listener [expr {-1*$cListeners}]
        
        foreach player $players {
            set trainerId [dict get $player trainer]
            set chan [dict get $player chan]
            if {$chan != "" && $chan != "DM"} {
                catch {discord deleteChannel $::session $chan}
            }
            remove_timers $trainerId $room 
        }
        
        if {$msg != ""} {announce $room $msg}
        dict unset battle(sessions) $room
    }
}

proc pokebattle::stop_game {guildId channelId userId} {
    return 0
}

proc pokebattle::forfeit {guildId channelId userId {auto 0} {arg "Y"}} {
    variable battle
}

proc pokebattle::pause {guildId channelId userId} {
    variable battle
    variable afterIds
    # No game running on this guild or wrong channel
    if {![dict exists $battle(sessionMap) $guildId $userId]} {
        return
    } else {
        set room [dict get $battle(sessionMap) $guildId $userId]
    }
    if {[dict get $battle(sessions) $room chan] != $channelId} {return}

    set players [dict get $battle(sessions) $room playerlist]
    if {$userId ni $playerlist} {return}
    dict set battle(sessions) $room pause $userId
    
    set responses [dict get $battle(sessions) $room responses]
    set pending [list]
    set userIds [dict keys $responses]
    foreach userId $userIds {
        set ids [dict get $responses $userId]
        foreach id $ids {
            lappend pending [lindex [after info $id] 0]
            set i [lsearch $afterIds $id]
            set afterIds [lreplace $afterIds $i $i]
            after cancel $id
        }
    }
    dict set battle(sessions) $room pending $pending
    announce $guildId "The battle has been paused."
}

proc pokebattle::resume {guildId channelId userId} {
    variable battle
    variable afterIds
    # No game running on this guild or wrong channel
    if {![dict exists $battle(sessionMap) $guildId $userId]} {
        return
    } else {
        set room [dict get $battle(sessionMap) $guildId $userId]
    }
    if {[dict get $battle(sessions) $room chan] != $channelId} {return}
    
    set pauseId [dict get $battle(sessions) $room pause]
    if {$userId != $pauseId} {
        set guildData {*}[guild eval {
            SELECT data FROM guild WHERE guildId = :guildId
        }]
        set presences [dict get $guildData presences]
        set idx [lsearch $presences "*$pauseId*"]
        if {
            $idx != -1 
            && [dict get [lindex $presences $idx] status] ne "offline"
        } {
            set msg "Only the player who paused the game can resume the game, "
            append msg "unless the that player is offline."
            ::meta::putdc [dict create content $msg] 0 $channelId
            return
        } elseif {$userId ni [dict get $battle(sessions) $room playerlist]} {
            return
        }
    }
    
    dict set battle(sessions) $room pause ""
    
    set responses [dict get $battle(sessions) $room responses]
    set pending [dict get $battle(sessions) $room pending]
    set userIds [dict keys $responses]
    foreach cmd $pending {
        lassign $cmd proc guildId channelId userId type
        set responses [dict get $battle(sessions) $room responses $userId]
        if {$type == 1} {
            set id [after $game(playwarning) $cmd]
            lappend afterIds $id
            lset responses 0 $id
        } elseif {$type == 0} {
            set id [after $game(playtimeout) $cmd]
            lappend afterIds $id
            lset responses 1 $id
        } else {
            puts unrecognized
        }
        dict set battle(sessions) $room responses $userId $responses
    }
    dict set battle(sessions) $room pending {}
    announce $room "The battle has been resumed."
}

proc pokebattle::start_battle {guildId channelId userId} {}

##
# Helpers
##
proc pokebattle::announce {room msg} {
    variable battle
    ::meta::putdc [dict create content $msg] 0 \
        [dict get $battle(sessions) $room chan]
    foreach player [dict get $battle(sessions) $room players] {
        private_say [dict get $player chan] [dict get $player trainer] $msg
    }
}

proc pokebattle::private_say {channelId userId msg} {
    variable battle
    if {$channelId == "DM"} {
        ::meta::putdcPM $userId [dict create content $msg] 0
    } elseif {$channelId != ""} {
        ::meta::putdc [dict create content $msg] 0 $channelId
    }
}

proc pokebattle::check_battle {guildId channelId userId room {warning 0}} {
    variable battle
    
    set cplayers [dict get $battle(sessions) $room playerlist]
    if {$warning} {
        set msg "Warning: You have "
        append msg "[expr {($battle(playtimeout)-$battle(playwarning))/1000}] "
        append msg "more seconds to make your selection before you time out."
        private_say $channelId $userId $msg
    } else {
        forfeit $guildId $channelId $userId 1 "Y"
    }
}

proc pokebattle::add_timer {guildId channelId userId room} {
    variable battle
    variable afterIds
    set responses [dict get $battle(sessions) $room responses]
    set id1 [after $battle(playwarning) \
        [list ::pokebattle::check_battle $guildId $channelId $userId $room 1]]
    lappend afterIds $id1
    set id2 [after $battle(playtimeout) \
        [list ::pokebattle::check_battle $guildId $channelId $userId $room 0]]
    lappend afterIds $id2
    dict set responses $userId [list $id1 $id2]
    dict set battle(sessions) $room responses $responses
}

proc pokebattle::remove_timers {userId room} {
    variable battle
    variable afterIds
    set responses [dict get $battle(sessions) $room responses]
    if {![catch {dict get $responses $userId} ids]} {
        foreach id $ids {
            if {$id in $afterIds} {
                set i [lsearch $afterIds $id]
                set afterIds [lreplace $afterIds $i $i]
            }
            after cancel $id
        }
        dict unset responses $userId
        dict set battle(sessions) $room responses $responses
    }
}

proc pokebattle::correct_channel {
    guildId channelId channels channelnames channelIds
} {
    if {$channelIds != ""} {
        set idx [lsearch $channelIds $channelId]
        if {$idx > -1} {
            set name [lindex $channelnames $idx]
            foreach chan $channels {
                if {
                    [dict get $chan id] == $channelId 
                    && [dict get $chan name] == $name
                } {
                    return 1
                }
            }
        }
    }
    return 0
}

proc pokebattle::create_channels {
    guild guildId categoryname categoryId channels channelnames channelIds
} {
    variable battle
    
    if {$guild == ""} {
        pokedb eval {
            INSERT INTO preferences VALUES
                (:guildId, :battle(defaultCat), '', :battle(defaultChan), '')
        }
        set categoryname $battle(defaultCat)
        set channelnames $battle(defaultChan)
    }
    if {$categoryname == ""} {set categoryname $battle(defaultCat)}
    if {$channelnames == ""} {set channelnames $battle(defaultChan)}
    
    set parentId ""
    set currentChanIds [lmap chan $channels {
        if {[dict get $chan type] == 0} {
            set chan [dict get $chan id]
        } else {
            continue
        }
    }]
    
    if {$channelsIds == ""} {
        
    }
    
}

##
# Moderation
##
proc pokebattle::settings {guildId channelId userId args} {
    for {set i 0} {$i < [llength $args]} {incr i} {
        set setting [lindex $args $i]
        set msg "Unable to change the setting $setting; value provided is not "
        append msg "recognised as being either true or false."
        switch $setting {
            guild {
                set value [lindex $args [incr i]]
                if {[string is true -strict $value]} {
                    enable_guild $guildId $channelId $userId
                } elseif {[string is false -strict $value]} {
                    disable_guild $guildId $channelId $userId
                } else {
                    ::meta::putdc [dict create content $msg] 0
                }
            }
            channel {
                set value [lindex $args [incr i]]
                set channels [lindex $args [incr i]]
                if {[string is true -strict $value]} {
                    enable_channel $guildId $channelId $userId $channels
                } elseif {[string is false -strict $value]} {
                    disable_channel $guildId $channelId $userId $channels
                } else {
                    ::meta::putdc [dict create content $msg] 0
                }
            }
            ban {
                set value [lindex $args [incr i]]
                set users [lindex $args [incr i]]
                if {[string is true -strict $value]} {
                    ban_user $guildId $channelId $userId $users
                } elseif {[string is false -strict $value]} {
                    unban_user $guildId $channelId $userId $users
                } else {
                    ::meta::putdc [dict create content $msg] 0
                }
            }
            category {
                set value [lindex $args [incr i]]
                default_category $guildId $channelId $userId $value
            }
            default_channel {
                set value [lindex $args [incr i]]
                default_channel $guildId $channelId $userId $value
            }
        }
    }
}

proc pokebattle::ban_user {guildId channelId userId targets} {
    variable battle
    set banned [list]
    foreach target $targets {
        if {[regexp {^<@!?([0-9]+)>$} $target - user]} {
            set targetId $user
        } elseif {$target == ""} {
            ::meta::putdc \
                [dict create content "Error: User to ban was not mentioned."] 0
            return
        } else {
            set guildData {*}[guild eval {
                SELECT data FROM guild WHERE guildId = :guildId
            }]
            set members [dict get $guildData members]
            set data [lsearch -inline -nocase $members "*$target*"]
            if {$data == ""} {
                ::meta::putdc [dict create content "No such user found."] 0
                return
            } else {
                set targetId [dict get $data user id]
            }
        }
        
        set banned [pokedb eval {
            SELECT value FROM config WHERE param = 'bannedUsers'
        }]
        if {$targetId in $banned} {
            ::meta::putdc [dict create content \
                "<@$targetId> is already banned from $battle(title)."] 0
        } else {
            lappend banned $targetId
            pokedb eval {
                UPDATE config SET value = :banned WHERE param = 'bannedUsers'
            }
            lappend banned "<@$targetId>"
            kill_player $guildId $channelId $userId 0 "Y"
        }
    }
    if {[llength $banned] == 1} {
        ::meta::putdc [dict create content \
            "[join banned] has been banned from $battle(title)."] 0
    } elseif {[llength $banned] > 1} {
        ::meta::putdc [dict create content \
            "[join banned {, }] have been banned from $battle(title)."] 0
    }
}

proc pokebattle::unban_user {guildId channelId userId targets} {
    variable battle
    set unbanned [list]
    foreach target $targets {
        if {[regexp {^<@!?([0-9]+)>$} $target - user]} {
            set targetId $user
        } elseif {$target == ""} {
            ::meta::putdc [dict create content \
                "Error: User to ban was not mentioned."] 0
            return
        } else {
            set guildData {*}[guild eval {
                SELECT data FROM guild WHERE guildId = :guildId
            }]
            set members [dict get $guildData members]
            set data [lsearch -inline -nocase $members "*$target*"]
            if {$data == ""} {
                ::meta::putdc [dict create content "No such user found."] 0
                return
            } else {
                set targetId [dict get $data user id]
            }
        }
        
        set banned [pokedb eval {
            SELECT value FROM config WHERE param = 'bannedUsers'
        }]
        set idx [lsearch $banned $targetId]
        if {$idx == -1} {
            ::meta::putdc [dict create content "<@$targetId> is not banned."] 0
        } else {
            set banned [lreplace $banned $idx $idx]
            pokedb eval {
                UPDATE config SET value = :banned WHERE param = 'bannedUsers'
            }
            lappend unbanned "<@$targetId>"
        }
    }
    if {[llength $unbanned] == 1} {
        ::meta::putdc [dict create content \
            "[join unbanned] has been unbanned from $battle(title)."] 0
    } elseif {[llength $banned] > 1} {
        ::meta::putdc [dict create content \
            "[join unbanned {, }] have been unbanned from $battle(title)."] 0
    }
}

proc pokebattle::disable_guild {guildId channelId userId} {
    variable battle
    set guilds [pokedb eval {
        SELECT value FROM config WHERE param = 'disabledGuilds'
    }]
    lappend guilds $guildId
    pokedb eval {
        UPDATE config SET value = :guilds WHERE param = 'disabledGuilds'
    }
    
    ::meta::putdc [dict create content \
        "$battle(title) has been disabled on this server."] 0
    kill_game $guildId $channelId $userId 0 "Y"
}

proc pokebattle::enable_guild {guildId channelId userId} {
    variable battle
    set guilds [pokedb eval {
        SELECT value FROM config WHERE param = 'disabledGuilds'
    }]
    set idx [lsearch $guilds $guildId]
    if {$idx == -1} {
        ::meta::putdc [dict create content \
            "$battle(title) is already enabled on this server."] 0
    } else {
        set guilds [lreplace $guilds $idx $idx]
        pokedb eval {
            UPDATE config SET value = :guilds WHERE param = 'disabledGuilds'
        }
        ::meta::putdc [dict create content \
            "$battle(title) has been enabled on this server."] 0
    }
}

proc pokebattle::disable_channel {guildId channelId userId {others ""}} {
    variable battle
    set chans [pokedb eval {
        SELECT value FROM config WHERE param = 'disabledChans'
    }]
    if {$others == ""} {
        lappend chans $channelId
        pokedb eval {
            UPDATE config SET value = :chans WHERE param = 'disabledChans'
        }
        ::meta::putdc [dict create content \
            "War of the Seas has been disabled on this channel."] 0
    } else {
        set done [list]
        set skip [list]
        foreach chan $others {
            if {[regexp {<#([0-9]+)>} $chan - id]} {
                if {$chan in $chans} {
                    lappend skip $chan
                } else {
                    lappend chans $chan
                    lappend done $chan
                }
            } else {
                # Textual search
                lappend skip $chan
            }
        }
        pokedb eval {
            UPDATE config SET value = :chans WHERE param = 'disabledChans'
                }
        set parts [list]
        if {$done != ""} {
            set msg "$battle(title) has been disabled on the following "
            append msg "channel(s): [join $done {, }]"
            lappend parts $msg
        }
        if {$skip != ""} {
            set msg "The following channels already have $battle(title) "
            append msg "disabled: [join $skip {, }]"
            lappend parts $msg
        }
        ::meta::putdc [dict create content [join $parts "\n"]] 0
    }
}

proc pokebattle::enable_channel {guildId channelId userId {others ""}} {
    variable battle
    set chans [pokedb eval {
        SELECT value FROM config WHERE param = 'disabledChans'
    }]
    if {$others == ""} {
        set idx [lsearch $chans $channelId]
        if {$idx == -1} {
            ::meta::putdc [dict create content \
                "$battle(title) is already enabled on this channel."] 0
        } else {
            set chans [lreplace $chans $idx $idx]
            pokedb eval {
                UPDATE config SET value = :chans WHERE param = 'disabledChans'
            }
            ::meta::putdc [dict create content \
                "$battle(title) has been enabled on this channel."] 0
        }
    } else {
        set done [list]
        set skip [list]
        foreach chan $others {
            if {[regexp {<#([0-9]+)>} $chan - id]} {
                if {$chan in $chans} {
                    set idx [lsearch $chans $chan]
                    set chans [lreplace $chans $idx $idx]
                    lappend done $chan
                } else {
                    lappend skip $chan
                }
            } else {
                # Textual search
                lappend skip $chan
            }
        }
        pokedb eval {
            UPDATE config SET value = :chans WHERE param = 'disabledChans'
        }
        set parts [list]
        if {$done != ""} {
            set msg "$battle(title) has been enabled on the following "
            append msg "channel(s): [join $done {, }]"
            lappend parts $msg
        }
        if {$skip != ""} {
            set msg "The following channels already have $battle(title) enabled:"
            append msg " [join $skip {, }]"
            lappend parts $msg
        }
        ::meta::putdc [dict create content [join $parts "\n"]] 0
    }
}

proc pokebattle::default_category {guildId channelId userId category} {
    variable battle
    set cDefault [pokedb eval {
        SELECT category FROM preferences WHERE guildId = :guildId
    }]
    set newcategory [::meta::channame_clean $category]
    
    if {$cDefault == ""} {
        pokedb eval {
            INSERT INTO preferences VALUES (:guildId, :newcategory, '', '', '')
        }
    } elseif {$cDefault ne $newcategory} {
        pokedb eval {
            UPDATE preferences SET category = :newcategory 
            WHERE guildId = :guildId
        }
    } else {
        set msg "The default category name is already set to $category"
        if {$newcategory ne $category} {
            append msg "(after applying Discord's category name restrictions of"
            append msg " only lowercase alphanumeric characters, underscores and"
            append msg " dashes allowed)."
        } else {
            append msg "."
        }
        ::meta::putdc [dict create content $msg] 0
        return
    }
    set msg "Default category name for $battle(title) successfully set!"
    if {$newcategory ne $category} {
        append msg " Some changes were necessary due to Discord's restriction "
        append msg "on category names (only lowercase alphanumeric characters, "
        append msg "underscores and dashes allowed), however. The new category "
        append msg "name is $newcategory"
    }
    ::meta::putdc [dict create content $msg] 0
}

proc pokebattle::default_channel {guildId channelId userId channels} {
    variable battle
    set cDefault [pokedb eval {
        SELECT channel FROM preferences WHERE guildId = :guildId
    }]
    set newchannels [lmap x $channels {::meta::channame_clean $x}]
    if {$cDefault == ""} {
        pokedb eval {
            INSERT INTO preferences VALUES (:guildId, '', '', :newchannels, '')
        }
    } elseif {[lsort $cDefault] != [lsort $newchannels]} {
        pokedb eval {
            UPDATE preferences
            SET
                channel = :newchannels,
                channelId = ''
            WHERE guildId = :guildId
        }
    } else {
        set msg "The default channel name already has those settings"
        if {[lsort $cDefault] != [lsort $channels]} {
            append msg " (after applying Discord's channel name restrictions of"
            append msg " only lowercase alphanumeric characters, underscores "
            append msg "and dashes allowed)."
        } else {
            append msg "."
        }
        ::meta::putdc [dict create content $msg] 0
        return
    }
    
    set msg "Default channel name for $battle(title) successfully set!"
    if {$newchannels ne $channels} {
        append msg " Some changes were necessary due to Discord's restriction "
        append msg "on channel names (only lowercase alphanumeric characters, "
        append msg "underscores and dashes allowed)."
    }
    ::meta::putdc [dict create content $msg] 0
}

proc pokebattle::pre_rehash {} {
    variable afterIds
    foreach id $afterIds {
        after cancel $id
    }
    
    # Message running battles that there is an ongoing rehash
}

puts "pokebattle.tcl v0.1 loaded"