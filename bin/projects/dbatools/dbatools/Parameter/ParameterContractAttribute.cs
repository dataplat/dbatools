using System;

namespace Sqlcollaborative.Dbatools.Parameter
{
    /// <summary>
    /// The attribute used to define the elements of a ParameterClass contract
    /// </summary>
    [AttributeUsage(AttributeTargets.All)]
    public class ParameterContractAttribute : Attribute
    {
        private ParameterContractType type;
        private ParameterContractBehavior behavior;

        /// <summary>
        /// Returns the type of the element this attribute is supposed to be attached to.
        /// </summary>
        public ParameterContractType Type
        {
            get
            {
                return type;
            }
        }

        /// <summary>
        /// Returns the behavior to expect from the contracted element. This sets the expectations on how this element is likely to act.
        /// </summary>
        public ParameterContractBehavior Behavior
        {
            get
            {
                return behavior;
            }
        }

        /// <summary>
        /// Ceates a perfectly common parameter contract attribute. For use with all parameter classes' public elements.
        /// </summary>
        /// <param name="Type"></param>
        /// <param name="Behavior"></param>
        public ParameterContractAttribute(ParameterContractType Type, ParameterContractBehavior Behavior)
        {
            type = Type;
            behavior = Behavior;
        }
    }
}