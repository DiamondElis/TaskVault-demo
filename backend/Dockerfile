# vuln-8: intentionally outdated base image + runs as root (no USER instruction).
# Reinforces runAsUser: 0 in k8s/backend-deployment.yaml. See spec §5.3.
FROM node:16-alpine AS build

WORKDIR /app

COPY tsconfig.base.json /tsconfig.base.json
COPY backend/package.json backend/package-lock.json ./
RUN npm ci

COPY backend/tsconfig.json backend/tsconfig.build.json ./
COPY backend/src ./src
COPY backend/migrations ./migrations

RUN npm run build

FROM node:16-alpine AS stage-1

WORKDIR /app

COPY backend/package.json backend/package-lock.json ./
RUN npm ci --omit=dev

COPY --from=build /app/dist ./dist
COPY backend/migrations ./migrations

# vuln-4: fake secret fixture in image layer for scanner correlation (spec §5.2).
# Never read by application code.
COPY backend/test/fixtures/fake-secrets.txt /fixtures/fake-secrets.txt

EXPOSE 8080

# Deliberately no USER — container runs as root (vuln-8).
CMD ["npm", "start"]

# db-migrator entrypoint: same backend artifact, current Node for node-pg-migrate tooling.
FROM node:22-alpine AS migrator

WORKDIR /app

COPY backend/package.json backend/package-lock.json ./
RUN npm ci --omit=dev

COPY --from=build /app/dist ./dist
COPY backend/migrations ./migrations

CMD ["node", "dist/src/db/migrate-and-seed.js"]
