# bash completion for nova. Install: copy into a bash-completion completions
# directory (e.g. ~/.local/share/bash-completion/completions/nova, no
# extension) -- sourced automatically by the bash-completion package, no
# ~/.bashrc edit needed.
_nova() {
  local cur prev
  _init_completion || return
  local cmds="encode decode convert preview info bench version"

  if [ "$COMP_CWORD" -eq 1 ]; then
    COMPREPLY=($(compgen -W "$cmds --version" -- "$cur"))
    return
  fi

  case ${COMP_WORDS[1]} in
    encode)
      case $prev in
        -m) COMPREPLY=($(compgen -W "adaptive lossless lossy" -- "$cur")); return ;;
        -l) COMPREPLY=($(compgen -W "0 1 2 3 4 5" -- "$cur")); return ;;
        -live) COMPREPLY=($(compgen -f -X '!*.@(mov|MOV)' -- "$cur")); return ;;
      esac
      COMPREPLY=($(compgen -f -- "$cur")) ;;
    decode|convert)
      case $prev in
        -m) COMPREPLY=($(compgen -W "lossy lossless" -- "$cur")); return ;;
        -look) COMPREPLY=($(compgen -W "canon darktable" -- "$cur")); return ;;
      esac
      COMPREPLY=($(compgen -f -- "$cur")) ;;
    preview|info)
      COMPREPLY=($(compgen -f -X '!*.nova' -- "$cur")) ;;
    bench)
      COMPREPLY=($(compgen -f -X '!*.@(png|PNG|jpg|JPG|jpeg|JPEG)' -- "$cur")) ;;
    *)
      COMPREPLY=($(compgen -f -- "$cur")) ;;
  esac
}
complete -F _nova nova
