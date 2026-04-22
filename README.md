[![Review Assignment Due Date](https://classroom.github.com/assets/deadline-readme-button-22041afd0340ce965d47ae6ef1cefeee28c7c493a6346c4f15d667ab976d596c.svg)](https://classroom.github.com/a/EbtZGzoI)
[![Open in Codespaces](https://classroom.github.com/assets/launch-codespace-2972f46106e565e64193e422d61a12cf1da4916b45550586e14ef0a7c637dd04.svg)](https://classroom.github.com/open-in-codespaces?assignment_repo_id=23668567)

# 🚀 Proyecto Implementación: Detección del Primer Evento Crítico (503) en ARM64

----------

## 👤 Información General

-   **Autor:** Castillo Aragon Angel Jovany
-   **Matricula:** 23211933
-   **Horario:** 4pm
    
-   **Arquitectura:** ARM64 (AArch64)
    
-   **Plataforma:** AWS Linux (EC2 ARM64)
    
-   **Lenguajes:** ARM64 Assembly
    
-   **Enfoque:** Optimización de bajo nivel y análisis de rendimiento

# Mini Cloud Log Analyzer — Variante C

**Modalidad:** Individual
**Entorno de trabajo:** AWS Ubuntu ARM64 + GitHub Classroom
**Lenguaje:** ARM64 Assembly (GNU Assembler) + Bash + GNU Make
**Variante asignada:** C — Detectar el primer evento crítico (código 503)

---

## 1) Introduccion de la práctica

Implementar un analizador de logs de servidor en ARM64 Assembly que reciba por `stdin` una secuencia de códigos HTTP (un entero por línea), y detecte la **primera aparición del código 503**, reportando el número de línea exacto en que ocurrió.

Ejecución esperada:

```bash
cat data/logs_C.txt | ./analyzer
```

---

## 2) Objetivos de aprendizaje

Al finalizar esta práctica, el estudiante es capaz de:

1. Compilar y enlazar un programa ARM64 sin C ni libc.
2. Invocar syscalls Linux (`read`, `write`, `exit`) directamente desde ensamblador.
3. Parsear enteros desde flujo de bytes (`stdin`) usando lógica de acumulación de dígitos.
4. Implementar comparación exacta de valores numéricos en ARM64.
5. Diseñar estructuras de control iterativas con saltos condicionales.
6. Manejar casos borde: EOF sin newline final, archivo sin ningún 503.
7. Validar resultados con scripts de prueba reproducibles.

---

## 3) Estructura del repositorio

```text
cloud-log-analyzer/
├── README.md
├── Makefile
├── run.sh
├── src/
│   └── analyzer.s          ← implementación Variante C
├── data/
│   ├── logs_A.txt
│   ├── logs_B.txt
│   ├── logs_C.txt          ← dataset de esta variante
│   ├── logs_D.txt
│   └── logs_E.txt
├── tests/
│   ├── test.sh             ← pruebas adaptadas a Variante C
│   └── expected_outputs.txt
└── instructor/
    └── VARIANTES.md
```

---

## 4) Pseudocódigo de la solución

```
INICIO
  linea_actual   ← 0
  numero_actual  ← 0
  tiene_digitos  ← false

  imprimir titulo

  MIENTRAS haya bytes en stdin:
    leer bloque con syscall read

    PARA cada byte en el bloque:
      SI byte es digito ('0'..'9'):
        numero_actual ← numero_actual * 10 + (byte - '0')
        tiene_digitos ← true

      SI byte es '\n' (ASCII 10):
        SI tiene_digitos:
          linea_actual ← linea_actual + 1
          SI numero_actual == 503:
            imprimir "Primer 503 encontrado en la linea: N"
            SALIR (exit 0)
        reiniciar numero_actual ← 0
        reiniciar tiene_digitos ← false

  // Al llegar EOF: verificar numero pendiente (sin '\n' final)
  SI tiene_digitos:
    linea_actual ← linea_actual + 1
    SI numero_actual == 503:
      imprimir "Primer 503 encontrado en la linea: N"
      SALIR (exit 0)

  imprimir "No se encontro ningun codigo 503"
  SALIR (exit 0)
FIN
```

---

## 5) Diseño y lógica del programa ARM64

### 5.1 Mapa de registros

| Registro | Uso en esta práctica |
|---|---|
| `x19` | `linea_actual` — contador de líneas procesadas |
| `x22` | `numero_actual` — acumulador de dígitos de la línea actual |
| `x23` | `tiene_digitos` — flag 0/1, indica si hay número pendiente |
| `x24` | índice `i` dentro del bloque leído |
| `x25` | total de bytes leídos en el bloque actual |
| `x26` | byte actual (temporal, se reutiliza en cada iteración) |
| `x27` | constante `10` para la multiplicación del parser |
| `x0–x2, x8` | argumentos y número de syscall (convención Linux ARM64) |
| `x9–x17` | registros auxiliares dentro de subrutinas |

### 5.2 Syscalls utilizadas

| Syscall | Número | Uso |
|---|---|---|
| `read` | 63 | Leer bytes desde stdin |
| `write` | 64 | Escribir texto hacia stdout |
| `exit` | 93 | Terminar el proceso |

### 5.3 Flujo de control principal

```
_start
  │
  ├─► imprimir título
  │
  └─► leer_bloque ◄──────────────────────────────┐
        │                                         │
        ├─ EOF → fin_lectura                      │
        │                                         │
        └─► procesar_byte ◄──────────┐            │
              │                      │            │
              ├─ dígito → acumular ──┘            │
              │                                   │
              ├─ '\n' → fin_numero                │
              │    │                              │
              │    ├─ sin dígitos → reiniciar ────┘
              │    │                              │
              │    ├─ linea++ → ¿== 503?          │
              │    │    ├─ SÍ  → encontrado_503   │
              │    │    └─ NO  → reiniciar ───────┘
              │    │
              └─ otro byte → ignorar ─────────────┘

        fin_lectura
              ├─ número pendiente + == 503 → encontrado_503
              └─ sin 503 → no_encontrado

        encontrado_503 → imprimir línea → salida_ok
        no_encontrado  → imprimir mensaje → salida_ok
```

### 5.4 Subrutinas implementadas

**`write_cstr`** — imprime una cadena terminada en `'\0'` hacia stdout.
Calcula la longitud byte a byte y ejecuta la syscall `write`.

**`print_uint`** — convierte un entero sin signo a texto ASCII e imprime.
Divide sucesivamente entre 10, escribe dígitos de atrás hacia adelante en `num_buf`, luego imprime.

### 5.5 Casos borde manejados

| Caso | Comportamiento |
|---|---|
| Archivo sin ningún 503 | Imprime `"No se encontro ningun codigo 503"` |
| 503 en la última línea sin `\n` final | Detectado correctamente en `fin_lectura` |
| Líneas vacías en el archivo | Flag `tiene_digitos` evita contarlas |
| Múltiples códigos 503 | Solo se reporta el primero; el programa termina |

---

## 6) Requisitos técnicos

- Sistema objetivo: **AWS Ubuntu 24 ARM64**
- Arquitectura: **AArch64 Linux**
- Ensamblador: **GNU assembler (`as`)** + enlazador `ld`
- Restricciones estrictas:
  - Sin libc
  - Sin lenguaje C
  - Solo syscalls Linux + Bash + Make

---

## 7) Instrucciones de compilación y ejecución

### 7.1 Compilar

```bash
make
```

Salida esperada en ARM64:

```
[INFO] Compilando en host ARM64 con as/ld...
```

### 7.2 Ejecutar con el dataset de la variante

```bash
cat data/logs_C.txt | ./analyzer
```

### 7.3 Ejecutar pruebas automatizadas

```bash
make test
```

### 7.4 Limpiar artefactos de compilación

```bash
make clean
```

---

## 8) Evidencia de ejecución

#Evidencia Asciinema#
- [![asciicast](https://asciinema.org/a/LYfTfye7glBSqzXg.svg)](https://asciinema.org/a/LYfTfye7glBSqzXg)
- 

### Dataset utilizado — `data/logs_C.txt`

```
200
200
301
302
404
500
503   ← línea 7: primer 503
200
503
204
```

### Salida del programa

```
=== Mini Cloud Log Analyzer (Variante C) ===
Primer 503 encontrado en la linea: 7
```

### Prueba: archivo sin ningún 503

```bash
echo -e "200\n404\n201" | ./analyzer
```

```
=== Mini Cloud Log Analyzer (Variante C) ===
No se encontro ningun codigo 503
```

### Prueba: 503 en última línea sin newline final

```bash
printf "200\n404\n503" | ./analyzer
```

```
=== Mini Cloud Log Analyzer (Variante C) ===
Primer 503 encontrado en la linea: 3
```

### Resultado de `make test`

```
[TEST] Validando data/logs_C.txt
[OK] logs_C.txt

[TEST] Validando caso sin ningun 503
[OK] Caso sin 503

[TEST] Validando 503 en ultima linea (sin newline final)
[OK] 503 en ultima linea

[RESULTADO] Todas las pruebas pasaron. Variante C correcta.
```

---

## 9) Variantes de la práctica

| Variante | Descripción |
|---|---|
| **A** | Contar respuestas 2xx, errores 4xx y errores 5xx |
| **B** | Determinar el código de estado más frecuente |
| **C ✓** | **Detectar el primer evento crítico (código 503)** ← esta |
| **D** | Detectar tres errores consecutivos (4xx/5xx) |
| **E** | Calcular health score: `100 - (errores × 10)` |

---

## 10) Rúbrica de evaluación

| Criterio | Ponderación |
|---|---:|
| Compilación correcta en ARM64 | 20% |
| Correctitud de la solución (Variante C) | 35% |
| Uso adecuado de ARM64 y syscalls | 25% |
| Documentación y comentarios en el código | 10% |
| Evidencia de pruebas (make test) | 10% |

---

## 11) Restricciones

No está permitido:

- Resolver la lógica en C o Python
- Usar libc o funciones externas
- Modificar la variante asignada
- Omitir el uso de ARM64 Assembly

---

## 12) Competencia desarrollada

Comprender cómo un problema de detección de eventos críticos en logs es resuelto a nivel de arquitectura de máquina, mediante instrucciones ARM64, manejo directo de registros, memoria y syscalls Linux, sin ninguna capa de abstracción de lenguaje de alto nivel.
