namespace Sqlcollaborative.Dbatools.Discovery
{
    /// <summary>
    /// Indiciator for whether an instance is known to be available or not
    /// </summary>
    public enum DbaInstanceAvailability
    {
        /// <summary>
        /// It is not known, whether the instance is available or not
        /// </summary>
        Unknown = 0,

        /// <summary>
        /// The instance is known to be available
        /// </summary>
        Available = 1,

        /// <summary>
        /// The instance is known to be not available
        /// </summary>
        Unavailable = 2
    }
}
