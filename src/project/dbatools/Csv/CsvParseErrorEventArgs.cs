using System;

namespace Dataplat.Dbatools.Csv
{
    /// <summary>
    /// Provides data for the ParseError event.
    /// </summary>
    public sealed class CsvParseErrorEventArgs : EventArgs
    {
        /// <summary>
        /// Gets the parse error information.
        /// </summary>
        public CsvParseError Error { get; }

        /// <summary>
        /// Gets or sets the action to take in response to the error.
        /// </summary>
        public CsvParseErrorAction Action { get; set; }

        /// <summary>
        /// Initializes a new instance of the CsvParseErrorEventArgs class.
        /// </summary>
        public CsvParseErrorEventArgs(CsvParseError error, CsvParseErrorAction defaultAction)
        {
            Error = error ?? throw new ArgumentNullException(nameof(error));
            Action = defaultAction;
        }
    }
}
