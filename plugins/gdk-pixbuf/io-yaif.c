/* gdk-pixbuf loader for YAIF (.yaif), on libyaifdec: Eye of GNOME, GIMP (import), GTK apps and
   GNOME thumbnails (gdk-pixbuf-thumbnailer). EXIF orientation is passed as the "orientation" option
   (gdk_pixbuf_apply_embedded_orientation). RAW files give their embedded 512 px preview.
   ponytail: animations give their first frame; add a GdkPixbufAnimation if a GTK viewer needs them. */
#include <stdlib.h>
#include <string.h>
#define GDK_PIXBUF_ENABLE_BACKEND
#include <gdk-pixbuf/gdk-pixbuf-io.h>
#include "yaifdec.h"

typedef struct {
  GdkPixbufModuleSizeFunc size_func;
  GdkPixbufModulePreparedFunc prepared_func;
  GdkPixbufModuleUpdatedFunc updated_func;
  gpointer user_data;
  GByteArray *data;
} YaifContext;

static void free_pixels(guchar *px, gpointer data) { (void)data; free(px); }

static GdkPixbuf *decode(const guint8 *d, gsize n, YaifContext *ctx, GError **error) {
  yaif_info info;
  uint8_t *px = NULL;
  int w, h, alpha, sw = 0, sh = 0;
  GdkPixbuf *pb;
  char o[2] = { 0, 0 };
  if (yaif_read_info(d, n, &info)) {
    g_set_error(error, GDK_PIXBUF_ERROR, GDK_PIXBUF_ERROR_CORRUPT_IMAGE, "YAIF: %s", info.error);
    return NULL;
  }
  w = info.width; h = info.height;
  if (ctx && ctx->size_func) {
    sw = w; sh = h;
    ctx->size_func(&sw, &sh, ctx->user_data);
    if (sw == 0 || sh == 0) return NULL;   /* only the size was wanted */
  }
  if (info.raw) px = yaif_decode_preview(d, n, &w, &h);
  else {
    /* A small enough requested size (a thumbnail) is served from the PREV thumbnail: ~50x faster. */
    if (info.has_preview && info.frames == 1 && sw > 0 && (sw < w || sh < h)) {
      px = yaif_decode_preview(d, n, &w, &h);
      if (px && (w < sw || h < sh)) { free(px); px = NULL; w = info.width; h = info.height; }
    }
    if (!px) px = yaif_decode(d, n, &info);
  }
  if (!px) {
    g_set_error(error, GDK_PIXBUF_ERROR, GDK_PIXBUF_ERROR_CORRUPT_IMAGE, "YAIF: %s", info.raw ? "no preview" : info.error);
    return NULL;
  }
  alpha = info.planes == 4;
  if (!alpha) {   /* RGBA -> RGB in place: gdk-pixbuf wants 3 channels without alpha */
    size_t i, np = (size_t)w * h;
    for (i = 0; i < np; i++) memmove(px + i * 3, px + i * 4, 3);
  }
  pb = gdk_pixbuf_new_from_data(px, GDK_COLORSPACE_RGB, alpha, 8, w, h, w * (alpha ? 4 : 3), free_pixels, NULL);
  if (!pb) { free(px); g_set_error(error, GDK_PIXBUF_ERROR, GDK_PIXBUF_ERROR_INSUFFICIENT_MEMORY, "YAIF: out of memory"); return NULL; }
  if (info.orientation > 1) {
    o[0] = (char)('0' + info.orientation);
    gdk_pixbuf_set_option(pb, "orientation", o);
  }
  return pb;
}

static GdkPixbuf *yaif_load(FILE *f, GError **error) {
  GByteArray *a = g_byte_array_new();
  guint8 buf[65536];
  size_t r;
  GdkPixbuf *pb;
  while ((r = fread(buf, 1, sizeof buf, f)) > 0) g_byte_array_append(a, buf, (guint)r);
  pb = decode(a->data, a->len, NULL, error);
  g_byte_array_free(a, TRUE);
  return pb;
}

static gpointer begin_load(GdkPixbufModuleSizeFunc size_func, GdkPixbufModulePreparedFunc prepared_func,
                           GdkPixbufModuleUpdatedFunc updated_func, gpointer user_data, GError **error) {
  YaifContext *ctx = g_new0(YaifContext, 1);
  (void)error;
  ctx->size_func = size_func;
  ctx->prepared_func = prepared_func;
  ctx->updated_func = updated_func;
  ctx->user_data = user_data;
  ctx->data = g_byte_array_new();
  return ctx;
}

static gboolean load_increment(gpointer data, const guchar *buf, guint size, GError **error) {
  YaifContext *ctx = data;
  (void)error;
  g_byte_array_append(ctx->data, buf, size);
  return TRUE;
}

static gboolean stop_load(gpointer data, GError **error) {
  YaifContext *ctx = data;
  GdkPixbuf *pb = decode(ctx->data->data, ctx->data->len, ctx, error);
  gboolean ok = pb != NULL || (error && !*error);
  if (pb) {
    if (ctx->prepared_func) ctx->prepared_func(pb, NULL, ctx->user_data);
    if (ctx->updated_func) ctx->updated_func(pb, 0, 0, gdk_pixbuf_get_width(pb), gdk_pixbuf_get_height(pb), ctx->user_data);
    g_object_unref(pb);
  }
  g_byte_array_free(ctx->data, TRUE);
  g_free(ctx);
  return ok;
}

G_MODULE_EXPORT void fill_vtable(GdkPixbufModule *module);
G_MODULE_EXPORT void fill_info(GdkPixbufFormat *info);

G_MODULE_EXPORT void fill_vtable(GdkPixbufModule *module) {
  module->load = yaif_load;
  module->begin_load = begin_load;
  module->load_increment = load_increment;
  module->stop_load = stop_load;
}

G_MODULE_EXPORT void fill_info(GdkPixbufFormat *info) {
  static GdkPixbufModulePattern signature[] = { { "\x89YAIF\r\n\x1a\n", NULL, 100 }, { NULL, NULL, 0 } };
  static gchar *mime_types[] = { "image/x-yaif", NULL };
  static gchar *extensions[] = { "yaif", NULL };
  info->name = "yaif";
  info->signature = signature;
  info->description = "YAIF image";
  info->mime_types = mime_types;
  info->extensions = extensions;
  info->flags = GDK_PIXBUF_FORMAT_THREADSAFE;
  info->license = "MIT";
}
