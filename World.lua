local Chunk = require("Chunk")
local Block = require("Block")
local Lighting = require("Lighting")

local World = {}
World.__index = World

function World.new()
    local self = setmetatable({}, World)
    self.chunks = {}
    self.width = 4
    self.depth = 4
    self.height = 32
    return self
end

function World:generateArea(width, depth)
    self.width = width or 4
    self.depth = depth or 4
    
    for cx = 1, self.width do
        self.chunks[cx] = {}
        for cz = 1, self.depth do
            local chunk = Chunk.new(cx, cz, self)
            chunk:generate()
            self.chunks[cx][cz] = chunk
        end
    end
    
    self:generateTrees()
    
    self.lighting = Lighting.new(self)
    self.lighting:recalculate()
    
    for cx = 1, self.width do
        for cz = 1, self.depth do
            self.chunks[cx][cz]:buildMesh()
        end
    end
end

function World:generateTrees()
    for cx = 1, self.width do
        for cz = 1, self.depth do
            local chunk = self.chunks[cx][cz]
            local num_trees = math.random(1, 3)
            
            for t = 1, num_trees do
                local tx = math.random(3, 14)
                local tz = math.random(3, 14)
                
                local ty = 1
                for y = self.height, 1, -1 do
                    if chunk.data[tx][y][tz] == 1 then
                        ty = y
                        break
                    end
                end
                
                if ty > 1 and ty < self.height - 7 then
                    local trunk_height = math.random(4, 6)
                    
                    for h = 1, trunk_height do
                        chunk.data[tx][ty + h][tz] = 4
                    end
                    
                    local ly = ty + trunk_height
                    for lx = tx - 2, tx + 2 do
                        for lz = tz - 2, tz + 2 do
                            for l_y = ly - 1, ly + 2 do
                                if lx >= 1 and lx <= 16 and lz >= 1 and lz <= 16 then
                                    local dist = (lx - tx)^2 + (lz - tz)^2 + (l_y - ly)^2
                                    if dist <= 6.5 then
                                        if chunk.data[lx][l_y][lz] == 0 then
                                            chunk.data[lx][l_y][lz] = 5
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

-- Освещение делегируется Lighting.lua
function World:initLighting()
    if self.lighting then self.lighting:init() end
end

function World:propagateLighting()
    if self.lighting then self.lighting:propagate() end
end

function World:getBlock(x, y, z)
    if y < 1 or y > self.height then return 0 end
    
    local cx = math.floor((x - 1) / 16) + 1
    local cz = math.floor((z - 1) / 16) + 1
    
    if cx < 1 or cx > self.width or cz < 1 or cz > self.depth then
        return 0
    end
    
    local row = self.chunks[cx]
    if not row then return 0 end
    local chunk = row[cz]
    if not chunk then return 0 end
    
    local bx = (x - 1) % 16 + 1
    local bz = (z - 1) % 16 + 1
    
    return chunk.data[bx][y][bz] or 0
end

function World:setBlock(x, y, z, id)
    if y < 1 or y > self.height then return false end
    
    local cx = math.floor((x - 1) / 16) + 1
    local cz = math.floor((z - 1) / 16) + 1
    
    if cx < 1 or cx > self.width or cz < 1 or cz > self.depth then
        return false
    end
    
    local row = self.chunks[cx]
    if not row then return false end
    local chunk = row[cz]
    if not chunk then return false end
    
    local bx = (x - 1) % 16 + 1
    local bz = (z - 1) % 16 + 1
    
    chunk.data[bx][y][bz] = id
    
    -- Полный пересчёт освещения через Lighting модуль
    if self.lighting then
        self.lighting:recalculate()
    end
    
    -- Помечаем ВСЕ чанки dirty
    for ccx = 1, self.width do
        for ccz = 1, self.depth do
            self.chunks[ccx][ccz].dirty = true
        end
    end
    
    return true
end

function World:getLight(x, y, z, light_type)
    if y < 1 or y > self.height then return 0 end
    
    local cx = math.floor((x - 1) / 16) + 1
    local cz = math.floor((z - 1) / 16) + 1
    
    if cx < 1 or cx > self.width or cz < 1 or cz > self.depth then
        return light_type == "sky" and 15 or 0
    end
    
    local row = self.chunks[cx]
    if not row then return light_type == "sky" and 15 or 0 end
    local chunk = row[cz]
    if not chunk then return light_type == "sky" and 15 or 0 end
    
    local bx = (x - 1) % 16 + 1
    local bz = (z - 1) % 16 + 1
    
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
                elseif math.abs(dy) > math.abs(dy) and math.abs(dy) > math.abs(dz) then
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