FROM node:22-slim AS build
WORKDIR /app
COPY package.json package-lock.json .npmrc ./
RUN npm ci
COPY . .
# The browser talks to the API directly, on this published host port.
ARG VITE_API_PORT=8780
ENV VITE_API_PORT=$VITE_API_PORT
RUN npm run build

FROM node:22-slim
WORKDIR /app
COPY --from=build /app/build ./build
COPY package.json ./
ENV PORT=3000 HOST=0.0.0.0
EXPOSE 3000
USER node
CMD ["node", "build"]
