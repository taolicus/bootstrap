#!/bin/sh
# Bootstrap a file-based workflow for agent-driven projects.
set -eu

VERSION=0.2.0

usage() {
    cat <<'EOF'
Usage: bootstrap.sh [options] [project-dir]

Writes a work-item lifecycle and its rules into project-dir (default: .).
Existing files are left alone unless --upgrade or --force is given.

Options:
  --upgrade        Update files installed by an earlier run. Files you have
                   modified are kept; the new version is written beside them
                   as <file>.new.
  --force          Overwrite everything, including locally modified files.
  --phone NAME     Record the phone used for this project.
  --laptop NAME    Record the laptop used for this project.
  --init           Run 'git init' if project-dir is not a repository.
  -h, --help       Show this message.

Files are tracked in workflow/.bootstrap-manifest, which records the hash of
each file as installed. That is what makes --upgrade safe.
EOF
}

MODE=create
PROJECT_DIR=.
PHONE=
LAPTOP=
INIT_GIT=0
FORCE=0

while [ $# -gt 0 ]; do
    case $1 in
    --upgrade) MODE=upgrade ;;
    --force) FORCE=1 ;;
    --init) INIT_GIT=1 ;;
    --phone)
        shift
        if [ $# -eq 0 ]; then
            printf 'bootstrap: --phone needs a value\n' >&2
            exit 2
        fi
        PHONE=$1
        ;;
    --laptop)
        shift
        if [ $# -eq 0 ]; then
            printf 'bootstrap: --laptop needs a value\n' >&2
            exit 2
        fi
        LAPTOP=$1
        ;;
    -h | --help)
        usage
        exit 0
        ;;
    -*)
        printf 'bootstrap: unknown option: %s\n' "$1" >&2
        usage >&2
        exit 2
        ;;
    *)
        PROJECT_DIR=$1
        ;;
    esac
    shift
done

mkdir -p "$PROJECT_DIR"
PROJECT_DIR=$(cd "$PROJECT_DIR" && pwd)
cd "$PROJECT_DIR"

MANIFEST=workflow/.bootstrap-manifest

# --- helpers ----------------------------------------------------------------

hash_file() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | cut -d' ' -f1
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | cut -d' ' -f1
    elif command -v openssl >/dev/null 2>&1; then
        openssl dgst -sha256 "$1" | sed 's/.*= *//'
    else
        printf 'bootstrap: need sha256sum, shasum, or openssl to track files\n' >&2
        exit 2
    fi
}

say() {
    printf '%s\n' "$1"
}

manifest_hash() {
    if [ ! -f "$MANIFEST" ]; then
        return 0
    fi
    awk -v p="$1" '$NF == p { h = $1 } END { if (h != "") print h }' "$MANIFEST"
}

record() {
    rel=$1
    if [ -f "$NEW_MANIFEST" ]; then
        awk -v p="$rel" '$NF != p' "$NEW_MANIFEST" >"$NEW_MANIFEST.tmp"
    else
        : >"$NEW_MANIFEST.tmp"
    fi
    printf '%s  %s\n' "$(hash_file "$rel")" "$rel" >>"$NEW_MANIFEST.tmp"
    mv "$NEW_MANIFEST.tmp" "$NEW_MANIFEST"
}

install_rel() {
    rel=$1
    mkdir -p "$(dirname "$rel")"
    cp "$STAGE/$rel" "$rel"
}

# --- directories ------------------------------------------------------------

for d in issues tasks/open tasks/closed features; do
    mkdir -p "$d"
    if [ ! -e "$d/.gitkeep" ]; then
        : >"$d/.gitkeep"
    fi
done
mkdir -p workflow

# --- stage ------------------------------------------------------------------

STAGE=${TMPDIR:-/tmp}/bootstrap-stage.$$
trap 'rm -rf "$STAGE"' 0 1 2 15
rm -rf "$STAGE"
mkdir -p "$STAGE/workflow"

cat >"$STAGE/AGENTS.md" <<'EOF'
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

Start new work items from `workflow/issue-template.md` and
`workflow/task-template.md`. Delete the sections that do not apply rather than
filling them in.

Run `sh workflow/lint.sh` before declaring a task complete. It checks the
invariants the rules assume but cannot enforce: dependencies that resolve,
closed tasks that record an outcome, and unique work-item filenames.

Put reusable workflow lessons in `workflow/`. Do not use commit messages or
conversation history as substitutes for durable documentation.
EOF

cat >"$STAGE/workflow/README.md" <<'EOF'
# Workflow

Read the rules relevant to the task. Apply them proportionately; do not turn
routine changes into unnecessary planning, investigation, or administration.

## Work item lifecycle

- `issues/`: unresolved observations, problems, questions, and investigations.
- `tasks/open/`: actionable work sufficiently understood to implement.
- `tasks/closed/`: completed tasks retained for history.
- `features/`: durable knowledge about implemented system behaviour and design.

Start a new item from `task-template.md` or `issue-template.md`.

Move an issue to `tasks/open/` when it becomes actionable.
Move a completed task to `tasks/closed/`, preserving its filename and context.
Record the outcome under `## Outcome`; `lint.sh` requires it for a closed task.
Update relevant feature documentation when work establishes useful durable
knowledge. Do not duplicate information already documented.

Create follow-up issues for material, actionable work outside the current scope.
Do not create issues for trivial observations, speculative improvements, or work
already tracked elsewhere.

The split matters more than it looks: an agent that cannot tell an unresolved
observation from an actionable task will start implementing the observation.

## Workflow rules

- `execution-and-stopping.md`
- `incremental-task-scoping.md`
- `work-item-metadata.md`
- `device-aware-development.md`
- `commit-policy.md`
- `verify-what-the-user-sees.md`

## Templates

- `task-template.md`
- `issue-template.md`

## Checks

`sh workflow/lint.sh` verifies the invariants these rules assume and exits
nonzero when one does not hold, so it can gate a commit or a CI job.

## Ruleset version

`workflow/VERSION` records the ruleset revision this project received.
`workflow/.bootstrap-manifest` records the hash of every installed file, which
is what makes an update safe. Re-run the bootstrap script with `--upgrade` to
receive a later revision: files you have not touched are replaced, and files you
have edited are kept with the new version beside them as `<file>.new`.
EOF

printf '%s\n' "$VERSION" >"$STAGE/workflow/VERSION"

cat >"$STAGE/workflow/work-item-metadata.md" <<'EOF'
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

`sh workflow/lint.sh` fails when a declared dependency does not resolve, and
when two work items share a filename.

Do not add a priority field. Decide what to work on during planning based on
the task, constraints, dependencies, and available time.
EOF

cat >"$STAGE/workflow/incremental-task-scoping.md" <<'EOF'
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

`task-template.md` has that shape. Copy it rather than inventing one; an
inconsistent format costs more to read than it saves to write.

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

cat >"$STAGE/workflow/execution-and-stopping.md" <<'EOF'
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
- Run `sh workflow/lint.sh` when the repository has work items; it catches the
  bookkeeping errors that a passing build does not.
- If a relevant check fails, make targeted attempts to diagnose and fix it
  within scope.
- If blocked, record the evidence, limitation, and next concrete action rather
  than repeating unsuccessful attempts or claiming completion.
- Stop when the acceptance criteria are met, relevant verification is complete
  to the extent possible, necessary documentation is updated, and the required
  commit/push steps have been attempted.
- Report material limitations, failed checks, and follow-up work explicitly.
EOF

cat >"$STAGE/workflow/commit-policy.md" <<'EOF'
# Commit Policy

Commits are concise historical records of meaningful changes, not implementation
reports. Use a short message describing the outcome or intent of the change.

Put durable system context in relevant files under `features/`.
Put reusable workflow lessons in relevant files under `workflow/`.
Keep task-specific findings with the work item unless they establish knowledge
that will be useful beyond that task. Do not duplicate documentation in commits.

## Completing tasks

- Run `sh workflow/lint.sh` and the relevant tests and checks when the
  environment permits.
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

cat >"$STAGE/workflow/device-aware-development.md" <<'EOF'
# Device-Aware Development

Choose tasks based on the current device's capabilities, actual availability,
task risk, and the ability to verify the result.

## Phone

Prefer bounded tasks that can be performed and reviewed effectively on a phone:
- Review code, diffs, documentation, and investigation results.
- Refine plans, acceptance criteria, and issue descriptions.
- Make small, low-risk edits when suitable tools are available.

Do not assume every coding task must wait for a laptop.

## Laptop

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

if [ -n "$PHONE" ] || [ -n "$LAPTOP" ]; then
    printf '\n## Devices in this project\n\n' >>"$STAGE/workflow/device-aware-development.md"
    if [ -n "$PHONE" ]; then
        printf -- '- Phone: %s\n' "$PHONE" >>"$STAGE/workflow/device-aware-development.md"
    fi
    if [ -n "$LAPTOP" ]; then
        printf -- '- Laptop: %s\n' "$LAPTOP" >>"$STAGE/workflow/device-aware-development.md"
    fi
fi

cat >"$STAGE/workflow/verify-what-the-user-sees.md" <<'EOF'
# Verify What The User Sees

A change is not verified by the diff that produces it. It is verified by the
result someone can observe. When the outcome is rendered, served, or deployed,
check that result, not the code that should cause it.

## A change that does nothing

- A style change must change a computed value. Read the current cascade and the
  property's default first: a rule that restates a default, such as
  `justify-content: flex-start` on a flex column, deploys cleanly, passes every
  check, and changes nothing on screen.
- Layout and styling that exist in one state only — playing, lobby, error — can
  only be checked in that state. A rule scoped to one state is invisible from
  every other.

## The artefact may be stale, or the rule may be a no-op

When a change is reported as not visible, compare what is served with what is in
the repository before blaming the client: fetch the file with a cache-busting
query and compare it against the working tree. If the bytes match, the rule was
a no-op or applies in the wrong state.

## Verify on the device that will see it

A phone, a desktop, and a CI browser are different clients. Prefer verifying on
the one that reported the problem. If that device cannot run the check, say so
in the task outcome rather than implying the check passed.

## Do not keep rules that do nothing

Rules added while diagnosing and then left behind read as if they matter, and
they hide the one rule that does. Remove them when the diagnosis is done.
EOF

cat >"$STAGE/workflow/task-template.md" <<'EOF'
---
# area: <slug>
# dependencies: [<work-item>.md]
---

# <The change to be made, as one outcome>

## Context

Why this work exists, what is already known, and any constraint that shapes it.

## Acceptance criteria

- An observable condition that must hold when the task is complete.

## Verification

How each criterion will be checked, and on which device or environment.

## Outcome

Filled in when the task is closed: what was done, what was verified, what was
not, and what remains.
EOF

cat >"$STAGE/workflow/issue-template.md" <<'EOF'
---
# area: <slug>
# dependencies: [<work-item>.md]
---

# <The observation, as a statement>

## What was observed

Concrete evidence: the command, the input, the output, the environment.

## Open questions

- What is not yet known.

## What would resolve it

The check or the decision that would turn this into actionable work.

## Affects

Work items, feature documentation, or code that this touches.
EOF

cat >"$STAGE/workflow/lint.sh" <<'EOF'
#!/bin/sh
# Check the work-item invariants that the workflow rules assume.
#
#   sh workflow/lint.sh [project-dir]
#
# Exit status is 0 when everything holds, 1 when it does not, 2 on misuse.
# One line per problem, so it can gate a commit or a CI job unread.

set -u

ROOT=${1:-.}
if [ ! -d "$ROOT" ]; then
    printf 'lint: not a directory: %s\n' "$ROOT" >&2
    exit 2
fi
cd "$ROOT" || exit 2

errors=0

err() {
    printf '%s: %s\n' "$1" "$2" >&2
    errors=$((errors + 1))
}

TMP=${TMPDIR:-/tmp}/workflow-lint.$$
trap 'rm -f "$TMP".*' 0 1 2 15

# Required structure.

for d in issues tasks/open tasks/closed features workflow; do
    if [ ! -d "$d" ]; then
        err "$d" "missing directory"
    fi
done

# Collect work items.

: >"$TMP.items"
for d in issues tasks/open tasks/closed; do
    if [ ! -d "$d" ]; then
        continue
    fi
    for f in "$d"/*.md; do
        if [ -e "$f" ]; then
            printf '%s\n' "$f" >>"$TMP.items"
        fi
    done
done

# Filenames must be unique across the three lifecycle directories.

: >"$TMP.names"
while IFS= read -r f; do
    printf '%s|%s\n' "$(basename "$f")" "$f" >>"$TMP.names"
done <"$TMP.items"
sort "$TMP.names" >"$TMP.sorted"
prev=''
prev_path=''
while IFS='|' read -r name path; do
    if [ "$name" = "$prev" ]; then
        err "$path" "duplicate work-item filename (also $prev_path)"
    fi
    prev=$name
    prev_path=$path
done <"$TMP.sorted"

# Per-item checks.

while IFS= read -r f; do
    title=$(awk '
        BEGIN { fm = 0; seen = 0 }
        NR == 1 && $0 == "---" { fm = 1; next }
        fm && $0 == "---" { fm = 0; next }
        fm { next }
        !seen && NF > 0 { print; seen = 1 }
    ' "$f")
    case $title in
    "# "*) ;;
    *) err "$f" "no '# ' title after front matter" ;;
    esac

    awk '
        BEGIN { fm = 0; block = 0 }
        NR == 1 { if ($0 == "---") { fm = 1; next } else { exit } }
        fm && $0 == "---" { exit }
        fm && /^dependencies:[[:space:]]*\[/ {
            s = $0
            sub(/^dependencies:[[:space:]]*\[/, "", s)
            sub(/\].*$/, "", s)
            n = split(s, parts, ",")
            for (i = 1; i <= n; i++) {
                t = parts[i]
                gsub(/[[:space:]]/, "", t)
                if (t != "") print t
            }
            next
        }
        fm && /^dependencies:[[:space:]]*$/ { block = 1; next }
        block && /^[[:space:]]*-[[:space:]]*/ {
            t = $0
            sub(/^[[:space:]]*-[[:space:]]*/, "", t)
            gsub(/[[:space:]]/, "", t)
            if (t != "") print t
            next
        }
        block { block = 0 }
    ' "$f" | sed "s/['\"]//g" >"$TMP.deps"

    while IFS= read -r dep; do
        if [ -z "$dep" ]; then
            continue
        fi
        found=0
        for d in issues tasks/open tasks/closed; do
            if [ -f "$d/$dep" ]; then
                found=1
            fi
        done
        if [ "$found" -eq 0 ]; then
            err "$f" "dependency does not resolve: $dep (expected a bare work-item filename)"
        fi
    done <"$TMP.deps"

    case $f in
    tasks/closed/*)
        if ! grep -q '^## Outcome[[:space:]]*$' "$f"; then
            err "$f" "closed task has no '## Outcome' section"
        fi
        ;;
    esac
done <"$TMP.items"

# Relative links between markdown files must resolve.

find . -name '*.md' \
    -not -path './.git/*' \
    -not -path './node_modules/*' \
    -not -path './vendor/*' \
    -not -path './dist/*' >"$TMP.md" 2>/dev/null

while IFS= read -r f; do
    dir=$(dirname "$f")
    grep -o '](\([^)]*\))' "$f" 2>/dev/null | sed 's/^](//; s/)$//' >"$TMP.links"
    while IFS= read -r link; do
        case $link in
        '' | '#'* | /* | http://* | https://* | mailto:* | '//'*) continue ;;
        esac
        target=${link%%#*}
        if [ -z "$target" ]; then
            continue
        fi
        if [ ! -e "$dir/$target" ]; then
            err "$f" "link target does not resolve: $link"
        fi
    done <"$TMP.links"
done <"$TMP.md"

if [ "$errors" -gt 0 ]; then
    printf '\n%d problem(s).\n' "$errors" >&2
    exit 1
fi

printf 'lint: ok\n'
exit 0
EOF

# --- reconcile --------------------------------------------------------------

MANAGED="AGENTS.md
workflow/README.md
workflow/VERSION
workflow/work-item-metadata.md
workflow/incremental-task-scoping.md
workflow/execution-and-stopping.md
workflow/commit-policy.md
workflow/device-aware-development.md
workflow/verify-what-the-user-sees.md
workflow/task-template.md
workflow/issue-template.md
workflow/lint.sh"

NEW_MANIFEST=$MANIFEST.new
if [ -f "$MANIFEST" ]; then
    cp "$MANIFEST" "$NEW_MANIFEST"
else
    : >"$NEW_MANIFEST"
fi

for rel in $MANAGED; do
    if [ ! -f "$STAGE/$rel" ]; then
        continue
    fi

    if [ "$FORCE" -eq 1 ]; then
        install_rel "$rel"
        record "$rel"
        say "wrote $rel"
        continue
    fi

    if [ ! -e "$rel" ]; then
        old=$(manifest_hash "$rel")
        install_rel "$rel"
        record "$rel"
        if [ -n "$old" ]; then
            say "restored $rel"
        else
            say "created $rel"
        fi
        continue
    fi

    if [ "$MODE" = create ]; then
        say "kept $rel"
        continue
    fi

    old=$(manifest_hash "$rel")

    if [ -z "$old" ]; then
        say "kept $rel (not installed by this script)"
        continue
    fi

    current=$(hash_file "$rel")
    if [ "$current" = "$old" ]; then
        install_rel "$rel"
        record "$rel"
        say "updated $rel"
        continue
    fi

    if [ "$(hash_file "$STAGE/$rel")" = "$old" ]; then
        say "kept $rel (modified; unchanged upstream)"
        continue
    fi

    cp "$STAGE/$rel" "$rel.new"
    say "kept $rel (modified); new version at $rel.new"
done

if [ -f workflow/lint.sh ]; then
    chmod +x workflow/lint.sh
fi

if [ -s "$NEW_MANIFEST" ]; then
    mv "$NEW_MANIFEST" "$MANIFEST"
else
    rm -f "$NEW_MANIFEST"
    say "note: no files were recorded, so --upgrade will have nothing to track"
fi

# Preserve a pre-existing workflow/README.md: add anything it does not mention.

add_rule_reference() {
    rule_file=$1
    rule_base=$(basename "$rule_file")

    if grep -Fq "\`$rule_file\`" workflow/README.md; then
        return 0
    fi
    if grep -Fq "\`$rule_base\`" workflow/README.md; then
        return 0
    fi
    if ! grep -Fq "## Additional workflow rules" workflow/README.md; then
        printf '\n## Additional workflow rules\n' >>workflow/README.md
    fi
    entry=$(printf -- '- `%s`' "$rule_base")
    awk -v entry="$entry" '
        { print }
        $0 == "## Additional workflow rules" && !done {
            print entry
            done = 1
        }
    ' workflow/README.md >workflow/README.md.tmp
    mv workflow/README.md.tmp workflow/README.md
}

if [ -f workflow/README.md ]; then
    add_rule_reference workflow/execution-and-stopping.md
    add_rule_reference workflow/incremental-task-scoping.md
    add_rule_reference workflow/work-item-metadata.md
    add_rule_reference workflow/device-aware-development.md
    add_rule_reference workflow/commit-policy.md
    add_rule_reference workflow/verify-what-the-user-sees.md
fi

# --- git --------------------------------------------------------------------

if [ "$INIT_GIT" -eq 1 ]; then
    if [ ! -d .git ]; then
        git init -q .
        say "initialised a git repository"
    fi
fi

if [ ! -d .git ]; then
    say "note: $PROJECT_DIR is not a git repository; commit-policy.md assumes one"
fi

printf 'Bootstrap %s complete: %s\n' "$VERSION" "$PROJECT_DIR"
