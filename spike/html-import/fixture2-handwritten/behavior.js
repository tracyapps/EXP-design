// Fixture-only behavior receipt: importing may render this inside the bounded,
// non-persistent browser, but EXP must preserve it as opaque source and never
// reinterpret it as editable canvas behavior or grant automatic write-back.
window.fixtureBehaviorLoaded = true;
