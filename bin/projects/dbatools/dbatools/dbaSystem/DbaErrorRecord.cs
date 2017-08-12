using System;
using System.Management.Automation;

namespace Sqlcollaborative.Dbatools.dbaSystem
{
    /// <summary>
    /// An error record written by dbatools
    /// </summary>
    [Serializable]
    public class DbaErrorRecord
    {
        /// <summary>
        /// The category of the error
        /// </summary>
        public ErrorCategoryInfo CategoryInfo;

        /// <summary>
        /// The details on the error
        /// </summary>
        public ErrorDetails ErrorDetails;

        /// <summary>
        /// The actual exception thrown
        /// </summary>
        public Exception Exception;

        /// <summary>
        /// The specific error identity, used to identify the target
        /// </summary>
        public string FullyQualifiedErrorId;

        /// <summary>
        /// The details of how this was called.
        /// </summary>
        public object InvocationInfo;

        /// <summary>
        /// The script's stacktrace
        /// </summary>
        public string ScriptStackTrace;

        /// <summary>
        /// The object being processed
        /// </summary>
        public object TargetObject;

        /// <summary>
        /// The name of the function throwing the error
        /// </summary>
        public string FunctionName;

        /// <summary>
        /// When was the error thrown
        /// </summary>
        public DateTime Timestamp;

        /// <summary>
        /// The message that was written in a userfriendly manner
        /// </summary>
        public string Message;

        /// <summary>
        /// The runspace the error occured on.
        /// </summary>
        public Guid Runspace;

        /// <summary>
        /// Create an empty record
        /// </summary>
        public DbaErrorRecord()
        {

        }

        /// <summary>
        /// Create a filled out error record
        /// </summary>
        /// <param name="Record">The original error record</param>
        /// <param name="FunctionName">The function that wrote the error</param>
        /// <param name="Timestamp">When was the error generated</param>
        /// <param name="Message">What message was passed when writing the error</param>
        public DbaErrorRecord(ErrorRecord Record, string FunctionName, DateTime Timestamp, string Message)
        {
            this.FunctionName = FunctionName;
            this.Timestamp = Timestamp;
            this.Message = Message;

            CategoryInfo = Record.CategoryInfo;
            ErrorDetails = Record.ErrorDetails;
            Exception = Record.Exception;
            FullyQualifiedErrorId = Record.FullyQualifiedErrorId;
            InvocationInfo = Record.InvocationInfo;
            ScriptStackTrace = Record.ScriptStackTrace;
            TargetObject = Record.TargetObject;
        }

        /// <summary>
        /// Create a filled out error record
        /// </summary>
        /// <param name="Record">The original error record</param>
        /// <param name="FunctionName">The function that wrote the error</param>
        /// <param name="Timestamp">When was the error generated</param>
        /// <param name="Message">What message was passed when writing the error</param>
        /// <param name="Runspace">The ID of the runspace writing the error. Used to separate output between different runspaces in the same process.</param>
        public DbaErrorRecord(ErrorRecord Record, string FunctionName, DateTime Timestamp, string Message, Guid Runspace)
        {
            this.FunctionName = FunctionName;
            this.Timestamp = Timestamp;
            this.Message = Message;
            this.Runspace = Runspace;

            CategoryInfo = Record.CategoryInfo;
            ErrorDetails = Record.ErrorDetails;
            Exception = Record.Exception;
            FullyQualifiedErrorId = Record.FullyQualifiedErrorId;
            InvocationInfo = Record.InvocationInfo;
            ScriptStackTrace = Record.ScriptStackTrace;
            TargetObject = Record.TargetObject;
        }
    }
}