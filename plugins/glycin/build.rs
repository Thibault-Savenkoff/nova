fn main() {
    println!("cargo:rerun-if-changed=../../libnova/novadec.c");
    cc::Build::new().file("../../libnova/novadec.c").std("c99").opt_level(2).compile("novadec");
}
