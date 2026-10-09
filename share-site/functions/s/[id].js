import { escapeHtml, getSong } from "../_shared.js";

const page = ({ title, artist, album, coverUrl, pageUrl, deepLink, fallbackUrl }) => {
  const safeTitle = escapeHtml(title);
  const safeArtist = escapeHtml(artist);
  const safeAlbum = escapeHtml(album);
  const safeCover = escapeHtml(coverUrl);
  const safePage = escapeHtml(pageUrl);
  const safeDeepLink = escapeHtml(deepLink);
  const fallbackAction = fallbackUrl
    ? `<a class="fallback" href="${escapeHtml(fallbackUrl)}" rel="noopener">Abrir alternativa en YouTube</a>`
    : "";

  return `<!doctype html>
<html lang="es">
<head>
  <meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="theme-color" content="#071510">
  <meta property="og:type" content="music.song">
  <meta property="og:site_name" content="SoundNeed">
  <meta property="og:title" content="${safeTitle} · SoundNeed">
  <meta property="og:description" content="${safeArtist}${album ? ` · ${safeAlbum}` : ""} · Compartido desde SoundNeed">
  <meta property="og:url" content="${safePage}">
  <meta property="og:image" content="${safeCover}">
  <meta property="og:image:secure_url" content="${safeCover}">
  <meta property="og:image:type" content="${escapeHtml(coverUrl.endsWith(".png") ? "image/png" : coverUrl.endsWith(".webp") ? "image/webp" : "image/jpeg")}">
  <meta property="og:image:alt" content="Portada de ${safeTitle}">
  <meta name="twitter:card" content="summary_large_image">
  <meta name="twitter:title" content="${safeTitle} · SoundNeed">
  <meta name="twitter:description" content="${safeArtist}${album ? ` · ${safeAlbum}` : ""} · Compartido desde SoundNeed">
  <meta name="twitter:image" content="${safeCover}">
  <title>${safeTitle} · SoundNeed</title>
  <style>
    :root{color-scheme:dark;font-family:Inter,Roboto,"Segoe UI",Arial,sans-serif;background:#06110e;color:#f5f8f6}
    *{box-sizing:border-box}body{margin:0;min-height:100vh;display:grid;place-items:center;padding:24px;background:radial-gradient(ellipse at 10% 0,#12382b 0,transparent 48%),radial-gradient(ellipse at 100% 100%,#10241d 0,transparent 48%),#06110e}
    main{width:min(100%,640px);padding:20px;border:1px solid #c5efda20;border-radius:24px;background:linear-gradient(145deg,#0d241b 0%,#091710 68%,#07120f 100%);box-shadow:0 28px 90px #0008,0 8px 32px #36ce8120;overflow:hidden}
    .top{display:grid;grid-template-columns:110px minmax(0,1fr);gap:20px;align-items:center}.cover{width:110px;height:110px;object-fit:cover;border-radius:16px;background:#18251f;box-shadow:0 8px 24px #0005}.copy{min-width:0}.eyebrow{margin:0 0 9px;color:#76e2a1;font-size:11px;font-weight:600;letter-spacing:.12em}.title{margin:0 0 7px;color:#fff;font-size:clamp(19px,4vw,25px);font-weight:700;line-height:1.2;overflow-wrap:anywhere}.meta{margin:0;color:#c3cec7;font-size:14px;line-height:1.5;overflow-wrap:anywhere}.album{color:#96a79c}.listen{display:inline-flex;align-items:center;gap:8px;margin-top:12px;color:#79e5a6;font-size:14px;font-weight:600;text-decoration:none;min-height:44px}.listen:focus-visible,.fallback:focus-visible{outline:2px solid #79e5a6;outline-offset:3px;border-radius:8px}.divider{height:1px;margin:17px 0;background:#e5f4e91c}.footer{display:flex;align-items:center;gap:12px;min-height:46px;color:#becbc3}.linkicon{width:34px;height:34px;flex:none;display:grid;place-items:center;border-radius:11px;background:#ffffff0b;color:#82dfa5}.footcopy{min-width:0;flex:1}.foot-title{font-size:13px;font-weight:600;color:#e9f3ec}.foot-note{margin-top:3px;font-size:12px;color:#a3b3a9}.arrow{flex:none;color:#82dfa5}.fallback{display:inline-flex;align-items:center;min-height:44px;margin:8px 0 0 46px;color:#9db1a5;font-size:12px;text-decoration:underline;text-underline-offset:3px}
    .footer{text-decoration:none}.footer:hover .foot-title{color:#fff}.footer:focus-visible{outline:2px solid #79e5a6;outline-offset:3px;border-radius:8px}
    @media(max-width:420px){body{padding:14px}main{padding:16px;border-radius:20px}.top{grid-template-columns:88px minmax(0,1fr);gap:14px}.cover{width:88px;height:88px;border-radius:13px}.eyebrow{font-size:9px;letter-spacing:.09em}.title{font-size:18px}.meta{font-size:13px}.listen{font-size:13px;margin-top:7px}.divider{margin:13px 0}}
    @media(prefers-reduced-motion:no-preference){main{animation:enter .2s ease-out}@keyframes enter{from{opacity:.7;transform:scale(.985)}to{opacity:1;transform:scale(1)}}}
  </style>
</head>
<body><main>
  <section class="top" aria-label="Canción compartida">
    <img class="cover" src="${safeCover}" alt="Portada de ${safeTitle}" width="110" height="110">
    <div class="copy"><p class="eyebrow">SOUNDNEED · CANCIÓN COMPARTIDA</p><h1 class="title">${safeTitle}</h1>
      <p class="meta">${safeArtist}${album ? `<br><span class="album">${safeAlbum}</span>` : ""}</p>
      <a class="listen" href="${safeDeepLink}" aria-label="Escuchar ${safeTitle} en SoundNeed">Escuchar canción <span aria-hidden="true">→</span></a>
    </div>
  </section>
  <div class="divider"></div>
  <a class="footer" href="${safeDeepLink}" aria-label="Abrir ${safeTitle} en SoundNeed"><span class="linkicon" aria-hidden="true"><svg width="18" height="18" viewBox="0 0 24 24" fill="none"><path d="M10 13.5a5 5 0 0 0 7.1 0l2.1-2.1a5 5 0 0 0-7.1-7.1l-1.2 1.2M14 10.5a5 5 0 0 0-7.1 0l-2.1 2.1a5 5 0 0 0 7.1 7.1l1.2-1.2" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg></span>
    <span class="footcopy"><span class="foot-title">Compartido desde SoundNeed</span><span class="foot-note">Escúchala en SoundNeed.</span></span>
    <span class="arrow" aria-hidden="true"><svg width="20" height="20" viewBox="0 0 24 24" fill="none"><path d="m9 18 6-6-6-6" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg></span>
  </a>${fallbackAction}
</main></body></html>`;
};

export async function onRequest({ env, params, request }) {
  const id = String(params.id || "");
  const song = await getSong(env, id);
  if (!song) return new Response("No encontramos esta canción compartida.", { status: 404 });

  const origin = new URL(request.url).origin;
  const extension = song.cover_type === "image/png" ? "png" : song.cover_type === "image/webp" ? "webp" : "jpg";
  const coverUrl = `${origin}/cover/${encodeURIComponent(id)}.${extension}`;
  const html = page({ ...song, coverUrl, pageUrl: `${origin}/s/${encodeURIComponent(id)}` });
  return new Response(html, {
    headers: {
      "content-type": "text/html; charset=utf-8",
      "cache-control": "public, max-age=300, s-maxage=300",
      "x-content-type-options": "nosniff",
      "referrer-policy": "strict-origin-when-cross-origin",
    },
  });
}
