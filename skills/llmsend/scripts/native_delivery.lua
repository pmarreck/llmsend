-- Native thread delivery policy. The RPC port owns transport and deadlines.
local M={}
function M.new(rpc,target)
	local initialized=false
	local function verify()
		if not initialized then
			local reply=rpc.request('initialize',{clientInfo={name='llmsend',version='1'}})
			if not reply then return false,'native-initialize-failed' end
			rpc.notify('initialized',{})
			initialized=true
		end
		local cursor,found
		for _=1,16 do
			local reply=rpc.request('thread/loaded/list',{cursor=cursor,limit=100})
			if not reply or type(reply.data)~='table' then return false,'native-registry-unavailable' end
			for _,id in ipairs(reply.data) do if id==target.thread then found=true end end
			if found then break end
			cursor=type(reply.nextCursor)=='string' and reply.nextCursor or nil
			if not cursor then break end
		end
		if not found then return false,'native-thread-not-loaded' end
		local reply=rpc.request('thread/read',{threadId=target.thread,includeTurns=false})
		local thread=reply and reply.thread
		if not thread or thread.id~=target.thread or thread.cwd~=target.project then return false,'native-identity-mismatch' end
		if not thread.status or thread.status.type~='idle' then return false,'native-thread-not-idle' end
		return true
	end
	return {verify=verify,deliver=function(message,operation)
		local valid,reason=verify()
		if not valid then return {status='deferred',reason=reason} end
		local reply=rpc.request('turn/start',{threadId=target.thread,clientUserMessageId=operation,
			input={{type='text',text=message}}})
		if not reply or not reply.turn or type(reply.turn.id)~='string' then
			return {status='unconfirmed',reason='native-acceptance-unconfirmed'}
		end
		return {status='delivered',receipt=reply.turn.id}
	end}
end
return M
