local root = arg[1]
package.path = root .. '/skills/llmsend/scripts/?.lua;' .. package.path
local wake = require('herdr_wake')
local count = 0
local function eq(want, got, label)
	assert(want == got, label .. ': expected ' .. tostring(want) .. ', got ' .. tostring(got))
	count = count + 1
end
local e = '\27['
local function codex(body, continuation)
	return e..'48;2;57;55;73m› '..body..'\27[0m\n'
		..e..'48;2;57;55;73m'..(continuation or '')..'\27[0m\n'
		..e..'48;2;57;55;73m \27[0m\n'
		..'gpt-6-astra · Context 60% left\n'
end
local function claude(body, continuation)
	return '──────── project ─\n❯ '..body..'\n'..(continuation or '')..'\n──────────\n  bypass permissions on\n'
end
local function grok(body, continuation)
	return '╭────────────────────╮\n│ ❯ '..body..' │\n'..(continuation or '')..'╰── Grok 4.6 ─╯\nShift+Tab:mode\n'
end
local screens = {
	codex = codex(e..'2mAsk Codex to do anything'),
	claude = claude(e..'2mrun the tests\27[0m'),
	grok = grok(''),
}
-- Observed on Einstein's Codex 0.153.4 pane, 2026-09-11: the
-- composer has a bold marker and dim suggestion, but NO background SGR.
local plain_footer='  '..e..'38;2;246;226;183mgpt-6-astra high'..e..'0m'..e..'2m · '..e..'0m'
	..'Full Access · Context 23% left · weekly 71% left · 0.153.4\r\n'
local function plain_codex(body, continuation)
	return ' \r\n'..e..'0m'..e..'1m›'..e..'0m '..body..e..'0m\r\n'
		..(continuation or '')..' \r\n'..plain_footer
end
eq('empty',wake.composer('codex',plain_codex(e..'2mAsk Codex to do anything')).kind,'Einstein unboxed composer')
for _,width in ipairs({24,80,315}) do
	local pad=string.rep(' ',width)
	eq('empty',wake.composer('codex',plain_codex(pad)).kind,'unboxed empty '..width)
	for _,text in ipairs({'x','Ask Codex to do anything','🙂','[Pasted text #1]'}) do
		eq('draft',wake.composer('codex',plain_codex(text..pad)).kind,'unboxed draft '..width..' '..text)
		eq('draft',wake.composer('codex',plain_codex('',text..'\r\n')).kind,'unboxed wrapped draft '..width..' '..text)
	end
end
eq('unknown',wake.composer('codex','› \n \n'..plain_footer).kind,'unboxed unstyled transcript rejected')
eq('unknown',wake.composer('codex',plain_codex('')..'more transcript\n').kind,'unboxed footer must end viewport')
eq('unknown',wake.composer('codex',e..'1m› '..e..'0m\n \n').kind,'unboxed clipped footer rejected')
for agent, screen in pairs(screens) do
	eq('empty', wake.composer(agent, screen).kind, agent..' observed empty/suggestion')
end
for _, draft in ipairs({'x', 'please fix', '[Pasted text #1]', 'do you trust this folder?'}) do
	for agent, render in pairs({codex=codex, claude=claude, grok=grok}) do
		eq('draft', wake.composer(agent, render(draft)).kind, agent..' draft '..draft)
	end
end
eq('draft', wake.composer('codex', codex('', 'wrapped human text')).kind, 'codex wrapped draft')
eq('draft', wake.composer('claude', claude('', 'wrapped human text')).kind, 'claude wrapped draft')
eq('draft', wake.composer('grok', grok('', '│ wrapped human text │\n')).kind, 'grok wrapped draft')
eq('draft', wake.composer('claude', claude(e..'2msuggestion\27[0m human addition')).kind, 'mixed suggestion and human text')
eq('draft', wake.composer('codex', codex('Ask Codex to do anything')).kind, 'typed placeholder is real text')
eq('unknown', wake.composer('codex', '› old transcript\nfinished').kind, 'transcript is not composer')
eq('unknown', wake.composer('grok', '│ ❯ \n').kind, 'clipped box')
eq('unknown', wake.composer('claude', '❯ \n').kind, 'missing bottom boundary')
for _,width in ipairs({24,40,80,160,315}) do
	local pad=string.rep(' ',width)
	for agent,render in pairs({codex=codex,claude=claude,grok=grok}) do
		eq('empty',wake.composer(agent,render(pad)).kind,agent..' empty at width '..width)
		for _,token in ipairs({'x','0','🙂','never submit me'}) do
			eq('draft',wake.composer(agent,render(token..pad)).kind,agent..' retains draft at width '..width)
		end
	end
end
eq('draft',wake.composer('claude',claude(e..'38;2;2;2;2mvisible text')).kind,'RGB 2 is not SGR dim')
eq('draft',wake.composer('claude',claude(e..'2mghost'..e..'22mreal')).kind,'SGR 22 restores real text')

local function sample(screen, change)
	local s = {identity='session-1', geometry='80x24', status='idle', scroll=0,
		agent='codex', screen=screen or screens.codex}
	for k,v in pairs(change or {}) do s[k]=v end
	return s
end
local pointer='[llmsend:abc123] Read the inbox note at /tmp/project/inbox/note.frontmatter.md.'
local function simulate(samples, options)
	local calls, i, now, record = {}, 0, 0, nil
	local port = {
		now=function() return now end,
		wait=function(seconds) now=now+seconds end,
		exists=function() return not (options or {}).gone end,
		snapshot=function() i=i+1; return samples[math.min(i,#samples)] end,
		claim=function() return not (options or {}).claimed end,
		record=function(state) record=state end,
		submit=function() calls[#calls+1]='prompt'; return (options or {}).transport or 'stalled' end,
		enter=function() calls[#calls+1]='enter'; return true end,
	}
	local result=wake.run(port, {pointer=pointer, timeout=10, poll=1, retry_after=5})
	return result, table.concat(calls, ','), record
end
local r,c=simulate({sample(),sample(),sample(nil,{status='working'})})
eq('activity-observed',r.status,'idle wakes'); eq('prompt',c,'one prompt')
r,c=simulate({sample(),sample(),false,sample(nil,{status='working'})})
eq('activity-observed',r.status,'transient snapshot during lifecycle change retries observation'); eq('prompt',c,'transient snapshot never resends')
r,c=simulate({sample(codex('human draft'))})
eq('deferred',r.status,'draft defers'); eq('',c,'draft untouched')
eq('human-draft',r.reason,'draft deferral is diagnosable')
r,c=simulate({sample('unrecognized layout')})
eq('composer-unrecognized',r.reason,'unsupported layout is diagnosable')
r,c=simulate({sample(),sample(codex('new human keystroke'))})
eq('',c,'draft appearing on final recheck untouched')
r,c=simulate({sample(),sample(nil,{identity='replacement'})})
eq('deferred',r.status,'replacement aborts'); eq('',c,'no replacement input')
r,c=simulate({sample(nil,{scroll=20})})
eq('',c,'scrolled viewport is not live input')
r,c=simulate({sample(nil,{status='blocked'})})
eq('',c,'blocked agent untouched')
r,c=simulate({sample(),sample(),sample(codex(pointer))})
eq('unconfirmed',r.status,'unsent not falsely acknowledged'); eq('prompt,enter',c,'bounded enter only recovery')
r,c=simulate({sample(),sample(),sample(codex(pointer))},{transport='unknown'})
eq('prompt',c,'transport timeout cannot justify Enter while original operation may still be queued')
r,c=simulate({sample(),sample(),sample(codex(pointer..' human addition'))})
eq('prompt',c,'never submit merged draft')
r,c=simulate({sample(),sample(),sample(codex(pointer),{geometry='40x40'})})
eq('prompt',c,'no recovery after resize')
r,c=simulate({sample(),sample(),sample(),sample(),sample(),sample(),sample(),sample(nil,{status='working'})})
eq('activity-observed',r.status,'late submission observed'); eq('prompt',c,'no blind enter at five seconds')
r,c=simulate({sample()}, {claimed=true})
eq('already-attempted',r.status,'durable dedup'); eq('',c,'no duplicate input')
r,c=simulate({sample()}, {gone=true})
eq('note-gone',r.status,'already handled note'); eq('',c,'no obsolete wake')
r,c=simulate({sample(),sample(),sample(codex(pointer)),sample(codex(pointer)),sample(codex(pointer)),sample(codex(pointer)),sample(codex(pointer..' typing'))})
eq('prompt',c,'new typing just before retry prevents Enter')
for _,status in ipairs({'working','blocked','unknown','crashed'}) do
	r,c=simulate({sample(nil,{status=status})})
	eq('',c,'no initial input while '..status)
end
print('herdr-wake: '..count..' assertions passed')
