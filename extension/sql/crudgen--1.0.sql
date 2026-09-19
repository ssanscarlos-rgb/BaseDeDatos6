-- crudgen--1.0.sql
-- Esqueleto inicial de la extensión. Cada función debe implementarse
-- según lo acordado en CONTRATO.md. NO borrar los comentarios de
-- referencia al contrato al implementar.

CREATE SCHEMA IF NOT EXISTS crudgen;

-- =========================================================
-- 1. verificar_extension()  -- ver CONTRATO.md sección 1
-- =========================================================
CREATE OR REPLACE FUNCTION crudgen.verificar_extension()
RETURNS TABLE(instalada BOOLEAN, disponible_para_usuario BOOLEAN, version TEXT)
LANGUAGE plpgsql
AS $$
BEGIN
    SELECT extversion INTO v_version FROM pg_extension WHERE extname = 'crudgen';
    IF v_version IS NULL THEN
        RETURN QUERY SELECT false, false, NULL::TEXT;
        RETURN;
    END IF;
    RETURN QUERY SELECT true, has_schema_privilege(current_user, 'crudgen', 'USAGE'), v_version;
END;
$$;

-- =========================================================
-- 2. listar_esquemas()  -- ver CONTRATO.md sección 2
-- =========================================================
CREATE OR REPLACE FUNCTION crudgen.listar_esquemas()
RETURNS TABLE(nombre_esquema TEXT)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT schema_name::TEXT
    FROM information_schema.schemata
    WHERE schema_name NOT IN ('pg_catalog', 'information_schema', 'crudgen')
      AND schema_name NOT LIKE 'pg_toast%'
      AND schema_name NOT LIKE 'pg_temp%';
END;
$$;

-- =========================================================
-- 3. listar_tablas(esquema TEXT)  -- ver CONTRATO.md sección 3
-- =========================================================
CREATE OR REPLACE FUNCTION crudgen.listar_tablas(esquema TEXT)
RETURNS TABLE(nombre_tabla TEXT, tiene_pk BOOLEAN)
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.schemata WHERE schema_name = esquema) THEN
        RAISE EXCEPTION 'CRUDGEN:ESQUEMA_NO_EXISTE: el esquema % no existe', esquema;
    END IF;

    RETURN QUERY
    SELECT
        t.table_name::TEXT,
        EXISTS (
            SELECT 1 FROM information_schema.table_constraints tc
            WHERE tc.table_schema = esquema
              AND tc.table_name = t.table_name
              AND tc.constraint_type = 'PRIMARY KEY'
        )
    FROM information_schema.tables t
    WHERE t.table_schema = esquema AND t.table_type = 'BASE TABLE';
END;
$$;

-- =========================================================
-- 4. analizar_tabla(esquema TEXT, tabla TEXT)  -- ver CONTRATO.md sección 4
-- =========================================================
CREATE OR REPLACE FUNCTION crudgen.analizar_tabla(esquema TEXT, tabla TEXT)
RETURNS TABLE(
    columna TEXT,
    tipo TEXT,
    orden INT,
    es_pk BOOLEAN,
    es_autogenerada BOOLEAN,
    valor_default TEXT,
    es_nullable BOOLEAN
)
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = esquema AND table_name = tabla
    ) THEN
        RAISE EXCEPTION 'CRUDGEN:TABLA_NO_EXISTE: la tabla %.% no existe', esquema, tabla;
    END IF;

    RETURN QUERY
    SELECT
        c.column_name::TEXT,
        c.data_type::TEXT,
        c.ordinal_position::INT,
        EXISTS (
            SELECT 1
            FROM information_schema.key_column_usage kcu
            JOIN information_schema.table_constraints tc
              ON tc.constraint_name = kcu.constraint_name AND tc.table_schema = kcu.table_schema
            WHERE tc.constraint_type = 'PRIMARY KEY'
              AND kcu.table_schema = esquema AND kcu.table_name = tabla
              AND kcu.column_name = c.column_name
        ),
        (c.column_default LIKE 'nextval(%' OR c.is_identity = 'YES'),
        c.column_default::TEXT,
        (c.is_nullable = 'YES')
    FROM information_schema.columns c
    WHERE c.table_schema = esquema AND c.table_name = tabla
    ORDER BY c.ordinal_position;
END;
$$;

-- =========================================================
-- 5. generar_crud(esquema TEXT, tabla TEXT, operaciones TEXT[])
--    ver CONTRATO.md sección 5
-- =========================================================
CREATE OR REPLACE FUNCTION crudgen.generar_crud(esquema TEXT, tabla TEXT, operaciones TEXT[])
RETURNS TABLE(operacion TEXT, nombre_procedimiento TEXT, ya_existia BOOLEAN)
LANGUAGE plpgsql
AS $$
BEGIN
    -- TODO: implementar (responsable: B)
    RAISE EXCEPTION 'CRUDGEN:NOT_IMPLEMENTED: generar_crud pendiente';
END;
$$;

-- =========================================================
-- 6. asignar_privilegio(esquema TEXT, nombre_procedimiento TEXT, rol TEXT)
--    ver CONTRATO.md sección 6
-- =========================================================
CREATE OR REPLACE FUNCTION crudgen.asignar_privilegio(esquema TEXT, nombre_procedimiento TEXT, rol TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
BEGIN
    -- TODO: implementar (responsable: B)
    RAISE EXCEPTION 'CRUDGEN:NOT_IMPLEMENTED: asignar_privilegio pendiente';
END;
$$;

-- =========================================================
-- 7. revocar_privilegio(esquema TEXT, nombre_procedimiento TEXT, rol TEXT)
--    ver CONTRATO.md sección 7
-- =========================================================
CREATE OR REPLACE FUNCTION crudgen.revocar_privilegio(esquema TEXT, nombre_procedimiento TEXT, rol TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
BEGIN
    -- TODO: implementar (responsable: B)
    RAISE EXCEPTION 'CRUDGEN:NOT_IMPLEMENTED: revocar_privilegio pendiente';
END;
$$;
