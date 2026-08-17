@echo off
setlocal EnableExtensions
title BoutonSPAM - creation / verification du layout Visual Studio

rem ============================================================================
rem  99_make-layout.cmd - lanceur double-clic pour 06_layout.ps1.
rem
rem  Verifie le layout (charges Office + .NET desktop + pack de ciblage 4.8) et,
rem  si le poste est EN LIGNE, telecharge le manquant DANS installers\vslayout
rem  (dans le projet), pret a copier tel quel sur un poste hors ligne.
rem  Le layout n'est JAMAIS inclus dans l'archive (00_make-archive.sh).
rem
rem  Layout PARTIEL bloque ? (le moteur affiche "Total packages to download: 0"
rem  alors qu'il manque des charges) -> relancez en mode propre :
rem     powershell -ExecutionPolicy Bypass -File 06_layout.ps1 -Download -Fresh
rem  (ou ajoutez -Fresh a la ligne d'appel ci-dessous.)
rem ============================================================================

set "HERE=%~dp0"
if not exist "%HERE%06_layout.ps1" (
  echo ERREUR : 06_layout.ps1 introuvable a cote de ce fichier ^(%HERE%^).
  pause
  exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%HERE%06_layout.ps1" -Download
set "RC=%ERRORLEVEL%"
echo.
echo Code de sortie : %RC%   ^(0 = layout complet et verifie^)
if not "%RC%"=="0" (
  echo.
  echo Le layout n'est pas encore complet. Relancez ce fichier pour REPRENDRE,
  echo ou en cas de blocage : 06_layout.ps1 -Download -Fresh
)
pause
