// WIC codec for .yaif: Windows Explorer thumbnails, Photo Viewer, Paint, XnView MP and every app that
// opens images through the Windows Imaging Component. Decodes with libyaifdec.
// Install (administrator): regsvr32 yaif_wic.dll    Remove: regsvr32 /u yaif_wic.dll
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
#include "yaifdec.h"
#include "upright.h"

static const CLSID CLSID_YaifDecoder = {0x9dc17227, 0x1614, 0x4248, {0xbe, 0xd2, 0xbd, 0xe1, 0xf1, 0x36, 0x52, 0x06}};
static const GUID GUID_ContainerYaif = {0x307e9cb1, 0x1596, 0x49c5, {0xb0, 0x6b, 0xb0, 0x2d, 0x05, 0x11, 0xa8, 0x51}};
static const wchar_t *DECODER = L"{9DC17227-1614-4248-BED2-BDE1F1365206}";
static const wchar_t *CONTAINER = L"{307E9CB1-1596-49C5-B06B-B02D0511A851}";
static const wchar_t *BGRA = L"{6FDDC324-4E03-4BFE-B185-3D77768DC90F}";  // GUID_WICPixelFormat32bppBGRA
static const wchar_t *DECODERS = L"{7ED96837-96F0-4812-B211-F13C24117ED3}"; // CATID_WICBitmapDecoders
static const wchar_t *THUMBS = L"{E357FCCD-A995-4576-B01F-234630154E96}";   // IThumbnailProvider
static const wchar_t *PHOTO_THUMBS = L"{C7657C4A-9F68-40FA-A4DF-96BC08EB3551}"; // Windows photo thumbnail provider
// Double-click: Windows Photo Viewer (still in Windows 11, decodes through WIC, so through this codec).
// Photos (the Store app) opens .yaif blank: it does not use third-party codecs.
static const wchar_t *VIEW = L"%SystemRoot%\\System32\\rundll32.exe \"%ProgramFiles%\\Windows Photo Viewer\\PhotoViewer.dll\", ImageView_Fullscreen %1";
static const uint8_t SIG[9] = {0x89, 'Y', 'A', 'I', 'F', 0x0D, 0x0A, 0x1A, 0x0A};

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
  yaif_info info{};
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
      rgba = yaif_decode_preview(file.data(), file.size(), &sw, &sh);
      n = 1;
    } else {
      rgba = yaif_decode(file.data(), file.size(), &info);
    }
    if (!rgba) return decoded = WINCODEC_ERR_BADIMAGE;
    size_t size = size_t(sw) * sh * 4;
    px.resize(size * n);
    for (int i = 0; i < n; i++) yaif_upright_bgra(rgba + size * i, sw, sh, info.orientation, px.data() + size * i, &w, &h);
    free(rgba);
    return decoded = S_OK;
  }
};

static HRESULT factory(IWICImagingFactory **f) {
  return CoCreateInstance(CLSID_WICImagingFactory, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(f));
}

struct YaifFrame : IWICBitmapFrameDecode {
  COM_REFCOUNT
  std::shared_ptr<Image> img;
  UINT index;
  YaifFrame(std::shared_ptr<Image> i, UINT n) : img(std::move(i)), index(n) { InterlockedIncrement(&g_objects); }
  virtual ~YaifFrame() { InterlockedDecrement(&g_objects); }

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
    uint8_t *rgba = img->info.has_preview ? yaif_decode_preview(img->file.data(), img->file.size(), &w, &h) : nullptr;
    if (!rgba) return WINCODEC_ERR_CODECNOTHUMBNAIL;
    auto t = std::make_shared<Image>();  // an already decoded one-frame image
    t->px.resize(size_t(w) * h * 4);
    yaif_upright_bgra(rgba, w, h, img->info.orientation, t->px.data(), &t->w, &t->h);
    free(rgba);
    t->decoded = S_OK;
    *out = new (std::nothrow) YaifFrame(t, 0);
    return *out ? S_OK : E_OUTOFMEMORY;
  }
};

struct YaifDecoder : IWICBitmapDecoder {
  COM_REFCOUNT
  std::shared_ptr<Image> img;
  YaifDecoder() { InterlockedIncrement(&g_objects); }
  virtual ~YaifDecoder() { InterlockedDecrement(&g_objects); }

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
    *cap = got == 9 && yaif_check(head, 9) ? WICBitmapDecoderCapabilityCanDecodeAllImages | WICBitmapDecoderCapabilityCanDecodeThumbnail : 0;
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE Initialize(IStream *s, WICDecodeOptions) override {
    if (!s) return E_INVALIDARG;
    auto i = std::make_shared<Image>();
    uint8_t buf[65536];
    ULONG got;
    // ponytail: .yaif is never embedded in another file, so the image starts at 0 (Wine hands the
    // stream over positioned after the signature it matched)
    LARGE_INTEGER zero = {};
    s->Seek(zero, STREAM_SEEK_SET, nullptr);
    while (SUCCEEDED(s->Read(buf, sizeof buf, &got)) && got) {
      if (i->file.size() > (size_t(1) << 31)) return WINCODEC_ERR_BADIMAGE;
      i->file.insert(i->file.end(), buf, buf + got);
    }
    if (yaif_read_info(i->file.data(), i->file.size(), &i->info)) return WINCODEC_ERR_BADHEADER;
    int w = i->info.width, h = i->info.height;
    if (i->info.raw) {
      uint8_t *p = yaif_decode_preview(i->file.data(), i->file.size(), &w, &h);
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
    *g = GUID_ContainerYaif;
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE GetDecoderInfo(IWICBitmapDecoderInfo **out) override {
    if (!out) return E_INVALIDARG;
    IWICImagingFactory *f;
    HRESULT hr = factory(&f);
    if (FAILED(hr)) return hr;
    IWICComponentInfo *c;
    hr = f->CreateComponentInfo(CLSID_YaifDecoder, &c);
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
    *out = new (std::nothrow) YaifFrame(img, i);
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
    YaifDecoder *d = new (std::nothrow) YaifDecoder;
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
  if (clsid != CLSID_YaifDecoder) return CLASS_E_CLASSNOTAVAILABLE;
  return g_factory.QueryInterface(iid, out);
}

STDAPI DllCanUnloadNow() { return g_objects ? S_FALSE : S_OK; }

// Registry: a WIC decoder (HKCR\CLSID\{decoder} + the decoders category) and the .yaif type,
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
  bool ok = str(k, nullptr, L"YAIF Decoder") && str(k, L"FriendlyName", L"YAIF Decoder") && str(k, L"Author", L"YAIF") &&
            str(k, L"Vendor", CONTAINER) && str(k, L"Version", L"2.0.0") && str(k, L"ContainerFormat", CONTAINER) &&
            str(k, L"FileExtensions", L".yaif") && str(k, L"MimeTypes", L"image/x-yaif") && dword(k, L"SupportsAnimation", 1) &&
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
  ok = ok && str(cat, L"CLSID", DECODER) && str(cat, L"FriendlyName", L"YAIF Decoder");
  wsprintfW(sub, L".yaif\\ShellEx\\%s", THUMBS);
  ok = ok && str(L".yaif", L"Content Type", L"image/x-yaif") && str(L".yaif", L"PerceivedType", L"image") && str(sub, nullptr, PHOTO_THUMBS);
  // YAIF.Image: name, icon (this DLL's) and Photo Viewer as the program; the default for .yaif
  wchar_t icon[MAX_PATH + 4];
  wsprintfW(icon, L"%s,0", dll);
  ok = ok && str(L"YAIF.Image", nullptr, L"YAIF image") && str(L"YAIF.Image\\DefaultIcon", nullptr, icon) &&
       set(HKEY_CLASSES_ROOT, L"YAIF.Image\\shell\\open\\command", nullptr, REG_EXPAND_SZ, VIEW, DWORD((wcslen(VIEW) + 1) * sizeof(wchar_t))) &&
       str(L".yaif", nullptr, L"YAIF.Image") && str(L".yaif\\OpenWithProgids", L"YAIF.Image", L"");
  // Explorer lists .yaif as a picture (search, "Kind" column, photo views)
  const wchar_t *kind = L"picture";
  set(HKEY_LOCAL_MACHINE, L"SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Explorer\\KindMap", L".yaif", REG_SZ, kind,
      DWORD((wcslen(kind) + 1) * sizeof(wchar_t)));
  SHChangeNotify(SHCNE_ASSOCCHANGED, SHCNF_IDLIST, nullptr, nullptr);
  return ok ? S_OK : SELFREG_E_CLASS;
}

// MSI custom action (win/yaif.wxs): tells Explorer the file types changed, as DllRegisterServer does.
extern "C" UINT __stdcall Refresh(unsigned long) {
  SHChangeNotify(SHCNE_ASSOCCHANGED, SHCNF_IDLIST, nullptr, nullptr);
  return 0;
}

STDAPI DllUnregisterServer() {
  wchar_t k[256];
  wsprintfW(k, L"CLSID\\%s", DECODER);
  RegDeleteTreeW(HKEY_CLASSES_ROOT, k);
  wsprintfW(k, L"CLSID\\%s\\Instance\\%s", DECODERS, DECODER);
  RegDeleteTreeW(HKEY_CLASSES_ROOT, k);
  RegDeleteTreeW(HKEY_CLASSES_ROOT, L".yaif");
  RegDeleteTreeW(HKEY_CLASSES_ROOT, L"YAIF.Image");
  HKEY m;
  if (RegOpenKeyExW(HKEY_LOCAL_MACHINE, L"SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Explorer\\KindMap", 0, KEY_WRITE, &m) == ERROR_SUCCESS) {
    RegDeleteValueW(m, L".yaif");
    RegCloseKey(m);
  }
  SHChangeNotify(SHCNE_ASSOCCHANGED, SHCNF_IDLIST, nullptr, nullptr);
  return S_OK;
}
