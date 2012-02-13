#!/bin/bash
# 
# Expands custom localization macros and then runs `genstrings`.
# 
# - This script is not quite 'tried and true' yet but it should work.
# - Make sure that the config values below are correct for you.
# - Run this script from the root directory of your XCode project.
# 
# All of your custom localization macros should be defined in one header file.
# This header file should not import any other files, and the macros it defines
# must expand to a format that genstrings understands -- i.e. NSLocalizedString
# and friends.
# 
# Here is an example of a `Localization.h`:
# 
#     #define LOC NSLocalizedString
#     
#     #define LOC_DEF(__key, __defvalue, __comment) \
#         NSLocalizedStringWithDefaultValue(\
#             (__key), nil, [NSBundle mainBundle],\
#             (__defvalue), (__comment))
#     
#     #define LOC_F(__key, __comment, ...) \
#         [NSString stringWithFormat:\
#          LOC(__key, __comment), __VA_ARGS__]
#     
#     #define LOC_DEF_F(__key, __defvalue, __comment, ...) \
#         [NSString stringWithFormat:\
#          LOC_DEF(__key, __defvalue, __comment), __VA_ARGS__]
# 
# All your source code files are copied into the same temporary directory, so
# you should not have source files with the same name in your project.
# 
# Copyright (c) 2011-2012 Ali Rantakari
# This script is licensed under the WTFPL: http://sam.zoy.org/wtfpl/
# 


# Config values
# -----------------------------------------------------------------------------

# The name of the header file that includes your custom localization macros:
# 
LOC_HEADER_FILE="Localization.h"

# The C compiler to use for preprocessing the source files:
# 
CC=cc

# Extended regex for matching filenames of localizable source code files:
# 
SOURCES_REGEX='.*\.(m|h|mm)$'


# Functions
# -----------------------------------------------------------------------------

# Return a list of all localizable source files:
# 
get_localizable_sources()
{
	find -E . -iregex "${SOURCES_REGEX}"
}

# Prepend a line of text ($1) to a file ($2):
# 
prepend_to_file()
{
    tempfile="/tmp/prepend-temp-file"
    echo "$1" | cat - "$2" > "$tempfile" && mv "$tempfile" "$2"
}


# Script body
# -----------------------------------------------------------------------------

# Determine L10N designator for the base language (native development region)
# by reading it from the Info.plist file:
# 
INFO_PLIST=$(ls *Info.plist | head -1)
if [ -z "${INFO_PLIST}" ];then
    echo "Error: Cannot find *Info.plist."
    exit 1
fi
BASE_L10N_REGION=$(/usr/libexec/PlistBuddy -c "Print CFBundleDevelopmentRegion" "${INFO_PLIST}")
if [ -z "${BASE_L10N_REGION}" ];then
    echo "Error: Cannot determine localization native development region"
    echo "(tried to read it from '${INFO_PLIST}')."
    exit 1
fi

# Confirm our destructive action with the user:
# 
if [ -e "${BASE_L10N_REGION}.lproj/Localizable.strings" ]; then
    echo "${BASE_L10N_REGION}.lproj/Localizable.strings will be replaced."
else
    echo "NOTE: ${BASE_L10N_REGION}.lproj/Localizable.strings does not exist."
    echo "      It will be generated if you continue."
fi
echo "Press return to continue or Ctrl-C to cancel."
read

# Create temp dir:
# 
TEMPDIR=$(mktemp -dq -t genstrings)
if [ $? -ne 0 ]; then
    echo "$0: Can't create temp dir, exiting..."
    exit 1
fi

# Copy localizable source files to the temp dir:
# 
for f in $(get_localizable_sources); do
    cp "$f" "$TEMPDIR/."
done

# Remove all imports and includes (we don't want the preprocessor to
# follow them; we only want it to expand the L10N macros):
# 
perl -p -i -e 's/^\s*\#(import|include).*$//xsg' $TEMPDIR/*

# Run the C preprocessor on each of the files to expand the L10N macros:
# 
for f in $TEMPDIR/*; do
    if [[ $(basename "$f") != "$LOC_HEADER_FILE" ]]; then
        prepend_to_file "#include \"$LOC_HEADER_FILE\"" "$f"
        "${CC}" -E "$f" > /tmp/out && mv /tmp/out "$f"
    fi
done

# Remove LOC_HEADER_FILE so that genstrings won't try to process it:
# 
rm "$TEMPDIR/$LOC_HEADER_FILE"

# Make sure the .lproj folder exists (genstrings chokes if it doesn't):
# 
if [ ! -e "${BASE_L10N_REGION}.lproj" ];then
    mkdir "${BASE_L10N_REGION}.lproj"
fi

# Generate Localizable.strings based on the processed temp copies
# of our source files:
# 
genstrings -o "${BASE_L10N_REGION}.lproj" $TEMPDIR/*

[ $? -eq 0 ] && echo "${BASE_L10N_REGION}.lproj/Localizable.strings has been updated."
