FROM ubuntu:22.04
LABEL org.opencontainers.image.authors="johannes.dieterich@amd.com"
ENV TZ=America/Chicago
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

RUN apt upgrade -y
RUN apt update && apt install -y sudo wget gnupg2 git gcc gfortran libboost-dev bzip2 openmpi-bin flex build-essential bison libboost-all-dev vim libsqlite3-dev numactl sqlite3 gdb
RUN wget -q -O - https://repo.radeon.com/rocm/rocm.gpg.key | sudo apt-key add -
RUN echo 'deb [arch=amd64] https://repo.radeon.com/rocm/apt/debian/ ubuntu main' | sudo tee /etc/apt/sources.list.d/rocm.list
RUN apt update
RUN apt install -y rocm-dev6.0.0 rocm-libs6.0.0 build-essential libssl-dev swig numpy-stl

COPY target.lst /opt/rocm/bin/

# recent cmake required for FAISS 
WORKDIR /root
RUN wget https://github.com/Kitware/CMake/releases/download/v3.23.1/cmake-3.23.1.tar.gz && tar -zxvf cmake-3.23.1.tar.gz && cd cmake-3.23.1 && ./bootstrap && make -j && make install
 
# ROCm-enabled BLAS (BLIS)
WORKDIR /root
RUN git clone https://github.com/ROCmSoftwarePlatform/blis
WORKDIR blis
RUN git checkout rocm
RUN ./configure -p /opt/blis -t openmp --enable-cblas --enable-amd-offload amd64
RUN make -j
RUN make install

# ROCm-enabled LAPACK (libflame)
WORKDIR /root
RUN git clone https://github.com/ROCmSoftwarePlatform/libflame
WORKDIR libflame
RUN git checkout rocm
RUN ./configure --prefix=/opt/libflame --enable-lapack2flash --enable-vector-intrinsics=sse --enable-supermatrix --enable-hip --enable-blis-use-of-fla-malloc --enable-dynamic-build --enable-static-build --enable-verbose-make-output --enable-multithreading=pthreads --enable-lto
RUN make -j
RUN make install

ENV LD_LIBRARY_PATH=/opt/rocm/lib:$LD_LIBRARY_PATH
RUN ldconfig

# FAISS
WORKDIR /root
RUN git clone https://github.com/ROCm/faiss.git
WORKDIR faiss
RUN git checkout jeffdaily/rocm2 #temporary
RUN cmake -B build  -DFAISS_ENABLE_GPU=OFF -DFAISS_ENABLE_HIP=ON -DBLAS_LIBRARIES=/opt/blis/lib/libblis.so -DLAPACK_LIBRARIES=/opt/libflame/lib/libflame.so -DBUILD_TESTING=ON -DFAISS_HIP_WF32=ON -DCMAKE_PREFIX_PATH=/opt/rocm .
RUN make -C build -j faiss install
#RUN make -C build test

# make the python wrapper (work)
RUN make -C build -j swigfaiss
RUN apt install -y pip
RUN (cd build/faiss/python && python3 setup.py install)

# get rpd
RUN apt install -y libfmt-dev
WORKDIR /root
RUN git clone https://github.com/ROCmSoftwarePlatform/rocmProfileData
WORKDIR rocmProfileData
RUN make
RUN make install

WORKDIR /root/faiss
