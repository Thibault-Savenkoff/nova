fn main() {
    println!("cargo:rerun-if-changed=../../libyaif/yaifdec.c");
    cc::Build::new().file("../../libyaif/yaifdec.c").std("c99").opt_level(2).compile("yaifdec");
}
