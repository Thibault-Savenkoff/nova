# KIO thumbnail creator for .nova (Dolphin and the other Plasma 6 file views).
# Build: cmake -S plugins/kde -B build-kde && cmake --build build-kde && sudo cmake --install build-kde
# Needs the Qt plugin (plugins/qt) installed: this one only asks QImageReader for the image.
cmake_minimum_required(VERSION 3.16)
project(novathumb LANGUAGES CXX)
find_package(Qt6 REQUIRED COMPONENTS Core Gui)
find_package(KF6KIO REQUIRED)
set(CMAKE_AUTOMOC ON)
add_library(novathumb MODULE nova_thumb.cpp)
target_link_libraries(novathumb PRIVATE Qt6::Core Qt6::Gui KF6::KIOGui)
set_target_properties(novathumb PROPERTIES CXX_STANDARD 17)
# Absolute Qt plugin directory: with the default prefix the file would land in /usr/local, which Qt does not scan.
install(TARGETS novathumb LIBRARY DESTINATION ${QT6_INSTALL_PREFIX}/${QT6_INSTALL_PLUGINS}/kf6/thumbcreator)
