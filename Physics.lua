local Block = require("Block")

local Physics = {}

function Physics.getSurroundingBlocks(world, pos, size)
    local minX = math.floor(pos.x - size.w / 2) + 1
    local maxX = math.floor(pos.x + size.w / 2) + 1
    local minY = math.floor(pos.y) + 1
    local maxY = math.floor(pos.y + size.h) + 1
    local minZ = math.floor(pos.z - size.d / 2) + 1
    local maxZ = math.floor(pos.z + size.d / 2) + 1
    
    local blocks = {}
    for x = minX, maxX do
        for y = minY, maxY do
            for z = minZ, maxZ do
                local block = world:getBlock(x, y, z)
                if block and Block.isCollidable(block) then
                    table.insert(blocks, {
                        x = x, y = y, z = z,
                        minX = x - 1, maxX = x,
                        minY = y - 1, maxY = y,
                        minZ = z - 1, maxZ = z
                    })
                end
            end
        end
    end
    return blocks
end

function Physics.checkCollision(pos, size, blocks)
    local p_minX = pos.x - size.w / 2
    local p_maxX = pos.x + size.w / 2
    local p_minY = pos.y
    local p_maxY = pos.y + size.h
    local p_minZ = pos.z - size.d / 2
    local p_maxZ = pos.z + size.d / 2
    
    for _, b in ipairs(blocks) do
        if p_maxX > b.minX and p_minX < b.maxX and
           p_maxY > b.minY and p_minY < b.maxY and
           p_maxZ > b.minZ and p_minZ < b.maxZ then
            return true
        end
    end
    return false
end

function Physics.update(player, world, dt, keys, camera)
    -- Ограничиваем dt, чтобы избежать пролетов сквозь стены при зависаниях кадров
    dt = math.min(dt, 0.03)

    -- Гравитация
    if not player.flying then
        player.vel.y = player.vel.y - 24 * dt
        if player.vel.y < -40 then player.vel.y = -40 end
    else
        player.vel.y = 0
    end
    
    -- Получение вектора движения игрока
    local speed = player.flying and 12 or 5
    local moveX, moveZ = 0, 0
    local yaw = camera.yaw
    local forward = { x = math.sin(yaw), z = -math.cos(yaw) }
    local right = { x = math.cos(yaw), z = math.sin(yaw) }
    
    if keys["w"] then
        moveX = moveX + forward.x
        moveZ = moveZ + forward.z
    end
    if keys["s"] then
        moveX = moveX - forward.x
        moveZ = moveZ - forward.z
    end
    if keys["a"] then
        moveX = moveX - right.x
        moveZ = moveZ - right.z
    end
    if keys["d"] then
        moveX = moveX + right.x
        moveZ = moveZ + right.z
    end
    
    -- Нормализация вектора перемещения
    local len = math.sqrt(moveX * moveX + moveZ * moveZ)
    if len > 0 then
        moveX = (moveX / len) * speed
        moveZ = (moveZ / len) * speed
    end
    
    player.vel.x = moveX
    player.vel.z = moveZ
    
    -- Прыжок или подъем/спуск в полете
    if player.flying then
        if keys["space"] then
            player.pos.y = player.pos.y + 10 * dt
        end
        if keys["lshift"] or keys["shift"] then
            player.pos.y = player.pos.y - 10 * dt
        end
    else
        if keys["space"] and player.on_ground then
            player.vel.y = 8.5
            player.on_ground = false
        end
    end
    
    -- Раздельное разрешение коллизий по трем осям (Слайдинг-эффект)
    
    -- 1. Ось X
    player.pos.x = player.pos.x + player.vel.x * dt
    local blocks = Physics.getSurroundingBlocks(world, player.pos, player.size)
    for _, b in ipairs(blocks) do
        if player.pos.x + player.size.w/2 > b.minX and player.pos.x - player.size.w/2 < b.maxX and
           player.pos.y + player.size.h > b.minY and player.pos.y < b.maxY and
           player.pos.z + player.size.d/2 > b.minZ and player.pos.z - player.size.d/2 < b.maxZ then
            if player.vel.x > 0 then
                player.pos.x = b.minX - player.size.w/2 - 0.0001
            elseif player.vel.x < 0 then
                player.pos.x = b.maxX + player.size.w/2 + 0.0001
            end
            player.vel.x = 0
            break
        end
    end
    
    -- 2. Ось Y
    player.on_ground = false
    player.pos.y = player.pos.y + player.vel.y * dt
    blocks = Physics.getSurroundingBlocks(world, player.pos, player.size)
    for _, b in ipairs(blocks) do
        if player.pos.x + player.size.w/2 > b.minX and player.pos.x - player.size.w/2 < b.maxX and
           player.pos.y + player.size.h > b.minY and player.pos.y < b.maxY and
           player.pos.z + player.size.d/2 > b.minZ and player.pos.z - player.size.d/2 < b.maxZ then
            if player.vel.y > 0 then
                player.pos.y = b.minY - player.size.h - 0.0001
            elseif player.vel.y < 0 then
                player.pos.y = b.maxY + 0.0001
                player.on_ground = true
            end
            player.vel.y = 0
            break
        end
    end
    
    -- 3. Ось Z
    player.pos.z = player.pos.z + player.vel.z * dt
    blocks = Physics.getSurroundingBlocks(world, player.pos, player.size)
    for _, b in ipairs(blocks) do
        if player.pos.x + player.size.w/2 > b.minX and player.pos.x - player.size.w/2 < b.maxX and
           player.pos.y + player.size.h > b.minY and player.pos.y < b.maxY and
           player.pos.z + player.size.d/2 > b.minZ and player.pos.z - player.size.d/2 < b.maxZ then
            if player.vel.z > 0 then
                player.pos.z = b.minZ - player.size.d/2 - 0.0001
            elseif player.vel.z < 0 then
                player.pos.z = b.maxZ + player.size.d/2 + 0.0001
            end
            player.vel.z = 0
            break
        end
    end
    
    -- Синхронизация камеры с глазами игрока
    camera.pos.x = player.pos.x
    camera.pos.y = player.pos.y + 1.62 -- Высота глаз Стива над землей
    camera.pos.z = player.pos.z
end

return Physics
