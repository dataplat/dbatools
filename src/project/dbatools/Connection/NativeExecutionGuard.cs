using System;
using System.Management.Automation;
using System.Threading;

namespace Dataplat.Dbatools.Connection
{
    /// <summary>Rejects compatibility execution by the command under native verification.</summary>
    public static class NativeExecutionGuard
    {
        private static long refusalCount;
        private static readonly string strictCommand;

        static NativeExecutionGuard()
        {
            strictCommand = Environment.GetEnvironmentVariable("DBATOOLS_NATIVE_STRICT") ?? String.Empty;
        }

        /// <summary>The process's verification command, captured before command execution.</summary>
        public static string StrictCommand
        {
            get { return strictCommand; }
        }

        /// <summary>Counts blocked hops even when a caller catches the strict-mode exception.</summary>
        public static long RefusalCount
        {
            get { return Interlocked.Read(ref refusalCount); }
        }

        /// <summary>Checks the invoking command without preventing other fixture commands.</summary>
        public static void Check(PSCmdlet host)
        {
            if (String.IsNullOrEmpty(strictCommand))
                return;
            if (host == null)
            {
                Interlocked.Increment(ref refusalCount);
                throw new ArgumentNullException("host");
            }

            string command = host.MyInvocation.MyCommand.Name;
            if (String.Equals(strictCommand,
                command, StringComparison.OrdinalIgnoreCase))
            {
                Interlocked.Increment(ref refusalCount);
                throw new InvalidOperationException(String.Format(
                    "native strict mode: PowerShell hop in {0}", command));
            }
        }
    }
}
