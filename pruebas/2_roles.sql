-- 02_roles.sql
-- Roles de la prueba de privilegios (3 niveles de acceso). Se pueden
-- correr varias veces. NOLOGIN: se prueban con SET ROLE desde la app.
-- (Si quieren probar con login real, cambien NOLOGIN por
--  LOGIN PASSWORD '...'.)

DO $$
DECLARE r TEXT;
BEGIN
    FOREACH r IN ARRAY ARRAY['vendedor', 'supervisor', 'administrador'] LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = r) THEN
            EXECUTE format('CREATE ROLE %I NOLOGIN', r);
        END IF;
    END LOOP;
END $$;

-- Matriz esperada (la aplica la app Python, o 03_prueba_automatica.sql):
--   vendedor       : insertar, consultar
--   supervisor     : insertar, consultar, actualizar
--   administrador  : insertar, consultar, actualizar, eliminar
