# Node 20 hết hỗ trợ 30/04/2026 (không còn bản vá bảo mật) -> Node 24 LTS (hỗ trợ tới 04/2028), pin bản cụ thể
FROM node:24.22.3-alpine
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev
COPY . .
ENV PORT=3001
EXPOSE 3001
CMD ["node", "server.js"]
