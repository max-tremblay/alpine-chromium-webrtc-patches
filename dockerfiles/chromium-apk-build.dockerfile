FROM alpine:3.23.3

RUN apk add --no-cache abuild alpine-sdk doas

RUN adduser -D builder && \
    addgroup builder abuild && \
    echo 'permit nopass :abuild' > /etc/doas.conf && \
    apk update

USER builder

# Generate a signing key baked into the image
RUN abuild-keygen -a -i -n

WORKDIR /home/builder/chromium

CMD ["sh", "-c", "REPODEST=/home/builder/packages abuild -r"]
