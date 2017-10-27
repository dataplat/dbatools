using System;

namespace Sqlcollaborative.Dbatools.dbaSystem
{
    /// <summary>
    /// The kind of information the logged entry was.
    /// </summary>
    [Flags]
    public enum LogEntryType
    {
        /// <summary>
        /// This entry wasn't written to any stream
        /// </summary>
        None = 0,

        /// <summary>
        /// A message that was written to the current host equivalent, if available also to the information stream
        /// </summary>
        Information = 1,

        /// <summary>
        /// A message that was written to the verbose stream
        /// </summary>
        Verbose = 2,

        /// <summary>
        /// A message that was written to the Debug stream
        /// </summary>
        Debug = 4,

        /// <summary>
        /// A message written to the warning stream
        /// </summary>
        Warning = 8
    }
}