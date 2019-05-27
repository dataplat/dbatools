namespace Sqlcollaborative.Dbatools.Message
{
    /// <summary>
    /// The messaging system provides these kinds of transformations for input.
    /// </summary>
    public enum TransformType
    {
        /// <summary>
        /// A target transform can transform the target object specified. Used for live-state objects that should not be serialized on a second thread.
        /// </summary>
        Target = 1,

        /// <summary>
        /// An exception transform allows automatic transformation of exceptions. Primarily used to unwrap exceptions from an API that wraps all exceptions.
        /// </summary>
        Exception = 2,
    }
}
