cmake_minimum_required(VERSION 3.14)
project(ImageSquoosherNativeTests LANGUAGES CXX)

enable_testing()
add_executable(shell_integration_test
  shell_integration_test.cpp
  ../runner/shell_integration.cpp
)
target_compile_features(shell_integration_test PRIVATE cxx_std_17)
target_compile_options(shell_integration_test PRIVATE /W4 /WX /utf-8)
target_compile_definitions(shell_integration_test PRIVATE UNICODE _UNICODE NOMINMAX)
target_link_libraries(shell_integration_test PRIVATE shell32 advapi32 ole32 windowscodecs)
add_test(NAME shell_integration COMMAND shell_integration_test)
