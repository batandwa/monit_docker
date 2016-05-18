FROM vimagick/monit

RUN apk add -U curl bash && \
    rm -rf /var/cache/apk/*
