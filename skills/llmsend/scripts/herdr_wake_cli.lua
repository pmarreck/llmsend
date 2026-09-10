local directory=arg[0]:match('^(.*)/') or '.'
package.path=directory..'/?.lua;'..package.path
local wake=require('herdr_wake')
local json=require('cjson.safe')
local lfs=require('lfs')
local ffi=require('ffi')
ffi.cdef[[
typedef struct { long tv_sec; long tv_nsec; } wake_timespec;
int clock_gettime(int, wake_timespec *);
int nanosleep(const wake_timespec *, wake_timespec *);
void *fopen(const char *, const char *);
int fileno(void *); int flock(int, int); int fclose(void *);
int chmod(const char *, unsigned int);
unsigned int geteuid(void); int setenv(const char *,const char *,int);
]]
local function emit(result,code) print(assert(json.encode(result))); os.exit(code) end
local function fail(message,code) emit({status='error',reason=message},code or 1) end
local function quote(s) return "'"..s:gsub("'","'\\''").."'" end
local function command(args)
	local escaped={}
	for _,a in ipairs(args) do escaped[#escaped+1]=quote(tostring(a)) end
	local p=io.popen(table.concat(escaped,' ')..' 2>&1; printf "\\nLLMSEND_RC=%s\\n" "$?"','r')
	if not p then return nil end
	local output=p:read('*a'); p:close()
	local body,code=output:match('^(.*)\nLLMSEND_RC=(%d+)\n$')
	return body,tonumber(code)
end
local herdr=os.getenv('LLMSEND_HERDR') or 'herdr'
local function api(...)
	local args={'timeout','8s',herdr,...}
	return command(args)
end
local function object(...)
	local out,code=api(...)
	if code~=0 then return nil end
	return json.decode(out)
end
local function now()
	local t=ffi.new('wake_timespec[1]')
	assert(ffi.C.clock_gettime(ffi.os=='OSX' and 6 or 1,t)==0,'monotonic clock unavailable')
	return tonumber(t[0].tv_sec)+tonumber(t[0].tv_nsec)/1e9
end
local function wait(seconds)
	local t=ffi.new('wake_timespec[1]')
	t[0].tv_sec=math.floor(seconds); t[0].tv_nsec=(seconds-math.floor(seconds))*1e9
	ffi.C.nanosleep(t,nil)
end
local target=arg[1]
if arg[2]~='--wake' or not arg[3] then fail('Usage: notify-session TARGET --wake NOTE [--timeout SECONDS] [--dry-run]',2) end
local note,timeout,dry=arg[3],60,false
local service_socket,expected_session
local i=4
while i<=#arg do
	if arg[i]=='--timeout' then timeout=tonumber(arg[i+1]); i=i+2
	elseif arg[i]=='--dry-run' then dry=true; i=i+1
	elseif arg[i]=='--service-socket' then service_socket=arg[i+1]; if not service_socket then fail('missing service socket',2) end; i=i+2
	elseif arg[i]=='--expect-session' then expected_session=arg[i+1]; if not expected_session then fail('missing native session',2) end; i=i+2
	else fail('unknown wake option: '..arg[i],2) end
end
if not timeout or timeout<0.25 or timeout>300 then fail('timeout must be between 0.25 and 300 seconds',2) end
if not target or target:match('^%-') or target:find('[%z\1-\31\127]') or note:find('[%z\1-\31\127]') then fail('invalid target or path',2) end
if service_socket then
	-- Explicit operator opt-in for daemons, never a fabricated pane context.
	if service_socket:sub(1,1)~='/' or service_socket:find('[%z\1-\31\127]') or not expected_session or expected_session=='' then
		fail('service mode requires an absolute private socket and expected native session')
	end
	local socket=lfs.symlinkattributes(service_socket)
	if not socket or socket.mode~='socket' or socket.uid~=tonumber(ffi.C.geteuid())
		or socket.permissions:sub(5,5)=='w' or socket.permissions:sub(8,8)=='w' then
		fail('service socket must be a real operator-owned Unix socket without group/other write access')
	end
	assert(ffi.C.setenv('HERDR_SOCKET_PATH',service_socket,1)==0)
elseif os.getenv('HERDR_ENV')~='1' then fail('Run inside the intended Herdr session') end
local a=lfs.symlinkattributes(note)
if not a or a.mode~='file' or a.size>1024*1024 then fail('wake requires an existing regular inbox note (at most 1 MiB)',2) end
local resolved,rc=command({'realpath','-e','--',note})
if rc~=0 then fail('cannot resolve note',2) end
note=resolved:gsub('\n$','')
local info=object('agent','get',target)
local agent=info and info.result and info.result.agent
if not agent or not agent.pane_id or not agent.agent_session or not agent.agent_session.value then fail('live native agent identity required') end
if expected_session and agent.agent_session.value~=expected_session then emit({status='deferred',reason='native-session-changed'},3) end
local pane=agent.pane_id
local cwd,cwd_rc=command({'realpath','-e','--',agent.cwd})
if cwd_rc~=0 then fail('cannot resolve agent cwd') end
cwd=cwd:gsub('\n$','')
if note:match('^(.*)/[^/]+$')~=cwd..'/inbox' or not note:match('%.md$') then fail('note must be a direct Markdown file in the target project inbox',2) end
local function snapshot()
	local first=object('agent','get',pane)
	local p=object('pane','get',pane)
	local layout=object('pane','layout','--pane',pane)
	local x=first and first.result and first.result.agent
	local rect
	for _,entry in ipairs(layout and layout.result and layout.result.layout and layout.result.layout.panes or {}) do
		if entry.pane_id==pane then rect=entry.rect end
	end
	if not x or not x.agent_session or not rect or not p or not p.result or not p.result.pane then return nil end
	if x.agent_session.value~=agent.agent_session.value or x.terminal_id~=agent.terminal_id or x.cwd~=agent.cwd then return nil end
	if rect.height<4 or rect.height>1000 or rect.width<20 then return nil end
	local screen,status=api('agent','read',pane,'--source','visible','--format','ansi','--lines',tostring(rect.height))
	local last=object('agent','get',pane)
	local y=last and last.result and last.result.agent
	if status~=0 or not y or not y.agent_session or x.agent_session.value~=y.agent_session.value or x.agent_status~=y.agent_status or x.terminal_id~=y.terminal_id then return nil end
	local after=object('pane','layout','--pane',pane)
	local after_rect
	for _,entry in ipairs(after and after.result and after.result.layout and after.result.layout.panes or {}) do
		if entry.pane_id==pane then after_rect=entry.rect end
	end
	local after_pane=object('pane','get',pane)
	local after_scroll=after_pane and after_pane.result and after_pane.result.pane and after_pane.result.pane.scroll
	if not after_rect or after_rect.width~=rect.width or after_rect.height~=rect.height
		or not after_scroll or not p.result.pane.scroll
		or after_scroll.offset_from_bottom~=p.result.pane.scroll.offset_from_bottom then return nil end
	return {agent=x.agent,identity=table.concat({pane,x.terminal_id or '',x.agent_session.value,x.cwd or ''},'|'),
		geometry=rect.width..'x'..rect.height, status=x.agent_status,screen=screen,
		scroll=p.result.pane.scroll and p.result.pane.scroll.offset_from_bottom}
end
if dry then
	local s=snapshot()
	if not s then emit({status='deferred',reason='snapshot-unavailable'},3) end
	emit({status='dry-run',composer=wake.composer(s.agent,s.screen).kind,agent_status=s.status,
		pane=pane,geometry=s.geometry,scroll=s.scroll,note=note},0)
end

local state_root=(os.getenv('XDG_STATE_HOME') or (assert(os.getenv('HOME'))..'/.local/state'))..'/llmsend-wake'
local _,mk=command({'mkdir','-p','--',state_root})
if mk~=0 or lfs.symlinkattributes(state_root,'mode')~='directory' then fail('unsafe or unavailable state directory') end
assert(ffi.C.chmod(state_root,448)==0,'cannot make state private')
local function hash(value)
	local out,status=command({'sha256sum','--',value})
	if status~=0 then fail('could not hash durable note') end
	return assert(out:match('^(%x+)'))
end
local function text_hash(value)
	local p=io.popen('printf %s '..quote(value)..' | sha256sum','r')
	local output=p:read('*a'); p:close(); return assert(output:match('^(%x+)'))
end
local note_hash=hash(note)
local endpoint=os.getenv('HERDR_SOCKET_PATH') or os.getenv('HERDR_SESSION_ID') or 'default'
local session_key=table.concat({endpoint,pane,agent.terminal_id or '',agent.agent_session.value},'\0')
-- Shell argv cannot carry NUL; encode keys before passing to the hash tool.
session_key=text_hash(assert(json.encode(session_key)))
local key=text_hash(assert(json.encode({session_key,note,note_hash})))
local pointer='[llmsend:'..key:sub(1,16)..'] Read the inbox note at '..note..'.'
local lock_path=state_root..'/'..session_key..'.lock'
if lfs.symlinkattributes(lock_path,'mode')=='link' then fail('refusing symlink lock') end
local lock=ffi.C.fopen(lock_path,'a')
if lock==nil then fail('cannot open wake lock') end
if ffi.C.flock(ffi.C.fileno(lock),6)~=0 then ffi.C.fclose(lock); emit({status='deferred',reason='another wake owns this pane'},3) end
local record_path=state_root..'/'..key..'.json'
local attempted=false
local function record(status)
	local f=assert(io.open(record_path..'.tmp','w'))
	f:write(assert(json.encode({status=status,note=note,pane=pane,session=agent.agent_session.value,
		id=key:sub(1,16),datetime=os.date('!%Y-%m-%dT%H:%M:%SZ')}))..'\n'); assert(f:close())
	assert(os.rename(record_path..'.tmp',record_path))
end
local ok,result=pcall(function()
	api('notification','show','Inbox: '..target,'--body','Pending inbox note: '..note,'--sound','none')
	return wake.run({now=now,wait=wait,snapshot=snapshot,
		exists=function() return lfs.symlinkattributes(note,'mode')=='file' end,
		claim=function()
			if lfs.symlinkattributes(record_path) then return false end
			if hash(note)~=note_hash then error('note changed during observation') end
			record('attempted'); attempted=true; return true
		end,
		record=record,
		submit=function(text)
			local output,code=api('agent','prompt',pane,text)
			local reply=output and json.decode(output)
			if code==1 and reply and reply.error and reply.error.code=='agent_prompt_stalled' then return 'stalled' end
			return code==0 and 'accepted' or 'unknown'
		end,
		enter=function() local _,code=api('agent','send-keys',pane,'enter'); return code==0 end,
	}, {pointer=pointer,timeout=timeout,poll=0.25,retry_after=5})
end)
ffi.C.fclose(lock)
if not ok then emit({status=attempted and 'unconfirmed' or 'error',reason=tostring(result)},1) end
result.note=note; result.pane=pane; result.id=key:sub(1,16); result.record=record_path
emit(result,result.status=='deferred' and 3 or result.status=='unconfirmed' and 4 or 0)
