# anime-manga.tcl --
#
#       This file implements the Tcl code for anime and manga commands
#
# Copyright (c) 2019-2020, Jerry Yong
#
# See the file "LICENSE" for information on usage and redistribution of this
# file.

package require sqlite3
package require http
package require htmlparse
  
if {![namespace exists meta]} {
    puts "Failed to load anime-manga.tcl: Requires meta.tcl to be loaded."
    return
}

namespace eval anime {
    sqlite3 animedb "${scriptDir}/anime-manga/animedb.sqlite3"
    animedb eval {
        CREATE TABLE IF NOT EXISTS animefavs(
            userId text,
            animeName text,
            custom text,
            categories text
        )
    }
    animedb eval {
        CREATE TABLE IF NOT EXISTS latestanime(
            title text,
            link text,
            category text,
            torrent text,
            magnet text,
            size text,
            time text,
            seeders int,
            leechers int,
            downloads int,
            date int
        )
    }
    
    set afterIds                   [list]
    
    set anime(site)             "https://nyaa.si"
    set anime(favicon)          "/static/favicon.png"
    set anime(delay)            5
    set anime(limit-anime)      500
    set anime(ver)              1.0
}

proc anime::command {} {
    upvar data data text text channelId channelId guildId guildId userId userId
    switch [lindex $text 0] {
        "!subscribe" {
            
            subscribe [regsub {!subscribe *} $text {}]
        }
        "!unsubscribe" {
            unsubscribe [regsub {!unsubscribe *} $text {}]
        }
        "!viewsubs" {
            viewsubs
        }
        default {
            return 0
        }
    }
    return 1
}

proc anime::checksite {} {
    variable anime
    
    if {[catch {::http::geturl $anime(site)} token]} {
        after [expr {$anime(delay)*60*1000}] ::anime::checksite
        return
    }
    set file [::http::data $token]
    ::http::cleanup $token
    if {![regexp {<tbody>(.*?)</tbody>} $file - match]} {
        after [expr {$anime(delay)*60*1000}] ::anime::checksite
        return
    }
    set results [regexp -all -inline {<tr(?:.*?)>(.*?)</tr>} $match]
    
    set new [list]
    foreach {main sub} $results {
        set torrentInfo [regexp -all -inline {<td(?:.*?)>(.*?)</td>} $sub]
        set colNo 0
        array set animeInfo {}
        foreach {col info} $torrentInfo {
            switch $colNo {
                0 {regexp {title="([^\"]+)"} $info - animeInfo(category)}
                1 {
                    set s [regexp -all -inline \
                            {href="(.*?)".*? title="(.*?)"} $info]
                    foreach {m l t} $s {
                        set animeInfo(link) $l 
                        set animeInfo(title) $t
                    }
                }
                2 {
                    set links [regexp -all -inline {href="([^\"]+)"} $info]
                    lassign $links - animeInfo(torrent) - animeInfo(magnet)
                }
                3 {set animeInfo(size) $info}
                4 {set animeInfo(time) $info}
                5 {set animeInfo(seeders) $info}
                6 {set animeInfo(leechers) $info}
                7 {set animeInfo(downloads) $info}
            }
            incr colNo
        }
        lappend new [list $animeInfo(link) [array get animeInfo]]
    }
    set current [animedb eval {SELECT 1 FROM latestanime LIMIT 1}]
    set now [clock seconds]
    if {$current != 1} {
        # If it's the first time the command runs, we don't want to flood
        foreach ep $new {
            array set animeInfo [lindex $ep 1]
            animedb eval {INSERT INTO latestanime VALUES(
                :animeInfo(title),
                :animeInfo(link),
                :animeInfo(category),
                :animeInfo(torrent),
                :animeInfo(magnet),
                :animeInfo(size),
                :animeInfo(time),
                :animeInfo(seeders),
                :animeInfo(leechers),
                :animeInfo(downloads),
                :now
            )}
        }
    } else {
        foreach ep $new {
            array set animeInfo [lindex $ep 1]
            set old [animedb eval {
                SELECT 1 FROM latestanime WHERE link = :animeInfo(link)
            }]
            if {$old != 1} {
                set title "[encoding convertto utf-8 $animeInfo(title)]"
                set url "$anime(site)$animeInfo(link)"
                set desc "**$animeInfo(category)**\n"
                append desc "Size: $animeInfo(size) "
                append desc "\[Torrent\]($anime(site)$animeInfo(torrent))\n"
                append desc "Seeders: $animeInfo(seeders) Leechers: "
                append desc "$animeInfo(leechers) Downloads: "
                append desc "$animeInfo(downloads)"
                set embed [dict create \
                    title [::htmlparse::mapEscapes $title] \
                    url $url \
                    description $desc \
                    footer [dict create text $animeInfo(time) icon_url \
                        "$anime(site)$anime(favicon)" \
                    ] \
                ]

                metadb eval {
                    SELECT channelId FROM config WHERE type = 'anime'
                } arr {
                    ::meta::putGc [dict create embed $embed] 1 $arr(channelId)
                }
                
                animedb eval {SELECT * FROM animefavs} arr {
                    if {[string first $arr(animeName) $animeInfo(title)] > -1} {
                        set re {(.+) > (.+)}
                        if {
                            $arr(custom) ne ""
                            && [regexp $re $arr(custom) - f t]
                        } {
                            regsub $f $link $t link
                        }
                        coroutine ::meta::putDm[::id] ::meta::putDm \
                                $arr(userId) [dict create embed $embed] 1
                    }
                }
                animedb eval {INSERT INTO latestanime VALUES(
                    :animeInfo(title),
                    :animeInfo(link),
                    :animeInfo(category),
                    :animeInfo(torrent),
                    :animeInfo(magnet),
                    :animeInfo(size),
                    :animeInfo(time),
                    :animeInfo(seeders),
                    :animeInfo(leechers),
                    :animeInfo(downloads),
                    :now
                )}
            }
        }
    }
    
    while {
        [animedb eval {SELECT COUNT(*) FROM latestanime}] > $anime(limit-anime)
    } {
        set earliest [animedb eval {SELECT MIN(date) FROM latestanime}]
        animedb eval {DELETE FROM latestanime WHERE date = :earliest}
    }
    
    after [expr {$anime(delay)*60*1000}] ::anime::checksite
}

proc anime::subscribe {animeName} {
    upvar userId userId
    if {[string first "-format" $animeName] > -1} {
        regexp {^(.+?) -format (.+?)$} $animeName - name format
        if {![regexp {(.+) > (.+)} $format - f t]} {
            set msg "Invalid format. The format should be like: "
            append msg "```css\nfrom > to```."
            ::meta::putGc [dict create content $msg] 0
            return
        }
        if {[catch {regsub $f {test} $t} err]} {
        ::meta::putGc [dict create content \
                "Error with the regular expression: $err"] 0
        return
        }
    } else {
        lassign [list $animeName ""] name format
    }
    set subs [animedb eval {
        SELECT animeName, custom FROM animefavs WHERE animeName = :name
    }]
    if {[llength $subs] > 0} {
        lassign $subs cName cFormat
        if {$format eq "" && $cFormat eq ""} {
            set msg "You already are subscribed for $name!"
        } else {
            animedb eval {
                UPDATE animefavs SET custom = :format WHERE animeName = :name
            }
            set msg "Your subscription for $name has been updated!"
        }
    } else {
        animedb eval {INSERT INTO animefavs VALUES(:userId, :name, :format)}
        set msg "You have been subscribed for $name!"
    }
    ::meta::putGc [dict create content $msg] 1
}

proc anime::unsubscribe {animeName} {
    upvar userId userId
    set result [animedb eval {
        SELECT * FROM animefavs WHERE userId = :userId AND animeName = :animeName
    }]
    if {[llength $result] == 0} {
        if {$animeName eq "all"} {
            animedb eval {
                DELETE FROM animefavs WHERE userId = :userId
            }
            set msg "You have been unsubscribed for all anime!"
        } else {
            set msg "No such subscriptions was found..."
        }
    } else {
        animedb eval {
            DELETE FROM animefavs
            WHERE userId = :userId AND animeName = :animeName
        }
        set msg "You have been unsubscribed for $animeName!"
    }
    ::meta::putGc [dict create content $msg] 1
}

proc anime::viewsubs {} {
    upvar userId userId
    set results [animedb eval {
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
    ::meta::putGc [dict create content $msg] 1
}

proc anime::pre_reboot {} {
    variable afterIds
    foreach id $afterIds {
        after cancel $id
    }
}

#lappend ::anime::afterIds [after 10000 [list ::anime::checksite]]
puts "anime-manga.tcl v$::anime::anime(ver) loaded"