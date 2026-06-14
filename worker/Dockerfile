FROM node:22-alpine AS build

WORKDIR /app

COPY tsconfig.base.json /tsconfig.base.json
COPY worker/package.json worker/package-lock.json ./
RUN npm ci

COPY worker/tsconfig.json worker/tsconfig.build.json ./
COPY worker/src ./src

RUN npm run build

FROM node:22-alpine

WORKDIR /app

RUN addgroup -g 1001 app && adduser -u 1001 -G app -D app

COPY worker/package.json worker/package-lock.json ./
RUN npm ci --omit=dev

COPY --from=build /app/dist ./dist

RUN chown -R app:app /app

USER app

EXPOSE 8081

CMD ["npm", "start"]
