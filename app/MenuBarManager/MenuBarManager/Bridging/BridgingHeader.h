#ifndef BridgingHeader_h
#define BridgingHeader_h

#include <CoreGraphics/CoreGraphics.h>

// Private CGS (CoreGraphics Services) API declarations
// These are undocumented Apple APIs used by Ice, Bartender, etc.

typedef int CGSConnectionID;

extern CGSConnectionID CGSMainConnectionID(void);

extern CGError CGSGetWindowList(
    CGSConnectionID cid,
    uint64_t val,
    int count,
    uint32_t *list,
    int *
);

extern CGError CGSGetOnScreenWindowList(
    CGSConnectionID cid,
    uint64_t val,
    int count,
    uint32_t *list,
    int *
);

extern CGError CGSGetScreenRectForWindow(
    CGSConnectionID cid,
    uint32_t wid,
    CGRect *outRect
);

extern CGError CGSGetWindowLevel(
    CGSConnectionID cid,
    uint32_t wid,
    int *level
);

#endif
