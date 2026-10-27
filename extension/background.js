"use strict";

// Must match the name of the native messaging manifest installed under
// ~/Library/Application Support/Mozilla/NativeMessagingHosts/.
const NATIVE_HOST = "com.sennadevos.kdrive_open_local";

// Only these can name a single drive item. The host re-parses the URL and is the authority on
// which shapes are understood; this filter just keeps us out of every other request.
const URL_FILTER = {
  urls: ["*://kdrive.infomaniak.com/*", "*://ksuite.infomaniak.com/*"],
  types: ["main_frame"],
};

let requestCounter = 0;

/**
 * Asks the native host to open the link locally.
 *
 * Returns a BlockingResponse. Cancelling is reserved for the one case where the item really did
 * open on the Mac; every other outcome — not synced, no kDrive client, host missing, host
 * crashed — must let the page load so the link never simply dies.
 */
async function onBeforeRequest(details) {
  if (details.method !== "GET") {
    return {};
  }

  const { openFilesDirectly } = await browser.storage.local.get("openFilesDirectly");

  let response;
  try {
    response = await browser.runtime.sendNativeMessage(NATIVE_HOST, {
      id: ++requestCounter,
      url: details.url,
      fileAction: openFilesDirectly ? "open" : "reveal",
    });
  } catch (error) {
    // The host is not installed, not executable, or died. Fall through to the web app.
    console.warn("kDrive open local: native host unavailable:", error);
    return {};
  }

  if (!response || response.status !== "opened") {
    if (response && response.status === "error") {
      console.warn("kDrive open local:", response.detail);
    }
    return {};
  }

  // The item is now showing in the Finder, so this navigation is redundant. A link followed from
  // inside a page leaves the tab on its current page; a link opened from Mail or Slack creates a
  // fresh tab that would be left blank, so close that one.
  closeIfBlank(details.tabId);
  return { cancel: true };
}

async function closeIfBlank(tabId) {
  if (tabId < 0) {
    return;
  }
  try {
    const tab = await browser.tabs.get(tabId);
    // After cancelling, tab.url is whatever the tab was showing before the navigation.
    if (!tab.url || tab.url === "about:blank" || tab.url === "about:newtab") {
      await browser.tabs.remove(tabId);
    }
  } catch (error) {
    // The tab went away on its own; nothing to do.
  }
}

browser.webRequest.onBeforeRequest.addListener(onBeforeRequest, URL_FILTER, ["blocking"]);
