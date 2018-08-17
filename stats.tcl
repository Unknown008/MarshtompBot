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
          if {
            ![::meta::hasPerm $userId {ADMINISTRATOR MANAGE_CHANNELS MANAGE_GUILD}] || 
            $userId != $::ownerId
          } {
            return 1
          }
          clearServstats $guildId [regsub "!s(?:tat)?s [lindex $text 1] *" $text ""]
        }
        "reg" {
          regStats $guildId [regsub {!s(?:tat)?s reg *} $text ""]
        }
        "" {
          putServstats $guildId [regsub {!s(?:tat)?s *} $text ""]
        }
        default {
          ::meta::putdc [dict create content \
            "Unknown option. Should be !stats ?\[clear|reg\]?"]
        }
      }
    }
    default {return 0}
  }
  return 1
}

proc stats::putServstats {guildId {channelId {}}} {
  if {$channelId == ""} {
    set stats [statsdb eval {SELECT * FROM stats WHERE guildId = :guildId}]
    set loc "the server"
  } else {
    set stats [statsdb eval {SELECT * FROM stats WHERE channelId = :channelId}]
    set loc "<#$channelId>"
  }
  if {[llength $stats] > 0} {
    set desc ""
    set guildName [dict get [set ${::session}::guilds] $guildId name]
    set date [statsdb eval {SELECT date FROM statsFrom WHERE guildId = :guildId}]
    if {$channelId == ""} {
      set lines [statsdb eval {
        SELECT SUM(value) FROM stats WHERE guildId = :guildId AND type < 125
      }]
      set words [statsdb eval {
        SELECT SUM(value) FROM stats WHERE guildId = :guildId AND type = 200
      }]
      set toplines [statsdb eval {
        SELECT userId, SUM(value) FROM stats 
        WHERE guildId = :guildId AND type < 125
        GROUP BY userId ORDER BY SUM(value) DESC LIMIT 1
      }
      lassign $toplines topliner toplines
      lassign [topGuild $guildId 200] topworder topwords
      lassign [topContainGuild $guildId 140] questioner qperc
      lassign [topContainGuild $guildId 201] yeller yperc
      lassign [topContainGuild $guildId 130] capper cperc
      lassign [topContainGuild $guildId 202] smiler sperc
      lassign [topContainGuild $guildId 203] frowner fperc
      lassign [topGuild $guildId 600] nickChanger nickChanges
      lassign [topGuild $guildId 500] kicker kickers
      lassign [topGuild $guildId 501] kicked kickeds
      lassign [topGuild $guildId 400] editor edits
      lassign [topGuild $guildId 401] deleter deleted
      lassign [topGuild $guildId 402] janitor janitored
    } else {
      set lines [statsdb eval {
        SELECT SUM(value) FROM stats WHERE channelId = :channelId AND type < 125
      }]
      set words [statsdb eval {
        SELECT SUM(value) FROM stats WHERE channelId = :channelId AND type = 200
      }]
      set toplines [statsdb eval {
        SELECT userId, SUM(value) FROM stats 
        WHERE channelId = :channelId AND type < 125
        GROUP BY userId ORDER BY SUM(value) DESC LIMIT 1
      }
      lassign $toplines topliner toplines
      lassign [topChannel $channelId 200] topworder topwords
      lassign [topContainChannel $channelId 140] questioner qperc
      lassign [topContainChannel $channelId 201] yeller yperc
      lassign [topContainChannel $channelId 130] capper cperc
      lassign [topContainChannel $channelId 202] smiler sperc
      lassign [topContainChannel $channelId 203] frowner fperc
      lassign [topChannel $channelId 400] editor edits
      lassign [topChannel $channelId 401] deleter deleted
      lassign [topChannel $channelId 402] janitor janitored
    }
    append desc "Totals: $lines messages and $words words.\n"
    append desc "Highest messages recorded: $topliner with $toplines messages!\n"
    append desc "Highest words recorded: [::meta::getUsernameNick $topworder $guildId] with $topwords words!\n"
    append desc "• [::meta::getUsernameNick $questioner $guildId] appears to be in search for knowledge, or maybe is just asking too many questions... [format %.1f%% $qperc] of their messages contained questions!\n"
    append desc "• The loudest one was [::meta::getUsernameNick $yeller $guildId] who yelled [format %.1f%% $yperc] of the time!\n"
    append desc "• It seems that [::meta::getUsernameNick $capper $guildId]'s shift key is handing; [format %.1f%% $cperc] of the time they wrote in UPPERCASE!\n"
    append desc "• [::meta::getUsernameNick $smiler $guildId] brings happiness to the world; [format %.1f%% $sperc] of their messages contained smiley faces!\n"
    append desc "• [::meta::getUsernameNick $frowner $guildId] seems to be sad at the moment; [format %.1f%% $fperc] messages contained sad faces!\n"
    append desc "• [::meta::getUsernameNick $editer $guildId] keeps changing their minds, or maybe the evil autocorrect is changing their words; they edited their messages $edits times!\n"
    append desc "• Is [::meta::getUsernameNick $deleter $guildId] a paranoid? They deleted $deleted of their messages!\n"
    append desc "• [::meta::getUsernameNick $janitor $guildId] is either crazy or just a responsible janitor; they deleted $janitored messages!\n"
    if {$channelId == ""} {
      append desc "• [::meta::getUsernameNick $nickChanger $guildId] seems to have some personality issues; they changed their nicknames $nickChanges times!\n"
      append desc "• [::meta::getUsernameNick $kicker $guildId] is either insane or just a fair moderator, kicking people a total of $kickers times!\n"
      append desc "• [::meta::getUsernameNick $kicked $guildId] seems to get bullied quite a lot, getting kicked $kickeds times!"
    }
    set msg [dict create embed [dict create \
      title "Stats for $guildName:"
      description $desc
      footer [dict create text "Stats collected as from [clock format $date -timezone UTC]"]
    ]
  } else {
    set msg "There are no stats saved for $loc!"
  }
  ::meta::putdc [dict create content $msg] 1
}

proc stats::clearServstats {guildId {channelId {}}} {
  if {$channelId == ""} {
    set stats [statsdb eval {SELECT * FROM stats WHERE guildId = :guildId}]
    if {[llength $stats] > 0} {
      statsdb eval {DELETE FROM stats WHERE guildId = :guildId}
      statsdb eval {DELETE FROM statsFrom WHERE guildId = :guildId}]
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
      bumpAction $guildId $channelId $userId $hr
      
      # All caps
      if {[string toupper $content] eq $content} {
        bumpAction $guildId $channelId $userId 130
      
      # Yelling
      } elseif {[regexp {^.+\y[A-Z]{2,}\y} $content]} {
        bumpAction $guildId $channelId $userId 201
      }
      
      # Questions
      if {[string first "?" $content] != -1} {
        bumpAction $guildId $channelId $userId 140
      }
      
      # Words
      set words [llength [split $content " "]]
      bumpAction $guildId $channelId $userId 200 $words
      
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
        bumpAction $guildId $channelId $userId 202
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
        bumpAction $guildId $channelId $userId 203
      }
      
      # Letters
      set letters [llength [regexp -all {[[:alnum:]]} $content]]
      bumpAction $guildId $channelId $userId 300 $letters
    }
    editMsg {
      bumpAction $guildId $channelId $userId 400
    }
    deleteMsg {
      if {$content eq ""} {
        bumpAction $guildId $channelId $userId 401
      } else {
        bumpAction $guildId $channelId $userId 402
      }
    }
    nickChange {
      if {![::meta::hasPerm $userId {CHANGE_NICKNAME}]} {return}
      bumpAction $guildId $channelId $userId 600
    }
    userKick {
      bumpAction $guildId $channelId $userId 500
      bumpAction $guildId $channelId $content 100
    }
    default {}
  }
}

proc stats::regStats {guildId arg} {
  set arg [split $arg]
  if {[llength $arg] != 2} {
    ::meta::putdc [dict create content \
      "Wrong number of parameters. Should be `!statsreg (smile|frown) *emote*`" \
    ] 0
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

proc stats::bumpAction {guildId channelId userId action {amt 1}} {
  set recs {
    SELECT 1 FROM stats
    WHERE guildId = :guildId AND userId = :userId AND action = :action LIMIT 1
  }
  if {$recs == ""} {
    statsdb eval {
      INSERT INTO stats VALUES (:guildId, :channelId, :userId, :action, 1)
    }
  } else {
    statsdb eval {
      UPDATE stats SET value = value + :amt
      WHERE guildId = :guildId AND userId = :userId AND action = :action
    }
  }
}

proc stats::topGuild {guildId action} {
  return [statsdb eval {
    SELECT userId, value FROM stats 
    WHERE guildId = :guildId AND type = :action
    ORDER BY value DESC LIMIT 1
  }
}

proc stats::topContainGuild {guildId action} {
  return [statsdb eval {
    SELECT a.userId, 100*SUM(b.value*1.0)/SUM(a.value)/COUNT(*) FROM stats a
    JOIN stats b
    ON a.guildId = b.guildId AND a.userId = b.userId 
    AND a.type < 125 AND b.type = :action
    WHERE a.guildId = :guildId
    GROUP BY a.userId
    ORDER BY 100*SUM(b.value*1.0)/SUM(a.value)/COUNT(*) DESC LIMIT 1
  }]
}

proc stats::topChannel {channelId action} {
  return [statsdb eval {
    SELECT userId, value FROM stats 
    WHERE channelId = :channelId AND type = :action
    ORDER BY value DESC LIMIT 1
  }
}

proc stats::topContainChannel {channelId action} {
  return [statsdb eval {
    SELECT a.userId, 100*SUM(b.value*1.0)/SUM(a.value)/COUNT(*) FROM stats a
    JOIN stats b
    ON a.channelId = b.channelId AND a.userId = b.userId 
    AND a.type < 125 AND b.type = :action
    WHERE a.channelId = :channelId
    GROUP BY a.userId
    ORDER BY 100*SUM(b.value*1.0)/SUM(a.value)/COUNT(*) DESC LIMIT 1
  }]
}



puts "stats.tcl loaded"