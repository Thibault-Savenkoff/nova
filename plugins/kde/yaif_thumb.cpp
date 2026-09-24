// Thumbnail creator for Dolphin and the other KIO file views (Plasma 6): KDE's own image
// thumbnailer has a fixed list of MIME types, which no image format plugin can extend, so
// image/x-yaif needs this one. The decoding is the Qt plugin's (plugins/qt), through QImageReader.
#include <KIO/ThumbnailCreator>
#include <KPluginFactory>
#include <QImage>
#include <QImageReader>

class YaifThumbnail : public KIO::ThumbnailCreator {
  Q_OBJECT
public:
  YaifThumbnail(QObject *parent, const QVariantList &args) : KIO::ThumbnailCreator(parent, args) {}

  KIO::ThumbnailResult create(const KIO::ThumbnailRequest &request) override {
    QImageReader r(request.url().toLocalFile(), "yaif");
    r.setAutoTransform(true);   // EXIF orientation of the source
    const QSize s = r.size();
    if (s.isValid() && !request.targetSize().isEmpty() && (s.width() > request.targetSize().width() || s.height() > request.targetSize().height())) {
      // Scaled while reading: Qt keeps the aspect ratio itself only for a whole size, so compute it.
      QSize t = s.scaled(request.targetSize(), Qt::KeepAspectRatio);
      if (!t.isEmpty()) r.setScaledSize(t);
    }
    const QImage img = r.read();
    return img.isNull() ? KIO::ThumbnailResult::fail() : KIO::ThumbnailResult::pass(img);
  }
};

K_PLUGIN_CLASS_WITH_JSON(YaifThumbnail, "yaif_thumb.json")

#include "yaif_thumb.moc"
