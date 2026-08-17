@echo off
setlocal EnableExtensions
REM ============================================================
REM  install-silencieux.cmd - installation SILENCIEUSE d'un poste
REM  ZERO ACTION UTILISATEUR : MSI /qn + prerequis VSTO + config
REM  registre + anti-desactivation Outlook.
REM  A lancer EN ADMINISTRATEUR. Utilisable tel quel par SCCM /
REM  Intune (Win32) / script de deploiement / GPO de demarrage.
REM ============================================================
set "HERE=%~dp0"

REM --- [1/4] Prerequis : VSTO Runtime (silencieux, si fourni et absent) ---
if exist "%HERE%..\installers\vstor_redist.exe" (
  reg query "HKLM\SOFTWARE\Microsoft\VSTO Runtime Setup\v4R" /v Version >nul 2>&1
  if errorlevel 1 (
    echo [1/4] Installation du VSTO Runtime ^(silencieux^) ...
    "%HERE%..\installers\vstor_redist.exe" /q /norestart
  ) else (
    echo [1/4] VSTO Runtime deja present.
  )
) else (
  echo [1/4] vstor_redist.exe non fourni : suppose deja present ^(installe avec Office^).
)

REM --- [2/4] MSI en mode silencieux (aucune fenetre, aucune question) ---
set "MSI="
for %%f in ("%HERE%..\setup\Release\*.msi") do set "MSI=%%~ff"
if not defined MSI (
  echo ERREUR : aucun MSI dans setup\Release\ - generer d'abord ^(scripts\04_build.ps1^).
  exit /b 1
)
echo [2/4] Installation de "%MSI%" ...
msiexec /i "%MSI%" /qn /norestart ALLUSERS=1
if errorlevel 1 (
  echo ERREUR : msiexec code %errorlevel%
  exit /b %errorlevel%
)

REM --- [3/4] Configuration (HKLM) ---
echo [3/4] Configuration ^(HKLM^) ...
reg import "%HERE%..\resources\RegistryConfig.reg"

REM --- [4/4] Anti-desactivation Outlook (HKCU, utilisateur COURANT) ---
echo [4/4] Anti-desactivation Outlook ^(HKCU, utilisateur courant^) ...
reg import "%HERE%..\resources\DoNotDisableAddinList.reg"
echo.
echo REMARQUE : l'anti-desactivation est PAR UTILISATEUR. En parc, preferer
echo la GPO utilisateur du modele deploy\ADMX ^(appliquee a l'ouverture de
echo session, sans action de l'utilisateur^).
echo Termine : le bouton apparait au prochain demarrage d'Outlook.
exit /b 0
