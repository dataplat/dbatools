using System;
using System.Collections.Generic;
using Dataplat.Dbatools.Commands;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace Dataplat.Dbatools.Commands.Test
{
    /// <summary>
    /// TB-010 coverage for the OFFLINE core of IndexToTable, the C# parity port of
    /// private/functions/Convert-DbaIndexToTable.ps1: the datatype branches (fixed
    /// no-length list, *varcharmax -> (max) rewrite, *char* with length, default), the
    /// RowNr append, the exact helper-verbatim statement text, the zero-column no-emission
    /// rule, and the PS -in filter semantics. The SMO adapter (Convert) cannot be tested
    /// offline - constructing an SMO Column connects on Set DataType (probed) - so its
    /// traversal rides the future Invoke-DbaDbDataMasking lab gate, the TB-007 live/offline
    /// split. A null-db guard is the adapter's one offline-observable behavior.
    /// </summary>
    [TestClass]
    public class IndexToTableTest
    {
        private static IndexToTableColumn NewColumn(string name, string dataType, int length)
        {
            IndexToTableColumn column = new IndexToTableColumn();
            column.Name = name;
            column.DataType = dataType;
            column.Length = length;
            return column;
        }

        [TestMethod]
        public void BuildColumnStatement_CoversAllFourHelperBranches()
        {
            // Branch 1: the fixed list renders without length. NOTE: this branch is
            // output-equivalent to default for all reachable inputs (same format string),
            // so these assertions cannot isolate it - what makes the helper's missing
            // `break` safe is that no fixed-list member contains 'char' or ends in
            // 'varcharmax', the real invariant (opus round 1).
            Assert.AreEqual("[Created] [datetime]", IndexToTable.BuildColumnStatement("Created", "datetime", 8));
            Assert.AreEqual("[N] [bigint]", IndexToTable.BuildColumnStatement("N", "bigint", 8));
            // Branch 2: *varcharmax loses its max suffix and gains (max) - helper line 80.
            Assert.AreEqual("[Notes] [nvarchar](max)", IndexToTable.BuildColumnStatement("Notes", "nvarcharmax", -1));
            Assert.AreEqual("[Blob] [varchar](max)", IndexToTable.BuildColumnStatement("Blob", "varcharmax", -1));
            // Branch 3: any other *char* renders with its length.
            Assert.AreEqual("[Name] [nvarchar](50)", IndexToTable.BuildColumnStatement("Name", "nvarchar", 50));
            Assert.AreEqual("[Code] [nchar](4)", IndexToTable.BuildColumnStatement("Code", "nchar", 4));
            // Branch 4 (default): everything else renders without length.
            Assert.AreEqual("[Amount] [decimal]", IndexToTable.BuildColumnStatement("Amount", "decimal", 9));
        }

        [TestMethod]
        public void BuildStatement_ProducesHelperVerbatimTextWithRowNr()
        {
            List<IndexToTableColumn> columns = new List<IndexToTableColumn>();
            columns.Add(NewColumn("Name", "nvarchar", 50));
            columns.Add(NewColumn("Notes", "nvarcharmax", -1));
            columns.Add(NewColumn("Created", "datetime", 8));

            IndexToTableStatement statement = IndexToTable.BuildStatement("dbo", "Customers", columns);

            Assert.IsNotNull(statement);
            CollectionAssert.AreEqual(new[] { "Name", "Notes", "Created", "RowNr" }, statement.Columns);
            Assert.AreEqual("dbo", statement.Schema);
            Assert.AreEqual("Customers", statement.Table);
            Assert.AreEqual("dbo_Customers", statement.TempTableName);
            Assert.AreEqual("CREATE TABLE dbo_Customers([Name] [nvarchar](50),[Notes] [nvarchar](max),[Created] [datetime],[RowNr] [bigint]);", statement.CreateStatement, "unbracketed table name and trailing semicolon are helper-verbatim");
            Assert.AreEqual("UIX_dbo_Customers", statement.UniqueIndexName);
            Assert.AreEqual("CREATE UNIQUE NONCLUSTERED INDEX [UIX_dbo_Customers] ON dbo_Customers([Name],[Notes],[Created],[RowNr] ASC);", statement.UniqueIndexStatement, "ASC only after the last column is helper-verbatim");
        }

        [TestMethod]
        public void BuildStatement_ZeroQualifyingColumnsEmitsNothing()
        {
            // Helper line 96: [RowNr] alone never emits a statement.
            Assert.IsNull(IndexToTable.BuildStatement("dbo", "Counters", new List<IndexToTableColumn>()));
        }

        [TestMethod]
        public void MatchesPsIn_IsCaseInsensitiveLikePsIn()
        {
            Assert.IsTrue(IndexToTable.MatchesPsIn(new[] { "DBO" }, "dbo"), "PS -in over strings is case-insensitive");
            Assert.IsFalse(IndexToTable.MatchesPsIn(new[] { "sales" }, "dbo"));
            Assert.IsFalse(IndexToTable.MatchesPsIn(new string[0], "dbo"), "an empty set matches nothing");
        }

        [TestMethod]
        public void IsPsTruthy_UnwrapsSingletonsLikePsArrayTruthiness()
        {
            // The codex round-1 catch: `if ($Schema)` with @("") is FALSY in PS - the
            // singleton unwraps - so the filter is disabled, not match-everything-out.
            Assert.IsFalse(IndexToTable.IsPsTruthy(null));
            Assert.IsFalse(IndexToTable.IsPsTruthy(new string[0]));
            Assert.IsFalse(IndexToTable.IsPsTruthy(new[] { "" }), "a singleton empty string unwraps to falsy");
            Assert.IsFalse(IndexToTable.IsPsTruthy(new string[] { null }), "a singleton null unwraps to falsy");
            Assert.IsTrue(IndexToTable.IsPsTruthy(new[] { "dbo" }));
            Assert.IsTrue(IndexToTable.IsPsTruthy(new[] { "", "" }), "two elements are truthy regardless of content");
        }

        [TestMethod]
        public void Convert_NullDatabaseGuards()
        {
            Assert.ThrowsException<ArgumentNullException>(delegate { IndexToTable.Convert(null, null, null, false, null); });
        }
    }
}
