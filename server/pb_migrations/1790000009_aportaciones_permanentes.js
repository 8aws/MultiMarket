/// <reference path="../pb_data/types.d.ts" />
// Las aportaciones APROBADAS (fotos y productos) pasan a ser permanentes en la base común:
// su autor ya no puede borrarlas. Mientras estén pendientes sí puede retirarlas.
// Una petición de supresión de datos personales dentro de una foto se atiende por el administrador.
migrate((app) => {
  for (const nombre of ["fotos", "productos"]) {
    const c = app.findCollectionByNameOrId(nombre);
    c.deleteRule = 'owner = @request.auth.id && status != "approved"';
    app.save(c);
  }
}, (app) => {
  for (const nombre of ["fotos", "productos"]) {
    const c = app.findCollectionByNameOrId(nombre);
    c.deleteRule = 'owner = @request.auth.id';
    app.save(c);
  }
});
