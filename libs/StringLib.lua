-- StringLib.lua: Minimal custom string library for QPS (to avoid global string pollution)
-- Provides robust, dependency-free string manipulation utilities for the addon, including safe substring, byte, split, and pattern helpers.

local strchar_cache = string.char
local strbyte_cache = string.byte
local strgsub_cache = string.gsub
local strfind_cache = string.find

StringLib = {}
StringLib._cache = {}

-- Converts a string to a table of characters and returns the table and its length
function StringLib._toTable(s)
    -- Converts a string to a table of characters for internal caching and manipulation.
    -- Returns the table and its length. Used internally for all string operations.
    local t = {}
    local i = 1
    while true do
        local b = strbyte_cache and strbyte_cache(s, i) or nil
        if not b then break end
        t[i] = strchar_cache and strchar_cache(b) or "?"
        i = i + 1
    end
    return t, i - 1
end

-- Returns the length of the string without using any string library functions or # operator
function StringLib.Len(s)
    -- Returns the length of a string, using internal caching for efficiency. Returns 0 if input is not a string.
    -- Returns 0 if input is not a string.
    if type(s) ~= "string" then return 0 end
    if not StringLib._cache[s] then
        local t, len = StringLib._toTable(s)
        StringLib._cache[s] = { t = t, len = len }
    end
    return StringLib._cache[s].len
end

-- Returns the byte value of the character at position i (1-based), or nil if out of bounds
function StringLib.Byte(s, i)
    -- Returns the ASCII byte value of the character at the given position in the string (1-based). Returns nil if out of bounds or invalid input.
    -- Returns nil if out of bounds or invalid input.
    if type(s) ~= "string" or type(i) ~= "number" or i < 1 then return nil end
    if not StringLib._cache[s] then
        local t, len = StringLib._toTable(s)
        StringLib._cache[s] = { t = t, len = len }
    end
    local ch = StringLib._cache[s].t[i]
    if not ch then return nil end
    -- Return the byte value for any character (ASCII 0-255)
    local b = 0
    -- Use cached string.byte if available, else fallback to manual lookup
    if strbyte_cache then
        b = strbyte_cache(ch)
    else
        -- Fallback: build a lookup table for ASCII 0-255
        if not StringLib._byte_lookup then
            StringLib._byte_lookup = {}
            for n = 0, 255 do
                StringLib._byte_lookup[strchar_cache(n)] = n
            end
        end
        b = StringLib._byte_lookup[ch] or 0
    end
    return b
end

-- Returns a substring from i to j (inclusive, 1-based, like string.sub)
function StringLib.Sub(s, i, j)
    -- Returns a substring from position i to j (inclusive), using internal caching. Returns an empty string if indices are invalid.
    -- Returns an empty string if indices are invalid.
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

-- Safely extracts two numbers separated by a slash (e.g., '1/5') from a string. Returns the two numbers, or nil, nil if not found. Optionally logs debug info.
function StringLib.SafeExtractNumbers(str, debugFunc)
    -- Safely extracts two numbers separated by a slash (e.g., '1/5') from a string. Returns the two numbers, or nil, nil if not found. Optionally logs debug info.
    -- Returns the two numbers, or nil, nil if not found. Optionally logs debug info.
    if type(str) ~= "string" then return nil, nil end
    local len = StringLib.Len(str)
    local slash = nil
    for i = 1, len do
        local c = StringLib.Byte(str, i)
        if c == 47 then slash = i break end
    end
    if not slash then
        if debugFunc then debugFunc("[QPS-DEBUG] No slash found in: " .. tostring(str)) end
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
        if debugFunc then debugFunc("[QPS-WARN] Failed to extract numbers from: " .. tostring(str)) end
    end
    return nil, nil
end

-- Finds a pattern in a string, supporting optional init and plain arguments (like string.find). Returns the start and end indices of the match, or nil if not found.
function StringLib.Find(s, pattern, init, plain)
    -- Finds a pattern in a string, supporting optional init and plain arguments (like string.find). Returns the start and end indices of the match, or nil if not found.
    -- Returns the start and end indices of the match, or nil if not found.
    if type(s) ~= "string" or type(pattern) ~= "string" then return nil end
    -- Behaves like string.find: supports patterns and optional init/plain
    return strfind_cache(s, pattern, init, plain)
end

-- Performs a global substitution on a string, replacing all matches of pattern with repl. Returns the new string.
function StringLib.Gsub(s, pattern, repl)
    -- Performs a global substitution on a string, replacing all matches of pattern with repl. Returns the new string.
    -- Returns the new string.
    if type(s) ~= "string" or type(pattern) ~= "string" or type(repl) ~= "string" then return s end
    -- Use cached string.gsub for full pattern support
    return strgsub_cache(s, pattern, repl)
end

-- Matches a string against a pattern. Supports exact match or prefix match if pattern ends with '*'. Returns the matched string or prefix, or nil if not matched.
function StringLib.Match(s, pattern)
    -- Matches a string against a pattern. Supports exact match or prefix match if pattern ends with '*'. Returns the matched string or prefix, or nil if not matched.
    -- Returns the matched string or prefix, or nil if not matched.
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
    -- Converts a byte value (0-255) to a two-digit uppercase hexadecimal string.
    byte = tonumber(byte) or 0
    local hexChars = "0123456789ABCDEF"
    local high = math.floor(byte / 16) + 1
    local low = byte - math.floor(byte / 16) * 16 + 1
    return StringLib.Sub(hexChars, high, high) .. StringLib.Sub(hexChars, low, low)
end

-- Converts an ASCII byte value (0-255) to its corresponding character.
function StringLib.Char(byte)
    -- Converts an ASCII byte value (0-255) to its corresponding character.
    byte = tonumber(byte) or 0
    if byte < 0 then byte = 0 end
    if byte > 255 then byte = 255 end
    return strchar_cache(byte)
end

-- Converts a string to uppercase (ASCII only).
function StringLib.Upper(str)
    -- Converts a string to uppercase (ASCII only).
    -- Only works for ASCII, which is fine for Vanilla class tokens
    local b = {}
    local len = StringLib.Len(str)
    for i = 1, len do
        local c = StringLib.Byte(str, i)
        if c and c >= 97 and c <= 122 then -- a-z
            b[i] = StringLib.Char(c - 32)
        else
            b[i] = StringLib.Char(c or 0)
        end
    end
    return table.concat(b)
end

-- Converts a string to lowercase (ASCII only).
function StringLib.Lower(str)
    -- Converts a string to lowercase (ASCII only).
    -- Only works for ASCII, which is fine for quest text and 'quest abandoned' checks
    local b = {}
    local len = StringLib.Len(str)
    for i = 1, len do
        local c = StringLib.Byte(str, i)
        if c and c >= 65 and c <= 90 then -- A-Z
            b[i] = StringLib.Char(c + 32)
        else
            b[i] = StringLib.Char(c or 0)
        end
    end
    return table.concat(b)
end

-- Returns true if the string contains any x/y pattern (e.g., 1/5, 10/20, 1 / 5, etc.) anywhere in the string.
function StringLib.HasNumberSlashNumber(s)
    -- Returns true if the string contains any x/y pattern (e.g., 1/5, 10/20, 1 / 5, etc.) anywhere in the string.
    -- Returns true if the string contains any x/y pattern (e.g., 1/5, 10/20, 1 / 5, etc.) anywhere in the string
    if type(s) ~= "string" then return false end
    local len = StringLib.Len(s)
    local i = 1
    while i <= len do
        local c = StringLib.Byte(s, i)
        if c and c >= 48 and c <= 57 then -- found digit
            local j = i + 1
            while j <= len and StringLib.Byte(s, j) == 32 do j = j + 1 end -- skip spaces
            if j <= len and StringLib.Byte(s, j) == 47 then -- found slash
                local k = j + 1
                while k <= len and StringLib.Byte(s, k) == 32 do k = k + 1 end -- skip spaces
                if k <= len then
                    local c3 = StringLib.Byte(s, k)
                    if c3 and c3 >= 48 and c3 <= 57 then
                        LogDebugMessage("[QPS-DEBUG] HasNumberSlashNumber: matched in '"..tostring(s).."'")
                        return true
                    end
                end
            end
        end
        i = i + 1
    end
    LogDebugMessage("[QPS-DEBUG] HasNumberSlashNumber: no match in '"..tostring(s).."'")
    return false
end

-- Splits a string into a table of substrings using a plain separator (no pattern support).
function StringLib.Split(s, sep)
    -- Splits a string into a table of substrings using a plain separator (no pattern support).
    -- Returns a table of substrings.
    if type(s) ~= "string" or type(sep) ~= "string" or sep == "" then return {s} end
    local result = {}
    local slen = StringLib.Len(s)
    local seplen = StringLib.Len(sep)
    local i = 1
    local last = 1
    while i <= slen do
        if StringLib.Sub(s, i, i + seplen - 1) == sep then
            table.insert(result, StringLib.Sub(s, last, i - 1))
            i = i + seplen
            last = i
        else
            i = i + 1
        end
    end
    table.insert(result, StringLib.Sub(s, last, slen))
    return result
end

-- Extracts the quest name and objective index from a key formatted as 'questName-idx'. Returns quest name and objective index as strings, or nil, nil if not valid.
function StringLib.ExtractQuestAndObjIdx(key)
    -- Extracts the quest name and objective index from a key formatted as 'questName-idx'. Returns quest name and objective index as strings, or nil, nil if not valid.
    -- Returns quest name and objective index as strings, or nil, nil if not valid.
    if type(key) ~= "string" then
        LogDebugMessage("[QPS-DEBUG] ExtractQuestAndObjIdx: key is not a string: " .. tostring(key))
        return nil, nil
    end
    local len = StringLib.Len(key)
    local dashPos = nil
    -- Find the last '-' in the string (to allow dashes in quest names)
    for i = len, 1, -1 do
        if StringLib.Sub(key, i, i) == "-" then
            dashPos = i
            break
        end
    end
    if not dashPos then
        LogDebugMessage("[QPS-DEBUG] ExtractQuestAndObjIdx: no dash found in key: " .. tostring(key))
        return nil, nil
    end
    local quest = StringLib.Sub(key, 1, dashPos - 1)
    local objIdxStr = StringLib.Sub(key, dashPos + 1, len)
    -- Check that objIdxStr is all digits
    local isDigits = true
    for i = 1, StringLib.Len(objIdxStr) do
        local b = StringLib.Byte(objIdxStr, i)
        if b < 48 or b > 57 then isDigits = false break end
    end
    if not isDigits then
        LogDebugMessage("[QPS-WARN] ExtractQuestAndObjIdx: objIdx is not all digits: " .. tostring(objIdxStr) .. " in key: " .. tostring(key))
        return nil, nil
    end
    LogDebugMessage(string.format("[QPS-DEBUG] ExtractQuestAndObjIdx: key='%s', quest='%s', objIdx='%s'", tostring(key), tostring(quest), tostring(objIdxStr)))
    return quest, objIdxStr
end