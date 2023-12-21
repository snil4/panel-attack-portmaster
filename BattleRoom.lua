local logger = require("logger")
local Player = require("Player")
local tableUtils = require("tableUtils")
local sceneManager = require("scenes.sceneManager")
local GameModes = require("GameModes")
local class = require("class")
local ServerMessages = require("network.ServerMessages")
local ClientMessages = require("network.ClientProtocol")
local ReplayV1 = require("replayV1")

-- A Battle Room is a session of matches, keeping track of the room number, player settings, wins / losses etc
BattleRoom = class(function(self, mode)
  assert(mode)
  self.mode = mode
  self.players = {}
  self.spectators = {}
  self.spectating = false
  self.trainingModeSettings = nil
  self.allAssetsLoaded = false
  self.ranked = false
  self.puzzles = {}
  self.state = 1
  if GAME.tcpClient:isConnected() then
    -- this is a bit naive but effective
    self.online = true
  end
end)

-- defining these here so they're available in network.BattleRoom too
-- maybe splitting BattleRoom wasn't so smart after all
BattleRoom.states = { Setup = 1, MatchInProgress = 2, Issue = 3 }


function BattleRoom.createFromMatch(match)
  local gameMode = {}
  gameMode.playerCount = #match.players
  gameMode.doCountdown = match.doCountdown
  gameMode.stackInteraction = match.stackInteraction
  gameMode.winConditions = deepcpy(match.winConditions)
  gameMode.gameOverConditions = deepcpy(match.gameOverConditions)
  gameMode.playerCount = #match.players

  local battleRoom = BattleRoom(gameMode)

  for i = 1, #match.players do
    battleRoom:addPlayer(match.players[i])
  end

  battleRoom.match = match
  battleRoom.match:start()
  battleRoom.state = BattleRoom.states.MatchInProgress

  return battleRoom
end

function BattleRoom.createFromServerMessage(message)
  local battleRoom
  -- two player versus being the only option so far
  -- in the future this information should be in the message!
  local gameMode = GameModes.getPreset("TWO_PLAYER_VS")

  if message.spectate_request_granted then
    message = ServerMessages.sanitizeSpectatorJoin(message)
    if message.replay then
      local replay = ReplayV1.transform(message.replay)
      local match = Match.createFromReplay(replay, false)
      -- need this to make sure both have the same player tables
      -- there's like one stupid reference to battleRoom in engine that breaks otherwise
      battleRoom = BattleRoom.createFromMatch(match)
      battleRoom.mode.gameScene = gameMode.gameScene
      battleRoom.mode.setupScene = gameMode.setupScene
      battleRoom.mode.richPresenceLabel = gameMode.richPresenceLabel
    else
      battleRoom = BattleRoom(gameMode)
      for i = 1, #message.players do
        local player = Player(message.players[i].name, message.players[i].playerNumber, false)
        battleRoom:addPlayer(player)
      end
    end
    for i = 1, #battleRoom.players do
      battleRoom.players[i]:updateWithMenuState(message.players[i])
    end
    battleRoom.spectating = true
  else
    battleRoom = BattleRoom(gameMode)
    message = ServerMessages.sanitizeCreateRoom(message)
    -- player 1 is always the local player so that data can be ignored in favor of local data
    battleRoom:addPlayer(GAME.localPlayer)
    GAME.localPlayer.playerNumber = message.players[1].playerNumber
    GAME.localPlayer.rating = message.players[1].ratingInfo

    local player2 = Player(message.players[2].name, message.players[2].playerNumber, false)
    player2:updateWithMenuState(message.players[2])
    battleRoom:addPlayer(player2)
  end

  battleRoom:registerNetworkCallbacks()

  return battleRoom
end

function BattleRoom.createLocalFromGameMode(gameMode)
  local battleRoom = BattleRoom(gameMode)

  -- always use the game client's local player
  battleRoom:addPlayer(GAME.localPlayer)
  for i = 2, gameMode.playerCount do
    battleRoom:addPlayer(Player.getLocalPlayer())
  end

  if gameMode.style ~= GameModes.Styles.CHOOSE then
    for i = 1, #battleRoom.players do
      battleRoom.players[i]:setStyle(gameMode.style)
    end
  end

  return battleRoom
end

function BattleRoom.setWinCounts(self, winCounts)
  for i = 1, #winCounts do
    self.players[i].wins = winCounts[i]
  end
end

function BattleRoom:setRatings(ratings)
  for i = 1, #self.players do
    self.players[i].rating = ratings[i]
  end
end

-- returns the total amount of games played, derived from the sum of wins across all players
-- (this means draws don't count as games)
function BattleRoom:totalGames()
  local totalGames = 0
  for i = 1, #self.players do
    totalGames = totalGames + self.players[i].wins
  end
  return totalGames
end

-- Returns the player with more win count.
-- TODO handle ties?
function BattleRoom:winningPlayer()
  if #self.players == 1 then
    return self.players[1]
  else
    if self.players[1].wins >= self.players[2].wins then
      return self.players[1]
    else
      return self.players[2]
    end
  end
end

-- creates a match with the players in the BattleRoom
function BattleRoom:createMatch()
  local supportsPause = not self.online or #self.players == 1
  local optionalArgs = { timeLimit = self.mode.timeLimit }
  if #self.puzzles > 0 then
    optionalArgs.puzzle = table.remove(self.puzzles, 1)
  end

  self.match = Match(
    self.players,
    self.mode.doCountdown,
    self.mode.stackInteraction,
    self.mode.winConditions,
    self.mode.gameOverConditions,
    supportsPause,
    optionalArgs
  )
  return self.match
end

-- creates a new Player based on their minimum information and adds them to the BattleRoom
function BattleRoom:addNewPlayer(name, publicId, isLocal)
  local player = Player(name, publicId, isLocal)
  player.playerNumber = #self.players + 1
  self:addPlayer(player)
  return player
end

-- adds an existing Player to the BattleRoom
function BattleRoom:addPlayer(player)
  if player.isLocal then
    for i = 1, #GAME.input.inputConfigurations do
      if not GAME.input.inputConfigurations[i].usedByPlayer then
        player:restrictInputs(GAME.input.inputConfigurations[i])
        break
      end
    end
  end

  player.playerNumber = #self.players + 1
  self.players[#self.players + 1] = player
end

function BattleRoom:updateLoadingState()
  local fullyLoaded = true
  for i = 1, #self.players do
    local player = self.players[i]
    if not characters[player.settings.characterId].fully_loaded or not stages[player.settings.stageId].fully_loaded then
      fullyLoaded = false
    end
  end

  self.allAssetsLoaded = fullyLoaded

  if not self.allAssetsLoaded then
    self:startLoadingNewAssets()
  end
end

function BattleRoom:refreshReadyStates()
  -- ready should probably be a battleRoom prop, not a player prop? at least for local player(s)?
  for playerNumber = 1, #self.players do
    self.players[playerNumber].ready = tableUtils.trueForAll(self.players, function(pc)
      return (pc.hasLoaded or pc.isLocal) and pc.settings.wantsReady
    end) and self.allAssetsLoaded
  end
end

-- returns true if all players are ready, false otherwise
function BattleRoom:allReady()
  -- ready should probably be a battleRoom prop, not a player prop? at least for local player(s)?
  for playerNumber = 1, #self.players do
    if not self.players[playerNumber].ready then
      return false
    end
  end

  return true
end

function BattleRoom:updateRankedStatus(rankedStatus, comments)
  if self.online then
    self.ranked = rankedStatus
    self.rankedComments = comments
    -- legacy crutches
    if self.ranked then
      match_type = "Ranked"
    else
      match_type = "Casual"
    end
  else
    error("Trying to apply ranked state to the room even though it is either not online or does not support ranked")
  end
end

-- creates a match based on the room and player settings, starts it up and switches to the Game scene
function BattleRoom:startMatch(stageId, seed, replayOfMatch)
  -- TODO: lock down configuration to one per player to avoid macro like abuses via multiple configs

  local match
  if not self.match then
    match = self:createMatch()
  else
    match = self.match
  end

  match.replay = replayOfMatch
  match:setStage(stageId)
  match:setSeed(seed)

  if (#match.players > 1 or match.stackInteraction == GameModes.StackInteractions.VERSUS) then
    GAME.rich_presence:setPresence((match:hasLocalPlayer() and "Playing" or "Spectating") .. " a " .. (self.mode.richPresenceLabel or self.mode.gameScene) ..
                                       " match", match.players[1].name .. " vs " .. (match.players[2].name), true)
  else
    GAME.rich_presence:setPresence("Playing " .. self.mode.richPresenceLabel .. " mode", nil, true)
  end

  if match_type == "Ranked" and not match.room_ratings then
    match.room_ratings = {}
  end

  match:start()
  self.state = BattleRoom.states.MatchInProgress
  local scene = sceneManager:createScene(self.mode.gameScene, {match = self.match, nextScene = self.mode.setupScene})
  sceneManager:switchToScene(scene)

  -- to prevent the game from instantly restarting, unready all players
  for i = 1, #self.players do
    self.players[i]:setWantsReady(false)
  end
end

-- sets the style of "level" presets the players select from
-- 1 = classic
-- 2 = modern
-- in the future this may become a player only prop but for now it's battleRoom wide and players have to match
function BattleRoom:setStyle(styleChoice)
  -- style could be configurable per play instead but let's not for now
  if self.mode.style == GameModes.Styles.CHOOSE then
    self.style = styleChoice
    self.onStyleChanged(styleChoice)
  else
    error("Trying to set difficulty style in a game mode that doesn't support style selection")
  end
end

-- not player specific, so this gets a separate callback that can only be overwritten once
-- so the UI can update and load up the different controls for it
function BattleRoom.onStyleChanged(style, player)
end

function BattleRoom:addPuzzle(puzzle)
  assert(self.mode.needsPuzzle, "Trying to set a puzzle for a non-puzzle mode")
  self.puzzles[#self.puzzles + 1] = puzzle
end

function BattleRoom:startLoadingNewAssets()
  if CharacterLoader.loading_queue:len() == 0 then
    for i = 1, #self.players do
      local playerSettings = self.players[i].settings
      if not characters[playerSettings.characterId].fully_loaded then
        CharacterLoader.load(playerSettings.characterId)
      end
    end
  end
  if StageLoader.loading_queue:len() == 0 then
    for i = 1, #self.players do
      local playerSettings = self.players[i].settings
      if not stages[playerSettings.stageId].fully_loaded then
        StageLoader.load(playerSettings.stageId)
      end
    end
  end
end

function BattleRoom:update(dt)
  -- if there are still unloaded assets, we can load them 1 asset a frame in the background
  StageLoader.update()
  CharacterLoader.update()

  if self.online then
    -- here we fetch network updates and update the battleroom / match
    if not GAME.tcpClient:processIncomingMessages() then
      -- oh no, we probably disconnected
      self:shutdown()
      -- let's try to log in back via lobby
      sceneManager:switchToScene(sceneManager:createScene("Lobby"))
      return
    else
      GAME.tcpClient:updateNetwork(dt)
      self:runNetworkTasks()
    end
  end

  if self.state == BattleRoom.states.Setup then
    -- the setup phase of the room
    self:updateLoadingState()
    self:refreshReadyStates()
    if self:allReady() then
      -- if online we have to wait for the server message
      if not self.online then
        self:startMatch()
      end
    end
  else

  end
end

function BattleRoom:shutdown()
  for i = 1, #self.players do
    local player = self.players[i]
    -- this is mostly to clear the input configs for future use
    player:unrestrictInputs()
  end
  self:shutdownNetwork()
  GAME:initializeLocalPlayer()
  GAME.battleRoom = nil
  self = nil
end

return BattleRoom
