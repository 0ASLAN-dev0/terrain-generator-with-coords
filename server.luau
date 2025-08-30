local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Terrain = workspace.Terrain

-- tweaked these values through lots of testing
local CHUNK_SIZE = 64
local CELL_SIZE = 4
local RENDER_DISTANCE = 3
local BASE_HEIGHT = 10
local MAX_HEIGHT = 150
local WATER_LEVEL = 40
local WORLD_SEED = 6767 -- hehehe

local loadedChunks = {}
local playerConnections = {}

local function clamp(value, min, max)
	return math.min(math.max(value, min), max)
end

-- layered noise function - took forever to get the frequencies right
local function getNoiseValue(x, z, frequency, octaves, persistence, lacunarity)
	local total = 0
	local amplitude = 1
	local maxValue = 0

	for octave = 1, octaves do

		local noiseVal = math.noise(x * frequency + WORLD_SEED, z * frequency - WORLD_SEED, WORLD_SEED)
		total = total + noiseVal * amplitude

		maxValue = maxValue + amplitude
		amplitude = amplitude * persistence
		frequency = frequency * lacunarity
	end

	-- normalize to [-1, 1] range
	return maxValue > 0 and total / maxValue or 0
end



local function calculateTerrainHeight(x, z)

	local continentMask = (getNoiseValue(x, z, 0.00047, 2, 0.5, 2) + 1) * 0.5

	local plainsNoise = (getNoiseValue(x, z, 0.0019, 4, 0.5, 2) + 1) * 0.5
	local height = BASE_HEIGHT + plainsNoise * 18

	-- still nto happy with how mountains turend out
	local mountainNoise = (getNoiseValue(x, z, 0.0042, 6, 0.5, 2) + 1) * 0.5
	local sharpenedMountains = mountainNoise ^ 3
	height = height + sharpenedMountains * (MAX_HEIGHT * 3) * continentMask


	local riverNoise = math.abs(getNoiseValue(x, z, 0.00083, 3, 0.5, 2))
	local riverMask = clamp(1 - (riverNoise / 0.052), 0, 1)
	height = height - riverMask * 37 * (1 - continentMask * 0.55)

	return clamp(height, 1, BASE_HEIGHT + MAX_HEIGHT * 3)
end

-- chooses material based on height and some noise
local function getMaterialForHeight(height, x, z)
	local biomeNoise = (getNoiseValue(x, z, 0.0023, 3, 0.5, 2) + 1) * 0.5

	if height < WATER_LEVEL then 
		return Enum.Material.Sand 
	end


	if biomeNoise > 0.71 and height < BASE_HEIGHT + 37 then 
		return Enum.Material.Sand 
	end

	if height > BASE_HEIGHT + 83 then 
		return Enum.Material.Snow 
	end

	if height > BASE_HEIGHT + 52 then 
		return Enum.Material.Rock 
	end


	return Enum.Material.Grass
end

local function generateChunk(chunkX, chunkZ)
	local chunkId = chunkX .. "_" .. chunkZ

	-- this is purely for performance purposes, so if two players render distance overlap it dosent generate the already generated chunks
	if loadedChunks[chunkId] then 
		return 
	end

	loadedChunks[chunkId] = true


	local chunkFolder = Instance.new("Folder")
	chunkFolder.Name = chunkId
	chunkFolder.Parent = workspace

	local startX = chunkX * CHUNK_SIZE
	local startZ = chunkZ * CHUNK_SIZE
	local highestPoint = 0

	-- run generation in separate thread so it doesn't freeze the game
	task.spawn(function()
		local processedRows = 0

		for x = startX, startX + CHUNK_SIZE - CELL_SIZE, CELL_SIZE do
			for z = startZ, startZ + CHUNK_SIZE - CELL_SIZE, CELL_SIZE do
				local centerX = x + CELL_SIZE * 0.5
				local centerZ = z + CELL_SIZE * 0.5

				local terrainHeight = math.floor(calculateTerrainHeight(centerX, centerZ) + 0.5)

				-- keep track of highest point for cleanup later
				if terrainHeight > highestPoint then 
					highestPoint = terrainHeight 
				end

				local material = getMaterialForHeight(terrainHeight, centerX, centerZ)

				if terrainHeight < WATER_LEVEL then
					local waterDepth = WATER_LEVEL - terrainHeight
					if waterDepth >= 1 then
						Terrain:FillBlock(
							CFrame.new(centerX, (terrainHeight + WATER_LEVEL) * 0.5, centerZ),
							Vector3.new(CELL_SIZE, waterDepth, CELL_SIZE),
							Enum.Material.Water
						)
					end
				end

				if terrainHeight >= 1 then
					Terrain:FillBlock(
						CFrame.new(centerX, terrainHeight * 0.5, centerZ),
						Vector3.new(CELL_SIZE, terrainHeight, CELL_SIZE),
						material
					)
				end
			end

			processedRows = processedRows + 1


			if processedRows % 12 == 0 then 
				task.wait() 
			end
		end

		-- store info for cleanup
		chunkFolder:SetAttribute("startX", startX)
		chunkFolder:SetAttribute("startZ", startZ)
		chunkFolder:SetAttribute("highestPoint", highestPoint)
		loadedChunks[chunkId] = chunkFolder
	end)
end

local function removeChunk(chunkId)
	local chunkData = loadedChunks[chunkId]
	if not chunkData or typeof(chunkData) ~= "Instance" then 
		return 
	end

	local startX = chunkData:GetAttribute("startX") or 0
	local startZ = chunkData:GetAttribute("startZ") or 0
	local maxHeight = (chunkData:GetAttribute("highestPoint") or (BASE_HEIGHT + MAX_HEIGHT)) + 45

	-- clear terrain in separate thread
	task.spawn(function()
		for x = startX, startX + CHUNK_SIZE - CELL_SIZE, CELL_SIZE do
			for z = startZ, startZ + CHUNK_SIZE - CELL_SIZE, CELL_SIZE do
				local centerX = x + CELL_SIZE * 0.5
				local centerZ = z + CELL_SIZE * 0.5

				-- fill with air to remove terrain
				Terrain:FillBlock(
					CFrame.new(centerX, maxHeight * 0.5, centerZ),
					Vector3.new(CELL_SIZE, maxHeight, CELL_SIZE),
					Enum.Material.Air
				)
			end

			if x % 5 == 0 then 
				task.wait() 
			end
		end

		-- clean up folder
		if chunkData.Parent then 
			chunkData:Destroy() 
		end
		loadedChunks[chunkId] = nil
	end)
end



local function updatePlayerChunks(player)
	local character = player.Character
	if not character then return end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return end

	local playerPos = rootPart.Position
	local playerChunkX = math.floor(playerPos.X / CHUNK_SIZE)
	local playerChunkZ = math.floor(playerPos.Z / CHUNK_SIZE)

	
	local neededChunks = {}
	for x = playerChunkX - RENDER_DISTANCE, playerChunkX + RENDER_DISTANCE do
		for z = playerChunkZ - RENDER_DISTANCE, playerChunkZ + RENDER_DISTANCE do
			local chunkId = x .. "_" .. z
			neededChunks[chunkId] = true


			if not loadedChunks[chunkId] then 
				generateChunk(x, z) 
			end
		end
	end

	for chunkId, chunkData in pairs(loadedChunks) do
		if not neededChunks[chunkId] and typeof(chunkData) == "Instance" then
			removeChunk(chunkId)
		end
	end
end

local function startPlayerLoop(player)
	if playerConnections[player] then 
		return 
	end

	local lastUpdate = 0

	playerConnections[player] = RunService.Heartbeat:Connect(function()
		local currentTime = os.clock()

		-- only update every half second to avoid performance issues
		if currentTime - lastUpdate > 0.5 then
			updatePlayerChunks(player)
			lastUpdate = currentTime
		end
	end)
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function()
		-- small delay to let character fully load
		task.wait(0.4)
		startPlayerLoop(player)
	end)

	player.CharacterRemoving:Connect(function()
		if playerConnections[player] then 
			playerConnections[player]:Disconnect() 
			playerConnections[player] = nil 
		end
	end)
end)

-- clean up when players leave
Players.PlayerRemoving:Connect(function(player)
	if playerConnections[player] then 
		playerConnections[player]:Disconnect() 
		playerConnections[player] = nil 
	end
end)


for _, player in ipairs(Players:GetPlayers()) do
	if player.Character then
		startPlayerLoop(player)
	else
		player.CharacterAdded:Connect(function()
			task.wait(0.4)
			startPlayerLoop(player)
		end)
	end
end
