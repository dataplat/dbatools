using System;
using System.Collections;
using System.Collections.Generic;
using System.Management.Automation;

namespace Sqlcollaborative.Dbatools.dbaSystem
{
    /// <summary>
    /// Wrapper class that can emulate any exception for purpose of serialization without blowing up the storage space consumed
    /// </summary>
    [Serializable]
    public class DbatoolsException
    {
        private Exception _Exception;
        /// <summary>
        /// Returns the original exception object that we interpreted. This is on purpose not a property, as we want to avoid messing with serialization size.
        /// </summary>
        /// <returns>The original exception that got thrown</returns>
        public Exception GetException()
        {
            return _Exception;
        }

        #region Properties & Fields
        #region Wrapper around 'official' properties
        /// <summary>
        /// The actual Exception Message
        /// </summary>
        public string Message;

        /// <summary>
        /// The original source of the Exception
        /// </summary>
        public string Source;

        /// <summary>
        /// Where on the callstack did the exception occur?
        /// </summary>
        public string StackTrace;

        /// <summary>
        /// What was the target site on the code that caused it. This property has been altered to avoid export issues, if a string representation is not sufficient, access the original exception using GetException()
        /// </summary>
        public string TargetSite;

        /// <summary>
        /// The HResult of the exception. Useful in debugging native code errors.
        /// </summary>
        public int HResult;

        /// <summary>
        /// Link to a proper help article.
        /// </summary>
        public string HelpLink;

        /// <summary>
        /// Additional data that has been appended
        /// </summary>
        public IDictionary Data;

        /// <summary>
        /// The inner exception in a chain of exceptions.
        /// </summary>
        public DbatoolsException InnerException;
        #endregion Wrapper around 'official' properties

        #region Custom properties for exception abstraction
        /// <summary>
        /// The full namespace name of the exception that has been wrapped.
        /// </summary>
        public string ExceptionTypeName;

        /// <summary>
        /// Contains additional properties other exceptions might contain.
        /// </summary>
        public Hashtable ExceptionData = new Hashtable();
        #endregion Custom properties for exception abstraction

        #region ErrorRecord Data
        /// <summary>
        /// The category of the error
        /// </summary>
        public ErrorCategoryInfo CategoryInfo;

        /// <summary>
        /// The details on the error
        /// </summary>
        public ErrorDetails ErrorDetails;

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
        /// The runspace the error occured on.
        /// </summary>
        public Guid Runspace;
        #endregion ErrRecord Data
        #endregion Properties & Fields

        #region Constructors
        /// <summary>
        /// Creates an empty exception object. Mostly for serialization support
        /// </summary>
        public DbatoolsException()
        {

        }

        /// <summary>
        /// Creates an exception based on an original exception object
        /// </summary>
        /// <param name="Except">The exception to wrap around</param>
        public DbatoolsException(Exception Except)
        {
            _Exception = Except;

            Message = Except.Message;
            Source = Except.Source;
            StackTrace = Except.StackTrace;
            try { TargetSite = Except.TargetSite.ToString(); }
            catch { }
            HResult = Except.HResult;
            HelpLink = Except.HelpLink;
            Data = Except.Data;
            if (Except.InnerException != null) { InnerException = new DbatoolsException(Except.InnerException); }

            ExceptionTypeName = Except.GetType().FullName;

            PSObject tempObject = new PSObject(Except);
            List<string> defaultPropertyNames = new List<string>();
            defaultPropertyNames.Add("Data");
            defaultPropertyNames.Add("HelpLink");
            defaultPropertyNames.Add("HResult");
            defaultPropertyNames.Add("InnerException");
            defaultPropertyNames.Add("Message");
            defaultPropertyNames.Add("Source");
            defaultPropertyNames.Add("StackTrace");
            defaultPropertyNames.Add("TargetSite");

            foreach (PSPropertyInfo member in tempObject.Properties)
            {
                if (!defaultPropertyNames.Contains(member.Name))
                    ExceptionData[member.Name] = member.Value;
            }
        }

        /// <summary>
        /// Creates a rich information exception object based on a full error record as recorded by PowerShell
        /// </summary>
        /// <param name="Record">The error record to copy from</param>
        public DbatoolsException(ErrorRecord Record)
            : this(Record.Exception)
        {
            CategoryInfo = Record.CategoryInfo;
            ErrorDetails = Record.ErrorDetails;
            FullyQualifiedErrorId = Record.FullyQualifiedErrorId;
            InvocationInfo = Record.InvocationInfo;
            ScriptStackTrace = Record.ScriptStackTrace;
            TargetObject = Record.TargetObject;
        }

        /// <summary>
        /// Creates a new exception object with rich meta information from the Dbatools runtime.
        /// </summary>
        /// <param name="Except">The exception thrown</param>
        /// <param name="FunctionName">The name of the function in which the error occured</param>
        /// <param name="Timestamp">When did the error occur</param>
        /// <param name="Message">The message to add to the exception</param>
        /// <param name="Runspace">The ID of the runspace from which the exception was thrown. Useful in multi-runspace scenarios.</param>
        public DbatoolsException(Exception Except, string FunctionName, DateTime Timestamp, string Message, Guid Runspace)
            : this(Except)
        {
            this.Runspace = Runspace;
            this.FunctionName = FunctionName;
            this.Timestamp = Timestamp;
            this.Message = Message;
        }

        /// <summary>
        /// Creates a new exception object with rich meta information from the Dbatools runtime.
        /// </summary>
        /// <param name="Record">The error record written</param>
        /// <param name="FunctionName">The name of the function in which the error occured</param>
        /// <param name="Timestamp">When did the error occur</param>
        /// <param name="Message">The message to add to the exception</param>
        /// <param name="Runspace">The ID of the runspace from which the exception was thrown. Useful in multi-runspace scenarios.</param>
        public DbatoolsException(ErrorRecord Record, string FunctionName, DateTime Timestamp, string Message, Guid Runspace)
            : this(Record)
        {
            this.Runspace = Runspace;
            this.FunctionName = FunctionName;
            this.Timestamp = Timestamp;
            this.Message = Message;
        }
        #endregion Constructors

        /// <summary>
        /// Returns a string representation of the exception.
        /// </summary>
        /// <returns></returns>
        public override string ToString()
        {
            return Message;
        }
    }
}