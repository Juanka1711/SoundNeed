import { jsonResponse, validId } from "../_shared.js";

const MAX_COVER_BYTES = 450_000;
const ALLOWED_IMAGE_TYPES = new Set(["image/jpeg", "image/png", "image/webp"]);

export async function onRequestPost({ request, env }) {
  if (!env.DB) return jsonResponse({ error: "La base de enlaces no está configurada." }, 503);

  let payload;
  try {
    payload = await request.json();
  } catch (_) {
    return jsonResponse({ error: "Solicitud no válida." }, 400);
  }

  const id = String(payload.id || "");
  const title = String(payload.title || "").trim().slice(0, 180);
  const artist = String(payload.artist || "").trim().slice(0, 180);
  const album = String(payload.album || "").trim().slice(0, 180);
  const deepLink = String(payload.deepLink || "");
  const coverType = String(payload.coverType || "image/jpeg").toLowerCase();
  const coverBase64 = String(payload.coverBase64 || "");

  if (!validId(id) || !title || !artist || !deepLink.startsWith("soundneed://track")) {
    return jsonResponse({ error: "Faltan datos válidos de la canción." }, 400);
  }
  if (!ALLOWED_IMAGE_TYPES.has(coverType)) {
    return jsonResponse({ error: "La portada debe ser JPEG, PNG o WebP." }, 400);
  }

  const estimatedBytes = Math.floor(coverBase64.length * 3 / 4);
  if (!coverBase64 || estimatedBytes > MAX_COVER_BYTES || !/^[A-Za-z0-9+/]+={0,2}$/.test(coverBase64)) {
    return jsonResponse({ error: "La portada está vacía o supera el tamaño permitido." }, 413);
  }

  await env.DB.prepare(
    `INSERT INTO shared_songs (id, title, artist, album, cover_base64, cover_type, deep_link, created_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
     ON CONFLICT(id) DO UPDATE SET title=excluded.title, artist=excluded.artist, album=excluded.album,
       cover_base64=excluded.cover_base64, cover_type=excluded.cover_type, deep_link=excluded.deep_link,
       created_at=CURRENT_TIMESTAMP`,
  ).bind(id, title, artist, album, coverBase64, coverType, deepLink).run();

  return jsonResponse({ url: new URL(`/s/${id}`, request.url).toString() }, 201);
}

export async function onRequest(context) {
  if (context.request.method === "OPTIONS") {
    return new Response(null, {
      headers: {
        "access-control-allow-origin": "*",
        "access-control-allow-methods": "POST, OPTIONS",
        "access-control-allow-headers": "content-type",
        "access-control-max-age": "86400",
      },
    });
  }
  if (context.request.method !== "POST") return new Response("Method not allowed", { status: 405 });
  const response = await onRequestPost(context);
  const headers = new Headers(response.headers);
  headers.set("access-control-allow-origin", "*");
  return new Response(response.body, { status: response.status, headers });
}
