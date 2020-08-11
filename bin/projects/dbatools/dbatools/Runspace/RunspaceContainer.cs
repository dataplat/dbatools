using System;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Threading;

namespace Sqlcollaborative.Dbatools.Runspace
{
    /// <summary>
    /// Class that contains the logic necessary to manage a unique runspace
    /// </summary>
    public class RunspaceContainer
    {
        private ScriptBlock Script;

        private PowerShell Runspace;

        /// <summary>
        /// The name of the runspace.
        /// </summary>
        public readonly string Name;

        /// <summary>
        /// The Guid of the running Runspace
        /// </summary>
        public Guid RunspaceGuid
        {
            get { return Runspace.Runspace.InstanceId; }
        }

        /// <summary>
        /// Sets the script to execute in the runspace. Will NOT take immediate effect. Only after restarting the runspace will it be used.
        /// </summary>
        /// <param name="Script">The scriptblock to execute</param>
        public void SetScript(ScriptBlock Script)
        {
            this.Script = Script;
        }

        /// <summary>
        /// The state the runspace currently is in.
        /// </summary>
        public DbaRunspaceState State
        {
            get { return _State; }
        }
        private DbaRunspaceState _State = DbaRunspaceState.Stopped;

        /// <summary>
        /// Starts the Runspace.
        /// </summary>
        public void Start()
        {
            if ((Runspace != null) && (State == DbaRunspaceState.Stopped))
            {
                Kill();
            }

            if (Runspace == null)
            {
                Runspace = PowerShell.Create();
                try { SetName(Runspace.Runspace); }
                catch { }
                Runspace.AddScript(Script.ToString());
                _State = DbaRunspaceState.Running;
                try { Runspace.BeginInvoke(); }
                catch { _State = DbaRunspaceState.Stopped; }
            }
        }

        /// <summary>
        /// Sets the name on a runspace. This WILL FAIL for PowerShell v3!
        /// </summary>
        /// <param name="Runspace">The runspace to be named</param>
        private void SetName(System.Management.Automation.Runspaces.Runspace Runspace)
        {
            #if (NORUNSPACENAME)

            #else
            Runspace.Name = Name;
            #endif
        }

        /// <summary>
        /// Gracefully stops the Runspace
        /// </summary>
        public void Stop()
        {
            _State = DbaRunspaceState.Stopping;

            int i = 0;

            // Wait up to the limit for the running script to notice and kill itself
            if ((Runspace != null) && (Runspace.Runspace != null))
            {
                while ((Runspace.Runspace.RunspaceAvailability != RunspaceAvailability.Available) && (i < (10 * RunspaceHost.StopTimeoutSeconds)))
                {
                    i++;
                    Thread.Sleep(100);
                }
            }

            Kill();
        }

        /// <summary>
        /// Very ungracefully kills the runspace. Use only in the most dire emergency.
        /// </summary>
        public void Kill()
        {
            if (Runspace != null)
            {
                try { Runspace.Runspace.Close(); }
                catch { }
                Runspace.Dispose();
                Runspace = null;
            }

            _State = DbaRunspaceState.Stopped;
        }

        /// <summary>
        /// Signals the registered runspace has stopped execution
        /// </summary>
        public void SignalStopped()
        {
            _State = DbaRunspaceState.Stopped;
        }

        /// <summary>
        /// Creates a new runspace container with the basic information needed
        /// </summary>
        /// <param name="Name">The name of the Runspace</param>
        /// <param name="Script">The code using the runspace logic</param>
        public RunspaceContainer(string Name, ScriptBlock Script)
        {
            this.Name = Name.ToLower();
            this.Script = Script;
        }
    }
}
