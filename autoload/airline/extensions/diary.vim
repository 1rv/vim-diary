scriptencoding utf-8

if exists('g:loaded_diary_airline')
  finish
else
  let g:loaded_diary_airline = 'yes'
endif

let s:spc = g:airline_symbols.space

function! airline#extensions#diary#init(ext)
  call airline#parts#define_raw('diary', '%{airline#extensions#diary#get()}')
  call a:ext.add_statusline_func('airline#extensions#diary#apply')
endfunction

function! airline#extensions#diary#apply(...)
  let w:airline_section_c = get(w:, 'airline_section_c', g:airline_section_c)
  let w:airline_section_c .= s:spc.g:airline_left_alt_sep.s:spc.'%{airline#extensions#diary#get()}'
endfunction

function! airline#extensions#diary#get()
  let parts = ['status:']

  let remaining = diary#get_remaining_smart_format()
  if remaining !=# ''
    call add(parts, remaining)
  endif

  let status = diary#get_status_formatted()
  if status !=# ''
    call add(parts, status)
  endif

  return join(parts, ' ')
endfunction

augroup TtAirline
  autocmd!
  autocmd User TtTick call airline#update_statusline()
augroup END
