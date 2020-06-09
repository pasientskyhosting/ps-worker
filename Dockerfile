FROM debian:buster-slim
LABEL maintainer "Andreas Krüger <ak@patientsky.com>"
ENV MONO_GC_PARAMS="nursery-size=32M"

RUN apt-get update && \
  apt-get upgrade -y && \
  apt-get install -y -q --install-recommends --no-install-suggests \
  apt-transport-https \
  dirmngr \
  gnupg2 \
  lsb-release \
  wget \
  tzdata \
  curl \
  apt-utils \
  net-tools \
  ca-certificates \
  && rm -rf /var/lib/apt/lists/*


RUN apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 3FA7E0328081BFF6A14DA29AA6A19B38D3D831EF \
  && echo "deb https://download.mono-project.com/repo/debian buster/snapshots/6.0 main" > /etc/apt/sources.list.d/mono-official-stable.list \
  && apt-get update \
  && apt-get install -y -q --install-recommends --no-install-suggests ca-certificates-mono fsharp \
  && rm -rf /var/lib/apt/lists/*

COPY --from=pasientskyhosting/ps-mono:6.0-jemalloc /opt/mono /usr/local

CMD ["/bin/bash"]
