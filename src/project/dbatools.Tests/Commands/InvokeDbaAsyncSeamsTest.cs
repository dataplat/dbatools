using System.Collections.ObjectModel;
using System.Data;
using System.Management.Automation;
using Dataplat.Dbatools.Commands;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace Dataplat.Dbatools.Commands.Test
{
    /// <summary>
    /// Offline coverage for the pure seams of the absorbed Invoke-DbaAsync engine (TB-066),
    /// ported across InvokeDbaQueryCommand.Async.cs. Three connection-independent units are
    /// pinned here: the DBNullScrubber DataRowToPSObject (a line-for-line semantic lift of
    /// the C# class the PS source embeds via Add-Type, verified by these pins rather than
    /// asserted byte-identical), the GO batch split/filter (SplitGoBatches), and the
    /// empty/one/many pipeline shaping (ShapePipelineValue). The remaining engine surface -
    /// SqlParameter binding, the -As emission modes, statement decoration, and live
    /// execution - requires a SQL connection or a hosted cmdlet pipeline and rides the
    /// Invoke-DbaQuery integration gate.
    /// </summary>
    [TestClass]
    public class InvokeDbaAsyncSeamsTest
    {
        private static DataTable MakeTable()
        {
            DataTable table = new DataTable();
            table.Columns.Add("Id", typeof(int));
            table.Columns.Add("Name", typeof(string));
            table.Columns.Add("Note", typeof(string));
            return table;
        }

        [TestMethod]
        public void DataRowToPSObject_ScrubsDBNullToNullAndPreservesValues()
        {
            DataTable table = MakeTable();
            DataRow row = table.NewRow();
            row["Id"] = 7;
            row["Name"] = "widget";
            row["Note"] = System.DBNull.Value;
            table.Rows.Add(row);

            PSObject result = InvokeDbaQueryCommand.DataRowToPSObject(row);

            Assert.AreEqual(3, result.Properties.Match("*").Count, "one note property per column");
            Assert.AreEqual(7, result.Properties["Id"].Value, "non-null int preserved");
            Assert.AreEqual("widget", result.Properties["Name"].Value, "non-null string preserved");
            Assert.IsNull(result.Properties["Note"].Value, "DBNull scrubbed to a real null");
        }

        [TestMethod]
        public void DataRowToPSObject_PreservesColumnOrder()
        {
            DataTable table = MakeTable();
            DataRow row = table.NewRow();
            row["Id"] = 1;
            row["Name"] = "a";
            row["Note"] = "b";
            table.Rows.Add(row);

            PSObject result = InvokeDbaQueryCommand.DataRowToPSObject(row);

            System.Collections.Generic.List<string> names = new System.Collections.Generic.List<string>();
            foreach (PSPropertyInfo p in result.Properties)
                names.Add(p.Name);
            CollectionAssert.AreEqual(new[] { "Id", "Name", "Note" }, names, "column order preserved");
        }

        [TestMethod]
        public void DataRowToPSObject_DetachedRowYieldsEmptyObject()
        {
            DataTable table = MakeTable();
            DataRow detached = table.NewRow();
            detached["Id"] = 9;

            PSObject result = InvokeDbaQueryCommand.DataRowToPSObject(detached);

            Assert.AreEqual(0, result.Properties.Match("*").Count, "detached row yields no properties");
        }

        [TestMethod]
        public void DataRowToPSObject_NullRowYieldsEmptyObject()
        {
            // The source guards `row != null` explicitly; a null row must yield an empty
            // PSObject, not throw.
            PSObject result = InvokeDbaQueryCommand.DataRowToPSObject(null);
            Assert.AreEqual(0, result.Properties.Match("*").Count, "null row yields no properties");
        }

        [TestMethod]
        public void DataRowToPSObject_AllNullRowIsAllNullProperties()
        {
            DataTable table = MakeTable();
            DataRow row = table.NewRow();
            table.Rows.Add(row);

            PSObject result = InvokeDbaQueryCommand.DataRowToPSObject(row);

            Assert.AreEqual(3, result.Properties.Match("*").Count, "one property per column");
            Assert.IsNull(result.Properties["Id"].Value, "DBNull int scrubbed");
            Assert.IsNull(result.Properties["Name"].Value, "DBNull string scrubbed");
            Assert.IsNull(result.Properties["Note"].Value, "DBNull string scrubbed");
        }

        [TestMethod]
        public void SplitGoBatches_SplitsOnGoLinesAndDropsEmpties()
        {
            // GO on its own line (any surrounding whitespace, case-insensitive) is a
            // separator; the pieces between are kept only when non-empty after Trim.
            var pieces = InvokeDbaQueryCommand.SplitGoBatches("SELECT 1\nGO\nSELECT 2\n");
            Assert.AreEqual(2, pieces.Count, "two statements around one GO");
            StringAssert.Contains(pieces[0], "SELECT 1");
            StringAssert.Contains(pieces[1], "SELECT 2");
        }

        [TestMethod]
        public void SplitGoBatches_LeadingTrailingAndDoubleGoProduceNoEmptyPieces()
        {
            var pieces = InvokeDbaQueryCommand.SplitGoBatches("GO\n  go  \nSELECT 1\nGO\n");
            Assert.AreEqual(1, pieces.Count, "only the one non-empty statement survives");
            StringAssert.Contains(pieces[0], "SELECT 1");
        }

        [TestMethod]
        public void SplitGoBatches_GoInsideAStatementIsNotASeparator()
        {
            // GO must be alone on its line; a token like GONE or an inline GO is not a
            // separator, so a single statement stays whole.
            var pieces = InvokeDbaQueryCommand.SplitGoBatches("SELECT 'GO' AS GONE");
            Assert.AreEqual(1, pieces.Count, "inline GO does not split");
            StringAssert.Contains(pieces[0], "GONE");
        }

        [TestMethod]
        public void ShapePipelineValue_EmptyOneMany()
        {
            Assert.IsNull(InvokeDbaQueryCommand.ShapePipelineValue(new Collection<PSObject>()),
                "empty -> null");

            PSObject one = new PSObject();
            Collection<PSObject> single = new Collection<PSObject> { one };
            Assert.AreSame(one, InvokeDbaQueryCommand.ShapePipelineValue(single),
                "one -> the single object itself, not wrapped");

            PSObject a = new PSObject();
            PSObject b = new PSObject();
            Collection<PSObject> many = new Collection<PSObject> { a, b };
            object shaped = InvokeDbaQueryCommand.ShapePipelineValue(many);
            // Exact runtime type, not IsInstanceOfType: a PSObject[] is covariantly an
            // object[], but the source's element type is object[] and GetType is observable.
            Assert.AreEqual(typeof(object[]), shaped.GetType(), "many -> object[], not PSObject[]");
            object[] arr = (object[])shaped;
            Assert.AreEqual(2, arr.Length);
            Assert.AreSame(a, arr[0]);
            Assert.AreSame(b, arr[1]);
        }
    }
}
