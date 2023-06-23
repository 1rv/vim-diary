let s:plugin_dir = expand('<sfile>:p:h:h')

function! s:init()
  let s:state = {
    \'starttime': -1,
    \'remaining': -1,
    \'status': '',
    \'ondone': ''
  \}
  let s:user_state = {}

  if ! exists('g:diary_diaryfile')
    let g:diary_diaryfile = '~/diary'
  endif

  if ! exists('g:diary_soundfile')
    let g:diary_soundfile = s:plugin_dir . '/' . 'bell.wav'
  endif

  if ! exists('g:diary_statefile')
    let g:diary_statefile = s:get_vimdir() . '/' . 'diary.state'
  endif

  if ! exists('g:diary_progressmark')
    let g:diary_progressmark = '†'
  endif

  call s:read_state()

  if exists('g:diary_use_defaults') && g:diary_use_defaults
    call s:use_defaults()
  endif

  call timer_start(1000, function('s:tick'), { 'repeat': -1 })
endfunction

function! diary#get_status()
  return s:state.status
endfunction

function! diary#get_status_formatted()
  if s:state.status ==# ''
    return s:state.status
  endif
  return '|' . s:state.status . '|'
endfunction

function! diary#set_status(status)
  call s:set_state({ 'status': a:status }, {})
endfunction

function! diary#clear_status()
  call s:set_state({ 'status': '' }, {})
endfunction

function! diary#set_timer(duration)
  let l:was_running = diary#is_running() && diary#get_remaining() > 0
  call diary#pause_timer()
  call s:set_state({ 'remaining': s:parse_duration(a:duration) }, {})
  if l:was_running
    call diary#start_timer()
  endif
endfunction

function! diary#start_timer()
  if diary#get_remaining() >= 0
    call s:set_state({ 'starttime': localtime() }, {})
  endif
endfunction

function! diary#is_running()
  return s:state.starttime >= 0
endfunction

function! diary#pause_timer()
  call s:set_state({ 'starttime': -1, 'remaining': diary#get_remaining() }, {})
endfunction

function! diary#toggle_timer()
  if diary#is_running()
    call diary#pause_timer()
  else
    call diary#start_timer()
  endif
endfunction

function! diary#clear_timer()
  call s:set_state({ 'starttime': -1, 'remaining': -1, 'ondone': '' }, {})
endfunction

function! diary#when_done(ondone)
  call s:set_state({ 'ondone': a:ondone }, {})
endfunction

function! diary#get_remaining()
  if ! diary#is_running()
    return s:state.remaining
  endif

  let l:elapsed = localtime() - s:state.starttime
  let l:difference = s:state.remaining - l:elapsed
  return l:difference < 0 ? 0 : l:difference
endfunction

function! diary#get_remaining_full_format()
  let l:remaining = diary#get_remaining()
  return s:format_duration_display(l:remaining)
endfunction

function! diary#get_remaining_smart_format()
  let l:remaining = diary#get_remaining()
  if diary#is_running()
    return s:format_abbrev_duration(l:remaining)
  else
    return l:remaining < 0
      \? ''
      \: s:format_duration_display(l:remaining)
  endif
endfunction

function! diary#get_state(key, default)
  return has_key(s:user_state, a:key)
    \? s:user_state[a:key]
    \: a:default
endfunction

function! diary#set_state(key, value)
  let l:user_state = {}
  let l:user_state[a:key] = a:value
  call s:set_state({}, l:user_state)
endfunction

function! diary#play_sound()
  let l:soundfile = expand(g:diary_soundfile)
  if ! filereadable(l:soundfile)
    return
  endif

  if executable('afplay')
    call system('afplay ' . shellescape(l:soundfile) . ' &')
  elseif executable('aplay')
    call system('aplay ' . shellescape(l:soundfile) . ' &')
  elseif has('win32') && has ('pythonx')
    pythonx import winsound
    execute 'pythonx' printf('winsound.PlaySound(r''%s'', winsound.SND_ASYNC | winsound.SND_FILENAME)', l:soundfile)
  endif
endfunction

function! s:format_duration_display(duration)
  return '[' . s:format_duration(a:duration) . ']'
endfunction

function! s:format_duration(duration)
  let l:duration = a:duration < 0 ? 0 : a:duration
  let l:hours = l:duration / 60 / 60
  let l:minutes = l:duration / 60 % 60
  let l:seconds = l:duration % 60
  return printf('%02d:%02d:%02d', l:hours, l:minutes, l:seconds)
endfunction

function! s:format_abbrev_duration(duration)
  let l:hours = a:duration / 60 / 60
  let l:minutes = a:duration / 60 % 60
  let l:seconds = a:duration % 60

  if a:duration <= 60
    return printf('%d:%02d', l:minutes, l:seconds)
  elseif l:hours > 0
    let l:displayed_hours = l:hours
    if l:minutes > 0 || l:seconds > 0
      let l:displayed_hours += 1
    endif
    return printf('%dh', l:displayed_hours)
  else
    let l:displayed_minutes = l:minutes
    if l:seconds > 0
      let l:displayed_minutes += 1
    endif
    return printf('%dm', l:displayed_minutes)
  endif
endfunction

function! s:get_vimdir()
  return split(&runtimepath, ',')[0]
endfunction

function! s:parse_duration(duration)
  let l:hours = 0
  let l:minutes = 0
  let l:seconds = 0

  let l:parts = split(a:duration, ":")
  if len(l:parts) == 1
    let [l:val] = l:parts
    if match(l:val, 's$') >= 0
      let l:seconds = l:val
    elseif match(l:val, 'h$') >= 0
      let l:hours = l:val
    else
      let l:minutes = l:val
    endif
  elseif len(l:parts) == 2
    let [l:minutes, l:seconds] = l:parts
  elseif len(parts) == 3
    let [l:hours, l:minutes, l:seconds] = l:parts
  endif

  return l:hours*60*60 + l:minutes*60 + l:seconds
endfunction

function! s:read_state()
  if filereadable(expand(g:diary_statefile))
    let l:state = readfile(expand(g:diary_statefile))
    if l:state[0] ==# 'diary.v3' && len(l:state) == 8
      let s:state = {
        \'starttime': l:state[1],
        \'remaining': l:state[2],
        \'status': l:state[3],
        \'ondone': l:state[4],
      \}
      let s:user_state = eval(l:state[7])
    endif
  endif
endfunction

function! s:set_state(script_state, user_state)
  for l:key in keys(a:script_state)
    let s:state[l:key] = a:script_state[l:key]
  endfor

  for l:key in keys(a:user_state)
    let s:user_state[l:key] = a:user_state[l:key]
  endfor

  let l:state = [
    \'diary.v3',
    \s:state.starttime,
    \s:state.remaining,
    \s:state.status,
    \s:state.ondone,
    \string(s:user_state),
  \]
  call writefile(l:state, expand(g:diary_statefile))
endfunction

function! s:is_new_buffer()
  let l:is_unnamed = bufname('%') == ''
  let l:is_empty = line('$') == 1 && getline(1) == ''
  let l:is_normal = &buftype == ''
  return l:is_unnamed && l:is_empty && l:is_normal
endfunction

function! s:tick(timer)
  if s:state.ondone !=# '' && diary#is_running() && diary#get_remaining() == 0
    let l:ondone = s:state.ondone
    call s:set_state({ 'ondone': '' }, {})
    execute l:ondone
  endif

  doautocmd <nomodeline> User TtTick
endfunction

function! diary#open_diary()
  if ! exists('g:diary_diaryfile') || g:diary_diaryfile ==# ''
    throw 'You must set g:diary_diaryfile before calling diary#open_diary()'
  endif

  let l:diaryfile = expand(g:diary_diaryfile)
  if bufwinid(l:diaryfile) >= 0
    return
  endif

  let l:original_win = bufwinid('%')
  "call s:open_file(l:diaryfile)
  execute "40vsplit " . l:diaryfile
  if ! exists('b:diary_diaryfile_initialized')
    nnoremap <buffer> <CR> :Work<CR>
    let b:diary_diaryfile_initialized = 1
  endif
  call win_gotoid(l:original_win)
endfunction

function! diary#focus_diary()
  let l:win_id = bufwinid(expand(g:diary_diaryfile))

  if l:win_id < 0
    throw 'You must call diary#open_diary() before calling diary#focus_diary()'
  endif

  call win_gotoid(l:win_id)
endfunction

function! diary#write_time()
  let l:test_first = line("$")
  if l:test_first != 1
    execute 'normal! GAa'
  endif
  let l:last_line_num = line("$")
  let l:date = strftime("|%A %x - %I:%M%p|")
  call setline(l:last_line_num, date)
  execute 'normal! GA'
endfunction

function! diary#highlight_diary()
  match dateHeader /\_^\v\|([^|]+)\|/
  execute 'highlight dateHeader guifg = lightred'
endfunction

function! s:use_defaults()
  command! Work
    \  call diary#set_timer(25)
    \| call diary#start_timer()
    \| call diary#set_status('working')
    \| call diary#when_done('AfterWork')

  command! AfterWork
    \  call diary#play_sound()
    \| call diary#open_diary()
    \| call diary#focus_diary()
    \| call diary#highlight_diary()
    \| call diary#write_time()
    \| Break

  command! Break call Break()
  function! Break()
    let l:count = diary#get_state('break-count', 0)
    if l:count >= 3
      call diary#set_timer(15)
      call diary#set_status('long break')
      call diary#set_state('break-count', 0)
    else
      call diary#set_timer(5)
      call diary#set_status('break')
      call diary#set_state('break-count', l:count + 1)
    endif
    call diary#start_timer()
    call diary#when_done('AfterBreak')
  endfunction

  command! AfterBreak
    \  call diary#play_sound()
    \| call diary#set_status('ready')
    \| call diary#clear_timer()

  command! ClearTimer
    \  call diary#clear_status()
    \| call diary#clear_timer()

  command! -range MarkTask <line1>,<line2>call diary#mark_task()
  command! OpenDiary call diary#open_diary() <Bar> call diary#focus_diary() <Bar> call diary#highlight_diary()
  command! -nargs=1 SetTimer call diary#set_timer(<f-args>)
  command! ShowTimer echomsg diary#get_remaining_full_format() . " " . diary#get_status_formatted() . " " . diary#get_task()
  command! ToggleTimer call diary#toggle_timer()

  nnoremap <Leader>tb :Break<cr>
  nnoremap <Leader>tp :ToggleTimer<cr>
  nnoremap <Leader>ts :ShowTimer<cr>
  nnoremap <Leader>tt :OpenDiary<cr>
  nnoremap <Leader>tw :Work<cr>
  call diary#set_status('ready')
endfunction

call s:init()
