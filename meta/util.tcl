# util.tcl --
#
#       This file contains some utility procedures for the bot to use.
#
# Copyright (c) 2018-2020, Jerry Yong
#
# See the file "LICENSE" for information on usage and redistribution of this
# file.

package require http

namespace eval util {

}

# util::parseArgs --
#
#   Parses arguments into a dictionary
#
# Arguments:
#   type      Dictionary of parameter names and criteria
#   arg       Arguments to be parsed
#
# Results:
#   Dictionary containing the parameters as key preceded by '-' and values for 
#   each

proc util::parseArgs {type arg} {
    lassign {{} {} {}} params dictArg paramPatterns
    dict for {key val} $type {
        lappend params $key
        lappend paramPatterns [lindex $val 0]
    }
    set errors {}
    for {set i 0} {$i < [llength $arg]} {incr i} {
        if {[string index [lindex $arg $i] 0] eq "-"} {
            set found 0
            foreach pat $paramPatterns {
                if {[regexp -nocase $pat [lindex $arg $i]]} {
                    set found 1
                    break
                }
            }
            if {!$found} {
                lappend errors "Invalid parameter [lindex $arg $i]."
            } else {
                set param [string tolower [lindex $arg $i]]
                set value [string tolower [lindex $arg $i+1]]

                if {[catch {validateParamValue $type $param $value} value]} {
                    lappend errors {*}$value
                } else {
                    dict set dictArg $param $value
                }
                
                set paramIdx [lsearch $params $param]
                set params [lreplace $params $paramIdx $paramIdx]
                set paramPatterns [lreplace $paramPatterns $paramIdx $paramIdx]
                incr i
            }
        } else {
            set param [lindex $params 0]
            set value [lindex $arg $i]
            if {$value eq "help"} {return ""}

            lassign [dict get $type $param] - paramType required -
            if {$paramType eq "text"} {
                set value [lrange $arg $i end]
            } elseif {[catch {validateParamValue $type $param $value} value]} {
                if {[llength $param] > 1 && !$required} {
                    incr i -1
                } else {
                    lappend errors {*}$value
                }
            } else {
                dict set dictArg $param $value
            }
            
            set params [lreplace $params 0 0]
            set paramPatterns [lreplace $paramPatterns 0 0]
        }
    }

    foreach param $params {
        set value [dict get $type $param]
        set required [lindex $value 2]
        if {$required} {
            lappend errors "Missing parameter [string trimleft $param {-}]."
        } else {
            dict set dictArg $param ""
        }
    }

    if {[llength $errors] > 0} {return -code error $errors}

    return $dictArg
}

# util::validateParamValue --
#
#   Validates a value against the options available for a parameter according to
#   its type
#
# Arguments:
#   type      The command name that called this procedure
#   param     The current parameter being validated
#   value     The current value of the parameter under validation
#   
# Results:
#   The validated value if valid, otherwise, raises an error with a list of 
#   what is wrong

proc util::validateParamValue {type param value} {
    set errors {}
    lassign [dict get $type $param] - paramType - options
    switch $paramType {
        "string" {
            if {$options ne {} && $value ni $options} {
                set msg "Invalid value for $param. Its valid values are: "
                append msg "[join $options {, }]."
                lappend errors $msg
            }
        }
        "text" {}
        "int" {
            if {![string is integer -strict $value]} {
                set msg "Invalid value for parameter $param. The value must be "
                append msg "an integer."
                lappend errors $msg
            } elseif {[catch {validateNumber $value $options} value]} {
                lappend errors {*}$value
            }
        }
        "double" {
            if {[catch {validateNumber $value $options} value]} {
                lappend errors {*}$value
            }
        }
        "date" -
        "duration" -
        "view" -
        "message" -
        "channel" -
        "user" {
            set dataTypeCheck [format "::util::validate%s" \
                [string totitle $paramType]]
            if {[catch {$dataTypeCheck $value $options} value]} {
                lappend errors {*}$value
            }
        }
        "guild" {}
        default {
            puts "util::validateParamValue Error: Unknown param type: $type"
        }
    }

    if {[llength $errors] > 0} {return -code error $errors}
    return $value
}

# util::validateNumber --
#
#   Validates a number
#
# Arguments:
#   value     The number value to be validated.
#   options   Any other options for the number.
#   
# Results:
#   The number if valid, otherwise throws an error with a list of what is 
#   wrong.

proc util::validateNumber {value options} {
    set errors {}

    if {$options != ""} {
        array set check {}
        foreach condition $options {
            regexp {[<>=!]*[0-9]+} $condition - sign amount
            switch $sign {
                "" {
                    lappend check(in) $amount
                }
                "!" {
                    lappend check(ni) $amount
                }
                ">=" -
                ">" -
                "<=" -
                "<" {
                    lappend check(ineq) [list $sign $amount]
                }
                default {
                    set msg "An internal error occurred with the validation. "
                    append msg "The module called by the command used does not "
                    append msg "have proper validation checks."
                    lappend errors $msg
                    break
                }
            }
        }

        if {$errors != ""} {
            set pass 1

            if {$check("in") != "" && $value ni $check(in)} {
                set msg "Invalid value for parameter $param. The value must be "
                append msg "one of [join $check(in) {, }]."
                set pass 0
            }

            if {$pass && $check("ni") != "" && $value in $check(ni)} {
                set msg "Invalid value for parameter $param. The value must not"
                append msg " be one of [join $check(ni) {, }]."
                set pass 0
            }

            foreach {sign amount} $check(ineq) {
                if {$pass && ![expr "$value $sign $amount"]} {
                    set msg "Invalid value for parameter $param. The value must"
                    append msg " be %s $amount."
                    array set repl {
                        ">=" "at least"
                        ">" "greater than"
                        "<=" "at most"
                        "<" "less than"
                    }
                    set msg [format $msg $repl($sign)]
                    set pass 0
                }
            }
            lappend errors $msg
        }
    }

    if {[llength $errors] > 0} {return -code error $errors}
    return $value
}

# util::validateDate --
#
#   Validates a date
#
# Arguments:
#   value     The date value to be validated.
#   options   Any other options for the date.
#   
# Results:
#   The date as epoch if valid, otherwise throws an error with a list of what is
#   wrong.

proc util::validateDate {value options} {
    set errors {}

    

    if {[llength $errors] > 0} {return -code error $errors}
    return $value
}

# util::validateDuration --
#
#   Validates a duration
#
# Arguments:
#   value     The duration value to be validated.
#   options   Any other options for the duration.
#   
# Results:
#   The duration in seconds if valid, otherwise throws an error with a list of 
#   what is wrong.

proc util::validateDuration {value options} {
    set errors {}

    set re [join [lmap x {y M w d h m s} {set x "(?:(\\d+)$x)?"}] ""]
    set durations {
        d(year) d(month) d(week) d(day) d(hour) d(minute) d(second)
    }
    if {[regexp "^$re\$" $value - {*}$durations]} {
        set now [clock seconds]
        set duration [lmap {k v} [array get d] {
            if {$v == ""} continue
            set r "$v $k"
        }]
        set value [clock add $now {*}[join $duration]]
    } elseif {[regexp {^perm(?:anent)?$} $value]} {
        set value "perm"
    } else {
        set msg "Invalid duration. A duration can only contain positive"
        append msg " integers and the following measures: year (y), "
        append msg "month (M), week (w), day (d), hour (h), minute (m),"
        append msg " second (s), in order of longest duration to "
        append msg "shortest duration e.g. a duration of 1y2M3w4d5h6m7s"
        append msg " will impose a ban of 1 year, 2 months, 3 weeks, 4 "
        append msg "days, 5 hours, 6 minutes and 7 seconds. Use 'permanent' or"
        append msg " 'perm' to indicate an indefinite duration."
        lappend errors $msg
    }

    if {[llength $errors] > 0} {return -code error $errors}
    return $value
}

# util::validateView --
#
#   Validates a view
#
# Arguments:
#   value     The view value to be validated.
#   options   Any other options for the view.
#   
# Results:
#   The view dictionary if valid, otherwise throws an error with a list of 
#   what is wrong.

proc util::validateView {value options} {
    set errors {}

    if {$value == ""} {return ""}

    set values [split $value "|"]
    set re {^([^:,]+)(?::([^,]+))?(?:,(a(?:sc?)|d(?:esc)?))?$}
    set view {}
    foreach v $values {
        if {![regexp $re $v - column filter sort]} {
            set msg "Invalid view $v. A view must be in the format "
            append msg "**columnName**, **columnName:filter**, "
            append msg "**columnName,sortOrder** or "
            append msg "**coumnName:filter,sorOrder** (sortOrder must "
            append msg "be either **asc** or **desc**)"
            lappend errors $msg
            break
        } elseif {[string tolower $column] ni $options} {
            set msg "Invalid column name $column. Valid options are "
            append msg "$options."
            lappend errors $msg
            break
        }
        lappend view [dict create \
            column [string totitle $column] \
            filter $filter \
            sort $sort \
        ]
    }
    
    if {[llength $errors] > 0} {return -code error $errors}
    return $view
}

# util::validateMessage --
#
#   Validates a message ID
#
# Arguments:
#   value     The message ID to be validated.
#   options   Any other options for the message ID.
#   
# Results:
#   The message ID if valid, otherwise throws an error with a list of what is
#   wrong.

proc util::validateMessage {value options} {
    set errors {}

    

    if {[llength $errors] > 0} {return -code error $errors}
    return $value
}

# util::validateChannel --
#
#   Validates a channel
#
# Arguments:
#   value     The channel value to be validated. Can be a channel highlight or 
#             a plain channel ID.
#   options   Any required permissions the bot needs to have to proceed
#   
# Results:
#   The channel ID if valid, otherwise, raises an error with a list of what is 
#   wrong.

proc util::validateChannel {value options} {
    set errors {}

    if {[regexp {^(?:<#([0-9]+)>|([0-9]+))$} $value - m1 m2]} {
        set value $m1$m2

        set channelExists [guild eval {
            SELECT 1 FROM chan WHERE channelId = :value
        }]
        if {$channelExists == ""} {
            set msg "I don't have access to this channel, or "
            append msg "it is doesn't exist."
            lappend errors $msg
        # TODO: Update when hasPerm gets updated
        } elseif {
            ![::meta::hasPerm \
                [dict get [set ${::session}::self] id] $options]
        } {
            set msg "I don't have the necessary permissions on "
            append msg "this channel. I need the following: "
            # TODO: list readable permissions
            append msg ""
            lappend errors $msg
        }
    } else {
        upvar 3 guldId guildId
        set guildData {*}[guild eval {
            SELECT data FROM guild WHERE guildId = :guildId
        }]
        set channels [dict get $guildData channels]

        set chanNames [lmap x $channels {
            if {[dict get $x type] != 0} {
                set x ""
            } else {
                string tolower [dict get $x name]
            }
        }]
        
        set indices [lsearch -nocase -all -- $chanNames $channel]
        if {$indices == ""} {
            set msg "I don't have access to this channel, or "
            append msg "it is doesn't exist"
            lappend errors $msg
        } elseif {[llength $indices] > 1} {
            set msg "More than one channel matched the specified "
            append msg "channel. Tag the channel or use its ID."
            lappend errors $msg
        # TODO: Update when hasPerm gets updated
        } elseif {
            ![::meta::hasPerm \
                [dict get [set ${::session}::self] id] $options]
        } {
            set msg "I don't have the necessary permissions on "
            append msg "this channel. I need the following: "
            # TODO: list readable permissions
            append msg ""
            lappend errors $msg
        } else {
            set idx [lsearch -nocase $chanNames $channel]
            set value [dict get [lindex $channels $idx] id]
        }
    }

    if {[llength $errors] > 0} {return -code error $errors}
    return $value
}


# util::validateUser --
#
#   Validates a user
#
# Arguments:
#   value     The user value to be validated. Can be a user highlight, nick
#             highlight, plain user ID, username, nick or "me".
#   options   Options for a user, typicailly can exclude bots or self
#   
# Results:
#   The user ID if valid, otherwise, raises an error with a list of what is 
#   wrong

proc util::validateUser {value options} {
    set errors {}

    if {[regexp {^(?:<@!?([0-9]+)>|([0-9]+))$} $value - m1 m2]} {
        set value $m1$m2

        set userExists [guild eval {
            SELECT 1 FROM users WHERE userId = :value
        }]
        if {$userExists == ""} {
            lappend errors "This user doesn't exist."
        }
        upvar 4 guildId guildId
        set guildData {*}[guild eval {
            SELECT data FROM guild WHERE guildId = :guildId
        }]
        set users [dict get $guildData members]
        
        upvar 4 userId userId
        set userIds [lmap x $users {
            if {
                "!bot" in $options && [dict get $x user bot] eq "true"
            } {
                continue
            } elseif {
                "!self" in $options && [dict get $x user id] eq $userId
            } {
                continue
            }
            dict get $x user id
        }]

        if {$value ni $userIds} {
            lappend errors "This user doesn't exist."
        }
    } elseif {$value eq "me"} {
        upvar 4 userId userId
        set value $userId
    } else {
        upvar 4 guildId guildId
        set guildData {*}[guild eval {
            SELECT data FROM guild WHERE guildId = :guildId
        }]
        set users [dict get $guildData members]
        
        set nameDict {}
        foreach u $users {
            if {
                "!bot" in $options && [dict get $u user bot] eq "true"
            } {
                continue
            } elseif {
                "!self" in $options && [dict get $u user id] eq $userId
            } {
                continue
            }
            dict set nameDict [dict get $u user username] \
                [dict get $u user id]
            if {[dict exists $u nick] && [dict get $u nick] != null} {
                dict set nameDict [dict get $u nick] \
                    [dict get $u user id]
            }
        }

        if {$value ni [dict keys $nameDict]} {
            lappend errors "This user doesn't exist."
        } else {
            set ids [dict get $namedict $value]
            if {[llength $ids] > 1} {
                set msg "More than one user matched the specified name."
                append msg " Tag the user or use their ID."
                lappend errors $msg
            } else {
                set value $ids
            }
        }
    }

    if {[llength $errors] > 0} {return -code error $errors}
    return $value
}




# util::saveAttachment --
#
#   Saves an attachment to the attachments directory
#
# Arguments:
#   fileName  Filename for the attachment consisting of the message ID and the 
#             actual file name
#   token     http token returned by ::http::geturl
#
# Results:
#   None

proc util::saveAttachment {fileName token} {
    set data [::http::data $token]
    ::http::cleanup $token

    if {![file isdirectory attachments]} {file mkdir attachments}

    set fOut [open [file join attachments $fileName] w]
    fcondigure $fOut -translation binary
    puts -nonewline $fOut $data
    close $fOut
}

# util::deleteFiles --
#
#   Deletes files
#
# Arguments:
#   paths     List of paths for the files to be deleted
#
# Results:
#   None

proc util::deleteFiles {paths} {
    foreach path paths {
        catch {file delete -force $path}
    }
}

# util::formatTime --
#
#   Formats time to how long ago the provided time is to the present time
#
# Arguments:
#   duration   Unix time to be formatted
#
# Results:
#   Time formatted. E.g. +1 day(s) 2h3m4s

proc util::formatTime {duration} {
    set s [expr {$duration % 60}]
    set i [expr {$duration / 60}]
    set m [expr {$i % 60}]
    set i [expr {$i / 60}]
    set h [expr {$i % 24}]
    set d [expr {$i / 24}]
    return [format "%+d day(s) %02dh%02dm%02ds" $d $h $m $s]
}

# util::shuffle --
#
#   Shuffles a list. Based on shuffle10a see shuffle10a
#   https://wiki.tcl-lang.org/page/Shuffle+a+list
#
# Arguments:
#   items     List to be shuffled
#
# Results:
#   items     Shuffled list

proc util::shuffle {items} {   
    set len [llength $items]
    while {$len} {
        set n [expr {int($len*rand())}]
        set tmp [lindex $items $n]
        lset items $n [lindex $items [incr len -1]]
        lset items $len $tmp
    }
    return $items
}

# util::cleanChanName --
#
#   Returns a valid Discord channel name. Discord requires a channel name to
#   consist of letters, underscores and dashes only
#
# Arguments:
#   name     Name of the channel to be created
#
# Results:
#   name     Valid discord channel name

proc util::cleanChanName {name} {
    set name [string tolower [regsub -all -nocase {[^a-z0-9_-]} $name {}]]
    if {$name == ""} {
        return -code error "Invalid channel name"
    } else {
        return $name
    }
}

# util::formatTable --
#
#   Returns text formatted as table in discord's code block feature based on 
#   headers, rows and a view sub-syntax
#
# Arguments:
#   header   List of headers for the table with their types
#   rows     List of rows for the table
#   view     View sub-syntax to indicate which columns to display, which values 
#            to filter, which order to sort the rows and the max size of a row 
#            in terms of characters (defaults to 70 characters)
#
# Results:
#   text     Formatted table

proc util::formatTable {header rows view} {
    upvar guildId guildId userId userId
    set tableHeader {}
    array set max {}
    array set filter {}
    array set sort {}

    foreach column $view {
        if {$column eq "Size"} {
            set size [dict get $column filter]
            continue
        }
        set colName [dict get $column column]
        set filter($colName) [dict get $column filter]
        set sort($colName) [dict get $column sort]
        lappend tableHeader $colName
        set max($colName) [string length $colName]
    }

    set tableRows {}
    foreach row $rows {
        set skipRow 0
        set tableRow {}
        foreach colName $tableHeader {
            set colValue [dict get $row $colName]

            set colType [dict get $header $colName]
            switch $colType {
                "user" {
                    if {$colValue eq "me"} {set colValue $userId}
                    if {"Guild" ni $header} {
                        set colValue \
                            [::meta::getUsernameNick $colValue $guildId]
                    } else {
                        set colValue \
                            [::meta::getUsernameNick $colValue $guildId "%s"]
                    }
                }
                "guild" {
                    set guildData {*}[guild eval {
                        SELECT data FROM guild WHERE guildId = :guildId
                    }]
                    set colValue [dict get $guildData name]
                }
                "date" {
                    # To convert to a format maybe so the filter can work on
                    # dates in formats other than unix
                }
                "text" {}
            }

            # Only supports equality filter on one value
            if {$filter($colName) != "" && $filter($colName) != $colValue} {
                set skipRow 1
                break
            }

            lappend tableRow $colValue
            set max($colName) [expr {
                max([string length $colVaue], $max($colName))
            }]
        }

        if {$skipRow} {continue}
        lappend tableRows $tableRow
    }

    set table {}
    set formats {}
    set row {}

    for {set i 0} {$i < [llength $tableHeader]} {incr i} {
        set colName [lindex $tableHeader $i]
        set colType [dict get $header $colname]

        switch $sort(colName) {
            "asc" {set order "-increasing"}
            "desc" {set order "-decreasing"}
            default {set order ""}
        }
            
        if {$colType in {date int}} {
            if {$order != ""} {
                set tableRows [lsort $order -integer -index $i $tableRows]
            }
            set format "%$max($colName)s"
        } elseif {$colType eq "double"} {
            if {$order != ""} {
                set tableRows [lsort $order -real -index $i $tableRows]
            }
            set format "%$max($colName)s"
        } else {
            if {$order != ""} {
                set tableRows [lsort $order -index $i $tableRows]
            }
            set format "%-$max($colName)s"
        }
        lappend formats $format
        lappend row [format $format $colName]
    }

    set formatString [join $formats " "]
    set curSize [string length [join $row " "]]
    
    if {$curSize > $size} {
        set textIds [lsearch -all $header text]
        set textCols [lmap id $textIds {lindex $header $id-1}]
        set actualCols [lmap header $tableHeader {
            if {$header in $textCols} {
                set header
            } else {
                continue
            }
        }]
        set textSizes [lmap col $actualCols {set max($col)}]
        set minSizes [lmap size $textSizes {expr {min($size,20)}}]
        set adjust [lmap t $textSizes m $minSizes {expr {$t-$m}}]
        set totalAdjust [::tcl::mathop::+ {*}$adjust]
        if {$totalAdjust > 0} {
            set diff [expr {$curSize - $size}]
            if {$totalAjust <= $diff} {
                set newSizes $minSizes
            } else {
                set totalMinSize [::tcl::mathop::+ {*}$minSizes]
                set newSizes {}
                for {set i 0} {$i < [llength $adjust]} {incr i} {
                    if {[lindex $adjust $i] == 0} {
                        lappend newSizes [lindex $minSizes $i]
                    } else {
                        lappend newSizes [expr {
                            [lindex $minSizes $i]/$totalMinSizes*$diff
                        }]
                    }
                }
            }
        }

        for {set i 0} {$i < [llength $actualCols]} {incr i} {
            set max($col) [lindex $minSizes $i]
        }

        set finalFormats {}
        for {set i 0} {$i < [llength $tableHeader]} {incr i} {
            set colName [lindex $tableHeader $i]
            set colType [dict get $header $colName]
            if {$colType eq "text"} {
                lappend finalFormats "%-$max($colName)s"
            } else {
                lappend finalFormats [lindex $formats $i]
            }
        }
        set formatString [join $finalFormats " "]
    }

    lappend table [join $row " "]
    
    foreach tableRow $tableRows {
        # not correct, needs to wrap text
        lappend table [format $formatString {*}$tableRow]
    }

    return "```[join $table \n]```"
}