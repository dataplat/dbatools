using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.IO;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Runtime.Serialization;
using Dataplat.Dbatools.Commands;
using Dataplat.Dbatools.Parameter;
using Microsoft.Data.SqlClient;
using Microsoft.SqlServer.Management.Smo;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace Dataplat.Dbatools.Message.Test
{
    /// <summary>Retains the dispatch result without pipeline enumeration.</summary>
    [Cmdlet("Test", "MessageTransform")]
    public class MessageTransformProbe : DbaBaseCmdlet
    {
        [Parameter] public object InputItem { get; set; }
        [Parameter] public SwitchParameter ExceptionMode { get; set; }
        [Parameter] public SwitchParameter WriteMode { get; set; }
        [Parameter] public ErrorRecord[] InputRecords { get; set; }

        protected override void ProcessRecord()
        {
            var request = new MessageService.MessageRequest { FunctionName = "Test-Transform", ModuleName = "fixture" };
            if (WriteMode)
            {
                request.Message = (string)InputItem;
                request.Level = Dataplat.Dbatools.Message.MessageLevel.Warning;
                request.ErrorRecord = InputRecords;
                MessageService.Write(this, request);
                WriteObject("completed");
                return;
            }
            object result = ExceptionMode
                ? MessageService.ResolveException(this, request, (Exception)InputItem)
                : MessageService.ResolveTarget(this, request, InputItem);
            PSObject envelope = new PSObject();
            envelope.Properties.Add(new PSNoteProperty("Result", result));
            WriteObject(envelope);
        }
    }

    [TestClass]
    [DoNotParallelize]
    public partial class MessageTransformTest
    {
        private Dictionary<string, ScriptBlock> targets;
        private Dictionary<string, ScriptBlock> exceptions;
        private TransformList targetList;
        private TransformList exceptionList;
        private Dictionary<string, NativeMessageTransform> nativeTargets;
        private Dictionary<string, NativeMessageTransform> nativeExceptions;
        private NativeTransformList nativeTargetList;
        private NativeTransformList nativeExceptionList;
        private Dictionary<string, MessageEventSubscription> events;
        private bool disableVerbosity;
        private System.Management.Automation.Runspaces.Runspace runspace;
        private string moduleRoot;

        [TestInitialize]
        public void Initialize()
        {
            moduleRoot = Environment.GetEnvironmentVariable("DBATOOLS_TRANSFORM_MODULE_ROOT");
            Assert.IsTrue(Directory.Exists(moduleRoot), "Set DBATOOLS_TRANSFORM_MODULE_ROOT to the paired PowerShell checkout.");
            targets = MessageHost.TargetTransforms;
            exceptions = MessageHost.ExceptionTransforms;
            targetList = MessageHost.TargetTransformlist;
            exceptionList = MessageHost.ExceptionTransformList;
            nativeTargets = MessageHost.NativeTargetTransforms;
            nativeExceptions = MessageHost.NativeExceptionTransforms;
            nativeTargetList = MessageHost.NativeTargetTransformList;
            nativeExceptionList = MessageHost.NativeExceptionTransformList;
            events = MessageHost.Events;
            disableVerbosity = MessageHost.DisableVerbosity;
            MessageHost.NativeTargetTransforms = new Dictionary<string, NativeMessageTransform>();
            MessageHost.NativeExceptionTransforms = new Dictionary<string, NativeMessageTransform>();
            MessageHost.NativeTargetTransformList = new NativeTransformList();
            MessageHost.NativeExceptionTransformList = new NativeTransformList();
            MessageHost.Events = new Dictionary<string, MessageEventSubscription>();
            MessageHost.DisableVerbosity = false;
            ReplaceLegacyRegistries(true);
            InitialSessionState state = InitialSessionState.CreateDefault2();
            state.Commands.Add(new SessionStateCmdletEntry("Test-MessageTransform", typeof(MessageTransformProbe), null));
            state.Commands.Add(new SessionStateCmdletEntry("Write-Message", typeof(WriteMessageCommand), null));
            runspace = RunspaceFactory.CreateRunspace(state);
            runspace.Open();
            Execute(File.ReadAllText(Path.Combine(moduleRoot, "private/functions/message/Register-DbaMessageTransform.ps1")));
        }

        [TestCleanup]
        public void Cleanup()
        {
            if (runspace != null) runspace.Dispose();
            MessageHost.TargetTransforms = targets;
            MessageHost.ExceptionTransforms = exceptions;
            MessageHost.TargetTransformlist = targetList;
            MessageHost.ExceptionTransformList = exceptionList;
            MessageHost.NativeTargetTransforms = nativeTargets;
            MessageHost.NativeExceptionTransforms = nativeExceptions;
            MessageHost.NativeTargetTransformList = nativeTargetList;
            MessageHost.NativeExceptionTransformList = nativeExceptionList;
            MessageHost.Events = events;
            MessageHost.DisableVerbosity = disableVerbosity;
        }

        private static void ReplaceLegacyRegistries(bool activate)
        {
            MessageHost.TargetTransforms = new Dictionary<string, ScriptBlock>();
            MessageHost.ExceptionTransforms = new Dictionary<string, ScriptBlock>();
            MessageHost.TargetTransformlist = new TransformList();
            MessageHost.ExceptionTransformList = new TransformList();
            if (activate)
            {
                // Existing compatibility cases intentionally start with emptied legacy registries.
                LegacyTransformRegistryMode.Activate(TransformType.Target, MessageHost.TargetTransforms, MessageHost.TargetTransformlist);
                LegacyTransformRegistryMode.Activate(TransformType.Exception, MessageHost.ExceptionTransforms, MessageHost.ExceptionTransformList);
            }
        }

        private void Execute(string script)
        {
            using (PowerShell shell = PowerShell.Create())
            {
                shell.Runspace = runspace;
                shell.AddScript(script).Invoke();
                Assert.IsFalse(shell.HadErrors, String.Join(Environment.NewLine, shell.Streams.Error));
            }
        }

        private void RegisterBuiltins()
        {
            Execute(File.ReadAllText(Path.Combine(moduleRoot, "private/scripts/message-transforms.ps1")));
        }

        private object Resolve(object input, bool exception = false)
        {
            // Script overrides remain supported by the explicitly unfinished Write-Message frontend.
            if (!exception || input == null)
                return WriteMessage(input).TargetObject;
            var records = new[] { new ErrorRecord((Exception)input, "fixture", ErrorCategory.NotSpecified, null) };
            WriteMessage(null, records: records);
            return records[0].Exception;
        }

        private object ResolveNative(object input, bool exception = false)
        {
            using (PowerShell shell = PowerShell.Create())
            {
                shell.Runspace = runspace;
                shell.AddCommand("Test-MessageTransform").AddParameter("InputItem", input).AddParameter("ExceptionMode", exception);
                var output = shell.Invoke();
                Assert.IsFalse(shell.HadErrors, String.Join(Environment.NewLine, shell.Streams.Error));
                Assert.AreEqual(1, output.Count);
                return output[0].Properties["Result"].Value;
            }
        }

        private static void AssertTarget(string expected, object actual)
        {
            var collection = actual as Collection<PSObject>;
            Assert.IsNotNull(collection, "Native dispatch must preserve the existing target collection shape.");
            Assert.AreEqual(1, collection.Count);
            Assert.AreEqual(expected, collection[0].BaseObject);
        }

        private static Server DisconnectedServer()
        {
            Server server = new Server("unused-transform-fixture");
            PSObject wrapped = PSObject.AsPSObject(server);
            wrapped.Properties.Add(new PSNoteProperty("ComputerName", "fixture"));
            wrapped.Properties.Add(new PSNoteProperty("DbaInstanceName", "named"));
            wrapped.Properties.Add(new PSNoteProperty("NetPort", 1544));
            return server;
        }

        private static SqlException SqlError()
        {
            return (SqlException)FormatterServices.GetUninitializedObject(typeof(SqlException));
        }

        [TestMethod]
        public void Builtins_TargetsPreserveFullSmoNameAndCollectionShape()
        {
            RegisterBuiltins();
            var instance = new DbaInstanceParameter("fixture\\named,1544");
            AssertTarget(instance.FullSmoName, Resolve(instance));
            var server = DisconnectedServer();
            AssertTarget(new DbaInstanceParameter((object)server).FullSmoName, Resolve(server));
        }

        [TestMethod]
        public void Builtins_KeepOriginalExceptionOrFirstSqlExceptionByIdentity()
        {
            RegisterBuiltins();
            var plain = new Exception("outer", new InvalidOperationException("inner"));
            Assert.AreSame(plain, Resolve(plain, true));
            var sql = SqlError();
            Assert.AreSame(sql, Resolve(sql, true));
            var nested = new Exception("outer", new Exception("middle", sql));
            Assert.AreSame(sql, Resolve(nested, true));
            Assert.IsNull(Resolve(null, true));
        }

        [TestMethod]
        public void ExactCallerOverrideWinsAndBuiltinExactBeatsTargetFilter()
        {
            RegisterBuiltins();
            Execute("Register-DbaMessageTransform -TargetTypeFilter '*' -ScriptBlock { 'conditional' }");
            var instance = new DbaInstanceParameter("fixture");
            AssertTarget(instance.FullSmoName, Resolve(instance));
            Execute("Register-DbaMessageTransform -TargetType 'Dataplat.Dbatools.Parameter.DbaInstanceParameter' -ScriptBlock { 'caller' }");
            AssertTarget("caller", Resolve(instance));
            Execute("Register-DbaMessageTransform -ExceptionType 'System.Exception' -ScriptBlock { $args[0].InnerException }");
            var inner = new InvalidOperationException("selected");
            Assert.AreSame(inner, Resolve(new Exception("outer", inner), true));
        }

        [TestMethod]
        public void ConditionalRegistrationIsFirstMatchWithDuplicateSuppression()
        {
            Execute("Register-DbaMessageTransform -ExceptionTypeFilter '*' -ScriptBlock { $args[0].InnerException }");
            RegisterBuiltins();
            var inner = new InvalidOperationException("selected");
            Assert.AreSame(inner, Resolve(new Exception("outer", inner), true));
            Assert.AreEqual(1, MessageHost.ExceptionTransformList.GetAll().Length);
            Execute("Register-DbaMessageTransform -TargetTypeFilter 'System.*' -FunctionNameFilter 'Other-*' -ScriptBlock { 'wrong' }; Register-DbaMessageTransform -TargetTypeFilter 'System.*' -ScriptBlock { 'first' }; Register-DbaMessageTransform -TargetTypeFilter '*' -ScriptBlock { 'second' }");
            AssertTarget("first", Resolve("input"));
        }

        [TestMethod]
        public void BuiltinCatchAllRetainsPositionAndExactInitializationOverwrites()
        {
            RegisterBuiltins();
            Execute("Register-DbaMessageTransform -ExceptionTypeFilter 'System.*' -ScriptBlock { $args[0].InnerException }");
            var original = new Exception("original", new InvalidOperationException("inner"));
            Assert.AreSame(original, Resolve(original, true));
            Execute("Register-DbaMessageTransform -TargetType 'Dataplat.Dbatools.Parameter.DbaInstanceParameter' -ScriptBlock { 'caller' }");
            RegisterBuiltins();
            AssertTarget("fixture", Resolve(new DbaInstanceParameter("fixture")));
            Assert.AreEqual(2, MessageHost.ExceptionTransformList.GetAll().Length);
        }

        [TestMethod]
        public void FailingExactAndConditionalScriptsReturnInputAndQueueError()
        {
            Execute("Register-DbaMessageTransform -TargetType 'System.Object' -ScriptBlock { throw 'exact failure' }; Register-DbaMessageTransform -ExceptionTypeFilter '*' -ScriptBlock { throw 'conditional failure' }");
            var item = new object();
            int before = MessageHost.GetTransformErrors().Length;
            Assert.AreSame(item, Resolve(item));
            var exception = new Exception("original");
            Assert.AreSame(exception, Resolve(exception, true));
            var errors = MessageHost.GetTransformErrors();
            Assert.AreEqual(before + 2, errors.Length);
            Assert.AreSame(item, errors[before].Object);
            Assert.AreEqual(TransformType.Target, errors[before].Type);
            Assert.AreSame(exception, errors[before + 1].Object);
            Assert.AreEqual(TransformType.Exception, errors[before + 1].Type);
            Assert.AreEqual("Test-Transform", errors[before].FunctionName);
            Assert.AreEqual("fixture", errors[before].ModuleName);
            Assert.AreEqual(runspace.InstanceId, errors[before].Runspace);
        }

        [TestMethod]
        public void RemovingExactBuiltinRegistrationRevealsConditionalTransform()
        {
            RegisterBuiltins();
            MessageHost.TargetTransforms.Remove(typeof(DbaInstanceParameter).FullName.ToLowerInvariant());
            Execute("Register-DbaMessageTransform -TargetTypeFilter '*' -ScriptBlock { 'fallback' }");
            AssertTarget("fallback", Resolve(new DbaInstanceParameter("fixture")));
        }
    }
}
