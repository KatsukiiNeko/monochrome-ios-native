# Turntable widget motion

The widget is a face over `PlayerController`, not a second player. The app
writes `playback-snapshot.json` into the App Group
`group.com.katsukiineko.monochrome`; the extension only reads it. No network,
no credentials, no playback state of its own.

## Two motion levels

| Option in the edit sheet | What it does | Guarantee |
| --- | --- | --- |
| `Still` | One timeline entry; the platter and arm hold the pose at the snapshot. | Always works, including when WidgetKit declines frequent updates. |
| `Spin (experimental)` | Timeline entries every 2 seconds; the platter advances 400° per entry and the arm tracks the song. | Stepped at best. WidgetKit decides when entries render, so the platter can hesitate or skip. |

Level 2 does not use a 60 fps animation. Home Screen widgets cannot run one.
`WidgetKit` may render fewer entries than the timeline contains; that is why the
option is labelled experimental and why `Still` exists. With Reduce Motion on,
the provider silently uses the still pose even if Spin is selected.

## Geometry

The deck uses a 9-inch arm with IEC groove radii:

| Value | Millimetres |
| --- | --- |
| Effective length `L` | 228.6 |
| Null radii `r1`, `r2` | 66.0, 120.9 |
| Pivot distance `d = √(L² − r1·r2)` | 210.42 |
| Offset angle `β = asin((r1 + r2) / 2L)` | 24.13° |
| Music groove | 146.05 to 60.325 |
| Label radius | 50.0 |
| Rest radius | 190.0 |

For a stylus radius `r`, the pivot angle is

```
φ(r) = acos((d² + L² − r²) / (2dL))
```

and the clockwise screen rotation from the rest pose is
`restAngle − φ(r)`. Groove radius falls linearly with song progress, so the arm
advances monotonically during uninterrupted playback. A seek moves the arm to
the target groove; it never changes the platter angle backward.

The platter turns at 200°/s (33⅓ rpm). The snapshot stores an absolute,
never-wrapping angle; the widget adds `200 × seconds since snapshot.date` only
while `isPlaying` is true. The app advances the same angle from the previous
snapshot when it writes, so the record never jumps because the song position
moved.

## Drop

`playStartedAt` is set when the engine actually starts producing audio and is
cleared on pause. Planner poses:

| Time since start | Arm | Lift |
| --- | --- | --- |
| `< 2 s` | parked, rotation 0 | 1 |
| `2 s ..< 4 s` | over the groove | 1 |
| `>= 4 s` | on the groove | 0 |

`lift` softens and lengthens the arm shadow. Frames are keyed to the start date,
so a timeline rebuild three seconds into the drop continues it instead of
replaying or skipping it. A resume is a new drop.

## Snapshot and reload policy

- Written on track change, play/pause/stop/failure, seek, duration becoming
  known, and artwork becoming available. Position ticks wake the observation
  loop but do not write.
- `isPlaying` comes from `engine.facts.isProducingAudio`, not from the requested
  state. Buffering, a stalled stream and a pause therefore show a stopped
  platter.
- Reloads are coalesced to one per 5 seconds; a transition to playing is urgent
  and reloads immediately. The timeline ends 60 seconds after its last spinning
  entry and then asks for a refresh; a still or paused deck asks after 15
  minutes.
- If artwork cannot be prepared, the label keeps the Monochrome logo and the
  snapshot has no artwork file. Artwork is downsampled with ImageIO to a 256 px
  JPEG, keeping only the last three files.

## States

| State | Widget |
| --- | --- |
| App Group unavailable | `Open Monochrome`, parked arm |
| No track | `Not playing`, parked arm |
| Loading / buffering | Last metadata, stopped platter |
| Playing | Spin steps or still pose, arm on the groove |
| Paused | Stopped platter, arm on the groove |
| Failed | Last metadata, stopped platter |
| End of queue | Last metadata, stopped platter |
| Reduce Motion | Still pose, no animation modifiers |

## Known limits

- No continuous animation; timeline cadence is controlled by iOS.
- The extension cannot prove it has the App Group until it runs on a device
  signed with both entitlements. A free/personal team may not accept App Groups;
  that is not knowable from source.
- A force-quit while playing leaves a snapshot that says playing; on relaunch the
  next paused snapshot continues the platter angle from wall-clock time. The
  record can therefore jump once after a long gap.
- `cdhash`/team/App Group provisioning, install, Lock Screen and Home Screen
  rendering, and reload cadence are device checks. None of them were verified on
  this Linux host.

See `docs/DEVICE_TEST_CHECKLIST.md` for the human checks.
