local logger = require("logger")
local class = require("class")
local ChallengeModePlayer = require("ChallengeModePlayer")
local GameModes = require("GameModes")
local sceneManager = require("scenes.sceneManager")
local MessageTransition = require("scenes.Transitions.MessageTransition")
local levelPresets = require("LevelPresets")

-- Challenge Mode is a particular play through of the challenge mode in the game, it contains all the settings for the mode.
local ChallengeMode =
  class(
  function(self, difficulty, stageIndex)
    self.mode = GameModes.getPreset("ONE_PLAYER_CHALLENGE")
    self.stages = self:createStages(difficulty)
    self.difficultyName = loc("challenge_difficulty_" .. difficulty)
    self.continues = 0

    self.stageTimeQuads = {}
    self.totalTimeQuads = {}

    self:addPlayer(GAME.localPlayer)
    self.player = ChallengeModePlayer(#self.players + 1)
    self:addPlayer(self.player)
    self:setStage(stageIndex or 1)
  end,
  BattleRoom
)

ChallengeMode.numDifficulties = 6

function ChallengeMode:createStages(difficulty)
  local stages = {}

  local stageCount
  local secondsToppedOutToLoseBase 
  local secondsToppedOutToLoseIncrement
  local lineClearGPMBase
  local lineClearGPMIncrement
  local lineHeightToKill
  local panelLevel

  if difficulty == 1 then
    stageCount = 10
    secondsToppedOutToLoseBase = 1
    secondsToppedOutToLoseIncrement = 0.05
    lineClearGPMBase = 3.3
    lineClearGPMIncrement = 0.45
    panelLevel = 2
    lineHeightToKill = 6
  elseif difficulty == 2 then
    stageCount = 11
    secondsToppedOutToLoseBase = 1.1
    secondsToppedOutToLoseIncrement = 0.1
    lineClearGPMBase = 5
    lineClearGPMIncrement = 0.7
    panelLevel = 4
    lineHeightToKill = 6
  elseif difficulty == 3 then
    stageCount = 12
    secondsToppedOutToLoseBase = 1.2
    secondsToppedOutToLoseIncrement = 0.2
    lineClearGPMBase = 15.5
    lineClearGPMIncrement = 0.7
    panelLevel = 6
    lineHeightToKill = 6
  elseif difficulty == 4 then
    stageCount = 12
    secondsToppedOutToLoseBase = 1.2
    secondsToppedOutToLoseIncrement = 0.5
    lineClearGPMBase = 15.5
    lineClearGPMIncrement = 1.5
    panelLevel = 6
    lineHeightToKill = 6
  elseif difficulty == 5 then
    stageCount = 12
    secondsToppedOutToLoseBase = 1.2
    secondsToppedOutToLoseIncrement = 4.0
    lineClearGPMBase = 30
    lineClearGPMIncrement = 1.5
    panelLevel = 8
    lineHeightToKill = 6
  elseif difficulty == 6 then
    stageCount = 12
    secondsToppedOutToLoseBase = 1.2
    secondsToppedOutToLoseIncrement = 4.0
    lineClearGPMBase = 35
    lineClearGPMIncrement = 1.5
    panelLevel = 10
    lineHeightToKill = 6
  else
    error("Invalid challenge mode difficulty level of " .. difficulty)
  end

  for stageIndex = 1, stageCount, 1 do
    local incrementMultiplier = stageIndex - 1
    local stage = {}
    stage.attackSettings = self:getAttackSettings(difficulty, stageIndex)
    stage.healthSettings = {
      secondsToppedOutToLose = secondsToppedOutToLoseBase + secondsToppedOutToLoseIncrement * incrementMultiplier,
      lineClearGPM = lineClearGPMBase + lineClearGPMIncrement * incrementMultiplier,
      lineHeightToKill = lineHeightToKill,
      riseSpeed = levelPresets.getModern(panelLevel).startingSpeed
    }
    stage.playerLevel = panelLevel
    stage.expendedTime = 0
    stage.index = stageIndex

    stages[stageIndex] = stage
  end

  return stages
end

function ChallengeMode:attackFilePath(difficulty, stageIndex)
  for i = stageIndex, 1, -1 do
    local path = "default_data/training/challenge-" .. difficulty .. "-" .. i .. ".json"
    if love.filesystem.getInfo(path) then
      return path
    end
  end

  return nil
end

function ChallengeMode:getAttackSettings(difficulty, stageIndex)
  local attackFile = readAttackFile(self:attackFilePath(difficulty, stageIndex))
  assert(attackFile ~= nil, "could not find attack file for challenge mode")
  return attackFile
end

local stageQuads = {}

function ChallengeMode.render(self)
  self:drawTimeSplits()

  local drawX = canvas_width / 2
  local drawY = 440
  local limit = 400
  gprintf(loc("difficulty"), drawX - limit/2, drawY, limit, "center", nil, nil, 10)
  gprintf(self.difficultyName, drawX - limit/2, drawY + 26, limit, "center", nil, nil, 10)

  drawY = 520
  gprintf("Stage", drawX - limit/2, drawY, limit, "center", nil, nil, 10)
  GraphicsUtil.draw_number(self.stageIndex, themes[config.theme].images.IMG_number_atlas_2P, stageQuads, drawX, drawY + 26, themes[config.theme].win_Scale, "center")

  drawY = 600
  gprintf("Continues", drawX - limit/2, drawY, limit, "center", nil, nil, 10)
  gprintf(self.continues, drawX - limit/2, drawY + 26, limit, "center", nil, nil, 10)
end


function ChallengeMode:drawTimeSplits()
  local totalTime = 0
  local xPosition = 1180
  local yPosition = 120
  local yOffset = 30
  local row = 0
  local padding = 6
  local width = 180
  local height = yOffset * (#self.stages + 1) + padding * 2

  -- Background
  grectangle_color("fill", (xPosition - width/2) / GFX_SCALE , yPosition / GFX_SCALE, width/GFX_SCALE, height/GFX_SCALE, 0, 0, 0, 0.5)

  yPosition = yPosition + padding

  for i = 1, self.stageIndex do
    if self.stageTimeQuads[i] == nil then
      self.stageTimeQuads[i] = {}
    end
    local time = self.stages[i].expendedTime
    local currentStageTime = time
    local isCurrentStage = i == self.stageIndex
    if isCurrentStage and GAME.battleRoom.match.P1:game_ended() == false then
      currentStageTime = currentStageTime + GAME.battleRoom.match.P1.game_stopwatch
    end
    totalTime = totalTime + currentStageTime

    if isCurrentStage then
      set_color(0.8,0.8,1,1)
    end
    GraphicsUtil.draw_time(frames_to_time_string(currentStageTime, true), self.stageTimeQuads[i], xPosition, yPosition + yOffset * row, themes[config.theme].time_Scale)
    if isCurrentStage then
      set_color(1,1,1,1)
    end

    row = row + 1
  end

  set_color(1,1,0.8,1)
  GraphicsUtil.draw_time(frames_to_time_string(totalTime, true), self.totalTimeQuads, xPosition, yPosition + yOffset * row, themes[config.theme].time_Scale)
  set_color(1,1,1,1)
end

function ChallengeMode:recordStageResult(winners, gameLength)
  local stage = self.stages[self.stageIndex]
  stage.expendedTime = stage.expendedTime + gameLength

  if #winners == 1 then
    -- increment win count on winning player if there is only one
    winners[1]:incrementWinCount()

    if winners[1] == self.player then
      self.continues = self.continues + 1
    else
      self.stageIndex = self.stageIndex + 1
      if self.stages[self.stageIndex] then
        local stageSettings = self.stages[self.stageIndex]
        self.player.settings.attackEngineSettings = stageSettings.attackEngineSettings
        self.player.settings.healthSettings = stageSettings.healthSettings
        if stageSettings.characterId then
          self.player:setCharacter(stageSettings.characterId)
        else
          self.player:setCharacterForStage(self.stageIndex)
        end
      end
    end
  elseif #winners == 2 then
    -- tie, stay on the same stage
    -- but since the player didn't lose, they shouldn't have to pay the timer
    stage.expendedTime = stage.expendedTime - gameLength
  elseif #winners == 0 then
    -- this means an abort which is a LOSS because it's a local game and only manual abort is possible
    self.continues = self.continues + 1
  end
end

function ChallengeMode:onMatchEnded(match)
  -- TODO: call recordStageResult on top of what the regular BattleRoom does
  self.matchesPlayed = self.matchesPlayed + 1

  local winners = match:getWinners()
  -- an abort is always the responsibility of the local player in challenge mode
  -- so always record the result, even if it may have been an abort
  local gameTime = match.clock
  if match.doCountdown then
    gameTime = gameTime - 180
  end
  self:recordStageResult(winners, gameTime)
  if self.online and match:hasLocalPlayer() then
    self:reportLocalGameResult(winners)
  end

  if match.aborted then
  -- match:deinit is the responsibility of the one switching out of the game scene
    match:deinit()

    -- in challenge mode, an abort is always a manual pause and leave by the local player
    local setupScene = sceneManager:createScene(self.mode.setupScene)
    sceneManager:switchToScene(setupScene)

    -- when challenge mode becomes spectatable, there needs to be a network abort that isn't leave_room for spectators
  end

  -- nilling the match here doesn't keep the game scene from rendering it as it has its own reference
  self.match = nil
  self.state = BattleRoom.states.Setup
end

function ChallengeMode:setStage(index)
  self.stageIndex = index
  GAME.localPlayer:setLevel(self.stages[index].playerLevel)

  self.player:setCharacterForStage(index)
  self.player:setStage("")
  self.player.settings.healthSettings = self.stages[index].healthSettings
  self.player.settings.attackEngineSettings = self.stages[index].attackSettings
end

return ChallengeMode