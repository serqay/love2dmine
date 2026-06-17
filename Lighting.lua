-- Lighting.lua
-- ПРОСТАЯ И ГАРАНТИРОВАННО РАБОЧАЯ ВЕРСИЯ
-- Sky light распространяется ВНИЗ через воздух (Minecraft правило)

local Lighting = {}
local Block = require("Block")

Lighting.MAX = 15

function Lighting.new(world)
    local self = setmetatable({}, {__index = Lighting})
    self.world = world
    return self
end

function Lighting:recalculate()
    -- Сброс всего освещения
    for cx = 1, self.world.width do
        for cz = 1, self.world.depth do
            self.world.chunks[cx][cz]:resetLighting()
        end
    end
    
    -- === BLOCK LIGHT ===
    local bqueue = {}
    
    for cx = 1, self.world.width do
        for cz = 1, self.world.depth do
            local chunk = self.world.chunks[cx][cz]
            for x = 1, chunk.size_x do
                for y = 1, chunk.size_y do
                    for z = 1, chunk.size_z do
                        if Block.isEmissive(chunk.data[x][y][z]) then
                            local lvl = Block.getLightLevel(chunk.data[x][y][z])
                            chunk:setLight(x, y, z, "block", lvl)
                            table.insert(bqueue, {
                                x = (cx-1)*16 + x,
                                y = y,
                                z = (cz-1)*16 + z,
                                level = lvl
                            })
                        end
                    end
                end
            end
        end
    end
    
    local dirs = {{1,0,0},{-1,0,0},{0,1,0},{0,-1,0},{0,0,1},{0,0,-1}}
    
    -- Block light flood fill
    local i = 1
    while i <= #bqueue do
        local cur = bqueue[i]
        i = i + 1
        
        for _, d in ipairs(dirs) do
            local nx = cur.x + d[1]
            local ny = cur.y + d[2]
            local nz = cur.z + d[3]
            
            if ny >= 1 and ny <= self.world.height then
                local ncx = math.floor((nx-1)/16) + 1
                local ncz = math.floor((nz-1)/16) + 1
                
                if ncx >= 1 and ncx <= self.world.width and ncz >= 1 and ncz <= self.world.depth then
                    local nc = self.world.chunks[ncx][ncz]
                    local nlx = ((nx-1) % 16) + 1
                    local nlz = ((nz-1) % 16) + 1
                    
                    if Block.isTransparent(nc.data[nlx][ny][nlz] or 0) then
                        local ex = nc:getLight(nlx, ny, nlz, "block")
                        if cur.level - 1 > ex then
                            nc:setLight(nlx, ny, nlz, "block", cur.level - 1)
                            table.insert(bqueue, {x = nx, y = ny, z = nz, level = cur.level - 1})
                        end
                    end
                end
            end
        end
    end
    
    -- === SKY LIGHT (правильное распространение ВНИЗ) ===
    local squeue = {}
    
    -- Инициализация: sky = 15 сверху
    for cx = 1, self.world.width do
        for cz = 1, self.world.depth do
            local chunk = self.world.chunks[cx][cz]
            for x = 1, chunk.size_x do
                for z = 1, chunk.size_z do
                    local topY = chunk.size_y
                    if Block.isTransparent(chunk.data[x][topY][z]) then
                        chunk:setLight(x, topY, z, "sky", Lighting.MAX)
                        table.insert(squeue, {
                            x = (cx-1)*16 + x,
                            y = topY,
                            z = (cz-1)*16 + z,
                            level = Lighting.MAX
                        })
                    end
                end
            end
        end
    end
    
    -- BFS распространение sky light (включая ВНИЗ через дыры)
    i = 1
    while i <= #squeue do
        local cur = squeue[i]
        i = i + 1
        
        for _, d in ipairs(dirs) do
            local nx = cur.x + d[1]
            local ny = cur.y + d[2]
            local nz = cur.z + d[3]
            
            if ny >= 1 and ny <= self.world.height then
                local ncx = math.floor((nx-1)/16) + 1
                local ncz = math.floor((nz-1)/16) + 1
                
                if ncx >= 1 and ncx <= self.world.width and ncz >= 1 and ncz <= self.world.depth then
                    local nc = self.world.chunks[ncx][ncz]
                    local nlx = ((nx-1) % 16) + 1
                    local nlz = ((nz-1) % 16) + 1
                    
                    if Block.isTransparent(nc.data[nlx][ny][nlz] or 0) then
                        local ex = nc:getLight(nlx, ny, nlz, "sky")
                        
                        -- КЛЮЧЕВОЕ ПРАВИЛО MINECRAFT:
                        -- При движении ВНИЗ свет НЕ убывает
                        local dec = (d[2] < 0) and 0 or 1
                        local newl = cur.level - dec
                        
                        if newl > ex then
                            nc:setLight(nlx, ny, nlz, "sky", newl)
                            table.insert(squeue, {
                                x = nx, y = ny, z = nz, level = newl
                            })
                        end
                    end
                end
            end
        end
    end
    
    -- Помечаем все чанки dirty
    for cx = 1, self.world.width do
        for cz = 1, self.world.depth do
            self.world.chunks[cx][cz].dirty = true
        end
    end
end

return Lighting