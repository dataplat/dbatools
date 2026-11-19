using Dataplat.Dbatools.Commands;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace Dataplat.Dbatools.Commands.Test
{
    /// <summary>
    /// Covers the absorbed Get-AdjustedTotalRowsCopied helper carried by both
    /// ImportDbaCsvCommand and WriteDbaDbTableDataCommand. The legacy bulk copy library
    /// tracks rows copied in a 4-byte counter that wraps past int.MaxValue
    /// (dataplat/dbatools#6927); the helper reconstructs the rows-added delta from
    /// the wrapped reported value and the previously reported value. Expected values are
    /// ground-truthed against the PowerShell helper on both editions with Int64-typed
    /// inputs. Three call sites feed these methods: both commands' progress handlers pass
    /// SqlRowsCopiedEventArgs.RowsCopied (Int64) and a long previous field, and
    /// ImportDbaCsvCommand's final count passes the int result of the reflection read
    /// (GetBulkRowsCopiedCount, -1 on failure) widened to long - so every compiled input
    /// arrives as long and stays inside the int32 counter domain plus the -1 sentinel.
    /// Known divergence, accepted: the PowerShell helper receives that final count
    /// Int32-typed, and for a reported value of exactly int.MinValue with a negative
    /// previous, [math]::Abs binds the Int32 overload and throws OverflowException where
    /// this long version returns a negative delta (probed on both editions). Reaching it
    /// requires the reflected counter to read exactly int.MinValue at the final read.
    /// Math.Abs(long) has the same guard at long.MinValue - both copies throw there -
    /// but that magnitude is outside anything a wrapped int32 counter can produce.
    /// </summary>
    [TestClass]
    public class AdjustedRowsCopiedTest
    {
        private static readonly long[][] GroundTruth = new[]
        {
            // { reportedRowsCopied, previousRowsCopied, expected }
            new[] { 100L, 0L, 100L },
            new[] { 5L, -10L, 15L },
            new[] { -2147483648L, 2147483647L, 1L },
            new[] { -2147483643L, 2147483647L, 6L },
            new[] { -5L, -10L, 5L },
            new[] { 0L, 12345L, 0L },
            new[] { 0L, -12345L, 0L },
            new[] { 7L, -2147483648L, 2147483655L },
            new[] { -2147483000L, 1000000L, 2146484296L },
            // The reflection-read failure sentinel: -1 reported with a non-negative
            // previous takes the positive-to-negative wrap branch and adds 4294967295
            // phantom rows to the total. The PowerShell source does the same; the
            // shipped behavior is pinned, not fixed.
            new[] { -1L, 0L, 4294967295L },
            // A counter moving backward while negative yields a NEGATIVE delta in the
            // source; the shipped behavior is preserved rather than clamped.
            new[] { -10L, -5L, -5L },
        };

        [TestMethod]
        public void AdjustedRows_ImportCopyMatchesGroundTruth()
        {
            foreach (long[] c in GroundTruth)
            {
                Assert.AreEqual(c[2], ImportDbaCsvCommand.GetAdjustedTotalRowsCopied(c[0], c[1]),
                    $"reported={c[0]} previous={c[1]}");
            }
        }

        [TestMethod]
        public void AdjustedRows_WriteCopyMatchesGroundTruth()
        {
            foreach (long[] c in GroundTruth)
            {
                Assert.AreEqual(c[2], WriteDbaDbTableDataCommand.GetAdjustedTotalRowsCopied(c[0], c[1]),
                    $"reported={c[0]} previous={c[1]}");
            }
        }

        [TestMethod]
        public void AdjustedRows_BothCopiesAgreeAcrossBoundarySweep()
        {
            // Pure drift guard: the two copies are character-identical today, so equal
            // outputs carry no correctness signal - the sweep exists to catch a future
            // edit landing in one copy only. Values outside the int32 counter domain
            // wrap unchecked, identically in both copies. long.MinValue is excluded
            // here because Math.Abs throws on it in both copies; that shape is pinned
            // separately below.
            long[] interesting = new[]
            {
                long.MinValue + 1, (long)int.MinValue, int.MinValue + 1L, -2147483000L,
                -12345L, -10L, -5L, -1L, 0L, 1L, 5L, 10L, 12345L, 1000000L,
                int.MaxValue - 1L, (long)int.MaxValue, long.MaxValue - 1,
            };
            foreach (long reported in interesting)
            {
                foreach (long previous in interesting)
                {
                    long importResult = ImportDbaCsvCommand.GetAdjustedTotalRowsCopied(reported, previous);
                    long writeResult = WriteDbaDbTableDataCommand.GetAdjustedTotalRowsCopied(reported, previous);
                    Assert.AreEqual(importResult, writeResult,
                        $"copy drift at reported={reported} previous={previous}");
                }
            }
        }

        [TestMethod]
        public void AdjustedRows_Int32MinValueReportedReturnsWhereScriptThrows()
        {
            // The accepted divergence pinned as a value contract: an Int32-typed
            // reported value of exactly int.MinValue with a negative previous makes the
            // PowerShell helper throw ([math]::Abs binds the Int32 overload), while the
            // long parameters here compute Abs(previous) - Abs(reported) = -2147483643
            // (probed on both editions). If either copy starts throwing or returning
            // something else, the documented contract changed.
            Assert.AreEqual(-2147483643L, ImportDbaCsvCommand.GetAdjustedTotalRowsCopied(int.MinValue, -5));
            Assert.AreEqual(-2147483643L, WriteDbaDbTableDataCommand.GetAdjustedTotalRowsCopied(int.MinValue, -5));
        }

        [TestMethod]
        public void AdjustedRows_BothCopiesThrowAtLongMinValuePrevious()
        {
            // Math.Abs(long) guards long.MinValue with an OverflowException regardless
            // of checked context; a positive report with a long.MinValue previous hits
            // Math.Abs(previous) in both copies. The magnitude is outside anything a
            // wrapped int32 counter can produce - pinned so a future rewrite that stops
            // throwing is a visible contract change, not silent drift.
            Assert.ThrowsException<System.OverflowException>(
                () => ImportDbaCsvCommand.GetAdjustedTotalRowsCopied(7, long.MinValue));
            Assert.ThrowsException<System.OverflowException>(
                () => WriteDbaDbTableDataCommand.GetAdjustedTotalRowsCopied(7, long.MinValue));
        }

        [TestMethod]
        public void AdjustedRows_ZeroReportedIsAlwaysZero()
        {
            // Neither branch of the source runs when the reported value is zero, so the
            // delta is zero regardless of the previous value.
            Assert.AreEqual(0L, ImportDbaCsvCommand.GetAdjustedTotalRowsCopied(0, long.MaxValue - 1));
            Assert.AreEqual(0L, ImportDbaCsvCommand.GetAdjustedTotalRowsCopied(0, long.MinValue + 1));
            Assert.AreEqual(0L, WriteDbaDbTableDataCommand.GetAdjustedTotalRowsCopied(0, long.MaxValue - 1));
            Assert.AreEqual(0L, WriteDbaDbTableDataCommand.GetAdjustedTotalRowsCopied(0, long.MinValue + 1));
        }

        [TestMethod]
        public void AdjustedRows_FullWrapCycleAccumulatesShippedTotals()
        {
            // Drive a simulated counter through a full wrap the way the bulk copy event
            // stream does: accumulate deltas across the positive climb, the wrap to
            // int.MinValue, and the climb back toward zero. Totals match the true
            // (unwrapped) row count at every step EXCEPT a zero report: a counter that
            // reaches exactly 0 again (2^32 rows) hits the helper's reported==0
            // short-circuit and the completing row is not counted - the source behaves
            // the same way, so the undercount is pinned as shipped behavior, not fixed.
            long total = 0;
            long previous = 0;
            long[] reportedSequence = new[] { 1000000000L, 2000000000L, 2147483647L, -2147483648L, -2000000000L, -1L, 0L };
            long[] expectedTotals = new[] { 1000000000L, 2000000000L, 2147483647L, 2147483648L, 2294967296L, 4294967295L, 4294967295L };
            for (int i = 0; i < reportedSequence.Length; i++)
            {
                total += ImportDbaCsvCommand.GetAdjustedTotalRowsCopied(reportedSequence[i], previous);
                previous = reportedSequence[i];
                Assert.AreEqual(expectedTotals[i], total, $"after reported={reportedSequence[i]}");
            }
        }
    }
}
