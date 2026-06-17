local World = require("World")
local Camera = require("Camera")
local Render = require("Render")
local Physics = require("Physics")

local Game = {}

function Game.init()
    Render.init()
    
    -- Загрузка текстуры атласа блоков
    local success, img = pcall(love.graphics.newImage, "terrain.png")
    if success then
        Game.texture = img
        -- Отключаем фильтрацию (размытие), чтобы пиксель-арт оставался четким и кубическим!
        Game.texture:setFilter("nearest", "nearest")
    else
        -- Заглушка, если файл не найден
        local img_data = love.image.newImageData(16, 16)
        for x=0,15 do
            for y=0,15 do
                img_data:setPixel(x,y, 0.8, 0.4, 0.8, 1)
            end
        end
        Game.texture = love.graphics.newImage(img_data)
        Game.texture:setFilter("nearest", "nearest")
    end
    
    -- Создаем мир размером 4x4 чанка (64x64 блоков по горизонтали, 32 по вертикали)
    Game.world = World.new()
    Game.world:generateArea(4, 4)
    
    -- Инициализируем камеру
    Game.camera = Camera.new()
    
    -- Инициализируем игрока
    Game.player = {
        pos = {x = 32, y = 15, z = 32}, -- Исходная позиция
        vel = {x = 0, y = 0, z = 0},
        size = {w = 0.6, h = 1.8, d = 0.6}, -- Реалистичные габариты Стива
        on_ground = false,
        flying = false -- Начинаем с выключенным полетом (работает физика)
    }
    
    Game.time = math.pi / 2.5 -- Старт суточного цикла (утро/полдень, светло и красиво!)
    
    -- Ставим игрока ровно на поверхность ландшафта, чтобы не провалиться
    local spawnX, spawnZ = 32, 32
    for y = Game.world.height, 1, -1 do
        if Game.world:getBlock(spawnX, y, spawnZ) ~= 0 then
            Game.player.pos.y = y + 0.1
            break
        end
    end
    
    Game.selected_block = 1 -- По умолчанию выбрана трава
    Game.keys = {}
    Game.mx, Game.my = 0, 0
    Game.target = {hit = false}
end

function Game.update(dt)
    -- 1. Обновляем время суток (медленный суточный цикл день/закат/ночь/рассвет)
    Game.time = (Game.time + dt * 0.015) % (2 * math.pi)

    -- 2. Обновляем направление взгляда камеры (вращение)
    Game.camera:update(Game.mx, Game.my)
    Game.mx, Game.my = 0, 0 -- Сбрасываем относительное смещение мыши
    
    -- 3. Обновляем физику и коллизии игрока
    Physics.update(Game.player, Game.world, dt, Game.keys, Game.camera)
    
    -- 4. Выполняем трассировку луча (Raycast) из камеры для выделения блоков
    local origin = {
        x = Game.camera.pos.x,
        y = Game.camera.pos.y,
        z = Game.camera.pos.z
    }
    local dir = Game.camera:getForwardVector()
    Game.target = Game.world:raycast(origin, dir, 5.0) -- Дистанция взаимодействия - 5 блоков
end

function Game.draw()
    Render.draw(Game.world, Game.camera, Game.texture, Game.target, Game.player, Game.selected_block, Game.time)
end

function Game.keypressed(key)
    -- Переключение режимов полета
    if key == "f" then
        Game.player.flying = not Game.player.flying
        Game.player.vel.y = 0 -- Сбрасываем вертикальную скорость при переключении
    end
    
    -- Быстрый выбор блока на клавиши 1-9
    local block_map = {
        ["1"] = 1, -- Трава
        ["2"] = 2, -- Земля
        ["3"] = 3, -- Камень
        ["4"] = 4, -- Ствол дерева
        ["5"] = 5, -- Листья
        ["6"] = 6, -- Стекло
        ["7"] = 7, -- Доски
        ["8"] = 8, -- Факел (свет)
        ["9"] = 9, -- Светящийся камень
    }
    if block_map[key] then
        Game.selected_block = block_map[key]
    end
end

function Game.mousepressed(x, y, button)
    if button == 1 then
        -- ЛКМ: Сломать блок
        if Game.target and Game.target.hit then
            Game.world:setBlock(Game.target.bx, Game.target.by, Game.target.bz, 0)
        end
    elseif button == 2 then
        -- ПКМ: Поставить блок
        if Game.target and Game.target.hit then
            local px = Game.target.bx + Game.target.normal.x
            local py = Game.target.by + Game.target.normal.y
            local pz = Game.target.bz + Game.target.normal.z
            
            -- Проверка, чтобы не поставить блок внутри игрока
            local b_minX, b_maxX = px - 1, px
            local b_minY, b_maxY = py - 1, py
            local b_minZ, b_maxZ = pz - 1, pz
            
            local p_minX = Game.player.pos.x - Game.player.size.w / 2
            local p_maxX = Game.player.pos.x + Game.player.size.w / 2
            local p_minY = Game.player.pos.y
            local p_maxY = Game.player.pos.y + Game.player.size.h
            local p_minZ = Game.player.pos.z - Game.player.size.d / 2
            local p_maxZ = Game.player.pos.z + Game.player.size.d / 2
            
            local collides = p_maxX > b_minX and p_minX < b_maxX and
                             p_maxY > b_minY and p_minY < b_maxY and
                             p_maxZ > b_minZ and p_minZ < b_maxZ
                             
            if not collides then
                Game.world:setBlock(px, py, pz, Game.selected_block)
            end
        end
    end
end

return Game
