#!/bin/sh
# This line and the trailing backslash  is required so that tclsh ignores the next line \
exec tclsh8.6 "$0" "${1+"$@"}"

# tclqBot.tcl --
#
#       This file implements the Tcl code for a Discord bot written with the
#       discord.tcl library.
#
# Copyright (c) 2016, Yixin Zhang
#
# See the file "LICENSE" for information on usage and redistribution of this
# file.

package require Tcl 8.6
package require sqlite3
package require logger

set scriptDir [file dirname [info script]]
lappend ::auto_path "${scriptDir}/discord/"
package require discord

# to remove later
source "${scriptDir}/sandbox_procs.tcl"
# Set ownerId and token variables
source "${scriptDir}/private.tcl"

# Link to manage discord bots
# https://discordapp.com/developers/applications/me
# Live bot invite (defaulted to server/guild admin rights)
# https://discordapp.com/oauth2/authorize?&client_id=204180397649559552&permissions=8&scope=bot
# Test bot invite (defaulted to server/guild admin rights)
# https://discordapp.com/oauth2/authorize?&client_id=204180300673187840&permissions=8&scope=bot

###### Custom scripts here ######

source [file join $scriptDir custom.tcl]
source [file join $scriptDir meta.tcl]
source [file join $scriptDir pokedex.tcl]
source [file join $scriptDir stats.tcl]
source [file join $scriptDir pogo.tcl]

###### End custom stuff ######

## Things beyond this point are mainly what was in the original script. I changed only a few things.

set log [logger::init tclqBot]
${log}::setlevel debug

# Open sqlite3 database
sqlite3 infoDb "${scriptDir}/info.sqlite3"
infoDb eval {
  CREATE TABLE IF NOT EXISTS procs(
    guildId TEXT,
    name BLOB,
    args BLOB,
    body BLOB,
    UNIQUE(guildId, name) ON CONFLICT REPLACE
  )
}
infoDb eval {
  CREATE TABLE IF NOT EXISTS vars(
    guildId TEXT PRIMARY KEY,
    list BLOB
  )
}
infoDb eval {
  CREATE TABLE IF NOT EXISTS bot(
    guildId TEXT PRIMARY KEY,
    trigger BLOB
  )
}
infoDb eval {
  CREATE TABLE IF NOT EXISTS perms(
    guildId TEXT,
    userId TEXT PRIMARY KEY,
    allow BLOB
  )
}
infoDb eval {
  CREATE TABLE IF NOT EXISTS callbacks(
    guildId TEXT PRIMARY KEY,
    dict BLOB
  )
}
infoDb eval {
  CREATE INDEX IF NOT EXISTS procsGuildIdIdx ON procs(guildId)
}

proc logDebug { text } {
  variable debugFile
  variable debugLog
  variable maxSize
  if {[file size $debugFile] >= $maxSize} {
    close $debugLog
    set fileName "${debugFile}.[clock milliseconds]"
    if {[catch {file copy $debugFile $fileName} res]} {
      puts stderr $res
      set suffix 0
      while {$suffix < 10} {
        if {[catch {file copy $debugFile ${fileName}.${suffix}} res]} {
          puts stderr $res
        } else {
          break
        }
      }
    }
    if {[catch {open $debugFile "w"} debugLog]} {
      puts stderr $debugLog
      set debugLog {}
    }
  }
  if {$debugLog eq {}} {
    return
  }
  puts $debugLog "[clock format [clock seconds] -format {[%Y-%m-%d %T]}] $text"
  flush $debugLog
}

# Lambda for "unique" number
coroutine id apply { { } {
  set x 0
  while 1 {
    yield $x
    incr x
  }
}}

proc setupSandboxEval { sandbox sessionNs data } {
  set channel_id [dict get $data channel_id]
  set guild_id [dict get [set ${sessionNs}::channels] $channel_id]
  set guild [dict get [set ${sessionNs}::guilds] $guild_id]
  set channels [dict get $guild channels]
  set channel {}
  foreach chan $channels {
    if {[dict get $chan id] eq $channel_id} {
      set channel $chan
      break
    }
  }
  set user_id [dict get $data author id]
  foreach varName [list data channel_id guild_id guild channel user_id] {
    $sandbox eval [list set ::$varName [set $varName]]
  }
  foreach varName [list author content] {
    $sandbox eval [list set ::$varName [dict get $data $varName]]
  }
}

proc sandboxEval { sessionNs data script } {
  variable log
  set channelId [dict get $data channel_id]
  set guildId [dict get [set ${sessionNs}::channels] $channelId]
  set sandbox [dict get $::guildInterps $guildId]
  setupSandboxEval $sandbox $sessionNs $data
  $sandbox limit time -seconds [expr {[clock seconds] + 2}]
  catch {
    $sandbox eval [list uplevel #0 $script]
  } res
  $sandbox limit time -seconds {}
  if {![regexp "^\n*$" $res]} {
    set resCoro [discord sendMessage $sessionNs $channelId $res 1]
    if {$resCoro eq {}} {
      ${log}::warning "[info coroutine]: No result coroutine returned."
      return
    }
    yield $resCoro
    set response [$resCoro]
    set resData [lindex $response 0]
    if {$resData eq {} || ![dict exists $resData id]} {
      array set state [lindex $response 1]
      ${log}::error "${state(http)}: ${state(body)}"
    } else {
      set messageId [dict get $resData id]
      ${log}::debug "handlePlease: Sent message ID: $messageId"
    }
  }
}

proc getTrigger { guildId } {
  return [dict get $::guildBotTriggers $guildId]
}

proc setTrigger { guildId pattern } {
  dict set ::guildBotTriggers $guildId $pattern
  infoDb eval {INSERT OR REPLACE INTO bot VALUES($guildId, $pattern)}
}

proc handleChanEvnt { sessionNs data text } {
  set channelId [dict get $data channel_id]
  set guildId [dict get $data guild_id]
  set userId [dict get $data author id]
  switch -regexp -nocase -- $text {
    {^o/} {
      if {$userId == $::ownerId} {::custom::wave $channelId}
    }
    {^!} {
      ::meta::command $data $text $channelId $guildId $userId
    }
    {^@delete} {
      set msg_id [dict get $data id]
      ::meta::logDelete $guildId $msg_id $channelId
    }
    {^@msgedit} {
      ::meta::logMsgEdit $data
    }
    {^(?:y(?:es)?|no?)} {
      ::pogo::command
    }
  }
}

proc handleGuildEvnt {sessionNs data text} {
  set guildId [dict get $data guild_id]
  set userId [dict get $data user id]
  switch -regexp -- $text {
    {join} {
      ::meta::welcomeMsg $guildId $userId
    }
    {part} {
      ::meta::partMsg $guildId $userId
    }
    {presence} {
      ::meta::logPresence $guildId $userId $data
    }
    {member} {
      ::meta::logMember $guildId $userId $data
    }
    {banremove} {
      ::meta::logBanRemove $guildId $userId
    }
  }
}

proc messageCreate { sessionNs event data } {
  set content [dict get $data content]
  set channelId [dict get $data channel_id]
  if {$channelId in [dict keys [set ${sessionNs}::dmChannels]]} {
    return
  }
  set guildId [dict get [set ${sessionNs}::channels] $channelId]
  set trigger [dict get $::guildBotTriggers $guildId]
  if {[regexp $::defaultTrigger $content -> text] || [regexp $trigger $content -> text]} {
    coroutine handleChanEvnt[::id] handleChanEvnt $sessionNs $data $text
  } elseif {[string match "!*" $content] || $content eq "o/" || $::pogo::silph(listen) != {}} {
    coroutine handleChanEvnt[::id] handleChanEvnt $sessionNs $data $content
  }
}

proc guildCreate { sessionNs event data } {
  # Setup safe interp for "Please eval"
  set guildId [dict get $data id]
  dict set ::guildInterps $guildId [interp create -safe]
  set sandbox [dict get $::guildInterps $guildId]

  # Restore saved bot trigger regex
  set savedTriggers [infoDb eval {
    SELECT trigger FROM bot WHERE guildId IS $guildId
  }]
  set numTriggers [llength $savedTriggers]
  if {$numTriggers > 0} {
    if {$numTriggers > 1} {
      ${log}::error "More than one trigger found for guild $guildId!"
    }
    dict set ::guildBotTriggers $guildId [lindex $savedTriggers 0]
  } else {
    dict set ::guildBotTriggers $guildId $::defaultTrigger
    infoDb eval {INSERT INTO bot VALUES($guildId, $::defaultTrigger)}
  }
  set calls {
    getChannel modifyChannel deleteChannel getMessages getMessage sendMessage 
    uploadFile editMessage deleteMessage bulkDeleteMessages 
    editChannelPermissions deleteChannelPermission getChannelInvites 
    createChannelInvite triggerTyping getPinnedMessages pinMessage unpinMessage 
    getGuild modifyGuild getChannels createChannel changeChannelPositions 
    getMember getMembers addMember modifyMember modifyBotnick addGuildMemberRole
    removeGuildMemberRole kickMember getBans ban unban getRoles createRole 
    batchModifyRoles modifyRole deleteRole getPruneCount prune 
    getGuildVoiceRegions getGuildInvites getIntegrations createIntegration 
    modifyIntegration deleteIntegration syncIntegration getGuildEmbed 
    getGuildVanityUrl modifyGuildEmbed getAuditLog getCurrentUser getUser 
    modifyCurrentUser getGuilds leaveGuild getDMs createDM getConnections 
    getVoiceRegions sendDM closeDM
  }
  foreach call $calls {
    set args [list]
    if {$call in $::guildSpecificCalls} {
      lappend args $guildId
    }
    $sandbox alias ${call} apply {
      {sandbox call sessionNs args} {
        set coro ::${call}Coro
        set name ::${call}Result
        $sandbox eval [list set $name {}]
        set resCoro [coroutine $coro apply {
          {sandbox varName call sessionNs args} {
            set resCoro [discord $call $sessionNs {*}$args]
            if {$resCoro eq {}} {
              return
            }
            yield $resCoro
            lassign [$resCoro] data state
            $sandbox eval [list set $varName $data]
          }
        } $sandbox $name $call $sessionNs {*}$args]
        if {$resCoro eq {}} {
          return
        } else {
          $sandbox eval [list vwait $name]
          set res [$sandbox eval [list set $name]]
          $sandbox eval [list unset $name]
          return $res
        }
      }
    } $sandbox $call $sessionNs {*}$args
  }
  $sandbox alias getPermList discord getPermList
  $sandbox alias addPermissions discord setPermissions
  $sandbox alias hasPermissions discord hasPermissions
  $sandbox alias permDesc discord getPermissionDescription
  $sandbox alias snowflakeTime apply {
    {snowflake} {
      return [getSnowflakeUnixTime $snowflake $::discord::Epoch]
    }
  }
  $sandbox alias getMsgFormat discord getMessageFormat
  $sandbox alias setPerms setMemberPermissions $sessionNs $guildId
  $sandbox alias getPerms getMemberPermissions $sessionNs $guildId
  $sandbox alias addPerms addMemberPermissions $sessionNs $guildId
  $sandbox alias delPerms delMemberPermissions $sessionNs $guildId
  $sandbox alias getCallbacks getGuildCallbacks $guildId
  $sandbox alias addCallback addGuildCallback $sessionNs $guildId
  $sandbox alias delCallback delGuildCallback $sessionNs $guildId
  set protectCmds [$sandbox eval info commands]
  set currentVars [$sandbox eval info vars]
  infoDb eval {SELECT * FROM vars WHERE guildId IS $guildId} vars {
    dict for {name value} $vars(list) {
      if {$name ni $currentVars} {
        $sandbox eval [list set $name $value]
      }
    }
  }
  set totalProcsSize 0
  # Restore saved procs
  infoDb eval {SELECT * FROM procs WHERE guildId IS $guildId} proc {
    $sandbox eval [list proc $proc(name) $proc(args) $proc(body)]
    incr totalProcsSize [string length [array get proc]]
  }
  dict set ::guildSavedProcsSize $guildId $totalProcsSize
  foreach cmd [list proc rename] {
    $sandbox hide $cmd
  }
  $sandbox alias proc procSave $sandbox $guildId $protectCmds
  $sandbox alias rename renameSave $sandbox $guildId $protectCmds
  infoDb eval {SELECT * FROM callbacks WHERE guildId IS $guildId} callbacks {
    dict for {event callback} $callbacks(dict) {
      dict set ::guildCallbacks $guildId $event $callback
      discord setCallback $sessionNs $event ::mainCallbackHandler
    }
  }
  infoDb eval {SELECT * FROM perms WHERE guildId IS $guildId} perm {
    dict set ::guildPermissions $perm(guildId) $perm(userId) $perm(allow)
  }
  setMemberPermissions $sessionNs $guildId [dict get $data owner_id] \
    [$sandbox eval info commands]
  # Temporary
  catch {
    setMemberPermissions $sessionNs $guildId $::ownerId \
      [$sandbox eval info commands]
  }
}

proc ::mainCallbackHandler { sessionNs event data } {
  ::meta::bump $event
  puts "$event\n$data\n"
  switch $event {
    GUILD_CREATE {
      ::guildCreate $sessionNs $event $data
      ::meta::buildLogs
    }
    CHANNEL_CREATE {
      ::meta::buildLogs [dict get $data id]
    }
    MESSAGE_CREATE {
      set channelId [dict get $data channel_id]
      if {$channelId in [dict keys [set ${sessionNs}::dmChannels]]} {
        set guildId $channelId
      } else {
        set guildId [dict get [set ${sessionNs}::channels] $channelId]
      }
      set content [dict get $data content]
      set id [dict get $data author id]
      ::meta::logChat $guildId [dict get $data id] $id $content \
        [dict get $data embeds] [dict get $data attachments]
      
      if {$id eq [dict get [set ${sessionNs}::self] id]} {
        return
      } else {
        if {![catch {dict get [set ${sessionNs}::users] $id} user]} {
          if {[dict exists $user bot] && [dict get $user bot] eq "true"} {
            return
          }
        }
        ::messageCreate $sessionNs $event $data
      }
    }
    MESSAGE_UPDATE {
      if {![dict exists $data type] || [dict get $data type] != 0} {return}
      coroutine handleChanEvnt[::id] handleChanEvnt $sessionNs $data "@msgedit"
    }
    MESSAGE_DELETE {
      dict set data author id ""
      coroutine handleChanEvnt[::id] handleChanEvnt $sessionNs $data "@delete"
    }
    READY -
    RESUMED -
    MESSAGE_DELETE_BULK -
    TYPING_START -
    USER_SETTINGS_UPDATE -
    USER_UPDATE {}
    GUILD_MEMBER_UPDATE {
      coroutine handleGuildEvnt[::id] handleGuildEvnt $sessionNs $data "member"
    }
    PRESENCE_UPDATE {
      coroutine handleGuildEvnt[::id] handleGuildEvnt $sessionNs $data "presence"
    }
    GUILD_UPDATE -
    GUILD_DELETE {}
    GUILD_MEMBER_ADD -
    GUILD_MEMBER_REMOVE {
      set userId [dict get $data user id]
      if {$userId ne [dict get [set ${sessionNs}::self] id]} {
        if {![catch {dict get [set ${sessionNs}::users] $userId} user]} {
          if {[dict exists $user bot] && [dict get $user bot] eq "true"} {
            return
          }
        }
        switch $event {
          GUILD_MEMBER_ADD     {set action "join"}
          GUILD_MEMBER_REMOVE  {set action "part"}
        }
        coroutine handleGuildEvnt[::id] handleGuildEvnt $sessionNs $data $action
      }
    }
    GUILD_BAN_ADD {}
    GUILD_BAN_REMOVE {
      coroutine handleGuildEvnt[::id] handleGuildEvnt $sessionNs $data banremove
    }
    default {}
  }
}

proc ::rolesGet {} {
  discord getRoles ::discord::session::0 141472246937026560 1
}

proc registerCallbacks {sessionNs} {
  discord setCallback $sessionNs READY                       ::mainCallbackHandler
  discord setCallback $sessionNs RESUMED                     ::mainCallbackHandler
  discord setCallback $sessionNs CHANNEL_CREATE              ::mainCallbackHandler
  discord setCallback $sessionNs CHANNEL_UPDATE              ::mainCallbackHandler
  discord setCallback $sessionNs CHANNEL_DELETE              ::mainCallbackHandler
  discord setCallback $sessionNs GUILD_CREATE                ::mainCallbackHandler
  discord setCallback $sessionNs GUILD_UPDATE                ::mainCallbackHandler
  discord setCallback $sessionNs GUILD_DELETE                ::mainCallbackHandler
  discord setCallback $sessionNs GUILD_BAN_ADD               ::mainCallbackHandler
  discord setCallback $sessionNs GUILD_BAN_REMOVE            ::mainCallbackHandler
  discord setCallback $sessionNs GUILD_EMOJIS_UPDATE         ::mainCallbackHandler
  discord setCallback $sessionNs GUILD_INTEGRATIONS_UPDATE   ::mainCallbackHandler
  discord setCallback $sessionNs GUILD_MEMBER_ADD            ::mainCallbackHandler
  discord setCallback $sessionNs GUILD_MEMBER_REMOVE         ::mainCallbackHandler
  discord setCallback $sessionNs GUILD_MEMBER_UPDATE         ::mainCallbackHandler
  discord setCallback $sessionNs GUILD_MEMBERS_CHUNK         ::mainCallbackHandler
  discord setCallback $sessionNs GUILD_ROLE_CREATE           ::mainCallbackHandler
  discord setCallback $sessionNs GUILD_ROLE_UPDATE           ::mainCallbackHandler
  discord setCallback $sessionNs GUILD_ROLE_DELETE           ::mainCallbackHandler
  discord setCallback $sessionNs MESSAGE_CREATE              ::mainCallbackHandler
  discord setCallback $sessionNs MESSAGE_UPDATE              ::mainCallbackHandler
  discord setCallback $sessionNs MESSAGE_DELETE              ::mainCallbackHandler
  discord setCallback $sessionNs MESSAGE_DELETE_BULK         ::mainCallbackHandler
  discord setCallback $sessionNs PRESENCE_UPDATE             ::mainCallbackHandler
  discord setCallback $sessionNs TYPING_START                ::mainCallbackHandler
  discord setCallback $sessionNs USER_SETTINGS_UPDATE        ::mainCallbackHandler
  discord setCallback $sessionNs USER_UPDATE                 ::mainCallbackHandler
  discord setCallback $sessionNs VOICE_STATE_UPDATE          ::mainCallbackHandler
  discord setCallback $sessionNs VOICE_SERVER_UPDATE         ::mainCallbackHandler
  discord setCallback $sessionNs MESSAGE_REACTION_ADD        ::mainCallbackHandler
  discord setCallback $sessionNs MESSAGE_REACTION_REMOVE     ::mainCallbackHandler
  discord setCallback $sessionNs MESSAGE_ACK                 ::mainCallbackHandler
  discord setCallback $sessionNs CHANNEL_PINS_ACK            ::mainCallbackHandler
  discord setCallback $sessionNs CHANNEL_PINS_UPDATE         ::mainCallbackHandler
}

# For console stdin eval
proc asyncGets {chan {callback ""}} {
  if {[gets $chan line] >= 0} {
    if {[string trim $line] ne ""} {
      if {[catch {uplevel #0 $line} out options]} {
        puts "$out\n$options"
      } else {
        puts $out
      }
    }
  }
  if [eof $chan] { 
    set ::forever 0
    return
  }
  puts -nonewline "% "
  flush stdout
}

# Ad-hoc log file size limiting follows
set debugFile "${scriptDir}/debug"
set debugLog {}
set maxSize [expr {4 * 1024**2}]

if {[catch {open $debugFile "a"} debugLog]} {
  puts stderr $debugLog
} else {
  ${discord::log}::logproc debug ::logDebug
}

# Set to 0 for a cleaner debug log.
discord::gateway logWsMsg 1
${discord::log}::setlevel debug

puts -nonewline "% "
flush stdout
fconfigure stdin -blocking 0 -buffering line
fileevent stdin readable [list asyncGets stdin]

# Assume a maximum of 2000 characters per proc. Of course procs can be defined
# through variables which can exceed the Discord limit.
set maxSavedProcsSize [expr {2**20}]
set defaultTrigger {^% Please (.*)$}

set guildBotTriggers [dict create]
set guildInterps [dict create]
set guildSavedProcsSize [dict create]
set guildPermissions [dict create]
set guildCallbacks [dict create]
set guildSpecificCalls {
  getGuild modifyGuild getChannels createChannel
  changeChannelPosition getMember getMembers addMember modifyMember
  kickMember getBans ban unban getRoles createRole batchModifyRoles
  modifyRole deleteRole getPruneCount prune getGuildVoiceRegions
  getGuildInvites getIntegrations createIntegration modifyIntegration
  deleteIntegration syncIntegration getGuildEmbed modifyGuildEmbed
  leaveGuild
}

namespace eval TraceExeTime {
  variable EnterTimes [dict create]
  variable Times [dict create]
}

proc TraceExeTime::Enter { cmdStr op } {
  variable EnterTimes
  lassign $cmdStr cmd
  dict set EnterTimes $cmd [clock microseconds]
}

proc TraceExeTime::Leave { cmdStr code result op } {
  set leaveTime [clock microseconds]
  variable EnterTimes
  variable Times
  lassign $cmdStr cmd
  set enterTime [dict get $EnterTimes $cmd]
  set duration [expr {$leaveTime - $enterTime}]
  dict lappend Times $cmd $duration
  puts "Last execution time for '$cmd': $duration us"
  Average $cmd
}

proc TraceExeTime::Average { command } {
  variable Times
  set allTimes [dict get $Times $command]
  set avgTime [expr {[::tcl::mathop::+ {*}$allTimes] / [llength $allTimes]}]
  puts "Average time from enter to leave for '$command': $avgTime us"
}

#trace add execution discord::gateway::Handler enter TraceExeTime::Enter
#trace add execution discord::gateway::Handler leave TraceExeTime::Leave
#trace add execution discord::ManageEvents enter TraceExeTime::Enter
#trace add execution discord::ManageEvents leave TraceExeTime::Leave

set startTime [clock seconds]

set session [discord connect $token ::registerCallbacks]

vwait forever

if {[catch {discord disconnect $session} res]} {
    puts stderr $res
}

dict for {guildId sandbox} $guildInterps {
  set vars [dict create]
  foreach var [$sandbox eval info vars] {
    if {[llength [array get $var]] > 0} {
      foreach {key value} [array get $var] {
        dict set vars "${var}($key)" $value
      }
    } else {
      dict set vars $var [$sandbox eval [list set $var]]
    }
  }
  infoDb eval {
    INSERT OR REPLACE INTO vars
    VALUES($guildId, $vars)
  }
}

close $debugLog
${log}::delete
infoDb close
