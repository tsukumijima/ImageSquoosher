#ifndef IMAGE_SQUOOSHER_SHELL_EXTENSION_H_
#define IMAGE_SQUOOSHER_SHELL_EXTENSION_H_

#include <guiddef.h>

namespace image_squoosher::shell_extension {

inline constexpr CLSID kExplorerCommandCLSID = {
    0x899d9bf0,
    0x62f9,
    0x49ac,
    {0xb5, 0x92, 0x01, 0xee, 0xe3, 0xc8, 0xcf, 0x27},
};

}  // namespace image_squoosher::shell_extension

#endif
