const validId = (id) => /^[A-Za-z0-9_-]{12,24}$/.test(id || "");
const escapeHtml = (value = "") => String(value).replace(/[&<>"']/g, (character) => ({
  "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;",
})[character]);
const json = (value, status = 200) => new Response(JSON.stringify(value), {
  status,
  headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" },
});

async function getSong(env, id) {
  if (!validId(id) || !env.DB) return null;
  return env.DB.prepare(
    "SELECT id, title, artist, album, cover_base64, cover_type, preview_base64, preview_type, deep_link, fallback_url FROM shared_songs WHERE id = ?",
  ).bind(id).first();
}

async function createShare(request, env) {
  if (!env.DB) return json({ error: "La base de enlaces no está configurada." }, 503);
  const length = Number(request.headers.get("content-length") || 0);
  if (length > 1_300_000) return json({ error: "La solicitud es demasiado grande." }, 413);

  let payload;
  try { payload = await request.json(); } catch (_) { return json({ error: "Solicitud no válida." }, 400); }
  const id = String(payload.id || "");
  const title = String(payload.title || "").trim().slice(0, 180);
  const artist = String(payload.artist || "").trim().slice(0, 180);
  const album = String(payload.album || "").trim().slice(0, 180);
  const deepLink = String(payload.deepLink || "");
  const fallbackUrl = String(payload.fallbackUrl || "");
  const coverType = String(payload.coverType || "").toLowerCase();
  const coverBase64 = String(payload.coverBase64 || "");
  const previewType = String(payload.previewType || "").toLowerCase();
  const previewBase64 = String(payload.previewBase64 || "");
  const allowedTypes = new Set(["image/jpeg", "image/png", "image/webp"]);

  if (!validId(id) || !title || !artist) return json({ error: "Faltan datos válidos de la canción." }, 400);
  let deepUri;
  try { deepUri = new URL(deepLink); } catch (_) { return json({ error: "Enlace de SoundNeed no válido." }, 400); }
  if (deepUri.protocol !== "soundneed:" || deepUri.hostname !== "track") {
    return json({ error: "Enlace de SoundNeed no válido." }, 400);
  }
  if (fallbackUrl && !/^https:\/\/(www\.)?youtube\.com\/watch\?v=[A-Za-z0-9_-]{11}$/.test(fallbackUrl)) {
    return json({ error: "Enlace alternativo no válido." }, 400);
  }
  if (!allowedTypes.has(coverType)) return json({ error: "Formato de portada no válido." }, 400);
  if (!coverBase64 || coverBase64.length > 600_000 || Math.floor(coverBase64.length * 3 / 4) > 450_000 || !/^[A-Za-z0-9+/]+={0,2}$/.test(coverBase64)) {
    return json({ error: "La portada está vacía o supera el tamaño permitido." }, 413);
  }
  if (previewType !== "image/jpeg" || !previewBase64 || previewBase64.length > 600_000 || Math.floor(previewBase64.length * 3 / 4) > 450_000 || !/^[A-Za-z0-9+/]+={0,2}$/.test(previewBase64)) {
    return json({ error: "La vista previa está vacía, no es JPEG o supera el tamaño permitido." }, 413);
  }

  await env.DB.prepare(
    `INSERT INTO shared_songs (id, title, artist, album, cover_base64, cover_type, preview_base64, preview_type, deep_link, fallback_url, created_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
     ON CONFLICT(id) DO UPDATE SET title=excluded.title, artist=excluded.artist, album=excluded.album,
       cover_base64=excluded.cover_base64, cover_type=excluded.cover_type,
       preview_base64=excluded.preview_base64, preview_type=excluded.preview_type, deep_link=excluded.deep_link,
       fallback_url=excluded.fallback_url, created_at=CURRENT_TIMESTAMP`,
  ).bind(id, title, artist, album, coverBase64, coverType, previewBase64, previewType, deepLink, fallbackUrl).run();
  return json({ url: new URL(`/s/${id}`, request.url).toString() }, 201);
}

function songPage(song, origin) {
  const previewReady = Boolean(song.preview_base64 && song.preview_type);
  const extension = song.cover_type === "image/png" ? "png" : song.cover_type === "image/webp" ? "webp" : "jpg";
  const coverUrl = `${origin}/cover/${encodeURIComponent(song.id)}.${extension}`;
  const previewUrl = `${origin}/preview/${encodeURIComponent(song.id)}.jpg`;
  const pageUrl = `${origin}/s/${encodeURIComponent(song.id)}`;
  const title = escapeHtml(song.title);
  const artist = escapeHtml(song.artist);
  const album = escapeHtml(song.album || "");
  const coverImage = escapeHtml(coverUrl);
  const image = escapeHtml(previewReady ? previewUrl : coverUrl);
  const canonical = escapeHtml(pageUrl);
  const deepLink = escapeHtml(song.deep_link);
  const description = escapeHtml(`${song.artist}${song.album ? ` · ${song.album}` : ""} · Compartido desde SoundNeed`);
  const fallback = song.fallback_url
    ? `<a class="fallback" href="${escapeHtml(song.fallback_url)}" rel="noopener">Abrir alternativa en YouTube</a>`
    : "";
  const imageType = escapeHtml(previewReady ? "image/jpeg" : song.cover_type || "image/png");

  return `<!doctype html><html lang="es"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><meta name="theme-color" content="#071510">
<meta property="og:type" content="music.song"><meta property="og:site_name" content="SoundNeed"><meta property="og:title" content="${title} · SoundNeed">
<meta property="og:description" content="${description}"><meta property="og:url" content="${canonical}"><meta property="og:image" content="${image}"><meta property="og:image:secure_url" content="${image}">
<meta property="og:image:type" content="${imageType}"><meta property="og:image:width" content="${previewReady ? 1200 : 320}"><meta property="og:image:height" content="${previewReady ? 630 : 320}"><meta property="og:image:alt" content="Canción compartida: ${title} · ${artist}">
<meta name="twitter:card" content="summary_large_image"><meta name="twitter:title" content="${title} · SoundNeed"><meta name="twitter:description" content="${description}"><meta name="twitter:image" content="${image}"><title>${title} · SoundNeed</title>
<style>
:root{color-scheme:dark;font-family:Inter,Roboto,"Segoe UI",Arial,sans-serif;background:#06110e;color:#f5f8f6}*{box-sizing:border-box}body{margin:0;min-height:100vh;display:grid;place-items:center;padding:24px;background:radial-gradient(ellipse at 10% 0,#12382b 0,transparent 48%),radial-gradient(ellipse at 100% 100%,#10241d 0,transparent 48%),#06110e}
main{width:min(100%,640px);padding:20px;border:1px solid #c5efda20;border-radius:24px;background:linear-gradient(145deg,#0d241b 0%,#091710 68%,#07120f 100%);box-shadow:0 28px 90px #0008,0 8px 32px #36ce8120;overflow:hidden}.top{display:grid;grid-template-columns:110px minmax(0,1fr);gap:20px;align-items:center}.cover{width:110px;height:110px;object-fit:cover;border-radius:16px;background:#18251f;box-shadow:0 8px 24px #0005}.copy{min-width:0}.eyebrow{margin:0 0 9px;color:#76e2a1;font-size:11px;font-weight:600;letter-spacing:.12em}.title{margin:0 0 7px;color:#fff;font-size:clamp(19px,4vw,25px);font-weight:700;line-height:1.2;overflow-wrap:anywhere}.meta{margin:0;color:#c3cec7;font-size:14px;line-height:1.5;overflow-wrap:anywhere}.album{color:#96a79c}.listen{display:inline-flex;align-items:center;gap:8px;margin-top:12px;color:#79e5a6;font-size:14px;font-weight:600;text-decoration:none;min-height:44px}.listen:focus-visible,.footer:focus-visible,.fallback:focus-visible{outline:2px solid #79e5a6;outline-offset:3px;border-radius:8px}.divider{height:1px;margin:17px 0;background:#e5f4e91c}.footer{display:flex;align-items:center;gap:12px;min-height:46px;color:#becbc3;text-decoration:none;border-radius:10px}.footer:hover .foot-title{color:#fff}.linkicon{width:34px;height:34px;flex:none;display:grid;place-items:center;border-radius:11px;background:#ffffff0b;color:#82dfa5}.footcopy{min-width:0;flex:1}.foot-title,.foot-note{display:block}.foot-title{font-size:13px;font-weight:600;color:#e9f3ec}.foot-note{margin-top:3px;font-size:12px;color:#a3b3a9}.arrow{flex:none;color:#82dfa5}.fallback{display:inline-flex;align-items:center;min-height:44px;margin:8px 0 0 46px;color:#9db1a5;font-size:12px;text-decoration:underline;text-underline-offset:3px}
@media(max-width:420px){body{padding:14px}main{padding:16px;border-radius:20px}.top{grid-template-columns:88px minmax(0,1fr);gap:14px}.cover{width:88px;height:88px;border-radius:13px}.eyebrow{font-size:9px;letter-spacing:.09em}.title{font-size:18px}.meta{font-size:13px}.listen{font-size:13px;margin-top:7px}.divider{margin:13px 0}}@media(prefers-reduced-motion:no-preference){main{animation:enter .2s ease-out}@keyframes enter{from{opacity:.7;transform:scale(.985)}to{opacity:1;transform:scale(1)}}}
</style></head><body><main><section class="top" aria-label="Canción compartida"><img class="cover" src="${coverImage}" alt="Portada de ${title}" width="110" height="110"><div class="copy"><p class="eyebrow">SOUNDNEED · CANCIÓN COMPARTIDA</p><h1 class="title">${title}</h1><p class="meta">${artist}${album ? `<br><span class="album">${album}</span>` : ""}</p><a class="listen" href="${deepLink}" aria-label="Escuchar ${title} en SoundNeed">Escuchar canción <span aria-hidden="true">→</span></a></div></section>
<div class="divider"></div><a class="footer" href="${deepLink}" aria-label="Abrir ${title} en SoundNeed"><span class="linkicon" aria-hidden="true"><svg width="18" height="18" viewBox="0 0 24 24" fill="none"><path d="M10 13.5a5 5 0 0 0 7.1 0l2.1-2.1a5 5 0 0 0-7.1-7.1l-1.2 1.2M14 10.5a5 5 0 0 0-7.1 0l-2.1 2.1a5 5 0 0 0 7.1 7.1l1.2-1.2" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg></span><span class="footcopy"><span class="foot-title">Compartido desde SoundNeed</span><span class="foot-note">Escúchala en SoundNeed.</span></span><span class="arrow" aria-hidden="true"><svg width="20" height="20" viewBox="0 0 24 24" fill="none"><path d="m9 18 6-6-6-6" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg></span></a>${fallback}</main></body></html>`;
}

function imageResponse(song) {
  if (!song?.cover_base64) return new Response("No se encontró la portada.", { status: 404 });
  let binary;
  try { binary = atob(song.cover_base64); } catch (_) { return new Response("Portada no válida.", { status: 500 }); }
  const bytes = Uint8Array.from(binary, (character) => character.charCodeAt(0));
  return new Response(bytes, { headers: {
    "content-type": song.cover_type, "content-length": String(bytes.byteLength),
    "cache-control": "public, max-age=31536000, immutable", "x-content-type-options": "nosniff",
  }});
}

function previewResponse(song) {
  if (!song?.preview_base64 || song.preview_type !== "image/jpeg") {
    return imageResponse(song);
  }
  let binary;
  try { binary = atob(song.preview_base64); } catch (_) { return new Response("Vista previa no válida.", { status: 500 }); }
  const bytes = Uint8Array.from(binary, (character) => character.charCodeAt(0));
  return new Response(bytes, { headers: {
    "content-type": "image/jpeg", "content-length": String(bytes.byteLength),
    "cache-control": "public, max-age=31536000, immutable", "x-content-type-options": "nosniff",
  }});
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.pathname === "/api/share") {
      if (request.method !== "POST") return new Response("Method not allowed", { status: 405, headers: { allow: "POST" } });
      return createShare(request, env);
    }

    const apiSongRoute = url.pathname.match(/^\/api\/song\/([A-Za-z0-9_-]{12,24})\/?$/);
    if (apiSongRoute && request.method === "GET") {
      const song = await getSong(env, apiSongRoute[1]);
      if (!song) return json({ error: "No encontramos esta canción compartida." }, 404);
      return json({ title: song.title, artist: song.artist, album: song.album, deepLink: song.deep_link });
    }

    const songRoute = url.pathname.match(/^\/s\/([A-Za-z0-9_-]{12,24})\/?$/);
    if (songRoute && request.method === "GET") {
      const song = await getSong(env, songRoute[1]);
      if (!song) return new Response("No encontramos esta canción compartida.", { status: 404 });
      return new Response(songPage(song, url.origin), { headers: {
        "content-type": "text/html; charset=utf-8", "cache-control": "public, max-age=300, s-maxage=300",
        "x-content-type-options": "nosniff", "referrer-policy": "strict-origin-when-cross-origin",
      }});
    }

    const coverRoute = url.pathname.match(/^\/cover\/([A-Za-z0-9_-]{12,24})\.(jpg|png|webp)$/i);
    if (coverRoute && request.method === "GET") return imageResponse(await getSong(env, coverRoute[1]));
    const previewRoute = url.pathname.match(/^\/preview\/([A-Za-z0-9_-]{12,24})\.jpg$/i);
    if (previewRoute && request.method === "GET") return previewResponse(await getSong(env, previewRoute[1]));
    return env.ASSETS.fetch(request);
  },
};
