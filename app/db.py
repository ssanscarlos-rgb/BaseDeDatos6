"""Capa de acceso a PostgreSQL de la aplicación (wrappers de la extensión crudgen).

Este módulo NO contiene lógica de generación de SQL específica de ninguna
tabla: eso vive en la extensión (ver docs/CONTRATO.md). Aquí solo se llaman
las funciones de la extensión con parámetros enlazados, y los identificadores
que hay que armar dinámicamente (nombre de un procedimiento, un rol) se
construyen con psycopg.sql.Identifier, nunca concatenando texto.
"""

import configparser
from pathlib import Path

import psycopg
from psycopg import sql


def conectar(host: str, puerto: int, base_datos: str, usuario: str, contrasena: str):
    """Establece la conexión (autocommit). Lanza psycopg.OperationalError si falla."""
    return psycopg.connect(
        host=host, port=puerto, dbname=base_datos, user=usuario, password=contrasena,
        autocommit=True,
    )


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
    if not config.read(ruta, encoding="utf-8"):
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


# ---------------------------------------------------------------------------
# Verificación de la extensión
# ---------------------------------------------------------------------------

def verificar_extension(conn) -> dict:
    """Determina el estado de crudgen en la base conectada.
    estado: INSTALADA, NO_INSTALADA, SIN_ARCHIVOS, SIN_PERMISOS o ERROR.
    Siempre se consulta al SERVIDOR (pg_extension); nunca se asume que la
    extensión existe por haber archivos en el equipo cliente."""
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
                           "están en el servidor (ejecute 'make install' en el servidor).",
            }

        version = filas[0][0]

        # 3. Está instalada. ¿El usuario puede usarla?
        fila = _ejecutar(conn, "SELECT * FROM crudgen.verificar_extension();")[0]
        if not fila[1]:  # disponible_para_usuario
            return {
                "estado": "SIN_PERMISOS",
                "mensaje": "La extensión está instalada, pero el usuario "
                           "conectado no tiene permisos para usarla "
                           "(falta GRANT USAGE ON SCHEMA crudgen).",
            }
        return {
            "estado": "INSTALADA",
            "mensaje": f"Extensión crudgen {version} lista.",
        }

    except psycopg.errors.InsufficientPrivilege:
        return {
            "estado": "SIN_PERMISOS",
            "mensaje": "La extensión está instalada, pero el usuario "
                       "conectado no tiene permisos para usarla "
                       "(falta GRANT USAGE ON SCHEMA crudgen).",
        }
    except psycopg.Error as e:
        return {"estado": "ERROR", "mensaje": f"Error al consultar la extensión: {e}"}


# ---------------------------------------------------------------------------
# Wrappers de la extensión (ver docs/CONTRATO.md)
# ---------------------------------------------------------------------------

def listar_esquemas(conn) -> list[str]:
    """CONTRATO sección 2."""
    filas = _ejecutar(conn, "SELECT nombre_esquema FROM crudgen.listar_esquemas();")
    return [r[0] for r in filas]


def listar_tablas(conn, esquema: str) -> list[dict]:
    """CONTRATO sección 3."""
    filas = _ejecutar(
        conn,
        "SELECT nombre_tabla, tiene_pk FROM crudgen.listar_tablas(%s);",
        (esquema,),
    )
    return [{"nombre_tabla": r[0], "tiene_pk": r[1]} for r in filas]


def analizar_tabla(conn, esquema: str, tabla: str) -> list[dict]:
    """CONTRATO sección 4."""
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
    """CONTRATO sección 5."""
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
    """CONTRATO sección 6."""
    filas = _ejecutar(
        conn,
        "SELECT crudgen.asignar_privilegio(%s, %s, %s);",
        (esquema, procedimiento, rol),
    )
    return filas[0][0]


def revocar_privilegio(conn, esquema: str, procedimiento: str, rol: str) -> bool:
    """CONTRATO sección 7."""
    filas = _ejecutar(
        conn,
        "SELECT crudgen.revocar_privilegio(%s, %s, %s);",
        (esquema, procedimiento, rol),
    )
    return filas[0][0]


def listar_roles(conn) -> list[dict]:
    """CONTRATO sección 8."""
    filas = _ejecutar(
        conn, "SELECT nombre_rol, puede_iniciar_sesion FROM crudgen.listar_roles();"
    )
    return [{"nombre_rol": r[0], "puede_iniciar_sesion": r[1]} for r in filas]


def listar_procedimientos_generados(conn, esquema: str, tabla: str | None = None) -> list[dict]:
    """CONTRATO sección 9. Sin tabla, lista los de todo el esquema."""
    filas = _ejecutar(
        conn,
        """
        SELECT nombre_procedimiento, tipo, definicion
        FROM crudgen.listar_procedimientos_generados(%s, %s);
        """,
        (esquema, tabla),
    )
    return [
        {"nombre_procedimiento": r[0], "tipo": r[1], "definicion": r[2]}
        for r in filas
    ]


# ---------------------------------------------------------------------------
# Ejecución de los procedimientos generados
# ---------------------------------------------------------------------------

def obtener_parametros(conn, esquema: str, procedimiento: str) -> list[dict]:
    """Parámetros de entrada de un procedimiento generado, en orden.
    Se lee de pg_proc (no de information_schema, que oculta objetos según
    los privilegios del usuario). 'opcional' = el parámetro tiene DEFAULT."""
    filas = _ejecutar(
        conn,
        """
        SELECT a.nombre,
               pg_catalog.format_type(a.tipo, NULL),
               a.pos > (p.pronargs - p.pronargdefaults)
        FROM pg_catalog.pg_proc p
        JOIN pg_catalog.pg_namespace s ON s.oid = p.pronamespace
        CROSS JOIN LATERAL unnest(p.proargnames, p.proargtypes::oid[])
                   WITH ORDINALITY AS a(nombre, tipo, pos)
        WHERE s.nspname = %s
          AND p.proname = %s
          AND p.prokind IN ('f', 'p')
        ORDER BY a.pos;
        """,
        (esquema, procedimiento),
    )
    return [{"nombre": r[0], "tipo": r[1], "opcional": r[2]} for r in filas]


def es_funcion(conn, esquema: str, procedimiento: str) -> bool:
    """True si es FUNCTION (se llama con SELECT), False si es PROCEDURE (con CALL)."""
    filas = _ejecutar(
        conn,
        """
        SELECT p.prokind
        FROM pg_catalog.pg_proc p
        JOIN pg_catalog.pg_namespace s ON s.oid = p.pronamespace
        WHERE s.nspname = %s AND p.proname = %s AND p.prokind IN ('f', 'p');
        """,
        (esquema, procedimiento),
    )
    if not filas:
        raise CrudgenError("PROC_NO_EXISTE", f"No existe {esquema}.{procedimiento}")
    return filas[0][0] == "f"


def ejecutar_procedimiento(conn, esquema: str, procedimiento: str,
                           valores: dict, como_rol: str | None = None):
    """Ejecuta un procedimiento generado pasando los parámetros por nombre.
    Con como_rol, lo ejecuta con los permisos de ese rol (SET ROLE).
    Devuelve (columnas, filas); en un CALL, ambas vienen vacías."""
    # 1. Decidir CALL o SELECT con el usuario real, antes de cambiar de rol
    funcion = es_funcion(conn, esquema, procedimiento)

    argumentos = sql.SQL(", ").join(
        sql.SQL("{} => {}").format(sql.Identifier(nombre), sql.Placeholder())
        for nombre in valores
    )
    plantilla = "SELECT * FROM {}.{}({});" if funcion else "CALL {}.{}({});"
    consulta = sql.SQL(plantilla).format(
        sql.Identifier(esquema), sql.Identifier(procedimiento), argumentos
    )

    # 2. Si se pidió, cambiar de rol solo durante la ejecución
    if como_rol:
        _ejecutar(conn, sql.SQL("SET ROLE {};").format(sql.Identifier(como_rol)))
    try:
        return _ejecutar(conn, consulta, tuple(valores.values()), con_columnas=True)
    finally:
        if como_rol:
            _ejecutar(conn, "RESET ROLE;")
