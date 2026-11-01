# Tinker — store readiness checklist

Part of "done" for M7. Keep every artefact in the repo.

- [x] Working title chosen: Tinker (see docs/PROGRESS.md Decisions for the search results)
- [ ] Trademark: lawyer glance at TINKER serial 99107334 (Thinking Machines Lab, class 9) before listing
- [ ] Final icon (placeholder at `game/assets/icons/icon.svg`)
- [ ] Privacy policy page hosted (device id only, no ads SDK unless `ads_enabled` ships on)
- [ ] Age rating: everyone / 4+ (no gambling, no violence beyond cartoon cat and mouse)
- [ ] 6 portrait screenshots per store, one 15-second trailer from Daily GIFs
- [ ] Apple Developer and Google Play accounts; signing keys in GitHub secrets (never in the repo)
- [ ] In-app purchase configured in both consoles and tested in sandbox; price set in consoles, not in code
- [ ] Store description written without any wagering vocabulary
- [ ] `ads_enabled` remote config flag, default off; interstitials in code but never shown unless on

Package id: `my.otono.tinker` (set in `game/export_presets.cfg`; change before first upload if a different id is wanted).
