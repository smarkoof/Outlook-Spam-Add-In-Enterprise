# logs/ — journaux d'exécution des scripts

Transcriptions complètes de ce que font les scripts, conservées même si le
terminal est fermé pendant une opération longue (installations notamment).

- `verification-<machine>-<AAAAMMJJ-HHMMSS>.log`         : inventaire du poste
- `verification-<machine>-<AAAAMMJJ-HHMMSS>-INSTALL.log` : exécution de -Install (installations)
- `customize-<AAAAMMJJ-HHMMSS>.log`                      : application de branding.conf
- `make-archive-<AAAAMMJJ-HHMMSS>.log`                   : génération de l'archive

Ces journaux sont horodatés (on les conserve) mais NON embarqués dans l'archive
et NON suivis par git (propres à chaque poste/exécution).
