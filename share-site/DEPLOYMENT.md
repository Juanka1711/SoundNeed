# Enlaces compartidos de SoundNeed

Los enlaces nuevos se sirven desde Cloudflare Pages en `https://soundneed-links.pages.dev`. El Worker en modo avanzado guarda las canciones y playlists compartidas en la base D1 y entrega páginas con metadatos Open Graph para WhatsApp. Al instalar SoundNeed, Android verifica el host con `/.well-known/assetlinks.json` y abre los enlaces compatibles directamente en la app.

## Publicar el proyecto

La configuración de Pages está en `../wrangler.pages.jsonc`; reutiliza la base `soundneed-shares`. El proyecto `soundneed-links` ya está publicado en `https://soundneed-links.pages.dev`.

Para una instalación nueva, crea el proyecto Pages clásico con una rama de producción:

```powershell
pnpm dlx wrangler@3.114.17 pages project create soundneed-links --production-branch main
```

Para desplegarlo, Wrangler Pages requiere que su configuración se llame `wrangler.jsonc` en el directorio de trabajo. Como la raíz de este repositorio ya tiene una configuración de Worker con ese nombre, prepara una copia temporal antes de desplegar:

```powershell
$stage = Join-Path $env:TEMP ("soundneed-pages-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $stage | Out-Null
Copy-Item -LiteralPath "share-site" -Destination (Join-Path $stage "share-site") -Recurse
Copy-Item -LiteralPath "wrangler.pages.jsonc" -Destination (Join-Path $stage "wrangler.jsonc")
Push-Location $stage
try {
    pnpm dlx wrangler@3.114.17 pages deploy share-site --project-name soundneed-links
} finally {
    Pop-Location
}
Remove-Item -LiteralPath $stage -Recurse -Force
```

Se fija Wrangler 3 para conservar el host `pages.dev`; Wrangler 4 despliega el flujo actualizado de Workers con un host `workers.dev` que incluye el subdominio de la cuenta.

El Worker anterior en `soundneed-shares.breinermuleth64.workers.dev` se conserva para que los enlaces enviados anteriormente sigan funcionando. Despliega también la ruta de asociaciones Android en ese host:

```powershell
pnpm dlx wrangler deploy
```

Si la base D1 aún no tiene las tablas, inicialízala con:

```powershell
pnpm dlx wrangler d1 execute soundneed-shares --remote --file=share-site/schema.sql
```

Para una base existente, aplica las migraciones faltantes en orden desde `share-site/migrations/` antes de publicar.

## Crear enlaces

La app envía canciones a `/api/share` y playlists, incluida **Me gusta**, a `/api/playlist`. Las respuestas generan enlaces cortos `/s/<id>` y `/p/<id>`. Las rutas sirven el HTML completo desde la primera respuesta para que WhatsApp pueda construir la vista previa.

Si se cambia el host público, actualiza `lib/services/soundneed_share_links.dart`, `android/app/src/main/AndroidManifest.xml` y `android/app/src/main/kotlin/com/example/music_player/MainActivity.kt`. Publica `/.well-known/assetlinks.json` en cada host para mantener el App Link verificado.

## Límites y datos

- El servidor acepta portadas y tarjetas JPEG, PNG o WebP hasta 450 KB.
- Las playlists guardan el nombre, las canciones compactadas y una imagen con las cuatro primeras portadas.
- Los enlaces usan identificadores aleatorios y no contienen título, artista ni portada en la URL.
- Los enlaces se conservan en D1 y no tienen fecha de caducidad configurada.
- Sin la app instalada, el enlace mantiene la página web de SoundNeed para abrir o importar el contenido.
