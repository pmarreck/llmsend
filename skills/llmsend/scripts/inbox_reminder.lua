-- Scheduling and delivery sequencing; filesystem, clock and transport are ports.
local M={}
local function copy(value)
	if type(value)~='table' then return value end
	local result={}; for k,v in pairs(value) do result[k]=copy(v) end; return result
end
function M.pending(entries)
	local names,seen={},{}
	for _,e in ipairs(entries) do
		local name=e.name
		if type(name)=='string' and e.kind=='file' and name:match('%.md$')
			and not name:match('^%.') and not name:find('[/\\%z\1-\31\127]') and not seen[name] then
			names[#names+1]=name; seen[name]=true
		end
	end
	table.sort(names); return names
end
local function remaining(state,interval)
	local due
	for _,note in ipairs(state.notes) do due=math.min(due or note.due,note.due) end
	if not due then return nil end
	return math.max(0,math.max(due,state.blocked_until or 0)-state.elapsed)
end
function M.run(port,options)
	local interval=options.interval or 3600
	assert(interval>0 and interval<math.huge,'invalid interval')
	local clock=port.clock()
	local state=copy(port.load())
	if state and (state.version~=1 or state.identity~=options.identity) then
		return {status='deferred',reason='state-identity-mismatch'}
	end
	local changed=not state or state.clock.boot~=clock.boot
	state=state or {version=1,identity=options.identity,elapsed=0,notes={},sequence=0,attempts=0}
	if state.clock then
		local delta=clock.boot==state.clock.boot and clock.mono-state.clock.mono or clock.wall-state.clock.wall
		state.elapsed=state.elapsed+math.max(0,delta)
	end
	state.clock=clock
	local entries=port.scan()
	local names=M.pending(entries)
	local old,ids={},{}
	local notes_changed=#state.notes~=#names
	for _,note in ipairs(state.notes) do old[note.name]=note end
	for _,e in ipairs(entries) do ids[e.name]=e.id end
	state.notes={}
	for _,name in ipairs(names) do
		local previous=old[name]
		if not previous or previous.id~=ids[name] then notes_changed=true end
		state.notes[#state.notes+1]={name=name,id=ids[name],
			due=previous and previous.id==ids[name] and previous.due or state.elapsed+interval}
	end
	if notes_changed then changed=true; state.retry_operation=nil end
	local function result(status,reason)
		local delay=remaining(state,interval)
		return {status=status,reason=reason,pending=#names,operation=state.operation,
			next_due_seconds=delay,next_due_at=delay and clock.wall+delay,
			last_outcome=state.last_outcome,receipt=state.receipt}
	end
	local function persist() if not options.dry_run then port.save(state) end end
	if #names==0 then
		state.blocked_until=nil; state.attempts=0; state.operation=nil; state.receipt=nil
		state.retry_operation=nil; state.last_outcome='empty'; if changed then persist() end
		return result('empty')
	end
	if remaining(state,interval)>0 then if changed then persist() end; return result('waiting') end
	if options.dry_run then return result('due') end
	local function failure(status,reason,retry_operation)
		state.attempts=state.attempts+1
		local delay=options.retry or 60
		state.retry_operation=retry_operation or state.retry_operation
		if state.attempts>=(options.max_attempts or 3) then delay=interval; state.attempts=0; state.retry_operation=nil end
		state.blocked_until=state.elapsed+delay
		state.last_outcome=status; state.reason=reason
		for _,note in ipairs(state.notes) do note.due=state.elapsed end
		persist(); return result(status,reason)
	end
	local verified,reason=port.verify()
	if not verified then return failure('deferred',reason) end
	local fresh=port.scan()
	local fresh_names=M.pending(fresh)
	local fresh_ids={}; for _,entry in ipairs(fresh) do fresh_ids[entry.name]=entry.id end
	if #fresh_names~=#names then return failure('deferred','note-set-changed') end
	for index,name in ipairs(names) do
		if name~=fresh_names[index] or ids[name]~=fresh_ids[name] then return failure('deferred','note-set-changed') end
	end
	if not state.retry_operation then
		state.sequence=state.sequence+1
		state.operation=options.identity..':'..state.sequence
	end
	state.retry_operation=nil
	state.last_outcome='unconfirmed'; state.receipt=nil; state.reason=nil
	state.blocked_until=nil
	for _,note in ipairs(state.notes) do note.due=state.elapsed+interval end
	-- Claim before delivery. A crash or timeout may have delivered; the next
	-- interval is a new reminder, never an immediate replay of this operation.
	persist()
	local message='Pending inbox reminder. Act on the original notes; move unfinished authorized work into PLAN.md with its owner, blocker and next action. Report genuine owner blockers to the coordinator. Trash envelopes only after completion or durable transfer; reading alone is not handling. Notes: '
		..assert(require('cjson.safe').encode(names))
	local outcome=port.deliver(message,state.operation)
	if outcome.status=='failed' or outcome.status=='deferred' then return failure(outcome.status,outcome.reason,true) end
	state.last_outcome=outcome.status=='delivered' and 'delivered' or 'unconfirmed'
	state.receipt=outcome.receipt; state.attempts=0
	persist(); return result(state.last_outcome,outcome.reason)
end
return M
