# Base image with Flutter preinstalled (official image)
FROM ghcr.io/cirruslabs/flutter:stable

# Install common build dependencies
USER root
RUN apt-get update && apt-get install -y \
    clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev unzip xz-utils git curl \
    && apt-get clean

# Optional: accept Android SDK licenses (if Android SDK is installed in the image)
RUN yes | flutter doctor --android-licenses || true

# Set working directory
WORKDIR /workspace