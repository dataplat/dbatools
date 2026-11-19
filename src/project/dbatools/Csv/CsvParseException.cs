using System;

namespace Dataplat.Dbatools.Csv
{
    /// <summary>
    /// Exception thrown when a CSV parsing error occurs.
    /// </summary>
    public sealed class CsvParseException : Exception
    {
        /// <summary>
        /// Gets the parse error information associated with this exception.
        /// </summary>
        public CsvParseError ParseError { get; }

        /// <summary>
        /// Gets or sets whether this exception was thrown because the maximum error count was exceeded.
        /// </summary>
        public bool IsMaxErrorsExceeded { get; set; }

        /// <summary>
        /// Initializes a new instance of the CsvParseException class.
        /// </summary>
        public CsvParseException() : base("CSV parsing error")
        {
        }

        /// <summary>
        /// Initializes a new instance of the CsvParseException class with a message.
        /// </summary>
        public CsvParseException(string message) : base(message)
        {
        }

        /// <summary>
        /// Initializes a new instance of the CsvParseException class with a message and inner exception.
        /// </summary>
        public CsvParseException(string message, Exception innerException) : base(message, innerException)
        {
        }

        /// <summary>
        /// Initializes a new instance of the CsvParseException class with a message and parse error.
        /// </summary>
        public CsvParseException(string message, CsvParseError error) : base(message)
        {
            ParseError = error;
        }

        /// <summary>
        /// Initializes a new instance of the CsvParseException class with a message, parse error, and inner exception.
        /// </summary>
        public CsvParseException(string message, CsvParseError error, Exception innerException) : base(message, innerException)
        {
            ParseError = error;
        }

        /// <summary>
        /// Returns a string representation of this exception.
        /// </summary>
        public override string ToString()
        {
            if (ParseError != null)
            {
                return $"{Message}\n{ParseError}\n{base.ToString()}";
            }
            return base.ToString();
        }
    }
}
