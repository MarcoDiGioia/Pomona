// Pomona Touch Bar profiles: writes the id of the focused application to
// $XDG_RUNTIME_DIR/pomona-focus, where pomona-touchbard reads it.
// SPDX-License-Identifier: GPL-3.0-or-later
import GLib from 'gi://GLib';
import Shell from 'gi://Shell';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

const FOCUS_FILE = 'pomona-focus';

export default class PomonaExtension extends Extension {
    enable() {
        this._path = GLib.build_filenamev([GLib.get_user_runtime_dir(), FOCUS_FILE]);
        this._last = null;
        this._signal = global.display.connect('notify::focus-window', () => this._update());
        this._update();
    }

    disable() {
        if (this._signal) {
            global.display.disconnect(this._signal);
            this._signal = null;
        }
        this._write('');
        this._last = null;
    }

    _appId() {
        const win = global.display.focus_window;
        if (!win)
            return '';
        const app = Shell.WindowTracker.get_default().get_window_app(win);
        const id = app ? app.get_id() : null;
        return id || win.get_wm_class() || '';
    }

    _update() {
        const id = this._appId();
        if (id === this._last)
            return;
        this._last = id;
        this._write(id);
    }

    _write(text) {
        try {
            GLib.file_set_contents(this._path, text);
        } catch (e) {
            console.error(`pomona: cannot write ${this._path}: ${e.message}`);
        }
    }
}
