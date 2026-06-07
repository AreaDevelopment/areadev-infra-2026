FROM node:20-alpine

WORKDIR /app

RUN corepack enable && corepack prepare pnpm@latest --activate

# Install node-cron and tsx for running TypeScript
COPY package.json pnpm-lock.yaml* ./
RUN pnpm install --frozen-lockfile 2>/dev/null || pnpm install

COPY cron-runner.ts ./

CMD ["pnpm", "exec", "tsx", "cron-runner.ts"]
