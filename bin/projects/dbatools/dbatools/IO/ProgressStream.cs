using System;
using System.IO;

namespace Sqlcollaborative.Dbatools.IO
{
    /// <summary>
    /// Provides progress callbacks for a stream being read.
    /// </summary>
    public class ProgressStream : Stream
    {
        readonly Stream inner;
        readonly Action<double> callback;
        readonly long progressSize;
        long length;
        long progressAccumulator;

        /// <summary>
        /// Reads the progress of a stream.
        /// </summary>
        public ProgressStream(Stream inner, Action<double> callback, double factor)
        {
            this.inner = inner;
            this.callback = callback;

            this.length = inner.Length;
            this.progressSize = (long)(length * factor);
        }

        /// <summary>
        /// Gets a value indicating whether the current stream supports reading.
        /// </summary>
        public override bool CanRead
        {
            get { return inner.CanRead; }
        }

        /// <summary>
        /// Gets a value indicating whether the current stream supports seeking.
        /// </summary>
        public override bool CanSeek
        {
            get { return inner.CanSeek; }
        }

        /// <summary>
        /// Gets a value indicating whether the current stream supports writing.
        /// </summary>
        public override bool CanWrite
        {
            get { return inner.CanWrite; }
        }

        /// <summary>
        /// Gets the length in bytes of the stream.
        /// </summary>
        public override long Length
        {
            get { return inner.Length; }
        }


        /// <summary>
        /// Gets or sets the position within the current stream.
        /// </summary>
        public override long Position
        {
            get { return inner.Position; }
            set { inner.Position = value; }
        }

        /// <summary>
        /// Clears all buffers for this stream and causes any buffered data to be written to the underlying device.
        /// </summary>
        public override void Flush()
        {
            inner.Flush();
        }

        /// <summary>
        /// Reads a sequence of bytes from the current stream and advances the position within the stream by the number of bytes read.
        /// </summary>
        public override int Read(byte[] buffer, int offset, int count)
        {
            var l = inner.Read(buffer, offset, count);
            progressAccumulator += l;
            bool needsUpdate = false;
            while (progressSize > 0 && progressAccumulator > progressSize)
            {
                progressAccumulator -= progressSize;
                needsUpdate = true;
            }
            if (needsUpdate)
            {
                callback((double)inner.Position / inner.Length);
            }
            return l;
        }

        /// <summary>
        /// Sets the position within the current stream.
        /// </summary>
        public override long Seek(long offset, SeekOrigin origin)
        {
            return inner.Seek(offset, origin);
        }

        /// <summary>
        /// Sets the length of the current stream.
        /// </summary>
        public override void SetLength(long value)
        {
            inner.SetLength(value);
        }

        /// <summary>
        /// Writes a sequence of bytes to the current stream and advances the current position within this stream by the number of bytes written.
        /// </summary>
        public override void Write(byte[] buffer, int offset, int count)
        {
            inner.Write(buffer, offset, count);
        }

        /// <inheritdoc/>
        protected override void Dispose(bool disposing)
        {
            if (disposing)
            {
                inner.Dispose();
            }
        }
    }
}