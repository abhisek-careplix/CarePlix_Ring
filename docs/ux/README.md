# CarePlix Ring · iOS experience redesign

A research-first redesign of the ring app's user experience: profile capture, pairing, the four tabs (**Today · Sleep · Measure · Breathe**), the ring's battery and sync presence, and the design system that makes it all one product family with the CarePlix band app.

| Doc | What it answers |
|---|---|
| [01-audit.md](01-audit.md) | What is wrong today, ranked by the journey it breaks |
| [02-research.md](02-research.md) | What Oura, WHOOP, Apple Watch/Health and iOS 26 do, and the principles we take |
| [03-sensor-data-map.md](03-sensor-data-map.md) | Every datum the Veepoo SDK exposes for this ring, mapped to a screen, plus what we will never show |
| [04-journeys.md](04-journeys.md) | First night, morning check-in, midday measure, breathe, evening battery, disconnects, weekly |
| [05-screens.md](05-screens.md) | Information architecture and every screen top-to-bottom with states and copy |
| [06-design-system.md](06-design-system.md) | Tokens, type, motion, chart grammar and the ring's components |

Implementation: `ios/RingExperience` (SwiftUI design system, screens, a `RingDataSource` protocol with a mock source and a Veepoo adapter) builds on `ios/RingDiscovery` (pairing). The visual mockups live in the design canvas linked from the pull request.

## The redesign in one paragraph

The ring is worn all day and looked at for ninety seconds each morning. Today opens with **one time-aware answer** (Readiness in the morning, Stress or Activity in the afternoon, Tonight in the evening), a row of score shortcuts, and six overnight vitals each against the wearer's **own typical range**. The ring itself is always present as a **status accessory above the tab bar** (connected · battery · last sync) and a Ring sheet with a battery forecast and a bedtime charge reminder. Sleep shows a real night (hypnogram, stages, contributors, overnight vitals, sleep debt) and says plainly when the ring was not worn or ran out. Measure is "how am I right now" (today's heart-rate line plus capability-gated spot tests with honest exits), and Breathe holds breathing rate overnight and now, oxygen through the night, and guided breathing. Profile capture asks only what is used, explains why, and adds wear hand and finger, bedtime and sleep goal. The search bar goes.
