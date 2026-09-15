"""
Aplicación Python - Generador automático de CRUD para PostgreSQL.

Flujo mínimo (ver enunciado):
Conectar -> Verificar conexión -> Verificar extensión -> Seleccionar esquema
-> Seleccionar tablas -> Analizar estructura -> Seleccionar operaciones CRUD
-> Generar procedimientos -> Seleccionar usuarios/roles -> Asignar privilegios
-> Aplicar configuración -> Mostrar resultado

Este módulo NO debe contener lógica de generación de SQL específica de
tabla alguna: eso vive en la extensión (ver ../CONTRATO.md).
"""

import psycopg


def conectar(host: str, puerto: int, base_datos: str, usuario: str, contrasena: str):
    """Establece y valida la conexión. Lanza excepción si falla."""
    conn = psycopg.connect(
        host=host, port=puerto, dbname=base_datos, user=usuario, password=contrasena
    )
    return conn


def verificar_extension(conn) -> dict:
    """Llama a crudgen.verificar_extension(). Ver CONTRATO.md sección 1."""
    with conn.cursor() as cur:
        cur.execute("SELECT * FROM crudgen.verificar_extension();")
        fila = cur.fetchone()
        return {
            "instalada": fila[0],
            "disponible_para_usuario": fila[1],
            "version": fila[2],
        }


def listar_esquemas(conn) -> list[str]:
    """Ver CONTRATO.md sección 2."""
    with conn.cursor() as cur:
        cur.execute("SELECT nombre_esquema FROM crudgen.listar_esquemas();")
        return [r[0] for r in cur.fetchall()]


# TODO: listar_tablas, analizar_tabla, generar_crud, asignar_privilegio,
# revocar_privilegio -- wrappers análogos a los de arriba, siguiendo
# CONTRATO.md. Responsable: C.

# TODO: capa de UI (CLI o gráfica) que orqueste el flujo completo.


if __name__ == "__main__":
    print("Generador CRUD - punto de entrada. Implementar flujo (ver docstring).")
