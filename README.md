# CarePlix Ring

Tooling and reference implementations for the CarePlix ring's Bluetooth layer.

| Path | What it is |
|---|---|
| [`ios/RingDiscovery`](ios/RingDiscovery) | iOS BLE discovery and connect for the ring, plus the root-cause analysis of why the shipping ring app found nothing. **Start with its README.** |
| [`tools/ring-provisioner`](tools/ring-provisioner) | Android tool that renames a ring's BLE name to `LOOP-XXXX`. Also the best on-disk record of what the ring hardware actually does over the air. |

The two are connected: the provisioner sets the advertised name, and `RingDiscovery` matches on it.
Change the naming scheme in one and the other stops finding rings — `RingNaming.BRAND` and
`RingNameMatcher.brand` are one decision written down twice.

Neither is a shipping app. Both are meant to be read and dropped into the products that need them.
