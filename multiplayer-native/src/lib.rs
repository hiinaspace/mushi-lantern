mod session;
mod viseme;

use godot::prelude::*;

struct MushiExtension;
#[gdextension]
unsafe impl ExtensionLibrary for MushiExtension {}
