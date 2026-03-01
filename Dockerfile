FROM node:20-bookworm-slim AS builder

ARG ZOLA_VERSION=0.17.2

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl git \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL "https://github.com/getzola/zola/releases/download/v${ZOLA_VERSION}/zola-v${ZOLA_VERSION}-x86_64-unknown-linux-gnu.tar.gz" \
    | tar -xz -C /usr/local/bin zola

WORKDIR /app

COPY package.json package_abridge.js ./
RUN npm install --no-audit --no-fund

COPY . .

RUN if [ ! -d themes/abridge/templates ]; then \
      mkdir -p themes \
      && git clone --depth=1 https://github.com/Jieiku/abridge themes/abridge; \
    fi

RUN mkdir -p templates

RUN npm run abridge

FROM nginx:1.27-alpine AS runtime

COPY --from=builder /app/public /usr/share/nginx/html

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
