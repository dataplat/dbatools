using System;

namespace Sqlcollaborative.Dbatools.Configuration
{
    /// <summary>
    /// Contains all information about a configuration item's value
    /// </summary>
    [Serializable]
    public class ConfigurationValue
    {
        #region Public Properties
        /// <summary>
        /// The runtime value of the setting.
        /// </summary>
        public object Value
        {
            get
            {
                if (_Value != null)
                    return _Value;

                if (PersistedValue != null)
                    try
                    {
                        _Value = ConfigurationHost.ConvertFromPersistedValue(PersistedValue, PersistedType);
                        return _Value;
                    }
                    catch { }

                return null;
            }
            set
            {
                if (value == null)
                {
                    PersistedType = ConfigurationValueType.Null;
                    _PersistedValue = "null";
                }
                else
                    _PersistedValue = null;

                _Value = value;
            }
        }

        /// <summary>
        /// The value in its persisted state
        /// </summary>
        public string PersistedValue
        {
            get
            {
                if (_PersistedValue == null)
                {
                    ConfigurationValue tempValue = ConfigurationHost.ConvertToPersistedValue(_Value);
                    PersistedType = tempValue.PersistedType;
                    _PersistedValue = tempValue.PersistedValue;
                }

                return _PersistedValue;
            }
            set
            {
                _PersistedValue = value;
                _Value = null;
            }
        }

        /// <summary>
        /// The kind of 
        /// </summary>
        public ConfigurationValueType PersistedType;

        /// <summary>
        /// The type qualified representation of the persisted value
        /// </summary>
        public string TypeQualifiedPersistedValue
        {
            get { return String.Format("{1}:{0}", PersistedValue, PersistedType); }
            set { }
        }

        /// <summary>
        /// Ensures wanton Get-PSFConfig will not deserialize persisted objects that might have registered deserialization in their module.
        /// </summary>
        public object SafeValue
        {
            get
            {
                if (PersistedType == ConfigurationValueType.Null)
                    return null;
                if (_Value != null)
                    return _Value;
                if (PersistedType == ConfigurationValueType.Object)
                    return PersistedValue;
                return Value;
            }
            set { }
        }
        #endregion Public Properties

        #region Private fields
        /// <summary>
        /// Internal storage for the Value property
        /// </summary>
        private object _Value;

        /// <summary>
        /// Internal storage for the PersistedValue property
        /// </summary>
        private string _PersistedValue;
        #endregion Private fields

        #region Methods
        /// <summary>
        /// The string representation of its actual value
        /// </summary>
        /// <returns>Returns the type-qualified string representation of its value</returns>
        public override string ToString()
        {
            return String.Format("{0}:{1}", PersistedType, PersistedValue);
        }
        #endregion Methods

        #region Constructors
        /// <summary>
        /// Creates a value object from persisted data
        /// </summary>
        /// <param name="PersistedValue">The value that will be persisted</param>
        /// <param name="PersistedType">The type of the value to be persisted</param>
        public ConfigurationValue(string PersistedValue, ConfigurationValueType PersistedType)
        {
            this.PersistedType = PersistedType;
            this.PersistedValue = PersistedValue;
        }

        /// <summary>
        /// Creates a value object from runtime data
        /// </summary>
        /// <param name="Value">The value that will be stored</param>
        public ConfigurationValue(object Value)
        {
            this.Value = Value;
        }
        #endregion Constructors
    }
}
