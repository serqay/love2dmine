local Chunk = require("Chunk")
local Block = require("Block")
local Lighting = require("Lighting")
local mat = require("MathUtils")

local World = {}
World.__index = World

local CHUNK_SIZE = 16

local function fract(n)
    return n - math.floor(n)
end

local function makeSeed()
    local seed = os.time()
    if love and love.timer and love.timer.getTime then
        seed = seed + math.floor(love.timer.getTime() * 1000000)
    end
    return math.abs(seed) % 2147483647
end

local function hash01(seed, a, b, c)
    local n = math.sin(a * 127.1 + b * 311.7 + c * 74.7 + seed * 0.001) * 43758.5453123
    return fract(n)
end

function World.new(seed)
    local self = setmetatable({}, World)
    self.chunks = {}          -- [cx][cz] = chunk, cx/cz могут быть отрицательными
    self.active_chunks = {}   -- чанки рядом с игроком, только они рендерятся
    self.height = 32
    self.render_distance = 3  -- радиус в чанках: 3 = область 7x7 чанков вокруг игрока
    self.seed = seed or makeSeed()
    self.seed_x = (self.seed % 100000) * 0.013
    self.seed_z = (math.floor(self.seed / 100000) % 100000) * 0.017
    self.center_cx = 1
    self.center_cz = 1
    return self
end

function World:blockToChunk(x, z)
    local cx = math.floor((x - 1) / CHUNK_SIZE) + 1
    local cz = math.floor((z - 1) / CHUNK_SIZE) + 1
    return cx, cz
end

function World:blockToLocal(x, z)
    local bx = ((x - 1) % CHUNK_SIZE) + 1
    local bz = ((z - 1) % CHUNK_SIZE) + 1
    return bx, bz
end

function World:chunkBlockBounds(cx, cz)
    local minX = (cx - 1) * CHUNK_SIZE + 1
    local maxX = minX + CHUNK_SIZE - 1
    local minZ = (cz - 1) * CHUNK_SIZE + 1
    local maxZ = minZ + CHUNK_SIZE - 1
    return minX, maxX, minZ, maxZ
end

function World:getChunk(cx, cz)
    return self.chunks[cx] and self.chunks[cx][cz]
end

function World:getTerrainHeightAt(x, z)
    -- Сид двигает координаты шума, поэтому каждый запуск дает новый мир,
    -- но один и тот же seed всегда генерирует одинаковый ландшафт.
    local n = mat.fbm2D(x + self.seed_x, z + self.seed_z, 4)
    local h = math.floor(n * 16) + 4
    return math.max(2, math.min(self.height - 8, h))
end

function World:rand01(cx, cz, salt)
    return hash01(self.seed, cx, cz, salt or 0)
end

function World:randInt(cx, cz, salt, minValue, maxValue)
    local r = self:rand01(cx, cz, salt)
    return minValue + math.floor(r * (maxValue - minValue + 1))
end

function World:generateTreesForChunk(chunk)
    -- Детерминированные деревья: не зависят от порядка генерации чанков.
    local tree_chance = self:rand01(chunk.cx, chunk.cz, 11)
    local num_trees = 0
    if tree_chance > 0.82 then
        num_trees = 2
    elseif tree_chance > 0.45 then
        num_trees = 1
    end
    
    for t = 1, num_trees do
        local tx = self:randInt(chunk.cx, chunk.cz, 20 + t * 4, 3, 14)
        local tz = self:randInt(chunk.cx, chunk.cz, 21 + t * 4, 3, 14)
        local ty = chunk.surface[tx] and chunk.surface[tx][tz] or 1
        
        if ty > 1 and ty < self.height - 7 and chunk.data[tx][ty][tz] == 1 then
            local trunk_height = self:randInt(chunk.cx, chunk.cz, 22 + t * 4, 4, 6)
            
            for h = 1, trunk_height do
                if ty + h <= self.height then
                    chunk.data[tx][ty + h][tz] = 4
                end
            end
            
            local ly = ty + trunk_height
            for lx = tx - 2, tx + 2 do
                for lz = tz - 2, tz + 2 do
                    for l_y = ly - 1, ly + 2 do
                        if lx >= 1 and lx <= CHUNK_SIZE and lz >= 1 and lz <= CHUNK_SIZE and l_y >= 1 and l_y <= self.height then
                            local dist = (lx - tx)^2 + (lz - tz)^2 + (l_y - ly)^2
                            if dist <= 6.5 and chunk.data[lx][l_y][lz] == 0 then
                                chunk.data[lx][l_y][lz] = 5
                            end
                        end
                    end
                end
            end
        end
    end
end

function World:ensureChunk(cx, cz)
    if not self.chunks[cx] then self.chunks[cx] = {} end
    if self.chunks[cx][cz] then
        return self.chunks[cx][cz], false
    end
    
    local chunk = Chunk.new(cx, cz, self)
    chunk:generate()
    self:generateTreesForChunk(chunk)
    chunk.dirty = true
    chunk.priority_dirty = false
    self.chunks[cx][cz] = chunk
    return chunk, true
end

function World:updateLoadedChunks(playerX, playerZ, skipLighting)
    local bx = math.floor(playerX) + 1
    local bz = math.floor(playerZ) + 1
    local pcx, pcz = self:blockToChunk(bx, bz)
    self.center_cx, self.center_cz = pcx, pcz
    
    local active = {}
    local generated = false
    local minGX, maxGX, minGZ, maxGZ
    local r = self.render_distance
    
    for cx = pcx - r, pcx + r do
        for cz = pcz - r, pcz + r do
            local chunk, created = self:ensureChunk(cx, cz)
            active[#active + 1] = chunk
            
            if created then
                generated = true
                local minX, maxX, minZ, maxZ = self:chunkBlockBounds(cx, cz)
                minGX = minGX and math.min(minGX, minX) or minX
                maxGX = maxGX and math.max(maxGX, maxX) or maxX
                minGZ = minGZ and math.min(minGZ, minZ) or minZ
                maxGZ = maxGZ and math.max(maxGZ, maxZ) or maxZ
            end
        end
    end
    
    self.active_chunks = active
    
    if generated and self.lighting and not skipLighting then
        -- Новый чанк должен получить свет и свет от соседей. Берем запас 15 блоков,
        -- потому что максимальный радиус света равен 15.
        self.lighting:recalculateArea(minGX - 15, maxGX + 15, minGZ - 15, maxGZ + 15, true)
    end
end

function World:getRenderChunks()
    return self.active_chunks
end

function World:getActiveBlockBounds(padding)
    padding = padding or 0
    if not self.active_chunks or #self.active_chunks == 0 then return nil end
    
    local minX, maxX, minZ, maxZ
    for _, chunk in ipairs(self.active_chunks) do
        local cminX, cmaxX, cminZ, cmaxZ = self:chunkBlockBounds(chunk.cx, chunk.cz)
        minX = minX and math.min(minX, cminX) or cminX
        maxX = maxX and math.max(maxX, cmaxX) or cmaxX
        minZ = minZ and math.min(minZ, cminZ) or cminZ
        maxZ = maxZ and math.max(maxZ, cmaxZ) or cmaxZ
    end
    
    return minX - padding, maxX + padding, minZ - padding, maxZ + padding
end

function World:generateArea(render_distance, spawnX, spawnZ)
    self.render_distance = render_distance or self.render_distance or 3
    spawnX = spawnX or 8
    spawnZ = spawnZ or 8
    
    self.chunks = {}
    self.active_chunks = {}
    self.lighting = Lighting.new(self)
    self:updateLoadedChunks(spawnX, spawnZ, true)
    self.lighting:recalculate()
    
    for _, chunk in ipairs(self.active_chunks) do
        chunk:buildMesh()
    end
end

-- Освещение делегируется Lighting.lua
function World:initLighting()
    if self.lighting then self.lighting:recalculate() end
end

function World:propagateLighting()
    if self.lighting then self.lighting:recalculate() end
end

function World:getBlock(x, y, z)
    if y < 1 or y > self.height then return 0 end
    
    local cx, cz = self:blockToChunk(x, z)
    local chunk = self:getChunk(cx, cz)
    if not chunk then return 0 end
    
    local bx, bz = self:blockToLocal(x, z)
    return chunk.data[bx][y][bz] or 0
end

function World:getSurfaceHeight(x, z)
    local cx, cz = self:blockToChunk(x, z)
    local chunk = self:getChunk(cx, cz)
    local bx, bz = self:blockToLocal(x, z)
    
    -- Берем ИСХОДНУЮ высоту земли. Поэтому если игрок роет вертикальную шахту,
    -- солнечный свет ниже старой поверхности постепенно затухает.
    if chunk and chunk.surface and chunk.surface[bx] and chunk.surface[bx][bz] then
        return chunk.surface[bx][bz]
    end
    
    return self:getTerrainHeightAt(x, z)
end

function World:markDirtyArea(minX, maxX, minZ, maxZ)
    minX = math.floor(minX)
    maxX = math.floor(maxX)
    minZ = math.floor(minZ)
    maxZ = math.floor(maxZ)
    
    if minX > maxX or minZ > maxZ then return end
    
    local cx1, cz1 = self:blockToChunk(minX, minZ)
    local cx2, cz2 = self:blockToChunk(maxX, maxZ)
    
    if cx1 > cx2 then cx1, cx2 = cx2, cx1 end
    if cz1 > cz2 then cz1, cz2 = cz2, cz1 end
    
    for cx = cx1, cx2 do
        for cz = cz1, cz2 do
            local chunk = self:getChunk(cx, cz)
            if chunk then
                chunk.dirty = true
            end
        end
    end
end

function World:markDirtyAround(x, y, z, radius)
    radius = radius or 1
    self:markDirtyArea(x - radius, x + radius, z - radius, z + radius)
end

function World:setBlock(x, y, z, id)
    if y < 1 or y > self.height then return false end
    
    local cx, cz = self:blockToChunk(x, z)
    local chunk = self:getChunk(cx, cz)
    if not chunk then
        chunk = self:ensureChunk(cx, cz)
    end
    if not chunk then return false end
    
    local bx, bz = self:blockToLocal(x, z)
    
    if chunk.data[bx][y][bz] == id then
        return true
    end
    
    chunk.data[bx][y][bz] = id
    
    -- Геометрию измененного чанка перестраиваем первой, чтобы блок появился/исчез сразу.
    local function markPriority(ccx, ccz)
        local c = self:getChunk(ccx, ccz)
        if c then
            c.dirty = true
            c.priority_dirty = true
        end
    end
    
    markPriority(cx, cz)
    if bx == 1 then markPriority(cx - 1, cz) end
    if bx == CHUNK_SIZE then markPriority(cx + 1, cz) end
    if bz == 1 then markPriority(cx, cz - 1) end
    if bz == CHUNK_SIZE then markPriority(cx, cz + 1) end
    
    -- Быстрый локальный пересчет освещения вместо полного пересчета всего мира.
    if self.lighting and self.lighting.recalculateLocal then
        self.lighting:recalculateLocal(x, y, z, 15)
    elseif self.lighting then
        self.lighting:recalculate()
    else
        self:markDirtyAround(x, y, z, 2)
    end
    
    return true
end

function World:getLight(x, y, z, light_type)
    if y < 1 or y > self.height then return 0 end
    
    local cx, cz = self:blockToChunk(x, z)
    local chunk = self:getChunk(cx, cz)
    if not chunk then
        if light_type == "sky" then
            return y > self:getTerrainHeightAt(x, z) and 15 or 0
        end
        return 0
    end
    
    local bx, bz = self:blockToLocal(x, z)
    return chunk:getLight(bx, y, bz, light_type) or 0
end

function World:raycast(origin, direction, max_dist)
    local step = 0.05
    local t = 0
    local last_pos = {x = origin.x, y = origin.y, z = origin.z}
    
    while t < max_dist do
        local px = origin.x + direction.x * t
        local py = origin.y + direction.y * t
        local pz = origin.z + direction.z * t
        
        local bx = math.floor(px) + 1
        local by = math.floor(py) + 1
        local bz = math.floor(pz) + 1
        
        local block = self:getBlock(bx, by, bz)
        if block and block ~= 0 then
            local lbx = math.floor(last_pos.x) + 1
            local lby = math.floor(last_pos.y) + 1
            local lbz = math.floor(last_pos.z) + 1
            
            local normal = {
                x = lbx - bx,
                y = lby - by,
                z = lbz - bz
            }
            
            if math.abs(normal.x) + math.abs(normal.y) + math.abs(normal.z) > 1 then
                local dx = last_pos.x - (bx - 0.5)
                local dy = last_pos.y - (by - 0.5)
                local dz = last_pos.z - (bz - 0.5)
                if math.abs(dx) > math.abs(dy) and math.abs(dx) > math.abs(dz) then
                    normal = {x = dx > 0 and 1 or -1, y = 0, z = 0}
                elseif math.abs(dy) > math.abs(dx) and math.abs(dy) > math.abs(dz) then
                    normal = {x = 0, y = dy > 0 and 1 or -1, z = 0}
                else
                    normal = {x = 0, y = 0, z = dz > 0 and 1 or -1}
                end
            end
            
            return {
                hit = true,
                bx = bx,
                by = by,
                bz = bz,
                normal = normal,
                px = px,
                py = py,
                pz = pz
            }
        end
        
        last_pos.x = px
        last_pos.y = py
        last_pos.z = pz
        t = t + step
    end
    
    return {hit = false}
end

return World
