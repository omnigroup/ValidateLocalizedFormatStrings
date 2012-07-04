// Copyright 2012 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/Foundation.h>

#define RCS_ID(x) // Not pulling in OmniBase in this tool
RCS_ID("$Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/trunk/OmniGroup/Tools/ValidateLocalizedFormatStrings/ValidateLocalizedFormatStrings.m 165886 2012-04-23 21:43:43Z bungi $")

static BOOL _hasPrefix(NSRegularExpression *regexp, NSString *string)
{
    NSRange matchRange = [regexp rangeOfFirstMatchInString:string options:NSMatchingAnchored range:NSMakeRange(0, [string length])];
    return matchRange.location == 0;
}

static int _positionForSpecifier(NSString *specifier)
{
    int position = [[specifier substringFromIndex:1] intValue]; // Hacky, but effective.
    //NSLog(@"  specifier %@ -> position %d", specifier, position);
    return position;
}

static id _stringFormatSpecifiersForString(NSURL *fileURL, NSString *key, NSString *format)
{
    NSMutableArray *formatSpecifiers = [NSMutableArray array];
    NSUInteger location = 0, end = [format length];
    
    static NSRegularExpression *PositionalPrefixRegularExpression = nil;
    static NSCharacterSet *FormatTerminatingCharacterSet = nil;
    static NSCharacterSet *NotFormatModifierCharacterSet = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // Stuff that definitely would end a format
        // TODO: Remove 'p'. There is no good reason to localize format strings that have pointers in them.
        FormatTerminatingCharacterSet = [[NSCharacterSet characterSetWithCharactersInString:@"%@sduefgcCp"] copy];
        
        // Double check stuff that is allowed inside a format specifier.
        // NOTE: This doesn't include '*' since we don't currently need it and we might need extra validation for positional specifiers (haven't looked at how that works -- does the next specifier after than have position+1 or position+2?)
        NotFormatModifierCharacterSet = [[[NSCharacterSet characterSetWithCharactersInString:@"+0123456789$.luq"] invertedSet ]copy];
        
        NSError *error = nil;
        PositionalPrefixRegularExpression = [[NSRegularExpression alloc] initWithPattern:@"%\\d+\\$" options:0 error:&error];
        if (!PositionalPrefixRegularExpression) {
            NSLog(@"Error creating positional prefix regular expression: %@", error);
            exit(1);
        }
    });
    
    while (location < end) {
        NSRange percentRange = [format rangeOfString:@"%" options:0 range:NSMakeRange(location, end - location)];
        if (percentRange.location == NSNotFound)
            break;

        NSRange endRange = [format rangeOfCharacterFromSet:FormatTerminatingCharacterSet options:0 range:NSMakeRange(NSMaxRange(percentRange), end - NSMaxRange(percentRange))];
        if (endRange.location == NSNotFound) {
            // If there are no format specifiers already found, this is probably not actually intended to be a format string. Rather, it is probably something like "100% Zoom". Skip past this % (to stand a better chance of detecting errors of the form '% %d')
            if ([formatSpecifiers count] == 0) {
                location = NSMaxRange(percentRange);
                continue;
            }
            
            NSLog(@"ERROR: <%@ key \"%@\"> Cannot find end of format specifier starting at %ld in \"%@\"", fileURL, key, percentRange.location, format);
            return nil;
        }
        
        NSString *specifier = [format substringWithRange:NSMakeRange(percentRange.location, NSMaxRange(endRange) - percentRange.location)];
        
        // Do a minimal double check that the specifier has things that look like they belong in the middle of a format string
        NSRange badCharacterRange = [specifier rangeOfCharacterFromSet:NotFormatModifierCharacterSet options:0 range:NSMakeRange(1, [specifier length] - 2)];
        if (badCharacterRange.length) {
            NSLog(@"ERROR: <%@ key \"%@\"> Found format specifier \"%@\" in \"%@\" that has an unexpected modifier character at %ld", fileURL, key, specifier, format, badCharacterRange.location);
            return nil;
        }
        
        // Only keep track of argument-consuming specifiers. These are the ones that can cause the sort of conflicts we are looking for, and using "%d%%" shouldn't force the %d to be %1$d.
        if (![specifier isEqualToString:@"%%"])
            [formatSpecifiers addObject:specifier];
        
        location = NSMaxRange(endRange);
    }
    
    // If there are more than one argument-consuming specifier, then they should all have the positional format prefix '%[0-9]+$'. If there is exactly one, then it shouldn't.
    NSUInteger formatSpecifierCount = [formatSpecifiers count];
    if (formatSpecifierCount > 1) {
        for (NSString *specifier in formatSpecifiers) {
            if (!_hasPrefix(PositionalPrefixRegularExpression, specifier)) {
                NSLog(@"ERROR: <%@ key \"%@\"> Multiple-specifier format \"%@\" does not have all positional specifiers %@", fileURL, key, format, formatSpecifiers);
                return nil;
            }
        }
        
        // With positional specifiers, the position we find it in the string isn't important. Sort by the position.
        NSArray *positionSortedSpecifiers = [formatSpecifiers sortedArrayUsingComparator:^NSComparisonResult(NSString *specifier1, NSString *specifier2) {
            int position1 = _positionForSpecifier(specifier1);
            int position2 = _positionForSpecifier(specifier2);
            
            if (position1 < position2)
                return NSOrderedAscending;
            if (position1 > position2)
                return NSOrderedDescending;
            return NSOrderedSame;
        }];
        
        // The positions should start at one and fill every offset. In a few cases we use positional specifiers twice, so it is legal to have %1$@, %1$@, but not %1$@, %3$@
        int previousPosition = 0;
        for (NSString *specifier in positionSortedSpecifiers) {
            int position = _positionForSpecifier(specifier);
            if (position != previousPosition && position != previousPosition + 1) {
                NSLog(@"ERROR: <%@ key \"%@\"> Multiple-specifier format \"%@\" has non-continuous positions %@", fileURL, key, format, positionSortedSpecifiers);
                return nil;
            }
            previousPosition = position;
        }
        
        return positionSortedSpecifiers;
    } else if (formatSpecifierCount == 1) {
        // If we have one specifier, it should either have no position specified or should the position should be 1.
        NSString *specifier = [formatSpecifiers lastObject];
        if (_hasPrefix(PositionalPrefixRegularExpression, specifier)) {
            int position = _positionForSpecifier(specifier);
            if (position != 1) {
                NSLog(@"ERROR: <%@ key \"%@\"> Single-specifier format \"%@\" has position other than one", fileURL, key, format);
                return nil;
            }
        }
        
        return formatSpecifiers;
    } else {
        return formatSpecifiers;
    }

}

static BOOL _validateSameLocalizedStringFormatsWithURLs(NSArray *stringFileURLs)
{
    __block BOOL success = YES;
    
    NSMutableDictionary *keyToFormatSpecifiers = [NSMutableDictionary dictionary];
    for (NSURL *stringFileURL in stringFileURLs) {
        NSDictionary *stringTable = [NSDictionary dictionaryWithContentsOfURL:stringFileURL];
        if (!stringTable) {
            NSLog(@"ERROR: Unable to load string table from %@", stringFileURL);
            success = NO;
            continue;
        }
        
        [stringTable enumerateKeysAndObjectsUsingBlock:^(NSString * key, NSString *value, BOOL *stop){
            id formatSpecifiers = _stringFormatSpecifiersForString(stringFileURL, key, value);
            if (formatSpecifiers == nil) {
                // Couldn't parse the format specifier for some reason
                success = NO;
                *stop = YES;
                return;
            }
            
            //NSLog(@"format \"%@\" -> specifiers %@", value, formatSpecifiers);
            
            id otherFormatSpecifiers = [keyToFormatSpecifiers objectForKey:key];
            
            if (!otherFormatSpecifiers) {
                [keyToFormatSpecifiers setObject:formatSpecifiers forKey:key];
            } else if (![formatSpecifiers isEqual:otherFormatSpecifiers]) {
                NSLog(@"ERROR: The key \"%@\" of string table %@ has format specifiers %@, but another localization has %@", key, stringFileURL, formatSpecifiers, otherFormatSpecifiers);
                success = NO;
            }
        }];
    }
    
    return success;
}

static void _collectStringsFiles(NSMutableDictionary *stringFileURLsByIdentifier, NSURL *fileURL)
{
    //NSLog(@"examining %@", fileURL);

    // Traverse symlinks. In normal builds our Debug build output has the real files. In Release builds, it will have symlinks.
    // Sadly -enumeratorAtURL:includingPropertiesForKeys:options:errorHandler: doesn't have a symlink resolving option.
    NSURL *resolvedURL = [fileURL URLByResolvingSymlinksInPath];
    if (!resolvedURL) {
        NSLog(@"Cannot resolve symlinks in %@", fileURL);
        exit(1);
    }
    fileURL = resolvedURL;
    
    NSError *attributesError = nil;
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:[fileURL path] error:&attributesError];
    if (!attributes) {
        NSLog(@"Cannot get attributes of %@: %@", fileURL, attributesError);
        exit(1);
    }
    
    NSString *fileType = [attributes fileType];
    if ([fileType isEqualToString:NSFileTypeDirectory]) {
        NSError *error = nil;
        NSArray *childURLs = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:fileURL includingPropertiesForKeys:nil options:0 error:&error];
        if (!childURLs) {
            NSLog(@"Cannot get children of %@: %@", fileURL, error);
            exit(1);
        }
        
        for (NSURL *childURL in childURLs)
            _collectStringsFiles(stringFileURLsByIdentifier, childURL);
        return;
    }

    if ([fileType isEqualToString:NSFileTypeRegular]) {
        if ([[fileURL pathExtension] isEqualToString:@"strings"]) {
            // We expect all strings files will have an immediate and exactly one ancestor directory that is an lproj (put the defaults in English.lproj/en.lproj, not directly in the bundle).
            NSMutableArray *pathComponents = [[[fileURL pathComponents] mutableCopy] autorelease];
            if (![[[pathComponents objectAtIndex:[pathComponents count] - 2] pathExtension] isEqualToString:@"lproj"]) {
                NSLog(@"Strings file at %@ is not directly in an lproj!", fileURL);
                return; // EnglishToISO.strings in OmniFoundation...
                //exit(1);
            }
            
            [pathComponents removeObjectAtIndex:[pathComponents count] - 2];
            NSString *identifier = [NSString pathWithComponents:pathComponents];
            
            NSMutableArray *stringFileURLs = [stringFileURLsByIdentifier objectForKey:identifier];
            if (!stringFileURLs) {
                stringFileURLs = [NSMutableArray array];
                [stringFileURLsByIdentifier setObject:stringFileURLs forKey:identifier];
            }
            [stringFileURLs addObject:fileURL];
        }
        return;
    }
    
    NSLog(@"Unhandled file type %@ for %@", fileType, fileURL);
    exit(1);
}

static BOOL _validateDirectoryWithPath(NSURL *fileURL)
{
    NSMutableDictionary *stringFileURLsByIdentifier = [NSMutableDictionary dictionary];
    _collectStringsFiles(stringFileURLsByIdentifier, fileURL);
        
    BOOL success = YES;
    for (NSString *identifier in stringFileURLsByIdentifier) {
        NSArray *stringFileURLs = [stringFileURLsByIdentifier objectForKey:identifier];
        
        @autoreleasepool {
            if (!_validateSameLocalizedStringFormatsWithURLs(stringFileURLs))
                success = NO;
        }
    }
    
    return success;
}

int main(int argc, const char * argv[])
{
    if (argc != 2) {
        fprintf(stderr, "usage: %s directory\n", argv[0]);
        exit(1);
    }
    
    @autoreleasepool {
        NSString *directoryPath = [[NSFileManager defaultManager] stringWithFileSystemRepresentation:argv[1] length:strlen(argv[1])];
        
        return _validateDirectoryWithPath([NSURL fileURLWithPath:directoryPath]) ? 0 : 1;
    }
}

