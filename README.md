# bootstrap

Scaffolds a file-based workflow for agent-driven projects: a four-tier work-item
lifecycle, the rules for working through it, and a linter that checks the
bookkeeping the rules assume.

One POSIX shell script. No dependencies. Nothing to install.

```sh
sh bootstrap.sh path/to/project
```

Then commit the result:

```sh
git -C path/to/project add -A
git -C path/to/project commit -m "Add project workflow"
```

`--init` will create the repository for you if there is not one already.

## Modes

| Command | Behaviour |
| --- | --- |
| `sh bootstrap.sh DIR` | Create missing files. Everything already there is left alone. |
| `sh bootstrap.sh --upgrade DIR` | Update files installed by an earlier run. Files you edited are kept, with the new version written beside them as `<file>.new`. |
| `sh bootstrap.sh --force DIR` | Overwrite everything, including files you edited. |

Optional: `--phone NAME` and `--laptop NAME` record the hardware this project is
worked on. Without them the device rule stays generic.

## Why this exists

An agent begins every session with no memory of the last one. Everything it knows
is what is in the repository. Left alone, the decisions, the open questions, and
the reason a thing is the way it is end up in conversation history, in commit
messages, or nowhere at all — and the next session either re-derives them or
quietly contradicts them.

This puts that state in files the agent already reads, and gives it a lifecycle
so work does not accumulate in one undifferentiated pile.

## What it writes

```
AGENTS.md                          entry point; tells the agent where to read
workflow/
  README.md                        the lifecycle, the rule index, the update note
  VERSION                          ruleset revision this project received
  .bootstrap-manifest              hash of every installed file
  execution-and-stopping.md        how to start, control scope, and finish
  incremental-task-scoping.md      when to split work, and when to stop
  work-item-metadata.md            optional `area` and `dependencies` fields
  device-aware-development.md      choosing work by device and verifiability
  commit-policy.md                 what to commit, verify, and push
  verify-what-the-user-sees.md     verify the result, not the diff
  task-template.md                 shape for actionable work
  issue-template.md                shape for an unresolved observation
  lint.sh                          checks the invariants below
issues/                            unresolved observations and questions
tasks/open/                        actionable work
tasks/closed/                      completed work, kept for history
features/                          durable knowledge about the implemented system
```

Each lifecycle directory gets a `.gitkeep`, because git does not track empty
directories and a fresh clone would otherwise lose the whole structure.

## The lifecycle

| Directory | Holds | Moves by |
| --- | --- | --- |
| `issues/` | Observations, problems, questions, investigations | Moving to `tasks/open/` once actionable |
| `tasks/open/` | Work understood well enough to start | Moving to `tasks/closed/` once acceptance criteria are met |
| `tasks/closed/` | Completed work and its outcome | Staying put |
| `features/` | How the system behaves and why, independent of any one task | Growing over time |

Filenames are preserved across moves and stay unique across the three work-item
directories, so that `dependencies` can name them.

The split matters more than it looks. An agent that cannot tell an unresolved
observation from an actionable task will start implementing the observation.

## The rules

| File | Governs |
| --- | --- |
| `execution-and-stopping.md` | Reading only what is needed, proportionate planning, scope control, verification |
| `incremental-task-scoping.md` | Task size, acceptance criteria, and when decomposition should stop |
| `work-item-metadata.md` | `area` and `dependencies` — both optional, both only when they constrain real work |
| `device-aware-development.md` | Picking work by device capability and the ability to verify the result |
| `commit-policy.md` | Staging only intended changes, verifying before claiming success, when to push |
| `verify-what-the-user-sees.md` | Checking the rendered or served result, not the diff that should cause it |

Two rules cut against the grain of most process documentation, and they are the
ones worth keeping:

- **Proportionality.** *"Apply them proportionately; do not turn routine changes
  into unnecessary planning, investigation, or administration."* A small change
  is one task and no ceremony.
- **No priority field.** Deciding what to work on belongs to planning, where the
  constraints and the available time are visible — not to a label applied days
  earlier.

## Templates

`task-template.md` and `issue-template.md` carry the shape that three projects
converged on: optional `area` and `dependencies` front matter, then one outcome,
observable acceptance criteria, verification, and — for a closed task — an
`## Outcome` recording what actually happened. Delete the sections that do not
apply rather than filling them in.

They exist because the absence was expensive. In the largest of the three
projects, eighty-one closed tasks spread the same two ideas across several
different headings, and reading them back cost more than writing them did.

## Checks

```sh
sh workflow/lint.sh
```

Exit `0` when everything holds, `1` when it does not, `2` on misuse. One line of
output per problem, so it gates a commit or a CI job without being read. It
checks:

- the lifecycle directories exist;
- work-item filenames are unique across `issues/`, `tasks/open/`, `tasks/closed/`;
- every work item has a `# ` title;
- every declared `dependency` resolves to a work item;
- every closed task has an `## Outcome` section;
- every relative link between markdown files resolves.

It does not check the parts that need judgement: whether a task is the right
size, whether acceptance criteria are observable, or whether the outcome is true.
Those remain prose.

## Staying current

`workflow/VERSION` records the ruleset revision, and
`workflow/.bootstrap-manifest` records the SHA-256 of every file as installed.
That manifest is what makes `--upgrade` safe. For each file:

| Project state | Result |
| --- | --- |
| untouched since install, ruleset changed | replaced |
| untouched since install, ruleset unchanged | left alone |
| edited, ruleset unchanged | left alone, silently |
| edited *and* ruleset changed | kept, new version written as `<file>.new` |
| edited out of the managed set | left alone and reported |

A `.new` file is a proposal, not a merge. Read it, fold in what you want, and
delete it. The manifest is not updated for a file you kept, so the next upgrade
offers the change again.

## In use

The workflow is not a proposal. It emerged while building [kxp](https://github.com/taolicus/kxp),
was extracted into this script, seeded two greenfield projects, and was then
retrofitted onto kxp. All three are public and playable, and all three carry
their own work-item record:

| Project | Play | Commits | Work items |
| --- | --- | --- | --- |
| [kxp](https://github.com/taolicus/kxp) — real-time rock-paper-scissors tournament | [kxp.pifia.net](https://kxp.pifia.net) | 323 | 133 |
| [asteroids](https://github.com/taolicus/asteroids) — two-player co-op Asteroids on one ship | [asteroids.pifia.net](https://asteroids.pifia.net) | 72 | 33 |
| [komikan](https://github.com/taolicus/komikan) — the Komikan board game | [komikan.tequionet.org](https://komikan.tequionet.org) | 37 | 26 |

About one work item per two commits. The rules in the three projects are *not*
identical — `incremental-slice-scoping.md` was renamed to `incremental-task-scoping.md`,
`work-item-metadata.md` was added later, `device-aware-development.md` is
localised to each project's actual devices, and one project grew a rule of its
own. The divergence is the evidence that the rules are being used rather than
copied.

Two of those local lessons are now part of what this script ships:
`verify-what-the-user-sees.md`, written in `asteroids` after a CSS rule that was
already the default shipped and changed nothing, and the `## Outcome` discipline
that `lint.sh` now enforces. The corpus still runs the pre-`0.2` ruleset.

Two examples worth reading in place:

- `workflow/verify-what-the-user-sees.md` in `asteroids` — the original of the
  rule above.
- `docs/tasks/closed/` in `kxp` — tasks that separate *waiting on effort* from
  *waiting on an artifact*, and say which device can close them.

## What this is not

- **Not enforcement of the judgement rules.** `lint.sh` checks bookkeeping:
  filenames, dependencies, outcomes, links. It cannot tell whether a task is
  well-scoped or an outcome is honest. Those stay prose, and a model can ignore
  prose.
- **Not a tracker.** No UI, no query language, no reporting. `grep` and `ls` are
  the interface, deliberately.
- **Not portable process.** The device rule assumes one person with a phone and a
  laptop. It is the least universal file here; change it or drop it.
- **Not evidence that the workflow works.** There is no counterfactual. What the
  three projects show is a consistent record kept for three months, which is
  evidence of follow-through — not proof that the process caused the outcome.

## Status

Ruleset `0.2.0`. Tested on macOS; the tooling uses only POSIX `sh`, `awk`, `sed`,
`find`, and one of `sha256sum`, `shasum`, or `openssl` for the manifest.

Known limits:

- Link checking verifies that a path resolves, not that a `#fragment` names a
  real heading.
- There is no CI snippet. Wiring `sh workflow/lint.sh` into a workflow is one
  line, but it is not written down here.
- No worked example project. The three real projects are the evidence, and they
  are large enough that a reader cannot see one chain end to end quickly.

## Roadmap

- [ ] **Write the case study.** One task from issue to closed task to commit in a
      single project, the diff in `workflow/` between the first and third
      project, and what the rules got wrong the first time. That is the real
      argument for this approach, and the one thing a reader cannot reconstruct
      from the files.
- [ ] **Check link fragments.** Compare `#fragment` targets against the headings
      they name. The Node implementation in `kxp` already does this; the POSIX
      port does not.
- [ ] **Ship a CI snippet.** A short, copyable job that runs `lint.sh` on push,
      so a bootstrapped project gets the check for free.
- [ ] **Add a worked example.** A minimal repository with one complete chain,
      small enough to read in a couple of minutes.

## Requirements

POSIX `sh`. No GNU-specific flags. Needs `awk`, `sed`, `find`, and one SHA-256
implementation for the manifest.

## Licence

No licence file yet.
