namespace Dataplat.Dbatools.Csv.Reader
{
    /// <summary>
    /// Specifies how to handle rows with a different number of fields than expected.
    /// </summary>
    public enum MismatchedFieldAction
    {
        /// <summary>
        /// Throw an exception when the field count doesn't match the header count.
        /// This is the default behavior.
        /// </summary>
        ThrowException,

        /// <summary>
        /// Pad missing fields with null values.
        /// Rows with fewer fields than headers will have nulls appended.
        /// </summary>
        PadWithNulls,

        /// <summary>
        /// Truncate extra fields.
        /// Rows with more fields than headers will have extra fields ignored.
        /// </summary>
        TruncateExtra,

        /// <summary>
        /// Both pad missing fields with nulls and truncate extra fields.
        /// This is the most lenient option for handling messy data.
        /// </summary>
        PadOrTruncate
    }
}
