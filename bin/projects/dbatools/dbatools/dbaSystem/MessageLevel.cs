namespace Sqlcollaborative.Dbatools.dbaSystem
{
    /// <summary>
    /// The various levels of verbosity available.
    /// </summary>
    public enum MessageLevel
    {
        /// <summary>
        /// Very important message, should be shown to the user as a high priority
        /// </summary>
        Critical = 1,

        /// <summary>
        /// Important message, the user should read this
        /// </summary>
        Important = 2,

        /// <summary>
        /// Important message, the user should read this
        /// </summary>
        Output = 2,

        /// <summary>
        /// Message relevant to the user.
        /// </summary>
        Significant = 3,

        /// <summary>
        /// Not important to the regular user, still of some interest to the curious
        /// </summary>
        VeryVerbose = 4,

        /// <summary>
        /// Background process information, in case the user wants some detailed information on what is currently happening.
        /// </summary>
        Verbose = 5,

        /// <summary>
        /// A footnote in current processing, rarely of interest to the user
        /// </summary>
        SomewhatVerbose = 6,

        /// <summary>
        /// A message of some interest from an internal system persepctive, but largely irrelevant to the user.
        /// </summary>
        System = 7,

        /// <summary>
        /// Something only of interest to a debugger
        /// </summary>
        Debug = 8,

        /// <summary>
        /// This message barely made the cut from being culled. Of purely development internal interest, and even there is 'interest' a strong word for it.
        /// </summary>
        InternalComment = 9,

        /// <summary>
        /// This message is a warning, sure sign something went badly wrong
        /// </summary>
        Warning = 666
    }
}