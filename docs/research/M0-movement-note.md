# M0 movement research note

## Design question

The target is a loose, drifting cluster that gathers and stretches under the lantern. It should read as a small animal group responding through local perception, inertia, and mutual influence. Blue should persuade rather than vacuum agents onto a cursor; orange should apply pressure rather than explode the flock.

M0 only needs to decide whether social motion improves that feeling and whether short individual arousal persistence adds useful texture. It is not a search for biologically complete flocking, an optimal shepherding policy, or a general alife framework.

## What the sources contribute

- Reynolds (1987) supports the core construction: independent agents using local perception, limited acceleration, collision avoidance, velocity matching, and centering can produce coherent aggregate motion. The practical aesthetic lesson is that finite acceleration and momentum are as important as the three social labels. They keep direction changes from looking digital.
- Reynolds (1999) separates steering from locomotion and distinguishes **seek** from physical attraction. Seek changes desired velocity; an attractive force can orbit. His **arrival** behavior ramps desired speed down near a target. For M0, a moving lantern footprint should feed a desired-velocity/arrival term, while the motion layer caps acceleration and speed. Correlated wander and obstacle avoidance then remain separately understandable.
- Couzin et al. (2002) use prioritized local zones: repulsion takes precedence at short range, then orientation and attraction act farther out, with a rear blind region. Small changes in interaction ranges can move the group between swarm, torus, and polarized states; speed, turning rate, and noise also affect group type and spatial sorting. M0 should borrow the lesson that interaction geometry can cause qualitative transitions, without copying the 3D fish-school model or deliberately seeking every phase.
- Strömbom et al. (2014) model agents attracted to nearby neighbours and repelled by a shepherd, and switch the shepherd between collecting a far outlier and driving a cohesive group. That cleanly names two player situations already in the charter: recover a split and move a gathered group. The paper’s autonomous shepherd, global-centre calculations, flock-size scaling, and completion optimization are outside M0. A human lantern already chooses where to apply pressure.

## A bounded comparison

Use the same three-creature fixture, then the same three groups of eight, seeds, obstacle layout, player route, and lamp trajectory. Preserve each accepted preset. Change one dimension per pair and stop once the movement is legible and pleasant; do not cross every setting into a factorial sweep.

1. **Motion texture before social tuning.** With social and lantern strengths held modest, compare two acceleration/turning limits. Keep the slower response only if agents visibly carry momentum but can still recover around a trunk. Use persistent/correlated wander; fresh frame-by-frame random headings will look like jitter rather than life.
2. **Loose social shape.** With the chosen motion limits, compare one cohesion/alignment balance against a slightly looser alternative. Separation stays high priority and short range. Prefer the smallest change that lets a cluster elongate behind a moving lantern and relax back together without forming a rigid ball or marching formation.
3. **Lantern response.** Compare two adjacent response strengths or arrival radii, not both at once. Judge whether lateral lamp placement bends and stretches the group. Reject settings where every agent independently points straight at the lamp, piles onto its exact position, or tracks it with nearly identical velocity. Retain enough local wander and neighbour influence that the source changes the group’s tendency rather than dictating every trajectory.
4. **Social contribution control.** Disable all social terms (separation, cohesion and alignment) while retaining the selected locomotion, wander, and lantern response. If independent seekers are equally readable and pleasant, the social layer is not earning its complexity. If social motion creates recoverable lag, flank response, and loose regrouping, keep it.
5. **Individual arousal memory last.** At the selected baseline, compare no memory with one short leaky state. If persistence helps, compare only two nearby relaxation times, roughly “brief trace” and “clearly lingering”; exact seconds should come from play, not the papers. Keep it only if blue leaves a temporarily calmer drift and orange leaves bounded activity that remains recoverable after the beam moves away.

For each pair, record only: gather readability, stretch while leading, turn predictability, split recovery, settling after release, and a one-line feel note. Automated delivery time can reveal breakage but cannot select “soothing” or “primordial.” A short captured trajectory or video from the same seed is better evidence than a large parameter table.

Stop when one preset supports gathering, carrying, turning, and releasing for several minutes without obvious magnetism. If no nearby setting does, change the lantern steering formulation or tool placement before adding more animal state.

## Collective hysteresis is not the arousal hypothesis

Couzin et al.’s “collective memory” is hysteresis in group structure. Individuals have no explicit memory variable. When an interaction parameter such as the orientation zone is increased and later decreased, the group may follow different transitions because its current spatial and directional configuration carries history. Identical current individual rules can therefore support different collective states.

M0’s proposed arousal `e` is an explicit scalar stored by each individual, driven by filtered light and relaxing toward baseline. It directly modulates preferred speed, wander, pulse, or sound after the stimulus disappears. This is an authored game hypothesis; Couzin et al. do not validate it.

Both mechanisms can make motion persist after a change, so label them separately in debug output. With `e` disabled, lingering order caused by positions, velocities, inertia, and neighbour geometry is emergent group history. With the same group snapshot and motion state, a difference caused by retained `e` is individual arousal memory. M0 does not need to suppress emergent hysteresis or map its phase diagram. It only needs to avoid claiming that the explicit arousal feature is the paper’s collective memory result.

## Practical parameter priorities

Keep the live panel small. The highest-value exposed comparisons are:

| Dimension | What to watch | Failure signature |
| --- | --- | --- |
| Acceleration/turn limit and inertia | Curved, carried motion; recovery around obstacles | Digital pivots at one extreme, helpless overshoot at the other |
| Correlated wander strength/time | Individual life within a coherent drift | High-frequency jitter or aimless loss of player influence |
| Separation range/priority | Personal space and obstacle-safe local motion | Clumping, overlap, or explosive mutual repulsion |
| Cohesion/alignment balance and neighbour radius | Loose cluster, stretch, regrouping | Rigid synchronized ball or incoherent dust |
| Lantern response strength and arrival radius | Player can bend, lead, flank, and release | Cursor magnetism, orbiting, or a dead stop that cannot follow |
| Optional arousal drive and relaxation | Brief behavioral trace that remains controllable | Permanent scatter, sluggish waiting, or no visible difference |

Do not expose Couzin-style zone sweeps, nearest-neighbour scaling, blind-angle studies, Strömbom collecting thresholds, extra species variables, metabolism, or learning in M0. Those are references for interpretation, not commitments to new game scope.

## References

Full bibliographic metadata, retrieval details, exact checksums, and source links are in [SOURCES.md](SOURCES.md).
