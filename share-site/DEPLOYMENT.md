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

Si la base ya tiene canciones compartidas, aplica también la tabla de playlists antes de desplegar:

```powershell
pnpm dlx wrangler d1 execute soundneed-shares --remote --file=share-site/migrations/0003_shared_playlists.sql
```

El Worker está publicado en `https://soundneed-shares.breinermuleth64.workers.dev`. La app ya usa este origen de forma predeterminada; si más adelante cambias el dominio, puedes sobrescribirlo al compilar:

```powershell
flutter build apk --release --dart-define=SOUNDNEED_SHARE_BASE_URL=https://<tu-subdominio>.workers.dev
```

No pongas una ruta después del dominio. La app envía los datos y una tarjeta propia de SoundNeed a `/api/share`; el servidor devuelve un enlace corto `/s/<id>`. Para playlists y “Me gusta”, envía el nombre, las canciones y una imagen compuesta con las cuatro primeras portadas a `/api/playlist`; el servidor devuelve `/p/<id>`. Ambas rutas sirven HTML con Open Graph desde la primera respuesta, para que WhatsApp pueda mostrar la tarjeta correcta.

## Límites y datos

- El servidor acepta portadas y tarjetas JPEG, PNG o WebP hasta 450 KB; las vistas previas se sirven como JPEG.
- Las playlists compartidas guardan el nombre, el recuento, la lista compacta de canciones y la imagen con las cuatro primeras portadas.
- El enlace utiliza un identificador aleatorio, sin título, artista ni portada en la URL.
- Los enlaces se conservan en D1 y no tienen una fecha de caducidad configurada.
- Las páginas de canción y playlist abren el contenido en SoundNeed mediante enlaces verificados y ofrecen una acción de apertura si se visitan desde un navegador.
- WhatsApp decide el aspecto de su propia vista previa. La página de destino y los metadatos Open Graph sí se controlan desde SoundNeed.

Hasta que el Worker esté publicado y el APK se compile con su origen público, la app no podrá crear enlaces dinámicos.
