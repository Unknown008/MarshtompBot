namespace eval meta {
  sqlite3 metadb "${scriptDir}/metadb.sqlite3"
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
  
  variable botstats
  set botstats(order) {
    UPTIME RESUMED READY CHANNEL_CREATE CHANNEL_UPDATE CHANNEL_DELETE
    GUILD_CREATE GUILD_UPDATE GUILD_DELETE GUILD_BAN_ADD GUILD_BAN_REMOVE
    GUILD_MEMBER_ADD GUILD_MEMBER_REMOVE GUILD_MEMBER_UPDATE GUILD_EMOJI_UPDATE 
    GUILD_INTEGRATIONS_UPDATE GUILD_ROLE_CREATE GUILD_ROLE_UPDATE 
    GUILD_ROLE_DELETE MESSAGE_CREATE MESSAGE_UPDATE MESSAGE_DELETE 
    MESSAGE_DELETE_BULK PRESENCE_UPDATE TYPING_START USER_UPDATE 
    MESSAGE_REACTION_ADD MESSAGE_REACTION_REMOVE CHANNEL_PINS_UPDATE 
    PRESENCES_REPLACE MESSAGE_ACK CHANNEL_PINS_ACK CHANNEL_PINS_UPDATE 
    PRESENCES_REPLACE   
  }
  set botstats(UPTIME)                    [clock scan now]
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
}

proc meta::buildLogs {{guildId {}}} {
  if {$guildId == ""} {
    foreach {guildId data} [set ${::session}::guilds] {
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

proc meta::command {data text channelId guildId userId} {
  set banned [metadb eval {SELECT userId FROM banned WHERE userId = :userId}]
  if {$userId in $banned} {return}
  switch [lindex $text 0] {
    "!setup" {
      if {![hasPerm $userId {ADMINISTRATOR MANAGE_CHANNELS MANAGE_GUILD}]} {
        return
      }
      setup [regsub {!setup *} $text ""]
    }
    "!ban" {
      if {
        ![hasPerm $userId {ADMINISTRATOR MANAGE_CHANNELS MANAGE_GUILD} || 
        $userId != $::ownerId
      } {
        return
      }
      ban [regsub {!ban *} $text ""]
    }
    "!unban" {
      if {
        ![hasPerm $userId {ADMINISTRATOR MANAGE_CHANNELS MANAGE_GUILD} || 
        $userId != $::ownerId
      } {
        return
      }
      unban [regsub {!unban *} $text ""]
    }
    "!botstats" {
      putBotStats
    }
    "!help" {
      help
    }
    default {
      # Other commands
      if {[::custom::command]} {
        return
      } elseif {[::pokedex::command]} {
        return
      } elseif {[::stats::command]} {
        return
      } elseif {[::pogo::command]} {
        return
      }
    }
  }
}

# To test for disconnects; resend message
proc meta::putdc {data encode {channelId {}} {cmdlist {}}} {
  if {$channelId eq ""} {
    set channelId [uplevel #2 {set channelId}]
  } elseif {$channelId eq "test"} {
    set channelId 236097944158208000
  }
  
  if {$encode && [dict exists $data content]} {
    set text [dict get $data content]
    set text [encoding convertto utf-8 $text]
    dict set data content $text
  }
  if {[catch {discord sendMessage $::session $channelId $data 1} resCoro]} {
    puts "meta::putdc $resCoro"
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

# To test for disconnects; resend message
proc meta::putdcPM {userId text {cmdlist {}}} {
  if {[catch {discord sendDM $::session $userId $text 1} resCoro]} {
    set resCoro [discord createDM $::session $userId 1]
    if {$resCoro eq {}} {return}
    yield $resCoro
    set response [$resCoro]
    set data [lindex $response 0]
    if {$data ne {} && [dict exists $data recipients]} {
      dict set ${::session}::dmChannels [dict get $data id] $data
      set resCoro [discord sendDM $::session $userId $text 1]
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

proc meta::editdc {data encode msgId channelId {cmdlist {}}} {
  if {$encode && [dict exists $data content] && [dict get $data content] ne ""} {
    set text [dict get $data content]
    set text [encoding convertto utf-8 $text]
    dict set data content $text
  }
  set resCoro [discord editMessage $::session $channelId $msgId $data 1]
  if {$resCoro eq {}} {return}
  yield $resCoro
  set response [$resCoro]
  set data [lindex $response 0]
  if {$data ne {} && $cmdlist != {}} {
    set cmdlist [lassign $cmdlist cmd]
    {*}$cmd $cmdlist
  }
}

proc meta::help {} {
  putdc [dict create content \
    "Available commands are listed here: https://pastebin.com/wDDzUmYn"] 0
}

proc meta::setup {arg} {
  if {[llength [split $arg { }]] != 2} {
    putdc [dict create content \
      "Incorrect number of parameters.\nUsage: !setup **type** **channel**"] 0
    return
  }
  lassign [split $arg { }] type channel
  if {$type ni [list log anime serebii]} {
    putdc [dict create content \
      "Invalid setup type. Should be log, serebii or anime"] 0
    return
  }
  
  upvar guildId guildId
  if {[regexp {^(?:<#([0-9]+)>|([0-9]+))$} $channel - m1 m2]} {
    set channelId $m1$m2
  }
  set channelObj [dict get [set ${::session}::guilds] $guildId channels]
  set channelIds [lmap x $channelObj {dict get $x id}]
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

proc meta::logDelete {guildId id source_id} {
  set channelId [metadb eval {
    SELECT channelId FROM config WHERE guildId = :guildId AND type = 'log'
  }]
  lassign [metadb eval "
    SELECT userId, content, embed, attachment FROM chatlog_$guildId WHERE msgId = :id 
  "] targetId content embed attachment
  
  set targetName [dict get [set ${::session}::users] $targetId username]
  if {![catch {dict get [set ${::session}::users] $targetId nick $guildId} nick]} {
    if {$nick ne ""} {
      set targetName "$targetName ($nick)"
    }
  }   
  
  if {$channelId eq ""} {set channelId test}
  set callback [discord getAuditLog $::session $guildId {limit 10} 1]
  # No callback generated. Shouldn't really happen
  if {$callback eq "" || $targetId eq ""} {
    putdc [dict create content \
      "Message ID $id was deleted from <#$source_id>"] 0 $channelId
  } else {
    yield $callback
    set response [$callback]
    set data [lindex $response 0]
    # Delete is in recent logs, logically always non-empty
    if {$data ne ""} {
      set auditObj ""
      foreach x [dict get $data audit_log_entries] {
        if {
          [dict get $x id] > $id &&
          [dict get $x action_type] == 72 &&
          [dict get $x target_id] == $targetId &&
          [dict get $x options channel_id] == $source_id &&
          [dict get $x options count] >= 1
        } {
          set auditObj $x
          break
        }
      }
      # Match found - user deleted someone else's message
      if {$auditObj != ""} {
        set userId [dict get $auditObj user_id]
        set userName [getUsernameNick $userId $guildId]
        set msg "Message ID $id by *$targetName* was deleted from <#$source_id> by *$userName*."
        after idle [list ::stats::bump deleteMsg $guildId $source_id $targetId $userId]
      # Match not found - user deleted own message
      } else {
        set msg "Message ID $id by *$targetName* was deleted from <#$source_id>."
        after idle [list ::stats::bump deleteMsg $guildId $source_id $targetId ""]
      }
      set delMsg [dict create content $content embed $embed]
      if {$attachment ne ""} {
        set links [lmap x $attachment {dict get $x url}]
        dict set delMsg content "$content: [join $links {,}]"
      }
      set cmd [list putdc $delMsg 1 $channelId]
      putdc [dict create content $msg] 1 $channelId [list $cmd]
    # Delete is not in recent logs, shouldn't happen
    } else {
      putdc [dict create content \
        "Message ID $id was deleted from <#$source_id>"] 0 $channelId
    }
  }
}

proc meta::logChat {guildId msgId userId content embed attachment} {
  metadb eval "
    INSERT INTO chatlog_$guildId VALUES (:msgId,:userId,:content,:embed,:attachment,'false')
  "
  set len [metadb eval "SELECT COUNT(*) FROM chatlog_$guildId"]
  if {$::custom::say(state) == 1 && $content != "!say end" &&
    $userId != [dict get [set ${::session}::self] id]
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
    after idle [list ::stats::bump createMsg $guildId $channelId $userId $content]
  }
}

proc meta::bump {event} {
  variable botstats
  if {[info exists botstats($event)]} {
    incr botstats($event)
  }
}

proc meta::putBotStats {} {
  variable botstats
  set msg [list]
  set kmax 8
  set vmax 0
  
  lappend msg [list SERVERS [expr {[llength [set ${::session}::guilds]] / 2}]]
  lappend msg [list CHANNELS [expr {[llength [set ${::session}::channels]] / 2}]]
  lappend msg ""
  foreach k $botstats(order) {
    if {$k eq "UPTIME"} {
      set v [formatTime [expr {[clock scan now]-$botstats($k)}]]
      lappend msg [list $k $v]
    } else {
      if {$botstats($k) > 0} {
        if {$botstats($k) > 1000} {
          regsub -all {(?=(?:\d{3})+$)} $botstats($k) "," v
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


proc meta::ban {text} {
  set users [set ${::session}::users]
  if {[regexp {<@!?([0-9]+)>} $text - userId] && $userId in $users} {
    set result [metadb eval {SELECT userId FROM banned WHERE userId = :userId}]
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

proc meta::unban {text} {
  if {[regexp {<@!?([0-9]+)>} $text - userId]} {
    set result [metadb eval {SELECT userId FROM banned WHERE userId = :userId}]
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

proc meta::formatTime {duration} {
  set s [expr {$duration % 60}]
  set i [expr {$duration / 60}]
  set m [expr {$i % 60}]
  set i [expr {$i / 60}]
  set h [expr {$i % 24}]
  set d [expr {$i / 24}]
  return [format "%+d day(s) %02dh%02dm%02ds" $d $h $m $s]
}

proc meta::logPresence {guildId userId data} {
  set channelId [metadb eval {
    SELECT channelId FROM config WHERE guildId = :guildId AND type = 'log'
  }]
  if {$channelId eq ""} {set channelId test}
  if {![catch {dict get $data user username} newUsername]} {
    set prevUsername [dict get [set ${::session}::users] $userId username]
    if {$newUsername ne $prevUsername} {
      if {![catch {dict get [set ${::session}::users] $userId nick $guildId} nick]} {
        set old "$old ($nick)"
      }
      if {![catch {dict get $data nick} nick]} {
        set new "$new ($nick)"
      }
      dict set ${::session}::users $userId username $new
      putdc [dict create content \
        "$prevUsername changed their username to $newUsername."] 1 $channelId
      after idle [list ::stats::bump nickChange $guildId "" $userId ""]
    }
  }
  # Else check for game change or status change (log in/out)
}

proc meta::logMember {guildId userId data} {
  set channelId [metadb eval {
    SELECT channelId FROM config WHERE guildId = :guildId AND type = 'log'
  }]
  if {$channelId eq ""} {set channelId test}
  set username [dict get $data user username]
  if {[catch {dict get $data nick} newNick]} {
    set newNick ""
  }
  if {[catch {dict get [set ${::session}::users] $userId nick $guildId} prevNick]} {
    set prevNick ""
  }
  if {$newNick ne $prevNick} {
    if {$newNick ne "" && $prevNick ne ""} {
      dict set ${::session}::users $userId nick $guildId $newNick
      set msg "$username's nickname was changed from $prevNick to $newNick."
    } elseif {$newNick eq ""} {
      dict set ${::session}::users $userId nick $guildId $newNick
      set msg "$username dropped their nickname: $prevNick."
    } else {
      dict set ${::session}::users $userId nick $guildId {}
      set msg "$username has a new nickname: $newNick."
    }
    putdc [dict create content $msg] 1 $channelId
  }
  # Else check for role change
}

proc meta::logMsgEdit {body} {
  set guildId [dict get $body guild_id]
  set channelId [metadb eval {
    SELECT channelId FROM config WHERE guildId = :guildId AND type = 'log'
  }]
  set userId [dict get $body author id]
  if {$userId == [dict get [set ${::session}::self] id]} {return}
  if {$channelId == ""} {
    set channelId test
  }
  set msgId [dict get $body id]
  set pinned [dict get $body pinned]
  lassign [metadb eval "
    SELECT userId, content, embed, attachment, pinned FROM chatlog_$guildId
    WHERE msgId = :msgId 
  "] targetId content embed attachment oldpinned
  if {$oldpinned != $pinned} {
    metadb eval \
      "UPDATE chatlog_$guildId SET pinned = '$pinned' WHERE msgId = :msgId"
    return
  }
  
  set sourceId [dict get $body channel_id]
  set userName [getUsernameNick $userId $guildId]
  set oldMsg ""
  set newMsg ""
  set msg "$userName edited message with ID $msgId."
  
  if {$content != ""} {
    set oldMsg [dict create content "From: $content" embed $embed]
    if {$attachment ne ""} {
      set links [lmap x $attachment {dict get $x url}]
      dict set delMsg content "$content: [join $links {,}]"
    }
    set cmd [list putdc $oldMsg 1 $channelId]
  }
  
  set callback [discord getMessage $::session $sourceId $msgId 1]
  if {$callback eq ""} {
    if {$oldMsg eq ""} {
      putdc [dict create content \
        "$msg *Could not retrieve message contents*." ] 1
    } else {
      set cmd1 [list putdc [dict create content \
        "To: *Could not retrieve message contents*."] 0 $channelId]
      putdc [dict create content $msg] 0 $channelId [list $cmd $cmd1]
    }
  } else {
    yield $callback
    set response [$callback]
    set data [lindex $response 0]
    if {$data ne ""} {
      set content [dict get $data content]
      set embed [dict get $data embeds]
      set cmd1 [list putdc [dict create content "To: $content" embed $embed] 0 \
        $channelId]
      if {$oldMsg eq ""} {
        putdc [dict create content $msg] 1 $channelId [list $cmd1]
      } else {
        putdc [dict create content $msg] 1 $channelId [list $cmd $cmd1]
      }
    } else {
      if {$oldMsg eq ""} {
        putdc [dict create content \
          "$msg *Could not retrieve message contents*."] 0
      } else {
        set cmd1 [list putdc [dict create content \
          "To: *Could not retrieve message contents*."] 0 $channelId]
        putdc [dict create content $msg] 1 $channelId [list $cmd $cmd1]
      }
    }
  }
  after idle [list ::stats::bump editMsg $guildId $channelId $userId ""]
}

proc meta::welcomeMsg {guildId userId} {
  set channelId [metadb eval {
    SELECT channelId FROM config WHERE guildId = :guildId AND type = 'log'
  }]
  if {$channelId != ""} {
    set msg "<@$userId> joined the server."
  } else {
    set servername [dict get [set ${::session}::guilds] $guildId name]
    set msg "<@$userId> joined $servername."
    set channelId "test"
  }
  putdc [dict create content $msg] 0 $channelId
}

proc meta::partMsg {guildId userId} {
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
            [dict get $x action_type] in {20 22} &&
            [dict get $x target_id] == $userId
          } {
            set auditObj $x
            break
          }
        }
        
        if {$auditObj != ""} {
          set actionId [dict get $auditObj user_id]
          set userName [getUsernameNick $actionId $guildId]
          if {$actionId == 20} {
            set msg "<@$userId> ($name) was kicked from the server by *$userName*."
          } else {
            set msg "<@$userId> ($name) was kickbanned from the server by *$userName*."
          }
          if {![catch {dict get $auditObj reason} reason] && $reason ne ""} {
            set msg "$msg (Reason: $reason)."
          } else {
            set msg "$msg (*No reason provided*)."
          }
          after idle [list ::stats::bump userKick $guildId "" $actionId $userId]
        }
      }
    }
    putdc [dict create content $msg] 1 $channelId
  } else {
    set serverName [dict get [set ${::session}::guilds] $guildId name]
    set userName [getUsernameNick $userId $guildId {%s @ %s}]
    if {$userName eq ""} {
      putdc [dict create content "<@$userId> left $serverName."] 0 $channelId
    } else {
      putdc [dict create content "<@$userId> ($userName) left $serverName."] 1 test
    }
  }
}

proc meta::logBanRemove {guildId userId} {
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
            [dict get $x action_type] == 23 &&
            [dict get $x target_id] == $userId
          } {
            set auditObj $x
            break
          }
        }
        
        if {$auditObj != ""} {
          set actionId [dict get $auditObj user_id]
          set userName [getUsernameNick $actionId $guildId]
          set msg "The ban on <@$userId> has been lifted by *$userName*."
        }
      }
    }
    putdc [dict create content $msg] 0 $channelId
  } else {
    set servername [dict get [set ${::session}::guilds] $guildId name]
    
    if {[catch {dict get [set ${::session}::users] $userId username} name]} {
      set msg "The ban on <@$userId> has been lifted."
    } else {
      set msg "The ban on <@$userId> (*$name*) has been lifted."
    }
    putdc [dict create content $msg] 1 test
  }
}

proc meta::hasPerm {userId permissions} {
  upvar guildId guildId
  set members [dict get [set ${::session}::guilds] $guildId members]
  set memObj [lsearch -inline -index {1 3} $members $userId]
  set mRoles [dict get $memObj roles]
  
  set guildRoles [dict get [set ${::session}::guilds] $guildId roles]
  
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

proc meta::getUsernameNick {userId guildId {fmt {}}} {
  if {[catch {dict get [set ${::session}::users] $userId username} username]} {
    set username ""
  } else {
    if {![catch {dict get [set ${::session}::users] $userId nick $guildId} nick]} {
      if {$fmt eq ""} {
        set username "$username ($nick)"
      } else {
        set username [format $fmt $username $nick]
      }
    }
  }
  return $username
}

##
# Debug file control
##
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

after idle [list ::meta::cleanDebug]

puts "meta.tcl loaded"