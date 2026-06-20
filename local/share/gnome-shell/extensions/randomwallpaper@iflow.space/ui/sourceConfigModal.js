let _a, _b, _c, _d, _e;
import Adw from 'gi://Adw';
import GLib from 'gi://GLib';
import Gtk from 'gi://Gtk';
import Gio from 'gi://Gio';
import GObject from 'gi://GObject';
import * as Utils from './../utils.js';
import { SourceRow } from './sourceRow.js';
// Imports for initializing the translation domain in templates
import { gettext as _ } from 'resource:///org/gnome/Shell/Extensions/js/extensions/prefs.js';
/**
 * Subclass of Adw.Window for configuring a single source in a modal window.
 */
class SourceConfigModal extends Adw.Window {
    /**
     * Craft a new source row using an unique ID.
     *
     * Default unique ID is Date.now()
     * Previously saved settings will be used if the ID matches.
     *
     * @param {Adw.Window} parentWindow The window that this model is transient for.
     * @param {SourceRow} source Optional SourceRow object for editing if not present a new SourceRow will be created.
     */
    constructor(parentWindow, source) {
        super({
            title: source ? _('Edit Source') : _('Add New Source'),
            transient_for: parentWindow,
            modal: true,
            defaultHeight: parentWindow.get_height() * 0.9,
            defaultWidth: parentWindow.get_width() * 0.9,
        });
        if (!source) {
            this._currentSourceRow = new SourceRow();
            this._button_cancel.show();
            this._button_add.show();
            this._button_close.hide();
        }
        else {
            this._currentSourceRow = source;
            this._button_cancel.hide();
            this._button_add.hide();
            this._button_close.show();
        }
        if (!_a._stringList) {
            const availableTypeNames = [];
            for (const mapping of Utils.SourceTypeMapping)
                availableTypeNames.push(Utils.getSourceTypeName(mapping[0]));
            _a._stringList = Gtk.StringList.new(availableTypeNames);
        }
        this._combo.model = _a._stringList;
        const storedSourceType = this._currentSourceRow.settings.getInt('type');
        this._combo.selected = Utils.getInterfaceIndexForSourceType(storedSourceType);
        this._currentSourceRow.settings.bind('name', this._source_name, 'text', Gio.SettingsBindFlags.DEFAULT);
        const storeSourceType = (uiIndex) => {
            this._currentSourceRow.settings.setInt('type', Utils.getSourceTypeForInterfaceIndex(uiIndex));
            this._fillRow(Utils.getSourceTypeForInterfaceIndex(uiIndex));
        };
        this._combo.connect('notify::selected', (comboRow) => storeSourceType(comboRow.selected));
        storeSourceType(this._combo.selected);
    }
    /**
     * Fill this source row with adapter settings.
     *
     * @param {number} type Enum of the adapter to use
     */
    _fillRow(type) {
        const targetWidget = this._currentSourceRow.getSettingsWidget(type);
        if (targetWidget !== null)
            this._settings_container.set_child(targetWidget);
    }
    /**
     * Open the modal window.
     *
     * @returns {Promise<SourceRow>} Returns a promise resolving into the created/edited source row when closed/saved.
     */
    async open() {
        const promise = await new Promise((resolve, reject) => {
            this.show();
            this._button_add.connect('clicked', () => {
                this.close();
                resolve(this._currentSourceRow);
            });
            this._button_close.connect('clicked', () => {
                this.close();
                resolve(this._currentSourceRow);
            });
            this._button_cancel.connect('clicked', () => {
                this.close();
                this._currentSourceRow.clearConfig();
                reject(new Error('Canceled'));
            });
        });
        return promise;
    }
}
_a = SourceConfigModal, _b = GObject.GTypeName, _c = Gtk.template, _d = Gtk.children, _e = Gtk.internalChildren;
SourceConfigModal[_b] = 'SourceConfigModal';
// @ts-expect-error Gtk.template is not in the type definitions files yet
SourceConfigModal[_c] = GLib.uri_resolve_relative(import.meta.url, './sourceConfigModal.ui', GLib.UriFlags.NONE);
// @ts-expect-error Gtk.children is not in the type definitions files yet
SourceConfigModal[_d] = [];
// @ts-expect-error Gtk.children is not in the type definitions files yet
SourceConfigModal[_e] = [
    'combo',
    'settings_container',
    'source_name',
    'button_add',
    'button_cancel',
    'button_close',
];
(() => {
    GObject.registerClass(_a);
})();
export { SourceConfigModal };
