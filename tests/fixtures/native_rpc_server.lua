local json=require('cjson.safe')
local project,log=arg[1],arg[2]
for line in io.lines() do
	local request=assert(json.decode(line))
	local result
	if request.method=='initialize' then result={}
	elseif request.method=='thread/loaded/list' then result={data={'00000000-0000-0000-0000-000000000001'}}
	elseif request.method=='thread/read' then
		result={thread={id='00000000-0000-0000-0000-000000000001',cwd=project,status={type='idle'}}}
	elseif request.method=='turn/start' then
		local f=assert(io.open(log,'a')); f:write(assert(json.encode(request.params))..'\n'); assert(f:close())
		result={turn={id='fixture-turn'}}
	elseif request.method~='initialized' then error('unexpected native method') end
	if request.id then print(assert(json.encode({id=request.id,result=result}))); io.flush() end
end
