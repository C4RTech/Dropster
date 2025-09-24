@echo off
REM Script: Empuja la rama ci-build con el workflow actualizado
REM Úsalo desde la raíz del repositorio: C:\Users\Usuario\Desktop\dropster

REM 1) Cambiar a la rama ci-build (si no existe, crearla)
git rev-parse --verify ci-build >nul 2>&1
if %ERRORLEVEL% neq 0 (
  git checkout -b ci-build
) else (
  git checkout ci-build
)

REM 2) Asegurar que el workflow actualizado esté staged
git add .github/workflows/ci.yml

REM 3) Commit (si hay cambios)
git commit -m "ci: trigger PlatformIO on ci-build and allow manual dispatch" || echo No hay cambios para commitear

REM 4) Asegurar remote origin
git remote get-url origin >nul 2>&1
if %ERRORLEVEL% neq 0 (
  echo No se encontró 'origin'. Agrega el remote con:
  echo git remote add origin https://github.com/C4RTech/Dropster.git
  pause
  exit /b 1
)

REM 5) Push y seguimiento
git push -u origin ci-build

echo.
echo Empujado. Abre:
echo https://github.com/C4RTech/Dropster/actions
echo y busca el run asociado a la rama "ci-build" (debe aparecer como https://github.com/C4RTech/Dropster/actions/runs/<numero>)
pause