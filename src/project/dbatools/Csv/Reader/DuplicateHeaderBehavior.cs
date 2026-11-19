namespace Dataplat.Dbatools.Csv.Reader
{
    /// <summary>
    /// Specifies how to handle duplicate column headers in CSV files.
    /// </summary>
    public enum DuplicateHeaderBehavior
    {
        /// <summary>
        /// Throw an exception when duplicate headers are encountered.
        /// This is the default behavior.
        /// </summary>
        ThrowException,

        /// <summary>
        /// Automatically rename duplicate headers by appending a numeric suffix.
        /// For example: Name, Name_2, Name_3.
        /// </summary>
        Rename,

        /// <summary>
        /// Use the first occurrence of the header and ignore subsequent duplicates.
        /// Data from duplicate columns will be discarded.
        /// </summary>
        UseFirstOccurrence,

        /// <summary>
        /// Use the last occurrence of the header.
        /// Earlier occurrences will be renamed with numeric suffixes.
        /// </summary>
        UseLastOccurrence
    }
}
