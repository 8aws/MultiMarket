/// <reference path="../pb_data/types.d.ts" />
// Las cuentas de dispositivo usan correos @device.invalid: el aviso «inicio de sesión desde una ubicación nueva»
// solo generaba un intento de correo rechazado por el relay (450) en cada acceso desde otra red.
migrate((app) => {
  const users = app.findCollectionByNameOrId("users");
  users.authAlert.enabled = false;
  app.save(users);
}, (app) => {
  const users = app.findCollectionByNameOrId("users");
  users.authAlert.enabled = true;
  app.save(users);
});
