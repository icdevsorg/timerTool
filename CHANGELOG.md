
#v0.2.2

- FIX: canisters holding a 0.1.x timer state could not upgrade to 0.2.0/0.2.1 (M0170). Those
  releases rewrote the `v0_1_0` migration types in place from stableheapbtreemap + mo:map to
  mo:core Map. `v0_1_0` is the 0.1.x layout again; the core layout is `v0_2_0`, with an
  upgrade that converts the containers. `currentStateVersion` is `#v0_2_0`.
- deps: map 9.0.1 and stableheapbtreemap 1.5.0 (for the legacy layout only)

#v0.2.1

- updated to core 2.1.0
- updated to moc 1.3.0

#v0.2.0

- breaking changes!
- fixed initialization bug
- updated to core


#v0.1.2

- Updated Dependencies

#v0.1.0

- Added Class Plus
- Breaking Change - You will need to update your class instantiations.

#v0.0.3

Fixed Value Type
Fixed Value Share