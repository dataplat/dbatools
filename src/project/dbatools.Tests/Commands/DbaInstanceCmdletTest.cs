using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using Dataplat.Dbatools.Commands;
using Dataplat.Dbatools.Parameter;
using Microsoft.SqlServer.Management.Smo;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace Dataplat.Dbatools.Commands.Test
{
    /// <summary>
    /// Host cmdlet over DbaInstanceCmdlet.ConnectInstance, driven against an unreachable
    /// instance (a closed local port) so the connect fails without a lab. The abstract
    /// SqlInstance/SqlCredential are overridden as plain auto-properties - the base leaves
    /// them attribute-free so each concrete cmdlet owns its parameter shape; this host
    /// constructs the target directly rather than binding it.
    /// </summary>
    [Cmdlet("Test", "DbaInstanceConnect")]
    public sealed class TestDbaInstanceConnectCommand : DbaInstanceCmdlet
    {
        public override DbaInstanceParameter[] SqlInstance { get; set; }

        public override PSCredential SqlCredential { get; set; }

        protected override void ProcessRecord()
        {
            DbaInstanceParameter target = new DbaInstanceParameter("tcp:127.0.0.1,9");
            Server server = ConnectInstance(target, "Failed to connect");
            // Reached only when ConnectInstance RETURNED (did not throw out of the cmdlet).
            WriteObject("server=" + (server == null ? "null" : "notnull"));
            WriteObject("interrupted=" + Interrupted);
        }
    }

    /// <summary>
    /// Direct MSTest coverage for DbaInstanceCmdlet.ConnectInstance - the canonical connect
    /// wrapper every instance-scoped cmdlet routes through. Proves the two failure shapes the
    /// contract promises: without EnableException a failed connect runs the Stop-Function
    /// -Continue equivalent and returns null while leaving Interrupted false (the caller's loop
    /// proceeds); with EnableException the same failure throws out of the cmdlet. The connect is
    /// aimed at a closed local port so it fails fast and needs no lab; the assertions hold
    /// whatever the underlying failure is, because ConnectInstance catches every exception.
    /// </summary>
    [TestClass]
    public class DbaInstanceCmdletTest
    {
        private static Collection<PSObject> Invoke(bool enableException, out bool threw, out bool hadErrors)
        {
            Collection<PSObject> output = new Collection<PSObject>();
            threw = false;
            InitialSessionState iss = InitialSessionState.CreateDefault2();
            iss.Commands.Add(new SessionStateCmdletEntry("Test-DbaInstanceConnect", typeof(TestDbaInstanceConnectCommand), null));
            using (System.Management.Automation.Runspaces.Runspace runspace = RunspaceFactory.CreateRunspace(iss))
            {
                runspace.Open();
                using (PowerShell shell = PowerShell.Create())
                {
                    shell.Runspace = runspace;
                    shell.AddCommand("Test-DbaInstanceConnect");
                    if (enableException)
                        shell.AddParameter("EnableException");
                    try
                    {
                        output = shell.Invoke();
                    }
                    catch (Exception)
                    {
                        threw = true;
                    }
                    hadErrors = shell.HadErrors;
                }
            }
            return output;
        }

        private static bool HasRecord(Collection<PSObject> output, string text)
        {
            foreach (PSObject item in output)
            {
                if (item != null && String.Equals(item.BaseObject as string, text, StringComparison.Ordinal))
                    return true;
            }
            return false;
        }

        private static bool AnyRecordStartsWith(Collection<PSObject> output, string prefix)
        {
            foreach (PSObject item in output)
            {
                string value = item == null ? null : item.BaseObject as string;
                if (value != null && value.StartsWith(prefix, StringComparison.Ordinal))
                    return true;
            }
            return false;
        }

        [TestMethod]
        [Timeout(120000)]
        public void ConnectInstance_UnreachableInstance_ReturnsNullAndContinues()
        {
            bool threw;
            bool hadErrors;
            Collection<PSObject> output = Invoke(false, out threw, out hadErrors);

            Assert.IsFalse(threw, "without EnableException a failed connect must not throw");
            Assert.IsTrue(HasRecord(output, "server=null"), "ConnectInstance returns null on connect failure");
            Assert.IsTrue(HasRecord(output, "interrupted=False"),
                "the -Continue equivalent leaves Interrupted false so the caller's loop proceeds");
        }

        [TestMethod]
        [Timeout(120000)]
        public void ConnectInstance_UnreachableInstance_ThrowsUnderEnableException()
        {
            bool threw;
            bool hadErrors;
            Collection<PSObject> output = Invoke(true, out threw, out hadErrors);

            Assert.IsFalse(AnyRecordStartsWith(output, "server="),
                "under EnableException the failed connect throws before ConnectInstance returns");
            Assert.IsTrue(threw || hadErrors, "the connect failure surfaces to the caller under EnableException");
        }
    }
}
