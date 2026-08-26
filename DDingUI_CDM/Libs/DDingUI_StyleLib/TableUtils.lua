------------------------------------------------------
-- DDingUI_StyleLib :: TableUtils
-- 테이블 유틸리티 (inspired by AbstractFramework)
------------------------------------------------------
local MAJOR = "DDingUI-StyleLib-1.0"
local Lib = LibStub:GetLibrary(MAJOR)
if not Lib then return end

---------------------------------------------------------------------
-- Deep Copy
---------------------------------------------------------------------
--- 테이블 딥카피 (중첩 테이블 포함)
--- @param orig table
--- @return table copy
function Lib.DeepCopy(orig)
    if type(orig) ~= "table" then return orig end
    local copy = {}
    for k, v in pairs(orig) do
        if type(v) == "table" then
            copy[k] = Lib.DeepCopy(v)
        else
            copy[k] = v
        end
    end
    return copy
end

---------------------------------------------------------------------
-- IsEmpty
---------------------------------------------------------------------
--- 테이블이 비어있는지 확인
--- @param t table
--- @return boolean
function Lib.IsEmpty(t)
    if t == nil then return true end
    return next(t) == nil
end

---------------------------------------------------------------------
-- Contains
---------------------------------------------------------------------
--- 테이블에 값이 포함되어 있는지 확인 (배열 순회)
--- @param t table
--- @param value any
--- @return boolean
function Lib.Contains(t, value)
    for _, v in pairs(t) do
        if v == value then return true end
    end
    return false
end

---------------------------------------------------------------------
-- Remove by value
---------------------------------------------------------------------
--- 배열에서 값으로 첫 번째 매칭 요소 제거
--- @param t table (array)
--- @param value any
--- @return boolean removed
function Lib.RemoveByValue(t, value)
    for i, v in ipairs(t) do
        if v == value then
            tremove(t, i)
            return true
        end
    end
    return false
end

---------------------------------------------------------------------
-- Merge (shallow)
---------------------------------------------------------------------
--- t2의 키/값을 t1에 병합 (기존 키는 덮어쓰기)
--- @param t1 table  대상
--- @param t2 table  소스
--- @return table t1
function Lib.Merge(t1, t2)
    for k, v in pairs(t2) do
        t1[k] = v
    end
    return t1
end

---------------------------------------------------------------------
-- Keys / Values
---------------------------------------------------------------------
--- 테이블의 키를 배열로 반환
function Lib.Keys(t)
    local keys = {}
    for k in pairs(t) do
        tinsert(keys, k)
    end
    return keys
end

--- 테이블의 값을 배열로 반환
function Lib.Values(t)
    local vals = {}
    for _, v in pairs(t) do
        tinsert(vals, v)
    end
    return vals
end

---------------------------------------------------------------------
-- Count (hash table length)
---------------------------------------------------------------------
--- 해시 테이블의 요소 수 반환
function Lib.Count(t)
    local n = 0
    for _ in pairs(t) do
        n = n + 1
    end
    return n
end
