FROM swift:6.0.3-jammy
RUN apt-get update && apt-get install -y --no-install-recommends libsqlite3-dev && rm -rf /var/lib/apt/lists/*
WORKDIR /workspace
ENV CLANG_MODULE_CACHE_PATH=/tmp/clang-cache
CMD ["swift", "test", "--package-path", "Packages/VoiceLearning"]
