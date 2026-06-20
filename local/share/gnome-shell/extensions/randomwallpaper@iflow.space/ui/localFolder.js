let _a, _b, _c, _d;
import Adw from 'gi://Adw';
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import GObject from 'gi://GObject';
import Gtk from 'gi://Gtk';
import * as Settings from './../settings.js';
import { gettext as _ } from 'resource:///org/gnome/Shell/Extensions/js/extensions/prefs.js';
/**
 * Subclass containing the preferences for LocalFolder adapter
 */
class LocalFolderSettings extends Adw.PreferencesPage {
    /**
     * Craft a new adapter using an unique ID.
     *
     * Previously saved settings will be used if the adapter and ID match.
     *
     * @param {string} id Unique ID
     */
    constructor(id) {
        super(undefined);
        const path = `${Settings.RWG_SETTINGS_SCHEMA_PATH}/sources/localFolder/${id}/`;
        this._settings = new Settings.Settings(Settings.RWG_SETTINGS_SCHEMA_SOURCES_LOCAL_FOLDER, path);
        this._settings.bind('folder', this._folder_row, 'text', Gio.SettingsBindFlags.DEFAULT);
        this._folder.connect('clicked', () => {
            // TODO: GTK 4.10+
            // Gtk.FileDialog();
            // https://stackoverflow.com/a/54487948
            this._saveDialog = new Gtk.FileChooserNative({
                title: _('Choose a Wallpaper Folder'),
                action: Gtk.FileChooserAction.SELECT_FOLDER,
                accept_label: _('Open'),
                cancel_label: _('Cancel'),
                transient_for: this.get_root() ?? undefined,
                modal: true,
            });
            this._saveDialog.connect('response', (_dialog, response_id) => {
                if (response_id === Gtk.ResponseType.ACCEPT) {
                    const chosenPath = _dialog.get_file()?.get_path();
                    if (chosenPath)
                        this._folder_row.text = chosenPath;
                }
                _dialog.destroy();
            });
            this._saveDialog.show();
        });
    }
    /**
     * Clear all config options associated to this specific adapter.
     */
    clearConfig() {
        this._settings.resetSchema();
    }
}
_a = LocalFolderSettings, _b = GObject.GTypeName, _c = Gtk.template, _d = Gtk.internalChildren;
LocalFolderSettings[_b] = 'LocalFolderSettings';
// @ts-expect-error Gtk.template is not in the type definitions files yet
LocalFolderSettings[_c] = GLib.uri_resolve_relative(import.meta.url, './localFolder.ui', GLib.UriFlags.NONE);
// @ts-expect-error Gtk.internalChildren is not in the type definitions files yet
LocalFolderSettings[_d] = [
    'folder',
    'folder_row',
];
(() => {
    GObject.registerClass(_a);
})();
export { LocalFolderSettings };
