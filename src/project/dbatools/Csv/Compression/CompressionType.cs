using System;

namespace Dataplat.Dbatools.Csv.Compression
{
    /// <summary>
    /// Specifies the type of compression used for CSV files.
    /// Addresses issues #8554 and #8646 for compression support.
    /// </summary>
    public enum CompressionType
    {
        /// <summary>
        /// No compression.
        /// </summary>
        None = 0,

        /// <summary>
        /// GZip compression (.gz files).
        /// </summary>
        GZip = 1,

        /// <summary>
        /// Deflate compression.
        /// </summary>
        Deflate = 2,

#if NET8_0_OR_GREATER
        /// <summary>
        /// Brotli compression (.br files).
        /// Only available on .NET Core 2.1+.
        /// </summary>
        Brotli = 3,

        /// <summary>
        /// ZLib compression.
        /// Only available on .NET 6+.
        /// </summary>
        ZLib = 4,
#endif
    }
}
