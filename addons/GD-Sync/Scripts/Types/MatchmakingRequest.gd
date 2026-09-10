## Builder for a matchmaking search passed to [method MultiplayerClient.matchmaking_start].
## [br][br]Construct a request, optionally chain configuration methods, then start matchmaking and handle
## [signal MultiplayerClient.matchmaking_started], [signal MultiplayerClient.matchmaking_status_changed],
## [signal MultiplayerClient.matchmaking_match_found], [signal MultiplayerClient.matchmaking_failed], and
## [signal MultiplayerClient.matchmaking_cancelled]. Starting a new request cancels any active one. Closed
## lobbies are never joined.
## [br][br]The constructor [code]player_limit[/code] is the maximum lobby size. [method set_min_players]
## controls how many queued players are required before a match lobby is created (default: equal to the
## player limit). After creation, more matching players can join while the lobby stays open.
## [br][br][b]Methods:[/b] [method set_required_tags], [method set_search_mode],
## [method set_min_players], [method set_timeout], [method set_skill_rating], [method set_skill_range],
## [method clear_skill_matching], [method set_lobby_data]. Configuration
## methods return this request so calls can be chained.
## [br][br][codeblock]
## var request := MatchmakingRequest.new(8)
## request.set_min_players(2)
## request.set_required_tags({"Mode": "PvP"})
## request.set_timeout(60.0)
## GDSync.matchmaking_start(request)
## [/codeblock]
class_name MatchmakingRequest
extends RefCounted

#Copyright (c) 2023-present GD-Sync.
#All rights reserved.
#
#Redistribution and use in source form, with or without modification,
#are permitted provided that the following conditions are met:
#
#1. Redistributions of source code must retain the above copyright notice,
#   this list of conditions and the following disclaimer.
#
#2. Neither the name of GD-Sync nor the names of its contributors may be used
#   to endorse or promote products derived from this software without specific
#   prior written permission.
#
#THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY
#EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
#OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT
#SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
#INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED
#TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR
#BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
#CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN
#ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
#SUCH DAMAGE.

## Where a request may find players.
enum SearchMode {
	## Only join existing public lobbies that match tags and player limit. Fails with
	## [code]NO_MATCH[/code] if none are available.
	PUBLIC_ONLY,
	## Try public lobbies first, then wait in the matchmaking queue. This is the default.
	PUBLIC_THEN_MATCHMAKE,
	## Skip public lobbies and only use the matchmaking queue.
	MATCHMAKE_ONLY,
}

var _player_limit: int
var _min_players: int = 0
var _required_tags: Dictionary = {}
var _search_mode: SearchMode = SearchMode.PUBLIC_THEN_MATCHMAKE
var _timeout_seconds: float = 0.0
var _initial_lobby_data: Dictionary = {}
var _uses_skill: bool = false
var _skill_rating: float = 0.0
var _initial_skill_range: float = 0.0
var _maximum_skill_range: float = 0.0
var _skill_expansion_per_second: float = 0.0


## Creates a request whose lobbies hold up to [param player_limit] players.
## [br][br]Until [method set_min_players] is called, the minimum to create a lobby equals
## [param player_limit]. Must be greater than [code]0[/code] and within your plan limit.
func _init(player_limit: int) -> void:
	_player_limit = player_limit
	_min_players = player_limit


## Sets all required tags at once, matching [method MultiplayerClient.lobby_create] tags.
## [br][br]Public lobbies and queued players must include every entry. Replaces any previously
## set tags. Pass an empty dictionary to clear. Returns this request for chaining.
func set_required_tags(tags: Dictionary) -> MatchmakingRequest:
	_required_tags = tags.duplicate(true)
	return self


## Sets whether to search public lobbies, the matchmaking queue, or both.
## [br][br]See [enum SearchMode]. Defaults to [constant SearchMode.PUBLIC_THEN_MATCHMAKE].
## Returns this request for chaining.
func set_search_mode(mode: SearchMode) -> MatchmakingRequest:
	_search_mode = mode
	return self


## Sets how many queued players are required before a match lobby is created.
## [br][br]Lobby capacity remains the constructor player limit. For example, a limit of [code]8[/code]
## with a minimum of [code]2[/code] creates a lobby at two players; others may join until the lobby
## is full or closed. Must be between [code]1[/code] and the player limit. Defaults to the full
## player limit. Returns this request for chaining.
func set_min_players(min_players: int) -> MatchmakingRequest:
	_min_players = min_players
	return self


## Sets how long to wait before failing with [code]TIMEOUT[/code].
## [br][br]Use [code]0.0[/code] to wait indefinitely. Returns this request for chaining.
func set_timeout(seconds: float) -> MatchmakingRequest:
	_timeout_seconds = seconds
	return self


## Enables skill-based matching using this player's rating.
## [br][br]If never called, skill is ignored. Use with [method set_skill_range]. Returns this request
## for chaining.
func set_skill_rating(rating: float) -> MatchmakingRequest:
	_uses_skill = true
	_skill_rating = rating
	return self


## Configures the allowed skill distance from [method set_skill_rating].
## [br][br]The allowed range starts at [param initial] and may grow toward [param maximum] by
## [param expansion_per_second] while waiting. Expansion is applied when candidates are evaluated.
## Returns this request for chaining.
func set_skill_range(initial: float, maximum: float, expansion_per_second: float = 0.0) -> MatchmakingRequest:
	_initial_skill_range = initial
	_maximum_skill_range = maximum
	_skill_expansion_per_second = expansion_per_second
	return self


## Disables skill matching so only tags, limits, and search mode apply.
## [br][br]Returns this request for chaining.
func clear_skill_matching() -> MatchmakingRequest:
	_uses_skill = false
	return self


## Sets private lobby data at once, matching [method MultiplayerClient.lobby_create] data.
## [br][br]Applied only to lobbies created by matchmaking (not when joining public lobbies).
## Replaces any previously set data. Pass an empty dictionary to clear. Returns this request for chaining.
func set_lobby_data(data: Dictionary) -> MatchmakingRequest:
	_initial_lobby_data = data.duplicate(true)
	return self


## Returns whether this request can be started. Used internally by the plugin.
## [br][br]Invalid requests fail with [code]INVALID_REQUEST[/code].
func _is_valid() -> bool:
	if _player_limit <= 0:
		return false
	var min_players := _min_players if _min_players > 0 else _player_limit
	if min_players <= 0 or min_players > _player_limit:
		return false
	if _search_mode < SearchMode.PUBLIC_ONLY or _search_mode > SearchMode.MATCHMAKE_ONLY:
		return false
	if _timeout_seconds < 0.0:
		return false
	if var_to_bytes(_required_tags).size() > 2048:
		return false
	if var_to_bytes(_initial_lobby_data).size() > 8192:
		return false
	if _initial_skill_range < 0.0 or _maximum_skill_range < _initial_skill_range:
		return false
	if _skill_expansion_per_second < 0.0:
		return false
	return true


## Serializes this request for the server. Used internally by the plugin.
func _to_dictionary() -> Dictionary:
	var min_players := _min_players if _min_players > 0 else _player_limit
	var request := {
		"PlayerLimit": _player_limit,
		"MinPlayers": min_players,
		"RequiredTags": _required_tags.duplicate(true),
		"SearchMode": int(_search_mode),
		"TimeoutSeconds": _timeout_seconds,
		"InitialLobbyData": _initial_lobby_data.duplicate(true),
		"UsesSkill": _uses_skill,
	}
	if _uses_skill:
		request["SkillRating"] = _skill_rating
		request["InitialSkillRange"] = _initial_skill_range
		request["MaximumSkillRange"] = _maximum_skill_range
		request["SkillExpansionPerSecond"] = _skill_expansion_per_second
	return request
