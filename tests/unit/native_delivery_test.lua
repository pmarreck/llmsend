local root=arg[1]
package.path=root..'/skills/llmsend/scripts/?.lua;'..package.path
local native=require('native_delivery')
local n=0
local function eq(a,b,label) assert(a==b,label..': '..tostring(b)); n=n+1 end
local function fixture()
	local f={calls={},status='idle',cwd='/projects/example',loaded=true,thread='native-id'}
	f.rpc={request=function(method,params)
		f.calls[#f.calls+1]={method=method,params=params}
		if method=='initialize' then return {} end
		if method=='thread/loaded/list' then return {data=f.loaded and {'native-id'} or {}} end
		if method=='thread/read' then return {thread={id=f.thread,cwd=f.cwd,status={type=f.status}}} end
		if method=='turn/start' then
			if f.fail then return nil,'timeout' end
			return {turn={id='turn-receipt'}}
		end
		error('unexpected method')
	end,notify=function(method) f.calls[#f.calls+1]={method=method} end}
	f.adapter=native.new(f.rpc,{thread='native-id',project='/projects/example'})
	return f
end
local f=fixture()
eq(true,f.adapter.verify(),'verified loaded idle identity')
eq('initialize',f.calls[1].method,'handshake first')
eq('initialized',f.calls[2].method,'initialized notification')
f.status='active'
local result=f.adapter.deliver('reminder','stable-id')
eq('deferred',result.status,'busy at last check deferred')
for _,c in ipairs(f.calls) do eq(false,c.method=='turn/start','no send while busy') end
for _,change in ipairs({{status='notLoaded'},{status='systemError'},{cwd='/wrong'},{thread='wrong'},{loaded=false}}) do
	f=fixture(); for k,v in pairs(change) do f[k]=v end
	eq(false,f.adapter.verify(),'ineligible state')
end
f=fixture(); result=f.adapter.deliver('reminder','stable-id')
eq('delivered',result.status,'native acceptance')
eq('turn-receipt',result.receipt,'turn receipt retained')
local call=f.calls[#f.calls]
eq('turn/start',call.method,'only native turn used')
eq('native-id',call.params.threadId,'pinned native id')
eq('reminder',call.params.input[1].text,'original reminder')
eq(nil,call.params.input[1].text_elements,'omit optional empty array rather than encoding an object')
eq('stable-id',call.params.clientUserMessageId,'operation identity passed to native API')
eq(nil,call.params.cwd,'no sticky cwd override')
eq(nil,call.params.approvalPolicy,'no approval override')
f=fixture(); f.fail=true
result=f.adapter.deliver('reminder','stable-id')
eq('unconfirmed',result.status,'timeout never claims delivery')
print('native-delivery: '..n..' assertions passed')
