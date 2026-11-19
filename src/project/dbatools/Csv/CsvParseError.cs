using System;

namespace Dataplat.Dbatools.Csv
{
    /// <summary>
    /// Contains information about a parse error that occurred during CSV reading.
    /// </summary>
    public sealed class CsvParseError
    {
        /// <summary>
        /// Gets the zero-based record index where the error occurred.
        /// </summary>
        public long RecordIndex { get; }

        /// <summary>
        /// Gets the zero-based field index where the error occurred, or -1 if not applicable.
        /// </summary>
        public int FieldIndex { get; }

        /// <summary>
        /// Gets the raw content of the problematic field or line.
        /// </summary>
        public string RawContent { get; }

        /// <summary>
        /// Gets the error message describing what went wrong.
        /// </summary>
        public string Message { get; }

        /// <summary>
        /// Gets the exception that caused the error, if any.
        /// </summary>
        public Exception Exception { get; }

        /// <summary>
        /// Gets the line number in the file where the error occurred (1-based).
        /// </summary>
        public long LineNumber { get; }

        /// <summary>
        /// Gets the character position within the line where the error occurred (1-based).
        /// </summary>
        public int CharPosition { get; }

        /// <summary>
        /// Initializes a new instance of the CsvParseError class.
        /// </summary>
        public CsvParseError(
            long recordIndex,
            int fieldIndex,
            string rawContent,
            string message,
            Exception exception,
            long lineNumber,
            int charPosition)
        {
            RecordIndex = recordIndex;
            FieldIndex = fieldIndex;
            RawContent = rawContent ?? string.Empty;
            Message = message ?? string.Empty;
            Exception = exception;
            LineNumber = lineNumber;
            CharPosition = charPosition;
        }

        /// <summary>
        /// Returns a string representation of this parse error.
        /// </summary>
        public override string ToString()
        {
            return $"Parse error at record {RecordIndex}, field {FieldIndex}, line {LineNumber}: {Message}";
        }
    }
}
