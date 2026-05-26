echo "== user =="
getent passwd zdmuser || true
sudo passwd -S zdmuser || true
echo "== sshd settings =="
sudo sshd -T 2>/dev/null | egrep 'passwordauthentication|kbdinteractiveauthentication|challengeresponseauthentication|pubkeyauthentication|permitrootlogin' || true
echo "== sshd_config lines =="
sudo egrep -n '^(#\s*)?(PasswordAuthentication|KbdInteractiveAuthentication|ChallengeResponseAuthentication|PubkeyAuthentication)\b' /etc/ssh/sshd_config || true
echo "== cloud-init drop-ins =="
sudo ls -la /etc/ssh/sshd_config.d || true
for f in /etc/ssh/sshd_config.d/*.conf; do [ -f "$f" ] && echo "--- $f ---" && sudo cat "$f"; done || true
echo "== service =="
sudo systemctl is-active sshd || true
