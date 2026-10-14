local root=arg[1]
package.path=root..'/skills/llmsend/scripts/?.lua;'..package.path
local reminder=require('inbox_reminder')
local json=require('cjson.safe')
local count=0
local function eq(want,got,label)
	assert(want==got,label..': expected '..tostring(want)..', got '..tostring(got)); count=count+1
end
local function clone(x) return assert(json.decode(assert(json.encode(x)))) end
local entries={
	{name='one.frontmatter.md',kind='file',id='1'}, {name='legacy.md',kind='file',id='2'},
	{name='.secret.md',kind='file'}, {name='link.md',kind='link'}, {name='fifo.md',kind='named pipe'},
	{name='dir.md',kind='directory'}, {name='processed/old.md',kind='file'},
	{name='nested/note.md',kind='file'}, {name='readme.txt',kind='file'},
}
local notes=reminder.pending(entries)
eq('legacy.md,one.frontmatter.md',table.concat(notes,','),'classifier exact set')
local function fixture()
	local f={state=nil,time=0,wall=10000,boot='boot-1',entries={{name='note.md',kind='file',id='n1'}},effects={},outcome={status='delivered',receipt='turn-1'},valid=true}
	f.port={
		clock=function() return {mono=f.time,wall=f.wall,boot=f.boot} end,
		load=function() return f.state and clone(f.state) end,
		scan=function() return f.entries end,
		verify=function()
			if f.remove_on_verify then f.entries={} end
			return f.valid, 'recipient-unavailable'
		end,
		save=function(state)
			if f.fail_save then error('injected save failure') end
			f.saves=(f.saves or 0)+1
			f.state=clone(state)
		end,
		deliver=function(message,id)
			f.effects[#f.effects+1]={message=message,id=id}
			if f.crash then error('injected delivery ambiguity') end
			if f.fail_after_send then f.fail_save=true end
			return f.outcome
		end,
	}
	function f.run(dry) return reminder.run(f.port,{interval=3600,retry=60,max_attempts=3,identity='project/session',dry_run=dry}) end
	function f.at(n) f.wall=f.wall+n-f.time; f.time=n; return f.run() end
	return f
end
local f=fixture()
eq('waiting',f.run().status,'first observation starts timer')
eq('waiting',f.at(3599).status,'3599 not due')
eq(1,f.saves,'unchanged scan does not rewrite checkpoint')
eq('delivered',f.at(3600).status,'3600 due')
eq(1,#f.effects,'one aggregate')
eq('waiting',f.at(3601).status,'3601 no duplicate')
eq('waiting',f.run().status,'completed rerun no-op')
eq('delivered',f.at(7200).status,'next hour')
eq(2,#f.effects,'one aggregate per hour')
eq(false,f.effects[1].id==f.effects[2].id,'hourly operations distinct')
assert(f.effects[1].message:find('PLAN',1,true)); count=count+1
f=fixture(); f.run(); f.time=1800; f.wall=11800
f.entries[2]={name='new.md',kind='file',id='n2'}; f.run()
eq('delivered',f.at(3600).status,'new note cannot postpone old note')
eq(2,#f.state.notes,'aggregate includes both')
f=fixture(); f.run(); f.time=3600; f.wall=13600
local persisted=clone(f.state); f.state=persisted
eq('delivered',f.run().status,'restart retains deadline')
f=fixture(); f.run(); f.time=3599; f.wall=1
eq('waiting',f.run().status,'wall rollback uses monotonic elapsed')
f.time=3600; eq('delivered',f.run().status,'wall rollback still due')
f=fixture(); f.run(); f.boot='boot-2'; f.time=1; f.wall=9999
eq('waiting',f.run().status,'reboot rollback does not flood')
f.time=3601; eq('delivered',f.run().status,'reboot rollback resumes countdown')
f=fixture(); f.run(); f.entries={}; eq('empty',f.at(3600).status,'removed notes silent')
f.entries={{name='note.md',kind='file',id='n2'}}
eq('waiting',f.run().status,'recreated file new obligation')
eq(0,#f.effects,'deletion never sends')
f=fixture(); f.run(); f.valid=false
eq('deferred',f.at(3600).status,'offline recipient deferred')
eq(0,#f.effects,'no send without identity')
f.valid=true; eq('waiting',f.at(3659).status,'deferred bounded retry')
eq('delivered',f.at(3660).status,'recipient recovers')
f=fixture(); f.run(); f.outcome={status='failed',reason='rejected'}
eq('failed',f.at(3600).status,'known failed send')
eq('waiting',f.at(3659).status,'no rapid retry')
f.at(3660); f.at(3720)
eq(3,#f.effects,'bounded attempts')
eq(f.effects[1].id,f.effects[2].id,'definite failure retry keeps logical operation identity')
eq('waiting',f.at(3780).status,'exhausted retry waits hour')
f=fixture(); f.run(); f.crash=true
local ok=pcall(function() f.at(3600) end); eq(false,ok,'injected crash after side effect')
f.crash=false
eq('waiting',f.at(3601).status,'ambiguous crash cannot resend')
eq(1,#f.effects,'attempt checkpoint survives crash')
f=fixture(); f.run(); f.fail_save=true
ok=pcall(function() f.at(3600) end); eq(false,ok,'checkpoint failure')
eq(0,#f.effects,'no delivery before durable checkpoint')
f=fixture(); f.run(); f.time=3600; f.wall=13600
local before=json.encode(f.state)
eq('due',f.run(true).status,'dry-run due')
eq(before,json.encode(f.state),'dry-run leaves state untouched')
eq(0,#f.effects,'dry-run never delivers')
f=fixture(); f.run(); f.state.identity='different/session'
eq('deferred',f.at(3600).status,'persisted identity mismatch fails closed')
eq(0,#f.effects,'mismatched state never sends')
f=fixture(); f.run(); f.remove_on_verify=true
eq('deferred',f.at(3600).status,'note removal before send aborts')
eq(0,#f.effects,'no stale reminder after last scan')
f=fixture(); f.run(); f.fail_after_send=true
ok=pcall(function() f.at(3600) end); eq(false,ok,'receipt persistence failure')
f.fail_save=false; f.fail_after_send=false
eq('waiting',f.at(3601).status,'receipt persistence failure retains attempt')
eq(1,#f.effects,'delivered effect not duplicated after failed checkpoint')
f=fixture(); f.run(); f.outcome={status='failed'}; f.at(3600)
f.entries={}; f.at(3601)
f.entries={{name='replacement.md',kind='file',id='new'}}; f.at(3602)
f.outcome={status='delivered',receipt='new-turn'}; f.at(7202)
eq(false,f.effects[1].id==f.effects[2].id,'new obligation cannot inherit an abandoned retry identity')
f=fixture(); f.run(); f.outcome={status='failed'}; f.at(3600)
f.entries={{name='note.md',kind='file',id='new-inode'}}; f.at(3601)
f.outcome={status='delivered',receipt='replacement-turn'}; f.at(7201)
eq(false,f.effects[1].id==f.effects[2].id,'replaced batch cannot reuse an earlier message identity')
print('inbox-reminder: '..count..' assertions passed')
