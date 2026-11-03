# Google Play listing — Tinker: Contraption Puzzles

App: **Tinker: Contraption Puzzles** · package `my.otono.tinker` · Play Console app id 4973318101926770067
(Techmatters personal account). Build: `PROJECT=gen-lang-client-0293187856 bash tools/build_aab.sh` after
`tools/build_clients.sh` → `build/play/tinker-<versionCode>.aab`. Upload key: Secret Manager
`tinker-upload-keystore` (+ `-password`), alias `upload`. Play App Signing holds the app signing key.

## Store listing (Grow users → Store presence → Main store listing)

**App name (30):** Tinker: Contraption Puzzles

**Short description (≤80):**
Build silly machines from planks, ropes and balloons. A new puzzle every day.

**Full description (≤4000):**
Tinker is a physics puzzle game about building wonderfully silly machines.

Drag planks, springs, fans, ropes, pulleys, balloons and candles onto the board, press RUN, and watch
your contraption roll, swing, pop and bounce until the ball lands in the basket, the candle lights, or
the mouse finally gets its cheese.

★ 40 hand-made levels across 4 worlds: Workshop, Tight squeeze, Menagerie and Rigging
★ The Daily: the same puzzle for everyone, every day. Use the fewest parts, climb the leaderboard
★ Real physics: every machine plays out exactly the same way every time, so a good idea always works
★ Sandbox: build your own level with every part, solve it, and send the link to a friend
★ Leaderboards: today's Daily, yesterday's, and the campaign, worldwide or in your country
★ Stuck? Hints show where a part goes. Coins come from solving levels, the Daily and the daily bonus

No account needed. Optional purchases: coin packs and a "no ads" pass.

**Category:** Game → Puzzle · **Tags:** Puzzle, Physics, Casual, Logic, Brain
**Contact email:** (Bassel to choose: also set it in the admin console → Store → Publisher)
**Website:** https://otono.my
**Privacy policy URL:** https://tinker-api-yp2v2qmz3a-ew.a.run.app/privacy

**Graphics:** `icon_512.png` (512×512) · `feature_graphic_1024x500.png` · phone screenshots in
`screens/` (1080×1920, 9:16): map, machine running, pop and drop, leaderboard, hint.

## App content (Policy → App content)

| Form | Answer |
|---|---|
| Privacy policy | URL above |
| Ads | **Yes, contains ads** (rewarded ads for tries/coins; interstitials only if switched on in the admin console) |
| App access | All functionality is available without special access (no login) |
| Content rating (IARC) | Category: Game. Violence: none (cartoon cat chases a mouse, no harm shown). Fear, sex, language, drugs, gambling: none. Users interact / share content: **yes** (shared Sandbox levels, display names on leaderboards). Digital purchases: **yes**. Location sharing: no. Expected rating: Everyone / PEGI 3 |
| Target audience | **13+** (13–15, 16–17, 18+). Not designed for children: avoids the Families policy, which needs family-certified ad networks |
| News app | No |
| COVID-19, health, financial features, government | No |
| Data safety | see below |

### Data safety

Data is **encrypted in transit** (HTTPS). Users **can request deletion** (contact email, device id from
Settings). No data is **sold**. Collection is **required** unless marked optional.

| Data type (Play category) | Collected | Shared | Purpose |
|---|---|---|---|
| Personal info → Name (display name on leaderboards) | Yes, **optional** | No | App functionality |
| Financial info → Purchase history | Yes | No | App functionality, account management (wallet, refunds) |
| App activity → App interactions (levels solved, runs, hints, ads watched) | Yes | No | App functionality, analytics |
| App activity → Other user-generated content (shared Sandbox levels) | Yes | No | App functionality |
| App info and performance → Other app performance data (OS version, device model, app version) | Yes | No | Analytics, app functionality |
| Device or other IDs (app-generated random id; push token) | Yes | No | App functionality, analytics, fraud prevention |
| Device or other IDs → advertising ID | **Only once AdMob is switched on** (by the ads SDK) | Yes (ad network) | Advertising |
| Location, contacts, photos, audio, files, messages, health, web history | No | | |

When AdMob is enabled later, update Data safety (advertising ID shared with Google for advertising) and
add the `com.google.android.gms.permission.AD_ID` permission.

## In-app products (Monetise with Play → Products → In-app products)

Same ids as the admin console (Store → Products). Create each as a **one-time product**, consumable:

| Product id | Name | Price (USD) |
|---|---|---|
| coins_200 | Handful of coins (200) | 0.99 |
| coins_1200 | Bag of coins (1200) | 4.99 |
| coins_2600 | Chest of coins (2600) | 9.99 |
| noads_7d | No ads for 7 days | 1.99 |
| noads_30d | No ads for 30 days | 3.99 |
| noads_forever | No ads, forever | 7.99 |
| starter_pack | Starter pack: 500 coins + 7 days no ads | 2.99 |

Products can only be created after the first bundle containing the BILLING permission is uploaded.

## API access for purchase verification and releases

Play Console → Users and permissions → Invite new users → the Cloud Run runtime service account
`tinker-api@gen-lang-client-0293187856.iam.gserviceaccount.com`, app **Tinker**, permissions: View app
information; View financial data, orders and cancellation survey responses; Manage orders and
subscriptions; Release to testing tracks. Then switch the admin console Store → Mode to **live**.

## Closed testing (personal account rule)

At least **12 testers opted in for 14 continuous days** before applying for production access.
Testing → Closed testing → create track "Closed testing - Alpha" → Testers: an email list (Google
accounts) → share the opt-in link. Internal testing (up to 100 testers, no review) is available at once.
