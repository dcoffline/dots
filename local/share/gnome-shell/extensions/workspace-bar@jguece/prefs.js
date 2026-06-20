import Adw from "gi://Adw";
import Gtk from "gi://Gtk";
import { ExtensionPreferences } from "resource:///org/gnome/Shell/Extensions/js/extensions/prefs.js";

export default class WorkspaceBarPrefs extends ExtensionPreferences {
    fillPreferencesWindow(window) {
        let settings = this.getSettings();

        let page = new Adw.PreferencesPage({ title: "Workspace Bar" });

        let group = new Adw.PreferencesGroup({ title: "Settings" });

        // Size Mode
        let sizeRow = new Adw.ComboRow({
            title: "Size",
            subtitle: "Controls icon size, font size, spacing, and roundness",
            model: Gtk.StringList.new(["Small", "Medium", "Large"]),
        });
        let sizeMap = { small: 0, medium: 1, large: 2 };
        let sizeReverse = ["small", "medium", "large"];
        sizeRow.set_selected(sizeMap[settings.get_string("size-mode")] ?? 1);
        sizeRow.connect("notify::selected", () => {
            settings.set_string("size-mode", sizeReverse[sizeRow.get_selected()]);
        });
        group.add(sizeRow);

        // Position
        let posRow = new Adw.ComboRow({
            title: "Position",
            subtitle: "Where to place the workspace bar in the top panel",
            model: Gtk.StringList.new(["Left", "Center", "Right"]),
        });
        let posMap = { left: 0, center: 1, right: 2 };
        let posReverse = ["left", "center", "right"];
        posRow.set_selected(posMap[settings.get_string("position")] ?? 0);
        posRow.connect("notify::selected", () => {
            settings.set_string("position", posReverse[posRow.get_selected()]);
        });
        group.add(posRow);

        // Position Index
        let posIndexRow = new Adw.SpinRow({
            title: "Position In Box",
            subtitle: "0 = first. Higher values move it further along the chosen box.",
            adjustment: new Gtk.Adjustment({
                lower: 0,
                upper: 20,
                step_increment: 1,
                page_increment: 5,
            }),
        });
        posIndexRow.set_value(settings.get_int("position-index"));
        posIndexRow.connect("notify::value", () => {
            settings.set_int("position-index", posIndexRow.get_value());
        });
        group.add(posIndexRow);

        // Left Margin
        let marginRow = new Adw.SpinRow({
            title: "Left Margin",
            subtitle: "Horizontal offset in pixels",
            adjustment: new Gtk.Adjustment({
                lower: 0,
                upper: 200,
                step_increment: 1,
                page_increment: 10,
            }),
        });
        marginRow.set_value(settings.get_int("left-margin"));
        marginRow.connect("notify::value", () => {
            settings.set_int("left-margin", marginRow.get_value());
        });
        group.add(marginRow);

        // Show Icons Background
        let bgRow = new Adw.SwitchRow({
            title: "Show Icons Background",
            subtitle: "Draw a subtle fill behind the workspace icons",
        });
        bgRow.set_active(settings.get_boolean("show-icons-background"));
        bgRow.connect("notify::active", () => {
            settings.set_boolean("show-icons-background", bgRow.get_active());
        });
        group.add(bgRow);

        // Focus Scale Effect
        let focusRow = new Adw.SwitchRow({
            title: "Focus Scale Effect",
            subtitle: "Slightly shrink unfocused app icons with a smooth transition",
        });
        focusRow.set_active(settings.get_boolean("focus-scale-effect"));
        focusRow.connect("notify::active", () => {
            settings.set_boolean("focus-scale-effect", focusRow.get_active());
        });
        group.add(focusRow);

        // Focus Scale Reduction (only meaningful when the toggle is on)
        let focusAmountRow = new Adw.SpinRow({
            title: "Reduction Amount",
            subtitle: "Percentage by which unfocused icons are shrunk",
            adjustment: new Gtk.Adjustment({
                lower: 5,
                upper: 95,
                step_increment: 1,
                page_increment: 5,
            }),
        });
        focusAmountRow.set_value(settings.get_int("focus-scale-reduction"));
        focusAmountRow.set_sensitive(focusRow.get_active());
        focusAmountRow.connect("notify::value", () => {
            settings.set_int("focus-scale-reduction", focusAmountRow.get_value());
        });
        focusRow.connect("notify::active", () => {
            focusAmountRow.set_sensitive(focusRow.get_active());
        });
        group.add(focusAmountRow);

        page.add(group);
        window.add(page);
    }
}
