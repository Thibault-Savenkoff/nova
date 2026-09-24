/* libyaifdec: a small YAIF v2 image decoder in C99, without dependencies, for image viewer plugins.
   Levels 0-5 (every non-RAW .yaif): same pixels as `yaif decode`, bit for bit (test/libyaif.sh).
   RAW files (level 6) are not decoded: use yaif_decode_preview (their PREV thumbnail).
   Thread-safe: each call has its own state. Format: FORMAT.md. */
#ifndef YAIFDEC_H
#define YAIFDEC_H
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
  int width, height;     /* pixels */
  int planes;            /* 3 RGB, 4 RGBA (1: RAW sensor frame) */
  int frames;            /* 1, or the frame count of an animation */
  int delay;             /* ms between frames of an animation */
  int raw;               /* 1: RAW sensor frame (only the preview can be decoded) */
  int has_preview;       /* 1: a PREV thumbnail is present */
  int orientation;       /* EXIF orientation 1-8 (1: as stored); apply it when showing the image */
  const char *error;     /* set when a call fails */
} yaif_info;

/* 1 if d starts with the YAIF signature (enough bytes: 9). */
int yaif_check(const uint8_t *d, size_t n);

/* Reads the header and chunk list (fast, no pixel decoding). Returns 0, or -1 (info->error). */
int yaif_read_info(const uint8_t *d, size_t n, yaif_info *info);

/* Decodes every frame: info->frames x width x height x 4 bytes of RGBA (not premultiplied, frames one
   after the other; RGB images have alpha 255). malloc'ed: free() it. NULL on error (info->error). */
uint8_t *yaif_decode(const uint8_t *d, size_t n, yaif_info *info);

/* Decodes the PREV thumbnail (512 px long side): w x h x 4 RGBA, malloc'ed. NULL if absent or bad. */
uint8_t *yaif_decode_preview(const uint8_t *d, size_t n, int *w, int *h);

/* ICC profile of the source (JPEG/HEIC: MDAT APP2 ICC_PROFILE segments joined; PNG: MDAT iCCP,
   inflated), *len bytes, malloc'ed: free() it. NULL if there is none or it is corrupt. */
uint8_t *yaif_icc(const uint8_t *d, size_t n, size_t *len);

#ifdef __cplusplus
}
#endif
#endif
