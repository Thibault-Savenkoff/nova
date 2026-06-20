/*
 * LibRaw → WASM thin wrapper.
 *
 * Exported functions (callable from JS via Emscripten):
 *   uint16_t* libraw_decode(const uint8_t* data, int size, int* out_w, int* out_h)
 *   void      libraw_free(void* ptr)
 *
 * Output: uint16_t[w * h * 3]  linear-light RGB (no gamma, no auto-bright).
 * 0 = black, 65535 = sensor clip.  Apply ACES + sRGB gamma for display.
 */
#include <libraw/libraw.h>
#include <cstdlib>
#include <cstring>
#include <cstdint>

extern "C" {

uint16_t* libraw_decode(
    const uint8_t* data, int size,
    int* out_w, int* out_h
) {
    try {
        LibRaw proc;

        // Linear light: gamma (1,1), no auto-bright, full-size, 16-bit.
        // Camera white balance applied; sRGB colour primaries via colour matrix.
        proc.imgdata.params.use_camera_wb    = 1;
        proc.imgdata.params.no_auto_bright   = 1;
        proc.imgdata.params.output_bps       = 16;
        proc.imgdata.params.gamm[0]          = 1.0; // gamma = 1 (linear)
        proc.imgdata.params.gamm[1]          = 1.0;
        proc.imgdata.params.output_color     = 1;   // sRGB colour primaries
        proc.imgdata.params.half_size        = 0;
        proc.imgdata.params.use_fuji_rotate  = 0;

        if (proc.open_buffer((void*)data, (size_t)size) != LIBRAW_SUCCESS) return nullptr;
        if (proc.unpack()          != LIBRAW_SUCCESS) return nullptr;
        if (proc.dcraw_process()   != LIBRAW_SUCCESS) return nullptr;

        int err = 0;
        libraw_processed_image_t* img = proc.dcraw_make_mem_image(&err);
        if (!img || err != LIBRAW_SUCCESS) return nullptr;

        *out_w = img->width;
        *out_h = img->height;

        // img->data is uint16_t RGB when output_bps=16
        uint16_t* result = (uint16_t*)std::malloc(img->data_size);
        if (result) std::memcpy(result, img->data, img->data_size);

        LibRaw::dcraw_clear_mem(img);
        return result;
    } catch (...) {
        return nullptr;
    }
}

void libraw_free(void* ptr) {
    std::free(ptr);
}

} // extern "C"
