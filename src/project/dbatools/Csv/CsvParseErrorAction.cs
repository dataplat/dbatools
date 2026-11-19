using System;

namespace Dataplat.Dbatools.Csv
{
    /// <summary>
    /// Specifies the action to take when a parse error occurs during CSV reading.
    /// </summary>
    public enum CsvParseErrorAction
    {
        /// <summary>
        /// Throws an exception when a parse error occurs.
        /// </summary>
        ThrowException = 0,

        /// <summary>
        /// Skips the current line and advances to the next line.
        /// </summary>
        AdvanceToNextLine = 1,

        /// <summary>
        /// Raises an error event and continues based on the event handler's response.
        /// </summary>
        RaiseEvent = 2
    }
}
