-- Lighting.lua
-- Локальное воксельное освещение для бесконечной генерации.
-- Sky light выше исходной поверхности = 15, ниже поверхности постепенно затухает,
-- поэтому шахты и тоннели уходят в темноту.

local Lighting = {}
local Block = require("Block")

Lighting.MAX = 15

local DIRS = {
    { 1,  0,  0},
    {-1,  0,  0},
    { 0,  1,  0},
    { 0, -1,  0},
    { 0,  0,  1},
    { 0,  0, -1},
}

function Lighting.new(world)
    local self = setmetatable({}, {__index = Lighting})
    self.world = world
    return self
end

function Lighting:getChunkAndLocal(wx, wz)
    local cx, cz = self.world:blockToChunk(wx, wz)
    local chunk = self.world:getChunk(cx, cz)
    if not chunk then return nil end
    
    local lx, lz = self.world:blockToLocal(wx, wz)
    return chunk, lx, lz
end

function Lighting:isInsideWorld(wx, y, wz)
    if y < 1 or y > self.world.height then return false end
    return self:getChunkAndLocal(wx, wz) ~= nil
end

function Lighting:isInsideArea(wx, wz, minX, maxX, minZ, maxZ)
    return wx >= minX and wx <= maxX and wz >= minZ and wz <= maxZ
end

function Lighting:getLightAt(wx, y, wz, light_type)
    return self.world:getLight(wx, y, wz, light_type) or 0
end

function Lighting:setLightAt(wx, y, wz, light_type, value)
    if y < 1 or y > self.world.height then return false end
    local chunk, lx, lz = self:getChunkAndLocal(wx, wz)
    if not chunk then return false end
    chunk:setLight(lx, y, lz, light_type, value)
    return true
end

function Lighting:getBlockAt(wx, y, wz)
    return self.world:getBlock(wx, y, wz) or 0
end

function Lighting:isTransparentAt(wx, y, wz)
    return Block.isTransparent(self:getBlockAt(wx, y, wz))
end

function Lighting:clearArea(minX, maxX, minZ, maxZ)
    local height = self.world.height
    
    for wx = minX, maxX do
        for wz = minZ, maxZ do
            local chunk, lx, lz = self:getChunkAndLocal(wx, wz)
            if chunk then
                for y = 1, height do
                    chunk.light[lx][y][lz].sky = 0
                    chunk.light[lx][y][lz].block = 0
                end
            end
        end
    end
end

function Lighting:markDirtyArea(minX, maxX, minZ, maxZ)
    -- +1 блок по краям: меш соседнего solid-блока может смотреть в измененную air-клетку.
    if self.world.markDirtyArea then
        self.world:markDirtyArea(minX - 1, maxX + 1, minZ - 1, maxZ + 1)
    end
end

function Lighting:pushLight(queue, wx, y, wz, light_type, level, minX, maxX, minZ, maxZ)
    if level <= 0 then return end
    if not self:isInsideWorld(wx, y, wz) then return end
    if not self:isInsideArea(wx, wz, minX, maxX, minZ, maxZ) then return end
    
    local current = self:getLightAt(wx, y, wz, light_type)
    if level > current then
        self:setLightAt(wx, y, wz, light_type, level)
        queue[#queue + 1] = {x = wx, y = y, z = wz, level = level}
    end
end

function Lighting:flood(queue, light_type, minX, maxX, minZ, maxZ)
    local i = 1
    while i <= #queue do
        local cur = queue[i]
        i = i + 1
        
        if cur.level > 1 then
            for _, d in ipairs(DIRS) do
                local nx = cur.x + d[1]
                local ny = cur.y + d[2]
                local nz = cur.z + d[3]
                
                if self:isInsideWorld(nx, ny, nz)
                    and self:isInsideArea(nx, nz, minX, maxX, minZ, maxZ)
                    and self:isTransparentAt(nx, ny, nz) then
                    
                    local newLevel = cur.level - 1
                    self:pushLight(queue, nx, ny, nz, light_type, newLevel, minX, maxX, minZ, maxZ)
                end
            end
        end
    end
end

function Lighting:seedBlockLights(minX, maxX, minZ, maxZ, queue)
    local height = self.world.height
    
    for wx = minX, maxX do
        for wz = minZ, maxZ do
            if self:getChunkAndLocal(wx, wz) then
                for y = 1, height do
                    local id = self:getBlockAt(wx, y, wz)
                    if Block.isEmissive(id) then
                        self:pushLight(queue, wx, y, wz, "block", Block.getLightLevel(id), minX, maxX, minZ, maxZ)
                    end
                end
            end
        end
    end
end

function Lighting:seedSkyLights(minX, maxX, minZ, maxZ, queue)
    local height = self.world.height
    
    for wx = minX, maxX do
        for wz = minZ, maxZ do
            if self:getChunkAndLocal(wx, wz) then
                local surface = self.world:getSurfaceHeight(wx, wz)
                
                -- Выше исходной поверхности столб воздуха считается открытым небом.
                -- Ниже surface свет приходит flood-fill'ом с затуханием.
                local minSkyY = math.max(surface + 1, 1)
                for y = height, minSkyY, -1 do
                    if self:isTransparentAt(wx, y, wz) then
                        self:pushLight(queue, wx, y, wz, "sky", Lighting.MAX, minX, maxX, minZ, maxZ)
                    else
                        -- Непрозрачный блок над поверхностью: крыша/ствол/постройка дает тень.
                        break
                    end
                end
            end
        end
    end
end

function Lighting:seedBoundaryLights(minX, maxX, minZ, maxZ, blockQueue, skyQueue)
    local height = self.world.height
    
    for wx = minX, maxX do
        for wz = minZ, maxZ do
            if self:getChunkAndLocal(wx, wz) then
                for y = 1, height do
                    if self:isTransparentAt(wx, y, wz) then
                        for _, d in ipairs(DIRS) do
                            local nx = wx + d[1]
                            local ny = y + d[2]
                            local nz = wz + d[3]
                            
                            if ny >= 1 and ny <= height and not self:isInsideArea(nx, nz, minX, maxX, minZ, maxZ) then
                                local blockLevel = self:getLightAt(nx, ny, nz, "block") - 1
                                if blockLevel > 0 then
                                    self:pushLight(blockQueue, wx, y, wz, "block", blockLevel, minX, maxX, minZ, maxZ)
                                end
                                
                                local skyLevel = self:getLightAt(nx, ny, nz, "sky") - 1
                                if skyLevel > 0 then
                                    self:pushLight(skyQueue, wx, y, wz, "sky", skyLevel, minX, maxX, minZ, maxZ)
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

function Lighting:recalculateArea(minX, maxX, minZ, maxZ, useBoundary)
    minX = math.floor(minX)
    maxX = math.floor(maxX)
    minZ = math.floor(minZ)
    maxZ = math.floor(maxZ)
    
    if minX > maxX or minZ > maxZ then return end
    
    self:clearArea(minX, maxX, minZ, maxZ)
    
    local blockQueue = {}
    local skyQueue = {}
    
    self:seedBlockLights(minX, maxX, minZ, maxZ, blockQueue)
    self:seedSkyLights(minX, maxX, minZ, maxZ, skyQueue)
    
    if useBoundary then
        self:seedBoundaryLights(minX, maxX, minZ, maxZ, blockQueue, skyQueue)
    end
    
    self:flood(blockQueue, "block", minX, maxX, minZ, maxZ)
    self:flood(skyQueue, "sky", minX, maxX, minZ, maxZ)
    
    self:markDirtyArea(minX, maxX, minZ, maxZ)
end

function Lighting:recalculateLocal(wx, y, wz, radius)
    radius = radius or Lighting.MAX
    -- Y не ограничиваем: при копании шахты меняется весь световой столб сверху вниз.
    self:recalculateArea(wx - radius, wx + radius, wz - radius, wz + radius, true)
end

function Lighting:recalculate()
    local minX, maxX, minZ, maxZ = self.world:getActiveBlockBounds(0)
    if not minX then return end
    self:recalculateArea(minX, maxX, minZ, maxZ, false)
end

return Lighting
