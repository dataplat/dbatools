using System;
using System.Management.Automation;

namespace Sqlcollaborative.Dbatools.TabExpansion
{
    /// <summary>
    /// Regular container to store scripts in, that are used in TEPP
    /// </summary>
    public class ScriptContainer
    {
        /// <summary>
        /// The name of the scriptblock
        /// </summary>
        public string Name;

        /// <summary>
        /// The scriptblock doing the logic
        /// </summary>
        public ScriptBlock ScriptBlock;

        /// <summary>
        /// The last time the scriptblock was called. Must be updated by the scriptblock itself
        /// </summary>
        public DateTime LastExecution;

        /// <summary>
        /// The time it took to run the last time
        /// </summary>
        public TimeSpan LastDuration;
    }
}