"""Generador automático de CRUD para PostgreSQL — aplicación de consola.

Flujo (ver enunciado):
Conectar -> Verificar extensión -> Esquema -> Tablas -> Estructura
-> Operaciones -> Generar -> Mostrar -> Roles/privilegios -> Aplicar
-> Resultado -> Menú (ejecutar procedimientos, probar privilegios)
"""

import psycopg

import consola
from db import (
    CrudgenError,
    analizar_tabla,
    asignar_privilegio,
    cargar_config,
    conectar,
    ejecutar_procedimiento,
    generar_crud,
    listar_esquemas,
    listar_procedimientos_generados,
    listar_roles,
    listar_tablas,
    obtener_parametros,
    revocar_privilegio,
    verificar_extension,
)

# Operación de la extensión -> nombre que ve el usuario (y sufijo del procedimiento)
OPERACIONES = {
    "INSERT": "insertar",
    "SELECT": "consultar",
    "UPDATE": "actualizar",
    "DELETE": "eliminar",
}


# ---------------------------------------------------------------------------
# Pasos 1 a 6: conexión, verificación, selección y estructura
# ---------------------------------------------------------------------------

def pedir_datos_conexion() -> dict:
    """Pide los cinco datos de conexión por teclado."""
    while True:
        puerto = consola.pedir_texto("Puerto")
        if puerto.isdigit():
            break
        print("  El puerto debe ser un número.")
    return {
        "host": consola.pedir_texto("Servidor"),
        "puerto": int(puerto),
        "base_datos": consola.pedir_texto("Base de datos"),
        "usuario": consola.pedir_texto("Usuario"),
        "contrasena": consola.pedir_texto("Contraseña"),
    }


def paso_conectar(usar_config: bool = True):
    """Paso 1: obtener los datos de conexión y conectar.
    Reintenta hasta conectar; devuelve None solo si el usuario decide salir."""
    consola.titulo("1. Conexión a PostgreSQL")

    datos = None
    if usar_config:
        try:
            datos = cargar_config()
            print(f"  Configuración encontrada: {datos['usuario']}@{datos['host']}:"
                  f"{datos['puerto']}/{datos['base_datos']}")
            if not consola.pedir_si_no("¿Usar esta configuración?"):
                datos = None
        except FileNotFoundError:
            print("  No hay config.ini; ingrese los datos manualmente.")

    while True:
        if datos is None:
            datos = pedir_datos_conexion()
        try:
            conn = conectar(**datos)
            print("  Conexión exitosa.")
            return conn
        except psycopg.OperationalError as e:
            print(f"\n  No se pudo conectar: {e}")
            if not consola.pedir_si_no("¿Intentar con otros datos?"):
                return None
            datos = None


def paso_verificar(conn) -> bool:
    """Paso 2: comprobar que la extensión está instalada y disponible."""
    consola.titulo("2. Verificación de la extensión")
    estado = verificar_extension(conn)
    print(f"  {estado['estado']}: {estado['mensaje']}")
    return estado["estado"] == "INSTALADA"


def conectar_y_verificar():
    """Pasos 1 y 2 juntos: no avanza hasta tener una conexión con la
    extensión lista. Devuelve None solo si el usuario decide salir."""
    conn = paso_conectar()
    while conn is not None and not paso_verificar(conn):
        opcion = consola.elegir_uno(
            ["Verificar de nuevo", "Conectar a otra base", "Salir"], "¿Qué desea hacer?"
        )
        if opcion == "Conectar a otra base":
            conn.close()
            conn = paso_conectar(usar_config=False)
        elif opcion == "Salir":
            conn.close()
            return None
    return conn


def paso_esquema(conn) -> str | None:
    """Paso 3: elegir un esquema. None si la base no tiene esquemas."""
    consola.titulo("3. Selección de esquema")
    esquemas = listar_esquemas(conn)
    if not esquemas:
        print("  No hay esquemas disponibles.")
        return None
    return consola.elegir_uno(esquemas, "Esquema")


def paso_tablas(conn, esquema: str) -> list[str]:
    """Paso 4: elegir una, varias o todas las tablas del esquema.
    Devuelve [] si el esquema no tiene tablas."""
    consola.titulo(f"4. Selección de tablas en '{esquema}'")
    tablas = listar_tablas(conn, esquema)
    if not tablas:
        print("  Este esquema no tiene tablas.")
        return []

    etiquetas = {}
    for t in tablas:
        etiqueta = t["nombre_tabla"]
        if not t["tiene_pk"]:
            etiqueta += "  (sin PK: no admite UPDATE ni DELETE)"
        etiquetas[etiqueta] = t["nombre_tabla"]

    elegidas = consola.elegir_varios(list(etiquetas), "Tablas")
    return [etiquetas[e] for e in elegidas]


def paso_estructura(conn, esquema: str, tablas: list[str]) -> dict:
    """Paso 5: mostrar la estructura de cada tabla.
    Devuelve, por tabla, si tiene PK y si tiene columnas actualizables."""
    consola.titulo("5. Estructura de las tablas")
    info = {}
    for tabla in tablas:
        columnas = analizar_tabla(conn, esquema, tabla)
        print(f"\n  Tabla {esquema}.{tabla}")
        consola.mostrar_tabla(
            ["columna", "tipo", "PK", "autogenerada", "acepta NULL", "default"],
            [
                (
                    c["columna"],
                    c["tipo"],
                    "sí" if c["es_pk"] else "",
                    "sí" if c["es_autogenerada"] else "",
                    "sí" if c["es_nullable"] else "",
                    c["valor_default"] or "",
                )
                for c in columnas
            ],
        )
        info[tabla] = {
            "tiene_pk": any(c["es_pk"] for c in columnas),
            "tiene_actualizables": any(
                not c["es_pk"] and not c["es_autogenerada"] for c in columnas
            ),
        }
    return info


def paso_operaciones(info: dict) -> dict:
    """Paso 6: elegir operaciones y ajustarlas a lo que admite cada tabla.
    Devuelve {tabla: [operaciones]}."""
    consola.titulo("6. Operaciones CRUD")
    elegidas = consola.elegir_varios(list(OPERACIONES), "Operaciones")

    plan = {}
    for tabla, datos in info.items():
        ops = list(elegidas)
        if not datos["tiene_pk"]:
            quitadas = [op for op in ops if op in ("UPDATE", "DELETE")]
            ops = [op for op in ops if op not in ("UPDATE", "DELETE")]
            if quitadas:
                print(f"  Aviso: {tabla} no tiene PK; se omite {', '.join(quitadas)}.")
        elif not datos["tiene_actualizables"] and "UPDATE" in ops:
            ops.remove("UPDATE")
            print(f"  Aviso: {tabla} no tiene columnas actualizables; se omite UPDATE.")
        if ops:
            plan[tabla] = ops
        else:
            print(f"  Aviso: no queda ninguna operación para {tabla}; se omite la tabla.")
    return plan


# ---------------------------------------------------------------------------
# Pasos 7 a 11: generación, privilegios y resultado
# ---------------------------------------------------------------------------

def paso_generar(conn, esquema: str, plan: dict) -> list[dict]:
    """Paso 7: generar los procedimientos de cada tabla.
    Si una tabla falla, se informa y se sigue con las demás."""
    consola.titulo("7. Generación de procedimientos")
    generados = []
    for tabla, ops in plan.items():
        try:
            for r in generar_crud(conn, esquema, tabla, ops):
                generados.append({
                    "tabla": tabla,
                    "operacion": r["operacion"],
                    "procedimiento": r["nombre_procedimiento"],
                    "ya_existia": r["ya_existia"],
                })
        except CrudgenError as e:
            print(f"  Error en {tabla}: {e.mensaje}")

    consola.mostrar_tabla(
        ["tabla", "operación", "procedimiento", "estado"],
        [
            (g["tabla"], g["operacion"], g["procedimiento"],
             "reemplazado" if g["ya_existia"] else "creado")
            for g in generados
        ],
    )
    return generados


def paso_mostrar(conn, esquema: str, generados: list[dict]) -> None:
    """Paso 8: listar los procedimientos creados y permitir ver su código."""
    consola.titulo("8. Procedimientos creados")

    definiciones = {}
    for tabla in dict.fromkeys(g["tabla"] for g in generados):
        for p in listar_procedimientos_generados(conn, esquema, tabla):
            definiciones[p["nombre_procedimiento"]] = p

    nombres = [g["procedimiento"] for g in generados if g["procedimiento"] in definiciones]
    consola.mostrar_tabla(
        ["procedimiento", "tipo"],
        [(n, definiciones[n]["tipo"]) for n in nombres],
    )
    while consola.pedir_si_no("¿Ver el código de algún procedimiento?"):
        nombre = consola.elegir_uno(nombres, "Procedimiento")
        print()
        print(definiciones[nombre]["definicion"])


def paso_privilegios(conn, generados: list[dict]) -> dict:
    """Paso 9: elegir roles y qué operaciones puede ejecutar cada uno.
    Devuelve la matriz {rol: [operaciones permitidas]}."""
    consola.titulo("9. Roles y privilegios")
    roles = [r["nombre_rol"] for r in listar_roles(conn)]
    elegidos = consola.elegir_varios(roles, "Roles a configurar")

    # Solo se ofrecen las operaciones que realmente se generaron
    disponibles = [
        nombre for op, nombre in OPERACIONES.items()
        if any(g["operacion"] == op for g in generados)
    ]
    NINGUNA = "(ninguna)"

    matriz = {}
    for rol in elegidos:
        print(f"\n  ¿Qué operaciones puede ejecutar '{rol}'?")
        permitidas = consola.elegir_varios(disponibles + [NINGUNA], "Operaciones")
        matriz[rol] = [] if NINGUNA in permitidas else permitidas

    print("\n  Matriz de privilegios:")
    consola.mostrar_tabla(
        ["rol"] + disponibles,
        [
            tuple([rol] + ["✓" if op in permitidas else "✗" for op in disponibles])
            for rol, permitidas in matriz.items()
        ],
    )
    return matriz


def paso_aplicar(conn, esquema: str, generados: list[dict], matriz: dict) -> list[tuple]:
    """Paso 10: traducir la matriz a GRANT (✓) y REVOKE (✗)."""
    consola.titulo("10. Aplicar configuración")
    if not consola.pedir_si_no("¿Aplicar esta matriz de privilegios?"):
        print("  No se aplicaron cambios.")
        return []

    resultados = []
    for rol, permitidas in matriz.items():
        for g in generados:
            permitido = OPERACIONES[g["operacion"]] in permitidas
            try:
                if permitido:
                    asignar_privilegio(conn, esquema, g["procedimiento"], rol)
                else:
                    revocar_privilegio(conn, esquema, g["procedimiento"], rol)
                estado = "ok"
            except CrudgenError as e:
                estado = f"error: {e.mensaje}"
            resultados.append(
                (rol, g["procedimiento"], "GRANT" if permitido else "REVOKE", estado)
            )

    consola.mostrar_tabla(["rol", "procedimiento", "acción", "resultado"], resultados)
    return resultados


def paso_resultado(generados: list[dict], aplicados: list[tuple]) -> None:
    """Paso 11: resumen de lo realizado."""
    consola.titulo("11. Resultado")
    creados = sum(1 for g in generados if not g["ya_existia"])
    reemplazados = len(generados) - creados
    errores = sum(1 for a in aplicados if a[3] != "ok")
    print(f"  Procedimientos creados:      {creados}")
    print(f"  Procedimientos reemplazados: {reemplazados}")
    print(f"  Privilegios aplicados:       {len(aplicados) - errores}")
    print(f"  Errores de privilegios:      {errores}")


# ---------------------------------------------------------------------------
# Menú final: ejecutar procedimientos y comprobar privilegios
# ---------------------------------------------------------------------------

def accion_ejecutar(conn, esquema: str, generados: list[dict], como_rol: str | None = None) -> None:
    """Pide los parámetros de un procedimiento y lo ejecuta."""
    procedimiento = consola.elegir_uno([g["procedimiento"] for g in generados], "Procedimiento")

    parametros = obtener_parametros(conn, esquema, procedimiento)
    valores = {}
    if parametros:
        print("  (Escriba NULL para enviar un valor nulo.)")
    for p in parametros:
        valor = consola.pedir_texto(f"  {p['nombre']} ({p['tipo']})", opcional=p["opcional"])
        if valor is None:
            continue  # parámetro opcional omitido
        valores[p["nombre"]] = None if valor.upper() == "NULL" else valor

    quien = f" como '{como_rol}'" if como_rol else ""
    try:
        columnas, filas = ejecutar_procedimiento(
            conn, esquema, procedimiento, valores, como_rol=como_rol
        )
    except CrudgenError as e:
        print(f"\n  No se pudo ejecutar{quien}: {e.mensaje}")
        return
    except psycopg.Error as e:
        print(f"\n  PostgreSQL rechazó la operación{quien}: "
              f"{e.diag.message_primary or e}")
        return

    print()
    if columnas:
        consola.mostrar_tabla(columnas, filas)
    else:
        print(f"  {procedimiento} se ejecutó correctamente{quien}.")


def menu(conn, esquema: str, generados: list[dict]) -> str:
    """Menú final para operar con los procedimientos generados.
    Devuelve 'tablas', 'esquema' o 'salir' según lo que elija el usuario."""
    EJECUTAR = "Ejecutar un procedimiento"
    COMO_ROL = "Ejecutar un procedimiento como otro rol (probar privilegios)"
    VER = "Ver procedimientos creados"
    PRIVILEGIOS = "Reconfigurar privilegios"
    OTRAS = "Generar para otras tablas de este esquema"
    CAMBIAR = "Cambiar de esquema"
    SALIR = "Salir"

    while True:
        consola.titulo("Menú")
        opcion = consola.elegir_uno(
            [EJECUTAR, COMO_ROL, VER, PRIVILEGIOS, OTRAS, CAMBIAR, SALIR]
        )
        if opcion == EJECUTAR:
            accion_ejecutar(conn, esquema, generados)
        elif opcion == COMO_ROL:
            roles = [r["nombre_rol"] for r in listar_roles(conn)]
            rol = consola.elegir_uno(roles, "Rol")
            accion_ejecutar(conn, esquema, generados, como_rol=rol)
        elif opcion == VER:
            paso_mostrar(conn, esquema, generados)
        elif opcion == PRIVILEGIOS:
            matriz = paso_privilegios(conn, generados)
            paso_aplicar(conn, esquema, generados, matriz)
        elif opcion == OTRAS:
            return "tablas"
        elif opcion == CAMBIAR:
            return "esquema"
        else:
            return "salir"


def que_sigue(motivo: str) -> str:
    """Cuando un paso no puede continuar: explicar y dejar elegir cómo seguir.
    Devuelve 'tablas', 'esquema' o 'salir'."""
    print(f"\n  {motivo}")
    opcion = consola.elegir_uno(
        ["Elegir otras tablas u operaciones", "Cambiar de esquema", "Salir"],
        "¿Qué desea hacer?",
    )
    return {"Elegir otras tablas u operaciones": "tablas",
            "Cambiar de esquema": "esquema",
            "Salir": "salir"}[opcion]


# ---------------------------------------------------------------------------

def main() -> None:
    conn = conectar_y_verificar()
    if conn is None:
        print("\n  Hasta luego.")
        return

    try:
        esquema = None
        while True:
            # Paso 3: solo se pide esquema al inicio o si el usuario quiere cambiarlo
            if esquema is None:
                esquema = paso_esquema(conn)
                if esquema is None:
                    if consola.pedir_si_no("¿Volver a consultar los esquemas?"):
                        continue
                    break

            # Paso 4
            tablas = paso_tablas(conn, esquema)
            if not tablas:
                esquema = None  # esquema vacío: volver a elegir esquema
                continue

            # Pasos 5 y 6
            info = paso_estructura(conn, esquema, tablas)
            plan = paso_operaciones(info)
            if not plan:
                siguiente = que_sigue("Con esa selección no hay nada que generar.")
            else:
                # Paso 7
                generados = paso_generar(conn, esquema, plan)
                if not generados:
                    siguiente = que_sigue("No se generó ningún procedimiento.")
                else:
                    # Pasos 8 a 11 y menú
                    paso_mostrar(conn, esquema, generados)
                    matriz = paso_privilegios(conn, generados)
                    aplicados = paso_aplicar(conn, esquema, generados, matriz)
                    paso_resultado(generados, aplicados)
                    siguiente = menu(conn, esquema, generados)

            if siguiente == "salir":
                break
            if siguiente == "esquema":
                esquema = None
            # 'tablas': se conserva el esquema y el ciclo vuelve al paso 4
    finally:
        conn.close()

    print("\n  Hasta luego.")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n\nProceso cancelado por el usuario.")