# Enlaces de canciones para WhatsApp

SoundNeed comparte un enlace de GitHub Pages (`https://juanka1711.github.io/SoundNeed/share.html?...`). La página intenta abrir `soundneed://track/...`; Android abre la canción si SoundNeed está instalada. Si el salto automático se bloquea, el usuario toca **Abrir en SoundNeed**. Si no tiene la app, puede escuchar la canción en YouTube cuando hay un ID disponible.

## Activar la página una sola vez

En GitHub, abre `Juanka1711/SoundNeed` → **Settings → Pages** y selecciona **GitHub Actions** como origen de publicación. Después publica el workflow `.github/workflows/deploy-share-page.yml` en `main`; GitHub Actions desplegará `share-site/` y la página quedará en:

`https://juanka1711.github.io/SoundNeed/share.html`

No requiere Firebase, dominio propio ni archivo de asociación de Android. El enlace usa un esquema propio de SoundNeed y la página web sirve de puente para lanzarlo.
