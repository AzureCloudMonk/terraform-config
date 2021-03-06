#!/bin/bash

set -o errexit

PACKER_USERS="matt ryn emma halle carmen"

main() {
  create_docker_group
  create_packer_user
  setup_ssh_access
  install_apt_packages
  install_go
  install_ruby
  install_vsphere_images
  install_packer
  install_packer_builders
  clone_packer_templates
  fix_ownership
}

create_docker_group() {
  if getent group docker >/dev/null; then
    echo ">>> Skipping creating docker group"
    return 0
  fi

  echo ">>> Creating docker group"
  groupadd docker
}

create_packer_user() {
  if getent passwd packer >/dev/null; then
    echo ">>> Updating packer user"
    chsh -s /bin/bash packer
    usermod -aG ssh-user,docker packer
    return 0
  fi

  echo ">>> Creating packer user"
  useradd -m -G ssh-user,docker -s /bin/bash packer
  mkdir /home/packer/bin
}

setup_ssh_access() {
  echo ">>> Copying keys to packer user"
  mkdir -p /home/packer/.ssh
  rm -f /home/packer/.ssh/authorized_keys
  touch /home/packer/.ssh/authorized_keys

  for user in $PACKER_USERS; do
    cat "/home/$user/.ssh/authorized_keys" >>/home/packer/.ssh/authorized_keys
  done
}

install_apt_packages() {
  echo ">>> Installing apt packages"

  # install docker from the official repo
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
  add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"

  # be able to install a recent Git version, trusty's is tremendously old
  add-apt-repository -y ppa:git-core/ppa
  apt-get update

  apt-get install -y \
    build-essential \
    docker-ce \
    git \
    libssl-dev \
    libreadline-dev \
    tmux \
    unzip \
    zlib1g-dev
}

install_go() {
  if [[ -d "/usr/local/go" ]]; then
    echo ">>> Skipping installing go"
  else
    echo ">>> Installing go"

    local go_archive="/tmp/go1.10.3.tar.gz"

    curl -L "https://dl.google.com/go/go1.10.3.linux-amd64.tar.gz" -o $go_archive
    tar -C /usr/local -xzf $go_archive
  fi

  cat >/etc/profile.d/go.sh <<'EOF'
export GOROOT=/usr/local/go
export PATH=$GOROOT/bin:$PATH
EOF

  # make Go available in this script
  # shellcheck disable=SC1091
  source /etc/profile.d/go.sh

  if ! grep -q 'export GOPATH' /home/packer/.profile; then
    cat >/home/packer/.profile <<'EOF'
export GOPATH=$HOME/go
export PATH=$(go env GOPATH)/bin:$PATH
EOF
  fi

  export GOPATH=/home/packer/go
  export PATH=/home/packer/go/bin:$PATH
}

install_ruby() {
  if [[ -f "/usr/local/bin/ruby" ]]; then
    echo ">>> Skipping installing ruby"
    return 0
  fi

  echo ">>> Installing ruby"
  git clone https://github.com/rbenv/ruby-build.git /tmp/ruby-build
  PREFIX=/usr/local /tmp/ruby-build/install.sh

  ruby-build 2.5.1 /usr/local
}

install_vsphere_images() {
  echo ">>> Installing vsphere-images"
  go get -u github.com/FiloSottile/gvt
  go get -u github.com/travis-ci/vsphere-images

  pushd $GOPATH/src/github.com/travis-ci/vsphere-images
  make deps
  make
  popd
}

install_packer() {
  if [[ -f "/usr/local/bin/packer" ]]; then
    echo ">>> Skipping installing packer"
    return 0
  fi

  echo ">>> Installing packer"
  local packer_archive="packer1.2.4.zip"
  curl -L "https://releases.hashicorp.com/packer/1.2.4/packer_1.2.4_linux_amd64.zip" -o $packer_archive
  unzip $packer_archive -d /usr/local/bin
}

install_packer_builder() {
  local builder_type=$1
  local packer_builder_dest="/usr/local/bin/packer-builder-vsphere-$builder_type.linux"
  if [[ -f $packer_builder_dest ]]; then
    echo ">>> Skipping installing packer-builder-vsphere-$builder_type"
  else
    echo ">>> Installing packer-builder-vsphere-$builder_type"
    curl -L "https://github.com/jetbrains-infra/packer-builder-vsphere/releases/download/v2.0/packer-builder-vsphere-$builder_type.linux" -o "$packer_builder_dest"
  fi

  chmod +x "$packer_builder_dest"
}

install_packer_builders() {
  install_packer_builder clone
  install_packer_builder iso
}

clone_packer_templates() {
  if [[ -d "/home/packer/packer-templates-mac" ]]; then
    echo ">>> Updating packer-templates-mac repository"
    pushd /home/packer/packer-templates-mac
    git reset --hard
    git checkout master
    git clean -df
    git pull
    popd

    return 0
  fi

  echo ">>> Cloning packer-templates-mac repository"
  pushd /home/packer
  git clone https://github.com/travis-ci/packer-templates-mac.git
  popd
}

fix_ownership() {
  echo ">>> Fixing ownership for /home/packer"
  chown -R packer:packer /home/packer
}

main "$@"
