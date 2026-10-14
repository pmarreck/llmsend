local root,base=arg[1],arg[2]
package.path=root..'/skills/llmsend/scripts/?.lua;'..package.path
local rpc=require('unix_rpc')
local ffi=require('ffi')
local json=require('cjson.safe')
ffi.cdef[[int fork(void); int waitpid(int,int *,int); int bind(int,const void *,unsigned int); int listen(int,int); int accept(int,void *,void *); void _exit(int);]]
local path=base..'/control.sock'
local addr=ffi.new('llmsend_sockaddr_un'); addr.family=1
assert(#path<ffi.sizeof(addr.path),'fixture socket path exceeds platform limit'); ffi.copy(addr.path,path)
if ffi.os=='OSX' then addr.len=ffi.sizeof(addr) end
local fd=ffi.C.socket(1,1,0); assert(fd>=0)
assert(ffi.C.bind(fd,addr,ffi.sizeof(addr))==0); assert(ffi.C.listen(fd,4)==0)
assert(ffi.C.chmod(path,384)==0)
local pid=ffi.C.fork(); assert(pid>=0)
if pid==0 then
	local c=ffi.C.accept(fd,nil,nil)
	local buffer=ffi.new('char[8192]'); local text=''
	while not text:find('\n',1,true) do
		local got=ffi.C.recv(c,buffer,8192,0)
		if got<=0 then ffi.C._exit(2) end
		text=text..ffi.string(buffer,got)
	end
	local request=json.decode(text:match('([^\n]+)'))
	local response=json.encode({method='ignored/notice',params={}})..'\n'
		..json.encode({id=request.id,result={echo=request.params.text}})..'\n'
	ffi.C.send(c,response,#response,0); ffi.C.close(c); ffi.C.close(fd); ffi.C._exit(0)
end
ffi.C.close(fd)
local client=ffi.C.socket(1,1,0); assert(client>=0)
assert(ffi.C.connect(client,addr,ffi.sizeof(addr))==0)
local connection=assert(rpc.from_fd(client,2))
local response=assert(connection.request('echo',{text='multiline\nUnicode 日本語 🙂'}))
assert(response.echo=='multiline\nUnicode 日本語 🙂','real socket preserves JSON bytes')
local missing=connection.request('after-close',{})
assert(missing==nil,'closed peer is not success')
connection.close()
local status=ffi.new('int[1]'); assert(ffi.C.waitpid(pid,status,0)==pid); assert(status[0]==0)
assert(not rpc.connect(base..'/missing',0.01),'missing socket deferred')
print('unix-rpc: PASS')
