-- =====================================================================
-- Módulo de Omaru (Persona 2)
-- generar_crud, asignar_privilegio, revocar_privilegio
--
-- Decisiones de diseño aplicadas (ya acordadas para el CONTRATO.md):
--   - INSERT / UPDATE / DELETE -> PROCEDURE (se llaman con CALL)
--   - SELECT                   -> FUNCTION  (se llama con SELECT * FROM ...)
--   - SECURITY DEFINER en todos, con search_path fijo (evita hijacking)
--   - Convención de nombres: <tabla>_insertar / _consultar / _actualizar / _eliminar
--   - SELECT generado: parámetros de PK opcionales (NULL = trae todo)
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
    v_op                TEXT;
    v_col               RECORD;
    v_pk_cols           TEXT[] := ARRAY[]::TEXT[];
    v_insert_cols       TEXT[] := ARRAY[]::TEXT[];
    v_insert_params     TEXT[] := ARRAY[]::TEXT[];
    v_insert_param_defs TEXT[] := ARRAY[]::TEXT[];
    v_pk_param_defs     TEXT[] := ARRAY[]::TEXT[];   -- p_col tipo   (obligatorios, para UPDATE/DELETE)
    v_pk_param_defs_opt TEXT[] := ARRAY[]::TEXT[];   -- p_col tipo DEFAULT NULL (para SELECT)
    v_update_param_defs TEXT[] := ARRAY[]::TEXT[];
    v_set_clauses       TEXT[] := ARRAY[]::TEXT[];
    v_where_pk          TEXT;
    v_pk_notnull_check  TEXT;
    v_nombre_proc       TEXT;
    v_sql               TEXT;
    v_ya_existia        BOOLEAN;
BEGIN
    -- 1. Validar que las operaciones pedidas sean válidas
    FOREACH v_op IN ARRAY p_operaciones LOOP
        IF v_op NOT IN ('INSERT','SELECT','UPDATE','DELETE') THEN
            RAISE EXCEPTION 'CRUDGEN:OPERACION_INVALIDA: % no es una operación soportada', v_op;
        END IF;
    END LOOP;

    -- 2. Leer la estructura real de la tabla (función 4 del contrato, de Jeanca)
    FOR v_col IN
        SELECT * FROM crudgen.analizar_tabla(p_esquema, p_tabla) ORDER BY orden
    LOOP
        IF v_col.es_pk THEN
            v_pk_cols       := array_append(v_pk_cols, v_col.columna);
            v_pk_param_defs := array_append(v_pk_param_defs, format('p_%s %s', v_col.columna, v_col.tipo));
            v_pk_param_defs_opt := array_append(v_pk_param_defs_opt, format('p_%s %s DEFAULT NULL', v_col.columna, v_col.tipo));
        END IF;

        IF NOT v_col.es_autogenerada THEN
            v_insert_cols       := array_append(v_insert_cols, v_col.columna);
            v_insert_params     := array_append(v_insert_params, format('p_%s', v_col.columna));
            v_insert_param_defs := array_append(v_insert_param_defs, format('p_%s %s', v_col.columna, v_col.tipo));
        END IF;

        IF NOT v_col.es_pk THEN
            v_update_param_defs := array_append(v_update_param_defs, format('p_%s %s DEFAULT NULL', v_col.columna, v_col.tipo));
            v_set_clauses       := array_append(v_set_clauses, format('%I = COALESCE(p_%s, %I)', v_col.columna, v_col.columna, v_col.columna));
        END IF;
    END LOOP;

    -- 3. Sin PK no se puede generar UPDATE/DELETE (caso límite del contrato)
    IF array_length(v_pk_cols, 1) IS NULL
       AND (p_operaciones && ARRAY['UPDATE','DELETE']) THEN
        RAISE EXCEPTION 'CRUDGEN:NO_PK: la tabla %.% no tiene clave primaria; no se puede generar UPDATE/DELETE', p_esquema, p_tabla;
    END IF;

    IF array_length(v_pk_cols, 1) IS NOT NULL THEN
        SELECT array_to_string(array_agg(format('%I = p_%s', c, c)), ' AND ')
          INTO v_where_pk
          FROM unnest(v_pk_cols) AS c;

        SELECT array_to_string(array_agg(format('p_%s IS NOT NULL', c)), ' AND ')
          INTO v_pk_notnull_check
          FROM unnest(v_pk_cols) AS c;
    END IF;

    -- 4. Generar cada operación pedida
    FOREACH v_op IN ARRAY p_operaciones LOOP
        CASE v_op

        WHEN 'INSERT' THEN
            v_nombre_proc := format('%s_insertar', p_tabla);
            SELECT EXISTS (
                SELECT 1 FROM pg_proc pr JOIN pg_namespace n ON n.oid = pr.pronamespace
                WHERE n.nspname = p_esquema AND pr.proname = v_nombre_proc
            ) INTO v_ya_existia;

            v_sql := format(
                'CREATE OR REPLACE PROCEDURE %I.%I(%s)
                 LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog AS $body$
                 BEGIN
                     INSERT INTO %I.%I (%s) VALUES (%s);
                 END; $body$;',
                p_esquema, v_nombre_proc,
                array_to_string(v_insert_param_defs, ', '),
                p_esquema, p_tabla,
                (SELECT array_to_string(array_agg(quote_ident(c)), ', ') FROM unnest(v_insert_cols) AS c),
                array_to_string(v_insert_params, ', ')
            );
            EXECUTE v_sql;
            -- Por defecto Postgres da EXECUTE a PUBLIC; sin esto la matriz
            -- de privilegios no significaría nada (cualquiera podría llamarlo).
            EXECUTE format('REVOKE EXECUTE ON PROCEDURE %I.%I FROM PUBLIC', p_esquema, v_nombre_proc);

            operacion := 'INSERT'; nombre_procedimiento := v_nombre_proc; ya_existia := v_ya_existia;
            RETURN NEXT;

        WHEN 'UPDATE' THEN
            v_nombre_proc := format('%s_actualizar', p_tabla);
            SELECT EXISTS (
                SELECT 1 FROM pg_proc pr JOIN pg_namespace n ON n.oid = pr.pronamespace
                WHERE n.nspname = p_esquema AND pr.proname = v_nombre_proc
            ) INTO v_ya_existia;

            v_sql := format(
                'CREATE OR REPLACE PROCEDURE %I.%I(%s, %s)
                 LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog AS $body$
                 BEGIN
                     UPDATE %I.%I SET %s WHERE %s;
                 END; $body$;',
                p_esquema, v_nombre_proc,
                array_to_string(v_pk_param_defs, ', '),
                array_to_string(v_update_param_defs, ', '),
                p_esquema, p_tabla,
                array_to_string(v_set_clauses, ', '),
                v_where_pk
            );
            EXECUTE v_sql;
            EXECUTE format('REVOKE EXECUTE ON PROCEDURE %I.%I FROM PUBLIC', p_esquema, v_nombre_proc);

            operacion := 'UPDATE'; nombre_procedimiento := v_nombre_proc; ya_existia := v_ya_existia;
            RETURN NEXT;

        WHEN 'DELETE' THEN
            v_nombre_proc := format('%s_eliminar', p_tabla);
            SELECT EXISTS (
                SELECT 1 FROM pg_proc pr JOIN pg_namespace n ON n.oid = pr.pronamespace
                WHERE n.nspname = p_esquema AND pr.proname = v_nombre_proc
            ) INTO v_ya_existia;

            v_sql := format(
                'CREATE OR REPLACE PROCEDURE %I.%I(%s)
                 LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog AS $body$
                 BEGIN
                     DELETE FROM %I.%I WHERE %s;
                 END; $body$;',
                p_esquema, v_nombre_proc,
                array_to_string(v_pk_param_defs, ', '),
                p_esquema, p_tabla,
                v_where_pk
            );
            EXECUTE v_sql;
            EXECUTE format('REVOKE EXECUTE ON PROCEDURE %I.%I FROM PUBLIC', p_esquema, v_nombre_proc);

            operacion := 'DELETE'; nombre_procedimiento := v_nombre_proc; ya_existia := v_ya_existia;
            RETURN NEXT;

        WHEN 'SELECT' THEN
            v_nombre_proc := format('%s_consultar', p_tabla);
            SELECT EXISTS (
                SELECT 1 FROM pg_proc pr JOIN pg_namespace n ON n.oid = pr.pronamespace
                WHERE n.nspname = p_esquema AND pr.proname = v_nombre_proc
            ) INTO v_ya_existia;

            IF array_length(v_pk_cols, 1) IS NOT NULL THEN
                v_sql := format(
                    'CREATE OR REPLACE FUNCTION %I.%I(%s)
                     RETURNS SETOF %I.%I
                     LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog AS $body$
                     BEGIN
                         IF %s THEN
                             RETURN QUERY SELECT * FROM %I.%I WHERE %s;
                         ELSE
                             RETURN QUERY SELECT * FROM %I.%I;
                         END IF;
                     END; $body$;',
                    p_esquema, v_nombre_proc,
                    array_to_string(v_pk_param_defs_opt, ', '),
                    p_esquema, p_tabla,
                    v_pk_notnull_check,
                    p_esquema, p_tabla, v_where_pk,
                    p_esquema, p_tabla
                );
            ELSE
                v_sql := format(
                    'CREATE OR REPLACE FUNCTION %I.%I()
                     RETURNS SETOF %I.%I
                     LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog AS $body$
                     BEGIN
                         RETURN QUERY SELECT * FROM %I.%I;
                     END; $body$;',
                    p_esquema, v_nombre_proc, p_esquema, p_tabla, p_esquema, p_tabla
                );
            END IF;
            EXECUTE v_sql;
            EXECUTE format('REVOKE EXECUTE ON FUNCTION %I.%I FROM PUBLIC', p_esquema, v_nombre_proc);

            operacion := 'SELECT'; nombre_procedimiento := v_nombre_proc; ya_existia := v_ya_existia;
            RETURN NEXT;

        END CASE;
    END LOOP;
END;
$$;


-- =====================================================================
-- asignar_privilegio / revocar_privilegio
-- Funcionan tanto para PROCEDURE (INSERT/UPDATE/DELETE) como para
-- FUNCTION (SELECT) porque resuelven el tipo real desde pg_proc.
-- =====================================================================

CREATE OR REPLACE FUNCTION crudgen.asignar_privilegio(
    p_esquema             TEXT,
    p_nombre_procedimiento TEXT,
    p_rol                 TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
    v_oid         OID;
    v_kind        CHAR;
    v_objeto_sql  TEXT;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = p_rol) THEN
        RAISE EXCEPTION 'CRUDGEN:ROL_NO_EXISTE: el rol % no existe', p_rol;
    END IF;

    SELECT p.oid, p.prokind INTO v_oid, v_kind
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = p_esquema AND p.proname = p_nombre_procedimiento
    LIMIT 1;

    IF v_oid IS NULL THEN
        RAISE EXCEPTION 'CRUDGEN:PROC_NO_EXISTE: %.% no existe', p_esquema, p_nombre_procedimiento;
    END IF;

    v_objeto_sql := format('%s %s',
        CASE WHEN v_kind = 'p' THEN 'PROCEDURE' ELSE 'FUNCTION' END,
        v_oid::regprocedure
    );

    -- EXECUTE sobre el procedimiento no sirve de nada sin USAGE sobre el
    -- esquema que lo contiene: sin esto el rol no puede ni referenciarlo.
    EXECUTE format('GRANT USAGE ON SCHEMA %I TO %I', p_esquema, p_rol);
    EXECUTE format('GRANT EXECUTE ON %s TO %I', v_objeto_sql, p_rol);
    RETURN TRUE;
END;
$$;


CREATE OR REPLACE FUNCTION crudgen.revocar_privilegio(
    p_esquema             TEXT,
    p_nombre_procedimiento TEXT,
    p_rol                 TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
    v_oid         OID;
    v_kind        CHAR;
    v_objeto_sql  TEXT;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = p_rol) THEN
        RAISE EXCEPTION 'CRUDGEN:ROL_NO_EXISTE: el rol % no existe', p_rol;
    END IF;

    SELECT p.oid, p.prokind INTO v_oid, v_kind
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = p_esquema AND p.proname = p_nombre_procedimiento
    LIMIT 1;

    IF v_oid IS NULL THEN
        RAISE EXCEPTION 'CRUDGEN:PROC_NO_EXISTE: %.% no existe', p_esquema, p_nombre_procedimiento;
    END IF;

    v_objeto_sql := format('%s %s',
        CASE WHEN v_kind = 'p' THEN 'PROCEDURE' ELSE 'FUNCTION' END,
        v_oid::regprocedure
    );

    EXECUTE format('REVOKE EXECUTE ON %s FROM %I', v_objeto_sql, p_rol);
    RETURN TRUE;
END;
$$;
