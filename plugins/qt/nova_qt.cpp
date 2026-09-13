// Qt 6 image format plugin for NOVA (.nova), on libnovadec. Stills and animations (QMovie,
// Gwenview), EXIF orientation (QImageReader autoTransform), ICC profile of JPEG/HEIC sources.
// Read only. RAW files show their embedded 512 px preview.
#include <QColorSpace>
#include <QImage>
#include <QImageIOHandler>
#include <QImageIOPlugin>
#include <QVariant>
#include <vector>
#include "novadec.h"

class NovaHandler : public QImageIOHandler {
public:
  bool canRead() const override {
    if (!device()) return false;
    if (!NovaHandler::canRead(device())) return false;
    setFormat("nova");
    return true;
  }

  static bool canRead(QIODevice *d) {
    const QByteArray h = d->peek(9);
    return nova_check(reinterpret_cast<const uint8_t *>(h.constData()), size_t(h.size()));
  }

  bool read(QImage *image) override {
    if (!load() || frame >= int(frames.size())) return false;
    *image = frames[frame];
    frame++;
    return true;
  }

  bool supportsOption(ImageOption o) const override {
    return o == Size || o == ImageFormat || o == Animation || o == ImageTransformation;
  }

  QVariant option(ImageOption o) const override {
    if (!const_cast<NovaHandler *>(this)->readInfo()) return {};
    switch (o) {
    case Size: return QSize(info.raw ? pw : info.width, info.raw ? ph : info.height);
    case ImageFormat: return info.planes == 4 ? QImage::Format_RGBA8888 : QImage::Format_RGBX8888;
    case Animation: return info.frames > 1;
    case ImageTransformation: return int(transform(info.orientation));
    default: return {};
    }
  }

  int imageCount() const override { return const_cast<NovaHandler *>(this)->readInfo() ? info.frames : 0; }
  int loopCount() const override { return -1; }   // forever (ANIM loop count is 0 in every file nova writes)
  int nextImageDelay() const override { return const_cast<NovaHandler *>(this)->readInfo() ? info.delay : 0; }
  int currentImageNumber() const override { return frame; }
  bool jumpToImage(int n) override { if (n < 0 || n >= imageCount()) return false; frame = n; return true; }
  bool jumpToNextImage() override { return jumpToImage(frame + 1); }

private:
  QByteArray data;
  nova_info info {};
  int pw = 0, ph = 0, frame = 0;
  bool infoOk = false, loaded = false;
  std::vector<QImage> frames;

  bool readInfo() {
    if (infoOk) return true;
    if (!device()) return false;
    data = device()->readAll();
    auto d = reinterpret_cast<const uint8_t *>(data.constData());
    if (nova_read_info(d, size_t(data.size()), &info)) return false;
    if (info.raw) {   // RAW sensor frame: the preview is what can be shown
      uint8_t *p = nova_decode_preview(d, size_t(data.size()), &pw, &ph);
      if (!p) return false;
      frames.emplace_back(QImage(p, pw, ph, pw * 4, QImage::Format_RGBX8888, free, p));
      info.frames = 1;
      loaded = true;
    }
    infoOk = true;
    return true;
  }

  bool load() {
    if (!readInfo()) return false;
    if (loaded) return !frames.empty();
    loaded = true;
    auto d = reinterpret_cast<const uint8_t *>(data.constData());
    uint8_t *px = nova_decode(d, size_t(data.size()), &info);
    if (!px) return false;
    const size_t fs = size_t(info.width) * info.height * 4;
    QColorSpace cs;
    size_t n = 0;
    if (const uint8_t *icc = nova_icc(d, size_t(data.size()), &n))
      cs = QColorSpace::fromIccProfile(QByteArray(reinterpret_cast<const char *>(icc), qsizetype(n)));
    const auto fmt = info.planes == 4 ? QImage::Format_RGBA8888 : QImage::Format_RGBX8888;
    for (int i = 0; i < info.frames; i++) {
      QImage im(px + fs * i, info.width, info.height, info.width * 4, fmt);
      frames.push_back(im.copy());   // own the pixels: px is freed below
      if (cs.isValid()) frames.back().setColorSpace(cs);
    }
    free(px);
    return true;
  }

  static QImageIOHandler::Transformations transform(int o) {
    switch (o) {
    case 2: return TransformationMirror;
    case 3: return TransformationRotate180;
    case 4: return TransformationFlip;
    case 5: return TransformationFlipAndRotate90;
    case 6: return TransformationRotate90;
    case 7: return TransformationMirrorAndRotate90;
    case 8: return TransformationRotate270;
    default: return TransformationNone;
    }
  }
};

class NovaPlugin : public QImageIOPlugin {
  Q_OBJECT
  Q_PLUGIN_METADATA(IID QImageIOHandlerFactoryInterface_iid FILE "nova.json")
public:
  Capabilities capabilities(QIODevice *device, const QByteArray &format) const override {
    if (format == "nova") return CanRead;
    if (!format.isEmpty() || !device || !device->isOpen()) return {};
    return NovaHandler::canRead(device) ? CanRead : Capabilities();
  }
  QImageIOHandler *create(QIODevice *device, const QByteArray &format) const override {
    auto h = new NovaHandler;
    h->setDevice(device);
    Q_UNUSED(format);  // always "nova" (set by NovaHandler), even when detected from the content
    return h;
  }
};

#include "nova_qt.moc"
