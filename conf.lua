function love.conf(t)
    t.identity = nil
    t.version = "11.0" -- Совместимо со всеми версиями LÖVE 11.x и 12.x
    
    t.window.title = "LÖVE 3D Minecraft Clone"
    t.window.width = 800
    t.window.height = 600
    t.window.msaa = 4                   -- Сглаживание 4x
    t.window.depth = 24                 -- ВКЛЮЧАЕМ 24-битный буфер глубины при старте приложения (КРИТИЧЕСКИ ВАЖНО ДЛЯ 3D!)
    t.window.resizable = true           -- Разрешаем изменять размер окна
end
