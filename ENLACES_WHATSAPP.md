# Enlaces compartidos de SoundNeed

Los enlaces nuevos de canciones, playlists y **Me gusta** usan `https://soundneed-links.pages.dev`. Cuando SoundNeed está instalada, Android verifica el host con `/.well-known/assetlinks.json` y abre las rutas compatibles directamente dentro de la app. Sin la app, el enlace conserva su página web para mostrar la vista previa y permitir abrir o importar el contenido.

La configuración de Cloudflare Pages, el Worker y la base D1 está documentada en [share-site/DEPLOYMENT.md](share-site/DEPLOYMENT.md). Los enlaces anteriores de `soundneed-shares.breinermuleth64.workers.dev` se mantienen compatibles.
