-- this file is an attempt to sanitize the somewhat crazy messages the server sends during match setup
local ServerMessages = {}

function ServerMessages.sanitizeMenuState(menuState)
  --[[
    "b_menu_state": {
        "character_is_random": "__RandomCharacter",
        "stage_is_random": "__RandomStage",
        "character_display_name": "",
        "cursor": "__Ready",
        "panels_dir": "panelhd_basic_mizunoketsuban",
        "ranked": true,
        "stage": "__RandomStage",
        "character": "__RandomCharacter",
        "level": 5,
        "inputMethod": "controller"
    },

    or 

    "character_is_random": "__RandomCharacter",
    "stage_is_random": "__RandomStage",
    "character_display_name": "Dragon",
    "cursor": "__Ready",
    "ready": true,
    "level": 5,
    "wants_ready": true,
    "ranked": true,
    "panels_dir": "panelhd_basic_mizunoketsuban",
    "character": "pa_characters_dragon",
    "stage": "pa_stages_wind",
    "loaded": true
  --]]

  local sanitized = { sanitized = true}
  sanitized.panelId = menuState.panels_dir
  sanitized.characterId = menuState.character
  if menuState.character_is_random ~= random_character_special_value then
    sanitized.selectedCharacterId = menuState.character_is_random
  end
  sanitized.stageId = menuState.stage
  if menuState.stage_is_random ~= random_stage_special_value then
    sanitized.selectedStageId = menuState.stage_is_random
  end
  sanitized.level = menuState.level
  sanitized.wantsRanked = menuState.ranked

  sanitized.wantsReady = menuState.wants_ready
  sanitized.hasLoaded = menuState.loaded
  sanitized.ready = menuState.ready

  -- ignoring cursor for now
  --sanitized.cursorPosCode = menuState.cursor
  -- categorically ignoring character display name


  return sanitized
end

function ServerMessages.sanitizeCreateRoom(message)
  -- how these messages look
  --[[
  "a_menu_state": {
        see sanitizeMenuState
    },
    "b_menu_state": {
        see sanitizeMenuState
    },
    "create_room": true,
    "your_player_number": 2,
    "op_player_number": 1,
    "ratings": [{
            "new": 1391,
            "league": "Silver",
            "old": 1391,
            "difference": 0
        }, {
            "league": "Newcomer",
            "placement_match_progress": "0/30 placement matches played.",
            "new": 0,
            "old": 0,
            "difference": 0
        }
    ],
    "opponent": "oh69fermerchan",
    "rating_updates": true
}
  ]]--
  local players = {}
  players[1] = ServerMessages.sanitizeMenuState(message.a_menu_state)
  -- the recipient is "you"!
  players[1].playerNumber = message.your_player_number
  players[1].name = config.name

  players[2] = ServerMessages.sanitizeMenuState(message.b_menu_state)
  players[2].name = message.opponent
  players[2].playerNumber = message.op_player_number

  if message.rating_updates then
    players[1].ratingInfo = message.ratings[1]
    players[2].ratingInfo = message.ratings[2]
  end

  return { create_room = true, sanitized = true, players = players}
end

function ServerMessages.toServerMenuState(player)
  -- what we're expected to send:
  --[[
    {
      "character_is_random": "__RandomCharacter", -- somewhat optional (bundles only)
      "stage_is_random": "__RandomStage",         -- somewhat optional (bundles only)
      "character_display_name": "Dragon",         -- I think not even stable is processing this one
      "cursor": "__Ready",                        -- this one uses a different grid system so I don't think it's worth the effort
      "ready": true,
      "level": 5,
      "wants_ready": true,
      "ranked": true,
      "panels_dir": "panelhd_basic_mizunoketsuban",
      "character": "pa_characters_dragon",
      "stage": "pa_stages_wind",
      "loaded": true
    }
  --]]
  local menuState = {}
  menuState.stage = player.settings.stageId
  menuState.character = player.settings.characterId
  menuState.panels_dir = player.settings.panelId
  menuState.wants_ready = player.settings.wantsReady
  menuState.ranked = player.settings.wantsRanked
  menuState.level = player.settings.level
  menuState.loaded = GAME.battleRoom.allAssetsLoaded
  menuState.ready = menuState.loaded and menuState.wants_ready
  menuState.cursor = "__Ready" -- play pretend

  return menuState
end

function ServerMessages.sanitizeSettings(settings)
  return
  {
    playerNumber = settings.player_number,
    level = settings.level,
    characterId = settings.character,
    panelId = settings.panels_dir,
    sanitized = true
  }
end

function ServerMessages.sanitizeStartMatch(message)
  --[[
    "ranked": false,
    "opponent_settings": {
        "character_display_name": "Bumpty",
        "player_number": 2,
        "level": 8,
        "panels_dir": "pdp_ta_common",
        "character": "pa_characters_bumpty"
    },
    "stage": "pa_stages_fire",
    "player_settings": {
        "character_display_name": "Blargg",
        "player_number": 1,
        "level": 8,
        "panels_dir": "panelhd_basic_mizunoketsuban",
        "character": "pa_characters_blargg"
    },
    "seed": 3245472,
    "match_start": true
  --]]
  local playerSettings = {}
  playerSettings[1] = ServerMessages.sanitizeSettings(message.player_settings)
  playerSettings[2] = ServerMessages.sanitizeSettings(message.opponent_settings)

  local matchStart = {
    playerSettings = playerSettings,
    seed = message.seed,
    ranked = message.ranked,
    stageId = message.stage,
    match_Start = true,
    sanitized = true
  }

  return matchStart
end

return ServerMessages