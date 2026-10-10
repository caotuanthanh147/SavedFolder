// GET /api/dash/info — runtime shape the frontend needs at boot: dev-mode
// flag, login mode, demo project slug, free-flow policy, Discord OAuth
// availability. The dev admin token is ONLY exposed when DASH_DEV_MODE is
// explicitly on (local harness; never in production).

import { connection, NextResponse } from "next/server";
import { DASH_DEV_MODE, getStore } from "@/server/store";

export async function GET(): Promise<Response> {
  await connection();
  const store = await getStore();
  return NextResponse.json({
    dev_mode: DASH_DEV_MODE,
    dev_admin_token: DASH_DEV_MODE ? store.devAdminToken : null,
    discord_oauth: store.discordConfigured,
    project: { name: "Yuri Hub", slug: "yuri", script: "Homumado" },
    free: { ...store.config.free, cooldown_seconds: 90 },
  });
}
