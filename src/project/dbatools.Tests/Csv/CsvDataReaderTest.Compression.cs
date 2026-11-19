using System;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Text;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using Dataplat.Dbatools.Csv;
using Dataplat.Dbatools.Csv.Reader;

namespace Dataplat.Dbatools.Csv.Tests
{
    public partial class CsvDataReaderTest
    {

        [TestMethod]
        public void TestDecompressionBombProtection_ThrowsWhenExceeded()
        {
            // Create CSV data that will exceed the size limit when decompressed
            var csvBuilder = new StringBuilder();
            csvBuilder.AppendLine("Name,Value");
            for (int i = 0; i < 100; i++)
            {
                csvBuilder.AppendLine(String.Format("Row{0},SomeDataThatRepeatsWell", i));
            }
            string csvData = csvBuilder.ToString();
            byte[] uncompressedBytes = Encoding.UTF8.GetBytes(csvData);

            // Compress the data using GZip
            byte[] compressedBytes;
            using (var compressedStream = new MemoryStream())
            {
                using (var gzipStream = new GZipStream(compressedStream, CompressionLevel.Optimal, leaveOpen: true))
                {
                    gzipStream.Write(uncompressedBytes, 0, uncompressedBytes.Length);
                }
                compressedBytes = compressedStream.ToArray();
            }

            // Set a size limit smaller than the uncompressed data
            var options = new CsvReaderOptions
            {
                MaxDecompressedSize = uncompressedBytes.Length / 2 // Limit to half the actual size
            };

            // Use CompressionHelper to decompress with limit
            using (var compressedInput = new MemoryStream(compressedBytes))
            {
                var decompressedStream = Dataplat.Dbatools.Csv.Compression.CompressionHelper.WrapForDecompression(
                    compressedInput,
                    Dataplat.Dbatools.Csv.Compression.CompressionType.GZip,
                    options.MaxDecompressedSize);

                using (var reader = new StreamReader(decompressedStream))
                {
                    var ex = Assert.ThrowsException<InvalidOperationException>(() =>
                    {
                        // Read all content to trigger the bomb protection
                        reader.ReadToEnd();
                    });

                    Assert.IsTrue(ex.Message.Contains("Decompressed data exceeded maximum allowed size"),
                        String.Format("Expected bomb protection message, got: {0}", ex.Message));
                    Assert.IsTrue(ex.Message.Contains("decompression bomb"),
                        String.Format("Expected 'decompression bomb' in message, got: {0}", ex.Message));
                }
            }
        }

        [TestMethod]
        public void TestDecompressionBombProtection_AllowsWithinLimit()
        {
            // Create small CSV data
            string csvData = "Name,Value\nRow1,Data1\nRow2,Data2\n";
            byte[] uncompressedBytes = Encoding.UTF8.GetBytes(csvData);

            // Compress the data
            byte[] compressedBytes;
            using (var compressedStream = new MemoryStream())
            {
                using (var gzipStream = new GZipStream(compressedStream, CompressionLevel.Optimal, leaveOpen: true))
                {
                    gzipStream.Write(uncompressedBytes, 0, uncompressedBytes.Length);
                }
                compressedBytes = compressedStream.ToArray();
            }

            // Set a size limit larger than the uncompressed data
            long sizeLimit = uncompressedBytes.Length * 2;

            using (var compressedInput = new MemoryStream(compressedBytes))
            {
                var decompressedStream = Dataplat.Dbatools.Csv.Compression.CompressionHelper.WrapForDecompression(
                    compressedInput,
                    Dataplat.Dbatools.Csv.Compression.CompressionType.GZip,
                    sizeLimit);

                using (var reader = new StreamReader(decompressedStream))
                {
                    // Should not throw - data is within limit
                    string content = reader.ReadToEnd();
                    Assert.IsTrue(content.Contains("Row1,Data1"));
                    Assert.IsTrue(content.Contains("Row2,Data2"));
                }
            }
        }

        [TestMethod]
        public void TestDecompressionBombProtection_UnlimitedWhenZero()
        {
            // Create CSV data
            string csvData = "Name,Value\nRow1,Data1\n";
            byte[] uncompressedBytes = Encoding.UTF8.GetBytes(csvData);

            // Compress the data
            byte[] compressedBytes;
            using (var compressedStream = new MemoryStream())
            {
                using (var gzipStream = new GZipStream(compressedStream, CompressionLevel.Optimal, leaveOpen: true))
                {
                    gzipStream.Write(uncompressedBytes, 0, uncompressedBytes.Length);
                }
                compressedBytes = compressedStream.ToArray();
            }

            // Set limit to 0 (unlimited)
            using (var compressedInput = new MemoryStream(compressedBytes))
            {
                var decompressedStream = Dataplat.Dbatools.Csv.Compression.CompressionHelper.WrapForDecompression(
                    compressedInput,
                    Dataplat.Dbatools.Csv.Compression.CompressionType.GZip,
                    maxDecompressedSize: 0); // Unlimited

                using (var reader = new StreamReader(decompressedStream))
                {
                    // Should not throw even with 0 limit (means unlimited)
                    string content = reader.ReadToEnd();
                    Assert.IsTrue(content.Contains("Row1,Data1"));
                }
            }
        }

    }
}
