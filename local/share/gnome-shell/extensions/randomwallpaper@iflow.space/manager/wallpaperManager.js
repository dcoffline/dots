import { Settings } from './../settings.js';
import { getEnumFromSettings } from './../utils.js';
import { gettext as _ } from 'gettext';
// Generated code produces a no-shadow rule error
/* eslint-disable */
var Mode;
(function (Mode) {
    /** Only change the desktop background */
    Mode[Mode["BACKGROUND"] = 0] = "BACKGROUND";
    /** Only change the lock screen background */
    Mode[Mode["LOCKSCREEN"] = 1] = "LOCKSCREEN";
    /** Change the desktop and lock screen background to the same image. */
    // This allows for optimizations when processing images.
    Mode[Mode["BACKGROUND_AND_LOCKSCREEN"] = 2] = "BACKGROUND_AND_LOCKSCREEN";
    /** Change each - the desktop and lock screen background - to different images. */
    Mode[Mode["BACKGROUND_AND_LOCKSCREEN_INDEPENDENT"] = 3] = "BACKGROUND_AND_LOCKSCREEN_INDEPENDENT";
})(Mode || (Mode = {}));
/* eslint-enable */
/**
 * Wallpaper manager is a base class for manager to implement.
 */
class WallpaperManager {
    constructor() {
        this.canHandleMultipleImages = false;
        this._backgroundSettings = new Settings('org.gnome.desktop.background');
        this._screensaverSettings = new Settings('org.gnome.desktop.screensaver');
    }
    /**
     * Set the wallpapers for a given mode.
     *
     * @param {string[]} wallpaperPaths Array of paths to the desired wallpapers, should match the display count
     * @param {Mode} mode Enum indicating what images to change
     */
    async setWallpaper(wallpaperPaths, mode = Mode.BACKGROUND) {
        if (wallpaperPaths.length < 1)
            throw new Error('Empty wallpaper array');
        const promises = [];
        if (mode === Mode.BACKGROUND || mode === Mode.BACKGROUND_AND_LOCKSCREEN)
            promises.push(this._setBackground(wallpaperPaths));
        if (mode === Mode.LOCKSCREEN || mode === Mode.BACKGROUND_AND_LOCKSCREEN)
            promises.push(this._setLockScreen(wallpaperPaths));
        if (mode === Mode.BACKGROUND_AND_LOCKSCREEN_INDEPENDENT) {
            if (wallpaperPaths.length < 2)
                throw new Error('Not enough wallpaper');
            // Half the images for the background
            promises.push(this._setBackground(wallpaperPaths.slice(0, wallpaperPaths.length / 2)));
            // Half the images for the lock screen
            promises.push(this._setLockScreen(wallpaperPaths.slice(wallpaperPaths.length / 2)));
        }
        await Promise.allSettled(promises);
    }
}
/**
 * Retrieve the human readable enum name.
 *
 * @param {Mode} mode The mode to name
 * @returns {string} Name
 */
function _getModeName(mode) {
    let name;
    switch (mode) {
        case Mode.BACKGROUND:
            name = _('Background');
            break;
        case Mode.LOCKSCREEN:
            name = _('Lockscreen');
            break;
        case Mode.BACKGROUND_AND_LOCKSCREEN:
            name = `${_('Background')} ${_('and')} ${_('Lockscreen')}`;
            break;
        case Mode.BACKGROUND_AND_LOCKSCREEN_INDEPENDENT:
            name = `${_('Background')} ${_('and')} ${_('Lockscreen')} ${_('Independently')}`;
            break;
        default:
            name = 'Mode name not found';
            break;
    }
    return name;
}
/**
 * Get a list of human readable enum entries.
 *
 * @returns {string[]} Array with key names
 */
function getModeNameList() {
    const list = [];
    const values = Object.values(Mode).filter(v => !isNaN(Number(v)));
    for (const i of values)
        list.push(_getModeName(i));
    return list;
}
/**
 * Get a list of all the valid enum entries and return them as an array of strings
 *
 * Note: The list gets pre-filtered of unwanted values.
 *
 * @returns {string[]} Array of string containing valid enum values
 */
function getScalingModeEnum() {
    const excludes = [
        'none', // No wallpaper
        'wallpaper', // Tiled wallpapers, repeating pattern
        'spanned', // Ignoring aspect ratio
    ];
    return getEnumFromSettings(new Settings('org.gnome.desktop.background'), 'picture-options')
        .filter(s => !excludes.includes(s));
}
export { WallpaperManager, Mode, getModeNameList, getScalingModeEnum };
