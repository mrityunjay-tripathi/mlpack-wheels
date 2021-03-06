# Custom functionality for multibuilds.
source gfortran-install/gfortran_utils.sh

function pre_build
{
  # Do the mlpack build so the Python package is ready before the multibuild
  # starts.

  need_sudo="";
  install_prefix="/usr";
  if [ -n "$IS_OSX" ];
  then
    need_sudo="sudo";
    install_prefix="/usr/local";
  fi

  if [ ! -n "$IS_OSX" ];
  then
    # We need to get mlpack dependencies.  We are root inside the container, and
    # this is RHEL5.
    yum install -y wget make gcc-c++
  else
    echo "use brew to get deps";
    # This is OS X, so use brew to get dependencies.
    brew install gcc make wget cmake boost ccache
  fi

  # Make sure OpenBLAS is available.  (not sure how to do LAPACK yet)
  local lib_plat=$PLAT
  echo "lib_plat $PLAT";
  if [ -n "$IS_OSX" ]; then
    echo "do install_gfortran";
    install_gfortran
  fi
  echo "now build_libs $lib_plat";
  build_libs $lib_plat
  echo "done build_libs";

  if [ ! -n "$IS_OSX" ];
  then
    # Install RPMs that were manually made for this image.
    wget http://www.ratml.org/misc/cmake-3.13.5-1.x86_64.rpm
    rpm -ivh cmake-3.13.5-1.x86_64.rpm
    wget http://www.ratml.org/misc/boost-1.70.0-1.x86_64.rpm
    rpm -ivh boost-1.70.0-1.x86_64.rpm

    # Install precompiled LAPACK (this is specific to this image).
    wget http://www.ratml.org/misc/lapack-3.8.0.el5.x86_64.tar.gz
    tar -xzpf lapack-3.8.0.el5.x86_64.tar.gz -C /
  fi

  echo "get and install armadillo";
  # Build and install Armadillo.
  wget http://www.ratml.org/misc/armadillo-9.400.4.tar.gz
  tar -xzpf armadillo-9.400.4.tar.gz
  cd armadillo-9.400.4/
  cmake -DCMAKE_INSTALL_PREFIX=$install_prefix .
  make
  $need_sudo make install
  cd ../

  # Install Python dependencies.
  pip install setuptools numpy pandas Cython

  # Finally let's go ahead and build mlpack.
  cd mlpack/
  source patch-info.sh
  # Hacky patch: use cmake -E copy_if_different not cmake -E copy for Python
  # files, so it doesn't recompile with different options during the install.
  sed -i -e "s/-E copy/-E copy_if_different/g" \
      src/mlpack/bindings/python/CMakeLists.txt
  mkdir build
  cd build/
  cmake \
      -DBUILD_TESTS=OFF \
      -DBUILD_CLI_EXECUTABLES=OFF \
      -DBUILD_PYTHON_BINDINGS=ON \
      -DBoost_NO_BOOST_CMAKE=ON \
      -DCMAKE_CXX_COMPILER_LAUNCHER=`which ccache` \
      ../
  echo "mlpack build directory:"
  pwd
  make -j2 python
  echo "done building, now install";
  $need_sudo make install

  # Modify setup.py to reflect 'mlpack3' PyPI package name.
  if [ "a$PATCH" == "a1" ];
  then
    echo "patching name to mlpack3 (patch is $PATCH)"
    sed -i -e "s/setup(name='mlpack'/setup(name='mlpack3'/" src/mlpack/bindings/python/setup.py
  else
    echo "not patching name; patch is $PATCH"
  fi

  # Make sure the directory is right to work around possible bdist_egg
  # permission failure.
  $need_sudo chmod -R 777 src/mlpack/bindings/python/
}

function build_libs {
    local plat=${1:-$PLAT}
    local tar_path=$(abspath $(get_gf_lib "openblas-${OPENBLAS_VERSION}" "$plat"))
    # Sudo needed for macOS
    local use_sudo=""
    [ -n "$IS_OSX" ] && use_sudo="sudo"
    (cd / && $use_sudo tar zxf $tar_path)
}

function run_tests
{
  # Let's just make sure mlpack loads.  TODO: maybe run the tests.
  python --version
  python -c 'import sys; import mlpack; import numpy as np; x = np.random.rand(100, 10); o = mlpack.pca(input=x, new_dimensionality=5, verbose=True)'
}
