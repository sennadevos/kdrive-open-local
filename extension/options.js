"use strict";

const checkbox = document.getElementById("openFilesDirectly");

browser.storage.local.get("openFilesDirectly").then(({ openFilesDirectly }) => {
  checkbox.checked = Boolean(openFilesDirectly);
});

checkbox.addEventListener("change", () => {
  browser.storage.local.set({ openFilesDirectly: checkbox.checked });
});
