#include <ApplicationServices/ApplicationServices.h>

/*
 * Sunshine macOS Input Fix:
 * Sunshine's macOS input backend (libvirtualhid) caches the display ID (CGMainDisplayID)
 * only once at daemon startup. When dynamic virtual displays (BetterDisplay Remote Screen)
 * or headless configurations change the Main display during streaming, Sunshine
 * continues to scale and clamp mouse coordinates against the startup display bounds.
 *
 * This dyld interposer dynamically queries the active main display bounds at runtime,
 * ensuring coordinates are always mapped to the active streaming screen.
 */
CGRect my_CGDisplayBounds(CGDirectDisplayID display) {
    (void)display;
    CGDirectDisplayID main_id = CGMainDisplayID();
    CGDisplayModeRef mode = CGDisplayCopyDisplayMode(main_id);
    CGFloat w = 0, h = 0;
    if (mode) {
        w = (CGFloat)CGDisplayModeGetWidth(mode);
        h = (CGFloat)CGDisplayModeGetHeight(mode);
        CFRelease(mode);
    } else {
        w = (CGFloat)CGDisplayPixelsWide(main_id);
        h = (CGFloat)CGDisplayPixelsHigh(main_id);
    }
    return CGRectMake(0.0, 0.0, w, h);
}

struct interpose_s {
    const void *replacement;
    const void *original;
};

__attribute__((used, section("__DATA,__interpose")))
static const struct interpose_s interposers[] = {
    { (const void *)my_CGDisplayBounds, (const void *)CGDisplayBounds },
};
