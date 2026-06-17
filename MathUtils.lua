local mat = {}

function mat.identity()
    return {
        1, 0, 0, 0,
        0, 1, 0, 0,
        0, 0, 1, 0,
        0, 0, 0, 1
    }
end

-- Создание перспективной матрицы проекции (Row-Major для LÖVE 11+)
function mat.perspective(fov, aspect, near, far)
    local f = 1 / math.tan(fov / 2)
    local m = {}
    for i=1,16 do m[i] = 0 end
    m[1] = f / aspect
    m[6] = f
    m[11] = -(far + near) / (far - near)
    m[12] = -(2 * far * near) / (far - near)
    m[15] = -1
    return m
end

-- Перемножение матриц (Row-Major)
function mat.multiply(a, b)
    local result = {}
    for i = 1, 16 do result[i] = 0 end
    for row = 1, 4 do
        for col = 1, 4 do
            local sum = 0
            for k = 1, 4 do
                sum = sum + a[(row-1)*4 + k] * b[(k-1)*4 + col]
            end
            result[(row-1)*4 + col] = sum
        end
    end
    return result
end

-- Матрица переноса (Row-Major)
function mat.translate(x, y, z)
    local m = mat.identity()
    m[4], m[8], m[12] = x, y, z
    return m
end

-- Поворот вокруг X (Row-Major)
function mat.rotateX(angle)
    local m = mat.identity()
    local c, s = math.cos(angle), math.sin(angle)
    m[6], m[7], m[10], m[11] = c, s, -s, c
    return m
end

-- Поворот вокруг Y (Row-Major)
function mat.rotateY(angle)
    local m = mat.identity()
    local c, s = math.cos(angle), math.sin(angle)
    m[1], m[3], m[9], m[11] = c, -s, s, c
    return m
end

-- Вспомогательные функции для 2D генерации ландшафта (FBM Value Noise)
local function hash2D(x, z)
    local n = math.sin(x * 12.9898 + z * 78.233) * 43758.5453123
    return n - math.floor(n)
end

local function lerp(a, b, t)
    return a + (b - a) * t
end

local function fade(t)
    return t * t * t * (t * (t * 6 - 15) + 10)
end

function mat.noise2D(x, z)
    local x0 = math.floor(x)
    local z0 = math.floor(z)
    local xf = x - x0
    local zf = z - z0
    
    local u = fade(xf)
    local v = fade(zf)
    
    local n00 = hash2D(x0, z0)
    local n10 = hash2D(x0 + 1, z0)
    local n01 = hash2D(x0, z0 + 1)
    local n11 = hash2D(x0 + 1, z0 + 1)
    
    local x1 = lerp(n00, n10, u)
    local x2 = lerp(n01, n11, u)
    
    return lerp(x1, x2, v)
end

function mat.fbm2D(x, z, octaves)
    local total = 0
    local frequency = 0.05
    local amplitude = 1.0
    local maxValue = 0
    for i = 1, octaves do
        total = total + mat.noise2D(x * frequency, z * frequency) * amplitude
        maxValue = maxValue + amplitude
        amplitude = amplitude * 0.5
        frequency = frequency * 2
    end
    return total / maxValue
end

return mat
