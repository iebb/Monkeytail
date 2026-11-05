<p align="center"><img src="docs/brand/monkeytail-banner.png" alt="Monkeytail — HTTP y cURL para iPhone, iPad y Mac de Kitta Co" width="880"></p>

# Monkeytail

[English](README.md) · **Español** · [Français](README.fr.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [简体中文](README.zh-Hans.md)

**Un depurador de solicitudes nativo para iPhone, iPad, Mac y visionOS, con una app complementaria compacta para Apple Watch.** Importa un comando, edita la solicitud e inspecciona la respuesta. Creado con SwiftUI, con un editor compacto para iPhone y un espacio de trabajo de escritorio adaptable.

Gratis. Sin compras dentro de la app. Sin cuenta. Kitta Co no recopila ningún dato.

[Producto](https://docs.kitta.co/monkeytail/) · [Privacidad](https://docs.kitta.co/monkeytail/privacy/) · [Soporte](https://docs.kitta.co/monkeytail/support/) · [Herramientas de API](docs/APITools.md) · [Scripts](docs/Scripting.md) · [Perfiles de navegador](docs/BrowserProfiles.md) · [Configuración de publicación](docs/Release.md)

<p><img src="docs/screenshots/iphone-request.png" alt="Editor de solicitudes de Monkeytail en iPhone con cabeceras en línea" width="285"> <img src="docs/screenshots/iphone-response.png" alt="Visor de respuestas JSON de Monkeytail en iPhone" width="285"></p>

Consulta los [resultados de verificación y las capturas de pantalla en dispositivos](docs/Verification.md). Se incluyen [espacios de trabajo de ejemplo](docs/examples) importables para Monkeytail, Postman e Insomnia.

## Ejecución

Abre **`Monkeytail.xcodeproj`**. Selecciona **Monkeytail** para iPhone/iPad, **MonkeytailMac** para Mac, **MonkeytailVision** para visionOS o **MonkeytailWatch** para la app complementaria del Watch. Requiere iOS 17, macOS 14, visionOS 1 o watchOS 10; la importación de certificados de cliente en Mac requiere macOS 15. Las compilaciones y la verificación usan Xcode 27. Elige tu equipo de firma para dispositivos físicos y para las compilaciones de Mac con iCloud. Las compilaciones Debug de Mac usan entitlements de sandbox independientes para pruebas locales ad hoc; Release activa el contenedor compartido de iCloud.

El proyecto de Xcode generado está incluido en el repositorio. Si cambias los ajustes de los targets en `project.yml`, vuelve a generarlo con [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```sh
xcodegen generate
```

La colección inicial usa httpbin.org. Las solicitudes solo se envían cuando tocas **Enviar** o usas el atajo de teclado de envío. Sustituye `base_url` en el entorno Playground para usar tu propio servidor.

## Incluye

- Editor de solicitudes nativo: métodos, URL, variables de ruta `:name`, cabeceras y parámetros de consulta activables y desactivables con edición en bloque al estilo de Postman, cuerpos JSON/texto/URL-encoded/multipart y subida de archivos binarios, autenticación heredada, bearer/basic/Digest, claves de API, firma OAuth 1.0, JWT Bearer (HS/RS/PS/ES 256–512, firmado localmente en cada envío, en una cabecera o un parámetro de consulta), OAuth 2.0 con PKCE y renovación, AWS SigV4, tiempo de espera y redirecciones.
- Importación y exportación de cURL, incluidos el entrecomillado de shell, los comandos multilínea, los datos, JSON, las cookies, la autenticación basic y `--digest`, y la selección de proxy. El importador analiza texto; nunca invoca un shell.
- Colecciones y carpetas anidadas con cabeceras, autenticación, variables y scripts heredados; añadir, renombrar, duplicar, eliminar, buscar y guardado local automático. La sincronización con iCloud Drive está activada de forma predeterminada y usa la sesión existente del dispositivo; no hay cuenta de Monkeytail.
- Entornos con nombre, variables globales del espacio de trabajo y sustitución de `{{variable}}` en todas las partes de la solicitud; variables anidadas con detección de variables ausentes y de ciclos, además de variables dinámicas de Postman como `{{$guid}}`, `{{$timestamp}}` y `{{$randomEmail}}`. Los valores resueltos aparecen bajo la URL, y al escribir `{{` se sugieren variables.
- Ejecutor de colecciones y carpetas: iteraciones, retardo, archivos de datos CSV/JSON, `pm.execution.setNextRequest`/`skipRequest`, resultados de éxito/fallo en directo y exportación de informes en JSON o JUnit. Se ejecuta localmente; sin cuenta ni ejecutor en la nube.
- Transporte HTTP real, cancelación, compartición de respuestas y diagnósticos por salto de DNS/conexión/TLS/subida/servidor/descarga, con las cabeceras que informa el transporte y los cuerpos enviados acotados.
- [Perfiles TLS y HTTP/2 de navegador](docs/BrowserProfiles.md) opcionales para Chrome, Firefox y Safari, incluidos preajustes de iOS y Android en iOS y Mac. visionOS usa el TLS del sistema; la biblioteca de navegador fijada no tiene versión para visionOS. Se ejecuta localmente con una versión fijada de curl-impersonate; la verificación de certificados sigue activada.
- Formato legible de JSON, minificación en la biblioteca principal, colores de sintaxis, árbol desplegable, búsqueda por líneas, copia y formato del cuerpo de la solicitud.
- Vistas previas de imágenes según el tipo MIME con zoom por pellizco, reproducción nativa de audio y vídeo, y visores Hex (con desplazamiento y ASCII) y binario. Los archivos multimedia no compatibles se pueden inspeccionar como bytes o guardar.
- Hooks locales de JavaScript antes de la solicitud y después de la respuesta, con un subconjunto de `pm` compatible con Postman: `pm.expect` al estilo de Chai, `pm.response.to.*`, `pm.sendRequest`, variables de entorno/colección/globales, cookies, CryptoJS integrado, subconjuntos de lodash y moment, y registros de consola. Los scripts se ejecutan en cada envío, incluidos los importados.
- Redes del sistema o proxies HTTP CONNECT personalizados, HTTPS CONNECT envueltos en TLS y SOCKS5, con credenciales opcionales y sin recurrir a la conexión directa cuando falla un proxy personalizado.
- Importación de OpenAPI/Swagger en JSON y YAML con indicaciones de parámetros, ejemplos y validación portátil de JSON Schema.
- Edición de consultas, variables y operaciones de GraphQL, introspección y sugerencias de campos del esquema con búsqueda.
- Cronologías de WebSocket y SSE con inspección de texto/JSON/binario, filtros, ping, cancelación y reconexión.
- Almacenes de cookies locales del dispositivo por entorno, identidades de cliente PKCS#12 por host exacto y confianza por host para certificados autofirmados (fijados por huella SHA-256 en lugar de desactivar la verificación). Los diagnósticos del transporte del sistema muestran la cadena de certificados, la validez, los identificadores negociados de TLS/cifrado y el protocolo.
- Aserciones visuales de estado/tiempo/cabecera/JSONPath/esquema, resultados de éxito/fallo y comprobaciones de JavaScript editables.
- Fragmentos de código para cURL, JavaScript fetch, Node.js axios, Python requests, Go, Java HttpClient, C# HttpClient, PHP cURL, Ruby Net::HTTP, Swift URLSession, Kotlin OkHttp, HTTPie y PowerShell, con ocultación opcional de credenciales.
- Ejemplos de respuesta guardados por solicitud (ejemplos `response` de Postman), simulaciones de respuesta sin conexión a partir de ejemplos, respuestas actuales o instantáneas, retardos/estados/errores, y un servidor de simulación local en loopback que funciona en primer plano.
- Pestañas de solicitudes en Mac y iPad, restauradas al volver a abrir la app, documentación en Markdown para solicitudes, carpetas y colecciones, y una vista previa de respuestas HTML en sandbox.
- Importación desde Postman (colecciones v1, v2/v2.1, entornos, variables globales y volcados de datos completos), Insomnia (v4 JSON/YAML y v5 YAML), Bruno (carpetas `.bru` y exportaciones JSON), Hoppscotch, Thunder Client, HAR, archivos `.http` de VS Code REST Client/JetBrains, OpenAPI y cURL. Puedes elegir varios archivos o una carpeta entera a la vez.
- Importación directa desde otra app: inicia sesión en Postman, Insomnia o Hoppscotch igual que lo hacen sus propias apps y trae tus colecciones sincronizadas, o conecta un repositorio de GitHub. Se importan todas las colecciones, entornos y variables globales. Las sesiones y los tokens se usan solo para esa importación y nunca se guardan; Monkeytail sigue sin tener cuenta.
- Exportación de colecciones Postman v2.1 y exportación Insomnia v4 JSON. La versión actual de Insomnia puede importar este formato heredado.
- Importación y exportación completas del JSON del espacio de trabajo de Monkeytail, integración con Archivos y la hoja para compartir del sistema.
- Instantáneas de respuesta guardadas con búsqueda, comparación de JSON/estado/cabeceras y extracción con JSONPath (`$`, claves, índices, comodines). Las instantáneas se quedan en el dispositivo y se conservan como máximo 50 entradas dentro de 60 MB.
- Historial con las últimas 50 definiciones de solicitudes, con estado y tiempos; se restauran sin reenviarse automáticamente.
- Apariencias clara y oscura, Dynamic Type, etiquetas de VoiceOver, atajo de envío con teclado físico (⌘↵) y diseños adaptables en vertical y horizontal.

## Diseños por dispositivo

La barra lateral funciona como en Postman: un selector de espacios de trabajo en la parte superior y, debajo, todas las colecciones de ese espacio de trabajo como un árbol de carpetas y solicitudes anidadas. Cada espacio de trabajo tiene sus propias colecciones, entornos y variables globales, y los datos existentes están en **Mi espacio de trabajo**. Mueve solicitudes y carpetas con **Mover a** o arrastrándolas, y añade una carpeta desde **+** o desde el menú de cualquier colección, carpeta o solicitud. La interfaz está disponible en inglés, español, francés, japonés, coreano y chino simplificado, y sigue el idioma del dispositivo.

Los colores siguen el sistema de diseño de forma predeterminada. **Ajustes → Tema y tipos de letra** ofrece seis preajustes (Monkeytail, Navy, Ocean, Ember, Grape, Graphite), una apariencia Sistema/Clara/Oscura y colores claros y oscuros por función para el acento, el lienzo, la superficie, la advertencia, el peligro, la información, otros métodos y los errores. También puedes elegir tipos de letra distintos para la interfaz y el código entre los instalados en el dispositivo. Los temas se guardan en el dispositivo y se aplican a todas las ventanas de inmediato.

En iPhone, el método y la URL permanecen visibles sobre un editor compacto. **Enviar/Cancelar** y **Solicitud/Respuesta** se quedan en la parte inferior, al alcance del pulgar, y se colocan sobre el teclado mientras editas. Los nombres y valores de cabeceras y parámetros comparten una fila con controles de 44 puntos. En un teléfono, las pestañas de la respuesta se contraen mientras escribes una búsqueda para que las líneas coincidentes sigan visibles sobre el teclado. La ayuda opcional está contraída, y los nombres de las solicitudes se pueden editar directamente en la barra de navegación. La opción para compartir cURL está en el menú de acciones.

El diseño se adapta al **tamaño de ventana disponible**:

| Espacio disponible | Diseño |
| --- | --- |
| Teléfono estrecho / ventana plegada | Selector Solicitud/Respuesta en la parte inferior; colecciones mediante el botón atrás/barra lateral |
| Área de detalle del iPad de al menos 640 × 440 puntos | Solicitud y respuesta una al lado de la otra |
| Ventana de teléfono en horizontal de poca altura | Un solo panel para que el editor siga siendo usable |
| Ventana de al menos 1.100 puntos | Barra lateral de colecciones más paneles de solicitud y respuesta |
| Plegable entreabierto, con el pliegue atravesando la pantalla (modo mesa) | Respuesta sobre la bisagra; URL, Enviar y editor de solicitudes debajo. Nada cruza el pliegue |
| Tamaños de texto de accesibilidad | Editor de un solo panel para mantener el texto legible |

La selección y el estado del editor se conservan al cambiar el ancho, al girar el dispositivo, al redimensionar ventanas en el iPad y al cambiar el tamaño de un plegable. En iOS 27.1 y posteriores, el diseño en modo mesa sigue a `UIHingeInteraction` (parcialmente abierto) y a la región reservada `.division` del sistema, de modo que la división queda justo sobre el pliegue indicado, con 7 puntos de margen a cada lado. Si la bisagra está plana o cerrada, o el pliegue no es horizontal, se aplican los diseños habituales.

## App complementaria para Apple Watch

Marca una solicitud como favorita en el menú de acciones del iPhone. Abre **Apple Watch**, toca un favorito para copiarlo y luego toca **Sincronizar** cuando la app emparejada esté instalada. El Watch muestra hasta diez copias: abre una y toca **Enviar** o **Cancelar**, y después inspecciona el estado, el tiempo, las cabeceras o el texto Pretty/Raw/Hex. En el Watch no hay editor de solicitudes ni consultas automáticas periódicas.

El entorno seleccionado y las cabeceras y la autenticación heredadas se resuelven al copiar. **Incluir credenciales y cuerpo** es una opción guardada y está activada salvo que la hayas desactivado. Las copias usan archivos locales de forma predeterminada, almacenamiento opcional en el llavero y el contexto de aplicación más reciente de WatchConnectivity. Si editas una solicitud o cambias de entorno, tienes que volver a copiarla; Sincronizar elimina las copias que ya no son favoritas. El Watch hace su propia solicitud HTTP, así que el servidor debe ser accesible desde el Watch. Las respuestas se quedan en memoria. La transferencia entre dispositivos físicos emparejados todavía debe verificarse en hardware.

El Watch admite HTTP/GraphQL del sistema, HTTPS verificado y cabeceras manuales basic/bearer/clave de API. Los proxies, los preajustes TLS de navegador, las identidades de cliente, las cookies, OAuth/JWT/AWS, los scripts, las simulaciones, WebSocket y SSE siguen disponibles solo en la app completa. Las configuraciones no compatibles producen un error antes de copiar. El tiempo de espera es de 30 segundos como máximo, un cuerpo copiado de 32 KB como máximo, la transferencia de 60 KB como máximo, una respuesta de 256 KB como máximo y un cuerpo mostrado de 16 KB como máximo.

La ventana de visionOS comparte con iPhone y Mac el editor completo del espacio de trabajo, los visores de respuestas, las herramientas de API y el contenedor de iCloud. Selecciona el TLS del sistema en visionOS; los preajustes TLS de navegador no están disponibles ahí. Los paquetes Swift exclusivos del sistema y del Watch enlazan las fuentes canónicas mediante enlaces simbólicos incluidos en el repositorio, lo que evita el binario de curl de iOS/Mac en plataformas no compatibles.

La versión 1.4 está disponible para iPhone/iPad con la app complementaria del Watch, Mac y visionOS. La versión 1.5 está pendiente de App Review en las tres plataformas. Consulta el [registro de publicaciones](docs/app-store/README.md) para ver las compilaciones y la validación. La transferencia a un Watch físico emparejado y la transferencia real por iCloud siguen sin verificarse.

En Mac, la solicitud y la respuesta se apilan de forma predeterminada en una división redimensionable. Elige **Acciones del espacio de trabajo → Disposición del espacio de trabajo** para colocarlas una al lado de la otra; la posición de la división se recuerda para cada disposición. La barra lateral permanece abierta al redimensionar hasta que la ocultes. Los ajustes se abren en la ventana nativa de Ajustes. Usa ⌘F para buscar una solicitud, ⇧⌘I para importar/exportar, ⇧⌘E para exportar cURL, ⌘N para una nueva solicitud y ⌘Retorno para enviar o cancelar.

## Alcance de la interoperabilidad

El JSON del espacio de trabajo de Monkeytail conserva todos los campos del modelo, los entornos y los ajustes de proxy. Las importaciones añaden colecciones y entornos y generan ID nuevos; las importaciones nativas también aplican sus ajustes de proxy guardados. Los scripts importados se ejecutan al enviar, como en Postman; revísalos en cada pestaña Scripts o desactiva **Ejecutar scripts** para omitirlos.

La exportación a Postman conserva las carpetas anidadas y exporta el **entorno activo** como variables de colección. Las importaciones de Postman conservan la jerarquía de carpetas y las cabeceras, la autenticación, las variables y los scripts heredados. Se admiten cuerpos raw, URL-encoded, multipart, de archivo y JSON de GraphQL. Los scripts se conservan; la ejecución admite las API documentadas en [Scripts](docs/Scripting.md).

Las exportaciones JSON/YAML de Insomnia v4 y las colecciones YAML v5 se importan con su árbol de carpetas. El entorno base se convierte en variables de colección, los subentornos en entornos, y los entornos, cabeceras, autenticación y scripts de carpeta en valores predeterminados de la carpeta. Las referencias `{{ _.variable }}` y `{{ _['variable'] }}` se normalizan. Las etiquetas de plantilla (como el encadenamiento de respuestas) generan un aviso y se mantienen como texto; las solicitudes gRPC se omiten.

Las carpetas de colecciones de Bruno (`bruno.json`, `collection.bru`, `folder.bru`, `environments/`) y las exportaciones JSON conservan las carpetas, los valores predeterminados, las variables de entorno secretas, los scripts y las aserciones (convertidas en tests). Las colecciones y los entornos de Hoppscotch convierten las referencias `<<variable>>` y conservan todos los tipos de autenticación. Las colecciones de Thunder Client convierten sus tests declarativos en scripts. Los archivos HAR agrupan las solicitudes por host y conservan las respuestas grabadas como ejemplos guardados. Los archivos `.http`/`.rest` conservan `@variables`, `# @name`, los cuerpos y los controladores de respuesta `> {% %}`. Los scripts importados escritos para estos clientes se ejecutan con objetos de compatibilidad; consulta [Scripts](docs/Scripting.md#other-clients).

Importar → **Importar desde Postman, Insomnia, Hoppscotch o GitHub**:

- **Postman:** Monkeytail inicia sesión igual que la app de escritorio de Postman. **Iniciar sesión en Postman** muestra la propia página de inicio de sesión de Postman en una sesión de navegador privada (correo y contraseña, GitHub o SSO) y lee la sesión de la redirección con la que termina. Después, Monkeytail muestra tus espacios de trabajo a través del gateway de Postman y trae las colecciones, los entornos y las variables globales de cada espacio de trabajo seleccionado desde el servicio de sincronización de Postman, en el formato v1 que guarda la app de escritorio. Se admiten cuentas de EE. UU. y de la UE. Cuando se importan varios espacios de trabajo, los entornos llevan delante el nombre de su espacio de trabajo.
- **Insomnia:** Monkeytail inicia sesión igual que la app de escritorio de Insomnia. **Iniciar sesión en Insomnia** abre el sitio web de Insomnia con una clave de un solo uso; pega el código que muestra. Monkeytail abre la caja sellada de inicio de sesión, desbloquea las claves de cifrado de extremo a extremo de la cuenta, muestra los proyectos de Cloud Sync de todas las organizaciones y trae la instantánea más reciente de la rama predeterminada de cada proyecto seleccionado. Los documentos se descifran en el dispositivo. Los proyectos locales y de Git Sync no están en la nube de Insomnia; usa la opción de GitHub o exporta un archivo.
- **Hoppscotch:** introduce tu correo electrónico para recibir un enlace de inicio de sesión y pega el enlace sin abrirlo. En hoppscotch.io es el inicio de sesión por enlace de correo de la app web; en un servidor autoalojado (introduce la URL de su backend) es el enlace mágico de la app de escritorio. Se importan las colecciones y los entornos personales, las variables globales y las colecciones y los entornos de todos los equipos; los entornos de equipo llevan delante el nombre del equipo.
- **GitHub:** introduce `owner/repo`, `owner/repo@branch` o la URL de una carpeta (`…/tree/branch/folder`). Se importan todos los archivos de Postman, Insomnia Git Sync, Bruno, Thunder Client, Hoppscotch, `.http`, HAR y OpenAPI, y cada colección de Bruno se decodifica respecto a su propio `bruno.json`. Los repositorios públicos no necesitan token; para los privados, usa un token detallado de solo lectura. Se importan como máximo 1.000 archivos y 40 MB.

Bruno y Thunder Client guardan las colecciones como archivos o en Git. Las credenciales y las sesiones se envían solo al servicio elegido a través de una sesión efímera, sin cookies ni caché, y se descartan después de la importación.

Los formatos de terceros no conservan todos los ajustes de Monkeytail, como los tiempos de espera de las solicitudes o la selección global de proxy. La autenticación no compatible genera un aviso de importación; los parámetros de cURL no compatibles producen un error explícito. Las rutas de archivo importadas son solo metadatos: elige cada archivo con Archivos o Fotos antes de enviar. Las exportaciones nativas del espacio de trabajo incluyen los bytes de los archivos; las exportaciones de Postman/Insomnia/cURL hacen referencia a los nombres de archivo. Usa Cuerpo → Exportar archivo para transferir los adjuntos reales junto con las exportaciones de terceros. gRPC, las cuentas y los espacios de trabajo de equipo, los monitores y simulaciones en la nube, y los entornos de ejecución de scripts completos de otros clientes quedan fuera de esta versión; Monkeytail nunca exige iniciar sesión. La importación de OpenAPI y la validación de JSON Schema tienen subconjuntos admitidos explícitos; consulta [Herramientas de API](docs/APITools.md).

Los perfiles de navegador se conservan en ambos sentidos a través del JSON nativo y de los comandos `curl-impersonate --impersonate`. Las exportaciones de Postman e Insomnia incluyen metadatos `_monkeytail` para volver a importarlas en Monkeytail; esas apps no aplican por sí mismas los perfiles de navegador.

## Datos y red

El espacio de trabajo y el historial se guardan en el directorio Application Support de la app y usan la protección de archivos de la plataforma y el sandbox de apps de Mac. Las credenciales del espacio de trabajo y el historial usan archivos locales de forma predeterminada. **Usar el llavero** es opcional y se aplica a las credenciales del espacio de trabajo, las cookies, las identidades de cliente y las copias del Watch. Con esa opción desactivada, no se hace ninguna consulta al llavero al iniciar la app. Los valores antiguos del llavero no se tocan y se pueden restaurar activando la opción; las exportaciones incluyen los valores guardados. No hay analítica ni backend gestionado por Kitta. La sincronización con iCloud Drive está activada de forma predeterminada, y la versión 1.6.3 la activa una vez en las instalaciones existentes (desactiva **Sincronización con iCloud** en Ajustes para mantener los datos solo en local). Comparte colecciones, entornos, scripts y credenciales entre tus dispositivos, combina cada entidad según su edición más reciente y conserva marcas de eliminación. Las ediciones de solicitudes distintas sobreviven a los cambios simultáneos; para una misma entidad, gana la edición más reciente. Antes de aplicar cambios remotos se guarda una copia local protegida de recuperación. La app se puede usar sin conexión, y la sincronización comprueba si hay cambios mientras está activa y al pasar a primer plano. **Incluir credenciales** determina si los campos de autenticación y de credenciales se incluyen en la sincronización con iCloud; está activada salvo que la hayas desactivado, así que todo se sincroniza de forma predeterminada. Las cookies, las identidades de cliente, los adjuntos, las instantáneas y el historial de solicitudes se quedan en el dispositivo. Los campos como `Authorization` o `X-API-Key` no se marcan como confidenciales automáticamente y siguen visibles; **Marcar como confidencial** oculta un valor. Con **Incluir credenciales** desactivado, **Usar el llavero** activado o la ocultación en el código activada, los nombres que parecen credenciales siguen protegidos salvo que se marquen como normales. Los scripts importados o sincronizados requieren una aceptación explícita en cada dispositivo. Para cambiar la sesión de iCloud del dispositivo hay que desactivar y volver a activar la sincronización. Los cuerpos de respuesta se quedan en memoria hasta que se guardan explícitamente como instantáneas o se exportan; las vistas previas de audio y vídeo usan archivos temporales protegidos que se eliminan cuando se libera su respuesta en caché. Los archivos que deja una sesión interrumpida se limpian al iniciar la app después de un día. Al guardar explícitamente se exportan los bytes originales. Las cookies se activan por solicitud, con almacenes locales del dispositivo independientes para cada entorno. Las sesiones nunca usan las cookies de Safari. OAuth abre el proveedor en una sesión de navegador efímera; no crea una cuenta de Monkeytail. Las identidades de cliente se quedan en el dispositivo, en archivos o en el almacenamiento opcional del llavero. El servidor de simulación solo escucha en 127.0.0.1 y se detiene cuando la app pasa a segundo plano. La verificación de confianza TLS sigue activada; instala y marca como de confianza una CA de depuración en los Ajustes de iOS cuando sea necesario. ATS permite HTTP porque esta app es un cliente general de API y depuración.

Las respuestas están limitadas a 20 MB; las vistas previas de texto/árbol y de bytes, a 1 MB. Las imágenes se decodifican en una vista previa de 2.048 píxeles como máximo; al guardar se conserva el original. La reproducción de audio y vídeo usa solo el archivo descargado, con las referencias a contenido multimedia externo desactivadas. El formato de JSON, la preparación del árbol y la división en líneas se ejecutan fuera del hilo principal. Las filas de texto y de árbol se renderizan de forma diferida, los arrays de líneas se reutilizan durante la búsqueda y el resaltado de sintaxis usa una sola expresión compilada con un límite de longitud para las líneas largas. La caché de respuestas conserva hasta 8 respuestas dentro de 40 MB. Las importaciones están limitadas a 40 MB; las subidas, a 20 MB; los metadatos de iCloud, a 20 MB. JSONPath y las diferencias de JSON funcionan con cuerpos de hasta 2 MB, con límites de nodos y de cambios. Los contextos de JavaScript tienen un plazo de tres segundos, usan un almacén de datos efímero de WebKit y bloquean el acceso directo a la red y la navegación del DOM. Su único puente nativo es `pm.sendRequest`, limitado a 10 solicitudes HTTP(S) por script a través del proxy seleccionado; no hay puente a archivos ni a la app. Un contexto que supera el tiempo de espera se descarta. Los scripts son una API de conveniencia, no un entorno de ejecución general de Node.js.

## Verificación

Tests puros de modelos, analizadores, colecciones, codificación, JSON, configuración de proxy, multipart, combinación/marcas de eliminación/secretos de la sincronización, JSONPath y comparación de respuestas:

```sh
swift test
```

Los tests de integración en el simulador y los tests de interfaz usan fixtures locales de HTTP, TLS/HTTP2, CONNECT y SOCKS5, sin depender de API públicas:

```sh
./Scripts/test.sh 'platform=iOS Simulator,name=iPhone Duo'
# Or pass another installed simulator destination, e.g.:
./Scripts/test.sh 'platform=iOS Simulator,name=iPhone 18 Pro,OS=27.0'
```

La batería de tests verifica el transporte, el ClientHello de TLS y los SETTINGS de HTTP/2 en la red, el rechazo de certificados, la sustitución de cabeceras del navegador, las redirecciones, la eliminación de credenciales entre orígenes, la cancelación, los límites, ambos protocolos de proxy, la modificación/aserciones/errores/tiempos de espera/bloqueo de red de los scripts, la persistencia en el llavero, el desalojo de instantáneas, las subidas multipart/binarias en ambos transportes, los diagnósticos por salto y un flujo de interfaz enviar → inspeccionar → importar → editar → exportar cURL en vertical y horizontal. Los tests de interfaz usan un espacio de trabajo temporal aislado y no modifican las colecciones normales del usuario.

## Estructura del proyecto

```text
Sources/MonkeytailCore/  Codable models, request builder, HTTP transport, cURL,
                        collection codecs, JSON formatting/tree
Sources/MonkeytailCurl/  Small C bridge for the static browser transport
Vendor/                 Pinned curl-impersonate XCFramework and provenance
Monkeytail/Services/    Observable workspace/persistence and WebKit script runner
Monkeytail/Views/       Native adaptive SwiftUI interface
Tests/                 Core Swift package tests
MonkeytailMac/         Mac sandbox/iCloud entitlements and app metadata
MonkeytailMacTests/    Shared advanced hosted integration tests
MonkeytailVision/      Native visionOS app and shared iCloud entitlements
MonkeytailWatch/       Compact favourite-request companion and WatchConnectivity
Packages/              System-only visionOS and bounded Watch core packages
MonkeytailTests/       Hosted simulator integration tests
MonkeytailUITests/     End-to-end device UI tests
Scripts/               Local verification and network fixtures, samples, icon packaging
docs/                  Scripting, release metadata, branding, screenshots
```

Referencias de protocolos: [configuración de proxy de Apple](https://developer.apple.com/documentation/network/proxyconfiguration), [ejecución de JavaScript en WebKit](https://developer.apple.com/documentation/webkit/wkwebview/callasyncjavascript(_:arguments:in:in:completionhandler:)), [esquema de Postman](https://schema.postman.com/), [importación/exportación de Insomnia](https://developer.konghq.com/insomnia/import-export/).

## Licencia

Publicado bajo la [licencia BSD de 3 cláusulas](LICENSE). Las páginas públicas del producto, de soporte y de privacidad están alojadas en [docs.kitta.co](https://docs.kitta.co/monkeytail/).

Los componentes de terceros mantienen sus propias licencias; sus avisos se incluyen en Ajustes → Licencias. Consulta la [procedencia de los componentes de terceros](Vendor/README.md) para ver los binarios fijados y el procedimiento para regenerarlos.
