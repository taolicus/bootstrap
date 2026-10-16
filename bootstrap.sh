#!/bin/sh
set -eu

PROJECT_DIR=${1:-.}
mkdir -p "$PROJECT_DIR"
cd "$PROJECT_DIR"

mkdir -p workflow issues tasks/open tasks/closed features

# Create a file only if it does not already exist.
create_if_missing() {
    target=$1
    if [ ! -e "$target" ]; then
        cat > "$target"
    else
        cat > /dev/null
    fi
}

# Add a workflow rule reference without duplicating existing references.
add_rule_reference() {
    rule_file=$1

    if ! grep -Fq "$rule_file" workflow/README.md; then
        if ! grep -Fq "## Additional workflow rules" workflow/README.md; then
            printf '\n## Additional workflow rules\n' >> workflow/README.md
        fi
        printf '%s\n' "- \`$rule_file\`" >> workflow/README.md
    fi
}

create_if_missing AGENTS.md <<'EOF'
# Agent Instructions

Read `workflow/README.md` before working on this project.

Follow the relevant workflow rules. Inspect only the context needed for the
task, preserve existing work, avoid unrelated changes, and keep the repository
in a coherent state.

Use:
- `issues/` for unresolved observations, problems, and questions.
- `tasks/open/` for actionable work.
- `tasks/closed/` for completed tasks retained for history.
- `features/` for durable knowledge about the implemented system.

Put reusable workflow lessons in `workflow/`. Do not use commit messages or
conversation history as substitutes for durable documentation.
EOF

create_if_missing workflow/README.md <<'EOF'
# Workflow

Read the rules relevant to the task. Apply them proportionately; do not turn
routine changes into unnecessary planning, investigation, or administration.

## Work item lifecycle

- `issues/`: unresolved observations, problems, questions, and investigations.
- `tasks/open/`: actionable work sufficiently understood to implement.
- `tasks/closed/`: completed tasks retained for history.
- `features/`: durable knowledge about implemented system behaviour and design.

Move an issue to `tasks/open/` when it becomes actionable.
Move a completed task to `tasks/closed/`, preserving its filename and context.
Update relevant feature documentation when work establishes useful durable
knowledge. Do not duplicate information already documented.

Create follow-up issues for material, actionable work outside the current scope.
Do not create issues for trivial observations, speculative improvements, or work
already tracked elsewhere.

## Workflow rules

- `workflow/work-item-metadata.md`
- `workflow/device-aware-development.md`
- `workflow/commit-policy.md`
- `workflow/incremental-task-scoping.md`
- `workflow/execution-and-stopping.md`
EOF

create_if_missing workflow/work-item-metadata.md <<'EOF'
# Work Item Metadata

Metadata is optional. Use it only when it adds practical value.

## Area

- `area` is an optional, single slug for grouping or filtering work.
- Omit it when it provides no useful distinction.

## Dependencies

- `dependencies` is an optional list of work item filenames.
- Each reference must resolve to an item in `issues/`, `tasks/open/`,
  or `tasks/closed/`.
- Filenames must be unique across these directories.
- Preserve filenames when moving items between lifecycle directories.
- Update references if a referenced file is renamed or removed.
- Dependencies represent genuine execution constraints, not merely related work.
- Check declared dependencies before implementation.
- For completed dependencies, inspect their recorded outcome and current code
  only as needed to determine whether the requirement is satisfied.
- If an unresolved dependency blocks the task, record the blocker and determine
  the appropriate next step. Do not silently work around it.
- Do not investigate unrelated dependency history.
- Omit the field when no dependencies apply.

Do not add a priority field. Decide what to work on during planning based on
the task, constraints, dependencies, and available time.
EOF

create_if_missing workflow/device-aware-development.md <<'EOF'
# Device-Aware Development

Choose tasks based on the current device's capabilities, actual availability,
task risk, and the ability to verify the result.

## Phone: Google Pixel 7 Pro

Prefer bounded tasks that can be performed and reviewed effectively on a phone:
- Review code, diffs, documentation, and investigation results.
- Refine plans, acceptance criteria, and issue descriptions.
- Make small, low-risk edits when suitable tools are available.

Do not assume every coding task must wait for a laptop.

## Laptop: M1 MacBook Pro

Defer work when it materially depends on capabilities unavailable on the phone,
for example:
- Local builds, substantial test runs, or debugging.
- Simulator or desktop-tool workflows unavailable on the phone.
- Changes that cannot be reliably reviewed or verified on mobile.

Do not defer work merely because a laptop is generally preferable for coding.

## Decision and handoff

Assess device suitability once at the start using required tools, environment,
risk, and verification needs. Reassess only when requirements change or a
concrete limitation is encountered.

Record device constraints in a task only when they materially affect execution
or verification. Do not require device metadata on every task.

For cross-device handoffs, record:
- Findings and decisions.
- Changes made and unresolved questions.
- The next concrete action.
- Which step requires the other device.

Preserve uncommitted work. Never assume changes are available on another device
unless repository synchronisation has been verified.
EOF

create_if_missing workflow/commit-policy.md <<'EOF'
# Commit Policy

Commits are concise historical records of meaningful changes, not implementation
reports. Use a short message describing the outcome or intent of the change.

Put durable system context in relevant files under `features/`.
Put reusable workflow lessons in relevant files under `workflow/`.
Keep task-specific findings with the work item unless they establish knowledge
that will be useful beyond that task. Do not duplicate documentation in commits.

## Completing tasks

- Commit completed task changes after relevant verification.
- Push completed task commits when a suitable configured remote is available
  and the current branch can be pushed safely.
- Inspect the working tree, current branch, remotes, and upstream as needed.
- Inspect the diff before staging and stage only the intended changes.
- Verify the staged diff before committing.
- Do not commit unrelated changes or overwrite another contributor's work.
- If existing changes have unclear ownership or purpose, do not stage, amend,
  discard, or include them. Continue only if your changes can be safely isolated;
  otherwise, report the blocker.
- Run relevant tests and checks when the environment permits.
- Investigate and fix failures relevant to the task. Distinguish task-related
  failures from pre-existing failures and environmental limitations.
- Do not pursue unrelated fixes just to make all checks pass.
- If verification is incomplete, state that limitation accurately.
- If the push fails, report the reason. Do not force-push, guess the remote,
  or change remote settings. Retry only when the cause is understood and the
  corrective action is clearly safe and within scope.
- Never claim a commit or push succeeded without verifying the result.

Task lifecycle and Git history are separate. Move a task to `tasks/closed/`
only when its acceptance criteria are met. Record outstanding limitations or
follow-up work explicitly.
EOF

create_if_missing workflow/incremental-task-scoping.md <<'EOF'
# Incremental Task Scoping

Break substantial work into the smallest practical set of coherent tasks that
materially improves reviewability, reduces risk, resolves uncertainty, or
enables independent progress.

Prefer the simplest workable breakdown. Avoid both oversized tasks and excessive
fragmentation.

## When to split

Split work when:
- A meaningful outcome can be implemented and verified independently.
- Distinct outcomes have different acceptance criteria.
- A step resolves significant uncertainty before further implementation.
- Separation materially reduces regression risk or simplifies diagnosis.
- Dependencies require a clear execution order.

Do not split merely because work touches multiple files, layers, or technical
steps. Keep tightly coupled changes together when splitting adds artificial
boundaries, scaffolding, or extra coordination without meaningful benefit.

## Size and acceptance criteria

A small, routine change should usually remain one task. Substantial work may need
a short plan and several tasks. Use a detailed breakdown only when complexity,
risk, or dependencies justify it.

Each task should define:
- One coherent outcome.
- Scope and important constraints.
- Observable acceptance criteria.
- Relevant verification.
- Genuine dependencies, if any.

Make each task small enough for a focused review but large enough to deliver
meaningful value. Do not create tasks for trivial edits, routine substeps, or
every file touched.

## Preserve repository coherence

A completed task should leave the repository in a coherent, reviewable state.
Where applicable, it should build and pass relevant tests.

Order dependent work so intermediate states remain valid. Use compatibility
layers, feature flags, adapters, or incremental migrations only when needed to
keep intermediate states safe and the added complexity is justified.

If changes cannot be separated without breaking the repository or adding
excessive scaffolding, keep the coupled work together. Do not label an unsafe
intermediate state as independently complete.

## Stop decomposing

Once each task has a coherent outcome, clear acceptance criteria, and a safe
implementation path, stop decomposing and begin work.

Reassess the breakdown only when new information materially changes the scope,
risk, dependencies, or feasibility. If implementation reveals independent work
outside scope, record it separately instead of silently expanding the task.
EOF

create_if_missing workflow/execution-and-stopping.md <<'EOF'
# Execution and Stopping Rules

## Start with relevant context

- Start from the requested outcome.
- Read project instructions, the relevant work item, directly relevant feature
  documentation, and declared dependencies.
- Investigate further only to resolve a concrete implementation or verification
  question.
- Use the best available evidence. Do not repeatedly revisit settled decisions
  without new evidence.
- Do not inspect unrelated files or history without a specific reason.

## Plan proportionately

- Use a lightweight plan for routine, low-risk changes; do not create a separate
  planning phase unless it adds value.
- For substantial changes, establish scope, acceptance criteria, and a practical
  implementation sequence.
- Split tasks only according to `incremental-task-scoping.md`.
- If a material uncertainty remains after reasonable, targeted investigation,
  record what is known and the next action. Ask for clarification when the
  uncertainty prevents a safe or correct decision.

## Control scope

- Implement the requested outcome without unrelated cleanup or speculative
  improvements.
- Record material, actionable discoveries outside the current scope as follow-up
  issues or tasks.
- Update documentation only when it adds useful durable system knowledge or a
  reusable workflow lesson.
- Do not repeat checks, recreate artifacts, or reconsider settled decisions
  unless new evidence justifies it.

## Verify and stop

- Verify against the task's acceptance criteria using the most relevant available
  checks. Do not try to prove the absence of every possible defect.
- If a relevant check fails, make targeted attempts to diagnose and fix it
  within scope.
- If blocked, record the evidence, limitation, and next concrete action rather
  than repeating unsuccessful attempts or claiming completion.
- Stop when the acceptance criteria are met, relevant verification is complete
  to the extent possible, necessary documentation is updated, and the required
  commit/push steps have been attempted.
- Report material limitations, failed checks, and follow-up work explicitly.
EOF

add_rule_reference workflow/work-item-metadata.md
add_rule_reference workflow/device-aware-development.md
add_rule_reference workflow/commit-policy.md
add_rule_reference workflow/incremental-task-scoping.md
add_rule_reference workflow/execution-and-stopping.md

printf 'Bootstrap complete: %s\n' "$PROJECT_DIR"
