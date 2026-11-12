---
date: 2026-11-12
status: proposed
---

# Isolate memory-mapped proof artifacts

## Context

Lean loads proof artifacts with private writable mappings.
[Lean 4.34.1](https://github.com/leanprover/lean4/blob/5045d0056413266e57c625dcd7c365b10e377c52/src/library/module.cpp#L502) requires the mappings for pointer fixups.
[Darwin](https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/bsd/kern/kern_mman.c#L576) updates mapped files' access times unless the volume disables access-time updates.
Strict leases can reject reads of source inputs and generated artifacts.

## Decision

Run proofs and their source checkout on private, temporary Apple File System (APFS) disk images mounted with `noatime`.
Create the hosted checkout volume before fetching source.
Verify mount flags and bound capacity and deadlines.
Keep artifact digests, modes, identities, and event-free leases unchanged.
Detach the volume before deleting its owning scratch directory.
Require the system `diskutil image` interface on proof hosts.
The pinned Xcode 27 workflow requires [macOS 26.6 or later](https://developer.apple.com/xcode/system-requirements).

## Alternatives

Ignoring attribute events loses evidence of reversible changes.
Changing the host volume's mount options affects unrelated files.
Keeping the current storage prevents valid proof execution.
Supporting deprecated image commands adds remounting outside the pinned workflow.

## Consequences

Proof hosts need temporary disk images.
Reconsider if system mounting becomes unavailable or Lean stops mapping artifacts.

## Confirmation

Require native source and artifact mapping, mutation-rejection, cleanup, and mount-option tests.
Run the full pinned source and formal verification gates.
Verification remains pending.
