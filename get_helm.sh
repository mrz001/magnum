#!/usr/bin/env bash
PROJECT_NAME="helm"
TILLER_NAME="tiller"
. /etc/sysconfig/heat-params
: ${USE_SUDO:="true"}
: ${HELM_INSTALL_DIR:="/usr/local/bin"}
initArch() {
  ARCH=$(uname -m)
  case $ARCH in
    armv5*) ARCH="armv5";;
    armv6*) ARCH="armv6";;
    armv7*) ARCH="arm";;
    aarch64) ARCH="arm64";;
    x86) ARCH="386";;
    x86_64) ARCH="amd64";;
    i686) ARCH="386";;
    i386) ARCH="386";;
  esac
}
initOS() {
  OS=$(echo `uname`|tr '[:upper:]' '[:lower:]')

  case "$OS" in
    # Minimalist GNU for Windows
    mingw*) OS='windows';;
  esac
}
runAsRoot() {
  local CMD="$*"

  if [ $EUID -ne 0 -a $USE_SUDO = "true" ]; then
    CMD="sudo $CMD"
  fi

  $CMD
}
verifySupported() {
  local supported="darwin-386\ndarwin-amd64\nlinux-386\nlinux-amd64\nlinux-arm\nlinux-arm64\nlinux-ppc64le\nwindows-386\nwindows-amd64"
  if ! echo "${supported}" | grep -q "${OS}-${ARCH}"; then
    echo "No prebuilt binary for ${OS}-${ARCH}."
    echo "To build from source, go to https://github.com/helm/helm"
    exit 1
  fi

  if ! type "curl" > /dev/null && ! type "wget" > /dev/null; then
    echo "Either curl or wget is required"
    exit 1
  fi
}
checkDesiredVersion() {
  if [ "x$DESIRED_VERSION" == "x" ]; then
    TAG="v2.16.1"
  else
    TAG=$DESIRED_VERSION
  fi
}
checkHelmInstalledVersion() {
  if [[ -f "${HELM_INSTALL_DIR}/${PROJECT_NAME}" ]]; then
    local version=$("${HELM_INSTALL_DIR}/${PROJECT_NAME}" version -c | grep '^Client' | cut -d'"' -f2)
    if [[ "$version" == "$TAG" ]]; then
      echo "Helm ${version} is already ${DESIRED_VERSION:-latest}"
      return 0
    else
      echo "Helm ${TAG} is available. Changing from version ${version}."
      return 1
    fi
  else
    return 1
  fi
}
downloadFile() {
  HELM_DIST="helm-$TAG-$OS-$ARCH.tar.gz"
  DOWNLOAD_URL="${HELM_DOWNLOAD_URL_PREFIX:-https://get.helm.sh/}$HELM_DIST"
  CHECKSUM_URL="$DOWNLOAD_URL.sha256"
  HELM_TMP_ROOT="$(mktemp -dt helm-installer-XXXXXX)"
  HELM_TMP_FILE="$HELM_TMP_ROOT/$HELM_DIST"
  HELM_SUM_FILE="$HELM_TMP_ROOT/$HELM_DIST.sha256"
  echo "Downloading $DOWNLOAD_URL"
  if type "curl" > /dev/null; then
    curl -SsL "$CHECKSUM_URL" -o "$HELM_SUM_FILE"
  elif type "wget" > /dev/null; then
    wget -q -O "$HELM_SUM_FILE" "$CHECKSUM_URL"
  fi
  if type "curl" > /dev/null; then
    curl -SsL "$DOWNLOAD_URL" -o "$HELM_TMP_FILE"
  elif type "wget" > /dev/null; then
    wget -q -O "$HELM_TMP_FILE" "$DOWNLOAD_URL"
  fi
}
installFile() {
  HELM_TMP="$HELM_TMP_ROOT/$PROJECT_NAME"
  local sum=$(openssl sha1 -sha256 ${HELM_TMP_FILE} | awk '{print $2}')
  local expected_sum=$(cat ${HELM_SUM_FILE})
  if [ "$sum" != "$expected_sum" ]; then
    echo "SHA sum of ${HELM_TMP_FILE} does not match. Aborting."
    exit 1
  fi
  mkdir -p "$HELM_TMP"
  tar xf "$HELM_TMP_FILE" -C "$HELM_TMP"
  HELM_TMP_BIN="$HELM_TMP/$OS-$ARCH/$PROJECT_NAME"
  TILLER_TMP_BIN="$HELM_TMP/$OS-$ARCH/$TILLER_NAME"
  echo "Preparing to install $PROJECT_NAME and $TILLER_NAME into ${HELM_INSTALL_DIR}"
  runAsRoot cp "$HELM_TMP_BIN" "$HELM_INSTALL_DIR"
  echo "$PROJECT_NAME installed into $HELM_INSTALL_DIR/$PROJECT_NAME"
  if [ -x "$TILLER_TMP_BIN" ]; then
    runAsRoot cp "$TILLER_TMP_BIN" "$HELM_INSTALL_DIR"
    echo "$TILLER_NAME installed into $HELM_INSTALL_DIR/$TILLER_NAME"
  else
    echo "info: $TILLER_NAME binary was not found in this release; skipping $TILLER_NAME installation"
  fi
}
fail_trap() {
  result=$?
  if [ "$result" != "0" ]; then
    if [[ -n "$INPUT_ARGUMENTS" ]]; then
      echo "Failed to install $PROJECT_NAME with the arguments provided: $INPUT_ARGUMENTS"
      help
    else
      echo "Failed to install $PROJECT_NAME"
    fi
    echo -e "\tFor support, go to https://github.com/helm/helm."
  fi
  cleanup
  exit 0
}
help () {
  echo "Accepted cli arguments are:"
  echo -e "\t[--help|-h ] ->> prints this help"
  echo -e "\t[--version|-v <desired_version>]"
  echo -e "\t[--no-sudo]  ->> install without sudo"
}
cleanup() {
  if [[ -d "${HELM_TMP_ROOT:-}" ]]; then
    rm -rf "$HELM_TMP_ROOT"
  fi
}

. /etc/sysconfig/heat-params

if [ "$(echo $KUBEAPPS_ENABLED | tr '[:upper:]' '[:lower:]')" == "true" ]; then

    trap "fail_trap" EXIT
    set -e
    export INPUT_ARGUMENTS="${@}"
    set -u
    while [[ $# -gt 0 ]]; do
      case $1 in
        '--version'|-v)
          shift
          if [[ $# -ne 0 ]]; then
              export DESIRED_VERSION="${1}"
          else
              echo -e "Please provide the desired version. e.g. --version v2.4.0 or -v latest"
              exit 0
          fi
          ;;
        '--no-sudo')
          USE_SUDO="false"
          ;;
        '--help'|-h)
          help
          exit 0
          ;;
        *) exit 1
          ;;
      esac
      shift
    done
    set +u

    initArch
    initOS
    verifySupported
    checkDesiredVersion
    if ! checkHelmInstalledVersion; then
      downloadFile
      installFile
    fi
    cleanup
    exit 0
fi
