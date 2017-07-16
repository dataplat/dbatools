namespace Sqlcollaborative.Dbatools.General
{
    /// <summary>
    /// What kind of mode do you want to run a command in?
    /// This allows the user to choose how a dbatools function handles a bump in the execution where terminating directly may not be actually mandated.
    /// </summary>
    public enum ExecutionMode
    {
        /// <summary>
        /// When encountering issues, terminate, or skip the currently processed input, rather than continue.
        /// </summary>
        Strict,

        /// <summary>
        /// Continue as able with a best-effort attempt. Simple verbose output should do the rest.
        /// </summary>
        Lazy,

        /// <summary>
        /// Continue, but provide output that can be used to identify the operations that had issues.
        /// </summary>
        Report
    }
}