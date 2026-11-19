namespace Dataplat.Dbatools.Commands
{
    /// <summary>
    /// One-way interrupt handoff used by satellite compatibility hops.
    /// </summary>
    public interface INestedCommandInterruptHost
    {
        /// <summary>
        /// Latches the host command after a module-scoped Stop-Function call.
        /// </summary>
        void InterruptFromNestedCommand();
    }
}
