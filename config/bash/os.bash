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

