# Article 3 capture plan (v2, two acts)

**Written:** 29 Oct 2026 (M5). **Runs in:** M6, in one session, after ArgoCD and the app-of-apps root are live.
**Article:** GitOps vs. Manual Drift: Measuring the Failure Window ArgoCD Closes. Drafted in M7, published in M9.

## What I am capturing and why

Most GitOps demos show only the save. Someone changes something by hand, and the controller puts it back. That hides the point. The risk is the window, the time when the live cluster no longer matches Git and nobody is correcting it. So I capture two acts in the same session, with the same mutation.

- **Act 1, self-heal off.** I scale a Deployment by hand. ArgoCD notices and flags it OutOfSync, but does not correct it. The drift stays until a person acts.
- **Act 2, self-heal on.** The same mutation. ArgoCD detects it and reverts it, and I record each step with timestamps.

Act 1 is the argument. Act 2 without Act 1 is a product demo.

## What the numbers mean

The Act 1 window has no natural end. It lasts until a human acts. I stop it after about 10 minutes because that is when I stop watching, not because the system closes it. So I never present the 10 minutes as a measured property. The numbers I do present are these.

| Measure | Act | What it shows |
|---|---|---|
| Detection time | 1 and 2 | How fast ArgoCD notices the drift |
| Reconciliation cycles with no fix | 1 | ArgoCD checked the app this many times and corrected nothing |
| Revert time | 2 | How fast self-heal puts the live state back to Git |
| Back to healthy | 2 | How fast the pods settle after the revert |

## Setup before the session

| Item | Detail |
|---|---|
| Cluster | t4g.medium server from the M5 topology decision, built with `scripts/dev-apply.sh` |
| ArgoCD | Installed by Terraform through the Helm provider, chart pinned. UI reached only through SSM port forwarding |
| Root app | App-of-apps with automated sync. Prune stays off for this capture |
| Drift target | Namespace `drift-demo`, Deployment `web`, image `nginx` pinned to a digest, `replicas: 2`, requests and limits set, defined in `apps/drift-demo/` in Git |
| Child Application | `drift-demo`, automated sync on, `selfHeal: false` for Act 1 |

The drift target is a plain nginx Deployment because the API does not exist until M7. The article explains what the same window means for a stateful service.

## Record the settings first

Detection and revert times depend on ArgoCD's version and settings, so I save them before either act.

~~~bash
K="sudo /usr/local/bin/k3s kubectl"
{
  date -u +%FT%TZ
  $K version
  $K -n argocd get deploy argocd-application-controller -o jsonpath='{.spec.template.spec.containers[0].image}'; echo
  $K -n argocd get cm argocd-cm -o yaml
  $K -n argocd get cm argocd-cmd-params-cm -o yaml
  $K -n argocd get application drift-demo -o yaml
} > versions-and-settings.txt
~~~

## The watcher

A loop on the node logs the Deployment and the ArgoCD Application status about once a second. Its output is the timeline for both acts.

~~~bash
#!/usr/bin/env bash
# watch-drift.sh writes one timestamped line per poll.
# Usage: ./watch-drift.sh act1-timeline.log
set -euo pipefail
OUT=$1
K="sudo /usr/local/bin/k3s kubectl"
while true; do
  ts=$(date -u +%FT%T.%3NZ)
  spec=$($K -n drift-demo get deploy web -o jsonpath='{.spec.replicas}')
  ready=$($K -n drift-demo get deploy web -o jsonpath='{.status.readyReplicas}')
  sync=$($K -n argocd get application drift-demo -o jsonpath='{.status.sync.status}')
  health=$($K -n argocd get application drift-demo -o jsonpath='{.status.health.status}')
  echo "$ts spec=$spec ready=${ready:-0} sync=$sync health=$health" | tee -a "$OUT"
  sleep 1
done
~~~

Each poll makes four API calls, so the real resolution is about 1 to 2 seconds. That is fine for detection measured in seconds and a revert measured in seconds.

## Act 1, self-heal off

1. Confirm the start state is `spec=2 ready=2 sync=Synced health=Healthy`.
2. Start the watcher in a second SSM session with `./watch-drift.sh act1-timeline.log`.
3. Wait 30 seconds so the log shows a clean baseline.
4. Mutate, and log the exact time.
   ~~~bash
   echo "MUTATION $(date -u +%FT%T.%3NZ)" | tee -a act1-timeline.log
   $K -n drift-demo scale deploy web --replicas=5
   ~~~
5. Leave it alone for at least three reconciliation cycles and about 10 minutes in total. The default cycle is 3 minutes, and I confirm the real value in `versions-and-settings.txt`.
6. Save the evidence while the drift is still live.
   ~~~bash
   $K -n argocd get application drift-demo -o yaml > act1-application-status.yaml
   $K -n drift-demo get deploy web -o yaml > act1-live-deployment.yaml
   ~~~
   Then take a screenshot of the ArgoCD UI showing OutOfSync with the diff, saved as `act1-ui-outofsync.png`.
7. Stop the watcher. End the drift with a manual sync from the UI, and log the time as `MANUAL SYNC`. Only a person closes the Act 1 window, and the log should show that.

## Act 2, self-heal on

1. Turn on self-heal with a Git commit that sets `selfHeal: true` on the drift-demo Application. Never with `kubectl patch`, because changing ArgoCD by hand during a demo about manual drift would undercut the point. Wait until ArgoCD shows the change applied.
2. Confirm the start state is `spec=2 ready=2 sync=Synced health=Healthy` again.
3. Start the watcher with `./watch-drift.sh act2-timeline.log`, and wait 30 seconds.
4. Make the same mutation, with the time logged as `MUTATION` in `act2-timeline.log`.
5. Watch until the log shows `spec=2 ready=2 sync=Synced health=Healthy` again, then wait another 60 seconds.
6. Save the evidence.
   ~~~bash
   $K -n drift-demo get events --sort-by=.lastTimestamp > act2-events.txt
   $K -n argocd logs deploy/argocd-application-controller --since=15m | grep drift-demo > act2-controller.log
   $K -n argocd get application drift-demo -o yaml > act2-application-status.yaml
   ~~~
   Then take a screenshot of the Application's sync history in the UI, saved as `act2-ui-history.png`.

## Where the files go

All capture files go in `docs/evidence/drift-capture/` in this repo. The README and ADR-006 point at them as evidence, not only the article. The article itself is written in the devops-blog repo, which is the only place the website builds from, so I copy the screenshots it uses into that repo when I write it.

| File | Act |
|---|---|
| `versions-and-settings.txt` | Both |
| `act1-timeline.log`, `act1-application-status.yaml`, `act1-live-deployment.yaml`, `act1-ui-outofsync.png` | 1 |
| `act2-timeline.log`, `act2-events.txt`, `act2-controller.log`, `act2-application-status.yaml`, `act2-ui-history.png` | 2 |
| `capture-notes.md`, with the measured numbers, anything unexpected, and the date | Both |

## Check before destroying

Nothing gets destroyed until every item here passes.

- Every file exists and is not empty.
- Both timelines contain a MUTATION line. Act 1 ends with MANUAL SYNC. Act 2 shows the return to `spec=2`.
- The screenshots show what I need and contain no secrets. The ArgoCD admin password must never appear.
- The numbers in `capture-notes.md` match the timelines.
- The files are copied off the node before `scripts/dev-destroy.sh` runs.

## If something goes wrong

- **A Spot interruption during the session.** Rebuild and rerun both acts. Both acts must come from the same cluster and the same settings.
- **Act 2 reverts too fast for the watcher to see OutOfSync.** That is a result, not a failure. I record it, and the controller log and events still show the order of steps.
- **A file is missing at the check.** Rerun that act before destroying. Re-staging this later under M8's heavier workload is exactly what this plan avoids.
