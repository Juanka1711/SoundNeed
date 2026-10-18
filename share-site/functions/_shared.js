export const jsonResponse = (body, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
    },
  });

export const escapeHtml = (value = "") =>
  String(value).replace(/[&<>"']/g, (character) => ({
    "&": "&amp;",
    "<": "&lt;",
    ">": "&gt;",
    '"': "&quot;",
    "'": "&#39;",
  })[character]);

export const validId = (id) => /^[A-Za-z0-9_-]{12,24}$/.test(id || "");

export async function getSong(env, id) {
  if (!validId(id) || !env.DB) return null;
  return env.DB.prepare(
    "SELECT id, title, artist, album, cover_base64, cover_type, deep_link FROM shared_songs WHERE id = ?",
  ).bind(id).first();
}
