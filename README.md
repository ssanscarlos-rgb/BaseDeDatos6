# Generador automático de procedimientos CRUD para PostgreSQL

Proyecto de Bases de Datos II — ITCR, Campus San Carlos.

## Integrantes
- [ ] Nombre 1 — módulo: Extensión (análisis de catálogo + generación SELECT/INSERT)
- [ ] Nombre 2 — módulo: Extensión (generación UPDATE/DELETE + privilegios)
- [ ] Nombre 3 — módulo: Aplicación Python

## Estructura del repositorio

```
.
├── CONTRATO.md          # Contrato de interfaz extensión <-> app (leer primero)
├── extension/            # Extensión PostgreSQL
│   ├── crudgen.control
│   ├── sql/               # Scripts SQL versionados de la extensión
│   └── src/                # Código fuente (funciones, si se usa C o PL/pgSQL extenso)
├── app/                  # Aplicación Python
│   ├── main.py
│   └── requirements.txt
├── docs/                 # Documentación de uso, diagramas, matriz de privilegios
└── pruebas/               # Scripts/datos para los 3 casos de prueba obligatorios
```

## Flujo de trabajo (Git)

- `main` → solo versiones estables/entregables.
- `develop` → rama de integración.
- `feature/<algo>` → una rama por tarea/módulo, se mergea a `develop` seguido (no acumular cambios grandes).

Antes de programar, lean `CONTRATO.md`. Si necesitan cambiar la firma de una función ya acordada, avísenlo al equipo antes de tocar el código.

## Cómo levantar el entorno (completar conforme avancen)

```bash
# Instalar la extensión (ejemplo)
cd extension
make && make install
psql -c "CREATE EXTENSION crudgen;"

# App Python
cd app
pip install -r requirements.txt
python main.py
```
