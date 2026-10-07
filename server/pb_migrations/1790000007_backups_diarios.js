/// <reference path="../pb_data/types.d.ts" />
// Copias de seguridad automáticas de PocketBase: cada día a las 04:00 (hora del servidor), conservando las 7 últimas.
// Quedan en pb_data/backups/ (en el mismo disco: ver server/backup_pull.sh para guardar una copia fuera).
migrate((app) => {
  const s = app.settings();
  s.backups.cron = "0 4 * * *";
  s.backups.cronMaxKeep = 7;
  app.save(s);
}, (app) => {
  const s = app.settings();
  s.backups.cron = "";
  app.save(s);
});
