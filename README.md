# Generador automático de procedimientos CRUD para PostgreSQL

Proyecto de Bases de Datos II — ITCR, Campus Tecnológico San Carlos.

Solución en dos partes:

- **Extensión PostgreSQL `crudgen`**: lee el catálogo del sistema (`pg_catalog`) y genera dinámicamente procedimientos almacenados CRUD para cualquier tabla, además de administrar los privilegios (`GRANT`/`REVOKE`) sobre ellos.
- **Aplicación Python de consola**: conecta a la base, verifica la extensión, permite elegir esquema, tablas, operaciones y roles, aplica la matriz de privilegios y permite ejecutar los procedimientos generados.

La aplicación no contiene lógica de generación: todo lo relacionado con la estructura de las tablas vive en la extensión. La app solo llama a sus funciones y muestra los resultados.

## Integrantes

| Nombre | Módulo |
|---|---|
| OMAR | Extensión: análisis de catálogo y funciones de listado |
| JEAN | Extensión: generación CRUD y privilegios |
| ANDRES | Aplicación Python |

## Contenido

1. [Estructura del repositorio](#estructura-del-repositorio)
2. [Requisitos](#requisitos)
3. [Instalación de la extensión](#instalación-de-la-extensión)
4. [Instalación y ejecución de la aplicación](#instalación-y-ejecución-de-la-aplicación)
5. [Uso de la aplicación](#uso-de-la-aplicación)
6. [Procedimientos generados](#procedimientos-generados)
7. [Seguridad](#seguridad)
8. [Pruebas](#pruebas)
9. [Errores y mensajes](#errores-y-mensajes)
10. [Limitaciones conocidas](#limitaciones-conocidas)
11. [Solución de problemas](#solución-de-problemas)
12. [Flujo de trabajo (Git)](#flujo-de-trabajo-git)

## Estructura del repositorio

```
.
├── README.md                    # Este documento (documentación de uso)
├── .gitignore
├── docs/
│   ├── CONTRATO.md              # Contrato extensión <-> app (firmas y errores)
│   └── guion_video.md           # Guion de la demostración en video
├── extension/                   # ENTREGABLE 1
│   ├── crudgen.control
│   ├── Makefile
│   └── sql/crudgen--1.0.sql     # Todo el SQL/PLpgSQL de la extensión
├── app/                         # ENTREGABLE 2
│   ├── main.py                  # Flujo de la aplicación (punto de entrada)
│   ├── db.py                    # Acceso a PostgreSQL (wrappers de la extensión)
│   ├── consola.py               # Utilidades de terminal
│   ├── requirements.txt
│   └── config.ejemplo.ini
└── pruebas/
    ├── 1_tablas_prueba.sql      # Esquema "demo" con las tablas de prueba
    ├── 2_roles.sql              # Roles vendedor / supervisor / administrador
    └── 3_prueba_automatica.sql  # Prueba de extremo a extremo con aserciones
```

El código de la aplicación separa responsabilidades: `db.py` es el único módulo que habla con PostgreSQL (nunca imprime ni lee de la terminal), `consola.py` es el único que interactúa con la terminal (nunca toca la base), y `main.py` combina ambos siguiendo el flujo del enunciado.

## Requisitos

- PostgreSQL **12 o superior** (usa `PROCEDURE` y `pg_attribute.attgenerated`).
- Para instalar con `make`: paquete de desarrollo de PostgreSQL con `pg_config` (en Debian/Ubuntu: `postgresql-server-dev-<versión>`). Si no se tiene, la extensión se puede instalar copiando los archivos a mano (ver abajo).
- Python **3.10 o superior**.

## Instalación de la extensión

Una extensión no vive dentro de la base de datos sino en la instalación del servidor: primero se copian sus archivos al servidor y después se instala en cada base donde se vaya a usar.

### 1. Copiar los archivos al servidor

**Con `make` (Linux/macOS con PGXS):**

```bash
cd extension
sudo make install                 # copia crudgen.control y crudgen--1.0.sql a share/extension
```

**A mano (Windows, o sin `make`):** ubicar la carpeta de extensiones del servidor con

```sql
SELECT setting FROM pg_config() WHERE name = 'SHAREDIR';
```

y copiar `extension/crudgen.control` y `extension/sql/crudgen--1.0.sql` a esa ruta + `/extension`. Rutas habituales:

| Instalación | Carpeta de extensiones |
|---|---|
| Windows (instalador oficial) | `C:\Program Files\PostgreSQL\<versión>\share\extension` |
| macOS (instalador oficial) | `/Library/PostgreSQL/<versión>/share/postgresql/extension` |
| macOS (Homebrew) | `/opt/homebrew/share/postgresql@<versión>/extension` |
| Linux / imagen oficial de Docker | `/usr/share/postgresql/<versión>/extension` |

**Si PostgreSQL corre en Docker**, los archivos van dentro del contenedor (el nombre aparece en la columna `NAMES` de `docker ps`):

```bash
docker cp extension/crudgen.control <contenedor>:/usr/share/postgresql/<versión>/extension/
docker cp extension/sql/crudgen--1.0.sql <contenedor>:/usr/share/postgresql/<versión>/extension/
```

### 2. Instalar en la base de datos

En cada base donde se quiera usar, con un usuario con permiso para crear extensiones (por ejemplo `postgres`):

```sql
SELECT current_database();   -- confirmar que es la base correcta
CREATE EXTENSION crudgen;
```

> En pgAdmin, el Query Tool queda conectado a la base que estaba seleccionada al abrirlo. `CREATE DATABASE` no cambia de base: hay que abrir un Query Tool nuevo sobre la base recién creada.

Esto crea el esquema `crudgen` con las funciones de la extensión. El usuario con el que se conecte la app necesita poder usar ese esquema:

```sql
GRANT USAGE ON SCHEMA crudgen TO mi_usuario_admin;
```

Además, ese usuario debe poder **crear objetos** en el esquema de las tablas (`CREATE` sobre el esquema) y es quien quedará como **propietario** de los procedimientos generados (ver [Seguridad](#seguridad)).

### 3. Actualizar la extensión

Si cambian los archivos de la extensión, copiarlos de nuevo (paso 1) y reinstalarla en la base:

```sql
DROP EXTENSION crudgen;
CREATE EXTENSION crudgen;
```

Esto solo reemplaza las funciones del esquema `crudgen`; tablas, datos y roles no se tocan. Los procedimientos generados antes conservan el código anterior, así que conviene regenerarlos desde la app.

## Instalación y ejecución de la aplicación

```bash
cd app
python3 -m venv .venv              # Windows: python -m venv .venv
source .venv/bin/activate          # Windows: .venv\Scripts\activate
pip install -r requirements.txt

cp config.ejemplo.ini config.ini   # editar con los datos de conexión (opcional)
python main.py
```

Con el entorno virtual activo la terminal muestra `(.venv)`; hay que activarlo en cada terminal nueva. En macOS, fuera del entorno virtual el comando es `python3`.

### Configuración de la conexión

`config.ini` tiene este formato:

```ini
[postgres]
host = localhost
puerto = 5432
base_datos = proyecto_demo
usuario = postgres
contrasena = su_contraseña
```

Si existe, la app muestra la configuración encontrada (sin la contraseña) y ofrece usarla; si no existe o se rechaza, pide servidor, puerto, base de datos, usuario y contraseña (la contraseña no se muestra al escribirla). `config.ini` está en `.gitignore`: cada persona crea el suyo y no se sube al repositorio.

> **Docker:** el puerto es el que Docker expone en la máquina, que puede no ser 5432. En `docker ps`, una columna `PORTS` con `0.0.0.0:54648->5432/tcp` significa que hay que usar el puerto `54648`.

## Uso de la aplicación

### Cómo responder en la consola

| Pregunta | Respuesta | Ejemplo |
|---|---|---|
| Elegir una opción | El número | `2` |
| Elegir varias | Números separados por coma | `1,3,4` |
| Elegir todas | Asterisco | `*` |
| Sí / no | `s` o `n` | `s` |
| Valor opcional | Enter para omitirlo | |
| Valor nulo al ejecutar | La palabra `NULL` | `NULL` |

Una respuesta inválida se vuelve a preguntar. La app no se cierra ante errores esperados: informa y deja continuar. Solo termina al elegir **Salir** o con **Ctrl + C**.

### Flujo

1. **Conexión**: se validan los datos; si falla se muestra el motivo y se puede reintentar.
2. **Verificación de la extensión**: se consulta al servidor (no se asume nada por archivos locales) y se informa un estado:

   | Estado | Significado | Qué hacer |
   |---|---|---|
   | `INSTALADA` | Lista para usar | Continúa |
   | `NO_INSTALADA` | Archivos en el servidor, falta `CREATE EXTENSION` en esta base | [Instalar en la base](#2-instalar-en-la-base-de-datos) |
   | `SIN_ARCHIVOS` | Los archivos no están en el servidor | [Copiar los archivos](#1-copiar-los-archivos-al-servidor) |
   | `SIN_PERMISOS` | Instalada, pero el usuario no puede usarla | `GRANT USAGE ON SCHEMA crudgen` |
   | `ERROR` | Falló la consulta | Revisar el mensaje |

   Si no está `INSTALADA` se puede verificar de nuevo, conectar a otra base o salir.
3. **Esquema**: se elige uno de los esquemas de la base.
4. **Tablas**: una, varias (`1,3`) o todas (`*`). Las tablas sin PK se marcan. Si el esquema no tiene tablas, se vuelve a pedir el esquema.
5. **Estructura**: para cada tabla se muestran columnas, tipo, PK, autogeneradas, si admiten NULL y su default.
6. **Operaciones CRUD**: INSERT, SELECT, UPDATE, DELETE. La app omite con aviso lo que una tabla no admite (UPDATE/DELETE sin PK; UPDATE sin columnas actualizables). Si no queda nada que generar, ofrece elegir otras tablas u operaciones, cambiar de esquema o salir.
7. **Generación** de los procedimientos, indicando cuáles se crearon y cuáles se reemplazaron. Si una tabla falla, se informa y se sigue con las demás.
8. **Mostrar** los procedimientos creados y, a elección, su código SQL.
9. **Roles y privilegios**: se eligen roles y qué operaciones puede ejecutar cada uno (o `(ninguna)`). Se muestra la matriz resultante. La matriz se aplica a los procedimientos de todas las tablas elegidas; para permisos distintos por tabla, repetir el flujo por tabla.
10. **Aplicar**: tras confirmar, la matriz se traduce a `GRANT EXECUTE` (✓) y `REVOKE EXECUTE` (✗). Revocar los ✗ garantiza que los permisos reales queden exactamente como la matriz.
11. **Resultado**: resumen de procedimientos y privilegios aplicados.

### Menú final

| Opción | Qué hace |
|---|---|
| Ejecutar un procedimiento | Pide los parámetros (leídos de la definición real del procedimiento) y lo ejecuta. Los resultados de `*_consultar` se muestran como tabla. |
| Ejecutar como otro rol | Igual, pero con los permisos del rol elegido (`SET ROLE`). Al terminar la conexión vuelve siempre al usuario original, incluso si falla. Sirve para comprobar la matriz. |
| Ver procedimientos creados | Lista y código |
| Reconfigurar privilegios | Repite los pasos 9 y 10 |
| Generar para otras tablas de este esquema | Vuelve al paso 4 |
| Cambiar de esquema | Vuelve al paso 3 |
| Salir | Cierra la conexión y termina |

Para "Ejecutar como otro rol", el usuario conectado debe poder asumir ese rol (ser superusuario o miembro del rol).

## Procedimientos generados

Para una tabla `cliente`:

| Operación | Objeto generado | Tipo | Llamada |
|---|---|---|---|
| INSERT | `cliente_insertar(...)` | PROCEDURE | `CALL esquema.cliente_insertar(p_nombre => 'Ana')` |
| SELECT | `cliente_consultar(...)` | FUNCTION | `SELECT * FROM esquema.cliente_consultar(p_id => 1)` |
| UPDATE | `cliente_actualizar(...)` | PROCEDURE | `CALL esquema.cliente_actualizar(p_id => 1, p_email => 'a@b.c')` |
| DELETE | `cliente_eliminar(...)` | PROCEDURE | `CALL esquema.cliente_eliminar(p_id => 1)` |

Los parámetros se llaman `p_<columna>`. La app los invoca por nombre (`p_nombre => ...`), así que el orden no importa y los opcionales se omiten.

Reglas de generación:

- **INSERT**: las columnas autogeneradas (`serial`, `IDENTITY`, `GENERATED ... STORED`) no son parámetros. Las columnas con `DEFAULT` y las que admiten NULL son parámetros opcionales (si se omiten usan su default o NULL). Las `NOT NULL` sin default son obligatorias. Si la tabla solo tiene columnas autogeneradas se genera `INSERT ... DEFAULT VALUES`.
- **UPDATE / DELETE**: se identifican por la **clave primaria completa**, simple o compuesta (todos sus parámetros son obligatorios). En UPDATE, los demás parámetros son opcionales: los omitidos (o NULL) no se modifican.
- **SELECT**: los parámetros de PK son opcionales y funcionan como filtros; sin parámetros devuelve toda la tabla. Con PK compuesta se puede filtrar por una parte de la clave.
- **Regenerar** una tabla (por ejemplo tras un `ALTER TABLE`) elimina las versiones anteriores y crea la nueva, sin dejar sobrecargas duplicadas. Los nombres `<tabla>_insertar`, `_consultar`, `_actualizar` y `_eliminar` quedan **reservados** para el generador. Los privilegios se reaplican desde la app tras regenerar.

## Seguridad

- **Sin concatenar valores**: en la extensión todos los identificadores se arman con `format('%I')` / `quote_ident()`; en Python los valores van como parámetros enlazados y los identificadores (esquemas, procedimientos, parámetros, roles) con `psycopg.sql.Identifier`. Esto evita inyección SQL y permite nombres con mayúsculas, espacios o palabras reservadas.
- **`SECURITY DEFINER`** con `SET search_path = pg_catalog` en todos los procedimientos generados. Se eligió porque así los roles reciben **solo** `EXECUTE` sobre el procedimiento y no necesitan ningún privilegio sobre la tabla: la matriz de privilegios del procedimiento es la única puerta de entrada. El `search_path` fijo evita el secuestro por objetos con el mismo nombre en otros esquemas.
- **Propietario**: el procedimiento se ejecuta con los permisos de su propietario, que es el usuario que corrió la generación. Se recomienda **no generar como superusuario** sino con un rol dueño de las tablas y con privilegios mínimos; si se genera como `postgres`, los procedimientos correrán como superusuario.
- **`PUBLIC` sin acceso**: cada procedimiento se crea con `REVOKE EXECUTE ... FROM PUBLIC`. Sin `GRANT` explícito, nadie puede ejecutarlo.
- `asignar_privilegio` otorga `EXECUTE` al procedimiento y `USAGE` sobre el esquema que lo contiene (sin `USAGE` el rol no podría referenciarlo). No otorga ningún permiso sobre las tablas.
- Privilegios necesarios para quien genera: `USAGE` sobre `crudgen`, `CREATE` sobre el esquema destino. Para otorgar/revocar: ser propietario de los procedimientos (o superusuario).
- **Credenciales fuera del código**: los datos de conexión están en `config.ini`, excluido del repositorio; la contraseña no se muestra en pantalla.

## Pruebas

Las tablas de prueba cubren los tres casos obligatorios y varios casos borde:

| Caso | Tabla(s) |
|---|---|
| 1. PK simple | `demo.cliente` (con `serial`, defaults y columna opcional) |
| 2. PK compuesta | `demo.inscripcion` (y `demo.matricula`, donde toda la tabla es la PK) |
| 3. Valores generados | `demo.producto` (`IDENTITY` + columna `GENERATED ... STORED`) |
| Borde | `demo.bitacora` (sin PK), `demo.contador` (solo autogenerada → `DEFAULT VALUES`), `demo."Orden Detalle"` (espacios, tildes, palabras reservadas), `demo.pedido` (tipo `enum` con default) |

```bash
createdb proyecto_demo
psql -d proyecto_demo -f pruebas/1_tablas_prueba.sql    # crea la extensión y las tablas
psql -d proyecto_demo -f pruebas/2_roles.sql            # roles de la prueba de privilegios
psql -d proyecto_demo -v ON_ERROR_STOP=1 -f pruebas/3_prueba_automatica.sql
```

Con Docker, los mismos scripts se pueden ejecutar desde pgAdmin, o con `docker exec -i <contenedor> psql -U postgres -d proyecto_demo < pruebas/1_tablas_prueba.sql`.

El último script ejecuta toda la generación y verifica con aserciones: los 3 casos, los errores esperados, la regeneración sin duplicados y la **matriz de privilegios con 3 roles**:

| Rol | Insertar | Consultar | Actualizar | Eliminar |
|---|:-:|:-:|:-:|:-:|
| vendedor | ✓ | ✓ | ✗ | ✗ |
| supervisor | ✓ | ✓ | ✓ | ✗ |
| administrador | ✓ | ✓ | ✓ | ✓ |

Si todo sale bien termina con `TODAS LAS PRUEBAS PASARON`. Para la prueba **desde la aplicación**, correr `main.py`, elegir el esquema `demo`, todas las tablas y operaciones, configurar esa matriz y usar la opción del menú "Ejecutar como otro rol".

## Errores y mensajes

### Errores de la extensión

Las funciones lanzan errores con el formato `CRUDGEN:<CODIGO>: <mensaje>`, que la app muestra como mensaje legible sin cerrarse:

| Código | Cuándo ocurre |
|---|---|
| `ESQUEMA_NO_EXISTE` | El esquema indicado no existe |
| `TABLA_NO_EXISTE` | La tabla indicada no existe |
| `NO_PK` | UPDATE o DELETE sobre una tabla sin clave primaria |
| `SIN_COLUMNAS_ACTUALIZABLES` | UPDATE sobre una tabla sin columnas modificables |
| `OPERACION_INVALIDA` | Operación distinta de INSERT, SELECT, UPDATE o DELETE |
| `NOMBRE_MUY_LARGO` | El nombre generado superaría los 63 caracteres de PostgreSQL |
| `ROL_NO_EXISTE` | Asignar o revocar privilegios a un rol inexistente |
| `PROC_NO_EXISTE` | Usar un procedimiento que no existe |

### Errores al ejecutar procedimientos

Al ejecutar desde el menú, PostgreSQL puede rechazar la operación por permisos o por los datos. La app lo muestra como *PostgreSQL rechazó la operación*. Ejemplos:

| Mensaje | Causa |
|---|---|
| `permission denied for procedure ...` | El rol no tiene `EXECUTE` (resultado esperado según la matriz) |
| `null value in column ... violates not-null constraint` | Falta un valor obligatorio |
| `duplicate key value violates unique constraint` | La clave ya existe |
| `invalid input syntax for type ...` | El valor no corresponde al tipo de la columna |
| `... violates check constraint` | El valor no cumple una restricción `CHECK` |
| `invalid input value for enum ...` | El valor no está entre los permitidos |

## Limitaciones conocidas

- En los procedimientos `*_actualizar`, NULL significa "no modificar", por lo que no se puede dejar una columna en NULL con ellos.
- Los parámetros de `*_consultar` son solo las columnas de la PK; no se filtra por otras columnas. Tablas sin PK devuelven siempre todas las filas.
- Los procedimientos usan `search_path = pg_catalog`: columnas de tipos de extensiones externas cuyos operadores viven en otro esquema (por ejemplo `citext`) pueden no resolverse en `UPDATE`/`DELETE`/`SELECT`.
- Los nombres de tabla deben tener como máximo 52 caracteres y los de columna 61 (límite de 63 de PostgreSQL con los prefijos/sufijos generados).
- La matriz de privilegios de la app se aplica igual a todas las tablas elegidas en una misma pasada.

## Solución de problemas

| Problema | Causa probable y solución |
|---|---|
| `password authentication failed` | Usuario o contraseña incorrectos. En Docker, la contraseña está en `docker inspect <contenedor>` (`POSTGRES_PASSWORD`). |
| `connection refused` | Servidor apagado o puerto incorrecto. En Docker, revisar el puerto en `docker ps`. |
| `database "..." does not exist` | El nombre de la base no coincide. Listar con `\l` en `psql` o en el árbol de pgAdmin. |
| `NO_INSTALADA` aunque se ejecutó `CREATE EXTENSION` | Se ejecutó en otra base. Confirmar con `SELECT current_database();`. |
| `SIN_ARCHIVOS` | Los archivos no están en la carpeta de extensiones del servidor (en Docker, dentro del contenedor). |
| `ModuleNotFoundError: No module named 'psycopg'` | El entorno virtual no está activo o faltó `pip install -r requirements.txt`. |
| `command not found: python` (macOS) | Fuera del entorno virtual el comando es `python3`. |
| Un cambio en la extensión no se refleja | Falta reinstalarla en la base y regenerar los procedimientos ([Actualizar la extensión](#3-actualizar-la-extensión)). |

## Flujo de trabajo (Git)

- `main`: solo versiones estables/entregables.
- `feature/<algo>`: una rama por tarea; se integra a `main` mediante Pull Request.

Antes de cambiar la firma de una función de la extensión, actualizar `docs/CONTRATO.md` y avisar al equipo.