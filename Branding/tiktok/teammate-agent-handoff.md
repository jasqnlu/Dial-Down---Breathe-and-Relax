# ICE Teammate-Side Agent Handoff

You are the coding agent for the **teammate side** of ICE. Work with the human user to complete this side's code and setup tasks from the local collaboration notes (`colab.md`) and architecture plan (`plan.md`). Treat those notes as the source of scope and interfaces, but do not commit either notes file.

## Start safely

1. Locate the existing ICE repository (`github.com/MegaGimen/ICE-Agent`, expected default branch `master`) and inspect its current state and any `AGENTS.md` or repository instructions before editing.
2. Do all repository work in a **separate Git worktree on your own feature branch**. Do not edit the main checkout. If the repository is already present, create the worktree from its current `master` state, for example:

   ```bash
   git worktree add ../ICE-teammate -b teammate/<short-feature-name> master
   cd ../ICE-teammate
   ```

   Choose a branch name that reflects the work. If the repo is not present locally, report that and use the repository's documented checkout procedure; do not invent or expose credentials.
3. Inspect `ice/daemon/contracts.py` if present. The collaboration notes propose that it is the single source of truth for shared interfaces. Preserve the proposed contract unless there is a concrete conflict; announce any needed change in `colab.md` §6 and communicate it to the intake-pipeline developer before changing it.
4. Never commit `plan.md` or `colab.md`. Keep secrets, tokens, private keys, certificates, and real customer/host log data out of Git. Use environment variables or local ignored files for credentials.
5. Do not restart or kill shared model/services, alter host security settings, or use the host's remote access unless the human has provided current authorization and connection details. The notes describe ephemeral access; do not assume those details remain valid.

## Your ownership

Implement the teammate-side code in the agreed directories, avoiding files owned by the intake-pipeline developer:

- `ice/daemon/safety/`: safety gate, deterministic backstops, and human-facing explanations.
- `ice/daemon/backward/`: post-remediation verification and report generation.
- `ice/daemon/evolve/`: error book / experience memory, retest, and regression flow.
- `ice/daemon/graph/`: Kùzu integration, only after the core path works.
- `deploy/`: setup/configuration artifacts for certificates, NemoClaw, reverse proxy, and Slack apps, as appropriate.
- `targets/`: authorized exercise scenarios and supporting local threat-intelligence data, as appropriate.

The intake-pipeline developer owns perception, `judge()`, detection, investigation, orchestrator, and MCP server. Do not take over or rewrite those modules. Your code should integrate through the shared contracts and mocks.

## Build in this priority order

### 1. Safety gate

Implement `safety_gate(command, intent)` against the shared contract. Review the **actual proposed command and target**, not only a model-written summary. Return the agreed verdict shape with `AUTO`, `ASK`, or `DENY`, scores, and a request ID where required.

Include deterministic safeguards from the plan:

- Irreversible actions require human approval.
- Actions affecting configured critical assets require approval or denial according to policy.
- Support a kill switch and rate limiting.
- An approval request must be asynchronous. `ASK` returns promptly; the out-of-sandbox ICE Gate approval callback is the authority for approval. Never accept an approval assertion from the agent itself.
- Keep all execution behind the external safety gate.

### 2. Backward pass

Implement `run_backward(case)` using the agreed `Case` and `judge()` interfaces. This is **post-incident verification, not model training**.

- Compare T0 (pre-attack), T1 (detection), and T2 (post-remediation) snapshots.
- Use deterministic probes to check expected cleanup, remaining indicators, recurrence, service health, and collateral changes.
- Ask the shared `judge()` helper to explain residual changes and score response quality; the plan proposes an overall score of 70% deterministic probes and 30% Kev quality score.
- Represent outcomes clearly: fully cleared, partial, not cleared, or cleared with collateral impact; include confidence and evidence.
- If confidence is low or results show residue/recurrence, support extending observation and deeper checks.
- Produce a Slack-ready report/card payload, but keep the verification logic independent of Slack transport.
- Compare the full T0/T2 view, not just ICE's own recorded indicators, so misses can feed the learning loop.

Use fixtures/mocks for snapshots and `judge()` so this work can proceed without live services.

### 3. Evolution loop

Implement the smallest useful error-book flow: record misses and evidence, create candidate detection/experience notes, and support retesting against the original scenario plus a variant. Keep new rules out of the active set until the retest demonstrates detection without falsely flagging normal activity. Add regression support as time permits. Do not attempt online model-weight training as part of the backward pass.

### 4. Graph (lowest priority)

After safety, backward, and the error-book flow work, add a local Kùzu graph for correlation and display. Keep graph reads read-only to the agent and do not make the graph responsible for security decisions.

### 5. Human-only setup

Help the human complete setup that requires an interactive wizard, browser, account, or physical media: offline bundle/model checks, certificate/CA creation, NemoClaw onboarding, HTTPS MCP connection, Slack OpenClaw channel, separate ICE Gate app, and authorized exercise setup. Follow the order in `plan.md` §9, especially creating certificates before onboarding. Never put Slack tokens or private keys in the repository. If a step needs a human login, approval, or device action, prepare the exact instructions/configuration and ask the human to perform that step; do not claim it is complete until verified.

## Shared contracts to honor

The collaboration notes propose five frozen interfaces:

1. Structured `ChangeEntry` from perception, including provenance, `seen_before`, direction, and attacker-controlled strings in an explicitly untrusted field.
2. MCP tool signatures: `host_query`, `graph_query`, `host_exec`, and `explain_for_human`.
3. `judge()` input/output: question type and options in; probabilities/scores and confidence out. The intake side implements it; you consume it.
4. `Case` fields: `case_id`, `timeline`, `hosts`, `attck`, `confidence`, `ioc`, `reason`, `proposed_actions`, `blast_radius`, `status`.
5. Safety-gate verdict: decision (`AUTO`/`ASK`/`DENY`), scores (`legit`, `needs_human`, `reversible`, `scope_match`), and `request_id`.

Use the actual checked-in definitions if they exist. If the repository does not yet contain them, create or propose only the shared definitions needed for your modules and coordinate the change before modifying the contract. Keep contract definitions free of implementation logic.

## Work style and completion

- Work in small, reviewable changes on your feature branch. Use mocks and fixtures first; integrate with real services only when available and authorized.
- Keep the human informed about completed milestones, blockers, and any contract changes. Record interface changes/blockers in `colab.md` §6 when appropriate, but never add that file to Git.
- Do not claim tests or live integrations were run unless you actually ran them. Do not add or run tests unless the user asks; if the repository has required validation instructions, follow them and report the commands/results.
- Before finishing, summarize changed files, behavior implemented, validation performed, remaining setup requiring the human, and the branch/worktree location. Leave the worktree intact for review; do not merge or delete it unless explicitly requested.
