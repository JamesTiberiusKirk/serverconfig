FROM alpine:3.20
RUN apk add --no-cache curl jq bash
COPY bootstrap.sh /usr/local/bin/bootstrap.sh
RUN chmod +x /usr/local/bin/bootstrap.sh
ENTRYPOINT ["/usr/local/bin/bootstrap.sh"]
