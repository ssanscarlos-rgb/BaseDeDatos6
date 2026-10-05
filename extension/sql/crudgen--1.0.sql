-- crudgen--1.0.sql
-- Script único de instalación de la extensión. PostgreSQL solo carga
-- ESTE archivo (nombre--version.sql) al hacer CREATE EXTENSION.
-- NO crear archivos .sql sueltos adicionales en esta carpeta.
--
-- Ver docs/CONTRATO.md (v0.3) para la especificación de cada función.
-- Requiere PostgreSQL 12 o superior (usa pg_attribute.attgenerated y
-- PROCEDURE).
--
-- NOTA: no llevar CREATE SCHEMA aquí. El crudgen.control ya declara
-- "schema = crudgen", así que PostgreSQL crea el esquema automáticamente
-- antes de correr este script y lo registra como propio de la extensión.
-- Si este script también lo crea, CREATE EXTENSION falla con:
-- "el esquema crudgen no es un miembro de la extensión «crudgen»".

-- =========================================================
-- 1. verificar_extension()  -- CONTRATO sección 1
-- =========================================================
CREATE OR REPLACE FUNCTION crudgen.verificar_extension()
RETURNS TABLE(instalada BOOLEAN, disponible_para_usuario BOOLEAN, version TEXT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_version TEXT;
BEGIN
    SELECT extversion INTO v_version
    FROM pg_extension
    WHERE extname = 'crudgen';

    IF v_version IS NULL THEN
        RETURN QUERY SELECT false, false, NULL::TEXT;
        RETURN;
    END IF;

    RETURN QUERY SELECT
        true,
        has_schema_privilege(current_user, 'crudgen', 'USAGE'),
        v_version;
END;
$$;

-- =========================================================
-- 2. listar_esquemas()  -- CONTRATO sección 2
-- =========================================================
CREATE OR REPLACE FUNCTION crudgen.listar_esquemas()
RETURNS TABLE(nombre_esquema TEXT)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT s.schema_name::TEXT
    FROM information_schema.schemata s
    WHERE s.schema_name NOT IN ('pg_catalog', 'information_schema', 'crudgen')
      AND s.schema_name NOT LIKE 'pg\_toast%'
      AND s.schema_name NOT LIKE 'pg\_temp%'
    ORDER BY s.schema_name;
END;
$$;

-- =========================================================
-- 3. listar_tablas(p_esquema TEXT)  -- CONTRATO sección 3
-- =========================================================
CREATE OR REPLACE FUNCTION crudgen.listar_tablas(p_esquema TEXT)
RETURNS TABLE(nombre_tabla TEXT, tiene_pk BOOLEAN)
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.schemata s WHERE s.schema_name = p_esquema) THEN
        RAISE EXCEPTION 'CRUDGEN:ESQUEMA_NO_EXISTE: el esquema % no existe', p_esquema;
    END IF;

    RETURN QUERY
    SELECT
        t.table_name::TEXT,
        EXISTS (
            SELECT 1
            FROM information_schema.table_constraints tc
            WHERE tc.table_schema = p_esquema
              AND tc.table_name = t.table_name
              AND tc.constraint_type = 'PRIMARY KEY'
        )
    FROM information_schema.tables t
    WHERE t.table_schema = p_esquema
      AND t.table_type = 'BASE TABLE'
    ORDER BY t.table_name;
END;
$$;

-- =========================================================
-- 4. analizar_tabla(p_esquema TEXT, p_tabla TEXT)  -- CONTRATO sección 4
--
-- Lee TODO directamente de pg_catalog (no de information_schema, que
-- solo muestra lo que el usuario tiene permiso de ver y no resuelve bien
-- tipos definidos por el usuario).
--
-- SET search_path = pg_catalog: así format_type() y pg_get_expr() devuelven
-- los nombres de tipos y funciones calificados con su esquema cuando no son
-- de pg_catalog (ej. public.mi_enum), lo que los hace utilizables dentro de
-- los procedimientos generados, que también corren con search_path fijo.
-- =========================================================
CREATE OR REPLACE FUNCTION crudgen.analizar_tabla(p_esquema TEXT, p_tabla TEXT)
RETURNS TABLE(
    columna         TEXT,
    tipo            TEXT,
    orden           INT,
    es_pk           BOOLEAN,
    es_autogenerada BOOLEAN,
    valor_default   TEXT,
    es_nullable     BOOLEAN
)
LANGUAGE plpgsql
SET search_path = pg_catalog
AS $$
DECLARE
    v_reloid OID;
BEGIN
    SELECT c.oid INTO v_reloid
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = p_esquema
      AND c.relname = p_tabla
      AND c.relkind IN ('r', 'p');          -- tabla ordinaria o particionada

    IF v_reloid IS NULL THEN
        RAISE EXCEPTION 'CRUDGEN:TABLA_NO_EXISTE: la tabla %.% no existe', p_esquema, p_tabla;
    END IF;

    RETURN QUERY
    SELECT
        a.attname::TEXT,
        format_type(a.atttypid, NULL)::TEXT,
        (row_number() OVER (ORDER BY a.attnum))::INT,
        COALESCE(a.attnum = ANY (pk.indkey::INT2[]), false),
        (
            a.attidentity <> ''                       -- IDENTITY (ALWAYS / BY DEFAULT)
            OR a.attgenerated <> ''                   -- GENERATED ALWAYS AS (...) STORED
            OR COALESCE(pg_get_expr(d.adbin, d.adrelid) LIKE 'nextval(%', false)  -- serial
        ),
        pg_get_expr(d.adbin, d.adrelid)::TEXT,
        NOT a.attnotnull
    FROM pg_attribute a
    LEFT JOIN pg_attrdef d
           ON d.adrelid = a.attrelid AND d.adnum = a.attnum
    LEFT JOIN pg_index pk
           ON pk.indrelid = a.attrelid AND pk.indisprimary
    WHERE a.attrelid = v_reloid
      AND a.attnum > 0
      AND NOT a.attisdropped
    ORDER BY a.attnum;
END;
$$;

-- =========================================================
-- Auxiliar interna: _crear_objeto
-- Crea un procedimiento/función generado de forma segura:
--   1. Elimina TODAS las sobrecargas existentes con ese nombre en el esquema
--      (CREATE OR REPLACE con otra firma crearía una sobrecarga en lugar de
--      reemplazar, dejando basura y haciendo ambiguos GRANT/REVOKE).
--   2. Ejecuta el CREATE.
--   3. Quita EXECUTE a PUBLIC (la matriz de privilegios manda).
--   4. Marca el objeto con COMMENT 'crudgen:generado'.
-- Devuelve true si ya existía algún objeto con ese nombre.
-- Los nombres <tabla>_insertar/_consultar/_actualizar/_eliminar quedan
-- reservados para el generador.
-- =========================================================
CREATE OR REPLACE FUNCTION crudgen._crear_objeto(
    p_esquema TEXT,
    p_nombre  TEXT,
    p_tipo    TEXT,      -- 'PROCEDURE' o 'FUNCTION'
    p_sql     TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
    v_existente  RECORD;
    v_ya_existia BOOLEAN := false;
    v_oid        OID;
BEGIN
    FOR v_existente IN
        SELECT p.oid::regprocedure AS firma, p.prokind
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = p_esquema
          AND p.proname = p_nombre
          AND p.prokind IN ('f', 'p')
    LOOP
        v_ya_existia := true;
        EXECUTE format('DROP %s %s',
                       CASE WHEN v_existente.prokind = 'p' THEN 'PROCEDURE' ELSE 'FUNCTION' END,
                       v_existente.firma);
    END LOOP;

    EXECUTE p_sql;

    SELECT p.oid INTO v_oid
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = p_esquema AND p.proname = p_nombre;

    EXECUTE format('REVOKE EXECUTE ON %s %s FROM PUBLIC', p_tipo, v_oid::regprocedure);
    EXECUTE format('COMMENT ON %s %s IS %L', p_tipo, v_oid::regprocedure, 'crudgen:generado');

    RETURN v_ya_existia;
END;
$$;

-- =====================================================================
-- 5. generar_crud(p_esquema TEXT, p_tabla TEXT, p_operaciones TEXT[])
--    CONTRATO sección 5
--
-- Decisiones de diseño:
--   - INSERT / UPDATE / DELETE -> PROCEDURE (se llaman con CALL)
--   - SELECT                   -> FUNCTION  (se llama con SELECT * FROM ...)
--   - SECURITY DEFINER en todos, con search_path fijo (evita hijacking).
--     Los procedimientos se ejecutan con los permisos de su PROPIETARIO
--     (quien corrió generar_crud); los roles a los que se hace GRANT EXECUTE
--     NO necesitan permisos sobre la tabla.
--   - Nombres: <tabla>_insertar / _consultar / _actualizar / _eliminar
--   - Los parámetros se llaman p_<columna> (entrecomillados con quote_ident,
--     así soportan espacios, mayúsculas y palabras reservadas).
--
-- INSERT:
--   * columnas autogeneradas (serial/identity/generated) -> no son parámetro
--   * columnas con DEFAULT   -> parámetro opcional: COALESCE(p, <default>)
--   * columnas NULL sin DEFAULT -> parámetro opcional (NULL si se omite)
--   * columnas NOT NULL sin DEFAULT -> parámetro obligatorio
--   * si no queda ninguna columna a insertar -> INSERT ... DEFAULT VALUES
-- UPDATE:
--   * PK obligatoria (todas las columnas de la clave, simple o compuesta)
--   * resto de columnas opcionales: NULL = "no modificar" (COALESCE).
--     LIMITACIÓN CONOCIDA: con este procedimiento no se puede dejar una
--     columna en NULL.
-- SELECT:
--   * parámetros de PK opcionales; los NULL no filtran (si no se pasa
--     ninguno, devuelve toda la tabla; se puede filtrar por parte de una PK
--     compuesta).
-- =====================================================================
CREATE OR REPLACE FUNCTION crudgen.generar_crud(
    p_esquema     TEXT,
    p_tabla       TEXT,
    p_operaciones TEXT[]
)
RETURNS TABLE(operacion TEXT, nombre_procedimiento TEXT, ya_existia BOOLEAN)
LANGUAGE plpgsql
AS $$
DECLARE
    v_op        TEXT;
    v_ops       TEXT[];
    v_col       RECORD;
    v_c         TEXT;      -- columna entrecomillada
    v_p         TEXT;      -- parámetro entrecomillado (p_<columna>)

    v_pk_n          INT := 0;
    v_pk_req        TEXT[] := ARRAY[]::TEXT[];   -- p_x tipo
    v_pk_opt        TEXT[] := ARRAY[]::TEXT[];   -- p_x tipo DEFAULT NULL
    v_pk_where      TEXT[] := ARRAY[]::TEXT[];   -- x = p_x
    v_pk_filtro     TEXT[] := ARRAY[]::TEXT[];   -- (p_x IS NULL OR x = p_x)

    v_ins_cols      TEXT[] := ARRAY[]::TEXT[];
    v_ins_vals      TEXT[] := ARRAY[]::TEXT[];
    v_ins_req       TEXT[] := ARRAY[]::TEXT[];
    v_ins_opt       TEXT[] := ARRAY[]::TEXT[];

    v_upd_params    TEXT[] := ARRAY[]::TEXT[];
    v_upd_set       TEXT[] := ARRAY[]::TEXT[];

    v_nombre    TEXT;
    v_sql       TEXT;
    v_existia   BOOLEAN;
BEGIN
    -- 1. Validar operaciones
    IF p_operaciones IS NULL OR array_length(p_operaciones, 1) IS NULL THEN
        RAISE EXCEPTION 'CRUDGEN:OPERACION_INVALIDA: no se indicó ninguna operación';
    END IF;

    SELECT array_agg(DISTINCT upper(o)) INTO v_ops FROM unnest(p_operaciones) AS o;

    FOREACH v_op IN ARRAY v_ops LOOP
        IF v_op NOT IN ('INSERT', 'SELECT', 'UPDATE', 'DELETE') THEN
            RAISE EXCEPTION 'CRUDGEN:OPERACION_INVALIDA: % no es una operación soportada', v_op;
        END IF;
    END LOOP;

    -- Los nombres generados deben caber en 63 caracteres (si no, Postgres
    -- los trunca en silencio y dejarían de coincidir).
    IF length(p_tabla) + length('_actualizar') > 63 THEN
        RAISE EXCEPTION 'CRUDGEN:NOMBRE_MUY_LARGO: el nombre de la tabla % es demasiado largo para generar procedimientos', p_tabla;
    END IF;

    -- 2. Leer la estructura real de la tabla (función 4 del contrato)
    FOR v_col IN SELECT * FROM crudgen.analizar_tabla(p_esquema, p_tabla)
    LOOP
        IF length('p_' || v_col.columna) > 63 THEN
            RAISE EXCEPTION 'CRUDGEN:NOMBRE_MUY_LARGO: el nombre de la columna % es demasiado largo para generar su parámetro', v_col.columna;
        END IF;

        v_c := quote_ident(v_col.columna);
        v_p := quote_ident('p_' || v_col.columna);

        IF v_col.es_pk THEN
            v_pk_n      := v_pk_n + 1;
            v_pk_req    := array_append(v_pk_req,    format('%s %s', v_p, v_col.tipo));
            v_pk_opt    := array_append(v_pk_opt,    format('%s %s DEFAULT NULL', v_p, v_col.tipo));
            v_pk_where  := array_append(v_pk_where,  format('%s = %s', v_c, v_p));
            v_pk_filtro := array_append(v_pk_filtro, format('(%s IS NULL OR %s = %s)', v_p, v_c, v_p));
        END IF;

        IF NOT v_col.es_autogenerada THEN
            v_ins_cols := array_append(v_ins_cols, v_c);
            IF v_col.valor_default IS NOT NULL THEN
                -- Tiene DEFAULT: parámetro opcional; si llega NULL se usa el default
                v_ins_opt  := array_append(v_ins_opt,  format('%s %s DEFAULT NULL', v_p, v_col.tipo));
                v_ins_vals := array_append(v_ins_vals, format('COALESCE(%s, %s)', v_p, v_col.valor_default));
            ELSIF v_col.es_nullable THEN
                v_ins_opt  := array_append(v_ins_opt,  format('%s %s DEFAULT NULL', v_p, v_col.tipo));
                v_ins_vals := array_append(v_ins_vals, v_p);
            ELSE
                v_ins_req  := array_append(v_ins_req,  format('%s %s', v_p, v_col.tipo));
                v_ins_vals := array_append(v_ins_vals, v_p);
            END IF;
        END IF;

        -- Columnas actualizables: ni PK ni autogeneradas (una columna
        -- GENERATED tampoco puede tocarse en UPDATE).
        IF NOT v_col.es_pk AND NOT v_col.es_autogenerada THEN
            v_upd_params := array_append(v_upd_params, format('%s %s DEFAULT NULL', v_p, v_col.tipo));
            v_upd_set    := array_append(v_upd_set,    format('%s = COALESCE(%s, %s)', v_c, v_p, v_c));
        END IF;
    END LOOP;

    -- 3. Validaciones de casos límite
    IF v_pk_n = 0 AND (v_ops && ARRAY['UPDATE', 'DELETE']) THEN
        RAISE EXCEPTION 'CRUDGEN:NO_PK: la tabla %.% no tiene clave primaria; no se puede generar UPDATE/DELETE', p_esquema, p_tabla;
    END IF;

    IF 'UPDATE' = ANY (v_ops) AND array_length(v_upd_set, 1) IS NULL THEN
        RAISE EXCEPTION 'CRUDGEN:SIN_COLUMNAS_ACTUALIZABLES: la tabla %.% no tiene columnas fuera de la clave primaria; no se puede generar UPDATE', p_esquema, p_tabla;
    END IF;

    -- 4. Generar cada operación pedida
    FOREACH v_op IN ARRAY v_ops LOOP
        CASE v_op

        WHEN 'INSERT' THEN
            v_nombre := p_tabla || '_insertar';
            IF array_length(v_ins_cols, 1) IS NULL THEN
                v_sql := format(
                    'CREATE PROCEDURE %I.%I()
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog AS $body$
BEGIN
    INSERT INTO %I.%I DEFAULT VALUES;
END; $body$;',
                    p_esquema, v_nombre, p_esquema, p_tabla);
            ELSE
                v_sql := format(
                    'CREATE PROCEDURE %I.%I(%s)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog AS $body$
BEGIN
    INSERT INTO %I.%I (%s) VALUES (%s);
END; $body$;',
                    p_esquema, v_nombre,
                    array_to_string(v_ins_req || v_ins_opt, ', '),   -- obligatorios primero
                    p_esquema, p_tabla,
                    array_to_string(v_ins_cols, ', '),
                    array_to_string(v_ins_vals, ', '));
            END IF;
            v_existia := crudgen._crear_objeto(p_esquema, v_nombre, 'PROCEDURE', v_sql);
            operacion := 'INSERT'; nombre_procedimiento := v_nombre; ya_existia := v_existia;
            RETURN NEXT;

        WHEN 'UPDATE' THEN
            v_nombre := p_tabla || '_actualizar';
            v_sql := format(
                'CREATE PROCEDURE %I.%I(%s, %s)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog AS $body$
BEGIN
    UPDATE %I.%I SET %s WHERE %s;
END; $body$;',
                p_esquema, v_nombre,
                array_to_string(v_pk_req, ', '),
                array_to_string(v_upd_params, ', '),
                p_esquema, p_tabla,
                array_to_string(v_upd_set, ', '),
                array_to_string(v_pk_where, ' AND '));
            v_existia := crudgen._crear_objeto(p_esquema, v_nombre, 'PROCEDURE', v_sql);
            operacion := 'UPDATE'; nombre_procedimiento := v_nombre; ya_existia := v_existia;
            RETURN NEXT;

        WHEN 'DELETE' THEN
            v_nombre := p_tabla || '_eliminar';
            v_sql := format(
                'CREATE PROCEDURE %I.%I(%s)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog AS $body$
BEGIN
    DELETE FROM %I.%I WHERE %s;
END; $body$;',
                p_esquema, v_nombre,
                array_to_string(v_pk_req, ', '),
                p_esquema, p_tabla,
                array_to_string(v_pk_where, ' AND '));
            v_existia := crudgen._crear_objeto(p_esquema, v_nombre, 'PROCEDURE', v_sql);
            operacion := 'DELETE'; nombre_procedimiento := v_nombre; ya_existia := v_existia;
            RETURN NEXT;

        WHEN 'SELECT' THEN
            v_nombre := p_tabla || '_consultar';
            IF v_pk_n > 0 THEN
                v_sql := format(
                    'CREATE FUNCTION %I.%I(%s)
RETURNS SETOF %I.%I
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog AS $body$
BEGIN
    RETURN QUERY SELECT * FROM %I.%I WHERE %s;
END; $body$;',
                    p_esquema, v_nombre,
                    array_to_string(v_pk_opt, ', '),
                    p_esquema, p_tabla,
                    p_esquema, p_tabla,
                    array_to_string(v_pk_filtro, ' AND '));
            ELSE
                v_sql := format(
                    'CREATE FUNCTION %I.%I()
RETURNS SETOF %I.%I
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog AS $body$
BEGIN
    RETURN QUERY SELECT * FROM %I.%I;
END; $body$;',
                    p_esquema, v_nombre, p_esquema, p_tabla, p_esquema, p_tabla);
            END IF;
            v_existia := crudgen._crear_objeto(p_esquema, v_nombre, 'FUNCTION', v_sql);
            operacion := 'SELECT'; nombre_procedimiento := v_nombre; ya_existia := v_existia;
            RETURN NEXT;

        END CASE;
    END LOOP;
END;
$$;

-- =====================================================================
-- 6/7. asignar_privilegio / revocar_privilegio  -- CONTRATO secciones 6 y 7
-- Funcionan para PROCEDURE (INSERT/UPDATE/DELETE) y FUNCTION (SELECT).
-- Se aplican a TODAS las sobrecargas del nombre (normalmente hay una).
-- =====================================================================
CREATE OR REPLACE FUNCTION crudgen.asignar_privilegio(
    p_esquema              TEXT,
    p_nombre_procedimiento TEXT,
    p_rol                  TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
    v_obj   RECORD;
    v_n     INT := 0;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = p_rol) THEN
        RAISE EXCEPTION 'CRUDGEN:ROL_NO_EXISTE: el rol % no existe', p_rol;
    END IF;

    FOR v_obj IN
        SELECT p.oid::regprocedure AS firma, p.prokind
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = p_esquema
          AND p.proname = p_nombre_procedimiento
          AND p.prokind IN ('f', 'p')
    LOOP
        IF v_n = 0 THEN
            -- EXECUTE sobre el procedimiento no sirve sin USAGE sobre su esquema.
            EXECUTE format('GRANT USAGE ON SCHEMA %I TO %I', p_esquema, p_rol);
        END IF;
        EXECUTE format('GRANT EXECUTE ON %s %s TO %I',
                       CASE WHEN v_obj.prokind = 'p' THEN 'PROCEDURE' ELSE 'FUNCTION' END,
                       v_obj.firma, p_rol);
        v_n := v_n + 1;
    END LOOP;

    IF v_n = 0 THEN
        RAISE EXCEPTION 'CRUDGEN:PROC_NO_EXISTE: %.% no existe', p_esquema, p_nombre_procedimiento;
    END IF;
    RETURN TRUE;
END;
$$;

CREATE OR REPLACE FUNCTION crudgen.revocar_privilegio(
    p_esquema              TEXT,
    p_nombre_procedimiento TEXT,
    p_rol                  TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
    v_obj   RECORD;
    v_n     INT := 0;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = p_rol) THEN
        RAISE EXCEPTION 'CRUDGEN:ROL_NO_EXISTE: el rol % no existe', p_rol;
    END IF;

    FOR v_obj IN
        SELECT p.oid::regprocedure AS firma, p.prokind
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = p_esquema
          AND p.proname = p_nombre_procedimiento
          AND p.prokind IN ('f', 'p')
    LOOP
        EXECUTE format('REVOKE EXECUTE ON %s %s FROM %I',
                       CASE WHEN v_obj.prokind = 'p' THEN 'PROCEDURE' ELSE 'FUNCTION' END,
                       v_obj.firma, p_rol);
        v_n := v_n + 1;
    END LOOP;

    IF v_n = 0 THEN
        RAISE EXCEPTION 'CRUDGEN:PROC_NO_EXISTE: %.% no existe', p_esquema, p_nombre_procedimiento;
    END IF;
    RETURN TRUE;
END;
$$;

-- =====================================================================
-- 8. listar_roles()  -- CONTRATO sección 8
-- Necesaria para el paso "seleccionar usuarios o roles" del flujo.
-- =====================================================================
CREATE OR REPLACE FUNCTION crudgen.listar_roles()
RETURNS TABLE(nombre_rol TEXT, puede_iniciar_sesion BOOLEAN)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT r.rolname::TEXT, r.rolcanlogin
    FROM pg_roles r
    WHERE r.rolname NOT LIKE 'pg\_%'  -- excluye roles internos de Postgres
    ORDER BY r.rolname;
END;
$$;

-- =====================================================================
-- 9. listar_procedimientos_generados(p_esquema TEXT, p_tabla TEXT DEFAULT NULL)
--    CONTRATO sección 9
-- Con p_tabla: los 4 procedimientos de esa tabla (comparación exacta de
-- nombre, sin comodines LIKE). Sin p_tabla: todos los marcados con
-- COMMENT 'crudgen:generado' en el esquema.
-- =====================================================================
CREATE OR REPLACE FUNCTION crudgen.listar_procedimientos_generados(p_esquema TEXT, p_tabla TEXT DEFAULT NULL)
RETURNS TABLE(nombre_procedimiento TEXT, tipo TEXT, definicion TEXT)
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.schemata s WHERE s.schema_name = p_esquema) THEN
        RAISE EXCEPTION 'CRUDGEN:ESQUEMA_NO_EXISTE: el esquema % no existe', p_esquema;
    END IF;

    RETURN QUERY
    SELECT
        p.proname::TEXT,
        (CASE WHEN p.prokind = 'p' THEN 'PROCEDURE' ELSE 'FUNCTION' END)::TEXT,
        pg_get_functiondef(p.oid)
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = p_esquema
      AND p.prokind IN ('f', 'p')
      AND (
          (p_tabla IS NULL AND obj_description(p.oid, 'pg_proc') = 'crudgen:generado')
          OR p.proname IN (p_tabla || '_insertar', p_tabla || '_consultar',
                           p_tabla || '_actualizar', p_tabla || '_eliminar')
      )
    ORDER BY p.proname;
END;
$$;
