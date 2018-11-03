namespace eval wots {
  variable game
  
  sqlite3 wotsdb "${scriptDir}/wotsdb.sqlite3"
  
  # Game Sessions
  set game(sessions)     [list]
  # Help
  set game(help)         ""
  set game(listeners)    [list]
  set game(deck)         [list]
  set game)specChan)     "waroftheseas-spectator"
  set game(parent)       "games"
  
  wotsdb eval {
    CREATE TABLE IF NOT EXISTS config(
      param text,
      value text
    )
  }
  
  wotsdb eval {
    CREATE TABLE IF NOT EXISTS preferences(
      guildId text,
      category text,
      channel text
    )
  }
  
  if {![wotsdb exists {SELECT 1 FROM config}]} {
    wotsdb eval {
      INSERT INTO config VALUES
      ('disabledGuilds', ''),
      ('disabledChans', ''),
      ('bannedUsers', ''),
      ('jointimeout', '120000'),
      ('playtimeout', '120000')
    }
    set game(jointimeout) 120000
    set game(playtimeout) 120000
  } else {
    set game(jointimeout) [wotsdb eval {SELECT value FROM config WHERE param = 'jointimeout'}]
    set game(playtimeout) [wotsdb eval {SELECT value FROM config WHERE param = 'playtimeout'}]
  }
  
  set suits [list Skull Ship Sword Coin]
  foreach suit $suits {
    for {set i 1} {$i < 11} {incr i} {
      lappend game(deck) [list $suit $i]
    }
  }
}

proc wots::command {} {
  variable game
  upvar data data text text channelId channelId guildId guildId userId userId
  
  set banned [wotsdb eval {SELECT value FROM config WHERE param = 'bannedUsers'}]
  set disabledG [wotsdb eval {SELECT value FROM config WHERE param = 'disabledGuilds'}]
  set disabledC [wotsdb eval {SELECT value FROM config WHERE param = 'disabledChans'}]
  if {$userId in $banned} {
    ::meta::putdc [dict create content "You are not allowed to begin a game of War of the Seas."] 0
    return 0
  } elseif {($guildId != "" && $guildId in $disabledG) || $channelId in $disabledC} {
    if {[lindex $text 0] != "!wotsset" } {return 0}
  }
  
  switch [lindex $text 0] {
    "!host" {
      if {![::meta::hasPerm [dict get [set ${::session}::self] id] {MANAGE_CHANNELS}]} {
        set msg "Sorry, I don't have the permissions on this server to manage channels. I cannot create a game of Wars of the Seas."
        ::meta::putdc [dict create content $msg] 0
        return
      }
      create_game $userId $guildId
    }
    "!start" {check_game $guildId $channelId $userId}
    "!in" -
    "!join" {join_game $guildId $channelId $userId}
    "!out" -
    "!drop" {drop_player $guildId $channelId $userId}
    
    "!wotsset" {
      if {![hasPerm $userId {ADMINISTRATOR MANAGE_GUILD}]} {return}
      settings $guildId $channelId $userId {*}[regsub {!wotsset } $text ""]

    }
    
    "!pause" {}
    "!resume" {}
    
    "!cancel" -
    "!abort" -
    "!stop" {
      stop_game $guildId $channelId $userId
    }
    default {
      if {[llength $game(listeners)] > 0} {
        for {set i 0} {$i < [llength $game(listeners)]} {incr i} {
          set cmd [lindex $game(listeners) $i]
          if {$userId == [dict get $cmd id] &&
              [string toupper $text] in [dict get $cmd word]} {
            set game(listeners) [lreplace $game(listeners) $i $i]
            {*}[dict get $cmd cmd] $text
            incr i -1
            incr ::listener -1
          }
        }
      } else {
        return 0
      }
    }
  }
  return 1
}

proc wots::create_game {userId guildId} {
  variable game
  
  if {$guildId in [dict keys $game(sessions)]} {
    ::meta::putdc [dict create content "A game of War of the Seas is already running!"] 0
    return
  }
  
  set channels [dict get [set ${::session}::guilds] $guildId channels]
  set catExists 0
  set chanExists 0
  set parentId ""
  
  lassign [wotsdb eval {
    SELECT category, channel FROM preferences WHERE guildId = :guildId LIMIT 1
  }] categoryname channelname
  
  if {$categoryname eq ""} {
    set categoryname "Games"
  }
  if {$channelname eq ""} {
    set channelname "waroftheseas-spectator"
  }
  
  foreach channel $channels {
    if {[string equal -nocase [dict get $channel name] $categoryname] &&
        [dict get $channel type] == 4} {
      set parentId [dict get $channel id]
      set catExists 1
    }
    if {[string equal -nocase [dict get $channel name] $channelname] &&
        [dict get $channel type] == 0} {
      set channelId [dict get $channel id]
      set chanData $channel
      set chanExists 1
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
    set topic "Spectator room for War of the Seas game"
    if {
      [catch {
        discord createChannel $::session $guildId $channelname \
          [dict create type 0 topic $topic parent_id $parentId] 1
        } resCoro]
    } {
      return
    }
    if {$resCoro eq {}} {return}
    yield $resCoro
    set response [$resCoro]
    set data [lindex $response 0]
    set channelId [dict get $data id]
  } else {
    if {[dict exists $chanData parent_id] && $parentId != [dict get $chanData parent_id]} {
      set parentId [dict get $chanData parent_id]
    }
  }
  
  set afterId [after $game(jointimeout) [list coroutine ::wots::check_game[::id] ::wots::check_game $guildId $channelId $userId]]
  # Game modes
  # 1 - Awaiting players
  # 2 - Setting up channels
  # 3 - Awaiting moves
  dict set game(sessions) $guildId [dict create mode 1 chan $channelId players \
    [list [dict create player $userId chan {} hand {} host 1]] pile [list] \
    parent $parentId after $afterId playerlist [list $userId] current "" \
    target "" \
  ]

  set msg "<@$userId> is hosting a game of War of the Seas. Type `!join` to join the game, you have [expr {$game(jointimeout)/1000}] seconds to join. Up to 3 additional players can join the game."
  ::meta::putdc [dict create content $msg] 0 $channelId
}

proc wots::join_game {guildId channelId userId} {
  variable game
  
  # No game running on this guild or wrong channel
  if {$guildId ni [dict keys $game(sessions)]} {
    return
  } elseif {[dict get $game(sessions) $guildId chan] != $channelId} {
    return
  } elseif {$userId in [dict get $game(sessions) $guildId playerlist]} {
    set msg "You have already joined the game!"
    ::meta::putdc [dict create content $msg] 0 $channelId
    return
  }
  
  # Game is not running or is underway
  switch [dict get $game(sessions) $guildId mode] {
    0 {
      # Should not get here, but for now, leaving it
    }
    1 {
      set cplayers [dict get $game(sessions) $guildId players]
      lappend cplayers [dict create player $userId chan {} hand {} host 0]
      dict set game(sessions) $guildId players $cplayers
      
      set playerlist [dict get $game(sessions) $guildId playerlist]
      lappend playerlist $userId
      dict set game(sessions) $guildId playerlist $playerlist
      
      ::meta::putdc [dict create content "<@$userId> joined the game!"] 0
      if {[llength $cplayers] == 4} {
        start_game $guildId $channelId [dict get [lindex $cplayers 0] player]
      }
    }
    default {
      set msg "You cannot join the current game of War of the Seas anymore. Please wait until the game is over and host or join the next one."
      ::meta::putdc [dict create content $msg] 0 $channelId
    }
  }
}

proc wots::drop_player {guildId channelId userId {target ""} {silent 0}} {
  variable game
  
  # No game running on this guild or wrong channel
  if {$guildId ni [dict keys $game(sessions)]} {
    return
  } elseif {[dict get $game(sessions) $guildId chan] != $channelId} {
    return
  } elseif {$userId ni [dict get $game(sessions) $guildId playerlist]} {
    return
  }
  
  if {[regexp {^<@!?([0-9]+)>$} $target - user]} {
    set targetId $user
  } elseif {$target == ""} {
    set targetId $userId
  } else {
    set members [dict get [set ${::session}::guilds] $guildId members]
    set data [lsearch -inline -nocase $members "*$target*"]
    if {$data == ""} {
      ::meta::putdc [dict create content "No such user found."] 0
      return
    } else {
      set targetId [dict get $data user id]
    }
  }
  
  if {$targetId ni [dict get $game(sessions) $guildId playerlist]} {
    ::meta::putdc [dict create content "$target is not currently in a game of War of the Seas."] 0
    return
  }
  
  switch [dict get $game(sessions) $guildId mode] {
    0 {
      # Should not get here, but for now, leaving it
    }
    1 {
      set cmd [list ::wots::kill_player $guildId $channelId $targetId 0]
      lappend game(listeners) [dict create id $userId cmd $cmd word {Y N}]
      if {$userId == $targetId} {
        set msg "Are you sure you want to quit the current game? (Y/N)"
      } else {
        set msg "Are you sure you want to remove <@$targetId> from the current game? (Y/N)"
      }
      ::meta::putdc [dict create content $msg] 0 $channelId
    }
    2 -
    3 {
      set cmd [list ::wots::kill_player $guildId $channelId $targetId 0]
      lappend game(listeners) [dict create id $userId cmd $cmd word {Y N}]
      # To add warning here when it's decided what should happen if someone gets dropped
      if {$userId == $targetId} {
        set msg "Are you sure you want to quit the current game? (Y/N)"
      } else {
        set msg "Are you sure you want to remove <@$targetId> from the current game? (Y/N)"
      }
      incr ::listener
      ::meta::putdc [dict create content $msg] 0 $channelId
    }
    default {
      set msg "Something wrong happened here..."
      ::meta::putdc [dict create content $msg] 0 $channelId
    }
  }
}

proc wots::check_game {guildId channelId userId} {
  variable game
  
  set cplayers [dict get $game(sessions) $guildId playerlist]
  if {[llength $cplayers] < 2} {
    stop_game $guildId $channelId $userId 1
  } else {
    if {[dict get $game(sessions) $guildId mode] == 1} {
      start_game $guildId $channelId $userId
    }
  }
}

proc wots::start_game {guildId channelId userId} {
  variable game
  
  if {$guildId ni [dict keys $game(sessions)]} {
    return
  } elseif {$channelId != [dict get $game(sessions) $guildId chan]} {
    return
  }
  
  set players [dict get $game(sessions) $guildId players]
  
  if {$userId != [dict get [lindex $players 0] player]} {
    return
  }
  
  set afterId [dict get $game(sessions) $guildId after]
  catch {after cancel $afterId}
  
  if {[llength $players] < 2} {
    kill_game $guildId $channelId $userId 1 "Y"
    return
  }
  
  dict set game(sessions) $guildId mode 2
  
  set parentId [dict get $game(sessions) $guildId parent]
  
  if {[catch {discord getRoles $::session $guildId 1} resCoro]} {
    return
  }
  if {$resCoro eq {}} {return}
  yield $resCoro
  set response [$resCoro]
  set roles [lindex $response 0]
  set permissions [list]
  set view_channel_bit [dict get $::discord::PermissionValues VIEW_CHANNEL]
  foreach role $roles {
    set roleId [dict get $role id]
    lappend permissions [dict create id $roleId type "role" allow 0 \
      deny [expr {$view_channel_bit}]]
  }
  set channel_perms [::discord::setPermissions 0 {
    VIEW_CHANNEL SEND_MESSAGES READ_MESSAGE_HISTORY
  }]
  lappend permissions [dict create id [dict get [set ${::session}::self] id] \
    type "member" allow $channel_perms deny 0]
  
  set admins 0
  foreach player $players {
    if {[::meta::hasPerm $userId ADMINISTRATOR]} {
      set admins 1
      break
    }
  }
  
  # Set up private channels
  for {set i 0} {$i < [llength $players]} {incr i} {
    set player [lindex $players $i]
    set playerId [dict get $player player]
    set topic $game(help)
    
    if {$admins} {
      set channelId "DM"
    } else {
      if {[catch {dict get [set ${::session}::users] $playerId nick $guildId} nick]} {
        set channame [dict get [set ${::session}::users] $playerId username]
      } else {
        if {$nick eq ""} {
          set channame [dict get [set ${::session}::users] $playerId username]
        } else {
          set channame $nick
        }
      }
      
      set playerPerms [list {*}$permissions [dict create id $playerId z
        type "member" allow $channel_perms deny 0]]
      
      set data [dict create type 0 topic $topic permission_overwrites $playerPerms]
      if {$parentId != ""} {
        dict set data parent_id $parentId
      }
      if {
        [catch {discord createChannel $::session $guildId $channame $data 1} resCoro]
      } {
        return
      }
      if {$resCoro eq {}} {return}
      yield $resCoro
      set response [$resCoro]
      set data [lindex $response 0]
      set channelId [dict get $data id]
    }
    
    dict set player chan $channelId
    lset players $i $player
  }
  
  set pile [::meta::shuffle $game(deck)]
  
  # Deal cards
  for {set i 0} {$i < [llength $players]} {incr i} {
    set player [lindex $players $i]
    set hand [lrange $pile 0 6]
    set pile [lreplace $pile 0 6]
    dict set player hand $hand
    set msg "Welcome to a game of War of the Seas. Here is your hand:"
    set hand [lmap card $hand {set card "`$card`"}]
    set channelId [dict get $player chan]
    if {$channelId eq "DM"} {
      ::meta::putdcPM [dict get $player player] [dict create content "$msg\n[join $hand {, }]"] 0
    } else {
      ::meta::putdc [dict create content "$msg\n[join $hand {, }]"] 0 $channelId
    }
    lset players $i $player
  }
  dict set game(sessions) $guildId players $players
  dict set game(sessions) $guildId pile $pile
  dict set game(sessions) $guildId mode 3
  set current [expr {int(rand()*[llength $players])}]
  dict set game(sessions) $guildId current $current
  set playerId [dict get [lindex $players $current] player]
  set msg "The attacker for this turn will be <@$playerId>!"
  announce $guildId $msg
  
  select_target $guildId
}

proc wots::stop_game {guildId channelId userId {silent 0}} {
  variable game
  
  # No game running on this guild or wrong channel
  if {$guildId ni [dict keys $game(sessions)]} {
    return
  } elseif {[dict get $game(sessions) $guildId chan] != $channelId} {
    return
  }
  
  set players [dict get $game(sessions) $guildId players]
  
  if {$userId != [dict get [lindex $players 0] player]} {
    set presences [dict get [set ${::session}::guilds] $guildId presences]
    set idx [lsearch $presences "*$userId*"]
    if {$idx != -1 && [dict get [lindex $presences $idx] status] ne "offline"} {
      ::meta::putdc [dict create content "Only the game host can stop an ongoing game of War of the Seas unless the game host is offline."] 0 $channelId
      return
    } elseif {$userId ni [dict get $game(sessions) $guildId playerlist]} {
      return
    }
  }
  
  switch [dict get $game(sessions) $guildId mode] {
    0 {
      # Should not get here, but for now, leaving it
    }
    1 -
    2 -
    3 {
      if {$silent} {
        ::wots::kill_game $guildId $channelId $userId 1 "Y"
      } else {
        set cmd [list ::wots::kill_game $guildId $channelId $userId 0]
        lappend game(listeners) [dict create id $userId cmd $cmd word {Y N}]
        set msg "Are you sure you want to stop the current game? (Y/N)"
        incr ::listener
        ::meta::putdc [dict create content $msg] 0 $channelId
      }
    }
    default {
      set msg "No game is currently running."
      ::meta::putdc [dict create content $msg] 0 $channelId
    }
  }
}

proc wots::kill_game {guildId channelId userId {auto 0} {arg "N"}} {
  variable game
  
  if {$arg eq "Y" && [dict exists $game(sessions) $guildId]} {
    set afterId [dict get $game(sessions) $guildId after]
    catch {after cancel $afterId}
    
    set players [dict get $game(sessions) $guildId players]
    
    foreach player $players {
      set chan [dict get $player chan]
      if {$chan != "" && $chan != "DM"} {
        catch {discord deleteChannel $::session $chan}
      }
    }
    
    dict unset game(sessions) $guildId
    if {$auto} {
      set msg "No players joined the game. The game was aborted."
    } else {
      set msg "The current game has been aborted by <@$userId>."
    }
    ::meta::putdc [dict create content $msg] 0 $channelId
    
    # Remove listeners if any
  }
}

proc wots::kill_player {guildId channelId userId {auto 0} {arg "N"}} {
  variable game
  
  if {$arg eq "Y" && [dict exists $game(sessions) $guildId]} {
    set players [dict get $game(sessions) $guildId players]
    set playerlist [dict get $game(sessions) $guildId playerlist]
    set found 0
    
    for {set i 0} {$i < [llength $players]} {incr i} {
      set player [lindex $players $i]
      if {[dict get $player player] == $userId} {
        set playerchan [dict get $player chan]
        if {$playerchan != ""} {
          catch {discord deleteChannel $::session $playerchan}
        }
        set players [lreplace $players $i $i]
        set playerlist [lreplace $playerlist $i $i]
        incr found
        break
      }
    }
    
    if {$found == 0} {return}
    
    # To resume game properly e.g. if removed player was current player
    dict set game(sessions) $guildId players $players
    dict set game(sessions) $guildId playerlist $playerlist
    if {$auto} {
      set msg "<@$userId> was removed from the game due to inactivity."
    } else {
      set msg "<@$userId> was removed from the game."
    }
    ::meta::putdc [dict create content $msg] 0 $channelId
    
    # Remove listeners if any for this specific player
  }
}

proc wots::announce {guildId msg} {
  variable game
  ::meta::putdc [dict create content $msg] 0 [dict get $game(sessions) $guildId chan]
  foreach player [dict get $game(sessions) $guildId players] {
    set fMsg [string totitle [regsub -all -- "<@[dict get $player player]>" $msg "you"]]
    if {[dict get $player chan] == "DM"} {
      ::meta::putdcPM [dict get $player player] [dict create content $fMsg] 0
    } else {
      ::meta::putdc [dict create content $fMsg] 0 [dict get $player chan]
    }
  }
}

proc wots::select_target {guildId} {
  variable game
  
  set players [dict get $game(sessions) $guildId players]
  set current [dict get $game(sessions) $guildId current]
  
  set playerData [lindex $players $current]
  set playerId [dict get $playerData player]
  
  set num 1
  set selection [list]
  set targets [list]
  set options [list]
  foreach player $players {
    set id [dict get $player player]
    if {$id == $playerId} {continue}
    set name [dict get [set ${::session}::users] $id username]
    set discriminator [dict get [set ${::session}::users] $id discriminator]
    if {[catch {dict get [set ${::session}::users] $id nick $guildId} nick]} {
      set nick ""
    }
    if {$nick == ""} {
      lappend selection "$num. $name#$discriminator"
    } else {
      lappend selection "$num. $name#$discriminator AKA $nick"
    }
    lappend targets $id
    lappend options $num
    incr num
  }
  
  set cmd [list ::wots::target $guildId $playerId $targets]
  set num 0
  lappend game(listeners) [dict create id $playerId cmd $cmd \
    word $options]
  set msg "Select the target you want to battle against (type a number):\n```[join $selection \n]```"
  set chan [dict get $playerData chan]
  if {$chan == "DM"} {
    ::meta::putdcPM $playerId [dict create content $msg] 0
  } else {
    ::meta::putdc [dict create content $msg] 0 $chan
  }
  incr ::listener
}

proc wots::target {guildId userId targets select} {
  variable game
  
  set targetId [lindex $targets $select-1]
  dict set $game(sessions) $guildId target $targetId
  set msg "<@$userId> has picked <@$targetId> as target!"
  announce $guildId $msg
  
  set current [dict get $game(sessions) $guildId current]
  set playerData [lindex [dict get $game(sessions) $guildId players] $current]
  
  set num 1
  set selection [list]
  foreach card [dict get $playerData hand] {
    lappend selection "$num. $card"
    incr num
  }
  
  set cmd [list ::wots::play $guildId $userId]
  set num 0
  lappend game(listeners) [dict create id $userId cmd $cmd \
    word [list {*}[lmap i [dict get $playerData hand] {incr num}]]]
  set msg "Select the card you want to play:\n```[join $selection \n]```"
  set chan [dict get $playerData chan]
  if {$chan == "DM"} {
    ::meta::putdcPM $userId [dict create content $msg] 0
  } else {
    ::meta::putdc [dict create content $msg] 0 $chan
  }
  incr ::listener
}

proc wots::play {guildId userId select} {
  variable game
  
  
}


##
# Moderation
##
proc wots::settings {guildId channelId userId args} {
  for {set i 0} {$i < [llength $args]} {incr i} {
    set setting [lindex $args $i]
    set msg "Unable to change the setting $setting; value provided is not recognised as being either true or false."
    switch $setting {
      guild {
        set value [lindex $setting [incr i]]
        if {[string is true -strict $value]} {
          enable_guild $guildId $channelId $userId
        } elseif {[string is false -strict $value]} {
          disable_guild $guildId $channelId $userId
        } else {
          ::meta::putdc [dict create content $msg] 0
        }
      }
      channel {
        set value [lindex $setting [incr i]]
        set channels [lindex $setting [incr i]]
        if {[string is true -strict $value]} {
          enable_channel $guildId $channelId $userId $channels
        } elseif {[string is false -strict $value]} {
          disable_channel $guildId $channelId $userId $channels
        } else {
          ::meta::putdc [dict create content $msg] 0
        }
      }
      ban {
        set value [lindex $setting [incr i]]
        set users [lindex $setting [incr i]]
        if {[string is true -strict $value]} {
          ban_user $guildId $channelId $userId $users
        } elseif {[string is false -strict $value]} {
          unban_user $guildId $channelId $userId $users
        } else {
          ::meta::putdc [dict create content $msg] 0
        }
      }
      category {
        set value [lindex $setting [incr i]]
        default_category $guildId $channelId $userId $value
      }
      channel {
        set value [lindex $setting [incr i]]
        default_channel $guildId $channelId $userId $value
      }
    }
  }
}

proc wots::ban_user {guildId channelId userId targets} {
  set banned [list]
  foreach target $targets {
    if {[regexp {^<@!?([0-9]+)>$} $target - user]} {
      set targetId $user
    } elseif {$target == ""} {
      ::meta::putdc [dict create content "Error: User to ban was not mentioned."] 0
      return
    } else {
      set members [dict get [set ${::session}::guilds] $guildId members]
      set data [lsearch -inline -nocase $members "*$target*"]
      if {$data == ""} {
        ::meta::putdc [dict create content "No such user found."] 0
        return
      } else {
        set targetId [dict get $data user id]
      }
    }
    
    set banned [wotsdb eval {SELECT value FROM config WHERE param = 'bannedUsers'}]
    if {$targetId in $banned} {
      ::meta::putdc [dict create content "<@$targetId> is already banned from War of the Seas."] 0
    } else {
      lappend banned $targetId
      wotsdb eval {UPDATE config SET value = :banned WHERE param = 'bannedUsers'}
      lappend banned "<@$targetId>"
      kill_player $guildId $channelId $userId 0 "Y"
    }
  }
  if {[llength $banned] == 1} {
    ::meta::putdc [dict create content "[join banned] has been banned from War of the Seas."] 0
  } elseif {[llength $banned] > 1} {
    ::meta::putdc [dict create content "[join banned {, }] have been banned from War of the Seas."] 0
  }
}

proc wots::unban_user {guildId channelId userId targets} {
  set unbanned [list]
  foreach target $targets {
    if {[regexp {^<@!?([0-9]+)>$} $target - user]} {
      set targetId $user
    } elseif {$target == ""} {
      ::meta::putdc [dict create content "Error: User to ban was not mentioned."] 0
      return
    } else {
      set members [dict get [set ${::session}::guilds] $guildId members]
      set data [lsearch -inline -nocase $members "*$target*"]
      if {$data == ""} {
        ::meta::putdc [dict create content "No such user found."] 0
        return
      } else {
        set targetId [dict get $data user id]
      }
    }
    
    set banned [wotsdb eval {SELECT value FROM config WHERE param = 'bannedUsers'}]
    set idx [lsearch $banned $targetId]
    if {$idx == -1} {
      ::meta::putdc [dict create content "<@$targetId> is not banned."] 0
    } else {
      set banned [lreplace $banned $idx $idx]
      wotsdb eval {UPDATE config SET value = :banned WHERE param = 'bannedUsers'}
      lappend unbanned "<@$targetId>"
    }
  }
  if {[llength $unbanned] == 1} {
    ::meta::putdc [dict create content "[join unbanned] has been unbanned from War of the Seas."] 0
  } elseif {[llength $banned] > 1} {
    ::meta::putdc [dict create content "[join unbanned {, }] have been unbanned from War of the Seas."] 0
  }
}

proc wots::disableguild {guildId channelId userId} {
  set guilds [wotsdb eval {SELECT value FROM config WHERE param = 'disabledGuilds'}]
  lappend guilds $guildId
  wotsdb eval {UPDATE config SET value = :guilds WHERE param = 'disabledGuilds'}
  
  ::meta::putdc [dict create content "War of the Seas has been disabled on this server."] 0
  kill_game $guildId $channelId $userId 0 "Y"
}

proc wots::enableguild {guildId channelId userId} {
  set guilds [wotsdb eval {SELECT value FROM config WHERE param = 'disabledGuilds'}]
  set idx [lsearch $guilds $guildId]
  if {$idx == -1} {
    ::meta::putdc [dict create content "War of the Seas is already enabled on this server."] 0
  } else {
    set guilds [lreplace $guilds $idx $idx]
    wotsdb eval {UPDATE config SET value = :guilds WHERE param = 'disabledGuilds'}
    ::meta::putdc [dict create content "War of the Seas has been enabled on this server."] 0
  }
}

proc wots::disablechannel {guildId channelId userId {others ""}} {
  set chans [wotsdb eval {SELECT value FROM config WHERE param = 'disabledChans'}]
  if {$others == ""} {
    lappend chans $channelId
    wotsdb eval {UPDATE config SET value = :chans WHERE param = 'disabledChans'}
    ::meta::putdc [dict create content "War of the Seas has been disabled on this channel."] 0
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
    wotsdb eval {UPDATE config SET value = :chans WHERE param = 'disabledChans'}
    set parts [list]
    if {$done != ""} {
      lappend parts "War of the Seas has been disabled on the following channel(s): [join $done {, }]"
    }
    if {$skip != ""} {
      lappend parts "The following channels already have War of the Seas disabled: [join $skip {, }]"
    }
    ::meta::putdc [dict create content [join $parts "\n"]] 0
  }
}

proc wots::enablechannel {guildId channelId userId {others ""}} {
  set chans [wotsdb eval {SELECT value FROM config WHERE param = 'disabledChans'}]
  if {$others == ""} {
    set idx [lsearch $chans $channelId]
    if {$idx == -1} {
      ::meta::putdc [dict create content "War of the Seas is already enabled on this channel."] 0
    } else {
      set chans [lreplace $chans $idx $idx]
      wotsdb eval {UPDATE config SET value = :chans WHERE param = 'disabledChans'}
      ::meta::putdc [dict create content "War of the Seas has been enabled on this channel."] 0
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
    wotsdb eval {UPDATE config SET value = :chans WHERE param = 'disabledChans'}
    set parts [list]
    if {$done != ""} {
      lappend parts "War of the Seas has been enabled on the following channel(s): [join $done {, }]"
    }
    if {$skip != ""} {
      lappend parts "The following channels already have War of the Seas enabled: [join $skip {, }]"
    }
    ::meta::putdc [dict create content [join $parts "\n"]] 0
  }
}

proc wots::default_category {guildId channelId userId category} {
  set cDefault [wotsdb eval {SELECT category FROM preferences WHERE guildId = :guildId}]
  set newcategory [::meta::channame_clean $category]
  
  if {$cDefault == ""} {
    wotsdb eval {INSERT INTO preferences VALUES (:guildId, :newcategory, '')}
  } elseif {$cDefault ne $newcategory} {
    wotsdb eval {UPDATE preferences SET category = :newcategory WHERE guildId = :guildId}
  } else {
    if {$newcategory ne $category} {
      ::meta::putdc [dict create content "The default category name is already set to $category (after applying Discord's category name restrictions of only lowercase alphanumeric characters, underscores and dashes allowed)."] 0
    } else {
      ::meta::putdc [dict create content "The default category name is already set to $category."] 0
    }
    return
  }
  set msg "Default category name for War of the Seas successfully set!"
  if {$newcategory ne $category} {
    append msg " Some changes were necessary due to Discord's restriction on category names (only lowercase alphanumeric characters, underscores and dashes allowed), however. The new category name is $newcategory"
  }
  ::meta::putdc [dict create content $msg] 0
}

proc wots::default_channel {guildId channelId userId channel} {
  set cDefault [wotsdb eval {SELECT channel FROM preferences WHERE guildId = :guildId}]
  set newchannel [::meta::channame_clean $channel]
  
  if {$cDefault == ""} {
    wotsdb eval {INSERT INTO preferences VALUES (:guildId, '', :newchannel)}
  } elseif {$cDefault ne $newchannel} {
    wotsdb eval {UPDATE preferences SET channel = :newchannel WHERE guildId = :guildId}
  } else {
    if {$newchannel ne $channel} {
      ::meta::putdc [dict create content "The default channel name is already set to $channel (after applying Discord's channel name restrictions of only lowercase alphanumeric characters, underscores and dashes allowed)."] 0
    } else {
      ::meta::putdc [dict create content "The default channel name is already set to $channel."] 0
    }
    return
  }
  set msg "Default channel name for War of the Seas successfully set!"
  if {$newchannel ne $channel} {
    append msg " Some changes were necessary due to Discord's restriction on channel names (only lowercase alphanumeric characters, underscores and dashes allowed), however. The new channel name is $newchannel"
  }
  ::meta::putdc [dict create content $msg] 0
}

puts "WarOfTheSeas.tcl v0.1 loaded"
