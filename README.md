# SoundNeed

SoundNeed es un reproductor de música multiplataforma construido con Flutter. Permite organizar música local, reproducir contenido en línea, gestionar playlists, consultar letras, descubrir artistas y compartir canciones o playlists mediante enlaces públicos.

## Funcionalidades

- Reproducción de música local con controles en segundo plano.
- Biblioteca organizada por canciones, álbumes, artistas, carpetas y playlists.
- Búsqueda y reproducción de resultados en línea.
- Letras sincronizadas o disponibles desde servicios externos cuando existen.
- Ecualizador, visualizador de audio y selección de salida Bluetooth/Cast.
- Widget y controles rápidos para Android.
- Compartir canciones y playlists mediante páginas públicas con tarjetas Open Graph.
- Descubrimiento de artistas, álbumes, podcasts y recomendaciones.

> El contenido de terceros debe utilizarse respetando sus licencias, derechos de autor y condiciones de servicio. La aplicación no debe presentarse como una herramienta para descargar contenido protegido sin autorización.

## Tecnologías

- Flutter y Dart.
- Android nativo con Kotlin.
- `just_audio` y `audio_service` para reproducción y segundo plano.
- `video_player` y `webview_flutter` para contenido audiovisual.
- Cloudflare Workers + D1 para enlaces compartidos.
- NewPipe Extractor para la resolución de contenido en Android.

## Requisitos

- Flutter con Dart SDK `^3.13.4`.
- Android Studio y Android SDK instalados.
- JDK compatible con la versión de Gradle del proyecto.
- Para probar funciones de Android: un dispositivo o emulador con los permisos necesarios.
- Para desplegar enlaces compartidos: cuenta de Cloudflare, Wrangler y una base D1 configurada.

## Instalación

```powershell
git clone https://github.com/Juanka1711/SoundNeed.git
cd SoundNeed
flutter pub get
```

Ejecutar en modo desarrollo:

```powershell
flutter run
```

Validar el proyecto:

```powershell
flutter analyze
flutter test
```

## Compilar Android

Para obtener un APK de prueba no se necesita una clave de producción:

```powershell
flutter build apk --debug
```

El resultado se genera en:

```text
build/app/outputs/flutter-apk/app-debug.apk
```

Para distribución, Google Play recomienda subir un Android App Bundle:

```powershell
flutter build appbundle --release
```

El identificador Android actual es `sound_need.music_player`.

### Firma de release

La firma release se configura de forma local mediante [android/key.properties.example](android/key.properties.example). Cada desarrollador debe crear su propio `android/key.properties`; este archivo no se debe subir al repositorio.

Ejemplo:

```properties
storePassword=TU_CONTRASEÑA
keyPassword=TU_CONTRASEÑA
keyAlias=soundneed
storeFile=C:/ruta/privada/soundneed-release.jks
```

El archivo `.jks` tampoco debe subirse. Para publicar actualizaciones de la misma aplicación se debe conservar la clave oficial de firma y protegerla en un gestor seguro o en CI/CD.

## Enlaces compartidos

La aplicación usa Cloudflare Pages, Workers y D1 para guardar metadatos, portadas y playlists compartidas. Los nuevos enlaces usan el host de marca `soundneed-links.pages.dev`. La configuración y los comandos de despliegue están en [share-site/DEPLOYMENT.md](share-site/DEPLOYMENT.md).

Para usar otro dominio al compilar:

```powershell
flutter build appbundle --release `
  --dart-define=SOUNDNEED_SHARE_BASE_URL=https://soundneed-links.pages.dev
```

El dominio debe incluir solo el origen HTTPS, sin una ruta adicional.

## Estructura principal

```text
lib/                         Código Flutter y lógica de la aplicación
lib/services/                Servicios de reproducción, búsqueda y compartir
lib/sections/                Secciones principales de la interfaz
lib/widgets/                 Widgets reutilizables
android/app/src/main/kotlin/ Integraciones nativas Android
assets/                      Audio e iconos incluidos en la aplicación
share-site/                  Worker, páginas y migraciones D1
test/                        Pruebas automatizadas
```

## Flujo de trabajo del equipo

1. Crear una rama para cada cambio.
2. No subir `android/local.properties`, `android/key.properties`, archivos `.jks`, logs, APKs ni carpetas generadas.
3. Ejecutar `flutter analyze` y `flutter test` antes de hacer commit.
4. Probar primero con `flutter build apk --debug`.
5. Usar la clave oficial solo para builds de release controlados.

## Estado del proyecto

El proyecto está en desarrollo. Antes de una publicación pública hay que completar la validación de la compilación release, la política de privacidad, el formulario de seguridad de datos, los metadatos de la tienda y la revisión de derechos sobre contenido y servicios de terceros.
