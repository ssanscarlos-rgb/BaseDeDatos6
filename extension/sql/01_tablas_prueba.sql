-- =====================================================================
-- Tablas de prueba obligatorias (según enunciado del proyecto)
-- Caso 1: PK simple | Caso 2: PK compuesta | Caso 3: columna autogenerada
-- =====================================================================

CREATE SCHEMA IF NOT EXISTS ventas;

-- Caso 1: clave primaria simple
DROP TABLE IF EXISTS ventas.clientes CASCADE;
CREATE TABLE ventas.clientes (
    id      SERIAL PRIMARY KEY,   -- autogenerada además de PK
    nombre  TEXT NOT NULL,
    email   TEXT
);

-- Caso 2: clave primaria compuesta
DROP TABLE IF EXISTS ventas.matricula CASCADE;
CREATE TABLE ventas.matricula (
    estudiante_id INTEGER NOT NULL,
    curso_id      INTEGER NOT NULL,
    nota          NUMERIC(4,2),
    PRIMARY KEY (estudiante_id, curso_id)
);

-- Caso 3: columna con valor autogenerado (independiente de la PK)
DROP TABLE IF EXISTS ventas.productos CASCADE;
CREATE TABLE ventas.productos (
    codigo      TEXT PRIMARY KEY,   -- PK simple, NO autogenerada
    nombre      TEXT NOT NULL,
    creado_en   TIMESTAMP NOT NULL DEFAULT now()  -- autogenerada, no es PK
);

-- Roles de prueba para privilegios
DROP ROLE IF EXISTS vendedor;
DROP ROLE IF EXISTS supervisor;
DROP ROLE IF EXISTS administrador;
CREATE ROLE vendedor LOGIN;
CREATE ROLE supervisor LOGIN;
CREATE ROLE administrador LOGIN;
