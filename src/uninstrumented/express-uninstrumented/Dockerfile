FROM node:24-alpine

WORKDIR /app

COPY package*.json ./

RUN npm ci --omit=dev

COPY *.js .

USER node

EXPOSE 3000

CMD ["node", "app.js"]
