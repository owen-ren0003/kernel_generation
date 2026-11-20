# A5 Memory and Data-Movement Reference

## Cache versus explicit local storage

Do not read `L0`, `L1`, and `L2` as one conventional cache ladder.

| Hardware-managed cache | Explicitly managed buffer/scratchpad |
|---|---|
| shared L2 | AIC L1 |
| instruction caches | L0A / L0B / L0C |
| SIMT DCache | AIV Unified Buffer |
| AI CPU L1/L2/L3 | BiasTable Buffer / Fixpipe Buffer |

The kernel/compiler chooses local addresses, issues movement, and protects
reuse for L1/L0/UB. L2 uses tags, hit/miss behavior, and allocation policy.

## Canonical payload paths

```text
Matrix input:       GM/L2 → MTE2 → L1 → MTE1 → L0A/L0B
Matrix compute:     L0A + L0B → Cube → L0C
Matrix output:      L0C → Fixpipe → GM/L2, L1, or AIV UB
Vector input:       GM/L2 → MTE2/DMA → UB → registers
Vector output:      registers → UB → MTE3/DMA → GM/L2
N-D rearrangement:  GM/L2 → NDDMA → UB
System transfer:    SDMA at chip/system level
```

MTE names engines/pipelines, not memory levels:

- MTE2 is the common inward/copy-in path;
- MTE1 stages AIC matrix operands from L1 into L0A/L0B;
- MTE3 is the common AIV outward/copy-out path;
- Fixpipe is the Cube-result output/transform path;
- NDDMA performs up-to-five-dimensional GM→UB rearrangement;
- SDMA is distinct, system-level DMA.

Architecture 3510 adds `L1 ↔ UB` and `L0C → UB`, and removes direct
`GM → L0A/L0B` and direct `L1 → GM` paths from the documented MTE model.

## Logical GM paths still involve L2

An API-level `GM → UB` copy means the kernel names a global-memory address and
a UB destination. Physically, shared L2 can satisfy or allocate the request.
The programmer does not normally issue separate `GM→L2` and `L2→UB` copies.

Therefore, distinguish:

```text
programming view:  GM → MTE2 → UB
memory view:       package memory ↔ shared L2 ↔ MTE2 → UB
```

L2 hints can alter allocation behavior; they do not erase the cache from the
physical path.

## Direct Cube–Vector fusion

Two direct mechanisms avoid an external intermediate:

```text
AIC L1 ↔ AIV UB
Cube → L0C → Fixpipe → AIV UB
```

The second path can distribute a matrix result to two AIV UBs in a 1:2 mixed
kernel. Compared with `L0C → GM/L2 → UB`, it can avoid one outward transfer,
one inward transfer, and intermediate L2 occupancy. It still requires legal
layout, alignment, buffer ownership, and cross-core synchronization.

SSBuffer is a separate AIC–AIV communication facility. Public sources do not
establish that it is the bulk tensor path or disclose its payload semantics.

## Dedicated parameter stores

- **BT / BiasTable Buffer** receives bias/table data from L1 for the matrix
  path.
- **FP / Fixpipe Buffer** receives Fixpipe parameters, especially
  quantization-related data, from L1.

The main Fixpipe tensor payload normally comes from L0C. `L1 → FP Buffer`
does not mean ordinary matrix data bypasses Cube.

## Alignment and layout

| Storage | Minimum start alignment | Recommended/typical 3510 layout |
|---|---:|---|
| UB | 32 B | no general layout requirement |
| L1 | 32 B | `FRACTAL_NZ` for matrix staging |
| L0A | 512 B | `FRACTAL_NZ` |
| L0B | 512 B | `FRACTAL_ZN` |
| L0C | 64 B | `FRACTAL_NZ` |
| BiasTable Buffer | 64 B | bias-specific |
| Fixpipe Buffer | 64 B | parameter-specific |

Address alignment, transfer granularity, tensor layout, and legal instruction
shape are independent constraints. A 512-byte-aligned L0A address can still
hold an illegal layout.

Fractal atoms are the memory view of datatype-specific Cube fragments; they
are not another unconstrained scheduler tile. `NZ`/`ZN` additionally describes
ordering/orientation.

## Debugging questions

1. What is the logical source and destination address space?
2. Which movement engine must realize that path?
3. Does the generated IR use the intended direct path or a GM round trip?
4. Are alignment, shape, and layout each legal?
5. Can a tile remain in L1, L0C, UB, or registers for reuse?
6. Is a purported bandwidth problem actually a bank conflict or dependency
   stall?

Source: local A5 guide Sections 2, 5, 7–9, 11–13, and 17.
