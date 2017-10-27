namespace Sqlcollaborative.Dbatools.Connection
{
    /// <summary>
    /// The various types of state a connection-protocol may have
    /// </summary>
    public enum ManagementConnectionProtocolState
    {
        /// <summary>
        /// The default initial state, before any tests are performed
        /// </summary>
        Unknown = 1,

        /// <summary>
        /// A successful connection was last established
        /// </summary>
        Success = 2,

        /// <summary>
        /// Connecting using the relevant protocol failed last it was tried
        /// </summary>
        Error = 4,

        /// <summary>
        /// The relevant protocol has been disabled and should not be used
        /// </summary>
        Disabled = 8
    }
}