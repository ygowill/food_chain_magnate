# Stage 1: 构建 Vue Portal
FROM node:20-alpine AS portal-builder
WORKDIR /build
COPY web/portal/package.json web/portal/package-lock.json* ./
RUN npm ci --ignore-scripts
COPY web/portal/ .
RUN npm run build

# Stage 2: nginx 服务
FROM nginx:alpine

# Vue SPA 构建产物
COPY --from=portal-builder /build/dist /usr/share/nginx/html

# Godot HTML5 导出（由构建上下文提供，覆盖 public/game/ 占位文件）
COPY build/client/web /usr/share/nginx/html/game

# nginx 配置
COPY web/nginx.conf /etc/nginx/conf.d/default.conf
