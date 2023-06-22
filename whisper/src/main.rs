use std::{
    ffi::{c_int, CStr, CString},
    io::{Read, Write},
};

mod miniaudio;
use miniaudio as ma;

const SAMPLE_RATE: u32 = 16000;

unsafe fn record() -> ma::Result<()> {
    let mut ctx = ma::Context::init()?;

    let mut config = ma::Config::init(ma::DeviceType::ma_device_type_capture);
    config.capture.format = ma::Format::ma_format_f32;
    config.capture.channels = 1;
    config.sampleRate = SAMPLE_RATE;

    let mut file = std::fs::File::create("out.raw").unwrap();
    config.set_data_callback(Box::new(move |_outb: &mut [u8], inb: &[u8]| {
        file.write_all(inb).unwrap();
    }));

    let mut device = ma::Device::init(&mut ctx, config)?;

    device.start()?;
    println!("recording...");
    let _: u8 = std::io::stdin().bytes().next().unwrap().unwrap();
    println!("stop...");
    device.stop()?;

    Ok(())
}

const MODEL_PATH: &str = "../whisper.cpp/models/ggml-small.en.bin";

fn whisper() {
    let buf = std::fs::read("out.raw").unwrap();

    unsafe {
        let model_path = CString::new(MODEL_PATH.as_bytes()).unwrap();
        let ctx = whisper_sys::whisper_init_from_file(model_path.as_ptr());

        let params = whisper_sys::whisper_full_default_params(
            whisper_sys::whisper_sampling_strategy::WHISPER_SAMPLING_GREEDY,
        );
        let samples: &[f32] = std::slice::from_raw_parts(buf.as_ptr() as *const f32, buf.len() / 4);
        if whisper_sys::whisper_full(ctx, params, samples.as_ptr(), samples.len() as c_int) != 0 {
            panic!("whisper_full");
        }

        let segs = whisper_sys::whisper_full_n_segments(ctx);
        for seg in 0..segs {
            let text = CStr::from_ptr(whisper_sys::whisper_full_get_segment_text(ctx, seg));
            println!("{:?}", text.to_str().unwrap());
        }
    }
}

fn main() {
    unsafe {
        record().unwrap();
    }
    println!("whisper");
    whisper();
}
