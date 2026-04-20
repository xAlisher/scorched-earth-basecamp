cmake_minimum_required(VERSION 3.28)
project(scorched-earth-basecamp VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(Qt6 REQUIRED COMPONENTS Core)
find_package(Qt6 OPTIONAL_COMPONENTS Test)

add_subdirectory(scorched-earth)
