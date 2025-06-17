-- StringLib.lua: Minimal custom string library for QPS (to avoid global string pollution)

local strchar_cache = string.char

StringLib = {}
StringLib._cache = {}

-- Converts a string to a table of characters and returns the table and its length
function StringLib._toTable(s)
    local t = {}
    local i = 1
    while true do
        local b = string.byte and string.byte(s, i) or nil
        if not b then break end
        t[i] = string.char and string.char(b) or "?"
        i = i + 1
    end
    return t, i - 1
end

-- Returns the length of the string without using any string library functions or # operator
function StringLib.Len(s)
    if type(s) ~= "string" then return 0 end
    if not StringLib._cache[s] then
        local t, len = StringLib._toTable(s)
        StringLib._cache[s] = { t = t, len = len }
    end
    return StringLib._cache[s].len
end

-- Returns the byte value of the character at position i (1-based), or nil if out of bounds or not a recognized char
function StringLib.Byte(s, i)
    if type(s) ~= "string" or type(i) ~= "number" or i < 1 then return nil end
    if not StringLib._cache[s] then
        local t, len = StringLib._toTable(s)
        StringLib._cache[s] = { t = t, len = len }
    end
    local ch = StringLib._cache[s].t[i]
    if not ch then return nil end
    if ch == " " then return 32 end
    if ch == "/" then return 47 end
    if ch >= "0" and ch <= "9" then return string.byte and string.byte(ch) or nil end
    return nil
end

-- Returns a substring from i to j (inclusive, 1-based, like string.sub)
function StringLib.Sub(s, i, j)
    if type(s) ~= "string" or type(i) ~= "number" then return "" end
    if not StringLib._cache[s] then
        local t, len = StringLib._toTable(s)
        StringLib._cache[s] = { t = t, len = len }
    end
    local t = StringLib._cache[s].t
    local len = StringLib._cache[s].len
    local start = i or 1
    local stop = j or len
    if start < 1 then start = 1 end
    if stop > len then stop = len end
    if stop < start then return "" end
    local out = ""
    for k = start, stop do
        out = out .. (t[k] or "")
    end
    return out
end

function StringLib.SafeExtractNumbers(str, debugFunc)
    if type(str) ~= "string" then return nil, nil end
    local len = StringLib.Len(str)
    local slash = nil
    for i = 1, len do
        local c = StringLib.Byte(str, i)
        if c == 47 then slash = i break end
    end
    if not slash then
        if debugFunc then debugFunc("No slash found in: " .. tostring(str)) end
        return nil, nil
    end
    local num1_end = slash - 1
    while num1_end >= 1 and StringLib.Byte(str, num1_end) == 32 do num1_end = num1_end - 1 end
    local num1_start = num1_end
    while num1_start >= 1 do
        local c = StringLib.Byte(str, num1_start)
        if c == nil or c < 48 or c > 57 then break end
        num1_start = num1_start - 1
    end
    num1_start = num1_start + 1
    local num2_start = slash + 1
    while num2_start <= len and StringLib.Byte(str, num2_start) == 32 do num2_start = num2_start + 1 end
    local num2_end = num2_start
    while num2_end <= len do
        local c = StringLib.Byte(str, num2_end)
        if c == nil or c < 48 or c > 57 then break end
        num2_end = num2_end + 1
    end
    num2_end = num2_end - 1
    if num1_start <= num1_end and num2_start <= num2_end then
        local n1, n2 = 0, 0
        for i = num1_start, num1_end do n1 = n1 * 10 + (StringLib.Byte(str, i) - 48) end
        for i = num2_start, num2_end do n2 = n2 * 10 + (StringLib.Byte(str, i) - 48) end
        if debugFunc then debugFunc("Extracted: " .. tostring(n1) .. "/" .. tostring(n2) .. " from: " .. tostring(str)) end
        if n1 and n2 then return n1, n2 end
    else
        if debugFunc then debugFunc("Failed to extract numbers from: " .. tostring(str)) end
    end
    return nil, nil
end

function StringLib.Find(s, pattern)
    if type(s) ~= "string" or type(pattern) ~= "string" then return nil end
    -- Only supports plain string search, not patterns
    local slen = StringLib.Len(s)
    local plen = StringLib.Len(pattern)
    if plen == 0 or slen == 0 or plen > slen then return nil end
    for i = 1, slen - plen + 1 do
        if StringLib.Sub(s, i, i + plen - 1) == pattern then
            return i
        end
    end
    return nil
end

function StringLib.Gsub(s, pattern, repl)
    -- Only supports plain string replacement, not patterns
    if type(s) ~= "string" or type(pattern) ~= "string" or type(repl) ~= "string" then return s end
    local out = ""
    local i = 1
    local slen = StringLib.Len(s)
    local plen = StringLib.Len(pattern)
    if plen == 0 then return s end
    while i <= slen do
        if StringLib.Sub(s, i, i + plen - 1) == pattern then
            out = out .. repl
            i = i + plen
        else
            out = out .. StringLib.Sub(s, i, i)
            i = i + 1
        end
    end
    return out
end

function StringLib.Match(s, pattern)
    -- Only supports exact match or prefix match (pattern ending with *)
    if type(s) ~= "string" or type(pattern) ~= "string" then return nil end
    local plen = StringLib.Len(pattern)
    if plen == 0 then return nil end
    if StringLib.Sub(pattern, plen, plen) == "*" then
        local prefix = StringLib.Sub(pattern, 1, plen - 1)
        if StringLib.Sub(s, 1, plen - 1) == prefix then
            return prefix
        end
    elseif s == pattern then
        return s
    end
    return nil
end

-- Converts a byte (0-255) to a two-digit uppercase hex string using only StringLib
function StringLib.ByteToHex(byte)
    byte = tonumber(byte) or 0
    local hexChars = "0123456789ABCDEF"
    local high = math.floor(byte / 16) + 1
    local low = byte - math.floor(byte / 16) * 16 + 1
    return StringLib.Sub(hexChars, high, high) .. StringLib.Sub(hexChars, low, low)
end

function StringLib.PatternMatch(s, pattern)
    -- Only supports a single capture group: '^(.+):' or similar
    -- Returns the first capture, or nil if not matched
    if type(s) ~= "string" or type(pattern) ~= "string" then return nil end
    -- Only support patterns like "^(.+):" (prefix up to first colon)
    if pattern == "^(.+):" then
        local colon = StringLib.Find(s, ":")
        if colon and colon > 1 then
            return StringLib.Sub(s, 1, colon - 1)
        end
        return nil
    end
    -- Fallback: exact match
    if s == pattern then return s end
    return nil
end

-- Add StringLib.Char for ASCII code to character conversion
function StringLib.Char(byte)
    byte = tonumber(byte) or 0
    if byte < 0 then byte = 0 end
    if byte > 255 then byte = 255 end
    return strchar_cache(byte)
end
