#![forbid(unsafe_op_in_unsafe_fn)]
#![forbid(clippy::multiple_unsafe_ops_per_block)]
#![deny(clippy::undocumented_unsafe_blocks)]
#![warn(clippy::collection_is_never_read)]
#![warn(clippy::use_self)]
#![warn(clippy::explicit_iter_loop)]
#![warn(clippy::suspicious_operation_groupings)]
#![warn(clippy::wildcard_imports)]
#![warn(clippy::enum_glob_use)]
#![warn(clippy::infinite_loop)]
#![warn(clippy::suspicious_to_owned)]
#![warn(clippy::unused_trait_names)]

#[cfg(all(target_os = "android", not(feature = "android")))]
compile_error!("to compile for android, enable the 'android' feature");
#[cfg(all(target_family = "wasm", not(feature = "wasm")))]
compile_error!("to compile for web assembly, enable the 'wasm' feature");
#[cfg(all(feature = "nothreads", not(feature = "wasm")))]
compile_error!("must have feature 'wasm' enabled to enable 'nothreads'");

mod macros;

use godot::{
	init::{ExtensionLibrary, gdextension},
	meta::AsArg,
	prelude::*,
};

struct RustExtension;

// SAFETY: This trait requires that all non-rust code does not violate any safety guarantees.
// Since this project uses only rust code, this is guaranteed.
#[gdextension]
unsafe impl ExtensionLibrary for RustExtension {}

#[derive(GodotClass)]
#[class(init, base = Node)]
struct Root {
	base: Base<Node>,
}

#[allow(dead_code)]
fn spawn<T>(path: impl AsArg<GString>) -> Gd<T>
where
	T: Inherits<Node>,
{
	let node = load::<PackedScene>(path);
	let node = node.instantiate().unwrap();
	node.cast::<T>()
}

#[allow(dead_code)]
fn queue_free_children(node: &Node) {
	for mut child in node.get_children().iter_shared() {
		child.queue_free();
	}
}
