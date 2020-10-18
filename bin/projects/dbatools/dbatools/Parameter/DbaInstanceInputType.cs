namespace Sqlcollaborative.Dbatools.Parameter
{
    /// <summary>
    /// What kind of object was bound to the parameter class?
    /// </summary>
    public enum DbaInstanceInputType
    {
        /// <summary>
        /// Anything, really. An unspecific not reusable type was bound
        /// </summary>
        Default,

        /// <summary>
        /// A live smo linked server object was bound
        /// </summary>
        Linked,

        /// <summary>
        /// A live smo server object was bound
        /// </summary>
        Server,

        /// <summary>
        /// A Central Management Server RegisteredServer SMO object was bound
        /// </summary>
        RegisteredServer,

        /// <summary>
        /// An actual connection string was specified. Connection strings are directly reused for SMO connections
        /// </summary>
        ConnectionString,

        /// <summary>
        /// A connection string pointing at a local, file-based DB
        /// </summary>
        ConnectionStringLocalDB,

        /// <summary>
        /// An already established sql connection to was created outside of SMO
        /// </summary>
        SqlConnection
    }
}