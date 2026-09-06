FROM node:22-alpine AS development

WORKDIR /workspace

COPY package.json package-lock.json ./
RUN npm ci

COPY . .

EXPOSE 5173

FROM development AS build

RUN npm run build

FROM caddy:2.10-alpine AS production

RUN setcap -r /usr/bin/caddy \
    && addgroup \
      --system \
      --gid 10001 \
      web \
    && adduser \
      --system \
      --disabled-password \
      --no-create-home \
      --uid 10001 \
      --ingroup web \
      web \

    && mkdir -p /srv /config /data /tmp \
    && chown -R web:web /srv /config /data /tmp

COPY --from=build --chown=web:web /workspace/dist /srv
COPY --chown=web:web Caddyfile /etc/caddy/Caddyfile

ENV XDG_CONFIG_HOME=/config
ENV XDG_DATA_HOME=/data

USER 10001:10001

EXPOSE 8080

CMD ["caddy", "run", "--config", "/etc/caddy/Caddyfile", "--adapter", "caddyfile"]

