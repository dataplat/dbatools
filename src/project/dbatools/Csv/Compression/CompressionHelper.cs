using System;
using System.IO;
using System.IO.Compression;
using Dataplat.Dbatools.Csv.Reader;
using Dataplat.Dbatools.Csv.Writer;

namespace Dataplat.Dbatools.Csv.Compression
{
    /// <summary>
    /// Helper class for detecting and handling compressed streams.
    /// Addresses issues #8554 and #8646 for compression support.
    /// </summary>
    public static class CompressionHelper
    {
        /// <summary>
        /// Default maximum decompressed size (10 GB) to prevent decompression bombs.
        /// Large enough for most legitimate files, small enough to catch obvious bombs.
        /// </summary>
        public const long DefaultMaxDecompressedSize = 10L * 1024 * 1024 * 1024;

        // Magic bytes for compression detection
        private static readonly byte[] GZipMagic = new byte[] { 0x1F, 0x8B };
        private static readonly byte[] DeflateZlibMagic = new byte[] { 0x78 }; // 0x78 0x01, 0x78 0x5E, 0x78 0x9C, 0x78 0xDA

        /// <summary>
        /// Detects the compression type from a file path based on extension.
        /// </summary>
        public static CompressionType DetectFromExtension(string filePath)
        {
            if (string.IsNullOrEmpty(filePath))
                return CompressionType.None;

            string ext = Path.GetExtension(filePath).ToLowerInvariant();

            switch (ext)
            {
                case ".gz":
                case ".gzip":
                    return CompressionType.GZip;

                case ".deflate":
                    return CompressionType.Deflate;

#if NET8_0_OR_GREATER
                case ".br":
                case ".brotli":
                    return CompressionType.Brotli;

                case ".zlib":
                case ".zl":
                    return CompressionType.ZLib;
#endif
                default:
                    return CompressionType.None;
            }
        }

        /// <summary>
        /// Detects the compression type from the stream's magic bytes.
        /// Note: The stream must be seekable for this to work.
        /// </summary>
        public static CompressionType DetectFromStream(Stream stream)
        {
            if (stream == null || !stream.CanRead)
                return CompressionType.None;

            if (!stream.CanSeek)
                return CompressionType.None;

            long originalPosition = stream.Position;
            try
            {
                byte[] header = new byte[2];
                int bytesRead = stream.Read(header, 0, 2);

                if (bytesRead < 2)
                    return CompressionType.None;

                // Check GZip magic
                if (header[0] == GZipMagic[0] && header[1] == GZipMagic[1])
                    return CompressionType.GZip;

                // Check for ZLib/Deflate (various compression levels)
                if (header[0] == 0x78 && (header[1] == 0x01 || header[1] == 0x5E || header[1] == 0x9C || header[1] == 0xDA))
                {
#if NET8_0_OR_GREATER
                    return CompressionType.ZLib;
#else
                    return CompressionType.Deflate;
#endif
                }

                return CompressionType.None;
            }
            finally
            {
                stream.Position = originalPosition;
            }
        }

        /// <summary>
        /// Wraps a stream with the appropriate decompression stream.
        /// Uses DefaultMaxDecompressedSize (10GB) limit by default.
        /// </summary>
        public static Stream WrapForDecompression(Stream stream, CompressionType compressionType)
        {
            return WrapForDecompression(stream, compressionType, DefaultMaxDecompressedSize);
        }

        /// <summary>
        /// Wraps a stream with the appropriate decompression stream with size limit protection.
        /// </summary>
        /// <param name="stream">The compressed stream to wrap.</param>
        /// <param name="compressionType">The type of compression used.</param>
        /// <param name="maxDecompressedSize">Maximum allowed decompressed size in bytes. Use 0 for unlimited.</param>
        /// <returns>A decompression stream, optionally wrapped with size limiting.</returns>
        /// <exception cref="InvalidOperationException">Thrown when decompressed data exceeds the size limit.</exception>
        public static Stream WrapForDecompression(Stream stream, CompressionType compressionType, long maxDecompressedSize)
        {
            if (stream == null)
                throw new ArgumentNullException(nameof(stream));

            Stream decompressedStream;
            switch (compressionType)
            {
                case CompressionType.None:
                    return stream;

                case CompressionType.GZip:
                    decompressedStream = new GZipStream(stream, CompressionMode.Decompress, leaveOpen: false);
                    break;

                case CompressionType.Deflate:
                    decompressedStream = new DeflateStream(stream, CompressionMode.Decompress, leaveOpen: false);
                    break;

#if NET8_0_OR_GREATER
                case CompressionType.Brotli:
                    decompressedStream = new BrotliStream(stream, CompressionMode.Decompress, leaveOpen: false);
                    break;

                case CompressionType.ZLib:
                    decompressedStream = new ZLibStream(stream, CompressionMode.Decompress, leaveOpen: false);
                    break;
#endif
                default:
                    throw new ArgumentException($"Unknown compression type: {compressionType}", nameof(compressionType));
            }

            // Wrap with size-limiting stream if a limit is specified
            if (maxDecompressedSize > 0)
            {
                return new LimitedReadStream(decompressedStream, maxDecompressedSize);
            }

            return decompressedStream;
        }

        /// <summary>
        /// Wraps a stream with the appropriate compression stream.
        /// </summary>
        public static Stream WrapForCompression(Stream stream, CompressionType compressionType, CompressionLevel level = CompressionLevel.Optimal)
        {
            if (stream == null)
                throw new ArgumentNullException(nameof(stream));

            switch (compressionType)
            {
                case CompressionType.None:
                    return stream;

                case CompressionType.GZip:
                    return new GZipStream(stream, level, leaveOpen: false);

                case CompressionType.Deflate:
                    return new DeflateStream(stream, level, leaveOpen: false);

#if NET8_0_OR_GREATER
                case CompressionType.Brotli:
                    return new BrotliStream(stream, level, leaveOpen: false);

                case CompressionType.ZLib:
                    return new ZLibStream(stream, level, leaveOpen: false);
#endif
                default:
                    throw new ArgumentException($"Unknown compression type: {compressionType}", nameof(compressionType));
            }
        }

        /// <summary>
        /// Gets the recommended file extension for a compression type.
        /// </summary>
        public static string GetFileExtension(CompressionType compressionType)
        {
            switch (compressionType)
            {
                case CompressionType.None:
                    return "";
                case CompressionType.GZip:
                    return ".gz";
                case CompressionType.Deflate:
                    return ".deflate";
#if NET8_0_OR_GREATER
                case CompressionType.Brotli:
                    return ".br";
                case CompressionType.ZLib:
                    return ".zlib";
#endif
                default:
                    return "";
            }
        }

        /// <summary>
        /// Opens a file stream with automatic decompression detection.
        /// Uses DefaultMaxDecompressedSize (10GB) limit by default.
        /// </summary>
        public static Stream OpenFileForReading(string filePath, bool autoDetect = true)
        {
            return OpenFileForReading(filePath, autoDetect, DefaultMaxDecompressedSize);
        }

        /// <summary>
        /// Opens a file stream with automatic decompression detection and optional size limit.
        /// </summary>
        /// <param name="filePath">The path to the file to open.</param>
        /// <param name="autoDetect">Whether to auto-detect compression from magic bytes.</param>
        /// <param name="maxDecompressedSize">Maximum decompressed size in bytes. Use 0 for unlimited.</param>
        public static Stream OpenFileForReading(string filePath, bool autoDetect, long maxDecompressedSize)
        {
            if (string.IsNullOrEmpty(filePath))
                throw new ArgumentNullException(nameof(filePath));

            Stream fileStream = new FileStream(filePath, FileMode.Open, FileAccess.Read, FileShare.Read,
                bufferSize: CsvReaderOptions.DefaultBufferSize, FileOptions.SequentialScan);

            CompressionType compressionType;

            if (autoDetect)
            {
                // First try extension
                compressionType = DetectFromExtension(filePath);

                // If no extension match, try magic bytes
                if (compressionType == CompressionType.None)
                {
                    compressionType = DetectFromStream(fileStream);
                }
            }
            else
            {
                compressionType = DetectFromExtension(filePath);
            }

            return WrapForDecompression(fileStream, compressionType, maxDecompressedSize);
        }

        /// <summary>
        /// Opens a file stream for writing with the specified compression.
        /// </summary>
        public static Stream OpenFileForWriting(string filePath, CompressionType compressionType, CompressionLevel level = CompressionLevel.Optimal)
        {
            if (string.IsNullOrEmpty(filePath))
                throw new ArgumentNullException(nameof(filePath));

            Stream fileStream = new FileStream(filePath, FileMode.Create, FileAccess.Write, FileShare.None,
                bufferSize: CsvWriterOptions.DefaultBufferSize, FileOptions.SequentialScan);

            return WrapForCompression(fileStream, compressionType, level);
        }
    }

    /// <summary>
    /// A stream wrapper that limits the total number of bytes that can be read.
    /// Used to prevent decompression bomb attacks.
    /// </summary>
    internal sealed class LimitedReadStream : Stream
    {
        private readonly Stream _innerStream;
        private readonly long _maxBytes;
        private long _totalBytesRead;

        public LimitedReadStream(Stream innerStream, long maxBytes)
        {
            _innerStream = innerStream ?? throw new ArgumentNullException(nameof(innerStream));
            _maxBytes = maxBytes;
        }

        public override bool CanRead => _innerStream.CanRead;
        public override bool CanSeek => false;
        public override bool CanWrite => false;
        public override long Length => throw new NotSupportedException();
        public override long Position
        {
            get => _totalBytesRead;
            set => throw new NotSupportedException();
        }

        public override int Read(byte[] buffer, int offset, int count)
        {
            int bytesRead = _innerStream.Read(buffer, offset, count);
            _totalBytesRead += bytesRead;

            if (_totalBytesRead > _maxBytes)
            {
                throw new InvalidOperationException(
                    $"Decompressed data exceeded maximum allowed size of {_maxBytes:N0} bytes. " +
                    "This may indicate a decompression bomb attack or corrupted data.");
            }

            return bytesRead;
        }

        public override void Flush() => _innerStream.Flush();
        public override long Seek(long offset, SeekOrigin origin) => throw new NotSupportedException();
        public override void SetLength(long value) => throw new NotSupportedException();
        public override void Write(byte[] buffer, int offset, int count) => throw new NotSupportedException();

        protected override void Dispose(bool disposing)
        {
            if (disposing)
            {
                _innerStream.Dispose();
            }
            base.Dispose(disposing);
        }
    }
}
