local ffi=require('ffi')
local lfs=require('lfs')
local json=require('cjson.safe')
local rpc=require('unix_rpc')
ffi.cdef[[
int flock(int,int); int fsync(int); int getpid(void); unsigned int umask(unsigned int);
long write(int,const void *,unsigned long); char *realpath(const char *,char *); void free(void *);
typedef struct { long sec; int usec; } llmsend_boot_time;
int sysctlbyname(const char *,void *,unsigned long *,void *,unsigned long);
]]
local M={}
local uid=tonumber(ffi.C.geteuid())
local function owned(stat,kind)
	return stat and stat.mode==kind and stat.uid==uid
		and stat.permissions:sub(5,5)~='w' and stat.permissions:sub(8,8)~='w'
end
function M.canonical(path)
	assert(type(path)=='string' and path:sub(1,1)=='/' and not path:find('[%z\1-\31\127]'),'absolute path required')
	local p=ffi.C.realpath(path,nil); assert(p~=nil,'path unavailable')
	local value=ffi.string(p); ffi.C.free(p); return value
end
function M.read(path,private)
	local stat=lfs.symlinkattributes(path)
	assert(owned(stat,'file') and stat.size<=1024*1024,'unsafe or oversized file')
	if private then assert(stat.permissions:sub(4)=='------','file must be private') end
	local f=assert(io.open(path,'r')); local value=f:read('*a'); assert(f:close())
	return value
end
function M.scan(project)
	local path=project..'/inbox'
	local stat=lfs.symlinkattributes(path)
	if not stat then return {} end
	assert(stat.uid==uid,'inbox must be owned')
	path=M.canonical(path)
	assert(owned(lfs.symlinkattributes(path),'directory'),'unsafe inbox directory')
	local entries={}
	for name in lfs.dir(path) do
		assert(#entries<4096,'inbox entry limit exceeded')
		local a=lfs.symlinkattributes(path..'/'..name)
		if a then entries[#entries+1]={name=name,kind=a.mode,id=tostring(a.dev)..':'..tostring(a.ino)} end
	end
	return entries
end
function M.clock()
	if ffi.os=='OSX' then
		local boot=ffi.new('llmsend_boot_time[1]'); local size=ffi.new('unsigned long[1]',ffi.sizeof(boot))
		assert(ffi.C.sysctlbyname('kern.boottime',boot,size,nil,0)==0,'boot identity unavailable')
		return {mono=rpc.monotonic(),wall=os.time(),boot=tostring(tonumber(boot[0].sec))..':'..tonumber(boot[0].usec)}
	end
	local boot=io.open('/proc/sys/kernel/random/boot_id','r')
	assert(boot,'boot identity unavailable')
	local id=boot:read('*l'); boot:close()
	return {mono=rpc.monotonic(),wall=os.time(),boot=id}
end
function M.open(root,dry)
	local stat=lfs.symlinkattributes(root)
	if not stat and not dry then
		local mask=ffi.C.umask(63); local ok,err=lfs.mkdir(root); ffi.C.umask(mask)
		assert(ok,err); stat=lfs.symlinkattributes(root)
	end
	if stat then assert(owned(stat,'directory') and stat.permissions:sub(4)=='------','state directory must be private and owned') end
	local sequence=0
	local function file(key,suffix)
		assert(key:match('^[%w_-]+$'),'invalid state key')
		return root..'/'..key..suffix
	end
	return {
		load=function(key)
			local path=file(key,'.json')
			if not lfs.symlinkattributes(path) then return nil end
			return assert(json.decode(M.read(path,true)),'invalid state JSON')
		end,
		lock=function(key)
			assert(not dry,'dry-run cannot acquire a writing lock')
			local path=file(key,'.lock')
			local before=lfs.symlinkattributes(path)
			assert(not before or owned(before,'file') and before.permissions:sub(4)=='------','unsafe lock')
			local flags=ffi.os=='OSX' and 0x302 or 0x20042
			local fd=ffi.C.open(path,flags,ffi.cast('int',384)); assert(fd>=0,'cannot open state lock')
			assert(ffi.C.fcntl(fd,2,ffi.cast('int',1))==0,'cannot isolate lock descriptor')
			if ffi.C.flock(fd,6)~=0 then ffi.C.close(fd); return nil end
			return function() ffi.C.flock(fd,8); ffi.C.close(fd) end
		end,
		save=function(key,state)
			assert(not dry,'dry-run cannot write state')
			sequence=sequence+1
			local path=file(key,'.json')
			local temporary=path..'.tmp.'..ffi.C.getpid()..'.'..sequence
			local flags=ffi.os=='OSX' and 0xa01 or 0xc1
			local fd=ffi.C.open(temporary,flags,ffi.cast('int',384)); assert(fd>=0,'cannot create state checkpoint')
			local data=assert(json.encode(state))..'\n'
			local written=ffi.C.write(fd,data,#data)
			local synced=written==#data and ffi.C.fsync(fd)==0
			ffi.C.close(fd); assert(synced,'state checkpoint incomplete')
			assert(os.rename(temporary,path),'cannot publish state checkpoint')
			local dir=ffi.C.open(root,0); assert(dir>=0,'cannot open state directory')
			local ok=ffi.C.fsync(dir)==0; ffi.C.close(dir); assert(ok,'cannot sync state directory')
		end,
	}
end
return M
