-- =====================================================================
-- MOCK TEMPORAL de crudgen.analizar_tabla
-- ---------------------------------------------------------------------
-- Esto NO es responsabilidad de Omaru (Persona 2) — es la función 4 del
-- contrato, que le corresponde a Jeanca (Persona 1).
--
-- Está implementada de forma genérica (lee pg_catalog de verdad, no
-- devuelve datos inventados) para que las pruebas de generar_crud sean
-- reales y no haya que reescribir nada cuando Jeanca suba su versión.
--
-- BORRAR / REEMPLAZAR este archivo en cuanto la función oficial de
-- Jeanca esté lista y mergeada a develop.
-- =====================================================================

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
AS $$
DECLARE
    v_reloid OID;
BEGIN
    -- Validar que la tabla exista
    SELECT c.oid INTO v_reloid
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = p_esquema AND c.relname = p_tabla;

    IF v_reloid IS NULL THEN
        RAISE EXCEPTION 'CRUDGEN:TABLA_NO_EXISTE: la tabla %.% no existe', p_esquema, p_tabla;
    END IF;

    RETURN QUERY
    SELECT
        col.column_name::TEXT,
        col.udt_name::TEXT AS tipo,
        col.ordinal_position::INT AS orden,
        COALESCE(pk.es_pk, false) AS es_pk,
        (
            col.column_default IS NOT NULL
            OR col.is_identity = 'YES'
        ) AS es_autogenerada,
        col.column_default::TEXT AS valor_default,
        (col.is_nullable = 'YES') AS es_nullable
    FROM information_schema.columns col
    LEFT JOIN (
        SELECT a.attname AS column_name, true AS es_pk
        FROM pg_index i
        JOIN pg_attribute a
          ON a.attrelid = i.indrelid AND a.attnum = ANY(i.indkey)
        WHERE i.indrelid = v_reloid AND i.indisprimary
    ) pk ON pk.column_name = col.column_name
    WHERE col.table_schema = p_esquema AND col.table_name = p_tabla
    ORDER BY col.ordinal_position;
END;
$$;
