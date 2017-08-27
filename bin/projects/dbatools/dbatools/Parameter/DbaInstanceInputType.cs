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
        RegisteredServer
    }
}