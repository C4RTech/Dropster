@echo off
REM Script to commit & push repository and create tag Dropster_BETA_1.0
REM Usage: Run this script from the project root (e.g., C:\Users\Usuario\Desktop\dropster)

cd /d %~dp0
echo Working directory: %cd%
echo.

echo === Git status ===
git status
echo.

echo === Adding changes ===
git add -A

echo === Committing ===
git commit -m "DROPSTER BETA 1.0" || echo "No changes to commit or commit failed"
echo.

REM Check if origin remote exists
git remote get-url origin >nul 2>&1
if %errorlevel% neq 0 (
  echo Remote 'origin' not found. Adding origin -> https://github.com/C4RTech/Dropster.git
  git remote add origin https://github.com/C4RTech/Dropster.git
) else (
  echo Remote 'origin' exists:
  git remote -v
)
echo.

REM Determine current branch
for /f "tokens=*" %%i in ('git rev-parse --abbrev-ref HEAD') do set BRANCH_NAME=%%i
echo Current branch is %BRANCH_NAME%
echo.

REM Push current HEAD to remote main
echo Pushing current HEAD to origin main...
git push -u origin HEAD:refs/heads/main
echo.

REM Create annotated tag and push it
echo Creating annotated tag: Dropster_BETA_1.0
git tag -a Dropster_BETA_1.0 -m "Dropster Beta 1.0"
echo Pushing tag to origin...
git push origin Dropster_BETA_1.0
echo.

REM Optional: create GitHub release with GH CLI (if installed and authenticated)
echo If you have GitHub CLI (gh) installed and authenticated you can create a release with:
echo gh release create Dropster_BETA_1.0 --title "Dropster Beta 1.0" --notes-file CHANGELOG.md
echo.

echo Done.
pause
exit /b 0