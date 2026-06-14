FROM node:22-alpine AS build

WORKDIR /app

COPY tsconfig.base.json /tsconfig.base.json
COPY frontend/package.json frontend/package-lock.json ./
RUN npm ci

COPY frontend/index.html frontend/vite.config.ts frontend/tsconfig.json ./
COPY frontend/public ./public
COPY frontend/src ./src

RUN npm run build

FROM nginx:1.27-alpine

RUN addgroup -g 1001 app && adduser -u 1001 -G app -D app

COPY frontend/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/dist /usr/share/nginx/html
COPY frontend/docker-entrypoint.sh /docker-entrypoint.sh

RUN chmod +x /docker-entrypoint.sh \
  && chown -R app:app /usr/share/nginx/html /var/cache/nginx /var/log/nginx \
  && touch /var/run/nginx.pid \
  && chown app:app /var/run/nginx.pid

USER app

EXPOSE 8080

ENTRYPOINT ["/docker-entrypoint.sh"]
