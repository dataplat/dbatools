using System;
using System.Management.Automation;

namespace Sqlcollaborative.Dbatools.Message
{
    /// <summary>
    /// An error occured during a message transformation
    /// </summary>
    public class TransformError
    {
        /// <summary>
        /// The error record of what went wrong
        /// </summary>
        public ErrorRecord Record;

        /// <summary>
        /// The name of the function writing the message that failed to transform
        /// </summary>
        public string FunctionName;

        /// <summary>
        /// The name of the module the command writing the message came from
        /// </summary>
        public string ModuleName;

        /// <summary>
        /// When did it all happen?
        /// </summary>
        public DateTime Timestamp;

        /// <summary>
        /// The object that was supposed to be transformed
        /// </summary>
        public object Object;

        /// <summary>
        /// The kind of transform that failed
        /// </summary>
        public TransformType Type;

        /// <summary>
        /// The runspace it all happened on
        /// </summary>
        public Guid Runspace;

        /// <summary>
        /// Creates a new transform error
        /// </summary>
        /// <param name="Record">The record of what went wrong</param>
        /// <param name="FunctionName">The name of the function writing the transformed message</param>
        /// <param name="ModuleName">The module the function writing the transformed message is part of</param>
        /// <param name="Object">The object that should have been transformed</param>
        /// <param name="Type">The type of transform that was attempted</param>
        /// <param name="Runspace">The runspace it all happened on</param>
        public TransformError(ErrorRecord Record, string FunctionName, string ModuleName, object Object, TransformType Type, Guid Runspace)
        {
            this.Record = Record;
            this.FunctionName = FunctionName;
            this.ModuleName = ModuleName;
            this.Object = Object;
            this.Type = Type;
            this.Runspace = Runspace;
            Timestamp = DateTime.Now;
        }
    }
}
