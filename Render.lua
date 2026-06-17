local mat = require("MathUtils")

local Render = {}

function Render.init()
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

function Render.draw(world, camera, texture, target, player, selected_block, day_time)
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
    for cx = 1, world.width do
        for cz = 1, world.depth do
            local chunk = world.chunks[cx][cz]
            local mesh = chunk:buildMesh()
            if mesh then
                mesh:setTexture(texture)
                love.graphics.draw(mesh)
            end
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
    
    -- Восстанавливаем цвет рисунка
    love.graphics.setColor(1, 1, 1, 1)
end

return Render
