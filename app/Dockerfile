FROM node:20-slim AS dependencies
WORKDIR /usr/src/app
COPY package*.json ./
RUN npm ci --omit=dev

FROM node:20-slim AS runtime
WORKDIR /usr/src/app
ENV NODE_ENV=production
ENV PORT=8080
COPY --from=dependencies /usr/src/app/node_modules ./node_modules
COPY . .
USER node
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s --retries=3 CMD node -e "require('http').get('http://localhost:8080/health', function (res) { process.exit(res.statusCode < 400 ? 0 : 1) }).on('error', function () { process.exit(1) })"
CMD [ "npm", "start" ]
