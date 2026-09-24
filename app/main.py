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
import configparser
from pathlib import Path

def conectar(host: str, puerto: int, base_datos: str, usuario: str, contrasena: str):
    """Establece y valida la conexión. Lanza excepción si falla."""
    conn = psycopg.connect(
        host=host, port=puerto, dbname=base_datos, user=usuario, password=contrasena,
        autocommit=True
    )
    return conn

def cargar_config() -> dict:
    """Lee app/config.ini. Ver config.ejemplo.ini para el formato."""
    ruta = Path(__file__).parent / "config.ini"
    config = configparser.ConfigParser()
    if not config.read(ruta):
        raise FileNotFoundError(
            f"No existe {ruta}. Copia config.ejemplo.ini como config.ini y pon tus datos."
        )
    pg = config["postgres"]
    return {
        "host": pg["host"],
        "puerto": pg.getint("puerto"),
        "base_datos": pg["base_datos"],
        "usuario": pg["usuario"],
        "contrasena": pg["contrasena"],
    }


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

def listar_tablas(conn, esquema: str) -> list[dict]:
    """Ver CONTRATO.md sección 3."""
    with conn.cursor() as cur:
        cur.execute(
            "SELECT nombre_tabla, tiene_pk FROM crudgen.listar_tablas(%s);",
            (esquema,),
        )
        return [
            {"nombre_tabla": r[0], "tiene_pk": r[1]}
            for r in cur.fetchall()
        ]
    
def analizar_tabla(conn, esquema: str, tabla: str) -> list[dict]:
    """Ver CONTRATO.md sección 4."""
    with conn.cursor() as cur:
        cur.execute(
            """
            SELECT columna, tipo, orden, es_pk, es_autogenerada,
                   valor_default, es_nullable
            FROM crudgen.analizar_tabla(%s, %s);
            """,
            (esquema, tabla),
        )
        return [
            {
                "columna": r[0],
                "tipo": r[1],
                "orden": r[2],
                "es_pk": r[3],
                "es_autogenerada": r[4],
                "valor_default": r[5],
                "es_nullable": r[6],
            }
            for r in cur.fetchall()
        ] 

def generar_crud(conn, esquema: str, tabla: str, operaciones: list[str]) -> list[dict]:
    """Ver CONTRATO.md sección 5."""
    with conn.cursor() as cur:
        cur.execute(
            """
            SELECT operacion, nombre_procedimiento, ya_existia
            FROM crudgen.generar_crud(%s, %s, %s);
            """,
            (esquema, tabla, operaciones),
        )
        return [
            {
                "operacion": r[0],
                "nombre_procedimiento": r[1],
                "ya_existia": r[2],
            }
            for r in cur.fetchall()
        ]

def asignar_privilegio(conn, esquema: str, procedimiento: str, rol: str) -> bool:
    """Ver CONTRATO.md sección 6."""
    with conn.cursor() as cur:
        cur.execute(
            "SELECT crudgen.asignar_privilegio(%s, %s, %s);",
            (esquema, procedimiento, rol),
        )
        return cur.fetchone()[0]


def revocar_privilegio(conn, esquema: str, procedimiento: str, rol: str) -> bool:
    """Ver CONTRATO.md sección 7."""
    with conn.cursor() as cur:
        cur.execute(
            "SELECT crudgen.revocar_privilegio(%s, %s, %s);",
            (esquema, procedimiento, rol),
        )
        return cur.fetchone()[0]

# TODO: capa de UI (CLI o gráfica) que orqueste el flujo completo.

if __name__ == "__main__":
    cfg = cargar_config()
    conn = conectar(**cfg)
 
    print(verificar_extension(conn))
    print(listar_esquemas(conn))
    for col in analizar_tabla(conn, "ventas", "clientes"):
        print(col)
    for t in listar_tablas(conn, "ventas"):
        print(t)
    for r in generar_crud(conn, "ventas", "clientes", ["INSERT", "SELECT"]):
        print(r)

    print(asignar_privilegio(conn, "ventas", "clientes_insertar", "vendedor"))
    print(asignar_privilegio(conn, "ventas", "clientes_consultar", "vendedor"))
    print(revocar_privilegio(conn, "ventas", "clientes_insertar", "vendedor"))

    conn.close()