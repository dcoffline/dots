# =========================================================
# OS DETECTION
# =========================================================

case "$OSTYPE" in
darwin*)
  export OS_TYPE="mac"
  export IS_MAC=1
  export IS_LINUX=0
  ;;
linux*)
  export OS_TYPE="linux"
  export IS_MAC=0
  export IS_LINUX=1
  ;;
*)
  export OS_TYPE="unknown"
  export IS_MAC=0
  export IS_LINUX=0
  ;;
esac

if [ -f /run/.containerenv ]; then
  export ENV_TYPE="container"
elif [ -f /run/ostree-booted ] || [ "$OS_TYPE" = "mac" ]; then
  export ENV_TYPE="immutable"
else
  export ENV_TYPE="mutable"
fi

# Drains unread terminal query responses (OSC 11 / CPR) from stdin in interactive shells
if [[ $- == *i* ]]; then
  read -t 0.05 -n 10000 _ 2>/dev/null || true
fi

