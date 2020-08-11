using System;

namespace Sqlcollaborative.Dbatools.Parameter
{
    /// <summary>
    /// Defines how this element will behave
    /// </summary>
    [Flags]
    public enum ParameterContractBehavior
    {
        /// <summary>
        /// This elements is not actually part of the contract. Generally you wouldn't want to add the attribute at all in that case. However, in some places it helps avoiding confusion.
        /// </summary>
        NotContracted = 0,

        /// <summary>
        /// This element may never be null and must be considered in all assignments. Even if the element is de facto not nullable, all constructors must assign it.
        /// </summary>
        Mandatory = 1,

        /// <summary>
        /// This element may contain data, but is not required to. In case of a method, it may simply do nothing
        /// </summary>
        Optional = 2,

        /// <summary>
        /// This method may throw an error when executing and should always be handled with try/catch. Use this on methods that use external calls.
        /// </summary>
        Failable = 4,

        /// <summary>
        /// The content of the thus marked field determines the dependent's state. Generally, only if the arbiter is true, will the dependent elements be mandatory. This behavior may only be assigned to boolean fields.
        /// </summary>
        Arbiter = 8,

        /// <summary>
        /// This behavior can be assigned together with the 'Mandatory' behavior. It means the field is only mandatory if an arbiter field is present and set to true.
        /// </summary>
        Conditional = 16,

        /// <summary>
        /// Converts content. Generally applied only to operators, but some methods may also convert information.
        /// </summary>
        Conversion = 32
    }
}