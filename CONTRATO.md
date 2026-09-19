# Contrato de Interfaz — Extensión PostgreSQL ↔ Aplicación Python

Este documento es la **fuente de verdad** sobre qué funciones expone la extensión y cómo la app Python debe consumirlas. Cualquier cambio a una firma aquí definida debe avisarse al equipo antes de modificar el código.

Versión: 0.2 — actualizado tras revisión conjunta de `analizar_tabla` (Jeanca + Omaru)

**Cambios respecto a v0.1:**
- Todos los parámetros de las funciones ahora usan prefijo `p_` (evita ambigüedad entre nombre de parámetro y nombre de columna en las queries — causaba errores de "column reference is ambiguous" en PL/pgSQL).
- El campo `tipo` en `analizar_tabla` ahora usa `udt_name` en vez de `data_type` (da el nombre corto del tipo, ej. `varchar`, útil directo para generar la firma de los procedimientos en `generar_crud`).
- Definición de `es_autogenerada` acotada explícitamente (ver sección 4) para no excluir de más en `generar_crud`.

---

## Convenciones generales

- Todos los parámetros de toda función de la extensión llevan prefijo `p_` (ej. `p_esquema`, `p_tabla`, `p_rol`).
- Todas las funciones viven en el esquema `crudgen` para no chocar con objetos del usuario.
- Los errores esperables (ej. "tabla sin PK", "extensión no disponible") se comunican con `RAISE EXCEPTION` usando un código y mensaje reconocible, **no** con columnas de estado — así Python los captura de forma uniforme con try/except sobre la librería de conexión (ej. `psycopg`).
- Formato del mensaje de excepción: `CRUDGEN:<CODIGO>: <mensaje legible>` (ej. `CRUDGEN:NO_PK: la tabla no tiene clave primaria`).
- Ningún nombre de esquema/tabla/columna se concatena directo en SQL dinámico — siempre vía `quote_ident()` / `format('%I', ...)`.

---

## 1. `crudgen.verificar_extension()`

- **Input:** ninguno (opera sobre la conexión activa).
- **Output:** `TABLE(instalada BOOLEAN, disponible_para_usuario BOOLEAN, version TEXT)`
- **Casos límite:**
  - Si la extensión no está instalada → `instalada = false` (no lanza excepción; Python decide qué mostrar).
  - Si está instalada pero el usuario conectado no tiene privilegio de uso → `disponible_para_usuario = false`.

## 2. `crudgen.listar_esquemas()`

- **Input:** ninguno.
- **Output:** `TABLE(nombre_esquema TEXT)`
- **Casos límite:** excluye esquemas de sistema (`pg_catalog`, `information_schema`, `pg_toast%`, `pg_temp%`, `crudgen`).

## 3. `crudgen.listar_tablas(p_esquema TEXT)`

- **Input:** `p_esquema` — nombre del esquema seleccionado.
- **Output:** `TABLE(nombre_tabla TEXT, tiene_pk BOOLEAN)`
- **Casos límite:**
  - Esquema inexistente → `RAISE EXCEPTION 'CRUDGEN:ESQUEMA_NO_EXISTE: ...'`.
  - Esquema sin tablas → devuelve conjunto vacío (no es error).

## 4. `crudgen.analizar_tabla(p_esquema TEXT, p_tabla TEXT)`

- **Input:** `p_esquema`, `p_tabla`.
- **Output:** `TABLE(columna TEXT, tipo TEXT, orden INT, es_pk BOOLEAN, es_autogenerada BOOLEAN, valor_default TEXT, es_nullable BOOLEAN)`
- **`tipo`**: se llena con `udt_name` (no `data_type`) — nombre corto del tipo (`varchar`, `int4`, `bool`, etc.), listo para usar en la firma de un procedimiento generado.
- **`es_autogenerada`**: `true` **únicamente** si el valor por defecto proviene de una secuencia (`column_default LIKE 'nextval(%'`) o la columna es `IDENTITY` (`is_identity = 'YES'`). Una columna con `DEFAULT true` o `DEFAULT now()` **no** cuenta como autogenerada — sí debe poder recibirse como parámetro (opcional) en el INSERT generado.
- **Casos límite:**
  - Tabla inexistente → `RAISE EXCEPTION 'CRUDGEN:TABLA_NO_EXISTE: ...'`.
  - Tabla sin PK → todas las filas con `es_pk = false` (no es error; Python debe advertir que UPDATE/DELETE no estarán disponibles).
  - PK compuesta → varias filas con `es_pk = true`, una por columna de la clave.

## 5. `crudgen.generar_crud(p_esquema TEXT, p_tabla TEXT, p_operaciones TEXT[])`

- **Input:** `p_esquema`, `p_tabla`, `p_operaciones` — subconjunto de `{'INSERT','SELECT','UPDATE','DELETE'}`.
- **Output:** `TABLE(operacion TEXT, nombre_procedimiento TEXT, ya_existia BOOLEAN)`
- **Comportamiento:** crea (`CREATE OR REPLACE PROCEDURE`/`FUNCTION`) los procedimientos solicitados en el esquema de la tabla, usando internamente `crudgen.analizar_tabla(p_esquema, p_tabla)`.
- **Casos límite:**
  - Operación `UPDATE`/`DELETE` sobre tabla sin PK → `RAISE EXCEPTION 'CRUDGEN:NO_PK: ...'`.
  - Procedimiento ya existente → se reemplaza (`OR REPLACE`) y se reporta `ya_existia = true`, sin fallar.
  - Columnas con `es_autogenerada = true` → excluidas de los parámetros del procedimiento de INSERT.

## 6. `crudgen.asignar_privilegio(p_esquema TEXT, p_nombre_procedimiento TEXT, p_rol TEXT)`

- **Input:** `p_esquema`, `p_nombre_procedimiento`, `p_rol`.
- **Output:** `BOOLEAN` (éxito).
- **Comportamiento:** ejecuta `GRANT EXECUTE ON PROCEDURE ... TO p_rol`.
- **Casos límite:**
  - Rol inexistente → `RAISE EXCEPTION 'CRUDGEN:ROL_NO_EXISTE: ...'`.
  - Procedimiento inexistente → `RAISE EXCEPTION 'CRUDGEN:PROC_NO_EXISTE: ...'`.

## 7. `crudgen.revocar_privilegio(p_esquema TEXT, p_nombre_procedimiento TEXT, p_rol TEXT)`

- Análoga a la anterior pero con `REVOKE EXECUTE`. Mismos casos límite.

---

## Tabla resumen

| Función | Responsable | Estado |
|---|---|---|
| `verificar_extension` | Jeanca (A) | ✅ Implementada |
| `listar_esquemas` | Jeanca (A) | ✅ Implementada |
| `listar_tablas` | Jeanca (A) | ✅ Implementada |
| `analizar_tabla` | Jeanca (A) | ✅ Implementada (reemplaza el mock de Omaru) |
| `generar_crud` | Omaru (B) | 🔲 Pendiente de mergear a `crudgen--1.0.sql` |
| `asignar_privilegio` / `revocar_privilegio` | Omaru (B) | 🔲 Pendiente de mergear a `crudgen--1.0.sql` |

---

## Pendientes a decidir en equipo

- [ ] ¿`generar_crud` genera `PROCEDURE` o `FUNCTION`?
- [ ] ¿`SECURITY INVOKER` o `SECURITY DEFINER` para los procedimientos generados?
- [ ] Convención de nombres exacta (ej. `<tabla>_insertar` vs `sp_<tabla>_insertar`).
- [ ] Cómo se representan los criterios de búsqueda en el `SELECT` generado.

## Reglas de trabajo (recordatorio tras el incidente del mock/archivos sueltos)

- Todo el SQL de la extensión vive en **un solo archivo**: `extension/sql/crudgen--1.0.sql`. PostgreSQL solo carga el archivo que coincide con `<nombre>--<version>.sql` al hacer `CREATE EXTENSION` — archivos sueltos adicionales en esa carpeta no se ejecutan automáticamente.
- Los scripts de tablas de prueba van en `pruebas/`, no en `extension/sql/`.
- Si necesitan una función temporal (mock) mientras el responsable real la termina, está bien — pero se avisa en el grupo y se borra en cuanto la versión oficial esté mergeada.
