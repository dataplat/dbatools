using System;
using System.Management.Automation;
using System.Text.RegularExpressions;

namespace Sqlcollaborative.Dbatools.Utility
{
    /// <summary>
    /// Validates that each parameter argument matches the RegexPattern
    /// </summary>
    public class DbaValidatePatternAttribute : ValidateEnumeratedArgumentsAttribute
    {
        /// <summary>
        /// Gets the Regex pattern to be used in the validation
        /// </summary>
        public string RegexPattern { get; private set; }

        /// <summary>
        /// Gets or sets the Regex options to be used in the validation
        /// </summary>
        public RegexOptions Options { set; get; }

        /// <summary>
        /// Gets or sets the custom error message pattern that is displayed to the user.
        ///
        /// The text representation of the object being validated and the validating regex is passed as
        /// the first and second formatting parameters to the ErrorMessage formatting pattern.
        /// <example>
        /// [ValidatePattern("\s+", ErrorMessage="The text '{0}' did not pass validation of regex '{1}'")]
        /// </example>
        /// </summary>
        public string ErrorMessage { get; set; }

        /// <summary>
        /// Validates that each parameter argument matches the RegexPattern
        /// </summary>
        /// <param name="element">object to validate</param>
        /// <exception cref="ValidationMetadataException">if <paramref name="element"/> is not a string
        ///  that matches the pattern
        ///  and for invalid arguments</exception>
        protected override void ValidateElement(object element)
        {
            if (element == null)
                throw new ValidationMetadataException("Argument Is Empty");

            string objectString = element.ToString();
            Regex regex = null;
            regex = new Regex(RegexPattern, Options);
            Match match = regex.Match(objectString);
            if (!match.Success)
            {
                var errorMessageFormat = String.IsNullOrEmpty(ErrorMessage) ? "Failed to validate: {0} against pattern {1}" : ErrorMessage;
                throw new ValidationMetadataException(String.Format(errorMessageFormat, element, RegexPattern));
            }
        }

        /// <summary>
        /// Initializes a new instance of the PsfValidatePatternAttribute class
        /// </summary>
        /// <param name="regexPattern">Pattern string to match</param>
        /// <exception cref="ArgumentException">for invalid arguments</exception>
        public DbaValidatePatternAttribute(string regexPattern)
        {
            Options = RegexOptions.IgnoreCase;
            if (String.IsNullOrEmpty(regexPattern)) {
                throw new ArgumentNullException("regexPattern", "Must specify a pattern!");
            }

            RegexPattern = regexPattern;
        }
    }
}
