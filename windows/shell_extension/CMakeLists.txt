cmake_minimum_required(VERSION 3.14)
project(ImageSquoosherShellExtension LANGUAGES CXX)

add_library(ImageSquoosherShell SHARED
  shell_extension.cpp
  shell_extension.def
)
target_compile_features(ImageSquoosherShell PRIVATE cxx_std_17)
# WRL の静的モジュール格納型に必要なパディングは SDK 内部に限定し、製品コードでは /W4 /WX を維持する
target_compile_options(ImageSquoosherShell PRIVATE
  /W4
  /WX
  /utf-8
  /permissive-
  /wd4324
)
target_compile_definitions(ImageSquoosherShell PRIVATE
  UNICODE
  _UNICODE
  NOMINMAX
  WIN32_LEAN_AND_MEAN
)
target_link_libraries(ImageSquoosherShell PRIVATE
  advapi32
  ole32
  runtimeobject
  shell32
  shlwapi
)
set_target_properties(ImageSquoosherShell PROPERTIES
  OUTPUT_NAME "ImageSquoosherShell"
)

# 単独構成時だけ実 COM 境界のテスト一式を用意し、Flutter の通常ビルドは製品ターゲットだけで構成する
if(CMAKE_SOURCE_DIR STREQUAL CMAKE_CURRENT_SOURCE_DIR)
  include(CTest)
endif()

if(BUILD_TESTING AND CMAKE_SOURCE_DIR STREQUAL CMAKE_CURRENT_SOURCE_DIR)
  set(SHELL_TEST_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/shell_extension_test")

  add_executable(ImageSquoosherShellTestHost tests/test_host.cpp)
  target_compile_features(ImageSquoosherShellTestHost PRIVATE cxx_std_17)
  target_compile_options(ImageSquoosherShellTestHost PRIVATE /W4 /WX /utf-8)
  target_compile_definitions(ImageSquoosherShellTestHost PRIVATE
    UNICODE
    _UNICODE
    NOMINMAX
    WIN32_LEAN_AND_MEAN
  )
  target_link_libraries(ImageSquoosherShellTestHost PRIVATE shell32)
  set_target_properties(ImageSquoosherShellTestHost PROPERTIES
    OUTPUT_NAME "ImageSquoosher"
    RUNTIME_OUTPUT_DIRECTORY "${SHELL_TEST_OUTPUT_DIRECTORY}"
  )

  add_executable(ImageSquoosherShellTest tests/shell_extension_test.cpp)
  target_compile_features(ImageSquoosherShellTest PRIVATE cxx_std_17)
  target_compile_options(ImageSquoosherShellTest PRIVATE /W4 /WX /utf-8)
  target_compile_definitions(ImageSquoosherShellTest PRIVATE
    UNICODE
    _UNICODE
    NOMINMAX
    WIN32_LEAN_AND_MEAN
  )
  target_include_directories(ImageSquoosherShellTest PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}"
  )
  target_link_libraries(ImageSquoosherShellTest PRIVATE ole32 shell32)
  set_target_properties(ImageSquoosherShellTest PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${SHELL_TEST_OUTPUT_DIRECTORY}"
  )
  set_target_properties(ImageSquoosherShell PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${SHELL_TEST_OUTPUT_DIRECTORY}"
  )
  add_dependencies(ImageSquoosherShellTest
    ImageSquoosherShell
    ImageSquoosherShellTestHost
  )

  add_test(
    NAME ImageSquoosherShellCOM
    COMMAND ImageSquoosherShellTest $<TARGET_FILE:ImageSquoosherShell>
  )
endif()
