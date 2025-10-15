FROM debian:bookworm-slim

WORKDIR /app

RUN apt-get update && \
    apt-get install --no-install-recommends -y ca-certificates iproute2 iptables curl && \
    echo "deb [trusted=yes] https://packages.twingate.com/apt/ /" | tee /etc/apt/sources.list.d/twingate.list && \
    apt-get update -o Dir::Etc::sourcelist="sources.list.d/twingate.list" -o Dir::Etc::sourceparts="-" -o APT::Get::List-Cleanup="0" && \
    apt-get install --no-install-recommends -y twingate && \
    ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && \
    echo "Asia/Singapore" > /etc/timezone && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh healthcheck.sh /app/

ENTRYPOINT [ "/app/entrypoint.sh" ]
