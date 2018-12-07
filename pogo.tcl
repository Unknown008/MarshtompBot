namespace eval pogo {
  set silph(site)   "https://sil.ph/"
  set silph(listen) [list]
  
  sqlite3 pogodb pogo.sqlite3
  
  pogodb eval {
    CREATE TABLE IF NOT EXISTS pogo(
      id text,
      account text
    )
  }
  
  pogodb eval {
    CREATE TABLE IF NOT EXISTS config(
      guildId text,
      param text,
      value text
    )
  }
}

proc pogo::command {} {
  variable silph
  upvar data data text text channelId channelId guildId guildId userId userId
  switch [lindex $text 0] {
    "!silphcard" {
      showcard [regsub {!silphcard *} $text ""]
    }
    "!set" {
      if {[lindex $text 1] eq "silph"} {
        setsilph [regsub {!set silph *} $text ""]
      } else {
        return 0
      }
    }
    default {
      set idx [lsearch -index 0 $silph(listen) [list $userId $channelId $guildId]]
      if {$idx > -1 || [regexp -nocase {^y} $text]} {
        setsilph [lindex $silph(listen) 1]
        set silph(listen) [lreplace $silph(listen) $idx $idx]
        showcard ""
      } elseif {$idx > -1 || [regexp -nocase {^n} $text]} {
        set silph(listen) [lreplace $silph(listen) $idx $idx]
      }
      return 0
    }
  }
  return 1
}

proc pogo::setsilph {username} {
  upvar userId userId
  set res [pogodb eval {SELECT COUNT(*) FROM pogo WHERE id = :userId}]
  if {$res == 0} {
    pogodb eval {INSERT INTO pogo VALUES(:userId, :username)}
    ::meta::putdc [dict create content \
      "Your account has successfully been linked!"] 0
  } else {
    pogodb eval {UPDATE pogo SET account = :username WHERE id = :userId}
    ::meta::putdc [dict create content \
      "Your account has successfully been modified!"] 0
  }
}

proc pogo::showcard {text} {
  variable silph
  upvar guildId guildId userId userId channelId channelId
  set guildData [guild eval {SELECT data FROM guild WHERE guildId = :guildId}]
  set guildData {*}$guildData
  set members [dict get $guildData members]
  if {[regexp {^<@!?([0-9]+)>$} $text - user]} {
    set data [lsearch -inline $members "*$user*"]
  } elseif {[string tolower $text] in {me {}}} {
    set data [lsearch -inline -regexp $members "\\y$userId\\y"]
  } else {
    set data [lsearch -inline -nocase $members "*$text*"]
  }
  
  if {$data != ""} {
    set username [dict get $data user username]
    set id [dict get $data user id]
    
    set silphacc [pogodb eval {SELECT account FROM pogo WHERE id = :id LIMIT 1}]
  
    if {$silphacc == ""} {
      puts "{$text}"
      if {$text in {me {}}} {
        if {![catch {dict get $data nick} nick]} {
          set username $nick
        }
        set silph(listen) [list [list $userId $channelId $guildId] $username]
        after 3000 {set silph(listen) ""}
        ::meta::putdc [dict create content \
          "It doesn't seem like you have linked your silph profile. Would you like to do it now?"] 0
      } else {
        ::meta::putdc [dict create content \
          "It doesn't seem like this user has linked their silph profile."] 0
      }
      return
    }
  } else {
    set silphacc $text
  }
  
  set token [::http::geturl "$silph(site)$silphacc.json"]
  
  set status [::http::status $token]
  switch $status {
    ok {
      set silphdata [::http::data $token]
      set silphdict [::json::json2dict $silphdata]
      if {[lindex [dict keys $silphdict] 0] == "error"} {
        set msg [dict create content "No such user named $silphacc found on sil.ph"]
      } else {
        set title      [dict get $silphdict data title]
        set level      [dict get $silphdict data trainer_level]
        set team       [dict get $silphdict data team]
        set style      [dict get $silphdict data playstyle]
        set usrname    [dict get $silphdict data in_game_username]
        set goal       [dict get $silphdict data goal]
        set home       [dict get $silphdict data home_region]
        set cardid     [dict get $silphdict data card_id]
        set modified   [dict get $silphdict data modified]
        set socials    [dict get $silphdict data socials]
        set joined     [dict get $silphdict data joined]
        set badges     [llength [dict get $silphdict data badges]]
        set checkins   [llength [dict get $silphdict data checkins]]
        set handshakes [dict get $silphdict data handshakes]
        set migrations [dict get $silphdict data nest_migrations]
        set pokedex    [dict get $silphdict data pokedex_count]
        set raids      [dict get $silphdict data raid_average]
        set avatar     [dict get $silphdict data avatar]
        
        switch $team {
          Mystic {set colour "blue"}
          Valor {set colour "red"}
          Instinct {set colour "yellow"}
        }
        foreach social $socials {
          switch [dict get $social vendor] {
            "Discord" {
              set discord ":ballot_box_with_check: Connected to Discord: [dict get $social username]"
            }
            "Reddit" {
              set reddit ":ballot_box_with_check: Connected to Discord: [dict get $social username]"
            }
            default {lassign [list "" ""] discord reddit}
          }
        }
        if {![info exists discord]} {set discord ""}
        
        set msg [dict create embed [dict create \
          author [dict create \
            name "$title $usrname" \
            url "$silph(site)$silphacc.json" \
            icon_url "https://i.imgur.com/fn9E5nb.png" \
          ] \
          thumbnail [dict create \
            url "$avatar" \
          ] \
          fields [list \
            [dict create \
              name Playstyle \
              value "$style, working on $goal.\nActive around $home.\n\n$discord" \
            ] \
            [dict create \
              name "__Silph Stats__" \
              value "**Joined:** $joined\n**Badges:** $badges\n**Check-ins:** $checkins\n**Handshakes:** $handshakes\n**Migrations:** $migrations" \
              inline true \
            ] \
            [dict create \
              name "__Game Stats__" \
              value "**Name:** $usrname\n**Team:** $team\n**Level:** $level\n**Pokedex:** $pokedex\n**Avg raids/week:** $raids" \
              inline true \
            ] \
          ] \
          footer [dict create \
            text "Silph Road Travelers Card - ID$cardid - Last updated $modified" \
            icon_url "https://assets.thesilphroad.com/img/snoo_sr_icon.png" \
          ] \
          color "$colour"\
        ]]
      }
    }
    error {
      set error [::http::error $token]
      set msg [dict create content \
        "Error: Could not retrieve data from sil.ph. Error: $error"]
    }
    default {
      set msg [dict create content \
        "Error: Could not retrieve data from sil.ph. Status: $status"]
    }
  }
  
  ::http::cleanup $token
  ::meta::putdc $msg 0
}

proc pogo::getBadges {} {
  package require Img

  set images [glob *.png]
  set imgNames [list]
  set out [image create photo]
  set point 0

  foreach image $images {
    set img [image create photo -file $image]
    set height [image height $img]
    set width [image width $img]
    for {set x 0} {$x < $width} {incr x} {
      for {set y 0} {$y < $height} {incr y} {
        set data [$img data -from $x $y [expr {$x+1}] [expr {$y+1}]]
        set transparency [$img transparency get $x $y]
        $out put $data -to [expr {$x+$point}] [expr {$y}] [expr {$x+1+$point}] [expr {$y+1}]
        $out transparency set [expr {$x+$point}] [expr {$y}] $transparency
      }
    }
    incr point $width
  }

  $out write a.png -format png
}