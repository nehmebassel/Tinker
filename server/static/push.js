// Tinker web push (FCM). Loaded by the game's HTML shell (/play/push.js).
// window.tinkerPush is read by the Godot game through JavaScriptBridge:
//   status: "unsupported" | "default" | "denied" | "granted" | "error"
//   token:  FCM registration token once known ("" until then)
//   prompt(): shows an HTML "Allow" dialog; the browser permission request runs inside that real tap
//             (iOS only allows it from a user gesture, and only for installed PWAs).
(function () {
  const FB = "https://www.gstatic.com/firebasejs/11.10.0/";
  const state = { status: "default", token: "", error: "", prompt: () => {} };
  window.tinkerPush = state;

  const supported = "serviceWorker" in navigator && "PushManager" in window && "Notification" in window;
  if (!supported) { state.status = "unsupported"; return; }
  state.status = Notification.permission;

  function load(src) {
    return new Promise((ok, bad) => { const s = document.createElement("script"); s.src = src; s.onload = ok; s.onerror = bad; document.head.appendChild(s); });
  }

  let messaging = null, swReg = null, cfg = null;
  async function setup() {
    if (messaging) return;
    const r = await fetch("../push/config");
    cfg = await r.json();
    if (!cfg.web || !cfg.web.apiKey) throw new Error("push not configured on the server");
    await load(FB + "firebase-app-compat.js");
    await load(FB + "firebase-messaging-compat.js");
    firebase.initializeApp(cfg.web);
    messaging = firebase.messaging();
    const q = encodeURIComponent(JSON.stringify(cfg.web));
    swReg = await navigator.serviceWorker.register("fcm/sw.js?config=" + q, { scope: "fcm/" });
    // Foreground messages: show them too (the SW handles background ones).
    messaging.onMessage((m) => {
      const n = m.notification || {};
      swReg.showNotification(n.title || "Tinker", { body: n.body || "", icon: "index.144x144.png", data: { url: "./" } });
    });
  }

  async function fetchToken() {
    try {
      await setup();
      const opts = { serviceWorkerRegistration: swReg };
      if (cfg.vapidKey) opts.vapidKey = cfg.vapidKey;
      state.token = await messaging.getToken(opts);
      state.status = "granted";
    } catch (e) {
      state.status = Notification.permission === "denied" ? "denied" : "error";
      state.error = String(e && e.message || e);
      console.warn("tinkerPush:", state.error);
    }
  }

  // Already allowed on an earlier visit: get the (possibly refreshed) token silently.
  if (Notification.permission === "granted") fetchToken();

  state.prompt = function () {
    if (Notification.permission === "granted") { fetchToken(); return; }
    if (Notification.permission === "denied") { state.status = "denied"; return; }
    if (document.getElementById("tinker-push-ask")) return;
    const box = document.createElement("div");
    box.id = "tinker-push-ask";
    box.style.cssText = "position:fixed;inset:auto 16px 24px 16px;z-index:9999;background:#2d2a4a;color:#fbf6ea;border:5px solid #1f1a2e;border-radius:24px;padding:20px;font:600 18px system-ui,sans-serif;box-shadow:0 8px 24px rgba(0,0,0,.35)";
    box.innerHTML = '<div style="margin-bottom:14px">Get a reminder when the new Daily is ready?</div>' +
      '<div style="display:flex;gap:12px"><button id="tp-yes" style="flex:1;padding:14px;border-radius:16px;border:4px solid #1f1a2e;background:#7bd389;font:700 18px system-ui">Allow</button>' +
      '<button id="tp-no" style="flex:1;padding:14px;border-radius:16px;border:4px solid #1f1a2e;background:#c9c2b6;font:700 18px system-ui">Not now</button></div>';
    document.body.appendChild(box);
    box.querySelector("#tp-no").onclick = () => box.remove();
    box.querySelector("#tp-yes").onclick = async () => {
      box.remove();
      const p = await Notification.requestPermission();  // inside the tap: allowed on iOS PWAs
      state.status = p;
      if (p === "granted") fetchToken();
    };
  };
})();
