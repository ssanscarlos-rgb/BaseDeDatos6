-- 03_prueba_automatica.sql
-- Prueba de extremo a extremo SOLO con SQL (sin la app Python).
-- Requiere haber corrido antes 01_tablas_prueba.sql y 02_roles.sql.
-- Ejecutar con un superusuario (ej. postgres):
--     psql -d proyecto_demo -v ON_ERROR_STOP=1 -f 03_prueba_automatica.sql
-- Si algo falla se corta con "FALLO: ..."; si todo pasa termina con
-- "TODAS LAS PRUEBAS PASARON".

\set ON_ERROR_STOP on
SET client_min_messages = notice;

-- ---------------------------------------------------------------------
-- A. Generación sobre todas las tablas
-- ---------------------------------------------------------------------
DO $$
DECLARE
    t TEXT;
    n INT;
BEGIN
    -- Tablas con PK y columnas actualizables: las 4 operaciones
    FOREACH t IN ARRAY ARRAY['cliente','inscripcion','producto','Orden Detalle','pedido'] LOOP
        PERFORM crudgen.generar_crud('demo', t, ARRAY['INSERT','SELECT','UPDATE','DELETE']);
    END LOOP;

    -- Sin PK: solo INSERT y SELECT
    PERFORM crudgen.generar_crud('demo', 'bitacora', ARRAY['INSERT','SELECT']);
    -- Solo PK / solo serial: sin UPDATE
    PERFORM crudgen.generar_crud('demo', 'matricula', ARRAY['INSERT','SELECT','DELETE']);
    PERFORM crudgen.generar_crud('demo', 'contador',  ARRAY['INSERT','SELECT','DELETE']);

    SELECT count(*) INTO n FROM crudgen.listar_procedimientos_generados('demo');
    IF n <> 5*4 + 2 + 3 + 3 THEN
        RAISE EXCEPTION 'FALLO: se esperaban 28 procedimientos generados y hay %', n;
    END IF;
    RAISE NOTICE 'OK A: generación (28 procedimientos)';
END $$;

-- ---------------------------------------------------------------------
-- B. Errores esperados
-- ---------------------------------------------------------------------
DO $$
BEGIN
    BEGIN
        PERFORM crudgen.generar_crud('demo', 'bitacora', ARRAY['UPDATE']);
        RAISE EXCEPTION 'FALLO: UPDATE sobre tabla sin PK no lanzó error';
    EXCEPTION WHEN raise_exception THEN
        IF SQLERRM NOT LIKE 'CRUDGEN:NO_PK:%' THEN RAISE; END IF;
    END;

    BEGIN
        PERFORM crudgen.generar_crud('demo', 'matricula', ARRAY['UPDATE']);
        RAISE EXCEPTION 'FALLO: UPDATE sobre tabla de solo-PK no lanzó error';
    EXCEPTION WHEN raise_exception THEN
        IF SQLERRM NOT LIKE 'CRUDGEN:SIN_COLUMNAS_ACTUALIZABLES:%' THEN RAISE; END IF;
    END;

    BEGIN
        PERFORM crudgen.generar_crud('demo', 'no_existe', ARRAY['INSERT']);
        RAISE EXCEPTION 'FALLO: tabla inexistente no lanzó error';
    EXCEPTION WHEN raise_exception THEN
        IF SQLERRM NOT LIKE 'CRUDGEN:TABLA_NO_EXISTE:%' THEN RAISE; END IF;
    END;

    BEGIN
        PERFORM crudgen.generar_crud('demo', 'cliente', ARRAY['TRUNCATE']);
        RAISE EXCEPTION 'FALLO: operación inválida no lanzó error';
    EXCEPTION WHEN raise_exception THEN
        IF SQLERRM NOT LIKE 'CRUDGEN:OPERACION_INVALIDA:%' THEN RAISE; END IF;
    END;

    RAISE NOTICE 'OK B: errores esperados (NO_PK, SIN_COLUMNAS_ACTUALIZABLES, TABLA_NO_EXISTE, OPERACION_INVALIDA)';
END $$;

-- ---------------------------------------------------------------------
-- C. Caso 1: PK simple + serial + DEFAULT + columna opcional
-- ---------------------------------------------------------------------
DO $$
DECLARE r demo.cliente; n INT;
BEGIN
    CALL demo.cliente_insertar(p_nombre => 'Ana');                    -- email, activo, creado omitidos
    CALL demo.cliente_insertar(p_nombre => 'Beto', p_email => 'b@x.com', p_activo => false);

    SELECT * INTO r FROM demo.cliente WHERE nombre = 'Ana';
    IF r.id IS NULL OR r.activo IS NOT TRUE OR r.creado IS NULL OR r.email IS NOT NULL THEN
        RAISE EXCEPTION 'FALLO C: defaults/serial de Ana incorrectos: %', r;
    END IF;
    SELECT * INTO r FROM demo.cliente WHERE nombre = 'Beto';
    IF r.activo IS NOT FALSE OR r.email <> 'b@x.com' THEN
        RAISE EXCEPTION 'FALLO C: valores explícitos de Beto incorrectos: %', r;
    END IF;

    SELECT count(*) INTO n FROM demo.cliente_consultar();
    IF n <> 2 THEN RAISE EXCEPTION 'FALLO C: consultar() devolvió % filas', n; END IF;
    SELECT * INTO r FROM demo.cliente_consultar(p_id => (SELECT id FROM demo.cliente WHERE nombre = 'Beto'));
    IF r.nombre <> 'Beto' THEN RAISE EXCEPTION 'FALLO C: consultar por PK'; END IF;

    CALL demo.cliente_actualizar(p_id => r.id, p_email => 'nuevo@x.com');   -- solo cambia email
    SELECT * INTO r FROM demo.cliente WHERE id = r.id;
    IF r.email <> 'nuevo@x.com' OR r.nombre <> 'Beto' THEN
        RAISE EXCEPTION 'FALLO C: update parcial: %', r;
    END IF;

    CALL demo.cliente_eliminar(p_id => r.id);
    SELECT count(*) INTO n FROM demo.cliente;
    IF n <> 1 THEN RAISE EXCEPTION 'FALLO C: delete'; END IF;
    RAISE NOTICE 'OK C: caso 1 (PK simple, serial, defaults)';
END $$;

-- ---------------------------------------------------------------------
-- D. Caso 2: PK compuesta
-- ---------------------------------------------------------------------
DO $$
DECLARE r demo.inscripcion; n INT;
BEGIN
    CALL demo.inscripcion_insertar(p_estudiante_id => 1, p_curso_id => 10, p_nota => 80);
    CALL demo.inscripcion_insertar(p_estudiante_id => 1, p_curso_id => 20);
    CALL demo.inscripcion_insertar(p_estudiante_id => 2, p_curso_id => 10);

    -- UPDATE con PK completa: solo afecta una fila
    CALL demo.inscripcion_actualizar(p_estudiante_id => 1, p_curso_id => 20, p_nota => 95);
    SELECT * INTO r FROM demo.inscripcion WHERE estudiante_id = 1 AND curso_id = 20;
    IF r.nota <> 95 THEN RAISE EXCEPTION 'FALLO D: update PK compuesta'; END IF;
    SELECT * INTO r FROM demo.inscripcion WHERE estudiante_id = 1 AND curso_id = 10;
    IF r.nota <> 80 THEN RAISE EXCEPTION 'FALLO D: el update tocó otra fila'; END IF;

    -- SELECT por parte de la PK y por la PK completa
    SELECT count(*) INTO n FROM demo.inscripcion_consultar(p_estudiante_id => 1);
    IF n <> 2 THEN RAISE EXCEPTION 'FALLO D: consultar por parte de la PK dio %', n; END IF;
    SELECT count(*) INTO n FROM demo.inscripcion_consultar(p_estudiante_id => 1, p_curso_id => 10);
    IF n <> 1 THEN RAISE EXCEPTION 'FALLO D: consultar por PK completa dio %', n; END IF;

    -- DELETE con PK completa: solo una fila
    CALL demo.inscripcion_eliminar(p_estudiante_id => 1, p_curso_id => 10);
    SELECT count(*) INTO n FROM demo.inscripcion;
    IF n <> 2 THEN RAISE EXCEPTION 'FALLO D: delete PK compuesta dejó % filas', n; END IF;
    RAISE NOTICE 'OK D: caso 2 (PK compuesta)';
END $$;

-- ---------------------------------------------------------------------
-- E. Caso 3: IDENTITY + columna GENERATED
-- ---------------------------------------------------------------------
DO $$
DECLARE r demo.producto;
BEGIN
    CALL demo.producto_insertar(p_nombre => 'Teclado', p_precio => 100);
    SELECT * INTO r FROM demo.producto WHERE nombre = 'Teclado';
    IF r.id IS NULL OR r.iva <> 13 THEN RAISE EXCEPTION 'FALLO E: identity/generated: %', r; END IF;

    CALL demo.producto_actualizar(p_id => r.id, p_precio => 200);   -- iva se recalcula solo
    SELECT * INTO r FROM demo.producto WHERE id = r.id;
    IF r.iva <> 26 THEN RAISE EXCEPTION 'FALLO E: iva tras update: %', r; END IF;
    RAISE NOTICE 'OK E: caso 3 (identity + generated)';
END $$;

-- ---------------------------------------------------------------------
-- F. Casos borde: sin PK, solo-serial, nombres raros, enum
-- ---------------------------------------------------------------------
DO $$
DECLARE n INT; e demo.estado; u TEXT;
BEGIN
    CALL demo.bitacora_insertar(p_mensaje => 'hola');
    SELECT count(*) INTO n FROM demo.bitacora_consultar();
    IF n <> 1 THEN RAISE EXCEPTION 'FALLO F: bitacora'; END IF;

    CALL demo.contador_insertar();                      -- DEFAULT VALUES
    CALL demo.contador_insertar();
    SELECT count(*) INTO n FROM demo.contador;
    IF n <> 2 THEN RAISE EXCEPTION 'FALLO F: contador (DEFAULT VALUES)'; END IF;

    CALL demo.matricula_insertar(p_estudiante_id => 1, p_curso_id => 1);
    CALL demo.matricula_eliminar(p_estudiante_id => 1, p_curso_id => 1);

    -- Nombres con espacios, mayúsculas, tildes y palabras reservadas
    CALL demo."Orden Detalle_insertar"("p_Código Único" => 7, p_order => 'urgente');
    SELECT "user" INTO u FROM demo."Orden Detalle" WHERE "Código Único" = 7;
    IF u <> 'anonimo' THEN RAISE EXCEPTION 'FALLO F: default de "user": %', u; END IF;
    CALL demo."Orden Detalle_actualizar"("p_Código Único" => 7, "p_Precio Total" => 99.5);
    IF (SELECT "Precio Total" FROM demo."Orden Detalle_consultar"("p_Código Único" => 7)) <> 99.5 THEN
        RAISE EXCEPTION 'FALLO F: nombres con espacios';
    END IF;
    CALL demo."Orden Detalle_eliminar"("p_Código Único" => 7);

    -- Enum con default (tipo definido por el usuario)
    CALL demo.pedido_insertar(p_id => 1);
    SELECT estado INTO e FROM demo.pedido WHERE id = 1;
    IF e <> 'nuevo' THEN RAISE EXCEPTION 'FALLO F: default de enum: %', e; END IF;
    CALL demo.pedido_actualizar(p_id => 1, p_estado => 'listo');
    SELECT estado INTO e FROM demo.pedido WHERE id = 1;
    IF e <> 'listo' THEN RAISE EXCEPTION 'FALLO F: update de enum'; END IF;
    RAISE NOTICE 'OK F: casos borde (sin PK, DEFAULT VALUES, nombres raros, enum)';
END $$;

-- ---------------------------------------------------------------------
-- G. Regenerar tras ALTER TABLE: sin sobrecargas duplicadas
-- ---------------------------------------------------------------------
ALTER TABLE demo.cliente ADD COLUMN telefono text;
DO $$
DECLARE n INT; ya BOOLEAN;
BEGIN
    SELECT bool_and(g.ya_existia) INTO ya
    FROM crudgen.generar_crud('demo', 'cliente', ARRAY['INSERT','SELECT','UPDATE','DELETE']) g;
    IF ya IS NOT TRUE THEN RAISE EXCEPTION 'FALLO G: ya_existia debía ser true'; END IF;

    SELECT count(*) INTO n FROM pg_proc p JOIN pg_namespace s ON s.oid = p.pronamespace
    WHERE s.nspname = 'demo' AND p.proname = 'cliente_insertar';
    IF n <> 1 THEN RAISE EXCEPTION 'FALLO G: % sobrecargas de cliente_insertar', n; END IF;

    CALL demo.cliente_insertar(p_nombre => 'Carla', p_telefono => '8888-0000');
    IF (SELECT telefono FROM demo.cliente WHERE nombre = 'Carla') <> '8888-0000' THEN
        RAISE EXCEPTION 'FALLO G: la columna nueva no se insertó';
    END IF;
    RAISE NOTICE 'OK G: regeneración tras ALTER TABLE (sin sobrecargas duplicadas)';
END $$;

-- ---------------------------------------------------------------------
-- H. Privilegios con 3 roles (matriz del enunciado)
--    vendedor: ins+con | supervisor: ins+con+act | administrador: todo
-- ---------------------------------------------------------------------
DO $$
DECLARE
    ops   TEXT[] := ARRAY['insertar','consultar','actualizar','eliminar'];
    mat   JSONB  := '{"vendedor":[1,1,0,0],"supervisor":[1,1,1,0],"administrador":[1,1,1,1]}';
    rol   TEXT;
    i     INT;
BEGIN
    FOR rol IN SELECT jsonb_object_keys(mat) LOOP
        FOR i IN 1..4 LOOP
            IF (mat -> rol ->> (i-1))::INT = 1 THEN
                PERFORM crudgen.asignar_privilegio('demo', 'cliente_' || ops[i], rol);
            ELSE
                PERFORM crudgen.revocar_privilegio('demo', 'cliente_' || ops[i], rol);
            END IF;
        END LOOP;
    END LOOP;
    RAISE NOTICE 'OK H1: matriz aplicada';
END $$;

DO $$
DECLARE
    id_cli INT;
BEGIN
    SELECT id INTO id_cli FROM demo.cliente WHERE nombre = 'Ana';

    -- vendedor: puede insertar y consultar...
    SET LOCAL ROLE vendedor;
    CALL demo.cliente_insertar(p_nombre => 'Hecho por vendedor');
    PERFORM * FROM demo.cliente_consultar();
    -- ...pero NO actualizar ni eliminar
    BEGIN
        CALL demo.cliente_actualizar(p_id => id_cli, p_nombre => 'x');
        RAISE EXCEPTION 'FALLO H: vendedor pudo actualizar';
    EXCEPTION WHEN insufficient_privilege THEN NULL; END;
    BEGIN
        CALL demo.cliente_eliminar(p_id => id_cli);
        RAISE EXCEPTION 'FALLO H: vendedor pudo eliminar';
    EXCEPTION WHEN insufficient_privilege THEN NULL; END;
    -- y no puede tocar la tabla directamente
    BEGIN
        PERFORM * FROM demo.cliente;
        RAISE EXCEPTION 'FALLO H: vendedor leyó la tabla directamente';
    EXCEPTION WHEN insufficient_privilege THEN NULL; END;
    RESET ROLE;

    -- supervisor: actualiza pero NO elimina
    SET LOCAL ROLE supervisor;
    CALL demo.cliente_actualizar(p_id => id_cli, p_nombre => 'Ana M.');
    BEGIN
        CALL demo.cliente_eliminar(p_id => id_cli);
        RAISE EXCEPTION 'FALLO H: supervisor pudo eliminar';
    EXCEPTION WHEN insufficient_privilege THEN NULL; END;
    RESET ROLE;

    -- administrador: elimina
    SET LOCAL ROLE administrador;
    CALL demo.cliente_eliminar(p_id => id_cli);
    RESET ROLE;

    -- Un rol sin ningún GRANT (PUBLIC revocado) no puede nada
    BEGIN
        CREATE ROLE intruso NOLOGIN;
    EXCEPTION WHEN duplicate_object THEN NULL; END;
    SET LOCAL ROLE intruso;
    BEGIN
        CALL demo.cliente_insertar(p_nombre => 'x');
        RAISE EXCEPTION 'FALLO H: rol sin privilegios pudo insertar';
    EXCEPTION WHEN insufficient_privilege THEN NULL; END;
    RESET ROLE;

    RAISE NOTICE 'OK H2: privilegios verificados con vendedor, supervisor, administrador (+ rol sin permisos)';
END $$;

-- Limpieza del rol auxiliar
DROP ROLE IF EXISTS intruso;

SELECT 'TODAS LAS PRUEBAS PASARON' AS resultado;
