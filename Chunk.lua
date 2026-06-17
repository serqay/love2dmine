local Block = require("Block")

local Chunk = {}
Chunk.__index = Chunk

-- Определение граней в правильном порядке обхода:
local faces_def = {
    { -- Front  (-Z)
        verts = {{0,0,0}, {1,0,0}, {1,1,0}, {0,1,0}},
        type = "side",
        neighbor = {0, 0, -1}
    },
    { -- Back   (+Z)
        verts = {{1,0,1}, {0,0,1}, {0,1,1}, {1,1,1}},
        type = "side",
        neighbor = {0, 0, 1}
    },
    { -- Top    (+Y)
        verts = {{0,1,0}, {1,1,0}, {1,1,1}, {0,1,1}},
        type = "top",
        neighbor = {0, 1, 0}
    },
    { -- Bottom (-Y)
        verts = {{0,0,1}, {1,0,1}, {1,0,0}, {0,0,0}},
        type = "bottom",
        neighbor = {0, -1, 0}
    },
    { -- Right  (+X)
        verts = {{1,0,0}, {1,0,1}, {1,1,1}, {1,1,0}},
        type = "side",
        neighbor = {1, 0, 0}
    },
    { -- Left   (-X)
        verts = {{0,0,1}, {0,0,0}, {0,1,0}, {0,1,1}},
        type = "side",
        neighbor = {-1, 0, 0}
    },
}

function Chunk.new(cx, cz, world)
    local self = setmetatable({}, Chunk)
    self.cx, self.cz = cx, cz
    self.world = world
    self.size_x = 16
    self.size_y = 32
    self.size_z = 16
    self.data = {}
    self.light = {}        -- light levels [x][y][z] = {sky, block}
    self.mesh = nil
    self.dirty = true
    
    for x = 1, self.size_x do
        self.data[x] = {}
        self.light[x] = {}
        for y = 1, self.size_y do
            self.data[x][y] = {}
            self.light[x][y] = {}
            for z = 1, self.size_z do
                self.data[x][y][z] = 0
                self.light[x][y][z] = {sky = 0, block = 0}
            end
        end
    end
    
    return self
end

function Chunk:generate()
    local mat = require("MathUtils")
    for x = 1, self.size_x do
        local worldX = (self.cx - 1) * self.size_x + x
        for z = 1, self.size_z do
            local worldZ = (self.cz - 1) * self.size_z + z
            
            local n = mat.fbm2D(worldX, worldZ, 4)
            local h = math.floor(n * 16) + 4
            
            for y = 1, self.size_y do
                if y > h then
                    self.data[x][y][z] = 0
                elseif y == h then
                    self.data[x][y][z] = 1
                elseif y > h - 3 then
                    self.data[x][y][z] = 2
                else
                    self.data[x][y][z] = 3
                end
            end
        end
    end
    self.dirty = true
end

-- НОВОЕ: Инициализация/сброс освещения
function Chunk:resetLighting()
    for x = 1, self.size_x do
        for y = 1, self.size_y do
            for z = 1, self.size_z do
                self.light[x][y][z] = {sky = 0, block = 0}
            end
        end
    end
end

-- Получить свет соседнего блока (кросс-чанковый)
function Chunk:getNeighborLight(wx, wy, wz, light_type)
    local nx = wx
    local ny = wy
    local nz = wz
    
    -- Переводим в локальные координаты текущего чанка
    local lx = ((nx - 1) % 16) + 1
    local lz = ((nz - 1) % 16) + 1
    
    if lx < 1 or lx > 16 or lz < 1 or lz > 16 or ny < 1 or ny > self.size_y then
        -- Запрашиваем у мира
        return self.world:getLight(nx, ny, nz, light_type)
    end
    
    if self.light[lx] and self.light[lx][ny] and self.light[lx][ny][lz] then
        return self.light[lx][ny][lz][light_type] or 0
    end
    return 0
end

function Chunk:setLight(x, y, z, light_type, value)
    if x < 1 or x > self.size_x or y < 1 or y > self.size_y or z < 1 or z > self.size_z then
        return
    end
    self.light[x][y][z][light_type] = math.max(0, math.min(15, value))
end

function Chunk:getLight(x, y, z, light_type)
    if x < 1 or x > self.size_x or y < 1 or y > self.size_y or z < 1 or z > self.size_z then
        -- Выход за границы чанка — спрашиваем у мира (кросс-чанковое освещение)
        local wx = (self.cx - 1) * self.size_x + x
        local wz = (self.cz - 1) * self.size_z + z
        return self.world:getLight(wx, y, wz, light_type) or 0
    end
    return self.light[x][y][z][light_type] or 0
end

function Chunk:buildMesh()
    if not self.dirty then return self.mesh end
    
    local vertices = {}
    local vertexFormat = {
        {"VertexPosition", "float", 3},
        {"VertexTexCoord", "float", 2},
        {"VertexColor", "byte", 4},
    }
    
    for x = 1, self.size_x do
        local wx = (self.cx - 1) * self.size_x + x
        for y = 1, self.size_y do
            for z = 1, self.size_z do
                local id = self.data[x][y][z]
                
                if id and id ~= 0 then
                    local wz = (self.cz - 1) * self.size_z + z
                    
                    for _, face in ipairs(faces_def) do
                        local nx = wx + face.neighbor[1]
                        local ny = y + face.neighbor[2]
                        local nz = wz + face.neighbor[3]
                        
                        local neighbor_id = self.world:getBlock(nx, ny, nz)
                        local is_transparent = Block.isTransparent(neighbor_id)
                        
                        if is_transparent then
                            local u, v = Block.getUV(id, face.type)
                            local v1, v2, v3, v4 = face.verts[1], face.verts[2], face.verts[3], face.verts[4]
                            local ox, oy, oz = wx - 1, y - 1, wz - 1
                            
                            local eps = 0.005 * Block.UV_SIZE
                            local u1, v1_uv = u + eps, v + eps
                            local u2, v2_uv = u + Block.UV_SIZE - eps, v + Block.UV_SIZE - eps
                            
                            -- === ОСВЕЩЕНИЕ ===
                            local block_light = self:getLight(x, y, z, "block")
                            local sky_light = self:getLight(x, y, z, "sky")
                            
                            -- Базовый directional shade
                            local shade = 1.0
                            if face.type == "top" then shade = 1.0
                            elseif face.type == "side" then
                                if face.neighbor[1] ~= 0 then shade = 0.85
                                else shade = 0.7 end
                            elseif face.type == "bottom" then shade = 0.55 end
                            
                            -- Комбинируем (максимум из block light и sky light)
                            local max_light = math.max(block_light, sky_light)
                            local final_light = max_light / 15.0
                            
                            -- Яркость: в полной темноте ~10%, при максимальном свете 100%
                            local brightness = shade * (0.10 + final_light * 0.90)
                            
                            local r = math.floor(255 * brightness)
                            local g = math.floor(255 * brightness)
                            local b = math.floor(255 * brightness)
                            local a = 255
                            
                            -- Добавляем вершины
                            table.insert(vertices, {ox+v1[1], oy+v1[2], oz+v1[3], u1, v2_uv, r, g, b, a})
                            table.insert(vertices, {ox+v2[1], oy+v2[2], oz+v2[3], u2, v2_uv, r, g, b, a})
                            table.insert(vertices, {ox+v3[1], oy+v3[2], oz+v3[3], u2, v1_uv, r, g, b, a})
                            
                            table.insert(vertices, {ox+v1[1], oy+v1[2], oz+v1[3], u1, v2_uv, r, g, b, a})
                            table.insert(vertices, {ox+v3[1], oy+v3[2], oz+v3[3], u2, v1_uv, r, g, b, a})
                            table.insert(vertices, {ox+v4[1], oy+v4[2], oz+v4[3], u1, v1_uv, r, g, b, a})
                        end
                    end
                end
            end
        end
    end
    
    if #vertices > 0 then
        self.mesh = love.graphics.newMesh(vertexFormat, vertices, "triangles", "static")
    else
        self.mesh = nil
    end
    
    self.dirty = false
    return self.mesh
end

return Chunk