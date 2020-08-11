using System;

namespace Sqlcollaborative.Dbatools.Database
{
    /// <summary>
    /// Class containing all dependency information over a database object
    /// </summary>
    [Serializable]
    public class Dependency
    {
        /// <summary>
        /// The name of the SQL server from whence the query came
        /// </summary>
        public string ComputerName;

        /// <summary>
        /// Name of the service running the database containing the dependency
        /// </summary>
        public string ServiceName;

        /// <summary>
        /// The Instance the database containing the dependency is running in.
        /// </summary>
        public string SqlInstance;

        /// <summary>
        /// The name of the dependent
        /// </summary>
        public string Dependent;

        /// <summary>
        /// The kind of object the dependent is
        /// </summary>
        public string Type;

        /// <summary>
        /// The owner of the dependent (usually the Database)
        /// </summary>
        public string Owner;

        /// <summary>
        /// Whether the dependency is Schemabound. If it is, then the creation statement order is of utmost importance.
        /// </summary>
        public bool IsSchemaBound;

        /// <summary>
        /// The immediate parent of the dependent. Useful in multi-tier dependencies.
        /// </summary>
        public string Parent;

        /// <summary>
        /// The type of object the immediate parent is.
        /// </summary>
        public string ParentType;

        /// <summary>
        /// The script used to create the object.
        /// </summary>
        public string Script;

        /// <summary>
        /// The tier in the dependency hierarchy tree. Used to determine, which dependency must be applied in which order.
        /// </summary>
        public int Tier;

        /// <summary>
        /// The smo object of the dependent.
        /// </summary>
        public object Object;

        /// <summary>
        /// The Uniform Resource Name of the dependent.
        /// </summary>
        public object Urn;

        /// <summary>
        /// The object of the original resource, from which the dependency hierachy has been calculated.
        /// </summary>
        public object OriginalResource;
    }
}