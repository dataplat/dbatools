using System;
using System.Buffers;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Data;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Runtime.CompilerServices;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using Dataplat.Dbatools.Csv.Compression;
using Dataplat.Dbatools.Csv.TypeConverters;

namespace Dataplat.Dbatools.Csv.Reader
{
    public sealed partial class CsvDataReader
    {

        /// <summary>
        /// Occurs when a parse error is encountered and ParseErrorAction is RaiseEvent.
        /// </summary>
        public event EventHandler<CsvParseErrorEventArgs> ParseError;



        /// <inheritdoc />
        public int Depth => 0;
        /// <inheritdoc />
        public bool IsClosed => _isClosed;
        /// <inheritdoc />
        public int RecordsAffected => -1;

        /// <inheritdoc />
        public bool NextResult() => false;

        /// <inheritdoc />
        public void Close()
        {
            if (!_isClosed)
            {
                _isClosed = true;

                // Stop parallel pipeline first
                StopParallelPipeline();

                if (_ownsReader)
                {
                    _reader.Dispose();
                }

                // Return pooled buffer ONLY when no read is in flight; a concurrent reader
                // keeps the array (deferred to GC) so it can neither observe a null field nor
                // write through a pool-returned array. The disposed inner reader ends the
                // in-flight read with its own ObjectDisposedException at the next refill.
                lock (_bufferLifecycleLock)
                {
                    if (System.Threading.Interlocked.CompareExchange(ref _activeReads, 0, 0) == 0)
                    {
                        if (_bufferFromPool && _buffer != null)
                        {
                            ArrayPool<char>.Shared.Return(_buffer);
                        }
                        _buffer = null;
                    }
                }
            }
        }

        /// <inheritdoc />
        public void Dispose()
        {
            Close();
        }



        private void ThrowIfClosed()
        {
            if (_isClosed)
                throw new ObjectDisposedException(GetType().Name);
        }

        private void ValidateOrdinal(int ordinal)
        {
            if (ordinal < 0 || ordinal >= _columns.Count + _staticColumns.Count)
                throw new ArgumentOutOfRangeException(nameof(ordinal));
        }

        private void EnsureRecordBufferCapacity(int requiredCapacity)
        {
            if (_recordBuffer == null || _recordBuffer.Length < requiredCapacity)
            {
                int newCapacity = Math.Max(requiredCapacity, 64);
                if (_recordBuffer != null)
                {
                    newCapacity = Math.Max(newCapacity, _recordBuffer.Length * 2);
                }
                _recordBuffer = new string[newCapacity];
                _quotedBuffer = new bool[newCapacity];
            }
        }

    }
}
