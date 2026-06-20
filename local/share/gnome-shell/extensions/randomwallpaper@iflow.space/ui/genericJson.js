let _a, _b, _c, _d;
import Adw from 'gi://Adw';
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import GObject from 'gi://GObject';
import Gtk from 'gi://Gtk';
import * as Settings from './../settings.js';
/**
 * Subclass containing the preferences for GenericJson adapter
 */
class GenericJsonSettings extends Adw.PreferencesPage {
    /**
     * Craft a new adapter using an unique ID.
     *
     * Previously saved settings will be used if the adapter and ID match.
     *
     * @param {string} id Unique ID
     */
    constructor(id) {
        super(undefined);
        const path = `${Settings.RWG_SETTINGS_SCHEMA_PATH}/sources/genericJSON/${id}/`;
        this._settings = new Settings.Settings(Settings.RWG_SETTINGS_SCHEMA_SOURCES_GENERIC_JSON, path);
        this._settings.bind('domain', this._domain, 'text', Gio.SettingsBindFlags.DEFAULT);
        this._settings.bind('request-url', this._request_url, 'text', Gio.SettingsBindFlags.DEFAULT);
        this._settings.bind('image-path', this._image_path, 'text', Gio.SettingsBindFlags.DEFAULT);
        this._settings.bind('image-prefix', this._image_prefix, 'text', Gio.SettingsBindFlags.DEFAULT);
        this._settings.bind('post-path', this._post_path, 'text', Gio.SettingsBindFlags.DEFAULT);
        this._settings.bind('post-prefix', this._post_prefix, 'text', Gio.SettingsBindFlags.DEFAULT);
        this._settings.bind('author-name-path', this._author_name_path, 'text', Gio.SettingsBindFlags.DEFAULT);
        this._settings.bind('author-url-path', this._author_url_path, 'text', Gio.SettingsBindFlags.DEFAULT);
        this._settings.bind('author-url-prefix', this._author_url_prefix, 'text', Gio.SettingsBindFlags.DEFAULT);
    }
    /**
     * Clear all config options associated to this specific adapter.
     */
    clearConfig() {
        this._settings.resetSchema();
    }
}
_a = GenericJsonSettings, _b = GObject.GTypeName, _c = Gtk.template, _d = Gtk.internalChildren;
GenericJsonSettings[_b] = 'GenericJsonSettings';
// @ts-expect-error Gtk.template is not in the type definitions files yet
GenericJsonSettings[_c] = GLib.uri_resolve_relative(import.meta.url, './genericJson.ui', GLib.UriFlags.NONE);
// @ts-expect-error Gtk.internalChildren is not in the type definitions files yet
GenericJsonSettings[_d] = [
    'author_name_path',
    'author_url_path',
    'author_url_prefix',
    'domain',
    'image_path',
    'image_prefix',
    'post_path',
    'post_prefix',
    'request_url',
];
(() => {
    GObject.registerClass(_a);
})();
export { GenericJsonSettings };
