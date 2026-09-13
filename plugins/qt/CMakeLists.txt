# Qt 6 image format plugin for .nova (Gwenview, Okular, Krita, Dolphin thumbnails, any Qt app).
# Build: cmake -B build -S plugins/qt && cmake --build build
# Install for this user: see README.md ("Viewer plugins").
cmake_minimum_required(VERSION 3.16)
project(qnova LANGUAGES C CXX)
find_package(Qt6 REQUIRED COMPONENTS Core Gui)
find_package(Threads REQUIRED)
set(CMAKE_AUTOMOC ON)
add_library(qnova MODULE nova_qt.cpp ../../libnova/novadec.c)
target_include_directories(qnova PRIVATE ../../libnova)
target_link_libraries(qnova PRIVATE Qt6::Core Qt6::Gui Threads::Threads)
set_target_properties(qnova PROPERTIES C_STANDARD 99 CXX_STANDARD 17)
install(TARGETS qnova LIBRARY DESTINATION ${QT6_INSTALL_PLUGINS}/imageformats)
