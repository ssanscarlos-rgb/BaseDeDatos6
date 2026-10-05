-- 01_tablas_prueba.sql
-- Esquema "demo" con las tablas de prueba. Se puede correr varias veces:
-- recrea el esquema completo (borra también los procedimientos generados).
-- Ejecutar con un usuario que pueda crear esquemas y la extensión
-- (ej. postgres):  psql -d proyecto_demo -f 01_tablas_prueba.sql

CREATE EXTENSION IF NOT EXISTS crudgen;

DROP SCHEMA IF EXISTS demo CASCADE;
CREATE SCHEMA demo;

-- CASO 1 (obligatorio) - Clave primaria SIMPLE.
-- Además: serial, columnas con DEFAULT y una columna opcional (email).
CREATE TABLE demo.cliente (
    id      serial       PRIMARY KEY,
    nombre  varchar(80)  NOT NULL,
    email   text,
    activo  boolean      NOT NULL DEFAULT true,
    creado  timestamptz  NOT NULL DEFAULT now()
);

-- CASO 2 (obligatorio) - Clave primaria COMPUESTA (2 columnas).
CREATE TABLE demo.inscripcion (
    estudiante_id  int          NOT NULL,
    curso_id       int          NOT NULL,
    nota           numeric(4,1),
    fecha          date         NOT NULL DEFAULT current_date,
    PRIMARY KEY (estudiante_id, curso_id)
);

-- CASO 3 (obligatorio) - Valores GENERADOS automáticamente:
-- IDENTITY y columna GENERATED ... STORED.
CREATE TABLE demo.producto (
    id      int           GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre  text          NOT NULL,
    precio  numeric(10,2) NOT NULL,
    iva     numeric(10,2) GENERATED ALWAYS AS (precio * 0.13) STORED
);

-- ---- Casos borde adicionales ------------------------------------------

-- Sin clave primaria: solo admite INSERT y SELECT.
CREATE TABLE demo.bitacora (
    mensaje text        NOT NULL,
    fecha   timestamptz DEFAULT now()
);

-- Toda la tabla es la PK (relación N:M pura): no admite UPDATE.
CREATE TABLE demo.matricula (
    estudiante_id int NOT NULL,
    curso_id      int NOT NULL,
    PRIMARY KEY (estudiante_id, curso_id)
);

-- Única columna autogenerada: el INSERT debe usar DEFAULT VALUES.
CREATE TABLE demo.contador (
    id serial PRIMARY KEY
);

-- Nombres con espacios, mayúsculas, tildes y palabras reservadas.
CREATE TABLE demo."Orden Detalle" (
    "Código Único"  int     PRIMARY KEY,
    "order"         text    NOT NULL,
    "user"          text    DEFAULT 'anonimo',
    "Precio Total"  numeric
);

-- Tipo definido por el usuario (enum) con DEFAULT.
CREATE TYPE demo.estado AS ENUM ('nuevo', 'listo', 'entregado');
CREATE TABLE demo.pedido (
    id      int         PRIMARY KEY,
    estado  demo.estado NOT NULL DEFAULT 'nuevo'
);
