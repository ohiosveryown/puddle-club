#import <Foundation/Foundation.h>

#if __has_attribute(swift_private)
#define AC_SWIFT_PRIVATE __attribute__((swift_private))
#else
#define AC_SWIFT_PRIVATE
#endif

/// The "PuddleClubLogo" asset catalog image resource.
static NSString * const ACImageNamePuddleClubLogo AC_SWIFT_PRIVATE = @"PuddleClubLogo";

/// The "WaveformIcon" asset catalog image resource.
static NSString * const ACImageNameWaveformIcon AC_SWIFT_PRIVATE = @"WaveformIcon";

#undef AC_SWIFT_PRIVATE
