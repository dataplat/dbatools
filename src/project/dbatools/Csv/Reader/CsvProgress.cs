using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text;
using System.Threading;
using Dataplat.Dbatools.Csv.Compression;
using Dataplat.Dbatools.Csv.TypeConverters;

namespace Dataplat.Dbatools.Csv.Reader
{
    /// <summary>
    /// Provides progress information during CSV reading operations.
    /// </summary>
    public sealed class CsvProgress
    {
        /// <summary>
        /// Gets the number of records read so far.
        /// </summary>
        public long RecordsRead { get; }

        /// <summary>
        /// Gets the current line number in the file.
        /// </summary>
        public long LineNumber { get; }

        /// <summary>
        /// Gets the number of bytes read from the source (if available).
        /// Returns -1 if byte position is not available.
        /// </summary>
        public long BytesRead { get; }

        /// <summary>
        /// Gets the total size of the source in bytes (if available).
        /// Returns -1 if total size is not available.
        /// </summary>
        public long TotalBytes { get; }

        /// <summary>
        /// Gets the percentage complete (0-100) if total size is known, otherwise -1.
        /// </summary>
        public double PercentComplete => TotalBytes > 0 ? (double)BytesRead / TotalBytes * 100.0 : -1;

        /// <summary>
        /// Gets the elapsed time since reading started.
        /// </summary>
        public TimeSpan Elapsed { get; }

        /// <summary>
        /// Gets the estimated rows per second based on current progress.
        /// </summary>
        public double RowsPerSecond => Elapsed.TotalSeconds > 0 ? RecordsRead / Elapsed.TotalSeconds : 0;

        /// <summary>
        /// Creates a new progress instance.
        /// </summary>
        public CsvProgress(long recordsRead, long lineNumber, long bytesRead, long totalBytes, TimeSpan elapsed)
        {
            RecordsRead = recordsRead;
            LineNumber = lineNumber;
            BytesRead = bytesRead;
            TotalBytes = totalBytes;
            Elapsed = elapsed;
        }
    }
}
