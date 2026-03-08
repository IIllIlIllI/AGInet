export function getEnv() {
  return {
    NODE_ENV: process.env.NODE_ENV ?? "development",
    API_PORT: Number(process.env.API_PORT ?? 3001),
    DATABASE_URL: process.env.DATABASE_URL ?? "",
    PILOT_SUBREDDITS: (process.env.PILOT_SUBREDDITS ?? "technology,news,gaming")
      .split(",")
      .map((s) => s.trim())
      .filter(Boolean),
    ENABLE_PUBLIC_SURFACES: (process.env.ENABLE_PUBLIC_SURFACES ?? "false") === "true"
  };
}
