# patch_octave.cmake
if(NOT DEFINED FILE_TO_PATCH)
    message(FATAL_ERROR "FILE_TO_PATCH variable has not been defined.")
endif()

if(NOT EXISTS "${FILE_TO_PATCH}")
    message(FATAL_ERROR "Target file not found: ${FILE_TO_PATCH}")
endif()

# Read the target file content
file(READ "${FILE_TO_PATCH}" FILE_CONTENT)

# Check for idempotency (skip if already patched)
if(FILE_CONTENT MATCHES "RTLD_DEEPBIND")
    message(STATUS "RTLD_DEEPBIND patch is already applied to ${FILE_TO_PATCH}")
    return()
endif()

# Robust pattern to detect the RTLD_GLOBAL block while ignoring spacing and newline variations
# \s* matches any whitespace including tabs and newlines
set(PATTERN "(#[ \t]*if[ \t]+defined[ \t]*\\([ \t]*RTLD_GLOBAL[ \t]*\\)[ \t]*\n[ \t]*flags[ \t]*\\|=[ \t]*RTLD_GLOBAL;[ \t]*\n[ \t]*#[ \t]*endif)")

# Text block to insert right after the matched RTLD_GLOBAL block
set(PATCH_TEXT "\\1\n\n  // Prefer symbols from the library being loaded over symbols already\n  // present in the global namespace. This avoids BLAS/LAPACK symbol\n  // interposition when loading MEX files linked against alternative\n  // numerical libraries.\n\n#  ifdef RTLD_DEEPBIND\n  flags |= RTLD_DEEPBIND;\n#  endif")

# Apply regex replacement
string(REGEX REPLACE "${PATTERN}" "${PATCH_TEXT}" UPDATED_CONTENT "${FILE_CONTENT}")

# Verify whether the target pattern was successfully found and replaced
if(FILE_CONTENT STREQUAL UPDATED_CONTENT)
    message(FATAL_ERROR "Failed to locate the RTLD_GLOBAL target block in ${FILE_TO_PATCH}. Check if source code has changed.")
else()
    file(WRITE "${FILE_TO_PATCH}" "${UPDATED_CONTENT}")
    message(STATUS "RTLD_DEEPBIND patch successfully applied to ${FILE_TO_PATCH}")
endif()
