using System;
using System.Collections.Generic;
using System.Linq;
using System.Management.Automation;
using Dataplat.Dbatools.Utility;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace Dataplat.Dbatools.Utility.Test
{
    /// <summary>
    /// TB-004 coverage for CollationSensitiveFilter.Compare, the C# parity port of
    /// private/functions/Compare-DbaCollationSensitiveObject.ps1. The SMO comparer comes
    /// from an unconnected Server, so everything runs offline: case-insensitive vs
    /// case-sensitive collations drive the In/NotIn/Eq/Ne legs, and the helper's quirks
    /// are pinned - PS-falsy items skipped, null-Value foreach semantics (In yields
    /// nothing, NotIn yields everything), missing-property-compares-as-null, PSObject
    /// inputs, lazy emission in input order, and invalid-collation faulting before
    /// enumeration.
    /// </summary>
    [TestClass]
    public class CollationSensitiveFilterTest
    {
        private const string CaseInsensitive = "SQL_Latin1_General_CP1_CI_AS";
        private const string CaseSensitive = "SQL_Latin1_General_CP1_CS_AS";

        private static PSObject Named(string name)
        {
            PSObject item = new PSObject();
            item.Properties.Add(new PSNoteProperty("Name", name));
            return item;
        }

        private static string[] NamesOf(IEnumerable<object> items)
        {
            return items.Select(item => (string)PSObject.AsPSObject(item).Properties["Name"].Value).ToArray();
        }

        [TestMethod]
        public void Compare_In_MatchesCaseInsensitivelyUnderCiCollation()
        {
            object[] input = { Named("Alpha"), Named("beta"), Named("Gamma") };
            string[] values = { "ALPHA", "BETA" };

            string[] result = NamesOf(CollationSensitiveFilter.Compare(input, "Name", CollationSensitiveFilter.FilterMode.In, values, CaseInsensitive));

            CollectionAssert.AreEqual(new[] { "Alpha", "beta" }, result, "CI collation must match across case and preserve input order");
        }

        [TestMethod]
        public void Compare_In_RespectsCaseUnderCsCollation()
        {
            object[] input = { Named("Alpha"), Named("beta") };
            string[] values = { "ALPHA", "beta" };

            string[] result = NamesOf(CollationSensitiveFilter.Compare(input, "Name", CollationSensitiveFilter.FilterMode.In, values, CaseSensitive));

            CollectionAssert.AreEqual(new[] { "beta" }, result, "CS collation must not match differing case");
        }

        [TestMethod]
        public void Compare_NotIn_ReturnsNonMatchesAndNullValueReturnsEverything()
        {
            object[] input = { Named("Alpha"), Named("beta"), Named("Gamma") };

            string[] filtered = NamesOf(CollationSensitiveFilter.Compare(input, "Name", CollationSensitiveFilter.FilterMode.NotIn, new[] { "ALPHA" }, CaseInsensitive));
            CollectionAssert.AreEqual(new[] { "beta", "Gamma" }, filtered);

            // PS `foreach ($dif in $null)` iterates zero times: nothing ever matches,
            // so NotIn emits every (truthy) item.
            string[] everything = NamesOf(CollationSensitiveFilter.Compare(input, "Name", CollationSensitiveFilter.FilterMode.NotIn, null, CaseInsensitive));
            CollectionAssert.AreEqual(new[] { "Alpha", "beta", "Gamma" }, everything);
        }

        [TestMethod]
        public void Compare_In_NullValueYieldsNothing()
        {
            object[] input = { Named("Alpha") };

            object[] result = CollationSensitiveFilter.Compare(input, "Name", CollationSensitiveFilter.FilterMode.In, null, CaseInsensitive).ToArray();

            Assert.AreEqual(0, result.Length, "In against a null value set can never match");
        }

        [TestMethod]
        public void Compare_EqAndNe_WithScalarValue()
        {
            object[] input = { Named("Alpha"), Named("beta") };

            string[] equal = NamesOf(CollationSensitiveFilter.Compare(input, "Name", CollationSensitiveFilter.FilterMode.Eq, "alpha", CaseInsensitive));
            CollectionAssert.AreEqual(new[] { "Alpha" }, equal);

            string[] notEqual = NamesOf(CollationSensitiveFilter.Compare(input, "Name", CollationSensitiveFilter.FilterMode.Ne, "alpha", CaseInsensitive));
            CollectionAssert.AreEqual(new[] { "beta" }, notEqual);
        }

        [TestMethod]
        public void Compare_SkipsPsFalsyItemsLikeTheHelperGuard()
        {
            // Helper line 84 `if (-not $obj) { return }` drops PS-FALSY items. This test
            // DISCRIMINATES: under Eq against a null Value, every falsy item's missing
            // "Name" property would compare null == null and be emitted if the guard were
            // broken - so any falsy leak fails the assertion. The truthy no-Name control
            // proves the null-property Eq-null match itself works.
            PSObject truthyWithoutName = new PSObject();
            truthyWithoutName.Properties.Add(new PSNoteProperty("Other", "control"));
            object[] input = { null, String.Empty, 0, false, truthyWithoutName };

            object[] result = CollationSensitiveFilter.Compare(input, "Name", CollationSensitiveFilter.FilterMode.Eq, null, CaseInsensitive).ToArray();

            Assert.AreEqual(1, result.Length, "only the truthy control may pass the falsy guard");
            Assert.AreSame(truthyWithoutName, result[0]);
        }

        private static IEnumerable<object> OneItemThenThrow()
        {
            yield return Named("Alpha");
            throw new InvalidOperationException("second item must never be pulled");
        }

        [TestMethod]
        public void Compare_IsLazyLikeTheProcessBlock()
        {
            // The helper streams per pipeline item; the port must too. A source that
            // throws on its second item proves it: building the query and pulling the
            // first match never reaches the poisoned element.
            IEnumerable<object> query = CollationSensitiveFilter.Compare(OneItemThenThrow(), "Name", CollationSensitiveFilter.FilterMode.In, new[] { "alpha" }, CaseInsensitive);

            using (IEnumerator<object> cursor = query.GetEnumerator())
            {
                Assert.IsTrue(cursor.MoveNext(), "first match must stream out before the source is exhausted");
                Assert.AreEqual("Alpha", (string)PSObject.AsPSObject(cursor.Current).Properties["Name"].Value);
                Assert.ThrowsException<InvalidOperationException>(delegate { cursor.MoveNext(); }, "pulling further must hit the poisoned element - proving consumption is demand-driven");
            }
        }

        [TestMethod]
        public void Compare_MissingPropertyComparesAsNull()
        {
            PSObject noName = new PSObject();
            noName.Properties.Add(new PSNoteProperty("Other", "x"));
            object[] input = { noName };

            // PS: $obj.Missing is $null; Compare($null, $null) is 0, so Eq against a null
            // Value emits the item - the helper's most surprising reachable behavior.
            object[] equalNull = CollationSensitiveFilter.Compare(input, "Name", CollationSensitiveFilter.FilterMode.Eq, null, CaseInsensitive).ToArray();
            Assert.AreEqual(1, equalNull.Length);

            // And In against real values never matches a null property.
            object[] never = CollationSensitiveFilter.Compare(input, "Name", CollationSensitiveFilter.FilterMode.In, new[] { "x" }, CaseInsensitive).ToArray();
            Assert.AreEqual(0, never.Length);
        }

        [TestMethod]
        public void Compare_ScalarValueEnumeratesOnceForIn()
        {
            object[] input = { Named("Alpha"), Named("beta") };

            string[] result = NamesOf(CollationSensitiveFilter.Compare(input, "Name", CollationSensitiveFilter.FilterMode.In, "ALPHA", CaseInsensitive));

            CollectionAssert.AreEqual(new[] { "Alpha" }, result, "a scalar Value iterates once like PS foreach");
        }

        private sealed class TouchRecordingEnumerable : IEnumerable<object>
        {
            public bool Touched;

            public IEnumerator<object> GetEnumerator()
            {
                Touched = true;
                yield break;
            }

            System.Collections.IEnumerator System.Collections.IEnumerable.GetEnumerator()
            {
                return GetEnumerator();
            }
        }

        [TestMethod]
        public void Compare_InvalidCollationFaultsBeforeEnumeration()
        {
            TouchRecordingEnumerable input = new TouchRecordingEnumerable();

            bool threw = false;
            try
            {
                // The helper faults the same way at its New-Object/getStringComparer line;
                // the fault fires when Compare is CALLED, before any item is read.
                CollationSensitiveFilter.Compare(input, "Name", CollationSensitiveFilter.FilterMode.In, new[] { "x" }, "No_Such_Collation_XX");
            }
            catch (Exception)
            {
                threw = true;
            }
            Assert.IsTrue(threw, "an unknown collation must fault like the PS helper's getStringComparer call");
            Assert.IsFalse(input.Touched, "the collation fault must fire before the input is enumerated");
        }

        [TestMethod]
        public void Compare_GuardsNullArgumentsBeforeTouchingSmo()
        {
            Assert.ThrowsException<ArgumentNullException>(delegate { CollationSensitiveFilter.Compare(null, "Name", CollationSensitiveFilter.FilterMode.In, "x", CaseInsensitive); });
            Assert.ThrowsException<ArgumentNullException>(delegate { CollationSensitiveFilter.Compare(new object[0], null, CollationSensitiveFilter.FilterMode.In, "x", CaseInsensitive); });
            Assert.ThrowsException<ArgumentNullException>(delegate { CollationSensitiveFilter.Compare(new object[0], "Name", CollationSensitiveFilter.FilterMode.In, "x", null); });
        }
    }
}
