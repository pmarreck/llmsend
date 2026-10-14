local root,base=arg[1],arg[2]
package.path=root..'/skills/llmsend/scripts/?.lua;'..package.path
local rpc=require('unix_rpc')
local native=require('native_delivery')
local ffi=require('ffi')
local json=require('cjson.safe')
ffi.cdef[[int bind(int,const void *,unsigned int); int listen(int,int);]]
local path=base..'/native.sock'
local addr=ffi.new('llmsend_sockaddr_un'); addr.family=1
assert(#path<ffi.sizeof(addr.path),'fixture socket path exceeds platform limit'); ffi.copy(addr.path,path)
if ffi.os=='OSX' then addr.len=ffi.sizeof(addr) end
local fd=ffi.C.socket(1,1,0); assert(fd>=0)
assert(ffi.C.bind(fd,addr,ffi.sizeof(addr))==0); assert(ffi.C.listen(fd,4)==0)
assert(ffi.C.chmod(path,384)==0)
local pid=ffi.C.fork(); assert(pid>=0)
if pid==0 then
	local null=ffi.C.open('/dev/null',1); ffi.C.dup2(null,1); ffi.C.dup2(null,2); ffi.C.close(null)
	ffi.C.execlp('timeout','timeout','10s','websocat','-t','-E','--oneshot','--accept-from-fd','--exec-exit-on-disconnect',
		'ws-upgrade:unix-l:'..fd,'exec:luajit','--exec-args',root..'/tests/fixtures/native_rpc_server.lua',base,base..'/effects',ffi.cast('char *',nil))
	ffi.C._exit(127)
end
ffi.C.close(fd)
local connection=assert(rpc.connect(path,5))
local adapter=native.new(connection,{project=base,thread='00000000-0000-0000-0000-000000000001'})
assert(adapter.verify(),'real WebSocket verifies native identity')
local result=adapter.deliver('one\nUnicode 日本語 reminder','stable-operation')
assert(result.status=='delivered' and result.receipt=='fixture-turn','real WebSocket turn receipt')
connection.close()
ffi.C.waitpid(pid,nil,0)
local file=assert(io.open(base..'/effects')); local effect=assert(json.decode(file:read('*l')))
assert(file:read('*l')==nil,'one native effect'); file:close()
assert(effect.clientUserMessageId=='stable-operation','operation identity survives protocol')
assert(effect.input[1].text=='one\nUnicode 日本語 reminder','native payload exact')
print('native-socket: PASS')
