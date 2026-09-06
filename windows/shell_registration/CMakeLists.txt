cmake_minimum_required(VERSION 3.14)
project(ImageSquoosherShellRegistration LANGUAGES CXX)

add_executable(ImageSquoosherShellRegistration WIN32
  registration_main.cpp
  registration_logic.cpp
  registration.rc
  registration.exe.manifest
)
target_compile_features(ImageSquoosherShellRegistration PRIVATE cxx_std_17)
target_compile_options(ImageSquoosherShellRegistration PRIVATE
  /W4
  /WX
  /EHsc
  /utf-8
  /permissive-
)
target_compile_definitions(ImageSquoosherShellRegistration PRIVATE
  UNICODE
  _UNICODE
  NOMINMAX
  WIN32_LEAN_AND_MEAN
)
target_link_libraries(ImageSquoosherShellRegistration PRIVATE
  advapi32
  ole32
  runtimeobject
  shell32
  shlwapi
)
set_target_properties(ImageSquoosherShellRegistration PROPERTIES
  OUTPUT_NAME "ImageSquoosherShellRegistration"
)

# 配布フォルダをそのまま loose package として登録できるよう、マニフェストとアイコンを実行ファイルの隣へ揃える
add_custom_command(TARGET ImageSquoosherShellRegistration POST_BUILD
  COMMAND ${CMAKE_COMMAND} -E copy_if_different
    "${CMAKE_CURRENT_SOURCE_DIR}/AppxManifest.xml"
    "$<TARGET_FILE_DIR:ImageSquoosherShellRegistration>/AppxManifest.xml"
  COMMAND ${CMAKE_COMMAND} -E copy_if_different
    "${CMAKE_CURRENT_SOURCE_DIR}/../../assets/images/app_icon_1024.png"
    "$<TARGET_FILE_DIR:ImageSquoosherShellRegistration>/app_icon_1024.png"
  VERBATIM
)

# 単独構成では Flutter のビルドを介さず、登録判定と引数境界だけを検証する
if(CMAKE_SOURCE_DIR STREQUAL CMAKE_CURRENT_SOURCE_DIR)
  include(CTest)
endif()

if(BUILD_TESTING AND CMAKE_SOURCE_DIR STREQUAL CMAKE_CURRENT_SOURCE_DIR)
  add_executable(ImageSquoosherShellRegistrationTest
    tests/registration_logic_test.cpp
    registration_logic.cpp
  )
  target_compile_features(ImageSquoosherShellRegistrationTest PRIVATE cxx_std_17)
  target_compile_options(ImageSquoosherShellRegistrationTest PRIVATE
    /W4
    /WX
    /EHsc
    /utf-8
    /permissive-
  )
  target_compile_definitions(ImageSquoosherShellRegistrationTest PRIVATE
    UNICODE
    _UNICODE
    NOMINMAX
    WIN32_LEAN_AND_MEAN
  )
  add_test(NAME shell_registration_logic COMMAND ImageSquoosherShellRegistrationTest)

  add_executable(ImageSquoosherShellRegistrationMutexTest
    tests/mutex_access_test.cpp
  )
  target_compile_features(ImageSquoosherShellRegistrationMutexTest PRIVATE cxx_std_17)
  target_compile_options(ImageSquoosherShellRegistrationMutexTest PRIVATE
    /W4
    /WX
    /EHsc
    /utf-8
    /permissive-
  )
  target_compile_definitions(ImageSquoosherShellRegistrationMutexTest PRIVATE
    UNICODE
    _UNICODE
    NOMINMAX
    WIN32_LEAN_AND_MEAN
  )
  target_link_libraries(ImageSquoosherShellRegistrationMutexTest PRIVATE
    advapi32
  )
  add_test(NAME shell_registration_mutex_access COMMAND ImageSquoosherShellRegistrationMutexTest)
endif()
