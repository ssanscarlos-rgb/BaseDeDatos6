"""Utilidades de terminal: mostrar opciones y leer respuestas.
Este módulo no sabe nada de PostgreSQL."""

from getpass import getpass


def titulo(texto: str) -> None:
    """Encabezado visible para separar cada paso del flujo."""
    print()
    print("=" * 60)
    print(f"  {texto}")
    print("=" * 60)


def elegir_uno(opciones: list[str], mensaje: str = "Elija una opción") -> str:
    """Muestra una lista numerada y devuelve la opción elegida."""
    for i, opcion in enumerate(opciones, start=1):
        print(f"  {i}. {opcion}")
    while True:
        respuesta = input(f"{mensaje} [1-{len(opciones)}]: ").strip()
        if respuesta.isdigit() and 1 <= int(respuesta) <= len(opciones):
            return opciones[int(respuesta) - 1]
        print("  Opción inválida, intente de nuevo.")


def elegir_varios(opciones: list[str], mensaje: str = "Elija opciones") -> list[str]:
    """Permite elegir varias separadas por coma (1,3) o todas con *."""
    for i, opcion in enumerate(opciones, start=1):
        print(f"  {i}. {opcion}")
    while True:
        respuesta = input(f"{mensaje} (ej: 1,3 o * para todas): ").strip()
        if respuesta == "*":
            return list(opciones)
        partes = [p.strip() for p in respuesta.split(",") if p.strip()]
        if partes and all(p.isdigit() and 1 <= int(p) <= len(opciones) for p in partes):
            indices = sorted(set(int(p) for p in partes))
            return [opciones[i - 1] for i in indices]
        print("  Selección inválida, intente de nuevo.")


def pedir_si_no(mensaje: str) -> bool:
    """Pregunta s/n hasta obtener una respuesta válida."""
    while True:
        respuesta = input(f"{mensaje} (s/n): ").strip().lower()
        if respuesta in ("s", "si", "sí"):
            return True
        if respuesta in ("n", "no"):
            return False
        print("  Responda s o n.")


def pedir_texto(mensaje: str, opcional: bool = False) -> str | None:
    """Pide un texto. Si es opcional y se deja vacío, devuelve None."""
    while True:
        respuesta = input(f"{mensaje}{' (Enter para omitir)' if opcional else ''}: ").strip()
        if respuesta:
            return respuesta
        if opcional:
            return None
        print("  Este valor es obligatorio.")


def pedir_secreto(mensaje: str) -> str:
    """Pide un valor sin mostrarlo en pantalla (contraseñas)."""
    while True:
        respuesta = getpass(f"{mensaje}: ")
        if respuesta:
            return respuesta
        print("  Este valor es obligatorio.")


def mostrar_tabla(columnas: list[str], filas: list[tuple]) -> None:
    """Imprime filas como una tabla con columnas alineadas."""
    if not filas:
        print("  (sin resultados)")
        return
    textos = [[("NULL" if v is None else str(v)) for v in fila] for fila in filas]
    anchos = [
        max(len(col), *(len(fila[i]) for fila in textos))
        for i, col in enumerate(columnas)
    ]
    print("  " + " | ".join(c.ljust(a) for c, a in zip(columnas, anchos)))
    print("  " + "-+-".join("-" * a for a in anchos))
    for fila in textos:
        print("  " + " | ".join(v.ljust(a) for v, a in zip(fila, anchos)))

