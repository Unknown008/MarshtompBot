namespace eval wots {
  variable game
  
  sqlite3 wotsdb "${scriptDir}/wotsdb.sqlite3"
  
  # Game Sessions
  set game(sessions)     [list]
  # Help
  set game(help)         ""
  set game(listeners)    [list]
  set game(deck)         [list]
  set game(defaultChan)  "waroftheseas-spectator"
  set game(defaultCat)   "games"
  
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
      ('playwarning', '240000'),
      ('playtimeout', '300000')
    }
    set game(jointimeout) 120000
    set game(playwarning) 240000
    set game(playtimeout) 300000
  } else {
    set game(jointimeout) [wotsdb eval {SELECT value FROM config WHERE param = 'jointimeout'}]
    set game(playwarning) [wotsdb eval {SELECT value FROM config WHERE param = 'playwarning'}]
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
        set cListeners $game(listeners)
        for {set i 0} {$i < [llength $cListeners]} {incr i} {
          set cmd [lindex $cListeners $i]
          if {$userId == [dict get $cmd id] &&
              [string toupper $text] in [dict get $cmd word]} {
            set game(listeners) [lreplace $game(listeners) $i $i]
            set cListeners [lreplace $cListeners $i $i]
            {*}[dict get $cmd cmd] $text
            incr i -1
            incr ::listener -1
          }
        }
        return 1
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
    set categoryname $game(defaultCat)
  }
  if {$channelname eq ""} {
    set channelname $game(defaultChan)
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
  
  set afterId [after $game(jointimeout) [list coroutine \
    ::wots::check_game[::id] ::wots::check_game $guildId $channelId $userId]]
  # Game modes
  #  1 - Awaiting players
  #  2 - Setting up channels
  #  3 - Awaiting moves
  #  4 - Defender ability
  #  5 - Attacker ability
  #  6 - Defender recon call
  #  7 - Attacker recon call
  #  8 - Battle resolve
  #  9 - Winner draw
  # 10 - Pick new attacker
  
  dict set game(sessions) $guildId [dict create mode 1 chan $channelId players \
    [list [dict create player $userId chan {} hand {} inplay {} host 1]] \
    pile [list] parent $parentId after $afterId playerlist [list $userId] \
    currentIdx "" targetId "" responses "" activated ""\
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
      lappend cplayers [dict create player $userId chan {} hand {} inplay {} host 0]
      dict set game(sessions) $guildId players $cplayers
      
      set playerlist [dict get $game(sessions) $guildId playerlist]
      lappend playerlist $userId
      dict set game(sessions) $guildId playerlist $playerlist
      
      ::meta::putdc [dict create content "<@$userId> joins the game!"] 0
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
  
  set admins 0
  foreach player $players {
    if {[::meta::hasPerm [dict get $player player] {ADMINISTRATOR MANAGE_GUILD}]} {
      set admins 1
      break
    }
  }
  
  if {!$admins} {
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
      
      set playerPerms [list {*}$permissions [dict create id $playerId \
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
    private_say $channelId [dict get $player player] "$msg\n[join $hand {, }]"
    lset players $i $player
  }
  dict set game(sessions) $guildId players $players
  dict set game(sessions) $guildId pile $pile
  dict set game(sessions) $guildId mode 3
  set current [expr {int(rand()*[llength $players])}]
  dict set game(sessions) $guildId currentIdx $current
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

proc wots::kill_game {guildId channelId userId {auto 0} {arg "N"}} {
  variable game
  
  if {$arg eq "Y" && [dict exists $game(sessions) $guildId]} {
    set afterId [dict get $game(sessions) $guildId after]
    catch {after cancel $afterId}
    
    set mode [dict get $game(sessions) $guildId mode]
    set players [dict get $game(sessions) $guildId players]
    if {$mode == 1} {
      if {$auto == 1} {
        set msg "No players joined the game. The game was aborted."
      } elseif {$auto == 0} {
        set msg "The current game has been aborted by <@$userId>."
      }
    } elseif {$mode > 1} {
      if {$auto == 1} {
        set msg "The game has been aborted: insufficient players to continue the game."
      } elseif {$auto == 0} {
        set msg "The current game has been aborted by <@$userId>."
      }
      
      foreach player $players {
        set chan [dict get $player chan]
        if {$chan != "" && $chan != "DM"} {
          catch {discord deleteChannel $::session $chan}
        }
        remove_timers $guildId [dict get $player player]
      }
    }
    
    foreach player $players {
      set playerId [dict get $player player]
      for {set i 0} {$i < [llength $game(listeners)]} {incr i} {
        set cmd [lindex $game(listeners) $i]
        if {$playerId == [dict get $cmd id]} {
          set game(listeners) [lreplace $game(listeners) $i $i]
          incr i -1
          incr ::listener -1
        }
      }
    }
    
    # If we are keeping scores, calculate here
    
    announce $guildId $msg
    dict unset game(sessions) $guildId
  }
}

proc wots::kill_player {guildId channelId userId {auto 0} {arg "N"}} {
  variable game
  
  if {$arg eq "Y" && [dict exists $game(sessions) $guildId]} {
    set players [dict get $game(sessions) $guildId players]
    set playerlist [dict get $game(sessions) $guildId playerlist]
    set found 0
    set host ""
    for {set i 0} {$i < [llength $players]} {incr i} {
      set player [lindex $players $i]
      if {[dict get $player player] == $userId} {
        set playerchan [dict get $player chan]
        if {$playerchan != "" && $playerchan != "DM"} {
          catch {discord deleteChannel $::session $playerchan}
        }
        if {$i == 0} {
          set nextPlayerData [lindex $players $i+1]
          if {$nextPlayerData != ""} {
            dict set nextPlayerData host 1
            set nextId [dict get $nextPlayerData player]
            set players [lreplace $players $i+1 $i+1 $nextPlayerData]
            set host " <@$nextId> is the new host."
          }
        }
        
        incr found
        break
      }
    }
    
    if {$found == 0} {return}
    
    # To resume game properly e.g. if removed player was current player
    set mode [dict get $game(sessions) $guildId mode]
    
    if {$auto == 1} {
      set msg "<@$userId> has been removed from the game due to inactivity."
      if {$host != ""} {append msg $host}
      announce $guildId $msg
    } elseif {$auto == 0} {
      set msg "<@$userId> has been removed from the game."
      if {$host != ""} {append msg $host}
      announce $guildId $msg
    }
    
    set players [lreplace $players $i $i]
    set playerlist [lreplace $playerlist $i $i]
    dict set game(sessions) $guildId players $players
    dict set game(sessions) $guildId playerlist $playerlist
    
    remove_timers $guildId $userId
    
    if {$mode > 1 && [llength $players] <= 1} {
      kill_game $guildId $channelId $userId 1 "Y"
    } else {
      for {set i 0} {$i < [llength $game(listeners)]} {incr i} {
        set cmd [lindex $game(listeners) $i]
        if {$userId == [dict get $cmd id]} {
          set game(listeners) [lreplace $game(listeners) $i $i]
          incr i -1
          incr ::listener -1
        }
      }
    }
  }
}

proc wots::select_target {guildId} {
  variable game
  
  set players [dict get $game(sessions) $guildId players]
  set current [dict get $game(sessions) $guildId currentIdx]
  
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
  incr ::listener
  private_say $chan $playerId $msg
  add_timer $guildId $chan $playerId
}

proc wots::target {guildId atkId targets select} {
  variable game
  
  remove_timers $guildId $atkId
  
  set defId [lindex $targets $select-1]
  dict set game(sessions) $guildId targetId $defId
  set msg "<@$atkId> has picked <@$defId> as target!"
  announce $guildId $msg
  
  # Tell attacker cards and ask for move
  set atkIdx [dict get $game(sessions) $guildId currentIdx]
  set atkData [lindex [dict get $game(sessions) $guildId players] $atkIdx]
  
  set num 1
  set selection [list]
  foreach card [dict get $atkData hand] {
    lappend selection "$num. $card"
    incr num
  }
  
  set cmd [list ::wots::play $guildId $atkId]
  set num 0
  lappend game(listeners) [dict create id $atkId cmd $cmd \
    word [list {*}[lmap i [dict get $atkData hand] {incr num}]]]
  set atkMsg "Select the card you want to play:\n```[join $selection \n]```"

  
  # Tell defender cards and ask for move
  set defData [lindex [dict get $game(sessions) $guildId players] \
    [lsearch [dict get $game(sessions) $guildId playerlist] $defId]]
  
  set num 1
  set selection [list]
  foreach card [dict get $defData hand] {
    lappend selection "$num. $card"
    incr num
  }
  
  set cmd [list ::wots::play $guildId $defId]
  set num 0
  lappend game(listeners) [dict create id $defId cmd $cmd \
    word [list {*}[lmap i [dict get $defData hand] {incr num}]]]
  set defMsg "Select the card you want to play:\n```[join $selection \n]```"
  
  # Post messages
  private_say [dict get $atkData chan] $atkId $atkMsg
  private_say [dict get $defData chan] $defId $defMsg
  incr ::listener 2
  
  add_timer $guildId [dict get $atkData chan] $atkId
  add_timer $guildId [dict get $defData chan] $defId
}

proc wots::play {guildId userId select} {
  variable game
  
  remove_timers $guildId $userId
  
  set players [dict get $game(sessions) $guildId players]
  for {set i 0} {$i < [llength $players]} {incr i} {
    set player [lindex $players $i]
    if {[dict get $player player] == $userId} {
      set hand [dict get $player hand]
      set card [lindex $hand $select-1]
      set hand [lreplace $hand $select-1 $select-1]
      dict set player hand $hand
      set inplay [dict get $player inplay]
      lappend inplay $card
      dict set player inplay $inplay
      set players [lreplace $players $i $i $player]
      break
    }
  }
  dict set game(sessions) $guildId players $players
  
  announce $guildId "<@$userId> has set $card!"
  
  if {[dict get $game(sessions) $guildId responses] != ""} {return}
  
  dict set game(sessions) $guildId mode 4
  
  set defId [dict get $game(sessions) $guildId targetId]
  foreach player [dict get $game(sessions) $guildId players] {
    if {[dict get $player player] == $defId} {
      set defData $player
      break
    }
  }
  set atkIdx [dict get $game(sessions) $guildId currentIdx]
  set atkData [lindex [dict get $game(sessions) $guildId players] $atkIdx]
  set atkId [dict get $atkData player]
  battle $guildId $atkId $atkData $defId $defData
}

proc wots::battle {guildId userId userData callerId callerData} {
  variable game
  set mode [dict get $game(sessions) $guildId mode]
  switch $mode {
    4 { ;# Defender ability
      dict set game(sessions) $guildId mode [incr mode]
      use_ability $guildId $callerId $callerData $userId $userData
    }
    5 { ;# Attacker ability
      dict set game(sessions) $guildId mode [incr mode]
      use_ability $guildId $userId $userData $callerId $callerData
    }
    6 { ;# Defender recon call
      dict set game(sessions) $guildId mode [incr mode]
      #recon_call $guildId
    }
    7 { ;# Attacker recon call
      dict set game(sessions) $guildId mode [incr mode]
    }
    8 { ;# Battle resolve
      dict set game(sessions) $guildId mode [incr mode]
    }
    9 { ;# Winner draw
      dict set game(sessions) $guildId mode [incr mode]
    }
    10 { ;# Pick new attacker
      dict set game(sessions) $guildId mode [incr mode]
    }
  }
}

proc wots::use_ability {guildId userId userData callerId callerData} {
  variable game
  
  set inplay [dict get $userData inplay]
  set card [lindex $inplay 0]
  lassign [split $card] suit value
  if {$value < 5} {
    set cmd [list ::wots::value_call $guildId $userId $userData $callerId \
      $callerData $card]
    lappend game(listeners) [dict create id $userId cmd $cmd word {Y N}]
    incr ::listener
    private_say [dict get $userData chan] $userId \
      "Would you like to activate your card's ability? (Y/N)"
    add_timer $guildId [dict get $userData chan] $userId
  } else {
    battle $guildId $callerId $callerData $userId $userData
  }
}

proc wots::value_call {guildId userId userData callerId callerData card select} {
  variable game
  
  remove_timers $guildId $userId
  
  if {$select == "Y"} {
    announce $guildId "<@$userId> activates their card's ability!"
    set cmd [list ::wots::block_ability $guildId $callerId $callerData $userId \
      $userData $card]
    lappend game(listeners) [dict create id $callerId cmd $cmd word {Y N}]
    incr ::listener
    private_say [dict get $callerData chan] $callerId \
      "Would you like to make a value call to block your opponent's card ability? (Y/N)"
    add_timer $guildId [dict get $callerData chan] $callerId
  } else {
    battle $guildId $callerId $callerData $userId $userData
  }
}

proc wots::block_ability {guildId userId userData callerId callerData card select} {
  variable game
  
  remove_timers $guildId $userId
  
  if {$select == "Y"} {
    announce $guildId "<@$userId> raises a value call!"
    set cmd [list ::wots::guess_value $guildId $userId $userData $callerId \
      $callerData $card]
    lappend game(listeners) [dict create id $userId cmd $cmd word {1 2 3 4}]
    incr ::listener
    private_say [dict get $userData chan] $userId \
      "Please insert the value of the card (1, 2, 3 or 4)"
    add_timer $guildId [dict get $userData chan] $userId
  } else {
    activate_ability $guildId $callerId $callerData $userId $userData $card
  }
}

proc wots::guess_value {guildId userId userData targetId targetData card select} {
  variable game
  
  remove_timers $guildId $userId
  lassign $card suit value
  set msg "<@$userId> calls the value of the defender's card to be $select!"
  
  if {$select == $value} {
    append msg " The guess is right! The card ability of <@$targetId> gets blocked!"
    announce $guildId $msg
    battle $guildId $userId $userData $targetId $targetData
  } else {
    append msg " The guess is wrong! The card ability of <@$targetId> proceeds!"
    announce $guildId $msg
    activate_ability $guildId $targetId $targetData $userId $userData $card
  }
}

proc wots::activate_ability {guildId userId userData targetId targetData card} {
  variable game
  
  lassign $card suit value
  set activated [dict get $game(sessions) $guildId activated]
  lappend activated $userId
  
  switch $suit {
    "Skull" {
      set hand [dict get $targetData hand]
      set inplay [dict get $targetData inplay]
      
      if {[llength $inplay] > 1} {
        announce $guildId "<@$userId>'s Mutiny activates!"
        
        set num 1
        set selection [list]
        foreach card $inplay {
          lappend selection "$num. Card $num"
          incr num
        }
        
        set cmd [list ::wots::select_inplay $guildId $userId $userData \
          $targetId $targetData]
        set num 0
        lappend game(listeners) [dict create id $userId cmd $cmd \
          word [list {*}[lmap i $inplay {incr num}]]]
        set msg "Select a card to take:\n```[join $selection \n]```"
        private_say [dict get $userData chan] $userId $msg
        incr ::listener 1
        add_timer $guildId [dict get $userData chan] $userId
        return
      } else {
        set card [lindex $inplay 0]
        set inplay [dict get $userData inplay]
        lappend inplay $card
        dict set userData inplay $inplay
        dict set targetData inplay ""
        
        for {set i 0} {$i < [llength $players]} {incr i} {
          set player [lindex $players $i]
          if {[dict get $player player] == $targetId} {
            lset players $i $targetData
          } elseif {[dict get $player player] == $userId} {
            lset players $i $userData
          }
        }
        dict set game(sessions) $guildId players $players
        
        announce $guildId "<@$userId>'s Mutiny activates! <@$targetId>'s card goes to <@$userId>!"
        
        if {$hand == ""} {
          announce $guildId "<@$targetId> is unable to play another card! <@$targetId loses the battle!"
        } else {
          set num 1
          set selection [list]
          foreach card $hand {
            lappend selection "$num. $card"
            incr num
          }
        
          set cmd [list ::wots::play_new $guildId $targetId $targetData \
            $userId $userData 1]
          set num 0
          lappend game(listeners) [dict create id $targetId cmd $cmd \
            word [list {*}[lmap i [dict get $targetData hand] {incr num}]]]
          set msg "Select a new card to play:\n```[join $selection \n]```"
          private_say [dict get $targetData chan] $targetId $msg
          incr ::listener 1
          add_timer $guildId [dict get $targetData chan] $targetId
          return
        }
      }
    }
    "Ship" {
      set card [draw $guildId]
      if {$card == ""} {
        announce $guildId "<@$userId>'s Reinforcements activates but fails! The card pile is empty!"
      } else {
        announce $guildId "<@$userId>'s Reinforcements activates! <@$userId> draws a card!"
        
        set hand [dict get $userData hand]
        lappend hand $card
        dict set userData hand $hand
        
        set players [dict get $game(sessions) $guildId players]
        for {set i 0} {$i < [llength $players]} {incr i} {
          set player [lindex $players $i]
          if {$userId == [dict get $player player]} {
            lset players $i $userData
            break
          }
        }
        dict set game(sessions) $guildId players $players
        
        set num 1
        set selection [list]
        foreach card [dict get $userData hand] {
          lappend selection "$num. $card"
          incr num
        }
        
        set cmd [list ::wots::play_new $guildId $userId $userData \
          $targetId $targetData 0]
        set num 0
        lappend game(listeners) [dict create id $userId cmd $cmd \
          word [list {*}[lmap i [dict get $userData hand] {incr num}]]]
        set msg "Select a new card to play:\n```[join $selection \n]```"
        private_say [dict get $userData chan] $userId $msg
        incr ::listener 1
        add_timer $guildId [dict get $userData chan] $userId
        return
      }
    }
    "Sword" {
      set hand [dict get $targetData hand]
      if {[llength $hand] == 0} {
        announce $guildId "<@$userId>'s Steal activates but fails! <@$targetId> has no card in hand!"
      } else {
        set id [expr {int(rand()*[llength $hand])}]
        set card [lindex $hand $id]
        
        set inplay [dict get $userData inplay]
        lappend inplay $card
        dict set userData inplay $inplay
        
        set hand [dict get $targetData hand]
        set hand [lreplace $hand $id $id]
        dict set targetData hand $hand
        
        set players [dict get $game(sessions) $guildId players]
        for {set i 0} {$i < [llength $players]} {incr i} {
          set player [lindex $players $i]
          if {[dict get $player player] == $userId} {
            lset players $i $userData
          } elseif {[dict get $player player] == $targetId} {
            lset players $i $targetData
          }
        }
        dict set game(sessions) $guildId players $players
        announce $guildId "<@$userId>'s Steal activates and takes $card from <@$targetId>! <@$userId> plays $card!"
      }
    }
    "Coin" {
      set hand [dict get $userData hand]
      if {$hand == ""} {
        set card [draw $guildId]
        if {$card == ""} {
          announce $guildId "<@$userId>'s Trade activates but fails! The card pile is empty!"
        } else {
          announce $guildId "<@$userId>'s Trade activates! <@$userId> draws a card!"
          
          set hand [dict get $userData hand]
          lappend hand $card
          dict set userData hand $hand
          
          set players [dict get $game(sessions) $guildId players]
          for {set i 0} {$i < [llength $players]} {incr i} {
            set player [lindex $players $i]
            if {$userId == [dict get $player player]} {
              lset players $i $userData
              break
            }
          }
          dict set game(sessions) $guildId players $players
        }
      } else {
        announce $guildId "<@$userId>'s Trade activates!"
        
        set num 1
        set selection [list]
        foreach card [dict get $userData hand] {
          lappend selection "$num. $card"
          incr num
        }
        
        set cmd [list ::wots::discard $guildId $userId $userData \
          $targetId $targetData]
        set num 0
        lappend game(listeners) [dict create id $userId cmd $cmd \
          word [list {*}[lmap i [dict get $userData hand] {incr num}]]]
        set msg "Select a card to discard:\n```[join $selection \n]```"
        private_say [dict get $userData chan] $userId $msg
        incr ::listener 1
        add_timer $guildId [dict get $userData chan] $userId
        return
      }
    }
  }
  battle $guildId $targetId $targetData $userId $userData
}

proc wots::play_new {guildId userId userData targetId targetData reverse select} {
  variable game
  
  remove_timers $guildId $userId
  set players [dict get $game(sessions) $guildId players]
  
  set hand [dict get $userData hand]
  set card [lindex $hand $select-1]
  set hand [lreplace $hand $select-1 $select-1]
  dict set userData hand $hand
  set inplay [dict get $userData inplay]
  lappend inplay $card
  dict set userData inplay $inplay
  
  for {set i 0} {$i < [llength $players]} {incr i} {
    set player [lindex $players $i]
    if {[dict get $player player] == $userId} {
      lset players $i $userData
      break
    }
  }
  dict set game(sessions) $guildId players $players
  announce $guildId "<@$userId> has set $card!"
  if {$reverse} {
    battle $guildId $userId $userData $targetId $targetData
  } else {
    battle $guildId $targetId $targetData $userId $userData
  }
}

proc wots::select_inplay {guildId userId userData targetId targetData select} {
  variable game
  
  remove_timers $guildId $userId
  set players [dict get $game(sessions) $guildId players]
  
  set inplay [dict get $targetData inplay]
  set card [lindex $inplay $select-1]
  set inplay [lreplace $inplay $select-1 $select-1]
  dict set targetData inplay $inplay
  
  set inplay [dict get $userData inplay]
  lappend inplay $card
  dict set userData inplay $inplay
  
  for {set i 0} {$i < [llength $players]} {incr i} {
    set player [lindex $players $i]
    if {[dict get $player player] == $targetId} {
      lset players $i $targetData
    } elseif {[dict get $player player] == $userId} {
      lset players $i $userData
    }
  }
  dict set game(sessions) $guildId players $players
  announce $guildId "<@$userId> has stolen $card from <@$targetId>!"
  
  battle $guildId $targetId $targetData $userId $userData
}

proc wots::discard {guildId userId userData targetId targetData select} {
  variable game
  
  remove_timers $guildId $userId
  set players [dict get $game(sessions) $guildId players]
  
  set hand [dict get $userData hand]
  set card [lindex $hand $select-1]
  set hand [lreplace $hand $select-1 $select-1]
  dict set userData hand $hand
  
  for {set i 0} {$i < [llength $players]} {incr i} {
    set player [lindex $players $i]
    if {[dict get $player player] == $userId} {
      lset players $i $userData
      break
    }
  }
  dict set game(sessions) $guildId players $players
  set msg "<@$userId> has discarded $card"
  
  set card [draw $guildId]
  if {$card == ""} {
    append msg "! Unfortunately the card pile is empty!"
  } else {
    append msg " and draws a card!"
    
    set hand [dict get $userData hand]
    lappend hand $card
    dict set userData hand $hand
    
    set players [dict get $game(sessions) $guildId players]
    for {set i 0} {$i < [llength $players]} {incr i} {
      set player [lindex $players $i]
      if {$userId == [dict get $player player]} {
        lset players $i $userData
        break
      }
    }
    dict set game(sessions) $guildId players $players
  }
        
  battle $guildId $targetId $targetData $userId $userData
}

proc wots::recon_call {$guildId} {}

##
# Helpers
##
proc wots::announce {guildId msg} {
  variable game
  ::meta::putdc [dict create content [card_mask $msg]] 0 \
    [dict get $game(sessions) $guildId chan]
  foreach player [dict get $game(sessions) $guildId players] {
    private_say [dict get $player chan] [dict get $player player] $msg
  }
}

proc wots::private_say {channelId userId msg} {
  variable game
  set msg [youify $userId $msg]
  if {$channelId == "DM"} {
    ::meta::putdcPM $userId [dict create content $msg] 0
  } elseif {$channelId != ""} {
    ::meta::putdc [dict create content $msg] 0 $channelId
  }
}

proc wots::card_mask {text} {
  if {[regexp {has set \w+ \d+} $text]} {
    regsub {has set \w+ \d+} $text "has set a card" text
  }
  return $text
}

proc wots::youify {userId text} {
  set mappings {
    " was" " were"
    " has" " have"
    " is"  " are"
    " activates" " activate"
    " raises" " raise"
    " loses" " lose"
    " draws" " draw"
    " calls" " call"
    " plays" " play"
  }
  set secondary {
    "you's" "your"
    "their" "your"
    "The card ability of you" "Your card's ability"
  }
  if {[regsub -all -- "<@$userId>( \\w+)?" $text \
    [format {you[string map {%s} "\1"]} $mappings] text] > 0} {
    set text [subst $text]
    set text [string map $secondary $text]
    regsub -all -- {(^|[.!?] )you(r)?\y} $text {\1You\2} text
  } else {
    set text [card_mask $text]
  }
  return $text
}

proc wots::check_game {guildId channelId userId {warning 0}} {
  variable game
  
  set cplayers [dict get $game(sessions) $guildId playerlist]
  switch [dict get $game(sessions) $guildId mode] {
    1 {
      if {[llength $cplayers] < 2} {
        stop_game $guildId $channelId $userId 1
      } else {
        if {[dict get $game(sessions) $guildId mode] == 1} {
          start_game $guildId $channelId $userId
        }
      }
    }
    default {
      if {$warning} {
        private_say $channelId $userId \
          "Warning: You have [expr {($game(playtimeout)-$game(playwarning))/1000}] more seconds to make your selection before you time out."
      } else {
        kill_player $guildId $channelId $userId 1 "Y"
      }
    }
  } 
}

proc wots::add_timer {guildId channelId userId} {
  variable game
  set responses [dict get $game(sessions) $guildId responses]
  set id1 [after $game(playwarning) [list ::wots::check_game $guildId $channelId $userId 1]]
  set id2 [after $game(playtimeout) [list ::wots::check_game $guildId $channelId $userId 0]]
  dict set responses $userId [list $id1 $id2]
  dict set game(sessions) $guildId responses $responses
}

proc wots::remove_timers {guildId userId} {
  variable game
  set responses [dict get $game(sessions) $guildId responses]
  if {![catch {dict get $responses $userId} ids]} {
    foreach id $ids {after cancel $id}
    dict unset responses $userId
    dict set game(sessions) $guildId responses $responses
  }
}

proc wots::draw {guildId} {
  variable game
  
  set pile [dict get $game(sessions) $guildId pile]
  set card [lindex $pile 0]
  if {$card == ""} {
    return ""
  } else {
    set pile [lreplace $pile 0 0]
    dict set game(sessions) $guildId pile $pile
    return $card
  }
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
