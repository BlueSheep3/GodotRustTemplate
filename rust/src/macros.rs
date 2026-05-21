#[macro_export]
macro_rules! connect_signal {
	($node:expr, $signal:ident, $obj:expr, $func:expr) => {
		$node.signals().$signal().connect_other($obj, $func);
	};
	($node:expr, $signal:ident, $func:expr) => {
		$node.signals().$signal().connect($func);
	};
}
