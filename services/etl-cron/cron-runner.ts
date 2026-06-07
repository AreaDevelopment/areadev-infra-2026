import cron from "node-cron";
import { execSync } from "node:child_process";

const schedule = process.env.SYNC_CRON_SCHEDULE || "0 */6 * * *";

const log = (level: string, msg: string, data?: Record<string, unknown>) => {
  const entry = { timestamp: new Date().toISOString(), level, msg, ...data };
  console.log(JSON.stringify(entry));
};

log("info", "ETL cron runner starting", { schedule });

if (!cron.validate(schedule)) {
  log("error", "Invalid cron schedule", { schedule });
  process.exit(1);
}

cron.schedule(schedule, async () => {
  const startedAt = Date.now();
  log("info", "Sync job triggered");

  try {
    // Run the ETL sync command — assumes areadev-etl-2024 is mounted or accessible
    const etlDir = process.env.ETL_PROJECT_DIR || "/etl";
    execSync("pnpm sync", {
      cwd: etlDir,
      stdio: "inherit",
      timeout: 600_000, // 10 minute timeout
      env: { ...process.env },
    });
    log("info", "Sync job completed", { durationMs: Date.now() - startedAt });
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    log("error", "Sync job failed", { error: message, durationMs: Date.now() - startedAt });
  }
});

log("info", "Cron scheduler running. Next execution based on schedule.", { schedule });

// Keep process alive
process.on("SIGTERM", () => {
  log("info", "Received SIGTERM, shutting down");
  process.exit(0);
});
