#!/bin/bash

##
# This script attempts to do the following:
#  1. Clone mesa
#  2. Build Vulkan drivers
#  3. Install built drivers
#  4. Generate a source-able script to setup an environment
#

if [ "$1" == "--help" ]; then
  echo "Mesa Vulkan installer for Raspberry Pi 4"
  echo -e "Usage: install_vulkan.sh [install[=~/mesa_vulkan]] [config[=release]] [src[=mesa]] [build[=build/\$config]] [script[=vk_icd.sh]]"
  exit
fi

# where to install built drivers: param 1
install=$HOME/mesa_vulkan
[[ $# > 0 ]] && install=$1
# build configuration: param 2
config=release
[[ $# > 1 ]] && config=$2
# where to clone mesa: param 3
src=mesa
[[ $# > 2 ]] && src=$3
# where to build driver (relative to src): param 4
build=build/$config
[[ $# > 3 ]] && build=$4
# where to generate source script: param 5
script=vk_icd.sh
[[ $# > 4 ]] && script=$5
# mesa URL
url=https://gitlab.freedesktop.org/mesa/mesa.git

# prologue
echo "== Vulkan Installer =="
echo -e "\n  install : $install\n  config  : $config\n  src     : $src\n  build   : $build\n"

# codegen
generate_vk_icd() {
  src="$1/share/vulkan/icd.d"
  if [ ! -d "$src" ]; then
    echo "Failed to locate srcectory: $src"
    exit 1
  fi

  file="$src/$(ls "$src")"
  if [ ! -f "$file" ]; then
    echo "Failed to find files in $src"
    exit 1
  fi

  [[ -f $2 || -L $2 ]] && rm -f $2
  
  echo '#!/bin/bash' > $2
  echo -e "\nexport VK_ICD_FILENAMES=$file" >> $2
  echo -e "echo \"Exported VK_ICD_FILENAMES=$VK_ICD_FILENAMES\"" >> $2
  chmod a+x $2

  echo "Generated $2 pointing to $file"
}

# store to return to later
cwd=$(pwd)

# install deps
sudo apt update -y
sudo apt install -y xorg-dev libvulkan-dev libvulkan1 vulkan-tools ninja-build clang lld

# clone mesa
if [[ -d "$src" && ! -d "$src/.git" ]]; then
  echo -e "\n$src/.git not found, purging contents for fresh clone..."
  rm -rf "$src"
fi
if [ ! -d "$src" ]; then
  echo -e "\nCloning mesa into $src..."
  git clone $url "$src" || exit 1
fi

# get latest
cd "$src"
git fetch && git reset --hard origin/main
# configure
meson --prefix "$install" --libdir lib -Dplatforms=x11 -Dvulkan-drivers=broadcom -Ddri-drivers= -Dgallium-drivers= -Dbuildtype=$config "$build" || exit 1

# build
echo -e "\nBuilding driver..."
ninja -C $build || exit 1

# install
echo -e "\nInstalling driver to [$install]..."
ninja install -C $build || exit 1

# return to pwd
cd "$cwd"

# generate script
echo -e "\nGenerating ICD env script..."
generate_vk_icd "$install" $script

if [[ "$cwd" != "$HOME" ]]; then
  # symlink script to ~
  [[ -f $HOME/$script || -L $HOME/$script ]] && rm -f $HOME/$script
  echo -e "\nSymlinking ICD env script to $HOME/vk_icd.sh..."
  ln -s "$cwd/$script" $HOME/$script
fi

# epilogue
echo -e "\nBuild complete"

exit
