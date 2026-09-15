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
    -- TODO: implementar (responsable: A)
    RAISE EXCEPTION 'CRUDGEN:NOT_IMPLEMENTED: verificar_extension pendiente';
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
    -- TODO: implementar (responsable: A)
    RAISE EXCEPTION 'CRUDGEN:NOT_IMPLEMENTED: listar_esquemas pendiente';
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
    -- TODO: implementar (responsable: A)
    RAISE EXCEPTION 'CRUDGEN:NOT_IMPLEMENTED: listar_tablas pendiente';
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
    -- TODO: implementar (responsable: A)
    RAISE EXCEPTION 'CRUDGEN:NOT_IMPLEMENTED: analizar_tabla pendiente';
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
