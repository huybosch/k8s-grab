FROM node:20-alpine
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev
COPY . .
ENV PORT=3005
EXPOSE 3005
CMD ["node", "server.js"]
