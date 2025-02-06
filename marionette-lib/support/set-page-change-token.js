const Marionette = window.$$marionette || {};
if (Marionette.PageChangeToken === undefined) {
  Marionette.PageChangeToken = arguments[0];
  if (Marionette.patchedHistory === undefined) {
    Marionette.patchedHistory = true;
    for (const method of ["pushState", "replaceState"]) {
      window.history[method] = new Proxy(window.history[method], {
        apply: (target, self, args) => {
          delete Marionette["PageChangeToken"];
          return target.apply(self, args);
        },
      });
    }
  }
}
window.$$marionette = Marionette;
