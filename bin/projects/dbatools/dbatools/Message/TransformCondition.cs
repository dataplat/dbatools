using System.Management.Automation;

namespace Sqlcollaborative.Dbatools.Message
{
    /// <summary>
    /// A condition, under which the object shall be transaformed
    /// </summary>
    public class TransformCondition
    {
        /// <summary>
        /// Name of the type. All similar types (as determined by the '-like' operator) will be transformed.
        /// </summary>
        public string TypeName;

        /// <summary>
        /// The name of the module to consider, using the -Like operator
        /// </summary>
        public string ModuleName;

        /// <summary>
        /// The name of the function name to consider, using the -Like operator
        /// </summary>
        public string FunctionName;

        /// <summary>
        /// The scriptblock that performs the transformation
        /// </summary>
        public ScriptBlock ScriptBlock;

        /// <summary>
        /// What kind of transformation is being performed?
        /// </summary>
        public TransformType Type;

        /// <summary>
        /// Initializes a transform condition
        /// </summary>
        /// <param name="TypeName">Only objects of similar name will be transformed</param>
        /// <param name="ModuleName">Only objects coming from similar modules will be considered</param>
        /// <param name="FunctionName">Only objects coming from similar functions will be considered</param>
        /// <param name="ScriptBlock">The scriptblock used for the transformation</param>
        /// <param name="Type">What kind of transformation this is</param>
        public TransformCondition(string TypeName, string ModuleName, string FunctionName, ScriptBlock ScriptBlock, TransformType Type)
        {
            this.TypeName = TypeName;
            this.ModuleName = ModuleName;
            this.FunctionName = FunctionName;
            this.ScriptBlock = ScriptBlock;
            this.Type = Type;
        }
    }
}
