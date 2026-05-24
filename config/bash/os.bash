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

# =========================================================
# ENVIRONMENT DETECTION
# =========================================================
if [ -f /run/.containerenv ]; then
  ENV_TYPE="container"
  echo "[ 🏗️  Container environment detected ]"
elif [ -f /run/ostree-booted ] || [ "$OS_TYPE" = "mac" ]; then
  ENV_TYPE="immutable"
  echo "[ 🛡️  Immutable host detected ]"
else
  ENV_TYPE="mutable"
  echo "[ 💻 Standard mutable host detected ]"
fi