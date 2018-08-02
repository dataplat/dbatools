using System;
using System.Management.Automation;

namespace Sqlcollaborative.Dbatools.Utility
{
    /// <summary>
    /// Class for validating against a script block.
    /// </summary>
    public class DbaValidateScriptAttribute : ValidateEnumeratedArgumentsAttribute
    {
        /// <summary>
        /// Gets or sets the custom error message that is displayed to the user.
        ///
        /// The item being validated and the validating scriptblock is passed as the first and second
        /// formatting argument.
        ///
        /// <example>
        /// [ValidateScript("$_ % 2", ErrorMessage = "The item '{0}' did not pass validation of script '{1}'")]
        /// </example>
        /// </summary>
        public string ErrorMessage { get; set; }

        /// <summary>
        /// Gets the scriptblock to be used in the validation
        /// </summary>
        public ScriptBlock ScriptBlock { get; private set; }

        /// <summary>
        /// Validates that each parameter argument matches the scriptblock
        /// </summary>
        /// <param name="element">object to validate</param>
        /// <exception cref="ValidationMetadataException">if <paramref name="element"/> is invalid</exception>
        protected override void ValidateElement(object element)
        {
            if (element == null)
            {
                throw new ValidationMetadataException("ArgumentIsEmpty", null);
            }

            object result = ScriptBlock.Invoke(element);

            if (!LanguagePrimitives.IsTrue(result))
            {
                var errorMessageFormat = String.IsNullOrEmpty(ErrorMessage) ? "Error executing validation script: {0} against {{ {1} }}" : ErrorMessage;
                throw new ValidationMetadataException(String.Format(errorMessageFormat, element, ScriptBlock));
            }
        }

        /// <summary>
        /// Initializes a new instance of the ValidateScriptBlockAttribute class
        /// </summary>
        /// <param name="scriptBlock">Scriptblock to match</param>
        /// <exception cref="ArgumentException">for invalid arguments</exception>
        public DbaValidateScriptAttribute(ScriptBlock scriptBlock)
        {
            if (scriptBlock == null) {
                throw new ArgumentNullException("scriptBlock", "Need to specify a scriptblock!");
            }
            this.ScriptBlock = ScriptBlock;
        }
    }
}
