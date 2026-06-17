local Block = {}

Block.UV_SIZE = 16 / 256

-- Реестр блоков (Координаты в классическом Minecraft атласе terrain.png)
-- ID -> { name, transparent, uv = { top, side, bottom } }
Block.Types = {
    [0] = { name = "Воздух", transparent = true },
    [1] = { 
        name = "Трава", 
        transparent = false,
        uv = { top = {0, 0}, side = {3, 0}, bottom = {2, 0} } 
    },
    [2] = { 
        name = "Земля", 
        transparent = false,
        uv = { all = {2, 0} } 
    },
    [3] = { 
        name = "Камень", 
        transparent = false,
        uv = { all = {1, 0} } 
    },
    [4] = { 
        name = "Дерево (Ствол)", 
        transparent = false,
        uv = { top = {5, 1}, side = {4, 1}, bottom = {5, 1} } 
    },
    [5] = { 
        name = "Листья", 
        transparent = true,
        uv = { all = {4, 3} } 
    },
    [6] = { 
        name = "Стекло", 
        transparent = true,
        uv = { all = {1, 3} } 
    },
    [7] = { 
        name = "Доски", 
        transparent = false,
        uv = { all = {4, 0} } 
    },
    -- ЭМИССИВНЫЕ БЛОКИ С ОСВЕЩЕНИЕМ (добавляем 8 = Факел)
    [8] = { 
        name = "Факел", 
        transparent = true,
        uv = { all = {0, 5} },
        emissive = true,
        light_level = 14
    },
    [9] = {
        name = "Светящийся камень",
        transparent = false,
        uv = { all = {13, 1} },
        emissive = true,
        light_level = 15
    },
}

function Block.getUV(id, face_type)
    local b = Block.Types[id]
    if not b or id == 0 then return 0, 0 end
    
    local uv = b.uv[face_type] or b.uv.all or {0,0}
    return uv[1] * Block.UV_SIZE, uv[2] * Block.UV_SIZE
end

function Block.isTransparent(id)
    local b = Block.Types[id]
    if not b then return true end
    return b.transparent == true
end

function Block.isEmissive(id)
    local b = Block.Types[id]
    if not b then return false end
    return b.emissive == true
end

function Block.getLightLevel(id)
    local b = Block.Types[id]
    if not b or not b.emissive then return 0 end
    return b.light_level or 0
end

function Block.getName(id)
    local b = Block.Types[id]
    if not b then return "Неизвестно" end
    return b.name
end

return Block
