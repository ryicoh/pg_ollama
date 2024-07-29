FROM debian:bookworm AS builder

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      git ca-certificates postgresql-server-dev-15 libcurl4-openssl-dev make g++ && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /src

RUN git clone https://github.com/pramsey/pgsql-http

WORKDIR /src/pgsql-http

RUN make && \
    make install

FROM postgres:15

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      ca-certificates libcurl4-openssl-dev && \
    rm -rf /var/lib/apt/lists/*

COPY --from=builder /usr/share/postgresql/15/extension/http.control /usr/share/postgresql/15/extension/
COPY --from=builder /usr/share/postgresql/15/extension/http--*.sql  /usr/share/postgresql/15/extension/
COPY --from=builder /usr/lib/postgresql/15/lib/http.so /usr/lib/postgresql/15/lib/

COPY ollama.control /usr/share/postgresql/15/extension/
COPY ollama--1.0.sql /usr/share/postgresql/15/extension/
