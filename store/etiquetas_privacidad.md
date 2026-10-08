# Etiquetas de privacidad de la App Store (borrador para App Store Connect)

Ten presente que debes revisarlas contigo mismo antes de enviarlas: son una declaración tuya ante Apple.

**¿Se rastrea al usuario (tracking)?** No. Sin publicidad, sin analítica, sin SDK de terceros de seguimiento.

**Datos recopilados y vinculados a la cuenta anónima del dispositivo** (función de la app, no para publicidad):
- **Identificadores → ID de usuario:** cuenta anónima aleatoria creada en el servidor propio al compartir listas o aportar contenido.
- **Contenido del usuario → Otro contenido del usuario:** los productos de las listas compartidas y las compras guardadas en el servidor; y las fotos y productos que el usuario decide aportar a la base común.
- **Contenido del usuario → Fotos o vídeos:** solo si el usuario comparte una foto de producto.
- **Información de contacto → Nombre:** solo el alias que el usuario escribe para otros miembros de la lista (opcional).

**Datos que no se recopilan:** correo (la cuenta es anónima), teléfono, dirección, salud, finanzas, historial de navegación, contactos, diagnósticos (salvo que el usuario active los informes de errores; si se lanza esa opción, declarar «Datos de diagnóstico → Datos de fallos», no vinculados a la identidad si se envían sin cuenta, o vinculados si se envían con el ID).

**Ubicación:** la posición se usa en el dispositivo para ordenar tiendas cercanas y detectar la tienda actual. Para buscar tiendas, la app consulta OpenStreetMap (Overpass) con la zona aproximada: declarar «Ubicación aproximada → Funcionalidad de la app, no vinculada a la identidad» si Apple lo considera datos recopilados por un tercero.

**Clasificación por edades:** sin contenido objetable; existe contenido generado por usuarios moderado (fotos de producto). Respuesta típica: 4+ (o 12+ si Apple pide marcar «contenido generado por usuarios sin filtrar»; aquí hay moderación previa).

**Cifrado:** solo HTTPS estándar → `ITSAppUsesNonExemptEncryption = NO` (ya conviene añadirlo a Info.plist).
