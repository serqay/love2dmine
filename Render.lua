local mat = require("MathUtils")
local Block = require("Block")

local Render = {}

function Render.init()
    Render.icon_quads = {}
    Render.gui_quads = {}
    -- Вершинный шейдер поддерживает смещение модели model_pos для прорисовки рамки блоков.
    local v_shader = [[
        uniform mat4 projection;
        uniform mat4 view;
        uniform vec3 model_pos;
        vec4 position(mat4 transform_projection, vec4 vertex_pos) {
            VaryingTexCoord = VertexTexCoord;
            VaryingColor = VertexColor; // КРИТИЧЕСКИ ВАЖНО: Передаем плоские тени граней из вершин в пиксельный шейдер!
            vec4 world_pos = vertex_pos + vec4(model_pos, 0.0);
            return projection * view * world_pos;
        }
    ]]
    -- Фрагментный шейдер перемножает текстуру на плоский цвет вершины (directional shade)
    -- и на общий уровень дневного света для получения плоского ретро-освещения!
    local f_shader = [[
        uniform float daylight;
        vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
            vec4 tex_color = Texel(tex, tc);
            if (tex_color.a < 0.1) discard; // Убираем прозрачные области (листья, стекла)
            
            // Умножаем текстуру на плоское освещение грани (color) и на общий уровень яркости дня (daylight)
            return vec4(tex_color.rgb * color.rgb * daylight, tex_color.a * color.a);
        }
    ]]
    Render.shader = love.graphics.newShader(v_shader, f_shader)
    
    -- Загружаем майнкрафт-шрифт
    local success_font, font = pcall(love.graphics.newFont, "Minecraft.otf", 20)
    if success_font then
        Render.font = font
    else
        Render.font = love.graphics.newFont(16)
    end
    
    -- Создаем белую текстуру 1x1 для прорисовки 3D каркасной сетки выделения
    local white_data = love.image.newImageData(1, 1)
    white_data:setPixel(0, 0, 1, 1, 1, 1)
    Render.white_texture = love.graphics.newImage(white_data)
    
    -- Создаем красивый полупрозрачный подсвечивающий куб выделения блока из полигонов (triangles)
    local d = 0.008 -- Увеличиваем размер рамки до 0.008, чтобы полностью устранить Z-Fighting (мерцание)
    local vertices = {
        -- Передняя грань (-Z)
        {-d, -d, -d}, {1+d, -d, -d}, {1+d, 1+d, -d},
        {-d, -d, -d}, {1+d, 1+d, -d}, {-d, 1+d, -d},
        
        -- Задняя грань (+Z)
        {-d, -d, 1+d}, {-d, 1+d, 1+d}, {1+d, 1+d, 1+d},
        {-d, -d, 1+d}, {1+d, 1+d, 1+d}, {1+d, -d, 1+d},
        
        -- Верхняя грань (+Y)
        {-d, 1+d, -d}, {-d, 1+d, 1+d}, {1+d, 1+d, 1+d},
        {-d, 1+d, -d}, {1+d, 1+d, 1+d}, {1+d, 1+d, -d},
        
        -- Нижняя грань (-Y)
        {-d, -d, -d}, {1+d, -d, -d}, {1+d, -d, 1+d},
        {-d, -d, -d}, {1+d, -d, 1+d}, {-d, -d, 1+d},
        
        -- Правая грань (+X)
        {1+d, -d, -d}, {1+d, 1+d, -d}, {1+d, 1+d, 1+d},
        {1+d, -d, -d}, {1+d, 1+d, 1+d}, {1+d, -d, 1+d},
        
        -- Левая грань (-X)
        {-d, -d, -d}, {-d, 1+d, -d}, {-d, 1+d, 1+d},
        {-d, -d, -d}, {-d, 1+d, 1+d}, {-d, -d, 1+d}
    }
    
    local format = {
        {"VertexPosition", "float", 3},
    }
    
    Render.outline_mesh = love.graphics.newMesh(format, vertices, "triangles", "static")
    Render.outline_mesh:setTexture(Render.white_texture)
end

function Render.draw(world, camera, texture, gui_texture, icons_texture, target, player, selected_block, day_time, hotbar, inventory, mode, dead)
    -- Расчет суточного времени для смены освещения и цвета неба
    -- Время идет от 0 до 2*pi.
    local angle = day_time or 0
    local height_y = math.sin(angle) -- Положительно днем, отрицательно ночью
    
    -- Классические плоские цвета неба и уровень дневного освещения из старого Minecraft:
    local sky_r, sky_g, sky_b
    local daylight_factor = 1.0
    
    if height_y > 0.15 then
        -- Чистый плоский дневной голубой цвет неба
        local t = math.min((height_y - 0.15) * 4, 1.0)
        sky_r = 0.5 * t + 0.85 * (1.0-t)
        sky_g = 0.69 * t + 0.45 * (1.0-t)
        sky_b = 1.0 * t + 0.25 * (1.0-t)
        
        daylight_factor = 1.0 * t + 0.7 * (1.0-t)
    elseif height_y > -0.15 then
        -- Плоский теплый цвет заката/рассвета
        local t = (height_y + 0.15) / 0.30
        sky_r = 0.85 * t + 0.05 * (1.0-t)
        sky_g = 0.45 * t + 0.05 * (1.0-t)
        sky_b = 0.25 * t + 0.10 * (1.0-t)
        
        daylight_factor = 0.7 * t + 0.22 * (1.0-t)
    else
        -- Абсолютно плоская темная майнкрафтовская ночь
        local t = math.min((-height_y - 0.15) * 4, 1.0)
        sky_r = 0.05 * (1.0-t) + 0.02 * t
        sky_g = 0.05 * (1.0-t) + 0.02 * t
        sky_b = 0.10 * (1.0-t) + 0.04 * t
        
        daylight_factor = 0.22 * (1.0-t) + 0.15 * t -- Ночной уровень света в Alpha
    end
    
    -- Очищаем экран классическим плоским цветом неба старых версий
    love.graphics.clear(sky_r, sky_g, sky_b, 1.0, true, true)
    
    -- Включаем буфер глубины для корректного трехмерного рендеринга
    love.graphics.setDepthMode("lequal", true)
    
    local proj = mat.perspective(math.rad(70), love.graphics.getWidth() / love.graphics.getHeight(), 0.1, 200)
    local view = camera:getViewMatrix()
    
    -- Отправляем матрицы
    Render.shader:send("projection", proj)
    Render.shader:send("view", view)
    
    -- Отправляем плоский коэффициент дневной яркости
    Render.shader:send("daylight", daylight_factor)
    
    love.graphics.setShader(Render.shader)
    
    -- 1. РЕНДЕРИМ ЧАНКИ (МИР)
    Render.shader:send("model_pos", {0, 0, 0})
    
    -- Чтобы копание не давало фриз, не перестраиваем все dirty-чанки в один кадр.
    -- Чанк, где реально изменился блок, помечается priority_dirty и обновляется сразу,
    -- остальные чанки со сменой освещения обновляются маленькими порциями.
    local rebuild_budget = 3
    
    local render_chunks = world.getRenderChunks and world:getRenderChunks() or {}
    for _, chunk in ipairs(render_chunks) do
        local mesh = chunk.mesh
        
        if chunk.dirty then
            local force_rebuild = chunk.priority_dirty == true
            if force_rebuild or rebuild_budget > 0 then
                mesh = chunk:buildMesh()
                chunk.priority_dirty = false
                if not force_rebuild then
                    rebuild_budget = rebuild_budget - 1
                end
            end
        end
        
        if mesh then
            mesh:setTexture(texture)
            love.graphics.draw(mesh)
        end
    end
    
    -- 2. РЕНДЕРИМ КРАСИВЫЙ ПОЛУПРОЗРАЧНЫЙ КУБ ВЫДЕЛЕНИЯ БЛОКА (ЕСЛИ СМОТРИМ НА НЕГО)
    if target and target.hit then
        Render.shader:send("model_pos", {target.bx - 1, target.by - 1, target.bz - 1})
        love.graphics.setColor(1, 1, 1, 0.35) -- Белая полупрозрачная подсветка блока (35% непрозрачности)
        love.graphics.draw(Render.outline_mesh)
        love.graphics.setColor(1, 1, 1, 1) -- Сброс цвета
    end
    
    -- ОТКЛЮЧАЕМ ШЕЙДЕР ДЛЯ ОТРИСОВКИ 2D ИНТЕРФЕЙСА
    love.graphics.setShader()
    love.graphics.setDepthMode() -- Отключаем тест глубины
    
    -- 3. РИСУЕМ КРЕСТИК-ПРИЦЕЛ ПО ЦЕНТРУ ЭКРАНА
    local screen_w = love.graphics.getWidth()
    local screen_h = love.graphics.getHeight()
    local cx, cy = screen_w / 2, screen_h / 2
    love.graphics.setColor(1, 1, 1, 0.7)
    love.graphics.setLineWidth(2)
    love.graphics.line(cx - 8, cy, cx + 8, cy)
    love.graphics.line(cx, cy - 8, cx, cy + 8)
    
    -- 4. РИСУЕМ ТОЛЬКО ФПС И КООРДИНАТЫ В СТИЛЕ МАЙНКРАФТА С ТЕНЬЮ И ШРИФТОМ
    if Render.font then
        love.graphics.setFont(Render.font)
    end
    
    local fps_text = "FPS: " .. love.timer.getFPS()
    local pos_text = string.format("XYZ: %.3f / %.3f / %.3f", player.pos.x, player.pos.y, player.pos.z)
    
    local function drawMinecraftText(text, x, y)
        love.graphics.setColor(0, 0, 0, 0.85) -- Тень
        love.graphics.print(text, x + 2, y + 2)
        love.graphics.setColor(1, 1, 1, 1) -- Белый текст
        love.graphics.print(text, x, y)
    end
    
    drawMinecraftText(fps_text, 10, 10)
    drawMinecraftText(pos_text, 10, 35)
    
    -- Отображение текущего суточного времени в углу для красоты
    local hours = math.floor((angle / (2 * math.pi)) * 24 + 6) % 24
    local minutes = math.floor((((angle / (2 * math.pi)) * 24 + 6) % 1) * 60)
    local time_text = string.format("Time: %02d:%02d", hours, minutes)
    drawMinecraftText(time_text, 10, 60)
    
    if world.seed then
        drawMinecraftText("Seed: " .. tostring(world.seed), 10, 85)
    end
    
    -- 5. Survival HUD / Indev-style GUI
    hotbar = hotbar or {1, 2, 3, 4, 5, 6, 7, 8}
    inventory = inventory or {}
    local slot_scale = 2
    local slot_source_size = 22
    local slot_size = slot_source_size * slot_scale
    local total_w = #hotbar * slot_size
    local hotbar_x = math.floor((screen_w - total_w) / 2)
    local hotbar_y = screen_h - slot_size - 18
    local tex_w = texture.getWidth and texture:getWidth() or 256
    local tex_h = texture.getHeight and texture:getHeight() or 256
    
    local function getGuiQuad(name, x, y, w, h)
        if not gui_texture then return nil end
        local key = name .. ":" .. tostring(gui_texture:getWidth()) .. ":" .. tostring(gui_texture:getHeight())
        local quad = Render.gui_quads[key]
        if not quad then
            quad = love.graphics.newQuad(x, y, w, h, gui_texture:getWidth(), gui_texture:getHeight())
            Render.gui_quads[key] = quad
        end
        return quad
    end
    
    local function getIconQuad(name, x, y, w, h)
        if not icons_texture then return nil end
        local key = name .. ":" .. tostring(icons_texture:getWidth()) .. ":" .. tostring(icons_texture:getHeight())
        local quad = Render.gui_quads[key]
        if not quad then
            quad = love.graphics.newQuad(x, y, w, h, icons_texture:getWidth(), icons_texture:getHeight())
            Render.gui_quads[key] = quad
        end
        return quad
    end
    
    local custom_gui = gui_texture and gui_texture:getWidth() <= 128
    local slot_quad = custom_gui and getGuiQuad("slot_custom", 0, 16, 22, 22) or getGuiQuad("slot_original", 0, 0, 22, 22)
    local selected_slot_quad = custom_gui and getGuiQuad("slot_selected_custom", 22, 16, 22, 22) or getGuiQuad("slot_selected_original", 0, 22, 24, 22)
    local selected_slot_offset = custom_gui and 0 or -2
    
    -- Для оригинального Minecraft icons.png: empty=16,0 full=52,0 half=61,0.
    -- Для fallback gui_indev.png сердца лежат в первых 27 пикселях.
    local heart_full = icons_texture and getIconQuad("heart_full_original", 52, 0, 9, 9) or getGuiQuad("heart_full_custom", 0, 0, 9, 9)
    local heart_half = icons_texture and getIconQuad("heart_half_original", 61, 0, 9, 9) or getGuiQuad("heart_half_custom", 9, 0, 9, 9)
    local heart_empty = icons_texture and getIconQuad("heart_empty_original", 16, 0, 9, 9) or getGuiQuad("heart_empty_custom", 18, 0, 9, 9)
    
    -- Сердца survival-режима
    local health = player.health or player.max_health or 20
    local max_health = player.max_health or 20
    local hearts = math.ceil(max_health / 2)
    local hearts_x = hotbar_x
    local hearts_y = hotbar_y - 28
    for i = 1, hearts do
        local hp_for_heart = health - (i - 1) * 2
        local q = heart_empty
        if hp_for_heart >= 2 then q = heart_full
        elseif hp_for_heart == 1 then q = heart_half end
        local heart_texture = icons_texture or gui_texture
        if q and heart_texture then
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.draw(heart_texture, q, hearts_x + (i - 1) * 18, hearts_y, 0, 2, 2)
        else
            love.graphics.setColor(hp_for_heart > 0 and 0.85 or 0.18, 0, 0, 1)
            love.graphics.rectangle("fill", hearts_x + (i - 1) * 18, hearts_y, 14, 14)
        end
    end
    
    -- Hotbar
    for i, block_id in ipairs(hotbar) do
        local x = hotbar_x + (i - 1) * slot_size
        local selected = block_id == selected_block
        local count = inventory[block_id] or 0
        
        local q = selected and selected_slot_quad or slot_quad
        if q and gui_texture then
            love.graphics.setColor(1, 1, 1, 1)
            local draw_x = selected and (x + selected_slot_offset) or x
            love.graphics.draw(gui_texture, q, draw_x, hotbar_y, 0, slot_scale, slot_scale)
        else
            love.graphics.setColor(0, 0, 0, selected and 0.72 or 0.48)
            love.graphics.rectangle("fill", x, hotbar_y, slot_size, slot_size)
            love.graphics.setLineWidth(selected and 4 or 2)
            love.graphics.setColor(selected and 1 or 0.55, selected and 1 or 0.55, selected and 1 or 0.55, 0.9)
            love.graphics.rectangle("line", x, hotbar_y, slot_size, slot_size)
        end
        
        local quad_key = tostring(block_id) .. ":" .. tostring(tex_w) .. ":" .. tostring(tex_h)
        local quad = Render.icon_quads[quad_key]
        if not quad then
            local u, v = Block.getUV(block_id, "top")
            quad = love.graphics.newQuad(u * tex_w, v * tex_h, 16, 16, tex_w, tex_h)
            Render.icon_quads[quad_key] = quad
        end
        
        love.graphics.setColor(1, 1, 1, count > 0 and 1 or 0.35)
        love.graphics.draw(texture, quad, x + 6, hotbar_y + 6, 0, 2, 2)
        
        love.graphics.setColor(1, 1, 1, 0.9)
        love.graphics.print(tostring(i), x + 4, hotbar_y + slot_size - 18)
        if count > 0 then
            local count_text = tostring(count)
            local count_w = (Render.font and Render.font.getWidth) and Render.font:getWidth(count_text) or (#count_text * 10)
            love.graphics.setColor(0, 0, 0, 0.9)
            love.graphics.print(count_text, x + slot_size - count_w - 3 + 2, hotbar_y + slot_size - 20 + 2)
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.print(count_text, x + slot_size - count_w - 3, hotbar_y + slot_size - 20)
        end
    end
    
    local selected_name = Block.getName(selected_block)
    local selected_count = inventory[selected_block] or 0
    if mode == "survival" then
        selected_name = selected_name .. " x" .. tostring(selected_count)
    end
    local name_w = (Render.font and Render.font.getWidth) and Render.font:getWidth(selected_name) or (#selected_name * 10)
    drawMinecraftText(selected_name, math.floor((screen_w - name_w) / 2), hotbar_y - 52)
    
    if dead then
        love.graphics.setColor(0.35, 0, 0, 0.55)
        love.graphics.rectangle("fill", 0, 0, screen_w, screen_h)
        local death_text = "You died"
        local death_w = (Render.font and Render.font.getWidth) and Render.font:getWidth(death_text) or (#death_text * 10)
        drawMinecraftText(death_text, math.floor((screen_w - death_w) / 2), math.floor(screen_h / 2) - 20)
        local respawn_text = "Respawn in 2s or press R"
        local respawn_w = (Render.font and Render.font.getWidth) and Render.font:getWidth(respawn_text) or (#respawn_text * 10)
        drawMinecraftText(respawn_text, math.floor((screen_w - respawn_w) / 2), math.floor(screen_h / 2) + 12)
    end
    
    -- Восстанавливаем цвет рисунка
    love.graphics.setColor(1, 1, 1, 1)
end

return Render
