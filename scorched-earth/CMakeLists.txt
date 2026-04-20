if(DEFINED ENV{LOGOS_CPP_SDK_ROOT})
    set(LOGOS_CPP_SDK "$ENV{LOGOS_CPP_SDK_ROOT}")
else()
    set(LOGOS_CPP_SDK "/nix/store/k8v22j4ds9vyjj67g6r5i4pvi9an755d-logos-cpp-sdk-headers-0.1.0")
endif()

if(DEFINED ENV{LOGOS_CPP_SDK_LIB})
    set(LOGOS_CPP_SDK_LIB "$ENV{LOGOS_CPP_SDK_LIB}")
else()
    set(LOGOS_CPP_SDK_LIB "/nix/store/ypxadc350lzj0rmic9nr1gl8pldcbs7v-logos-cpp-sdk-lib-0.1.0")
endif()

if(DEFINED ENV{LOGOS_LIBLOGOS_HEADERS})
    set(LOGOS_LIBLOGOS_HEADERS "$ENV{LOGOS_LIBLOGOS_HEADERS}")
else()
    set(LOGOS_LIBLOGOS_HEADERS "/nix/store/8cgbzy0jczrpizyga4i4pfjba77m3k7f-logos-liblogos-headers-0.1.0/include")
endif()

set(PLUGIN_SOURCES
    src/game_interface.h
    src/game_plugin.h
    src/game_plugin.cpp
    src/terrain.h
    src/terrain.cpp
    src/physics.h
    src/physics.cpp
)

configure_file(
    src/plugin_metadata.json
    ${CMAKE_CURRENT_BINARY_DIR}/src/plugin_metadata.json
    COPYONLY
)

add_library(scorched_earth_plugin MODULE ${PLUGIN_SOURCES})
set_target_properties(scorched_earth_plugin PROPERTIES
    PREFIX ""
    OUTPUT_NAME "scorched_earth_plugin"
    BUILD_RPATH  "$ORIGIN"
    INSTALL_RPATH "$ORIGIN"
)

target_include_directories(scorched_earth_plugin PRIVATE
    src
    "${LOGOS_CPP_SDK}/include"
    "${LOGOS_CPP_SDK}/include/cpp"
    "${LOGOS_CPP_SDK}/include/core"
    "${LOGOS_LIBLOGOS_HEADERS}"
    "${LOGOS_LIBLOGOS_HEADERS}/cpp"
    "${LOGOS_LIBLOGOS_HEADERS}/core"
)

target_link_libraries(scorched_earth_plugin PRIVATE
    Qt6::Core
    -Wl,--whole-archive
    "${LOGOS_CPP_SDK_LIB}/lib/liblogos_sdk.a"
    -Wl,--no-whole-archive
)

# ── Install ─────────────────────────────────────────────────────────────────
set(MODULE_DIR "modules/scorched-earth")

# Remove stale backup dirs
install(CODE "
    set(_modules_dir \"\${CMAKE_INSTALL_PREFIX}/modules\")
    file(GLOB _old \"\${_modules_dir}/scorched-earth.*\")
    foreach(_dir \${_old})
        file(REMOVE_RECURSE \"\${_dir}\")
    endforeach()
")

install(TARGETS scorched_earth_plugin LIBRARY DESTINATION "${MODULE_DIR}")
install(FILES manifest.json src/plugin_metadata.json DESTINATION "${MODULE_DIR}")

# Mirror to LogosBasecamp
install(CODE "
    set(SRC \"\${CMAKE_INSTALL_PREFIX}/modules/scorched-earth\")
    set(DST \"\$ENV{HOME}/.local/share/Logos/LogosBasecamp/modules/scorched-earth\")
    file(COPY \"\${SRC}/\" DESTINATION \"\${DST}\")
    message(STATUS \"Mirrored scorched_earth to LogosBasecamp\")
")
