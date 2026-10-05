# Contrato de Interfaz — Extensión PostgreSQL ↔ Aplicación Python

Este documento es la **fuente de verdad** sobre qué funciones expone la extensión `crudgen` y cómo la app Python las consume. Cualquier cambio a una firma aquí definida debe actualizarse en este archivo y avisarse al equipo antes de modificar el código.

**Versión 0.3** — refleja la implementación final de `extension/sql/crudgen--1.0.sql`.

**Cambios respecto a v0.2:**
- `generar_crud`, `asignar_privilegio` y `revocar_privilegio` implementadas; se resolvieron las decisiones pendientes (ver sección "Decisiones de diseño").
- Documentadas las funciones 8 (`listar_roles`) y 9 (`listar_procedimientos_generados`), que ya usaba la app.
- `analizar_tabla` ahora lee directamente de `pg_catalog` y `tipo` pasa de `udt_name` a `format_type()` (nombre completo del tipo, calificado con esquema si no es de `pg_catalog`, apto para usarlo en la firma de un procedimiento).
- `es_autogenerada` incluye también columnas `GENERATED ALWAYS AS (...) STORED`.
- Nueva función interna `_crear_objeto`; regenerar ya no deja sobrecargas duplicadas.
- Los parámetros generados se entrecomillan (`quote_ident`), por lo que soportan espacios y palabras reservadas.
- Nuevo código de error `NOMBRE_MUY_LARGO`.

---

## Convenciones generales

- Todos los parámetros de las funciones públicas llevan prefijo `p_` (`p_esquema`, `p_tabla`, `p_rol`...).
- Todas las funciones viven en el esquema `crudgen`. Las que empiezan con `_` son internas y no forman parte del contrato con la app.
- Los errores esperables se comunican con `RAISE EXCEPTION` con el formato **`CRUDGEN:<CODIGO>: <mensaje legible>`**. La app los captura (`db.CrudgenError`) a partir del mensaje primario de la excepción.
- Ningún nombre de esquema/tabla/columna se concatena directo en SQL dinámico: siempre `quote_ident()` o `format('%I', ...)`.

### Códigos de error

| Código | Cuándo |
|---|---|
| `ESQUEMA_NO_EXISTE` | El esquema indicado no existe |
| `TABLA_NO_EXISTE` | La tabla no existe en el esquema (o no es una tabla) |
| `NO_PK` | UPDATE/DELETE sobre tabla sin clave primaria |
| `SIN_COLUMNAS_ACTUALIZABLES` | UPDATE sobre tabla cuyas columnas son todas PK o autogeneradas |
| `OPERACION_INVALIDA` | Operación fuera de `INSERT/SELECT/UPDATE/DELETE`, o lista vacía |
| `NOMBRE_MUY_LARGO` | El nombre generado (procedimiento o parámetro) excedería 63 caracteres |
| `ROL_NO_EXISTE` | El rol del GRANT/REVOKE no existe |
| `PROC_NO_EXISTE` | El procedimiento del GRANT/REVOKE no existe |

---

## 1. `crudgen.verificar_extension()`

- **Output:** `TABLE(instalada BOOLEAN, disponible_para_usuario BOOLEAN, version TEXT)`
- Si la extensión no está instalada → `instalada = false` (sin excepción).
- Si está instalada pero el usuario no tiene `USAGE` sobre el esquema `crudgen` → `disponible_para_usuario = false`. (Si el usuario ni siquiera puede ejecutar la función, la app lo detecta por el error de privilegio y reporta `SIN_PERMISOS`.)
- La app además consulta `pg_extension` y `pg_available_extensions` para distinguir `INSTALADA`, `NO_INSTALADA`, `SIN_ARCHIVOS`, `SIN_PERMISOS` y `ERROR`.

## 2. `crudgen.listar_esquemas()`

- **Output:** `TABLE(nombre_esquema TEXT)`, ordenado por nombre.
- Excluye `pg_catalog`, `information_schema`, `pg_toast%`, `pg_temp%` y `crudgen`.

## 3. `crudgen.listar_tablas(p_esquema TEXT)`

- **Output:** `TABLE(nombre_tabla TEXT, tiene_pk BOOLEAN)`, ordenado por nombre.
- Esquema inexistente → `CRUDGEN:ESQUEMA_NO_EXISTE`. Esquema sin tablas → conjunto vacío.

## 4. `crudgen.analizar_tabla(p_esquema TEXT, p_tabla TEXT)`

- **Output:** `TABLE(columna TEXT, tipo TEXT, orden INT, es_pk BOOLEAN, es_autogenerada BOOLEAN, valor_default TEXT, es_nullable BOOLEAN)`
- Lee de `pg_class`, `pg_attribute`, `pg_attrdef` y `pg_index`. Se declara con `SET search_path = pg_catalog` para que los nombres de tipos y expresiones salgan calificados con su esquema cuando no son de `pg_catalog`.
- **`tipo`**: `format_type(atttypid, NULL)`, ej. `integer`, `character varying`, `demo.estado`.
- **`orden`**: posición de la columna entre las columnas vigentes (sin huecos por columnas eliminadas).
- **`es_autogenerada`**: `true` si la columna es `IDENTITY`, `GENERATED ... STORED`, o su default proviene de una secuencia (`nextval(...)`, es decir `serial`). Un `DEFAULT true` o `DEFAULT now()` **no** cuenta como autogenerada.
- **`valor_default`**: expresión del default como texto (puede ser NULL).
- Tabla inexistente → `CRUDGEN:TABLA_NO_EXISTE`. Tabla sin PK → todas las filas con `es_pk = false`. PK compuesta → varias filas con `es_pk = true`.

## 5. `crudgen.generar_crud(p_esquema TEXT, p_tabla TEXT, p_operaciones TEXT[])`

- **Input:** `p_operaciones` ⊆ `{'INSERT','SELECT','UPDATE','DELETE'}` (sin distinguir mayúsculas; se eliminan duplicados).
- **Output:** `TABLE(operacion TEXT, nombre_procedimiento TEXT, ya_existia BOOLEAN)`
- Crea los objetos en el esquema de la tabla usando `analizar_tabla`. Si ya existía algún objeto con ese nombre (cualquier firma), se **elimina y se recrea** (`ya_existia = true`), para no dejar sobrecargas duplicadas. Los privilegios del objeto anterior se pierden y deben reaplicarse.
- Cada objeto se crea con `REVOKE EXECUTE ... FROM PUBLIC` y `COMMENT 'crudgen:generado'`.
- La llamada es atómica: si falla una operación, no queda nada a medias.

| Operación | Objeto | Parámetros |
|---|---|---|
| INSERT | `PROCEDURE <tabla>_insertar` | Sin autogeneradas. Obligatorios: `NOT NULL` sin default. Opcionales (`DEFAULT NULL`): con default (usa `COALESCE(p, <default>)`) o nullables. Obligatorios primero. Sin columnas insertables → `DEFAULT VALUES` |
| UPDATE | `PROCEDURE <tabla>_actualizar` | Todas las columnas de la PK (obligatorias) + el resto no autogenerado, opcionales; `COALESCE(p, columna)` |
| DELETE | `PROCEDURE <tabla>_eliminar` | Todas las columnas de la PK (obligatorias) |
| SELECT | `FUNCTION <tabla>_consultar` → `SETOF <tabla>` | Columnas de la PK, todas opcionales; los NULL no filtran |

- Los parámetros se llaman `p_<columna>` y se entrecomillan cuando hace falta.
- Todos con `LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog`.
- Errores: `NO_PK`, `SIN_COLUMNAS_ACTUALIZABLES`, `OPERACION_INVALIDA`, `TABLA_NO_EXISTE`, `NOMBRE_MUY_LARGO`.
- Los nombres `<tabla>_insertar|_consultar|_actualizar|_eliminar` quedan reservados para el generador.

## 6. `crudgen.asignar_privilegio(p_esquema TEXT, p_nombre_procedimiento TEXT, p_rol TEXT)`

- **Output:** `BOOLEAN`. Ejecuta `GRANT USAGE ON SCHEMA` (necesario para poder referenciar el procedimiento) y `GRANT EXECUTE` sobre **todas** las sobrecargas del nombre. Funciona para `PROCEDURE` y `FUNCTION`.
- Errores: `ROL_NO_EXISTE`, `PROC_NO_EXISTE`.

## 7. `crudgen.revocar_privilegio(p_esquema TEXT, p_nombre_procedimiento TEXT, p_rol TEXT)`

- **Output:** `BOOLEAN`. `REVOKE EXECUTE` sobre todas las sobrecargas del nombre. No revoca `USAGE` del esquema. Mismos errores.

## 8. `crudgen.listar_roles()`

- **Output:** `TABLE(nombre_rol TEXT, puede_iniciar_sesion BOOLEAN)`, ordenado por nombre. Excluye los roles internos `pg_*`.

## 9. `crudgen.listar_procedimientos_generados(p_esquema TEXT, p_tabla TEXT DEFAULT NULL)`

- **Output:** `TABLE(nombre_procedimiento TEXT, tipo TEXT, definicion TEXT)`.
- Con `p_tabla`: los 4 objetos de esa tabla (comparación exacta de nombre). Sin `p_tabla`: todos los marcados con `COMMENT 'crudgen:generado'` en el esquema. `definicion` es el código completo (`pg_get_functiondef`).
- Esquema inexistente → `ESQUEMA_NO_EXISTE`.

## Interna: `crudgen._crear_objeto(p_esquema, p_nombre, p_tipo, p_sql)`

Usada por `generar_crud`: elimina las sobrecargas existentes del nombre, ejecuta el `CREATE`, revoca `EXECUTE` a `PUBLIC` y marca el objeto con el comentario. Devuelve si ya existía. **No** la usa la app.

---

## Decisiones de diseño (resueltas)

| Tema | Decisión |
|---|---|
| ¿PROCEDURE o FUNCTION? | INSERT/UPDATE/DELETE → `PROCEDURE`; SELECT → `FUNCTION` (un procedimiento no devuelve filas de forma utilizable) |
| ¿INVOKER o DEFINER? | `SECURITY DEFINER` con `search_path` fijo; los roles solo necesitan `EXECUTE` (ver README, "Seguridad") |
| Convención de nombres | `<tabla>_insertar`, `_consultar`, `_actualizar`, `_eliminar` |
| Criterios del SELECT | Parámetros opcionales sobre las columnas de la PK |
| UPDATE y NULL | NULL = "no modificar"; no se puede asignar NULL con el procedimiento generado (limitación documentada) |

## Reglas de trabajo

- Todo el SQL de la extensión vive en **un solo archivo**: `extension/sql/crudgen--1.0.sql`. PostgreSQL solo carga el archivo `<nombre>--<version>.sql` al hacer `CREATE EXTENSION`.
- Los scripts de tablas de prueba van en `pruebas/`, no en `extension/sql/`.
- Los archivos del repositorio usan saltos de línea LF.
