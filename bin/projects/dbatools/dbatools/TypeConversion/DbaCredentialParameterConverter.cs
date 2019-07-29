using System;
using System.Collections.Generic;
using System.Linq;
using System.Management.Automation;
using System.Text;
using System.Threading.Tasks;
using Sqlcollaborative.Dbatools.Parameter;

namespace Sqlcollaborative.Dbatools.TypeConversion
{
    /// <summary>
    /// Converts to and from DbaCredentialparameter
    /// </summary>
    public class DbaCredentialParameterConverter : PSTypeConverter
    {
        /// <summary>
        /// Verifies, whether a conversion for the object to the target type is possible
        /// </summary>
        /// <param name="SourceValue">The object to convert</param>
        /// <param name="DestinationType">The type to convert to</param>
        /// <returns>Whether it's possible, duh!</returns>
        public override bool CanConvertTo(object SourceValue, Type DestinationType)
        {
            if (SourceValue == null)
                return false;
            if (!(SourceValue is DbaCredentialParameter))
                return false;
            return IsSupportedType(DestinationType);
        }

        /// <summary>
        /// Converts from DbaCredentialparameter to whatever destination type is attempted
        /// </summary>
        /// <param name="sourceValue">The source object. Better be a DbaCredentialparameter!</param>
        /// <param name="destinationType">Should be a supported destination type</param>
        /// <param name="formatProvider">Irrelevant</param>
        /// <param name="ignoreCase">Irrelevant</param>
        /// <returns>The target content type</returns>
        public override object ConvertTo(object sourceValue, Type destinationType, IFormatProvider formatProvider, bool ignoreCase)
        {
            if (!CanConvertTo(sourceValue, destinationType))
                throw new ArgumentException("Conversion not supported!");

            switch (destinationType.FullName)
            {
                case "System.Net.NetworkCredential":
                    return (System.Net.NetworkCredential)sourceValue;
                case "System.Management.Automation.PSCredential":
                    return (PSCredential)sourceValue;
                default:
                    throw new InvalidCastException(String.Format("Cannot convert from {0} to {1}!", sourceValue.GetType().FullName, destinationType.FullName));
            }
        }

        /// <summary>
        /// Verifies, whether a conversion for the object from the source type to DbaCredentialParameter is possible
        /// </summary>
        /// <param name="SourceValue">The object to convert</param>
        /// <param name="DestinationType">The source type to convert to</param>
        /// <returns>Whether it's possible, duh!</returns>
        public override bool CanConvertFrom(object SourceValue, Type DestinationType)
        {
            if (DestinationType.FullName != "Sqlcollaborative.Dbatools.Parameter.DbaCredentialParameter")
                return false;
            if (SourceValue == null)
                return false;

            return IsSupportedType(SourceValue.GetType());
        }

        /// <summary>
        /// Converts a source object to DbaCredentialparameter
        /// </summary>
        /// <param name="sourceValue">The source object</param>
        /// <param name="destinationType">The destination type. Must be DbaCredentialParameter, or red stuff happens</param>
        /// <param name="formatProvider">Irrelevant</param>
        /// <param name="ignoreCase">Irrelevant</param>
        /// <returns></returns>
        public override object ConvertFrom(object sourceValue, Type destinationType, IFormatProvider formatProvider, bool ignoreCase)
        {
            if (!CanConvertFrom(sourceValue, destinationType))
                throw new ArgumentException("Conversion not supported!");

            return new DbaCredentialParameter(sourceValue);
        }

        /// <summary>
        /// Returns, whether a given type is supported for conversion
        /// </summary>
        /// <param name="type">The type to validate</param>
        /// <returns>Whether it's a supported conversion</returns>
        private bool IsSupportedType(Type type)
        {
            switch (type.FullName)
            {
                case "Sqlcollaborative.Dbatools.Parameter.DbaCredentialParameter":
                    return true;
                case "System.Net.NetworkCredential":
                    return true;
                case "System.Management.Automation.PSCredential":
                    return true;
                default:
                    return false;
            }
        }
    }
}
