using System;
using System.Collections.Generic;
using System.Management.Automation;

namespace Sqlcollaborative.Dbatools.Message
{
    /// <summary>
    /// Container for a callstack, to create a non-volatile copy of the relevant information
    /// </summary>
    [Serializable]
    public class CallStack
    {
        /// <summary>
        /// The entries that make up the callstack
        /// </summary>
        public List<CallStackEntry> Entries = new List<CallStackEntry>();

        /// <summary>
        /// String representation of the callstack copy
        /// </summary>
        /// <returns></returns>
        public override string ToString()
        {
            return String.Join("\n\t", Entries);
        }

        /// <summary>
        /// Create an empty callstack
        /// </summary>
        public CallStack()
        {

        }

        /// <summary>
        /// Initialize a callstack from a live callstack frame
        /// </summary>
        /// <param name="CallStack">The live powershell callstack</param>
        public CallStack(IEnumerable<CallStackFrame> CallStack)
        {
            foreach (CallStackFrame frame in CallStack)
                Entries.Add(new CallStackEntry(frame.FunctionName, frame.ScriptName, frame.ScriptLineNumber, frame.InvocationInfo));
        }
    }
}
