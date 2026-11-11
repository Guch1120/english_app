FROM swift:6.0.3-jammy@sha256:95f6ef898992dc840b35517e780f6f6db9661432775ab0b33cc0a531ea749bdb
# Ubuntu mirrors are occasionally unreachable from CI runners; retry instead of failing the gate.
RUN for attempt in 1 2 3 4 5; do \
      apt-get -o Acquire::Retries=3 update && \
      apt-get install -y --no-install-recommends libsqlite3-dev && break; \
      [ "$attempt" -lt 5 ] || exit 1; sleep 20; \
    done && rm -rf /var/lib/apt/lists/*
WORKDIR /workspace
ENV CLANG_MODULE_CACHE_PATH=/tmp/clang-cache
CMD ["swift", "test", "--package-path", "Packages/VoiceLearning"]
