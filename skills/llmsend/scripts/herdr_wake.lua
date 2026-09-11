-- Pure screen interpretation and wake sequencing. All clock and I/O are ports.
local M = {}
local function trim(s)
	return (s:gsub('\194\160',' '):gsub('^%s+',''):gsub('%s+$',''))
end

-- Preserve text alongside a mask of non-dim text. SGR colors are consumed as
-- groups: RGB component 2 must never be mistaken for the dim attribute.
local function lines(screen)
	local result = {}
	for raw in (screen:gsub('\r\n','\n')..'\n'):gmatch('(.-)\n') do
		local text, solid, dim, background = '', '', false, false
		local bold, prompt_bold = false, false
		local i=1
		while i<=#raw do
			local a,b,params=raw:find('\27%[([%d;:]*)m',i)
			local chunk=raw:sub(i,(a or (#raw+1))-1)
			-- Non-SGR control sequences mean this is not a rendered snapshot.
			if chunk:find('[%z\1-\8\11-\31\127]') then return nil end
			if text:match('^%s*$') and bold and chunk:match('^%s*›') then prompt_bold=true end
			text=text..chunk; solid=solid..(dim and chunk:gsub('[^ ]',' ') or chunk)
			if not a then break end
			local codes={}
			for code in (params..';'):gmatch('(.-);') do codes[#codes+1]=tonumber(code) or 0 end
			local n=1
			while n<=#codes do
				local c=codes[n]
				if c==0 then dim=false; bold=false
				elseif c==1 then bold=true
				elseif c==2 then dim=true
				elseif c==22 then dim=false; bold=false
				elseif c==38 or c==48 or c==58 then
					if c==48 then background=true end
					n=n+(codes[n+1]==2 and 4 or codes[n+1]==5 and 2 or 0)
				elseif c>=40 and c<=47 then background=true end
				n=n+1
			end
			i=b+1
		end
		result[#result+1]={text=text,solid=solid,background=background,prompt_bold=prompt_bold}
	end
	return result
end

function M.composer(agent, screen)
	local rows=lines(screen or '')
	local unknown={kind='unknown'}
	if not rows then return unknown end
	local start, prefix
	for i=#rows,1,-1 do
		local t=rows[i].text
		local p=agent=='grok' and t:match('^(%s*│%s*❯%s*)')
			or agent=='codex' and t:match('^(%s*›%s*)')
			or agent=='claude' and t:match('^(%s*❯[%s\194\160]*)')
		if p then start=i; prefix=#p; break end
	end
	if not start then return unknown end
	local unboxed=agent=='codex' and not rows[start].background
	if unboxed and not rows[start].prompt_bold then return unknown end
	if agent=='claude' and (start==1 or not rows[start-1].text:find('──',1,true)) then return unknown end
	if agent=='grok' and (start==1 or not trim(rows[start-1].text):match('^╭')) then return unknown end
	local body,solid={},{}
	local closed=false
	for i=start,#rows do
		local r=rows[i]
		if i>start then
			if unboxed then
				-- An unboxed composer has no color boundary. Require its bold
				-- prompt marker plus a separated, bottom-anchored status footer;
				-- include every intervening line so wrapped drafts stay visible.
				if trim(rows[i-1].text)=='' and r.text:match('^%s+.*Context %d+%% left') then
					for tail=i+1,#rows do if trim(rows[tail].text)~='' then return unknown end end
					closed=true; break
				end
			elseif agent=='codex' and not r.background then
				closed=trim(rows[i-1].text)=='' and r.text:find('Context',1,true)~=nil
				break
			elseif agent=='claude' and trim(r.text):match('^──') then closed=true; break
			elseif agent=='grok' and trim(r.text):match('^╰') then closed=true; break end
		end
		local t,s=r.text,r.solid
		if i==start then t=t:sub(prefix+1); s=s:sub(prefix+1) end
		if agent=='grok' then
			if i~=start then
				local p=t:match('^(%s*│)'); if not p then return unknown end
				t=t:sub(#p+1); s=s:sub(#p+1)
			end
			local edge=t:find('│%s*$'); if not edge then return unknown end
			t=t:sub(1,edge-1); s=s:sub(1,edge-1)
		end
		body[#body+1]=trim(t); solid[#solid+1]=trim(s)
	end
	if not closed then return unknown end
	local text=trim(table.concat(body,'\n'))
	local ink=trim(table.concat(solid,'\n'))
	local suggestion=ink=='' and (agent=='claude' or (agent=='codex' and text=='Ask Codex to do anything'))
	return {kind=(text=='' or suggestion) and 'empty' or 'draft', text=text,
		fingerprint=table.concat(body,'\n')..'\0'..table.concat(solid,'\n')}
end

local function eligible(s)
	return s and (s.status=='idle' or s.status=='done') and s.scroll==0
end
local function same(a,b)
	return a and b and a.identity==b.identity and a.geometry==b.geometry
end

function M.run(port, options)
	local start=port.now()
	local initial=port.snapshot()
	if not initial then return {status='deferred',reason='snapshot-unavailable'} end
	local submitted, entered, prior, sent_at=false,false,nil,nil
	local delivery
	local last_reason='observation-deadline'
	local s=initial
	local function finish(status,reason)
		if submitted then port.record(status) end
		return {status=status,reason=reason,submitted=submitted,enter_retry=entered}
	end
	while port.now()-start<=options.timeout do
		if not port.exists() then return finish('note-gone','note removed; not proof of acknowledgement') end
		if s then
			if s.identity~=initial.identity then return finish(submitted and 'unconfirmed' or 'deferred','agent-changed') end
			if submitted and s.status=='working' then return finish('activity-observed','activity is not message acknowledgement') end
			if submitted and s.geometry~=initial.geometry then return finish('unconfirmed','geometry-changed') end
			local composer=M.composer(s.agent,s.screen)
			local stable=eligible(prior) and same(prior,s) and prior.composer==composer.fingerprint
			if not eligible(s) then last_reason=s.scroll~=0 and 'scrollback' or 'agent-'..tostring(s.status)
			elseif composer.kind~='empty' then last_reason=composer.kind=='draft' and 'human-draft' or 'composer-unrecognized'
			elseif not stable then last_reason='snapshot-not-stable' end
			if eligible(s) and stable then
				if not submitted and composer.kind=='empty' then
					-- Claim BEFORE touching the terminal: after a crash, delivery is
					-- uncertain and must not be blindly repeated by another caller.
					if not port.claim() then return finish('already-attempted','inspect previous attempt') end
					submitted=true; sent_at=port.now(); initial=s
					delivery=port.submit(options.pointer)
				elseif submitted and delivery=='stalled' and not entered and composer.kind=='draft'
					and composer.text==options.pointer and port.now()-sent_at>=options.retry_after then
					entered=true; port.record('enter-attempted'); port.enter()
				end
			end
			prior=s; prior.composer=composer.fingerprint
		else
			-- A lifecycle transition can invalidate one capture. Observe again;
			-- absence of a snapshot is never evidence to type or to resend.
			prior=nil
			last_reason='snapshot-unavailable'
		end
		port.wait(options.poll)
		s=port.snapshot()
	end
	return finish(submitted and 'unconfirmed' or 'deferred',submitted and 'observation-deadline' or last_reason)
end
return M
