# SSM Reboot Fallback Test

**Date:** 2026-11-14
**Script:** `scripts/dev-apply.sh` (overridable timeouts from a53baba)
**Instance:** i-04a4765c59835b1c6, t4g.small Spot, K3s v1.35.9+k3s1

## What I tested

In M4 an instance profile created in the same apply was not usable at boot. The
SSM agent started before it had credentials, never registered, and did not
recover. `dev-apply.sh` handles this by rebooting the node once if SSM is not
Online in time. The real race cannot be triggered on demand, so the reboot path
had never run. I forced it by setting the first wait shorter than one poll.

```bash
script -q -c "SSM_TIMEOUT=10 ./scripts/dev-apply.sh" ~/m6-reboot-fallback.log
```

`SSM_TIMEOUT=10` is below the 15s poll interval, so the first wait always times
out. `REBOOT_SSM_TIMEOUT` stayed at its default of 300s, so the recovery had its
normal time.

## Script log

```text
2026-11-14T07:23:16Z K3s instance is i-04a4765c59835b1c6
2026-11-14T07:23:16Z Waiting for SSM Online, up to 10s
2026-11-14T07:23:18Z SSM status is None after 0s
2026-11-14T07:23:34Z Not Online after 10s, rebooting once
2026-11-14T07:23:51Z Waiting for SSM Online after the reboot, up to 300s
2026-11-14T07:23:54Z SSM Online
2026-11-14T07:23:54Z Waiting for K3s Ready, up to 600s
2026-11-14T07:24:01Z K3s check returned WAITING after 0s
2026-11-14T07:24:23Z K3s node i-04a4765c59835b1c6 is Ready
2026-11-14T07:24:23Z Full rebuild took 3m 11s, including the time to type yes
```

## Proof the node rebooted

SSM was Online 20s after the reboot command. That is fast enough that the status
could have been left over from before the reboot, so I checked the node's own
boot record.

```text
$ sudo journalctl --list-boots --no-pager
IDX BOOT ID                          FIRST ENTRY                 LAST ENTRY
 -1 116b770a01934faaa98c0e736bda1abd Sat 2026-11-14 07:22:19 UTC Sat 2026-11-14 07:23:44 UTC
  0 680fc68122d24d4eaeb7c676e8b08284 Sat 2026-11-14 07:23:47 UTC Sat 2026-11-14 07:27:00 UTC
$ uptime -s
2026-11-14 07:23:47
```

| Time (UTC) | Source | Event |
|---|---|---|
| 07:23:34 | script | `reboot-instances` sent |
| 07:23:44 | journal | First boot ends |
| 07:23:47 | journal | Second boot starts |
| 07:23:54 | script | SSM Online, 7s into the second boot |

Two boots, with the second starting after the reboot command, so the Online at
07:23:54 was a real recovery.

## Result

The fallback runs end to end. The timeout fires, the node reboots, SSM comes
back Online and K3s reaches Ready. The full rebuild took 3m 11s against the M5
baseline of 2m 57s, with the reboot included.
