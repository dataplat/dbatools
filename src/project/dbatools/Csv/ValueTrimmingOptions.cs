using System;

namespace Dataplat.Dbatools.Csv
{
    /// <summary>
    /// Specifies which values should have leading and trailing whitespace trimmed.
    /// </summary>
    [Flags]
    public enum ValueTrimmingOptions
    {
        /// <summary>
        /// No trimming is performed.
        /// </summary>
        None = 0,

        /// <summary>
        /// Trim unquoted field values only.
        /// </summary>
        UnquotedOnly = 1,

        /// <summary>
        /// Trim quoted field values only.
        /// </summary>
        QuotedOnly = 2,

        /// <summary>
        /// Trim all field values (both quoted and unquoted).
        /// </summary>
        All = UnquotedOnly | QuotedOnly
    }
}
