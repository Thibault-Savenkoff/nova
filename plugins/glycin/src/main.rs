// glycin loader for .yaif (GNOME Loupe, Nautilus thumbnails): decodes with libyaifdec.
// glycin runs it sandboxed, one process per image; the file arrives on a Unix socket.
use std::ffi::CStr;
use std::io::Read;
use std::os::raw::{c_char, c_int};
use std::time::Duration;

use glycin_utils::*;
use gufo_common::orientation::Orientation;

#[repr(C)]
struct YaifInfo {
    width: c_int,
    height: c_int,
    planes: c_int,
    frames: c_int,
    delay: c_int,
    raw: c_int,
    has_preview: c_int,
    orientation: c_int,
    error: *const c_char,
}

unsafe extern "C" {
    fn yaif_read_info(d: *const u8, n: usize, info: *mut YaifInfo) -> c_int;
    fn yaif_decode(d: *const u8, n: usize, info: *mut YaifInfo) -> *mut u8;
    fn yaif_decode_preview(d: *const u8, n: usize, w: *mut c_int, h: *mut c_int) -> *mut u8;
    fn yaif_icc(d: *const u8, n: usize, len: *mut usize) -> *mut u8;
    fn free(p: *mut u8);
}

fn fail(msg: &str) -> ProcessError {
    ProcessError::UnsupportedImageFormat(msg.to_string())
}

fn err_of(info: &YaifInfo) -> ProcessError {
    let msg = if info.error.is_null() { "bad YAIF file" } else { unsafe { CStr::from_ptr(info.error) }.to_str().unwrap_or("bad YAIF file") };
    fail(msg)
}

pub struct Yaif {
    width: u32,
    height: u32,
    frames: Vec<Vec<u8>>, // RGBA, one per frame
    delay: Option<Duration>,
    icc: Option<Vec<u8>>,
    next: usize,
}

impl LoaderImplementation for Yaif {
    fn init(mut stream: UnixStream, _mime_type: String, _details: InitializationDetails) -> Result<(Self, ImageDetails), ProcessError> {
        let mut d = Vec::new();
        stream.read_to_end(&mut d).internal_error()?;
        let mut info: YaifInfo = unsafe { std::mem::zeroed() };
        if unsafe { yaif_read_info(d.as_ptr(), d.len(), &mut info) } != 0 {
            return Err(err_of(&info));
        }
        // ponytail: every frame decoded at once; fine for YAIF animations (small), stream them if one is huge
        let (w, h, count, px) = if info.raw != 0 {
            let (mut w, mut h) = (0, 0);
            let p = unsafe { yaif_decode_preview(d.as_ptr(), d.len(), &mut w, &mut h) };
            if p.is_null() {
                return Err(fail("YAIF RAW file without a preview"));
            }
            (w, h, 1, p)
        } else {
            let p = unsafe { yaif_decode(d.as_ptr(), d.len(), &mut info) };
            if p.is_null() {
                return Err(err_of(&info));
            }
            (info.width, info.height, info.frames.max(1), p)
        };
        let size = w as usize * h as usize * 4;
        let all = unsafe { std::slice::from_raw_parts(px, size * count as usize) };
        let frames = all.chunks(size).map(|f| f.to_vec()).collect();
        unsafe { free(px) };
        let mut len = 0;
        let icc = unsafe { yaif_icc(d.as_ptr(), d.len(), &mut len) };
        let icc = (!icc.is_null()).then(|| {
            let v = unsafe { std::slice::from_raw_parts(icc, len) }.to_vec();
            unsafe { free(icc) };
            v
        });

        let mut details = ImageDetails::new(w as u32, h as u32);
        details.info_format_name = Some("YAIF".into());
        // pixels are stored as the camera wrote them: the viewer applies the EXIF orientation
        details.transformation_orientation = Orientation::try_from(info.orientation as u16).ok();
        let delay = (count > 1).then(|| Duration::from_millis(info.delay.max(10) as u64));
        Ok((Yaif { width: w as u32, height: h as u32, frames, delay, icc, next: 0 }, details))
    }

    fn frame(&mut self, request: FrameRequest) -> Result<Frame, ProcessError> {
        if self.next >= self.frames.len() {
            if !request.loop_animation {
                return Err(ProcessError::NoMoreFrames);
            }
            self.next = 0;
        }
        let px = &self.frames[self.next];
        self.next += 1;
        let mut memory = SharedMemory::new(px.len() as u64).internal_error()?;
        memory.copy_from_slice(px);
        let mut frame = Frame::new(self.width, self.height, MemoryFormat::R8g8b8a8, memory.into_binary_data()).internal_error()?;
        frame.delay = self.delay.into();
        if let Some(icc) = &self.icc {
            frame.details.color_icc_profile = Some(BinaryData::from_data(icc).internal_error()?);
        }
        Ok(frame)
    }
}

init_main_loader!(Yaif);
