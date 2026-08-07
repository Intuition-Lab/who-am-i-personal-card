# 100-user beta runbook

<!-- beta-runbook-schema:1 -->

This runbook governs invitations to 100 external beta users. Internal
clean-machine qualification is a release gate and does not count toward the
100.

`RELEASE_STATUS=GO` permits publishing a qualified immutable release.
It does not permit inviting testers. The rollout owner may change
`PILOT_STATUS` to `GO` only after every post-publication checklist item has
direct evidence and the machine-readable decision below is complete. The
manual **Pilot invitation gate** workflow must then pass against the live
release. That result authorizes exactly five pilot invitations.

<!-- pilot-decision:v1 status=HOLD wave=5 version=0.1.0-beta.4 tag=v0.1.0-beta.4 commit=TBD owner=TBD approved-at=TBD -->

## Roles and records

Assign names before the pilot:

| Role | Responsibility | Name / route |
| --- | --- | --- |
| Release owner | owns tag and release evidence | TBD |
| Rollout owner | sends invitations and records go/hold/rollback | TBD |
| Incident owner | triages P0/P1 and coordinates communication | TBD |
| Runtime owner | diagnoses install, permission and Runtime health failures | TBD |
| Product owner | accepts workflow behavior and known limitations | TBD |
| Privacy contact | decides handling of any personal-data incident | TBD |
| Support route | tester-visible issue/contact location | TBD |

Maintain a rollout ledger outside personal model data:

| Wave | Release/tag | Invited | Installed | Golden path passed | Blocked | P0/P1/P2/P3 | Decision/time |
| --- | --- | ---: | ---: | ---: | ---: | --- | --- |
| Pilot | TBD | 5 | 0 | 0 | 0 | 0/0/0/0 | TBD |
| Expansion | TBD | 20 | 0 | 0 | 0 | 0/0/0/0 | TBD |
| General | TBD | 75 | 0 | 0 | 0 | 0/0/0/0 | TBD |

Do not put product-derived personal context in the ledger.

## Preflight: internal clean-Mac proof

Before inviting anyone, test the exact release commit and published
instructions on:

- two clean Apple Silicon Macs;
- one clean Intel Mac;
- the minimum supported macOS 13 on at least one test machine;
- a checkout path containing spaces.

On each machine preserve:

- machine architecture and macOS version;
- product tag/commit and Runtime commit;
- command start/end time and exit status;
- sanitized result of required checks;
- install, onboarding, permission denial/retry and golden-path result;
- upgrade and rollback result.

Never preserve captures, model text, `HUMAN.md`, exports, tokens or credentials
as release evidence.

## Rollout waves

Release progressively so a permission, dependency, product or migration
failure cannot affect all testers at once.

### Wave 1 — pilot: 5 users

Select testers across the supported architectures and relevant product
conditions identified during intake. Give them the exact GitHub release,
checksum, install command, known issues, privacy boundary, uninstall guidance
and support route.

Exit only when:

- all five users have reported install outcome or the rollout owner explicitly
  records why a non-response is acceptable;
- at least one successful golden-path run exists on Apple Silicon and Intel;
- all install and workflow failures are classified;
- there is no unresolved P0/P1;
- the product-defined observation window has elapsed;
- the rollout owner records a go decision.

### Wave 2 — expansion: 20 users

Use the same immutable release unless a new candidate repeats internal
qualification and the pilot. Do not silently replace assets under a tag.

Exit only when:

- install and golden-path rates meet the thresholds approved in product
  intake;
- there is no unresolved P0/P1 and no worsening common P2;
- rollback is still available;
- the observation window has elapsed;
- the rollout owner records a go decision.

Changing the later 20- and 75-user waves from hold to go is a separate recorded
decision. A green five-user pilot gate must never be reused as authorization to
send the remaining invitations.

### Wave 3 — general: 75 users

Invite the remaining 75 users only after Wave 2 exits. Continue recording
outcomes and incidents; “all invitations sent” is not the same as “100 working
installs.”

## Invitation payload

Every invite must identify:

- product purpose and beta limitations;
- supported macOS versions and architectures;
- exact GitHub release and checksum verification path;
- exact install and update instructions;
- required system permissions and why they are needed;
- what data stays local and any approved exception;
- known issues, uninstall/rollback guidance and support route;
- what diagnostic information support may request;
- that testers must not post personal context in a public GitHub issue.

## Required support metadata

Collect only what is needed for support:

- product version/commit and Runtime commit;
- Mac architecture and macOS version;
- whether this was fresh install, reinstall, upgrade or rollback;
- failing phase and exact safe error message;
- the privacy-safe
  `bash "${PERSOME_INSTALL_HOME:-$HOME/.persome}/product-management/scripts/diagnose.sh" --json`
  output;
- whether Accessibility and Screen Recording were granted;
- product workflow ID and observed result;
- explicit consent before collecting any log that might contain personal
  context.

Never ask testers to upload `~/.persome`, raw captures, `HUMAN.md`, database
files, exports, API keys or bearer tokens. If a user independently supplies
personal data, restrict access, stop copying it into general issue trackers,
and escalate to the privacy contact.

## Support and incident classification

| Severity | Meaning | Immediate response | Rollout |
| --- | --- | --- | --- |
| P0 | confirmed/suspected data loss, secret exposure, unintended external access, destructive external action, or broken privacy promise | acknowledge, preserve safe evidence, notify incident/privacy owners, publish safe mitigation | stop and roll back or disable distribution |
| P1 | install/onboarding or promised golden path blocked for a supported configuration; unsafe rollback; widespread crash | assign owner, reproduce on supported Mac, communicate workaround only if verified | hold next wave; roll back if impact is common |
| P2 | one feature broken with a safe workaround; isolated supported-case defect | record workflow/environment, schedule fix and document workaround | owner decides hold/go using trend |
| P3 | cosmetic, copy or documentation defect | backlog with release reference | continue |

Any team member may call a hold. Only the rollout owner may record go after the
exit gate. Do not downgrade severity to meet a deadline.

## Stop conditions

Immediately stop new invitations when any of these occurs:

- a P0 or unresolved P1;
- release asset or checksum mismatch;
- the installer fetches a Runtime commit different from `runtime.lock`;
- product or Runtime data is deleted or cannot be used after upgrade/rollback;
- a token, credential or personal context appears in default diagnostics,
  analytics, a public issue or a release artifact;
- the Runtime server is reachable beyond loopback;
- a promised workflow performs an unapproved external action;
- the observed failure rate exceeds the product-approved wave threshold.

## Rollback procedure

1. Record a hold and stop sending invitations.
2. Disable or mark the affected GitHub release as unavailable/deprecated
   without changing an immutable tag or asset in place.
3. Notify invited users with affected product version, symptoms, safe action,
   data-preservation statement and next update time.
4. Preserve `~/.persome`; do not uninstall or delete Runtime data as a product
   rollback step.
5. Restore the previous product release together with its previous
   `runtime.lock`.
6. If onboarding is incomplete, run
   `"${PERSOME_INSTALL_HOME:-$HOME/.persome}/venv/bin/persome" onboard`, then
   run the installed management bundle's `scripts/verify.sh --full` and the
   previous release's golden-path test.
7. Confirm product-owned state compatibility using the product-specific
   rollback test.
8. Record affected versions, Runtime commits, migration state, counts and
   sanitized evidence.

If no previous qualified product release exists, the safe rollback is to stop
the product while preserving Runtime data. Do not claim that reinstalling an
unqualified build is a rollback.

## Recovery and resume

A stopped rollout resumes with a new immutable release only after:

- root cause and affected scope are documented;
- the fix has a regression test;
- internal clean-Mac, upgrade and rollback qualification passes again;
- P0/P1 communication is updated;
- the corrected release repeats the pilot;
- release and rollout owners record approval.
