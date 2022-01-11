using System;
using System.Management.Automation;

namespace Sqlcollaborative.Dbatools.Message
{
    /// <summary>
    /// A single entry within the callstack
    /// </summary>
    [Serializable]
    public class CallStackEntry
    {
        /// <summary>
        /// The name of the command that executed
        /// </summary>
        public string FunctionName;

        /// <summary>
        /// The file the command was defined in
        /// </summary>
        public string File
        {
            get
            {
                if (String.IsNullOrEmpty(_File))
                    return "<none>";
                return _File;
            }
            set { _File = value; }
        }
        private string _File;

        /// <summary>
        /// THe line in the scriptblock that has been executed
        /// </summary>
        public int Line;

        /// <summary>
        /// The full invocation info object
        /// </summary>
        public InvocationInfo InvocationInfo;

        /// <summary>
        /// Create an empty callstack entry.
        /// </summary>
        public CallStackEntry()
        {

        }

        /// <summary>
        /// Creates a prefilled callstack entry.
        /// </summary>
        /// <param name="FunctionName"></param>
        /// <param name="File"></param>
        /// <param name="Line"></param>
        /// <param name="InvocationInfo"></param>
        public CallStackEntry(string FunctionName, string File, int Line, InvocationInfo InvocationInfo)
        {
            this.FunctionName = FunctionName;
            this.File = File;
            this.Line = Line;
            this.InvocationInfo = InvocationInfo;
        }

        /// <summary>
        /// The string notation of the callstack entry
        /// </summary>
        /// <returns></returns>
        public override string ToString()
        {
            return String.Format("At {0}, {1}: Line {2}", FunctionName, File, Line);
        }
    }
}