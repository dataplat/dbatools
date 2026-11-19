namespace Dataplat.Dbatools.Csv.Reader
{
    /// <summary>
    /// Specifies how to handle quoting in CSV fields.
    /// </summary>
    public enum QuoteMode
    {
        /// <summary>
        /// Strict RFC 4180 compliant parsing.
        /// Quotes must properly enclose fields and be escaped by doubling (e.g., "" for a literal quote).
        /// This is the default and recommended mode for trusted data sources.
        /// </summary>
        Strict,

        /// <summary>
        /// Lenient parsing that handles common real-world malformed data.
        /// <para>
        /// Features:
        /// <list type="bullet">
        /// <item>A quote only starts a quoted field if it's at the field start AND has a matching closing quote.</item>
        /// <item>Unmatched quotes are treated as literal characters.</item>
        /// <item>Handles both RFC 4180 escaped quotes ("") and backslash-escaped quotes (\").</item>
        /// </list>
        /// </para>
        /// <para>
        /// <b>Security Considerations:</b>
        /// Lenient mode deviates from RFC 4180 and may parse data differently than strict parsers.
        /// This could lead to:
        /// <list type="bullet">
        /// <item>Inconsistent parsing results between systems using different parsers.</item>
        /// <item>Potential for specially crafted input to be interpreted differently than expected.</item>
        /// <item>Performance overhead from additional scanning to validate quote matching.</item>
        /// </list>
        /// Use only when processing data from sources known to produce malformed CSV, and validate
        /// results when possible. For untrusted data sources, prefer <see cref="Strict"/> mode.
        /// </para>
        /// </summary>
        Lenient
    }
}
