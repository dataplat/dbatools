using System;
using System.Collections.ObjectModel;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using Dataplat.Dbatools.Commands;
using Microsoft.SqlServer.Management.Common;
using Microsoft.SqlServer.Management.Smo;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace Dataplat.Dbatools.Commands.Test
{
    /// <summary>
    /// Host cmdlet for RestoreUtility.GetDbaDbPhysicalFile: the helper needs a live
    /// PSCmdlet for its Write-Message plumbing, so the test runs it inside a real
    /// in-process runspace. The Server under test targets an unreachable endpoint;
    /// note that presetting ServerConnection.ServerVersion does NOT make
    /// Server.VersionMajor resolve offline - SMO fetches version state through a live
    /// connection regardless, so every offline invocation fails at the version read.
    /// </summary>
    [Cmdlet("Test", "PhysicalFileHost")]
    public sealed class TestPhysicalFileHostCommand : DbaBaseCmdlet
    {
        protected override void ProcessRecord()
        {
            ServerConnection connection = new ServerConnection();
            connection.ServerInstance = "tcp:127.0.0.1,9";
            connection.ConnectTimeout = 1;
            Server server = new Server(connection);
            try
            {
                System.Data.DataRow[] rows = RestoreUtility.GetDbaDbPhysicalFile(this, server);
                WriteObject("ROWS:" + rows.Length);
            }
            catch (Exception ex)
            {
                WriteObject("THREW:" + ex.GetType().Name + ":" + ex.Message);
            }
        }
    }

    /// <summary>
    /// Coverage for RestoreUtility.GetDbaDbPhysicalFile, the C# parity port of
    /// private/functions/Get-DbaDbPhysicalFile.ps1. The offline-observable contract is
    /// STRUCTURAL: the fixed "Error enumerating files" mask wraps ONLY the query leg -
    /// in the PowerShell source the try covers only the $server.Query call, with the
    /// version-branch read outside it, and the port mirrors that boundary. A failure
    /// BEFORE the query (here: the version read on an unreachable server) is therefore
    /// never replaced by the mask; each world surfaces its own wrapper type at that
    /// boundary, so only mask-absence is pinned. The masked query-leg wrap itself and
    /// the live result shape require a connected instance and ride the integrator gate
    /// through Test-DbaBackupInformation.
    /// </summary>
    [TestClass]
    public class RestoreUtilityPhysicalFileTest
    {
        [TestMethod]
        public void PhysicalFile_PreQueryFailureSurfacesUnmasked()
        {
            InitialSessionState iss = InitialSessionState.CreateDefault2();
            iss.Commands.Add(new SessionStateCmdletEntry("Test-PhysicalFileHost", typeof(TestPhysicalFileHostCommand), null));
            using (System.Management.Automation.Runspaces.Runspace runspace = RunspaceFactory.CreateRunspace(iss))
            {
                runspace.Open();
                using (PowerShell shell = PowerShell.Create())
                {
                    shell.Runspace = runspace;
                    shell.AddCommand("Test-PhysicalFileHost");
                    Collection<PSObject> output = shell.Invoke();
                    Assert.AreEqual(1, output.Count, "host cmdlet emits exactly one outcome record");
                    string outcome = (string)output[0].BaseObject;
                    // The structural claim is TFM-durable: something threw, and the
                    // query-leg mask did not replace it. The concrete type observed on
                    // both current TFMs is ConnectionFailureException, but SMO owns
                    // that choice (and PS surfaces its own property-getter wrapper at
                    // the same boundary), so the type is deliberately not pinned.
                    StringAssert.StartsWith(outcome, "THREW:",
                        "an unreachable server must fail before any rows are produced");
                    Assert.IsFalse(outcome.Contains("Error enumerating files"),
                        "the fixed mask belongs to the query leg only");
                }
            }
        }

        [TestMethod]
        public void PhysicalFile_QueryMaskConstructsEngineRuntimeException()
        {
            // The query-leg mask cannot be DRIVEN offline: the version read precedes
            // the query and requires a live connection (SMO ignores a preset
            // ServerConnection.ServerVersion), so the thrown-mask behavior itself rides
            // the integrator gate. This pin guards the throw-type CONVENTION statically
            // instead: the method body must construct RuntimeException (the engine's
            // shape for the source's bare string throw - the exception type is
            // user-observable past the call site) and no other exception type.
            System.Reflection.MethodInfo method = typeof(RestoreUtility).GetMethod(
                "GetDbaDbPhysicalFile",
                System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Static);
            Assert.IsNotNull(method, "helper resolves");
            bool constructsRuntimeException = false;
            bool constructsOtherException = false;
            foreach (System.Reflection.ConstructorInfo ctor in ConstructedBy(method))
            {
                if (typeof(Exception).IsAssignableFrom(ctor.DeclaringType))
                {
                    if (ctor.DeclaringType == typeof(RuntimeException))
                    {
                        constructsRuntimeException = true;
                    }
                    else
                    {
                        constructsOtherException = true;
                    }
                }
            }
            Assert.IsTrue(constructsRuntimeException,
                "the mask must be the engine RuntimeException, matching PS throw \"string\"");
            Assert.IsFalse(constructsOtherException,
                "no other exception type may replace the mask");
        }

        /// <summary>Decodes the method body instruction by instruction (operand widths
        /// from the reflection-emit opcode table) and yields the constructor of every
        /// genuine newobj instruction - a raw byte scan would also match 0x73 bytes
        /// inside operands.</summary>
        private static System.Collections.Generic.List<System.Reflection.ConstructorInfo> ConstructedBy(System.Reflection.MethodInfo method)
        {
            System.Collections.Generic.Dictionary<short, System.Reflection.Emit.OpCode> opcodeTable =
                new System.Collections.Generic.Dictionary<short, System.Reflection.Emit.OpCode>();
            foreach (System.Reflection.FieldInfo field in typeof(System.Reflection.Emit.OpCodes).GetFields(
                System.Reflection.BindingFlags.Public | System.Reflection.BindingFlags.Static))
            {
                if (field.FieldType == typeof(System.Reflection.Emit.OpCode))
                {
                    System.Reflection.Emit.OpCode opcode = (System.Reflection.Emit.OpCode)field.GetValue(null);
                    opcodeTable[opcode.Value] = opcode;
                }
            }

            byte[] il = method.GetMethodBody().GetILAsByteArray();
            System.Collections.Generic.List<System.Reflection.ConstructorInfo> constructors =
                new System.Collections.Generic.List<System.Reflection.ConstructorInfo>();
            int i = 0;
            while (i < il.Length)
            {
                short value = il[i] == 0xFE ? (short)(0xFE00 | il[i + 1]) : il[i];
                System.Reflection.Emit.OpCode op = opcodeTable[value];
                i += op.Size;
                int operandLength;
                switch (op.OperandType)
                {
                    case System.Reflection.Emit.OperandType.InlineNone:
                        operandLength = 0;
                        break;
                    case System.Reflection.Emit.OperandType.ShortInlineBrTarget:
                    case System.Reflection.Emit.OperandType.ShortInlineI:
                    case System.Reflection.Emit.OperandType.ShortInlineVar:
                        operandLength = 1;
                        break;
                    case System.Reflection.Emit.OperandType.InlineVar:
                        operandLength = 2;
                        break;
                    case System.Reflection.Emit.OperandType.InlineI8:
                    case System.Reflection.Emit.OperandType.InlineR:
                        operandLength = 8;
                        break;
                    case System.Reflection.Emit.OperandType.InlineSwitch:
                        operandLength = 4 + 4 * BitConverter.ToInt32(il, i);
                        break;
                    default:
                        operandLength = 4;
                        break;
                }
                if (op == System.Reflection.Emit.OpCodes.Newobj)
                {
                    int token = BitConverter.ToInt32(il, i);
                    System.Reflection.ConstructorInfo ctor = method.Module.ResolveMethod(
                        token,
                        method.DeclaringType.GetGenericArguments(),
                        method.GetGenericArguments()) as System.Reflection.ConstructorInfo;
                    if (ctor != null)
                    {
                        constructors.Add(ctor);
                    }
                }
                i += operandLength;
            }
            return constructors;
        }
    }
}
