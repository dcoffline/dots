import Meta from "gi://Meta";
import St from "gi://St";
import Shell from "gi://Shell";
import Clutter from "gi://Clutter";
import * as Main from "resource:///org/gnome/shell/ui/main.js";
import * as DND from "resource:///org/gnome/shell/ui/dnd.js";
import GLib from "gi://GLib";

const ICON_TIMEOUT = 200;
const GAP_HALF_WIDTH = 15;

const FOCUS_ANIM_DURATION_MS = 200;

const ARROW_STRIP_WIDTH = 14;
const OVERFLOW_TOLERANCE = 4;
const SYNC_DEBOUNCE_MS = 50;
const SYNC_RETRY_MS = 120;
const SCROLL_SCHEDULE_MS = 30;
const SCROLL_RETRY_MS = 80;
const VIEWPORT_INIT_DELAY_MS = 100;
const VIEWPORT_MAX_PANEL_FRACTION = 0.4;
const WHEEL_STEP_PX = 40;

export default class WorkspaceBar {
    constructor(ext) {
        this._ext = ext;
        this._destroyed = false;
        this._setup();
    }

    _setup() {
        this._container = null;
        this._clip = null;
        this._viewport = null;
        this._arrowLeft = null;
        this._arrowRight = null;
        this._winIdsRepr = []; // [ws0[winId, winId], ws1[winId], ...]  — primary assignment only
        this._stickyListenerIds = new Map(); // winId -> { windowObj, signalId } for notify::on-all-workspaces
        this._gnomeEventIds = { display: [], workspace_manager: [] };
        this._mainEventIds = { layoutManager: [], panel: [] };
        this._glibTimeoutIds = new Set();
        this._gapDragMonitor = null;
        this._insertionIndicator = null;
        this._currentInsertIndex = -1;
        this._gapDropWindowObj = null;
        this._scrollOffset = 0;
        this._availableWidth = 0;
        this._syncPending = false;
        this._focusedWindowId = global.display.get_focus_window()?.get_id() ?? null;

        this._createContainer();
        this._insertContainer();
        this._initialPopulation();
        this._connectSignals();

        this._scheduleTimeout(VIEWPORT_INIT_DELAY_MS, () => this._updateAvailableWidth());
    }

    destroy(full = true) {
        this._destroyed = true;
        this._unregisterGapDragMonitor();

        if (this._viewport) {
            this._removeContainer();
            this._viewport.destroy();
            this._viewport = null;
            this._clip = null;
            this._container = null;
            this._arrowLeft = null;
            this._arrowRight = null;
        }

        // Disconnect GNOME signals
        for (let component in this._gnomeEventIds) {
            let obj = component === 'display' || component === 'workspace_manager'
                ? global[component] : Main[component];
            for (let id of this._gnomeEventIds[component]) {
                obj.disconnect(id);
            }
        }
        this._gnomeEventIds = null;

        for (let component in this._mainEventIds) {
            for (let id of this._mainEventIds[component]) {
                Main[component].disconnect(id);
            }
        }
        this._mainEventIds = null;

        // Clear timeouts
        for (let timeoutId of this._glibTimeoutIds) {
            GLib.Source.remove(timeoutId);
        }
        this._glibTimeoutIds.clear();
        this._glibTimeoutIds = null;

        // Clean up window-added events on workspaces
        for (let i = 0; i < global.workspace_manager.get_n_workspaces(); i++) {
            let wsObj = global.workspace_manager.get_workspace_by_index(i);
            if (wsObj.hasOwnProperty("_wsbWindowAddedId")) {
                wsObj.disconnect(wsObj._wsbWindowAddedId);
                delete wsObj._wsbWindowAddedId;
            }
        }

        // Disconnect per-window sticky listeners
        if (this._stickyListenerIds) {
            for (let entry of this._stickyListenerIds.values()) {
                try { entry.windowObj.disconnect(entry.signalId); } catch (_e) {}
            }
            this._stickyListenerIds.clear();
            this._stickyListenerIds = null;
        }

        this._winIdsRepr = null;

        if (full) {
            this._ext = null;
        } else {
            this._destroyed = false;
        }
    }

    // ===================== CONTAINER =====================

    _createContainer() {
        this._container = new St.BoxLayout({
            reactive: true,
            track_hover: true,
            x_expand: false,
            y_expand: false,
        });

        this._clip = new St.Widget({
            reactive: true,
            clip_to_allocation: true,
            x_expand: false,
            y_expand: false,
            layout_manager: new Clutter.FixedLayout(),
        });
        this._clip.add_child(this._container);

        this._viewport = new St.Widget({
            reactive: true,
            clip_to_allocation: true,
            x_expand: false,
            y_expand: true,
            layout_manager: new Clutter.FixedLayout(),
        });
        this._viewport.add_child(this._clip);

        this._arrowLeft = new St.Label({
            text: '◂',
            style_class: "wsb-overflow-arrow",
            reactive: false,
            can_focus: false,
            visible: false,
        });
        this._arrowRight = new St.Label({
            text: '▸',
            style_class: "wsb-overflow-arrow",
            reactive: false,
            can_focus: false,
            visible: false,
        });
        this._viewport.add_child(this._arrowLeft);
        this._viewport.add_child(this._arrowRight);

        this._viewport.connect('notify::width', () => this._updateOverlays());
        this._viewport.connect('notify::height', () => this._updateOverlays());
        this._viewport.connect('scroll-event', (_actor, event) => this._onScrollEvent(event));
    }

    _onScrollEvent(event) {
        let dir = event.get_scroll_direction();
        let active = global.workspace_manager.get_active_workspace_index();
        let nWs = global.workspace_manager.get_n_workspaces();

        if (dir === Clutter.ScrollDirection.UP) {
            if (active > 0)
                global.workspace_manager.get_workspace_by_index(active - 1).activate(global.get_current_time());
            return Clutter.EVENT_STOP;
        }
        if (dir === Clutter.ScrollDirection.DOWN) {
            if (active < nWs - 1)
                global.workspace_manager.get_workspace_by_index(active + 1).activate(global.get_current_time());
            return Clutter.EVENT_STOP;
        }
        if (dir === Clutter.ScrollDirection.LEFT) {
            this._setScrollOffset(this._scrollOffset - WHEEL_STEP_PX);
            return Clutter.EVENT_STOP;
        }
        if (dir === Clutter.ScrollDirection.RIGHT) {
            this._setScrollOffset(this._scrollOffset + WHEEL_STEP_PX);
            return Clutter.EVENT_STOP;
        }
        return Clutter.EVENT_PROPAGATE;
    }

    _insertContainer() {
        let pos = this._ext.getPosition();
        let posIndex = this._ext.getPositionIndex();
        let box;
        if (pos === 'center') box = Main.panel._centerBox;
        else if (pos === 'right') box = Main.panel._rightBox;
        else box = Main.panel._leftBox;

        let maxIndex = box.get_n_children();
        box.insert_child_at_index(this._viewport, Math.min(posIndex, maxIndex));
    }

    _removeContainer() {
        let parent = this._viewport.get_parent();
        if (parent) parent.remove_child(this._viewport);
    }

    onPositionChanged() {
        if (!this._viewport) return;
        this._removeContainer();
        this._insertContainer();
        this._updateAvailableWidth();
    }

    onSizeModeChanged() {
        if (!this._container) return;
        this._regenerateIcons();
    }

    onLeftMarginChanged() {
        if (!this._viewport) return;
        this._applyViewportWidth();
    }

    onFocusScaleEffectChanged() {
        this._refreshAllIconScales(true);
    }

    // ===================== FOCUS SCALE EFFECT =====================

    _onFocusWindowChanged() {
        if (!this._container) return;
        let focusedId = global.display.get_focus_window()?.get_id() ?? null;
        if (focusedId === this._focusedWindowId) return;
        this._focusedWindowId = focusedId;
        this._refreshAllIconScales(true);
    }

    _refreshAllIconScales(animate) {
        if (!this._container) return;
        for (let btn of this._container.get_children()) {
            let iconsWrapper = btn.get_children()[1];
            if (!iconsWrapper) continue;
            for (let iconWrapper of iconsWrapper.get_children()) {
                this._applyIconScale(iconWrapper, animate);
            }
        }
    }

    _applyIconScale(wrapper, animate) {
        let iconTex = wrapper._iconTex;
        if (!iconTex) return;

        let enabled = this._ext.getFocusScaleEffect();
        let isFocused = wrapper.windowId === this._focusedWindowId;
        let reduction = Math.max(0, Math.min(95, this._ext.getFocusScaleReduction())) / 100;
        let scale = (!enabled || isFocused) ? 1.0 : (1 - reduction);

        if (animate) {
            iconTex.ease({
                scale_x: scale,
                scale_y: scale,
                duration: FOCUS_ANIM_DURATION_MS,
                mode: Clutter.AnimationMode.EASE_OUT_QUAD,
            });
        } else {
            iconTex.scale_x = scale;
            iconTex.scale_y = scale;
        }
    }

    // ===================== OVERFLOW HANDLING =====================

    _scheduleTimeout(ms, callback) {
        if (this._destroyed) return 0;
        let id = GLib.timeout_add(GLib.PRIORITY_DEFAULT, ms, () => {
            this._glibTimeoutIds?.delete(id);
            if (!this._destroyed) callback();
            return GLib.SOURCE_REMOVE;
        });
        this._glibTimeoutIds.add(id);
        return id;
    }

    _updateAvailableWidth() {
        if (!this._viewport || this._destroyed) return;
        let panel = Main.panel;
        if (!panel) return;

        let panelW = panel.get_width();
        if (panelW <= 0) return;

        let siblingsW = 0;
        for (let child of panel._leftBox.get_children()) {
            if (child === this._viewport) continue;
            let [, natW] = child.get_preferred_width(-1);
            siblingsW += natW;
        }

        this._availableWidth = Math.max(120, panelW * VIEWPORT_MAX_PANEL_FRACTION - siblingsW);
        this._applyViewportWidth();
    }

    _applyViewportWidth() {
        if (!this._viewport || !this._container || this._destroyed) return;

        let contentW = this._container.get_width();
        let leftMargin = this._ext.getLeftMargin();
        let avail = this._availableWidth || 600;

        // Without arrow strips reserved: natural content + left margin.
        // When that exceeds the budget, fall back to the budget and let
        // _updateOverlays reserve the strips and enable scrolling.
        let desired = contentW + leftMargin;
        let w = (contentW > 0 && desired <= avail) ? desired : avail;

        this._viewport.set_width(w);
        this._viewport.style = `width: ${w}px; min-width: ${w}px; max-width: ${w}px;`;
        this._updateOverlays();
    }

    _scheduleSync() {
        if (this._destroyed || this._syncPending) return;
        this._syncPending = true;
        this._scheduleTimeout(SYNC_DEBOUNCE_MS, () => {
            this._syncPending = false;
            this._syncContainerWidth();
        });
    }

    _syncContainerWidth() {
        if (!this._container || this._destroyed) return;

        let children = this._container.get_children();
        if (children.length === 0) {
            this._container.set_width(-1);
            this._applyViewportWidth();
            return;
        }

        let total = 0;
        let hasPending = false;
        for (let c of children) {
            let [, natW] = c.get_preferred_width(-1);
            if (natW <= 0) hasPending = true;
            total += natW;
        }

        let preset = this._ext.getPreset();
        let minExpected = children.length * (preset.iconSize + preset.numSpacing * 2 + 8);
        if (hasPending || total < minExpected) {
            this._scheduleTimeout(SYNC_RETRY_MS, () => this._syncContainerWidth());
            return;
        }

        total += (children.length - 1) * (preset.btnSpacing || 6);
        total += 8;

        this._container.set_width(total);
        this._applyViewportWidth();
    }

    _realContentWidth() {
        if (!this._container) return 0;
        let children = this._container.get_children();
        if (children.length === 0) return 0;
        let last = children[children.length - 1].get_allocation_box();
        return last.x2;
    }

    _setScrollOffset(offset) {
        if (!this._viewport || !this._container || !this._clip || this._destroyed) return;

        let innerW = this._clip.get_width();
        if (innerW <= 0) return;

        let contentW = this._realContentWidth();
        let maxOffset = Math.max(0, contentW - innerW);
        this._scrollOffset = Math.max(0, Math.min(maxOffset, offset));
        this._container.set_x(-this._scrollOffset);
        this._updateOverlays();
    }

    _scheduleScrollToActive() {
        if (this._destroyed || !this._viewport) return;
        this._scheduleTimeout(SCROLL_SCHEDULE_MS, () => this._scrollToActive());
    }

    _scrollToActive() {
        if (!this._viewport || !this._container || !this._clip || this._destroyed) return;

        let active = global.workspace_manager.get_active_workspace_index();
        let children = this._container.get_children();
        if (active < 0 || active >= children.length) return;

        let innerW = this._clip.get_width();
        if (innerW <= 0) return;

        let btn = children[active];
        let alloc = btn.get_allocation_box();
        let btnX = alloc.x1;
        let btnW = alloc.x2 - alloc.x1;

        if (btnW <= 0 || (btnX === 0 && active > 0)) {
            this._scheduleTimeout(SCROLL_RETRY_MS, () => this._scrollToActive());
            return;
        }

        let contentW = this._realContentWidth();
        if (contentW <= innerW) {
            this._setScrollOffset(0);
            return;
        }

        let peek = Math.min(30, Math.floor(innerW / 8));
        let viewStart = this._scrollOffset;
        let viewEnd = viewStart + innerW;
        let maxOffset = Math.max(0, contentW - innerW);

        let target = null;
        if (btnX < viewStart + peek) {
            target = Math.max(0, btnX - peek);
        } else if (btnX + btnW > viewEnd - peek) {
            target = btnX + btnW - innerW + peek;
        }

        if (target === null) return;

        target = Math.max(0, Math.min(maxOffset, target));
        this._scrollOffset = target;
        this._container.set_x(-this._scrollOffset);
        this._updateOverlays();
    }

    _updateOverlays() {
        if (!this._viewport || !this._container || !this._clip || this._destroyed) return;
        if (!this._arrowLeft || !this._arrowRight) return;

        let viewW = this._viewport.get_width();
        let viewH = this._viewport.get_height();
        if (viewW <= 0 || viewH <= 0) return;

        let leftMargin = this._ext.getLeftMargin();
        let contentW = this._realContentWidth();

        // Overflow when the content is wider than the viewport minus the left margin.
        // Only then do we reserve the arrow strips; otherwise layout mirrors v1.
        let availForContent = Math.max(0, viewW - leftMargin);
        let hasOverflow = contentW > availForContent + OVERFLOW_TOLERANCE;

        let clipX, clipW;
        if (hasOverflow) {
            clipX = leftMargin + ARROW_STRIP_WIDTH;
            clipW = Math.max(0, viewW - clipX - ARROW_STRIP_WIDTH);
        } else {
            clipX = leftMargin;
            clipW = Math.min(contentW > 0 ? contentW : availForContent, availForContent);
        }

        this._clip.set_position(clipX, 0);
        this._clip.set_width(clipW);
        this._clip.set_height(viewH);

        let [, containerH] = this._container.get_preferred_height(-1);
        let effectiveH = Math.max(viewH, containerH);
        this._container.set_height(effectiveH);
        this._container.set_y(Math.floor((viewH - effectiveH) / 2));

        let [, arrowH] = this._arrowLeft.get_preferred_height(-1);
        let yCenter = Math.max(0, Math.floor((viewH - arrowH) / 2));
        this._arrowLeft.set_position(leftMargin, yCenter);
        this._arrowRight.set_position(Math.max(0, viewW - ARROW_STRIP_WIDTH), yCenter);

        let maxOffset = Math.max(0, contentW - clipW);
        if (!hasOverflow) {
            this._scrollOffset = 0;
        } else if (this._scrollOffset > maxOffset) {
            this._scrollOffset = maxOffset;
        }
        this._container.set_x(-this._scrollOffset);

        this._arrowLeft.visible = hasOverflow && this._scrollOffset > OVERFLOW_TOLERANCE;
        this._arrowRight.visible = hasOverflow && (this._scrollOffset + clipW < contentW - OVERFLOW_TOLERANCE);
    }

    // ===================== INITIAL POPULATION =====================

    _initialPopulation() {
        let nWs = global.workspace_manager.get_n_workspaces();
        for (let wsIndex = 0; wsIndex < nWs; wsIndex++) {
            this._winIdsRepr.push([]);
            this._addWorkspaceButton(wsIndex);

            let windows = this._getWorkspaceWindows(wsIndex);
            for (let windowObj of windows) {
                let winId = windowObj.get_id();
                this._winIdsRepr[wsIndex].push(winId);
                this._addWindowIcon("r", windowObj, wsIndex);
                this._connectStickyListener(windowObj);
            }

            this._addWindowAddedEvent(wsIndex);
        }

        // Add mirror icons for windows already sticky at startup
        for (let entry of this._stickyListenerIds.values()) {
            if (entry.windowObj.is_on_all_workspaces()) {
                this._addStickyMirrors(entry.windowObj);
            }
        }

        this._updateActiveWorkspace();
    }

    // ===================== WORKSPACE BUTTONS =====================

    _addWorkspaceButton(wsIndex) {
        let btnWrapper = new St.BoxLayout({ style_class: "wsb-ws-btn-wrapper", reactive: true });
        btnWrapper.wsIndex = wsIndex;

        let wsNumWrapper = new St.BoxLayout({ style_class: "wsb-ws-num-wrapper" });
        let wsNum = new St.Label({
            text: `${wsIndex + 1}`,
            style_class: "wsb-ws-num-label-elem",
            y_align: Clutter.ActorAlign.CENTER,
        });
        wsNumWrapper.add_child(wsNum);
        btnWrapper.add_child(wsNumWrapper);

        let iconsWrapper = new St.BoxLayout({ style_class: "wsb-icons-wrapper" });
        btnWrapper.add_child(iconsWrapper);

        // DnD: workspace button is both a drop target and a drag source
        let self = this;
        btnWrapper._delegate = {
            handleDragOver(source, actor, x, y) {
                if (!self._container) return DND.DragMotionResult.CONTINUE;
                if (source.windowObj) {
                    if (self._insertionIndicator) {
                        btnWrapper.remove_style_class_name("wsb-ws-btn-drag-hover");
                        return DND.DragMotionResult.CONTINUE;
                    }
                    btnWrapper.add_style_class_name("wsb-ws-btn-drag-hover");
                    return DND.DragMotionResult.MOVE_DROP;
                }
                if (source.wsButton && source.actor !== btnWrapper) {
                    btnWrapper.add_style_class_name("wsb-ws-btn-drag-hover");
                    return DND.DragMotionResult.MOVE_DROP;
                }
                return DND.DragMotionResult.CONTINUE;
            },
            acceptDrop(source) {
                btnWrapper.remove_style_class_name("wsb-ws-btn-drag-hover");
                if (source.windowObj) {
                    source.windowObj.change_workspace_by_index(btnWrapper.wsIndex, false);
                    global.workspace_manager.get_workspace_by_index(btnWrapper.wsIndex).activate(global.get_current_time());
                    self._scheduleWorkspaceCleanup();
                    return true;
                }
                if (source.wsButton) {
                    let srcIdx = source.actor.wsIndex;
                    let tgtIdx = btnWrapper.wsIndex;
                    if (srcIdx === tgtIdx) return false;
                    let wsObj = global.workspace_manager.get_workspace_by_index(srcIdx);
                    global.workspace_manager.reorder_workspace(wsObj, tgtIdx);
                    global.workspace_manager.get_workspace_by_index(tgtIdx).activate(global.get_current_time());
                    self._scheduleWorkspaceCleanup();
                    return true;
                }
                return false;
            },
            actor: btnWrapper,
            wsButton: true,
            getDragActor() {
                return new St.Label({
                    text: `${btnWrapper.wsIndex + 1}`,
                    style_class: 'wsb-ws-num-label-elem',
                    style: 'background-color: rgba(255,255,255,0.2); padding: 4px 10px; border-radius: 6px;',
                });
            },
            getDragActorSource() {
                return btnWrapper;
            },
        };

        let draggable = DND.makeDraggable(btnWrapper);
        draggable.connect('drag-begin', () => {
            btnWrapper.opacity = 128;
            btnWrapper._isDragging = true;
        });
        draggable.connect('drag-end', () => {
            if (!self._container) return;
            btnWrapper.opacity = 255;
            btnWrapper._isDragging = false;
            self._clearDragHover();
        });
        draggable.connect('drag-cancelled', () => {
            if (!self._container) return;
            btnWrapper.opacity = 255;
            btnWrapper._isDragging = false;
            self._clearDragHover();
        });

        this._container.insert_child_at_index(btnWrapper, wsIndex);
        this._updateWsNumbers();

        // Click handler
        btnWrapper.connect("button-release-event", (actor, event) => {
            if (actor._isDragging) return Clutter.EVENT_PROPAGATE;

            let button = event.get_button();

            // Middle click → toggle overview
            if (button === Clutter.BUTTON_MIDDLE) {
                Main.overview.toggle();
                return Clutter.EVENT_STOP;
            }

            if (button !== Clutter.BUTTON_PRIMARY) return Clutter.EVENT_PROPAGATE;

            // Detect if an icon was clicked
            let clickedWindowObj;
            let stage = actor.get_stage();
            let [x, y] = event.get_coords();
            let elemClicked = stage.get_actor_at_pos(Clutter.PickMode.ALL, x, y);
            let curElem = elemClicked;
            while (curElem && curElem !== actor) {
                if (curElem.has_style_class_name && curElem.has_style_class_name('wsb-single-icon-wrapper')) {
                    clickedWindowObj = curElem.windowObj;
                    break;
                }
                curElem = curElem.get_parent();
            }

            // Icon click while in Overview
            if (clickedWindowObj && Main.overview.visible) {
                let focusedWindow = global.display.get_focus_window();
                if (focusedWindow && focusedWindow.get_id() === clickedWindowObj.get_id()) {
                    // Already focused → close overview
                    Main.overview.hide();
                } else {
                    // Not focused → activate window (closes overview naturally)
                    global.workspace_manager.get_workspace_by_index(actor.wsIndex).activate(global.get_current_time());
                    clickedWindowObj.activate(global.get_current_time());
                }
                return Clutter.EVENT_STOP;
            }

            if (actor.wsIndex === global.workspace_manager.get_active_workspace_index() && !clickedWindowObj) {
                Main.overview.toggle();
            } else {
                global.workspace_manager.get_workspace_by_index(actor.wsIndex).activate(global.get_current_time());
            }

            if (clickedWindowObj) {
                clickedWindowObj.get_compositor_private()?.grab_key_focus();
                clickedWindowObj.activate(global.get_current_time());
            }
        });

        return btnWrapper;
    }

    _removeWorkspaceButton(wsIndex) {
        let children = this._container.get_children();
        if (wsIndex < children.length) {
            this._container.remove_child(children[wsIndex]);
        }
        this._updateWsNumbers();
    }

    _updateWsNumbers() {
        if (!this._container) return;
        let children = this._container.get_children();
        for (let i = 0; i < children.length; i++) {
            children[i].wsIndex = i;
            children[i].get_children()[0].get_children()[0].text = `${i + 1}`;
        }
    }

    _updateActiveWorkspace() {
        if (!this._container) return;
        let activeWs = global.workspace_manager.get_active_workspace_index();

        for (let btn of this._container.get_children()) {
            let [numWrapper, iconsWrapper] = btn.get_children();
            if (btn.wsIndex === activeWs) {
                numWrapper.add_style_class_name("wsb-ws-num-wrapper-active");
                iconsWrapper.add_style_class_name("wsb-icons-wrapper-active");
            } else {
                numWrapper.remove_style_class_name("wsb-ws-num-wrapper-active");
                iconsWrapper.remove_style_class_name("wsb-icons-wrapper-active");
            }
        }

        this._scheduleSync();
        this._scheduleScrollToActive();
    }

    // ===================== WINDOW ICONS =====================

    _addWindowIcon(loc, windowObj, wsIndex) {
        let iconElem = this._createWindowIcon(windowObj);
        let iconsWrapper = this._container.get_children()[wsIndex].get_children()[1];
        if (loc === "l") {
            iconsWrapper.insert_child_at_index(iconElem, 0);
        } else {
            // Append primary BEFORE any sticky mirrors so primary indices keep
            // matching _winIdsRepr[ws]
            let firstMirrorIdx = this._findFirstMirrorIndex(iconsWrapper);
            if (firstMirrorIdx < 0) iconsWrapper.add_child(iconElem);
            else iconsWrapper.insert_child_at_index(iconElem, firstMirrorIdx);
        }
        this._scheduleSync();
    }

    _moveWindowIcon(oldWsIndex, oldWinIndex, newWsIndex, newWinIndex) {
        let oldParent = this._container.get_children()[oldWsIndex].get_children()[1];
        let elem = oldParent.get_children()[oldWinIndex];
        oldParent.remove_child(elem);
        let newParent = this._container.get_children()[newWsIndex].get_children()[1];
        newParent.insert_child_at_index(elem, newWinIndex);
    }

    _removeWindowIcon(wsIndex, winIndex) {
        let iconsWrapper = this._container.get_children()[wsIndex].get_children()[1];
        let children = iconsWrapper.get_children();
        if (winIndex < children.length) {
            iconsWrapper.remove_child(children[winIndex]);
        }
        this._scheduleSync();
    }

    _createWindowIcon(windowObj) {
        let iconSize = this._ext.getPreset().iconSize;
        let wrapper = new St.BoxLayout({ style_class: "wsb-single-icon-wrapper", reactive: true });
        wrapper.windowId = windowObj.get_id();
        wrapper.windowObj = windowObj;

        let appObj = Shell.WindowTracker.get_default().get_window_app(windowObj);
        let iconTex = appObj
            ? appObj.create_icon_texture(iconSize)
            : new St.Icon({ icon_name: 'image-missing-symbolic', icon_size: iconSize });
        iconTex.set_pivot_point(0.5, 0.5);
        wrapper.add_child(iconTex);
        wrapper._iconTex = iconTex;
        this._applyIconScale(wrapper, false);

        // DnD: make icon draggable
        let self = this;
        wrapper._delegate = {
            windowObj: windowObj,
            actor: wrapper,
            getDragActor() {
                let dragApp = Shell.WindowTracker.get_default().get_window_app(windowObj);
                if (dragApp) return dragApp.create_icon_texture(iconSize);
                return new St.Icon({ icon_name: 'image-missing-symbolic', icon_size: iconSize });
            },
            getDragActorSource() {
                return wrapper;
            },
        };

        let draggable = DND.makeDraggable(wrapper);
        draggable.connect('drag-begin', () => {
            if (!self._container) return;
            wrapper.opacity = 128;
            self._registerGapDragMonitor(windowObj);
        });
        draggable.connect('drag-end', () => {
            if (!self._container) return;
            wrapper.opacity = 255;
            self._unregisterGapDragMonitor();
            self._clearDragHover();
        });
        draggable.connect('drag-cancelled', () => {
            if (!self._container) return;
            wrapper.opacity = 255;
            self._unregisterGapDragMonitor();
            self._clearDragHover();
        });

        return wrapper;
    }

    _regenerateIcons() {
        if (!this._container) return;
        let allWindows = global.display.get_tab_list(Meta.TabList.NORMAL_ALL, null);
        let windowsMap = {};
        for (let w of allWindows) windowsMap[w.get_id()] = w;

        for (let btn of this._container.get_children()) {
            let iconsWrapper = btn.get_children()[1];
            let icons = iconsWrapper.get_children();
            for (let i = 0; i < icons.length; i++) {
                let winId = icons[i].windowId;
                if (windowsMap[winId]) {
                    let wasMirror = icons[i]._isStickyMirror;
                    let newIcon = this._createWindowIcon(windowsMap[winId]);
                    if (wasMirror) newIcon._isStickyMirror = true;
                    iconsWrapper.replace_child(icons[i], newIcon);
                }
            }
        }
        this._scheduleSync();
    }

    // ===================== WINDOW TRACKING =====================

    _getWorkspaceWindows(wsIndex) {
        let wsObj = global.workspace_manager.get_workspace_by_index(wsIndex);
        let windows = global.display.get_tab_list(Meta.TabList.NORMAL, wsObj);
        return windows.filter(w => {
            if (w.skip_taskbar) return false;
            // Sticky windows: only include on their primary (anchor) workspace,
            // so each window has exactly one entry in _winIdsRepr. Mirror icons
            // for the other workspaces are added separately via _addStickyMirrors.
            if (w.is_on_all_workspaces()) {
                return w.get_workspace()?.index() === wsIndex;
            }
            return true;
        });
    }

    _getWinIdsMeta() {
        let meta = {};
        for (let wsIndex = 0; wsIndex < this._winIdsRepr.length; wsIndex++) {
            for (let winId of this._winIdsRepr[wsIndex]) {
                meta[winId] = { wsIndex };
            }
        }
        return meta;
    }

    // ===================== STICKY WINDOW MIRRORS =====================
    // A sticky ("Always on Visible Workspace") window appears once in _winIdsRepr
    // on its anchor workspace. To make its icon appear in every other workspace
    // button, we add tagged "mirror" icons (_isStickyMirror = true) at the end
    // of the other iconsWrappers. Primary icons keep [0, _winIdsRepr[ws].length)
    // child indices; mirrors always sit at the end so primary indexing stays valid.

    _findPrimaryWsForWindow(winId) {
        for (let i = 0; i < this._winIdsRepr.length; i++) {
            if (this._winIdsRepr[i].includes(winId)) return i;
        }
        return -1;
    }

    _findFirstMirrorIndex(iconsWrapper) {
        let children = iconsWrapper.get_children();
        for (let i = 0; i < children.length; i++) {
            if (children[i]._isStickyMirror) return i;
        }
        return -1;
    }

    _findMirrorIcon(winId, wsIndex) {
        let btn = this._container.get_children()[wsIndex];
        if (!btn) return null;
        let iconsWrapper = btn.get_children()[1];
        if (!iconsWrapper) return null;
        for (let icon of iconsWrapper.get_children()) {
            if (icon.windowId === winId && icon._isStickyMirror) return icon;
        }
        return null;
    }

    _connectStickyListener(windowObj) {
        let winId = windowObj.get_id();
        if (this._stickyListenerIds.has(winId)) return;
        let signalId = windowObj.connect('notify::on-all-workspaces', () => {
            this._onWindowStickyChanged(windowObj);
        });
        this._stickyListenerIds.set(winId, { windowObj, signalId });
    }

    _disconnectStickyListener(winId) {
        let entry = this._stickyListenerIds.get(winId);
        if (!entry) return;
        try { entry.windowObj.disconnect(entry.signalId); } catch (_e) {}
        this._stickyListenerIds.delete(winId);
    }

    _onWindowStickyChanged(windowObj) {
        if (!this._container) return;
        let winId = windowObj.get_id();
        if (windowObj.is_on_all_workspaces()) {
            this._addStickyMirrors(windowObj);
        } else {
            this._removeStickyMirrors(winId);
        }
    }

    _addStickyMirrors(windowObj) {
        if (!this._container) return;
        let winId = windowObj.get_id();
        let primaryWs = this._findPrimaryWsForWindow(winId);
        if (primaryWs < 0) return;
        let nWs = this._container.get_children().length;
        for (let wsIndex = 0; wsIndex < nWs; wsIndex++) {
            if (wsIndex === primaryWs) continue;
            if (this._findMirrorIcon(winId, wsIndex)) continue;
            let iconElem = this._createWindowIcon(windowObj);
            iconElem._isStickyMirror = true;
            let iconsWrapper = this._container.get_children()[wsIndex].get_children()[1];
            iconsWrapper.add_child(iconElem); // append at end keeps primary indices valid
        }
        this._scheduleSync();
    }

    _removeStickyMirrors(winId) {
        if (!this._container) return;
        for (let btn of this._container.get_children()) {
            let iconsWrapper = btn.get_children()[1];
            if (!iconsWrapper) continue;
            for (let icon of iconsWrapper.get_children()) {
                if (icon.windowId === winId && icon._isStickyMirror) {
                    iconsWrapper.remove_child(icon);
                }
            }
        }
        this._scheduleSync();
    }

    // ===================== GNOME SIGNALS =====================

    _connectSignals() {
        // monitors-changed → full rebuild
        this._mainEventIds.layoutManager.push(
            Main.layoutManager.connect('monitors-changed', () => {
                this.destroy(false);
                this._setup();
            })
        );

        // panel width → recompute viewport budget
        this._mainEventIds.panel.push(
            Main.panel.connect('notify::width', () => this._updateAvailableWidth())
        );

        // active-workspace-changed
        this._gnomeEventIds.workspace_manager.push(
            global.workspace_manager.connect("active-workspace-changed", () => {
                this._updateActiveWorkspace();
            })
        );

        // workspace-added
        this._gnomeEventIds.workspace_manager.push(
            global.workspace_manager.connect("workspace-added", (wm, wsIndex) => {
                this._winIdsRepr.splice(wsIndex, 0, []);
                this._addWorkspaceButton(wsIndex);
                this._addWindowAddedEvent(wsIndex);
                // Mirror any existing sticky windows into the new workspace
                for (let entry of this._stickyListenerIds.values()) {
                    if (!entry.windowObj.is_on_all_workspaces()) continue;
                    let winId = entry.windowObj.get_id();
                    if (this._findPrimaryWsForWindow(winId) === wsIndex) continue;
                    let iconElem = this._createWindowIcon(entry.windowObj);
                    iconElem._isStickyMirror = true;
                    let iconsWrapper = this._container.get_children()[wsIndex].get_children()[1];
                    iconsWrapper.add_child(iconElem);
                }
                this._scheduleSync();
            })
        );

        // workspace-removed
        this._gnomeEventIds.workspace_manager.push(
            global.workspace_manager.connect("workspace-removed", (wm, wsIndex) => {
                this._winIdsRepr.splice(wsIndex, 1);
                this._removeWorkspaceButton(wsIndex);
                this._updateActiveWorkspace();
            })
        );

        // workspaces-reordered → full rebuild
        this._gnomeEventIds.workspace_manager.push(
            global.workspace_manager.connect("workspaces-reordered", () => {
                this.destroy(false);
                this._setup();
            })
        );

        // notify::focus-window → animate icon scales
        this._gnomeEventIds.display.push(
            global.display.connect('notify::focus-window', () => {
                this._onFocusWindowChanged();
            })
        );

        // window-created
        this._gnomeEventIds.display.push(
            global.display.connect('window-created', (display, newWindowObj) => {
                let timeoutId = GLib.timeout_add(GLib.PRIORITY_DEFAULT, ICON_TIMEOUT, () => {
                    if (!this._container) {
                        this._glibTimeoutIds?.delete(timeoutId);
                        return GLib.SOURCE_REMOVE;
                    }

                    let newWinId, newWsIndex;
                    try {
                        newWinId = newWindowObj.get_id();
                        newWsIndex = newWindowObj.get_workspace().index();
                    } catch (err) {
                        this._glibTimeoutIds.delete(timeoutId);
                        return GLib.SOURCE_REMOVE;
                    }

                    let wsObj = global.workspace_manager.get_workspace_by_index(newWsIndex);
                    for (let windowObj of global.display.get_tab_list(Meta.TabList.NORMAL, wsObj)) {
                        if (windowObj.get_id() === newWinId) {
                            if (newWindowObj.skip_taskbar) break;
                            if (newWsIndex < this._winIdsRepr.length) {
                                this._winIdsRepr[newWsIndex].unshift(newWinId);
                                this._addWindowIcon("l", newWindowObj, newWsIndex);
                                this._connectStickyListener(newWindowObj);
                                if (newWindowObj.is_on_all_workspaces()) {
                                    this._addStickyMirrors(newWindowObj);
                                }
                            }
                            break;
                        }
                    }

                    this._glibTimeoutIds.delete(timeoutId);
                    return GLib.SOURCE_REMOVE;
                });

                this._glibTimeoutIds.add(timeoutId);
            })
        );

        // window-left-monitor (window closed or moved to another monitor)
        this._gnomeEventIds.display.push(
            global.display.connect('window-left-monitor', (display, oldMonitorIndex, windowObj) => {
                if (!this._container) return;

                let winIdsMeta = this._getWinIdsMeta();
                let windowId = windowObj.get_id();

                if (winIdsMeta[windowId] === undefined) return;

                let oldWsIndex = winIdsMeta[windowId].wsIndex;
                let oldWinIndex = this._winIdsRepr[oldWsIndex].indexOf(windowId);
                if (oldWinIndex < 0) return;

                let newMonitor = windowObj.get_monitor();

                if (newMonitor < 0) {
                    // Window was closed
                    this._removeWindowIcon(oldWsIndex, oldWinIndex);
                    this._winIdsRepr[oldWsIndex].splice(oldWinIndex, 1);
                    // If the window was sticky, also clean up its mirror icons
                    this._removeStickyMirrors(windowId);
                    this._disconnectStickyListener(windowId);
                }
                // If window just moved to another monitor (same workspace), icon stays — nothing to do
            })
        );
    }

    _addWindowAddedEvent(wsIndex) {
        let wsObj = global.workspace_manager.get_workspace_by_index(wsIndex);

        wsObj._wsbWindowAddedId = wsObj.connect('window-added', (workspace, windowObj) => {
            if (!this._container) return;

            let windowId = windowObj.get_id();
            let winIdsMeta = this._getWinIdsMeta();

            if (winIdsMeta[windowId] === undefined) return; // New window — handled by window-created

            let oldWsIndex = winIdsMeta[windowId].wsIndex;
            let newWsIndex = workspace.index();

            if (oldWsIndex === newWsIndex) return;

            let oldWinIndex = this._winIdsRepr[oldWsIndex].indexOf(windowId);
            if (oldWinIndex < 0) return;

            this._moveWindowIcon(oldWsIndex, oldWinIndex, newWsIndex, 0);
            this._winIdsRepr[oldWsIndex].splice(oldWinIndex, 1);
            this._winIdsRepr[newWsIndex].unshift(windowId);
        });
    }

    // ===================== DND HELPERS =====================

    _clearDragHover() {
        if (!this._container) return;
        for (let btn of this._container.get_children()) {
            btn.remove_style_class_name("wsb-ws-btn-drag-hover");
        }
    }

    _scheduleWorkspaceCleanup() {
        let timeoutId = GLib.idle_add(GLib.PRIORITY_DEFAULT, () => {
            try {
                Main.wm._workspaceTracker?._checkWorkspaces();
            } catch (e) {
                console.debug(`[Workspace Bar] workspace cleanup: ${e.message}`);
            }
            this._glibTimeoutIds?.delete(timeoutId);
            return GLib.SOURCE_REMOVE;
        });
        this._glibTimeoutIds.add(timeoutId);
    }

    // ===================== GAP-DROP (create new workspace between buttons) =====================

    _registerGapDragMonitor(windowObj) {
        if (this._gapDragMonitor) return;
        this._gapDropWindowObj = windowObj;
        this._gapDragMonitor = {
            dragMotion: (dragEvent) => this._windowIconDragMotion(dragEvent),
        };
        DND.addDragMonitor(this._gapDragMonitor);
    }

    _unregisterGapDragMonitor() {
        if (this._gapDragMonitor) {
            DND.removeDragMonitor(this._gapDragMonitor);
            this._gapDragMonitor = null;
        }
        this._removeInsertionIndicator();
        this._gapDropWindowObj = null;
    }

    _windowIconDragMotion(dragEvent) {
        if (!this._container) return DND.DragMotionResult.CONTINUE;
        if (!dragEvent.source?.windowObj) return DND.DragMotionResult.CONTINUE;

        let gap = this._detectGapAtPosition(dragEvent.x, dragEvent.y);

        if (gap) {
            if (this._currentInsertIndex !== gap.insertIndex) {
                this._removeInsertionIndicator();
                this._showInsertionIndicator(gap.insertIndex);
            }
            this._clearDragHover();
        } else {
            this._removeInsertionIndicator();
        }

        return DND.DragMotionResult.CONTINUE;
    }

    _detectGapAtPosition(stageX, stageY) {
        if (!this._container) return null;

        let [containerX, containerY] = this._container.get_transformed_position();
        let containerHeight = this._container.get_height();

        if (stageY < containerY || stageY > containerY + containerHeight) return null;

        let children = this._container.get_children();
        if (children.length === 0) return null;

        for (let i = 0; i <= children.length; i++) {
            let gapCenterX;

            if (i === 0) {
                let [btnX] = children[0].get_transformed_position();
                gapCenterX = btnX;
            } else if (i === children.length) {
                let [btnX] = children[i - 1].get_transformed_position();
                gapCenterX = btnX + children[i - 1].get_width();
            } else {
                let [prevX] = children[i - 1].get_transformed_position();
                let prevW = children[i - 1].get_width();
                let [nextX] = children[i].get_transformed_position();
                gapCenterX = (prevX + prevW + nextX) / 2;
            }

            if (Math.abs(stageX - gapCenterX) <= GAP_HALF_WIDTH) {
                return { insertIndex: i };
            }
        }

        return null;
    }

    _showInsertionIndicator(insertIndex) {
        this._removeInsertionIndicator();

        let [containerX, containerY] = this._container.get_transformed_position();
        let containerHeight = this._container.get_height();
        let children = this._container.get_children();

        let indicatorX;
        if (children.length === 0) {
            indicatorX = containerX;
        } else if (insertIndex === 0) {
            let [btnX] = children[0].get_transformed_position();
            indicatorX = btnX - 2;
        } else if (insertIndex >= children.length) {
            let [btnX] = children[children.length - 1].get_transformed_position();
            indicatorX = btnX + children[children.length - 1].get_width() + 2;
        } else {
            let [prevX] = children[insertIndex - 1].get_transformed_position();
            let prevW = children[insertIndex - 1].get_width();
            let [nextX] = children[insertIndex].get_transformed_position();
            indicatorX = (prevX + prevW + nextX) / 2 - 1;
        }

        let inset = 4;
        let hitAreaWidth = GAP_HALF_WIDTH * 2;

        this._insertionIndicator = new St.Widget({
            width: hitAreaWidth,
            height: containerHeight - inset * 2,
            reactive: true,
            layout_manager: new Clutter.BinLayout(),
            // Near-invisible background so Clutter picks this actor for DnD targeting
            style: 'background-color: rgba(0, 0, 0, 0.01);',
        });

        let visualBar = new St.Widget({
            style_class: 'wsb-insertion-indicator',
            width: 5,
            style: 'background-color: white;',
            x_align: Clutter.ActorAlign.CENTER,
            x_expand: true,
            y_expand: true,
        });
        this._insertionIndicator.add_child(visualBar);

        let self = this;
        this._insertionIndicator._delegate = {
            acceptDrop(source) {
                if (!source.windowObj || !self._gapDropWindowObj) return false;

                let windowObj = self._gapDropWindowObj;
                let idx = self._currentInsertIndex;

                self._removeInsertionIndicator();

                let numWs = global.workspace_manager.get_n_workspaces();
                global.workspace_manager.append_new_workspace(false, global.get_current_time());
                let newWsObj = global.workspace_manager.get_workspace_by_index(numWs);
                windowObj.change_workspace_by_index(numWs, false);
                global.workspace_manager.reorder_workspace(newWsObj, idx);
                global.workspace_manager.get_workspace_by_index(idx).activate(global.get_current_time());
                self._scheduleWorkspaceCleanup();

                return true;
            },
            handleDragOver(source) {
                if (source.windowObj) return DND.DragMotionResult.MOVE_DROP;
                return DND.DragMotionResult.CONTINUE;
            },
        };

        Main.uiGroup.add_child(this._insertionIndicator);
        this._insertionIndicator.set_position(
            indicatorX - Math.floor(hitAreaWidth / 2),
            containerY + inset
        );

        this._currentInsertIndex = insertIndex;
    }

    _removeInsertionIndicator() {
        if (this._insertionIndicator) {
            let parent = this._insertionIndicator.get_parent();
            if (parent) parent.remove_child(this._insertionIndicator);
            this._insertionIndicator.destroy();
            this._insertionIndicator = null;
            this._currentInsertIndex = -1;
        }
    }
}
