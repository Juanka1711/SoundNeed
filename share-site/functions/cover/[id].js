import { getSong, validId } from "../_shared.js";

export async function onRequest({ env, params }) {
  const id = String(params.id || "").replace(/\.(jpg|png|webp)$/i, "");
  if (!validId(id)) return new Response("Not found", { status: 404 });
  const song = await getSong(env, id);
  if (!song?.cover_base64) return new Response("Not found", { status: 404 });

  let binary;
  try {
    binary = atob(song.cover_base64);
  } catch (_) {
    return new Response("Invalid image", { status: 500 });
  }
  const bytes = Uint8Array.from(binary, (character) => character.charCodeAt(0));
  return new Response(bytes, {
    headers: {
      "content-type": song.cover_type,
      "content-length": String(bytes.byteLength),
      "cache-control": "public, max-age=31536000, immutable",
      "x-content-type-options": "nosniff",
    },
  });
}
