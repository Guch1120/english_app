FROM swift:6.0.3-jammy@sha256:95f6ef898992dc840b35517e780f6f6db9661432775ab0b33cc0a531ea749bdb
RUN apt-get update && apt-get install -y --no-install-recommends libsqlite3-dev && rm -rf /var/lib/apt/lists/*
WORKDIR /workspace
ENV CLANG_MODULE_CACHE_PATH=/tmp/clang-cache
CMD ["swift", "test", "--package-path", "Packages/VoiceLearning"]
