<p align="center"><img src="docs/brand/monkeytail-banner.png" alt="Monkeytail" width="880"></p>

[English](README.md) · **Español** · [Français](README.fr.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [简体中文](README.zh-Hans.md)

# Monkeytail

**Un cliente de API nativo para iPhone, iPad, Mac y Apple Vision Pro. Trae tus colecciones de Postman e Insomnia, conserva tus scripts y olvídate de iniciar sesión.**

Monkeytail abre las colecciones que ya tienes y las ejecuta igual. No hay cuenta de Monkeytail, ni muro de inicio de sesión, ni espacio de trabajo en la nube, ni telemetría. Las solicitudes van directamente a tus servidores y tus datos se quedan en tus dispositivos o en tu propio iCloud Drive.

<p><img src="docs/screenshots/iphone-request.png" alt="Editor de solicitudes en iPhone" width="285"> <img src="docs/screenshots/iphone-response.png" alt="Respuesta JSON en iPhone" width="285"></p>

## Descargar

**[Descárgalo en el App Store](https://apps.apple.com/app/id6814706725)**: gratis y sin compras dentro de la app, para iPhone, iPad, Mac y Apple Vision Pro. Sitio web: [monk.ieb.app](https://monk.ieb.app)

## Si vienes de Postman o Insomnia

- **Importa todo.** Colecciones de Postman (v1, v2, v2.1), entornos, globales y exportaciones completas de datos; exportaciones de Insomnia v4 y v5; además de Bruno, Hoppscotch, Thunder Client, HAR, archivos `.http`, OpenAPI/Swagger y cURL. Elige varios archivos o una carpeta entera a la vez.
- **O tráelo directamente de la nube.** Inicia sesión una vez en Postman, Insomnia o Hoppscotch para traer tus espacios de trabajo sincronizados, o indica un repositorio de GitHub. La sesión solo se usa para esa importación y nunca se guarda.
- **Tus scripts siguen funcionando.** Los scripts previos a la solicitud y de pruebas se ejecutan con una API `pm` compatible con Postman, incluidos `pm.test`, `pm.expect`, `pm.sendRequest`, CryptoJS, lodash y moment. Los scripts de Insomnia, Bruno y otros clientes se ejecutan mediante objetos de compatibilidad.
- **La misma forma de trabajar.** Espacios de trabajo, colecciones y carpetas anidadas que heredan autenticación, encabezados, variables y scripts; entornos, globales y `{{variables}}`, incluidas las dinámicas como `{{$guid}}`.
- **Exporta cuando quieras.** Postman v2.1, Insomnia v4 o un archivo JSON de Monkeytail sin pérdidas.

## Qué más hace

- HTTP, GraphQL con introspección, WebSocket y eventos enviados por el servidor
- OAuth 2.0 con PKCE, OAuth 1.0, JWT, AWS Signature V4, Digest, claves de API, Basic y Bearer
- Un ejecutor de colecciones con iteraciones y archivos de datos CSV/JSON, que exporta informes JSON o JUnit
- Aserciones visuales, ejemplos guardados, simulaciones sin conexión y un servidor de simulación local
- Un visor de respuestas con JSON formateado, árbol, búsqueda, comparación, imágenes, audio, vídeo y hexadecimal
- Generación de código en 13 lenguajes, e importación y exportación de cURL
- Desglose de tiempos, detalles de TLS, proxies HTTP/HTTPS/SOCKS5, certificados de cliente y perfiles TLS de navegador opcionales
- Temas, colores y tipos de letra personalizados, en inglés, español, francés, japonés, coreano y chino simplificado
- Sincronización con tu propio iCloud Drive y una app complementaria para Apple Watch con tus solicitudes favoritas

Más información: [Herramientas de API](docs/APITools.md) · [Scripts](docs/Scripting.md) · [Perfiles de navegador](docs/BrowserProfiles.md) · [Espacios de trabajo de ejemplo](docs/examples)

## Compilar

Abre `Monkeytail.xcodeproj` en Xcode y ejecuta el esquema **Monkeytail** (iPhone y iPad), **MonkeytailMac** o **MonkeytailVision**. Requiere iOS 17, macOS 14 o visionOS 1. Después de editar `project.yml`, ejecuta `xcodegen generate`.

## Pruebas

```sh
swift test
```

## Licencia

[BSD 3-Clause](LICENSE)
