// Edge function "upload-map": checks a map image for explicit content, then stores it.
// POST multipart/form-data: room, file. Returns { path }.
import { createClient } from "jsr:@supabase/supabase-js@2";
import { encodeBase64 } from "jsr:@std/encoding/base64";

const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
const MOD_KEY = Deno.env.get("OPENAI_API_KEY");
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "content-type, authorization, apikey",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (b: unknown, status = 200) =>
  new Response(JSON.stringify(b), { status, headers: { ...cors, "content-type": "application/json" } });
const TYPES: Record<string, string> = { "image/png": "png", "image/jpeg": "jpg", "image/webp": "webp", "image/gif": "gif" };
const FLAG = ["sexual", "sexual/minors", "violence/graphic", "self-harm", "self-harm/intent", "self-harm/instructions"];

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: cors });
  if (req.method !== "POST") return json({ error: "Not allowed" }, 405);
  try {
    const form = await req.formData();
    const room = String(form.get("room") || "");
    const file = form.get("file");
    if (!/^[a-z0-9-]{1,24}$/.test(room)) return json({ error: "Bad room" }, 400);
    if (!(file instanceof File) || !TYPES[file.type]) return json({ error: "Use a PNG, JPG, WebP or GIF image" }, 400);
    if (file.size > 12e6) return json({ error: "Image is too large (12 MB max)" }, 413);
    const { data: r } = await db.from("rooms").select("code").eq("code", room).maybeSingle();
    if (!r) return json({ error: "Room not found" }, 404);

    const bytes = new Uint8Array(await file.arrayBuffer());
    if (!MOD_KEY) return json({ error: "Image check is unavailable, try again later" }, 503);
    const mod = await fetch("https://api.openai.com/v1/moderations", {
      method: "POST",
      headers: { "content-type": "application/json", authorization: `Bearer ${MOD_KEY}` },
      body: JSON.stringify({
        model: "omni-moderation-latest",
        input: [{ type: "image_url", image_url: { url: `data:${file.type};base64,${encodeBase64(bytes)}` } }],
      }),
      signal: AbortSignal.timeout(20000),
    });
    if (!mod.ok) return json({ error: "Image check is unavailable, try again later" }, 503);
    const res = (await mod.json()).results?.[0];
    if (!res) return json({ error: "Image check is unavailable, try again later" }, 503);
    const hit = FLAG.some((k) => res.categories?.[k]) || (res.category_scores?.sexual ?? 0) >= 0.3;
    if (hit) return json({ error: "That image is not allowed" }, 422);

    const path = `${room}/${Date.now()}.${TYPES[file.type]}`;
    const up = await db.storage.from("maps").upload(path, bytes, { contentType: file.type });
    if (up.error) return json({ error: "Upload failed" }, 500);
    return json({ path });
  } catch {
    return json({ error: "Upload failed" }, 500);
  }
});
