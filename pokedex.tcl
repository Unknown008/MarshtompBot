##
# Pokedex Mode
##
namespace eval pokedex {
  variable pokedex
  set pokedex(ver)      "0.3"
  set pokedex(usage)    "Usage: !pokedex ?next|search? \[pokemon\]"
  set pokedex(logo)     "**-Pok\u00E9dex-**"
  set pokedex(gen)      6
  set pokedex(restrict) [list]
  
  variable ability
  set ability(ver)      "0.1"
  set ability(usage)    "Usage: !ability \[ability\]"
  set ability(logo)     "**-Abilitydex-**"
  set ability(error)    ""
  
  sqlite3 dex pokedexdb
}

### Procedures
proc pokedex::command {} {
  upvar data data text text channelId channelId guildId guildId userId userId
  switch [lindex $text 0] {
    "!pokedex" {
      pokedex [regsub {!pokedex } $text ""]
    }
    "!ability" {
      ability [regsub {!ability } $text ""]
    }
    "!move" {
      move [regsub {!move } $text ""]
    }
    "!item" {
      item [regsub {!item } $text ""]
    }
    default {
      return 0
    }
  }
  return 1
}

proc pokedex::pokedex {args} {
  variable pokedex
  set args [lindex $args 0]
  switch [lindex $args 0] {
    search {
      set arg [lindex $args 1]
      set result [search [join $arg { }]]
    }
    next {
      set arg [lassign $args type]
      set result [get_pokemon $type [join $arg { }]]
    }
    random {
      set flags [lassign $args cmd num]
      set result [random $num {*}$flags]
    }
    query {
      upvar userId userId
      if {$userId != $::ownerId} {return}
      set arg [lindex $args 1]
      set result [query $arg]
      ::meta::putdc [dict create content "```$result```"] 1
      return
    }
    default {
      if {[llength $args] == 0} {
        ::meta::putdc [dict create content $pokedex(usage)] 1
        return
      }
      set result [get_pokemon normal [join $args { }]]
    }
  }
  set result [lindex [lassign $result mode] 0]
  switch $mode {
    0 {
      ::meta::putdc $result 1
    }
    1 {
      set result [dict set result content $pokedex(logo)]
      ::meta::putdc $result 1
    }
    2 {
      set prefix "$pokedex(logo) Results: "
      set suffix ","
      for {set i 0} {[llength $result] > $i} {incr i 100} {
        if {$i > 0} {set prefix ""}
        if {[expr {$i+50}] >= [llength $result]} {
          set idx end
          set suffix ""
        } else {
          set idx [expr {$i+39}]
        }
        set group [lrange $result $i $idx]
        ::meta::putdc [dict create content \
          "$pokedex(logo) Results: [join $group {, }] $suffix"] 1
      }
    }
  }
}

proc pokedex::get_pokemon {state arg} {
  variable pokedex
  # modes
  # 0 - no results found
  # 1 - results obtained
  set mode 0
  set table pokeDetails$pokedex(gen)
  set result [dex eval "\
    SELECT * FROM $table WHERE lower(formname) = lower('$arg') \
  "]
  if {[llength $result] > 0} {
    set mode 1
    lassign $result id pokemon formname type genus ability ability2 hability \
      gender egggroup height weight legend evolve_cond hp atk def spatk spdef \
      spd capture final stage effort hatch_counter happiness exp forms colour \
      base_exp

    if {$state eq "normal"} {
      if {$ability2 ne ""} {append ability "/$ability2"}
      if {$hability ne ""} {append ability "/*$hability*"}
      set total [expr {$hp+$atk+$def+$spatk+$spdef+$spd}]
      
      return [list $mode [dict create embed [dict create \
        title "$id: $formname" \
        description "**Type:** $type\n**Abilities:** $ability\n**Stats (HP/Atk/Def/SpA/SpD/Spd):** $hp/$atk/$def/$spatk/$spdef/$spd (Total: $total)" \
      ]]]
    } elseif {$state eq "next"} {
      set quart ""
      
      while {$effort != 0} {
        set mod [expr {$effort%4}]
        set effort [expr {$effort/4}]
        set quart "$mod$quart"
      }
      set quart [string range [string reverse [format %06d $quart]] 0 5]
      lassign [split $quart ""] hp atk def spd satk sdef
      
      if {$gender ne "N/A"} {
        lassign [split $gender "/"] mr fr
        set gender "$mr/$fr"
      }
      set grw [lindex {"Medium fast" "Slow then very fast" \
        "Fast then very slow" "Medium slow" "Fast" "Slow"} $exp]
      set texp [lindex {"1,000,000" "600,000" "1,640,000" "1,059,860" \
        "800,000" "1,250,000"} $exp]
      return [list $mode [dict create embed [dict create \
        title "**$id:** $formname ($genus Pokémon)" \
        description "**Egg Group:** $egggroup\n**EV yield (HP/Atk/Def/SpA/SpD/Spd):** $hp/$atk/$def/$satk/$sdef/$spd\n**Biometrics:** $height m, $weight kg\n**Catch rate:** $capture\n**Base Happiness:** $happiness\n**Gender ratio (M/F):** $gender\n**Exp yield:** $base_exp\n**Growth Rate:** $grw\n**Max Exp:** $texp" \
      ]]]
    }
  } else {
    return [list $mode [dict create content "No matched results found"]]
  }
}

proc pokedex::search {arg} {
  variable pokedex
  # modes
  # 0 - no results found
  # 1 - results obtained
  # 2 - list of Pokemon as results
  set mode 0
  set table "pokeDetails$pokedex(gen)"
  set fields {
    id pokemon formname type genus ability ability2 hability gender egggroup 
    height weight legend evolve_cond hp atk def spatk spdef spd capture final 
    stage effort hatch_counter happiness exp forms colour base_exp pre_evos
  }
  set query [dex eval "SELECT * FROM $table"]
  set result ""
  foreach $fields $query {
    if {[regexp -nocase -- $arg [join [lmap x $fields {set $x}] " "]]} {
      lappend result $formname
      set mode 2
    } elseif {$pokemon == "Bulbasaur"} {
    }
  }
  if {!$mode} {
    return [list $mode [dict create content "No matched results found"]]
  } else {
    return [list $mode $result]
  }
}

proc pokedex::random {number args} {
  variable pokedex
  if {$number == ""} {set number 1}
  puts $number
  if {!($number > 0 && $number < 13)} {
    return [list 0 "The maximum random number of Pokémon that can be picked is 12"]
  }
  set condition [list]
  
  foreach {flag param} $args {
    switch -nocase -glob $flag {
      -region {
        set conds [list]
        set regions [regexp -all -inline -nocase -- {[a-z]+} $param]
        foreach reg $regions {
          switch -nocase -glob $reg {
            kan* {lappend conds "(id >= '#001' AND id < '#152')"}
            joh* {lappend conds "(id >= '#152' AND id < '#252')"}
            hoe* {lappend conds "(id >= '#252' AND id < '#387')"}
            sin* {lappend conds "(id >= '#387' AND id < '#495')"}
            uno* {lappend conds "(id >= '#495' AND id < '#650')"}
            kal* {lappend conds "(id >= '#650' AND id < '#722')"}
            alo* {lappend conds "(id >= '#722' AND id < '#999')"}
            default {return [list 0 "Invalid region parameter. Must be in the format \"Kanto\" or \"Kanto|Johto|etc\""]}
          }
        }
        lappend condition "([join $conds { OR }])"
      }
      -final {
        if {$param ni {0 1}} {return [list 0 "Invalid stage parameter. Must be 0 or 1"]}
        lappend condition "final = $param"
      }
      -legend* {
        if {$param ni {0 1}} {return [list 0 "Invalid legendary parameter. Must be 0 or 1"]}
        lappend condition "legend = $param"
      }
    }
  }
  if {[llength $condition] > 0} {
    set condition " WHERE [join $condition { AND }]"
  }
  set table pokeDetails$pokedex(gen)
  set query [dex eval "SELECT formname FROM $table$condition"]
  set result ""
  set size [llength $query]

  for {set i 1} {$i <= $number} {incr i; incr size -1} {
    set done 0
    while {!$done} {
      set rseed [expr {int(rand()*65535)}]
      if {$rseed} {set done 1}
    }
    set newrand [expr {srand($rseed)}]
  
    set pokemon [expr {int(rand()*$size)+1}]
    lappend result [lindex $query $pokemon]
    set query [lreplace $query $pokemon $pokemon]
  }
  
  return [list 2 $result]
}

proc pokedex::query {query} {
  variable pokedex
  if {[regexp -all -nocase -- {\y(?:ALTER|UPDATE|INTO|CREATE|INSERT)\y} $query]} {
    return [list 0 [dict create content "Data manipulation queries are not supported"]]
  }
  if {[catch {dex eval $query} res]} {
    return [list 0 [dict create content $res]]
  } elseif {$res == ""} {
    return [list 0 [dict create "No results were obtained."]]
  } else {
    set results ""
    set cols [list]
    dex eval $query values {lappend cols $values(*); break}
    set top [lindex $cols 0]
    lappend results $top
    
    foreach $top $res {
      set vals [lmap x $top {set $x}]
      lappend results $vals
    }
    
    set limit 5
    set maxes [list]
    for {set col 0} {$col < [llength [lindex $results 0]]} {incr col} {
      set max 0
      for {set row 0} {$row < [llength $results]} {incr row} {
        set size [string length [lindex $results $row $col]]
        if {$size > $max} {set max $size}
        if {$row >= $limit} {break}
      }
      lappend maxes "%-[expr {$max+2}]s"
    }
    set output [list]
    for {set row 0} {$row < [llength $results]} {incr row} {
      lappend output "[format [join $maxes { }] {*}[lindex $results $row]]"
      if {$row >= $limit} {break}
    }
    return [list 0 [dict create content ```[join $output "\n"]```]]
  }
}

##
# Abilitydex Mode
##

### Procedures
proc pokedex::ability {arg} {
  variable pokedex
  variable ability

  set args [split $arg]
  switch [lindex $args 0] {
      search {
      set arg [lindex $args 1]
      ::meta::putdc [search_ability $arg]
    }
    default {
      ::meta::putdc [get_ability $arg]
    }
  }
}

proc pokedex::get_ability { arg } {
  variable ability
  if {[llength $arg] < 1} {
    return $ability(usage)
  } 
  set value 0
  set ability [string tolower $arg]
  set data [open $abilityfile r]
  while { [gets $data line] != -1 } {
    if {([string tolower [lindex [split $line "@"] 0]] == $ability)} {
      set ability [lindex [split $line "@"] 0]
      set description [lindex [split $line "@"] 1]
      set value 1
      break
    }
  }
  close $data
  if {!$value} {return [format $ability(error) "No matched results found"]}
  return "**$ability(logo)**: $description"
}

proc pokedex::search_ability {nick host hand chan arg} {
  variable ability
  if {$chan == ""} {set chan $nick}
  set value 0
  set result ""
  set data [open $abilityfile r]
  while { [gets $data line] != -1 } {
    if {[regexp -all -nocase -- $arg $line]} {
      lappend result [lindex [split $line "@"] 0]
      set value 1
    }
  }
  close $data
  if {!$value} {return [format $ability(error) "No matched results found."]}
    if {[llength $result] >= 120} {
    set result1 [join [lrange $result 0 39] ", "]
    set result2 [join [lrange $result 40 79] ", "]
    set result3 [join [lrange $result 80 119] ", "]
    set result4 [join [lrange $result 120 159] ", "]
    putquick "PRIVMSG $chan :$ability(logo) Results: $result1,"
    putquick "PRIVMSG $chan :$result2,"
    putquick "PRIVMSG $chan :$result3,"
    putquick "PRIVMSG $chan :$result4"
  } elseif {[llength $result] >= 80} {
    set result1 [join [lrange $result 0 39] ", "]
    set result2 [join [lrange $result 40 79] ", "]
    set result3 [join [lrange $result 80 119] ", "]
    putquick "PRIVMSG $chan :$abilitylogo Results: $result1,"
    putquick "PRIVMSG $chan :$result2,"
    putquick "PRIVMSG $chan :$result3"
  } elseif {[llength $result] >= 40} {
    set result1 [join [lrange $result 0 39] ", "]
    set result2 [join [lrange $result 40 79] ", "]
    putquick "PRIVMSG $chan :$abilitylogo Results: $result1,"
    putquick "PRIVMSG $chan :$result2"
  } else {
    set result [join $result ", "]
    putquick "PRIVMSG $chan :$abilitylogo Results: $result"
  }
}

##
# Moves, Berries and Items
##
### Settings
set movesfile  "pokedex/Moves"
set berryfile  "pokedex/Berries"
set itemfile   "pokedex/Items"
set searchlist ""

### Procedures

proc pokedex::move {nick host hand chan arg} {
  global movesfile searchlist pokedex
  if {$chan in $pokedex(restrict)} {return}
  set args [split $arg]

  switch [lindex $args 0] {

    search {
      set file [open $movesfile r]
      set arg [lindex $args 1]
      while {[gets $file line] != -1} {

        if {[regexp -all -nocase -- $arg $line]} {

          lappend searchlist [lindex [split $line "@"] 0]

        }

      }

      close $file
      if {$searchlist == ""} {

        putquick "PRIVMSG $chan :Sorry, no matched results found."
        return
      }
      if {[llength $searchlist] >= 120} {
        set result1 [join [lrange $searchlist 0 39] ", "]
        set result2 [join [lrange $searchlist 40 79] ", "]
        set result3 [join [lrange $searchlist 80 119] ", "]
        set result4 [join [lrange $searchlist 120 159] ", "]
        putquick "PRIVMSG $chan :Results: $result1,"
        putquick "PRIVMSG $chan :$result2,"
        putquick "PRIVMSG $chan :$result3,"
        putquick "PRIVMSG $chan :$result4"
      } elseif {[llength $searchlist] >= 80} {
        set result1 [join [lrange $searchlist 0 39] ", "]
        set result2 [join [lrange $searchlist 40 79] ", "]
        set result3 [join [lrange $searchlist 80 119] ", "]
        putquick "PRIVMSG $chan :Results: $result1,"
        putquick "PRIVMSG $chan :$result2,"
        putquick "PRIVMSG $chan :$result3"
      } elseif {[llength $searchlist] >= 40} {
        set result1 [join [lrange $searchlist 0 39] ", "]
        set result2 [join [lrange $searchlist 40 79] ", "]
        putquick "PRIVMSG $chan :Results: $result1,"
        putquick "PRIVMSG $chan :$result2"
      } else {
        set result [join $searchlist ", "]
        putquick "PRIVMSG $chan :Results: $result"
      }
      set searchlist ""

      return  

    } default {

      do:movedesc $nick $host $hand $chan $arg

    }
  }

  return
}



proc do:berry {nick host hand chan arg} {
  global berryfile searchlist pokedex
  if {$chan in $pokedex(restrict)} {return}
  set args [split $arg]

  switch [lindex $args 0] {

    search {
      set file [open $berryfile r]
      set arg [lindex $args 1]
      while {[gets $file line] != -1} {

        if {[regexp -all -nocase -- $arg $line]} {

          lappend searchlist [lindex [split $line "@"] 1]

        }

      }

      close $file
      if {$searchlist == ""} {

        putquick "PRIVMSG $chan :Sorry, no matched results found."
        return
      }
      if {[llength $searchlist] >= 120} {
        set result1 [join [lrange $searchlist 0 39] ", "]
        set result2 [join [lrange $searchlist 40 79] ", "]
        set result3 [join [lrange $searchlist 80 119] ", "]
        set result4 [join [lrange $searchlist 120 159] ", "]
        putquick "PRIVMSG $chan :Results: $result1,"
        putquick "PRIVMSG $chan :$result2,"
        putquick "PRIVMSG $chan :$result3,"
        putquick "PRIVMSG $chan :$result4"
      } elseif {[llength $searchlist] >= 80} {
        set result1 [join [lrange $searchlist 0 39] ", "]
        set result2 [join [lrange $searchlist 40 79] ", "]
        set result3 [join [lrange $searchlist 80 119] ", "]
        putquick "PRIVMSG $chan :Results: $result1,"
        putquick "PRIVMSG $chan :$result2,"
        putquick "PRIVMSG $chan :$result3"
      } elseif {[llength $searchlist] >= 40} {
        set result1 [join [lrange $searchlist 0 39] ", "]
        set result2 [join [lrange $searchlist 40 79] ", "]
        putquick "PRIVMSG $chan :Results: $result1,"
        putquick "PRIVMSG $chan :$result2"
      } else {
        set result [join $searchlist ", "]
        putquick "PRIVMSG $chan :Results: $result"
      }
      set searchlist ""

      return  

    } default {

      do:berrydesc $nick $host $hand $chan $arg

    }
  }

  return

}



proc do:item {nick host hand chan arg} {
  global itemfile searchlist pokedex
  if {$chan in $pokedex(restrict)} {return}
  set args [split $arg]

  switch [lindex [split $arg] 0] {
    search {

      set file [open $itemfile r]
      set arg [lindex $args 1]
      while {[gets $file line] != -1} {

        if {[regexp -all -nocase -- $arg $line]} {

          lappend searchlist [lindex [split $line "@"] 0]

        }

      }

      close $file
      if {$searchlist == ""} {

        putquick "PRIVMSG $chan :Sorry, no matched results found."
        return
      }
      if {[llength $searchlist] >= 120} {
        set result1 [join [lrange $searchlist 0 39] ", "]
        set result2 [join [lrange $searchlist 40 79] ", "]
        set result3 [join [lrange $searchlist 80 119] ", "]
        set result4 [join [lrange $searchlist 120 159] ", "]
        putquick "PRIVMSG $chan :Results: $result1,"
        putquick "PRIVMSG $chan :$result2,"
        putquick "PRIVMSG $chan :$result3,"
        putquick "PRIVMSG $chan :$result4"
      } elseif {[llength $searchlist] >= 80} {
        set result1 [join [lrange $searchlist 0 39] ", "]
        set result2 [join [lrange $searchlist 40 79] ", "]
        set result3 [join [lrange $searchlist 80 119] ", "]
        putquick "PRIVMSG $chan :Results: $result1,"
        putquick "PRIVMSG $chan :$result2,"
        putquick "PRIVMSG $chan :$result3"
      } elseif {[llength $searchlist] >= 40} {
        set result1 [join [lrange $searchlist 0 39] ", "]
        set result2 [join [lrange $searchlist 40 79] ", "]
        putquick "PRIVMSG $chan :Results: $result1,"
        putquick "PRIVMSG $chan :$result2"
      } else {
        set result [join $searchlist ", "]
        putquick "PRIVMSG $chan :Results: $result"
      }
      set searchlist ""

      return  
    } default {

      do:itemdesc $nick $host $hand $chan $arg

    }
  }

  return

}



proc do:movedesc {nick host hand chan arg} {
  global movesfile pokedex
  if {$chan in $pokedex(restrict)} {return}
  set result 0
  set file [open $movesfile r]
  while {[gets $file line] != -1} {
    if {[string tolower [lindex [split $line "@"] 0]] == [string tolower $arg]} {
      set move [lindex [split $line "@"] 0]
      set category [lindex [split $line "@"] 1]
      set PP [lindex [split $line "@"] 2]
      set power [lindex [split $line "@"] 3]
      set accuracy [lindex [split $line "@"] 4]
      set desc [lindex [split $line "@"] 5]
      set type [lindex [split $line "@"] 6]
      set result 1
      break
    }
  }

  close $file
  if {!$result} {
    putquick "PRIVMSG $chan :Sorry, no matched results found."
    return
  }
  putquick "PRIVMSG $chan :\002\00303-Movedex-\003\002 Move: \002$move\002 \[\00303Type: $type\003, \00305Cat: $category\003, \00302PP: $PP\003, Pow: $power, \00306Acc: $accuracy\003\] $desc"

  return

}



proc do:berrydesc {nick host hand chan arg} {
  global berryfile pokedex
  if {$chan in $pokedex(restrict)} {return}
  set file [open $berryfile r]
  set result 0
  while {[gets $file line] != -1} {
    if {[string tolower [lindex [split $line "@"] 1]] == [string tolower $arg]} {
      set number [lindex [split $line "@"] 0]
      set berry [lindex [split $line "@"] 1]
      set desc [lindex [split $line "@"] 2]
      set result 1
      break
    }
  }
  close $file
  if {!$result} {
    putquick "PRIVMSG $chan :Sorry, no matched results found."
    return
  }
  putquick "PRIVMSG $chan :\002\00303-Berrydex-\003\002 $number: \002$berry\002 ~$desc."
  return

}



proc do:itemdesc {nick host hand chan arg} {
  global itemfile pokedex
  if {$chan in $pokedex(restrict)} {return}
  set file [open $itemfile r]
  set result 0
  while {[gets $file line] != -1} {
    if {[string tolower [lindex [split $line "@"] 0]] == [string tolower $arg]} {
      set item [lindex [split $line "@"] 0]
      set desc [lindex [split $line "@"] 1]
      set result 1
      break
    }
  }

  close $file
  if {!$result} {
    putquick "PRIVMSG $chan :Sorry, no matched results found."
    return
  }
  putquick "PRIVMSG $chan :\002\00303-Itemdex-\003\002 \002$item\002 ~$desc."

  return

}

proc priv:move {nick host hand arg} {
  do:move $nick $host $hand $nick $arg
}

proc priv:berry {nick host hand arg} {
  do:berry $nick $host $hand $nick $arg
}

proc priv:item {nick host hand arg} {
  do:item $nick $host $hand $nick $arg
}

### Loaded
puts "Pokedex $::pokedex::pokedex(ver), Abilitydesc $::pokedex::ability(ver) loaded"