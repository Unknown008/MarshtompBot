namespace eval custom {
  sqlite3 customdb "${scriptDir}/customdb.sqlite3"
  customdb eval {
    CREATE TABLE IF NOT EXISTS animefavs(
      userId text,
      animeName text,
      custom text
    )
  }
  customdb eval {
    CREATE TABLE IF NOT EXISTS latestanime(
      animeName text,
      date bigint
    )
  }
  
  customdb eval {
    CREATE TABLE IF NOT EXISTS serebii(
      id text,
      title text,
      article text,
      date text
    )
  }
  
  customdb eval {
    CREATE TABLE IF NOT EXISTS serebiimsgs(
      channelId text,
      id text,
      msgId text,
      date text
    )
  }
  
  variable scrapper
  set scrapper(site)             "http://www.gogoanime.to"
  set scrapper(delay)            5
  set scrapper(news)             "https://www.serebii.net"
  set scrapper(limit-anime)      500
  set scrapper(limit-news)       100
  set scrapper(limit-newsbuffer) 500
  
  variable say
  set say(state)    0
  set say(speaker)  ""
  set say(sourceId) ""
  set say(targetId) ""
  
  package require htmlparse
}

proc custom::command {} {
  upvar data data text text channelId channelId guildId guildId userId userId
  switch [lindex $text 0] {
    "!hp" {
      hp_calc [regsub {!hp *} $text ""]
    }
    "!8ball" {
      ball $guildId [regsub {!8ball *} $text ""]
    }
    "!status" {
      #pro:status [regsub {!status } $text ""]
    }
    "!subscribe" {
      subscribe [regsub {!subscribe *} $text ""]
    }
    "!unsubscribe" {
      unsubscribe [regsub {!unsubscribe *} $text ""]
    }
    "!viewsubs" {
      viewsubs
    }
    "!whois" {
      whois [regsub {!whois *} $text ""]
    }
    "!say" {
      say {*}[regsub {!say *} $text ""]
    }
    default {return 0}
  }
  return 1
}

proc custom::say {type {text {}}} {
  upvar channelId sourceId userId userId
  variable say
  switch $type {
    begin -
    start {
      if {$userId != $::ownerId || $say(state) != 0} {return}
      # Verify speak perm in targetId
      set say(state)    1
      set say(sourceId) $sourceId
      set say(targetId) $text
      set say(speaker)  $userId
      ::meta::putdc [dict create content "Chat session started!"] 0
    }
    say {
      if {$say(state) != 1} {return}
      if {$sourceId == $say(sourceId) && $say(speaker) == $userId} {
        set attachment [dict get $text attachment]
        set content [dict get $text content]
        if {$attachment ne ""} {
          set links [lmap x $attachment {dict get $x url}]
          set msg "$content: [join $links {,}]"
        } else {
          set msg $content
        }
        ::meta::putdc [dict create content $msg] 1 $say(targetId)
      } elseif {$sourceId == $say(targetId)} {
        upvar guildId guildId
        set attachment [dict get $text attachment]
        set content [dict get $text content]
        set user [dict get [set ${::session}::users] $userId username]
        if {![catch {dict get [set ${::session}::users] $userId nick $guildId} nick]} {
          if {$nick != ""} {
            set user "$user ($nick)"
          }
        }
        if {$attachment ne ""} {
          set links [lmap x $attachment {dict get $x url}]
          set msg "$content: [join $links {,}]"
        } else {
          set msg $content
        }
        ::meta::putdc [dict create content "$user: $msg"] 1 $say(sourceId)
      }
    }
    end {
      if {$userId != $::ownerId || $say(state) != 1} {return}
      set say(state)    0
      set say(sourceId) 0
      set say(targetId) 0
      set say(speaker)  ""
      ::meta::putdc [dict create content "Chat session ended!"] 0
    }
    default {return}
  }
}

proc custom::hp_calc {msg} {
  set elems [split $msg]
  if {[llength $elems] != 6} {
    ::meta::putdc [dict create content \
      "Invalid number of stats. Should be **HP Atk Def Spd SpA SpDef**." \
    ] 0
    return
  } elseif {![regexp {^\d+(?: \d+){5}$} $msg]} {
    ::meta::putdc [dict create content \
      "Non-numerical values supplied. Please only provide numerical values." \
    ] 0
    return
  }
  
  set sumT 0
  set sumD 0
  set i 0
  foreach s $elems {
    if {$s % 2} {set sumT [expr {$sumT+(2**$i)}]}
    if {$s % 4 > 1} {set sumD [expr {$sumD+(2**$i)}]}
    incr i
  }
  set resT [expr {$sumT*15/63}]
  set types [list Fighting Flying Poison Ground Rock Bug Ghost Steel Fire \
    Water Grass Electric Psychic Ice Dragon Dark]
  
  ::meta::putdc [dict create content "**Type:** [lindex $types $resT]"] 0
}

proc custom::ball {guildId arg} {
  set usage "Ask a question a 'yes/no', 'where', 'who', 'when', 'why' or 'how much' question."
  if {$arg == ""} {
    ::meta::putdc [dict create content "**8-ball** usage: $usage"]
    return
  } elseif {![regexp {[?]} $arg match]} {
    ::meta::putdc [dict create content \
      "**Error:** That's not a question! You are missing the question mark!" \
    ]
    return
  }
  switch -nocase -regexp -- $arg {
    "where" -
    "who" -
    "when" -
    "why" -
    "how (?:much|many)" {
      ::meta::putdc \
        [dict create content [throw_ball $guildId $arg]] 1
    }
    "what" -
    "how" -
    "which" {
      ::meta::putdc [dict create content \
        "**8-ball**: Sorry, I can't answer such questions. $usage" \
      ] 1
    }
    default {
      ::meta::putdc \
        [dict create content [throw_ball $guildId yesno]] 0
    }
  }
}

proc custom::throw_ball {guildId type} {
  switch $type {
    "where" {
      set lanswer [list \
        "In your country." \
        "Somewhere near you." \
        "It's not anywhere near to you." \
        "Behind you!" \
        "It's right under your nose..." \
        "It's so far away that it looks like a tiny dot." \
        "I don't know." \
        "I will most probably know soon, but as of now..." \
        "My sources tell me somewhere within a kilometre from you." \
      ]
    }
    "why" {
      set lonlines [dict get [set ${::session}::guilds] $guildId presences]
      set ids [lmap user $lonlines {set id "<@[lindex $user 1 1]>"}]
      set name "<@[lindex $ids [expr {int(rand()*[llength $ids])}]]>"
      set lanswer [list \
        "You haven't eaten enough cheese." \
        "Because, just because. Don't even think about questioning it." \
        "Why do you even question it?" \
        "I don't know, ask $name." \
        "I'm sure you can find the answer deep within yourself." \
        "Do you feel insulted?" \
        "Do you like cheese?" \
        "Why? Wynaut?" \
        "Don't you dare asking me why!" \
      ]
    }
    "who" {
      set lonlines [dict get [set ${::session}::guilds] $guildId presences]
      set lanswer [lmap user $lonlines {set id "<@[lindex $user 1 1]>"}]
    }
    "howmuch" {
      set lanswer [list \
        "Loads." \
        "Zero." \
        "A dozen." \
        "Only one." \
        "A pair." \
        "Triplets!" \
        "Two dozen" \
        "Over a million!" \
        "I think you already know the answer." \
        "My sources tell me 42." \
        "My sources tell me 1337." \
      ]
    }
    "when" {
      set lanswer [list \
        "Soon." \
        "NOW!" \
        "It won't happen any time soon." \
        "Yesterday." \
        "Two days ago." \
        "Tomorrow." \
        "In a century." \
        "Last week." \
        "Next week." \
        "It just happened." \
        "In a few hours." \
        "Last century." \
      ]
    }
    "yesno" {
      set lanswer [list \
        "Yes." \
        "Outlook good." \
        "Signs point to yes." \
        "Most likely." \
        "Certainly." \
        "Most probably yes." \
        "My sources say yes." \
        "It's simple, the answer is, yes!" \
        "As I see it, the answer is yes." \
        "You may rely on it." \
        "Without a doubt." \
        "Cannot predict now... try again later." \
        "I think you already know the answer." \
        "I better not tell you now." \
        "Concentrate then ask again later." \
        "Eat more cheese then ask again." \
        "Outlook hazy, try again." \
        "Focus on your inner self and you will find the anwer." \
        "Well, who knows?" \
        "Sorry, I'm busy sorting my Pok\u00E9mon figurines. Ask later." \
        "You have pretty eyes, you know that?" \
        "Noo! You ruined my winning streak!" \
        "No." \
        "Outlook not very good." \
        "Signs point to no." \
        "Most probably not." \
        "Unlikely." \
        "Certainly not!" \
        "Highly improbable..."
        "My sources say no." \
        "Can't you see that's a no?" \
        "In your dreams maybe." \
        "Don't count on it." \
      ]
    }
  }
  return [lindex $lanswer [expr {int(rand()*[llength $lanswer])}]]
}

proc pro:status {args} {
  set link "https://pokemonrevolution.net/status.php"

  set token [::http::geturl $link]
  set file [::http::data $token]
  ::http::cleanup $token
  set res [regexp -all -inline {<div id="status-[^\"]"[^>]*>.*?([^<>]+)</h1>} $file]
  if {$res == "" || [llength $res] != 2} {
    putdc "Unable to reach website"
  } else {
    switch -glob [lindex $args 0] {
      s* {::meta::putdc "Silver server is [string tolower [lindex $res 0]]."}
      g* {::meta::putdc "Gold server is [string tolower [lindex $res 0]]."}
      default {::meta::putdc "Silver server is [string tolower [lindex $res 0]].\nGold server is [string tolower [lindex $res 0]]."}
    }
  }
}

proc custom::checksite {} {
  variable scrapper
  
  if {[catch {::http::geturl $scrapper(site)} token]} {
    after [expr {$scrapper(delay)*60*1000}] ::custom::checksite
    return
  }
  set token [::http::geturl $scrapper(site)]
  set file [::http::data $token]
  ::http::cleanup $token
  
  if {![regexp -- {<td class="redgr" width="369" valign="top">(.*?)</td>} $file - match]} {
    after [expr {$scrapper(delay)*60*1000}] ::custom::checksite
    return
  }
  set results [regexp -all -inline -- {<li>(.*?)</li>} $match]
  
  set new [list]
  foreach {main sub} $results {
    set epname [string trim [regsub -all -- {<[^>]+>} $sub ""]]
    regexp -- {<a href="([^\"]+)">} $sub - link
    lappend new "$epname (link: $link)"
  }
  set current [customdb eval {SELECT 1 FROM latestanime LIMIT 1}]
  set now [clock scan now]
  if {$current != 1} {
    foreach ep $new {
      customdb eval {INSERT INTO latestanime VALUES(:ep, :now)}
    }
  } else {
    foreach ep $new {
      set old [customdb eval {SELECT 1 FROM latestanime WHERE animeName = :ep}]
      if {$old != 1} {
        regexp {(.+) \(link: (http[^\)]+)} $ep - title link
        switch -nocase -glob $title {
          *(raw) {set rep ":regional_indicator_r: :regional_indicator_a: :regional_indicator_w:"}
          *(sub) {set rep ":regional_indicator_s: :regional_indicator_u: :regional_indicator_b:"}
          *(preview) {set rep ":regional_indicator_p: :regional_indicator_r: :regional_indicator_e: :regional_indicator_v:"}
          default {set rep {\1}}
        }
        regsub -nocase {\((?:raw|sub|preview)\)} $title $rep title
        regsub -nocase {\((?:raw|sub|preview)\)} $ep $rep fmt
        metadb eval {SELECT channelId FROM config WHERE type = 'anime'} arr {
          ::meta::putdc [dict create content [::htmlparse::mapEscapes $fmt]] 1 \
          $arr(channelId)
        }
        set imgFound 0
        customdb eval {SELECT * FROM animefavs} arr {
          if {!$imgFound} {
            set token [::http::geturl $link]
            set body [::http::data $token]
            ::http::cleanup $token
            if {[regexp -- {<strong>Category:</strong> <a href="([^\"]+)"} $body - category]} {
              set token [::http::geturl $category]
              set body [::http::data $token]
              ::http::cleanup $token
              if {$category eq "$scrapper(site)/category/others/anime-movies"} {
                set re [format {<a [^>]*%s[^>]+><img [^>]*src="([^\"]+)"} $link]
              } else {
                set re {<img class="[^\"]+" style="[^\"]+" src="([^\"]+)"}
              }
              regexp -- $re $body - image
              set image "$scrapper(site)$image"
              set imgFound 1
            }
          }
          if {[string first $arr(animeName) $ep] > -1} {
            if {$arr(custom) ne "" && [regexp {(.+) > (.+)} $arr(custom) - f t]} {
              regsub $f $link $t link
            }
            if {$imgFound} {
              coroutine ::meta::putdcPM[::id] ::meta::putdcPM $arr(userId) \
                [dict create embed [dict create \
                   url $link \
                   type link \
                   title [encoding convertto utf-8 [::htmlparse::mapEscapes $title]] \
                   image [dict create url $image] \
                ]]
            } else {
              coroutine ::meta::putdcPM[::id] ::meta::putdcPM $arr(userId) \
                [dict create embed [dict create \
                   url $link \
                   type link \
                   title [encoding convertto utf-8 [::htmlparse::mapEscapes $title]] \
                ]]
            }
          }
        }
        customdb eval {INSERT INTO latestanime VALUES(:ep, :now)}
      }
    }
  }
  
  set len [customdb eval {SELECT COUNT(*) FROM latestanime}]
  while {$len > $scrapper(limit-anime)} {
    set earliest [customdb eval {SELECT MIN(date) FROM latestanime}]
    customdb eval {DELETE FROM latestanime WHERE date = :earliest}
    set len [customdb eval {SELECT COUNT(*) FROM latestanime}]
  }
  
  after [expr {$scrapper(delay)*60*1000}] ::custom::checksite
}

proc custom::subscribe {animeName} {
  upvar userId userId
  if {[string first "-format" $animeName] > -1} {
    regexp {^(.+?) -format (.+?)$} $animeName - name format
    if {![regexp {(.+) > (.+)} $format - f t]} {
      ::meta::putdc [dict create content \
        "Invalid format. The format should be like: ```css\nfrom > to```."] 0
      return
    }
    if {[catch {regsub $f "test" $t} err]} {
      ::meta::putdc [dict create content \
        "Error with the regular expression: $err"] 0
      return
    }
  } else {
    lassign [list $animeName ""] name format
  }
  set subs [customdb eval {
    SELECT animeName, custom FROM animefavs WHERE animeName = :name
  }]
  if {[llength $subs] > 0} {
    lassign $subs cName cFormat
    if {$format eq "" && $cFormat eq ""} {
      set msg "You already are subscribed for $name!"
    } else {
      customdb eval {UPDATE animefavs SET custom = :format WHERE animeName = :name}
      set msg "Your subscription for $name has been updated!"
    }
  } else {
    customdb eval {INSERT INTO animefavs VALUES(:userId, :name, :format)}
    set msg "You have been subscribed for $name!"
  }
  ::meta::putdc [dict create content $msg] 1
}

proc custom::unsubscribe {animeName} {
  upvar userId userId
  set result [customdb eval {
    SELECT * FROM animefavs WHERE userId = :userId AND animeName = :animeName
  }]
  if {[llength $result] == 0} {
    if {$animeName eq "all"} {
      customdb eval {
        DELETE FROM animefavs WHERE userId = :userId
      }
      set msg "You have been unsubscribed for all anime!"
    } else {
      set msg "No such subscriptions was found..."
    }
  } else {
    customdb eval {
      DELETE FROM animefavs WHERE userId = :userId AND animeName = :animeName
    }
    set msg "You have been unsubscribed for $animeName!"
  }
  ::meta::putdc [dict create content $msg] 1
}

proc custom::viewsubs {} {
  upvar userId userId
  set results [customdb eval {
    SELECT animeName, custom FROM animefavs WHERE userId = :userId
  }]
  if {[llength $results] == 0} {
    set msg "You have no subscriptions."
  } else {
    set msg "You are subscribed to the following:```"
    foreach {name custom} $results {
      if {$custom eq ""} {
        append msg "\n- $name"
      } else {
        append msg "\n- $name ($custom)"
      }
    }
    append msg "```"
  }
  ::meta::putdc [dict create content $msg] 1
}

proc custom::whois {text} {
  upvar guildId guildId userId userId
  set members [dict get [set ${::session}::guilds] $guildId members]
  
  if {[regexp {^<@!?([0-9]+)>$} $text - user]} {
    set data [lsearch -inline $members "*$user*"]
  } elseif {[string tolower $text] == "me"} {
    set data [lsearch -inline -regexp $members "\\y$userId\\y"]
    set text "<@$userId>"
  } else {
    set data [lsearch -inline -nocase $members "*$text*"]
  }
  
  if {$data == ""} {
    ::meta::putdc [dict create content "No such user found."] 0
  } else {
    set username [dict get $data user username]
    set id [dict get $data user id]
    set avatar [dict get $data user avatar]
    if {$avatar == "null"} {
      set avatar ""
    } else {
      set avatar "https://cdn.discordapp.com/avatars/$id/$avatar.png"
    }
    if {[catch {dict get $data user bot}]} {
      set type "User"
    } else {
      set type "Bot"
    }
    
    set roles [lmap role [dict get $data roles] {
      set r [dict get [set ${::session}::guilds] $guildId roles]
      set role [dict get [lsearch -inline $r "*id $role*"] name]
    }]
    set roles [join $roles ", "]
    if {$roles == ""} {set roles "*None*"}
 
    set joined_at [clock format [clock scan \
      [string range [dict get $data joined_at] 0 18] \
      -timezone UTC -format "%Y-%m-%dT%T"] -format "%a %d %b %Y %T UTC" \
      -timezone UTC]
    set datecreated [clock format [expr {
      [getSnowflakeUnixTime $id $::discord::Epoch]/1000
    }] -format "%a %d %b %Y %T UTC" -timezone UTC]
    ::meta::putdc [dict create embed \
      [dict create \
        title $type \
        description "$text is $username\nCreated on $datecreated\nRole(s): $roles\n" \
        footer [dict create text "$username is a member of the server since $joined_at"] \
        thumbnail [dict create url $avatar] \
      ] \
    ] 0
  }
}

proc custom::wave {channelId} {
  ::meta::putdc [dict create content "\\o"] 0 $channelId
}

proc custom::checknews {} {
  variable scrapper
  
  if {[catch {::http::geturl "$scrapper(news)/index2.shtml"} token]} {
    after [expr {$scrapper(delay)*60*1000}] ::custom::checknews
    return
  }
  set file [::http::data $token]
  ::http::cleanup $token
  
  set posts [regexp -inline -all -- {<div class="post">((?:<div(?:(?!</div>).)+</div>|(?!</div>).)+)</div>} $file]
  
  if {$posts == ""} {
    after [expr {$scrapper(delay)*60*1000}] ::custom::checknews
    return
  }
  set lnews [list]
  set ledits [list]
  set cmds [list]
  set now [clock scan now]
  set first [customdb eval {SELECT 1 FROM serebii LIMIT 1}]
  foreach {m post} $posts {
    regexp -- {<a href[^>]* id="([^\"]+)"[^>]*>} $post - id
    set matches [regexp -inline -all -- {<p class="title"[^>]*?>([^<]*?)</p>\s*?<p>(.*?)</p>} $post]
    set articles [dict create]
    foreach {m title text} $matches {
      if {[dict exists $articles $title]} {
        dict set articles $title "[dict get $articles $title]\n\n$text"
      } else {
        dict set articles $title $text
      }
    }
    set current 0
    dict for {title text} $articles {
      set dayarticles [customdb eval {
        SELECT article FROM serebii WHERE id = :id LIMIT 1
      }]
      
      if {$dayarticles == "" || $current} {
        customdb eval {INSERT INTO serebii VALUES (:id, :title, :text, :now)}
        if {$first != ""} {
          set pos [lsearch -index 1 $lnews $id]
          if {$pos > -1} {
            lset lnews 0 3 [list {*}[lindex $lnews 0 3] [list \
              name [encoding convertto utf-8 $title] \
              value [encoding convertto utf-8 [htmlCleanup $text]] \
            ]]
          } else {
            lappend lnews [dict create \
              title $id fields [list [dict create \
              name [encoding convertto utf-8 $title] \
              value [encoding convertto utf-8 [htmlCleanup $text]] \
            ]]]
          }
          if {"::custom::newsUpdate $id" ni $cmds} {
            lappend cmds "::custom::newsUpdate $id"
          }
        }
        set current 1
      } else {
        set result [customdb eval {
          SELECT article FROM serebii WHERE id = :id AND title = :title LIMIT 1
        }]
        set result [lindex $result 0]
        if {$result == ""} {
          customdb eval {INSERT INTO serebii VALUES (:id, :title, :text, :now)}
        } elseif {$result != $text} {
          customdb eval {
            UPDATE serebii SET article = :text WHERE id = :id AND title = :title
          }
        } else {
          continue
        }
        set fields ""
        customdb eval {SELECT title, article FROM serebii WHERE id = :id} arr {
          lappend fields [dict create \
            name [encoding convertto utf-8 $arr(title)] \
            value [encoding convertto utf-8 [htmlCleanup $arr(article)]] \
          ]
        }
        set pos [lsearch -index 1 $ledits $id]
        if {$pos > -1} {
          lset ledits $pos [dict create title $id fields $fields]
        } else {
          lappend ledits [dict create title $id fields $fields]
        }
      }
    }
  }

  metadb eval {SELECT channelId FROM config WHERE type = 'serebii'} arr {
    foreach news $lnews {
      customdb eval " \
        INSERT INTO serebiimsgs \
        VALUES (:arr(channelId),'[dict get $news title]','',:now) \
      "
      coroutine ::meta::putdc[::id] ::meta::putdc [dict create embed $news] 0 \
        $arr(channelId) [list {*}$cmds]
    }
    foreach edits $ledits {
      set id [dict get $edits title]
      customdb eval {
        SELECT msgId FROM serebiimsgs
        WHERE channelId = :arr(channelId)
        AND id = :id
        AND msgId <> ''
      } barr {
        ::meta::editdc [dict create embed $edits] 0 $barr(msgId) $arr(channelId)
      }
    }
  }
    
  set len [customdb eval {SELECT COUNT(*) FROM serebii}]
  while {$len > $scrapper(limit-news)} {
    set earliest [customdb eval {SELECT MIN(date) FROM serebii}]
    customdb eval {DELETE FROM serebii WHERE date = :earliest}
    set len [customdb eval {SELECT COUNT(*) FROM serebii}]
  }
  
  set len [customdb eval {SELECT COUNT(*) FROM serebiimsgs}]
  while {$len > $scrapper(limit-newsbuffer)} {
    set earliest [customdb eval {SELECT MIN(date) FROM serebiimsgs}]
    customdb eval {DELETE FROM serebiimsgs WHERE date = :earliest}
    set len [customdb eval {SELECT COUNT(*) FROM serebiimsgs}]
  }
  
  after [expr {$scrapper(delay)*60*1000}] ::custom::checknews
}

proc custom::newsUpdate {id args} {
  upvar data data channelId channelId
  set msgId [dict get $data id]
  customdb eval {
    UPDATE serebiimsgs SET msgId = :msgId
    WHERE id = :id AND channelId = :channelId
  }
}

proc custom::htmlCleanup {text} {
  # Replace newlines
  regsub -all {<[^>]*br[^>]*>} $text "\n" text
  
  # Replace formatting
  # Underline
  regsub -all {<u>((?:(?!</u>).)+)</u>} $text {*\1*} text
  # Bold
  regsub -all {<b>((?:(?!</b>).)+)</b>} $text {**\1**} text
 
  # URLs
  regsub -all {<a (?:[^>]* )?href="([^\"]*)"[^>]*>((?:(?!</a>).)+)</a>} $text \
    {[urlCleanup "\2" "\1"]} text
  
  # Remove all other html
  regsub -all {<[^>]+>} $text {} text
  
  set text [subst -novariables $text]
  
  return $text
}

proc custom::urlCleanup {text url} {
  variable scrapper
  if {[string first "http" $url] == -1} {
    set url "$scrapper(news)$url"
  }
  if {$text == ""} {set text "Link"}
  return "\[$text\]($url)"
}

#after 100000 [list ::custom::checksite]
after 50000 [list ::custom::checknews]

puts "custom.tcl loaded"