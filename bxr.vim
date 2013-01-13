" NOTE: You must, of course, install the bxr script
"       in your path: https://github.com/bakulf/mxr

" Location of the bxr utility
if !exists("g:bxrprg")
    let g:bxrprg="bxr -V "
endif

if !exists("g:bxr_qhandler")
  let g:bxr_qhandler="botright copen"
endif

if !exists("g:bxr_lhandler")
  let g:bxr_lhandler="botright lopen"
endif

if !exists("g:bxr_apply_qmappings")
  let g:bxr_apply_qmappings = !exists("g:bxr_qhandler")
endif

if !exists("g:bxr_apply_lmappings")
  let g:bxr_apply_lmappings = !exists("g:bxr_lhandler")
endif

function! s:bxr(cmd, task, format, args)
    redraw
    echo "Searching ..."

    " If no pattern is provided, search for the word under the cursor
    if empty(a:args)
        let l:grepargs = expand("<cword>")
    else
        let l:grepargs = a:args . join(a:000, ' ')
    end

    let grepprg_bak=&grepprg
    let grepformat_bak=&grepformat
    try
        let &grepprg=g:bxrprg
        let &grepformat=a:format
        execute a:cmd . " " . a:task . " " . escape(l:grepargs, '|')
    finally
        let &grepprg=grepprg_bak
        let &grepformat=grepformat_bak
    endtry

  if a:cmd =~# '^l'
    exe g:bxr_lhandler
    let l:apply_mappings = g:bxr_apply_lmappings
  else
    exe g:bxr_qhandler
    let l:apply_mappings = g:bxr_apply_qmappings
  endif

  if l:apply_mappings
    exec "nnoremap <silent> <buffer> q :ccl<CR>"
    exec "nnoremap <silent> <buffer> t <C-W><CR><C-W>T"
    exec "nnoremap <silent> <buffer> T <C-W><CR><C-W>TgT<C-W><C-W>"
    exec "nnoremap <silent> <buffer> o <CR>"
    exec "nnoremap <silent> <buffer> go <CR><C-W><C-W>"
    exec "nnoremap <silent> <buffer> h <C-W><CR><C-W>K"
    exec "nnoremap <silent> <buffer> H <C-W><CR><C-W>K<C-W>b"
    exec "nnoremap <silent> <buffer> v <C-W><CR><C-W>H<C-W>b<C-W>J<C-W>t"
    exec "nnoremap <silent> <buffer> gv <C-W><CR><C-W>H<C-W>b<C-W>J"
  endif

  redraw!
endfunction

command! -bang -nargs=* -complete=file BI call s:bxr('grep<bang>', 'i', '%f:%l:%c:%m', <q-args>)
command! -bang -nargs=* -complete=file BF call s:bxr('grep<bang>', 'f', '%f', <q-args>)
command! -bang -nargs=* -complete=file BS call s:bxr('grep<bang>', 's', '%f:%l:%m', <q-args>)
