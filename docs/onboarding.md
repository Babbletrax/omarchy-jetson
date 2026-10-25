# First-boot setup

`omarchy-jetson-onboarding` asks the new owner for what a fresh image cannot
know. It runs once, in text mode on the TV console (tty1), before greetd
shows the login screen.

## When it runs

`omarchy-jetson-onboarding.service` is a oneshot unit ordered
`Before=greetd.service display-manager.service` and `Conflicts=getty@tty1.service`.
It runs only while `/var/lib/omarchy-jetson/onboarding/done` is absent.

On its first start the script checks for a usable regular account. That
means a UID between `UID_MIN` and `UID_MAX`, a real login shell, and a
password that is not locked. A key-only account from
`scripts/write-usb-test-drive.sh` counts as usable. Arch Linux ARM's locked
`alarm` account does not. If a usable account exists, the script writes the
marker and exits, so an existing system that installs the package never sees
setup. greetd is only ordered after the unit, not bound to it, so the login
screen starts either way.

## Steps

Each step writes a marker under `/var/lib/omarchy-jetson/onboarding/steps`
when it finishes. If setup is interrupted, for example by a power loss, the
next boot continues at the first unfinished step. Once setup has started, it
resumes even though the new account already exists.

| Step | What happens |
|---|---|
| keyboard | Upstream's layout picker. The keymap is written with `systemd-firstboot` and loaded on the console. |
| account | Asks for a username and a password, entered twice. Name and e-mail for git are optional, using upstream's prompt. Passwordless sudo is offered and defaults to off. The groups are `wheel`, `video`, `render` and `audio`, which cover the Tegra display and nvhost GPU nodes and the DRM render nodes. |
| hostname | Kept if it is already set to anything other than a placeholder (`omarchy-jetson`, `alarm`, `localhost`). Otherwise `omarchy-jetson` is offered as the default, and the owner can type another name. |
| network | Skipped if the machine is online or a cable is connected. Otherwise a Wi-Fi list (NetworkManager) is shown, with an entry for a hidden network. The owner can skip it and stay offline. Setup creates a profile without the secret, then brings it up with `nmcli connection up ... passwd-file`, so the password never appears on a command line. The passwd-file is mode 0600, in a private directory that is removed straight after. |
| timezone | Online, the owner can opt into detection with upstream's `tzupdate`, which sends this network's address to a public geolocation service. Then pick from the list, or keep the current zone. Offline, only the list is shown. |
| keyring | Builds a new pacman keyring for this machine and populates it from the keyrings the installed packages ship. A keyring that is already present at first boot came with the image, and its local key would be the same on every copy of that image. |
| provision | Hands the account to upstream's `omarchy-provision-user --force --first-install`, the same way upstream's own `omarchy-provision-owner` does. If this step fails, setup still finishes and tells the owner to run `omarchy-provision-user --force` after logging in. |

When setup finishes, it points tuigreet's remembered user at the new account
and writes the marker. greetd then starts.

Setup does not choose an AI assistant. One can be added later from the
Omarchy menu (**Install → AI**).

Root stays locked, unlike upstream's own first boot, which gives root the
owner's password.

If an attempt fails, setup shows the log path and offers to try again,
reboot or power off. It never opens a shell, because console access must
not grant root. The setup-done marker stays absent, so setup runs again on
the next boot.

The locked `alarm` account stays as it is. It may appear in tuigreet's user
menu. Hiding it with tuigreet's `--user-menu-min-uid` is not safe: `alarm`
has UID 1000, and so do the owner's accounts on USB test-drive images and on
systems set up before this package.

## Hostname rule

`omarchy-jetson` is only a default. First-boot setup is the only packaged
code that writes `/etc/hostname`. It writes it at most once, and only when no
real hostname is set. Updates never write it. `tests/hostname-default.sh` and
`tests/onboarding.sh` enforce this.

## Commands

```sh
omarchy-jetson-onboard --status   # the steps done so far
omarchy-jetson-onboard --check    # exit 0 if setup would run
sudo omarchy-jetson-onboard       # run or resume setup by hand
```

`--root DIR` runs any of these against another root tree.
`tests/onboarding.sh` uses it with fake commands on `PATH`.
