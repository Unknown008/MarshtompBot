# FateGrandOrder.tcl --
#
#       This file implements the Tcl code for Fate Grand Order mobile game for
#       discord; a repository where a master can save their servants and track
#       required materials
#
# Copyright (c) 2019, Jerry Yong
#
# See the file "LICENSE" for information on usage and redistribution of this
# file.

package require sqlite3
package require http
package require json
package require tls

::http::register https 443 ::tls::socket

if {![namespace exists meta]} {
    puts "Failed to load FateGrandOrder.tcl: Requires meta.tcl to be loaded."
    return
}

namespace eval fgo {
    sqlite3 fgodb "${scriptDir}/FateGO/fgodb.sqlite3"

    set afterIds                   [list]

    set fgo(cmd)      "!fgo"
    set fgo(ver)      "0.1"
    set fgo(gitIssue) "http://github.com"
    set fgo(errors)   "${scriptDir}/FateGO/error-messages.json"
    set fog(timeout)  30000
    # List of dicts {user {} cmd {} after {} word {}}
    set fgo(listener) [list]

    set fgo(addOpts) {
        {{^-id?$}                  id}
        {{^-n(?:ame)?$}            na}
        {{^-a(?:sc(?:ension)?)?$}  as}
        {{^-l(?:vl?|evel)?$}       lv}
        {{^-s(?:kill)?1$}          s1}
        {{^-s(?:kill)?2$}          s2}
        {{^-s(?:kill)?3$}          s3}
    }
    
    set fgo(lookupOpts) {
        {{^-(?:r(?:ar(?:e|ity))?|s(?:tars?)?)$}   rarity}
        {{^-(?:i(?:mmediate)?|now?)$}               time}
        {{^-c(?:l(?:ass)?)?$}                      class}
        {{^-l(?:vl?|evel)?$}                       level}
        {{^-n(?:ame)?$}                             name}
    }
}

proc fgo::command {} {
    variable fgo
    upvar data data text text channelId channelId guildId guildId userId userId
    switch [lindex $text 0] {
        "!fgoservant" {
            servant $userId [regsub {!fgoservant *} $text ""]
        }
        "!fgolookup" {
            lookup $userId [regsub {!fgolookup *} $text ""]
        }
        "!fgoshare" {
            share $userId [regsub {!fgoshare *} $text ""]
        }
        "!fgoprofile" {
            manage_profile $userId [regsub {!fgoprofile *} $text ""]
        }
        default {
            set found 0
            for {set i 0} {$i < [llength $fgo(listener)]} {incr i} {
                set listener [lindex $fgo(listener) $i]
                if {
                    [dict get $listener user] == $userId &&
                    [string toupper $text] in [dict get $cmd word]
                } {
                    set found 1
                    incr ::listener -1
                    set fgo(listener) [lreplace $fgo(listener) $i $i]
                    incr i -1
                    {*}[dict get $listener cmd] $text [dict get $listener after]
                }
            }
            return $found
        }
    }
    return 1
}

proc fgo::servant {userId text} {
    switch [lindex $text 0] {
        add {
            add $userId [regsub {add *} $text ""]
        }
    }
}

proc fgo::add {userId data} {
    variable fgo
    
    if {$data eq "" || [string tolower $data] eq "help"} {
        send_error addHelp
        return
    } elseif {[llength $data] == 2 && [lindex $data 0] eq "-url"} {
        if {[catch {::http::geturl [lindex $data 1]} token]} {
            send_error addUrlError
            return
        }
        set data [::http::data $token]
        ::http::cleanup $token
        import_url $userId $data
        return
    } elseif {[llength $data] ni {6 12}} {
        send_error addError
        return
    }

    set errors [list]

    if {[llength $data] == 12} {
        set servant(id) ""
        set servant(as) ""
        set servant(lv) ""
        set servant(s1) ""
        set servant(s2) ""
        set servant(s3) ""

        foreach option $fgo(addOpts) {
            set position [lsearch -regexp $data [lindex $option 0]]
            if {$position > -1 && $position > [llength $data]+1} {
                set value [lindex $data $position+1]
                if {
                    [lindex $option 1] eq "na" &&
                    $servant(id) == "" && 
                    [lsearch -regexp $data {-id?}] == -1
                } {
                    set servant(id) $value
                } else {
                    set servant([lindex $option 1]) $value
                }
            } else {
                if {
                    [lindex $options 1] in "na" ||
                    ([lindex $options 1] eq "id" && 
                    [lsearch -regexp $data {-n(?:ame)?}] > -1)
                } {
                    continue
                } elseif {[lindex $options 1] in {s2 s3}} {
                    set servant([lindex $options 1]) 1
                    continue
                }
                lappend errors "servant[lindex $option 1]Missing"
            }
        }
    }

    if {[validate_servant $data]} {
        lassign $data servant(id) servant(lv) servant(as) servant(s1) \
                servant(s2) servant(s3)
    }
    if {$errors != ""} {
        send_error multiple $errors
        return
    }

    set now [clock seconds]
    fgodb eval {
        INSERT INTO master_servant VALUES (
            :userId,
            :servant(id),
            :servant(lv),
            :servant(as),
            :servant(s1),
            :servant(s2),
            :servant(s3),
            :now,
            :now
        )
    }

    set msg "Your servant was successfully added."
    set master [fgodb eval {SELECT 1 FROM master WHERE id = :userId}]
    if {$master == ""} {
        fgodb eval {INSERT INTO master VALUES (
            :userId,
            null,
            null,
            0,
            null,
            null,
            null,
            :now,
            null
        )}
        append msg " An account for you has automatically been created with " \
                "the servants you have created since it is your first time " \
                "registering a servant. Should you wish to delete it, you can" \
                " use `!fgodelete` to remove all your information saved. " \
                "If you also want others to see your account, you can turn " \
                "your account visibility settings on (off by default) by " \
                "using `!fgoshare on`."
    }

    ::meta::putdc [dict create content $msg] 0
}

proc fgo::lookup {userId data} {
    variable fgo

    set master [fgodb eval {SELECT 1 FROM master WHERE id = :userId}]
    if {$master == ""} {
        set msg "You are not registered. Add at least one servant to register "
        append msg "yourself (use `!fgoadd` to add a servant)."
        ::meta::putdc [dict create content $msg] 0
        return
    }
    set servants [list]
    set errors [list]
    set filtered [list]
    array set filter {} ;# Filter for servant criteria
    array set filterSvt {} ;# Filter for servant criteria
    array set filterLvl {} ;# Filter for ascension and skill level criteria

    if {$data != ""} {
        foreach option $fgo(lookupOpts) {
            set position [lsearch -regexp $data [lindex $option 0]]
            if {$position > -1} {
                switch [lindex $option 1] {
                    "rarity" {
                        # Allow for multiple queries, up to 5 because we got 5
                        # rarity levels (1-5)
                        for {set i 1} {$i <= 5} {incr i} {
                            set value [lindex $data $position+$i]
                            if {$value == "" && $i == 1} {
                                # First parameter is blank
                                lappend errors rarityFilter
                                break
                            } elseif {
                                $value == "" || 
                                [string index $value 0] eq "-"
                            } {
                                # No more parameters or another criteria begins
                                break
                            } elseif {![regexp {^(?:[<>]?=)?[1-5]$} $value]} {
                                lappend errors rarityFilter
                                break
                            } elseif {[regexp {^[1-5]$} $value]} {
                                set value "= $value"
                            }
                            lappend filter(rarity) $value
                        }
                    }
                    "class" {
                        # Allow for multiple queries, up to the number of
                        # servant classes
                        set classes [fgodb eval {SELECT name FROM class}]
                        for {set i 1} {$i <= [llength $classes]} {incr i} {
                            set value [lindex $data $position+$i]
                            if {$value == "" && $i == 1} {
                                # First parameter is blank
                                lappend errors classFilter
                                break
                            } elseif {
                                $value == "" || 
                                [string index $value 0] eq "-"
                            } {
                                # No more parameters or another criteria begins
                                break
                            } elseif {
                                [string tolower $value] ni 
                                    [string tolower $classes]
                            } {
                                lappend errors classFilter
                                break
                            } else {
                                set classId [fgodb eval {
                                    SELECT id FROM class 
                                    WHERE lower(name) = lower(:value)
                                }]
                                set value "= $classId"
                            }
                            lappend filter(class_id) $value
                        }
                    }
                    "level" {
                        # Allow for up to 7 queries, arbitrary count
                        for {set i 1} {$i <= 7} {incr i} {
                            set value [lindex $data $position+$i]
                            if {$value == "" && $i == 1} {
                                # First parameter is blank
                                lappend errors levelFilter
                                break
                            } elseif {
                                $value == "" || 
                                [string index $value 0] eq "-"
                            } {
                                # No more parameters or another criteria begins
                                break
                            } elseif {![regexp {^(?:[<>]?=)?\d{1,3}$} $value]} {
                                lappend errors levelFilter
                                break
                            } elseif {[regexp {^\d{1,3}$} $value]} {
                                set value "= $value"
                            }
                            lappend filterSvt(servant_level) $value
                        }
                    }
                    "time" {
                        set filterLvl([lindex $option 1]) 1
                    }
                    "name" {
                        # Allow for up to 7 queries, arbitrary count
                        set names [fgodb eval {SELECT name FROM servant}]
                        for {set i 1} {$i <= 7} {incr i} {
                            set value [lindex $data $position+$i]
                            if {$value == "" && $i == 1} {
                                # First parameter is blank
                                lappend errors nameFilter
                                break
                            } elseif {
                                $value == "" || 
                                [string index $value 0] eq "-"
                            } {
                                # No more parameters or another criteria begins
                                break
                            } elseif {
                                [lsearch -nocase $names *$value*] == -1
                            } {
                                lappend errors nameFilter
                                break
                            } else {
                                set value "LIKE '%$value%'"
                            }
                            lappend filter(name) $value
                        }
                    }
                }
            }
        }
    }
    fgodb eval {
        SELECT * FROM master_servant WHERE master_id = :userId
    } arr {
        lappend servants [list $arr(servant_id) $arr(servant_ascension) \
                $arr(servant_skill1_level) $arr(servant_skill2_level) \
                $arr(servant_skill3_level)]
        if {[array size filter] > 0 || [array size filterSvt] > 0} {
            set filterQuery {
                SELECT 1 FROM servant 
                WHERE id = :arr(servant_id)
            }

            foreach {criteria value} [array get filter] {
                set subQuery ""
                foreach query $value {
                    # Usually those would be OR'd
                    append subQuery [expr {$subQuery eq "" ? "" : " OR "}] \
                        "$criteria $query"
                }
                append filterQuery " AND ($subQuery)"
            }
            set valid [fgodb eval $filterQuery]

            set filterSvtQuery {
                SELECT 1 FROM master_servant 
                WHERE servant_id = :arr(servant_id)
            }

            foreach {criteria value} [array get filterSvt] {
                set subSvtQuery ""
                foreach query $value {
                    # Usually those would be AND'd
                    append subSvtQuery \
                        [expr {$subSvtQuery eq "" ? "" : " AND "}] \
                        "$criteria $query"
                }
                append filterSvtQuery " AND ($subSvtuery)"
            }
            set validSvt [fgodb eval $filterQuery]
            
            if {$valid == 1 && $validSvt == 1} {
                lappend filtered [list $arr(servant_id) \
                        $arr(servant_ascension) $arr(servant_skill1_level) \
                        $arr(servant_skill2_level) $arr(servant_skill3_level)]
            }
        }
    }
    if {$servants == ""} {
        set msg "You have no servants. You need at least one servant to "
        append msg "use this command (use `!fgoadd` to add a servant)."
        ::meta::putdc [dict create content $msg] 0
        return
    } elseif {$data != ""} {
        if {$errors != ""} {
            send_error multiple $errors
            return
        } elseif {$filtered == ""} {
            set msg "You have no servants matching the query criteria."
            ::meta::putdc [dict create content $msg] 0
            return
        }
        set servants $filtered
        unset filtered
    }

    array set requiredItems [list AAAQP 0]
    foreach s $servants {
        array unset servant
        lassign $s servant(id) servant(as) servant(s1) servant(s2) servant(s3)
        fgodb eval {SELECT * FROM servant WHERE id = :servant(id)} info {
            # Ascension
            for {set i $servant(as)} {$i < 4} {incr i} {
                set target [expr {$i+1}]
                set detail $info(ascension$target)
                if {[string is integer [dict get $detail cost]]} {
                    incr requiredItems(AAAQP) [dict get $detail cost]
                    set material [dict get $detail material]
                    foreach n $material {
                        lassign $n mat qty
                        if {$mat ni [array names requiredItems]} {
                            set requiredItems($mat) $qty
                        } else {
                            incr requiredItems($mat) $qty
                        }
                    }
                }
                if {[info exists filterLvl(time)]} break
            }
            
            # Skills
            for {set i 1} {$i <= 3} {incr i} {
                for {set j $servant(s$i)} {$j < 10} {incr j} {
                    set target [expr {$j+1}]
                    set detail $info(skill$target)
                    if {[string is integer [dict get $detail cost]]} {
                        incr requiredItems(AAAQP) [dict get $detail cost]
                        set material [dict get $detail material]
                        foreach n $material {
                            lassign $n mat qty
                            if {$mat ni [array names requiredItems]} {
                                set requiredItems($mat) $qty
                            } else {
                                incr requiredItems($mat) $qty
                            }
                        }
                    }
                    if {[info exists filterLvl(time)]} break
                }
            }
        }
    }

    set msg [list]
    set kmax 0
    set vmax 0

    foreach {key val} [array get requiredItems] {
        if {$val > 1000} {
            regsub -all {[0-9](?=(?:\d{3})+$)} $val {\0,} val
        }
        if {$key ne "QP"} {
            fgodb eval {SELECT name FROM item WHERE id = :key} arr {
                set key $arr(name)
            }
        }
        lappend msg [list $key $val]
        set kmax [expr {[string len $key] > $kmax ? [string len $key] : $kmax}]
        set vmax [expr {[string len $val] > $vmax ? [string len $val] : $vmax}]
    }
    set msg [lmap x [lsort -index 0 $msg] {
        if {[lindex $x 0] eq "AAAQP"} {
            lset x 0 "QP"
        } 
        format "%-${kmax}s %${vmax}s" {*}$x
    }]

    set finalMsg [join $msg \n]
    if {[string length $finalMsg] > 1994} {
        set finalMsg [string range $finalMsg 0 1960]
        regexp {.+(?=\n)} $finalMsg finalMsg
        append finalMsg "\nResults too long to display more."
    }
    
    ::meta::putdc [dict create content "```$finalMsg```"] 0
}

proc fgo::share {userId param} {
    switch $param {
        1 -
        on {
            set current [fgodb eval {
                SELECT share FROM master WHERE id = :userId
            }]
            if {$current == 1} {
                set msg "Your account's sharing setting is already on!"
            } elseif {$current == 0} {
                fgodb eval {UPDATE master SET share = 1}
                set msg "Account profile share setting turned on."
            } else {
                set msg "You do not have a registered account!"
            }
        }
        0 -
        off {
            set current [fgodb eval {
                SELECT share FROM master WHERE id = :userId
            }]
            if {$current == 0} {
                set msg "Your account's sharing setting is already off!"
            } elseif {$current == 1} {
                fgodb eval {UPDATE master SET share = 0}
                set msg "Account profile share setting turned off."
            } else {
                set msg "You do not have a registered account!"
            }
        }
        default {
            set msg "Unrecognised parameter. Usage **!fgoshare _on|off_**"
        }
    }
    ::meta::putdc [dict create content $msg] 0
}

proc fgo::manage_profile {userId param} {
    upvar guildId guildId
    switch [lindex $param 0] {
        "" -
        v -
        view {
            profile_view $userId [lrange $param 1 end]
            return
        }
        e -
        edit {
            set msg "Sorry this has not been implemented yet."
            #profile_edit $userId [lrange $param 1 end]
            #return
        }
        d -
        del -
        delete {
            profile_delete $userId
            return
        }
        find -
        search {
            set msg "Sorry this has not been implemented yet."
            #profile_search [lrange $param 1 end]
            #return
        }
        default {
            set msg "Unrecognised parameter. Usage **!fgoprofile "
            append msg "_view|edit|delete|search_**"
        }
    }
    ::meta::putdc [dict create content $msg] 0
}

proc fgo::profile_view {userId param} {
    upvar guildId guildId
    if {$param in {"" "me"}} {
        set found [fgodb eval {
            SELECT
                id, ign, server, share, friend_code, message, tag, created,
                updated
            FROM master WHERE id = :userId
        }]
        if {$found == ""} {
            set msg "You don't seem to have an FGO profile registered. An FGO "
            append msg "profile gets automatically created when you add a "
            append msg "servant using **!fgoservant add**."
            ::meta::putdc [dict create content $msg] 0
            return
        }
    } elseif {[regexp {^<@!?([0-9]+)>$} $param - user]} {
        set found [fgodb eval {
            SELECT
                id, ign, server, share, friend_code, message, tag, created,
                updated
            FROM master WHERE id = :user AND share = 1
        }]
        if {$found == ""} {
            set msg "No such user found or the user has their profile "
            append msg "visibility turned off."
            ::meta::putdc [dict create content $msg] 0
            return
        }
    } elseif {[regexp {^[^#]+#[0-9]{4}$} $param - tag]} {
        set found [fgodb eval {
            SELECT
                id, ign, server, share, friend_code, message, tag, created,
                updated
            FROM master WHERE tag = :tag AND share = 1
        }]
        if {$found == ""} {
            set msg "No user matching the provided tag found in my database or "
            append msg "the user has their profile visibility turned off."
            ::meta::putdc [dict create content $msg] 0
            return
        }
    } else {
        # put error
        return
    }

    lassign $found id ign server share friend_code message tag created \
            updated
    set desc "**User:** [sanitize $tag] (IGN: [sanitize $ign])\n"
    append desc "**Server:** [sanitize $server]\n"
    append desc "**Friend Code:** [sanitize $friend_code]\n"
    append desc "**Message:** [sanitize $message]\n"
    append desc "**Profile visibility:** [sanitize $share share]"
    set msg [dict create \
        title "Profile Card" \
        description $desc \
        footer [dict create text [sanitize "$created $updated" time]]
    ]
    ::meta::putdc [dict create embed $msg] 0
}

proc fgo::profile_edit {userId param} {

}

proc fgo::profile_delete {userId} {
    variable fgo

    set master [fgodb eval {SELECT 1 FROM master WHERE id = :userId}]
    if {$master != ""} {
        set msg "You were not registered as a master."
        ::meta::putdc [dict create content $msg] 0
        return
    }

    set msg "Are you sure you want to delete your profile? (Y/N) This action "
    append msg "cannot be undone."
    incr ::listener
    set afterId [after $fgo(timeout) ::fgo::profile_delete_confirm $userId "N"]
    lappend fgo(listener) [dict create user $userId cmd \
            [list profile_delete_confirm $userId] after $afterId word {Y N}]
    ::meta::putdc [dict create content $msg] 0
}

proc fgo::profile_delete_confirm {userId text {afterId {}}} {
    variable fgo

    switch -nocase -- $text {
        Y {
            after cancel $afterId
            fgodb eval {DELETE FROM master WHERE id = :userId}
            fgodb eval {DELETE FROM master_servant WHERE master_id = :userId}
            set msg "Your profile has been deleted as requested."
        }
        N {
            if {$afterId == ""} {
                set msg "Operation timeout. Deletion of your profile has been "
                append msg "cancelled."
            } else {
                after cancel $afterId
                set msg "Deletion of your profile has been cancelled as "
                append msg "requested."
            }
        }
    }
    ::meta::putdc [dict create content $msg] 0
}

proc fgo::profile_search {param} {

}

proc fgo::import_url {userId fullData} {
    variable fgo

    set errors [list]
    set addServants [list]

    foreach data [split $fullData \n] {
        set data [split [string trim $data] ","]

        if {![validate_servant $data]} {
            send_error multiple $errors
            return
        }
        lappend addServants $data
    }

    set now [clock seconds]
    foreach s $addServants {
        array unset servant
        lassign $s servant(id) servant(lv) servant(as) servant(s1) \
                servant(s2) servant(s3)
        set exists [fgodb eval {
            SELECT 1 FROM master_servant
            WHERE master_id == :userId AND servant_id == :servant(id)
        }]
        if {$exists != ""} {
            fgodb eval {
                UPDATE master_servant SET
                    servant_level = :servant(lv),
                    servant_ascension = :servant(as),
                    servant_skill1_level = :servant(s1),
                    servant_skill2_level = :servant(s2),
                    servant_skill3_level = :servant(s3),
                    updated = :now
                WHERE master_id = :userId AND servant_id = :servant(id)
            }
        } else {
            fgodb eval {
                INSERT INTO master_servant VALUES (
                    :userId,
                    :servant(id),
                    :servant(lv),
                    :servant(as),
                    :servant(s1),
                    :servant(s2),
                    :servant(s3),
                    :now,
                    :now
                )
            }
        }
    }

    set master [fgodb eval {SELECT 1 FROM master WHERE id = :userId}]
    set msg "Your servants were successfully added"
    if {$master == ""} {
        fgodb eval {INSERT INTO master VALUES (
            :userId,
            null,
            null,
            0,
            null,
            null,
            null,
            :now,
            null
        )}
        append msg ". An account for you has automatically been created with " \
                "the servants you have created since it is your first time " \
                "registering a servant. Should you wish to delete it, you can" \
                " use `!fgodelete` to remove all your information saved. " \
                "If you also want others to see your account, you can turn " \
                "your account visibility settings on (off by default) by " \
                "using `!fgoshare on`."
    } else {
        append msg " and/or updated."
    }

    ::meta::putdc [dict create content $msg] 0
}

proc fgo::validate_servant {data} {
    lassign $data servant(id) servant(lv) servant(as) servant(s1) servant(s2) \
            servant(s3)
    
    set errors [list]
    
    # Validate Name and ID
    if {![regexp {^\d+(?:\.\d)?$} $servant(id)]} {
        set results [fgodb eval {
            SELECT id FROM servant WHERE name LIKE :servant(id)
        }]
        if {[llength $results] == 0} {
            lappend errors "servantNameNotFound $servant(id)"
        } elseif {[llength $results] > 1} {
            lappend errors "multipleServantFound $servant(id)"
        } else {
            set servant(id) $results
        }
    } else {
        if {[string length servant(id)] < 3} {
            set servant(id) [format %03d $servant(id)]
        }
        set results [fgodb eval {
            SELECT id FROM servant WHERE id = :servant(id)
        }]
        if {[llength $results] == 0} {
            lappend errors "servantIdNotFound $servant(id)"
        }
    }

    # Validate Level
    if {![string is integer $servant(lv)] || 
        !($servant(lv) > 0 && $servant(lv) <= 100)
    } {
        lappend errors invalidLevel
    }

    # Validate Ascension
    if {![string is integer $servant(as)] || 
        !($servant(as) >= 0 && $servant(as) <= 4)
    } {
        lappend errors invalidAscension
    }

    # Validate Skill Levels
    for {set i 1} {$i <= 3} {incr i} {
        if {![string is integer $servant(s$i)] || 
            !($servant(s$i) > 0 && $servant(s$i) <= 10)
        } {
            lappend errors invalidSkillLevel
        }
    }
    if {$errors != ""} {
        uplevel [list lappend errors {*}$errors]
        return 0
    }

    uplevel [list set data [list $servant(id) $servant(lv) $servant(as) \
            $servant(s1) $servant(s2) $servant(s3)]]
    return 1
}

proc fgo::send_error {type {param {}}} {
    variable fgo
    set file [open $fgo(errors) r]
    set errorDict [::json::json2dict [read $file]]
    close $file

    switch $type {
        multipleServantFound {
            set results [list]
            fgodb eval {
                SELECT id, name, class FROM servant WHERE name LIKE :param
            } info {
                lappend results "$info(id): $info(name) ($info(class))"
            }

            set msg [subst [dict get $errorDict multipleServantFound]]
        }
        multiple {
            set params $param
            set msg "One or more issues were encountered with your request:"
            foreach error $params {
                switch $error {
                    "multipleServantFound" {
                        set results [list]
                        fgodb eval {
                            SELECT id, name, class FROM servant 
                            WHERE name LIKE :param
                        } info {
                            lappend results \
                                "$info(id): $info(name) ($info(class))"
                        }
                        append msg "\n- [subst [dict get $errorDict $error]]"
                    }
                    "classFilter" {
                        set results [list]
                        set results [fgodb eval {
                            SELECT name FROM class WHERE id < 14 OR id > 17
                        }]
                        append msg "\n- [subst [dict get $errorDict $error]]"
                    }
                    default {
                        if {[llength $error] > 1} {
                            set param [lassign $error error]
                        }
                        append msg "\n- [subst [dict get $errorDict $error]]"
                    }
                }
            }
        }
        default {
            set msg [subst [dict get $errorDict $type]]
        }
    }
    
    ::meta::putdc [dict create content $msg] 0
}

proc fgo::sanitize {word {type {}}} {
    switch $type {
        "share" {
            return [expr {$word ? "On" : "Off"}]
        }
        "time" {
            set created [clock format [lindex $word 0] -format \
                    "%a %d %b %Y %T UTC" -timezone UTC]
            set msg "Created on $created"
            if {[lindex $word 1] ne ""} {
                set updated [clock format [lindex $word 1] -format \
                    "%a %d %b %Y %T UTC" -timezone UTC]
                append msg " (Last updated on $updated"
            }
            return $msg
        }
        default {
            return [expr {$word eq "" ? "*Not registered*" : $word}]
        }
    }
}

proc fgo::pre_rehash {} {
    variable afterIds
    foreach id $afterIds {
        after cancel $id
    }
}

puts "FateGrandOrder.tcl $::fgo::fgo(ver) loaded"