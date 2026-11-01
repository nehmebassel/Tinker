import { createApp } from "./app.js";
import { config } from "./config.js";

const app = createApp();
app.listen(config.port, () => {
  console.log(`tinker-server listening on :${config.port} (project=${config.project || "-"}, emulator=${config.emulator}, godot=${config.godotBin})`);
});
