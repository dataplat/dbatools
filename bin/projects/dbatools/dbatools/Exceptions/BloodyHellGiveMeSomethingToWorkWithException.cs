using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace Sqlcollaborative.Dbatools.Exceptions
{
    /// <summary>
    /// An exception that is thrown by parameter classes when given empty input
    /// </summary>
    public class BloodyHellGiveMeSomethingToWorkWithException : ArgumentException
    {
        /// <summary>
        /// The parameter class that did the throwing
        /// </summary>
        public string ParameterClass;

        /// <summary>
        /// Creates an exception with a message and a nested exception
        /// </summary>
        /// <param name="Message">The message to tell</param>
        /// <param name="Inner">The inner exception to nest</param>
        internal BloodyHellGiveMeSomethingToWorkWithException(string Message, Exception Inner)
            : base(Message, Inner)
        {

        }

        /// <summary>
        /// Creates an exception with a message and a ParameterClass
        /// </summary>
        /// <param name="Message">The message to tell</param>
        /// <param name="ParameterClass">The Parameter Class that threw the exception</param>
        internal BloodyHellGiveMeSomethingToWorkWithException(string Message, string ParameterClass)
            : base(Message)
        {
            this.ParameterClass = ParameterClass;
        }

        /// <summary>
        /// Creates an exception with a message, a nested exception and a ParameterClass
        /// </summary>
        /// <param name="Message">The message to tell</param>
        /// <param name="Inner">The inner exception to nest</param>
        /// <param name="ParameterClass">The Parameter Class that threw the exception</param>
        internal BloodyHellGiveMeSomethingToWorkWithException(string Message, Exception Inner, string ParameterClass)
            : base(Message, Inner)
        {
            this.ParameterClass = ParameterClass;
        }
    }
}
