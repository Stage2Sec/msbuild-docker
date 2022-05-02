# build arguments
ARG UBUNTU_VERSION="20.04"
ARG USER_ID
ARG GROUP_ID
ARG SOLUTION_DIR

FROM ubuntu:${UBUNTU_VERSION}

# environment variables
ENV DEBIAN_FRONTEND="noninteractive"
ENV DOTNET_CLI_TELEMETRY_OPTOUT=1
ENV USER_ID=${USER_ID:-1000}
ENV GROUP_ID=${GROUP_ID:-1000}
ENV SOLUTION_DIR=${SOLUTION_DIR:-/src}

# install available updates, add the wine repository and install the required packages
RUN apt-get update && \
    apt-get full-upgrade --yes && \
    apt-get install --yes wget software-properties-common xvfb && \
    dpkg --add-architecture i386 && \
    wget -qO- https://dl.winehq.org/wine-builds/winehq.key | apt-key add - && \
    apt-add-repository "deb http://dl.winehq.org/wine-builds/ubuntu/ $(lsb_release -cs) main" && \
    apt-get update && \
    apt-get install --install-recommends --yes winehq-stable winbind cabextract && \
    wget -q https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks -O /usr/bin/winetricks && \
    chmod +x /usr/bin/winetricks && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# create a new user called runner (running things as root is not necessary at this point anymore), create the src folder and give the user full permission to that folder
RUN groupadd --gid ${GROUP_ID} runner && \
    useradd --create-home --uid ${USER_ID} --gid ${GROUP_ID} runner && \
    mkdir /src && \
    chown -R ${USER_ID}:${GROUP_ID} /src && \
    mkdir /opt/msbuild && \
    chown -R ${USER_ID}:${GROUP_ID} /opt/msbuild
USER runner

# install Windows SDK
# Initialize the wine environment. Wait until the wineserver process has
# exited before closing the session, to avoid corrupting the wine prefix.
RUN export WINEDLLOVERRIDES="mscoree=" && \
    xvfb-run wineboot --init && \
    while pgrep wineserver > /dev/null; do sleep 1; done

# Set to win10
RUN export WINEDEBUG="-all" && \
    xvfb-run winetricks --force --unattended win10 && \
    (wineserver --kill || true) && \
    rm -rf ${HOME}/.cache/* /tmp/*

# install dotnet 3.5
RUN export WINEDEBUG="-all" && \
    xvfb-run winetricks --force --unattended dotnet35 && \
    (wineserver --kill || true) && \
    rm -rf ${HOME}/.cache/* /tmp/*

# install dotnet 4.8
RUN export WINEDEBUG="-all" && \
    xvfb-run winetricks --force --unattended dotnet48 && \
    (wineserver --kill || true) && \
    rm -rf ${HOME}/.cache/* /tmp/*

# download and install the windows 10 17763 SDK
RUN export WINEDEBUG="-all" && \
    wget -q https://go.microsoft.com/fwlink/p/?LinkID=2033908 -O /tmp/winsdksetup.exe && \
    xvfb-run wine64 /tmp/winsdksetup.exe /norestart /q /installpath "Z:\\opt\\msbuild\\winsdk" && \
    (wineserver --kill || true) && \
    rm -rf ${HOME}/.cache/* /tmp/*


## install .NET 5.0 SDK
RUN wget -q https://download.visualstudio.microsoft.com/download/pr/cc9263cb-9764-4d34-a792-054bebe3abed/08c84422ab3dfdbf53f8cc03f84e06be/dotnet-sdk-5.0.407-win-x64.exe -O /tmp/dotnet-sdk-5.0.407-win-x64.exe && \
    xvfb-run wine /tmp/dotnet-sdk-5.0.407-win-x64.exe /q /norestart && \
    (wineserver --kill || true) && \
    rm -rf ${HOME}/.cache/* /tmp/*

## install .NET Framework 4.5.2 developer/targeting pack
RUN wget -q "https://download.microsoft.com/download/4/3/B/43B61315-B2CE-4F5B-9E32-34CCA07B2F0E/NDP452-KB2901951-x86-x64-DevPack.exe" -O /tmp/NDP452-KB2901951-x86-x64-DevPack.exe && \
    winecfg -v win7 && \
    xvfb-run wine /tmp/NDP452-KB2901951-x86-x64-DevPack.exe /q /norestart /repair && \
    (wineserver --kill || true) && \
    rm -rf ${HOME}/.cache/* /tmp/*

# install .NET Framework 4.5 devel/targeting pack from win8 sdk
RUN export WINEDEBUG="-all" && \
    wget -q "https://go.microsoft.com/fwlink/p/?LinkId=226658" -O /tmp/win8sdk.exe && \
    xvfb-run wine /tmp/win8sdk.exe /q /norestart && \
    (wineserver --kill || true) && \
    rm -rf ${HOME}/.cache/* /tmp/*

# copy buildtools into container
COPY --chown=${USER_ID}:${GROUP_ID} vs_buildtools /opt/msbuild/vs_buildtools

# fix winsdk script
# this if-statement condition ALWAYS fails under wine, seems to be a wine bug?
RUN sed -i 's/\"!result:~0,3!\"==\"10.\"/\"1\"==\"1\"/g' /opt/msbuild/vs_buildtools/Common7/Tools/vsdevcmd/core/winsdk.bat

# copy scripts
COPY bin /usr/bin

# set working directory to /src (or Z:\src in wine terms)
WORKDIR /src
VOLUME ["/src"]

# set vs_cmd as entrypoint
ENTRYPOINT ["vs_cmd"]

# pass "cmd" as argument to vs_cmd by default, this will open a command prompt
CMD ["cmd"]
