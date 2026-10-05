# Guion del video de evidencia (Entregable 3)

Duración sugerida: 6–8 minutos. Tener lista la base `proyecto_demo` **sin** la extensión instalada y con el esquema `demo` ya creado (`pruebas/01_tablas_prueba.sql` sin su primera línea `CREATE EXTENSION`, o recrear la base). Tener dos terminales: una con `psql` y otra para la app.

| # | Punto del enunciado | Qué mostrar |
|---|---|---|
| 1 | Instalación de la extensión | Terminal en `extension/`: `sudo make install`. En `psql`: `CREATE EXTENSION crudgen;` y `\dx` para ver la versión. `GRANT USAGE ON SCHEMA crudgen TO <usuario_app>;` |
| 2 | Conexión mediante Python | `python main.py`: mostrar la conexión (probar primero con una contraseña mala para ver el error y el reintento, luego la correcta) |
| 3 | Detección de la extensión | Mostrar el estado `INSTALADA`. (Opcional, antes: conectar a una base sin la extensión para mostrar `NO_INSTALADA`) |
| 4 | Selección del esquema | Elegir `demo` |
| 5 | Selección de tablas | Mostrar la selección de una, varias y todas (`*`). Señalar `bitacora (sin PK...)` |
| 6 | Generación de procedimientos | Mostrar la estructura analizada (PK, autogeneradas, defaults), elegir las 4 operaciones y la tabla de resultado. Ver el código de `cliente_insertar` y de `inscripcion_actualizar` (PK compuesta) |
| 7 | Ejecución de los procedimientos | Menú → "Ejecutar un procedimiento": `cliente_insertar` (omitiendo opcionales), `cliente_consultar`, `inscripcion_actualizar` con los dos campos de la PK, `producto_insertar` (identity + generated) |
| 8 | Asignación de privilegios | Elegir `vendedor`, `supervisor`, `administrador` y configurar la matriz; mostrar la tabla de GRANT/REVOKE aplicados |
| 9 | Validación con distintos usuarios | Menú → "Ejecutar como otro rol": `vendedor` inserta (✓) y actualiza (✗ permission denied); `supervisor` actualiza (✓) y elimina (✗); `administrador` elimina (✓) |
| 10 | Tablas no usadas en el desarrollo | Crear en `psql` una tabla nueva (ej. `demo.libro` con PK compuesta y un `serial` o `DEFAULT now()`), volver a la app → "Generar para otras tablas" y ejecutar sus procedimientos |

Sugerencia extra: mostrar al final `psql -f pruebas/03_prueba_automatica.sql` terminando en `TODAS LAS PRUEBAS PASARON`.
