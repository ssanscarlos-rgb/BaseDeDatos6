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

class CrudgenError(Exception):
    """Error esperado de la extensión, con formato CRUDGEN:<CODIGO>: <mensaje>."""

    def __init__(self, codigo: str, mensaje: str):
        super().__init__(mensaje)
        self.codigo = codigo
        self.mensaje = mensaje

def _ejecutar(conn, consulta, params: tuple = (), con_columnas: bool = False):
    """Ejecuta una consulta y devuelve sus filas (o [] si no produce resultado).
    Con con_columnas=True devuelve (nombres_de_columnas, filas).
    Traduce los errores CRUDGEN:... de la extensión a CrudgenError."""
    try:
        with conn.cursor() as cur:
            cur.execute(consulta, params)
            if cur.description is None:          # CALL, GRANT, etc.: no hay filas
                filas, columnas = [], []
            else:
                filas = cur.fetchall()
                columnas = [c.name for c in cur.description]
            return (columnas, filas) if con_columnas else filas
    except psycopg.Error as e:
        mensaje = e.diag.message_primary or str(e)
        if mensaje.startswith("CRUDGEN:"):
            _, codigo, texto = mensaje.split(":", 2)
            raise CrudgenError(codigo, texto.strip()) from e
        raise

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
    """Determina el estado de crudgen en la base conectada.
    estado: INSTALADA, NO_INSTALADA, SIN_ARCHIVOS, SIN_PERMISOS o ERROR."""
    try:
        # 1. ¿Está instalada en esta base?
        filas = _ejecutar(
            conn, "SELECT extversion FROM pg_extension WHERE extname = 'crudgen';"
        )
        if not filas:
            # 2. No está instalada. ¿Al menos están los archivos en el servidor?
            disponible = _ejecutar(
                conn,
                "SELECT 1 FROM pg_available_extensions WHERE name = 'crudgen';",
            )
            if disponible:
                return {
                    "estado": "NO_INSTALADA",
                    "mensaje": "Los archivos están en el servidor, pero falta "
                               "CREATE EXTENSION crudgen en esta base.",
                }
            return {
                "estado": "SIN_ARCHIVOS",
                "mensaje": "La extensión no está instalada ni sus archivos "
                           "están en el servidor.",
            }

        version = filas[0][0]

        # 3. Está instalada. ¿El usuario puede usarla?
        fila = _ejecutar(conn, "SELECT * FROM crudgen.verificar_extension();")[0]
        if not fila[1]:  # disponible_para_usuario
            return {
                "estado": "SIN_PERMISOS",
                "mensaje": "La extensión está instalada, pero el usuario "
                           "conectado no tiene permisos para usarla.",
            }
        return {
            "estado": "INSTALADA",
            "mensaje": f"Extensión crudgen {version} lista.",
        }

    except psycopg.errors.InsufficientPrivilege:
        return {
            "estado": "SIN_PERMISOS",
            "mensaje": "La extensión está instalada, pero el usuario "
                       "conectado no tiene permisos para usarla.",
        }
    except psycopg.Error as e:
        return {"estado": "ERROR", "mensaje": f"Error al consultar la extensión: {e}"}


def listar_esquemas(conn) -> list[str]:
    """Ver CONTRATO.md sección 2."""
    filas = _ejecutar(conn, "SELECT nombre_esquema FROM crudgen.listar_esquemas();")
    return [r[0] for r in filas]


# TODO: listar_tablas, analizar_tabla, generar_crud, asignar_privilegio,
# revocar_privilegio -- wrappers análogos a los de arriba, siguiendo
# CONTRATO.md. Responsable: C.

def listar_tablas(conn, esquema: str) -> list[dict]:
    """Ver CONTRATO.md sección 3."""
    filas = _ejecutar(
        conn,
        "SELECT nombre_tabla, tiene_pk FROM crudgen.listar_tablas(%s);",
        (esquema,),
    )
    return [{"nombre_tabla": r[0], "tiene_pk": r[1]} for r in filas]
    

def analizar_tabla(conn, esquema: str, tabla: str) -> list[dict]:
    """Ver CONTRATO.md sección 4."""
    filas = _ejecutar(
        conn,
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
        for r in filas
    ]

def generar_crud(conn, esquema: str, tabla: str, operaciones: list[str]) -> list[dict]:
    """Ver CONTRATO.md sección 5."""
    filas = _ejecutar(
        conn,
        """
        SELECT operacion, nombre_procedimiento, ya_existia
        FROM crudgen.generar_crud(%s, %s, %s);
        """,
        (esquema, tabla, operaciones),
    )
    return [
        {"operacion": r[0], "nombre_procedimiento": r[1], "ya_existia": r[2]}
        for r in filas
    ]


def asignar_privilegio(conn, esquema: str, procedimiento: str, rol: str) -> bool:
    """Ver CONTRATO.md sección 6."""
    filas = _ejecutar(
        conn,
        "SELECT crudgen.asignar_privilegio(%s, %s, %s);",
        (esquema, procedimiento, rol),
    )
    return filas[0][0]


def revocar_privilegio(conn, esquema: str, procedimiento: str, rol: str) -> bool:
    """Ver CONTRATO.md sección 7."""
    filas = _ejecutar(
        conn,
        "SELECT crudgen.revocar_privilegio(%s, %s, %s);",
        (esquema, procedimiento, rol),
    )
    return filas[0][0]

def obtener_parametros(conn, esquema: str, procedimiento: str) -> list[dict]:
    """Parámetros de entrada de un procedimiento generado, en orden."""
    filas = _ejecutar(
        conn,
        """
        SELECT p.parameter_name, p.udt_name, p.parameter_default IS NOT NULL
        FROM information_schema.parameters p
        JOIN information_schema.routines r
          ON r.specific_schema = p.specific_schema
         AND r.specific_name   = p.specific_name
        WHERE r.routine_schema = %s
          AND r.routine_name   = %s
          AND p.parameter_mode = 'IN'
        ORDER BY p.ordinal_position;
        """,
        (esquema, procedimiento),
    )
    return [
        {"nombre": r[0], "tipo": r[1], "opcional": r[2]}
        for r in filas
    ]

def es_funcion(conn, esquema: str, procedimiento: str) -> bool:
    """True si es FUNCTION (se llama con SELECT), False si es PROCEDURE (con CALL)."""
    filas = _ejecutar(
        conn,
        """
        SELECT routine_type FROM information_schema.routines
        WHERE routine_schema = %s AND routine_name = %s;
        """,
        (esquema, procedimiento),
    )
    if not filas:
        raise CrudgenError("PROC_NO_EXISTE", f"No existe {esquema}.{procedimiento}")
    return filas[0][0] == "FUNCTION"


def ejecutar_procedimiento(conn, esquema: str, procedimiento: str, valores: dict):
    """Ejecuta un procedimiento generado pasando los parámetros por nombre.
    valores: {"p_nombre": "Ana", ...}. Los parámetros opcionales se omiten.
    Devuelve (columnas, filas); en un CALL, ambas vienen vacías."""
    argumentos = sql.SQL(", ").join(
        sql.SQL("{} => {}").format(sql.Identifier(nombre), sql.Placeholder())
        for nombre in valores
    )
    plantilla = "SELECT * FROM {}.{}({});" if es_funcion(conn, esquema, procedimiento) \
        else "CALL {}.{}({});"
    consulta = sql.SQL(plantilla).format(
        sql.Identifier(esquema), sql.Identifier(procedimiento), argumentos
    )
    return _ejecutar(conn, consulta, tuple(valores.values()), con_columnas=True)


# TODO: capa de UI (CLI o gráfica) que orqueste el flujo completo.

if __name__ == "__main__":
    cfg = cargar_config()
    conn = conectar(**cfg)

    
    estado = verificar_extension(conn)
    print(estado["estado"], "-", estado["mensaje"])
    if estado["estado"] != "INSTALADA":
        conn.close()
        raise SystemExit(1)

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

    try:
        listar_tablas(conn, "no_existe")
    except CrudgenError as e:
        print(f"No se pudo: {e.mensaje} (código: {e.codigo})")

    for r in generar_crud(conn, "ventas", "clientes", ["INSERT", "SELECT", "UPDATE", "DELETE"]):
        print(r)
    for r in generar_crud(conn, "ventas", "matricula", ["INSERT", "SELECT", "DELETE"]):
        print(r)

    for proc in ["clientes_insertar", "clientes_actualizar", "clientes_consultar"]:
        print(proc, obtener_parametros(conn, "ventas", proc))  

    
    conn.close()