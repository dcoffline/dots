let _a, _b, _c, _d;
import Adw from 'gi://Adw';
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import GObject from 'gi://GObject';
import Gtk from 'gi://Gtk';
import * as Settings from './../settings.js';
/**
 * Subclass containing the preferences for Reddit adapter
 */
class RedditSettings extends Adw.PreferencesPage {
    /**
     * Craft a new adapter using an unique ID.
     *
     * Previously saved settings will be used if the adapter and ID match.
     *
     * @param {string} id Unique ID
     */
    constructor(id) {
        super(undefined);
        const path = `${Settings.RWG_SETTINGS_SCHEMA_PATH}/sources/reddit/${id}/`;
        this._settings = new Settings.Settings(Settings.RWG_SETTINGS_SCHEMA_SOURCES_REDDIT, path);
        this._settings.bind('allow-sfw', this._allow_sfw, 'active', Gio.SettingsBindFlags.DEFAULT);
        this._settings.bind('image-ratio1', this._image_ratio1, 'value', Gio.SettingsBindFlags.DEFAULT);
        this._settings.bind('image-ratio2', this._image_ratio2, 'value', Gio.SettingsBindFlags.DEFAULT);
        this._settings.bind('min-height', this._min_height, 'value', Gio.SettingsBindFlags.DEFAULT);
        this._settings.bind('min-width', this._min_width, 'value', Gio.SettingsBindFlags.DEFAULT);
        this._settings.bind('subreddits', this._subreddits, 'text', Gio.SettingsBindFlags.DEFAULT);
    }
    /**
     * Clear all config options associated to this specific adapter.
     */
    clearConfig() {
        this._settings.resetSchema();
    }
}
_a = RedditSettings, _b = GObject.GTypeName, _c = Gtk.template, _d = Gtk.internalChildren;
RedditSettings[_b] = 'RedditSettings';
// @ts-expect-error Gtk.template is not in the type definitions files yet
RedditSettings[_c] = GLib.uri_resolve_relative(import.meta.url, './reddit.ui', GLib.UriFlags.NONE);
// @ts-expect-error Gtk.internalChildren is not in the type definitions files yet
RedditSettings[_d] = [
    'allow_sfw',
    'image_ratio1',
    'image_ratio2',
    'min_height',
    'min_width',
    'subreddits',
];
(() => {
    GObject.registerClass(_a);
})();
export { RedditSettings };
