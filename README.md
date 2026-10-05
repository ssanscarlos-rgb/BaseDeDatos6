# Generador automático de procedimientos CRUD para PostgreSQL

Proyecto de Bases de Datos II — ITCR, Campus Tecnológico San Carlos.

Solución en dos partes:

- **Extensión PostgreSQL `crudgen`**: lee el catálogo del sistema (`pg_catalog`) y genera dinámicamente procedimientos almacenados CRUD para cualquier tabla, además de administrar los privilegios (`GRANT`/`REVOKE`) sobre ellos.
- **Aplicación Python de consola**: conecta a la base, verifica la extensión, permite elegir esquema, tablas, operaciones y roles, y aplica la matriz de privilegios.

## Integrantes

| Nombre | Módulo |
|---|---|
| _(completar)_ | Extensión: análisis de catálogo y funciones de listado |
| _(completar)_ | Extensión: generación CRUD y privilegios |
| _(completar)_ | Aplicación Python |

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
│   ├── main.py                  # Flujo de la aplicación
│   ├── db.py                    # Acceso a PostgreSQL (wrappers de la extensión)
│   ├── consola.py               # Utilidades de terminal
│   ├── requirements.txt
│   └── config.ejemplo.ini
└── pruebas/
    ├── 01_tablas_prueba.sql     # Esquema "demo" con las tablas de prueba
    ├── 02_roles.sql             # Roles vendedor / supervisor / administrador
    └── 03_prueba_automatica.sql # Prueba de extremo a extremo con aserciones
```

## Requisitos

- PostgreSQL **12 o superior** (usa `PROCEDURE` y `pg_attribute.attgenerated`).
- Paquete de desarrollo de PostgreSQL con `pg_config` (en Debian/Ubuntu: `postgresql-server-dev-<versión>`) y `make`.
- Python **3.10 o superior**.

## Instalación de la extensión

La extensión debe instalarse **en el servidor** donde corre PostgreSQL:

```bash
cd extension
sudo make install                 # copia crudgen.control y crudgen--1.0.sql a share/extension
```

Luego, en cada base de datos donde se quiera usar, con un usuario con permiso para crear extensiones (por ejemplo `postgres`):

```sql
CREATE EXTENSION crudgen;
```

Esto crea el esquema `crudgen` con las funciones de la extensión. El usuario con el que se conecte la app necesita poder usar ese esquema:

```sql
GRANT USAGE ON SCHEMA crudgen TO mi_usuario_admin;
```

Además, ese usuario debe poder **crear objetos** en el esquema de las tablas (`CREATE` sobre el esquema) y es quien quedará como **propietario** de los procedimientos generados (ver "Seguridad").

> **Windows:** si no se dispone de `make`/PGXS, copiar manualmente `crudgen.control` y `sql/crudgen--1.0.sql` a la carpeta `share/extension` de la instalación de PostgreSQL.

## Instalación y ejecución de la aplicación

```bash
cd app
python -m venv .venv
source .venv/bin/activate          # Windows: .venv\Scripts\activate
pip install -r requirements.txt

cp config.ejemplo.ini config.ini   # editar con los datos de conexión (opcional)
python main.py
```

Si existe `config.ini`, la app ofrece usarlo; si no (o se rechaza), pide servidor, puerto, base de datos, usuario y contraseña (la contraseña no se muestra al escribirla). `config.ini` está en `.gitignore`: no se sube al repositorio.

## Uso: flujo de la aplicación

1. **Conexión**: se validan los datos; si falla se puede reintentar.
2. **Verificación de la extensión**: se consulta al servidor (no se asume nada por archivos locales) y se informa uno de estos estados: `INSTALADA`, `NO_INSTALADA`, `SIN_ARCHIVOS`, `SIN_PERMISOS` o `ERROR`.
3. **Esquema**: se elige uno de los esquemas de la base.
4. **Tablas**: una, varias (`1,3`) o todas (`*`). Las tablas sin PK se marcan.
5. **Estructura**: se muestra para cada tabla columnas, tipo, PK, autogeneradas, NULL y default.
6. **Operaciones CRUD**: INSERT, SELECT, UPDATE, DELETE. La app omite con aviso lo que una tabla no admite (UPDATE/DELETE sin PK; UPDATE sin columnas actualizables).
7. **Generación** de los procedimientos y reporte de cuáles se crearon o reemplazaron.
8. **Mostrar** los procedimientos creados y, a elección, su código.
9. **Roles y privilegios**: se eligen roles y qué operaciones puede ejecutar cada uno (matriz).
10. **Aplicar**: la matriz se traduce a `GRANT EXECUTE` (✓) y `REVOKE EXECUTE` (✗).
11. **Resultado** y **menú**: ejecutar un procedimiento, ejecutarlo **como otro rol** (para comprobar los privilegios, usa `SET ROLE`), ver código, reconfigurar privilegios, generar para otras tablas o cambiar de esquema.

### Procedimientos generados

Para una tabla `cliente`:

| Operación | Objeto generado | Tipo | Llamada |
|---|---|---|---|
| INSERT | `cliente_insertar(...)` | PROCEDURE | `CALL esquema.cliente_insertar(p_nombre => 'Ana')` |
| SELECT | `cliente_consultar(...)` | FUNCTION | `SELECT * FROM esquema.cliente_consultar(p_id => 1)` |
| UPDATE | `cliente_actualizar(...)` | PROCEDURE | `CALL esquema.cliente_actualizar(p_id => 1, p_email => 'a@b.c')` |
| DELETE | `cliente_eliminar(...)` | PROCEDURE | `CALL esquema.cliente_eliminar(p_id => 1)` |

Los parámetros se llaman `p_<columna>`.

Reglas de generación:

- **INSERT**: las columnas autogeneradas (`serial`, `IDENTITY`, `GENERATED ... STORED`) no son parámetros. Las columnas con `DEFAULT` y las que admiten NULL son parámetros opcionales (si se omiten usan su default o NULL). Las `NOT NULL` sin default son obligatorias. Si la tabla solo tiene columnas autogeneradas se genera `INSERT ... DEFAULT VALUES`.
- **UPDATE / DELETE**: se identifican por la **clave primaria completa**, simple o compuesta (todos sus parámetros son obligatorios). En UPDATE, los demás parámetros son opcionales: los omitidos (o NULL) no se modifican.
- **SELECT**: los parámetros de PK son opcionales y funcionan como filtros; sin parámetros devuelve toda la tabla. Con PK compuesta se puede filtrar por una parte de la clave.
- **Regenerar** una tabla (por ejemplo tras un `ALTER TABLE`) elimina las versiones anteriores y crea la nueva, sin dejar sobrecargas duplicadas. Los nombres `<tabla>_insertar`, `_consultar`, `_actualizar` y `_eliminar` quedan **reservados** para el generador. Los privilegios se reaplican desde la app tras regenerar.

## Seguridad

- **Sin concatenar valores**: en la extensión todos los identificadores se arman con `format('%I')` / `quote_ident()`; en Python los valores van como parámetros enlazados y los identificadores con `psycopg.sql.Identifier`.
- **`SECURITY DEFINER`** con `SET search_path = pg_catalog` en todos los procedimientos generados. Se eligió porque así los roles reciben **solo** `EXECUTE` sobre el procedimiento y no necesitan ningún privilegio sobre la tabla: la matriz de privilegios del procedimiento es la única puerta de entrada. El `search_path` fijo evita el secuestro por objetos con el mismo nombre en otros esquemas.
- **Propietario**: el procedimiento se ejecuta con los permisos de su propietario, que es el usuario que corrió la generación. Se recomienda **no generar como superusuario** sino con un rol dueño de las tablas y con privilegios mínimos; si se genera como `postgres`, los procedimientos correrán como superusuario.
- **`PUBLIC` sin acceso**: cada procedimiento se crea con `REVOKE EXECUTE ... FROM PUBLIC`. Sin `GRANT` explícito, nadie puede ejecutarlo.
- `asignar_privilegio` otorga `EXECUTE` al procedimiento y `USAGE` sobre el esquema que lo contiene (sin `USAGE` el rol no podría referenciarlo). No otorga ningún permiso sobre las tablas.
- Privilegios necesarios para quien genera: `USAGE` sobre `crudgen`, `CREATE` sobre el esquema destino. Para otorgar/revocar: ser propietario de los procedimientos (o superusuario).

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
psql -d proyecto_demo -f pruebas/01_tablas_prueba.sql   # crea la extensión y las tablas
psql -d proyecto_demo -f pruebas/02_roles.sql           # roles de la prueba de privilegios
psql -d proyecto_demo -v ON_ERROR_STOP=1 -f pruebas/03_prueba_automatica.sql
```

El último script ejecuta toda la generación y verifica con aserciones: los 3 casos, los errores esperados, la regeneración sin duplicados y la **matriz de privilegios con 3 roles**:

| Rol | Insertar | Consultar | Actualizar | Eliminar |
|---|:-:|:-:|:-:|:-:|
| vendedor | ✓ | ✓ | ✗ | ✗ |
| supervisor | ✓ | ✓ | ✓ | ✗ |
| administrador | ✓ | ✓ | ✓ | ✓ |

Si todo sale bien termina con `TODAS LAS PRUEBAS PASARON`. Para la prueba **desde la aplicación**, correr `main.py`, elegir el esquema `demo`, todas las tablas y operaciones, configurar esa matriz y usar la opción del menú "Ejecutar un procedimiento como otro rol".

## Errores de la extensión

Las funciones lanzan errores con el formato `CRUDGEN:<CODIGO>: <mensaje>`, que la app traduce a mensajes legibles. Los códigos son: `ESQUEMA_NO_EXISTE`, `TABLA_NO_EXISTE`, `NO_PK`, `SIN_COLUMNAS_ACTUALIZABLES`, `OPERACION_INVALIDA`, `NOMBRE_MUY_LARGO`, `ROL_NO_EXISTE` y `PROC_NO_EXISTE`.

## Limitaciones conocidas

- En los procedimientos `*_actualizar`, NULL significa "no modificar", por lo que no se puede dejar una columna en NULL con ellos.
- Los parámetros de `*_consultar` son solo las columnas de la PK; no se filtra por otras columnas. Tablas sin PK devuelven siempre todas las filas.
- Los procedimientos usan `search_path = pg_catalog`: columnas de tipos de extensiones externas cuyos operadores viven en otro esquema (por ejemplo `citext`) pueden no resolverse en `UPDATE`/`DELETE`/`SELECT`.
- Los nombres de tabla deben tener como máximo 52 caracteres y los de columna 61 (límite de 63 de PostgreSQL con los prefijos/sufijos generados).

## Flujo de trabajo (Git)

- `main`: solo versiones estables/entregables.
- `develop`: rama de integración.
- `feature/<algo>`: una rama por tarea; se integra a `develop` con frecuencia.

Antes de cambiar la firma de una función de la extensión, actualizar `docs/CONTRATO.md` y avisar al equipo.
