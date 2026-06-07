FROM node:22-alpine

WORKDIR /app

RUN corepack enable && corepack prepare pnpm@9 --activate

# Install node-cron and tsx for running TypeScript
COPY package.json pnpm-lock.yaml* ./
RUN pnpm install --frozen-lockfile 2>/dev/null || pnpm install

COPY cron-runner.ts ./

CMD ["pnpm", "exec", "tsx", "cron-runner.ts"]
