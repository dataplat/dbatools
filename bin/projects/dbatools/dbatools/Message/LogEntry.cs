using System;
using System.Collections.Generic;
using System.Management.Automation;

namespace Sqlcollaborative.Dbatools.Message
{
    /// <summary>
    /// An individual entry for the message log
    /// </summary>
    [Serializable]
    public class LogEntry
    {
        /// <summary>
        /// The message logged
        /// </summary>
        public string Message;

        /// <summary>
        /// What kind of entry was this?
        /// </summary>
        public LogEntryType Type;

        /// <summary>
        /// When was the message logged?
        /// </summary>
        public DateTime Timestamp;

        /// <summary>
        /// What function wrote the message
        /// </summary>
        public string FunctionName;

        /// <summary>
        /// The name of the module of the function that wrote the message
        /// </summary>
        public string ModuleName;

        /// <summary>
        /// The tags applied to the message
        /// </summary>
        public List<string> Tags = new List<string>();

        /// <summary>
        /// What level was the message?
        /// </summary>
        public MessageLevel Level;

        /// <summary>
        /// What runspace was the message written from?
        /// </summary>
        public Guid Runspace;

        /// <summary>
        /// The computer the message was generated on
        /// </summary>
        public string ComputerName;

        /// <summary>
        /// The object that was the focus of this message.
        /// </summary>
        public object TargetObject;

        /// <summary>
        /// The file from which the message was written.
        /// </summary>
        public string File;

        /// <summary>
        /// The line on which the message was written.
        /// </summary>
        public int Line;

        /// <summary>
        /// The callstack when the message was written.
        /// </summary>
        public IEnumerable<CallStackFrame> CallStack;

        /// <summary>
        /// The user that did the writing.
        /// </summary>
        public string Username;

        /// <summary>
        /// Creates an empty log entry
        /// </summary>
        public LogEntry()
        {

        }

        /// <summary>
        /// Creates a filled out log entry
        /// </summary>
        /// <param name="Message">The message that was logged</param>
        /// <param name="Type">The type(s) of message written</param>
        /// <param name="Timestamp">When was the message logged</param>
        /// <param name="FunctionName">What function wrote the message</param>
        /// <param name="ModuleName">Name of the module the function writing this message came from</param>
        /// <param name="Tags">Tags that were applied to the message</param>
        /// <param name="Level">What level was the message written at.</param>
        /// <param name="Runspace">The ID of the runspace that wrote the message.</param>
        /// <param name="ComputerName">The computer the message was generated on.</param>
        /// <param name="TargetObject">The object this message was all about.</param>
        /// <param name="File">The file of the code that wrote the message.</param>
        /// <param name="Line">The line on which the message was written.</param>
        /// <param name="CallStack">The callstack that triggered the write.</param>
        /// <param name="Username">The user responsible for running the code that is writing the message.</param>
        public LogEntry(string Message, LogEntryType Type, DateTime Timestamp, string FunctionName, string ModuleName, List<string> Tags, MessageLevel Level, Guid Runspace, string ComputerName, object TargetObject, string File, int Line, IEnumerable<CallStackFrame> CallStack, string Username)
        {
            this.Message = Message;
            this.Type = Type;
            this.Timestamp = Timestamp;
            this.FunctionName = FunctionName;
            this.ModuleName = ModuleName;
            this.Tags = Tags;
            this.Level = Level;
            this.Runspace = Runspace;
            this.ComputerName = ComputerName;
            this.TargetObject = TargetObject;
            this.File = File;
            this.Line = Line;
            this.CallStack = CallStack;
            this.Username = Username;
        }
    }
}