#!/bin/bash
# Installs the smooth cross-fade rotator for the rack display. Run on pve2 (the kiosk node) as root.
cat > /home/kiosk/rack.html <<'RACKEOF'
<!doctype html>
<html><head><meta charset="utf-8"><title>Homelab Rack</title>
<style>
  html,body{margin:0;height:100%;background:#111217;overflow:hidden;cursor:none}
  iframe{position:absolute;inset:0;width:100%;height:100%;border:0;background:#111217;
         opacity:0;transition:opacity 1s ease-in-out}
  iframe.show{opacity:1}
</style></head>
<body>
<iframe id="a" scrolling="no"></iframe><iframe id="b" scrolling="no"></iframe>
<script>
// ---- settings ----
const GRAFANA = "http://10.0.0.31:3000";
const SCREENS = ["rack-overview","rack-alerts","rack-status","rack-cluster","rack-homelab","rack-guests",
                 "rack-nas","rack-capacity","rack-backups","rack-internet","rack-network","rack-wireless",
                 "rack-pihole","rack-services","rack-reliability","rack-gym"];
const SECONDS  = 15;          // time per screen
const PRELOAD  = 6;           // start loading the next screen this many seconds early
const NIGHT    = {from: 23, to: 6, screen: "rack-night"};   // dim clock between 11 pm and 6 am
const RELOAD_EVERY_H = 6;     // full page reload to keep Chrome's memory in check

const url = uid => `${GRAFANA}/d/${uid}?kiosk=true&theme=dark&_=${Date.now()}`;
const frames = [document.getElementById("a"), document.getElementById("b")];
let front = 0, i = 0;
const started = Date.now();

function isNight() { const h = new Date().getHours(); return NIGHT.from > NIGHT.to ? (h >= NIGHT.from || h < NIGHT.to) : (h >= NIGHT.from && h < NIGHT.to); }
function nextUid() { return isNight() ? NIGHT.screen : SCREENS[i % SCREENS.length]; }

function cycle() {
  if (Date.now() - started > RELOAD_EVERY_H * 3600e3) { location.reload(); return; }
  const back = 1 - front, uid = nextUid(), wait = isNight() ? 600 : SECONDS;   // night: refresh every 10 min
  frames[back].src = url(uid);                                     // load hidden
  setTimeout(() => {                                               // then cross-fade
    frames[back].classList.add("show");
    frames[front].classList.remove("show");
    const old = frames[front];
    setTimeout(() => { old.src = "about:blank"; }, 1500);          // free the old page's memory
    front = back;
    if (!isNight()) i++;
    setTimeout(cycle, (wait - PRELOAD) * 1000);
  }, PRELOAD * 1000);
}
// first screen: show as soon as it has loaded
frames[0].src = url(nextUid()); if (!isNight()) i++;
frames[0].onload = () => { frames[0].classList.add("show"); frames[0].onload = null; };
setTimeout(cycle, (SECONDS - PRELOAD) * 1000);
</script>
</body></html>
RACKEOF
chown kiosk:kiosk /home/kiosk/rack.html
cp /home/kiosk/start.sh /home/kiosk/start.sh.bak
sed -i 's|^KIOSK_URL=.*|KIOSK_URL="file:///home/kiosk/rack.html"|' /home/kiosk/start.sh
grep -n '^KIOSK_URL' /home/kiosk/start.sh
systemctl restart getty@tty1
echo "Rotator installed - the rack display restarts in a few seconds."
