FROM node:22-alpine AS development

WORKDIR /workspace

COPY package.json package-lock.json ./
RUN npm ci

COPY . .

EXPOSE 5173

FROM development AS build

RUN npm run build

FROM caddy:2.10-alpine AS production

COPY Caddyfile /etc/caddy/Caddyfile
COPY --from=build /workspace/dist /srv

USER caddy


EXPOSE 8080

