local directory=arg[0]:match('^(.*)/') or '.'
package.path=directory..'/?.lua;'..package.path
local json=require('cjson.safe')
local core=require('inbox_reminder')
local store=require('reminder_store')
local rpc=require('unix_rpc')
local native=require('native_delivery')
local function emit(value) print(assert(json.encode(value))) end
local function quote(s) return "'"..s:gsub("'","'\\''").."'" end
local function key(value)
	local p=assert(io.popen('printf %s '..quote(value)..' | sha256sum','r'))
	local result=p:read('*a'); p:close()
	return assert(result:match('^(%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x+)'),'identity hash failed')
end
local function main()
	local config_path,dry
	local i=1
	while i<=#arg do
		if arg[i]=='--help' or arg[i]=='-h' then
			print('Usage: inbox-remind --config PRIVATE_JSON [--dry-run]\nOne bounded scan of explicitly configured inboxes; JSON status and next due. Default interval: 3600 seconds. Exit 3: deferred/unconfirmed; exit 1: configuration or I/O failure.')
			return 0
		elseif arg[i]=='--about' then print('LLMsend inbox reminders 1; LuaJIT '..require('ffi').os..' '..require('ffi').arch); return 0
		elseif arg[i]=='--config' then config_path=arg[i+1]; assert(config_path,'missing config'); i=i+2
		elseif arg[i]=='--dry-run' then dry=true; i=i+1
		else error('unknown argument') end
	end
	assert(config_path,'--config is required')
	local config=assert(json.decode(store.read(config_path,true)),'invalid config JSON')
	assert(config.version==1 and type(config.projects)=='table' and #config.projects<=64,'invalid config schema')
	local interval=config.interval_seconds or 3600
	assert(type(interval)=='number' and interval>=1 and interval<=604800 and interval==math.floor(interval),'invalid interval')
	assert(type(config.state_dir)=='string' and config.state_dir:sub(1,1)=='/','absolute state_dir required')
	local targets,seen={},{}
	for _,entry in ipairs(config.projects) do
		local project=store.canonical(entry.project)
		assert(not seen[project],'duplicate canonical project'); seen[project]=true
		assert(type(entry.thread)=='string' and entry.thread:match('^[%x-]+$') and #entry.thread==36,'native UUID required')
		assert(type(entry.socket)=='string' and entry.socket:sub(1,1)=='/' and not entry.socket:find('[%z\1-\31\127]'),'absolute socket path required')
		targets[#targets+1]={project=project,thread=entry.thread,socket=entry.socket,key=key(project..'\n'..entry.thread)}
	end
	local storage=store.open(config.state_dir,dry)
	local results,exit_code={},0
	local deadline=rpc.monotonic()+50
	for _,target in ipairs(targets) do
		local connection,adapter,connection_reason,release
		local function verify()
			if rpc.monotonic()>=deadline then return false,'scan-budget-exhausted' end
			if not adapter then
				local ok,path=pcall(store.canonical,target.socket)
				if not ok then return false,'native-socket-unavailable' end
				connection,connection_reason=rpc.connect(path,math.min(5,deadline-rpc.monotonic()))
				if not connection then return false,connection_reason end
				adapter=native.new(connection,target)
			end
			return adapter.verify()
		end
		local success,result=pcall(function()
			if not dry then
				release=storage.lock(target.key)
				if not release then return {status='deferred',reason='another-run-holds-lock'} end
			end
			local r=core.run({
				clock=store.clock,
				load=function() return storage.load(target.key) end,
				save=function(state) storage.save(target.key,state) end,
				scan=function() return store.scan(target.project) end,
				verify=verify,
				deliver=function(message,operation)
					return adapter.deliver('[llmsend-reminder:'..operation..'] Inbox: '..target.project..'/inbox\n'..message,operation)
				end,
			},{interval=interval,retry=60,max_attempts=3,identity=target.key,dry_run=dry})
			if dry and r.pending and r.pending>0 then
				local valid,why=verify()
				r.recipient_status=valid and 'verified' or 'deferred'; r.recipient_reason=why
			end
			return r
		end)
		if connection then connection.close() end
		if release then release() end
		if not success then result={status='error',reason='project-scan-failed'}; exit_code=1 end
		if exit_code~=1 and (result.status=='deferred' or result.status=='unconfirmed' or result.status=='failed' or result.recipient_status=='deferred') then exit_code=3 end
		result.project=target.project; results[#results+1]=result
	end
	emit({projects=results,dry_run=dry or false})
	return exit_code
end
local ok,code=pcall(main)
if not ok then emit({status='error',reason='invalid-config-or-unavailable-state'}); os.exit(1) end
os.exit(code)
