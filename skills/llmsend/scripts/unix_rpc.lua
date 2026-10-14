-- Bounded newline JSON-RPC client for an existing operator-owned Unix socket.
local ffi=require('ffi')
local lfs=require('lfs')
local json=require('cjson.safe')
local bit=require('bit')
ffi.cdef[[
int socket(int,int,int); int connect(int,const void *,unsigned int);
long send(int,const void *,unsigned long,int); long recv(int,void *,unsigned long,int);
int close(int); int fcntl(int,int,...); int getsockopt(int,int,int,void *,unsigned int *);
int socketpair(int,int,int,int *); int fork(void); int dup2(int,int);
int execlp(const char *,const char *,...); void _exit(int);
int kill(int,int); int waitpid(int,int *,int); int open(const char *,int,...);
int chmod(const char *,unsigned int); unsigned int geteuid(void);
typedef struct { int fd; short events; short revents; } llmsend_pollfd;
int poll(llmsend_pollfd *,unsigned long,int);
typedef struct { long sec; long nsec; } llmsend_timespec;
int clock_gettime(int,llmsend_timespec *);
]]
if ffi.os=='OSX' then
	ffi.cdef[[typedef struct { unsigned char len; unsigned char family; char path[104]; } llmsend_sockaddr_un;]]
else
	ffi.cdef[[typedef struct { unsigned short family; char path[108]; } llmsend_sockaddr_un;]]
end
local M={}
function M.monotonic()
	local ts=ffi.new('llmsend_timespec[1]')
	assert(ffi.C.clock_gettime(ffi.os=='OSX' and 6 or 1,ts)==0,'monotonic clock unavailable')
	return tonumber(ts[0].sec)+tonumber(ts[0].nsec)/1e9
end
function M.from_fd(fd,timeout,cleanup)
	local function close()
		if fd>=0 then ffi.C.close(fd); fd=-1; if cleanup then cleanup() end end
	end
	local deadline=M.monotonic()+(timeout or 10)
	local function ready(events)
		local remaining=deadline-M.monotonic()
		if remaining<=0 or fd<0 then return false end
		local p=ffi.new('llmsend_pollfd[1]'); p[0].fd=fd; p[0].events=events
		return ffi.C.poll(p,1,math.ceil(remaining*1000))>0 and bit.band(p[0].revents,events)~=0
	end
	local flags=ffi.C.fcntl(fd,3)
	if flags<0 or ffi.C.fcntl(fd,4,ffi.cast('int',bit.bor(flags,ffi.os=='OSX' and 4 or 2048)))~=0 then
		close(); return nil,'socket-flags-failed'
	end
	local buffer,sequence='',0
	local chunk=ffi.new('char[8192]')
	local function send(value)
		local data=assert(json.encode(value))..'\n'
		local offset=0
		while offset<#data do
			if not ready(4) then return false end
			local sent=ffi.C.send(fd,data:sub(offset+1),#data-offset,ffi.os=='OSX' and 0x80000 or 0x4000)
			if sent<=0 then return false end
			offset=offset+tonumber(sent)
		end
		return true
	end
	return {
		close=close,
		notify=function(method,params) return send({method=method,params=params}) end,
		request=function(method,params)
			sequence=sequence+1
			if not send({id=sequence,method=method,params=params}) then return nil,'send-failed' end
			local received=0
			while received<2*1024*1024 do
				local line,rest=buffer:match('^([^\n]*)\n(.*)$')
				if line then
					buffer=rest
					local reply=json.decode(line)
					if not reply then return nil,'invalid-json' end
					if reply.id==sequence then
						if reply.error then return nil,'rpc-error' end
						return reply.result
					end
				else
					if not ready(1) then return nil,'read-timeout' end
					local got=ffi.C.recv(fd,chunk,8192,0)
					if got<=0 then return nil,'socket-closed' end
					received=received+tonumber(got); buffer=buffer..ffi.string(chunk,got)
				end
			end
			return nil,'response-too-large'
		end,
	}
end
function M.connect(path,timeout)
	local stat=lfs.symlinkattributes(path)
	if not stat or stat.mode~='socket' or stat.uid~=tonumber(ffi.C.geteuid())
		or stat.permissions:sub(5,5)=='w' or stat.permissions:sub(8,8)=='w' then
		return nil,'socket-must-be-private-and-owned'
	end
	local pair=ffi.new('int[2]')
	if ffi.C.socketpair(1,1,0,pair)~=0 then return nil,'socketpair-failed' end
	local pid=ffi.C.fork()
	if pid<0 then ffi.C.close(pair[0]); ffi.C.close(pair[1]); return nil,'transport-fork-failed' end
	if pid==0 then
		ffi.C.close(pair[0]); ffi.C.dup2(pair[1],0); ffi.C.dup2(pair[1],1); ffi.C.close(pair[1])
		local null=ffi.C.open('/dev/null',1); ffi.C.dup2(null,2); ffi.C.close(null)
		-- WebSocket framing belongs to the established client. Never reconnect:
		-- a lost response may already have caused a turn in the existing daemon.
		ffi.C.execlp('websocat','websocat','-t','-E','-B','2097152','--max-ws-frame-length','2097152',
			'--max-ws-message-length','2097152','-','ws-c:unix:'..path,ffi.cast('char *',nil))
		ffi.C._exit(127)
	end
	ffi.C.close(pair[1])
	return M.from_fd(pair[0],timeout,function()
		ffi.C.kill(pid,9); ffi.C.waitpid(pid,nil,0)
	end)
end
return M
