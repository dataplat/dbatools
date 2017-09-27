namespace Sqlcollaborative.Dbatools.Parameter
{
    /// <summary>
    /// Defines what kind of element is granted the contract
    /// </summary>
    public enum ParameterContractType
    {
        /// <summary>
        /// The contracted element is a field containing a value
        /// </summary>
        Field,

        /// <summary>
        /// The contracted element is a method, performing an action
        /// </summary>
        Method,

        /// <summary>
        /// The contracted element is an operator, facilitating type conversion. Generally into a dedicated object type this parameterclass abstracts.
        /// </summary>
        Operator
    }
}