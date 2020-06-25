# pokedex.tcl --
#
#       This file implements the Tcl code for querying the Pokedex database
#
# Copyright (c) 2018-2020, Jerry Yong
#
# See the file "LICENSE" for information on usage and redistribution of this
# file.

package require sqlite3
package require json

if {![namespace exists meta]} {
    puts "Failed to load pokedex.tcl: Requires meta.tcl to be loaded."
    return
}

if {![file exists "${scriptDir}/pokedex/pokedexdb"]} {
    puts "Failed to load pokedex.tcl: Requires pokedexdb to be loaded."
    return
}
    
namespace eval pokedex {
    set pokedex(ver)      "0.3"
    set pokedex(usage)    "Usage: !pokedex ?next|search? \[pokemon\]"
    set pokedex(logo)     "**-Pok\u00E9dex-**"
    set pokedex(gen)      6
    set pokedex(restrict) [list]

    set file [open "${scriptDir}/pokedex/messages.json" r]
    set pokedex(messages) [::json::json2dict [read $file]]
    close $file
    unset file    
    
    set ability(ver)      "0.1"
    set ability(usage)    "Usage: !ability ?search? \[ability\]"
    set ability(logo)     "**-Abilitydex-**"
    
    set move(ver)         "0.1"
    set move(usage)       "Usage: !move ?search? \[move\]"
    set move(logo)        "**-Modedex-**"
    
    set item(ver)         "0.1"
    set item(usage)       "Usage: !item ?search? \[move\]"
    set item(logo)        "**-Itemdex-**"
    
    sqlite3 dex "${scriptDir}/pokedex/pokedexdb"
}

##
# Pokedex
##
proc pokedex::command {} {
    upvar data data text text channelId channelId guildId guildId userId userId
    switch [lindex $text 0] {
        "!pokedex" {
            pokedex [regsub {!pokedex } $text {}]
        }
        "!ability" {
            ability [regsub {!ability } $text {}]
        }
        "!move" {
            move [regsub {!move } $text {}]
        }
        "!item" {
            item [regsub {!item } $text {}]
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
            ::meta::putGc [dict create content "```$result```"] 1
            return
        }
        default {
            if {[llength $args] == 0} {
                ::meta::putGc [dict create content $pokedex(usage)] 1
                return
            }
            set result [get_pokemon normal [join $args { }]]
        }
    }
    set result [lindex [lassign $result mode] 0]
    switch $mode {
        0 {
            ::meta::putGc $result 1
        }
        1 {
            set result [dict set result content $pokedex(logo)]
            ::meta::putGc $result 1
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
                ::meta::putGc [dict create content \
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
    set result [dex eval "
        SELECT * FROM $table WHERE lower(formname) = lower('$arg') OR id = '$arg'
    "]
    if {[llength $result] > 0} {
        set mode 1
        lassign $result id pokemon formname type genus ability ability2 \
            hability gender egggroup height weight legend evolve_cond hp atk \
            def spatk spdef spd capture final stage effort hatch_counter \
            happiness exp forms colour base_exp

        if {$state eq "normal"} {
            if {$ability2 ne ""} {append ability "/$ability2"}
            if {$hability ne ""} {append ability "/*$hability*"}
            set total [expr {$hp+$atk+$def+$spatk+$spdef+$spd}]            
            set msg [format [dict get $pokedex(messages) getPokemon] $type \
                    $ability $hp $atk $def $spatk $spdef $spd $total]
            return [list $mode [dict create embed [dict create \
                title "$id: $formname" description $msg \
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
            set msg [format [dict get $pokedex(messages) getPokemonNext] \
                    $egggroup $hp $atk $def $satk $sdef $spd $height $weight \
                    $capture $happiness $gender $base_exp $grw $texp]
            return [list $mode [dict create embed [dict create \
                title "**$id:** $formname ($genus Pokémon)" description $msg \
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
        id pokemon formname type genus ability1 ability2 hability gender 
        egggroup height weight legend evolve_cond hp atk def spatk spdef spd 
        capture final stage effort hatch_counter happiness exp forms colour 
        base_exp pre_evos
    }
    
    set result ""
    dex eval "SELECT * FROM $table" ar {
        if {[regexp -nocase $arg [join [lmap x $fields {set ar($x)}] { }]]} {
            lappend results $ar(formname)
            set mode 2
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
    if {!($number > 0 && $number < 13)} {
        return [list 0 \
            "The maximum random number of Pokémon that can be picked is 12"]
    }
    set condition [list]
    
    foreach {flag param} $args {
        switch -nocase -glob $flag {
            -region {
                set conds [list]
                set regions [regexp -all -inline -nocase {[a-z]+} $param]
                foreach reg $regions {
                    switch -nocase -glob $reg {
                        kan* {lappend conds "(id >= '#001' AND id < '#152')"}
                        joh* {lappend conds "(id >= '#152' AND id < '#252')"}
                        hoe* {lappend conds "(id >= '#252' AND id < '#387')"}
                        sin* {lappend conds "(id >= '#387' AND id < '#495')"}
                        uno* {lappend conds "(id >= '#495' AND id < '#650')"}
                        kal* {lappend conds "(id >= '#650' AND id < '#722')"}
                        alo* {lappend conds "(id >= '#722' AND id < '#999')"}
                        default {
                            return [list 0 [dict get $pokedex(messages) \
                                    getRandomRegion]]
                        }
                    }
                }
                lappend condition "([join $conds { OR }])"
            }
            -final {
                if {$param ni {0 1}} {
                    return [list 0 [dict get $pokedex(messages) getRandomFinal]]
                }
                lappend condition "final = $param"
            }
            -legend* {
                if {$param ni {0 1}} {
                    return [list 0 [dict get $pokedex(messages) \
                            getRandomLegend]]
                }
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
    set re {\y(?:ALTER|UPDATE|INTO|CREATE|INSERT)\y}
    if {[regexp -all -nocase $re $query]} {
        return [list 0 \
            [dict create content "Data manipulation queries are not supported."]]
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
# Abilitydex 
##
proc pokedex::ability {arg} {
    set args [split $arg]
    switch [lindex $args 0] {
            search {
            set arg [lindex $args 1]
            ::meta::putGc [search_ability $arg] 1
        }
        default {
            ::meta::putGc [get_ability $arg] 1
        }
    }
}

proc pokedex::get_ability {arg} {
    variable ability pokedex
    
    if {[llength $arg] < 1} {return $ability(usage)} 
    set value 0
    set ability [string tolower $arg]
    set table "abilDetails$pokedex(gen)"
    
    lassign [dex eval {SELECT id FROM abilities WHERE english = :arg LIMIT 1}] \
        id ability
    
    if {$id == ""} {return [dict create content "No matched results found"]}
    
    set results [dex eval "SELECT * FROM $table WHERE id = :id LIMIT 1"]
    
    if {$results != ""} {
        lassign $results id - description
        return [dict create embed [dict create \
            title "$id: $ability" \
            description "$description" \
        ]]
    } else {
        return [return [dict create content "No matched results found"]]
    }
}

proc pokedex::search_ability {arg} {
    variable ability pokedex
    
    set table "abilDetails$pokedex(gen)"
    set results ""
    
    dex eval "
        SELECT A.id, B.english, A.description FROM $table A
        JOIN abilities B ON A.id = B.id
    " arr {
        if {
            [regexp -nocase $arg \
                [join [list $arr(id) $arr(english) $arr(description)] { }]]
        } {
            lappend results $arr(english)
        }
    }
    
    if {$results == ""} {
        return [dict create content "No matched results found"]
    } else {
        return [dict create content "$ability(logo) Results: [join $results {, }]"]
    }
}

##
# Movedex
##
proc pokedex::move {arg} {
    set args [split $arg]
    switch [lindex $args 0] {
        search {
            set arg [lindex $args 1]
            ::meta::putGc [search_move $arg]
        } next {
            set arg [lindex $args 1]
            ::meta::putGc [flags_move $arg]
        } default {
            ::meta::putGc [get_move $arg]
        }
    }
}

proc pokedex::get_move {arg} {
    variable move pokedex
    
    if {[llength $arg] < 1} {return $move(usage)} 
    set value 0
    set move [string tolower $arg]
    set table "moveDetails$pokedex(gen)"
    
    lassign [dex eval {SELECT id FROM moves WHERE english = :arg LIMIT 1}] \
        id move
    
    if {$id == ""} {return [dict create content "No matched results found"]}
    
    set results [dex eval "SELECT * FROM $table WHERE id = :id LIMIT 1"]
    
    if {$results != ""} {
        lassign $results id type class pp basepower accuracy priority effect
        set msg [format [dict get $pokedex(messages) $type $class $pp \
                $basepower $accuracy $priority $effect]]
        return [dict create embed [dict create \
            title "$id: $move" description $msg \
        ]]
    } else {
        return [dict create content "No matched results found"]
    }
}

proc pokedex::search_move {arg} {
    variable move pokedex
    
    set table "moveDetails$pokedex(gen)"
    set results ""
    
    dex eval "
        SELECT A.id, B.english, A.description FROM $table A
        JOIN moves B ON A.id = B.id
    " arr {
        if {
            [regexp -nocase $arg \
                [join [list $arr(id) $arr(english) $arr(description)] { }]]
        } {
            lappend results $arr(english)
        }
    }
    
    if {$results == ""} {
        return [dict create content "No matched results found"]
    } else {
        return [dict create content "$move(logo) Results: [join $results {, }]"]
    }
}

proc pokedex::flags_move {arg} {
    variable move pokedex
    
    if {[llength $arg] < 1} {return $move(usage)} 
    set value 0
    set move [string tolower $arg]
    set table "moveDetails$pokedex(gen)"
    
    lassign [dex eval {SELECT id FROM moves WHERE english = :arg LIMIT 1}] \
        id move
    
    if {$id == ""} {return [dict create content "No matched results found"]}
    
    set results [dex eval "SELECT * FROM $table WHERE id = :id LIMIT 1"]
    
    if {$results != ""} {
        lassign $results id - - - - - - - contact charging recharge detectprotect \
            reflectable snatchable mirrormove punchbased sound gravity defrosts \
            range heal infiltrate
        set msg [format [dict get $pokedex(messages)] $contact $charging \
                $recharge $detectprotect $reflectable $snatchable $mirrormove \
                $punchbased $sound $gravity $defrosts $range $heal $infiltrate]
        return [dict create embed [dict create \
            title "$id: $move" description $msg \
        ]]
    } else {
        return [dict create content "No matched results found"]
    }
}

##
# Itemdex 
##
proc pokedex::item {arg} {
    ::meta::putGc [dict create content \
        "Unfortunately, this function is not available yet."] 0
    return
    set args [split $arg]
    switch [lindex $args 0] {
            search {
            set arg [lindex $args 1]
            ::meta::putGc [search_item $arg] 1
        }
        default {
            ::meta::putGc [get_item $arg] 1
        }
    }
}

proc pokedex::pre_reboot {} {
    return
}

### Loaded
puts "Pokedex $::pokedex::pokedex(ver) loaded"
puts "Abilitydex $::pokedex::ability(ver) loaded"
puts "Movedex $::pokedex::move(ver) loaded"