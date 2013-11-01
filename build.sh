
[[ $BC_CACHE ]] || export BC_CACHE="$HOME/.crowbar-build-cache/barclamps/glance"
[[ $CROWBAR_DIR ]] || export CROWBAR_DIR="$HOME/crowbar"
[[ $BC_DIR ]] || export BC_DIR="$HOME/crowbar/barclamps/glance"

echo "Using: BC_CACHE = $BC_CACHE"
echo "Using: CROWBAR_DIR = $CROWBAR_DIR"
echo "Using: BC_DIR = $BC_DIR"

bc_needs_build() {
  [[ ! -f "$BC_CACHE/files/docker/precise.xz" ]]
}

#bc_build() {
    mkdir -p "$BC_CACHE/files/docker"

    cd "$BC_CACHE/files/docker"
    if ! unzip -t "$BC_CACHE/files/docker/precise.zip" ; then
      echo "getting precise from https://github.com/tianon/docker-brew-ubuntu/archive/precise.zip "
      curl -Ls https://github.com/tianon/docker-brew-ubuntu/archive/precise.zip > precise.zip
    fi
    unzip precise.zip
    ls 
  #rm -rf precise.zip
    [[ ! -f ${BC_CACHE}/files/docker/docker-brew-ubuntu-precise/precise.tar.xz ]] && die "Can\'t find precise.tar.xz"
    cd -

#}

