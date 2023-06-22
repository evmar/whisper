pub fn main() {
    cc::Build::new()
        //.define("MINIAUDIO_IMPLEMENTATION", None)
        .file("miniaudio.c")
        .compile("miniaudio");
}
