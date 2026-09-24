// Qt 6 image format plugin for YAIF (.yaif), on libyaifdec. Stills and animations (QMovie,
// Gwenview), EXIF orientation (QImageReader autoTransform), ICC profile (JPEG, HEIC and PNG sources).
// Read only. RAW files show their embedded 512 px preview.
#include <QColorSpace>
#include <QImage>
#include <QImageIOHandler>
#include <QImageIOPlugin>
#include <QVariant>
#include <cstdlib>
#include <vector>
#include "yaifdec.h"

class YaifHandler : public QImageIOHandler {
public:
  bool canRead() const override {
    if (!device()) return false;
    if (!YaifHandler::canRead(device())) return false;
    setFormat("yaif");
    return true;
  }

  static bool canRead(QIODevice *d) {
    const QByteArray h = d->peek(9);
    return yaif_check(reinterpret_cast<const uint8_t *>(h.constData()), size_t(h.size()));
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
    if (!const_cast<YaifHandler *>(this)->readInfo()) return {};
    switch (o) {
    case Size: return QSize(info.raw ? pw : info.width, info.raw ? ph : info.height);
    case ImageFormat: return info.planes == 4 ? QImage::Format_RGBA8888 : QImage::Format_RGBX8888;
    case Animation: return info.frames > 1;
    case ImageTransformation: return int(transform(info.orientation));
    default: return {};
    }
  }

  int imageCount() const override { return const_cast<YaifHandler *>(this)->readInfo() ? info.frames : 0; }
  int loopCount() const override { return -1; }   // forever (ANIM loop count is 0 in every file yaif writes)
  int nextImageDelay() const override { return const_cast<YaifHandler *>(this)->readInfo() ? info.delay : 0; }
  int currentImageNumber() const override { return frame; }
  bool jumpToImage(int n) override { if (n < 0 || n >= imageCount()) return false; frame = n; return true; }
  bool jumpToNextImage() override { return jumpToImage(frame + 1); }

private:
  QByteArray data;
  yaif_info info {};
  int pw = 0, ph = 0, frame = 0;
  bool infoOk = false, loaded = false;
  std::vector<QImage> frames;

  bool readInfo() {
    if (infoOk) return true;
    if (!device()) return false;
    // The whole file, leaving the device where it was: an option() (size, animation) may be asked
    // during canRead(), and the next reader would then find nothing left (Gwenview reuses it).
    const qint64 pos = device()->pos();
    data = device()->readAll();
    if (data.isEmpty() && device()->seek(0)) data = device()->readAll();
    device()->seek(pos);
    auto d = reinterpret_cast<const uint8_t *>(data.constData());
    if (yaif_read_info(d, size_t(data.size()), &info)) return false;
    if (info.raw) {   // RAW sensor frame: the preview is what can be shown
      uint8_t *p = yaif_decode_preview(d, size_t(data.size()), &pw, &ph);
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
    uint8_t *px = yaif_decode(d, size_t(data.size()), &info);
    if (!px) return false;
    const size_t fs = size_t(info.width) * info.height * 4;
    QColorSpace cs;
    size_t n = 0;
    if (uint8_t *icc = yaif_icc(d, size_t(data.size()), &n)) {
      cs = QColorSpace::fromIccProfile(QByteArray(reinterpret_cast<const char *>(icc), qsizetype(n)));
      free(icc);
    }
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

class YaifPlugin : public QImageIOPlugin {
  Q_OBJECT
  Q_PLUGIN_METADATA(IID QImageIOHandlerFactoryInterface_iid FILE "yaif.json")
public:
  Capabilities capabilities(QIODevice *device, const QByteArray &format) const override {
    if (format == "yaif") return CanRead;
    if (!format.isEmpty() || !device || !device->isOpen()) return {};
    return YaifHandler::canRead(device) ? CanRead : Capabilities();
  }
  QImageIOHandler *create(QIODevice *device, const QByteArray &format) const override {
    auto h = new YaifHandler;
    h->setDevice(device);
    Q_UNUSED(format);  // always "yaif" (set by YaifHandler), even when detected from the content
    return h;
  }
};

#include "yaif_qt.moc"
