cmake_minimum_required(VERSION 3.20)

if(NOT DEFINED PROJECT_NAME)
  set(ARGPARSE_IS_TOP_LEVEL ON)
else()
  set(ARGPARSE_IS_TOP_LEVEL OFF)
endif()

project(
    dystopian-libs
        VERSION 0.0.1
        DESCRIPTION ""
        HOMEPAGE_URL "https://github.com/dcx7c5/dystopian-libs"
        LANGUAGES CXX
)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# Add source directory
add_subdirectory(lib/argparse)
add_subdirectory(src)

# Define the library target first, before using it
file(GLOB_RECURSE DYSTOPIAN_LIBS_SRC
        "src/*.cpp"
)

add_library(dystopian-libs STATIC ${DYSTOPIAN_LIBS_SRC})

# Include directories for the library
target_include_directories(dystopian-libs
    PUBLIC
        ${CMAKE_CURRENT_SOURCE_DIR}/include
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/src
)

# Set output directory
set_target_properties(dystopian-libs PROPERTIES
        LIBRARY_OUTPUT_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/lib
        ARCHIVE_OUTPUT_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/lib
)

# Package configuration
set(CPACK_PROJECT_NAME ${PROJECT_NAME})
set(CPACK_PROJECT_VERSION ${PROJECT_VERSION})
include(CPack)