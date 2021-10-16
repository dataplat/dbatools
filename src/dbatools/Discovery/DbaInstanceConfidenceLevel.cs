namespace Sqlcollaborative.Dbatools.Discovery
{
    /// <summary>
    /// How high is our confidence that this is a valid instance?
    /// </summary>
    public enum DbaInstanceConfidenceLevel
    {
        /// <summary>
        /// No confidence at all. There is virtually no way for this to be an instance
        /// </summary>
        None = 0,

        /// <summary>
        /// We have a few indications, but couldn't follow them up
        /// </summary>
        Low = 1,

        /// <summary>
        /// We're fairly sure this is legit, but can't guarantee it
        /// </summary>
        Medium = 2,

        /// <summary>
        /// This absolutely is an instance
        /// </summary>
        High = 4
    }
}
