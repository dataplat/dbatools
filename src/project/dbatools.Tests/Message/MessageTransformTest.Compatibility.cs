using System;
using System.Management.Automation;
using System.Reflection;
using Dataplat.Dbatools.Parameter;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace Dataplat.Dbatools.Message.Test
{
    public partial class MessageTransformTest
    {
        [TestMethod]
        public void PublicRegistriesRemainVisibleMutableAndClearable()
        {
            RegisterBuiltins();
            Assert.AreEqual(2, MessageHost.TargetTransforms.Count);
            foreach (ScriptBlock script in MessageHost.TargetTransforms.Values)
                Assert.IsNotNull(script);
            var condition = MessageHost.ExceptionTransformList.GetAll()[0];
            Assert.IsNotNull(condition.ScriptBlock);
            condition.ScriptBlock = ScriptBlock.Create("$args[0].InnerException");
            var inner = new Exception("selected");
            Assert.AreSame(inner, Resolve(new Exception("outer", inner), true));
            MessageHost.TargetTransforms.Clear();
            var instance = new DbaInstanceParameter("fixture");
            Assert.AreSame(instance, Resolve(instance));
            MessageHost.ExceptionTransformList.Remove(condition);
            var outer = new Exception("outer", SqlError());
            Assert.AreSame(outer, Resolve(outer, true));
        }

        [TestMethod]
        public void FirstSqlExceptionWinsEvenWhenAnotherSqlExceptionIsNested()
        {
            RegisterBuiltins();
            var first = SqlError();
            var second = SqlError();
            typeof(Exception).GetField("_innerException", BindingFlags.Instance | BindingFlags.NonPublic).SetValue(first, second);
            Assert.AreSame(first, Resolve(new Exception("outer", first), true));
        }

        [DataTestMethod]
        [DataRow(false, false)]
        [DataRow(false, true)]
        [DataRow(true, false)]
        [DataRow(true, true)]
        public void EveryScriptFailureBranchKeepsIdentity(bool exception, bool conditional)
        {
            string parameter = exception ? "ExceptionType" : "TargetType";
            string name = exception ? "System.Exception" : "System.Object";
            if (conditional) { parameter += "Filter"; name = "*"; }
            Execute(String.Format("Register-DbaMessageTransform -{0} '{1}' -ScriptBlock {{ throw 'fixture failure' }}", parameter, name));
            object item = exception ? (object)new Exception("original") : new object();
            int before = MessageHost.GetTransformErrors().Length;
            Assert.AreSame(item, Resolve(item, exception));
            var errors = MessageHost.GetTransformErrors();
            Assert.AreEqual(before + 1, errors.Length);
            Assert.AreSame(item, errors[before].Object);
            Assert.AreEqual(exception ? TransformType.Exception : TransformType.Target, errors[before].Type);
        }

        private LogEntry WriteMessage(object target, Exception exception = null, ErrorRecord[] records = null)
        {
            string marker = Guid.NewGuid().ToString();
            using (PowerShell shell = PowerShell.Create())
            {
                shell.Runspace = runspace;
                shell.AddCommand("Write-Message").AddParameter("Message", marker)
                    .AddParameter("FunctionName", "Test-Transform").AddParameter("ModuleName", "fixture")
                    .AddParameter("Target", target);
                if (exception != null) shell.AddParameter("Exception", exception);
                if (records != null) shell.AddParameter("ErrorRecord", records);
                shell.Invoke();
                Assert.IsFalse(shell.HadErrors, String.Join(Environment.NewLine, shell.Streams.Error));
            }
            foreach (LogEntry entry in LogHost.GetLog())
                if (entry.Message.Contains(marker)) return entry;
            Assert.Fail("Write-Message did not log the invocation.");
            return null;
        }

        [TestMethod]
        public void BinaryWriteMessageTransformsBothTargetsAndMultipleErrorRecords()
        {
            RegisterBuiltins();
            var instance = new DbaInstanceParameter("fixture\\named,1544");
            AssertTarget(instance.FullSmoName, WriteMessage(instance).TargetObject);
            var server = DisconnectedServer();
            AssertTarget(new DbaInstanceParameter((object)server).FullSmoName, WriteMessage(server).TargetObject);
            var sql = SqlError();
            var original = new Exception("unchanged");
            var records = new[] {
                new ErrorRecord(new Exception("wrapped", sql), "sql", ErrorCategory.InvalidOperation, instance),
                new ErrorRecord(original, "plain", ErrorCategory.NotSpecified, server)
            };
            var unchangedRecord = records[1];
            WriteMessage(instance, records: records);
            Assert.AreSame(sql, records[0].Exception);
            Assert.AreEqual("sql", records[0].FullyQualifiedErrorId);
            Assert.AreSame(instance, records[0].TargetObject);
            Assert.AreEqual(ErrorCategory.InvalidOperation, records[0].CategoryInfo.Category);
            Assert.AreSame(unchangedRecord, records[1]);
            int before = MessageHost.GetTransformErrors().Length;
            WriteMessage(instance, new Exception("wrapped", sql));
            Assert.AreEqual(before, MessageHost.GetTransformErrors().Length);
        }

        [TestMethod]
        public void BinaryWriteMessageHonorsOverrideAndFailureFallback()
        {
            RegisterBuiltins();
            Execute("Register-DbaMessageTransform -TargetType 'Dataplat.Dbatools.Parameter.DbaInstanceParameter' -ScriptBlock { 'caller' }");
            var instance = new DbaInstanceParameter("fixture");
            AssertTarget("caller", WriteMessage(instance).TargetObject);
            Execute("Register-DbaMessageTransform -TargetType 'Dataplat.Dbatools.Parameter.DbaInstanceParameter' -ScriptBlock { throw 'failure' }");
            int before = MessageHost.GetTransformErrors().Length;
            Assert.AreSame(instance, WriteMessage(instance).TargetObject);
            var errors = MessageHost.GetTransformErrors();
            Assert.AreEqual(before + 1, errors.Length);
            Assert.AreSame(instance, errors[before].Object);
            Assert.AreEqual(TransformType.Target, errors[before].Type);
        }
    }
}
