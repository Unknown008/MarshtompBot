namespace eval stats {
  sqlite3 statsdb "${scriptDir}/stats.sqlite3"
  # https://chanstat.net/stats/rizon/%23homescreen
  # action
  # 100 createMsg at 00 hr
  # 101 createMsg at 01 hr
  # 102 createMsg at 02 hr
  # 103 createMsg at 03 hr
  # 104 createMsg at 04 hr
  # 105 createMsg at 05 hr
  # 106 createMsg at 06 hr
  # 107 createMsg at 07 hr
  # 108 createMsg at 08 hr
  # 109 createMsg at 09 hr
  # 110 createMsg at 10 hr
  # 111 createMsg at 11 hr
  # 112 createMsg at 12 hr
  # 113 createMsg at 13 hr
  # 114 createMsg at 14 hr
  # 115 createMsg at 15 hr
  # 116 createMsg at 16 hr
  # 117 createMsg at 17 hr
  # 118 createMsg at 18 hr
  # 119 createMsg at 19 hr
  # 120 createMsg at 20 hr
  # 121 createMsg at 21 hr
  # 122 createMsg at 22 hr
  # 123 createMsg at 23 hr
  # 124 createMsg at 24 hr
  # 130 allCapsMsg
  # 140 questions
  
  # 200 words
  # 201 upperWords
  # 202 smile
  # 203 frown
  
  # 300 letters
  
  # 400 editMsg
  # 401 deleteMsg self
  # 402 deleteMsg others
  
  # 500 kicks
  # 501 kicked
  # 600 nickChange
  # 601 nameChange
  
  statsdb eval {
    CREATE TABLE IF NOT EXISTS stats(
      guildId text,
      channelId text,
      userId text,
      action int,
      value int
    )
  }
  
  statsdb eval {
    CREATE TABLE IF NOT EXISTS statsFrom(
      guildId text,
      date text
    )
  }
  
  # type: 0 - sad | 1 - smile
  statsdb eval {
    CREATE TABLE IF NOT EXISTS statsMood(
      guildId text,
      emote text,
      type int
    )
  }
  
  # some global emotes
  if {![statsdb exists {SELECT 1 FROM statsMood}]} {
    statsdb eval {
      INSERT INTO statsMood VALUES
      ('', ':)', 1),
      ('', ':(', 0),
      ('', '(:', 1),
      ('', '):', 0),
      ('', ':-)', 1),
      ('', ':-(', 0),
      ('', '(-:', 1),
      ('', ')-:', 0),
      ('', ':]', 1),
      ('', ':[', 0),
      ('', '[:', 1),
      ('', ']:', 0),
      ('', ':-]', 1),
      ('', ':-[', 0),
      ('', '[-:', 1),
      ('', ']-:', 0),
      ('', ':D', 1),
      ('', 'xD', 1),
      ('', 'XD', 1),
      ('', ':3', 1),
      ('', 'n_n', 1),
      ('', '^^', 1),
      ('', '^_^', 1),
      ('', 'owo', 1),
      ('', 'ouo', 1),
      ('', 'c:', 1),
      ('', 'D:', 0),
      ('', 'Dx', 0),
      ('', 'DX', 0),
      ('', ':c', 0)
    }
  }

  # time on server is EDT, need to use UTC
}

proc stats::command {} {
  upvar data data text text channelId channelId guildId guildId userId userId
  switch [lindex $text 0] {
    "!ss" -
    "!stats" {
      switch [lindex $text 1] {
        "delete" -
        "clear" {
          set roles {ADMINISTRATOR MANAGE_CHANNELS MANAGE_GUILD}
          if {![::meta::has_perm $userId $roles] || $userId != $::ownerId} {
            return 1
          }
          clear_servstats $guildId \
            [regsub {!s(?:tat)?s (?:delete|clear) *} $text ""]
        }
        "reg" {
          reg_stats $guildId [regsub {!s(?:tat)?s reg *} $text ""]
        }
        "" {
          put_servstats $guildId [regsub {!s(?:tat)?s *} $text ""]
        }
        default {
          regexp {<#([0-9]+)>} [lindex $text 1] - chan
          if {$chan != ""} {
            set res [statsdb eval {SELECT 1 FROM stats WHERE channelId = :chan}]
            if {$res != ""} {
              put_servstats $guildId $chan
              return 1
            }
          }
          ::meta::putdc [dict create content \
            "Unknown option. Should be !stats ?\[clear|reg\]?"] 0
        }
      }
    }
    default {return 0}
  }
  return 1
}

proc stats::put_servstats {guildId {channelId {}}} {
  if {$channelId == ""} {
    set stats [statsdb eval {SELECT * FROM stats WHERE guildId = :guildId}]
    set loc "the server"
  } else {
    set stats [statsdb eval {SELECT * FROM stats WHERE channelId = :channelId}]
    set loc "<#$channelId>"
  }
  if {[llength $stats] > 0} {
    set desc ""
    set guildData [guild eval {SELECT data FROM guild WHERE guildId = :guildId}]
    set guildData {*}$guildData
    set guildName [dict get $guildData name]
    set channelName ""
    set date [statsdb eval {
      SELECT date FROM statsFrom WHERE guildId = :guildId
    }]
    if {$channelId == ""} {
      set lines [statsdb eval {
        SELECT SUM(value) FROM stats WHERE guildId = :guildId AND action < 125
      }]
      set words [statsdb eval {
        SELECT SUM(value) FROM stats WHERE guildId = :guildId AND action = 200
      }]
      set toplines [statsdb eval {
        SELECT userId, SUM(value) FROM stats 
        WHERE guildId = :guildId AND action < 125
        GROUP BY userId ORDER BY SUM(value) DESC LIMIT 1
      }]
      lassign $toplines topliner toplines
      lassign [top guild $guildId 200] topworder topwords
      set bigWords [statsdb eval {
        SELECT a.userId, (a.value*1.0)/b.value FROM stats a
        JOIN stats b
        ON a.guildId = b.guildId AND a.userId = b.userId
        AND a.action = 300 AND b.action = 200
        WHERE guildId = :guildId
        ORDER BY (a.value*1.0)/b.value DESC LIMIT 1
      }]
      lassign $bigWords bigWords avgSize
      set tightLipped [statsdb eval {
        SELECT a.userId, (a.value*1.0)/b.value FROM stats a
        JOIN stats b
        ON a.guildId = b.guildId AND a.userId = b.userId
        AND a.action = 200 AND b.action < 130
        WHERE guildId = :guildId
        ORDER BY (a.value*1.0)/b.value DESC LIMIT 1
      }]
      lassign $tightLipped tightLipped avgWords
      lassign [top_contain guild $guildId 140] questioner qperc
      lassign [top_contain guild $guildId 201] yeller yperc
      lassign [top_contain guild $guildId 130] capper cperc
      lassign [top_contain guild $guildId 202] smiler sperc
      lassign [top_contain guild $guildId 203] frowner fperc
      lassign [top guild $guildId 600] nickChanger nickChanges
      lassign [top guild $guildId 500] kicker kickers
      lassign [top guild $guildId 501] kicked kickeds
      lassign [top guild $guildId 400] editor edits
      lassign [top guild $guildId 401] deleter deleted
      lassign [top guild $guildId 402] janitor janitored
    } else {
      foreach channelData [dict get $guildData channels] {
        if {[dict get $channelData id] == $channelId} {
          set channelName [dict get $channelData name]
          break
        }
      }
      set lines [statsdb eval {
        SELECT SUM(value) FROM stats
        WHERE channelId = :channelId AND action < 125
      }]
      set words [statsdb eval {
        SELECT SUM(value) FROM stats
        WHERE channelId = :channelId AND action = 200
      }]
      set toplines [statsdb eval {
        SELECT userId, SUM(value) FROM stats 
        WHERE channelId = :channelId AND action < 125
        GROUP BY userId ORDER BY SUM(value) DESC LIMIT 1
      }]
      lassign $toplines topliner toplines
      lassign [top channel $channelId 200] topworder topwords
      set bigWords [statsdb eval {
        SELECT a.userId, (a.value*1.0)/b.value FROM stats a
        JOIN stats b
        ON a.channelId = b.channelId AND a.userId = b.userId
        AND a.action = 300 AND b.action = 200
        WHERE channelId = :channelId
        ORDER BY (a.value*1.0)/b.value DESC LIMIT 1
      }]
      lassign $bigWords bigWords avgSize
      set tightLipped [statsdb eval {
        SELECT a.userId, (a.value*1.0)/b.value FROM stats a
        JOIN stats b
        ON a.channelId = b.channelId AND a.userId = b.userId
        AND a.action = 200 AND b.action < 130
        WHERE channelId = :channelId
        ORDER BY (a.value*1.0)/b.value DESC LIMIT 1
      }]
      lassign $tightLipped tightLipped avgWords
      lassign [top_contain channel $channelId 140] questioner qperc
      lassign [top_contain channel $channelId 201] yeller yperc
      lassign [top_contain channel $channelId 130] capper cperc
      lassign [top_contain channel $channelId 202] smiler sperc
      lassign [top_contain channel $channelId 203] frowner fperc
      lassign [top channel $channelId 400] editor edits
      lassign [top channel $channelId 401] deleter deleted
      lassign [top channel $channelId 402] janitor janitored
    }
    if {$lines != ""} {
      append desc "Totals: $lines messages and $words words.\n"
      append desc "Highest messages recorded: [::meta::getUsernameNick $topliner $guildId] with $toplines messages!\n"
      append desc "Highest words recorded: [::meta::getUsernameNick $topworder $guildId] with $topwords words!\n"
      append desc "• [::meta::getUsernameNick $bigWords $guildId] uses a lot of big words! The average size of their words was $avgSize letters per word!\n"
      append desc "• [::meta::getUsernameNick $tightLipped $guildId] Doesn't speak a lot... They had $avgWords words per line!\n"
    }
    if {$qperc != ""} {
      append desc "• [::meta::getUsernameNick $questioner $guildId] appears to be in search for knowledge, or maybe is just asking too many questions... [format %.1f%% $qperc] of their messages contained questions!\n"
    }
    if {$yperc != ""} {
      append desc "• The loudest one was [::meta::getUsernameNick $yeller $guildId] who yelled [format %.1f%% $yperc] of the time!\n"
    }
    if {$cperc != ""} {
      append desc "• It seems that [::meta::getUsernameNick $capper $guildId]'s shift key is handing; [format %.1f%% $cperc] of the time they wrote in UPPERCASE!\n"
    }
    if {$sperc != ""} {
      append desc "• [::meta::getUsernameNick $smiler $guildId] brings happiness to the world; [format %.1f%% $sperc] of their messages contained smiley faces!\n"
    }
    if {$fperc != ""} {
      append desc "• [::meta::getUsernameNick $frowner $guildId] seems to be sad at the moment; [format %.1f%% $fperc] messages contained sad faces!\n"
    }
    if {$edits != ""} {
      append desc "• [::meta::getUsernameNick $editor $guildId] keeps changing their minds, or maybe the evil autocorrect is changing their words; they edited their messages $edits times!\n"
    }
    if {$deleted != ""} {
      append desc "• Is [::meta::getUsernameNick $deleter $guildId] a paranoid? They deleted $deleted of their messages!\n"
    }
    if {$janitored != ""} {
      append desc "• [::meta::getUsernameNick $janitor $guildId] is either crazy or just a responsible janitor; they deleted $janitored messages!\n"
    }
    if {$channelId == ""} {
      if {$nickChanges != ""} {
        append desc "• [::meta::getUsernameNick $nickChanger $guildId] seems to have some personality issues; they changed their nicknames $nickChanges times!\n"
      }
      if {$kickers != ""} {
        append desc "• [::meta::getUsernameNick $kicker $guildId] is either insane or just a fair moderator, kicking people a total of $kickers times!\n"
        append desc "• [::meta::getUsernameNick $kicked $guildId] seems to get bullied quite a lot, getting kicked $kickeds times!"
      }
    }
    set medium [expr {$channelId == "" ? $guildName : $channelName}]
    set footer "Stats collected as from [clock format $date -timezone UTC]\n"
    append footer "Disclaimer: All of the above are not meant to be personal "
    append footer "attacks, but more as lighthearted jokes."
    set msg [dict create embed [dict create \
      title "Stats for $medium:" \
      description $desc \
      footer [dict create text $footer] \
    ]]
  } else {
    set msg "There are no stats saved for $loc!"
  }
  ::meta::putdc $msg 1
}

proc stats::clear_servstats {guildId {channelId {}}} {
  if {$channelId == ""} {
    set stats [statsdb eval {SELECT * FROM stats WHERE guildId = :guildId}]
    if {[llength $stats] > 0} {
      statsdb eval {DELETE FROM stats WHERE guildId = :guildId}
      statsdb eval {DELETE FROM statsFrom WHERE guildId = :guildId}
      set msg "Deleted stats for the server!"
    } else {
      set msg "There are no stats saved for the server!"
    }
  } else {
    set stats [statsdb eval {SELECT * FROM stats WHERE channelId = :channelId}]
    if {[llength $stats] > 0} {
      statsdb eval {DELETE FROM stats WHERE channelId = :channelId}
      set msg "Deleted stats for the <#$channelId>!"
    } else {
      set msg "There are no stats saved for <#$channelId>!"
    }
  }
  ::meta::putdc [dict create content $msg] 0
}

proc stats::bump {type guildId channelId userId content} {
  variable smileWords
  variable frownWords
  set date [statsdb eval {SELECT date FROM statsFrom WHERE guildId = :guildId}]
  if {$date eq ""} {
    set now [clock scan now]
    statsdb eval {INSERT INTO statsFrom VALUES (:guildId, :now)}
  }
  switch $type {
    createMsg {
      upvar msgId msgId
      # Lines
      set hr [clock format [expr {
        [::getSnowflakeUnixTime 448756188566388756 $::discord::Epoch]/1000
      }] -timezone UTC -format "%H"]
      set hr "1$hr"
      bump_action $guildId $channelId $userId $hr
      
      # All caps
      if {[string toupper $content] eq $content && [regexp {[A-Z]+} $content]} {
        bump_action $guildId $channelId $userId 130
      
      # Yelling
      } elseif {[regexp {^.+\y[A-Z]{2,}\y} $content]} {
        bump_action $guildId $channelId $userId 201
      }
      
      # Questions
      if {[string first "?" $content] != -1} {
        bump_action $guildId $channelId $userId 140
      }
      
      # Words
      set words [llength [split $content " "]]
      bump_action $guildId $channelId $userId 200 $words
      
      # :)
      set smilies [statsdb eval {
        SELECT emote FROM statsMood
        WHERE type = 1 AND (guildId = '' OR guildId = :guildId)
      }]
      set smile 0
      foreach smiley $smilies {
        if {[string first $smiley $content] >= 0} {
          set smile 1
          break
        }
      }
      
      if {$smile} {
        bump_action $guildId $channelId $userId 202
      }
      
      # :(
      set smilies [statsdb eval {
        SELECT emote FROM statsMood
        WHERE type = 0 AND (guildId = '' OR guildId = :guildId)
      }]
      set frown 0
      foreach smiley $smilies {
        if {[string first $smiley $content] >= 0} {
          set frown 1
          break
        }
      }
      
      if {$frown} {
        bump_action $guildId $channelId $userId 203
      }
      
      # Letters
      set letters [llength [regexp -all {[[:alpha:]]} $content]]
      bump_action $guildId $channelId $userId 300 $letters
    }
    editMsg {
      bump_action $guildId $channelId $userId 400
    }
    deleteMsg {
      if {$content eq ""} {
        bump_action $guildId $channelId $userId 401
      } else {
        bump_action $guildId $channelId $userId 402
      }
    }
    userKick {
      bump_action $guildId $channelId $userId 500
      bump_action $guildId $channelId $content 501
    }
    nickChange {
      if {![::meta::has_perm $userId {CHANGE_NICKNAME}]} {return}
      bump_action $guildId $channelId $userId 600
    }
    nameChange {
      bump_action $guildId $channelId $userId 601
    }
    default {}
  }
}

proc stats::reg_stats {guildId arg} {
  set arg [split $arg]
  if {[llength $arg] != 2} {
    set msg "Wrong number of parameters. Should be `!stats reg (smile|frown) "
    append msg "*emote*`"
    ::meta::putdc [dict create content $msg] 0
    return
  }
  lassign $arg type text
  switch $type {
    happy -
    smile {
      statsdb eval {INSERT INTO statsMood VALUES (:guildId, :text, 1)}
    }
    sad -
    frown {
      statsdb eval {INSERT INTO statsMood VALUES (:guildId, :text, 0)}
    }
  }
  ::meta::putdc [dict create content \
      "Successfully added $text to $type stats!" \
  ] 1
}

proc stats::bump_action {guildId channelId userId action {amt 1}} {
  set recs [statsdb eval {
    SELECT 1 FROM stats
    WHERE guildId = :guildId AND userId = :userId AND action = :action LIMIT 1
  }]
  if {$recs == ""} {
    statsdb eval {
      INSERT INTO stats VALUES (:guildId, :channelId, :userId, :action, :amt)
    }
  } else {
    statsdb eval {
      UPDATE stats SET value = value + :amt
      WHERE guildId = :guildId AND userId = :userId AND action = :action
    }
  }
}

proc stats::top {type id action} {
  set query {
    SELECT userId, value FROM stats 
    WHERE %s = :%s AND action = :action
    ORDER BY value DESC LIMIT 1
  }
  return [statsdb eval [format $query $type $id]]
}

proc stats::top_contain {type id action} {
  set query {
    SELECT a.userId, 100*SUM(b.value*1.0)/SUM(a.value)/COUNT(*) FROM stats a
    JOIN stats b
    ON a.%sId = b.%sId AND a.userId = b.userId 
    AND a.action < 125 AND b.action = :action
    WHERE a.%sId = :%s
    GROUP BY a.userId
    ORDER BY 100*SUM(b.value*1.0)/SUM(a.value)/COUNT(*) DESC LIMIT 1
  }
  return [statsdb eval [format $query $type $type $type $id]]
}

proc stats::pre_rehash {} {
  return
}

puts "stats.tcl loaded"