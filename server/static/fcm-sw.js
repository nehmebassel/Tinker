// Firebase Cloud Messaging service worker for Tinker's web build. Registered by push.js with scope
// /play/fcm/ so it never collides with the game's own PWA service worker. The Firebase web config
// arrives in the query string (served by /push/config), so nothing is hard-coded here.
importScripts("https://www.gstatic.com/firebasejs/11.10.0/firebase-app-compat.js");
importScripts("https://www.gstatic.com/firebasejs/11.10.0/firebase-messaging-compat.js");
const cfg = JSON.parse(new URL(self.location).searchParams.get("config") || "{}");
firebase.initializeApp(cfg);
firebase.messaging();  // displays notification-payload messages while the game is in the background
self.addEventListener("notificationclick", (e) => {
  e.notification.close();
  const url = new URL("../", self.location).href;  // /play/
  e.waitUntil(clients.matchAll({ type: "window", includeUncontrolled: true }).then((ws) => {
    for (const w of ws) if (w.url.startsWith(url) && "focus" in w) return w.focus();
    return clients.openWindow(url);
  }));
});
