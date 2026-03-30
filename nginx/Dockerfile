FROM node:20-alpine AS builder
WORKDIR /app
COPY landing/package.json landing/package-lock.json* ./
RUN npm ci --prefer-offline
COPY landing/ .
RUN npm run build

FROM nginx:alpine
COPY nginx/nginx.conf /etc/nginx/nginx.conf
COPY --from=builder /app/dist /usr/share/nginx/html
# ssl монтируется через volume в docker-compose — не копируем в image
