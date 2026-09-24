# Qt 6 image format plugin for .yaif (Gwenview, Okular, Krita, Dolphin thumbnails, any Qt app).
# Build: cmake -B build -S plugins/qt && cmake --build build
# Install for this user: see README.md ("Viewer plugins").
cmake_minimum_required(VERSION 3.16)
project(qyaif LANGUAGES C CXX)
find_package(Qt6 REQUIRED COMPONENTS Core Gui)
find_package(Threads REQUIRED)
set(CMAKE_AUTOMOC ON)
add_library(qyaif MODULE yaif_qt.cpp ../../libyaif/yaifdec.c)
target_include_directories(qyaif PRIVATE ../../libyaif)
target_link_libraries(qyaif PRIVATE Qt6::Core Qt6::Gui Threads::Threads)
set_target_properties(qyaif PROPERTIES C_STANDARD 99 CXX_STANDARD 17)
# Absolute Qt plugin directory: with the default prefix the file would land in /usr/local, which Qt does not scan.
install(TARGETS qyaif LIBRARY DESTINATION ${QT6_INSTALL_PREFIX}/${QT6_INSTALL_PLUGINS}/imageformats)
