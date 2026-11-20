# Source Notes and Confidence Boundary

## Local source A: Ascend A5 architecture guide

- Source file:
  `/path/to/hardware-references/ascend_a5_architecture_guide.md`
- Guide research snapshot: **2026-07-22**
- Scope: public programmer-visible Ascend 950PR/950DT, NPU architecture
  version 3510 (`dav-3510`)
- Source policy of the guide: first-party Huawei/Ascend public material

The guide distinguishes three kinds of statements:

1. **Documented** — explicitly stated in an official source.
2. **Conservative interpretation** — a useful explanation of public diagrams
   or APIs, not a physical implementation claim.
3. **Not public** — insufficient evidence for an exact value or mechanism.

The hardware consulting documents preserve that boundary. In particular,
they do not invent instruction latencies, queue depths, event propagation
latencies, SSBuffer capacity, exact path bandwidths, or undocumented overlap
rules.

The guide's official source map includes:

- Ascend 950 NPU Architecture Whitepaper;
- CANN `asc-devkit` architecture-3510 guide and examples;
- the official high-performance Matmul–GELU example;
- Ascend C storage-position and data-movement API documentation;
- CANN 9.0 release notes;
- the PTO virtual ISA.

Consult the source guide's Section 18 for the exact first-party links and the
claim-to-source mapping.

## Local source B: AscendNPU-IR feature-observation wiki capture

- Saved page:
  `/path/to/compiler-references/特性是否生效观察方法 - WIKI.html`
- Saved assets:
  `/path/to/compiler-references/特性是否生效观察方法 - WIKI_files/`
- Local capture date: **2026-08-04**
- Page title: **特性是否生效观察方法** (“How to observe whether a feature
  took effect”)

The page contains a summary table for eight feature families and detailed
notes for six of them. The consulting library omits personal names and account
identifiers from the captured conversation snippets; they are irrelevant to
the technical procedure.

The eight wiki labels are:

1. costmodel;
2. autoblockify;
3. SIMT template;
4. ssbuf;
5. cvpipeline;
6. cv 1:2;
7. multibuffer;
8. preload.

## Cross-check and known ambiguity

The wiki was cross-checked against this available local compiler snapshot:

```text
/path/to/reference-wheel/
  triton/backends/ascend/compiler.py
```

That file is supporting evidence only; it is not declared to be the current
production wheel. It confirms that defaults and option plumbing can drift.

The most important naming ambiguity is the wiki's **costmodel** row: its shown
control is `enable_vf_fusion` / `--enable-vf-fusion`, and its diagnostic is
`vf-fusion-max-parallel-analyzer`. The inspected compiler also has a separate
`enable_costmodel_backend` option. The consulting document therefore calls
this entry “costmodel and VF fusion” and forbids treating the two controls as
synonyms without build-specific source evidence.

## Update policy

When a wheel or compiler changes:

1. locate the effective `triton/backends/ascend/compiler.py`;
2. capture the option dataclass default and metadata override chain;
3. capture the generated `bishengir-compile` command;
4. repeat the feature-specific IR/debug check;
5. update the relevant setting document with the build identity and date;
6. retain old behavior as a labeled historical snapshot if it matters to an
   open task.

Never silently promote a wiki default into a timeless guarantee.
