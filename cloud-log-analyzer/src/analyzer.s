/*
Autor: Castillo Aragon Angel Jovany
Matricula: 23211933
Curso: Arquitectura de Computadoras / Ensamblador ARM64
Práctica: Mini Cloud Log Analyzer - Variante C
Fecha: Abril-22-2026
Descripcion: Lee codigos HTTP desde stdin, uno por linea.
             Detecta el PRIMER codigo 503 e imprime en que
             numero de linea aparecio. Si no existe, lo reporta.
             Solo usa syscalls Linux (sin libc, sin C).
*/

/*
PSEUDOCODIGO (Variante C):
1) Inicializar: linea_actual = 0, numero_actual = 0, tiene_digitos = false
2) Imprimir titulo
3) MIENTRAS haya bytes en stdin:
   3.1) Leer bloque con syscall read
   3.2) Por cada byte del bloque:
        - Si es digito: acumular numero_actual = numero_actual*10 + digito
                        marcar tiene_digitos = true
        - Si es '\n':
            Si tiene_digitos:
                linea_actual++
                Si numero_actual == 503 → imprimir linea y SALIR
            Reiniciar acumulador
4) Al llegar EOF: si queda numero pendiente, procesarlo igual
5) Si nunca se encontro 503 → imprimir mensaje "no encontrado"
6) Salir con codigo 0
*/

// ─────────────────────────────────────────────────────────────
// Numeros de syscall ARM64 Linux
// ─────────────────────────────────────────────────────────────
.equ SYS_read,   63
.equ SYS_write,  64
.equ SYS_exit,   93
.equ STDIN_FD,    0
.equ STDOUT_FD,   1

// ─────────────────────────────────────────────────────────────
// .bss  →  memoria reservada sin inicializar
// ─────────────────────────────────────────────────────────────
.section .bss
    .align 4
buffer:     .skip 4096      // bloque de lectura de stdin (4 KB)
num_buf:    .skip 32        // buffer temporal para convertir entero a ASCII

// ─────────────────────────────────────────────────────────────
// .data  →  cadenas de texto constantes
// ─────────────────────────────────────────────────────────────
.section .data
msg_titulo:
    .asciz "=== Mini Cloud Log Analyzer (Variante C) ===\n"
msg_encontrado:
    .asciz "Primer 503 encontrado en la linea: "
msg_no_encontrado:
    .asciz "No se encontro ningun codigo 503\n"
msg_newline:
    .asciz "\n"

// ─────────────────────────────────────────────────────────────
// .text  →  codigo ejecutable
// ─────────────────────────────────────────────────────────────
.section .text
.global _start

// ─────────────────────────────────────────────────────────────
// Mapa de registros (convencion interna de esta practica):
//   x19 = linea_actual        (contador de lineas leidas)
//   x22 = numero_actual       (acumulador de digitos)
//   x23 = tiene_digitos       (flag 0/1)
//   x24 = indice i en bloque  (byte actual que se procesa)
//   x25 = total bytes leidos en bloque
//   x26 = byte actual (temporal)
//   x27 = constante 10 (para multiplicar en parser)
// ─────────────────────────────────────────────────────────────

_start:
    mov x19, #0         // linea_actual = 0
    mov x22, #0         // numero_actual = 0
    mov x23, #0         // tiene_digitos = false (0)

    // Imprimir encabezado al inicio
    adrp x0, msg_titulo
    add  x0, x0, :lo12:msg_titulo
    bl   write_cstr

// ─────────────────────────────────────────────────────────────
// BUCLE EXTERNO: leer bloques de hasta 4096 bytes desde stdin
// ─────────────────────────────────────────────────────────────
leer_bloque:
    mov x0, #STDIN_FD           // fd = 0 (stdin)
    adrp x1, buffer
    add  x1, x1, :lo12:buffer   // puntero al buffer
    mov  x2, #4096              // maximo bytes a leer
    mov  x8, #SYS_read          // syscall read
    svc  #0                     // x0 = bytes leidos

    cmp  x0, #0
    beq  fin_lectura            // 0 bytes = EOF, terminar
    blt  salida_error           // negativo = error de lectura

    mov  x24, #0                // i = 0 (inicio del bloque)
    mov  x25, x0                // guardar total de bytes leidos

// ─────────────────────────────────────────────────────────────
// BUCLE INTERNO: procesar el bloque byte por byte
// ─────────────────────────────────────────────────────────────
procesar_byte:
    cmp  x24, x25
    b.ge leer_bloque            // bloque agotado → leer siguiente

    // Cargar byte buffer[i]
    adrp x1, buffer
    add  x1, x1, :lo12:buffer
    ldrb w26, [x1, x24]         // w26 = byte actual
    add  x24, x24, #1           // i++

    // ¿Es salto de linea '\n' (ASCII 10)?
    cmp  w26, #10
    b.eq fin_numero

    // ¿Es digito ASCII '0' (48) .. '9' (57)?
    cmp  w26, #'0'
    b.lt procesar_byte          // menor que '0' → ignorar
    cmp  w26, #'9'
    b.gt procesar_byte          // mayor que '9' → ignorar

    // Acumular digito:
    // numero_actual = numero_actual * 10 + (byte - '0')
    mov  x27, #10
    mul  x22, x22, x27          // numero_actual *= 10
    sub  w26, w26, #'0'         // convertir ASCII a valor numerico
    uxtw x26, w26               // extender a 64 bits sin signo
    add  x22, x22, x26          // sumar digito
    mov  x23, #1                // tiene_digitos = true
    b    procesar_byte

// ─────────────────────────────────────────────────────────────
// Se encontro '\n': procesar numero acumulado en x22
// ─────────────────────────────────────────────────────────────
fin_numero:
    cbz  x23, reiniciar         // sin digitos → linea vacia, ignorar

    add  x19, x19, #1           // linea_actual++

    // Comparar con 503
    cmp  x22, #503
    b.eq encontrado_503         // ← detectado! saltar a impresion

reiniciar:
    mov  x22, #0                // reiniciar acumulador
    mov  x23, #0                // reiniciar flag
    b    procesar_byte

// ─────────────────────────────────────────────────────────────
// EOF alcanzado: verificar si quedo numero sin '\n' final
// ─────────────────────────────────────────────────────────────
fin_lectura:
    cbz  x23, no_encontrado     // nada pendiente → reportar no encontrado

    add  x19, x19, #1           // linea_actual++ (ultima linea sin \n)
    cmp  x22, #503
    b.eq encontrado_503         // era 503 en la ultima linea

    // No era 503, caer a no_encontrado

// ─────────────────────────────────────────────────────────────
// Caso: ningun 503 en todo el archivo
// ─────────────────────────────────────────────────────────────
no_encontrado:
    adrp x0, msg_no_encontrado
    add  x0, x0, :lo12:msg_no_encontrado
    bl   write_cstr
    b    salida_ok

// ─────────────────────────────────────────────────────────────
// Caso: se detecto 503, imprimir numero de linea
// ─────────────────────────────────────────────────────────────
encontrado_503:
    // Imprimir "Primer 503 encontrado en la linea: "
    adrp x0, msg_encontrado
    add  x0, x0, :lo12:msg_encontrado
    bl   write_cstr

    // Imprimir el numero de linea (valor en x19)
    mov  x0, x19
    bl   print_uint

    // Imprimir salto de linea final
    adrp x0, msg_newline
    add  x0, x0, :lo12:msg_newline
    bl   write_cstr

    b    salida_ok

// ─────────────────────────────────────────────────────────────
// Salidas del programa
// ─────────────────────────────────────────────────────────────
salida_ok:
    mov x0, #0
    mov x8, #SYS_exit
    svc #0

salida_error:
    mov x0, #1
    mov x8, #SYS_exit
    svc #0

// ─────────────────────────────────────────────────────────────
// FUNCION: write_cstr
// Imprime una cadena terminada en '\0' hacia stdout
// Entrada:  x0 = puntero a la cadena
// Modifica: x0, x1, x2, x8, x9, x10, x11
// ─────────────────────────────────────────────────────────────
write_cstr:
    mov  x9,  x0        // x9 = puntero al inicio de la cadena
    mov  x10, #0        // x10 = longitud = 0

wc_loop:
    ldrb w11, [x9, x10] // cargar byte en posicion x10
    cbz  w11, wc_done   // si es '\0', terminar conteo
    add  x10, x10, #1   // longitud++
    b    wc_loop

wc_done:
    mov  x0, #STDOUT_FD // fd = stdout
    mov  x1, x9         // puntero al string
    mov  x2, x10        // numero de bytes
    mov  x8, #SYS_write
    svc  #0
    ret

// ─────────────────────────────────────────────────────────────
// FUNCION: print_uint
// Convierte un entero sin signo a texto ASCII y lo imprime
// Entrada:  x0 = numero a imprimir
// Modifica: x0, x1, x2, x8, x12..x17
// ─────────────────────────────────────────────────────────────
print_uint:
    // Caso especial: si el numero es 0, imprimir '0' directamente
    cbnz x0, pu_convertir

    adrp x1, num_buf
    add  x1, x1, :lo12:num_buf
    mov  w2, #'0'
    strb w2, [x1]           // guardar '0'
    mov  x0, #STDOUT_FD
    mov  x2, #1             // 1 byte
    mov  x8, #SYS_write
    svc  #0
    ret

pu_convertir:
    // Convertir numero a digitos de derecha a izquierda en num_buf
    adrp x12, num_buf
    add  x12, x12, :lo12:num_buf
    add  x12, x12, #31     // apuntar al final del buffer
    mov  w13, #0
    strb w13, [x12]         // byte centinela (para debug)

    mov  x14, #10           // divisor
    mov  x15, #0            // contador de digitos escritos

pu_loop:
    udiv x16, x0,  x14      // x16 = x0 / 10  (cociente)
    msub x17, x16, x14, x0  // x17 = x0 - x16*10  (residuo = digito)
    add  x17, x17, #'0'     // convertir a ASCII
    sub  x12, x12, #1       // retroceder un byte en buffer
    strb w17, [x12]         // guardar digito
    add  x15, x15, #1       // digitos++
    mov  x0,  x16           // x0 = cociente para siguiente iteracion
    cbnz x0, pu_loop        // repetir mientras queden digitos

    // Imprimir los digitos acumulados
    mov  x0, #STDOUT_FD
    mov  x1, x12            // puntero al primer digito
    mov  x2, x15            // cantidad de digitos
    mov  x8, #SYS_write
    svc  #0
    ret
