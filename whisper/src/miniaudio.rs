use miniaudio_sys::*;
use std::{ffi::c_void, mem::MaybeUninit, pin::Pin, ptr};

pub use miniaudio_sys::ma_device;

pub type Result<T> = std::result::Result<T, ma_result>;

fn check(res: ma_result) -> Result<()> {
    match res {
        ma_result::MA_SUCCESS => Ok(()),
        _ => Err(res),
    }
}

// Why the boxes: at one point the miniaudio docs mention that the pointer to Context must be stable:
// "Note that internally the context is only tracked by it's pointer which means you must not change
// the location of the ma_context object. If this is an issue, consider using malloc() to allocate
// memory for the context."
// It turns out they also implicitly require it for Device.
pub struct Context(Box<ma_context>);

impl Context {
    pub fn init() -> Result<Self> {
        let mut ctx = Box::new(MaybeUninit::<miniaudio_sys::ma_context>::uninit());
        unsafe {
            check(ma_context_init(
                ptr::null(),
                0,
                ptr::null(),
                ctx.as_mut_ptr(),
            ))?;
            Ok(Context(Box::from_raw(Box::into_raw(ctx).cast())))
        }
    }

    pub fn as_mut_ptr(&mut self) -> *mut ma_context {
        &mut *self.0
    }
}

pub type DeviceType = ma_device_type;
pub type Format = ma_format;

pub type DataCallback = Box<dyn FnMut(&mut [u8], &[u8])>;

/// Data attached to ma_device.pUserData.
#[derive(Default)]
struct DeviceUserData {
    data_callback: Option<DataCallback>,
}

pub struct Config {
    config: ma_device_config,
    user_data: Pin<Box<DeviceUserData>>,
}

unsafe extern "C" fn data_callback(
    device: *mut ma_device,
    outp: *mut c_void,
    inp: *const c_void,
    count: u32,
) {
    let user_data: &mut DeviceUserData = &mut *((*device).pUserData as *mut DeviceUserData);
    let outb = std::slice::from_raw_parts_mut::<u8>(outp as *mut u8, (count * 4) as usize);
    let inb = std::slice::from_raw_parts::<u8>(inp as *const u8, (count * 4) as usize);
    (user_data.data_callback.as_mut().unwrap())(outb, inb);
}

impl Config {
    pub fn init(type_: DeviceType) -> Self {
        Config {
            config: unsafe { ma_device_config_init(type_) },
            user_data: Box::pin(Default::default()),
        }
    }

    pub fn as_ptr(&self) -> *const ma_device_config {
        &self.config
    }

    pub fn set_data_callback(&mut self, callback: DataCallback) {
        self.user_data.data_callback = Some(callback);
        self.config.pUserData = &mut *self.user_data as *mut DeviceUserData as *mut c_void;
        self.config.dataCallback = Some(data_callback);
    }
}

impl std::ops::Deref for Config {
    type Target = ma_device_config;

    fn deref(&self) -> &Self::Target {
        &self.config
    }
}

impl std::ops::DerefMut for Config {
    fn deref_mut(&mut self) -> &mut Self::Target {
        &mut self.config
    }
}

pub struct Device {
    device: Box<ma_device>,
    // stored here to prolong lifetime
    #[allow(dead_code)]
    user_data: Pin<Box<DeviceUserData>>,
}

impl Device {
    pub fn init(ctx: &mut Context, config: Config) -> Result<Self> {
        let mut device = Box::new(MaybeUninit::<miniaudio_sys::ma_device>::uninit());
        unsafe {
            check(ma_device_init(
                ctx.as_mut_ptr(),
                config.as_ptr(),
                device.as_mut_ptr(),
            ))?;
            Ok(Device {
                device: Box::from_raw(Box::into_raw(device).cast()),
                user_data: config.user_data,
            })
        }
    }

    pub fn as_mut_ptr(&mut self) -> *mut ma_device {
        &mut *self.device
    }

    pub fn start(&mut self) -> Result<()> {
        check(unsafe { ma_device_start(self.as_mut_ptr()) })
    }

    pub fn stop(&mut self) -> Result<()> {
        check(unsafe { ma_device_stop(self.as_mut_ptr()) })
    }
}

impl Drop for Device {
    fn drop(&mut self) {
        unsafe { ma_device_uninit(self.as_mut_ptr()) };
    }
}
