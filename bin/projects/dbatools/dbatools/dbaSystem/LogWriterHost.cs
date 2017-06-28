using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Threading;

namespace Sqlcollaborative.Dbatools.dbaSystem
{
    /// <summary>
    /// Hosts all functionality of the log writer
    /// </summary>
    public static class LogWriterHost
    {
        #region Logwriter
        private static ScriptBlock LogWritingScript;

        private static PowerShell LogWriter;

        /// <summary>
        /// Setting this to true should cause the script running in the runspace to selfterminate, allowing a graceful selftermination.
        /// </summary>
        public static bool LogWriterStopper
        {
            get { return _LogWriterStopper; }
        }
        private static bool _LogWriterStopper;

        /// <summary>
        /// Set the script to use as part of the log writer
        /// </summary>
        /// <param name="Script">The script to use</param>
        public static void SetScript(ScriptBlock Script)
        {
            LogWritingScript = Script;
        }

        /// <summary>
        /// Starts the logwriter.
        /// </summary>
        public static void Start()
        {
            if ((DebugHost.ErrorLogFileEnabled || DebugHost.MessageLogFileEnabled) && (LogWriter == null))
            {
                _LogWriterStopper = false;
                LogWriter = PowerShell.Create();
                LogWriter.AddScript(LogWritingScript.ToString());
                LogWriter.BeginInvoke();
            }
        }

        /// <summary>
        /// Gracefully stops the logwriter
        /// </summary>
        public static void Stop()
        {
            _LogWriterStopper = true;

            int i = 0;

            // Wait up to 30 seconds for the running script to notice and kill itself
            while ((LogWriter.Runspace.RunspaceAvailability != RunspaceAvailability.Available) && (i < 300))
            {
                i++;
                Thread.Sleep(100);
            }

            Kill();
        }

        /// <summary>
        /// Very ungracefully kills the logwriter. Use only in the most dire emergency.
        /// </summary>
        public static void Kill()
        {
            if (LogWriter != null)
            {
                LogWriter.Runspace.Close();
                LogWriter.Dispose();
                LogWriter = null;
            }
        }
        #endregion Logwriter
    }
}