namespace Sqlcollaborative.Dbatools.Connection
{
    /// <summary>
    /// The protocol to connect over via SMO
    /// </summary>
    public enum SqlConnectionProtocol
    {
        /// <summary>
        /// Connect using any protocol available
        /// </summary>
        Any = 1,

        /// <summary>
        /// Connect using TCP/IP
        /// </summary>
        TCP = 2,

        /// <summary>
        /// Connect using named pipes or shared memory
        /// </summary>
        NP = 3
    }
}