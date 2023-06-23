let s:plugin_dir = expand('<sfile>:p:h:h')

function! s:init()
  let s:state = {
    \'starttime': -1,
    \'remaining': -1,
    \'status': '',
    \'ondone': ''
  \}
  let s:user_state = {}

  if ! exists('g:tt_diaryfile')
    let g:tt_diaryfile = '~/diary'
  endif

  if ! exists('g:tt_soundfile')
    let g:tt_soundfile = s:plugin_dir . '/' . 'bell.wav'
  endif

  if ! exists('g:tt_statefile')
    let g:tt_statefile = s:get_vimdir() . '/' . 'tt.state'
  endif

  if ! exists('g:tt_progressmark')
    let g:tt_progressmark = '†'
  endif

  call s:read_state()

  if exists('g:tt_use_defaults') && g:tt_use_defaults
    call s:use_defaults()
  endif

  call timer_start(1000, function('s:tick'), { 'repeat': -1 })
endfunction

function! tt#get_status()
  return s:state.status
endfunction

function! tt#get_status_formatted()
  if s:state.status ==# ''
    return s:state.status
  endif
  return '|' . s:state.status . '|'
endfunction

function! tt#set_status(status)
  call s:set_state({ 'status': a:status }, {})
endfunction

function! tt#clear_status()
  call s:set_state({ 'status': '' }, {})
endfunction

function! tt#set_timer(duration)
  let l:was_running = tt#is_running() && tt#get_remaining() > 0
  call tt#pause_timer()
  call s:set_state({ 'remaining': s:parse_duration(a:duration) }, {})
  if l:was_running
    call tt#start_timer()
  endif
endfunction

function! tt#start_timer()
  if tt#get_remaining() >= 0
    call s:set_state({ 'starttime': localtime() }, {})
  endif
endfunction

function! tt#is_running()
  return s:state.starttime >= 0
endfunction

function! tt#pause_timer()
  call s:set_state({ 'starttime': -1, 'remaining': tt#get_remaining() }, {})
endfunction

function! tt#toggle_timer()
  if tt#is_running()
    call tt#pause_timer()
  else
    call tt#start_timer()
  endif
endfunction

function! tt#clear_timer()
  call s:set_state({ 'starttime': -1, 'remaining': -1, 'ondone': '' }, {})
endfunction

function! tt#when_done(ondone)
  call s:set_state({ 'ondone': a:ondone }, {})
endfunction

function! tt#get_remaining()
  if ! tt#is_running()
    return s:state.remaining
  endif

  let l:elapsed = localtime() - s:state.starttime
  let l:difference = s:state.remaining - l:elapsed
  return l:difference < 0 ? 0 : l:difference
endfunction

function! tt#get_remaining_full_format()
  let l:remaining = tt#get_remaining()
  return s:format_duration_display(l:remaining)
endfunction

function! tt#get_remaining_smart_format()
  let l:remaining = tt#get_remaining()
  if tt#is_running()
    return s:format_abbrev_duration(l:remaining)
  else
    return l:remaining < 0
      \? ''
      \: s:format_duration_display(l:remaining)
  endif
endfunction

function! tt#get_state(key, default)
  return has_key(s:user_state, a:key)
    \? s:user_state[a:key]
    \: a:default
endfunction

function! tt#set_state(key, value)
  let l:user_state = {}
  let l:user_state[a:key] = a:value
  call s:set_state({}, l:user_state)
endfunction

function! tt#play_sound()
  let l:soundfile = expand(g:tt_soundfile)
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
  if filereadable(expand(g:tt_statefile))
    let l:state = readfile(expand(g:tt_statefile))
    if l:state[0] ==# 'tt.v3' && len(l:state) == 8
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
    \'tt.v3',
    \s:state.starttime,
    \s:state.remaining,
    \s:state.status,
    \s:state.ondone,
    \string(s:user_state),
  \]
  call writefile(l:state, expand(g:tt_statefile))
endfunction

function! s:is_new_buffer()
  let l:is_unnamed = bufname('%') == ''
  let l:is_empty = line('$') == 1 && getline(1) == ''
  let l:is_normal = &buftype == ''
  return l:is_unnamed && l:is_empty && l:is_normal
endfunction

function! s:tick(timer)
  if s:state.ondone !=# '' && tt#is_running() && tt#get_remaining() == 0
    let l:ondone = s:state.ondone
    call s:set_state({ 'ondone': '' }, {})
    execute l:ondone
  endif

  doautocmd <nomodeline> User TtTick
endfunction

function! tt#open_diary()
  if ! exists('g:tt_diaryfile') || g:tt_diaryfile ==# ''
    throw 'You must set g:tt_diary before calling tt#open_dairy()'
  endif

  let l:diaryfile = expand(g:tt_diaryfile)
  if bufwinid(l:diaryfile) >= 0
    return
  endif

  let l:original_win = bufwinid('%')
  "call s:open_file(l:diaryfile)
  execute vsplit l:diaryfile
  if ! exists('b:tt_diaryfile_initialized')
    nnoremap <buffer> <CR> :Work<CR>
    let b:tt_diaryfile_initialized = 1
  endif
  call win_gotoid(l:original_win)
endfunction

function! tt#focus_diary()
  let l:win_id = bufwinid(expand(g:tt_diaryfile))

  if l:win_id < 0
    throw 'You must call tt#open_diary() before calling tt#focus_diary()'
  endif

  call win_gotoid(l:win_id)
endfunction

function! s:use_defaults()
  command! Work
    \  call tt#set_timer(1)
    \| call tt#start_timer()
    \| call tt#set_status('working')
    \| call tt#when_done('AfterWork')

  command! AfterWork
    \  call tt#play_sound()
    \| call tt#open_diary()
    \| Break

  command! Break call Break()
  function! Break()
    let l:count = tt#get_state('break-count', 0)
    if l:count >= 3
      call tt#set_timer(15)
      call tt#set_status('long break')
      call tt#set_state('break-count', 0)
    else
      call tt#set_timer(5)
      call tt#set_status('break')
      call tt#set_state('break-count', l:count + 1)
    endif
    call tt#start_timer()
    call tt#when_done('AfterBreak')
  endfunction

  command! AfterBreak
    \  call tt#play_sound()
    \| call tt#set_status('ready')
    \| call tt#clear_timer()

  command! ClearTimer
    \  call tt#clear_status()
    \| call tt#clear_timer()

  command! -range MarkTask <line1>,<line2>call tt#mark_task()
  command! OpenDiary call tt#open_diary() <Bar> call tt#focus_diary()
  command! -nargs=1 SetTimer call tt#set_timer(<f-args>)
  command! ShowTimer echomsg tt#get_remaining_full_format() . " " . tt#get_status_formatted() . " " . tt#get_task()
  command! ToggleTimer call tt#toggle_timer()

  nnoremap <Leader>tb :Break<cr>
  nnoremap <Leader>tp :ToggleTimer<cr>
  nnoremap <Leader>ts :ShowTimer<cr>
  nnoremap <Leader>tt :OpenDiary<cr>
  nnoremap <Leader>tw :Work<cr>
  call tt#set_status('ready')
endfunction

call s:init()
