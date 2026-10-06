-- [12.1] Bounded, data-only SimC subset. Imported text is never executed as Lua.
local _, A = ...
local E = {}
A.Engine = E
local U = {}
E.Unknown = U
local prec = {["|"]=1,["^"]=2,["&"]=3,["="]=4,["=="]=4,["!="]=4,["<"]=4,[">"]=4,["<="]=4,[">="]=4,
    ["<?"]=5,[">?"]=5,["+"]=6,["-"]=6,["*"]=7,["%"]=7,["%%"]=7}
local function truth(v) return v ~= 0 and v ~= false end
local function numeric(v) if v == true then return 1 elseif v == false then return 0 else return v end end
local function finite(v) return (v ~= v or v == math.huge or v == -math.huge) and U or v end
local function trim(s) return s:match("^%s*(.-)%s*$") end

function E.Expression(source)
    if #source > 8192 then return nil, "expression exceeds 8192 bytes" end
    local tokens, pos, nodes, refs = {}, 1, 0, {}
    while pos <= #source do
        local rest, token = source:sub(pos)
        if rest:match("^%s") then pos = pos + 1
        else
            token = rest:match("^%d+%.?%d*[eE][%+%-]?%d+") or rest:match("^%d+%.?%d*")
                or rest:match("^%.%d+") or rest:match("^[%a_][%w_%.]*")
            if not token then
                local pair = rest:sub(1,2)
                token = (prec[pair] and pair) or rest:sub(1,1)
                if not prec[token] and token ~= "!" and token ~= "@" and token ~= "(" and token ~= ")" then
                    return nil, "unsupported character at "..pos..": "..token
                end
            end
            tokens[#tokens+1] = token
            pos = pos + #token
        end
    end
    local i, parse = 1
    local function node(op, l, r)
        nodes = nodes + 1
        if nodes > 1024 then error("expression node limit", 0) end
        return {op=op,l=l,r=r}
    end
    parse = function(minimum, depth)
        if depth > 64 then error("expression nesting limit", 0) end
        local t, left = tokens[i]
        i = i + 1
        if not t then error("expected expression", 0) end
        if t == "!" or t == "-" or t == "+" or t == "@" then left = node("u"..t, parse(8,depth+1))
        elseif (t == "floor" or t == "ceil") and tokens[i] == "(" then
            i = i + 1
            left = node(t,parse(1,depth+1))
            if tokens[i] ~= ")" then error("missing closing parenthesis",0) end
            i = i + 1
        elseif t == "(" then
            left = parse(1,depth+1)
            if tokens[i] ~= ")" then error("missing closing parenthesis",0) end
            i = i + 1
        elseif tonumber(t) then
            if math.abs(tonumber(t)) == math.huge then error("non-finite number",0) end
            left = node("number",tonumber(t))
        elseif t:match("^[%a_][%w_%.]*$") then refs[t]=true; left=node("ref",t)
        else error("unexpected token: "..t,0) end
        while tokens[i] and prec[tokens[i]] and prec[tokens[i]] >= minimum do
            local op = tokens[i]
            i = i + 1
            left = node(op,left,parse(prec[op]+1,depth+1))
        end
        return left
    end
    local ok, result = pcall(parse,1,0)
    if not ok then return nil,result end
    if tokens[i] then return nil,"unexpected token: "..tokens[i] end
    return result,nil,refs
end

local function evaluate(n, state, budget)
    budget.n = budget.n + 1
    if budget.n > 20000 then error("evaluation budget exceeded",0) end
    local op = n.op
    if op == "number" then return n.l end
    if op == "ref" then
        if n.l == "true" then return 1 elseif n.l == "false" then return 0 end
        local v = state[n.l]
        if v == nil or v == U then budget.missing=budget.missing or n.l; return U end
        return numeric(v)
    end
    local l = evaluate(n.l,state,budget)
    if op == "u!" then return l == U and U or (truth(l) and 0 or 1) end
    if op == "u-" then return l == U and U or -l end
    if op == "u+" then return l end
    if op == "u@" then return l == U and U or math.abs(l) end
    if op == "floor" then return l == U and U or math.floor(l) end
    if op == "ceil" then return l == U and U or math.ceil(l) end
    if op == "&" and l ~= U and not truth(l) then return 0 end
    if op == "|" and l ~= U and truth(l) then return 1 end
    local r = evaluate(n.r,state,budget)
    if op == "&" and r ~= U and not truth(r) then return 0 end
    if op == "|" and r ~= U and truth(r) then return 1 end
    if l == U or r == U then return U end
    if op == "&" then return truth(l) and truth(r) and 1 or 0
    elseif op == "|" then return (truth(l) or truth(r)) and 1 or 0
    elseif op == "^" then return truth(l) ~= truth(r) and 1 or 0
    elseif op == "=" or op == "==" then return l == r and 1 or 0
    elseif op == "!=" then return l ~= r and 1 or 0
    elseif op == "<" then return l < r and 1 or 0
    elseif op == ">" then return l > r and 1 or 0
    elseif op == "<=" then return l <= r and 1 or 0
    elseif op == ">=" then return l >= r and 1 or 0
    elseif op == "+" then return finite(l + r)
    elseif op == "-" then return finite(l - r)
    elseif op == "*" then return finite(l * r)
    elseif op == "%" then return r == 0 and U or finite(l / r)
    elseif op == "%%" then return r == 0 and U or math.fmod(l,r)
    elseif op == "<?" then return math.max(l,r)
    elseif op == ">?" then return math.min(l,r) end
    return U
end
function E.Value(ast, values)
    local budget = {n=0}
    local ok,v = pcall(evaluate,ast,values,budget)
    return ok and v or U, ok and budget.missing or v
end

local controls = {call_action_list=true,run_action_list=true,variable=true}
local unsupported = {use_item=true,use_items=true,potion=true,flask=true,food=true,
    augmentation=true,snapshot_stats=true,auto_attack=true,auto_shot=true,
    invoke_external_buff=true,cancel_buff=true,wait=true,pool_resource=true,
    restart_sequence=true,sequence=true,strict_sequence=true,wait_until_ready=true,cycling_variable=true}
local varops = {set=true,add=true,sub=true,mul=true,div=true,min=true,max=true,setif=true,
    reset=true,floor=true,ceil=true}
function E.Compile(raw)
    local pack = {lists={},refs={},actions={},issues={},warnings={},defaults={},count=0}
    local function issue(line,message)
        if #pack.issues < 100 then pack.issues[#pack.issues+1]={line=line,message=message} end
    end
    local function unsupportedRule(rule,message,list)
        rule.unsupported=rule.unsupported or message
        if #pack.warnings < 100 then
            pack.warnings[#pack.warnings+1]={line=rule.line,list=list,message=message}
        end
    end
    if type(raw) ~= "string" or #raw > 262144 then issue(0,"APL must be text up to 256 KiB"); return pack end
    local lineNo,listCount = 0,0
    for original in (raw.."\n"):gmatch("(.-)\n") do
        lineNo = lineNo + 1
        local line = trim(original:gsub("#.*$",""):gsub("\r",""))
        if line:match("^actions") then
            local header,body = line:match("^(.-)=(.*)$")
            local append = header and header:sub(-1) == "+"
            if append then header=header:sub(1,-2) end
            local name = header == "actions" and "default" or header and header:match("^actions%.([%w_]+)$")
            if not name or not body then issue(lineNo,"invalid actions line")
            else
                if not pack.lists[name] then listCount=listCount+1 end
                if listCount > 64 then issue(lineNo,"action list limit"); break end
                if not append or not pack.lists[name] then pack.lists[name]={} end
                local action,tail = body:match("^/?([%w_]+)(.*)$")
                if not action or (tail ~= "" and tail:sub(1,1) ~= ",") then issue(lineNo,"invalid action")
                else
                    local rule,options = {action=action,line=lineNo,list=name},{}
                    for part in tail:gmatch(",([^,]*)") do
                        local k,v = part:match("^%s*([%w_]+)%s*=(.-)%s*$")
                        if trim(part) == "" then -- SimC accepts empty separators in generated APLs.
                        elseif not k or v == "" then issue(lineNo,"invalid option: "..part)
                        elseif options[k] then issue(lineNo,"duplicate option: "..k)
                        else options[k]=v end
                    end
                    for k,v in pairs(options) do
                        if k == "target" or k == "target_if" or k == "cycle_targets" or k == "max_cycle_targets" then rule.targeting=true end
                        local valid = k == "if" or (controls[action] and k == "name")
                            or (action == "variable" and (k == "value" or k == "value_else" or k == "op" or k == "condition" or k == "default"))
                        if not valid then unsupportedRule(rule,"unsupported option: "..k,name)
                        elseif k == "default" then
                            local number=tonumber(v)
                            if not number or finite(number) == U then issue(lineNo,"variable default must be a finite number")
                            else rule.default=number end
                        elseif k == "if" or k == "value" or k == "value_else" or k == "condition" then
                            local ast,err,refs = E.Expression(v)
                            if not ast then issue(lineNo,k..": "..err)
                            else rule[k]=ast; for ref in pairs(refs) do pack.refs[ref]=true end end
                        else rule[k]=v end
                    end
                    if unsupported[action] then unsupportedRule(rule,"unsupported action: "..action,name) end
                    if controls[action] and (not rule.name or not rule.name:match("^[%w_]+$")) then issue(lineNo,"missing/invalid name") end
                    if action == "variable" then
                        rule.op=rule.op or "set"
                        if not varops[rule.op] then unsupportedRule(rule,"unsupported variable operation: "..rule.op,name) end
                        if varops[rule.op] and rule.op ~= "reset" and rule.op ~= "floor" and rule.op ~= "ceil" and not rule.value then issue(lineNo,"variable needs value") end
                        if rule.op == "setif" and (not rule.value_else or not rule.condition) then issue(lineNo,"setif needs condition and value_else") end
                        if rule.name and rule.default ~= nil then pack.defaults[rule.name]=rule.default end
                    elseif not controls[action] then pack.actions[action]=not unsupported[action] end
                    pack.count=pack.count+1
                    if pack.count > 4096 then issue(lineNo,"action limit"); break end
                    rule.options=options -- Preserve unsupported modifiers; never silently drop their semantics.
                    table.insert(pack.lists[name],rule)
                end
            end
        elseif line:match("^apl_variable%.") then issue(lineNo,"apl_variable overrides are unsupported")
        elseif line ~= "" and not line:match("^[%w_%.]+%+?=") then issue(lineNo,"unrecognized line") end
    end
    if not pack.lists.default or #pack.lists.default == 0 then issue(0,"missing default actions") end
    for _,list in pairs(pack.lists) do
        for _,rule in ipairs(list) do
            if (rule.action == "call_action_list" or rule.action == "run_action_list") and not pack.lists[rule.name] then
                issue(rule.line,"missing action list: "..(rule.name or "?"))
            end
        end
    end
    pack.valid = #pack.issues == 0
    pack.complete = pack.valid and #pack.warnings == 0
    return pack
end

function E.Select(pack, snapshot)
    if not pack.valid then
        local issue=pack.issues[1]
        return {kind="blocked",reason="line "..issue.line..": "..issue.message}
    end
    local values={}
    for k,v in pairs(snapshot.values or {}) do values[k]=v end
    local budget,visiting,walk={n=0},{}
    walk=function(name,depth)
        if depth > 32 or visiting[name] then return {kind="blocked",reason="cyclic action list: "..name} end
        visiting[name]=true
        local function done(result) visiting[name]=nil; return result end
        for _,rule in ipairs(pack.lists[name] or {}) do
            budget.missing=nil
            -- An if/range result for our current target cannot reject a rule that
            -- selects a different target. Only target-independent unavailability can.
            if rule.targeting and not (snapshot.disabled and snapshot.disabled[rule.action]) then
                return done({kind="blocked",reason=rule.unsupported,line=rule.line,list=name,action=rule.action})
            end
            local condition=rule["if"] and evaluate(rule["if"],values,budget) or 1
            if rule.action == "variable" then
                local key="variable."..rule.name
                if condition == U then values[key]=U
                elseif truth(condition) then
                    local old=values[key]
                    local value
                    if rule.unsupported then value=U
                    elseif rule.op == "reset" then value=pack.defaults[rule.name] or 0
                    elseif rule.op == "floor" or rule.op == "ceil" then
                        value=(old == nil or old == U) and U or math[rule.op](old)
                    else
                        local selector=rule.op == "setif" and evaluate(rule.condition,values,budget) or 1
                        value=selector == U and U or evaluate(truth(selector) and rule.value or rule.value_else,values,budget)
                    end
                    if not rule.unsupported and rule.op ~= "set" and rule.op ~= "setif" and rule.op ~= "reset" and rule.op ~= "floor" and rule.op ~= "ceil" then
                        if old == nil or old == U or value == U then value=U
                        elseif rule.op == "add" then value=old+value
                        elseif rule.op == "sub" then value=old-value
                        elseif rule.op == "mul" then value=old*value
                        elseif rule.op == "div" then value=value == 0 and 0 or old/value
                        elseif rule.op == "min" then value=math.min(old,value)
                        elseif rule.op == "max" then value=math.max(old,value) end
                    end
                    values[key]=value == U and U or finite(value)
                end
            elseif condition == U then
                if not (snapshot.ready and snapshot.ready[rule.action] == false) then
                    return done({kind="unknown",reason=budget.missing or "condition unknown",line=rule.line,list=name,action=rule.action})
                end
            elseif truth(condition) then
                local ready=snapshot.ready and snapshot.ready[rule.action]
                if ready == false and not controls[rule.action] then
                    -- A definitely unavailable action cannot win, including one with an opaque modifier.
                elseif rule.unsupported then
                    return done({kind="blocked",reason=rule.unsupported,line=rule.line,list=name,action=rule.action})
                elseif rule.action == "call_action_list" or rule.action == "run_action_list" then
                    local result=walk(rule.name,depth+1)
                    if result.kind ~= "none" or rule.action == "run_action_list" then return done(result) end
                else
                    if ready == nil or ready == U then
                        return done({kind="unknown",reason=snapshot.reasons and snapshot.reasons[rule.action] or "castability: "..rule.action,line=rule.line,list=name,action=rule.action})
                    elseif ready then return done({kind="action",action=rule.action,line=rule.line,list=name}) end
                end
            end
        end
        return done({kind="none",reason="no matching action"})
    end
    -- ponytail: precombat/persistent variables require a verified spec model.
    -- Do not replay initialization or invent a live value in this alpha.
    local ok,result=pcall(walk,"default",0)
    return ok and result or {kind="blocked",reason=result}
end

E.DemoAPL="actions=/spender,if=holy_power>=3\nactions+=/generator\n"
function E.Demo(power)
    local result,state={},{values={holy_power=power or 0},ready={generator=true,spender=true}}
    local pack=E.Compile(E.DemoAPL)
    for i=1,3 do
        local step=E.Select(pack,state)
        result[i]=step
        if step.action == "spender" then state.values.holy_power=state.values.holy_power-3
        else state.values.holy_power=math.min(5,state.values.holy_power+1) end
    end
    return result
end
