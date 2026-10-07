/// <reference path="../pb_data/types.d.ts" />
// Los productos llevan los datos de su tienda para que otros dispositivos puedan mostrarla
// aunque no la tengan en su zona (id de OpenStreetMap ≠ cercanía local).
migrate((app) => {
  const items = app.findCollectionByNameOrId("items");
  items.fields.add(new TextField({ name: "store_name", max: 120 }));
  items.fields.add(new TextField({ name: "store_chain", max: 60 }));
  items.fields.add(new NumberField({ name: "store_lat" }));
  items.fields.add(new NumberField({ name: "store_lon" }));
  app.save(items);
}, (app) => {
  const items = app.findCollectionByNameOrId("items");
  for (const n of ["store_name", "store_chain", "store_lat", "store_lon"]) {
    items.fields.removeByName(n);
  }
  app.save(items);
});
