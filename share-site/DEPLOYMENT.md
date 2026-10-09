# Enlaces de canciones de SoundNeed

La página pública corre en Cloudflare Workers con archivos estáticos y D1. El Worker guarda la canción compartida y sirve desde la primera respuesta el HTML con metadatos Open Graph que WhatsApp puede leer.

## Configuración de Cloudflare

La configuración del proyecto está en `../wrangler.jsonc`. El binding `DB` conecta la base `soundneed-shares`, y `ASSETS` sirve los archivos estáticos de esta carpeta.

Para volver a desplegar después de iniciar sesión con Wrangler:

```powershell
pnpm dlx wrangler deploy
```

Para crear o actualizar la tabla en D1:

```powershell
pnpm dlx wrangler d1 execute soundneed-shares --remote --file=share-site/schema.sql
```

El Worker está publicado en `https://soundneed-shares.breinermuleth64.workers.dev`. La app ya usa este origen de forma predeterminada; si más adelante cambias el dominio, puedes sobrescribirlo al compilar:

```powershell
flutter build apk --release --dart-define=SOUNDNEED_SHARE_BASE_URL=https://<tu-subdominio>.workers.dev
```

No pongas una ruta después del dominio. El APK envía título, artista, álbum y portada a `/api/share`; el servidor devuelve un enlace corto `/s/<id>`. Esa URL devuelve HTML con metadatos Open Graph, y `/cover/<id>.<formato>` sirve la portada para WhatsApp.

## Límites y datos

- El servidor acepta JPEG, PNG y WebP hasta 450 KB para mantener cada fila por debajo de los límites de D1.
- El enlace utiliza un identificador aleatorio, sin título, artista ni portada en la URL.
- Los enlaces se conservan en D1 y no tienen una fecha de caducidad configurada.
- La página abre la canción con el esquema `soundneed://`. Para canciones online también muestra una alternativa de YouTube cuando la app comparte esa URL.
- WhatsApp decide el aspecto de su propia vista previa. La página de destino y los metadatos Open Graph sí se controlan desde SoundNeed.

Hasta que el Worker esté publicado y el APK se compile con su origen público, la app no podrá crear enlaces dinámicos.
