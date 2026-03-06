------------------------------------------------------
-- DDingUI_StyleLib :: ObjectPool
-- 위젯 재활용 풀 (inspired by AbstractFramework)
-- Scroll, Dropdown 등에서 동적 위젯 재사용
------------------------------------------------------
local MAJOR = "DDingUI-StyleLib-1.0"
local Lib = LibStub:GetLibrary(MAJOR)
if not Lib then return end

---------------------------------------------------------------------
-- ObjectPool
---------------------------------------------------------------------
local ObjectPool = {}
ObjectPool.__index = ObjectPool

--- 새 오브젝트 풀 생성
--- @param createFunc function  새 오브젝트 생성 함수 (pool 자체가 인자로 전달됨)
--- @param resetFunc function|nil  반환 시 초기화 함수 (obj가 인자로 전달됨)
--- @return table pool
function Lib.NewObjectPool(createFunc, resetFunc)
    assert(type(createFunc) == "function", "DDingUI_StyleLib.NewObjectPool: createFunc must be a function")
    local pool = setmetatable({}, ObjectPool)
    pool._create = createFunc
    pool._reset = resetFunc
    pool._inactive = {}     -- 대기 중인 오브젝트
    pool._active = {}       -- 사용 중인 오브젝트
    pool._totalCreated = 0
    return pool
end

--- 풀에서 오브젝트 획득 (없으면 새로 생성)
--- @return any obj
function ObjectPool:Acquire()
    local obj = tremove(self._inactive)
    if not obj then
        self._totalCreated = self._totalCreated + 1
        obj = self._create(self)
    end
    self._active[obj] = true
    return obj
end

--- 오브젝트를 풀로 반환
--- @param obj any
function ObjectPool:Release(obj)
    if not self._active[obj] then return end
    self._active[obj] = nil

    if self._reset then
        self._reset(obj)
    end

    tinsert(self._inactive, obj)
end

--- 모든 활성 오브젝트를 풀로 반환
function ObjectPool:ReleaseAll()
    for obj in next, self._active do
        self:Release(obj)
    end
end

--- 활성 오브젝트 수
function ObjectPool:GetActiveCount()
    local count = 0
    for _ in next, self._active do
        count = count + 1
    end
    return count
end

--- 비활성(대기) 오브젝트 수
function ObjectPool:GetInactiveCount()
    return #self._inactive
end

--- 총 생성된 오브젝트 수
function ObjectPool:GetTotalCreated()
    return self._totalCreated
end

--- 활성 오브젝트를 순회
function ObjectPool:EnumerateActive()
    return next, self._active
end

---------------------------------------------------------------------
-- Queue (PixelUpdate 전투 안전 큐 등에 사용)
---------------------------------------------------------------------
local Queue = {}
Queue.__index = Queue

function Lib.NewQueue()
    local q = setmetatable({}, Queue)
    q._data = {}
    q._first = 1
    q._last = 0
    return q
end

function Queue:Push(item)
    self._last = self._last + 1
    self._data[self._last] = item
end

function Queue:Pop()
    if self._first > self._last then return nil end
    local item = self._data[self._first]
    self._data[self._first] = nil
    self._first = self._first + 1
    -- shrink 방지: 임계치 초과 시 재인덱싱
    if self._first > 1000 and self:IsEmpty() then
        self._first = 1
        self._last = 0
    end
    return item
end

function Queue:Peek()
    if self._first > self._last then return nil end
    return self._data[self._first]
end

function Queue:IsEmpty()
    return self._first > self._last
end

function Queue:Length()
    return self._last - self._first + 1
end

function Queue:Clear()
    wipe(self._data)
    self._first = 1
    self._last = 0
end
