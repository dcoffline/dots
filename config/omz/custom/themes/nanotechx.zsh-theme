PROMPT='%F{green}%2c%F{blue} [%f '
RPROMPT='$(if [ -n "$CONTAINER_ID" ]; then echo -n "%F{cyan}  $CONTAINER_ID%f "; fi)$(git_prompt_info) %F{blue}] %F{green}%D{%L:%M} %F{yellow}%D{%p}%f'

ZSH_THEME_GIT_PROMPT_PREFIX="%F{yellow}"
ZSH_THEME_GIT_PROMPT_SUFFIX="%f"
ZSH_THEME_GIT_PROMPT_DIRTY=" %F{red}*%f"
ZSH_THEME_GIT_PROMPT_CLEAN=""
