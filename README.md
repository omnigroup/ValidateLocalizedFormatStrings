## Overview

ValidateLocalizedFormatStrings checks for incompatible format strings across the localized variants of a strings file. For example, if you or your localizers accidentally localize "%@ points" to "%s mumble mumble" in some language, your later `+stringWithFormat:` call will crash or produce nonsense.

The types and order of format specifiers are checked. If there is more than one format specifier in a string, then all the format specifiers are required to have position indicators.

If your localizers hand edit strings files, it is not uncommon to have typos or copy/pasta that can cause crashes (one real world example left one of our files containing “%1$@“%@” when the localizer meant “%1$@”.

## Building

Currently this tool expects to be built as part of the OmniGroup project, but only to the extent that it needs a `../../Configurations` directory with our configurations. This is our first foray into submodules; hopefully this will get easier as we break out source up into smaller projects (like splitting out the Configurations into their own project)

## Running

`ValidateLocalizedFormatStrings /path/to/bundle`

## Limitations

* Doesn't handle all possible format specifiers, just the ones we hit in our apps
* Probably should remove 'p' as a valid specifier. Localized strings should really never have pointers in them, but we currently have a few.
* Doesn't look for strings in xibs that might be used as format specifiers -- that's kind of a crazy thing to do anyway, so don't do that.
