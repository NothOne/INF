# Build environment for INF's HarmonyOS NEXT target.
#
# The command-line-tools installer is only downloadable from
# developer.huawei.com behind a signed-in account, so it cannot be fetched in
# CI. Instead the tarball is cut locally from a normal install and published as
# a release asset:
#
#   tar -c -I "xz -T0 -3" -f clt.tar.xz \
#     --exclude='command-line-tools/sdk/default/openharmony/native/llvm' \
#     --exclude='command-line-tools/sdk/default/openharmony/native/docs' \
#     --exclude='command-line-tools/sdk/default/hms/native/BiSheng' \
#     --exclude='command-line-tools/sdk/default/hms/native/docs' \
#     --exclude='command-line-tools/codelinter' \
#     --exclude='command-line-tools/emulator' \
#     --exclude='command-line-tools/arktsdoc' \
#     command-line-tools
#
# 7.1 GB on disk -> 581 MB packed. The excluded trees are the C++ toolchain
# (llvm, BiSheng), reference docs and the IDE-only helpers; an ArkTS-only app
# never invokes them, and hvigor does not require their presence.
#
# glibc: the bundled node needs 2.28, so 24.04 is comfortably new enough.
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    TZ=Asia/Shanghai

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        git \
        git-lfs \
        libgl1 \
        locales \
        openjdk-21-jdk-headless \
        unzip \
        xz-utils \
    && locale-gen en_US.UTF-8 \
    && rm -rf /var/lib/apt/lists/*

# Unpacked in one layer so the tarball itself is never part of the image. The tarball keeps a
# local install's 0700 directories owned by uid 1000; the build user (uid 1001) must be able to
# read and run it, so permissions are opened in the same layer.
RUN --mount=type=bind,source=clt.tar.xz,target=/tmp/clt.tar.xz \
    tar -xJf /tmp/clt.tar.xz -C /opt --no-same-owner \
    && chmod -R a+rX /opt/command-line-tools

# LD_LIBRARY_PATH: the image transcoder hvigor loads for resources links skia from the
# previewer's libraries, and skia needs libGL.
ENV COMMANDLINE_TOOL_DIR=/opt/command-line-tools \
    DEVECO_SDK_HOME=/opt/command-line-tools/sdk \
    HOS_SDK_HOME=/opt/command-line-tools/sdk \
    HAP_SIGN_TOOL_PATH=/opt/command-line-tools/sdk/default/openharmony/toolchains/lib/hap-sign-tool.jar \
    JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64 \
    NODE_HOME=/opt/command-line-tools/tool/node \
    LD_LIBRARY_PATH=/opt/command-line-tools/sdk/default/openharmony/previewer/common/bin

ENV PATH="${JAVA_HOME}/bin:${COMMANDLINE_TOOL_DIR}/tool/node/bin:${COMMANDLINE_TOOL_DIR}/bin:${COMMANDLINE_TOOL_DIR}/ohpm/bin:${COMMANDLINE_TOOL_DIR}/hvigor/bin:${COMMANDLINE_TOOL_DIR}/sdk/default/openharmony/toolchains:${PATH}"

# The OpenHarmony fork is the only Flutter that can run `build hap`; stock
# Flutter has no ohos target. Pinned so the image and .metadata agree.
ARG FLUTTER_OHOS_REF=oh-3.47.7-preview
ENV FLUTTER_HOME=/opt/flutter-ohos

# GitHub's checkout step insists the workspace is owned by the runner user. Flutter is cloned as
# that user too: git refuses a checkout owned by someone else, and the tool writes its own cache.
RUN useradd -m -u 1001 runner \
    && mkdir -p /workspace "$FLUTTER_HOME" \
    && chown runner:runner /workspace "$FLUTTER_HOME"

USER runner

# precache pulls the engine artifacts now so app builds do not pay for them.
RUN git clone --depth 1 -b "$FLUTTER_OHOS_REF" \
        https://gitcode.com/openharmony-tpc/flutter_flutter.git "$FLUTTER_HOME" \
    && git -C "$FLUTTER_HOME" log --oneline -1 \
    && "$FLUTTER_HOME/bin/flutter" --version \
    && "$FLUTTER_HOME/bin/flutter" precache --ohos --no-web --no-linux --no-ios \
        --no-windows --no-macos --no-fuchsia

ENV PATH="${FLUTTER_HOME}/bin:${PATH}"
WORKDIR /workspace

# Fail the image build, not the app build, if the toolchain is broken.
RUN java -version \
    && node -v \
    && ohpm -v \
    && hvigorw -v \
    && flutter --version
