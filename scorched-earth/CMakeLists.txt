cmake_minimum_required(VERSION 3.14)
project(ScorchedEarthModule LANGUAGES CXX)

if(DEFINED ENV{LOGOS_MODULE_BUILDER_ROOT})
    include($ENV{LOGOS_MODULE_BUILDER_ROOT}/cmake/LogosModule.cmake)
elseif(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/cmake/LogosModule.cmake")
    include(cmake/LogosModule.cmake)
else()
    message(FATAL_ERROR "LogosModule.cmake not found — set LOGOS_MODULE_BUILDER_ROOT")
endif()

logos_module(
    NAME scorched_earth
    SOURCES
        src/game_interface.h
        src/game_plugin.h
        src/game_plugin.cpp
        src/terrain.h
        src/terrain.cpp
        src/physics.h
        src/physics.cpp
    INCLUDE_DIRS
        src
        src/generated
)
