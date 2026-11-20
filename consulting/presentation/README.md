# Harness Overview Slide

## Deliverables

- `/path/to/presentation/harness-overview-half-slide.pptx`
  — delivered editable one-slide PowerPoint; the legacy filename is retained,
  but the slide now uses the full page
- `harness-overview-half-slide.png` — rendered preview
- `build_slide.py` — deterministic generator

## Template consulted

```text
/path/to/presentation/template.pptx
```

The generated slide keeps the template's:

- 16:9 page size and original theme/master;
- full 16:9 content region, with the original template margins and navigation;
- dark-red (`#C00000`) title and section accents;
- Microsoft YaHei typography;
- red label cells, white cards, compact comparison table, and top-right
  navigation chevrons.

The template's subject matter is not copied.

## Slide message

The slide follows one general task through the harness lifecycle: bind the
task, define objective/success/scope, investigate, execute the scoped work,
verify the result, then review and close. A failed check visibly returns to the
analysis/planning loop. This supports implementation, investigation, analysis,
documentation, consulting, and presentation work—not only debugging.

The consulting panel lists the A5 hardware topics, all eight AscendNPU-IR
playbooks, the activation-evidence model, the harness-flow guide, and
source/drift notes. It routes these materials into Define, Investigate, and
Verify. The full-page lower section maps rules/skills, consulting,
scripts/instructions, and task state/hooks into the lifecycle; names
correctness, performance, compiler/IR, data/synchronization, and knowledge
improvement areas; and records hardware/platform limits that can cap or move a
solution to another layer.

## Regenerate

```bash
python consulting/presentation/build_slide.py \
  --template /path/to/presentation/template.pptx \
  --output '/path/to/presentation/harness-overview-half-slide.pptx'
```

The PNG preview is rendered with installed Microsoft PowerPoint during
verification; it is not synthesized separately from the slide.
