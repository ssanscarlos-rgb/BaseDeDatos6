# Contrato de Interfaz — Extensión PostgreSQL ↔ Aplicación Python

Este documento es la **fuente de verdad** sobre qué funciones expone la extensión y cómo la app Python debe consumirlas. Cualquier cambio a una firma aquí definida debe avisarse al equipo antes de modificar el código.

Versión: 0.1 (borrador inicial — completar/ajustar en equipo)

---

## Convenciones generales

- Todas las funciones viven en el esquema de la extensión (ej. `crudgen.*`) para no chocar con objetos del usuario.
- Los errores esperables (ej. "tabla sin PK", "extensión no disponible") se comunican con `RAISE EXCEPTION` usando un código y mensaje reconocible, **no** con columnas de estado — así Python los captura de forma uniforme con try/except sobre la librería de conexión (ej. `psycopg`).
- Formato sugerido del mensaje de excepción: `CRUDGEN:<CODIGO>: <mensaje legible>` (ej. `CRUDGEN:NO_PK: la tabla no tiene clave primaria`). Esto permite a Python distinguir el tipo de error sin parsear texto libre.
- Ningún nombre de esquema/tabla/columna se concatena directo en SQL dinámico — siempre vía `quote_ident()` / `format('%I', ...)`.

---

## 1. `crudgen.verificar_extension()`

- **Input:** ninguno (opera sobre la conexión activa).
- **Output:** `TABLE(instalada BOOLEAN, disponible_para_usuario BOOLEAN, version TEXT)`
- **Casos límite:**
  - Si la extensión no está instalada → `instalada = false` (no lanza excepción; Python decide qué mostrar).
  - Si está instalada pero el usuario conectado no tiene privilegio de uso → `disponible_para_usuario = false`.
- **Notas:** esta función debe poder ejecutarse incluso con privilegios mínimos, ya que es el primer chequeo del flujo.

## 2. `crudgen.listar_esquemas()`

- **Input:** ninguno.
- **Output:** `TABLE(nombre_esquema TEXT)`
- **Casos límite:** excluye esquemas de sistema (`pg_catalog`, `information_schema`, `pg_toast`).

## 3. `crudgen.listar_tablas(esquema TEXT)`

- **Input:** `esquema` — nombre del esquema seleccionado.
- **Output:** `TABLE(nombre_tabla TEXT, tiene_pk BOOLEAN)`
- **Casos límite:**
  - Esquema inexistente → `RAISE EXCEPTION 'CRUDGEN:ESQUEMA_NO_EXISTE: ...'`.
  - Esquema sin tablas → devuelve conjunto vacío (no es error).

## 4. `crudgen.analizar_tabla(esquema TEXT, tabla TEXT)`

- **Input:** `esquema`, `tabla`.
- **Output:** `TABLE(columna TEXT, tipo TEXT, orden INT, es_pk BOOLEAN, es_autogenerada BOOLEAN, valor_default TEXT, es_nullable BOOLEAN)`
- **Casos límite:**
  - Tabla inexistente → `RAISE EXCEPTION 'CRUDGEN:TABLA_NO_EXISTE: ...'`.
  - Tabla sin PK → todas las filas con `es_pk = false` (no es error; Python debe advertir al usuario que UPDATE/DELETE no estarán disponibles o pedirá otro criterio).
  - PK compuesta → varias filas con `es_pk = true`, una por columna de la clave.

## 5. `crudgen.generar_crud(esquema TEXT, tabla TEXT, operaciones TEXT[])`

- **Input:** `esquema`, `tabla`, `operaciones` — subconjunto de `{'INSERT','SELECT','UPDATE','DELETE'}`.
- **Output:** `TABLE(operacion TEXT, nombre_procedimiento TEXT, ya_existia BOOLEAN)`
- **Comportamiento:** crea (`CREATE OR REPLACE PROCEDURE`/`FUNCTION`) los procedimientos solicitados en el esquema de la tabla, usando la información de `analizar_tabla`.
- **Casos límite:**
  - Operación `UPDATE`/`DELETE` sobre tabla sin PK → `RAISE EXCEPTION 'CRUDGEN:NO_PK: ...'`.
  - Procedimiento ya existente → se reemplaza (`OR REPLACE`) y se reporta `ya_existia = true` en el resultado, sin fallar (cumple restricción de manejar objetos preexistentes).
  - Columnas autogeneradas (secuencia/DEFAULT) → excluidas de los parámetros del procedimiento de INSERT.

## 6. `crudgen.asignar_privilegio(esquema TEXT, nombre_procedimiento TEXT, rol TEXT)`

- **Input:** `esquema`, `nombre_procedimiento`, `rol`.
- **Output:** `BOOLEAN` (éxito).
- **Comportamiento:** ejecuta `GRANT EXECUTE ON PROCEDURE ... TO rol`.
- **Casos límite:**
  - Rol inexistente → `RAISE EXCEPTION 'CRUDGEN:ROL_NO_EXISTE: ...'`.
  - Procedimiento inexistente → `RAISE EXCEPTION 'CRUDGEN:PROC_NO_EXISTE: ...'`.

## 7. `crudgen.revocar_privilegio(esquema TEXT, nombre_procedimiento TEXT, rol TEXT)`

- Análoga a la anterior pero con `REVOKE EXECUTE`. Mismos casos límite.

---

## Tabla resumen (para referencia rápida)

| Función | Quién la implementa | Consumida por |
|---|---|---|
| `verificar_extension` | Extensión (A) | App Python — paso 1 del flujo |
| `listar_esquemas` | Extensión (A) | App Python — selección de esquema |
| `listar_tablas` | Extensión (A) | App Python — selección de tablas |
| `analizar_tabla` | Extensión (A) | App Python — mostrar estructura / Extensión (B) internamente |
| `generar_crud` | Extensión (B) | App Python — botón "Generar" |
| `asignar_privilegio` / `revocar_privilegio` | Extensión (B) | App Python — pantalla de privilegios |

---

## Pendientes a decidir en equipo

- [ ] ¿`generar_crud` genera `PROCEDURE` o `FUNCTION`? (el enunciado dice "procedimientos"; confirmar si usan `CREATE PROCEDURE` de PL/pgSQL con `CALL`, dado que simplifica el manejo de transacciones).
- [ ] ¿`SECURITY INVOKER` o `SECURITY DEFINER` para los procedimientos generados? Justificar la elección en la documentación de seguridad.
- [ ] Convención de nombres exacta (ej. `<tabla>_insertar` vs `sp_<tabla>_insertar`).
- [ ] ¿Cómo se representan los criterios de búsqueda en el `SELECT` generado (todas las columnas, filtro por PK, filtro arbitrario)?
