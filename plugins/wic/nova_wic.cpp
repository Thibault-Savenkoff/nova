// WIC codec for .nova: Windows Explorer thumbnails, Photos, Paint, XnView MP and every app that
// opens images through the Windows Imaging Component. Decodes with libnovadec.
// Install (administrator): regsvr32 nova_wic.dll    Remove: regsvr32 /u nova_wic.dll
// Pixels are given upright (EXIF orientation applied here) in 32-bit BGRA.
// ponytail: no metadata reader (EXIF, frame delays) and no ICC colour context; add them if an app needs them.
#include <windows.h>
#include <wincodec.h>
#include <shlobj.h>
#include <olectl.h>
#include <memory>
#include <mutex>
#include <new>
#include <vector>
#include "novadec.h"
#include "upright.h"

static const CLSID CLSID_NovaDecoder = {0x40e4326e, 0x629b, 0x488e, {0x8d, 0x94, 0x39, 0x59, 0x49, 0x8e, 0x1a, 0xcd}};
static const GUID GUID_ContainerNova = {0xb4afaa41, 0x52c1, 0x41d0, {0x9f, 0xd4, 0xc7, 0x7e, 0xfe, 0x7b, 0xfe, 0x19}};
static const wchar_t *DECODER = L"{40E4326E-629B-488E-8D94-3959498E1ACD}";
static const wchar_t *CONTAINER = L"{B4AFAA41-52C1-41D0-9FD4-C77EFE7BFE19}";
static const wchar_t *BGRA = L"{6FDDC324-4E03-4BFE-B185-3D77768DC90F}";  // GUID_WICPixelFormat32bppBGRA
static const wchar_t *DECODERS = L"{7ED96837-96F0-4812-B211-F13C24117ED3}"; // CATID_WICBitmapDecoders
static const wchar_t *THUMBS = L"{E357FCCD-A995-4576-B01F-234630154E96}";   // IThumbnailProvider
static const wchar_t *PHOTO_THUMBS = L"{C7657C4A-9F68-40FA-A4DF-96BC08EB3551}"; // Windows photo thumbnail provider
static const uint8_t SIG[9] = {0x89, 'N', 'O', 'V', 'A', 0x0D, 0x0A, 0x1A, 0x0A};

static HMODULE g_module;
static LONG g_objects;

#define COM_REFCOUNT \
  LONG refs = 1; \
  ULONG STDMETHODCALLTYPE AddRef() override { return InterlockedIncrement(&refs); } \
  ULONG STDMETHODCALLTYPE Release() override { \
    LONG n = InterlockedDecrement(&refs); \
    if (!n) delete this; \
    return n; \
  }

// The file and its pixels, shared by the decoder and its frames. Full decoding waits for the
// first CopyPixels: Explorer asks for the size and the thumbnail first.
struct Image {
  std::vector<uint8_t> file;
  nova_info info{};
  int w = 0, h = 0;              // upright size
  std::vector<uint8_t> px;       // frames x w x h BGRA, upright
  std::mutex lock;
  HRESULT decoded = S_FALSE;     // S_FALSE: not yet

  HRESULT decode() {
    std::lock_guard<std::mutex> g(lock);
    if (decoded != S_FALSE) return decoded;
    int sw = info.width, sh = info.height, n = info.frames;
    uint8_t *rgba;
    if (info.raw) {
      rgba = nova_decode_preview(file.data(), file.size(), &sw, &sh);
      n = 1;
    } else {
      rgba = nova_decode(file.data(), file.size(), &info);
    }
    if (!rgba) return decoded = WINCODEC_ERR_BADIMAGE;
    size_t size = size_t(sw) * sh * 4;
    px.resize(size * n);
    for (int i = 0; i < n; i++) nova_upright_bgra(rgba + size * i, sw, sh, info.orientation, px.data() + size * i, &w, &h);
    free(rgba);
    return decoded = S_OK;
  }
};

static HRESULT factory(IWICImagingFactory **f) {
  return CoCreateInstance(CLSID_WICImagingFactory, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(f));
}

struct NovaFrame : IWICBitmapFrameDecode {
  COM_REFCOUNT
  std::shared_ptr<Image> img;
  UINT index;
  NovaFrame(std::shared_ptr<Image> i, UINT n) : img(std::move(i)), index(n) { InterlockedIncrement(&g_objects); }
  virtual ~NovaFrame() { InterlockedDecrement(&g_objects); }

  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid, void **out) override {
    if (!out) return E_POINTER;
    if (iid == IID_IUnknown || iid == IID_IWICBitmapSource || iid == IID_IWICBitmapFrameDecode) {
      *out = static_cast<IWICBitmapFrameDecode *>(this);
      AddRef();
      return S_OK;
    }
    *out = nullptr;
    return E_NOINTERFACE;
  }
  HRESULT STDMETHODCALLTYPE GetSize(UINT *w, UINT *h) override {
    if (!w || !h) return E_INVALIDARG;
    *w = img->w;
    *h = img->h;
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE GetPixelFormat(WICPixelFormatGUID *f) override {
    if (!f) return E_INVALIDARG;
    *f = GUID_WICPixelFormat32bppBGRA;
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE GetResolution(double *x, double *y) override {
    if (!x || !y) return E_INVALIDARG;
    *x = *y = 96.0;
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE CopyPalette(IWICPalette *) override { return WINCODEC_ERR_PALETTEUNAVAILABLE; }
  HRESULT STDMETHODCALLTYPE CopyPixels(const WICRect *r, UINT stride, UINT size, BYTE *out) override {
    if (!out) return E_INVALIDARG;
    HRESULT hr = img->decode();
    if (FAILED(hr)) return hr;
    WICRect all = {0, 0, img->w, img->h};
    if (!r) r = &all;
    if (r->X < 0 || r->Y < 0 || r->Width < 0 || r->Height < 0 || r->X + r->Width > img->w || r->Y + r->Height > img->h) return E_INVALIDARG;
    UINT row = UINT(r->Width) * 4;
    if (stride < row || (r->Height && size < stride * UINT(r->Height - 1) + row)) return WINCODEC_ERR_INSUFFICIENTBUFFER;
    const uint8_t *src = img->px.data() + size_t(img->w) * img->h * 4 * index;
    for (int y = 0; y < r->Height; y++) memcpy(out + size_t(stride) * y, src + (size_t(r->Y + y) * img->w + r->X) * 4, row);
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE GetMetadataQueryReader(IWICMetadataQueryReader **) override { return WINCODEC_ERR_UNSUPPORTEDOPERATION; }
  HRESULT STDMETHODCALLTYPE GetColorContexts(UINT, IWICColorContext **, UINT *n) override {
    if (!n) return E_INVALIDARG;
    *n = 0;
    return S_OK;
  }
  // The PREV chunk (512 px), for quick thumbnails of big photos.
  HRESULT STDMETHODCALLTYPE GetThumbnail(IWICBitmapSource **out) override {
    if (!out) return E_INVALIDARG;
    int w, h;
    uint8_t *rgba = img->info.has_preview ? nova_decode_preview(img->file.data(), img->file.size(), &w, &h) : nullptr;
    if (!rgba) return WINCODEC_ERR_CODECNOTHUMBNAIL;
    auto t = std::make_shared<Image>();  // an already decoded one-frame image
    t->px.resize(size_t(w) * h * 4);
    nova_upright_bgra(rgba, w, h, img->info.orientation, t->px.data(), &t->w, &t->h);
    free(rgba);
    t->decoded = S_OK;
    *out = new (std::nothrow) NovaFrame(t, 0);
    return *out ? S_OK : E_OUTOFMEMORY;
  }
};

struct NovaDecoder : IWICBitmapDecoder {
  COM_REFCOUNT
  std::shared_ptr<Image> img;
  NovaDecoder() { InterlockedIncrement(&g_objects); }
  virtual ~NovaDecoder() { InterlockedDecrement(&g_objects); }

  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid, void **out) override {
    if (!out) return E_POINTER;
    if (iid == IID_IUnknown || iid == IID_IWICBitmapDecoder) {
      *out = static_cast<IWICBitmapDecoder *>(this);
      AddRef();
      return S_OK;
    }
    *out = nullptr;
    return E_NOINTERFACE;
  }
  HRESULT STDMETHODCALLTYPE QueryCapability(IStream *s, DWORD *cap) override {
    if (!s || !cap) return E_INVALIDARG;
    LARGE_INTEGER zero = {};
    ULARGE_INTEGER pos;
    HRESULT hr = s->Seek(zero, STREAM_SEEK_CUR, &pos);
    if (FAILED(hr)) return hr;
    uint8_t head[9];
    ULONG got = 0;
    s->Read(head, 9, &got);
    LARGE_INTEGER back;
    back.QuadPart = LONGLONG(pos.QuadPart);
    s->Seek(back, STREAM_SEEK_SET, nullptr);
    *cap = got == 9 && nova_check(head, 9) ? WICBitmapDecoderCapabilityCanDecodeAllImages | WICBitmapDecoderCapabilityCanDecodeThumbnail : 0;
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE Initialize(IStream *s, WICDecodeOptions) override {
    if (!s) return E_INVALIDARG;
    auto i = std::make_shared<Image>();
    uint8_t buf[65536];
    ULONG got;
    // ponytail: .nova is never embedded in another file, so the image starts at 0 (Wine hands the
    // stream over positioned after the signature it matched)
    LARGE_INTEGER zero = {};
    s->Seek(zero, STREAM_SEEK_SET, nullptr);
    while (SUCCEEDED(s->Read(buf, sizeof buf, &got)) && got) {
      if (i->file.size() > (size_t(1) << 31)) return WINCODEC_ERR_BADIMAGE;
      i->file.insert(i->file.end(), buf, buf + got);
    }
    if (nova_read_info(i->file.data(), i->file.size(), &i->info)) return WINCODEC_ERR_BADHEADER;
    int w = i->info.width, h = i->info.height;
    if (i->info.raw) {
      uint8_t *p = nova_decode_preview(i->file.data(), i->file.size(), &w, &h);
      if (!p) return WINCODEC_ERR_BADIMAGE;
      free(p);
    }
    bool swap = i->info.orientation >= 5 && i->info.orientation <= 8;
    i->w = swap ? h : w;
    i->h = swap ? w : h;
    img = i;
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE GetContainerFormat(GUID *g) override {
    if (!g) return E_INVALIDARG;
    *g = GUID_ContainerNova;
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE GetDecoderInfo(IWICBitmapDecoderInfo **out) override {
    if (!out) return E_INVALIDARG;
    IWICImagingFactory *f;
    HRESULT hr = factory(&f);
    if (FAILED(hr)) return hr;
    IWICComponentInfo *c;
    hr = f->CreateComponentInfo(CLSID_NovaDecoder, &c);
    f->Release();
    if (FAILED(hr)) return hr;
    hr = c->QueryInterface(IID_PPV_ARGS(out));
    c->Release();
    return hr;
  }
  HRESULT STDMETHODCALLTYPE CopyPalette(IWICPalette *) override { return WINCODEC_ERR_PALETTEUNAVAILABLE; }
  HRESULT STDMETHODCALLTYPE GetMetadataQueryReader(IWICMetadataQueryReader **) override { return WINCODEC_ERR_UNSUPPORTEDOPERATION; }
  HRESULT STDMETHODCALLTYPE GetPreview(IWICBitmapSource **) override { return WINCODEC_ERR_UNSUPPORTEDOPERATION; }
  HRESULT STDMETHODCALLTYPE GetColorContexts(UINT, IWICColorContext **, UINT *n) override {
    if (!n) return E_INVALIDARG;
    *n = 0;
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE GetThumbnail(IWICBitmapSource **) override { return WINCODEC_ERR_CODECNOTHUMBNAIL; }
  HRESULT STDMETHODCALLTYPE GetFrameCount(UINT *n) override {
    if (!n) return E_INVALIDARG;
    if (!img) return WINCODEC_ERR_NOTINITIALIZED;
    *n = img->info.raw ? 1 : UINT(img->info.frames);
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE GetFrame(UINT i, IWICBitmapFrameDecode **out) override {
    if (!out) return E_INVALIDARG;
    if (!img) return WINCODEC_ERR_NOTINITIALIZED;
    UINT n;
    GetFrameCount(&n);
    if (i >= n) return WINCODEC_ERR_FRAMEMISSING;
    *out = new (std::nothrow) NovaFrame(img, i);
    return *out ? S_OK : E_OUTOFMEMORY;
  }
};

struct Factory : IClassFactory {
  ULONG STDMETHODCALLTYPE AddRef() override { return 2; }
  ULONG STDMETHODCALLTYPE Release() override { return 1; }
  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid, void **out) override {
    if (!out) return E_POINTER;
    if (iid == IID_IUnknown || iid == IID_IClassFactory) {
      *out = static_cast<IClassFactory *>(this);
      return S_OK;
    }
    *out = nullptr;
    return E_NOINTERFACE;
  }
  HRESULT STDMETHODCALLTYPE CreateInstance(IUnknown *outer, REFIID iid, void **out) override {
    if (!out) return E_POINTER;
    *out = nullptr;
    if (outer) return CLASS_E_NOAGGREGATION;
    NovaDecoder *d = new (std::nothrow) NovaDecoder;
    if (!d) return E_OUTOFMEMORY;
    HRESULT hr = d->QueryInterface(iid, out);
    d->Release();
    return hr;
  }
  HRESULT STDMETHODCALLTYPE LockServer(BOOL lock) override {
    lock ? InterlockedIncrement(&g_objects) : InterlockedDecrement(&g_objects);
    return S_OK;
  }
};
static Factory g_factory;

extern "C" BOOL WINAPI DllMain(HINSTANCE h, DWORD reason, LPVOID) {
  if (reason == DLL_PROCESS_ATTACH) {
    g_module = h;
    DisableThreadLibraryCalls(h);
  }
  return TRUE;
}

STDAPI DllGetClassObject(REFCLSID clsid, REFIID iid, void **out) {
  if (clsid != CLSID_NovaDecoder) return CLASS_E_CLASSNOTAVAILABLE;
  return g_factory.QueryInterface(iid, out);
}

STDAPI DllCanUnloadNow() { return g_objects ? S_FALSE : S_OK; }

// Registry: a WIC decoder (HKCR\CLSID\{decoder} + the decoders category) and the .nova type,
// with Windows' photo thumbnail provider (which then uses this decoder).
static bool set(HKEY root, const wchar_t *path, const wchar_t *name, DWORD type, const void *data, DWORD n) {
  HKEY k;
  if (RegCreateKeyExW(root, path, 0, nullptr, 0, KEY_WRITE, nullptr, &k, nullptr) != ERROR_SUCCESS) return false;
  bool ok = RegSetValueExW(k, name, 0, type, static_cast<const BYTE *>(data), n) == ERROR_SUCCESS;
  RegCloseKey(k);
  return ok;
}
static bool str(const wchar_t *path, const wchar_t *name, const wchar_t *v) {
  return set(HKEY_CLASSES_ROOT, path, name, REG_SZ, v, DWORD((wcslen(v) + 1) * sizeof(wchar_t)));
}
static bool dword(const wchar_t *path, const wchar_t *name, DWORD v) { return set(HKEY_CLASSES_ROOT, path, name, REG_DWORD, &v, 4); }

STDAPI DllRegisterServer() {
  wchar_t dll[MAX_PATH], k[256], cat[256];
  if (!GetModuleFileNameW(g_module, dll, MAX_PATH)) return SELFREG_E_CLASS;
  wsprintfW(k, L"CLSID\\%s", DECODER);
  wsprintfW(cat, L"CLSID\\%s\\Instance\\%s", DECODERS, DECODER);
  wchar_t sub[256];
  bool ok = str(k, nullptr, L"NOVA Decoder") && str(k, L"FriendlyName", L"NOVA Decoder") && str(k, L"Author", L"NOVA") &&
            str(k, L"Vendor", CONTAINER) && str(k, L"Version", L"2.0.0") && str(k, L"ContainerFormat", CONTAINER) &&
            str(k, L"FileExtensions", L".nova") && str(k, L"MimeTypes", L"image/x-nova") && dword(k, L"SupportsAnimation", 1) &&
            dword(k, L"SupportsMultiframe", 1) && dword(k, L"SupportsLossless", 1) && dword(k, L"SupportsChromakey", 0) &&
            dword(k, L"ArbitrationPriority", 10);
  wsprintfW(sub, L"%s\\InprocServer32", k);
  ok = ok && str(sub, nullptr, dll) && str(sub, L"ThreadingModel", L"Both");
  wsprintfW(sub, L"%s\\Formats\\%s", k, BGRA);
  ok = ok && str(sub, nullptr, L"");
  wsprintfW(sub, L"%s\\Patterns\\0", k);
  static const uint8_t mask[9] = {0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff};
  ok = ok && dword(sub, L"Position", 0) && dword(sub, L"Length", 9) && set(HKEY_CLASSES_ROOT, sub, L"Pattern", REG_BINARY, SIG, 9) &&
       set(HKEY_CLASSES_ROOT, sub, L"Mask", REG_BINARY, mask, 9);
  ok = ok && str(cat, L"CLSID", DECODER) && str(cat, L"FriendlyName", L"NOVA Decoder");
  wsprintfW(sub, L".nova\\ShellEx\\%s", THUMBS);
  ok = ok && str(L".nova", L"Content Type", L"image/x-nova") && str(L".nova", L"PerceivedType", L"image") && str(sub, nullptr, PHOTO_THUMBS);
  // Explorer lists .nova as a picture (search, "Kind" column, photo views)
  const wchar_t *kind = L"picture";
  set(HKEY_LOCAL_MACHINE, L"SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Explorer\\KindMap", L".nova", REG_SZ, kind,
      DWORD((wcslen(kind) + 1) * sizeof(wchar_t)));
  SHChangeNotify(SHCNE_ASSOCCHANGED, SHCNF_IDLIST, nullptr, nullptr);
  return ok ? S_OK : SELFREG_E_CLASS;
}

STDAPI DllUnregisterServer() {
  wchar_t k[256];
  wsprintfW(k, L"CLSID\\%s", DECODER);
  RegDeleteTreeW(HKEY_CLASSES_ROOT, k);
  wsprintfW(k, L"CLSID\\%s\\Instance\\%s", DECODERS, DECODER);
  RegDeleteTreeW(HKEY_CLASSES_ROOT, k);
  wsprintfW(k, L".nova\\ShellEx\\%s", THUMBS);
  RegDeleteTreeW(HKEY_CLASSES_ROOT, k);
  HKEY m;
  if (RegOpenKeyExW(HKEY_LOCAL_MACHINE, L"SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Explorer\\KindMap", 0, KEY_WRITE, &m) == ERROR_SUCCESS) {
    RegDeleteValueW(m, L".nova");
    RegCloseKey(m);
  }
  SHChangeNotify(SHCNE_ASSOCCHANGED, SHCNF_IDLIST, nullptr, nullptr);
  return S_OK;
}
