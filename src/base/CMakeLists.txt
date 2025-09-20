add_library(base
        safe_input.cpp
)

target_include_directories(base PUBLIC
        ${CMAKE_SOURCE_DIR}/include
)
