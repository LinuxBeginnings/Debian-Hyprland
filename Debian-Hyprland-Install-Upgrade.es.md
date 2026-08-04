# Guía de Instalación y Actualización de Debian-Hyprland

Esta guía cubre los flujos de instalación y actualización mejorados para el proyecto Debian-Hyprland de KooL, incluyendo nuevas funciones de automatización, gestión centralizada de versiones y capacidades de dry-run.

## Tabla de Contenidos

1. [Resumen](#resumen)
2. [Nuevas Funciones](#nuevas-funciones)
3. [Referencia de Flags](#referencia-de-flags)
4. [Modo de Compatibilidad Debian 13 (Trixie)](#modo-de-compatibilidad-debian-13-trixie)
5. [Modo de Paquetes Debian](#modo-de-paquetes-debian)
6. [Gestión Central de Versiones](#gestión-central-de-versiones)
7. [Métodos de Instalación](#métodos-de-instalación)
8. [Flujos de Actualización](#flujos-de-actualización)
9. [Pruebas con Dry-Run](#pruebas-con-dry-run)
10. [Gestión de Logs](#gestión-de-logs)
11. [Uso Avanzado](#uso-avanzado)
12. [Solución de Problemas](#solución-de-problemas)

## Resumen

El proyecto Debian-Hyprland ahora incluye herramientas de automatización y gestión mejoradas, manteniendo la compatibilidad con el script original install.sh. Las principales adiciones son:

- **Gestión centralizada de versiones** mediante `hypr-tags.env`
- **Orden automático de dependencias** para los requisitos de Hyprland 0.51.x
- **Pruebas de compilación con dry-run** sin modificar el sistema
- **Actualizaciones selectivas de componentes** con `update-hyprland.sh`
- **Obtención automática de últimas versiones** desde GitHub
- **Modo de paquetes Debian** para instalar Hyprland directamente desde los repos de Debian (sin compilar desde el código fuente)
- **Visibilidad de versiones** — compara el candidato Debian, la etiqueta local y la versión upstream antes de elegir el modo de construcción

## Nuevas Funciones

### install.sh mejorado

El script original ahora:

- **Unifica versiones**: Lee `hypr-tags.env` y exporta variables de versión a todos los módulos
- **wayland-protocols automático**: Instala wayland-protocols desde el código fuente (≥1.45) antes de Hyprland
- **Orden robusto de dependencias**: Garantiza la secuencia correcta de requisitos

### Nuevos Scripts

#### update-hyprland.sh

Herramienta enfocada para gestionar y compilar solo el stack de Hyprland:

```bash
chmod +x ./update-hyprland.sh
./update-hyprland.sh --help  # Ver todas las opciones
```

Flags clave:

- --fetch-latest: obtiene las últimas etiquetas desde GitHub
- --force-update: sobrescribe valores fijados en hypr-tags.env (equivalente a FORCE=1)
- --dry-run / --install: solo compilar o compilar+instalar
- --only / --skip: limitar qué módulos se ejecutan
- --package-cleanup: purga el stack Hyprland de Debian antes de compilar
- --build-trixie / --no-trixie: habilita/deshabilita el modo de compatibilidad Debian 13 (auto-detectado por defecto)
- --mode auto|source|debian: seleccionar modo de operación (por defecto: auto → modo de paquetes Debian)
- --source / --deb-pkg: alias no interactivos para modo de código fuente o modo paquetes Debian
- --show-versions: muestra el candidato Debian, la etiqueta local y la versión upstream de Hyprland
- --debian-remove: elimina los paquetes Hyprland de Debian y termina
- --no-fetch: omite la obtención automática de etiquetas durante --install
- --bundled / --system: compila con las subproyectos bundled o con las librerías del sistema (por defecto: --system)

#### dry-run-build.sh

Herramienta de pruebas que compila componentes sin instalarlos:

```bash
chmod +x ./dry-run-build.sh
./dry-run-build.sh --help  # Ver todas las opciones
```

#### wayland-protocols-src.sh

Módulo que compila wayland-protocols desde el origen para satisfacer los requisitos de Hyprland 0.51.x.

## Referencia de Flags

Este repo incluye varios "flags de control" que afectan cómo se compila/instala el stack.

### Flags de update-hyprland.sh

- `--install` / `--dry-run`: compilar+instalar vs solo compilar
- `--only <lista>` / `--skip <lista>`: ejecutar solo un subconjunto de módulos
- `--with-deps`: instala dependencias de compilación (vía `00-dependencies.sh`) antes de compilar
- `--fetch-latest`: consulta GitHub Releases y refresca las etiquetas de `hypr-tags.env`
- `--force-update`: sobrescribe valores fijados en `hypr-tags.env` (equivalente a `FORCE=1`)
- `--restore`: restaura la copia de seguridad más reciente de `hypr-tags.env` antes de compilar
- `--set K=V [...]`: establece una o más etiquetas de versión (p. ej., `--set HYPRLAND=v0.53.0`)
- `--package-cleanup`: purga paquetes Hyprland de Debian antes de compilar
- `--build-trixie` / `--no-trixie`: habilita/deshabilita modo de compatibilidad Debian 13
- `--mode MODO`: seleccionar modo de operación — `auto` (por defecto), `source` o `debian`
- `--source`: alias para `--mode source` (modo fuente no interactivo)
- `--deb-pkg` / `--packages`: alias para `--mode debian` (instalación desde paquetes Debian no interactiva)
- `--show-versions` / `--versions`: muestra el candidato Debian, la etiqueta local en `hypr-tags.env` y la versión upstream de Hyprland, luego termina
- `--debian-install`: instala el stack Hyprland desde los repos de Debian y omite la compilación desde fuente
- `--debian-remove`: elimina los paquetes del stack Hyprland de Debian y termina
- `--no-fetch`: omite la obtención automática de etiquetas al usar `--install`
- `--bundled`: compila Hyprland con los subproyectos hypr* empaquetados en lugar de las librerías del sistema
- `--system`: prefiere las librerías hypr* instaladas en el sistema (por defecto)
- `--minimal`: compila solo el stack mínimo de prerrequisitos antes de Hyprland
- `--via-helper`: delega el dry-run a `dry-run-build.sh` para una vista de resumen compacta

Variables de entorno:
- `FORCE=1`: equivalente a `--force-update`
- `HYPR_AUTO_MODE_POLICY`: controla el comportamiento de `--mode auto` — `debian-default` (por defecto, selecciona el modo de paquetes Debian silenciosamente) o `menu` (prompt interactivo que compara versiones Debian/local/upstream)

Notas:
- Cuando el modo trixie está habilitado, `update-hyprland.sh` exporta `HYPR_BUILD_TRIXIE=1` y reenvía `--build-trixie` a los scripts de módulos.
- `--package-cleanup` elimina paquetes Hyprland de Debian para evitar versiones mezcladas (Hyprland, hyprutils/lang/graphics/cursor/wire, aquamarine, soporte Qt, guiutils, apps como hypridle/lock/picker/paper/sunset/launcher/systeminfo, hyprpm/hyprctl y xdg-desktop-portal-hyprland).
- En modo fuente con `--install`, `--package-cleanup` se activa automáticamente para evitar instalaciones mixtas Debian/fuente.
- En modo fuente con `--install`, las etiquetas se obtienen automáticamente antes de compilar, a menos que se use `--no-fetch`.

### Flags de install.sh

- `--preset <archivo>`: ejecutar con elecciones predefinidas
- `--build-trixie` / `--no-trixie`: habilita/deshabilita modo de compatibilidad Debian 13

También puedes forzar por variable de entorno:

```bash
HYPR_BUILD_TRIXIE=1 ./install.sh
```

### Flags de refresh-hypr-tags.sh

- `--get-latest` / `--fetch-latest`: refresca etiquetas a las últimas releases de GitHub (alias; el script siempre obtiene las últimas)
- `--force-update` / `--force`: forzar sobrescritura de valores fijados en `hypr-tags.env`

Equivalente con variable de entorno:

```bash
FORCE=1 ./refresh-hypr-tags.sh
# o
./refresh-hypr-tags.sh --force-update
```

Variable de entorno opcional para evitar límites de la API de GitHub:

```bash
GITHUB_TOKEN=<token> ./refresh-hypr-tags.sh
# GH_TOKEN también es aceptado
```

En sesiones interactivas el script muestra un resumen de los cambios planeados y solicita confirmación antes de escribir. Las ejecuciones no interactivas escriben inmediatamente.

## Modo de Compatibilidad Debian 13 (Trixie)

Versiones nuevas de Hyprland (0.53.x+) pueden requerir shims de compatibilidad en Debian 13 (trixie) debido a diferencias del toolchain/stdlib.

- Por defecto es **auto-detectado** (vía `/etc/os-release`): si `ID=debian` y `VERSION_CODENAME=trixie`, el modo se habilita.
- Puedes forzarlo ON/OFF:

```bash
# Forzar ON
./update-hyprland.sh --build-trixie --install

# Forzar OFF
./update-hyprland.sh --no-trixie --install
```

## Modo de Paquetes Debian

`update-hyprland.sh` ahora soporta instalar Hyprland directamente desde los repositorios de Debian además de compilar desde el código fuente. **El modo de paquetes Debian es el comportamiento por defecto** cuando no se especifica ningún flag de modo.

### Selección de Modo

- `--mode debian` / `--deb-pkg` / `--packages`: instalar desde los repos de Debian (sin compilación)
- `--mode source` / `--source`: compilar desde el código fuente usando las versiones en `hypr-tags.env`
- `--mode auto` (por defecto): comportamiento controlado por `HYPR_AUTO_MODE_POLICY`
  - `debian-default` (por defecto): selecciona el modo de paquetes Debian silenciosamente
  - `menu`: muestra un prompt interactivo con el candidato Debian, la etiqueta local y la versión upstream

Establece `HYPR_AUTO_MODE_POLICY=menu` en tu entorno para obtener el prompt de comparación de versiones en cada ejecución.

### Verificar Versiones Antes de Elegir

```bash
# Mostrar candidato Debian, etiqueta local en hypr-tags.env y última versión upstream, luego terminar
./update-hyprland.sh --show-versions
```

### Instalar en Modo de Paquetes Debian

```bash
# Instalación por defecto (modo de paquetes Debian)
./update-hyprland.sh --install

# Instalación explícita desde paquetes Debian
./update-hyprland.sh --deb-pkg --install
```

En **Trixie**, el script añade automáticamente `trixie-backports` si no está configurado.

### Instalar en Modo de Código Fuente

```bash
# Compilación desde fuente usando el hypr-tags.env actual
./update-hyprland.sh --source --install

# Compilación desde fuente tras obtener las últimas etiquetas
./update-hyprland.sh --source --fetch-latest --install
```

Cambiar al modo fuente purga automáticamente los paquetes Hyprland de Debian para evitar conflictos de versiones mixtas.

### Eliminar Paquetes Hyprland de Debian

```bash
./update-hyprland.sh --debian-remove
```

## Gestión Central de Versiones

### hypr-tags.env

Archivo con etiquetas de versión para todos los componentes de Hyprland:

```bash
# Etiquetas del stack base (ejemplo — los valores reales son actualizados por refresh-hypr-tags.sh)
HYPRLAND_TAG=v0.53.3
AQUAMARINE_TAG=v0.10.0
HYPRUTILS_TAG=v0.11.0
HYPRLANG_TAG=v0.6.8
HYPRGRAPHICS_TAG=v0.5.0
HYPRTOOLKIT_TAG=v0.4.1
HYPRWAYLAND_SCANNER_TAG=v0.4.5
HYPRLAND_PROTOCOLS_TAG=v0.7.0
HYPRLAND_QT_SUPPORT_TAG=v0.1.0
HYPRLAND_QTUTILS_TAG=v0.1.5
HYPRLAND_GUIUTILS_TAG=v0.2.0
HYPRWIRE_TAG=main
WAYLAND_PROTOCOLS_TAG=1.46
XDPH_TAG=v1.3.12
```

`HYPRWIRE_TAG` siempre está fijado a `main` (sin releases versionadas). Al ejecutar `refresh-hypr-tags.sh`, también se rastrean y actualizan etiquetas específicas de apps: `HYPRIDLE_TAG`, `HYPRLOCK_TAG`, `HYPRPICKER_TAG`, `HYPRSUNSET_TAG`, `HYPRLAUNCHER_TAG`, `HYPRSYSTEMINFO_TAG` y otras.

### Refrescar etiquetas (últimas releases)

Puedes refrescar `hypr-tags.env` a las últimas etiquetas publicadas en GitHub:

```bash
# Actualiza solo claves en auto/latest (o sin valor)
./refresh-hypr-tags.sh --get-latest

# Forzar sobrescritura de valores fijados
FORCE=1 ./refresh-hypr-tags.sh --get-latest
# o
./refresh-hypr-tags.sh --force-update
```

### Prioridad de Sobrescritura de Versiones

1. Variables de entorno (exportadas)
2. Valores en el archivo `hypr-tags.env`
3. Valores por defecto en cada módulo

## Métodos de Instalación

### Método 1: Instalación Completa Original

```bash
# Instalación estándar con todos los componentes
chmod +x install.sh
./install.sh
```

Ahora, este método automáticamente:

- Carga versiones desde `hypr-tags.env`
- Instala wayland-protocols desde el origen antes de Hyprland
- Mantiene el orden correcto de dependencias

### Método 2a: Stack de Hyprland desde Paquetes Debian (por defecto)

```bash
# Instalar desde los repos de Debian (modo por defecto)
./update-hyprland.sh --install
# o explícitamente:
./update-hyprland.sh --deb-pkg --install
```

### Método 2b: Stack de Hyprland desde Código Fuente

```bash
# Compilar desde el código fuente usando el hypr-tags.env actual
./update-hyprland.sh --source --install
```

Cambiar de paquetes Debian a modo fuente purga automáticamente los paquetes Debian primero. Para hacerlo manualmente:

```bash
./update-hyprland.sh --debian-remove
./update-hyprland.sh --source --install
```

### Método 3: Instalación Nueva desde Fuente con Últimas Versiones

```bash
# Obtener las últimas etiquetas de GitHub e instalar desde fuente
./update-hyprland.sh --source --fetch-latest --install

# Sobrescribir todos los valores fijados (incluidos los fijados manualmente):
./update-hyprland.sh --source --fetch-latest --force-update --install
```

### Método 4: Instalación con Preset

```bash
# Usa un preset para elecciones automáticas
./install.sh --preset ./preset.sh
```

## Flujos de Actualización

Enlace rápido: [Actualización 0.49/0.50.x → 0.51.1](#actualización-049050x--0511)

### Actualizar a la Última Versión de Hyprland

#### Opción A: Descubrimiento Automático (compilación desde fuente)

```bash
# Obtener las últimas etiquetas e instalar desde fuente (respeta pins en hypr-tags.env)
./update-hyprland.sh --source --fetch-latest --install

# Forzar la actualización de todas las etiquetas
./update-hyprland.sh --source --fetch-latest --force-update --install
```

#### Opción B: Versión Específica (compilación desde fuente)

```bash
# Establecer una versión específica de Hyprland y compilar desde fuente
./update-hyprland.sh --source --set HYPRLAND=v0.51.1 --install
```

#### Opción C: Probar Antes de Instalar

```bash
# Compilar y probar primero (modo fuente), luego instalar si es exitoso
./update-hyprland.sh --source --fetch-latest --dry-run
# Si es exitoso:
./update-hyprland.sh --source --install
```

### Actualizar Componentes Individuales

```bash
# Actualiza solo librerías núcleo desde fuente
./update-hyprland.sh --source --fetch-latest --install --only hyprutils,hyprlang

# Actualiza aquamarine específicamente
./update-hyprland.sh --source --set AQUAMARINE=v0.9.3 --install --only aquamarine
```

### Actualizaciones Selectivas

```bash
# Instalar todo excepto los componentes Qt (modo fuente)
./update-hyprland.sh --source --install --skip hyprland-qt-support,hyprland-qtutils

# Instalar solo componentes específicos
./update-hyprland.sh --source --install --only hyprland,aquamarine
```

### Actualización: 0.49/0.50.x ➜ 0.51.1

Si actualmente estás en Hyprland 0.49 o 0.50.x, puedes actualizar directamente a 0.51.1 sin una reinstalación completa.

Ruta recomendada:

```bash
# Asegura que hypr-tags.env apunte a la versión objetivo (omitir si ya es v0.51.1)
./update-hyprland.sh --set HYPRLAND=v0.51.1

# Actualiza Hyprland desde fuente (prerrequisitos se incluyen y ordenan automáticamente)
./update-hyprland.sh --source --install --only hyprland
```

Notas:

- El comando garantiza y ejecuta, según sea necesario: wayland-protocols-src, hyprland-protocols, hyprutils, hyprlang, aquamarine y luego hyprland.
- No es necesario usar install.sh para esta actualización, a menos que también quieras instalar/actualizar módulos opcionales (p. ej., SDDM, Bluetooth, Thunar, AGS, dotfiles) o estés recuperándote de una instalación fallida/parcial.
- Opcional: agrega --with-deps para reinstalar dependencias primero:

```bash
./update-hyprland.sh --source --with-deps --install --only hyprland
```

- Puedes hacer un dry-run primero para validar:

```bash
./update-hyprland.sh --source --dry-run --only hyprland
```

## Pruebas con Dry-Run

### ¿Por qué usar Dry-Run?

- Probar compatibilidad de compilación antes de instalar
- Validar combinaciones de versiones
- Depurar problemas de compilación sin cambios en el sistema
- Integración en CI/CD

### Uso Básico de Dry-Run

Las pruebas de dry-run son operaciones de modo fuente. Añade `--source` para asegurar que se ejecute la prueba de compilación en lugar de verificar la disponibilidad de paquetes Debian:

```bash
# Probar la configuración actual de versiones
./update-hyprland.sh --source --dry-run

# Probar con últimas versiones de GitHub
./update-hyprland.sh --source --fetch-latest --dry-run

# Probar una versión específica
./update-hyprland.sh --source --set HYPRLAND=v0.51.1 --dry-run
```

### Pruebas Avanzadas con Dry-Run

```bash
# Formato alternativo de resumen
./update-hyprland.sh --via-helper

# Probar con instalación de dependencias
./dry-run-build.sh --with-deps

# Probar solo componentes específicos
./dry-run-build.sh --only hyprland,aquamarine
```

### Limitaciones de Dry-Run

- **Las dependencias se instalan**: apt se ejecuta para asegurar la compilación
- **Requisitos de pkg-config**: Algunos componentes necesitan requisitos instalados en el sistema
- **Sin cambios en el sistema**: No instala archivos en /usr/local o /usr

## Gestión de Logs
## Artefactos de Build y Limpieza

Todas las fuentes descargadas y salidas de compilación ahora viven en `~/Debian-Hyprland/build/`:

- **Fuentes:** `build/src/<proyecto>`
- **Salida de build:** `build/<proyecto>`

Esto mantiene el repositorio limpio. Para eliminar todos los artefactos de compilación:

```bash
rm -rf ~/Debian-Hyprland/build
```

Nota: Esto solo elimina artefactos de compilación y fuentes descargadas; no desinstala nada del sistema.

### Ubicación de Logs

Todas las actividades de construcción generan logs con sello de tiempo en:

```
Install-Logs/
├── 01-Hyprland-Install-Scripts-YYYY-MM-DD-HHMMSS.log  # Log principal de instalación
├── install-DD-HHMMSS_module-name.log                   # Logs por módulo
├── build-dry-run-YYYY-MM-DD-HHMMSS.log                # Resumen de dry-run
└── update-hypr-YYYY-MM-DD-HHMMSS.log                  # Resumen de actualización
```

### Análisis de Logs

```bash
# Ver el log de instalación más reciente
ls -t Install-Logs/*.log | head -1 | xargs less

# Buscar errores en un módulo específico
grep -i error Install-Logs/install-*hyprland*.log

# Ver resumen de dry-run
cat Install-Logs/build-dry-run-*.log
```

### Retención de Logs

- Los logs se acumulan con el tiempo para referencia histórica
- Se recomienda limpieza manual periódica:

```bash
# Mantener solo logs de los últimos 30 días
find Install-Logs/ -name "*.log" -mtime +30 -delete
```

## Uso Avanzado

### Gestión de Versiones

#### Forzar la Actualización de Todas las Etiquetas

```bash
# Sobrescribe valores fijados en hypr-tags.env con las últimas versiones
./update-hyprland.sh --source --fetch-latest --force-update --dry-run
# Instalar si la dry-run es exitosa
./update-hyprland.sh --source --force-update --install
```

#### Copia de Seguridad y Restauración

```bash
# Las etiquetas se respaldan automáticamente cuando cambian
# Restaurar la copia más reciente
./update-hyprland.sh --source --restore --dry-run
```

#### Múltiples Conjuntos de Versiones

```bash
# Guardar configuración actual
cp hypr-tags.env hypr-tags-stable.env

# Probar versiones experimentales desde fuente
./update-hyprland.sh --source --fetch-latest --dry-run

# Restaurar estable si es necesario
cp hypr-tags-stable.env hypr-tags.env
```

### Integración con el Entorno

#### PKG_CONFIG_PATH personalizado (compilaciones desde fuente)

```bash
# Asegurar que /usr/local tenga prioridad
export PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:/usr/local/share/pkgconfig:${PKG_CONFIG_PATH:-}"
./update-hyprland.sh --source --install
```

#### Compilaciones en Paralelo

```bash
# Controlar el paralelismo (por defecto: todos los núcleos)
export MAKEFLAGS="-j4"
./update-hyprland.sh --source --install
```

### Flujo de Trabajo de Desarrollo

#### Probar Nuevos Lanzamientos

```bash
# 1. Crear entorno de pruebas
cp hypr-tags.env hypr-tags.backup

# 2. Compilar y probar nueva versión desde fuente
./update-hyprland.sh --source --set HYPRLAND=v0.52.0 --dry-run

# 3. Instalar desde fuente si es exitoso
./update-hyprland.sh --source --install

# 4. Revertir si hay problemas
./update-hyprland.sh --source --restore --install
```

#### Desarrollo de Componentes

```bash
# Solo instalar dependencias
./update-hyprland.sh --source --with-deps --dry-run

# Pruebas manuales de módulo
DRY_RUN=1 ./install-scripts/hyprland.sh

# Ver logs de un módulo específico
tail -f Install-Logs/install-*hyprland*.log
```

## Solución de Problemas

### Problemas Comunes

#### Falla de Configuración con CMake

**Síntomas**: "Package dependency requirement not satisfied"

**Soluciones**:

```bash
# Instalar requisitos faltantes desde fuente
./update-hyprland.sh --source --install --only wayland-protocols-src,hyprutils,hyprlang

# Limpiar caché de compilación
rm -rf hyprland aquamarine hyprutils hyprlang

# Reintentar instalación
./update-hyprland.sh --source --install --only hyprland
```

#### Errores de Compilación

**Síntomas**: "too many errors emitted"

**Soluciones**:

```bash
# Actualizar dependencias núcleo desde fuente primero
./update-hyprland.sh --source --fetch-latest --install --only hyprutils,hyprlang

# Revisar incompatibilidades de API en logs
grep -A5 -B5 "error:" Install-Logs/install-*hyprland*.log
```

#### Etiqueta No Encontrada

**Síntomas**: "Remote branch X not found"

**Soluciones**:

```bash
# Ver etiquetas disponibles
git ls-remote --tags https://github.com/hyprwm/Hyprland

# Usar etiqueta confirmada
./update-hyprland.sh --source --set HYPRLAND=v0.50.1 --install
```

### Pasos de Depuración

1. **Verificar compatibilidad del sistema**:

    ```bash
    # Verificar versión de Debian
    cat /etc/os-release

    # Asegurar deb-src habilitado
    grep -rE "^[[:space:]]*(deb-src|Types:.*deb-src)" /etc/apt/sources.list /etc/apt/sources.list.d/
    ```

2. **Verificar entorno**:

    ```bash
    # Ver etiquetas actuales
    cat hypr-tags.env

    # Probar dry-run primero (modo fuente)
    ./update-hyprland.sh --source --dry-run --only hyprland
    ```

3. **Analizar logs**:

    ```bash
    # Errores más recientes
    grep -i "error\|fail" Install-Logs/*.log | tail -20

    # Problemas por módulo
    ls -la Install-Logs/install-*[component]*.log
    ```

### Obtener Ayuda

1. **Revisar logs**: Consulte siempre Install-Logs/ para detalles
2. **Probar dry-run**: Valide antes de instalar
3. **Soporte de la comunidad**: Envíe issues con extractos de logs
4. **Documentación**: Consulte README.md del proyecto para requisitos base

## Migración desde Versiones Previas

### Instalaciones Existentes

Las nuevas herramientas funcionan junto a instalaciones existentes:

```bash
# Actualizar vía paquetes Debian (por defecto)
./update-hyprland.sh --install

# Actualizar vía compilación desde fuente
./update-hyprland.sh --source --install

# Probar compilación desde fuente sin afectar el sistema actual
./update-hyprland.sh --source --dry-run
```

### Convertir a Gestión por Etiquetas

```bash
# Las versiones actuales se guardan en hypr-tags.env automáticamente
# Verificar con:
cat hypr-tags.env

# Modificar versiones según necesidad:
./update-hyprland.sh --set HYPRLAND=v0.51.1
```

El flujo mejorado ofrece mayor control, capacidad de prueba y automatización, manteniendo la compatibilidad total con el proceso de instalación original.
