local Game = require("Game")

function love.load()
    -- Устанавливаем режим окна с 4x сглаживанием и включенным 24-битным буфером глубины
    love.window.setMode(800, 600, {msaa = 4, depth = 24, resizable = true})
    love.window.setTitle("LÖVE 3D Minecraft Clone")
    
    -- Скрываем и захватываем курсор мыши
    love.mouse.setVisible(false)
    love.mouse.setRelativeMode(true)
    
    Game.init()
end

function love.update(dt)
    Game.update(dt)
end

function love.draw()
    Game.draw()
end

function love.mousemoved(x, y, dx, dy)
    Game.mx, Game.my = dx, dy
end

function love.mousepressed(x, y, button)
    Game.mousepressed(x, y, button)
end

function love.wheelmoved(x, y)
    if Game.wheelmoved then Game.wheelmoved(x, y) end
end

function love.keypressed(key)
    Game.keys[key] = true
    Game.keypressed(key)
    if key == "escape" then love.event.quit() end
end

function love.keyreleased(key)
    Game.keys[key] = false
end
