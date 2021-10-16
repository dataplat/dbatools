namespace Sqlcollaborative.Dbatools.Configuration
{
    /// <summary>
    /// The data types supported by the configuration system.
    /// </summary>
    public enum ConfigurationValueType
    {
        /// <summary>
        /// An unknown type, should be prevented
        /// </summary>
        Unknown = 0,

        /// <summary>
        /// The value is as empty as the void.
        /// </summary>
        Null = 1,

        /// <summary>
        /// The value is of a true/false kind
        /// </summary>
        Bool = 2,

        /// <summary>
        /// The value is a regular integer
        /// </summary>
        Int = 3,

        /// <summary>
        /// The value is a double numeric value
        /// </summary>
        Double = 4,

        /// <summary>
        /// The value is a long type
        /// </summary>
        Long = 5,

        /// <summary>
        /// The value is a common string
        /// </summary>
        String = 6,

        /// <summary>
        /// The value is a regular timespan
        /// </summary>
        Timespan = 7,

        /// <summary>
        /// The value is a plain datetime
        /// </summary>
        Datetime = 8,

        /// <summary>
        /// The value is a fancy console color
        /// </summary>
        ConsoleColor = 9,

        /// <summary>
        /// The value is an array full of booty
        /// </summary>
        Array = 10,

        /// <summary>
        /// The value is a hashtable
        /// </summary>
        Hashtable = 11,

        /// <summary>
        /// The value is something indeterminate, but possibly complex
        /// </summary>
        Object = 12,
    }
}
