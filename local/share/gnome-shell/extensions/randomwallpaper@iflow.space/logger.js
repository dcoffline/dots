// https://gitlab.gnome.org/GNOME/gjs/-/blob/master/doc/Logging.md
// Generated code produces a no-shadow rule error
/* eslint-disable */
var LogLevel;
(function (LogLevel) {
    LogLevel[LogLevel["SILENT"] = 0] = "SILENT";
    LogLevel[LogLevel["ERROR"] = 1] = "ERROR";
    LogLevel[LogLevel["WARNING"] = 2] = "WARNING";
    LogLevel[LogLevel["INFO"] = 3] = "INFO";
    LogLevel[LogLevel["DEBUG"] = 4] = "DEBUG";
})(LogLevel || (LogLevel = {}));
/* eslint-enable */
const LOG_PREFIX = 'RandomWallpaper';
/**
 * A convenience logger class.
 */
class Logger {
    /**
     * Helper function to safely log to the console.
     *
     * @param {LogLevel} level the selected log level
     * @param {unknown} message Message to send, ideally an Error() or string
     * @param {object} sourceInstance Object where the log originates from (i.e., the source context)
     */
    static _log(level, message, sourceInstance) {
        if (Logger._selectedLogLevel() < level)
            return;
        let errorMessage = String(message);
        if (message instanceof Error)
            errorMessage = message.message;
        let sourceName = '';
        if (sourceInstance)
            sourceName = ` >> ${sourceInstance.constructor.name}`;
        // This logs messages with GLib.LogLevelFlags.LEVEL_MESSAGE
        console.log(`${LOG_PREFIX} [${LogLevel[level]}]${sourceName} :: ${errorMessage}`);
        // Log stack trace if available
        if (message instanceof Error && message.stack)
            // This logs messages with GLib.LogLevelFlags.LEVEL_WARNING
            console.warn(message);
    }
    /**
     * Get the log level selected by the user.
     *
     * Requires the static SETTINGS member to be set first.
     * Falls back to LogLevel.WARNING if settings object is not set.
     *
     * @returns {LogLevel} Log level
     */
    static _selectedLogLevel() {
        if (Logger.SETTINGS === null) {
            // If settings are not available be verbose
            return LogLevel.DEBUG;
        }
        return Logger.SETTINGS.getInt('log-level');
    }
    /**
     * Log a DEBUG message.
     *
     * @param {unknown} message Message to send, ideally an Error() or string
     * @param {object} sourceInstance Object where the log originates from (i.e., the source context)
     */
    static debug(message, sourceInstance) {
        Logger._log(LogLevel.DEBUG, message, sourceInstance);
    }
    /**
     * Log an INFO message.
     *
     * @param {unknown} message Message to send, ideally an Error() or string
     * @param {object} sourceInstance Object where the log originates from (i.e., the source context)
     */
    static info(message, sourceInstance) {
        Logger._log(LogLevel.INFO, message, sourceInstance);
    }
    /**
     * Log a WARN message.
     *
     * @param {unknown} message Message to send, ideally an Error() or string
     * @param {object} sourceInstance Object where the log originates from (i.e., the source context)
     */
    static warn(message, sourceInstance) {
        Logger._log(LogLevel.WARNING, message, sourceInstance);
    }
    /**
     * Log an ERROR message.
     *
     * @param {unknown} message Message to send, ideally an Error() or string
     * @param {object} sourceInstance Object where the log originates from (i.e., the source context)
     */
    static error(message, sourceInstance) {
        Logger._log(LogLevel.ERROR, message, sourceInstance);
    }
    /**
     * Get a list of human readable enum entries.
     *
     * @returns {string[]} Array with key names
     */
    static getLogLevelNameList() {
        const list = [];
        const values = Object.values(LogLevel).filter(v => !isNaN(Number(v)));
        for (const i of values)
            list.push(`${LogLevel[i]}`);
        return list;
    }
    /**
     * Remove references hold by this class
     */
    static destroy() {
        // clear reference to settings object
        Logger.SETTINGS = null;
    }
}
Logger.SETTINGS = null;
export { Logger };
