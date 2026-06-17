local mat = require("MathUtils")

local Camera = {}
Camera.__index = Camera

function Camera.new()
    local self = setmetatable({}, Camera)
    self.pos = {x = 32, y = 20, z = 32}
    self.yaw = 0
    self.pitch = 0
    return self
end

function Camera:update(mx, my)
    local sensitivity = 0.003

    self.yaw = self.yaw + mx * sensitivity
    
    -- Ограничиваем Pitch (взгляд вверх/вниз), чтобы не перевернуться
    self.pitch = self.pitch + my * sensitivity
    self.pitch = math.max(-math.pi/2 + 0.01, math.min(math.pi/2 - 0.01, self.pitch))
end

function Camera:getForwardVector()
    -- Получение направления взгляда камеры для рейкастинга
    return {
        x = math.sin(self.yaw) * math.cos(self.pitch),
        y = -math.sin(self.pitch),
        z = -math.cos(self.yaw) * math.cos(self.pitch)
    }
end

function Camera:getViewMatrix()
    local rotX = mat.rotateX(-self.pitch)
    local rotY = mat.rotateY(-self.yaw)
    local trans = mat.translate(-self.pos.x, -self.pos.y, -self.pos.z)
    
    return mat.multiply(rotX, mat.multiply(rotY, trans))
end

return Camera
