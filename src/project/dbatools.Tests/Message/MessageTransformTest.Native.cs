using System;
using System.Management.Automation;
using System.Reflection;
using Dataplat.Dbatools.Commands;
using Dataplat.Dbatools.Parameter;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace Dataplat.Dbatools.Message.Test
{
    public partial class MessageTransformTest
    {
        [TestMethod]
        public void BuiltinsSucceedWithoutCmdletOrDefaultRunspaceOnBothNativeSurfaces()
        {
            BuiltinMessageTransforms.Register();
            ReplaceLegacyRegistries(false);
            var previous = System.Management.Automation.Runspaces.Runspace.DefaultRunspace;
            try
            {
                System.Management.Automation.Runspaces.Runspace.DefaultRunspace = null;
                var request = new MessageService.MessageRequest();
                int before = MessageHost.GetTransformErrors().Length;
                var instance = new DbaInstanceParameter("fixture\\named,1544");
                var server = DisconnectedServer();
                var plain = new Exception("outer", new Exception("inner"));
                var sql = SqlError();
                var wrapped = new Exception("outer", sql);
                AssertTarget(instance.FullSmoName, MessageService.ResolveTarget(null, request, instance));
                AssertTarget(new DbaInstanceParameter((object)server).FullSmoName, MessageService.ResolveTarget(null, request, server));
                Assert.AreSame(plain, MessageService.ResolveException(null, request, plain));
                Assert.AreSame(sql, MessageService.ResolveException(null, request, wrapped));
                Assert.IsNull(MessageService.ResolveTarget(null, request, null));
                Assert.IsNull(MessageService.ResolveException(null, request, null));
                var command = new WriteMessageCommand { FunctionName = "Test-Transform", ModuleName = "fixture" };
                var targetMethod = typeof(WriteMessageCommand).GetMethod("ResolveTarget", BindingFlags.Instance | BindingFlags.NonPublic);
                var exceptionMethod = typeof(WriteMessageCommand).GetMethod("ResolveException", BindingFlags.Instance | BindingFlags.NonPublic);
                AssertTarget(instance.FullSmoName, targetMethod.Invoke(command, new object[] { instance }));
                AssertTarget(new DbaInstanceParameter((object)server).FullSmoName, targetMethod.Invoke(command, new object[] { server }));
                Assert.AreSame(plain, exceptionMethod.Invoke(command, new object[] { plain }));
                Assert.AreSame(sql, exceptionMethod.Invoke(command, new object[] { wrapped }));
                Assert.AreEqual(before, MessageHost.GetTransformErrors().Length);
            }
            finally { System.Management.Automation.Runspaces.Runspace.DefaultRunspace = previous; }
        }

        [TestMethod]
        public void IdenticalCallerTextIsStillAUserScriptBoundary()
        {
            BuiltinMessageTransforms.Register();
            RegisterBuiltins();
            var instance = new DbaInstanceParameter("fixture");
            string key = typeof(DbaInstanceParameter).FullName.ToLowerInvariant();
            ScriptBlock builtin = MessageHost.TargetTransforms[key];
            object result;
            Assert.IsTrue(LegacyMessageTransforms.TryTransform(builtin, instance, out result));
            Assert.AreEqual(instance.FullSmoName, result);
            ScriptBlock caller = ScriptBlock.Create(builtin.ToString());
            Assert.IsFalse(LegacyMessageTransforms.TryTransform(caller, instance, out result));
            MessageHost.TargetTransforms[key] = caller;
            AssertTarget(instance.FullSmoName, Resolve(instance));
            int before = MessageHost.GetTransformErrors().Length;
            Assert.ThrowsException<NotSupportedException>(() => MessageService.ResolveTarget(null, new MessageService.MessageRequest(), instance));
            Assert.AreEqual(before, MessageHost.GetTransformErrors().Length);
        }

        [TestMethod]
        public void NativeTargetFailureReturnsOriginalAndQueuesError()
        {
            BuiltinMessageTransforms.Register();
            var server = DisconnectedServer();
            PSObject.AsPSObject(server).Properties["ComputerName"].Value = 123;
            int before = MessageHost.GetTransformErrors().Length;
            Assert.AreSame(server, ResolveNative(server));
            RegisterBuiltins();
            Assert.AreSame(server, WriteMessage(server).TargetObject);
            var errors = MessageHost.GetTransformErrors();
            Assert.AreEqual(before + 2, errors.Length);
            for (int i = before; i < errors.Length; i++)
            {
                Assert.AreSame(server, errors[i].Object);
                Assert.AreEqual(TransformType.Target, errors[i].Type);
                Assert.AreEqual("Write-Message", errors[i].Record.FullyQualifiedErrorId);
                Assert.AreEqual(ErrorCategory.OperationStopped, errors[i].Record.CategoryInfo.Category);
                Assert.AreEqual(runspace.InstanceId, errors[i].Runspace);
            }
        }

        [TestMethod]
        public void BinaryExceptionOverrideAndFailureKeepRecordIdentityRules()
        {
            RegisterBuiltins();
            Execute("Register-DbaMessageTransform -ExceptionType 'System.Exception' -ScriptBlock { $args[0].InnerException }");
            var inner = new Exception("selected");
            var original = new Exception("outer", inner);
            var records = new[] { new ErrorRecord(original, "fixture", ErrorCategory.NotSpecified, null) };
            WriteMessage(null, records: records);
            Assert.AreSame(inner, records[0].Exception);
            Execute("Register-DbaMessageTransform -ExceptionType 'System.Exception' -ScriptBlock { throw 'failure' }");
            var originalRecord = new ErrorRecord(original, "fixture", ErrorCategory.NotSpecified, null);
            records[0] = originalRecord;
            int before = MessageHost.GetTransformErrors().Length;
            WriteMessage(null, records: records);
            Assert.AreSame(originalRecord, records[0]);
            Assert.AreEqual(before + 1, MessageHost.GetTransformErrors().Length);
        }

        [TestMethod]
        public void TypedDefaultsReinitializeExactEntriesAndKeepConditionIdentity()
        {
            BuiltinMessageTransforms.Register();
            string key = typeof(DbaInstanceParameter).FullName.ToLowerInvariant();
            var condition = MessageHost.NativeExceptionTransformList.GetAll()[0];
            var later = new NativeTransformCondition("System.*", "*", "*",
                new NativeMessageTransform(NativeTransformKind.FirstNestedSqlException), TransformType.Exception);
            MessageHost.NativeExceptionTransformList.Add(later);
            MessageHost.NativeTargetTransforms[key] = later.Transform;
            BuiltinMessageTransforms.Register();
            Assert.AreEqual(2, MessageHost.NativeTargetTransforms.Count);
            Assert.AreEqual(0, MessageHost.NativeExceptionTransforms.Count);
            Assert.AreEqual(0, MessageHost.NativeTargetTransformList.GetAll().Length);
            Assert.AreEqual(2, MessageHost.NativeExceptionTransformList.GetAll().Length);
            Assert.AreSame(condition, MessageHost.NativeExceptionTransformList.GetAll()[0]);
            Assert.AreSame(later, MessageHost.NativeExceptionTransformList.GetAll()[1]);
            Assert.AreEqual(NativeTransformKind.InstanceFullSmoName, MessageHost.NativeTargetTransforms[key].Kind);
            Assert.AreEqual(0, MessageHost.TargetTransforms.Count);
            Assert.AreEqual(0, MessageHost.ExceptionTransforms.Count);
            Assert.AreEqual(0, MessageHost.TargetTransformlist.GetAll().Length);
            Assert.AreEqual(0, MessageHost.ExceptionTransformList.GetAll().Length);
            var instance = new DbaInstanceParameter("fixture");
            object result;
            Assert.IsTrue(BuiltinMessageTransforms.TryTransform(MessageHost.NativeTargetTransforms[key], instance, out result));
            Assert.AreEqual(instance.FullSmoName, result);
        }

        [TestMethod]
        public void TypedConditionsKeepLiteralEqualityFirstMatchAndIdentityRemoval()
        {
            var transform = new NativeMessageTransform(NativeTransformKind.FirstNestedSqlException);
            var first = new NativeTransformCondition("System.*", "fixture", "Test-*", transform, TransformType.Exception);
            var duplicate = new NativeTransformCondition("System.*", "fixture", "Test-*", transform, TransformType.Exception);
            var overlapping = new NativeTransformCondition("*", "*", "*", transform, TransformType.Exception);
            var list = MessageHost.NativeExceptionTransformList;
            list.Add(first);
            list.Add(duplicate);
            list.Add(overlapping);
            Assert.AreEqual(2, list.GetAll().Length);
            Assert.IsTrue(list.IsContained(duplicate));
            Assert.IsFalse(list.IsListed(duplicate));
            Assert.AreSame(first, list.Get("System.Exception", "fixture", "Test-Transform"));
            Assert.AreSame(overlapping, list.Get("System.Exception", "other", "Test-Transform"));
            list.Remove(duplicate);
            Assert.AreSame(first, list.GetAll()[0]);
            list.Remove(first);
            Assert.AreSame(overlapping, list.Get("System.Exception", "fixture", "Test-Transform"));
        }

        [TestMethod]
        public void TypedExactPrecedenceAndRemovalExposeConditionalFailure()
        {
            BuiltinMessageTransforms.Register();
            var condition = new NativeTransformCondition("*", "*", "*",
                new NativeMessageTransform(NativeTransformKind.FirstNestedSqlException), TransformType.Target);
            MessageHost.NativeTargetTransformList.Add(condition);
            var instance = new DbaInstanceParameter("fixture");
            int before = MessageHost.GetTransformErrors().Length;
            AssertTarget(instance.FullSmoName, ResolveNative(instance));
            Assert.AreEqual(before, MessageHost.GetTransformErrors().Length);
            MessageHost.NativeTargetTransforms.Remove(typeof(DbaInstanceParameter).FullName.ToLowerInvariant());
            Assert.AreSame(instance, ResolveNative(instance));
            Assert.AreEqual(before + 1, MessageHost.GetTransformErrors().Length);
            Assert.AreSame(instance, MessageHost.GetTransformErrors()[before].Object);
            MessageHost.NativeTargetTransformList.Remove(condition);
            Assert.AreSame(instance, ResolveNative(instance));
            Assert.AreEqual(before + 1, MessageHost.GetTransformErrors().Length);
        }

        [TestMethod]
        public void NativeIgnoresNonmatchingLegacyFiltersButRejectsExplicitLegacyDefaults()
        {
            BuiltinMessageTransforms.Register();
            MessageHost.TargetTransforms["system.string"] = null;
            MessageHost.TargetTransformlist.Add(new TransformCondition("*", "other", "*", null, TransformType.Target));
            MessageHost.ExceptionTransformList.Add(new TransformCondition("*", "fixture", "Other-*", null, TransformType.Exception));
            var request = new MessageService.MessageRequest { FunctionName = "Test-Transform", ModuleName = "fixture" };
            var instance = new DbaInstanceParameter("fixture");
            var plain = new Exception("original");
            AssertTarget(instance.FullSmoName, MessageService.ResolveTarget(null, request, instance));
            Assert.AreSame(plain, MessageService.ResolveException(null, request, plain));
            RegisterBuiltins();
            AssertTarget(instance.FullSmoName, MessageService.ResolveTarget(null, request, instance));
            Assert.AreSame(plain, MessageService.ResolveException(null, request, plain));
        }

    }
}
